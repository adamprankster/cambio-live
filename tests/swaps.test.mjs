import {PGlite} from '@electric-sql/pglite';import {readFileSync,readdirSync} from 'node:fs';import assert from 'node:assert/strict';
import {newSwaps,swapMessage} from '../public/swap-effects.js';
const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean);create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
for(const f of ['baseline.sql','upgrade.sql','bots.sql',...readdirSync('supabase/migrations').sort().map(f=>'migrations/'+f)])await db.exec(readFileSync('supabase/'+f,'utf8'));
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',outsider='00000000-0000-0000-0000-000000000003';
async function as(id=a){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
async function admin(q,args=[]){await db.exec('reset role');return (await db.query(q,args)).rows;}
async function rpc(n,args=[]){return (await db.query(`select public.${n}(${args.map((_,i)=>'$'+(i+1)).join(',')}) v`,args)).rows[0].v;}
await admin('insert into auth.users values($1,true),($2,true),($3,true)',[a,b,outsider]);await as();const code=(await rpc('create_room',['Alex'])).room_code;await as(b);await rpc('join_room',[code,'Jordan']);await as();const bot=await rpc('add_bot',[code,'hard']);await rpc('start_game',[code]);await rpc('ready_for_round',[code]);await as(b);await rpc('ready_for_round',[code]);
const before=await rpc('get_game_view',[code]);assert.deepEqual(before.game.swap_events,[]);
async function prepare(actor,ability,target=b,pos=2){
 await admin("update public.game_state set current_turn_user_id=$2,phase='ability' where room_code=$1",[code,actor]);
 await admin("update public.turn_state set pending_ability=$2,peeked_target_user_id=$3,peeked_target_position=$4,peeked_card_id=(select id from public.game_cards where room_code=$1 and owner_user_id=$3 and position=$4 and zone='hand') where room_code=$1",[code,ability,target,pos]);await as(actor);
}
await prepare(a,'blind_swap');await assert.rejects(rpc('blind_swap',[code,99,b,2]));await as(outsider);await assert.rejects(rpc('blind_swap',[code,0,b,2]));await assert.rejects(rpc('get_game_view',[code]));await as();await rpc('blind_swap',[code,0,b,2]);let host=await rpc('get_game_view',[code]);await as(b);let guest=await rpc('get_game_view',[code]);
assert.deepEqual(host.game.swap_events,guest.game.swap_events);assert.equal(guest.game.swap_events.length,1);
const e=guest.game.swap_events[0];assert.deepEqual(Object.keys(e).sort(),['id','round','at','actor_seat','target_seat','own_position','target_position'].sort());assert.equal(e.own_position,0);assert.equal(e.target_position,2);assert.equal(swapMessage(e,guest),'Alex swapped your card 3!');assert.equal(swapMessage(e,host),'You swapped card 1 with Jordan.');
assert.equal(newSwaps(before,guest).length,1);assert.equal(newSwaps(guest,guest).length,0);assert.equal(newSwaps(null,guest).length,0);assert.equal(newSwaps(guest,{...guest,game:{...guest.game,round_number:2}}).length,0);
await prepare(a,'black_king_decide');await rpc('black_king_decide',[code,false,null]);assert.equal((await rpc('get_game_view',[code])).game.swap_events.length,1);
await prepare(a,'black_king_decide');await rpc('black_king_decide',[code,true,1]);assert.equal((await rpc('get_game_view',[code])).game.swap_events.length,2);
// Bot uses the same successful swap path and emits an event for the human target.
await prepare(bot,'black_king_decide',b,0);await admin("update public.game_cards set rank='A',suit='♠' where room_code=$1 and owner_user_id=$2 and position=0 and zone='hand'",[code,b]);await admin('delete from private.bot_memory where room_code=$1',[code]);await admin("select private.remember_card($1,$2,id) from public.game_cards where room_code=$1 and owner_user_id=$3 and position=0 and zone='hand'",[code,bot,b]);await admin("update public.rooms set bot_next_action_at=now()-interval '1 second' where code=$1",[code]);await as();await rpc('tick_bots',[code]);guest=await rpc('get_game_view',[code]);assert.equal(guest.game.swap_events.length,3);assert.equal(guest.game.swap_events[2].actor_seat,guest.players.find(p=>p.user_id===bot).seat);
await assert.rejects(db.query('select private.record_swap($1,0,$2,0)',[code,b]));
for(let i=0;i<20;i++){await prepare(a,'blind_swap');await rpc('blind_swap',[code,0,b,2]);}
assert.equal((await rpc('get_game_view',[code])).game.swap_events.length,16);
console.log('PASS: human and bot swaps shared with target; no secrets; denied/invalid/declined swaps emit nothing; deduplication, reconnect and round filtering; bounded history and private helper');await db.close();
