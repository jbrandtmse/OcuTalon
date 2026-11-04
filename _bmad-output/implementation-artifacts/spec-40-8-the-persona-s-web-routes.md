---
title: "Story 40.8: The persona's web routes"
type: 'feature'
created: '2026-11-04'
status: 'done'
baseline_revision: '6ccc3838e5e876d27116d02ac6a6814c2453a1dd'
baseline_commit: '6ccc3838e5e876d27116d02ac6a6814c2453a1dd'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-40-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 40.2 built the persona's save and read in `SettingsOps`, but nothing on the web reaches them, so the page can neither show nor change a person's persona and Story 40.4's card has nothing to call.

**Approach:** Add `GET` and `PUT /v1/persona` to `OcuTalon.Web.Api`. `GET` answers `SettingsOps.Persona` for the signed-in session. `PUT` submits `SetPersona` through `Commands.Submit` with origin `web_user` and turns the `CommandResult` into an HTTP answer. No other product class changes, and no page change (Story 40.4).

## Boundaries & Constraints

**Always:**
- The `SessionRef` comes from `Ownership.SessionRef` only; a `sessionRef` in the body is ignored (AD-4, AD-19).
- `SettingsOps` stays the one validator and the one writer: the route checks only the body's shape and passes `preset`, `language` and `custom` on unchanged (AD-19).
- Every sentence the routes send is one that already exists: `result.Message` as the owner gave it, or an existing parameter. **No new text and no new `Parameter MESSAGE...`.** Refusal texts are EXPERIENCE.md's, unchanged, and they already live in `SettingsOps`.
- Smallest footprint in `Web/Api.cls` (Epic 33 goes first there): two route lines appended at the end of the `UrlMap`, and the handlers as ONE self-contained block appended at the end of the class, just before its closing brace. The class comment at the top is not edited; the block's own doc comments carry the contract.
- Every error is `{"error": {"code", "message"}}` through `Fail` or `ServerError`.
- A persona value keeps its JSON string type in both answers, also when it looks like a number (`custom` of `12345`).
- ObjectScript and TypeScript source stay ASCII; a non-ASCII test character is `$Char(...)` or a `\u` escape (Rule 14). Comments state the contract, never the history.

**Never:**
- Any change to `Core/SettingsOps.cls`, `Core/SessionOps.cls`, `Core/CommandsIn.cls`, `Test/Core/SettingsOpsProbe.cls`, `Test/Msg/Contracts.cls`, anything under `web/src/`, `docker/**` (a new `docker/tests/` file included), `Install/**`, `src/module.xml`, `module.xml`, `preload/**`, `src/cpf/**` or `release/**`. If the routes turn out to need one, stop with `## Clarification Needed`; the same goes for a web-application or role change that a real `PUT` might need.
- Reading a `SessionRef` from the client, or a write to `OcuTalon.Data.Setting` from web code (`Test.Core.SettingsOps.TestOnlyRunTimeWriter` scans for it).
- A `ProposePersona`, a `setting` approval or a persona block (Stories 40.3, 40.5, 40.6). `pendingRef` only reports a request that exists.
- A real model key or a real Telegram bot; any target but lane A's slot and this stage's tagged throwaways.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Read, nothing saved | `GET`, session with no keys | 200 `{"preset":"professional","language":"","custom":"","customOffered":true,"pendingRef":""}`, keys in that order | No error expected |
| Read, saved values | `GET` after a saved `language` of Spanish | 200 with `preset` `language`, `language` Spanish | No error expected |
| Read, online demo | `GET`, `onlineDemo` 1 | 200 with `customOffered` false | No error expected |
| Read, pending request | `GET`, the session owns pending `setting` requests | `pendingRef` is the newest one's `Ref`; a `fix` request, an answered request and another session's request are not reported | No error expected |
| Read fails | `SettingsOps.Persona` gives an error status | 500 `server_error`, cause logged, no values sent | `ServerError` |
| Accepted preset | `PUT {"preset":"pirate"}` | 200 `{"result":"done","message":"Saved. Applies from your next message. Recorded in the audit log.","preset":"pirate","language":"","custom":""}`; the three keys hold it; one `Settings` audit entry, channel `web`, `from` the old form and `to` `pirate`; the command's `Origin` is `web_user` | No error expected |
| Accepted language, outside ASCII | `PUT {"preset":"language","language":"Português (Brasil)"}`, UTF-8 bytes | 200; `language` comes back as the same characters in `PUT` and `GET`; the entry's `to` is `language: ` and the name | No error expected |
| Accepted custom | `PUT {"preset":"custom","custom":"12345"}` on a local install | 200; `custom` is the JSON string `"12345"` in `PUT` and `GET`; no audit entry holds the text | No error expected |
| Values the preset does not use | `PUT {"preset":"pirate","language":"!!","custom":"{{"}` | 200, both stored empty (SettingsOps' rule, unchanged) | No error expected |
| Refused language name | `PUT {"preset":"language","language":"Spanish!"}` | 400, code `bad_language`, "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters." | Keys and audit log unchanged |
| Refused custom | `custom` of 1,001 characters, or holding `{{` or `@{` | 400, code `bad_custom`, "Use up to 1,000 characters, without {{ or @{." | Keys and audit log unchanged |
| Online demo refuses custom | `PUT {"preset":"custom","custom":"zz"}`, `onlineDemo` 1 | 400, code `custom_not_offered`, "On the online demo you can choose a preset or a language. Your choice lasts for this visit." | Keys and audit log unchanged |
| Online demo, a preset | `PUT {"preset":"kindfriend"}`, `onlineDemo` 1 | 200 as for any accepted preset | No error expected |
| Unknown preset | `PUT {"preset":"zz"}` or `{"preset":""}` | 400, code `bad_preset`, "Couldn't save. Nothing was changed." | Keys and audit log unchanged |
| Bad body | Not JSON, not an object, `preset` absent or not a string, `language` or `custom` present and not a string (`null` included), or no body | 400, code `bad_persona`, "Couldn't save. Nothing was changed." | Nothing is submitted: no header from `CommandsIn` to `SettingsOps` |
| Another session in the body | `PUT {"preset":"pirate","sessionRef":"<other>"}` | The caller's own persona changes; the other session's keys do not | No error expected |
| Save failed | Outcome `no_session`, `not_audited`, `failed` or any other not named here | 500, code `not_saved`, message `result.Message` as given: "Couldn't save. Nothing was changed." from `SettingsOps`, "Something went wrong inside OcuTalon, so the command may not have finished." from `CommandsIn` | Never a claim that nothing changed unless the owner said so |
| Stub owner | Outcome `not_built` | 501 `not_built`, `MESSAGENOTBUILT` | As `Unpair` and `DismissIncident` |
| Command not delivered | `Submit` gives an error status, or no result object | 500 `server_error` | `ServerError` |
| No OcuTalon session | `Ownership.SessionRef` gives an error status, on `GET` or `PUT` | 500 `server_error`; nothing written | `ServerError` |
| Signed out, real HTTP | `GET` or `PUT` with no session, with the envelope whole or broken | 401 `signed_out`, no `WWW-Authenticate` | `ApiBase.Login`, unchanged |
| Broken envelope, real HTTP | Signed-in `PUT` without `X-OcuTalon-Request`, or not JSON | 403 `no_request_header`, `not_json` | `OnPreDispatch`, unchanged; nothing written |
| Other method, real HTTP | Signed-in `POST /v1/persona` | 405 `method_not_allowed`, `Allow` names `GET` and `PUT` | `ReportHttpStatusCode`, unchanged |

</intent-contract>

## Code Map

All paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `web/` or `docker/`.

- `Web/Api.cls` -- the file to change. `UrlMap` lines 125-140 (the last route, `DELETE /v1/pairing`, is line 139); the class ends at line 1035.
  - Handler siblings: `Unpair` line 709 (session, `Commands.Submit`, `not_built`, 500), `DismissIncident` line 563 (the same, with outcomes mapped to statuses).
  - Body sibling: `MarkerBody` line 623 and `AnswerBody` line 497 (`%FromJSON(..BodyText())` in a `Try`, `%GetTypeOf`).
  - Seam siblings: `Post`, `Press`, `Mail` (lines 320, 331, 371).
  - Helpers to reuse: `BodyText` line 304 (decodes the UTF-8 body), `Fail` line 979 (handles 400, 409, 500, 501; its `extra` copy keeps JSON types with the iterator's `type`), `ServerError` line 171.
- `Core/SettingsOps.cls` -- read only. `Persona(sessionRef, Output sc)` line 305 answers exactly the `GET` body; `SavePersona` line 184 gives the outcomes `saved`, `bad_preset`, `bad_language`, `bad_custom`, `custom_not_offered`, `no_session`, `not_audited`, `failed`, with `Data` the saved values as JSON; `MESSAGENOTSAVED` line 46 is the bad-body text; `PersonaKey` line 289 and `ForgetPerson` line 332 serve the tests' reads and clean-up.
- `Core/Commands.cls` -- read only. `Submit(command, origin, Output result)`: an error status means the command never reached `CommandsIn`.
- `Core/CommandsIn.cls` -- read only. `SetPersona` is routed to `SettingsOps` from `web_user` only (line 176). `MESSAGEFAILED` (line 52) is its `failed` text, used on a timeout (`TIMEOUT` 120 s), when the write may still finish.
- `Msg/Command/SetPersona.cls`, `Msg/CommandResult.cls` -- read only. `Preset`, `Language`, `Custom`; `Ok`, `Outcome`, `Message`, `Data`.
- `Data/Ownership.cls` -- read only. `SessionRef(.sc)` line 141; with no CSP session it gives an error.
- `Data/Setting.cls` -- read only. `onlineDemo` is a public key, read uncached by `Get`, so a test's `Public.Settings.Set` reaches the `SettingsOps` job at once (no 60-second wait).
- `Web/Public/ApiBase.cls` -- read only. `Login` answers 401 `signed_out`.
- `Test/Web/PairingApi.cls` -- the model for the new test class: `Guard`, `Session`, `Call` (stand-in request, `Test.Web.Api.Written`), `noSession`, `OnAfterAllTests` clean-up (`Fixture.RemoveMessages`, `Fixture.Clean`).
- `Test/Web/Api.cls` -- `TestRoutes` line 948 pins the exact route list and the count 12; `Routes` line 1271; `Written` line 1359.
- `Test/Web/MailboxApi.cls` (`TestRoutes` line 213), `Test/Web/BreakFeedApi.cls` line 133 -- read the `UrlMap` for their own lines; they stay green.
- `Test/Web/StubRequest.cls` -- `MakeBody(application, json, binary)` gives a UTF-8 byte body.
- `Test/Web/ApiProbe.cls` -- the pattern for a subclass of `Web.Api` that overrides private seams.
- `Test/Core/SettingsPersona.cls` -- `TestPersonaRead` line 269 makes pending requests with `Test.Data.Fixture.Approval(session, "", "pending", time, {"Kind": "setting"})`.
- `Test/Bridge/AuditLog.cls` -- `Entries(since, source, type, event, marker)` reads the real audit log; `Test/Data/Fixture.cls` -- `Between(Headers(trace), 1, "CommandsIn", "SettingsOps")` counts commands that reached the owner.
- `web/e2e/api/pairing.spec.ts` -- the model for the new spec; `web/e2e/api/api.spec.ts` lines 344-364 for the 401 and 405 cases; `web/e2e/sign-in/helpers.ts` (`README_ACCOUNT`, `envelope`, `signInOverHttp`); `web/e2e/support/iris.ts` (`irisScript`, `chk`, `quoted`). `web/playwright.config.ts` runs one worker, so specs do not overlap.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- append `<Route Url="/v1/persona" Method="GET" Call="GetPersona"/>` and `<Route Url="/v1/persona" Method="PUT" Call="PutPersona"/>` after the last route; append one block before the closing brace: `GetPersona`, `PutPersona`, and the private `PersonaBody(Output preset, Output language, Output custom) As %Boolean`, `ReadPersona(sessionRef, Output sc)` and `SubmitPersona(command, Output result) As %Status`, as the matrix says -- the two seams are one-liners over `SettingsOps.Persona` and `Commands.Submit(command, "web_user", .result)`, so that a test can reach the failures the real items never give.
- `src/ocutalon/cls/OcuTalon/Test/Web/PersonaApiProbe.cls` -- new, `Extends OcuTalon.Web.Api`, no Test methods: `SubmitPersona` and `ReadPersona` answer from `^OcuTalonTest("PersonaApiProbe", ...)` -- stands in for a failing owner and a failing read.
- `src/ocutalon/cls/OcuTalon/Test/Web/PersonaApi.cls` -- new test class, every matrix row but the three real-HTTP ones, through the real production as `PairingApi` does: `Guard` fails every test where `OcuTalon.Production` does not run; the failure rows go through `PersonaApiProbe`. Expected texts are written out, never read from `SettingsOps`. It saves and puts back `onlineDemo`, and in `OnAfterAllTests` calls `SettingsOps.ForgetPerson` for each fixture session, then removes messages and rows. Area `Web` is already in shard `lane-b`, so `ci/units.sh` does not change.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- in `TestRoutes` only: add `GET /v1/persona GetPersona` and `PUT /v1/persona PutPersona` at the end of `expected`, and change 12 to 14 in the count, its label and the doc comment -- the exact-list pin must stay exact.
- `web/e2e/api/persona.spec.ts` -- new, the Rule 3 evidence over real HTTP on the README account: the three real-HTTP matrix rows; `GET` defaults; a `PUT` of a language outside ASCII, then `GET` and the row read through `irisScript`; a refused language name with the row unchanged. It finds the session by `IrisUser` in `irisScript`, calls `SettingsOps.ForgetPerson` before the first case and in `finally`. It needs no new fixture user, so `docker/tests/test-sign-in.sh` does not change. These are the first `PUT` calls any stack answers, so they also prove the method passes the web gateway; if it does not, stop with `## Clarification Needed`.

**Acceptance Criteria:**
- Given a signed-in person, when `PUT /api/v1/persona` carries acceptable values, then `SetPersona` is submitted with origin `web_user` for that person's own session, the answer is 200 with the saved `preset`, `language` and `custom` and the Saved sentence, and the keys and one `Settings` audit entry show the change (FR-67, FR-68).
- Given a signed-in person, when `PUT` carries a refused value (a bad language name, a bad custom text, an unknown preset, or `custom` on the online demo), then the answer is 400 with the outcome as its code and EXPERIENCE.md's sentence as its message, and no key and no audit entry changes (FR-67, FR-68).
- Given any person, when `GET /api/v1/persona` is called before and after a change, then it answers their preset, language and custom text (Professional by default), `customOffered`, and the `Ref` of the newest pending persona request or "" (FR-67, FR-70).
- Given a request with no signed-in session, when it calls `GET` or `PUT /api/v1/persona` over HTTP, then it is answered 401 `signed_out` like every session-checked route and nothing is written.
- Given a save that fails or may not have finished, when `PUT` answers, then the status is not 2xx, and the message says only what the owner said (`result.Message`), so no failure claims that nothing changed unless the owner did.
- Given a body that names another session, when `PUT` is accepted, then only the caller's persona changes (AD-4).
- Given the tests of `OcuTalon.Test.Web`, when they run, then they cover an accepted `PUT`, a refused language name, the online demo's refusal of `custom`, a `GET` before and after a change, and a request without a session.

## Spec Change Log

## Review Triage Log

### 2026-11-04 — Review pass
- verdicts: 14 findings (the same claim from several layers shares one row) — high 0, medium 0, low 14, false 0, maybe-false 0; 5 patched, 9 rejected
- findings:
  - `[low]` `patch` Ok result with an empty `Message` answers 200 with the server-error sentence (blind, edge-case, verification-gap) — real in code, unreachable today because `SettingsOps` always sets `Message`; patched with the existing `SettingsOps.#MESSAGESAVED` for an Ok result and pinned by `TestPutOkFromOwner`.
  - `[low]` `reject` Refusal outcome with an empty `Message` answers 400 with the server-error sentence (edge-case) — `wontfix-theoretical`: every `SettingsOps` outcome carries its message; reopen_if an owner outcome without `Message` is observed.
  - `[low]` `patch` Ok result with unparseable `Data` is 500 and has no test (blind, verification-gap) — the 500 is the honest answer to a result the route cannot read; added the probe-driven case to `TestPutOkFromOwner`.
  - `[low]` `reject` No length bound on `language`/`custom` before the command is stored (blind, edge-case) — by-design: the intent has the route check the shape only and `SettingsOps` the only validator (AD-19); the gateway bounds the body.
  - `[low]` `reject` Zero-entry audit assertions are point-in-time reads (blind, verification-gap) — `wontfix-accepted`: the route writes no audit entry, `SettingsOps` is Story 40.2's and pinned there; reopen_if a refusal is seen to audit late.
  - `[low]` `patch` `TestNoSessionIs500` closing assertions watched a session no call used (verification-gap) — replaced by a probe-driven PUT whose submit would succeed and an assertion that nothing was submitted; mutation recorded.
  - `[low]` `patch` `TestGetFails` redundant assertion `body '[ "pirate"` (blind, verification-gap, other) — removed.
  - `[low]` `patch` `persona.spec.ts` comment "the first PUT any stack answers" is history (edge-case) — reworded to the contract.
  - `[low]` `reject` Class header of `Api.cls` and `api-types.ts` do not list the persona routes (blind) — by-design: the intent forbids editing the class comment and anything under `web/src/`; Story 40.4 owns the client types.
  - `[low]` `reject` `persona.spec.ts` never PUTs a plain preset over HTTP (blind) — the language PUT passes the same gateway, method and role; the preset path is pinned in `PersonaApi`.
  - `[low]` `reject` Mutation lines cover only part of AC 2, AC 3 and AC 7 (verification-gap) — each AC has a pinning test whose recorded mutation goes red (Rule 19); further mutations are optional.
  - `[low]` `reject` e2e relies on seeded stack state (`onlineDemo` off, no pending request) (verification-gap other) — documented in the spec's header and the same seed as `pairing.spec.ts`.
  - `[low]` `reject` The 401 is asserted only in `persona.spec.ts`, not in `OcuTalon.Test.Web` (intent-alignment) — by-design: the spec's matrix puts the three real-HTTP rows in the Playwright spec and the unit test pins the no-session 500.
  - `[low]` `reject` Signed-out PUT cases do not check the row afterwards (intent-alignment) — a signed-out request has no session to write for; `ApiBase.Login` answers before `PutPersona` runs.

## Design Notes

**Governing decisions.** AD-1 (a state change enters as a command through `Commands.Submit`, its `Origin` set by the submitting code), AD-4 (the session comes from the server), AD-13 (401 `signed_out`, the browser envelope, the error shape), AD-17 (the audit entry, `SettingsOps` writes it), AD-19 (per-person values: session-checked endpoints with origin `web_user`, `SettingsOps` the only writer, its validation), AD-29 and AD-33 (the routes are in the REST surface table as `GET`, `PUT /api/v1/persona` -> `SettingsOps`; `Web.Api` is Lane B's). No AD is contradicted and the spine does not change: the route is already in its table.

**U-268.** From AD-1 this spec relies only on the two points above: `Commands.Submit` with origin `web_user`, and `CommandsIn`'s rule that `SetPersona` comes from `web_user` alone. It does not rely on the closed list of `tool` origins or on digest routing, and it does not cite AD-14. Story 33.2's additions do not touch either point.

**Integration ACs.** No consumers in this story; the first consumer will be Story 40.4. `web/e2e/api/persona.spec.ts` plays that client over real HTTP until then.
- Consumed-by: Story 40.4 (the Persona card reads `GET` to show the choice, `customOffered` and `pendingRef`, sends `PUT`, and shows `message` or `error.message` beside the field). Story 40.6's pending request reaches the card through `pendingRef`.
- Consumes: Story 40.2's `SettingsOps.Persona` and `SetPersona` handling, and `Commands.Submit`. `Test.Web.PersonaApi` exercises the real `CommandsIn` and `SettingsOps` items, not a mock, for every row but the failures they never give.

**Extend, don't copy.** `PutPersona` follows `Unpair` and `DismissIncident`, `PersonaBody` follows `MarkerBody`, and the seams follow `Post`, `Press` and `Mail`. Two copies have a stated reason:
- `Test.Web.PersonaApiProbe` is a new class rather than two methods in `ApiProbe`, and `Test.Web.PersonaApi` keeps its own small `Call` rather than a shared helper: the epic's contended-path rule prefers a new test class to an edit of a shared one.
- The handlers stay one block rather than sharing a `Commands.Submit` wrapper with `Unpair`, for the same reason: no edit above the block in a file Epic 33 changes first.

**Ledger inbox.** None for this story. Story 40.2's deferred `ProposePersona` owner binding is Story 40.5's.

**Why `result.Message` passes through on failure.** "Couldn't save. Nothing was changed." is true when `SettingsOps` says it. `CommandsIn` answers `failed` on a timeout too, when the write may still finish, and its text says so. Mapping every failure to one fixed sentence would claim something the route can't know.

**Decided in-stage.**
- Refused values are 400 with the outcome as the code, `custom_not_offered` included: one rule for the card, and nothing about the state conflicts.
- The accepted answer is `{"result":"done","message",...}` plus the three saved values, `result` as on the other command routes. The card needs `message`; it has the rest from its last `GET`, so `customOffered` and `pendingRef` are left out.
- A malformed body is 400 `bad_persona` with `SettingsOps`' existing "Couldn't save. Nothing was changed." The page never sends one, and a new sentence would be new public text.
- A failed `GET` is 500, not the defaults with an empty `pendingRef`, which would hide a pending request.
- `PUT` reads the session first, then the body, as `DismissIncident` does.
- `not_saved` and `bad_persona` are new error codes, not new text.
- An owner result with no `Message` is answered with the existing `MESSAGESERVERERROR` text (a refusal or a failure), never with a claim about the state.
- `Test.Web.PersonaApiProbe.ReadPersona` has a second mode, `defaults` (an OK status and the defaults whatever the session), so that `TestNoSessionIs500` pins `GetPersona`'s own session check: `SettingsOps.Persona("")` already gives an error status, which would hide a removed check.
- A result with `Ok` and no `Message` is answered with `SettingsOps`' existing Saved sentence, since an Ok from the owner means the write and its audit entry happened.
- `TestPutRefusals` waits for the control save's audit entry before it takes its mark, so the "no entry" count cannot see a late entry of the control save (one run in about seven showed it before this).
- No Task 0. `SettingsOps.Persona` has not yet run in a web process as a person without `%All`: it opens `Setting` rows by object, which needs no SQL privilege, and `Ownership.Approvals` is what the rail reads in the same process, so it should work (inference until `persona.spec.ts` runs it as the README account). `%CSP.REST` matches a route by URL and method, so two lines with one URL work (`irislib/%CSP/REST.cls`), and `%Api.Atelier` serves `PUT` the same way. If the spec shows either inference wrong, the fix is in a file this story may not change, so stop with `## Clarification Needed`.

## Verification

All calls run from the worktree root with `timeout: 600000`, one per call, each `ci/iris.sh` and `ci/warm.sh` call prefixed with `<A>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=40 stage=implement'`. Fresh tag `e40s8i`, warm tag `e40s8iw`. Every IRIS MCP call passes `server` `ocutalon-slot-a` and `namespace` `OCUTALON`, after `iris_server_info`; one `iris_execute_tests` per message, never two. A warm stack that has run other shards can show false reds, so the final runs below use fresh stacks.

**Commands:**
- (loop) `iris_doc_load` the changed and new classes into slot A and compile -- expected: they compile. `OcuTalon.Test.Web.PersonaApi` needs a running production, so it runs on a throwaway only.
- (loop) `<A> OCUTALON_RUN_TAG=e40s8iw ci/warm.sh up` once per stage, then one per call with `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e40s8iw ci/iris.sh class <Class>` for each of: `OcuTalon.Test.Web.PersonaApi`, `OcuTalon.Test.Web.Api` (the route pin), `OcuTalon.Test.Web.MailboxApi` and `OcuTalon.Test.Web.BreakFeedApi` (they read the `UrlMap`), `OcuTalon.Test.Core.SettingsOps` (`TestOnlyRunTimeWriter`), `OcuTalon.Test.Data.Tables` (`TestSqlNames`), `OcuTalon.Test.Core.SettingsPersona`, `OcuTalon.Test.Core.CommandsInProduction`. At the stage's end, also after a failure, `<A> OCUTALON_RUN_TAG=e40s8iw ci/warm.sh down` -- expected: `CLASS ... passed` each.
- (loop) `npm --silent --prefix web run e2e -- --list | grep -c 'api/persona.spec.ts'` -- expected: a count above 0, so the spec is in the chromium project and compiles.
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: passes (the new class is in area `Web`, shard `lane-b`, run once).
- (once) fresh stacks, one per call: `<A> OCUTALON_RUN_TAG=e40s8i ci/iris.sh class OcuTalon.Test.Web.PersonaApi`, then `... class OcuTalon.Test.Web.Api`, then `<A> OCUTALON_RUN_TAG=e40s8i ci/iris.sh teardown` -- expected: `CLASS ... passed` each.
- (once) `<A> OCUTALON_RUN_TAG=e40s8i ci/iris.sh build` (the web bundle, after the integrate-forward), then `<A> OCUTALON_RUN_TAG=e40s8i ci/iris.sh live sign-in --part 1/3`, then `ci/iris.sh teardown` with the same prefix and tag -- expected: the part's `PART` line lists `web/e2e/api/persona.spec.ts` (`web/e2e/api/` sorts first; if it is in another part, run that part) and the part passes.
- (once) `bash ci/checks.sh` -- expected: every script passes (ASCII source and the class rules included). It took more than 10 minutes on this machine under load: a call that passes the cap must not be started twice. Read what the first call printed; if it is cut off, run the remaining scripts of `CHECK_SCRIPTS` one per call.
- The rest of shards `lane-a` and `lane-b` and the other live units are left to CI.

**Mutations (Rule 19; the implement stage records each as `mutation: ... -> ...`):**
- AC 1: `SubmitPersona` with origin `web_admin` -> `PersonaApi` accepted-preset test red.
- AC 2: `Fail(400, ...)` with `MESSAGESERVERERROR` in place of `result.Message` -> `PersonaApi` refused-language test red.
- AC 3: `GetPersona` writing `pendingRef` as "" -> `PersonaApi` pending-request test red.
- AC 4: `GetPersona` not quitting on the `SessionRef` error -> `PersonaApi` no-session test red; `ApiBase.Login` answering 403 -> `persona.spec.ts` signed-out case red.
- AC 5: `not_saved` answered with `SettingsOps`' `MESSAGENOTSAVED` always -> `PersonaApi` failure test red (the `CommandsIn` `failed` text).
- AC 6: `command.SessionRef` taken from the body's `sessionRef` -> `PersonaApi` body-names-a-session test red.
- AC 7 is the test list itself: its pins are the mutations above.

Recorded by the implement stage (warm stack e40s8iw for the `PersonaApi` mutations, each reverted byte-identical and the class green again on the same stack; fresh stack e40s8i for the sign-in one):
- mutation: SubmitPersona with origin web_admin -> TestPutPreset (the answer, the keys, the entry, the command) and every other accepted-PUT test red
- mutation: Fail(400, ...) with MESSAGESERVERERROR in place of result.Message -> TestPutRefusals red (all seven refusals)
- mutation: GetPersona writing pendingRef as "" -> TestGetPending red
- mutation: GetPersona not quitting on the SessionRef error -> TestNoSessionIs500 red ("GET: 500 server_error even where the read itself would succeed", through the probe's `defaults` read)
- mutation: ApiBase.Login answering 403 -> persona.spec.ts signed-out case red (`ci/iris.sh live sign-in --part 1/3`: 89 passed, 2 failed, persona.spec.ts among them)
- mutation: not_saved answered with SettingsOps' MESSAGENOTSAVED always -> TestPutSaveFailed red (the CommandsIn failed text, the unknown outcome, the empty message)
- mutation: command.SessionRef taken from the body's sessionRef -> TestPutBodyNamesSession red
- mutation: PutPersona without its Quit on the SessionRef error -> TestNoSessionIs500 red (PUT: 500 server_error, even where the submit would succeed, and nothing submitted)
- mutation: an Ok result with an empty message answered with MESSAGESERVERERROR instead of the Saved sentence -> TestPutOkFromOwner red

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

Shared surfaces: `OcuTalon.Web.Api`'s `UrlMap`, 12 to 14 routes (`Test.Web.Api:TestRoutes` pins the list and the count, and Story 33.2 changes the same line; `Test.Web.MailboxApi:TestRoutes` and `Test.Web.BreakFeedApi` read the map); the test classes of area `Web` in shard `lane-b`, one more (`docker/tests/test-ci-config.sh`); the README account's persona keys in the sign-in stack, which `persona.spec.ts` removes before and after itself.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `GET` and `PUT /v1/persona` are on `OcuTalon.Web.Api`: two route lines at the end of the `UrlMap` and one appended block (`GetPersona`, `PutPersona`, `PersonaBody`, and the seams `ReadPersona` and `SubmitPersona`). `PUT` submits `SetPersona` through `Commands.Submit` with origin `web_user` for the session from `Ownership.SessionRef` and turns the `CommandResult` into 200, 400, 501 or 500. No new text.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- the routes and the handler block.
- `src/ocutalon/cls/OcuTalon/Test/Web/PersonaApiProbe.cls` -- new, overrides the two seams for failure cases.
- `src/ocutalon/cls/OcuTalon/Test/Web/PersonaApi.cls` -- new, 17 tests through the real production.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- `TestRoutes` pins 14 routes.
- `web/e2e/api/persona.spec.ts` -- new, real-HTTP evidence (401, 403, 405, defaults, a language outside ASCII, a refused name).

**Review.** 14 findings, all low, none high or medium. Patched 5: Ok with no message answers the Saved sentence, the Ok-with-bad-Data case is tested, `TestNoSessionIs500` now watches the submit it can reach, a redundant assertion is removed, and a history phrase in the e2e comment is reworded. Rejected 9, each with its reason in the triage log (theoretical, by-design per the intent, optional extra mutations, covered elsewhere). Nothing deferred. Follow-up review recommended: false (no high, fewer than two medium patched).

**Verification.** Warm stack `e40s8iw`: `PersonaApi`, `Web.Api`, `MailboxApi`, `BreakFeedApi`, `Core.SettingsOps`, `Data.Tables`, `Core.SettingsPersona`, `Core.CommandsInProduction` passed, and two new mutations went red and were reverted. Fresh stack `e40s8i`: `PersonaApi` and `Web.Api` passed, `ci/iris.sh build`, then `live sign-in --part 1/3` passed (91 tests, `persona.spec.ts` in the part), teardown clean. `bash ci/checks.sh` passed. `e2e --list` count 1, `test-ci-config.sh` passed. Both stacks torn down.

**Residual risks.** A refusal outcome with an empty owner message would answer 400 with the server-error sentence (the owner never does this today). Zero-audit-entry assertions are point-in-time reads.
