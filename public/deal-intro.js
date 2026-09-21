export function dealIntroKey(view){return `${view.room.code}:${view.game?.round_number}`;}
export function needsDealIntro(view,accepted){return view.room.status==='playing'&&view.game?.phase==='waiting'&&!view.players.find(p=>p.user_id===view.me)?.initial_ready&&accepted!==dealIntroKey(view);}
