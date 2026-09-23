# App Store upload — remaining decisions and checks

Updated September 23, 2026. **Not yet ready to submit.**

## User preference for future conversations

The publisher name, country/state and support email are **not decided**. The user asked to bring these and all other missing steps back up **the next time they ask what is needed for App Store upload**. Do not repeatedly ask for these during unrelated design work. Do not invent contact information, a company, legal jurisdiction or a release date.

## Owner details

- Choose your own or your partner’s Apple Developer account and legal publisher identity.
- Set a monitored support/privacy email, publisher name and country/state in `app-store.json` (`supportEmail`, `developerName`, `publisherLocation`, `appleTeamId`). Update the support/privacy pages and publish them after this decision. The current pages explicitly say the contact/publisher details are not yet available.
- If distributing in the EU, determine your trader status and provide the contact/verification details required by App Store Connect. Do not invent an address or publish a personal address without deciding how the business will be represented.

## Privacy and legal review

- This app DOES collect data. It uses a Supabase anonymous guest account, display name, ID, room membership, gameplay and scores. Do not select “Data Not Collected” on Apple’s privacy form.
- Verify actual Supabase/Netlify logs, retention, backups, hosting locations, subprocessors and transfer arrangements against your plan/settings. The source has no automatic guest-account expiry. Decide and implement a retention period if needed; do not claim data disappears when someone uninstalls.
- Check the published policy against the regions where you will release, your actual business identity, applicable privacy rights and your support process. Obtain a qualified legal review for those jurisdictions. The supplied text is not a guarantee of legal compliance.
- Decide the intended age audience and complete Apple’s age-rating questionnaire accurately. If targeting children or knowingly collecting children’s personal information, get advice on children’s privacy/consent requirements before launch; a disclaimer alone is not a solution.
- Confirm that you have commercial rights to the Cambio name, app icon, rule-sheet artwork and any playing-card illustrations. User-supplied assets have not been independently cleared. Software/font license texts are now included; they do not establish rights to the game branding/art.
- Review display-name abuse handling against Apple guideline 1.2. Names are user-generated content shared in private rooms. There is currently no name filter, in-app report queue or block mechanism. Establish appropriate prevention, reporting, response and blocking before claiming this is resolved. A “Terms” page alone does not provide moderation.
- No ads, tracking, purchases, subscriptions or real-money wagers are enabled. If any are added, revise policy, consent/ATT as applicable, age rating, privacy labels and SDK manifests before enabling them. Do not add tracking prompts when there is no tracking.

## Build, testing and listing

- Install/select full Xcode and build/run the native project. Source checks are not an iOS build, signed archive or TestFlight test.
- Register/confirm the bundle ID; choose signing team; validate an archive; test on supported iPhones/iPads and TestFlight.
- Verify multiplayer, bots, reconnecting, background privacy, native links/clipboard, rotation, and self-service guest deletion on a disposable test account.
- Test keyboard, VoiceOver, Switch Control, larger text, contrast and reduced motion on supported devices before claiming accessibility support. Current accessibility statement records known limitations; there is no WCAG certification claim.
- Complete App Store Connect privacy labels, support/privacy URLs, age rating, review notes/contact, screenshots, encryption/export questions, licenses and distribution agreements. Keep backend services available to reviewers.
- Review native privacy manifests, required-reason APIs and third-party SDK requirements with the actual Xcode archive. Recheck dependencies and current submission SDK requirements.
- Run `npm test`, `npm run ios:sync`, `npm run ios:check`, and `npm run ios:release-check`. A passed script does not replace the manual checks above or Apple’s review.

## Available now

Settings includes Privacy policy, Your data & deletion, Accessibility, Help & contact, Terms & fair play, Software credits, Reduce animations and confirmed guest-data deletion. Matching public pages are at `/privacy.html`, `/data.html`, `/accessibility.html`, `/support.html`, `/terms.html` and `/licenses.html`. Publisher/contact details remain incomplete by the user’s choice.

## Official sources

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 1.2, 2.1, 4.2, 5.1 and 5.2.
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)

- [EU Digital Services Act trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)
