export function dealIntroKey(view){return `${view.room.code}:${view.game?.round_number}:${view.me}`;}
export function needsDealIntro(view,accepted){
 const player=view.players.find(p=>p.user_id===view.me);
 return Boolean(player&&!player.is_bot&&view.room.status==='playing'&&view.game?.phase==='waiting'&&!player.initial_ready&&accepted!==dealIntroKey(view));
}
