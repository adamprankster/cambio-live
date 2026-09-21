import assert from 'node:assert/strict';import {readFileSync,existsSync,readdirSync,statSync} from 'node:fs';import {spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
const config=JSON.parse(readFileSync('capacitor.config.json'));assert.equal(config.webDir,'public');assert(!config.server?.url,'App must bundle its screens, not load a remote website');assert.equal(config.ios.webContentsDebuggingEnabled,false);
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
for(const f of ['index.html','app.js','ads.js','ads-provider.js','deal-intro.js','swap-effects.js','deal-rules.png','styles.css','config.js','store-config.js','vendor/supabase.js','vendor/native.js','fonts/dm-sans.woff2','fonts/manrope.woff2'])assert.equal(hash('public/'+f),hash('ios/App/App/public/'+f),'iOS assets out of sync: '+f);
const icon=readFileSync('ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png');assert.equal(icon.readUInt32BE(16),1024);assert.equal(icon.readUInt32BE(20),1024);assert(![4,6].includes(icon[25]),'App Store icon must not have an alpha channel');
const proj=readFileSync('ios/App/App.xcodeproj/project.pbxproj','utf8');assert(proj.includes('PrivacyInfo.xcprivacy in Resources'));assert.equal((proj.match(/PrivacyInfo.xcprivacy in Resources/g)||[]).length,2);
const info=readFileSync('ios/App/App/Info.plist','utf8');assert(info.includes('ITSAppUsesNonExemptEncryption'));assert(!info.includes('NSAllowsArbitraryLoads'));
assert(!readFileSync('public/styles.css','utf8').includes('fonts.googleapis.com'));
for(const file of ['public/app.js','native.js','scripts/check-ios.mjs'])assert.equal(spawnSync(process.execPath,['--check',file]).status,0);
console.log('PASS: native/web asset parity, bundled fonts, local entry point, 1024px opaque icon, privacy resources, secure transport, JavaScript syntax');
if(process.argv.includes('--release')){
 const settings=JSON.parse(readFileSync('app-store.json'));const blockers=[];
 for(const key of ['supportEmail','developerName','appleTeamId'])if(!settings[key])blockers.push('Set '+key+' in app-store.json');
 if(settings.supportEmail&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(settings.supportEmail))blockers.push('Support email is invalid');
 if(spawnSync('xcodebuild',['-version'],{encoding:'utf8'}).status!==0)blockers.push('Install full Xcode and select its developer tools');
 if(blockers.length){console.error('Submission blockers:\n- '+blockers.join('\n- '));process.exitCode=1;}else console.log('Configuration checks passed. Device tests, signing, archive validation and listing review are still required.');
}
