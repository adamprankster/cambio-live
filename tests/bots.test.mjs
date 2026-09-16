import {PGlite} from '@electric-sql/pglite';import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
for(const f of ['baseline.sql','upgrade.sql','bots.sql'])await db.exec(readFileSync('supabase/'+f,'utf8'));
const human='00000000-0000-0000-0000-000000000001',other='00000000-0000-0000-0000-000000000002';
async function as(id=human){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
async function rpc(n,args=[]){const {rows}=await db.query(`select * from public.${n}(${args.map((_,i)=>'$'+(i+1)).join(',')})`,args);return rows;}
async function admin(q,args=[]){await db.exec('reset role');return db.query(q,args);}
await as();const code=(await rpc('create_room',['Bot test']))[0].create_room.room_code;
await as(other);await rpc('join_room',[code,'Friend']);await assert.rejects(rpc('add_bot',[code,'hard']));await as();
const easy=(await rpc('add_bot',[code,'easy']))[0].add_bot;await rpc('remove_bot',[code,easy]);
const bots=[];for(const level of ['easy','medium','hard','hard'])bots.push((await rpc('add_bot',[code,level]))[0].add_bot);
await assert.rejects(rpc('add_bot',[code,'hard']));await assert.rejects(rpc('remove_bot',[code,other]));await rpc('start_game',[code]);await assert.rejects(rpc('remove_bot',[code,bots[0]]));
let v=(await rpc('get_game_view',[code]))[0].get_game_view;assert.equal(v.players.filter(p=>p.is_bot&&p.initial_ready).length,4);assert.equal(v.players.find(p=>p.user_id===human).initial_ready,false);
const memories=(await admin("select count(*)::int n from private.bot_memory m join public.game_cards c on c.id=m.card_id where m.room_code=$1 and not(c.zone='discard' or(c.zone='hand' and c.owner_user_id=m.bot_id and c.position in(2,3)))",[code])).rows[0].n;assert.equal(memories,0);
await as();await assert.rejects(db.query('select * from private.bot_memory'));await rpc('ready_for_round',[code]);await as(other);await rpc('ready_for_round',[code]);await as();
// A human can slam their own just-discarded draw, including during its power.
await assert.rejects(rpc('draw_from',[code,'discard']),/discard pile is for slamming/);
for(const rank of ['3','7']){
 await admin("update public.game_state set current_turn_user_id=$2,phase='turn' where room_code=$1",[code,human]);
 await admin("update public.game_cards set rank=$2 where room_code=$1 and zone='deck' and deck_order=(select min(deck_order) from public.game_cards where room_code=$1 and zone='deck')",[code,rank]);
 await admin("update public.game_cards set rank=$2 where room_code=$1 and owner_user_id=$3 and position=(select min(position) from public.game_cards where room_code=$1 and owner_user_id=$3 and zone='hand')",[code,rank,human]);
 await as();await rpc('draw_from',[code,'deck']);await rpc('resolve_draw',[code,'discard',null]);
 v=(await rpc('get_game_view',[code]))[0].get_game_view;
 const result=(await rpc('slam_card',[code,v.hand[0].position,v.discard_order]))[0].slam_card;assert.equal(result.matched,true);
 if(rank==='7')await rpc('skip_ability',[code]);
}
// Every difficulty finishes its actions through the same game RPCs.
let botSteps=0;
for(let step=0;step<140;step++){
 v=(await rpc('get_game_view',[code]))[0].get_game_view;if(v.room.status==='round_over')break;
 const turn=v.players.find(p=>p.user_id===v.game.current_turn_user_id);
 if(turn.is_bot){await admin("update public.rooms set bot_next_action_at=now()-interval '1 second' where code=$1",[code]);await as();await rpc('tick_bots',[code]);botSteps++;assert.equal((await db.query('select auth.uid() id')).rows[0].id,human);}
 else{await as(turn.user_id);if(v.game.phase==='turn'){if(step>18&&!v.room.cambio_called_by)await rpc('call_cambio',[code]);else await rpc('draw_from',[code,'deck']);}else if(v.game.phase==='drawn'){const own=v.players.find(p=>p.user_id===turn.user_id);await rpc('resolve_draw',[code,own.positions.length?'replace':'discard',own.positions[0]??null]);}else await rpc('skip_ability',[code]);await as();}
}
v=(await rpc('get_game_view',[code]))[0].get_game_view;assert.equal(v.room.status,'round_over');assert(botSteps>=8);assert.equal((await rpc('get_round_scores',[code])).length,6);
await rpc('return_to_lobby',[code]);await rpc('leave_room',[code]);await as(other);v=(await rpc('get_game_view',[code]))[0].get_game_view;assert.equal(v.room.host_user_id,other);await rpc('leave_room',[code]);assert.equal((await admin('select count(*)::int n from public.rooms where code=$1',[code])).rows[0].n,0);
console.log('PASS: host-only add/remove, six-seat cap, mixed difficulties, private legal memory, automatic readiness, bot powers/turns, scoring, identity restoration, human host transfer and cleanup');
await db.close();
