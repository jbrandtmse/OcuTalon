---
title: 'Story 16.3: Signing in opens a session this browser resumes until the reset'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: '4c70aa27b56afda59b5fe9d7df7872014285655c'
baseline_commit: '4c70aa27b56afda59b5fe9d7df7872014285655c'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-4, lines 152-175; AD-13, lines 342-386, the sign-in, session-lifetime, forwarded-address and busy bullets; AD-27, lines 742-751; AD-19''s seed and product-values bullets, 493-498, its proxy-address row, 508, and its public-settings bullet, 514-517; AD-25''s proxy bullet, 682-694, probe bullet, 710-713, and capacity bullet, 714-716)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only The splash screen, lines 98-124; Formats, 176-190; State Patterns › Too many sessions, line 347)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/mockups/splash.html (the too-many-sessions panel, lines 627-647)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the online demo every visitor signs in with the same IRIS account, and `Ownership.SessionRef` still resolves the session from the IRIS user name (`Session.ForUser`), so all visitors share one conversation, pairing, orders and approval requests (FR-14, FR-15, DW-16). Nothing limits new sessions per client address, and the splash cannot say so.

**Approach:**
- On the online demo, `OcuTalon.Web.SessionEvents.OnLogin` gives each sign-in its own `Session` row:
  - with no resumable cookie, a new row and a resume cookie whose reference the row keeps only as a SHA-256;
  - with a resumable cookie, the row it names is attached instead.
- `OcuTalon.Data.Ownership` stays the one resolver and never falls back to the user name there.
- New sessions from a proxied client address are counted in `OcuTalon.Data.AddressCounter`. The sixth in an hour is refused by the post-sign-in check, which ends the CSP session and shows the UX's field error on the splash.
- Local and IPM installs keep Story 2.2's one durable session per IRIS user, unchanged.

## Boundaries & Constraints

**Always:**
- **The flag decides.** Every new branch runs only when `Public.Settings.Get("onlineDemo")` is "1" (read through `Setting.Get`). With the flag off, `OnLogin`, `Ownership.SessionRef`, `Shell` and the Web step behave exactly as today: no cookie, no counter row, no seeded key, no refusal.
- **The resume reference** is `##class(OcuTalon.Bridge.Ids).NewRef()` (16 random bytes, base64url, 22 characters):
  - it lives only in the cookie and in local variables of the request that sets it;
  - the row stores `Session.Hash(reference)`: SHA-256, base64url without padding, 43 characters;
  - no property, global, `%session.Data` entry, production message, log line, live event or audit entry ever holds it.
- **The cookie** is `OcuTalonResume`, set only on a creation, by `%response.SetCookie("OcuTalonResume", reference, <expiry>, "/ocutalon/", "", 1, 1, "Strict")`. `<expiry>` is `Public.Settings.NextReset()` as an RFC 1123 GMT date ("Sun, 25 Oct 2026 20:00:00 GMT"), and "" when there is no next reset. A resume sets no cookie.
- **Resume.** A cookie whose hash opens a row of the signed-in IRIS user attaches that row:
  - `%session.Data(Ownership.#SESSIONKEY)` holds the row's Ref, and the row's `CspSessionId` is set to `%session.SessionId`;
  - the attach happens whatever the previous `CspSessionId` was, so nothing compares `%session.SessionId` to recognise a new CSP session;
  - a resume never counts toward the limit and is never refused by it.
- **Fresh session.** A missing, malformed or unknown cookie, or a row of another IRIS user, gives a new row with a new `Ref`, `TraceRef`, `Epoch` and reference, and a new cookie.
- **Only `/ocutalon` attaches.** The trace applications keep `EventClass` "". A sign-in that the group carries attaches at its first `/ocutalon` request.
- **Client address** (`SessionEvents.ClientAddress`):
  - a request is proxied when `proxyAddress` is set and equals `REMOTE_ADDR` exactly;
  - a proxied request's address is the right-most `X-Forwarded-For` entry, trimmed, or `REMOTE_ADDR` when there is no entry;
  - a request that is not proxied is exempt: it is never counted or refused, and its `X-Forwarded-For` is ignored.
- **Limit.**
  - The limit is `Setting.Get(Setting.#ADDRESSLIMITKEY, Setting.#ADDRESSLIMITSEED)`, seeded to 5 by the Web step when the flag is on.
  - A proxied creation is refused when the address already has that many `AddressCounter` rows created in the past hour.
  - The count, the creation and the counter row happen under one lock per address hash, so two concurrent sign-ins never both take the last place.
  - The counter stores `Session.Hash(address)` and `CreatedAt` only.
- **Refusal.** `OnLogin` creates no row and sets no cookie. It writes `%session.Data(Shell.#REFUSALKEY) = $ListBuild("addressLimit", <until>)`, where `<until>` is the oldest counted `CreatedAt` + 1 hour (UTC ISO with "Z"). In the same request, `Shell.OnPreDispatch` (after its role check) ends the CSP session (`Logout(1)`, `EndSession` 1) and answers with the splash in state "addressLimit". The splash shows:
  - "Too many new sessions from your network this hour. You can start another at {time}." in `#ocu-error` under **Sign in and start**;
  - `{time}` as `<time class="tnum" id="ocu-error-time" datetime="<until>">`, empty in the markup and filled by the splash script with `page-time.ts`'s formatter options (a page time in the browser's zone);
  - no `aria-invalid` on any field, the published values prefilled, the button enabled, and the error focused (`autofocus`) as the other splash errors are.
- **Resolution** (`Ownership.SessionRef`, DW-16):
  - the Ref in `%session.Data` wins when its row exists and belongs to `$Username`;
  - otherwise, on the online demo, the result is "" with an error status, and nothing is attached or created;
  - no endpoint reads a `SessionRef` from the request.
- **Purge** (AD-27): `AddressCounter.Purge(daysToKeep)` deletes the counter rows older than one hour, whatever `daysToKeep` is, and `Install.Step.Web.Purge` calls it after `Live.Event.Purge`. The purge task (Story 30.2) calls `Web.Purge`; until then the tests call it directly.
- **No SQL.** `OnLogin` runs as the signed-in demo account, which holds no SQL privilege. It reaches rows through object access only: `ResumeHashIndexOpen`, `RefIndexOpen`, `%OpenId` and the class's own index walk in `AddressCounter`. No unchecked prepare and no embedded SQL is added: `test-class-rules.sh`'s allow-list stays three entries.
- **Test discipline (Stories 16.1 and 16.2):**
  - every browser context and curl jar ends with the group-wide `/ocutalon/?IRISLogout=end`;
  - every page request carries a unique `probe=<n>`;
  - each spec creates and removes what it reads;
  - `proxyAddress` is restored to its start value after the limit phase, also when a check of the phase fails.
- **Runtime targets** (Rule 21):
  - stacks only through `ci/iris.sh` and `ci/warm.sh`, with lane C's three variables;
  - `ocutalon-slot-c`, namespace `OCUTALON`, only for `iris_doc_load` compiles, after `iris_server_info` shows build 154 on port 52792.

**Never:**
- No edit to `Data/Pairing.cls` (Epic 10's), to Lane A's or Epic 4's files, or to any contended path. Shared files get only this story's own members and lines:
  - `Data/Setting.cls` and `Test/Data/Setting.cls`;
  - the Lane B entries of `Test/Data/Tables.cls`.
- No change to `Web/Api.cls`, `Core/**`, `web/src/app/**`, `web/playwright.config.ts`, `web/package.json`, `ci/units.sh` or `src/short-names.tsv`.
- No session resolved from `$Username` on the online demo, and no lazy `Attach()` there.
- No new public text beyond the AC's error sentence. A needed text that is not in the AC or the UX is a `## Clarification Needed` stop.
- No grant, role or application change. No password or reference is ever printed by a test.
- Out of scope:
  - the 120-second CSP timeout, the idle cap, the place-freed notice, Sign out ending the OcuTalon session and expiring the cookie, and the epoch-change return (16.4). Until 16.4, Sign out ends only the CSP session, so the next sign-in resumes;
  - the busy refusal and `X-OcuTalon-Busy` (16.5);
  - the probe (16.6);
  - the reset notices (16.8);
  - `/state`'s Telegram block (10.3) and the rail's Telegram card check (12.7).

## I/O & Edge-Case Matrix

Rows 1, 2, 5 and 7 run as browser cases in `web/e2e-online/resume.spec.ts`, and row 11 in `web/e2e-online/address-limit.spec.ts`, in the `online-demo` unit's fresh flag-on throwaway. Rows 4, 6, 10, 12 and 14 (its live half) run as curl and `iris_script` rows of the same unit. Rows 3, 8, 13, 14 and 15 run in process on a warm stack, and row 9 on the local stacks.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | First sign-in (AC 1) | Fresh context, no cookie; sign in from the splash | The POST's answer carries `Set-Cookie: OcuTalonResume=<22 chars of A-Za-z0-9-_>` with the expiry of `/ocutalon/public/status`'s `nextReset` as RFC 1123 GMT, `path=/ocutalon/`, Secure, HttpOnly and SameSite strict. The browser keeps it (`httpOnly`, `secure`, `sameSite: 'Strict'`, `expires` = `nextReset` in seconds). One new `Session` row is found by `/state`'s `epoch`: a new `Ref`, `TraceRef` and `Epoch`, `IrisUser` the demo account, `ResumeHash` = SHA-256 base64url of the cookie value (computed in node), `CspSessionId` set, and no property equal to the value. The main page shows `app-empty-chat` and no turn | -- |
| 2 | Resume (AC 2; Story 10.3 and Story 12.7 parts off) | Row 1's session gets a done turn (`Fixture.Turn`), a pending approval request (`Fixture.Approval`), a fixture pairing (`Fixture.Pairing`) and a `BreakFeedRun` row ("sent", its orders' run). Then the group sign-out (the CSP session ends and the cookie stays), then an arrival from another site: a page at `http://elsewhere.test/` (route-fulfilled) links to the splash. Then sign in | The splash GET carries no `OcuTalonResume` cookie, and the POST does. While `/state` is held (`holdState`), the rail and main show their skeletons. Once it is released: the same `epoch`, the turn's text in the chat, the approval request in the rail, no new `Session` row, and the row's `CspSessionId` is the new CSP session's. The pairing and the `BreakFeedRun` rows still name the row's `Ref`, and its `TraceRef` is unchanged. `notBuilt('R2b: /state returns the fixture pairing', '10.3')` and `notBuilt('R2c: the rail\'s Telegram card shows the fixture pairing', '12.7')` | -- |
| 3 | Resume in process (AC 2) | `OnLogin` with the flag on and a cookie of an existing row of `$Username`; again when the new `%session.SessionId` equals the row's `CspSessionId`; then a cookie of another user's row | The row is attached (`%session.Data`), its `CspSessionId` is set, no cookie is set and no counter row is written, also with an equal session id. Another user's row gives a fresh row and a cookie | -- |
| 4 | Trace applications don't attach (AC 2) | curl: the demo account signs in on the OCUTALON trace application's sign-in page; then the same jar's GET `/ocutalon/` | The trace answer sets no `OcuTalonResume`, and the `Session` row count is unchanged. The `/ocutalon/` answer sets it, and the count is up by one | -- |
| 5 | Unknown cookie (AC 3) | Context holding `OcuTalonResume=<a random valid reference>`; sign in | A new `epoch`, a new cookie with a different value, and the old value's hash opens no row | -- |
| 6 | Reference never recorded (AC 3) | curl: sign in, keep the cookie value R, POST `/api/v1/messages` and wait for the turn's `chat.message` done event, group sign-out, sign in again with `-b OcuTalonResume=R` (the same `epoch`), sign out | R is in no line of the container's output, `messages.log` or the after-start log, in no `Ens_Util.Log` row, no `OcuTalon_Live.Event` payload, no `%SYS.Audit` entry, and no node of any global in the databases OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_PUBLIC (production messages included). Only counts are printed | -- |
| 7 | Two browsers (AC 4, DW-16; integration: `Web.Api` reads `Ownership.SessionRef`) | Contexts A and B sign in. A posts a message. Then A posts with `"sessionRef": <B's Ref>` in the body and `?sessionRef=<B's Ref>` | Two `epoch`s and two cookie values. A's chat and A's `/events` show the turn, and B's chat and B's `/events` after its cursor show none of A's events. The second turn is A's too | -- |
| 8 | Never by user name (AC 4) | In process, flag on: `SessionRef` with no Ref attached; with the Ref of a row of `$Username`; with the Ref of another user's row. Flag off: the same calls | Flag on: "" and an error with no row created for `$Username` (`Fixture.SessionCount` unchanged); the user's Ref returned; "" and an error. Flag off: Story 2.2's lazy attach, unchanged | -- |
| 9 | Local install unchanged (AC 4) | `live sign-in` (flag off); in process with the flag off: `OnLogin`, `Web.SeedSettings` | The local suite stays green unchanged (one durable session per user). No cookie, no counter row, no setting row | -- |
| 10 | Limit (AC 5) | Phase 2: `proxyAddress` set to the host's connection address (Task 0 (c)). Five curl sign-ins with `X-Forwarded-For: A`, then a sixth. Then a sign-in with `X-Forwarded-For: A` and A's first cookie (`-b OcuTalonResume=<value>`); then one with `X-Forwarded-For: A, C` | The first five give the shell and a cookie each. The sixth gives 200 and the splash whose `#ocu-error` (after the button) reads the AC's sentence with `<time datetime=<oldest + 1 h>>`. That answer has no `aria-invalid`, no `disabled` and no `OcuTalonResume` cookie, the refused jar's `/api/v1/state` gives 401, and no row is created. The cookie sign-in from A resumes (the first session's `epoch`). `A, C` counts C and is allowed. A has exactly five counter rows | Phase 2 first checks that one proxied sign-in wrote a counter row for its address, and fails naming the derived address otherwise |
| 11 | Limit on the page (AC 5; integration: `Shell` reads the refusal that `OnLogin` writes) | Phase 2, address L of its own: five API sign-ins with `X-Forwarded-For: L`, then the splash in a context with that header, `timezoneId` Asia/Kolkata, `locale` en-US; press **Sign in and start** | `#ocu-error` reads "Too many new sessions from your network this hour. You can start another at {pageTime(oldest + 1 h)}.", where `pageTime` comes from `page-time.ts` and the oldest from L's counter rows. It is the button's next element sibling and `document.activeElement`. Neither input has `aria-invalid`, the button is enabled, and there is no `app-root`. L's counter rows are removed after | -- |
| 12 | Exempt (AC 5) | Phase 1 (`proxyAddress` 192.0.2.10): six curl sign-ins with `X-Forwarded-For: A0`. In process, `ClientAddress` cases | All six give the shell, and there is no counter row for A0. From the proxy: "a, b" gives b, " b " gives b, no header gives `REMOTE_ADDR`; not from the proxy, or with no proxy set: exempt | -- |
| 13 | Window and purge (AC 5) | In process: counter rows 59 and 61 minutes old for one address; `Web.Purge(90)` and `Web.Purge(0)` | `Recent` counts 1 and returns the 59-minute row's time as the oldest. Each purge deletes the 61-minute row, keeps the 59-minute one and still purges the live events | -- |
| 14 | Seeded limit (AC 5) | In process: `Web.SeedSettings` with the flag on (absent key; an existing "7"), then off. Live: after the flag-on start | On: the key is written as "5" when absent, and "7" is kept. Off: no row. Live: `Setting.Get(key)` is 5 and its row exists | -- |
| 15 | Refusal markup (AC 5) | In process: `Login.Show("addressLimit", 0, "2026-10-25T15:20:00Z")` with the flag on | The AC's sentence with the `<time>` element (datetime escaped) in `#ocu-error` after the button, no `aria-invalid`, no `disabled`, the published values, `autofocus` on the error, and the splash's exact policy. `TOOMANY` equals `splash.tooManySessions` | -- |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`:
  - comment :1-6; `OnLogin` :11-14 calls `AttachFor(Shell.HasRole())`; `AttachFor` :18-29 (always OK, a failure logged); `Log` :32-38.
  - The online-demo branch goes in `AttachFor`, so the no-role and failure behaviour stay one path.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `SESSIONKEY` :31; `SessionRef` :116-135 (its comment at :118-119 says Story 16.3 extends it here); `Attach` :137-145; `Pairing` :245-251; `LocalFlag` :386-391 (the flag through `Setting.Get`);
  - `Rows` :401 is the one unchecked prepare. Don't use it for the new reads.
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`:
  - properties :11-32; indexes :34-38;
  - `ForUser` :40-83, whose row initialisation at :68-73 becomes the shared private `NewRow`;
  - storage :107-141: append `<Value name="9">ResumeHash` and `<Value name="10">CspSessionId`, existing slots unchanged.
  - `Turn.ClientId` (`Data/Turn.cls:36`, `COLLATION = "EXACT"`) is the precedent for an exact, mixed-case key.
- `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls`:
  - exists since Story 0.4 with `AddressHash` (:9), `CreatedAt` (:12), `AddressHashIndex` (:14) and `DEFAULTGLOBAL` `^OcuTalonP.AddrCount` (registered in `src/short-names.tsv:9`). No schema change;
  - its comment cites AD-1 by mistake: it is AD-13. Nothing writes it today.
- `src/bridge/cls/OcuTalon/Bridge/Ids.cls:7-10` -- `NewRef()`: the reference's generator.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls`:
  - `CACHESECONDS` :9; `Get` :26-40 (60 s cache; public keys delegated); `Seed` :44-55.
  - `Install/Step/Demo.cls:132` is the seed precedent (read only).
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- read only: `KEYS` :9 (`proxyAddress`), `Get` :19-27, `Set` :31-40, `NextReset` :60-75.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`:
  - `Run` :51-68; `Purge` :88-92 (today `Live.Event.Purge` only);
  - `SESSIONEVENTS` :44; `Common` :162-178 sets `EventClass` "" for the other applications.
- `src/ocutalon/cls/OcuTalon/Live/Event.cls:51-61` -- `Purge`: the checked `DELETE ... WHERE Ts < ?` that `AddressCounter.Purge` copies (a different table and window).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`:
  - `OnPreDispatch` :54-62 is the no-role precedent: `Logout(1)`, `EndSession`, `Error:FullURL`, `Login.Show(state, 0)`;
  - `Redirect` :77-82 answers the sign-in POST with a 303; `HasRole` :113-116.
  - It may reference only `%CSP` and the two public packages (AD-3), so `REFUSALKEY` lives here and `SessionEvents` reads `##class(OcuTalon.Web.Public.Shell).#REFUSALKEY`.
- `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls`:
  - `UseSplash` :89; `Show` :99-109 (`%OcuTalonState` :102, and the hand-over line to `Splash.Show`); `Message` :115.
  - The local page's output must stay byte-identical (`Test.Web.Splash.TestShowFollowsTheFlag`).
- `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - texts :15-63; `OnLoginPage` :89-160 (`message`/`marked` :93-94, the error paragraph :135-137);
  - `ResetLine` :176-189 is the `<time>` precedent.
- `web/src/signin/splash.js:133-167` -- `startCountdown`'s formatter `{hour: 'numeric', minute: '2-digit'}`, which the error's time reuses. `npm --prefix web run tokens` regenerates `Web/Public/SplashAssets.cls`, and the inherited generators re-hash the policy.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` (the `splash.*` entries of Story 16.2) and `Test/Msg/Catalog.cls` (counts, `Keys`, `Fixtures`); `Test/Web/PublicTexts.cls` (`Classified`, counts).
- Tests to extend:
  - `Test/Web/SessionEvents.cls` -- `TestAttachForAlwaysAnswersOK` :23-45 builds `%session` with `%CSP.Session.%New(id, 0)`. `Test/Web/StubRequest.cls` makes requests: `%request.Cookies(name, 1)`, `CgiEnvs`. `%response.Cookies(n, "n"|"v"|"e"|"p"|"s"|"h"|"ss")` holds what `SetCookie` stored (`irislib/%CSP/Response.cls:436-456`).
  - `Test/Data/Ownership.cls` -- saves and clears `onlineDemo` in `OnBeforeAllTests` (:24-25); `TestSessionRefFromTheCspSession` :62.
  - `Test/Data/Session.cls` -- `TestFindsOrCreates` :35.
  - `Test/Web/Install.cls` -- `TestPurgeDeclaration` :75-95 (throwaway only).
  - `Test/Web/Splash.cls` -- `TestNoRole` :215 and the settings fixture at :327.
  - `Test/Data/Setting.cls` -- fixture key `zz.<n>` :23-37.
  - `Test/Data/Tables.cls` -- the `Session` entry :272-287 and the `AddressCounter` entry :302-311.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Turn` :32, `Approval` :102, `Pairing` :191, `Adopt` :232, `SessionCount` :279, `Clean` :292. Don't add a `BreakFeedRun` helper: Epic 4's Story 4.2 is likely to add one. The spec writes and deletes that row in its own script.
- `web/e2e-online/support.ts` -- `signOutGroup` :19-28, `signInFromSplash` :40-47.
- `web/e2e/support/iris.ts` -- `irisScript` :59, `chk` :77, `quoted` :132; its seeders resolve a session by user name (`ForUser`), so the online specs find a visitor's row by `/state`'s `epoch` instead.
- `web/e2e/support/api.ts` -- `STATE`/`EVENTS`/`MESSAGES` :14-16, `post` :37, `sessionEvents` :45, `holdState` :114.
- `web/e2e/support/trace.ts:48` -- `postTurn`.
- `web/e2e/sign-in/helpers.ts:66-69` -- `signInOverHttp` (read only).
- `web/e2e/live/live.spec.ts:207-230` -- L5, the skeleton assertions to mirror.
- `web/e2e/demo-path/not-built.ts:11-15` -- `notBuilt`. `web/src/app/chat/page-time.ts` -- `pageTime`, the oracle.
- `docker/tests/test-online-demo.sh`:
  - header :2-40; the start values :78-99 (`OCUTALON_PROXY_ADDRESS` 192.0.2.10 at :93);
  - `logout_all` :244-249; `signin_outcome` :256-282; `page_token` :285-287 (the trace sign-in posts with it);
  - row 11 :443-563; the browser step :565-593 (`npm --prefix web run e2e:online-demo`);
  - `check_password_not_logged` :599-612 and `check_logs_clean` :616-632, which the reference search extends; the restart :635-663.
  - `docker/tests/lib-live.sh` -- `dc` :243, `iris_script` :307, `check_session` :479.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (implement, on lane C's throwaway; record each result under Verification): measure (a) to (d) below. Use the unit's first run, with `MEASURED` lines where the unit can print them. Any temporary diagnostic line must be reverted byte-identical and never committed.
  - (a) The Set-Cookie that `%response.SetCookie` writes in `OnLogin` is in the sign-in POST's 303 answer and in a group-carried first `/ocutalon/` GET. Print its attributes with the value replaced as `MEASURED resume Set-Cookie attributes:`.
    - If it is missing, the call moves to `Shell.OnPreDispatch` in the same request: the reference is handed over in a process-private `%`-variable that is killed at once. Record this under Design Notes and keep every other Always line.
  - (b) Chromium keeps a Secure cookie set over `http://127.0.0.1:<port>` (row 1's assertion).
    - If it doesn't, the unit passes `OCUTALON_URL=http://localhost:<port>` to the browser steps.
    - If neither host keeps it, stop with `## Clarification Needed`.
  - (c) The exact `REMOTE_ADDR` that IRIS sees for the host's requests on the developer machine, and how the unit derives it. Candidates: the iris container's default gateway (`/proc/net/route`), the project network's gateway (`docker network inspect`), or else a temporary echo application created on the throwaway at run time and never in `src/`. Phase 2's precondition guards it on CI.
  - (d) Whether build 154 reuses `%session.SessionId` after `?IRISLogout=end` and a new sign-in in the same jar. Print `MEASURED CSP session id reused on resume: yes|no`.
- [x] `src/ocutalon/cls/OcuTalon/Data/Session.cls`:
  - `Property ResumeHash As %String(COLLATION = "EXACT", MAXLEN = 43)` with `Index ResumeHashIndex On ResumeHash [ Unique ]`, and `Property CspSessionId As %String(MAXLEN = 64)`, both appended to the storage;
  - `Hash(text)`: SHA-256 of the UTF-8 text, base64url, no padding;
  - a private `NewRow(irisUser)` holding `ForUser`'s row initialisation, with `ForUser` otherwise unchanged;
  - `NewVisitor(irisUser, cspSessionId, Output reference, Output sc)`: `NewRow` plus a new reference, its hash and the CSP session id, saved;
  - `ForResume(reference)`: "" unless the reference is 22 characters of `A-Za-z0-9-_`, else `ResumeHashIndexOpen(..Hash(reference))`;
  - the class comment names both properties and why -- rows 1, 3, 5.
- [x] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `Resume(reference, Output sc) As %String`: `Session.ForResume`; only a row of `$Username`; records the CSP session on the row and its Ref in `%session.Data`; returns the Ref or "";
  - `StartVisitor(Output reference, Output sc) As %String`: `Session.NewVisitor($Username, %session.SessionId, ...)`, recorded the same way;
  - `SessionRef`: after the existing check, `If ..LocalFlag() = 0` answers "" with an error (no `Attach`);
  - the class comment states the online-demo resolution (DW-16) -- rows 1, 2, 3, 7, 8.
- [x] `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls`:
  - `Recent(address, Output oldest) As %Integer`: the rows of `Session.Hash(address)` created in the past hour, by walking the class's own `AddressHashIndex` with `$SYSTEM.Util.Collation(hash, 7)` and comparing the opened row's `AddressHash` exactly; no SQL;
  - `Add(address) As %Status`;
  - `Lock(address) As %Boolean` (5 s) and `Unlock(address)`, on `^OcuTalon.Data.AddressCounter(<hash>)`;
  - `Purge(daysToKeep) As %Status`: a checked `DELETE ... WHERE CreatedAt < <now - 3600 s>`;
  - the comment cites AD-13 and AD-27 -- rows 10 to 13.
- [x] `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- `Parameter ADDRESSLIMITKEY = "onlineDemo.sessionsPerAddress";` and `Parameter ADDRESSLIMITSEED = 5;`, each with a doc line ("new sessions per client address per hour, online demo"). No existing line changes -- row 14.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`:
  - `SeedSettings()`: with the flag on, `Setting.Seed(Setting.#ADDRESSLIMITKEY, Setting.#ADDRESSLIMITSEED)`;
  - `Run` calls it before the applications;
  - `Purge` returns the first error of `Live.Event.Purge` and then `AddressCounter.Purge`;
  - the class comment and `Purge`'s comment name the counter -- rows 13, 14.
- [x] `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`:
  - `Parameter RESUMECOOKIE = "OcuTalonResume"`;
  - `AttachFor` keeps its no-role and always-OK contract, and with the flag on calls `AttachVisitor()`: the cookie (`Ownership.Resume`); else `ClientAddress`; when proxied, `AddressCounter.Lock`, `Recent`, then either the refusal marker or `Ownership.StartVisitor` plus `Add`, then `Unlock`; when exempt, `StartVisitor` alone; then `SetCookie` per Always;
  - `ClientAddress(remote, forwarded, proxy, Output proxied)` and `CookieExpiry(nextReset)` are public class methods, so they can be tested;
  - log lines carry error codes only;
  - the class comment states the branch -- rows 1, 3, 10, 12.
- [x] `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`:
  - `Parameter REFUSALKEY = "OcuTalon.Refused"`;
  - `OnPreDispatch`: with the role and a marker, it ends the session and returns `Login.Show($List(marker, 1), 0, $ListGet(marker, 2))` as the no-role path does;
  - the class comment names it -- rows 10, 11.
- [x] `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls` -- `Show(state, writeHeader, until As %String = "")` sets `%OcuTalonUntil` beside `%OcuTalonState` and passes `until` in its hand-over line. No other line changes; the local output is unchanged -- rows 9, 15.
- [x] `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - `Parameter TOOMANY = "Too many new sessions from your network this hour. You can start another at {time}."`;
  - `OnLoginPage` reads and kills `%OcuTalonUntil`. State "addressLimit" gives that message with `{time}` replaced by the escaped `<time>` element, and `marked` stays 0;
  - the class comment names the state -- rows 11, 15.
- [x] `web/src/signin/splash.js`, then `npm --prefix web run tokens` (which regenerates `Web/Public/SplashAssets.cls`; never edit that file by hand) -- `#ocu-error-time` gets the formatted time of its `datetime` once, with `startCountdown`'s formatter options. ASCII, no `//` -- row 11.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` and `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` (footprint extensions) -- add `splash.tooManySessions` with the slot `time` (`text`) and a `source` naming EXPERIENCE › State Patterns › Too many sessions; update the counts, `Keys` and a `Fixtures` entry ("15:20") -- row 15.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` -- classify `TOOMANY` under `compared` (a key with slots, compared with `Entry(key).text`); the counts move by exactly one -- row 15.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls` -- `TestTexts` gains `TOOMANY`; new `TestTooManySessions` covers row 15 -- row 15.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls` -- saves and restores `onlineDemo`, `proxyAddress`, `resetAnchor` and `resetIntervalHours` through `Public.Settings`, and removes its rows and counter rows (also after a failure). New tests:
  - `TestFirstSignIn`: row 1's row and cookie fields, and the expiry string for a fixed anchor;
  - `TestResume`: row 3;
  - `TestUnknownCookie`: an unknown, a malformed and a deleted row's reference each give a fresh row and cookie;
  - `TestLimit`: five proxied creations, the sixth refused with the marker's `until`, a resume at the limit, no row on refusal;
  - `TestExempt`;
  - `TestClientAddress`: row 12;
  - `TestFlagOff`: row 9 -- rows 1, 3, 5, 9, 10, 12.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- `TestSessionRefOnTheOnlineDemo` (row 8) and `TestResumeAndStartVisitor`. The class keeps clearing the flag for its other tests -- rows 3, 8.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Session.cls` -- `TestNewVisitorAndForResume`: the hash shape, no property equal to the reference, `ForResume` of a malformed value -- rows 1, 5.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/AddressCounter.cls` (new; the `Data` area is in shard `lane-b`) -- `TestRecentWindow` and `TestAddStoresOnlyTheHash` -- rows 12, 13.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls` -- `TestPurgeAddressCounter`: row 13 through `Web.Purge` (throwaway only, like `TestPurgeDeclaration`) -- row 13.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls` -- `TestAddressLimitSetting`: the two parameters, and row 14 with the flag and the key's row saved and restored. No existing method changes -- row 14.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- the `Session` entry gains both properties and `ResumeHashIndex` (in the contract's own syntax); the Lane A entries are untouched.
- [x] `web/e2e-online/support.ts` -- add:
  - `RESUME_COOKIE`;
  - `resumeCookie(context)`;
  - `sha256url(text)` (node `crypto`);
  - `sessionRow(epoch)` (`irisScript`: the row's Ref, TraceRef, ResumeHash and CspSessionId by `Epoch`);
  - `signInOverHttpFrom(playwright, address)` (an API context with `X-Forwarded-For`) -- rows 1, 2, 5, 7, 11.
- [x] `web/e2e-online/resume.spec.ts` (new) -- rows 1, 2, 5 and 7 as R1, R2, R4 and R5, plus the two `notBuilt` declarations of row 2. Each case removes its fixture rows (`Fixture.Clean` by Refs, the `BreakFeedRun` row by id) and signs out in `finally` -- rows 1, 2, 5, 7.
- [x] `web/e2e-online/address-limit.spec.ts` (new) -- row 11 as L1. It is skipped with the reason "runs in the unit's proxied phase" unless `OCUTALON_ONLINE_PROXIED=1`, and its address comes from `OCUTALON_ONLINE_LIMIT_ADDRESS` -- row 11.
- [x] `docker/tests/test-online-demo.sh` -- the header names the new checks. Changes:
  - after row 11, self-contained blocks for rows 4, 6, 12 and 14 (live);
  - the reference search reuses `check_logs_clean`'s searches and adds the global scan;
  - Task 0's `MEASURED` lines;
  - after the browser step, phase 2: set `proxyAddress`, the precondition, row 10, then `OCUTALON_ONLINE_PROXIED=1 OCUTALON_ONLINE_LIMIT_ADDRESS=<L> npm --prefix web run e2e:online-demo -- address-limit.spec.ts`, then restore `proxyAddress` (checked) on every path -- rows 4, 6, 10, 12, 14.

**Acceptance Criteria:**
- Given the online demo and a browser without a resume cookie, when the visitor signs in from the splash, then `OnLogin` creates a `Session` row with a new `SessionRef`, `TraceRef` and epoch, records the new CSP session on it, and sets `OcuTalonResume` (HttpOnly, Secure, `SameSite=Strict`, path `/ocutalon/`, expiring at the next reset) to a 22-character base64url reference whose SHA-256 alone the row stores; the main page opens on an empty chat. Rows 1 and 3 hold.
- Given a session with a conversation, a fixture pairing, orders and a pending approval request, when the same browser signs in again after its CSP session ended (also when it arrives from another site), then `OnLogin` attaches the new CSP session to that row instead of creating one, and the page loads that conversation and approval request after skeletons; the trace applications don't attach; the `/state` and Telegram-card checks wait for Stories 10.3 and 12.7. Rows 2, 3 and 4 hold.
- Given a cookie whose row doesn't exist, or none, when the visitor signs in, then a fresh session and a new cookie are made, and the reference appears in no production message, log, live event or audit entry. Rows 5 and 6 hold.
- Given two browsers on the demo account, when each reads, polls and sends, then each gets its own session through `Ownership.SessionRef`, never from the user name, no endpoint takes a `SessionRef` from the client, and a local install keeps one durable session per IRIS user. Rows 7, 8 and 9 hold.
- Given 5 sessions created from one proxied address in the past hour (the seeded setting), when it signs in once more without a resumable cookie, then the post-sign-in check ends the CSP session, creates no session and the splash shows the field error with the time under **Sign in and start**, which stays enabled and marks no field; a resume still works; the right-most `X-Forwarded-For` entry is the address only behind the proxy, other sign-ins are exempt, the counter stores hashes with timestamps, and its `Purge(daysToKeep)` keeps one hour. Rows 10 to 15 hold.

### Review Findings

Code review, 2026-10-25 (four layers, full-opus tier; 46 rows: 18 entries patched, 7 deferred to the ledger, 16 rejected; no decision-needed). Fields: severity | fix-risk | footprint | spec-status | disposition.

- [x] [Review][Patch] Contract comments that the online-demo branch made untrue: the SessionEvents class comment still promised a lazy attach on the first API call, OnLogin and AttachFor named only the durable session, and the Splash class comment did not name the "addressLimit" state [src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls:1] -- low | low | in-story | clear | patched (also `Web/Public/Splash.cls:8`).
- [x] [Review][Patch] `Test.Web.SessionEvents`' header listed 7 of the story's 11 tests [src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls:6] -- low | low | in-story | clear | patched (it now names all 12, with TestNoRoleOnTheOnlineDemo).
- [x] [Review][Patch] `TestRecentWindow` claimed edges it did not test: 3599 seconds, and a case-variant hash. Its CASE rows were unrelated hashes, so `Recent`'s exact comparison was never reached [src/ocutalon/cls/OcuTalon/Test/Data/AddressCounter.cls:31] -- low | low | in-story | clear | patched: the comment is corrected, rows of the hash in lower and upper case are added, `Clean` removes them, and a mutation is recorded.
- [x] [Review][Patch] No test covered a no-role sign-in on the online demo: every flag-on test passed `AttachFor(1)` [src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls] -- low | low | in-story | clear | patched: `TestNoRoleOnTheOnlineDemo` (behind the proxy, with a visitor's cookie: nothing attached, created, set, counted or recorded, no console line), `SignIn` gains `hasRole`, and a mutation is recorded.
- [x] [Review][Patch] "and again after Unlock" could not fail, because a process can always retake its own lock [src/ocutalon/cls/OcuTalon/Test/Data/AddressCounter.cls:86] -- low | low | in-story | clear | patched: another job takes the lock after Unlock (`FreeInAnotherJob`), and a mutation was observed.
- [x] [Review][Patch] "nor does the unknown value" repeated the deleted-row check, because `cookie` held the loop's last case [src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls:196] -- low | low | in-story | clear | patched: it checks the random unknown reference.
- [x] [Review][Patch] The foreign-row fixture saves were unchecked, so the "another user's row" cases could pass on a failed save [src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls:160] -- low | low | in-story | clear | patched: the save is asserted and the reference shown to open the row (also `Test/Data/Ownership.cls:175`).
- [x] [Review][Patch] `TestSessionRefOnTheOnlineDemo`, the in-process pin for "no lazy Attach" (Decided in-stage), had no mutation line [src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls:107] -- low | low | in-story | clear | closed: a mutation is recorded under Verification.
- [x] [Review][Patch] A `Test.Data.Ownership` test that turned the flag on and then stopped on an error left it on for the class's later tests [src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls:20] -- low | low | in-story | clear | patched: `OnBeforeOneTest` clears the flag.
- [x] [Review][Patch] `CounterRow`'s save was unchecked, so "the 61-minute row is deleted" could pass with no row [src/ocutalon/cls/OcuTalon/Test/Web/Install.cls:128] -- low | low | in-story | clear | patched: `CounterRow` answers "" on a failed save, and both rows are asserted.
- [x] [Review][Patch] L1's five API sign-ins and R5's trace page carried no `probe=<n>`, against the Test-discipline Always line [web/e2e-online/support.ts:149] -- low | low | in-story | clear | patched: `signInOverHttpFrom` uses a probed splash path, and R5 calls `probed()` (`resume.spec.ts:254`).
- [x] [Review][Patch] Several R1, R2, R4 and R5 assertions would print a resume reference on failure, against the Never line "no reference is ever printed" [web/e2e-online/resume.spec.ts:57] -- low | low | in-story | clear | patched: cookie values are compared as booleans.
- [x] [Review][Patch] R2's "no new row" check could not fail, because `sessionRow(epoch)` always finds the first row [web/e2e-online/resume.spec.ts:159] -- low | low | in-story | clear | patched: the number of Session rows is compared before and after the resume.
- [x] [Review][Patch] R2's header promised "the new CSP session on the row", which nothing asserts (build 154 reuses the id) [web/e2e-online/resume.spec.ts:20] -- low | low | in-story | clear | patched: the header names `TestResume` as that pin.
- [x] [Review][Patch] Row 6's failure branch left its curl jar signed in [docker/tests/test-online-demo.sh:747] -- low | low | in-story | clear | patched: the branch calls `logout_all`.
- [x] [Review][Patch] The proxy's start value was written as a literal in four places, so the restore could put back a stale value [docker/tests/test-online-demo.sh:101] -- low | low | in-story | clear | patched: `proxy_start` is defined once and used by the override, row 2, the restore and the scan-public control.
- [x] [Review][Patch] Rule 2: `online_signin` repeated `signin_outcome`'s three sign-in requests (the splash GET, the POST and the redirect GET) with no stated reason [docker/tests/test-online-demo.sh:276] -- med | med | in-story | clear | patched: `online_signin` takes the account and moves above `signin_outcome`, which now delegates to it. The live unit is green, with Story 16.1's form rows unchanged.
- [x] [Review][Patch] Rule 2: `fillErrorTime` repeated `startCountdown`'s formatter options [web/src/signin/splash.js:183] -- low | low | in-story | clear | patched: both use one `timeFormat()`, and `SplashAssets.cls` was regenerated by `npm --prefix web run tokens`.
- [x] [Review][Defer] The address counter stores an unsalted SHA-256, so an IPv4 address can be recovered from a row within its hour [src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls:50] -- deferred: DW-233. med | med | in-story | clear | decision-pending (a veto-window item: stored data and security posture). Recommended: a keyed hash (HMAC with a per-instance key in the private database, renewed at each reset).
- [x] [Review][Defer] A proxy address that is unset, or that does not equal REMOTE_ADDR exactly, exempts every sign-in, and nothing reports it [src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls:89] -- deferred: DW-234. med | low | out-of-footprint (the demo host) | clear | routed to 29-3 (a launch check that a proxied sign-in writes a counter row; pin the proxy's address).
- [x] [Review][Defer] Rule 2: `AddressCounter.Shift` and `SessionEvents.CookieExpiry` repeat `Public.Settings`' private ToSeconds/FromSeconds parsing [src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls:82] -- deferred: DW-235. med | low | in-epic | forced (Public.Settings is read-only here, Data.Time is contended) | routed to 16-8.
- [x] [Review][Defer] Rule 2: `ref_script` and `check_ref_session` copy lib-live.sh's `iris_script` and `check_session` only to pass an environment variable [docker/tests/test-online-demo.sh:1000] -- deferred: DW-236. med | low | out-of-footprint (a contended file) | forced | escalated.
- [x] [Review][Defer] Rule 2: Story 10.3's `Pairing.HashCode` must delegate to `Session.Hash` [src/ocutalon/cls/OcuTalon/Data/Session.cls:108] -- deferred: DW-237. med | low | out-of-footprint (Epic 10) | forced by order | routed to 10-3.
- [x] [Review][Defer] `Session.ForUser` can return a visitor row as the durable session if the flag is turned off on an instance that keeps visitor rows [src/ocutalon/cls/OcuTalon/Data/Session.cls:73] -- deferred: DW-238. low | low | in-story | spec-bound ("ForUser otherwise unchanged") | wontfix-theoretical.
- [x] [Review][Defer] Rule 2: `Test.Web.Install.CounterRow` repeats `Test.Data.AddressCounter.Row` [src/ocutalon/cls/OcuTalon/Test/Web/Install.cls:128] -- deferred: DW-239. low | low | in-story | clear | wontfix-accepted (sharing it would tie a Web-area test class to a Data-area one).

Rejected:
- `low` (blind, edge) A failed visitor attach leaves the visitor with API errors and no marker. The lead's ruling accepts this interim until Story 16.4.
- `low` (blind, edge x2) A limit of 0, a negative limit or a non-numeric one refuses every creation, and the time reads empty. Only an operator's edit can cause it (the key is seeded and is not on the settings page), and the fix adds a guard.
- `low` (blind, edge) After the limit is lowered within the hour, the promised time is too early. The product never lowers the limit, and the fix needs the n-th oldest row.
- `low` (blind, edge) `Add` can fail after `StartVisitor`. That needs a database fault, and the fix adds branches.
- `false` (edge) OnLogin running twice in one CSP session would replace its Ref. OnLogin runs once per new CSP session's sign-in, and a silent sign-in again opens a new CSP session with empty data.
- `low` (edge) Resume's full-row save could overwrite `Core.Trace`'s thread fields. The window from open to save is microseconds and the effect is a split trace thread for one day, while the fix adds a lock.
- `false` (edge) A Secure cookie is dropped over plain HTTP. AD-4 sets Secure always, and the demo is HTTPS at the proxy.
- `false` (edge) The `/ocutalon/` cookie path misses `/ocutalon`. AD-4 fixes the path, the splash posts under the slash path, and R2 passes.
- `low` (edge) An IPv6 client can rotate addresses within its /64. FR-15 and AD-13 count per address, and two IPv4 addresses already exceed the demo's capacity.
- `false` (acceptance) Rule 6 high: AD-13 counts non-proxied sign-ins by the connection's address. The Story 16.3 AC in epics.md reads "sign-ins that don't come through the proxy, such as the probe's, are exempt (AD-13)", and AD-25 lets only the probe and an operator connect directly. The misconfiguration consequence is DW-234.
- `false` (gap) Row 5 (QA), the controls and the row 6 searches depend on row 6's state. It is one sequential script that no runner reorders, and each dependent check fails loudly without that state.
- `low` (gap) The purge tests delete every counter row older than an hour. Nothing depends on aged rows, and the product purges them anyway.

## Spec Change Log

## Review Triage Log

### 2026-10-25 -- Review pass
- verdicts: 33 findings -- high 0, medium 4, low 21, false 8, maybe-false 0 (the medium rows group into three patched entries: the lock and its concurrency test, the limit test, and R2's assertion)
- findings:
  - `[low]` `reject` (blind) address limit 0, negative or non-numeric refuses every sign-in and the time reads empty -- an operator typo only; the key is seeded and not edited by the product; the fix adds a guard and a fallback.
  - `[low]` `reject` (blind) the counted address is an unsalted SHA-256 -- AD-13 and the spec prescribe "a hashed address with timestamps"; rows live one hour; the fix amends the spec.
  - `[low]` `reject` (blind) lock timeout or `Add` failure leaves a visitor half attached -- the lock-timeout behaviour (500 until Story 16.4) is the lead's accepted interim; an `Add` failure needs a database fault; the fix adds cleanup branches.
  - `[false]` `reject` (blind) the refusal sentence has no text before the script runs -- the spec fixes it: the `<time>` is empty in the markup and the script fills it, as the reset line's time is.
  - `[low]` `reject` (blind) `Recent` hardcodes the index global and collation -- the spec says to walk the class's own index with collation 7; `TestRecentWindow` fails if the layout moves.
  - `[false]` `reject` (blind) the cookie path `/ocutalon/` misses `/ocutalon` -- AD-4 fixes the exact `SetCookie` call; the splash form posts under the slash-terminated application path (`Splash.OnLoginPage` builds its base with the slash).
  - `[low]` `reject` (blind) the test script restores `proxyAddress` to a literal and has no trap -- the literal is the script's own start value, and the stack is a throwaway that the unit tears down.
  - `[low]` `reject` (blind) `%OcuTalonUntil` is left set on the local page -- it holds "" there (`until` is only given on the online demo) and the spec says to set it beside `%OcuTalonState`.
  - `[medium]` `patch` (blind) no test of the concurrency the lock exists for -- patched with `Test.Data.AddressCounter.TestLockExcludesAnotherJob` (a second job probes the lock) and lock-release assertions in `TestLimit`; the same root cause as the verification-gap lock finding. A two-process race stays unproven (a deterministic one needs a harness); the lock's exclusion and release are pinned.
  - `[low]` `reject` (edge) limit 0 or non-numeric gives an empty time -- the same claim as the blind row above.
  - `[low]` `reject` (edge) a lowered limit shows a time that is too early -- the product never lowers the limit; the fix needs the n-th oldest row.
  - `[low]` `reject` (edge) `Add` failure after `StartVisitor` leaves an uncounted attached row -- as the blind row above.
  - `[low]` `reject` (edge) lock timeout or `Resume` failure records no marker -- the lead's spec gate accepts the interim (the API answers 500; Story 16.4 owns the return to the splash).
  - `[false]` `reject` (edge) the `addressLimit` state on the local page -- the marker is written only on the online demo, where `UseSplash` is 1; the local page cannot receive it.
  - `[low]` `reject` (edge) an empty `X-Forwarded-For` counts under the proxy's address; IPv6 forms -- both are in the spec's Decided in-stage (an empty entry cannot occur behind the proxy, which overwrites the header).
  - `[false]` `reject` (edge) `SameSite=Strict` and the cookie path miss a sign-in at `/ocutalon` -- as the blind cookie-path row; R2 pins a cross-site arrival.
  - `[low]` `reject` (edge) two CSP sessions can resume one row -- the spec says a resume attaches whatever the previous `CspSessionId` was.
  - `[false]` `reject` (edge) `Shift` of an empty time makes `Recent` and `Purge` miscount -- `NowUtc()` always returns a valid time; the claim needs a failing clock.
  - `[false]` `reject` (edge) the marker may not be a list -- only `OnLogin` writes it, as a `$ListBuild`.
  - `[false]` `reject` (edge) `SameSite=Strict` with a cross-site POST (low confidence) -- the cookie is read on the sign-in POST, which the splash form sends from the same site; R2 passes.
  - `[medium]` `patch` (gap) the limit is never varied by any test -- patched: `TestLimitIsTheSetting` (limits 2 and 7); mutation line recorded.
  - `[medium]` `patch` (gap) `Lock` and `Unlock` cannot fail in any test -- patched: `TestLockExcludesAnotherJob` and lock-release assertions in `TestLimit`; mutation lines recorded.
  - `[low]` `patch` (gap) row 11 passes on exit 0 and a skipped L1 also exits 0 -- patched: the unit requires "1 passed" and no "skipped" in the log.
  - `[low]` `patch` (gap) several pinning tests have no mutation line -- patched: the cross-user `Resume` guard, `ClientAddress` equality, `SeedSettings` with the flag on and off, and the splash's `datetime` escaping each have a recorded mutation.
  - `[medium]` `patch` (gap) R2's `cspSessionId` not empty cannot fail -- patched: the assertion is removed (build 154 reuses the id, so a browser case cannot see it change); `TestResume` pins the attach.
  - `[low]` `patch` (gap) `TestFlagOff` can pass with a pre-existing limit row -- patched: the row is removed first and its absence asserted; the mutation line is recorded.
  - `[low]` `reject` (gap) R5's trace-only step accepts any status of 400 or more -- Story 16.4 changes the interim 500 into a 401, so a stricter code would pin the interim; the recorded mutation turned it red.
  - `[low]` `reject` (gap) `Web.Purge`'s first-error ordering is unpinned -- a pin needs an injectable failing `Live.Event.Purge`, which adds a seam for a one-line ordering.
  - `[low]` `reject` (gap) the failure paths after `StartVisitor` are untested -- the behaviour is the lead's accepted interim and a fault injection is not available.
  - `[low]` `reject` (gap) limit 0 or non-numeric -- as above.
  - `[low]` `reject` (gap) `TestRecentWindow` boundary between 3541 and 3600 s -- the spec's row 13 names 59 and 61 minutes, which the test uses.
  - `[low]` `reject` (gap) R2's request-header capture could flake -- it fails, never passes vacuously.
  - `[false]` `reject` (intent-alignment) the descriptive report's divergences (hook tested through `AttachFor`, the refusal chain split between in-process and live checks, time text only in the browser) -- it claims no defect; each surface is covered by a named row.

## Design Notes

**Architecture decisions:**
- **AD-4** governs the resume:
  - the hook in `OnLogin` (S16);
  - the cookie and its exact `SetCookie` call;
  - the 22-character reference with only its SHA-256 stored, as a bearer secret;
  - new CSP sessions recognised in the session events only, and no attach in the trace applications;
  - cross-site arrivals resuming on the POST;
  - Ownership as the one resolver, with no `SessionRef` taken from the client;
  - one durable session per IRIS user locally;
  - only creations counting.
- **AD-13** governs:
  - the post-sign-in check that ends the CSP session (the no-role precedent);
  - the forwarded-address rule;
  - `AddressCounter` (hashed address with timestamps; the probe exempt);
  - the CI-checked allow-list of unchecked prepares, which this story leaves at three entries;
  - "REST code writes only the Session row, the address counter, ...".
- **AD-27:** the counter's area (the Web step, Lane B's area) declares `Purge(daysToKeep)`, which keeps one hour whatever the number. Story 30.2's task calls it.
- **AD-3:** no new persistent class (`AddressCounter` exists and is registered). `Shell` keeps to `%CSP` and the public packages, so the refusal key lives there.
- **AD-19:** `proxyAddress` through `Public.Settings`; the limit is a product value in `Setting`, seeded at install.
- **AD-25:** the proxy overwrites `X-Forwarded-For`, and the probe connects directly, so it is exempt.
- **AD-12, AD-17:** no live event or audit entry carries the reference (row 6).
- **AD-22, AD-29, AD-33:** throwaways only; Lane B's files and tables.
- No AC contradicts an AD's Rule.

**Stored fields** (rule: a field the AC and AD-4/AD-13 don't call for would be a veto item; there is none):
- `Session.ResumeHash`: the reference's SHA-256 (AC 1, AD-4 "only its SHA-256 is stored"). Exact collation, because base64url is case-sensitive, and unique, so that one reference opens one row.
- `Session.CspSessionId`: the CSP session last attached (AC 1 "records the new CSP session on it"; AD-4 "records the new CSP session"). It is not the bearer value: the session cookie's value is `%session.CSPSessionCookie` (`irislib/%CSP/Response.cls:623-626`).
- `AddressCounter.AddressHash` and `CreatedAt`: unchanged from Story 0.4 (AD-13 "a hashed address with timestamps"). Retention is one hour (AC, AD-27).
- `Setting` row `onlineDemo.sessionsPerAddress` = 5 (AC "a product setting this story seeds"), only with the flag on.
- An older row's empty `ResumeHash` is never looked up, so an in-place upgrade needs no index build (inference). `live storage-roundtrip` is run once.

**Decided in-stage:**
- **The cookie's name** is `OcuTalonResume`. The setting key is `onlineDemo.sessionsPerAddress`, seeded by the Web step only with the flag on, so a local install's data doesn't change.
- **The refusal path.** `OnLogin` alone sees a new CSP session, so it decides. The `Shell`, which already ends a no-role session in the same request, ends it and renders. `Show` gains an optional `until` argument (the local page ignores it). The marker is a list, so Story 16.5 adds "busy" without a new key.
- **The error's time** is a page time that the splash script fills from `<time datetime>`, empty in the markup, as the reset line's time is (Story 16.2). Its value is the oldest counted creation + 1 hour: the moment the address is below the limit again.
- **Exempt sign-ins write no counter row.** A proxied request with no `X-Forwarded-For` counts under the proxy's own address; that cannot happen behind AD-25's proxy, which overwrites the header.
- **A resume sets no new cookie** (the existing one already expires at the reset). A row of another IRIS user is not resumed: this matches `SessionRef`'s own user check.
- **With no next reset** the cookie has no expiry, so it is a browser-session cookie. On the online demo the anchor and interval are always set.
- **An online-demo CSP session with no attached session** (an `OnLogin` failure) gets `SessionRef`'s error, which the API answers as any resolution failure today (500, logged without the user). `Web/Api.cls` is shared with Epic 4, and Story 16.4 builds the return to the splash on a 401.
- **Orders on resume.** No page view of orders exists before Epic 4's Break the feed box (Story 4.4, not merged). Row 2 therefore pins the orders at the data surface:
  - the session's `BreakFeedRun` row still names its `Ref`;
  - its `TraceRef`, which tags its Orders messages, is unchanged.
  - The page half is reported to the lead below, not added to Story 4.4 here.
- **The hash helper** is one method, `Session.Hash`, which `AddressCounter` reuses. It has the shape of AD-4's `Pairing.HashCode`, which Story 10.3 adds to a class this story may not edit, so that copy is forced by order; 10.3 can delegate to `Session.Hash`.
- **Counting without SQL** walks the counter's own index, because `OnLogin` runs as the demo account, which holds no SQL privilege, and the unchecked-prepare allow-list stays three entries.
- **The limit's live check runs in a second phase,** with `proxyAddress` set to the host's connection address and then restored. In phase 1 every sign-in of the earlier specs is exempt, so none of them can be refused.
- **The resume browser case** uses seeded rows (`Fixture.Turn`, `Approval`, `Pairing`) rather than a model turn, to keep the unit lean (DW-220). Row 6's curl path sends one real message, so a production message exists for the reference search.

**Decided in-stage (implement):**
- **Row 4 pins "no `OnLogin` in the trace applications" through the console log.** The trace applications' account has no write access to OCUTALON_PRIVATE (no application roles), so an `OnLogin` that ran there (the mutation of the table) fails with a protection error inside `NewVisitor` and creates no row and no cookie: the row-count and cookie checks alone cannot turn red. The unit therefore also compares the number of `OcuTalon.Web.SessionEvents:` lines in `messages.log` before and after the trace sign-in (an attach that fails writes one).
- **Row 10 ages the first counter row to 50 minutes** before the sixth sign-in, so that the unit also pins the window: a `Recent` that counts only the past minute counts four and lets the sixth in. The unit's own times (five sign-ins within seconds) could not tell an hour from a minute.
- **R5 gains a trace-only context.** A context that signed in only at the trace application and then calls `/state` has a CSP session that no `OnLogin` attached (the API application has no session event class), so `SessionRef` answers an error and the API answers 500 (a status of 400 or more is asserted, as 16.4 replaces it with 401). That is the only browser step where a lazy `Attach()` on the online demo would be visible: `Test.Data.Ownership.TestSessionRefOnTheOnlineDemo` pins it in process.
- **R2 does not assert that the CSP session id changed.** Task 0 (d) measured that build 154 reuses `%session.SessionId` after `?IRISLogout=end` and a new sign-in in the same jar, so the row's `CspSessionId` may equal the old one; the cases assert it is set, and `TestResume` pins the attach with an equal and a different id.
- **`Install.Step.Web.Purge` returns the first error but always runs both purges.** The counter is purged even when the live-event purge failed.
- **Footprint additions inside the accepted paths:** `Shell.REFUSALKEY` is a new parameter of a public class, so `Test.Web.PublicTexts` classifies it under `notText` (26, not 25; `compared` is 36); `AddressCounter.Shift` is public (the hook and the tests use it); `Test.Web.SessionEvents.ReferenceHits` is the unit's global scan of row 6 and `DropVisitors` removes visitor rows of the test user that an earlier failed run left.
- **A lock timeout on an address** (5 s) gives `AttachVisitor` an error status, which `AttachFor` logs by code and answers OK for; the visitor then has no session (500 at the API until Story 16.4).
- **The Web step's seed reads the flag through `Setting.Get`**, as the contract says, not through `Public.Settings` directly.

**For Story 10.3 and Story 12.7:** `web/e2e-online/resume.spec.ts` declares `notBuilt('R2b: /state returns the fixture pairing', '10.3')` and `notBuilt('R2c: the rail\'s Telegram card shows the fixture pairing', '12.7')`. The story that turns one on replaces it with the real check on R2's resumed session. If 10.3 reads its real `Pairing` row, it swaps the fixture for it.

**Integration ACs:**
- `Web.Api` (`/state`, `/events`, `/messages`) consumes `Ownership.SessionRef`'s per-sign-in resolution and gives each browser its own snapshot and poll (row 7).
- `Shell.OnPreDispatch` consumes the refusal that `OnLogin` records and produces the splash's field error (rows 10, 11).
- `Install.Step.Web.Purge`, the purge task's declaration, consumes `AddressCounter.Purge` (row 13).

**Consumes:**
- Story 2.2: `Ownership`, `SessionEvents`, `Session`.
- Story 16.1: the `online-demo` unit, its start values, `proxyAddress` and `fixtureUser`.
- Story 16.2: the splash, `#ocu-error`, `signInFromSplash`, `SplashAssets` and `tokens.mjs`.
- Story 0.4: `AddressCounter`, `Bridge.Ids`.
- Story 2.10's skeletons (`holdState`).
- `Test.Data.Fixture` (`Turn`, `Approval`, `Pairing`).
- Epic 10's `Data/Pairing.cls`, read only.

**Consumed-by:**
- **16.4:** `SessionEvents.#RESUMECOOKIE`, to expire the cookie on Sign out; the row's `Epoch` and `CspSessionId`; `SessionRef`'s unattached error, for the 401 return to the splash.
- **16.5:** the post-sign-in hook, where the busy refusal goes before the counter (no count on busy), and `Shell`'s refusal marker with state "busy".
- **16.6:** the probe's direct sign-ins are exempt.
- **10.3, 12.7:** the off checks above.
- **30.2:** the purge task calls `Web.Purge`.
- **29.4:** isolation under load builds on per-sign-in sessions.

**Rule 2 (extend, don't copy):**
- `NewVisitor` and `ForUser` share `NewRow`.
- The reference is `Bridge.Ids.NewRef()`.
- `Resume`/`StartVisitor` record the attach as `Attach` does (the same `SESSIONKEY`).
- The refusal follows `Shell`'s no-role path; the error's `<time>` follows `ResetLine`; `TOOMANY` follows the `splash.*` keys.
- The specs reuse `signInFromSplash`, `signOutGroup`, `irisScript`, `Fixture`, `holdState`, `sessionEvents`, `postTurn`, `notBuilt` and `page-time.ts`.
- The unit reuses `check_logs_clean`'s searches, `logout_all`, `page_token` and `check_session`.
- Copies, with reasons:
  - `AddressCounter.Purge` repeats `Live.Event.Purge`'s six-line pattern for another table and window;
  - `Session.Hash` precedes `Pairing.HashCode` (above).

**Footprint extensions:** `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls` (one key and its counts, as Story 16.2's accepted extension). Everything else is in the footprint:
- `Data/{Ownership,Session,AddressCounter}.cls`, `Web/SessionEvents.cls`, `Web/Public/**`, `Install/Step/Web.cls`, `Test/{Web,Data}/**`, `web/src/signin/**`, `web/e2e-online/**`, `docker/tests/test-online-demo.sh`;
- shared by member: `Data/Setting.cls` and `Test/Data/Setting.cls` (own members only), and `Test/Data/Tables.cls` (Lane B entries only).

**For the lead:**
- **Orders on the page:** the AC's "the page loads that ... orders" has no page surface before Story 4.4. It is pinned at the data surface here (Decided in-stage). Whether Story 4.4 turns on a page check on a resumed session is the lead's or orchestrator's routing call.
- **DW-220:** the unit grows by about 45 to 70 s locally (inference: the curl rows, four browser cases and phase 2's second Playwright start). Record the measured time against DW-220's `reopen_if` (the image job passes 30 min).
- **Integrate-forward:** the catalog counts (as in Story 16.2), `Setting.cls`' members and `Tables.cls`' entries are union-merge points with Epics 4 and 5.

**Ledger inbox:**
- DW-16: addressed by the `Ownership.SessionRef` task and rows 7 and 8, where two sign-ins of the shared account get two sessions, each polling only its own events.

**Lead spec gate (2026-10-25, runner C):**
- Stored fields accepted (decide, spec-bound): `Session.ResumeHash` (AD-4: the row stores only the reference's SHA-256) and `Session.CspSessionId` (the AC: "records the new CSP session on it"); `AddressCounter` gains methods, no new stored field. Any other stored field is a veto-window item: escalate it.
- Orders after a resume are tested at the data level (the session's Break the feed row and `TraceRef` unchanged after a resume) until a page view of demo orders exists (decide): any page that reads the session's data reads the resumed session's, so nothing is routed to Epic 4.
- The interim behaviours until Story 16.4 (an attach failure on the online demo answers 500; Sign out ends only the CSP session) are accepted; Story 16.4's ACs own the return to the splash and `SessionOps.End`.
- Record the `online-demo` unit's measured time under Verification (DW-220).

## Verification

**Targets and variables:**
- Run every command from the worktree root, in the foreground with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- Every `ci/iris.sh` and `ci/warm.sh` call carries lane C's three variables, written out below for the implement stage. QA and review use their own stage name and tags:
  - implement `e16s3i` (fresh) and `e16s3iw` (warm);
  - QA `e16s3q`/`e16s3qw`;
  - review `e16s3r`/`e16s3rw`.
- The flag-on checks run only in the `online-demo` unit's throwaway compose project of lane C (`ocutalon-<label>-e16s3i-<epoch>-<pid>`), never on `ocutalon-slot-c`. Each stage tears down only its own tags.
- Run `ci/iris.sh build` before every browser run that should see a changed spec or asset.

**Commands:**
- (loop) `npm --prefix web run tokens` -- writes `SplashAssets.cls`; `git diff --stat -- src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls` shows nothing.
- (loop) `npm --prefix web test` -- every node test passes (`tokens`, `playwright-projects`, `ux-strings` among them).
- (loop) `npm --prefix web run lint` -- `tsc` passes over `e2e/` and `e2e-online/`.
- (loop) `bash docker/tests/test-web-build.sh` -- the build (with `tokens.mjs --check`) passes and the tree stays clean.
- (loop) `bash ci/checks.sh` -- every block passes. `class-rules`' unchecked-prepare and no-embedded-SQL rules are unchanged.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3iw bash ci/warm.sh up` -- once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s3iw bash ci/iris.sh class <Class>` -- one call per class, each printing `CLASS ... passed` after a `WARM reloaded` line:
  - `OcuTalon.Test.Web.SessionEvents`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Data.Session`, `OcuTalon.Test.Data.AddressCounter`, `OcuTalon.Test.Data.Setting`, `OcuTalon.Test.Data.Tables`;
  - `OcuTalon.Test.Web.Install`, `OcuTalon.Test.Web.Splash`, `OcuTalon.Test.Web.PublicTexts`, `OcuTalon.Test.Web.Status`, `OcuTalon.Test.Web.SignIn`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Msg.Catalog`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3iw bash ci/warm.sh down` -- at the stage's end and after a failure.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh build` -- before each `live` run.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh live online-demo` -- PASS: Stories 16.1 and 16.2's rows, plus rows 4, 6, 10, 12 and 14, R1, R2, R4, R5 and L1, and Task 0's `MEASURED` lines. Record its time: Story 16.2 measured 165 to 204 s; expected about 230 to 275 s, inside the 540 s default deadline.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh live sign-in` -- PASS, unchanged (row 9: one durable session per user on a local stack).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh live storage-roundtrip` -- PASS (the `Session` storage gained two slots and an index).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh shard lane-b` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh shard lane-a` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s3i bash ci/iris.sh teardown` -- nothing tagged `e16s3i` is left.
- The install, production, floor and demo-path units are left to CI.

**Task 0 results** (the unit's `MEASURED` lines on lane C's throwaway, build 154):
- (a) The Set-Cookie is in the sign-in POST's 303 answer: `MEASURED resume Set-Cookie attributes (the sign-in POST's answer): OcuTalonResume=<value>; expires=Mon, 26 Oct 2026 04:00:00 GMT; path=/ocutalon/; secure; httpOnly; sameSite=strict;`. The first `/ocutalon/` GET after that POST carries none (the session is attached already). A sign-in that the group carried (trace application first) gets the same line on its first `/ocutalon/` GET: `MEASURED resume Set-Cookie attributes (the group-carried first /ocutalon/ GET): OcuTalonResume=<value>; expires=...; path=/ocutalon/; secure; httpOnly; sameSite=strict;`. The header name is written in capitals by the web server (`SET-COOKIE`), so the unit's sed/grep is case-insensitive. No fallback to `Shell.OnPreDispatch` is needed.
- (b) `MEASURED Chromium keeps the Secure resume cookie over http://127.0.0.1:<port>: yes` (R1: `httpOnly`, `secure`, `sameSite: 'Strict'`, path and `expires` equal to `nextReset` to the second; Chromium reports a fractional `expires`, so the case floors it). `OCUTALON_URL` stays `http://127.0.0.1:<port>`.
- (c) IRIS sees the iris container's default gateway as `REMOTE_ADDR` for the host's requests (`MEASURED REMOTE_ADDR of the host's requests, derived from the container's default gateway: 172.22.0.1` on the last run; 172.28.0.1 and 172.29.0.1 on others: it follows the project network). The unit derives it from `/proc/net/route` (little-endian hex of the default route's gateway), and phase 2's precondition (one proxied sign-in writes a counter row for its forwarded address) passed with it. Phase 2 sets `proxyAddress` to it and puts `192.0.2.10` back, read back.
- (d) `MEASURED CSP session id reused on resume: yes`: build 154 reuses `%session.SessionId` after `?IRISLogout=end` and a new sign-in in the same jar. That is why nothing in the hook compares session ids.
- The `online-demo` unit's new local time (DW-220's `reopen_if`): 195.5 s wall-clock for the last green run of `ci/iris.sh live online-demo` (3:15.5), 203 s for the first all-green one (3:23.2); a final run after the review patches took 201 s (rc 0, 119 PASS lines); Story 16.2 measured 165 to 204 s. The unit's default deadline is 540 s.

**Shared surfaces:**
- The online demo's sign-in now creates one `Session` row per sign-in. Story 16.1 and 16.2's specs and the unit's curl sign-ins are exempt in phase 1 and run unchanged; search `web/e2e-online/` and the unit for any assumption of one shared demo session and update it.
- `Session`'s contract in `Test.Data.Tables`.
- `Test.Msg.Catalog`'s counts, `Keys` and `Fixtures`, and `PublicTexts`' counts.
- `SplashAssets` and the splash policy's hashes.
- The public `proxyAddress` (changed and restored in phase 2, and by the in-process tests).
- The `AddressCounter` rows, and the `Setting` row of the new key.
- `Web.Purge`'s behaviour (`TestPurgeDeclaration` stays green).
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; one per AC, each applied temporarily, observed red, then reverted byte-identical; a live mutation needs a fresh `live online-demo` run, with the bundle rebuilt for an asset change):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `resume.spec.ts` R1 | `SessionEvents` sets the cookie without HttpOnly |
| AC 1 | `Test.Web.SessionEvents.TestFirstSignIn` | `NewVisitor` stores the reference instead of its hash |
| AC 2 | `resume.spec.ts` R2 | `Ownership.Resume` always answers "" |
| AC 2 | `Test.Web.SessionEvents.TestResume` | the resume is skipped when the row's `CspSessionId` equals `%session.SessionId` |
| AC 2 | the unit's row 4 | `Web.Common` gives every application `EventClass` `SESSIONEVENTS` |
| AC 3 | `resume.spec.ts` R4 | `ForResume` falls back to the user's first row (`ForUser`) when the hash opens none |
| AC 3 | the unit's row 6 | `AttachFor` logs the reference on a resume |
| AC 4 | `resume.spec.ts` R5 | `Ownership.SessionRef` calls `Attach()` on the online demo too |
| AC 5 | the unit's row 10 | `AddressCounter.Recent` counts only the past minute |
| AC 5 | `address-limit.spec.ts` L1 | `Shell.OnPreDispatch` ignores the refusal marker |
| AC 5 | `Test.Web.SessionEvents.TestClientAddress` | the left-most `X-Forwarded-For` entry is taken |
| AC 5 | `Test.Web.Install.TestPurgeAddressCounter` | `Web.Purge` stops calling `AddressCounter.Purge` |

**Mutation record** (Rule 19; each mutation applied temporarily, observed red, then reverted with the tree byte-identical, restored from a backup made before it; live ones in a fresh `live online-demo` run, three runs for the mutations that cannot share one):
- mutation: `resume.spec.ts` R1 -- `SessionEvents` sets the cookie with HttpOnly 0 -- red: R1 failed in the unit's browser step (the Set-Cookie of the answer lost `httpOnly`).
- mutation: `Test.Web.SessionEvents.TestFirstSignIn` -- `NewVisitor` stores the reference instead of its hash -- red: `TestFirstSignIn`, `TestResume`, `TestUnknownCookie` failed ("the row keeps the SHA-256 of the reference").
- mutation: `resume.spec.ts` R2 -- `Ownership.Resume` always answers "" -- red: R2 failed in the browser step (a new epoch), and the unit's row 6 resume and row 10 cookie sign-in with it.
- mutation: `Test.Web.SessionEvents.TestResume` -- `Resume` returns "" when the row's `CspSessionId` equals `%session.SessionId` -- red: `TestResume` failed ("the row is attached again"), `TestFlagOff` followed from the rows it left.
- mutation: the unit's row 4 -- `Web.Common` gives every application `EventClass` `SESSIONEVENTS` -- red: row 4 failed on the console log's `OcuTalon.Web.SessionEvents:` lines (1 to 2); the first version of the row (cookie and row count only) stayed green, because the trace application's account cannot write the private database, so the check now counts the log lines (see Decided in-stage). The mutation also broke `/ocutalon/public/status` (rows 2 and 11) and, on the API, R5's trace-only step, which is why R5 has its own run.
- mutation: `resume.spec.ts` R4 -- `ForResume` falls back to the user's first row (`ForUser`) when the hash opens none -- red: R4 failed ("with a different value": the unknown cookie resumed another row).
- mutation: the unit's row 6 -- `AttachVisitor` logs the reference before the resume -- red: "row 6: '2' line(s) of the container's output, messages.log or the after-start log hold the resume reference", after the first start and after the restart.
- mutation: `resume.spec.ts` R5 -- `Ownership.SessionRef` attaches by user name on the online demo too (the online-demo block removed) -- red: R5 failed on its trace-only step (status 200 instead of 400 or more); it is the run's only failure. Before that step existed, R5 could not see this mutation (every visitor has a Ref from `OnLogin`).
- mutation: the unit's row 10 -- `AddressCounter.Recent` counts only the past minute (cutoff 60 s) -- red: row 10 failed (the sixth sign-in was let in: status 303, the shell) once the first counter row was aged to 50 minutes; with five fresh rows alone it stayed green.
- mutation: `address-limit.spec.ts` L1 -- `Shell.OnPreDispatch` ignores the refusal marker -- red: L1 failed in the proxied phase (no error on the page), and row 10's sixth sign-in with it.
- mutation: `Test.Web.SessionEvents.TestClientAddress` -- the left-most `X-Forwarded-For` entry is taken -- red: `TestClientAddress` ("'a, b' gives b", "the last of three", "an empty last entry ...") and `TestLimit` failed.
- mutation: `Test.Web.Install.TestPurgeAddressCounter` -- `Web.Purge` stops calling `AddressCounter.Purge` -- red: `TestPurgeAddressCounter` ("the 61-minute row is deleted").
- mutation: `Test.Web.SessionEvents.TestLimitIsTheSetting` -- `AttachVisitor` ignores the setting and uses the literal 5 -- red: "limit 2: creation 3 is refused".
- mutation: `Test.Data.AddressCounter.TestLockExcludesAnotherJob` -- `Unlock` does nothing -- red: "after Unlock another job takes it at once"; `Test.Web.SessionEvents.TestLimit` failed too ("the address's lock is released after the creations" and "after the refusal").
- mutation: `Test.Data.AddressCounter.TestLockExcludesAnotherJob` -- `Lock` answers 1 without locking -- red: "another job cannot take it while it is held".
- mutation: `Test.Data.Ownership.TestResumeAndStartVisitor` -- `Resume` drops the `IrisUser` check -- red: "another user's row is not resumed" and "and is not touched".
- mutation: `Test.Web.SessionEvents.TestClientAddress` and `TestExempt` -- `ClientAddress` treats every request as proxied when a proxy is set (no equality with `REMOTE_ADDR`) -- red: "not from the proxy: exempt", "the proxy's address is matched exactly" and `TestExempt` sign-in 6.
- mutation: `Test.Data.Setting.TestAddressLimitSetting` -- `SeedSettings` seeds nothing -- red: "writes the row of the absent key", "with the value 5".
- mutation: `Test.Web.SessionEvents.TestFlagOff` -- `SeedSettings` ignores the flag -- red: "and seeds nothing" (the limit's row is removed first, so the check can fail).
- mutation: `Test.Web.Splash.TestTooManySessions` -- the `datetime` attribute is written unescaped -- red: "the time attribute is escaped", "and never written raw".

**QA additions (QA; stage qa, tags `e16s3q`/`e16s3qw`).** Gaps found after the implement stage's matrix; every test creates and removes its own rows, in either order:
- (QA) `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls` -- `TestTamperedCookie` (row 5, AC 3: 18 decorations of a real reference -- one character changed, added, removed or doubled, `=` padding, white space, a line feed, a NUL, the other case, standard base64 letters, a wide character, 4000 characters, 22 of no permitted one -- each answers OK, writes no console line, makes a fresh row and a new cookie, never touches the real row, and the real reference resumes afterwards); `TestFlagOffIgnoresTheCookie` (row 9, AC 4: a flag-off sign-in carrying a visitor row's cookie still attaches the user's one durable session, sets no cookie, writes no counter row); `TestClientAddressEdges` (row 12, AC 5: tab and space padding, IPv6, five entries, a client-supplied first entry, commas and spaces only, a non-proxy with a long list, a remote that only starts with the proxy's address).
- (QA) `src/ocutalon/cls/OcuTalon/Test/Data/AddressCounter.cls` -- `TestPurgeIsPerRowNotPerAddress` (row 13, AC 5: three addresses, an old and a recent row, old only, recent only; 3590 s kept and 3610 s deleted; a second Purge changes nothing; `Recent` counts what is left); `Clean` lists its three fixture cases.
- (QA) `docker/tests/test-online-demo.sh` -- row 5 over HTTP (13 tampered or malformed cookies through the web gateway: each gives the shell, a new cookie and a new session, none writes an `OcuTalon.Web.SessionEvents` line, and the real reference still resumes its own epoch); and `check_search_controls`, run inside `check_logs_clean` (after the first start and after the restart): the container's output, `messages.log` and the after-start log are readable and not empty, the event log, the live events, the production message headers and the audit log hold rows, and the global scan finds the row 6 session's resume hash in OCUTALON_PRIVATE, the posted message's text in OCUTALON_DATA and the proxy address in OCUTALON_PUBLIC, so that a count of 0 in row 6 cannot come from a search that reads nothing.
- (QA) The row 6 search already covered every surface the AC names: the container's output, `messages.log`, the after-start log, `Ens_Util.Log`, `OcuTalon_Live.Event` payloads, `%SYS.Audit`, and every global of the three OCUTALON databases (production messages included), after a sign-in, a real message and a resume. Measured with the controls: the audit log holds entries (instance-wide auditing records configuration events; the sign-in itself is not an audited event, so the audit search can only catch a reference written into an entry), and the container has no web-server access log file (nothing but the three logs and `iscagent_console.log` exist). Left unexercised: `%session.Data` lives in the session global outside the three databases; `TestFirstSignIn` pins it in process.
- (QA) Runs: `OcuTalon.Test.Web.SessionEvents` and `OcuTalon.Test.Data.AddressCounter` pass on the warm stack (one class per call); `live online-demo` passed three times with the additions (128 PASS lines, 203 s and 203 s on the last two; the DW-220 time is unchanged within noise); `bash docker/tests/test-boundaries.sh` passes (the first version of the unit block held a raw non-ASCII character; it is now `printf` octal escapes).
- (QA) Measured fact: `$ZStrip(text, "<>W")` does not strip a carriage return on build 154 (a tab and a space are stripped), so `ClientAddress` of "a, b" followed by CR gives "b" with the CR. A web server never delivers a bare CR inside a header value, so it is unreachable over HTTP, and no test asserts it.

**Mutation record (QA)** (each applied temporarily, observed red, restored from a backup in the QA scratchpad folder, and `git status --short` and `git diff --stat` compared with their state before it: identical):
- mutation: `Test.Web.SessionEvents.TestTamperedCookie` and the unit's row 5 (QA) -- `Session.ForResume` drops the shape check and hashes `$Extract(reference, 1, 22)` -- red: `TestTamperedCookie` (cases 3, 4, 5 and the later ones: "a fresh session, not the real one", "exactly one row is created", "the real row is not touched"), and the unit's "row 5 (QA): of 13 tampered or malformed cookies 10 gave the shell, a new cookie and a new session (the others, as n:status/page: 2:303/shell 3:303/shell 8:303/shell)": the padded, the one-character-longer and the `%0A` values resumed the real session.
- mutation: the unit's row 6 controls (QA) -- `Test.Web.SessionEvents.ReferenceHits` ignores its database list and scans OCUTALON_DATA only -- red: "row 6 control: the searched records hold rows, and the global scan reads each of its three databases (2 of 6 values differ)" after the first start and after the restart (`scan-private` and `scan-public` blind), while the reference scan itself stayed green with 0 hits: the vacuous search the controls exist to expose.
- mutation: `Test.Web.SessionEvents.TestFlagOffIgnoresTheCookie` -- the flag-off branch of `AttachFor` also resumes the cookie's row (`Ownership.Resume` after `Attach`) -- red: "it attaches the user's durable session, not the visitor's row" and "the visitor's row is not touched" (`TestFailureIsLoggedWithoutTheUser` followed, as the extra call logs another error code).
- mutation: `Test.Web.SessionEvents.TestClientAddressEdges` -- `ClientAddress` strips spaces only (`$ZStrip(..., "<>", " ")`) -- red: "a tab-padded entry gives b" (it is the only failure: the older `TestClientAddress` cases use spaces).
- mutation: `Test.Data.AddressCounter.TestPurgeIsPerRowNotPerAddress` -- `Purge`'s cutoff is 3620 seconds instead of one hour -- red: "the old row of the mixed address is deleted" (the only failure: the old test's rows are 3700 and 3500 seconds). A second mutation, `Purge` deleting every row of an address that has an old row, also turned it red, with `TestPurgeKeepsOneHour`.

**Mutation record (code review)** (stage code-review, warm tag `e16s3rw`; each applied temporarily, observed red, restored from a backup in the review's scratch folder, the class green again on the same stack, and `git status --short` and `git diff --stat` identical to before):
- mutation: `Test.Web.SessionEvents.TestNoRoleOnTheOnlineDemo` (code review) -- `AttachFor` runs the online branch without the role (`If hasRole || (onlineDemo = 1)`) -- red: "it attaches nothing", "and the visitor's row is not touched".
- mutation: `Test.Data.AddressCounter.TestRecentWindow` (code review) -- `Recent` drops its exact `AddressHash` comparison -- red: "rows of the hash in another case are not counted".
- mutation: `Test.Data.Ownership.TestSessionRefOnTheOnlineDemo` (code review) -- `SessionRef`'s online-demo block is removed (the lazy `Attach` by user name runs on the online demo too) -- red: "online: with no Ref attached the result is empty", "nothing is attached", "online: another user's Ref gives an empty result", "online: a Ref with no row gives an empty result".
- mutation: `Test.Data.AddressCounter.TestAddStoresOnlyTheHash` (code review) -- `Unlock` does nothing -- red: "and after Unlock another job takes it" (with `TestLockExcludesAnotherJob`'s "after Unlock another job takes it at once"); the line it replaced could not fail.
- (code review) Runs after the patches: `OcuTalon.Test.Web.SessionEvents`, `Test.Data.AddressCounter`, `Test.Data.Ownership`, `Test.Web.Install` and `Test.Web.Splash` pass on the warm stack, one class per call, and `shard lane-b` passes (44 classes, 47 s). A fresh `live online-demo` (tag `e16s3r`) passes with 128 PASS lines in 219 s wall-clock (DW-220: Story 16.2 measured 165 to 204 s, QA 203 s). `npm --prefix web test` (568 pass), `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh` and `bash ci/checks.sh` pass. Both tags were torn down.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** On the online demo every sign-in now gets its own `Session` row: `SessionEvents.AttachVisitor` resumes the row of a valid `OcuTalonResume` cookie, or creates a visitor row and sets the cookie once (22-character reference, only its SHA-256 stored, HttpOnly, Secure, `SameSite=Strict`, path `/ocutalon/`, expiring at the next reset). `Ownership.SessionRef` never attaches by user name there (DW-16). Proxied creations are counted per hashed client address under one lock; the sixth in an hour is refused by `Shell.OnPreDispatch`, which ends the CSP session and shows the splash's field error with a page time. Local and IPM installs keep one durable session per user. The limit is a seeded setting (5), and `Web.Purge` purges the counter (one hour).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Session.cls`: `ResumeHash` and `CspSessionId` appended to the storage, `Hash`, `NewVisitor`, `ForResume`, shared `NewRow`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `Resume`, `StartVisitor`, the online-demo `SessionRef`.
- `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls`: `Recent`, `Add`, `Lock`, `Unlock`, `Purge`, `Shift`.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls`: the limit's key and seed.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`: `SeedSettings`, the counter's purge.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`, `Web/Public/{Shell,Login,Splash,SplashAssets}.cls`, `web/src/signin/splash.js`: the hook, the refusal, the splash error and its time.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls`, `Test/Web/PublicTexts.cls`: `splash.tooManySessions` and the counts.
- `src/ocutalon/cls/OcuTalon/Test/**` (Web and Data classes, the new `Test/Data/AddressCounter.cls`), `web/e2e-online/{support.ts,resume.spec.ts,address-limit.spec.ts}`, `docker/tests/test-online-demo.sh`: the tests and the unit's new rows and phase 2.

**Review.** 33 findings from four layers: 7 patched (3 entries at medium: the lock and its concurrency test, the limit test, R2's assertion; 3 low), 0 deferred, 26 rejected with the reasons in the triage log (spec-decided, accepted interim, or not reachable). Patches applied: `TestLimitIsTheSetting`, `TestLockExcludesAnotherJob` with `FreeInAnotherJob`, lock-release assertions in `TestLimit`, row 11 requiring one passed and none skipped, the weak R2 assertion removed, `TestFlagOff` clearing the limit's row first, and eight new mutation lines.

**Follow-up review recommended: true.** Three medium entries were patched (the limit test, the lock tests, R2's weak assertion). The unverified risk: the lock's two-process race on the last place is pinned by exclusion and release only, not by a concurrent sign-in test.

**Verification performed.**
- `npm --prefix web run tokens` (no change to `SignInAssets.cls`), `npm --prefix web test` (568 pass), `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh` and `bash ci/checks.sh`: all pass, after the patches.
- Warm stack, one class per call, all passed: SessionEvents, Ownership, Session, AddressCounter, Setting, Tables, Install, Splash, PublicTexts, Status, SignIn, Api (one pre-existing skip), Msg.Catalog; after the patches SessionEvents, AddressCounter, Ownership and Splash again, and the other classes through `shard lane-b`.
- `live online-demo`: green before and after the patches (201 s after); `live sign-in` green (438 s); `live storage-roundtrip` green; `shard lane-b` passed (44 classes, 115 s); `shard lane-a` passed (47 classes, 412 s); teardown left nothing tagged `e16s3i` or `e16s3iw`.
- Mutations (Rule 19): every line in the Mutation record turned red and was reverted byte-identical from a backup (compared with `cmp`).

**Residual risks.**
- The handoff subagent ran eleven warm class runs in one message, against the one-class-per-call rule. All passed, and this stage re-ran every class one per call.
- An address-lock timeout or an `OnLogin` failure leaves the visitor with no session until Story 16.4 (the API answers 500; the lead accepted this interim).
- The hashed address is an unsalted SHA-256, as AD-13 prescribes; an IPv4 value could be brute-forced from a counter row within its one-hour life.
