// Movement events contain positions only. Never render card values in an effect.
export function newSwaps(previous,next){
 if(!previous||previous.room.code!==next.room.code||previous.game?.round_number!==next.game?.round_number)return [];
 const seen=new Set((previous.game?.swap_events||[]).map(e=>e.id));
 return (next.game?.swap_events||[]).filter(e=>e.round===next.game.round_number&&!seen.has(e.id));
}
export function swapMessage(event,view){
 const actor=view.players.find(p=>p.seat===event.actor_seat),target=view.players.find(p=>p.seat===event.target_seat);
 if(target?.user_id===view.me)return `${actor?.name||'A player'} swapped your card ${event.target_position+1}!`;
 if(actor?.user_id===view.me)return `You swapped card ${event.own_position+1} with ${target?.name||'another player'}.`;
 return `${actor?.name||'A player'} swapped cards with ${target?.name||'another player'}.`;
}
let timer;const effects=new Set();
export function clearSwapEffects(){clearTimeout(timer);for(const el of effects)el.remove();effects.clear();document.querySelectorAll('.swap-highlight').forEach(el=>el.classList.remove('swap-highlight'));}
export function showSwapEffects(events,view){
 if(!events.length||document.hidden)return;
 clearSwapEffects();
 const notice=document.createElement('div');notice.className='swap-notice';notice.setAttribute('role','status');notice.setAttribute('aria-live','polite');
 notice.textContent=events.slice(-3).map(e=>swapMessage(e,view)).join(' ');document.body.append(notice);effects.add(notice);
 const reduced=document.documentElement.dataset.reduceMotion==='true'||matchMedia('(prefers-reduced-motion: reduce)').matches;
 for(const event of events){
  const find=(seat,pos)=>[...document.querySelectorAll('[data-card-seat][data-card-position]')].find(el=>Number(el.dataset.cardSeat)===seat&&Number(el.dataset.cardPosition)===pos);
  const a=find(event.actor_seat,event.own_position),b=find(event.target_seat,event.target_position);
  for(const el of [a,b])el?.classList.add('swap-highlight');
  if(!a||!b||reduced)continue;
  const ra=a.getBoundingClientRect(),rb=b.getBoundingClientRect();
  if([ra,rb].some(r=>r.bottom<0||r.top>innerHeight||!r.width))continue;
  for(const [from,to,angle] of [[ra,rb,12],[rb,ra,-12]]){
   const ghost=document.createElement('div');ghost.className='swap-ghost';ghost.textContent='♧';ghost.setAttribute('aria-hidden','true');
   Object.assign(ghost.style,{left:from.left+'px',top:from.top+'px',width:from.width+'px',height:from.height+'px'});document.body.append(ghost);effects.add(ghost);
   const dx=to.left+to.width/2-from.left-from.width/2,dy=to.top+to.height/2-from.top-from.height/2;
   const animation=ghost.animate([{transform:'translate(0,0) rotate(0deg)',opacity:1},{transform:`translate(${dx/2}px,${dy/2}px) rotate(${angle}deg)`,opacity:1,offset:.5},{transform:`translate(${dx}px,${dy}px) rotate(0deg)`,opacity:0}],{duration:1050,easing:'ease-in-out'});
   animation.onfinish=()=>{ghost.remove();effects.delete(ghost);};
  }
 }
 timer=setTimeout(clearSwapEffects,6500);
}
