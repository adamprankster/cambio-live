import assert from 'node:assert/strict';
import {lessons,beginLesson,currentStep,perform,advance,playStep} from '../public/tutorial-model.js';
let actions=0;
for(let i=0;i<lessons.length;i++){
 let s=beginLesson(i);
 for(let j=0;j<lessons[i].steps.length;j++){
  const before=structuredClone(s);assert.equal(advance(s),s);assert.equal(perform(s,'not-the-target'),s);
  const step=currentStep(s);s=perform(s,step.target);actions++;assert(s.review);assert(s.notice);assert.equal(before.review,false);assert.equal(perform(s,step.target),s);
  if(step.action==='replace'){assert.equal(s.own[0],'2♦');assert.equal(s.discard,'9♣');}
  if(step.action==='slam'){assert.equal(s.own.filter(Boolean).length,3);assert.equal(s.own[3],null);}
  if(step.action==='wrong'){assert.equal(s.own.length,5);assert.equal(s.own[2],'2♠');assert(!s.shown.includes('own4'));}
  if(step.action==='blindSwap'||step.action==='kingSwap'){assert.equal(s.own[0],'3♠');assert.equal(s.other[0],'9♣');assert.deepEqual(s.shown,[]);}
  if(step.action==='score'){assert.deepEqual(s.totals,{you:9,opponent:29});assert.equal(s.other.reduce((total,c)=>total+parseInt(c),0),21);assert.deepEqual(s.own,['Red K','Joker','A♦','2♠']);}
  s=advance(s);
 }
 assert.equal(s.lesson,(i+1)%lessons.length);
}
assert.deepEqual(beginLesson(0).shown,['own2','own3']);
console.log(`PASS: ${lessons.length} independent lessons, ${actions} guided actions, wrong-action/double-tap protection, replacement, slams, penalties, powers, scoring and restart`);

let slam=beginLesson(1);
slam=playStep(slam,'burn');assert.equal(currentStep(slam).target,'own3');assert(!slam.review);
slam=playStep(slam,'own3');assert.equal(slam.selected,3);assert.equal(currentStep(slam).target,'discard');assert(!slam.review);
slam=playStep(slam,'discard');assert.equal(slam.own[3],null);assert.equal(currentStep(slam).target,'skip');assert(!slam.review);
slam=playStep(slam,'skip');assert(slam.review);
let swap=beginLesson(5);for(const target of ['burn','own0'])swap=playStep(swap,target);
assert.equal(swap.selected,0);assert.equal(currentStep(swap).target,'other0');assert(!swap.review);
swap=playStep(swap,'other0');assert(swap.review);assert.equal(swap.own[0],'3♠');
console.log('PASS: slam and swap selections flow directly to their targets; only lesson endings pause');
