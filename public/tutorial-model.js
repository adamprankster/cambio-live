// A deterministic, local practice table. It never reads or changes a live room.
const hand=()=>['9♣','4♦','2♠','7♥'];
const step=(title,instruction,target,action,feedback)=>({title,instruction,target,action,feedback});
export const lessons=[
 {name:'1 · Remember & draw',steps:[
 step('Remember your bottom two','Your bottom cards are showing: 2 and 7. Remember their positions, then press I’m ready.','ready','ready','They turn face down. In a real game, opening peeks lock when your first turn begins.'),
 step('Draw from the deck','It’s your turn. Tap the highlighted draw pile. You cannot draw from the discard pile.','deck','draw2','You drew a 2. Lower numbers usually help your score.'),
 step('Choose a card to replace','Let’s replace your top-left card. Tap card 1. You don’t get to look at it first.','own0','select0','Card 1 is selected. The replacement is not complete yet.'),
 step('Finish the replacement','Press Replace selected card to keep the 2.','replace','replace','Your old 9 goes to the discard pile. The 2 stays face down in position 1. Replacing a card ends your turn and does not activate a power.') ]},
 {name:'2 · Slam a matching card',steps:[
 step('Discard your draw','You drew a 7. Your bottom-right card is also a 7. Discard your draw to set up a slam.','burn','burn','The discard is now a 7. Its own-card peek power is available; you can still slam during that power.'),
 step('Select your matching card','Tap your bottom-right card, which you memorized as a 7. Matching uses rank, so suits don’t matter.','own3','select3','Now tap the discard pile. Selecting a card alone does not slam it.'),
 step('Slam!','Tap the highlighted discard pile to slam your selected 7. There is no separate slam button.','discard','slam','Match! Your card is removed, leaving an empty space and three cards. You can slam after your own discard, or during someone else’s turn. Slamming does not activate another power.'),
 step('Finish the power','The 7 you drew still has a peek power. For this practice, skip it to finish your turn.','skip','skip','You can skip a power when you don’t want to use it.') ]},
 {name:'3 · A wrong slam',steps:[
 step('Try a deliberate mistake','The discard is a 5. Your bottom-left card is a 2. Select that card so you can see what a wrong slam does.','own2','select2','The selected card does not match the discard. Tap the pile to try it anyway.'),
 step('See the penalty','Tap the discard pile. In a real game, only slam when you remember a match.','discard','wrong','No match. Your 2 stays, and a fifth face-down card is added. The new card’s value is unknown; it counts toward your score. Penalty cards can be replaced or slammed too.') ]},
 {name:'4 · 7 / 8: peek at yours',steps:[
 step('Use a 7 or 8','You drew an 8. Discard it to use its own-card peek power.','burn','burn','Now select one of your own cards. Keeping the 8 by replacing a card would not activate this power.'),
 step('Choose your card','Select your top-left card.','own0','select0','Press Peek selected card to reveal it privately.'),
 step('Take a look','Press Peek selected card.','peek','peekOwn','It’s a 9. Remember it. In a real game this private peek closes automatically after a few seconds.'),
 step('Hide it again','Press Hide card when you have memorized the 9. Practice waits for you; the real game has a short peek timer.','hide','hide','The 9 is hidden again. Nobody else gets to see your peek.') ]},
 {name:'5 · 9 / 10: peek at theirs',steps:[
 step('Use a 9 or 10','Discard your drawn 10 to peek at an opponent’s card.','burn','burn','Choose a card on the practice opponent’s side.'),
 step('Peek at an opponent','Tap the opponent’s highlighted top-left card.','other0','peekOther','It’s a 3. This information is private to you; peeking does not move the card.'),
 step('Remember its location','Press Hide card.','hide','hide','The 3 stays with your opponent. Keep track of later swaps!') ]},
 {name:'6 · J / Q: blind swap',steps:[
 step('Use a jack or queen','Discard your queen to swap one of your cards with an opponent’s, without looking.','burn','burn','Choose your card first, then an opponent’s card.'),
 step('Choose yours','Select your top-left card.','own0','select0','Now select the opponent’s top-left card to complete the swap.'),
 step('Choose theirs','Tap the opponent’s highlighted card. Neither value will be revealed.','other0','blindSwap','The two face-down cards changed places. Swap notices tell everyone which positions moved, but not the card values.') ]},
 {name:'7 · Black king: peek & choose',steps:[
 step('Use a black king','Discard the black king you drew. It lets you peek at an opponent’s card and then decide whether to swap.','burn','burn','Tap the highlighted opponent card to look at it privately.'),
 step('Look before deciding','Tap the opponent’s top-left card.','other0','peekOther','It’s a 3. You can keep both cards as they are, or swap it with one of yours. Let’s practice swapping.'),
 step('Choose your swap','Your top-left card is a 9 in this preset lesson. Select it.','own0','select0','Press Swap selected card to exchange your 9 for their 3.'),
 step('Complete the king swap','Press Swap selected card.','swap','kingSwap','The 3 is now yours, face down. In a real game, choose Keep cards as they are if you don’t want the swap.') ]},
 {name:'8 · Cambio & scoring',steps:[
 step('Call before drawing','Your preset hand has a red king, joker, ace and 2: just 2 points. Call Cambio at the start of your turn, instead of drawing.','cambio','cambio','You take no draw. Every other player now gets exactly one final turn. With one opponent, that means one final turn.'),
 step('One final turn','Press Play opponent’s final turn to see the practice opponent draw and replace a card.','final','final','Their 8 is replaced by a 4. The round ends and all remaining cards are revealed.'),
 step('Add up the round','Your cards: −1 + 0 + 1 + 2 = 2. Opponent: 4 + 3 + 6 + 8 = 21. You called and are strictly lowest. Press Score round.','score','score','With the default −5 caller bonus, you score −3 this round (2 − 5). Your opponent scores 21. These add to previous rounds: starting at 12 and 8 gives totals of 9 and 29. A wrong or tied call gets +10 by default. The host can change these adjustments.'),
 step('You’re ready to play','Red kings are −1 with no power; jokers are 0. Aces are 1, numbers keep their value, and J/Q/black kings are 10. At the score limit (default 50), the lowest total wins. Overall ties share the win.','done','done','Practice complete. Try any lesson again, or close practice and start a real table.') ]}
];
export function beginLesson(index=0){
 return {lesson:index,step:0,review:false,own:hand(),other:['3♠','6♣','8♦','8♠'],shown:index===0?['own2','own3']:[],selected:null,discard:index===2?'5♥':'6♥',drawn:({1:'7♣',3:'8♠',4:'10♥',5:'Q♦',6:'Black K'})[index]||null,notice:'',totals:null,...(index===7?{own:['Red K','Joker','A♦','2♠'],other:['8♣','3♠','6♦','8♠'],shown:['own0','own1','own2','own3']}:{})};
}
export function currentStep(s){return lessons[s.lesson].steps[s.step];}
export function perform(s,target){
 if(s.review||target!==currentStep(s).target)return s;
 const n={...s,own:[...s.own],other:[...s.other],shown:[...s.shown],review:true,notice:currentStep(s).feedback};
 const a=currentStep(s).action;
 if(a==='ready'||a==='hide')n.shown=[];
 if(a==='draw2')n.drawn='2♦';
 if(a.startsWith('select'))n.selected=Number(a.slice(6));
 if(a==='replace'){n.discard=n.own[n.selected];n.own[n.selected]=n.drawn;n.drawn=null;n.selected=null;}
 if(a==='burn'){n.discard=n.drawn;n.drawn=null;}
 if(a==='slam'){n.discard=n.own[n.selected];n.own[n.selected]=null;n.selected=null;}
 if(a==='wrong'){n.own.push('J♣');n.selected=null;}
 if(a==='peekOwn')n.shown=['own'+n.selected];
 if(a==='peekOther')n.shown=['other0'];
 if(a==='blindSwap'||a==='kingSwap'){[n.own[n.selected],n.other[0]]=[n.other[0],n.own[n.selected]];n.selected=null;n.shown=[];}
 if(a==='final'){n.discard=n.other[0];n.other[0]='4♣';n.shown=['own0','own1','own2','own3','other0','other1','other2','other3'];}
 if(a==='score')n.totals={you:9,opponent:29};
 return n;
}
export function advance(s){if(!s.review)return s;if(s.step+1<lessons[s.lesson].steps.length)return {...s,step:s.step+1,review:false,notice:''};return beginLesson((s.lesson+1)%lessons.length);}

// Keep linked game actions flowing; pause only at a lesson boundary.
export function playStep(s,target){
 const result=perform(s,target);
 if(result===s)return s;
 if(result.step===lessons[result.lesson].steps.length-1)return result;
 return {...advance(result),notice:result.notice};
}
