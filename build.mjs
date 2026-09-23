import {legalPages} from './public/legal-content.js';
import {build} from 'esbuild';
import {mkdir,copyFile,readFile,writeFile,readdir} from 'node:fs/promises';
await mkdir('public/vendor',{recursive:true});
await build({stdin:{contents:"export { createClient } from '@supabase/supabase-js';",resolveDir:process.cwd()},bundle:true,format:'esm',platform:'browser',minify:true,outfile:'public/vendor/supabase.js'});
await build({entryPoints:['native.js'],bundle:true,format:'esm',platform:'browser',minify:true,outfile:'public/vendor/native.js'});
await mkdir('public/fonts',{recursive:true});
for(const family of ['dm-sans','manrope']){
 await copyFile(`node_modules/@fontsource-variable/${family}/files/${family}-latin-wght-normal.woff2`,`public/fonts/${family}.woff2`);
 await copyFile(`node_modules/@fontsource-variable/${family}/LICENSE`,`public/fonts/${family}-LICENSE.txt`);
}
const settings=JSON.parse(await readFile('app-store.json','utf8'));
await writeFile('public/store-config.js','export const supportEmail='+JSON.stringify(settings.supportEmail)+';\nexport const developerName='+JSON.stringify(settings.developerName)+';\nexport const publisherLocation='+JSON.stringify(settings.publisherLocation||'')+';\n');
console.log('Web and iOS assets ready in public/');

const pages=legalPages(settings);
for(const [kind,page] of Object.entries(pages)){
 const body=page.body.replaceAll('<h3>','<h2>').replaceAll('</h3>','</h2>');
 await writeFile('public/'+kind+'.html','<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cambio Live — '+page.title+'</title><link rel="stylesheet" href="styles.css"></head><body><main class="legal-page"><p><a href="./">Back to Cambio</a></p><h1>'+page.title+'</h1>'+body+'<p><a href="privacy.html">Privacy</a> · <a href="support.html">Support</a> · <a href="accessibility.html">Accessibility</a> · <a href="terms.html">Terms</a></p></main></body></html>');
}
// Ship the actual license texts for runtime dependencies and bundled fonts.
const root=JSON.parse(await readFile('package.json','utf8')),seen=new Set(),notices=[];
async function collect(name){
 if(seen.has(name))return;seen.add(name);const dir='node_modules/'+name;
 const pkg=JSON.parse(await readFile(dir+'/package.json','utf8'));
 const files=(await readdir(dir)).filter(f=>/^(license|licence|copying|notice)(\.|$)/i.test(f));
 if(!files.length)throw Error('Missing license text for '+name);
 let entry=name+' '+pkg.version+'\n';
 for(const file of files)entry+='\n'+await readFile(dir+'/'+file,'utf8');
 notices.push(entry);
 for(const dep of Object.keys(pkg.dependencies||{}))await collect(dep);
}
for(const dep of Object.keys(root.dependencies))await collect(dep);
await writeFile('public/third-party-notices.txt','Cambio Live — third-party software notices\n\n'+notices.join('\n\n'+'='.repeat(72)+'\n\n'));
console.log('Privacy, help, accessibility and legal pages generated; '+seen.size+' dependency notices included.');
