import {cardFace as face} from './card-art.js';
import {lessons,beginLesson,currentStep,playStep,advance} from './tutorial-model.js';
export function setupTutorial({isInGame=()=>false}={}){
 let state=beginLesson();let swapping=false;
 const dialog=document.createElement('dialog');dialog.id='tutorialDialog';dialog.setAttribute('aria-labelledby','tutorialTitle');
 dialog.innerHTML=`<div class="tutorial-top"><div><p class="eyebrow">GUIDED PRACTICE · PRESET CARDS</p><h2 id="tutorialTitle">Learn by playing</h2></div><button id="tutorialClose" class="icon-button" aria-label="Close practice">×</button></div><p id="tutorialLive" class="muted" hidden>Your live table keeps running while you practice. Close practice to return to it.</p><label for="tutorialLesson">Choose a lesson</label><select id="tutorialLesson"></select><div id="tutorialCoach" class="tutorial-coach" aria-live="polite" aria-atomic="true"></div><div id="tutorialTable" class="tutorial-table"></div><p id="tutorialFeedback" role="status"></p><div class="tutorial-controls"><button id="tutorialRestart">Restart lesson</button><button id="tutorialNext" class="primary">Continue →</button></div>`;
 document.body.append(dialog);const $=id=>dialog.querySelector('#'+id);
 lessons.forEach((l,i)=>{const opt=document.createElement('option');opt.value=i;opt.textContent=l.name;$('tutorialLesson').append(opt);});
 function node(tag,value,cls=''){const el=document.createElement(tag);el.textContent=value;el.className=cls;return el;}
 async function animateSwap(){
 const a=dialog.querySelector('.tutorial-own-group .selected'),b=dialog.querySelector('.opponent-practice .tutorial-card');if(!a||!b)return;
 a.classList.add('swap-highlight');b.classList.add('swap-highlight');
 if(document.documentElement.dataset.reduceMotion==='true'||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
 const rect=dialog.getBoundingClientRect(),ra=a.getBoundingClientRect(),rb=b.getBoundingClientRect();
 $('tutorialLesson').disabled=true;$('tutorialRestart').disabled=true;
 try{await Promise.all([[ra,rb],[rb,ra]].map(async([from,to])=>{
 const ghost=node('div','♧','tutorial-swap-ghost');ghost.setAttribute('aria-hidden','true');
 Object.assign(ghost.style,{left:(from.left-rect.left+dialog.scrollLeft)+'px',top:(from.top-rect.top+dialog.scrollTop)+'px',width:from.width+'px',height:from.height+'px'});dialog.append(ghost);
 try{await ghost.animate([{transform:'translate(0,0) rotate(0deg)'},{transform:`translate(${(to.left-from.left)/2}px,${(to.top-from.top)/2}px) rotate(12deg)`,offset:.5},{transform:`translate(${to.left-from.left}px,${to.top-from.top}px) rotate(0deg)`}],{duration:950,easing:'ease-in-out'}).finished;}finally{ghost.remove();}
 }));}finally{$('tutorialLesson').disabled=false;$('tutorialRestart').disabled=false;}
 }
 function control(key,label,cls=''){
 const b=node('button',label,cls),active=!state.review&&currentStep(state).target===key;b.type='button';b.disabled=!active&&!(key==='own'+state.selected&&!state.review);b.classList.toggle('tutorial-target',active);b.setAttribute('aria-describedby','tutorialCoach');
 b.onclick=async()=>{if(swapping)return;const action=currentStep(state).action;if(['blindSwap','kingSwap'].includes(action)&&currentStep(state).target===key){swapping=true;try{await animateSwap();}finally{swapping=false;}}if(key==='own'+state.selected&&currentStep(state).target!==key){state={...state,notice:'Card '+(state.selected+1)+' is selected. '+currentStep(state).instruction};}else state=playStep(state,key);render();const next=state.review?$('tutorialNext'):dialog.querySelector('.tutorial-target');next?.focus({preventScroll:true});};return b;
 }
 function card(key,label,caption,up=false){
 const b=control(key,'','tutorial-card '+(up?'face':'back')+(key==='own'+state.selected?' selected':''));b.setAttribute('aria-label',caption+(up?': '+label:''));if(key.startsWith('own'))b.setAttribute('aria-pressed',String(key==='own'+state.selected));
 b.append(up?face(label):node('strong','♧'));if(/^(own|other)/.test(key))b.append(node('small',caption.replace('Your card ','').replace('Opponent card ',''),'tutorial-position'));if(!state.review&&currentStep(state).target===key)b.append(node('span',key==='discard'?'Tap to slam':'Tap here ↑','tutorial-tap-marker'));if(key==='own'+state.selected)b.append(node('span','✓ Selected','tutorial-selected-marker'));return b;
 }
 function render(){
 const step=currentStep(state);$('tutorialLesson').value=state.lesson;
 $('tutorialCoach').replaceChildren(node('small',`Lesson ${state.lesson+1} of ${lessons.length} · Step ${state.step+1} of ${lessons[state.lesson].steps.length}`),node('h3',step.title),node('p',step.instruction));
 const table=$('tutorialTable');table.replaceChildren();
 const opponent=node('div','','tutorial-hand opponent-practice');state.other.forEach((c,i)=>opponent.append(card('other'+i,c,'Opponent card '+(i+1),state.shown.includes('other'+i))));const opponentGroup=node('section','','tutorial-opponent-group');opponentGroup.append(node('h3','Practice opponent'),opponent);opponentGroup.hidden=state.lesson<4||(state.review&&step.action==='done');table.append(opponentGroup);
 const piles=node('div','','tutorial-piles');const deck=node('div');deck.append(card('deck','','Draw pile'),node('small','DRAW'));const discard=node('div');discard.append(card('discard',state.discard,'Discard pile',true),node('small','DISCARD'));piles.append(deck,discard);
 if(state.drawn){const draw=node('div');draw.append(card('drawn',state.drawn,'Your draw',true),node('small','YOUR DRAW'));piles.append(draw);}table.append(piles);
 const ownGroup=node('section','','tutorial-own-group');ownGroup.append(node('h3',`Your cards · ${state.own.filter(Boolean).length}`));const own=node('div','','tutorial-hand');state.own.forEach((c,i)=>own.append(c?card('own'+i,c,'Your card '+(i+1),state.shown.includes('own'+i)):node('div','Empty','tutorial-empty')));ownGroup.append(own);table.append(ownGroup);
 const labels={ready:'I’m ready',replace:'Replace selected card',burn:'Discard this card',skip:'Skip power',peek:'Peek selected card',hide:'Hide card',swap:'Swap selected card',cambio:'Call Cambio',final:'Play opponent’s final turn',score:'Score round',done:'Finish practice'};
 if(labels[step.target])table.append(control(step.target,labels[step.target],'primary tutorial-action'));
 if(state.totals)table.append(node('p',`Running totals: You ${state.totals.you} · Opponent ${state.totals.opponent}`,'tutorial-totals'));
 $('tutorialFeedback').textContent=state.notice;$('tutorialFeedback').hidden=!state.review;$('tutorialNext').hidden=!state.review;
 const last=state.step===lessons[state.lesson].steps.length-1;const finished=last&&state.lesson===lessons.length-1;
 $('tutorialNext').textContent=finished?'Back to How to play':last?'Next lesson →':'Continue →';
 }
 $('tutorialLesson').onchange=()=>{if(swapping)return;state=beginLesson(Number($('tutorialLesson').value));render();};
 $('tutorialRestart').onclick=()=>{if(swapping)return;state=beginLesson(state.lesson);render();};
 $('tutorialNext').onclick=()=>{if(state.lesson===lessons.length-1&&state.step===lessons[state.lesson].steps.length-1){dialog.close();return;}state=advance(state);render();const target=dialog.querySelector('.tutorial-target');target?.focus({preventScroll:true});};
 $('tutorialClose').onclick=()=>dialog.close();
 document.getElementById('tutorialBtn').onclick=()=>{$('tutorialLive').hidden=!isInGame();render();dialog.showModal();};
}
