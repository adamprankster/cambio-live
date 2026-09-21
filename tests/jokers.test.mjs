import {PGlite} from '@electric-sql/pglite';
import {readFileSync,readdirSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean);create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
const migration='20260921165500_jokers.sql';
for(const f of ['baseline.sql','upgrade.sql','bots.sql',...readdirSync('supabase/migrations').filter(f=>f!==migration).sort().map(f=>'migrations/'+f)])await db.exec(readFileSync('supabase/'+f,'utf8'));
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002';
async function as(id=a){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
async function admin(q,args=[]){await db.exec('reset role');return (await db.query(q,args)).rows;}
async function rpc(n,args=[]){return (await db.query(`select public.${n}(${args.map((_,i)=>'$'+(i+1)).join(',')}) v`,args)).rows[0].v;}
await admin('insert into auth.users values($1,true),($2,true)',[a,b]);await as();const old=(await rpc('create_room',['Existing round'])).room_code;await as(b);await rpc('join_room',[old,'Friend']);await as();await rpc('start_game',[old]);
const before=await admin('select * from public.game_cards where room_code=$1 order by id',[old]);assert.equal(before.length,52);
await db.exec(readFileSync('supabase/migrations/'+migration,'utf8'));
assert.deepEqual(await admin('select * from public.game_cards where room_code=$1 order by id',[old]),before);
assert.deepEqual((await admin("select private.card_points('Joker','★') points,private.card_label('Joker','☆') label,private.card_ability('Joker','★') ability"))[0],{points:0,label:'Joker',ability:'none'});
await as();await assert.rejects(db.query("select private.build_deck($1)",[old]));
const code=(await rpc('create_room',['Joker test'])).room_code;await as(b);await rpc('join_room',[code,'Friend']);await as();await rpc('start_game',[code]);
assert.deepEqual((await admin("select count(*)::int cards,count(*) filter(where rank='Joker')::int jokers from public.game_cards where room_code=$1",[code]))[0],{cards:54,jokers:2});
await as();await rpc('ready_for_round',[code]);await as(b);await rpc('ready_for_round',[code]);
// Force a zero-point draw and its matching hand card to exercise the real RPCs.
await admin("update public.game_cards set rank='Joker',suit='★' where id=(select id from public.game_cards where room_code=$1 and zone='deck' order by deck_order limit 1)",[code]);await admin("update public.game_cards set rank='Joker',suit='☆' where room_code=$1 and owner_user_id=$2 and position=0",[code,a]);
await as();assert.equal((await rpc('draw_from',[code,'deck'])).card_label,'Joker');assert.equal((await rpc('resolve_draw',[code,'discard',null])).ability,'none');let v=await rpc('get_game_view',[code]);assert.equal(v.game.current_turn_user_id,b);assert.equal((await rpc('slam_card',[code,0,v.discard_order])).matched,true);
// A non-joker cannot match it; existing penalty behavior still applies.
await admin("update public.game_cards set rank='5',suit='♠' where room_code=$1 and owner_user_id=$2 and position=1",[code,a]);await as();v=await rpc('get_game_view',[code]);assert.equal((await rpc('slam_card',[code,1,v.discard_order])).penalty,true);
// Score a hand containing two jokers, an ace, and a red king: zero total.
await admin("update public.game_cards set rank=case when position in(1,2) then 'Joker' when position=3 then 'A' else 'K' end,suit='♥' where room_code=$1 and owner_user_id=$2 and zone='hand'",[code,a]);await admin('select private.finish_round($1)',[code]);
assert.equal((await admin('select raw_score from public.round_scores where room_code=$1 and user_id=$2',[code,a]))[0].raw_score,0);
assert.equal((await admin('select total_score from public.room_players where room_code=$1 and user_id=$2',[code,a]))[0].total_score,0);
// Bots evaluate a drawn joker as zero and keep it in place of a higher card.
await as();const bots=(await rpc('create_room',['Bot joker'])).room_code;const bot=await rpc('add_bot',[bots,'hard']);await rpc('start_game',[bots]);await rpc('ready_for_round',[bots]);
await admin("update public.game_cards set rank='8',suit='♠' where room_code=$1 and zone='hand' and owner_user_id=$2",[bots,bot]);await admin('delete from private.bot_memory where room_code=$1',[bots]);await admin("update public.game_cards set rank='Joker',suit='★' where id=(select id from public.game_cards where room_code=$1 and zone='deck' order by deck_order limit 1)",[bots]);await admin("update public.game_state set current_turn_user_id=$2,phase='turn' where room_code=$1",[bots,bot]);
for(let i=0;i<2;i++){await admin("update public.rooms set bot_next_action_at=now()-interval '1 second' where code=$1",[bots]);await as();await rpc('tick_bots',[bots]);}
assert.equal((await admin("select count(*)::int n from public.game_cards where room_code=$1 and owner_user_id=$2 and zone='hand' and rank='Joker'",[bots,bot]))[0].n,1);
console.log('PASS: existing rounds preserved; 54-card deals; zero-point joker labels, draw, no power, self-slam, incorrect slam penalty, round/cumulative scoring and bot replacement');await db.close();
