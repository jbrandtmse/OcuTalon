---
title: 'Story 39.2: Save your heartbeat settings and ask for a beat'
type: 'feature'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 39.1 named the heartbeat's Lane B parts and Stories 39.3, 39.4 and 39.7 built the beat, but a person still cannot save a checklist, interval, active hours or on/off, cannot read them back, and cannot ask for a beat now: the verbs `SetHeartbeat` and `RunHeartbeat`, their routing, the `SettingsOps` validation and the three session-checked routes do not exist, and `Msg.Enum` CHANNEL lacks `heartbeat`. The security overview also still names only the periodic beat (DW-684).

**Approach:** Add the heartbeat area beside Epic 40's persona area on the same per-person path: two verb classes, two `CommandsIn` routes (origin `web_user` only; `RunHeartbeat` is sent to `Checks` as a `BeatNow`), a `SettingsOps` save (validate, audit first, then the five keys) and read, and `GET`/`PUT /v1/heartbeat` plus `POST /v1/heartbeat/run` in `Web.Api` next to the persona routes. Append `heartbeat` to both enum copies and to the security overview, and prove sign-out already forgets the keys.

## Boundaries & Constraints

**Always:**
- Lane B files only (U-177). Lane A's `Checks/**`, `Data/HeartbeatBeat.cls`, `Live/Payload/Heartbeat.cls`, `Agent/Triage.cls`, `Test/Checks/**` and `docker/tests/test-triage-heartbeat.sh` are read and called, never edited.
- The `SessionRef` comes only from `Ownership.SessionRef` (the server-side session); a `sessionRef` in a body is ignored (AD-4). Commands go only through `Commands.Submit` with origin `web_user` (AD-1).
- `SettingsOps` is the only writer of the five keys, which are `Checks.Beat.SettingKey(sessionRef, name)` (Rule 2: one source of the names). An accepted save writes one `Settings` audit entry first (AD-17) and then all five keys in one transaction; a refused value writes and audits nothing. No audit entry, log line or response other than the person's own GET/PUT answer holds the checklist's text.
- The GET reads the rows, never a stale cache entry, and builds the public view with `Live.Payload.Heartbeat.FromRow` (so the GET and the `heartbeat` event cannot drift), the row read through `Data.Ownership` (AD-4).
- Every user-facing string is one listed under Design Notes › Public text, word for word. ASCII only in product files; contract-only comments (Rule 14); no machine path in a committed file.
- Committed storage blocks for the two new message classes, generated on slot D and written back (AD-5).

**Never:**
- No web change (`web/**`): the card and its API types are Story 39.5's.
- No edit to `Test/Install/SecurityOverview.cls`, `Test/Web/SettingsApi.cls`, `Test/Core/SettingsSave.cls`, `Production.cls` or any other file in the diff of Epic 11 or 17, except the one-name append to `docs/bridge-guide.md`'s channel list (Design Notes › Footprint).
- No new production item, task or timer; no change to `Checks`' run-now rules (the 2-minute rule and the skip rules are `Beat.RunNow`'s).
- No change to any AD's Rule; the one spine edit is the additive Enumerations name below.
- No real key, no real bot, no test on slot D (slot D is for load, compile and storage export only).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Save accepted | `PUT /v1/heartbeat` `{"on":true,"interval":60,"from":"07:15","to":"21:45","checklist":"a\nb"}` | 200 `{"result":"done","message":"Saved. Applies within a minute. Recorded in the audit log.","on":true,"interval":60,"from":"07:15","to":"21:45","checklist":"a\nb"}`; the five keys hold `1`,`60`,`07:15`,`21:45`,`a\nb`; one `Settings` entry (setting `heartbeat`, channel `web`, the IRIS user, the `SessionRef`, from/to in the audit form) written before the keys | none |
| All day | `from` and `to` both `""` | accepted; both keys stored `""` | none |
| Refused interval | `interval` 15, 45 or 2880 | 400 `bad_interval`, "Couldn't save. Nothing was changed."; no key, no audit | nothing written |
| Refused hours | `from` `"07:10"`, `"24:00"`, `"7:15"`, or only one of the two empty | 400 `bad_hours`, the not-saved sentence | nothing written |
| Refused checklist | 1,001 characters; holds `{{`, `@{`, a tab or `\u0007` | 400 `bad_checklist`, "Use up to 1,000 characters, without {{ or @{." | nothing written (an over-long one is refused by the route before any submit) |
| Accepted checklist | emoji, `\r\n` line breaks, exactly 1,000 characters, `""` | accepted | none |
| Bad body | not an object; `on` not a boolean; `interval` not a number; a missing member | 400 `bad_heartbeat`, the not-saved sentence; nothing submitted | nothing submitted |
| Body names a session | `{..., "sessionRef":"<another>"}` | saved for the CSP session's own session only | ignored |
| GET, no values (local) | fresh session | 200 `{"on":true,"interval":30,"from":"08:00","to":"20:00","checklist":"","sample":false}` (no row-backed member) | none |
| GET, online demo, no checklist row | `onlineDemo` on | `on` false, `interval` 30, `checklist` the three-line sample, `sample` true; no key written | none |
| GET after a beat | the person has a `HeartbeatBeat` row with a trace session | the row's public view (FromRow's members) plus `traceUrl` (TraceLink), `checklist`, `sample` false; never the `SessionRef`, a snapshot key, `LastItemId` or `LastDecisionRef` | none |
| GET reads the rows | a key changed by another process within 60 s | the GET shows the new value | none |
| Run accepted (Integration) | saved checklist, key present, not capped; `POST /v1/heartbeat/run` | 202 `{"result":"sent"}`; the real `Checks` set the row's `LastRunNowAt` and `LastItemId` | none |
| Run on cooldown (Integration) | a second POST within 2 minutes | 409 `{"error":{"code":"cooldown","message":"You can run it again at {time}."},"availableAt":"<UTC>"}`, `availableAt` = the first run's `LastRunNowAt` + 120 s; nothing sent | none |
| Run held | Checks answers `cap`, `nokey`, `empty` or `backoff` | 409 with that code and its sentence (Public text); `backoff` also carries `availableAt` | nothing sent |
| Run fails | `failed`, an unknown outcome, an error status or no result | 500 `server_error`; `not_built` is 501 `not_built` | cause logged, never sent |
| Origins | `SetHeartbeat`/`RunHeartbeat` from each origin of `Msg.Enum` ORIGIN, `"zz"`, `""`, and `web_user` inside a bridge context | routed only from `web_user` outside a context; `tool` (and any origin inside a context) gets not_allowed "That can't be done from the chat. Nothing was changed."; any other origin "OcuTalon can't take that command from here. Nothing was changed."; a refusal sends nothing | refusal |
| RunHeartbeat arrives as BeatNow | accepted `RunHeartbeat` | the owner `Checks` gets one `OcuTalon.Checks.Msg.BeatNow` with the command's `SessionRef` and `RequestedAt` a UTC stamp of now; its `CommandResult` is the answer as it is | none |
| Sign-out | online-demo `EndSession` of a session with the five heartbeat keys | ended; the five keys are gone; another session's keys stay | as today |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Msg/Command/SetPersona.cls` -- the sibling of `SetHeartbeat`: `%String(MAXLEN = "")` values, a reserved SQL word renamed with `SqlFieldName`, committed storage. Measured on slot D: `$SYSTEM.SQL.IsReservedWord` is 1 for ON, INTERVAL, FROM and TO, 0 for CHECKLIST.
- `src/ocutalon/cls/OcuTalon/Msg/Command/EndSession.cls` -- the shape of a verb with no own property (`RunHeartbeat`).
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:36`, `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls:24` -- CHANNEL in both copies; `Test.Msg.Contracts.TestBridgeEnumerationsEqualOcuTalons` keeps them equal.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `XData Routes` (line 173; append two rows), `Carry` (72; `request = $Select(verb = "Dismiss": ..Dismissal(command), ...)` at 88 is where `RunHeartbeat` becomes a BeatNow), `Dismissal` (141) is the converter to mirror, `TOOLVERBS` (36) stays unchanged so a tool is refused. Its class doc and the Routes doc name the persona verbs; add the heartbeat verbs.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls:181,238-273` (read only) -- Checks answers a BeatNow with a `CommandResult`: Ok 1 and Outcome `sent` (Ref the ItemId), else Ok 0 with Outcome `cooldown`, `empty`, `backoff`, `cap`, `nokey` or `failed` and Data `{"availableAt"}` for cooldown and backoff. `RequestedAt` must be `YYYY-MM-DDTHH:MM:SSZ` or Checks uses its own now.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` (read only) -- `KEYS`, `INTERVALS`, `CHECKLISTMAX`, `DEFAULT*`, `SettingKey(ref, name)` (the key names), `Values(ref)` (the five values with defaults and normalization, read through `Setting.Get`; from/to by `KeyIndexExists`), `InHours` (from = to counts as all day), `RunNow` (446-480).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls` (read only) -- `FromRow(row, values)`: the public view the GET reuses; with no row it holds only the settings.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls:39-55` (read only) -- `Get`'s per-process cache `^||OcuTalon.Setting(key)`, 60 s; `Set` drops only the writing process's entry.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- `Carry` (119), `SavePersona` (233), `WritePersona` (255; audit first, then the keys in one transaction: the body to share), `HasSession` (477), `OnlineDemo` (488), `PersonaProblem` (498; the control-character regex `[\p{Cc}&&[^\n\r]]`), `IsPersonKey` (535, reads `PERSONKEYS` at 55), `Persona` (545; the read to mirror), `ForgetPerson` (572; deletes every `person.<ref>.*` row and cache entry), `Result` (594), `MESSAGENOTSAVED`, `MESSAGEBADCUSTOM` (58-66). Class doc lines 1-49 list commands and outcomes.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:30,78-157` (read only) -- `Settings` shape `setting,from,to` plus `irisUser,sessionRef,channel`, all strings; `from`/`to` may be empty.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `Pairing` (342) is the single-row read to mirror; `Statement` (754; `kind = "pairing"` at 829, `"upload"` at 901) holds the fixed SQL per kind; `Rows` (706). `HeartbeatBeat.SessionRef` has the default (upper-case) collation, so the statement compares with `%EXACT`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- the URL map (146-170; the persona routes at 159-160), class doc (1-62), `Fail(status, code, message, approval, extra)` (1178; `extra` adds members such as `availableAt`), `ServerError` (244), `PayloadObject` (1104), `GetPersona`/`PutPersona`/`PersonaBody`/`ReadPersona`/`SubmitPersona` (1238-1340: the routes to mirror), `BodyText` (377). `Web.TraceLink.Viewer(.viewer)` and `Add(body, .viewer)` add `traceUrl` (as at 991-992).
- `src/ocutalon/cls/OcuTalon/Data/Time.cls:42,88` (read only) -- `AddSeconds`, `NowUtc`, `ForMessage(utc)` ("14:12" the same day, instance zone).
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:16-20,355-358` -- End already calls `SettingsOps.ForgetPerson`; only its doc needs the heartbeat named.
- Tests to mirror or extend: `Test/Core/CommandsStep3.cls` (the origin oracle loop, `NewProbe`/`NewCommand`/`Calls`/`Call`), `Test/Core/CommandsInProbe.cls`, `Test/Core/CommandsOwner.cls` (records `request.Origin` and `IdempotencyKey`, which a BeatNow does not have: extend it), `Test/Core/SettingsPersona.cls` with `Test/Core/SettingsOpsProbe.cls` (audit through the `WriteAudit` seam; `TestAppliesWithinSixtySeconds` at 256 is the other-process technique), `Test/Core/SessionOps.cls:664` (`TestEndForgetsPersona`), `Test/Web/PersonaApi.cls` and `PersonaApiProbe.cls` (stand-in request and CSP session through the real production; seams `SubmitPersona`, `ReadPersona`, `ServerError`), `Test/Checks/BeatCase.cls:34-49` (read only: `Beatable` preconditions, `Due`), `Test/Checks/Heartbeat.cls:468` (read only: the `[[mock:decide-ignore:<session>]]` checklist marker and waiting for the Decision).
- Shared-surface tests to update: `Test/Msg/Contracts.cls:39-96` (verb list of `TestVerbsInheritTheCommonFields`, `expected("CHANNEL")` at 74, `XData Contracts` with `SetPersona` at 320), `Test/Msg/Catalog.cls:123` (refused channels), `Test/Web/Api.cls:948-958` (the 22 routes), `Test/Web/BodyLimit.cls:14,49` (16 POST routes).
- `docs/security-overview.md:156` -- the hand-written bullet (outside the generated markers, so `Install.SecurityOverview` never writes it); `docker/tests/test-triage-heartbeat.sh:17,58-74` pins the existing sentence exactly once in that line and is the model for the new check. `docs/bridge-guide.md:266` -- the channel list that `docker/tests/test-bridge-guide.sh` (`enum_values` of the bridge enum, 301-325) requires to name every value in backticks.
- `ci/units.sh:12` -- the appended `CHECK_SCRIPTS` line; `docker/tests/test-ci-config.sh` requires every `docker/tests/test-*.sh` in exactly one list. `docker/tests/test-*.sh` is not an IRIS input (`NOT_IRIS_INPUT_PATTERN`, line 186).
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:1118` -- the Enumerations row, `Channel \`web, phone, mailbox, telegram, email, webhook, slack, system\`;`. No `.memlog.md` in the folder; lint with `.claude/skills/bmad-architecture/scripts/lint_spine.py`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetHeartbeat.cls` (new) -- Extends `OcuTalon.Msg.Command`; properties in order `On`, `Interval`, `From`, `To`, `Checklist`, each `%String(MAXLEN = "")`, with `SqlFieldName` `HeartbeatOn`, `HeartbeatInterval`, `HeartbeatFrom`, `HeartbeatTo` on the first four. Doc: origin `web_user` only, the session from the server; SettingsOps validates and writes. Compile on slot D and commit the generated storage block -- AD-1, AD-5, AD-18 Names, AD-19.
- `src/ocutalon/cls/OcuTalon/Msg/Command/RunHeartbeat.cls` (new) -- Extends `OcuTalon.Msg.Command`, no own property; doc: CommandsIn sends it to Checks as a BeatNow; origin `web_user` only. Storage as `EndSession`'s -- AD-1, AD-18.
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls` and `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls` -- append `,heartbeat` to CHANNEL in both -- AD-14, AD-18 Names, AD-2 (copies stay equal).
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- append to `XData Routes` `{"verb": "SetHeartbeat", "owner": "SettingsOps", "origins": "web_user"}` and `{"verb": "RunHeartbeat", "owner": "Checks", "origins": "web_user"}`; in `Carry`, send `RunHeartbeat` as `..BeatRequest(command)`, a private class method beside `Dismissal` that returns a new `OcuTalon.Checks.Msg.BeatNow` with the command's `SessionRef` and `RequestedAt = ##class(OcuTalon.Data.Time).NowUtc()`. Leave `TOOLVERBS` and the refusal texts unchanged. Update the class and Routes docs -- AD-1, AD-18 Run now, AD-26 (the existing `Join` puts the send in the session's trace).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `ClassMethod Heartbeat(sessionRef, Output sc) As OcuTalon.Data.HeartbeatBeat`: the session's own row or "", through a new `Statement` kind `heartbeat` (`SELECT TOP 1 h.ID FROM OcuTalon_Data.HeartbeatBeat h WHERE %EXACT(h.SessionRef) = ?`, binds `o`); add it to the class doc's list of reads -- AD-4.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- make these changes:
  - `PERSONKEYS` gains `heartbeat.on,heartbeat.interval,heartbeat.from,heartbeat.to,heartbeat.checklist`;
  - parameters `MESSAGEHEARTBEATSAVED` and `MESSAGEBADCHECKLIST` (texts in Public text);
  - `Carry` routes `OcuTalon.Msg.Command.SetHeartbeat` to a private `SaveHeartbeat(command)`: `HasSession` (else `no_session`, not-saved sentence); `HeartbeatProblem(on, interval, from, to, checklist, .outcome)` in the order on (`"0"` or `"1"`, else `bad_on`), interval (a canonical number in `Beat.INTERVALS`, else `bad_interval`), hours (both `""`, or both `HH:MM` with HH 00-23 and MM 00, 15, 30 or 45, else `bad_hours`), checklist (at most `Beat.CHECKLISTMAX` characters as `$Length` counts, no `{{`, no `@{`, no control character but `\n` and `\r`, else `bad_checklist` with `MESSAGEBADCHECKLIST`; the others answer `MESSAGENOTSAVED`); then the write; answer `saved` (Ok 1, `MESSAGEHEARTBEATSAVED`, Data the JSON `{on (number 0/1), interval (number), from, to, checklist}` as stored);
  - the write: move `WritePersona`'s audit-then-transaction body into one private method that both callers use (WritePersona keeps its signature, outcomes and log lines); for the heartbeat the entry is setting `heartbeat`, `from`/`to` the audit forms of the changed keys only (`HeartbeatAuditForm`: `name=value` pairs joined by `"; "` in KEYS order, the checklist as `checklist=<n> characters`; both `""` when nothing changed), then all five keys;
  - `ClassMethod Heartbeat(sessionRef, Output sc) As %DynamicObject`: kill this process's `^||OcuTalon.Setting` entries of the five keys, take `Beat.Values(sessionRef)`, the row from `Ownership.Heartbeat`, export `Live.Payload.Heartbeat.FromRow(row, values)` to a dynamic object, then add `checklist` (the stored value; on the online demo with no checklist row, `SampleChecklist()`) and `sample` (boolean, true only in that case); `sc` an error status when the row could not be read (the values still returned);
  - `ClassMethod SampleChecklist() As %String`: the three sample lines joined by `$Char(10)`;
  - update the class doc (the commands, outcomes `saved`/`bad_on`/`bad_interval`/`bad_hours`/`bad_checklist`, the per-person keys, Heartbeat) -- AD-17, AD-19, AD-33, FR-63.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- routes after the persona pair: `GET /v1/heartbeat` `GetHeartbeat`, `PUT /v1/heartbeat` `PutHeartbeat`, `POST /v1/heartbeat/run` `RunHeartbeat`:
  - GET: the session (500 on failure); `ReadHeartbeat(sessionRef, .sc)` (a seam calling `SettingsOps.Heartbeat`; an error is 500 `server_error`, no value sent); `TraceLink.Viewer`/`Add`; 200 the object;
  - PUT: the session; `HeartbeatBody(.on, .interval, .from, .to, .checklist)` (a JSON object with `on` a boolean, `interval` a number, `from`, `to`, `checklist` strings, other members ignored; else 400 `bad_heartbeat` with `SettingsOps.MESSAGENOTSAVED`); a checklist longer than `Beat.CHECKLISTMAX` is 400 `bad_checklist` before any submit; submit `SetHeartbeat` (on as `"1"`/`"0"`, interval as its number's text) through the seam `SubmitHeartbeat(command, .result)` (`Commands.Submit` with `web_user`); Ok is 200 `{"result":"done","message", on (boolean), interval, from, to, checklist}` from the result's Data; `bad_on`, `bad_interval`, `bad_hours`, `bad_checklist` are 400 with the outcome and the owner's message; `not_built` 501; anything else 500 `not_saved` with the owner's message (the server-error sentence when it has none); Data that cannot be read, an error status or no result is 500 `server_error`;
  - POST run: never reads the body; the session; submit a `RunHeartbeat` through `SubmitHeartbeat`; Ok is 202 `{"result":"sent"}`; outcomes `cooldown`, `cap`, `nokey`, `empty`, `backoff` are 409 with the outcome as the code, its sentence (`{time}` = `Data.Time.ForMessage(availableAt)`) and, when the result's Data has one, `availableAt` as an extra member; `not_built` 501; anything else 500 `server_error`;
  - the sentences as parameters `MESSAGERUNCOOLDOWN`, `MESSAGERUNCAP`, `MESSAGERUNNOKEY`, `MESSAGERUNEMPTY`, `MESSAGERUNBACKOFF`; the 202 status line is `%CSP.REST`'s `#HTTP202ACCEPTED`, as `Messages` uses it (Api.cls:349);
  - class doc: one paragraph for the three routes -- AD-1, AD-4, AD-12, AD-13, AD-19, AD-26, FR-63, FR-66.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` -- doc only: End's per-person step deletes the persona and heartbeat keys -- AD-4, AD-19.
- `docs/security-overview.md` -- append, in line 156 directly after the existing heartbeat sentence (a space between), the DW-684 sentence of Public text; change nothing else -- DW-684, FR-66.
- `docker/tests/test-heartbeat-overview.sh` (new) -- hosted check, structured like `test-triage-heartbeat.sh`'s overview rule: the DW-684 sentence occurs exactly once in `docs/security-overview.md`, inside the line that starts `- In model requests to the configured provider` under `Data leaves the instance only:` with no heading between, and directly after the existing heartbeat sentence; each way of breaking it is first tried on a synthetic file that must be flagged, and a good one that must not. One PASS/FAIL line per rule; exit 0 only when all pass -- DW-684, Rule 19.
- `ci/units.sh` -- line 12 becomes `CHECK_SCRIPTS="$CHECK_SCRIPTS eval-personas heartbeat-overview"` -- test-ci-config.
- `docs/bridge-guide.md` -- line 266: append `` , `heartbeat` `` before the final period of the Channels list; nothing else -- test-bridge-guide.
- `ARCHITECTURE-SPINE.md` (the spine path above) -- in the Enumerations row change `` slack, system` `` of Channel to `` slack, system, heartbeat` `` followed by ` [AMENDED 2026-11-05, Story 39.2: AD-18's Names bullet appends heartbeat to both enums, which stay equal]`; set `updated:` to the edit date; run the lint (`"ok": true`) -- Rule 20.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsOwner.cls` -- record `origin` and `key` only when the request extends `OcuTalon.Msg.Command` (and IncidentCommand as today); for an `OcuTalon.Checks.Msg.BeatNow` record `sessionRef` and `requestedAt`; update the doc -- the BeatNow has neither Origin nor IdempotencyKey.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsHeartbeat.cls` (new; mirrors `CommandsStep3`, through `CommandsInProbe`/`CommandsOwner`) -- `TestOrigins` (both verbs by the 6 origins, `zz`, `""`: 16 pairs, the matrix "Origins" row, routed pairs reach `SettingsOps`/`Checks`), `TestToolRefused` (each verb from `tool`, and from `web_user` inside a bridge context: not_allowed with the chat sentence, nothing sent: AD-1's governance test), `TestRunArrivesAsBeatNow` (matrix row: class, SessionRef, a UTC `RequestedAt` within a few seconds of now, the owner's result as the answer) -- AD-1.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsHeartbeat.cls` (new; mirrors `SettingsPersona` over `SettingsOpsProbe`) -- the save rows of the matrix (accepted, all day, each refusal with nothing written and nothing audited, accepted checklist edges), `TestAuditFirstAndWithoutText` (one entry before the keys; a failing audit writes no key; the entry's JSON never holds the checklist's text; from/to name only the changed keys), `TestKeyWriteFails` (no key changes), `TestNoSession`, `TestHeartbeatRead` (defaults local and online demo with the sample, saved values, another session's row not read, a row whose SessionRef differs only in case not read, reads rows not cache), `TestAppliesWithinSixtySeconds` (Integration: consumer `Checks.Beat.Values` reads the saved values at once in the writing process and, in another process, once its cache entry is older than 60 s, with SettingsPersona's technique), `TestPersonKeysAreGuarded` (`Apply` accepts the five heartbeat keys of a 22-character Ref only). Restore `onlineDemo`; remove every key, row and fixture -- AD-17, AD-19.
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls` -- add `TestEndForgetsHeartbeat` beside `TestEndForgetsPersona`: the five keys of the ended session are gone, another session's stay (then removed) -- AD-4, AD-19.
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApiProbe.cls` (new; mirrors `PersonaApiProbe`) -- seams `SubmitHeartbeat` (records class and values; answers fail, none or a given CommandResult JSON), `ReadHeartbeat` (fail or defaults), `ServerError` (records the cause).
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls` (new; mirrors `PersonaApi`; runs in throwaways and CI only, failing with its reason where the production does not run) -- GET rows of the matrix (defaults, online demo sample, after a saved PUT, the row's view with `traceUrl` and without private fields, a failed read is 500); PUT rows (accepted with the audit entry read back from the IRIS audit log within `SECONDS`, refusals with keys and audit unchanged, bad body and over-long checklist submit nothing, body sessionRef ignored, outcome mapping through the probe); `TestRunSendsThenCoolsDown` (Integration, real production: assert `Bridge.Keys.Status` of `Beat.AGENT` is 1 and `Bridge.Budget.State().capped` is 0 as `BeatCase.Beatable` does; PUT a checklist holding `[[mock:decide-ignore:<session>]]`; POST is 202 and the row has `LastRunNowAt` and `LastItemId`; a second POST is 409 cooldown with `availableAt` = LastRunNowAt + 120 s; wait for the beat's Decision through `Ownership.DecisionOfItem` before the clean-up so no late writer outlives the test), `TestRunEmptyThenCooldown` (real production: no checklist gives 409 `empty`, the next POST 409 `cooldown`), `TestRunOutcomes` (probe: `cap`, `nokey`, `backoff` with availableAt, `failed`, `not_built`, an error status and no result). OnAfterAllTests removes the sessions' heartbeat keys (`ForgetPerson`), their `HeartbeatBeat` rows, decisions and fixtures, and restores `onlineDemo` -- Rule 3, AD-1, AD-4, FR-63, FR-66.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` -- `expected("CHANNEL")` gains `,heartbeat`; the verb list of `TestVerbsInheritTheCommonFields` gains `SetHeartbeat`, `RunHeartbeat`; `XData Contracts` gains both classes (`SetHeartbeat` with its five `%String(MAXLEN=)` props and `"sql"` names `HeartbeatOn`, `HeartbeatInterval`, `HeartbeatFrom`, `HeartbeatTo`; `RunHeartbeat` with the common three) -- shared surface.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls:122-123` -- the refused channels become `email,webhook,slack,system,heartbeat` ("five Msg.Enum channels are refused") -- shared surface.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:948-955` -- the three routes after `PUT /v1/persona PutPersona`; 25 routes; doc line -- shared surface.
- `src/ocutalon/cls/OcuTalon/Test/Web/BodyLimit.cls:14,49` -- `/v1/heartbeat/run` joins `POSTROUTES`; seventeen -- shared surface.

**Acceptance Criteria:**
- Given Story 39.1's names, when this story's classes are compiled, then `OcuTalon.Msg.Command.SetHeartbeat` (`On`, `Interval`, `From`, `To`, `Checklist` and the common fields) and `.RunHeartbeat` match `Test.Msg.Contracts`, both `Msg.Enum` copies' CHANNEL end with `heartbeat` and stay equal, and the bridge guide and the spine's Enumerations row name it.
- Given `CommandsIn`, when either verb arrives from any origin, then it is routed only from `web_user` outside a bridge context (`SetHeartbeat` to `SettingsOps` as itself, `RunHeartbeat` to `Checks` as a `BeatNow`), and `Test.Core.CommandsHeartbeat` refuses each from origin `tool` with nothing sent (AD-1).
- Given a signed-in person, when they `PUT /v1/heartbeat`, then the route uses the server-side session only and submits `SetHeartbeat`; `SettingsOps` refuses any value outside the rules with a plain message and writes nothing, and for an accepted save writes the `Settings` audit entry (IRIS user, `SessionRef`, the changed keys, never the checklist's text) before the five keys, which `Checks.Beat.Values` reads within 60 seconds.
- Given `GET /v1/heartbeat`, when the person opens it, then it returns their values from the rows and their `HeartbeatBeat` row's public view (FromRow plus `traceUrl`), the defaults for a person with no values, and on the online demo off, 30 minutes and the unsaved sample checklist.
- Given `POST /v1/heartbeat/run`, when the person presses run, then the route submits `RunHeartbeat` and answers 202, 409 `cooldown` with `availableAt` while the 2-minute rule holds, and 409 with the reason (`cap`, `nokey`, and also `empty`, `backoff`) while Checks holds the beat.
- Given an online-demo session that signs out, when `SessionOps.End` runs, then its five `person.<SessionRef>.heartbeat.*` keys are deleted and another session's stay.
- DW-684: given `docs/security-overview.md`, when `bash docker/tests/test-heartbeat-overview.sh` and `bash docker/tests/test-triage-heartbeat.sh` run, then both pass: the existing beat sentence is unchanged and the run-now sentence follows it in the same bullet.
- Given the story's diff against the merge base with `origin/feature/OCT_OcuTalon_MVP`, when it is compared, then no file under `web/`, `src/ocutalon/cls/OcuTalon/Checks/`, `Data/HeartbeatBeat.cls`, `Live/`, `Test/Checks/`, `Test/Install/`, `Production.cls`, `Test/Web/SettingsApi.cls`, `Test/Core/SettingsSave.cls` or `docker/tests/test-triage-heartbeat.sh` changed, and `docs/bridge-guide.md` changed only on line 266.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-1: commands through `Commands.Submit`/`CommandsIn`; the personality verbs from `web_user` only; the governance test with origin `tool`.
- AD-4: the server-side `SessionRef`; REST reads through `Data.Ownership`; `SessionOps.End` forgets the per-person keys.
- AD-17: one `Settings` entry through `Bridge.Audit.Record`, before the write, naming the IRIS user.
- AD-18 (agent heartbeat; its Run now and Names bullets): the verbs, the BeatNow, the 2-minute rule and the cap live in Checks; the defaults.
- AD-19 (per-person values, the heartbeat area, Validation, The writer, At sign-out): keys, limits, `SettingsOps` the only writer, 60-second apply.
- AD-12 and AD-33: the GET reuses Lane A's `FromRow`; Checks stays the publisher of the `heartbeat` event, the routes publish nothing.
- AD-13 (browser envelope, enforced by the existing `OnPreDispatch`), AD-14 (CHANNEL), AD-26 (CommandsIn's `Join` traces the send under the session's `TraceRef`), AD-29 (lanes), AD-5 (committed storage), AD-28 (no route text claims all is well).

**AD-1 / AD-14 next to Story 33.2's additions (U-268).** The two verbs are routed by their own `Routes` rows with origins `web_user` only. The tool refusal holds because neither verb is on `TOOLVERBS`, an allow-list; the test asserts the refusal itself, so it holds whatever else joins that list (`SendDigest` from `tool`/`web_admin`, `GotIt`). `SetHeartbeat` from `web_admin` gets the not-allowed sentence, not the admin-only one, by the existing rule for a settings verb that lists `web_user`. Nothing in this story relies on digest routing: a beat's digest outcome is Lane A's and goes by AD-14 as for any untrusted item.

**Decided in-stage:**
- Routes live in `Web.Api` beside the persona routes (the sibling), not in a forwarded class like `Web.Documents`: a second `<Map>` would break `Test.Web.DocumentsApi.TestDispatch` ("exactly one Map"), while the inline routes change only `Test.Web.Api.TestRoutes` and `BodyLimit` lists, which this story updates.
- PUT takes all five values (the card's Edit saves them together); a missing member is `bad_heartbeat`. Every accepted save writes all five keys and one audit entry, so "Recorded in the audit log." is always true; from/to name only the changed keys.
- Verb values are `%String(MAXLEN = "")` as in `SetPersona`, so a bad value is `SettingsOps`' plain refusal and never a message-save validation error.
- `from` = `to` is accepted: `Beat.InHours` treats it as all day.
- The checklist allows `\r` with `\n`, as the persona check does (a CRLF line break).
- The GET drops the CSP process's five cache entries and calls `Beat.Values` instead of re-implementing its defaults (Rule 2: the same normalization Checks uses), so a GET right after a PUT shows the saved values.
- The 202 body is `{"result":"sent"}`; the ItemId stays inside. Checks' other held outcomes (`empty`, `backoff`) are 409 like `cap` and `nokey`, as the spine's REST row ("409 with `availableAt` or the reason") allows.
- `RequestedAt` is set by `CommandsIn` when it builds the BeatNow; `RunHeartbeat` carries no time from the client.
- Today's beat count and cost (the card's "Today" line) are not in this GET: no AC of 39.2 asks for them, and Story 39.5, also Lane B, decides their source.
- The spine's Enumerations row gains `heartbeat` (the additive name AD-18's Names bullet already records; Epic 40's precedent for `setting`).

**Extend, don't copy (Rule 2):** `SetHeartbeat` mirrors `SetPersona`; `BeatRequest` mirrors `Dismissal`; `SaveHeartbeat`/`HeartbeatProblem`/`Heartbeat` mirror `SavePersona`/`PersonaProblem`/`Persona` and share `WritePersona`'s write body (extracted, not copied); key names come from `Beat.SettingKey`; `Ownership.Heartbeat` is a `Rows` kind like `Pairing`; the routes mirror the persona routes; the tests extend `CommandsOwner`, `SettingsOpsProbe`, `Test.Core.SessionOps` and copy the shape of `CommandsStep3`, `SettingsPersona`, `PersonaApi` and their probes (test classes per area, the project's pattern). One copy: `test-heartbeat-overview.sh` repeats the overview rule of `test-triage-heartbeat.sh` (about 25 lines), because that script is Lane A's (U-177); the lead may route their unification to the epic's burn-down.

**Integration ACs:** in-story consumers: (1) the real `Checks` consumes `RunHeartbeat`: `POST /v1/heartbeat/run` in the running production answers 202 and Checks records `LastRunNowAt`, then 409 cooldown (`HeartbeatApi.TestRunSendsThenCoolsDown`); (2) `Checks.Beat.Values` reads what `SetHeartbeat` saved within 60 s (`SettingsHeartbeat.TestAppliesWithinSixtySeconds`). The first web consumer is Story 39.5.

**Consumed-by:**
- 39.5: the Heartbeat checklist card reads `GET /v1/heartbeat` (the event's members plus `checklist`, `sample`), saves with `PUT`, runs with `POST .../run` and shows the 409 codes and `availableAt`; it adds its own API types under `web/src/app/api/`.
- Checks (39.3/39.4, done): `BeatNow` handling consumes `RunHeartbeat`; `Beat.Values` reads the five keys.

**Consumes:** Lane A's `Checks.Process` BeatNow answer, `Beat` names/`Values`, `Live.Payload.Heartbeat.FromRow`, `Data.HeartbeatBeat`; Epic 40's persona path (`SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api`).

**Ledger inbox:** DW-684 is addressed by the `docs/security-overview.md` and `test-heartbeat-overview.sh` tasks and the DW-684 AC. No entry is declined.

**Footprint (checked 2026-11-05 against `origin/OCT-epic11` and `origin/OCT-epic17`):**
- In Epic 39's paths: `Msg/Command/{SetHeartbeat,RunHeartbeat}.cls`, `Msg/Enum.cls`, `Core/{CommandsIn,SettingsOps,SessionOps}.cls`, `Web/Api.cls`, `Test/{Core,Web}/**`, `docs/security-overview.md`, the spine.
- `footprint_extensions` to report (in no open epic's diff): `Data/Ownership.cls` (Lane B, Data by class), `Test/Msg/Contracts.cls`, `Test/Msg/Catalog.cls`, `docker/tests/test-heartbeat-overview.sh` (new file), `ci/units.sh` (a one-name append).
- Contended, under the standing precedent: `src/bridge/cls/OcuTalon/Bridge/Msg/Enum.cls` (the bridge folder is Epic 17's; this file is not in its diff; a one-name append) and `docs/bridge-guide.md` (in Epic 17's diff at lines 162 and 329; this story appends one name to line 266's list, as Epic 40 did for `setting`).

### Public text

| Where | Text (verbatim) | Source |
| --- | --- | --- |
| `docs/security-overview.md`, after the beat sentence | A beat that the person runs now sends the same, at most once every 2 minutes and only within the daily cost cap. | new (DW-684; AD-18 Run now: "at most once every 2 minutes per session, and inside the daily cap") |
| `SettingsOps.MESSAGEHEARTBEATSAVED` (PUT 200 `message`) | Saved. Applies within a minute. Recorded in the audit log. | EXPERIENCE › Heartbeat checklist card › Saved |
| `SettingsOps.MESSAGEBADCHECKLIST` (400 `bad_checklist`) | Use up to 1,000 characters, without {{ or @{. | EXPERIENCE › Persona card › Custom refusal (reused) |
| `SettingsOps.MESSAGENOTSAVED` (400 `bad_on`, `bad_interval`, `bad_hours`, `bad_heartbeat`; `no_session`) | Couldn't save. Nothing was changed. | existing (Epic 40) |
| `Web.Api.MESSAGERUNCOOLDOWN` (409 `cooldown`) | You can run it again at {time}. | EXPERIENCE › Button › Cooldown |
| `Web.Api.MESSAGERUNCAP` (409 `cap`) | The day's cost cap is reached. | EXPERIENCE › Skips ("…: the day's cost cap is reached."), as a sentence |
| `Web.Api.MESSAGERUNNOKEY` (409 `nokey`) | No model key is set. | EXPERIENCE › Skips ("…: no model key is set."), as a sentence |
| `Web.Api.MESSAGERUNEMPTY` (409 `empty`) | Your checklist is empty. | EXPERIENCE › Skips ("…: your checklist is empty."), as a sentence |
| `Web.Api.MESSAGERUNBACKOFF` (409 `backoff`) | Waiting after a failed check-in, until {time}. | EXPERIENCE › Skips ("…: waiting after a failed check-in, until {time}."), as a sentence |
| `SettingsOps.SampleChecklist()` (GET on the online demo) | Tell me if an Orders incident is still open or waiting for my approval. / Remind me of anything due in the next hour. / Ignore everything else. (three lines) | EXPERIENCE › Sample checklist (online demo) |
| `docs/bridge-guide.md:266` | - Channels: `web`, `phone`, `mailbox`, `telegram`, `email`, `webhook`, `slack`, `system`, `heartbeat`. | existing list, one name appended (fact) |
| Settings audit entry `from`/`to` (audit log, not on the page) | `on=1; interval=30; from=08:00; to=20:00; checklist=120 characters` (changed keys only) | new (data form) |
| CommandsIn refusals, 500/501 texts | unchanged existing texts | existing |

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`. Each command is a foreground call with `timeout: 600000`, one test class or script per call, never two at once. Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`; check it with `iris_server_info`, id FE850E91, build 154) is used only to load, compile and export the storage blocks of the two verb classes. Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s2implw ci/warm.sh up`, once -- expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s2implw ci/iris.sh class <Class>`, one call each -- expected: `CLASS ... passed`: `OcuTalon.Test.Core.CommandsHeartbeat`, `OcuTalon.Test.Core.CommandsRouting`, `OcuTalon.Test.Core.CommandsStep3`, `OcuTalon.Test.Core.SettingsHeartbeat`, `OcuTalon.Test.Core.SettingsPersona`, `OcuTalon.Test.Core.SessionOps`, `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.BodyLimit`, `OcuTalon.Test.Digest.Store` (reads every CHANNEL value).
- (loop) `<lane> OCUTALON_RUN_TAG=e39s2impl ci/iris.sh class <Class>`, fresh (production code), one call each -- expected: passed: `OcuTalon.Test.Web.HeartbeatApi`, `OcuTalon.Test.Web.PersonaApi`, `OcuTalon.Test.Core.PersonaAnswers`.
- (loop) `bash docker/tests/test-heartbeat-overview.sh`, `bash docker/tests/test-triage-heartbeat.sh`, `bash docker/tests/test-bridge-guide.sh`, `bash docker/tests/test-ci-config.sh` -- expected: no FAIL line, exit 0.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`.
- (once) `git diff --exit-code "$(git merge-base origin/feature/OCT_OcuTalon_MVP HEAD)" -- web src/ocutalon/cls/OcuTalon/Checks src/ocutalon/cls/OcuTalon/Data/HeartbeatBeat.cls src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Test/Checks src/ocutalon/cls/OcuTalon/Test/Install src/ocutalon/cls/OcuTalon/Production.cls src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls src/ocutalon/cls/OcuTalon/Test/Core/SettingsSave.cls docker/tests/test-triage-heartbeat.sh` -- expected: exit 0; and `git diff -U0 "$(git merge-base origin/feature/OCT_OcuTalon_MVP HEAD)" -- docs/bridge-guide.md` shows only line 266.
- (once) the hosted checks in three parts: `. ci/units.sh; echo $CHECK_SCRIPTS`, then three foreground calls of about a third each, `for n in <part>; do bash docker/tests/test-$n.sh >/dev/null 2>&1 || echo "FAIL $n"; done` -- expected: no FAIL line.
- (once) `<lane> OCUTALON_RUN_TAG=e39s2impl ci/iris.sh shard lane-b@Core --part 1/2`, then `--part 2/2`, then `shard lane-b@Web`, then `shard lane-b@Contract,Data,Demo,Live,Msg,Schedule`, fresh, one call each -- expected: passed; record each time (split further with `--part k/3` if a call nears 8 minutes).
- (once) `<lane> OCUTALON_RUN_TAG=e39s2impl ci/iris.sh shard lane-a@Digest,Tools`, fresh -- expected: passed (readers of CHANNEL).
- (once) `<lane> OCUTALON_RUN_TAG=e39s2implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s2impl ci/iris.sh teardown`, also after a failure.

Pinning mutations to apply, observe red, revert byte-identical and record (Rule 19), one per AC:
- drop `heartbeat` from `Msg.Enum` CHANNEL → `Test.Msg.Contracts.TestEnumerations` and `TestBridgeEnumerationsEqualOcuTalons`;
- `RunHeartbeat` origins `web_user,tool` in `Routes` → `CommandsHeartbeat.TestToolRefused`;
- `HeartbeatProblem` accepts interval 15 → `SettingsHeartbeat` (refused interval); the audit write moved after the keys → `TestAuditFirstAndWithoutText`;
- `SettingsOps.Heartbeat` without the cache kill → `TestHeartbeatRead` / `HeartbeatApi` GET-after-PUT;
- the route answers 202 for `cooldown` → `HeartbeatApi.TestRunSendsThenCoolsDown`;
- `ForgetPerson` limited to persona keys → `SessionOps.TestEndForgetsHeartbeat`;
- the DW-684 sentence removed → `test-heartbeat-overview.sh` FAIL.

**Shared surfaces:** `Msg.Enum` and `Bridge.Msg.Enum` CHANNEL (+`heartbeat`: `Test.Msg.Contracts`, `Test.Msg.Catalog` refused channels, `test-bridge-guide.sh` via `docs/bridge-guide.md`, `Test.Digest.Store` iterates it); `CommandsIn` `Routes` (+2 verbs; `CommandsRouting`'s 12-verb oracle is unchanged and stays green); `Test.Msg.Contracts` verb list and contracts (+2); `Web.Api` URL map (22 → 25 routes, `Test.Web.Api.TestRoutes`); `Test.Web.BodyLimit` POST routes (16 → 17); `SettingsOps.PERSONKEYS` (+5); `Ownership` `Statement` kinds (+1); `CHECK_SCRIPTS` (+`heartbeat-overview`, `test-ci-config.sh`); `CommandsOwner`'s recorded fields; the spine Enumerations row. Standing criterion: every test added or changed passes on a fresh environment, in either order. Added test time (inference): about 2 s warm and about 30-60 s fresh in `Test.Web.HeartbeatApi` (one real beat and its decision), well inside `image`'s `shard:lane-b`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
