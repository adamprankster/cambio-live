import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {dealIntroKey,needsDealIntro} from '../public/deal-intro.js';
const source=readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
const fn=source.slice(source.indexOf('async function revealOpening()'),source.indexOf('function closePeek()'));
for(const id of ['host','friend']){
 const player={user_id:id,initial_ready:false,first_turn_started:false};
 const state={view:{me:id,room:{code:'ABC123',status:'playing'},game:{phase:'waiting',round_number:1},players:[player]},initial:{},epoch:1,peekGeneration:0,autoPeekKey:null};
 let requests=0,mode='auto',deferred;
 const context=vm.createContext({state,document:{hidden:false},mine:()=>player,dealIntroKey,needsDealIntro,storage:{get:()=>null},openingMode:()=>mode,call:async()=>{requests++;return deferred?await deferred:[{position:2,card_label:'2♠'},{position:3,card_label:'Black K'}];}});
 vm.runInContext(fn,context);
 await context.revealOpening();assert.equal(requests,0,'do not consume reveal behind rules sheet');
 state.dealIntro=dealIntroKey(state.view);await context.revealOpening();assert.equal(Object.keys(state.initial).length,2);
 await context.revealOpening();assert.equal(requests,1,'do not reopen intentionally hidden cards on every poll');
 state.initial={};state.autoPeekKey=null;state.peekGeneration++;context.document.hidden=true;await context.revealOpening();assert.equal(requests,1);
 context.document.hidden=false;await context.revealOpening();assert.equal(Object.keys(state.initial).length,2,'returning before ready restores reveal');
 state.initial={};state.autoPeekKey=null;let resolve;deferred=new Promise(r=>resolve=r);const pending=context.revealOpening();state.peekGeneration++;context.document.hidden=true;resolve([{position:2,card_label:'2♠'},{position:3,card_label:'Black K'}]);await pending;
 assert.equal(state.autoPeekKey,null,'cancelled request must not consume reveal');assert.equal(Object.keys(state.initial).length,0);
 context.document.hidden=false;deferred=null;await context.revealOpening();assert.equal(Object.keys(state.initial).length,2);
 for(const block of ['pending','ready','firstTurn','manual','never']){
  state.initial={};state.autoPeekKey=null;state.readyPending=block==='pending';player.initial_ready=block==='ready';player.first_turn_started=block==='firstTurn';mode=['manual','never'].includes(block)?block:'auto';const before=requests;await context.revealOpening();assert.equal(requests,before,block+' must not auto reveal');
 }
}
console.log('PASS: host and friend opening reveal, rules acknowledgement, background/resume, cancelled requests, ready/first-turn locks and alternative modes');
