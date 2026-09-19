import {PGlite} from '@electric-sql/pglite';
import {readFileSync,readdirSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean);create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
for(const f of ['baseline.sql','upgrade.sql','bots.sql',...readdirSync('supabase/migrations').map(f=>'migrations/'+f)])await db.exec(readFileSync('supabase/'+f,'utf8'));
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002';
async function as(id){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
async function admin(q,args=[]){await db.exec('reset role');return db.query(q,args);}
async function rpc(n,args=[]){return (await db.query(`select public.${n}(${args.map((_,i)=>'$'+(i+1)).join(',')}) v`,args)).rows[0].v;}
for(const phase of ['waiting','drawn','black_king_decide']){
 await admin('insert into auth.users values($1,true),($2,true) on conflict do nothing',[a,b]);await as(a);const code=(await rpc('create_room',['Delete test'])).room_code;
 await as(b);await rpc('join_room',[code,'Friend']);await as(a);await rpc('start_game',[code]);
 if(phase!=='waiting'){
  await rpc('ready_for_round',[code]);await as(b);await rpc('ready_for_round',[code]);await as(a);
  if(phase==='black_king_decide')await admin("update public.game_cards set rank='K',suit='♠' where id=(select id from public.game_cards where room_code=$1 and zone='deck' order by deck_order limit 1)",[code]);
  await as(a);await rpc('draw_from',[code,'deck']);if(phase==='black_king_decide'){await rpc('resolve_draw',[code,'discard',null]);await rpc('peek_other_card',[code,b,0,null]);}
 }else{await as(b);await rpc('ready_for_round',[code]);await as(a);}
 const before=(await admin('select id,rank,suit,zone from public.game_cards where room_code=$1 order by id',[code])).rows;
 await as(a);await rpc('delete_guest_account');await assert.rejects(rpc('get_game_view',[code]));await assert.rejects(rpc('create_room',['Old token']));await assert.rejects(rpc('join_room',[code,'Old token']));await assert.rejects(rpc('delete_guest_account'));
 assert.equal((await admin('select count(*)::int n from auth.users where id=$1',[a])).rows[0].n,0);
 assert.deepEqual((await admin('select id,rank,suit,zone from public.game_cards where room_code=$1 order by id',[code])).rows,before);
 await as(b);let v=await rpc('get_game_view',[code]);assert.equal(v.room.host_user_id,b);assert(!JSON.stringify(v).includes(a));assert(!JSON.stringify(v).includes('Delete test'));assert.equal(v.players.filter(p=>p.is_bot).length,1);
 // Replacement bot can finish the deleted player's pending action.
 for(let i=0;i<10&&v.game.current_turn_user_id!==b;i++){
  await admin("update public.rooms set bot_next_action_at=now()-interval '1 second' where code=$1",[code]);await as(b);await rpc('tick_bots',[code]);v=await rpc('get_game_view',[code]);
 }
 assert.equal(v.game.current_turn_user_id,b);
 await rpc('delete_guest_account');assert.equal((await admin('select count(*)::int n from public.rooms where code=$1',[code])).rows[0].n,0);
}
await db.exec('set role anon');await assert.rejects(rpc('delete_guest_account'));await db.exec('reset role');
console.log('PASS: self-only guest deletion, stale-token rejection, active/waiting/power preservation, bot takeover, host transfer, last-human cleanup');await db.close();
