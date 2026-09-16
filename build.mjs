import {build} from 'esbuild';
import {mkdir,cp} from 'node:fs/promises';
await mkdir('public/vendor',{recursive:true});
await build({stdin:{contents:"export { createClient } from '@supabase/supabase-js';",resolveDir:process.cwd()},bundle:true,format:'esm',platform:'browser',minify:true,outfile:'public/vendor/supabase.js'});
console.log('Static files ready in public/');
