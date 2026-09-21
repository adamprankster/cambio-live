import assert from 'node:assert/strict';import {dealIntroKey,needsDealIntro} from '../public/deal-intro.js';
const v={room:{code:'ABC123',status:'playing'},game:{phase:'waiting',round_number:1},me:'human',players:[{user_id:'human',initial_ready:false}]};
assert(needsDealIntro(v,null));assert(!needsDealIntro(v,dealIntroKey(v)));assert(needsDealIntro({...v,game:{...v.game,round_number:2}},dealIntroKey(v)));
assert(!needsDealIntro({...v,game:{...v.game,phase:'turn'}},null));assert(!needsDealIntro({...v,players:[{user_id:'human',initial_ready:true}]},null));assert(!needsDealIntro({...v,room:{...v.room,status:'lobby'}},null));
assert(needsDealIntro({...v,room:{...v.room,code:'OTHER1'}},dealIntroKey(v)));
console.log('PASS: rules intro before readiness, acknowledgement persists by room/round, new rounds show rules, active turns/reconnecting ready players do not get interrupted');
