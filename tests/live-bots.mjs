import {createClient} from '@supabase/supabase-js';import assert from 'node:assert/strict';import {SUPABASE_URL,SUPABASE_ANON_KEY} from '../public/config.js';
const db=createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});let code;
async function rpc(n,p={}){const {data,error}=await db.rpc(n,p);if(error)throw error;return data;}
const call=(n,p={})=>rpc(n,{p_room_code:code,...p});
try{const {error}=await db.auth.signInAnonymously();if(error)throw error;code=(await rpc('create_room',{p_name:'Bot release check'})).room_code;
for(const p_difficulty of ['easy','medium','hard'])await call('add_bot',{p_difficulty});await call('start_game');await call('ready_for_round');await assert.rejects(call('draw_from',{p_source:'discard'}));await call('call_cambio');
let v;for(let i=0;i<60;i++){await call('tick_bots');v=await call('get_game_view');if(v.room.status==='round_over')break;await new Promise(r=>setTimeout(r,1300));}
assert.equal(v.room.status,'round_over');assert.equal((await call('get_round_scores')).length,4);await call('return_to_lobby');await call('leave_room');console.log('PASS live: one human, three difficulties, automatic bot final turns, scoring, discard draw blocked, fixture cleaned');
}catch(e){console.error(e.message,'Room:',code);process.exitCode=1;}finally{await db.auth.signOut();db.realtime.disconnect();}process.exit(process.exitCode||0);
