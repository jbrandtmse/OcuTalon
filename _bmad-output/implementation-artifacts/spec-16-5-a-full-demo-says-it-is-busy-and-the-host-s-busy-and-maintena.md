---
title: 'Story 16.5: A full demo says it is busy, and the host''s busy and maintenance pages are ready'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: 'dde430026f83883af8b79240c090b8a9288867ea'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, lines 122-151; AD-13, lines 342-386, above all the "Demo busy" bullets at 377-381 and the login-page bullets at 357-366; AD-25, lines 676-721, the proxy bullets at 682-694, the probe at 710-713 and capacity at 714-719; the Consistency Conventions rows "Announcements and focus", "Text OcuTalon sends", "README link" and "Shared look outside Angular", lines 894-929)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only Pages, lines 98-135; Titles, line 79; Interaction Primitives, lines 200-215 and 376-392; State Patterns > Demo busy, line 348; Status banners (web), lines 845-859)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/DESIGN.md (read only the splash-canvas token, lines 543-546; the Full logo, line 848; the canvas and card rules, lines 700-702; the contrast table, lines 626-644)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/mockups/splash.html (the too-many-sessions field error, lines 629-648; the resetting card, lines 651-671; .centered-page and .single-card, lines 419-429)'
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      A signed-in CSP session is not counted in $SYSTEM.License.InstanceConnections() on the throwaway (build 154, Community key, the image's own web server), so no number of sign-ins moves the status or the post-sign-in check toward the cap. The cap is the only lever the tests have, and whether the real demo host counts sessions is unmeasured.
    evidence: |-
      Task 0 (a) to (d), measured in the online-demo unit and by hand on lane C's warm stack: the count reads 1 (the reading script itself) with no session, with one, with two (the second from the browser), over keep-alive connections and after the first sign-out; the status's own count (HTTP view) stays 0; UserList shows no CSP user. AD-13's "every signed-in CSP session holds a licence connection" (S13) and the matrix rows 1, 5, 6 and 9 assume a count that sessions raise.
    location: >-
      src/ocutalon/cls/OcuTalon/Web/Public/Status.cls (Busy); src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls (OWNCONNECTIONS); docker/tests/test-online-demo.sh; web/e2e-online/busy.spec.ts
    severity: high
  - summary: >-
      No page control sends a guide prompt yet, so the online demo's 503 rule for a guide message (the entry leaves, nothing is announced) has no test.
    evidence: |-
      ChatOutbox.send(text, fromGuide) has no caller with fromGuide true in web/src/app; the first caller is Epic 4's guide. The rule is in ChatOutbox.refuse; B2 sends typed text only.
    location: >-
      web/src/app/chat/chat-outbox.ts (refuse)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** When the online demo is full, nothing tells the visitor so:
- the splash shows no busy state;
- a proxied sign-in past the reserve is let in;
- the signed-in page opens trace windows that the instance cannot hold, and treats an API 503 as an error or as silence;
- the demo host has no busy page or maintenance page to serve.

The proxy (Story 29.3) also cannot count the busy states that IRIS renders, because they carry no marker (FR-15, NFR-23).

**Approach:**
- **Server side.**
  - `OcuTalon.Web.Public.Status` gains one busy reader and the marker header.
  - The splash renders a server-side "busy" state with the UX's text and README link.
  - `SessionEvents`' online-demo hook refuses a proxied sign-in past the reserve before it resumes or counts anything. It does so through Story 16.3's refusal marker, which `Shell` already turns into the splash.
- **The signed-in page (online demo only).**
  - It checks `/ocutalon/public/status` before opening a trace window.
  - It turns any API 503 into a "Demo busy" banner, and gives a refused message's text back to the composer.
- **Two self-contained pages in `docker/`:** the busy page and the maintenance page, which the demo host serves.

## Boundaries & Constraints

**Always:**
- **The flag decides.** Every new behaviour runs only on the online demo:
  - Server side, a busy state needs a valid `connectionCap`, which only the `Public` step writes with the flag on. Without it, `Status.IsBusy` answers 0, so a local install never sees busy, a marker or a refusal.
  - On the page, it needs `snapshot.onlineDemo === true`. With the flag off, the page, its trace links and its 503 handling behave exactly as today.
- **Busy, before sign-in:** `Status.Busy()` is `IsBusy($SYSTEM.License.InstanceConnections(), Settings.Get("connectionCap"), Settings.Get("connectionReserve"))`. It is true when connections reach the cap minus the reserve. `Status.Body` and the splash both use it.
- **Busy, after sign-in:** `Status.Busy(own)` subtracts `own` connections before comparing. The hook calls it with the new session's own connection (`own` = 1, unless Task 0 (d) measures that `OnLogin` does not count it yet, in which case `own` = 0). So it refuses exactly when connections exceed the cap minus the reserve.
- **Licence connections.**
  - Only `$SYSTEM.License.InstanceConnections()` is read. No source of the product references `InstanceConnectionsMax`.
  - Neither check signs in, opens a session or takes a licence connection.
- **The marker.** `X-OcuTalon-Busy: 1` (`Status.#BUSYHEADER`) is on exactly three kinds of answer, and on no other:
  - `/ocutalon/public/status` while it reports busy;
  - the splash rendered in state "busy", at a plain GET;
  - the post-sign-in refusal.
  The status code of each stays 200.
- **Texts, exactly** (Rule 14: ASCII in sources, `&middot;` for U+00B7):
  - busy: "The demo is busy right now. Try again in a few minutes, or install it yourself.";
  - link: "Install it yourself (README)";
  - maintenance: "The demo is resetting." and "It usually takes a few minutes. This page returns to the sign-in screen by itself.", under the tab title "Resetting · OcuTalon".
  The busy text is the one catalog key `banner.demoBusy` (source: EXPERIENCE State Patterns / Demo busy). Splash's `BUSY` parameter is compared with that key.
- **The splash's busy state.**
  - **When it applies.** A request with no state and no message (`Message("", code, 0)` gives "") while `Status.Busy()` is 1 is shown in state "busy". Splash's `OnPreHTTP` decides this once, before the header is written, and both `Show` and a direct render call it first. The wrong-credentials and no-role messages win over busy.
  - **What it renders, in `#ocu-error` under **Sign in and start**:** the busy text, then the README link exactly as the footer writes it (`README`, `target="_blank"`, `rel="noopener noreferrer"`, the sr-only " (opens in a new tab)" and the external-link icon).
  - **What stays as it is:** no `aria-invalid`, the button keeps no `disabled`, the published values stay prefilled, and the error keeps `autofocus`, as every splash error does.
- **The post-sign-in refusal.**
  - **Order in `AttachVisitor`:**
    1. `ClientAddress` first.
    2. For a proxied request with `Status.Busy(own)` = 1: write `%session.Data(Shell.#REFUSALKEY) = $ListBuild("busy")` and stop. That means no resume, no `StartVisitor`, no lock, no counter row and no cookie.
    3. Only then the cookie resume and Story 16.3's counter.
  - A request that is not proxied (the probe, an operator) is exempt.
  - `Shell.OnPreDispatch`'s existing marker path ends the CSP session and renders `Login.Show("busy", 0, "")`.
- **The page's busy state.**
  - **One banner.** It shows while either cause holds:
    - an API 503 (any `/ocutalon/api/` answer), until the next 2xx API answer;
    - a trace check whose status said busy, until a later status check says otherwise.
  - **The banner itself.** It is `demoBusy` in the banner catalog, after `unreachable`: warning, triangle-alert, online demo only, not closable. Its text is `banner.demoBusy`, and its action is the existing `bannerAction.installYourself`, linking to `README_URL`. The banner stack announces it once, as it announces every banner. Nothing else announces it, and nothing moves focus.
  - **The re-check.** While the trace cause holds, the page checks status again every 10 s, quietly and without a session.
- **The trace check** (AD-13: "before opening a trace window, the page checks `/status`").
  - **Where.** A press on a `TraceLink` or on "Open my conversation in Visual Trace" on the online demo is taken over: `preventDefault`, then `GET /ocutalon/public/status?t=<ms>`. The unique query keeps any cache from answering.
    - Busy: the banner shows, and no window opens.
    - Otherwise: `window.open(url, '_blank', 'noopener,noreferrer')`.
  - **When the check fails.** A status check that fails (no answer within 5 s, or not JSON) opens the window, because the proxy's busy page covers a full demo.
  - **What stays as it is.** The popover closes as it does today. What the visitor typed stays in the composer.
- **A message refused with 503** (online demo).
  - A typed message's text goes back into the composer when the composer is empty, and the message leaves the chat.
  - When the composer already holds other text, the message stays as today's "Not sent" with "Retry sending".
  - A guide prompt's message leaves the chat.
  - No "Message not sent" is announced for a 503 that returned the text or removed a guide message.
  - The composer takes no focus for this; its one `.focus(` call stays.
- **The host pages: `docker/busy.html` and `docker/maintenance.html`.**
  - **What they hold.**
    - Pure ASCII, `<html lang="en">`, and one `<style>` block.
    - No script, no `style=` attribute, and no `<link>` but `<link rel="icon" href="data:,">`, so that the browser asks nobody for an icon.
    - No font file and no URL but those listed below.
    - The splash canvas: `#FFFFFF`, and `#11192B` under `prefers-color-scheme: dark`. A 400px card with DESIGN's surface, border and `rounded.md`. Ink, link and focus colours are the values of `SplashAssets.cls`' generated light and dark blocks. The focus ring is always visible.
    - No host, address, port or other infrastructure detail.
  - **The busy page.**
    - `<title>Try OcuTalon</title>`.
    - `<h1>`: "The demo is busy right now."; `<p>`: "Try again in a few minutes, or install it yourself.".
    - Then the README link as the splash writes it, to `https://github.com/jbrandtmse/OcuTalon#readme`.
    - No image, because it is served at any path, where a relative file would be answered by IRIS's 503 too.
  - **The maintenance page.**
    - `<title>Resetting &middot; OcuTalon</title>`.
    - The logo is a `<picture>`: the dark source for `prefers-color-scheme: dark`, then `<img alt="OcuTalon" width="320" height="179">`, using `OcuTalon-Logo-{light,dark}-{640,1280}.png` (640 at 1x, 1280 at 2x) by bare file name, beside the page.
    - The card holds `<h1>`: "The demo is resetting." and `<p>`: "It usually takes a few minutes. This page returns to the sign-in screen by itself.".
    - `<meta http-equiv="refresh" content="10; url=/ocutalon/">`: it reloads itself at the splash's address until the demo answers there.
  - The logos stay in `logo/web/`. The page's header comment names them as the files the host serves beside it.
- **Test discipline (Stories 16.1 to 16.3).**
  - Every curl jar and browser context ends with the group-wide `/ocutalon/?IRISLogout=end`, and every page request carries a unique `probe=<n>`.
  - Each case uses forwarded addresses of its own and removes what it creates.
  - The `connectionCap` it lowers is restored on every path and read back (8), as `proxyAddress` is.
  - The cap is always derived from a reading at run time, never a literal.
- **Runtime targets (Rule 21).**
  - Stacks go only through `ci/iris.sh` and `ci/warm.sh`, with lane C's variables.
  - `ocutalon-slot-c` (namespace `OCUTALON`, port 52792, build 154 checked first with `iris_server_info`) is used for `iris_doc_load` compiles only.

**Never:**
- **Files.**
  - No edit to Lane A's, Epic 4's or any contended file (the lead's lists): `Install/Step/{Public,Users,Roles}.cls`, `Core/**` other than this epic's named classes, `web/src/app/{phone,feed,guide,mailbox}/**`, `web/src/app/main-page/**`, `.github/workflows/**`, `README.md`, `docs/**`.
  - No edit to any existing `docker/**` file but `docker/tests/test-online-demo.sh`.
  - No binary file under `docker/`.
  - No change to `web/playwright.config.ts`, `web/package.json`, `ci/units.sh` or `src/short-names.tsv`.
- **Behaviour.**
  - No change to `LiveState`'s contact or load behaviour: a 503 on the first `/state` keeps "Couldn't load your session." with Retry (Design Notes).
  - No session, sign-in or licence connection is taken by a busy check, and nothing reads `InstanceConnectionsMax()`.
  - No change to the local sign-in page's output, which stays byte-identical, or to a flag-off sign-in.
  - No grant, role, application or setting-schema change.
  - Nothing touches the demo host or anything outward. The proxy's mapping and counting are Story 29.3's.
- **Text.** No new public text: a text that is not quoted above, in the AC or in the UX is a `## Clarification Needed` stop.
- **Out of scope:**
  - the probe (16.6);
  - the in-app resetting view, the countdown and `?since=` (16.8);
  - Sign out's dialog and `SessionOps.End` (16.4);
  - the allowances (16.9);
  - the busy page's HTTP status at the proxy (29.3).

## I/O & Edge-Case Matrix

Where each row runs:
- **In process, on a warm stack:** rows 1, 2, 3, 4 (its scan), 5, 7 and 8.
- **Curl rows of the `online-demo` unit's proxied phase, on a fresh flag-on throwaway:** rows 1, 2, 4 (its count), 5 and 6.
- **Playwright cases in `web/e2e-online/busy.spec.ts`, in the unit's browser step:** rows 7 (its live half), 9, 10, 11 and 12.
- **Playwright cases in `web/e2e-online/host-pages.spec.ts`:** rows 14 and 15.
- **Node tests under `web/scripts/`:** rows 13, 16 and 17.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Status busy (AC 1, 6) | Live: the proxied phase reads the HTTP view of the connections, b (Task 0 (a)), and sets `connectionCap` to b + 4 (reserve 2). Then S1 signs in, then S2. In process: a reserve larger than the cap forces busy; no cap means never busy | After S1: `busy:false` and no `X-OcuTalon-Busy`. After S2: `busy:true` and `X-OcuTalon-Busy: 1`, status 200. In process, `Show` sets the header exactly when `Body().busy` is true, and `Body` uses `Busy()` | -- |
| 2 | Splash busy (AC 1, 6) | Live: a fresh jar's `GET /ocutalon/?probe=n` while row 1 is busy, then again after S2 signs out. In process: `Render("splash"\|"show", "")` busy and not busy | Busy: `#ocu-error` is the button's next sibling. It holds the busy text and the README link (href, target, rel, sr-only text). There is no `aria-invalid` and no `disabled`, one `autofocus`, the published values, the splash's exact policy, and the header. Not busy: no `#ocu-error` and no header | -- |
| 3 | Other messages win (AC 1) | In process, busy forced: the wrong-credentials code; state "norole"; state "addressLimit" | The credentials error marks both fields, and there is no header. The no-role text shows. TOOMANY shows. None shows the busy text | -- |
| 4 | No connection taken, no high-water mark (AC 1) | Live: the HTTP view of the connections before and after 5 `/ocutalon/public/status` GETs and 5 splash GETs, with no jar kept. In process: every compiled `OcuTalon.*` method body outside `OcuTalon.Test.*` | The count is unchanged (printed as `MEASURED`). No method body contains `InstanceConnectionsMax` (the needle is built by concatenation, so the test itself does not match) | -- |
| 5 | Post-sign-in refusal (AC 2, 6) | Live: while row 1 is busy (S1 and S2 signed in), S3 signs in proxied with `X-Forwarded-For: <its own address>`; one more does so with a valid resume cookie of S1's row. In process: `AttachFor(1)`, the flag on, proxied, busy forced, with and without a cookie | The answer is 200: the splash with the busy error and `X-OcuTalon-Busy: 1`. It sets no `OcuTalonResume`, and the refused jar's `/ocutalon/api/v1/state` gives 401. The `Session` row count is unchanged and the address has no counter row. The cookie's row is not attached: its `CspSessionId` is unchanged. In process the marker is `$ListBuild("busy")`, and no lock is held afterwards | -- |
| 6 | The boundary and the new session's own connection (AC 2) | Live, as row 1: S2 is the sign-in that brings connections to exactly cap minus reserve | S2 is allowed (the shell and a cookie) and S3 is refused. Task 0 (d) records which `own` made both hold | If S2 is refused or S3 is let in, the row fails, naming the connections read before each |
| 7 | Exempt (AC 2) | In process: busy forced, a request that is not proxied (no proxy set; a remote other than the proxy). Live (`busy.spec.ts` B1, phase 1, where nothing is proxied): a third sign-in over HTTP while busy | Allowed: a new row, a cookie, no marker. B1's third sign-in gets the shell. Each is signed out at once | -- |
| 8 | Busy comes before the resume and the counter (AC 2) | In process: busy forced, proxied, at an address with 5 counter rows; and with a resumable cookie | The marker is "busy" (not "addressLimit"), the counter rows are unchanged (5), and the cookie's row is not attached | -- |
| 9 | A trace link while busy, at the real lowered cap (AC 3, 6) | B1: page P signs in from the splash, and session S2 signs in over HTTP. B1 seeds a turn on P's row (`Fixture.Turn`, R2's way), reads the connections, and sets `connectionCap` so that status is busy with exactly these two sessions. Then a fresh context opens the splash. P types "draft text" into the composer and presses "Open my conversation in Visual Trace" in the Visual Trace menu. Then S2 signs out | Status `busy:true`. The fresh splash shows row 2's error, focused, with the button enabled. After the press: no new page within 3 s, `[data-banner=demoBusy]` shows the busy text and "Install it yourself" (README, new tab), and the composer still holds "draft text". After S2 signs out, the banner clears within 15 s, and the next press opens a new page at the link's trace URL | `connectionCap` is restored in `finally`, then read back |
| 10 | A row's Trace link while status is busy (AC 3) | On a signed-in page with a reply's `app-trace-link` (the seeded turn, or `postTurn` as in O4 if the seeded reply has none), `page.route` answers `/ocutalon/public/status*` with `busy:true`. Then the link is pressed | No new page within 3 s, and the banner shows. The route is removed in `finally` | -- |
| 11 | An API 503 (AC 3, 6) | Signed-in page: `page.route` answers `POST /ocutalon/api/v1/messages` with 503 once. Type "busy check" and press Send. Then answer `/ocutalon/api/v1/events` with 503 for two polls, then remove both routes | After the send, the composer holds "busy check", and no "Not sent", no failed entry and no "Message not sent" announcement appear. The banner shows while the 503s last and clears at the first 2xx poll. Send then posts the text (202), and it appears in the chat | -- |
| 12 | The composer already holds other text (AC 3) | As row 11, but the route holds the POST until the test has typed "newer text", then answers 503 | The composer holds "newer text" (unchanged), and the message stays as "Not sent" with "Retry sending" (today's failure) | -- |
| 13 | The banner is the online demo's only (AC 3) | Node (`banner-view.test.mjs`): `activeBanners` with own `['demoBusy']`, onlineDemo true and false | One `demoBusy` banner, in table order after `unreachable`, with the catalog's text and the README action, when true; none when false. The local suites' 503 cases (`web/e2e/chat/chat.spec.ts`, banners B16) stay green unchanged | -- |
| 14 | The busy page (AC 4) | `docker/busy.html` is served by `page.route` on `http://demo.test/ocutalon/trace/ocutalon/any.csp?probe=1`. Every other request is aborted and recorded. Light and dark (`emulateMedia`) | `lang="en"`, title "Try OcuTalon", the h1 and paragraph texts, the link (href `README_URL`, target `_blank`, rel `noopener noreferrer`, accessible name "Install it yourself (README) (opens in a new tab)") and a 400px card. The body background is `rgb(255, 255, 255)`, and `rgb(17, 25, 43)` in dark. Tab focuses the link with a visible outline. No request but the page | -- |
| 15 | The maintenance page (AC 5) | `docker/maintenance.html` is served for `http://demo.test/ocutalon/`, with the logo files from `logo/web/` for their bare names under `/ocutalon/`. Every other request is aborted, so IRIS is unreachable. Light and dark. Then the route for `/ocutalon/` answers a stand-in page titled "Try OcuTalon" | Title "Resetting · OcuTalon", `lang="en"`, the two texts, a 400px card and the logo rendered 320px wide with `naturalWidth > 0`: the light file in light, the dark file in dark, and only that one. No other request. After the switch, the page is at `http://demo.test/ocutalon/` with the stand-in's title within 15 s | -- |
| 16 | The public-text check of the pages (AC 4, 5) | Node (`host-pages.test.mjs`) over both files | ASCII only and `lang="en"`. The titles, as above. The busy texts equal `PAGE_TEXTS['banner.demoBusy']` split at its first ". ". The link label and both maintenance texts occur word for word in EXPERIENCE.md. The README href equals `links.ts`' `README_URL`. No `<script`, no `style=` and exactly one `<link` (the data: icon). Every `href`, `src`, `srcset` and refresh URL is `README_URL`, `/ocutalon/` or one of the four logo names. No IPv4 or IPv6 literal, no `localhost`, no `host:port`. The refresh is `10; url=/ocutalon/`. `test-boundaries.sh` also scans both files (ASCII, paths, keys) | -- |
| 17 | Busy state logic (AC 3) | Node (`demo-busy.test.mjs`, fake timers) over `DemoBusyWatch` | A 503 makes it busy, and a later 2xx clears it. A busy status makes it busy, schedules a check every 10 s, and a not-busy check clears it. Either cause keeps it busy, and `stop()` cancels the timer. A 2xx does not clear the trace cause | -- |

</intent-contract>

## Code Map

- **`src/ocutalon/cls/OcuTalon/Web/Public/Status.cls`**
  - `Show` :40-45; `Body` :49-59, with the inline busy expression at :54; `IsBusy` :63-68, the existing pure formula that `Busy` extends.
  - The class comment :1-7 must name the header.
- **`src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`**
  - Texts :17-76 (`TOOMANY` :54, `INSTALL` :67, `NEWTAB` :69, `README` :76, `ICONEXTERNAL` :81).
  - `OnLoginPage` :97-172:
    - the state is read and killed at :99-101;
    - the `addressLimit` message at :103-105 is the precedent for "busy";
    - `marked` :106; the error paragraph :147-149;
    - the footer's README link :165-166 becomes the shared private `ReadmeLink()`.
  - It inherits `OnPreHTTP` from Login. The override goes here.
- **`src/ocutalon/cls/OcuTalon/Web/Public/Login.cls`**
  - `OnPreHTTP` :80-86; `Show` :101-112, whose comment at :94-100 lists the states, "busy" to be added; `Message` :118-131; `Icon` :180.
  - The local page's output stays byte-identical (`Test.Web.Splash.TestShowFollowsTheFlag`).
- **`src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls`**
  - `REFUSALKEY` :27. `OnPreDispatch` :62-78 already renders any marker's state: no code change.
  - The class comment :9-11 names only "addressLimit".
- **`src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`**
  - The class comment :8-16; `AttachVisitor` :50-82 (the cookie resume :52-56, `ClientAddress` :58, the counter :61-77); `ClientAddress` :88-94.
- **Read only:**
  - `Data/Public/Settings.cls` `KEYS` :9 (`connectionCap`, `connectionReserve`);
  - `Install/Step/Public.cls:24`: their start variables, defaults 8 and 2. These are Lane A's.
- **`src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`** (footprint extension): the banner entries :275-330; `splash.tooManySessions` :484 (the State Patterns source precedent); `splash.install` :514.
- **`src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`** (footprint extension): the key list near :1036, and `Fixtures` near :1263.
- **Tests to extend:**
  - `Test/Web/Status.cls`: `KEYS` :9 (already saves `connectionCap` and `connectionReserve`), `TestIsBusy` :73, `TestRouteAndAccess` :89-110, `SetAll` :372, `Restore` :383.
  - `Test/Web/Splash.cls`:
    - `TestTexts` :10; `TestTooManySessions` :229-253, the template for the busy test;
    - the fixture `OnBeforeOneTest` :346-361 saves every public key but sets no cap;
    - `Render` :408-451 returns the policy only and needs the busy header too.
  - `Test/Web/SessionEvents.cls`:
    - `OnBeforeOneTest` :28-42 saves four keys, and needs `connectionCap` and `connectionReserve`;
    - `TestLimit` :206-248 is the template; `SignIn` :515; `CounterRows` :539; `SetLimit` :588.
  - `Test/Web/PublicTexts.cls`: the counts at :37 and :77-79, the Splash `compared` block from :142, and `notText` :174-183.
- **`web/src/app/api/envelope.interceptor.ts`** :19-38: the one place that sees every `/ocutalon/api/` answer. A 401 is handled at :32-34. `api-types.ts` :77-84 has `PublicStatus` already.
- **`web/src/app/live/`**
  - `contact-watch.ts` (framework-free, injected timers, `BUSY_STATUS` :28) is the pattern for `demo-busy.ts`.
  - `live-state.ts` is read only (`snapshot` signal; `isBusy` :285-287).
- **`web/src/app/banners/`**
  - `banner-view.ts`: `BannerId` :25-34, `OwnCondition` :37, `BANNERS` :63-73, `OWN_CONDITIONS` :79, and the header comment :1-21 ("nine").
  - `banner-stack.ts`: `input` :168-175 builds `own` from `contact`; `announce` :218-232.
- **`web/src/app/header/header.ts`:** the conversation link :147-162; `pressConversation` :430-436; `closeTrace` :425.
- **`web/src/app/shared/trace-link.ts`** (footprint extension): the anchor :102-112; `press` :164-177, the one handler of every row's Trace link. Its callers are in `chat/` and `rail/` and stay untouched.
- **`web/src/app/chat/`** (footprint extension):
  - `chat-outbox.ts` `post` :71-87 (the announcement at :82);
  - `composer.ts` `send` :86-94, which empties the field before the answer.
  - `scripts/announce-focus-sources.test.mjs` :96-108 (the speakers) and :113 (the composer's one `.focus(`) must stay as they are.
- **The generated catalog** (footprint extensions): `web/src/app/msg/catalog.ts` is generated by `web/scripts/catalog.mjs`. Its `LISTED_KEYS` is at :37-53.
- **Node tests:**
  - `web/scripts/catalog.test.mjs`: `BANNER_KEYS` :28-41, the counts :59-70, and the fixture `BANNERS` :173-186;
  - `web/scripts/banner-view.test.mjs`: nine at :55-62, the onlineDemo rows at :82-83, the closable list at :87;
  - `web/scripts/ux-strings.test.mjs`: `SOURCES.ux` :143, the banner texts :241-243;
  - `web/scripts/contact-watch.test.mjs`: the pattern for the new node tests.
- **`web/src/app/links.ts:5`:** `README_URL`.
- **Host-page styling (read only):**
  - `web/src/signin/signin.css` :18-34 is the layout model: a centred page, a 320px logo, a 400px card with 24px padding.
  - `web/src/signin/splash.css`: the canvas :5-17, the focus ring :40-49, the h1 font stack :58-67, the card :92-98, the field error :203-216, the link :297-307.
  - `SplashAssets.cls`' `CSS` holds the resolved light and dark token values.
- **`logo/web/OcuTalon-Logo-{light,dark}-{640,1280}.png`:** 640x357 and 1280x714 PNGs, already tracked.
- **`web/e2e-online/`:**
  - `support.ts`: `signOutGroup` :24, `signInFromSplash` :45, `sessionRow` :106, `signInOverHttpFrom` :147;
  - `demo-account.spec.ts`: `opensTabStrict` :57-68 (`context.waitForEvent('page')`) and O4 :83-106, which opens online trace links and must stay green;
  - `address-limit.spec.ts`: the gating pattern.
- **`web/e2e/support/`:** `iris.ts` `irisScript` :59; `api.ts` `STATE`/`EVENTS`/`MESSAGES` :14-16, `holdState` :114; `trace.ts` `postTurn` :48.
- **`docker/tests/test-online-demo.sh`:**
  - the header :2-49; `proxy_start` :101; `logout_all` :265; `online_signin` :276; `splash_get` :481; `session_rows` :639; `counter_rows` :642;
  - the browser step :808-843 (`run_e2e` :820-830);
  - the proxied phase :845-959: `set_proxy` :848, the precondition :857-871, row 11 :937-953, and the proxy restore :955-959, the pattern for the cap's restore.
- **Read only, the reasons behind decisions:**
  - `docker/tests/test-boundaries.sh`: `non_ascii` :31 runs `grep` with no `-I` over `scan_files docker ...` :96. Measured during planning: macOS `/usr/bin/grep` prints "Binary file ... matches" for a PNG, so a logo under `docker/` fails the local check.
  - `.dockerignore` is an allow-list, so new `docker/` files never enter the image.
  - `ci/units.sh:65` `IRIS_INPUT` matches top-level `docker/` files.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, on lane C's throwaway; each result is recorded under Verification, as `MEASURED` lines where the unit can print them; any temporary diagnostic is reverted byte-identical):
  - (a) **Baseline.** On the fresh flag-on stack with no session: the value `InstanceConnections()` gives inside an `iris_script`, and the HTTP view of the connections. Find the HTTP view by the flip: set the cap to r + reserve; `/status` busy means the view is r, otherwise r - 1, checked with cap r - 1 + reserve. The unit derives b this way on every run.
  - (b) **One session.** One signed-in curl session raises the HTTP view by 1, and its group sign-out lowers it at once.
  - (c) **Pages take none.** Five `/status` GETs and five splash GETs leave the view unchanged (row 4).
  - (d) **`own`.** Run row 6 with `own` = 1. If S3 is let in, `OnLogin` does not count the new session yet: use `own` = 0 and run again. Record which held.
  - (e) **Popup after the check.** Chromium opens `window.open` after the awaited status check in the press handler (row 9's last step). If it is blocked, the handler opens `about:blank` synchronously before the check and then navigates the window or closes it. Record this under Design Notes; every other Always line stays.
  - (f) **Caching.** Whether two GETs of the same `/ocutalon/public/status` URL, with the cap changed between them, give different answers through the web gateway. This is recorded for Story 16.8's polling. The page adds `?t=<ms>` either way.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls` -- add `banner.demoBusy` with the busy text, slots `{}` and source "EXPERIENCE State Patterns / Demo busy", next to `banner.reconnecting`. Update the counts, the key list and a `Fixtures` entry -- rows 2, 13, 16.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Public/Status.cls`:
  - `Parameter BUSYHEADER = "X-OcuTalon-Busy";`;
  - `Busy(own As %Integer = 0) As %Boolean` over `IsBusy`, which `Body` calls;
  - `Show` sets the header to "1" when the body's busy is true;
  - the comment states the marker and `Busy(own)` -- rows 1, 4.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Public/Splash.cls`:
  - `Parameter BUSY` (the busy text);
  - an `OnPreHTTP` override: `##super()`, then the busy decision of Always, then the header;
  - `OnLoginPage` renders state "busy" as Always says, with `marked` 0;
  - a private `ReadmeLink()`, used by the footer and the error;
  - the class comment names the state -- rows 2, 3.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls` and `Shell.cls` -- comments only:
  - `Show`'s list of states, and Shell's refusal line, name "busy";
  - no code line changes -- rows 3, 5.
- [ ] `web/src/signin/splash.css`, then `npm --prefix web run tokens` -- only if the link inside `#ocu-error` needs a rule beyond `.link`. Never edit `SplashAssets.cls` by hand; `SignInAssets.cls` stays byte-identical -- row 2.
- [ ] `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls`:
  - `AttachVisitor` in the order of Always: the address, the busy refusal through `Status.Busy(own)`, then the resume and the counter, which are otherwise unchanged;
  - the class comment states the busy refusal and its exemption -- rows 5 to 8.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls`:
  - `TestBusyHeader`: `Show` with busy forced (reserve 9, cap 1) and with no cap, checking the header and the body;
  - `TestBusyOwn`: with the cap set to the live count plus the reserve, `Busy(0)` is 1 and `Busy(1)` is 0;
  - `TestNoHighWaterMark` (row 4's scan);
  - `TestRouteAndAccess` also asserts no header when not busy -- rows 1, 4.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/Splash.cls`:
  - the fixture sets `connectionCap` "" (never busy), so the existing cases do not depend on the stack;
  - `Render` gains an `Output busyHeader`;
  - `TestTexts` gains `BUSY`;
  - a new `TestDemoBusy` covers rows 2 and 3, `BUSY` equal to the catalog's `banner.demoBusy`, and the link's markup equal to the footer's -- rows 2, 3.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls`:
  - `OnBeforeOneTest` also saves `connectionCap` and `connectionReserve` and sets the cap "";
  - new `TestBusyRefusal` (row 5 in process, including the cookie case and that no lock is left), `TestBusyExempt` (row 7) and `TestBusyBeforeTheCounter` (row 8) -- rows 5, 7, 8.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` -- `Splash.BUSY` is compared with `banner.demoBusy` (37), and `Status.BUSYHEADER` goes under `notText` (27). Each count moves by exactly one -- row 2.
- [ ] `web/src/app/live/demo-busy.ts` (new, framework-free, erasable syntax) -- `DemoBusyWatch`:
  - the two causes, `apiAnswered(status)`, `statusChecked(busy)`, `busy`, `stop()`;
  - the 10 s re-check through injected timers, like `ContactWatch`;
  - exports `DEMO_BUSY_RECHECK_MS` -- row 17.
- [ ] `web/src/app/live/demo-busy-state.ts` (new) -- the root service `DemoBusyState`:
  - `busy` signal;
  - `apiAnswered(status)`;
  - `openTrace(url)`: the online demo's trace check of Always, through `HttpClient` with a 5 s timeout and `?t=`;
  - the re-check fetch. It announces nothing -- rows 9, 10.
- [ ] `web/src/app/api/envelope.interceptor.ts` -- every `/ocutalon/api/` answer reports its status to `DemoBusyState.apiAnswered`: a 503 error, and a 2xx response. The 401 path is unchanged -- row 11.
- [ ] `web/src/app/banners/banner-view.ts` and `banner-stack.ts`:
  - the `demoBusy` row after `unreachable` as Always says, `OwnCondition` and `OWN_CONDITIONS` extended, the header comment says ten;
  - the stack adds `'demoBusy'` to `own` while `DemoBusyState.busy()` -- rows 9 to 13.
- [ ] `web/src/app/header/header.ts` -- `pressConversation`: with a turn on the online demo, `preventDefault`, `closeTrace()`, `DemoBusyState.openTrace(url)`. Otherwise as today -- row 9.
- [ ] `web/src/app/shared/trace-link.ts` (footprint extension) -- `press`: on the online demo, with no help needed, `preventDefault` and `openTrace(url())`. The help path and the local path are unchanged -- row 10.
- [ ] `web/src/app/chat/chat-outbox.ts` and `composer.ts` (footprint extensions) -- the online demo's 503 rule of Always:
  - the outbox offers a typed message's text back, and the composer takes it only while its field is empty, without a `.focus(` call; otherwise the entry is marked failed as today;
  - a guide message leaves;
  - no announcement for a returned or removed entry -- rows 11, 12.
- [ ] `web/scripts/catalog.mjs`, then `npm --prefix web run catalog` (footprint extensions; `web/src/app/msg/catalog.ts` is regenerated, never hand-edited) -- `LISTED_KEYS` gains `banner.demoBusy` after `banner.reconnecting` -- row 13.
- [ ] `web/scripts/catalog.test.mjs`, `banner-view.test.mjs` and `ux-strings.test.mjs` (footprint extensions):
  - `catalog.test.mjs`: `BANNER_KEYS` and the fixture `BANNERS` gain the key, and the counts become 13 and 28;
  - `banner-view.test.mjs`: ten banners with the order, the onlineDemo rows and the closable list updated, plus row 13's cases;
  - `ux-strings.test.mjs`: `SOURCES.ux` gains the busy text -- row 13.
- [ ] `web/scripts/demo-busy.test.mjs` (new, footprint extension) -- row 17.
- [ ] `docker/busy.html` and `docker/maintenance.html` (new) -- the host pages of Always. Each page's header comment says:
  - what serves it (the demo host's proxy);
  - for the maintenance page, the four logo files of `logo/web/` to serve beside it;
  - that it must stay ASCII with no external file -- rows 14 to 16.
- [ ] `web/scripts/host-pages.test.mjs` (new, footprint extension) -- row 16.
- [ ] `web/e2e-online/host-pages.spec.ts` (new) -- H1 (row 14) and H2 (row 15), on `http://demo.test/`. No IRIS request; the files are read with node `fs` relative to the spec -- rows 14, 15.
- [ ] `web/e2e-online/busy.spec.ts` (new):
  - B1 (rows 7 and 9), B2 (rows 11 and 12) and B3 (row 10);
  - the cases may share one signed-in page;
  - B1 sets `connectionCap` through `irisScript` from a reading at run time, as Task 0 (a) found, and restores it in `finally`;
  - each case signs out every session it opened -- rows 7, 9 to 12.
- [ ] `web/e2e-online/support.ts` -- add:
  - `httpConnections()`: the HTTP view of the connections, by Task 0 (a)'s rule;
  - `setPublic(key, value)` and `publicValue(key)` through `irisScript`;
  - `DEMO_BUSY_TEXT` -- rows 9, 10.
- [ ] `docker/tests/test-online-demo.sh`:
  - the header names the new checks;
  - after the browser step, `connectionCap` reads back 8 and `connectionReserve` 2, and is put back otherwise, which fails the row;
  - in the proxied phase, after row 11: rows 1, 2, 4 (the count), 5 and 6 with addresses of their own;
  - `connectionCap` is restored and read back on every path, beside the proxy's restore;
  - Task 0's `MEASURED` lines -- rows 1, 2, 4 to 6.

**Acceptance Criteria:**
- Given the connection cap (8) and reserve (2) in the public settings, when `$SYSTEM.License.InstanceConnections()` reaches the cap minus the reserve, then:
  - `/ocutalon/public/status` reports busy;
  - the splash shows the busy field error with "Install it yourself (README)" under **Sign in and start**, which stays enabled and marks no field;
  - neither check takes a licence connection, and nothing reads `InstanceConnectionsMax()`.

  Rows 1 to 4 hold.
- Given a visitor who signs in through the proxy while connections exceed the cap minus the reserve, when the post-sign-in check runs, then:
  - it ends the new CSP session and returns to the splash with the busy error;
  - it creates no OcuTalon session and counts nothing toward the per-address limit;
  - a sign-in that doesn't come through the proxy is exempt.

  Rows 5 to 8 hold.
- Given a signed-in page on the online demo, when the visitor opens a trace link or "Open my conversation in Visual Trace" while status reports busy, or any API call answers HTTP 503, then:
  - the page shows the busy text instead of opening the trace window or showing an error;
  - it keeps what the visitor typed;
  - it works normally again once a place is free.

  Rows 9 to 13 and 17 hold.
- Given `docker/busy.html`, which the demo host's proxy serves in place of IRIS's 503 under `/ocutalon/` except `/ocutalon/api/`, when a browser opens it, then it shows the busy text and the README link on the splash canvas, with its own inline styles, loads nothing from IRIS, sets `lang="en"`, passes the public-text check and names no infrastructure detail. Rows 14 and 16 hold.
- Given `docker/maintenance.html`, when a browser opens it with IRIS unreachable, then it shows the 320px logo and the 400px card with both texts under "Resetting · OcuTalon", with only its inline styles and the logo files beside it, loads nothing from IRIS, reloads itself until the demo answers and then lands on the splash, sets `lang="en"`, and passes the public-text check with no infrastructure detail. Rows 15 and 16 hold.
- Given the busy answers IRIS renders (the splash's busy state, a busy status, the post-sign-in refusal), when any is sent, then it carries `X-OcuTalon-Busy: 1`. A test lowers the cap so that two signed-in test sessions make the demo busy, and checks the status answer, the splash error, the refusal, the header on each, the trace-window check and the page's handling of a 503. Rows 1, 2, 5, 9 and 11 hold.

## Spec Change Log

## Review Triage Log

### 2026-10-26 -- Review pass
- verdicts: 38 findings -- high 3, medium 7, low 23, false 4, maybe-false 1
- findings:
  - `[high]` `[defer]` (Blind) A signed-in CSP session does not raise InstanceConnections() on the throwaway, so the busy states never move through visitors and nothing tests a real host that counts sessions -- measured in Task 0 (b); the code follows AD-13/the spec, the premise is the architecture's and outside this change; recorded as the deferred high item for the lead (a real-host measurement or a counter fallback is a product call)
  - `[medium]` `[defer]` (Blind) Rows 5 and 6 run only at degenerate cap/reserve values (cap below reserve), and OWNCONNECTIONS = 1 is unverified -- same root cause as the premise row: the sessions add 0 here, so the lever is the cap; folded into the deferred item
  - `[low]` `[reject]` (Blind) Row 1 is circular (its thresholds come from the flip that uses IsBusy) -- TestIsBusy pins >= with literals and the recorded mutation went red; fix would add complexity for a test already pinned
  - `[low]` `[patch]` (Blind) Several new tests have no mutation line -- lines added for TestBusyOwn, TestBusyRefusal, TestBusyBeforeTheCounter, B3, B3b and B2's second half
  - `[low]` `[reject]` (Blind) DemoBusyWatch.stop() is never called -- SessionGate.onSignedOut does location.replace, so the page and its timer are discarded on every sign-out; no stale state survives
  - `[low]` `[reject]` (Blind) window.open runs after an awaited fetch, with no fallback in other browsers -- spec-bound: Task 0 (e) measured Chromium and the spec fixes the fallback only for that case
  - `[medium]` `[reject]` (Blind) maintenance.html's relative logo names break at a deep path -- by-design: the AC names the logo by bare file name beside the page, and Story 29.3 is told where to serve them (DW-240); noted under residual risks
  - `[low]` `[patch]` (Blind) SessionEvents class comment says a valid resume cookie is never refused -- comment now says never counted or refused at the address limit, the busy refusal coming first
  - `[low]` `[patch]` (Blind) busy.html carries a dead .logo rule -- rule removed; host-pages tests assert the rule only on the maintenance page
  - `[low]` `[reject]` (Blind) Splash (own 0) and the hook (own 1) disagree by one connection at the boundary -- spec-bound: the AC has the splash read Busy() and the hook Busy(own); row 6 pins it
  - `[low]` `[reject]` (Edge) window.open after the await may be blocked outside Chromium -- duplicate of the Blind row; spec-bound
  - `[low]` `[reject]` (Edge) A 503 or HTML answer to the status check is read as no answer -- by-design: the spec opens the window on a failed check because the proxy's busy page covers a full demo
  - `[low]` `[reject]` (Edge) The sign-in help path opens unguarded; modified clicks are intercepted -- spec-bound: the help path stays as it is and middle-click is not taken over; a modified click still opens a window
  - `[false]` `[reject]` (Edge) A press before the snapshot loads skips the check -- trace links and the conversation link render only from loaded payloads, so the snapshot exists when they can be pressed
  - `[low]` `[reject]` (Edge) stop() never called -- duplicate; the sign-out replaces the page
  - `[low]` `[reject]` (Edge) No in-flight guard on a double press; an older answer can re-raise the banner -- a double click on an anchor opened two tabs before this change; a busy flip between two answers inside milliseconds is not a user-reachable case
  - `[medium]` `[reject]` (Edge) maintenance.html logo at a deep path -- duplicate of the Blind row; by-design
  - `[low]` `[reject]` (Edge) Two proxied sign-ins at the boundary can both pass -- by-design: Design Notes decide no lock and the reserve absorbs one
  - `[low]` `[patch]` (Edge) The unit's S2 cookie is not asserted non-empty, so the cookie sign-in could be vacuous -- row 5 now fails when S2 gave no resume cookie
  - `[low]` `[patch]` (Edge) drop_session runs its SQL with an empty epoch when a sign-in failed -- drop_session returns at once for an empty epoch
  - `[high]` `[defer]` (Edge) Tests do not prove that sessions drive busy (AC 6 wording) -- duplicate of the premise row; folded into the deferred item
  - `[maybe-false]` `[defer]` (Edge) OWNCONNECTIONS = 1 may under- or over-count by one on a host that counts sessions -- cannot be settled without a host that counts sessions; folded into the deferred item
  - `[low]` `[reject]` (Edge) Row 1's mutation went red at the flip, not at row 1 -- duplicate of the Blind row
  - `[medium]` `[patch]` (Verification) The fail-open rule (a status check that fails opens the window) has no test -- B3b added (a non-JSON status answer opens the tab, no banner) with a mutation line
  - `[medium]` `[defer]` (Verification) The guide-prompt branch of the 503 rule has no test -- no page control calls ChatOutbox.send with fromGuide true yet (the caller is Epic 4's guide); a test needs that caller
  - `[medium]` `[defer]` (Verification) The live no-licence-connection check cannot fail on this stack -- the view is 0 whatever the pages do; a Set-Cookie assertion cannot be added without measuring whether the login page sets a CSP cookie; folded into the premise item, with TestNoHighWaterMark as the falsifiable pin
  - `[low]` `[patch]` (Verification) Pinning tests with no mutation line -- same as the Blind row: lines added
  - `[low]` `[reject]` (Verification) Row 1 is red only by accident -- duplicate
  - `[low]` `[reject]` (Verification) TestNoHighWaterMark's control is a tautology -- the recorded mutation (Busy reads InstanceConnectionsMax) turns the test red, so the scan reads bodies
  - `[high]` `[defer]` (Verification) Live busy rows are driven by the cap, not by sessions -- duplicate of the premise row
  - `[low]` `[reject]` (Verification) TestBusyOwn reads the count one statement before it asserts -- the count changes only by this process's own work on the warm stack; not user-reachable
  - `[low]` `[reject]` (Verification) H2 asserts the exact served list while the 10 s refresh runs -- the assertion runs within a second of load; a 10 s stall of the case is not expected
  - `[low]` `[reject]` (Verification) Source-text assertions of host-pages.test.mjs match wording only -- H1 and H2 run the behaviour; the node test pins the public-text rules
  - `[false]` `[reject]` (Verification) The unit skips the busy block when proxied_ok is not 1 -- the earlier phase has already failed the unit in that case
  - `[false]` `[reject]` (Verification) The flip is an inference between r and r-1 -- the unit fails loudly when neither holds
  - `[medium]` `[defer]` (Intent) The tests exercise the cap lever, not the real session-to-connection count -- descriptive; duplicate of the premise row
  - `[low]` `[reject]` (Intent) The help popover's Open Visual Trace opens the link without the status check -- spec-bound: the help path is unchanged
  - `[false]` `[reject]` (Intent) Narrower divergences (B1's splash and status made busy by the cap) -- descriptive; the live rows are assigned to the surfaces the matrix names

## Design Notes

**Architecture decisions:**
- **AD-13** governs:
  - busy before sign-in (`/status` and the login page, with no connection taken; the cap is a public setting, never `InstanceConnectionsMax()`);
  - the post-sign-in check, which ends a proxied session past the reserve, with the probe exempt;
  - the trace check before a trace window opens;
  - the Angular client showing busy for an API 503;
  - the login page rendering its busy state on the server, inline styles, no `style=`, the hashed policy, and `%CSP.Login`'s form contract kept.
- **AD-25:**
  - the proxy serves the busy page under `/ocutalon/` except `/ocutalon/api/`, and the maintenance page during resets;
  - this repository ships both pages in `docker/`;
  - the marker header that the proxy counts;
  - the probe connects directly, so it is exempt.
- **AD-3:** `Status`, `Splash`, `Login` and `Shell` stay in `OCUTALON_PUBLIC` and reference only `%CSP`, dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status` and the two public packages (`Test.Web.Status`' scan). They keep their own copies of the texts, which `PublicTexts` compares with the catalog.
- **AD-19:** the cap and the reserve are public settings, read through `Public.Settings`.
- **AD-4:** a busy refusal creates and attaches no session, so the resume cookie is never consulted.
- **AD-32 and the conventions:**
  - **"Text OcuTalon sends":** the banner text comes from the catalog through the generated `msg/catalog.ts`.
  - **"Announcements and focus":** only the banner stack announces, and nothing moves focus.
  - **"README link":** one address.
  - **"Shared look outside Angular":** the maintenance page is one self-contained HTML file. The AC's logo files beside it are its only companions.
- **AD-22, AD-29, AD-33:** throwaways only, Lane B's files.
- No AC contradicts an AD's Rule. No NFR is unmeasurable: NFR-23's "busy, never an error page" is observed by rows 2, 9, 11 and 14.

**Decided in implement (Task 0 (b)):**
- **The cap is the lever, not the sessions.** A CSP session does not change `InstanceConnections()` on the throwaway (Task 0 results), so the matrix rows that bring the connections to the cap with a third and fourth sign-in reach the same boundary with `connectionCap` instead, derived from the HTTP view b at run time:
  - the status is busy at cap b + reserve and not busy at b + reserve + 1 (row 1);
  - at cap b + reserve a proxied sign-in is allowed, because `Busy(own)` leaves out `OWNCONNECTIONS` (row 6), and at cap b - own + reserve it is refused with the busy splash (rows 5 and 6);
  - B1 sets the cap to b + reserve with P and S2 signed in, and "a place is free" is a cap one higher, set after S2 signs out.
  The unit asserts that two sessions leave the view at b, so a change in IRIS's behaviour turns it red. Task 0 (e)'s fallback (an `about:blank` window opened before the check) was not needed.

**Decided in-stage:**
- **The page's busy handling is the online demo's only.** On a local install the cap is unset, so status is never busy, and "The demo is busy" is the demo's own text. A local 503 and a local trace link behave as today, which the local suites pin.
- **One presentation on the signed-in page: a "Demo busy" banner.** The UX quotes the text but places it only on the splash and the host page. A banner is the page's one page-wide slot, so it serves both causes:
  - a trace press, where the link's own row may be anywhere;
  - a poll's 503, which has no control to sit beside.
  It clears with its cause ("works normally again"), uses the catalog's text and the existing "Install it yourself" README action of the online demo's other banners, and is announced once by the stack. It adds a tenth row to the banner table: see For the lead.
- **One catalog key, `banner.demoBusy`,** serves the splash's `BUSY` (compared by `PublicTexts`), the page banner (through `LISTED_KEYS`), and the host page's text (row 16). There are no two keys with one text.
- **The trace check runs at the press,** as AD-13 says ("before opening a trace window, the page checks /status").
  - A cached poll could be stale, and adds steady load.
  - The window opens with `window.open` after the answer. Task 0 (e) checks Chromium, and has a fallback.
  - A failed check opens the window (fail open): at the real cap, the proxy's busy page answers in that window anyway.
  - The check runs on the online demo only. Locally the cap is unset, so status is never busy, and the local behaviour stays the anchor's own.
  - Middle-click, which fires no `click`, is not taken over. The proxy's busy page covers it.
- **The 503 rule for a sent message.** "Instead of showing an error" and "keeps what the visitor typed" together mean the text goes back to the composer, with no "Not sent".
  - Only an empty composer takes it, so newer typing is never overwritten. In that rare case the message keeps today's failure state, and the text is still kept.
  - A guide prompt has no typed text, so its message just leaves.
- **A 503 on the first `/state` keeps "Couldn't load your session." with Retry.** Before the snapshot, the page cannot tell the online demo from a local install, and a local install must not show "The demo is busy". Retry is how it works again. The AC's "signed-in page" is read as the loaded page.
- **The splash.**
  - Busy is shown only where no other message is: a wrong password's error still marks the fields, and the no-role text still wins.
  - The error keeps `autofocus`, like every splash error.
  - The decision sits in `OnPreHTTP`, which sets the header, so the page and its header always agree.
- **The busy check comes before the resume.** A resume also takes a new CSP session and its licence connection, so the reserve must refuse it too. A busy refusal counts nothing, because the counter comes later.
- **No lock around the busy check.** Two sign-ins at the same instant can both pass at the boundary. The reserve absorbs one, and a lock would serialise every sign-in of the demo.
- **The host pages.**
  - Top-level `docker/busy.html` and `docker/maintenance.html`, inside the footprint glob. `IRIS_INPUT` runs every IRIS group when they change, the `image` group (the `online-demo` unit) included.
  - The logos are not copied into `docker/`. A PNG there fails `test-boundaries.sh`' ASCII rule under macOS grep (measured in planning). One source of the logos is also Rule 2's choice.
  - The busy page has no image, so that it works at any path.
  - The busy page's title is "Try OcuTalon", the splash's fixed title, in whose place it mostly stands. "Demo busy · OcuTalon" would be a new text.
  - Each page has one heading: the first sentence of its text. The busy text splits at its first ". ", and its whitespace-normalised text is unchanged.
  - The maintenance page reloads itself by `<meta http-equiv="refresh" content="10; url=/ocutalon/">`. This is the AC's "reloads itself", with no script. It lands on the splash because it reloads at the splash's address. Ten seconds matches the page's other retry cadence.
  - `<link rel="icon" href="data:,">` stops the browser asking any server for an icon.
- **`Status.#BUSYHEADER`** is one parameter, read by `Status` and `Splash`, so the header name is written once.

**Integration ACs:**
- `Shell.OnPreDispatch` consumes the "busy" refusal that `OnLogin` records, and produces the splash's busy error with the header (row 5, live).
- `BannerStack` consumes `DemoBusyState.busy`, and produces the `demoBusy` banner (rows 9 and 11).
- `TraceLink` and `Header` consume `DemoBusyState.openTrace`: no window while busy, and a window once free (rows 9 and 10).
- `ChatOutbox` and `Composer` consume the interceptor's 503, and the text returns to the composer (row 11).
- Outside the repository, the first consumer of the two pages and the header is Story 29.3 (the proxy).

**Consumes:**
- Story 0.5: `Status` and `IsBusy`.
- Story 3.8: the `Public` step's cap and reserve.
- Story 16.2: the splash, `#ocu-error`, the footer link, `SplashAssets` and `tokens.mjs`.
- Story 16.3: the hook, `ClientAddress`, `REFUSALKEY` and `Shell`'s marker path, the unit's proxied phase, `online_signin`, `counter_rows` and `signInOverHttpFrom`.
- Story 2.10's banner stack, 2.9 and 2.13's trace links, 2.5's outbox and composer, and 2.11's contact watch (read only).

**Consumed-by:**
- **16.6:** the probe classifies `busy` from a 503 or a busy status. It may also read `X-OcuTalon-Busy`, and its direct sign-ins are exempt from the refusal.
- **16.8:** the resetting view reuses the maintenance page's logo, texts and tab title. Task 0 (f) tells it whether its status poll needs a unique query.
- **29.3 (outward):**
  - the proxy serves `docker/busy.html` for IRIS 503s outside `/ocutalon/api/`, and `docker/maintenance.html` during resets, with the four logo files where the page's relative names resolve (`/ocutalon/OcuTalon-Logo-*.png` when it is served for `/ocutalon/`);
  - it counts `X-OcuTalon-Busy`.
- **16.4:** the refusal marker path and the splash states.

**Rule 2 (extend, don't copy):**
- **Extensions.**
  - `Busy` extends `IsBusy`, and `Body` calls it.
  - The splash's busy error follows `addressLimit`, and its link is the footer's, through the shared `ReadmeLink()`.
  - The refusal reuses `REFUSALKEY` and `Shell`'s marker path.
  - `DemoBusyWatch` follows `ContactWatch`'s injected-timer pattern.
  - The banner row reuses `bannerAction.installYourself`.
  - The specs reuse `signInFromSplash`, `signOutGroup`, `signInOverHttpFrom`, `irisScript`, `Fixture.Turn`, `postTurn` and `opensTabStrict`'s `context.waitForEvent('page')`.
  - The unit reuses `online_signin`, `logout_all`, `counter_rows`, `session_rows` and `set_proxy`'s restore pattern.
- **Copies, with reasons.**
  - The host pages' CSS restates the splash's resolved token values. Pages that the proxy serves cannot load IRIS's assets, and `tokens.mjs` has no static-page output (`web/scripts/tokens.mjs` is shared tooling). Row 14 pins the canvas values, and row 16 pins the link.

**Footprint extensions** (outside the stated footprint, on no contended list):
- `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls`: one key, as in Stories 16.2 and 16.3;
- `web/src/app/shared/trace-link.ts`;
- `web/src/app/chat/{chat-outbox,composer}.ts`;
- `web/src/app/msg/catalog.ts` (generated);
- `web/scripts/{catalog.mjs,catalog.test.mjs,banner-view.test.mjs,ux-strings.test.mjs}`, and the new `web/scripts/{demo-busy,host-pages}.test.mjs`.

Everything else is inside the footprint: `Web/Public/**`, `Web/SessionEvents.cls`, `Test/Web/**`, `web/src/signin/**`, `web/src/app/{live,api,banners,header}/**`, `web/e2e-online/**`, `docker/{busy,maintenance}.html` and `docker/tests/test-online-demo.sh`.

**For the lead:**
- **The banner table gains a tenth row, `demoBusy`.** EXPERIENCE's Status banners table and UX-DR100 name nine. The text is the UX's own (State Patterns › Demo busy), so no new text is introduced. The placement is the decision above. If it is ruled otherwise, the change stays inside `banners/` and the catalog's listing.
- **The busy page's tab title** is "Try OcuTalon", a fixed text. "Demo busy · OcuTalon" would need the owner's text approval.
- **A 503 on the first `/state`** keeps the load failure (Decided in-stage), which reads "any API call" as calls of the loaded page.
- **DW-220.** The unit grows by about 40 to 60 s locally (inference: about 8 curl and `iris_script` calls in the proxied phase, B1's 15 s re-check wait, and H2's 10 s refresh). Record the measured time.
- **Integrate-forward.** These are union-merge points with Epic 4: the catalog counts, `LISTED_KEYS`, `catalog.ts`, `catalog.test.mjs` and `banner-view.ts`.

**Ledger inbox:** none.

**Lead spec gate (2026-10-26, runner C):**
- The tenth banner ("Demo busy", the UX's own busy text) is accepted as a veto ruling (U-88): the UX is silent on the signed-in page, and the banner stack is the page's existing place for page-wide state.
- The busy page's tab title reuses "Try OcuTalon" (no new public text); a 503 on the first `/state` keeps today's "Couldn't load your session." (the page cannot tell the online demo before it loads) (decide).
- The logos stay in `logo/web/`; DW-240 routes "serve them beside `docker/maintenance.html`" to Story 29.3 (the orchestrator writes the bullet after the merge).
- Footprint extensions accepted (none contended): `web/src/app/shared/trace-link.ts`, `web/src/app/chat/{chat-outbox,composer}.ts`, `Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls`, the generated `web/src/app/msg/catalog.ts`, the named `web/scripts/*` tests.
- Record the `online-demo` unit's measured time under Verification (DW-220).

## Verification

**Targets and variables:**
- Every command runs from the worktree root, in the foreground with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- Every `ci/iris.sh` and `ci/warm.sh` call carries lane C's three variables, written out below for the implement stage. QA and review use their own stage names and tags:
  - implement `e16s5i` and `e16s5iw`;
  - QA `e16s5q` and `e16s5qw`;
  - review `e16s5r` and `e16s5rw`.
- The flag-on and lowered-cap checks run only in the `online-demo` unit's throwaway compose project of lane C (`ocutalon-<label>-e16s5i-<epoch>-<pid>`), never on `ocutalon-slot-c`.
- Each stage tears down only its own tags.
- Run `ci/iris.sh build` before every browser run that should see a changed spec, page or asset. A WebKit floor flake (DW-198) gets one rerun.

**Commands:**
- (loop) `npm --prefix web run tokens` -- `git diff --stat -- src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls` shows nothing.
- (loop) `npm --prefix web run catalog` -- writes `web/src/app/msg/catalog.ts`.
- (loop) `npm --prefix web test` -- every node test passes, among them `catalog`, `banner-view`, `ux-strings`, `announce-focus-sources`, `playwright-projects`, `demo-busy` and `host-pages`.
- (loop) `npm --prefix web run lint` -- `tsc` passes over `e2e/` and `e2e-online/`.
- (loop) `bash docker/tests/test-web-build.sh` -- the build, with `tokens.mjs --check` and `catalog.mjs --check`, passes and the tree stays clean.
- (loop) `bash ci/checks.sh` -- every block passes. `boundaries` scans `docker/busy.html` and `docker/maintenance.html`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5iw bash ci/warm.sh up` -- once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s5iw bash ci/iris.sh class <Class>` -- one call per class, each printing `CLASS ... passed` after a `WARM reloaded` line. The classes are `OcuTalon.Test.Web.Status`, `OcuTalon.Test.Web.Splash`, `OcuTalon.Test.Web.SessionEvents`, `OcuTalon.Test.Web.PublicTexts`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Web.SignIn` and `OcuTalon.Test.Web.Api`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5i bash ci/iris.sh build` -- before each `live` run.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5i bash ci/iris.sh live online-demo` -- PASS:
  - Stories 16.1 to 16.3's rows;
  - rows 1, 2, 4, 5 and 6, and the cap's read-back;
  - B1, B2, B3, H1 and H2;
  - Task 0's `MEASURED` lines.

  Record its time (DW-220): Story 16.3 measured 195 to 219 s, and this story expects about 240 to 280 s, inside the 540 s deadline.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5i bash ci/iris.sh live sign-in` -- PASS, unchanged: the local page's 503 cases and trace links (row 13's local half).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5i bash ci/iris.sh shard lane-b` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5i bash ci/iris.sh shard lane-a` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-c && pwd)" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s5i bash ci/iris.sh teardown` -- nothing tagged `e16s5i` is left. `ci/warm.sh down` has already removed `e16s5iw`.
- The install, production, floor and demo-path units are left to CI.

**Task 0 results** (implement stage, `online-demo` unit on lane C's throwaway, build 154, Community key; the unit's `MEASURED` lines unless marked):
- (a) MEASURED: with no session `InstanceConnections()` in an `iris_script` reads 1 (the script's own process), and the HTTP view of the connections, found by the flip, is 0 (the status's count).
- (b) MEASURED: a signed-in curl session does not raise the HTTP view. With one signed-in session the script reads 1 and the view is 0; with two (S1 and S2) 1 and 0; B1 read the view 0 with P (browser) and S2 signed in. The group sign-out has nothing to lower. The premise "a session raises the view by 1" does not hold on this stack. Also MEASURED by hand on the warm stack (flag off, the instance's own web server, a test user): the count stays 1 after a sign-in, after `/state`, over keep-alive connections, with a second session and after both sign-outs; `ShowSummary` reads 1 licence unit and 1 connection while a session is open, and `UserList` shows no CSP user. (inference) The demo host may count sessions, which this stack cannot show.
- (c) MEASURED: five `/status` GETs and five splash GETs on no jar leave the view at 0 (before 0).
- (d) MEASURED: `OWNCONNECTIONS` = 1 holds at the lever. With the view at 0 the status is busy at cap 2 (b + reserve) and a proxied sign-in is allowed there (the shell, a cookie, one counter row), and at cap 1 (b - own + reserve) it is refused with the busy splash. (inference) Whether `OnLogin` counts the new session itself is not measurable here, because a session adds 0; 1 stays the spec's default.
- (e) MEASURED (`busy.spec.ts` B1, Desktop Chrome): `window.open` called after the awaited status check opened the trace window (`context.waitForEvent('page')` received the page at the turn's trace URL); no popup block. The fallback is not needed.
- (f) MEASURED: two GETs of the same `/ocutalon/public/status?probe=...` URL with the cap changed between them answered busy=true and then busy=false: the web gateway does not cache the answer. Story 16.8's poll needs no unique query for the gateway's sake (a browser or the proxy may still cache; the page adds `?t=` either way).
- DW-220, MEASURED: the `online-demo` unit takes 249 s locally with this story (248 s on the earlier run, 246 to 250 s on the mutation runs), against Story 16.3's 195 to 219 s: about 30 to 54 s more.

**Shared surfaces:**
- **The public `connectionCap`.** B1, the proxied phase and the in-process tests lower it, then restore it and read it back. Every splash and status test of Stories 16.1 to 16.3 assumes the start value 8, with reserve 2.
- **The banner catalog** goes from nine rows to ten: `banner-view.test.mjs`, `catalog.test.mjs` (`BANNER_KEYS`, the counts, the fixtures), `ux-strings.test.mjs` `SOURCES`, and any local banner spec that counts the table.
- **The catalog's counts:** `Test.Msg.Catalog` and `PublicTexts`' counts.
- **`SplashAssets` and the splash policy's hashes,** if `splash.css` changes.
- **The online trace links,** which now open through the status check and `window.open`. `demo-account.spec.ts` O4 must stay green.
- **The local suites,** which stay unchanged: `web/e2e/chat/chat.spec.ts`' 503 cases and banners B16. The flag-off path is untouched.
- **The `online-demo` unit's browser step** runs two more specs, one of which lowers the cap.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19). Each mutation is applied temporarily, observed red, then reverted with the tree byte-identical. A live mutation needs a fresh `live online-demo`, with `ci/iris.sh build` first for a web or page change.

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | the unit's row 1 | `IsBusy` compares with `>` instead of `>=` |
| AC 1 | `Test.Web.Splash.TestDemoBusy` | Splash's `OnPreHTTP` skips the busy decision |
| AC 1 | `Test.Web.Status.TestNoHighWaterMark` | `Busy` reads `InstanceConnectionsMax()` |
| AC 2 | the unit's row 5 | `AttachVisitor` checks busy after the counter |
| AC 2 | the unit's row 6 | `Busy(own)` is called with `own` 0 (or 1, the other way from Task 0 (d)) |
| AC 2 | `Test.Web.SessionEvents.TestBusyExempt` | the busy check ignores `proxied` |
| AC 3 | `busy.spec.ts` B1 | `pressConversation` skips `openTrace` |
| AC 3 | `busy.spec.ts` B2 | the outbox marks a 503 as failed on the online demo too |
| AC 3 | `demo-busy.test.mjs` | `DemoBusyWatch` never re-checks |
| AC 3 | `banner-view.test.mjs` (row 13) | the `demoBusy` row drops `onlineDemo: true` |
| AC 4 | `host-pages.spec.ts` H1 | `busy.html` links a stylesheet at `/ocutalon/x.css` |
| AC 5 | `host-pages.spec.ts` H2 | the refresh element is removed |
| AC 4, 5 | `host-pages.test.mjs` | `maintenance.html` names an address (`http://203.0.113.9/`) |
| AC 6 | the unit's rows 2 and 5 | Splash's `OnPreHTTP` sets no header |
| AC 6 | `Test.Web.Status.TestBusyHeader` | `Show` sets no header |

**Mutation record:** the stage that adds or changes each pinning test writes its `mutation:` line here. Each mutation was applied from a backup, observed red and reverted; the tree was checked byte-identical by SHA-256 of every touched file and `git status --short`.
- mutation: the unit's row 1 -- `IsBusy` compares with `>` instead of `>=` -- red: the unit failed at Task 0 (a)'s flip ("the HTTP view of the connections could not be found by the flip"), before row 1, which is derived from it; the rows after it did not run.
- mutation: `Test.Web.Splash.TestDemoBusy` -- Splash's `OnPreHTTP` skips the busy decision (`&& 0`) -- red: `TestDemoBusy` failed ("the busy text, then the README link", "the marker header", "the link twice").
- mutation: `Test.Web.Status.TestNoHighWaterMark` -- `Busy` reads `InstanceConnectionsMax()` -- red: `TestNoHighWaterMark` failed ("no method body reads the high-water mark"), and `TestBusyOwn` with it.
- mutation: the unit's row 5 -- `AttachVisitor` checks busy after the counter -- red: row 5 failed (S3: a cookie in the POST, a new row, a counter row; the cookie sign-in: status 303, attached) and row 6's refused half.
- mutation: the unit's row 6 -- `Busy(0)` in place of `Busy(..#OWNCONNECTIONS)` -- red: row 6's allowed half failed (the sign-in at the boundary gave `other`, no cookie, 0 counter rows); run together with the header mutation below, which failed rows 2 and 5 only.
- mutation: `Test.Web.SessionEvents.TestBusyExempt` -- the busy check ignores `proxied` -- red: `TestBusyExempt` failed (no new row, no cookie, a marker).
- mutation: `busy.spec.ts` B1 -- `pressConversation` skips `openTrace` -- red: B1 failed in the unit's browser step (the window opened and no banner showed); run together with the next one.
- mutation: `busy.spec.ts` B2 -- the outbox marks a 503 as failed on the online demo too -- red: B2 failed (no text back in the composer, "Not sent" shown).
- mutation: `demo-busy.test.mjs` -- `DemoBusyWatch` never re-checks (`arm` returns at once) -- red: four tests of the trace cause failed.
- mutation: `banner-view.test.mjs` (row 13) -- the `demoBusy` row drops `onlineDemo: true` -- red: the table test and "is the online demo's only" failed.
- mutation: `host-pages.spec.ts` H1 -- `busy.html` links a stylesheet at `/ocutalon/x.css` -- red: H1 failed in both schemes ("and nobody was asked"; the unit's local run, no stack).
- mutation: `host-pages.spec.ts` H2 -- the refresh element is removed -- red: H2 (light) failed after 15 s ("the refresh lands on the splash address").
- mutation: `host-pages.test.mjs` -- `maintenance.html` names an address (`http://203.0.113.9/`) -- red: the no-address test and the address-list test failed.
- mutation: the unit's rows 2 and 5 -- Splash's `OnPreHTTP` sets no header -- red: row 2 failed (header none) and row 5 failed on "header" for S3 and for the cookie sign-in.
- mutation: `Test.Web.Status.TestBusyHeader` -- `Show` sets no header -- red: `TestBusyHeader` failed ("a busy status carries X-OcuTalon-Busy: 1").
- mutation: `Test.Web.Status.TestBusyOwn` -- `Busy` does not subtract `own` (`InstanceConnections()` in place of `InstanceConnections() - own`) -- red: `TestBusyOwn` failed ("with one own connection left out it is not").
- mutation: `Test.Web.SessionEvents.TestBusyRefusal` and `TestBusyBeforeTheCounter` -- `AttachVisitor` never checks busy (`If proxied, 0, ...`) -- red: both failed (the marker, the row, the cookie and the counter assertions); `TestFlagOff` also failed from the rows the mutated run left, and the class was green again after the revert.
- mutation: `busy.spec.ts` B3 -- `TraceLink.press` skips `openTrace` -- red: B3 failed ("after the press: the Demo busy banner shows") and `demo-account.spec.ts` O4 failed (no tab opened); run in one unit run with the next three.
- mutation: `busy.spec.ts` B3b -- `openTrace` returns when the status check gave no answer (`status === undefined`) -- red: B3b failed ("a status answer that is not JSON opens the tab").
- mutation: `busy.spec.ts` B2, second half -- the composer takes a refused message's text back without the empty-field check; and the envelope interceptor does not report a 2xx to `DemoBusyState` -- red: B2 failed in that unit run; the two were applied together, so which of the two assertions failed first was not captured (inference: either alone turns B2 red).

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-25).** The story was planned from the cached `epic-16-context.md`, Story 16.3's spec (continuity), the spine's AD-3, AD-13 and AD-25, and the UX's Demo busy, resetting and banner passages. The spec passed the READY FOR DEVELOPMENT standard and the run halted after planning, as the dispatch asked.

- **Warnings:** `multiple-goals` (server busy states, the page's busy handling and the two host pages), `oversized`.
- **Decided in-stage:** under Design Notes.
- **Items for the lead's gate:** under For the lead (the tenth banner row, the busy page's title, the first-load 503 reading, DW-220's growth).
- **Ledger inbox:** none.
- **Footprint extensions:** under Design Notes.

**Implement and review (2026-10-26).**
- **Summary.** The server marks and shows the busy states (`Status.Busy(own)`, the `X-OcuTalon-Busy` header on a busy status, the splash's busy state and the post-sign-in refusal that comes before the resume and the counter). The signed-in page checks the status before opening a trace window, turns an API 503 into one "Demo busy" banner, and returns a refused message's text to an empty composer. `docker/busy.html` and `docker/maintenance.html` are the two host pages. The catalog gains `banner.demoBusy`.
- **Files changed.**
  - Server: `Web/Public/{Status,Splash,Login,Shell}.cls`, `Web/SessionEvents.cls`, `Msg/Catalog/Core.cls`.
  - Page: `web/src/app/{api/envelope.interceptor,banners/banner-view,banners/banner-stack,header/header,shared/trace-link,chat/chat-outbox,chat/composer}.ts`, new `live/demo-busy.ts` and `live/demo-busy-state.ts`, generated `msg/catalog.ts`.
  - Host pages: new `docker/busy.html` and `docker/maintenance.html`.
  - Tests: `Test/Web/{Status,Splash,SessionEvents,PublicTexts}.cls`, `Test/Msg/Catalog.cls`; `web/scripts/{catalog,banner-view,catalog.test,ux-strings,demo-busy,host-pages}`; `web/e2e-online/{busy,host-pages}.spec.ts` and `support.ts`; `docker/tests/test-online-demo.sh`.
- **Review pass.** 38 findings from four layers: 23 low, 7 medium, 3 high, 4 false, 1 maybe-false. Patched (all in-story): the SessionEvents class comment, dead CSS in `busy.html`, the unit's cookie and empty-epoch guards, B3b (the fail-open rule, a medium), and six `mutation:` lines. Deferred: the high premise item and the guide-prompt test (frontmatter `deferred:`). The others are rejected with their reasons in the triage log.
- **For the lead: the licence-connection premise (high, deferred).** On the throwaway (build 154, Community key, the image's own web server) a signed-in CSP session never raises `$SYSTEM.License.InstanceConnections()`. The matrix rows 1, 5, 6 and 9 and the AC wording "two signed-in sessions make the demo busy" therefore reach busy with the cap, derived from the measured baseline at run time; the unit asserts that two sessions leave the count unchanged, so a change in IRIS turns it red. Whether the real demo host counts sessions is not measured here. If it does not, the busy splash, banner and refusal never fire there and only the proxy's own 503 and busy page remain. Story 29.3 or the owner needs a measurement on the host, or a counter of the visitor sessions in place of the licence count; that is a product and architecture call (AD-13 S13), not made here.
- **Verification performed (final tree).**
  - Node: 598 tests pass; `npm --prefix web run lint`, `tokens` (no change to the Assets classes) and `catalog` clean; `docker/tests/test-web-build.sh` and `bash ci/checks.sh` pass (the boundaries check scans both host pages).
  - Warm classes: Status, Splash, SessionEvents, PublicTexts, Msg.Catalog, SignIn, Api pass.
  - `live online-demo`: 38 browser cases and every unit row pass; the unit took 283 s wall on the final run (249 s on the implement run, Story 16.3 195 to 219 s; DW-220).
  - `live sign-in`: 192 passed, 1 skipped. `shard lane-b`: 44 classes pass. `shard lane-a`: 47 classes pass.
  - Rule 19: 21 `mutation:` lines, each applied from a backup, observed red and reverted (SHA-256 of every touched file identical, `git status --short` unchanged). Where two mutations ran together the line says so.
  - The warm stack and the tagged throwaways are torn down (`ci/warm.sh down`, `ci/iris.sh teardown`); HEAD was `dde4300` throughout.
- **Residual risks.**
  - The premise above.
  - `docker/maintenance.html` names its logos by bare file name, as the AC says, so a visitor on a deep path during a reset sees the alt text unless the proxy serves the logos at that depth (Story 29.3, DW-240).
  - `window.open` after the status check was measured in Chromium only (Task 0 (e)).
  - The guide prompt's 503 path has no test until Epic 4's guide calls `send(text, true)`.
- **Follow-up review recommended:** false (patched this pass: 1 medium, the rest low).
- **Ledger inbox:** none. Footprint extensions as under Design Notes; no contended path was edited.
