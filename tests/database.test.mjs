import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$; grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(readFileSync('supabase/baseline.sql','utf8'));
await db.exec(readFileSync('supabase/upgrade.sql','utf8'));
const ids=[1,2,3].map(n=>`00000000-0000-0000-0000-00000000000${n}`);
async function user(i){await db.exec(`reset role;select set_config('request.jwt.claim.sub','${ids[i]}',false);set role authenticated;`);}
async function rpc(name,args=[]){const r=await db.query(`select * from public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})`,args);return r.rows;}
async function admin(sql,args=[]){await db.exec('reset role');return db.query(sql,args);}
await user(0);const [{create_room:{room_code:code}}]=await rpc('create_room',['Tester 1']);
for(let i=1;i<3;i++){await user(i);await rpc('join_room',[code,'Tester '+(i+1)]);}
await user(0);await rpc('set_room_rules',[code,500,5,10]);await rpc('start_game',[code]);
for(let i=0;i<3;i++){await user(i);assert.equal((await rpc('get_initial_peek',[code,[2,3]])).length,2);await assert.rejects(rpc('get_initial_peek',[code,[0,1]]));await rpc('ready_for_round',[code]);}
await user(0);await assert.rejects(rpc('get_initial_peek',[code,[2]]));await assert.rejects(rpc('peek_own_card',[code,0]));
await rpc('draw_from',[code,'deck']);await assert.rejects(rpc('call_cambio',[code]));await rpc('resolve_draw',[code,'replace',0]);
await user(1);await assert.rejects(rpc('get_initial_peek',[code,[2]]));
await user(2);assert.equal((await rpc('get_initial_peek',[code,[2,3]])).length,2);
await user(1);await rpc('call_cambio',[code]);
for(const i of [2,0]){await user(i);await rpc('draw_from',[code,'deck']);await rpc('resolve_draw',[code,'replace',0]);}
await user(0);const scores=await rpc('get_round_scores',[code]);assert.equal(scores.length,3);assert(scores.every(x=>x.round_score===x.total_score));
await rpc('next_round',[code]);await assert.rejects(rpc('next_round',[code]));
await admin('select private.finish_round($1)',[code]);await admin('select private.finish_round($1)',[code]);
const totals=(await admin('select sum(total_score) n from public.room_players where room_code=$1',[code])).rows[0].n;
const ledger=(await admin('select sum(round_score) n from public.round_scores where room_code=$1',[code])).rows[0].n;assert.equal(totals,ledger);
console.log('PASS: initial peek boundaries, unauthorized powers, draw/Cambio timing, all final turns, cumulative scoring, retry protection');

// New round, deterministic card values exercise each server transition.
await user(0);await rpc('next_round',[code]);
for(let i=0;i<3;i++){await user(i);await rpc('ready_for_round',[code]);}
async function giveDraw(i,rank,suit='♠',source='deck'){
 await admin("update public.game_cards set rank=$2,suit=$3 where id=(select id from public.game_cards where room_code=$1 and zone=$4 order by case when $4='deck' then deck_order else -discard_order end limit 1)",[code,rank,suit,source]);
 await user(i);await rpc('draw_from',[code,source]);
}
await giveDraw(0,'7');await rpc('resolve_draw',[code,'discard',null]);await assert.rejects(rpc('peek_other_card',[code,ids[1],0,null]));await rpc('peek_own_card',[code,1]);await assert.rejects(rpc('peek_own_card',[code,1]));
await giveDraw(1,'9');await rpc('resolve_draw',[code,'discard',null]);await assert.rejects(rpc('peek_other_card',[code,ids[1],0,null]));await rpc('peek_other_card',[code,ids[0],1,null]);
await giveDraw(2,'J');await rpc('resolve_draw',[code,'discard',null]);await rpc('blind_swap',[code,0,ids[0],0]);await assert.rejects(rpc('blind_swap',[code,0,ids[0],0]));
await giveDraw(0,'K');await rpc('resolve_draw',[code,'discard',null]);await rpc('peek_other_card',[code,ids[1],0,null]);await assert.rejects(rpc('peek_other_card',[code,ids[2],0,null]));await rpc('black_king_decide',[code,true,2]);
await giveDraw(1,'K','♥');await rpc('resolve_draw',[code,'discard',null]);
await giveDraw(2,'7','♠','discard');await rpc('resolve_draw',[code,'discard',null]);await rpc('peek_own_card',[code,0]);
// Correct slams remove cards; incorrect slams retain them and add hidden cards.
await admin("update public.game_cards set rank='5' where room_code=$1 and (zone='discard' or (zone='hand' and owner_user_id=$2 and position=0))",[code,ids[1]]);
await user(1);let [{get_game_view:v}]=await rpc('get_game_view',[code]);let [slam]=await rpc('slam_card',[code,0,v.discard_order]);assert.equal(slam.slam_card.matched,true);
await assert.rejects(rpc('slam_card',[code,1,v.discard_order]));
await admin("update public.game_cards set rank='6' where room_code=$1 and zone='hand' and owner_user_id=$2 and position=1",[code,ids[1]]);
await user(1);[{get_game_view:v}]=await rpc('get_game_view',[code]);[slam]=await rpc('slam_card',[code,1,v.discard_order]);assert.equal(slam.slam_card.penalty,true);
[{get_game_view:v}]=await rpc('get_game_view',[code]);assert(v.hand.some(c=>c.position>=4));assert(v.hand.every(c=>!('rank' in c)&&!('visible_value' in c)));
// Empty hand gets a real zero score rather than disappearing from results.
await admin("update public.game_cards set zone='discard',owner_user_id=null,position=null,discard_order=nextval('private.discard_sequence') where room_code=$1 and owner_user_id=$2 and zone='hand'",[code,ids[2]]);
await admin('select private.finish_round($1)',[code]);await user(0);assert.equal((await rpc('get_round_scores',[code])).find(x=>x.user_id===ids[2]).round_score,0);
// Private card data and helpers cannot be accessed directly, even by a member.
await assert.rejects(db.query('select * from public.game_cards'));await assert.rejects(db.query('select private.build_deck($1)',[code]));
await db.exec("reset role;select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',false);set role authenticated");
await assert.rejects(rpc('get_game_view',[code]));await assert.rejects(rpc('get_initial_peek',[code,[2,3]]));await assert.rejects(rpc('call_cambio',[code]));
console.log('PASS: all powers, single-use abilities, discard-source rules, slam correctness/penalties/stale-discard rejection, zero-card scoring, secret isolation');

// A tied caller is penalized; a unique lowest caller earns the configured bonus.
await user(0);await rpc('return_to_lobby',[code]);await rpc('set_room_rules',[code,10,5,10]);
await admin('update public.room_players set total_score=0 where room_code=$1',[code]);
await user(0);await rpc('start_game',[code]);
await admin("update public.game_cards set rank='2' where room_code=$1 and zone='hand'",[code]);
await admin('update public.rooms set cambio_called_by=$2 where code=$1',[code,ids[0]]);await admin('select private.finish_round($1)',[code]);
let result=(await admin('select round_score,raw_score,call_adjustment from public.round_scores where room_code=$1 and user_id=$2 order by round_number desc limit 1',[code,ids[0]])).rows[0];assert.equal(result.raw_score,8);assert.equal(result.call_adjustment,10);assert.equal(result.round_score,18);
await user(0);let [{get_game_view:finished}]=await rpc('get_game_view',[code]);assert.equal(finished.room.game_over,true);assert.equal(finished.revealed_cards.length,12);await assert.rejects(rpc('next_round',[code]));await rpc('new_match',[code]);
await rpc('start_game',[code]);await admin("update public.game_cards set rank=case when owner_user_id=$2 then 'A' else '2' end where room_code=$1 and zone='hand'",[code,ids[0]]);await admin('update public.rooms set cambio_called_by=$2 where code=$1',[code,ids[0]]);await admin('select private.finish_round($1)',[code]);
result=(await admin('select round_score,call_adjustment from public.round_scores where room_code=$1 and user_id=$2',[code,ids[0]])).rows[0];assert.equal(result.call_adjustment,-5);assert.equal(result.round_score,-1);
console.log('PASS: tied-call penalty, unique-lowest bonus, match threshold, final reveal, new-match reset');
// Refill keeps the top discard and excludes a pending draw from penalty allocation.
await user(0);await rpc('next_round',[code]);for(let i=0;i<3;i++){await user(i);await rpc('ready_for_round',[code]);}
await admin("update public.game_cards set zone='discard',discard_order=nextval('private.discard_sequence') where room_code=$1 and zone='deck'",[code]);await admin('select private.refresh_public_state($1)',[code]);await user(0);let [{get_game_view:beforeRefill}]=await rpc('get_game_view',[code]);await rpc('draw_from',[code,'deck']);let [{get_game_view:afterRefill}]=await rpc('get_game_view',[code]);assert.equal(beforeRefill.discard_order,afterRefill.discard_order);assert(afterRefill.game.deck_count>0);assert(afterRefill.drawn_label);
await db.exec('reset role');const exports=await db.query("select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef");assert.equal(exports.rows[0].n,0);
console.log('PASS: deck recycling preserves top discard; public RPCs are invoker wrappers');
// A pending draw is reserved even when another player gets a slam penalty
// at the exact moment the deck is recycled.
await admin("update public.game_cards set zone='discard',discard_order=nextval('private.discard_sequence') where room_code=$1 and zone='deck' and id<>(select drawn_card_id from public.turn_state where room_code=$1)",[code]);
await admin("update public.game_cards set deck_order=0 where id=(select drawn_card_id from public.turn_state where room_code=$1)",[code]);
await admin("update public.game_cards set rank='5' where room_code=$1 and zone='discard'",[code]);await admin("update public.game_cards set rank='6' where room_code=$1 and zone='hand' and owner_user_id=$2 and position=0",[code,ids[1]]);
await user(1);let [{get_game_view:penaltyView}]=await rpc('get_game_view',[code]);await rpc('slam_card',[code,0,penaltyView.discard_order]);
const reserved=(await admin("select c.zone,c.owner_user_id from public.game_cards c join public.turn_state t on t.drawn_card_id=c.id where t.room_code=$1",[code])).rows[0];assert.equal(reserved.zone,'deck');assert.equal(reserved.owner_user_id,null);
console.log('PASS: penalty recycling never steals a pending draw');
await db.close();
