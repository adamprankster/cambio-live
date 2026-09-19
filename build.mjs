import {build} from 'esbuild';
import {mkdir,copyFile,readFile,writeFile} from 'node:fs/promises';
await mkdir('public/vendor',{recursive:true});
await build({stdin:{contents:"export { createClient } from '@supabase/supabase-js';",resolveDir:process.cwd()},bundle:true,format:'esm',platform:'browser',minify:true,outfile:'public/vendor/supabase.js'});
await build({entryPoints:['native.js'],bundle:true,format:'esm',platform:'browser',minify:true,outfile:'public/vendor/native.js'});
await mkdir('public/fonts',{recursive:true});
for(const family of ['dm-sans','manrope']){
 await copyFile(`node_modules/@fontsource-variable/${family}/files/${family}-latin-wght-normal.woff2`,`public/fonts/${family}.woff2`);
 await copyFile(`node_modules/@fontsource-variable/${family}/LICENSE`,`public/fonts/${family}-LICENSE.txt`);
}
const settings=JSON.parse(await readFile('app-store.json','utf8'));
await writeFile('public/store-config.js','export const supportEmail='+JSON.stringify(settings.supportEmail)+';\nexport const developerName='+JSON.stringify(settings.developerName)+';\n');
console.log('Web and iOS assets ready in public/');
const html=await readFile('public/index.html','utf8');
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
for(const kind of ['privacy','support']){
 let content=html.match(new RegExp('<dialog id="'+kind+'Dialog">([\\s\\S]*?)</dialog>'))[1].replace(/<button[\s\S]*?<\/button>/g,'');
 content=content.replace('<p id="privacyContact"></p>','<p>'+escape(settings.supportEmail?'Privacy contact: '+settings.supportEmail:'Support contact is not configured for release yet.')+'</p>').replace('<p id="privacyOperator"></p>','<p>'+escape(settings.developerName?'Operated by '+settings.developerName+'.':'')+'</p>');
 if(kind==='support'&&settings.supportEmail)content='<h2>Support</h2><p>For help with Cambio Live, contact <a href="mailto:'+escape(settings.supportEmail)+'">'+escape(settings.supportEmail)+'</a>. Include the room code and a description of the issue, but never share your session token.</p><p>For connection issues, check your internet connection and reopen the game. For deletion, use Settings → Delete my guest account.</p>';
 await writeFile('public/'+kind+'.html','<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cambio Live — '+kind+'</title><link rel="stylesheet" href="styles.css"></head><body><main style="max-width:720px;padding:32px">'+content+'<p><a href="./">Back to Cambio</a></p></main></body></html>');
}
