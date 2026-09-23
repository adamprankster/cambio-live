# iPhone / App Store project

The game now includes a Capacitor 8.5.2 iOS project. Start with [app-store/SUBMISSION.md](app-store/SUBMISSION.md). Run `sh scripts/prepare-ios.sh` to prepare/open Xcode. Native and web clients use the same screens, bundled fonts and live backend.

**Not yet a signed/uploadable release:** Xcode is not installed here; Apple team, publisher name and support email remain unset. Device testing, real screenshots, signing and App Store validation are still required. The release check reports these blockers rather than presenting an untested archive as complete.

The guest deletion migration is additive and has its own regression tests. Run all tests with `npm test`. Build and native asset parity are checked with `npm run ios:sync && npm run ios:check`.

# Current live release

Live: https://cambio-live.netlify.app

Hosts can add or remove bots in the lobby (Easy, Medium, Hard), with up to six total human/bot seats. Bots remember only legitimately seen cards; lower difficulties forget. Bot turns run while a human has the room open and resume when someone returns.

Draw only from the deck. To slam, tap your card then the discard pile, including after discarding your own draw. Wrong matches add a hidden penalty card. Selecting a card also enables an explicit replace/peek/swap action when appropriate. The supplied image is the favicon, home-screen icon and manifest icon.

The additive `supabase/bots.sql` migration has been applied to production. Existing rooms are retained. No manual Supabase steps are required for this release. Fresh installations apply baseline.sql, upgrade.sql, bots.sql, then every file in supabase/migrations in filename order, once each. Do not rerun migrations on the live database.

Validation: database regression tests, bot/mixed-room tests, own-discard slams (normal and power cards), deck-only enforcement, local browser game checks.

---

# Cambio Live

Updated static web app and Supabase game engine, recovered from the existing Netlify deployment and audited against the live database on September 15, 2026.

## Release status

**Live:** [cambio-live.netlify.app](https://cambio-live.netlify.app).

The frontend and Supabase update were published together. The two existing rooms, all 104 cards, current turns, and pending powers were preserved. A live two-player smoke test verified anonymous create/join, cross-client Realtime events, initial-peek locking, pending draws, drawing from both piles, Cambio, final reveals and cumulative scoring. Its temporary room was removed after the test.

The source was recovered from the existing Netlify deployment because the GitHub repository was initially empty. The SQL targets the actual live schema rather than the stale schema previously bundled with that deployment.

## What changed

- Server-enforced initial peek: only bottom positions 3 and 4, available repeatedly until each player's first turn starts. A ready stage gives the first player time to memorize their cards. Peeked cards hide at the turn boundary, on backgrounding, and when the table changes.
- New responsive home, lobby, table and results screens. Four persistent device themes: Garden club, After hours, Wild berry and Golden hour. Settings and rules open without leaving a game.
- Draw from the deck, replace any existing card including penalties, or discard the drawn card. A power activates only when the drawn card is discarded.
- 7/8 own peek; 9/10 opponent peek; J/Q blind swap; black King opponent peek followed by an optional swap; red King worth −1 with no power. Powers can be skipped. Private powers are validated and consumed by the server.
- Out-of-turn slams match ranks. Wrong guesses retain the original card and add one hidden penalty. Stale discard attempts are rejected without a penalty. Empty slots remain empty.
- Cambio before drawing, exactly one final turn for every other player, final card reveal and score breakdowns. Defaults: successful caller −5, wrong/tied caller +10, match ends when someone reaches 50. Hosts can edit those amounts in the lobby. Lowest total wins; overall ties share the win.
- A per-round score ledger adds totals exactly once. A completed match can be reset for another match.
- Explicit discard ordering, recycled decks, reserved pending draws, serialized room actions, dynamic hand sizes, and zero-card scores.
- One authenticated game-view RPC replaces mismatched frontend state reads. Reloads recover pending draws and powers; Realtime updates are backed by a two-second refresh while the page is visible.
- Public RPCs use invoker wrappers over checked private implementations. Internal helpers and hidden tables are not directly readable/callable by players. Search paths and grants are explicit.

## Supabase status

The upgrade is already applied to [Cambio Live](https://supabase.com/dashboard/project/kpusdvkmopdhzvuakbva) as migration `cambio_gameplay_ui_contract`. Anonymous sign-ins and Realtime are enabled. **No manual Supabase setup is needed for the live site.**

`supabase/upgrade.sql` is retained as the audited upgrade source. Do not rerun it or `baseline.sql` on the live project. Existing rounds keep their hands and turn state; their initial peeks remain closed. New rounds use the ready stage and exact first-turn peek boundary. `supabase/verify.sql` contains read-only inspection queries.

### Fresh Supabase projects only

Run `supabase/baseline.sql`, then `supabase/upgrade.sql`, then `supabase/bots.sql`. Enable anonymous sign-ins and update `public/config.js` for that project. The baseline is a reconstruction of the live schema, not the stale SQL previously hosted on Netlify.

## Netlify deployment

The app remains static. No backend server, framework migration, or new hosting provider is required.

- Git deployment: commit this project, use `npm run build`, and publish **`public`**. `netlify.toml` already contains these settings.
- Manual deployment: upload the contents of **`public/`**, or the included `cambio-live-deploy.zip`. The bundled Supabase browser client is already present, so a manual upload needs no build.
- The matching SQL update is already installed on the live project. Existing users should refresh their page to load the new interface. For future releases, keep frontend and database API versions compatible.
- Source, tests and SQL are outside `public/`, so they are not published as site assets.

## Development and verification

```sh
npm ci
npm run build
npm test
```

The database tests execute the actual SQL in PGlite, a local PostgreSQL runtime, using authenticated/anonymous role boundaries. They cover peek timing, unauthorized and replayed powers, draw/replace choices, every power, final turns, caller bonus/tie penalty, match threshold, final reveal, score idempotency, zero-card scoring, slams, stale discards, recycling, and reserved draws during penalties.

For an isolated interactive preview using the same SQL and a local-only Auth/API fixture:

```sh
node tests/preview-server.mjs
```

Open `http://127.0.0.1:4173`. This fixture does **not** contact or modify production. It uses polling instead of a Realtime server. It is for local development and is not deployed.

An automated browser suite is included:

```sh
npx playwright install chromium
npm run test:ui
```

You can set `PLAYWRIGHT_CHROMIUM_EXECUTABLE` to an installed Chromium/Chrome executable instead. In this session, the standalone browser process was blocked by the execution sandbox, so the automated Playwright suite could not run. Equivalent core flows were checked interactively in the Codex browser against the local SQL fixture: mobile and desktop layouts, saved theme after reload, room creation, initial peek, first-turn lock, draw recovery after reload, blind swap, final turn/results, and saving host scoring rules. The 390-pixel layout had no horizontal overflow.

## Audit notes and practical limits

- Live security advisors reported mutable search paths and exposed privileged functions. The upgrade fixes these. References: [function search paths](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable) and [privileged RPC access](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- Advisor notices for hidden tables with RLS and no policies are intentional: players must use checked RPCs. Room-member access for anonymous-authenticated players is also intentional. References: [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) and [anonymous users](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins).
- Password protection was disabled on the live project; this app uses anonymous sessions, not passwords. If password accounts are added later, review [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- A disconnected player keeps their seat. There is no host kick, turn timer or automatic forfeit. Clear a lost/abandoned room deliberately; do not remove a player mid-round.
- The initial peek cannot make a player forget information they legitimately saw or cached earlier. The server prevents new unauthorized reads after the first-turn boundary.
- The live two-client smoke test passed with six cross-client Realtime events. The bundled `tests/live-smoke.mjs` can repeat that check; it creates two guest users and an isolated room, then removes that room after passing.
- The bonus and penalty amounts were unspecified in the original request. The default is −5/+10, with a default limit of 50; all are adjustable by the host.

## Rules screen and jokers

After the host deals, each player sees the supplied rules sheet. Tap “Play smart. Play Cambio.” to enter the table, peek, and get ready. Every new round uses 54 cards, including two jokers worth zero with no special power; jokers match one another for slamming. The additive jokers migration preserves cards in existing rounds.

## App Store readiness

See [app-store/REMAINING-STEPS.md](app-store/REMAINING-STEPS.md) for unresolved upload steps, owner decisions and legal/privacy review items. Settings and public information pages are implemented; this does not mean the app has been approved or is ready to submit.
