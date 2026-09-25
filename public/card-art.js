// One card face for the live table, practice, and rules sheet.
export function cardFace(label){
 const make=(tag,value,cls)=>{const el=document.createElement(tag);el.textContent=value;el.className=cls;return el;};
 const card=make('span','','card-art');card.setAttribute('role','img');card.setAttribute('aria-label',label);
 const joker=label==='Joker',king=label.includes('K');
 const rank=joker?'JOKER':king?'K':label.replace(/[♠♥♦♣]/g,'');
 card.classList.toggle('red',/♥|♦|Red/.test(label));card.classList.toggle('joker-art',joker);
 card.append(make('span',rank,'art-rank'));
 if(joker){
  const portrait=document.createElementNS('http://www.w3.org/2000/svg','svg');portrait.setAttribute('viewBox','0 0 64 76');portrait.setAttribute('class','joker-portrait');portrait.setAttribute('aria-hidden','true');
  portrait.innerHTML='<path d="M12 31Q4 4 23 16Q30-6 39 16Q60 2 53 31L45 29Q46 15 38 23L32 13L26 23Q15 15 19 30Z" fill="currentColor"/><g fill="currentColor"><circle cx="9" cy="27" r="4"/><circle cx="32" cy="9" r="4"/><circle cx="55" cy="27" r="4"/></g><path d="M18 30Q16 53 32 59Q48 53 46 30Z" fill="none" stroke="currentColor" stroke-width="3"/><path d="M18 31Q32 25 46 31M24 39L28 40M36 40L40 39M26 48Q32 54 38 48" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/><path d="M17 54L12 68L26 64L32 73L38 64L52 68L47 54L38 60L32 64L26 60Z" fill="currentColor"/>';
  card.append(portrait);
 }else card.append(make('strong',(label.match(/[♠♥♦♣]/)||[])[0]||(king?'♚':rank),'art-suit'));
 card.append(make('span',rank,'art-rank bottom'));return card;
}
export function setupRuleCards(){
 const sheet=document.querySelector('#dealIntroView .deal-sheet');
 const section=(title,cls)=>{const el=document.createElement('section');el.className='rule-card-section '+cls;const h=document.createElement('h3');h.textContent=title;el.append(h);return el;};
 const tile=(labels,title,description)=>{const el=document.createElement('div');el.className='rule-card-tile';const cards=document.createElement('div');cards.className='rule-card-examples';for(const label of labels){const c=document.createElement('div');c.className='face rule-example';c.append(cardFace(label));cards.append(c);}const h=document.createElement('h4');h.textContent=title;const p=document.createElement('p');p.textContent=description;el.append(cards,h,p);return el;};
 const points=section('POINTS · LOWEST SCORE WINS','rule-points');
 for(const entry of [[['Black K'],'Face cards','10 points'],[['A♦'],'Ace','1 point'],[['Red K'],'Red king','−1 point'],[['Joker'],'Joker','0 points']])points.append(tile(...entry));
 const numbers=document.createElement('p');numbers.className='rule-number-note';numbers.textContent='Number cards 2–10 score their face value.';points.append(numbers);
 const powers=section('SPECIAL CARD POWERS','rule-powers');
 for(const entry of [[['7♥','8♣'],'7 or 8','Look at one of your own cards.'],[['9♦','10♠'],'9 or 10','Look at an opponent’s card.'],[['J♣','Q♥'],'Jack or queen','Blind swap one of yours with an opponent’s.'],[['Black K'],'Black king','Look at an opponent’s card, then optionally swap it with one of yours.']])powers.append(tile(...entry));
 sheet.querySelector('.sheet-points').replaceWith(points);sheet.querySelector('.sheet-powers').replaceWith(powers);
}
