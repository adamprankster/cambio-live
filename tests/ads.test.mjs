import assert from 'node:assert/strict';import {createRoomAdGate} from '../public/ads.js';
let calls=0,time=0;const provider={canRequestAds:()=>true,isReady:()=>true,show:async()=>{calls++;return true;}};
assert.equal(await createRoomAdGate({provider,settings:{enabled:false}})('A'),false);assert.equal(calls,0);
const gate=createRoomAdGate({provider,settings:{enabled:true,minimumIntervalMs:100},now:()=>time});assert.equal(await gate('A'),true);assert.equal(await gate('A'),false);assert.equal(await gate('B'),false);time=101;assert.equal(await gate('C'),true);assert.equal(calls,2);
for(const override of [{canRequestAds:()=>false},{isReady:()=>false},{show:async()=>{throw Error('no fill');}}])assert.equal(await createRoomAdGate({provider:{...provider,...override},settings:{enabled:true,minimumIntervalMs:0}})('D'),false);
let release;const concurrent=createRoomAdGate({provider:{...provider,show:()=>new Promise(r=>release=r)},settings:{enabled:true,minimumIntervalMs:0}});const first=concurrent('E');assert.equal(await concurrent('F'),false);release(true);assert.equal(await first,true);
console.log('PASS: ads disabled by default, room deduplication, frequency cap, consent/readiness checks, failure fallback and concurrency');
