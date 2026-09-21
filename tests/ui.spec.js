import { test, expect } from '@playwright/test';
import { PGlite } from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
const setup=`create role anon;create role authenticated;create schema auth;create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`;
test('mobile table, private peek, turn lock, settings persistence, reconnect and scoring',async({browser},testInfo)=>{
 const db=new PGlite();await db.exec(setup);await db.exec(readFileSync('supabase/baseline.sql','utf8'));await db.exec(readFileSync('supabase/upgrade.sql','utf8'));await db.exec(readFileSync('supabase/bots.sql','utf8'));await db.exec(readFileSync('supabase/migrations/20260921165500_jokers.sql','utf8'));
 let queue=Promise.resolve();const pages=[];const errors=[];
 for(let n=1;n<=2;n++){
  const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();pages.push(page);page.on('pageerror',e=>errors.push(e.message));
  const id=`00000000-0000-0000-0000-00000000000${n}`;
  await page.route('**/auth/v1/**',async route=>{const user={id,aud:'authenticated',role:'authenticated',is_anonymous:true,email:''};const token='eyJhbGciOiJIUzI1NiJ9.'+Buffer.from(JSON.stringify({sub:id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.signature';await route.fulfill({json:{user,access_token:token,refresh_token:'test-'+n,expires_in:3600,token_type:'bearer'}});});
  await page.route('**/rest/v1/rpc/*',route=>{queue=queue.then(async()=>{try{const name=route.request().url().split('/').pop(),args=route.request().postDataJSON()||{};await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);const keys=Object.keys(args);const {rows}=await db.query(`select * from public.${name}(${keys.map((k,i)=>k+'=> $'+(i+1)).join(',')})`,Object.values(args));const data=rows.length===1&&Object.hasOwn(rows[0],name)?rows[0][name]:rows;await route.fulfill({json:data});}catch(e){await route.fulfill({status:400,json:{message:e.message,code:e.code}});}});return queue;});
  await page.goto('/');
 }
 const [a,b]=pages;
 await expect(a.getByRole('heading',{name:'Play Cambio',exact:true})).toBeVisible();
 await a.screenshot({path:testInfo.outputPath('home-mobile.png'),fullPage:true});
 await a.getByRole('button',{name:'Settings',exact:true}).click();await a.getByRole('button',{name:'After hours'}).click();await a.getByRole('button',{name:'Close settings'}).click();await a.reload();await expect(a.locator('html')).toHaveAttribute('data-theme','midnight');
 await a.getByRole('button',{name:'Settings',exact:true}).click();await a.getByRole('button',{name:'Garden club'}).click();await a.screenshot({path:testInfo.outputPath('settings-mobile.png')});await a.getByRole('button',{name:'Close settings'}).click();
 await a.getByLabel('What should we call you?').fill('Alex');await a.getByRole('button',{name:/Create a table/}).click();await expect(a.locator('#lobbyView')).toBeVisible();const code=await a.locator('#copyCode').textContent();
 await b.getByLabel('What should we call you?').fill('Jordan');await b.getByLabel('Six-character room code').fill(code);await b.getByRole('button',{name:'Join →',exact:true}).click();await expect(b.locator('#lobbyView')).toBeVisible();
 await expect(a.locator('#startBtn')).toBeEnabled();await a.locator('#startBtn').click();for(const p of [a,b]){await expect(p.locator('#dealIntroView')).toBeVisible();await p.getByRole('button',{name:'Play smart. Play Cambio.',exact:true}).click();}await expect(a.locator('#gameView')).toBeVisible();await expect(b.locator('#gameView')).toBeVisible();
 await a.getByRole('button',{name:'Your card 3',exact:true}).click();await expect(a.locator('#hand .face')).toHaveCount(1);await a.getByRole('button',{name:'I’m ready',exact:true}).click();await b.getByRole('button',{name:'I’m ready',exact:true}).click();
 await expect(a.locator('#turnText')).toHaveText('Your move.');await expect(a.locator('#hand .face')).toHaveCount(0);
 await b.getByRole('button',{name:'Your card 3',exact:true}).click();await expect(b.locator('#hand .face')).toHaveCount(1);
 await a.getByRole('button',{name:'Draw from deck'}).click();await expect(a.locator('#actionPanel')).toContainText('You drew');await a.reload();await expect(a.locator('#actionPanel')).toContainText('You drew');await a.getByRole('button',{name:'Your card 1',exact:true}).click();await a.getByRole('button',{name:'Replace selected card',exact:true}).click();
 await expect(b.locator('#turnText')).toHaveText('Your move.');await expect(b.locator('#hand .face')).toHaveCount(0);await b.screenshot({path:testInfo.outputPath('table-mobile.png'),fullPage:true});
 await b.getByRole('button',{name:/Call Cambio/}).click();await expect(a.locator('#turnText')).toHaveText('Your move.');await a.getByRole('button',{name:'Draw from deck'}).click();await a.getByRole('button',{name:'Your card 1',exact:true}).click();await a.getByRole('button',{name:'Replace selected card',exact:true}).click();await expect(a.locator('#roundView')).toBeVisible();await expect(a.locator('.score-row')).toHaveCount(2);
 for(const p of pages){expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await p.context().close();}
 expect(errors).toEqual([]);await db.close();
});
