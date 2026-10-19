---
title: 'Story 0.3: Sign in to an empty OcuTalon page'
type: 'feature'
created: '2026-10-18'
status: 'done'
baseline_revision: '167a56ac02bdb05141d9dea0217a05d99ab6b873'
baseline_commit: '167a56ac02bdb05141d9dea0217a05d99ab6b873'
review_loop_iteration: 0
followup_review_recommended: true
context: ['{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/DESIGN.md']
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      A hash-route deep link such as /ocutalon/#/x is lost at sign-in.
    evidence: |-
      The form action is Error:FullURL and the 303 Location is built from the URL and query, so neither carries a fragment, and the browser does not send it. Signing in at /ocutalon/#/runs/5 lands on /ocutalon/. No route exists in Story 0.3 and row 13 pins a query deep link, so nothing fails today. It settles when the first hash route lands: sign in at that URL and expect to land on it.
    location: >-
      src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls Redirect, web/src/signin/signin.js
    severity: low
---

<intent-contract>

## Intent

**Problem:** After Story 0.2 the install reaches ready, but the `Roles`, `Users` and `Web` steps create nothing. So there is no OcuTalon role, no README account and no web application, and a judge has nothing to sign in to.

**Approach:**
- **Steps.** Fill the steps in place:
  - the role declarations, composed by the existing `Roles` step;
  - the README account, created once;
  - the three web applications in one sign-in group.
- **Sign-in.** `/ocutalon` is a dispatched application. Its public dispatch class `OcuTalon.Web.Public.Shell` does three things:
  - for every request without a session, it renders the branded `%CSP.Login` page `OcuTalon.Web.Public.Login` and serves only the five sign-in images;
  - after sign-in, it checks the OcuTalon user role;
  - it then serves the Angular shell built from `web/`, which IPM copies to the durable `csp/ocutalon/` folder.
- **Styles.** One generator turns `DESIGN.md`'s tokens into the shell's stylesheet and into the sign-in page's inline styles.

## Boundaries & Constraints

**Always:**
- **Before sign-in.** Every URL under `/ocutalon/` answers the sign-in page with AD-13's header: `default-src 'none'; script-src 'sha256-<script>'; style-src 'sha256-<css>'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`.
  - The only exceptions are the five sign-in images (Design Notes).
  - `/ocutalon/api/*` answers 401 with no body data.
  - The trace application shows IRIS's own login form.
  - No `style=` attribute, no external script, and the only fonts are system fonts.
- **Sign-in page.** It keeps `%CSP.Login`'s form contract:
  - the action comes from `Error:FullURL`;
  - `InsertHiddenFields`;
  - the fields `IRISUsername`, `IRISPassword` and `IRISLogin`;
  - `OnPreHTTP` calls the superclass.

  Its UX texts are verbatim, with any non-ASCII character written as an HTML entity (Rule 14).
- **After sign-in.** Every response to a user without `OcuTalonUser` ends the CSP session and shows the no-role message on the sign-in page. Users who hold the role get the built files, and `index.html` carries `Content-Security-Policy: script-src 'self'` and `Cache-Control: no-cache`.
- **Public package.** `OcuTalon.Web.Public.*` references only `%CSP` (`%CSP.REST`, `%CSP.Login`, `%CSP.StreamServer`), dynamic objects, `$SYSTEM.Status`, `$SYSTEM.Encryption` (compile-time generators only) and the two public packages (AD-3).
- **Structural or seed (AD-19).**
  - Roles and web applications are structural: they are rewritten every start through `Modify` (never delete and create again, which drops SQL grants).
  - The README account is seed: it is created when absent and never changed afterwards.
- **Steps.** They switch namespace only to `%SYS`, each in one method with `New $Namespace`, and keep the 15-step order (AD-23).
- **Runtime targets.**
  - Slot A: every call names `server: ocutalon-slot-a` and `namespace: OCUTALON`. Tests there create and delete only their own `Zz` fixtures.
  - Full installs and browser runs happen in throwaway projects through `lib-live.sh`, one IRIS stack at a time (Rule 21).
- **Dependencies.** No npm package beyond the Stack rows and their required peers (`@angular/forms`, `rxjs`, `tslib`). No test runner besides Playwright and Node's built-in `node --test`. No YAML library.

**Never:**
- **Owned by later stories:**
  - `/ocutalon/public` and its status class (0.5);
  - REST routes and the 403 envelope (0.5);
  - the OCUORDERS trace application and grants (0.6 and 3.1);
  - `OcuTalon.Web.SessionEvents` and Sign out through `POST /api/v1/session/end` (2.2);
  - the theme menu, context badge, user name, About and header links beyond home (2.1);
  - the splash, busy state and online-demo accounts and timeouts (Epic 16, 3.8);
  - the README (10.2).
- **Sign-in.** Never put a role check in `%CSP.SessionEvents.OnLogin`: an error there neither logs out nor shows the sign-in page (probe). Never change `InvalidLoginAction`, and never offer a password change.
- **The judges' `docker-compose.yml` doesn't change.**
- **Secrets.** Never read `.env`. Never run `docker compose config` without `--quiet` or `docker inspect` without `--format`.
- **Slots.** Never stop or recreate a slot. Nothing is loaded from `irislib/` or `irissys/`.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–13: `test-sign-in.sh` (live), with the Playwright specs in `web/e2e/sign-in/` for rows 5–13.
- Rows 14–15: `test-install-start.sh` and `test-install-upgrade.sh`.
- Rows 16–18: `%UnitTest` on slot A.
- Row 19: `node --test`.
- Row 20: `test-build-inputs.sh`.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Roles and account | first start | `OcuTalonUser` and `OcuTalonAdmin` hold no resource. `OcuTalonTraceViewer` holds exactly Use on `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent`, and Read on `%DB_OCUTALON_DATA` and `%DB_OCUTALON_CODE`; `CheckPrivilege` reports SELECT on `Ens.MessageHeader` in OCUTALON. User `ocutalon`: the three roles, PasswordNeverExpires 1, ChangePassword 0, AccountNeverExpires 1, Enabled 1. `InvalidLoginAction` is 0 | none |
| 2 | Applications | first start | The three applications have exactly the Design Notes properties. Trace `PermittedClasses` is exactly AD-24's seven, and no CORS list is set | none |
| 3 | No session, pages | GET `/ocutalon/`, `/ocutalon/index.html`, `/ocutalon/<a main-*.js>`, `/ocutalon/x/y?a=1` | 200 sign-in page: tab title "Sign in · OcuTalon", the CSP header above with the hashes of the served style and script, `Cache-Control: no-store`, no shell markup | none |
| 4 | No session, others | GET the 5 sign-in images; `/ocutalon/assets/brand/icon-192.png`; `/ocutalon/api/v1/zz`; `/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen` | images 200 `image/png`; `icon-192.png` answers the sign-in page; API 401; trace shows IRIS's login form, not the viewer | none |
| 5 | Sign-in page | open `/ocutalon/` in light and dark scheme | the logo `img` is loaded (`naturalWidth` > 0) from the light or dark file; `lang="en"`; `h1` "Sign in to OcuTalon"; labels "User name" and "Password" above their fields; full-width **Sign in**; help line; no CSP violation in the console | none |
| 6 | Wrong password | `ocutalon` / `wrong` | "That user name and password didn't work." under the button with `circle-alert`; focus on the error; user name kept; password empty; both inputs `aria-invalid` and `aria-describedby` the error | shown |
| 7 | Show password | press the toggle twice | `aria-pressed` true, then false; the input type is text, then password | none |
| 8 | README sign-in | `ocutalon` / `ocutalon` at `/ocutalon/` | the shell: title "OcuTalon"; 28px mark loaded; wordmark "Ocu" in `ink` and "Talon" in `brand-orange` (computed colours); account menu opens with "Sign out"; `main` holds only a visually hidden `h1`; `script-src 'self'` header; no CSP violation | none |
| 9 | Tokens and fonts | shell, light, then emulated dark | one custom property per group equals DESIGN's value: `--bg`, `--brand-orange`, `--action`, `--attention`, `--danger-ink`, `--scrim`, `--rounded-xs`, `--space-1`, one type token, plus one component property each for the elevation, icon and brand groups (a shadow, an `icon` value, the wordmark's font size), all as DESIGN states them. The colours switch to `-dark`; `document.fonts.check` passes for Montserrat 800, Inter 400 and JetBrains Mono 400; the reduced-motion rule is present | none |
| 10 | One group | signed in | `/ocutalon/api/v1/zz` answers 404, not 401, so the session is shared. Trace `EnsPortal.MessageViewer.zen` renders with no second sign-in. Trace `EnsPortal.Productions.zen` answers 404 | none |
| 11 | Sign out | menu → Sign out (`/ocutalon/?IRISLogout=end`) | sign-in page; API 401; trace shows the login form | none |
| 12 | No role | a fixture user with no roles signs in | sign-in page with "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it." and no field marked; API 401 afterwards; the shell is never served | shown |
| 13 | Deep link | sign in from `/ocutalon/index.html?x=1` | 303 to that URL, which then serves the shell | none |
| 14 | Bundle installed | first start | `/durable/iris/csp/ocutalon/index.html` is byte-identical to `/opt/ocutalon/src/ocutalon/csp/index.html`; STEP list unchanged | none |
| 15 | Upgrade keeps the account | under V0, change `ocutalon`'s password; then upgrade to V0+1 | the password hash and flags are unchanged; the durable `index.html` equals the new image's; rows 1–2 still hold | none |
| 16 | `Users.Ensure` | fixture user and roles; call twice with different passwords | first call creates with row 1's flags; second changes nothing (hash, roles, flags) | `%Status` |
| 17 | `Web` declarations | `Definitions`, `TraceApp("ZZNS")`, `Grants()`, `Apply` on a fixture application, `BundleCheck` | the Design Notes table exactly; no forbidden resource (AD-24 list); `Apply` restores a changed property; `BundleCheck` fails, naming the path, without `index.html` | `%Status` |
| 18 | Sign-in page contract | `Login` | header = AD-13's template with `Base64(SHA256)` of the `CSS` and `SCRIPT` parameters, recomputed by the test; UX texts verbatim; no `style=` in the class sources | none |
| 19 | Generator | `DESIGN.md` and fixtures | counts: colors 74 (37 pairs), typography 14, rounded 6, spacing 27; references resolved; dark exceptions kept; prose skipped; output deterministic; `--check` fails on a stale output | an unsupported YAML form, or an unresolved reference, exits non-zero naming the line |
| 20 | No bundle | the build context without `src/ocutalon/csp/` | `docker build` fails with "web bundle missing: run npm --prefix web run build" | build fails |

</intent-contract>

## Code Map

- **Spine**, read by range:
  - AD-2 L108–119, AD-3 L121–148, AD-13 L340–381, AD-19 L473–513, AD-23 L593–636 (static files L626), AD-24 L638–665, AD-29 L752–766;
  - Conventions L862–883, Stack L885–903, source tree L1119–1143, REST L1145–1160, S7 and S16 L1191–1215.
- **Epics:** this story L818–846. Later refinements: 2.1 L1368–1400 (sign-in and header details), 2.2 L1405–1420 (Sign out through the API), 10.2 L3087, 16.2 L3923, 16.4 L3989.
- **UX:**
  - `DESIGN.md` front matter L1–592;
  - `EXPERIENCE.md` L79 (titles), L126–128 (sign-in), L360 (error texts);
  - mockups `splash.html` L685–744 (sign-in, with CSS at 225–330 and 419–430) and `main-page.html` L109–121 and L318–331 (header).
- **Front matter shape**, which the generator reads:
  - indentation of 0, 2 or 4 spaces, at most 3 levels, one-line values only;
  - values are single-quoted strings, unquoted words, numbers with units, or `'{group.key}'` references (also inside compound strings);
  - full-line `#` comments, where `#` also appears inside quoted colours;
  - no lists, flow style, anchors, block scalars or double quotes;
  - every light colour has a `<name>-dark`. The exceptions are `qr-code-block` (literal), `simulated-phone.shadow-dark`, `splash-canvas.background-dark` and `brand-navy-dark` (= `bg-dark`);
  - prose properties are `note`, `marker`, `halo` and `decoration`.
- **Installer** (`src/ocutalon/cls/OcuTalon/Install/`):
  - `Registry.Order()` :14, `Declared` :88, `CallAreas` :69;
  - `Step/Roles.cls`: `Compose` and `Add`; `Apply` calls `Security.Roles.Modify`/`Create` in `%SYS`; a role declared with an empty resource is created holding nothing;
  - `Step/Users.cls` and `Step/Web.cls` are stubs. The steps have no shared `%SYS` helper (each uses `New $Namespace`).
- **Tests to keep green (Rule 19):**
  - `Test/Install/Registry.cls`: `TestRolesStep` :96 runs the real `Roles` step, which from now on creates the real roles on slot A; `TestOrder` :77.
  - `docker/tests/lib-live.sh`: `live_start` :16, `live_add_file` :38, `dc` :40, `iris_script` :94, `wait_started_ready` :149, `copy_build_context` :177. The override `compose.throwaway.yml` publishes no port. `test-install-upgrade.sh`'s `use_image_context` (about :44) assumes 3 base `LIVE_FILES`.
  - `test-compose-file.sh`: the exact `.dockerignore` list :148–158 (unchanged), `files_keep_lf` :123–126, the three COPY lines :109, and `src_binaries_not_forced_text` :134, which already expects `src/ocutalon/csp/*` as `text=auto`.
  - `test-boundaries.sh`: scope at :82 (`git ls-files -co --exclude-standard`); `web/` is not covered. On macOS BSD grep reports binaries on stdout, so scan text files only.
  - `test-pinned-sources.sh`: `each_resource_has_its_package` :128 matches only `<Resource `, so a `<FileCopy>` is fine.
  - `test-install-start.sh` row 1 :76–78: an exact STEP diff.
- **Image:**
  - `docker/Dockerfile` :11–21: COPY, then a RUN for version and modes. The guard goes into that RUN, before `USER`.
  - `.gitignore` :21–24: `src/ocutalon/csp/` is not ignored yet.
  - `after-start.sh` :69–77 builds `OCUTALON_PUBLIC_CLASSES` from the image's `OcuTalon/{Web,Data}/Public/*.cls`. `after-start.cos:6` requires each class's `.1.INT` routine to resolve to `OCUTALON_PUBLIC`, so every public class needs a method; an abstract class with parameters only may compile to no routine.
- **IRIS** (`irislib`/`irissys`):
  - `%CSP/Login.cls`: :37–73 (`OnPage`), :111–128 (form), :777–787 (`OnPreHTTP`).
  - `%CSP/REST.cls`: `Page` :140–200 (`AccessCheck` comes first, then 403), `Login` :245–300, `AccessCheck` :345–365 (needs Read on the data database: override it).
  - `%CSP/StreamServer.cls:40–140`: `FILE` is the URL, mapped through the application's `Path`; `ServeFiles` must not be 0; directories give 404.
  - Prior art: `%ZHSLIB/REST/AngularHandler.cls:9–66` (dispatch plus `StreamServer.Page()`; HS-only, so it is adapted, not extended).
  - `Security/Applications.cls`: `Create` :417, `Exists` :452, `Modify` :533. `Modify` keeps keys not passed, so pass every key in the table.
  - `Security/Users.cls`: `Create` :354, `Exists` :405.
  - `%SYSTEM/SQL/Security.cls`: `GrantPrivilege` :130, `CheckPrivilege(user,1,table,"s",ns)` :39.
  - `Security/System.cls:242` (`InvalidLoginAction`).
  - The merge creates the roles `%DB_OCUTALON_{CODE,DATA,PRIVATE,PUBLIC}` (RW), confirmed on slot A.
- **Probes** (October 18, throwaway `docker run` of the base image with `docker/merge.cpf`; logs under the session scratchpad `probe3`…`probe6`):
  - A password-only CSP application answers 404 (not its login page) before sign-in for `/<app>/` and every static file (`ServeFiles` 3), and a directory never serves `index.html`.
  - With `DispatchClass` set, `LoginPage` is never shown.
  - A public `%CSP.REST` dispatcher's `Login()` runs for every request without a session. The server has already set `Error:ErrorCode` (864 first, 822 wrong password), `Error:FullURL` with the query, and keeps `IRISUsername`. It renders and streams files.
  - The sign-in POST authenticates and then needs a POST route (303).
  - `%session.Logout(1)` plus `EndSession` and `?IRISLogout=end` end the whole group.
  - The same `CookiePath` gives `/ocutalon` and `/ocutalon/api` one session.
  - No CSRF token is emitted on a dispatched sign-in.
- **Spikes:**
  - S16: `spikes/batch2/s16/src/pub/OcuSpike.S16.Web.Public.Login.cls:12–31,47` (`objectgenerator` hash over `%parameter("CSS")`, header in `OnPreHTTP`).
  - S7: `spikes/trackD/logs/s7-final.log:1–8` (trace application settings, the seven-class pattern); `trackD/scripts/s7-sqlpriv.txt:2`.
  - S1: `docs/handoff/spike-results/S1.md:18–19,105,146` (`FileCopy` to `${dataDir}` follows upgrades; `${cspdir}` is read-only).
- **IPM 0.10.10** (`../spikes/install/ref/ipm-src/`):
  - `<FileCopy Name>` is relative to the module root (`src/`); a trailing `/` copies a directory, recursively, overwriting and never pruning;
  - a missing source fails the load;
  - `${dataDir}` = `$SYSTEM.Util.DataDirectory()` = `/durable/iris/` (`Utils/Module.cls:2641–2706`).
- **Angular 22.2.3:**
  - `outputPath {"base":"../src/ocutalon/csp","browser":""}` empties that folder on every build;
  - critical-CSS inlining adds an inline script, so set `inlineCritical:false`; also `fonts:false`, `autoCsp` off and `subresourceIntegrity` off;
  - zoneless by default;
  - CDK menu from `@angular/cdk/menu`;
  - `ng new`'s test runner would add vitest and jsdom, so don't add a `test` target.
- **Playwright 1.64.1:**
  - read headers with `headerValue`;
  - the base URL is an origin only, with `goto('/ocutalon/')`;
  - `npx playwright install chromium`.
- **Vendored files:**
  - Fonts (OFL-1.1), pinned at these raw URLs:
    - Inter v4.1, `rsms/inter/v4.1/docs/font-files/Inter-{Regular,SemiBold}.woff2`;
    - Montserrat v7.222, `JulietaUla/Montserrat/v7.222/fonts/webfonts/Montserrat-{Bold,ExtraBold}.woff2`;
    - JetBrains Mono v2.304, `JetBrains/JetBrainsMono/v2.304/fonts/webfonts/JetBrainsMono-Regular.woff2`;
    - each repository's licence file.
  - Icons: Lucide paths for `chevron-down`, `circle-alert` and `eye`, under ISC plus Feather's MIT notice.

## Tasks & Acceptance

**Execution:**

IRIS:
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls` (Lane A):
  - parameters `USER`, `PASSWORD` (the published `ocutalon`/`ocutalon`) and `ROLES`;
  - `Grants()` declares `OcuTalonUser` and `OcuTalonAdmin` alone;
  - `Ensure(user, password, roles) As %Status` creates the account with row 1's flags only when it doesn't exist (seed);
  - `Run()` calls `Ensure`.
  - AD-24, AD-19.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` (Lane B):
  - `Grants()` declares the trace role's six grants;
  - `Definitions(Output apps)` returns the table below; `TraceApp(ns, Output props)` gives the trace-application properties, for 0.6 to reuse for OCUORDERS;
  - `Apply(name, ByRef props)` runs `Exists`, then `Modify` or `Create`, in `%SYS`;
  - `BundleCheck(dir)`;
  - `GrantTraceSql()` grants in OCUTALON;
  - `Run()` = `BundleCheck($SYSTEM.Util.DataDirectory()_"csp/ocutalon/")`, then `Apply` for each definition, then `GrantTraceSql()`.
  - AD-13, AD-24.
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls` (`%CSP.REST`, `UseSession` 1):
  - `AccessCheck` always authorises;
  - `Login()` streams an allow-listed sign-in image (`FILE` = the URL, through `%CSP.StreamServer`), or calls `Login.Show("")`;
  - `OnPreDispatch` runs the role check: without the role, it calls `Logout(1)`, sets `EndSession=1`, sets `Error:FullURL`, calls `Show("norole")` and sets `pContinue=0`;
  - routes: `GET /` → `index.html`; `GET /(.*)` → the file, with both CSP and no-cache on `index.html`; `POST /(.*)` → 303 to the same URL and query.
  - Adapted from `AngularHandler` (Rule 2).
- `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls`:
  - `Extends (%CSP.Login, OcuTalon.Web.Public.SignInAssets)`;
  - `objectgenerator` methods `StyleHash()` and `ScriptHash()`;
  - `OnPreHTTP` calls `##super()`, then sets the CSP header and `Cache-Control: no-store`;
  - `Show(state)` = `OnPreHTTP`, `WriteHTTPHeader`, `OnPage`;
  - `OnLoginPage` renders per state: `""` with 864 shows no error; `norole`; any other `Error:ErrorCode` shows the wrong-credentials text.
  - Markup:
    - `<picture>` for the light/dark 640/1280 logos at `width=320`;
    - the card;
    - the toggle button (`type=button`, `aria-pressed`);
    - the error `p` (`tabindex=-1 autofocus`) with an inline `circle-alert` `svg` (`aria-hidden`);
    - the favicon link.
  - Texts as parameters (AD-3, a catalog comparison in 0.4).
- `src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls`: generated, never edited. It holds `Parameter CSS` (minified: only the custom properties that `signin.css` uses, light and dark through `prefers-color-scheme`, then the rules) and `Parameter SCRIPT` (from `signin.js`), plus `ClassMethod Css()`/`Script()` so it compiles to a routine.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: `%CSP.REST`, `UseSession` 1, JSON, an empty `UrlMap`. Story 0.5 fills it.

Package and image:
- `src/module.xml`: after the two resources, add `<FileCopy Name="ocutalon/csp/" Target="${dataDir}csp/ocutalon/"/>`. AD-2, AD-23.
- `docker/Dockerfile`: in the version RUN, before the chmods, add `test -f /opt/ocutalon/src/ocutalon/csp/index.html || { echo "web bundle missing: run npm --prefix web run build" >&2; exit 1; }`.
- `.gitignore`: add `src/ocutalon/csp/`, `web/public/assets/brand/`, `web/test-results/` and `web/playwright-report/`.
- `.gitattributes`: add `web/** text=auto eol=lf`.

`web/`:
- `web/package.json`, `web/package-lock.json`:
  - dependencies: `@angular/{cdk,common,compiler,core,forms,platform-browser,router}` 22.2.3, `rxjs` 7.8.2, `tslib` 2.8.1;
  - devDependencies: `@angular/{build,cli,compiler-cli}` 22.2.3, `@playwright/test` 1.64.1, `typescript` 6.0.3;
  - `engines.node` `^24.15.0 || >=26.0.0`;
  - scripts: `tokens` (write); `build` = `node scripts/tokens.mjs --check && node scripts/brand.mjs && ng build`; `e2e`.
- `web/angular.json`, `web/tsconfig.json`, `web/tsconfig.app.json`:
  - the builder settings above;
  - `baseHref` `/ocutalon/`;
  - assets from `public/`;
  - styles `src/styles/tokens.css` and `src/styles/base.css`;
  - `extractLicenses`;
  - schematic budgets;
  - `strictTemplates`;
  - `cli.analytics` false.
- `web/src/index.html`, `web/src/main.ts`, `web/src/app/app.config.ts` (`provideRouter([], withHashLocation())`), `web/src/app/app.ts`, `web/src/app/header/header.ts`, `web/src/app/icon/icon.ts`:
  - standalone components with signals;
  - a header with the mark and wordmark linking to `#/`;
  - an "Account" menu trigger (CDK menu, `chevron-down`), whose item "Sign out" goes to `/ocutalon/?IRISLogout=end`;
  - `main` with a hidden `h1` "OcuTalon";
  - no inline script.
- `web/src/styles/tokens.css` (generated) and `web/src/styles/base.css`:
  - `@font-face` with `url('/ocutalon/assets/fonts/...')`;
  - body;
  - the focus ring (UX-DR33);
  - reduced motion (UX-DR14);
  - a 12px minimum size;
  - tabular figures;
  - `.visually-hidden`.
- `web/src/signin/signin.css` and `web/src/signin/signin.js`: the sign-in page's rules and toggle. ASCII only.
- `web/scripts/tokens.mjs`:
  - dependency-free;
  - reads `DESIGN.md`;
  - writes `tokens.css` (custom properties `--<color>`, `--type-<token>-<prop>`, `--rounded-<k>`, `--space-<k>`, and `--<component>-<prop>` for CSS-valued properties; dark under `@media (prefers-color-scheme: dark)` on `:root:not([data-theme=light])`, and again under `[data-theme=dark]`) and `SignInAssets.cls`;
  - `--check` compares instead of writing.
- `web/scripts/tokens.test.mjs`: row 19.
- `web/scripts/brand.mjs` copies, from `../logo/web/`, the four `OcuTalon-Logo-{light,dark}-{640,1280}.png`, `icon-192.png` and `favicon-32.png` into `public/assets/brand/`.
- `web/public/assets/fonts/` (the five woff2) and `web/public/assets/licenses/` (the three OFL texts and `lucide-LICENSE.txt`, ISC plus the MIT notice).
- `web/playwright.config.ts` and `web/e2e/sign-in/{helpers,sign-in.spec,shell.spec}.ts`:
  - Chromium only, 1 worker, baseURL `OCUTALON_URL`;
  - rows 5–13;
  - console CSP-violation capture;
  - `signIn(page, user, password)` exported for 0.8.

Tests:
- `docker/tests/lib-live.sh`:
  - `ensure_web_bundle`, called by `live_start`: runs `npm --prefix web ci` when `web/node_modules` is missing, then `npm --prefix web run build` when `src/ocutalon/csp/index.html` is missing, and fails naming Node if it is absent;
  - `live_web_port`: the first free port of 52800–52819 on 127.0.0.1 (a `/dev/tcp` probe), or `OCUTALON_TEST_WEB_PORT`; writes an override `ports: ["127.0.0.1:<p>:52773"]` and passes it to `live_add_file`. No listed port of another instance or slot (1979, 52779, 8089, 1990, 1991, 52790, 52791, 8090, 8091) and not 52773 falls in that range;
  - `check_security`: rows 1–2's `CHK` script, shared by `test-sign-in.sh` and `test-install-upgrade.sh` (Rule 2).
- `docker/tests/test-sign-in.sh`, new, label `t03`:
  - always rebuilds the bundle;
  - `live_start`, then `live_web_port`, then up, then `wait_started_ready`;
  - creates a no-role fixture user with a random password that is never printed;
  - rows 1–2 through `iris_script` `CHK` lines;
  - runs `npm --prefix web run e2e` with `OCUTALON_URL` and the fixture's variables;
  - a 540 s deadline and the EXIT trap.
- `docker/tests/test-install-start.sh`, `docker/tests/test-install-upgrade.sh`: rows 14 and 15.
- `docker/tests/test-build-inputs.sh`: row 20, a build of `copy_build_context` without the bundle.
- `docker/tests/test-compose-file.sh`: pins the guard, the `.gitignore` entry and the `web/**` attribute.
- `docker/tests/test-boundaries.sh`: adds the tracked text files of `web` (`*.ts`, `*.html`, `*.css`, `*.mjs`, `*.json`) to its scope.
- `docker/tests/test-lib-live.sh`: `live_web_port` with stubbed in-use ports: it picks the first free one, honours the override, and fails clearly when none is free.
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` (row 16), `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls` (row 17), `src/ocutalon/cls/OcuTalon/Test/Web/SignIn.cls` (row 18): fixtures `Zz<n>`, deleted in `OnAfterAllTests`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`: `TestRolesStep` deletes every role that didn't exist before it ran.

**Acceptance Criteria:**
- Given a first start, when the steps run, then rows 1, 2 and 14 hold, and `test-install-start.sh`'s STEP list is unchanged.
- Given no session, when any `/ocutalon/` URL is opened, then only the sign-in page, the five images, an API 401 or the trace login form answer (rows 3–4).
- Given the README account, when it signs in, then the token-styled shell loads; Sign out ends `/ocutalon`, `/ocutalon/api` and the trace application (rows 8–11).
- Given a user without `OcuTalonUser`, when they sign in, then they see the no-role message and hold no session (row 12).
- Given the IRIS (non-Health) image, when `test-sign-in.sh` runs with `IRIS_IMAGE=iris-community:2026.3.0AI.154.0`, then it passes.
- Given a fresh checkout, when `npm --prefix web ci`, `npm --prefix web run build` and `git status --short` run, then the tree is clean (bundle and brand copies ignored, generated files current).

## Spec Change Log

### 2026-10-18 -- Plan intent gap answered (lead, author decisions)
- The plan halted `blocked` on an intent gap: AD-13's classic `/ocutalon` application cannot show the sign-in page at `/ocutalon/` on build 154.
- The author chose to amend AD-13 and AD-3 as recommended. The spine now says `/ocutalon` is a `%CSP.REST` application dispatched by `OcuTalon.Web.Public.Shell`, that `PermittedClasses` applies to the trace applications only, and that the public package also holds `Shell` and `SignInAssets`. Both are marked `[AMENDED 2026-10-18]`.
- The author also kept 0.3 as one story, with no split.
- The lead wrote the Stack rows: the Angular CDK plus custom components; Lucide icons (ISC, with Feather's MIT notice); Inter, Montserrat and JetBrains Mono woff2 files (OFL-1.1).
- The plan is unchanged. Status was reset from `blocked` to `ready-for-dev` (re-dispatch protocol).

### 2026-10-18 -- Design Notes table corrected while implementing (apply and report, Rule 5 first tier)
- Original: `CSPZENEnabled` 0 on `/ocutalon` and `/ocutalon/api`. Amended: 1 on all three applications. The value is not in the architecture spine or the frozen intent, and the matrix rows are unchanged.
- Why: measured on build 154 (Health and non-Health image): with 0, a signed-in request to a dispatched application never reaches its dispatch class (`/ocutalon` answers a gateway "Not Found" page after the sign-in POST; `/ocutalon/api` answers 200 with an empty body instead of the REST 404). The probes behind this spec (`probe3` to `probe6`) all used 1.
- Pinned by `Web.Definitions`, `Test.Web.Install`, `check_security` and the Playwright rows 8 to 13.

## Review Triage Log

### 2026-10-18 -- Review pass
- verdicts: 53 findings -- high 0, medium 6, low 40, false 7, maybe-false 0
- findings:
  - Blind Hunter:
    - `[low]` `reject` `Api` has no OcuTalonUser check, so a signed-in user without the role reaches it -- the empty `UrlMap` answers every signed-in request 404, so nothing is exposed; the role check in `Api.OnPreDispatch` and the 403 envelope are Story 0.5's (Never list, Consumed-by 0.5).
    - `[medium]` `patch` `Modify` keeps keys that are not passed, so a CORS list added by hand survives every start -- the Design Notes table lists `CorsAllowlist` as passed, but `Common()` left it out and `TestDefinitions` asserted it absent; probed on slot A that `Modify` with `""` clears a list. Fixed: `Common()` passes `CorsAllowlist = ""`, the tests assert it, `TestApply` adds a list by hand and expects it gone. The other omitted keys (`Resource`, `UseCookies`, `CSRFToken`, `TwoFactorEnabled`, ...) are outside the table and stay unpassed.
    - `[low]` `patch` `test-boundaries.sh` never scans `web/src/signin/signin.js` -- `*.js` added to `in_scope` and the file to the scope list.
    - `[low]` `defer` Hash-route deep links lose their route at sign-in -- the form action and the 303 carry no fragment; no route exists yet and row 13 pins a query deep link, so it is deferred to the first story with a hash route.
    - `[low]` `patch` The path guard and 404 branch of `Shell.Serve` have no test -- row 8 now asserts 404 for a missing file, a directory and two escaping paths, with a built file as the positive control.
    - `[low]` `patch` `OCUTALON_TEST_WEB_PORT` is checked against a deny-list only -- the override must now be a number in 52800-52819 (leading zeros read as decimal) and free; refusals pinned in `test-lib-live.sh`.
    - `[low]` `reject` The signed-in shell is served with only `script-src 'self'` and can be framed -- the intent fixes this exact header for `index.html` (AD-13); the fix would edit the spec.
    - `[low]` `reject` Bundle completeness is checked through `index.html` only -- `BundleCheck` and the Dockerfile guard are specified on `index.html`; `npm run build` copies the brand images first, and stale hashed files are harmless (Design Notes).
    - `[low]` `reject` The hand-written minifiers can change what is shipped -- the current inputs minify correctly (rows 5 and 18 apply and hash the output in a browser); a guard for future edits adds complexity.
    - `[low]` `reject` `tokens.test.mjs` is not wired to any script -- the Verification lists `node --test web/scripts/` and Story 0.7 wires it into CI.
    - `[low]` `reject` The image cannot be built from a fresh clone without the bundle -- by design: the Dockerfile guard is specified and Story 11.5 force-adds the bundle on the release branch.
  - Edge Case Hunter:
    - `[low]` `reject` `Api.cls` has no role check -- same claim as the first Blind Hunter row.
    - `[low]` `reject` An image rebuilt with a new bundle at an unchanged version skips the package load -- the version gates the load (AD-23); a development load refreshes the folder.
    - `[low]` `reject` An upgrade leaves old hashed files in the durable folder -- `FileCopy` never prunes and the Design Notes call it harmless.
    - `[medium]` `patch` Application keys that `Definitions` never passes survive `Modify` -- same root cause as the second Blind Hunter row.
    - `[low]` `reject` `?IRISLoginPage=0` shows the stock token page -- needs a crafted query on a product without two-factor sign-in; the page is IRIS's own and exposes nothing, and `Show` must call `OnPage` as specified.
    - `[low]` `reject` Forced password change and two-factor codes show the wrong-credentials text -- specified: any other `Error:ErrorCode` shows it; the README account has ChangePassword 0 and a password change is never offered.
    - `[low]` `patch` A leading-zero override such as 052773 reaches a forbidden port -- same fix as the port-override row above.
    - `[low]` `reject` Two concurrent runs can pick the same free port -- one throwaway IRIS stack at a time is the project rule.
    - `[low]` `reject` The 540 s deadline starts before `ensure_web_bundle` -- the deadline is an overall budget by design.
    - `[low]` `reject` An existing `src/ocutalon/csp/index.html` is taken as current -- specified: `ensure_web_bundle` builds when it is missing, and `test-sign-in.sh` always rebuilds.
    - `[medium]` `patch` `tokens.mjs` never runs `main()` when the repository is reached through a symbolic link, so `--check` passes silently -- `import.meta.url` is a real path while `process.argv[1]` is not. Fixed with `realpathSync`; `tokens.test.mjs` runs the script through a link.
    - `[low]` `reject` `darkDifferences` misaligns when a `-dark` override changes a reference into a plain value -- a hypothetical edit of `DESIGN.md`; the current file generates correctly and the fix adds a guard.
    - `[low]` `reject` `minifyCss` rewrites ` :` in selectors -- same root cause as the minifier row above.
    - `[low]` `reject` `minifyScript` joins lines and accepts `</script>` -- same root cause as the minifier row above.
    - `[low]` `reject` `OCUTALON_URL` unset gives an invalid-URL error -- Playwright's message names the problem; a guard adds code for a developer-only slip.
    - `[false]` `reject` The spec's "CSS-valued properties" wording and the icon-name tokens -- row 9 asserts `--field-error-icon`, so emitting every non-prose property is the intended output.
    - `[low]` `patch` The Playwright failure output may echo the fixture password -- `test-sign-in.sh` replaces the password in every log tail it prints.
  - Verification Gap:
    - `[medium]` `patch` The no-role answer's Content-Security-Policy and `no-store` are not asserted -- row 12 now checks the POST answer with the shared `expectSignInPage` helper (row 3 uses it too); mutation recorded.
    - `[medium]` `patch` The Web step's rewrite on restart is not exercised -- `test-install-upgrade.sh` changes an application and the trace role by hand under V0 and expects the post-upgrade `check_security` to find them restored; mutation recorded.
    - `[medium]` `patch` `Shell.Serve`'s 404 branch and the headers of `GET /` are not asserted -- row 8 reads both headers on `/ocutalon/` and `/ocutalon/index.html`, and the new row 8 test covers the 404s; mutation recorded.
    - `[false]` `reject` `document.fonts.check` is true when no font face matches -- the same test asserts `fonts.loaded` holds the three faces with status `loaded` after `document.fonts.load`, which fails without the `@font-face` rules.
    - `[low]` `reject` Row 3 names `main-*.js` from the local build -- `test-sign-in.sh` rebuilds the bundle immediately before building the image, so both are the same build.
    - `[low]` `patch` `fingerprint_changed` may be empty and still pass -- both fingerprint checks now require a non-empty value.
    - `[low]` `patch` No `forbidOnly` in the Playwright configuration -- set to true.
    - `[low]` `reject` The `eye` and `circle-alert` branches of `icon.ts` are not rendered -- the spec asks for the three icons; the later header stories use them.
    - `[low]` `reject` `test-lib-live.sh` stubs `port_in_use` -- the real probe runs in every live test.
    - `[low]` `patch` Several acceptance criteria have no `mutation:` line -- lines written for the criteria and tests changed in this pass (AC1 structural, AC3, AC4, AC6, generator, scope and port range); AC5 re-runs the AC2 to AC4 tests on another image.
    - `[low]` `patch` `Users.TestEnsureCreates` relies on an earlier clean state -- it removes its fixture user first, like its siblings.
    - `[low]` `reject` `TestEnsureReportsAFailure` relies on the instance's password pattern -- the tests run on slot A, a known build with the default pattern.
    - `[low]` `reject` `TestGrants` reads the live registry, which a leftover `Zz` step could break -- the Registry test removes its steps in `OnAfterAllTests`.
    - `[low]` `reject` `TestApply` and `TestGrantTraceSql` assume the OCUTALON namespace -- slot A tests run there by Rule 21.
    - `[low]` `patch` The `ensure_web_bundle` success test inherits `LIVE_REBUILD_WEB` -- the call sets it to 0.
    - `[low]` `patch` Row 9 reads computed tokens right after a static title appears -- `signInReadme` waits for the load state.
    - `[low]` `reject` The `RemoveNewRoles` cleanup of `Test.Install.Registry` is not asserted -- test cleanup code, not an acceptance criterion; a leftover role would fail the next run's "no roles" assertions.
  - Intent Alignment:
    - `[low]` `reject` The role check covers the `/ocutalon` dispatch class only, not the API or the trace application -- same root cause as the first Blind Hunter row.
    - `[false]` `reject` The Sign out link is a GET to `?IRISLogout=end` -- the Tasks specify it until Story 2.2.
    - `[false]` `reject` `Test.Install.Registry` creates the real roles on slot A -- the Tasks specify it, and the test deletes the roles it created.
    - `[low]` `reject` The form contract (`InsertHiddenFields`, superclass `OnPreHTTP`) has no direct assertion -- rows 6, 8, 12 and 13 sign in through the form, so a broken contract fails them.
    - `[false]` `reject` No check scans `Web/Public` for forbidden references -- the allow-list check over the public classes is Story 0.7's.
    - `[low]` `reject` The gitignored bundle and the judges' compose path -- same root cause as the fresh-clone row above.
    - `[false]` `reject` The 401 and the trace login form come from inheritance and configuration -- descriptive; row 4 asserts both on the wire.
    - `[false]` `reject` The UX texts are transcribed, not linked -- descriptive; Story 0.4 adds the catalog comparison.

## Design Notes

**ADs:**
- AD-2: one package, plus the bundle through `FileCopy`.
- AD-3: the public package and its allow-list.
- AD-5: the account is durable seed.
- AD-13: applications, group, login page, CSP, post-sign-in check.
- AD-19: structural or seed.
- AD-22: throwaway stacks, Playwright under `web/e2e/`.
- AD-23: order, static files in `${dataDir}`, image recipe.
- AD-24: roles, the trace application, forbidden grants.
- AD-29: lanes. `Users` and `Roles` are Lane A's; `Web`, `OcuTalon.Web.*` and `web/` are Lane B's; Epic 0 is one runner.

Spikes S1, S7 and S16.

**AD-13 amendment this plan rests on (Rule 20, the lead's).** On build 154, AD-13's classic `/ocutalon` application cannot show its login page at `/ocutalon/`, nor serve the logo before sign-in (probes, Code Map).

Recommended wording:
- `/ocutalon` is a `%CSP.REST`-dispatched application:
  - password authentication;
  - `Path` `${dataDir}csp/ocutalon/`, with `ServeFiles` 3;
  - dispatch class `OcuTalon.Web.Public.Shell`.
- Its `Login()` renders `OcuTalon.Web.Public.Login` for every request without a session, and serves only the five sign-in images.
- After sign-in it runs the user-role check and serves the built files through `%CSP.StreamServer`.
- `PermittedClasses` applies to the trace applications.
- AD-3's public package also holds the shell and the generated `SignInAssets`.
- The WebSocket (AD-12, second) is forwarded by the shell or moved to its own application, decided by its story.

**Applications** (every key passed to `Create`/`Modify`):

| Key | `/ocutalon` | `/ocutalon/api` | `/ocutalon/trace/ocutalon` (`TraceApp`) |
|---|---|---|---|
| NameSpace / Enabled / AutheEnabled | OCUTALON / 1 / 32 | same | same |
| DispatchClass | `OcuTalon.Web.Public.Shell` | `OcuTalon.Web.Api` | "" |
| Path / ServeFiles | `DataDirectory()_"csp/ocutalon/"` / 3 | "" / 0 | "" / 1 (S7) |
| GroupById / SessionScope / Timeout | `OcuTalon` / 2 / 28800 | same | same |
| CookiePath | `/ocutalon/` | `/ocutalon/` | `/ocutalon/trace/ocutalon/` |
| MatchRoles | `:%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE` | same | "" |
| PermittedClasses | "" | "" | `1(1"%CSP.Broker",1"EnsPortal.VisualTrace",1"EnsPortal.SVG.VisualTrace",1"EnsPortal.VisualTraceLegend",1"EnsPortal.SVG.TraceLegend",1"EnsPortal.MessageContents",1"EnsPortal.MessageViewer")` |
| LoginPage / CSPZENEnabled / InbndWebServicesEnabled / IsNameSpaceDefault / AutoCompile | "" / 1 / 0 / 0 / 0 | "" / 1 / 0 / 0 / 0 | "" / 1 / 0 / 0 / 0 |
| CorsAllowlist | empty | empty | empty |

- The application roles are the merge's `%DB_` roles, so no new role is added (AD-24's list is unchanged).
- The trace application takes S7's tested values.
- Local timeouts only. Story 16.4 adds the online demo's 120 s.

**Sign-in images (the only files served without a session):** `assets/brand/OcuTalon-Logo-{light,dark}-{640,1280}.png` and `assets/brand/favicon-32.png`. `img-src 'self'` allows them, and they need no `data:` URI. Fonts on the sign-in page are system stacks, because `default-src 'none'` blocks font loads (the Conventions allow system fonts).

**The bundle.**
- `npm --prefix web run build` writes `src/ocutalon/csp/`. That folder is ignored on development branches, and the release story (11.5) force-adds it.
- The Dockerfile refuses an image without it.
- IPM's `FileCopy` puts it in `${dataDir}csp/ocutalon/` on install, on upgrade and on every `OCUTALON_DEV` load, and never prunes stale hashed files (harmless).
- The epic branch commits sources, `package-lock.json`, the generated `tokens.css` and `SignInAssets.cls`, and the vendored fonts and licences.

**Decisions:**
- **Component library: the Angular CDK plus custom components.** This is a Stack row for the lead (Rule 20), as are the vendored Lucide paths (ISC) and fonts (OFL), which UX-DR10 and UX-DR15 name.
- **Sign out** uses `?IRISLogout=end` until Story 2.2 moves it to the API. Probe: it ends the whole group.
- **No CSRF token on the sign-in POST.** A dispatched sign-in emits none (probe). Login CSRF on a local install is the residual risk; `form-action 'self'` and `SessionScope` strict stay.
- **Declined (0.2's Consumed-by):** the login page reads no public setting yet. Its first read is 16.2's splash on `onlineDemo`.

**Reuse (Rule 2):**
- every step extends `OcuTalon.Install.Step` and uses `Registry.Declared` through `Roles`;
- `Shell` adapts `%ZHSLIB.REST.AngularHandler`, which is HS-only and outside AD-3's allow-list;
- `test-sign-in.sh` uses `lib-live.sh`;
- the hash generator follows S16.

**Integration ACs:**
- the `Roles` step (consumer) composes `Users`' and `Web`'s `Grants()` into the roles of row 1;
- the shell (consumer) renders with the generated `tokens.css` (row 9);
- `Login` (consumer) serves `SignInAssets`' CSS and script under hashes the browser enforces (rows 3 and 5).

**Consumes:**
- 0.2: the registry, `Step`, `Roles`, the public-class check, `lib-live.sh`;
- 0.1: `merge.cpf`'s databases, `%DB_` roles and public mappings, and the web port.

**Consumed-by:**
- 0.4: catalog comparison with `Login`'s texts.
- 0.5: `Api` routes, `/ocutalon/public` in `Web`, the role check in `Api.OnPreDispatch`.
- 0.6: `Web.TraceApp("OCUORDERS")` from `Demo`.
- 0.7: CI runs the build, `tokens --check`, `node --test`, `test-sign-in.sh`, and the allow-list check over the new public classes.
- 0.8: `web/playwright.config.ts` and `signIn()`.
- 2.1: header, theme (`data-theme`), badge, About.
- 2.2: `SessionEvents`, Sign out through the API.
- 10.2: the README's password change.
- 16.2: splash.
- 16.4: timeouts.
- 16.5: busy.

**Size (for the lead):** this is two goals and oversized. If it needs splitting, the natural line is 0.3a (the steps, the applications, `Shell`, `Login` and `SignInAssets`, rows 1–7 and 10–20) and 0.3b (the Angular shell, tokens and fonts, rows 8–9).

**Ledger inbox:** none.

## Verification

**Commands:**
- `(loop)` `npm --prefix web ci` (`timeout: 600000`). Expected: exit 0.
- `(loop)` `npx --prefix web playwright install chromium` (`timeout: 600000`). Expected: exit 0; it does nothing once the browser is cached.
- `(loop)` `node --test web/scripts/`. Expected: exit 0 (row 19).
- `(loop)` `node web/scripts/tokens.mjs --check`. Expected: exit 0.
- `(loop)` `npm --prefix web run build` (`timeout: 600000`). Expected: exit 0; `src/ocutalon/csp/index.html` exists with no inline `<script>`; `3rdpartylicenses.txt` and `assets/licenses/` are present.
- `(loop)` One per call: `bash docker/tests/test-compose-file.sh`, `test-build-inputs.sh`, `test-boundaries.sh`, `test-lib-live.sh`, `test-pinned-sources.sh`. Expected: exit 0 each.
- `(loop)` `bash docker/tests/test-sign-in.sh` (`timeout: 600000`). Expected: exit 0 in under 9 minutes, with nothing named `ocutalon-t03-*` left behind.
- `(loop)` `bash docker/tests/test-install-start.sh`, then `bash docker/tests/test-install-upgrade.sh`, one per call (`timeout: 600000`). Expected: exit 0 each.
- `(loop)` First `iris_server_info` (build 154, port 52790). Then `iris_doc_load` with `server: ocutalon-slot-a`, `namespace: OCUTALON`, `compile: true`, `flags: "ck"`, as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Then `iris_execute_tests` with `level: class`, one call each, waiting for each before the next: `OcuTalon.Test.Install.Users`, `OcuTalon.Test.Web.Install`, `OcuTalon.Test.Web.SignIn`, `OcuTalon.Test.Install.Registry`. Expected: 0 failed, and no `Zz` fixture left.
- `(once)` One per call, `timeout: 600000`: `bash docker/tests/test-compose-start.sh`, `test-after-start.sh`, `test-healthcheck.sh`, and `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-sign-in.sh`. Expected: exit 0 each.
- `(once)` `iris_execute_tests` for `OcuTalon.Test.Data.PublicSettings`, then `OcuTalon.Test.Install.PrivateData`. Expected: 0 failed.
- `(once)` `git status --short`. Expected: only the files in Tasks.

**Shared surfaces:**
- Security objects: roles, the user `ocutalon` and the three applications. Slot A tests use only `Zz` fixtures, and `TestRolesStep` deletes the roles it created.
- The Dockerfile now needs the bundle, so every live test and `test-build-inputs.sh` are affected.
- The `.gitignore` and `.gitattributes` pins, and `test-boundaries.sh`'s scope.
- The public-class list of `after-start.cos` gains `Login`, `Shell` and `SignInAssets`.
- `LIVE_FILES` stays at 3 base entries; the port override is added after them.
- Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate (Rule 19):**
- Rows 1–2:
  - drop `%Ens_MessageContent` from `Web.Grants()` → `test-sign-in.sh` red (row 1) and `Test.Web.Install` red;
    - mutation: removed the `%Ens_MessageContent` grant from `Web.Grants()` -> `test-sign-in.sh` "rows 1-2" red (the trace role's resources differ) and `OcuTalon.Test.Web.Install:TestGrants` red (six grants, Use on `%Ens_MessageContent`, the registry's six); reverted, tree unchanged.
  - `GroupById` `""` on the API application → row 10 red.
    - mutation: `Set api("GroupById") = ""` in `Web.Definitions` -> `test-sign-in.sh` "rows 1-2" red and Playwright `row 10: the API and the trace application share the session` red. Row 10 stayed green at first, because `/ocutalon` and `/ocutalon/api` share the CSP session through the same `CookiePath`; row 10 now also clears the shell's session cookie and expects the API to answer 404 from the group's login (without the group it answers 401). Reverted, tree unchanged.
- Rows 3 and 4:
  - `Login()` serves any file → row 4 red (`icon-192.png`);
    - mutation: `Shell.Login` also streams every `assets/` file -> Playwright `row 4` red (`icon-192.png` answers `image/png`, not the sign-in page); reverted, tree unchanged.
  - `ServeFiles` 1 with no dispatch → row 3 red.
    - mutation: `shell("DispatchClass") = ""` and `shell("ServeFiles") = 1` in `Web.Definitions` -> Playwright `row 3` red (`/ocutalon/` answers 404, not the sign-in page), rows 8 to 11 red with it (no sign-in form to fill in), and `test-sign-in.sh` "rows 1-2" red; reverted, tree unchanged.
- Row 6: `OnLoginPage` ignores 822 → red.
  - mutation: `Login.Message` treats code 822 like 864 (no error) -> Playwright `row 6` red and `OcuTalon.Test.Web.SignIn:TestWrongPassword` red; reverted, tree unchanged.
- Row 12: delete the role check in `OnPreDispatch` → red.
  - mutation: `Shell.OnPreDispatch` quits OK without calling `HasRole()` -> Playwright `row 12` red; reverted, tree unchanged. A second mutation of the same test: `Shell.OnPreDispatch` calls `Show("norole")` with the header written again inside the dispatch -> Playwright `row 12` red (the response header text appears in the page); reverted.
- Row 9: generator drops `-dark` → red.
  - mutation: `tokens.mjs` resolves every colour to its light value (`tokens.css` and `SignInAssets.cls` regenerated, the bundle rebuilt) -> Playwright `row 9` and `row 5: the page in the dark scheme` red, and `node --test web/scripts/` red (3 tests); regenerated and rebuilt from the original generator, tree unchanged.
- Row 15: `Ensure` resets the password when the account exists → red.
  - mutation: `Users.Ensure` sets the given password on an existing account -> `test-install-upgrade.sh` "row 15: the upgrade changed the README account" red and `OcuTalon.Test.Install.Users:TestEnsureKeepsAnExistingAccount` red; reverted, tree unchanged.
- Row 18: hash over CSS plus one byte → red.
  - mutation: `Login.StyleHash` hashes `css_"x"` -> `OcuTalon.Test.Web.SignIn:TestPolicy` red, and in the browser Playwright rows 3, 5 (light and dark), 8 and 12 red (the page's style is blocked); reverted, tree unchanged.
- Row 19: a reference left unresolved → red.
  - mutation: `resolveText` in `tokens.mjs` returns its input unchanged -> `node --test web/scripts/` red (4 tests, among them "resolves every reference" and "an unresolved reference"); reverted, tree unchanged.
- Row 20: delete the guard → red.
  - mutation: removed the `test -f /opt/ocutalon/src/ocutalon/csp/index.html ...` line from `docker/Dockerfile` -> `test-build-inputs.sh` red ("an image was built from a context without src/ocutalon/csp/") and `test-compose-file.sh` red (the guard pin); reverted, tree unchanged.

**Mutations added in the review pass (Rule 19):**
- AC1, structural applications (AD-19), CORS list:
  - mutation: `Set props("CorsAllowlist") = ""` removed from `Web.Common` -> `OcuTalon.Test.Web.Install:TestDefinitions` red (all three applications), `:TestTraceApp` red, and `:TestApply` red ("the CORS list added by hand is gone"); reverted, tree unchanged.
  - mutation: `Web.Apply` quits OK for an application that exists instead of calling `Modify` -> `test-install-upgrade.sh` "row 15 after the upgrade: roles, README account, sign-in policy and applications (1 of 9 values differ)" red (the hand-set `Timeout` 100 and the CORS list survive the upgrade); reverted, tree unchanged.
- AC4, row 12 headers:
  - mutation: `Login.Show` runs `OnPreHTTP` only when `writeHeader` is 1 -> Playwright `row 12` red (the no-role answer has no Content-Security-Policy); reverted, tree unchanged.
- AC3, row 8 served files:
  - mutation: `Shell.File` serves `index.html` for every path -> Playwright `row 8: a missing file, a directory and a path that leaves the folder answer 404` red, with `row 8` (the font answers the page's policy), `row 9` and `row 11` red; reverted, tree unchanged.
  - Deleting the `..`/leading-slash/backslash guard in `Shell.Serve` leaves every test green: the CSP gateway and `%CSP.StreamServer` answer 404 for those paths themselves, so the guard is defence in depth and the 404 outcome is what the test pins.
- AC6, generated files current:
  - mutation: one line appended to `web/src/styles/tokens.css` -> `npm --prefix web run build` exits 1 ("tokens.css is stale"); reverted, tree unchanged.
- AC5 re-runs the AC2 to AC4 pinning tests on the non-Health base image, so their mutations above are its mutations.
- Row 19, script path: `tokens.mjs` compares `resolve(process.argv[1])` instead of `realpathSync(process.argv[1])` -> `node --test web/scripts/` red ("runs when the script is reached through a symbolic link"); reverted, tree unchanged.
- Boundaries scope: `*.js` removed from `in_scope` in `test-boundaries.sh` -> "scope" red ("not scanned: web/src/signin/signin.js"); reverted, tree unchanged.
- `live_web_port` range: the range test of the override removed -> `test-lib-live.sh` red for `052773`, `0`, `80`, `99999`, `52799` and `52820`; reverted, tree unchanged.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A judge can now sign in. The `Roles`, `Users` and `Web` steps create the three roles, the README account (`ocutalon`, seed, created once) and the three web applications in one sign-in group (`OcuTalon`). `/ocutalon` is a `%CSP.REST` application dispatched by `OcuTalon.Web.Public.Shell`: a request without a session gets the branded sign-in page `OcuTalon.Web.Public.Login` (hash-pinned inline style and script, five images only), a signed-in user without `OcuTalonUser` gets the no-role page and loses the session, and a user with the role gets the Angular shell that IPM copies to the durable `csp/ocutalon/` folder. One generator (`web/scripts/tokens.mjs`) turns `DESIGN.md` into `tokens.css` and `SignInAssets.cls`.

**Files changed.**
- IRIS steps: `Install/Step/Users.cls` (`Ensure`, `Grants`), `Install/Step/Web.cls` (`Definitions`, `TraceApp`, `Apply`, `BundleCheck`, `GrantTraceSql`, `Grants`).
- Web classes: `Web/Public/Shell.cls`, `Web/Public/Login.cls`, `Web/Public/SignInAssets.cls` (generated), `Web/Api.cls` (empty URL map).
- Package and image: `src/module.xml` (`FileCopy`), `docker/Dockerfile` (bundle guard), `.gitignore`, `.gitattributes`.
- `web/`: Angular 22.2.3 shell (header, CDK account menu, hidden `h1`), `tokens.mjs` with `tokens.test.mjs`, `brand.mjs`, fonts and licences, `signin.css` and `signin.js`, Playwright config and the three specs.
- Tests: `Test/Install/Users.cls`, `Test/Web/Install.cls`, `Test/Web/SignIn.cls`, `Test/Install/Registry.cls`; `docker/tests/test-sign-in.sh` (new), `lib-live.sh`, `test-install-start.sh`, `test-install-upgrade.sh`, `test-build-inputs.sh`, `test-compose-file.sh`, `test-boundaries.sh`, `test-lib-live.sh`.

**Review.** Four layers reported 53 findings (high 0, medium 6, low 40, false 7). Five medium entries and nine low ones were patched, one low was deferred, the rest were rejected with the reasons in the triage log.
- Patched, medium: the CORS allow-list is now passed empty (Design Notes table); the no-role answer's headers are asserted; the Web step's rewrite is exercised by the upgrade test; `Shell.Serve`'s 404 branch and the `GET /` headers are asserted; `tokens.mjs --check` no longer passes silently when reached through a symbolic link.
- Patched, low: `signin.js` is scanned; the port override is range-checked; the fixture password is redacted from failure output; `forbidOnly`; a non-empty fingerprint check; self-contained `Users` test; `LIVE_REBUILD_WEB` reset in `test-lib-live.sh`; row 9 waits for the load state; mutation lines written.
- Deferred (frontmatter): hash-route deep links lose their route at sign-in (low).
- Follow-up review recommended: true. Risk: five medium entries were patched after the layers reported and no layer re-read them. The patched code and tests were run and mutation-checked here, and the `..` guard in `Shell.Serve` cannot be shown to matter (deleting it leaves every test green, because the gateway answers those paths 404).

**Amendments for the lead (Rule 5, first tier, applied and reported).** The Design Notes table said `CSPZENEnabled` 0 on `/ocutalon` and `/ocutalon/api`; it is 1 on all three applications. Measured on build 154 (Health and non-Health image): with 0 a signed-in request never reaches the dispatch class. The value is in no AD, so the spine is unchanged; see the Spec Change Log.

**Verification performed.**
- `npm --prefix web ci`, `playwright install chromium`, `node --test web/scripts/` (23 pass), `tokens.mjs --check`, `npm --prefix web run build` (no inline script, `3rdpartylicenses.txt` and `assets/licenses/` present): all exit 0.
- `test-compose-file.sh`, `test-build-inputs.sh`, `test-boundaries.sh`, `test-lib-live.sh`, `test-pinned-sources.sh`: exit 0 each.
- Live, one throwaway project each, nothing left behind: `test-sign-in.sh` (13 Playwright tests pass, about 50 s), `test-install-start.sh`, `test-install-upgrade.sh`, `test-compose-start.sh`, `test-after-start.sh`, `test-healthcheck.sh`, and `test-sign-in.sh` with `IRIS_IMAGE=iris-community:2026.3.0AI.154.0`: exit 0 each.
- Slot A (`ocutalon-slot-a`, OCUTALON): `Test.Install.Users` (4), `Test.Web.Install` (6), `Test.Web.SignIn` (9), `Test.Install.Registry` (11), `Test.Data.PublicSettings` (5), `Test.Install.PrivateData` (5): 0 failed; no `Zz` fixture, `OcuTalon*` role, `ocutalon` user or `/ocutalon*` application left.
- Matrix Test Audit: every row 1 to 20 has a covering test that ran and passed (rows 1 to 2 in `check_security`, 3 to 13 in the 13 Playwright tests, 14 and 15 in the install tests, 16 to 18 in the three `%UnitTest` classes, 19 in `node --test`, 20 in `test-build-inputs.sh`).
- Mutations: every line in `## Verification` was applied, observed red and reverted, with `git status --short` unchanged afterwards.

**Residual risks.**
- The Docker image cannot be built from a fresh clone of a development branch without Node and a built bundle (specified; Story 11.5 force-adds the bundle on the release branch).
- The API and the trace application have no role check of their own: the API answers 404 to everything until Story 0.5, and the trace application is gated by the trace role's resources.
- A hash-route deep link is lost at sign-in (deferred).
- Anything written through the editing tools turns a `\uXXXX` escape into the literal character; `test-boundaries.sh` catches it.
