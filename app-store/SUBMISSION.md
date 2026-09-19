# Cambio Live — iPhone and iPad release

## Current status

The iOS source project is prepared. It bundles the same HTML, CSS, JavaScript, fonts, game rules and Supabase connection as the website. Native and web players share rooms. Bots still require internet and a foreground human client. No remote website is loaded as the app's main screen.

**This is not a signed .ipa or a validated App Store archive.** Xcode is not installed on the preparation Mac, so no iOS simulator, device, compiler, signing or archive validation has been run. An Apple Developer team and a support email have not been selected. Apple decides approval; packaging a working game does not guarantee review acceptance.

## Open the project

1. Install the current stable Xcode from the Mac App Store and launch it to finish its setup. Capacitor 8.5.2 requires Xcode 26 or later; use Apple's currently accepted submission SDK.
2. Install Node.js 22 or later if needed.
3. In this project folder, run `sh scripts/prepare-ios.sh`. It installs pinned dependencies, bundles fonts/native adapters and copies the website into the iOS project.
4. Open `ios/App/App.xcodeproj`. Swift Package Manager resolves Capacitor and its App/Clipboard plugins. No CocoaPods installation is needed.
5. Select the **App** target → Signing & Capabilities → choose your Apple Developer team. The suggested bundle identifier is `com.cambiolive.app`; it is not registered or verified as available. Choose an available identifier before the first upload and keep it consistent in `capacitor.config.json`, `app-store.json` and both Xcode build configurations.

Use `npm run ios:sync` after changing the shared app. It does not replace the native icon, privacy manifest or Swift scene code. `npm run ios:check` verifies bundled-file parity and project resources.

## Owner information still needed

Edit `app-store.json`: supportEmail, developerName (the publisher's legal/public name) and appleTeamId. The team field is a release-check record; actual signing must also be selected in Xcode. The support address must be monitored. Run `npm run ios:sync` again after editing.

Publish the generated `public/privacy.html` and `public/support.html` with the website once those values are filled in. Use their HTTPS URLs for the listing. The release check intentionally blocks missing owner information. Do not submit the unconfigured support screen.

## Native and shared changes

- Same mobile design, club wordmark, four themes, controls and rules; safe-area spacing protects the display cutout/home indicator.
- Supplied image installed as an opaque 1024×1024 native App Store/home-screen icon.
- Native clipboard copies room codes. App lifecycle hooks refresh the room/auth session on foregrounding and close private peeks when backgrounded. A native privacy cover hides cards in the app switcher.
- Fonts are bundled with their licenses rather than fetched from Google at launch.
- Settings includes privacy, support and self-service guest account deletion. Deletion removes the guest authentication record and personal identifiers. Where friends remain, a fresh bot identity takes the seat so their pending game actions remain valid. Rooms without a human are removed only when that human explicitly deletes their account.
- Local app UI loads without a network; multiplayer and bot games require internet. There is no offline gameplay claim.

## Before uploading

Run `npm test`, `npm run ios:sync`, `npm run ios:check`, and `npm run ios:release-check`. Then test on an actual iPhone and iPad or supported simulators:

- Create/join a room with a browser player; verify updates in both directions.
- Play Easy/Medium/Hard bots, initial peeks, draw/replace, every power, self/out-of-turn slam and wrong-match penalties.
- Complete Cambio/final turns, a second round, cumulative scores and a new match.
- Background during a peek and pending draw; restore; confirm no cards show in the app switcher and the saved seat reconnects.
- Copy a room code, switch themes, kill/relaunch, rotate and use the keyboard on small and large displays.
- Disconnect/reconnect the network, delete a **new disposable test guest account** from Settings, and confirm other players can continue.
- Confirm privacy/support contact, VoiceOver labels, readable type and no horizontal clipping. Do not claim accessibility support until tested.

Create an App Store Connect record matching the bundle identifier. Set version/build number, select **Any iOS Device (arm64)**, then **Product → Archive → Validate App → Distribute App → App Store Connect**. Start with TestFlight. Provide real device screenshots, support/privacy URLs, age-rating answers, review contact and export-compliance answers. The app only uses platform HTTPS encryption and sets ITSAppUsesNonExemptEncryption=false; reassess if encryption changes.

## Privacy label draft — owner must verify provider practices

The source sends display name, guest user identifier and gameplay content (room membership, cards, scores) to Supabase for app functionality. These are linked to the guest ID, not used for advertising or tracking. There are no ad, analytics, purchase or tracking SDKs. Supabase/hosting operational logs and backup retention must be reviewed by the owner before finalizing the policy and App Store Connect disclosures. Do **not** select “Data Not Collected.” The included PrivacyInfo.xcprivacy declares the game's known collection; SDK manifests are included through Swift Package Manager.

## Draft listing

Name: Cambio Live
Subtitle: Memory, cards, and friends
Category: Games / Card
Description: Four cards. A few secrets. One goal: the lowest score. Create a private table, invite friends with a room code, or add computer opponents. Remember your cards, use special powers, slam matching ranks, and call Cambio when you are ready. Play across iPhone, iPad, and the web, with four color themes and scores that carry across rounds. Internet connection required, including for bot play.
Keywords: cambio,cards,memory,multiplayer,friends,strategy

Review notes: No email/password signup is required. Enter a display name, create a table, add one or more bots, and deal. Peek at the bottom two cards, then press I'm ready. All gameplay logic is server-validated. Bot levels can be selected in the lobby. Guest-account deletion is in Settings. This is a complete interactive card game with bundled screens, not a browser link or remotely downloaded UI. There are no purchases, ads or real-money wagering.

Support URL (after publication): https://cambio-live.netlify.app/support.html
Privacy URL (after publication): https://cambio-live.netlify.app/privacy.html
Marketing URL: https://cambio-live.netlify.app/

## References

- https://capacitorjs.com/docs/ios
- https://capacitorjs.com/docs/getting-started/environment-setup
- https://capacitorjs.com/docs/ios/privacy-manifest
- https://developer.apple.com/app-store/submitting/
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/support/offering-account-deletion-in-your-app/

## Verification record (September 19, 2026)

- Shared game/bot regressions and guest-deletion scenarios pass in local PostgreSQL (PGlite).
- Build, native/web byte parity, plist/project resource checks, icon size/opacity and Swift syntax parsing pass. Syntax parsing is not an iOS compilation.
- Browser preview verified guest table creation, bot lobby and Settings/privacy controls.
- The deletion migration was applied to production; the nine existing rooms and all 468 card records had identical before/after fingerprints.
- Production runtime npm dependencies have no reported vulnerabilities. Three moderate advisories remain in the Capacitor CLI's development-only xcode/uuid dependency chain; npm reports no available fix. These packages are build tools, not bundled game JavaScript or native runtime plugins. Recheck tooling before release.
- A native device build, TestFlight install, app-switcher privacy behavior, native clipboard and visual comparison on iPhone/iPad remain unverified until Xcode is available.
- The web deployment was not replaced with this unconfigured App Store candidate. Public privacy/support pages must be published after owner details are filled in.
