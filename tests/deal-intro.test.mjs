import assert from 'node:assert/strict';import {dealIntroKey,needsDealIntro} from '../public/deal-intro.js';
const v={room:{code:'ABC123',status:'playing'},game:{phase:'waiting',round_number:1},me:'human',players:[{user_id:'human',initial_ready:false}]};
assert(needsDealIntro(v,null));assert(!needsDealIntro(v,dealIntroKey(v)));assert(needsDealIntro({...v,game:{...v.game,round_number:2}},dealIntroKey(v)));
assert(!needsDealIntro({...v,game:{...v.game,phase:'turn'}},null));assert(!needsDealIntro({...v,players:[{user_id:'human',initial_ready:true}]},null));assert(!needsDealIntro({...v,room:{...v.room,status:'lobby'}},null));
assert(needsDealIntro({...v,room:{...v.room,code:'OTHER1'}},dealIntroKey(v)));
console.log('PASS: rules intro before readiness, acknowledgement persists by room/round, new rounds show rules, active turns/reconnecting ready players do not get interrupted');

// Each human acknowledges independently, regardless of who hosts the room.
const table={...v,room:{...v.room,host_user_id:'host'},players:[{user_id:'host',is_bot:false,initial_ready:false},{user_id:'guest',is_bot:false,initial_ready:false},{user_id:'bot',is_bot:true,initial_ready:true}]};
const host={...table,me:'host'},guest={...table,me:'guest'};
assert(needsDealIntro(host,null));assert(needsDealIntro(guest,null));
assert(needsDealIntro(guest,dealIntroKey(host)));assert(!needsDealIntro(guest,dealIntroKey(guest)));
assert(!needsDealIntro({...table,me:'bot'},null));
assert(!needsDealIntro({...table,me:'bot',players:[{user_id:'bot',is_bot:true,initial_ready:false}]},null));
assert(!needsDealIntro({...table,me:'missing'},null));
console.log('PASS: host and every human guest see rules independently; bots and non-members skip the sheet');
