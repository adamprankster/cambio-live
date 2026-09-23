import {legalPages} from './legal-content.js';
import {supportEmail,developerName,publisherLocation} from './store-config.js';
export function setupLegalUI(){
 for(const [key,page] of Object.entries(legalPages({supportEmail,developerName,publisherLocation}))){
  let dialog=document.getElementById(key+'Dialog');if(!dialog){dialog=document.createElement('dialog');dialog.id=key+'Dialog';document.body.append(dialog);}
  dialog.classList.add('legal-dialog');dialog.setAttribute('aria-label',page.title);
  dialog.innerHTML='<div class="dialog-heading"><h2></h2><button class="icon-button" type="button"></button></div><div class="legal-body">'+page.body+'</div>';
  dialog.querySelector('h2').textContent=page.title;const close=dialog.querySelector('button');close.textContent='×';close.setAttribute('aria-label','Close '+page.title.toLowerCase());close.onclick=()=>dialog.close();
  document.getElementById(key+'Btn').onclick=()=>dialog.showModal();
 }
 const toggle=document.getElementById('reduceMotion');let enabled=false;try{enabled=localStorage.getItem('cambio.reduceMotion')==='true';}catch{}
 const apply=()=>{document.documentElement.dataset.reduceMotion=String(toggle.checked);try{localStorage.setItem('cambio.reduceMotion',String(toggle.checked));}catch{}};
 toggle.checked=enabled;apply();toggle.addEventListener('change',apply);
}
