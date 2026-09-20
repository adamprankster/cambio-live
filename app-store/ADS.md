# Optional room-created advertisement

The placement hook is implemented, but no ad network is connected and ads are disabled. Adding an ID alone is not sufficient: a provider-specific SDK adapter is still required. No advertising SDK, tracking or ad requests are included in this release.

After create_room succeeds, the app saves the room code, calls showRoomCreatedAd, then opens the lobby. Joining/rejoining, refreshing, dealing and playing do not trigger this hook. It is at most one attempt per created room per app session, with a three-minute interval between successfully displayed ads. Disabled, unavailable, consent-ineligible and failed ads skip directly to the lobby. Only preloaded ads may display, so slow ad loading cannot delay room creation.

Connect the selected network in public/ads-provider.js. Implement synchronous canRequestAds() and isReady(), and asynchronous show({placement}), which resolves true on dismissal or false on presentation failure. The adapter must handle SDK dismissal/failure events, remove listeners, and never leave its promise pending on failure. Preloading and any consent UI occur separately before the create-room transition. No arbitrary network scripts should be pasted into the game.

For a native AdMob integration, add the supported iOS SDK/Capacitor plugin, application ID and interstitial unit, UMP consent flow, required privacy options and SDK configuration. Develop with test ads. A web ad provider needs its own adapter; an iOS AdMob unit cannot display in the website. Before enabling, update the privacy policy, native privacy manifest and App Store disclosures to match the selected provider, and perform a real-device check. Keep enabled:false until that work is complete.

Reference: https://developers.google.com/admob/ios/interstitial
Consent: https://developers.google.com/admob/ios/privacy
