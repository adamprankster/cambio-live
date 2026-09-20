import {adSettings,adProvider} from './ads-provider.js';
// Called only after a successful create_room, before showing its lobby.
// Providers must preload elsewhere; never hold the lobby waiting for an ad load.
export function createRoomAdGate({settings=adSettings,provider=adProvider,now=Date.now}={}){
 const attempted=new Set();let lastShown=-Infinity,showing=false;
 return async roomCode=>{
  if(!settings.enabled||!provider||showing||attempted.has(roomCode))return false;
  attempted.add(roomCode);
  if(attempted.size>100)attempted.delete(attempted.values().next().value);
  try{
   if(now()-lastShown<settings.minimumIntervalMs||!provider.canRequestAds()||!provider.isReady())return false;
   showing=true;
   // Resolves only on dismissal or failure. The adapter owns SDK event cleanup.
   const shown=await provider.show({placement:'room-created'});
   if(shown)lastShown=now();
   return Boolean(shown);
  }catch{return false;}finally{showing=false;}
 };
}
export const showRoomCreatedAd=createRoomAdGate();
