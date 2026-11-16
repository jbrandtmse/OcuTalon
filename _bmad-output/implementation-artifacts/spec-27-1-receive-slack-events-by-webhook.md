---
title: 'Story 27.1: Receive Slack events by webhook'
type: 'feature'
created: '2026-11-16'
status: 'done'
baseline_revision: '8d801c4f33bfc23dbc8782e200344a2ccdba5872'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-27-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon has no Slack channel. A Slack user cannot message it, and Slack's Events API has no OcuTalon address to post to. Socket mode is ruled out because the platform's WebSocket client fails right after opening.

**Approach (the narrowed scope this plan proposes; see "Proposed split" under Design Notes):** add a fixed Slack route, `POST /ocutalon/hook/slack/events`, to the existing hook application. It checks Slack's v0 signature over the raw body in constant time, rejects stale or unsigned requests with 401 (counted with the hook's capped audit), answers URL verification, and hands every valid event to a new adapterless service, `SlackIn`, before answering 200. `SlackIn` drops a retried event by its `event_id`. A linked member's direct message becomes a `user`-provenance turn on channel `slack` in the member's session. Every other event leaves one content-free `Ignored` record in Visual Trace and goes no further. Slack is off, and the route answers 404, unless both env vars are set and the install is not the online demo. The story also creates the `DraftTransform` command verb and its `CommandsIn` route to `IncidentManager`, from origin `tool` only and only for the session's own incidents. Story 28.1 writes the handler.

## Boundaries & Constraints

**Always:**
- `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` are read only with `$SYSTEM.Util.GetEnviron`, at use. Neither value is ever stored, put in a setting, message, log line, audit entry, trace, agent step or test output (NFR-11, AD-19).
- Slack is on only when both variables are non-empty and the online-demo flag is off. When Slack is off, the route answers exactly like an unknown path (404, no body), and `SlackIn` refuses input.
- Signature: `v0=` + lower-case hex of HMAC-SHA256(`v0:<X-Slack-Request-Timestamp>:<raw body bytes>`, secret), compared over its full length with no early exit. A timestamp more than 300 s from now, in either direction, is stale. The body is the bytes exactly as received, never decoded or re-encoded before hashing.
- Check order: off → 404; declared or actual size over `Data.Webhook` `BODYMAX` → 413; signature missing, wrong or stale → 401; body not a JSON object → 400; `url_verification` → 200 with the challenge as `text/plain`; otherwise the event goes to `SlackIn` → 200 with no body, or 503 when the production can't take it. The answer never waits for a decision.
- 401, 413 and 400 are rejections. They are counted in the existing `Data.Webhook.Reject` slot `slack` and audited through `RecordRejection` at most once per 60 s.
- Inbound Slack content is UNTRUSTED. Only a direct message (`event.type` `message`, `channel_type` `im`, no `subtype`, no `bot_id`, a sender, text that is not blank) from a member with a `Data.SlackLink` row whose session row exists becomes a turn: an `OcuTalon.Msg.Item` with Channel `slack`, Provenance `user`, `FromGuide` 0 and only the text, sent asynchronously to `Conversation`, after `Core.Trace.Join` (AD-14, AD-26).
- An event id is processed once: the first claim within 2 hours wins, and a repeat (Slack's retry, `X-Slack-Retry-Num`) does nothing and still answers 200.
- The trace, the audit, the console log and the `Ignored` record carry no message text, Slack member id, team id, channel id, name or email. They carry only fixed kinds, reasons and the event id.

**Contest Planner gate rulings, 2026-11-16 ~16:30Z (BINDING; full text `.worktrees/.coordination/prompts/story-271-rulings-20261116.md` outside the repo; every item is pinned by a test):**
- R1 Loop and noise guard: only a plain message becomes a user turn: `channel_type` `im`, NO `subtype`, NO `bot_id`, from a LINKED member. Bot messages (our own replies once 27.2 lands included), edits, deletes, joins and file-share subtypes each leave one content-free `Ignored` record. Pinned with a `bot_id` event and a `message_changed` event.
- R2 The link match includes the team: an event counts only when BOTH its `team_id` and its member id match a `Data.SlackLink` row; the same member id from another workspace is Ignored. Pinned.
- R3 The signature is checked BEFORE `url_verification`: an unsigned challenge gets 401. Pinned.
- R4 Answer fast: turn processing is asynchronous, so the 200 returns within Slack's 3-second window; Slack's retries (`X-Slack-Retry-Num`) are deduped by `event_id`. Pinned.
- R5 A 401 or stale request stores nothing from the body: only the count and the once-a-minute audit. Pinned.
- R6 Nothing typed in Slack can approve, reject or answer an approval request: a Slack turn has the same rights as a typed web-chat turn and no approval surface. Pinned: a typed "approve" over Slack approves nothing.
- R7 Model-facing check: confirm FROM CODE that no agent instruction text keys on the channel name, and record the evidence (file:line search) under Design Notes. If any instruction mentions channels (for example a telegram branch), HALT with `intent gap` naming it, BEFORE implementation: a new channel value would then be model-facing and needs the Planner's key-holder A/B.
- R8 Link retention: the AD-27 purge, or the removal of the session, deletes a removed user's link rows. Pinned. Member ids and team ids are personal identifiers: no trace, log or audit line carries them.
- R9 CI dummy SLACK_* values are NOT global: they are set ONLY for the `live:slack-hook` unit's throwaway, through a per-unit compose override or env. Every other throwaway keeps Slack OFF, as a default install does, and one assertion pins that a default throwaway answers 404 on `/ocutalon/hook/slack/events`.
- R10 Privileges: no new grant. If Task 0 shows the `OcuTalonWebhook` grants are not enough, STOP (HALT `intent gap`) for the Planner.
- R11 Approved: the route, `Data.SlackLink`, `^OcuTalonP.SlackE`, the `SlackIn` item, `Intake` dropping `Ignored`, env-only secrets, no new dependencies; the AD amendments AD-13 (second route, its check order, the 200), AD-24 (`OcuTalonWebhook` serves `SlackIn`, no new grant), AD-26 (`Ignored` in its own trace session), AD-1 (`DraftTransform` from origin tool, answers `failed` until 28.1). Contended appends approved: Production.cls lane B region (sequence within lane B), `Test/Data/Tables.cls` append only, `live:slack-hook` in `shards-3` (~28.7 min).
- R12 Public text: the catalog keys and `.env.example` lines are approved verbatim (27.1 ships only `.env.example`); the setup steps are REORDERED (secrets before the URL check) and step 1 is reworded; 27.2 adds `chat:write` to step 1 in the same commit as the reply code.

**R7 RULING (Contest Planner, ~17:15Z Nov 16; BINDING; same file, last section):**
- Option (a) APPROVED: `slack` becomes a new channel value in `Data/DailyNote.cls` `LINEMESSAGE` and `LINEDECISION` (not `(web)`, not `(chat)`). `Agent/Triage.cls:37` does NOT change. Findings 3 and 4 accepted (27.2 raises `Msg/Catalog.cls` `CHANNELS` at its gate).
- BUILD 27.1 now; the MERGE is gated on the Planner's separate key-holder A/B passing (run by the Planner, never bundled with any other A/B).
- A/B design, fixed before any data: an eval FIXTURE KNOB, in tests and eval only, with NO production code path, renders the session-start notes block with a chosen channel label from the same fixed note set. Side A = `(telegram)`, side B = `(slack)`. Cases: every existing session-start eval case that carries notes; if fewer than 4 exist, add up to 4 notes-bearing cases that mirror existing ones (same expectations, with the notes block added). The case list is PINNED in this spec (`## Verification`, "R7 A/B cases") before the Planner runs. Default model Haiku 5.5, N = 5 per side, alternating, one stack at a time, attempt 1 of each run. PASS only if no case does worse on B than on A (rule (i)); a fallback counts as a miss.
- Deliverable for the A/B: once the knob and cases are pushed on `OCT-epic27`, the lead sends the orchestrator the sha and the EXACT command for each side. The spec therefore names both commands (side A, side B) under `## Verification`.

**Never:**
- No call to slack.com or any Slack API, no `SlackOut`, no reply in Slack, no WebSocket and no socket mode. The reply path is Story 27.2's.
- No Settings UI, no admin link/unlink command or REST route, and no shipped user-facing text. These move to the proposed sibling (Story 27.3). The texts are only proposed here.
- No edit to a Lane A class (Telegram's, `Watch/IncidentManager.cls`), and no new role, grant or `Data.Setting` key.
- No allowance call: Slack is off wherever the allowance flag is on (the online demo).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Linked DM | Signed `event_callback`, `message`/`im` from a linked member | 200, no body; one Item (slack, user, text) to `Conversation` in the member's session thread; a Turn row appears in that session, once | Hand-over error → 503, console line with no request data |
| Retry | Same `event_id` again, `X-Slack-Retry-Num: 1` | 200; nothing sent, nothing recorded | — |
| Unlinked member | Signed DM from a member with no link (or a link whose session row is gone) | 200; one `Ignored` (kind `message.im`, reason `unlinked`) in Visual Trace; no Item, no Turn | — |
| Channel message / bot / subtype / other type | Signed `message` in a channel, a bot's own message, `message_changed`, `app_mention`, `app_rate_limited` | 200; one `Ignored` with the matching reason; nothing else | — |
| URL verification | Signed `{"type":"url_verification","challenge":"c"}` | 200, `text/plain`, body `c`; nothing handed over | — |
| Unsigned / wrong / stale | Signature header missing or wrong, or timestamp off by more than 300 s | 401, no body; counted in slot `slack`; one audit entry per 60 s at most | Audit write failure is logged without request data |
| Too big / not JSON | Over 65,536 bytes; a form, text or JSON scalar | 413 / 400, no body; counted | — |
| Slack off | Either variable empty, or the online demo | 404 like any unknown path; nothing counted or handed over; `SlackIn` refuses input | — |

</intent-contract>

## Code Map

All classes are under `src/ocutalon/cls/OcuTalon/`. Lane = AD-29 owner.

**Inbound path (Lane B):**
- `Web/Hook.cls` -- hook dispatch class (Story 35.3). UrlMap :47-49 has the one route `/:ref` (:48); the Slack route goes BEFORE it. Reuse the private seams: `Rejected` :126 (capped count plus audit), `BodySize` :161, `IsForm` :170, `OnlineDemo` :206, `Log` :212, `ReportHttpStatusCode` :60 and `Http405` :67 (405 is rewritten to 404), `Hand` :192 (`CreateBusinessService` + `ProcessInput`; a disabled or missing item is an error, irislib `Ens/Director.cls:1470`). `BodyText` :177 decodes UTF-8: Slack's HMAC needs the undecoded bytes.
- `Data/Webhook.cls` -- `BODYMAX` :29 (65536), `Matches` :90 (constant-time loop shape), `Reject(slot, now, .count)` :196, `RecordRejection(slot, count)` :248 (Action `webhook_rejected`), `COUNTGLOBAL` :23 (precedent for a non-table global parameter). A Ref is always 22 characters, so slot `slack` and the two-segment path `/slack/events` never collide with a webhook.
- `Channel/Webhook/In.cls`, `Channel/Webhook/Event.cls` -- the adapterless-service and plain-event pattern for `SlackIn` and `Slack.Event`.
- `Channel/Telegram/In.cls` (Lane A, read-only, U-177) -- `Turn` :798-860 is the turn recipe (open the Session row; `Trace.Join`; set `%SessionId`/`%SuperSession`; build the Item; `SendTurn` :877-880 = `SendRequestAsync`; `Trace.Started` when the thread is new; always clear both ids and `Kill $$$JobSessionId`, re-throw). Slack skips its allowance and file steps (no allowance: Slack is off on the demo).
- `Core/Trace.cls` -- `Join(sessionRef, .sc, now)` :39, `Started(sessionRef, sessionId, now)` :84. Only channel services call Join.
- `Core/Intake.cls` -- `OnRequest` :72 calls `Refusal` :122, which warns on any non-Item. `Ignored` needs a silent early return before it. Tests: `Test/Core/Intake.cls` (`TestRefusedItems` :334).
- `Core/Conversation.cls` -- accepts `user` provenance only (:270), copies `Item.Channel` to the Turn and to `chat.message` (:230), `StartsSession` :532 adds `{"sessionStart":1}` (:507-513).
- `Data/Session.cls` -- `Ref` :28 (`%String(MAXLEN = 22)`, default collation), `RefIndex` :72 `[ Unique ]`, `ForEval` :136, `IsEval` :156, `DropEval` :165. No callbacks, triggers or foreign keys exist anywhere under `OcuTalon/`.
- `Data/Purge.cls` (Lane D, CONTENDED, read-only) -- the only person-session delete is `%DeleteId(id)` :87 in `DeleteSessions` :64, after `Keeps` :121 and `DeleteOwnedRows` :98. `Data.Session.DropEval` :178 is the only other delete (`%DeleteId`).
- `Data/Pairing.cls` -- sibling identity table (Telegram) for `Data.SlackLink`'s shape: `SessionRef` `%String(MAXLEN = 22)` :27, `SessionRefIndex` :58.
- `Core/AnswersIn.cls` -- the ONLY way an approval is answered (`Answer` with Action approve/reject, Channel `web`/`phone`/`telegram`, :9, :28; web via `Web/Api.cls:276` → `FromPage` :780; Telegram via inline-button `Press` `Channel/Telegram/In.cls:405-419`). No command verb answers an approval. `Test/Core/AnswersIn.cls:445` `TestAnswersInIsTheOnlySender`.
- `Production.cls` -- Lane B region ends at :106 (`<!-- lane B: end -->`), `WebhookIn` :105. `Test/Core/ProductionItems.cls` Lane B oracle (WebhookIn row :42); `Test/Install/Production.cls` `TestDefinition` :136.
- `src/short-names.tsv` (Webhook row :37; Pairing :13) + `docker/tests/test-storage.sh:3-10` (unique short/global/class; `DEFAULTGLOBAL` = the row's global; `DataLocation` global+`D`, `IndexLocation` global+`I`). `Test/Data/Tables.cls` (Lane D, append only): contract entry shape at :512-525 (`super`, `props` with exact type specs, `indexes` `"Props[ unique]"`; foreign keys are not compared), registry entries from :733, `TestEveryTableIsRegistered` :46.
- `Test/Web/HookProbe.cls`, `Test/Web/Hook.cls` (`TestOtherPaths` :184, `TestOnlineDemo` :249, `TestLogsHoldNothing` :299), `Test/Web/StubRequest.cls` -- the probe-subclass test pattern.
- `Test/Data/Fixture.cls` -- `Session` :22, `Turn` :64, `Approval(ownerRef, ...)` :137. `Test/Agent/KeyScan.cls` `SetEnv`/`UnsetEnv` (used by `Test/Install/Public.cls:308-324`) toggles an env var in-process.
- `Core/CommandsIn.cls` -- `TOOLVERBS` :71, origin check :118, own-incident check for `ProposeFix` :128, Routes row :381. `Test/Bridge/CodeRules.cls` `TOOLVERBS` copy :110; `Test/Msg/Contracts.cls` verbs list :42 and contract entries (Dismiss :361); `Test/Core/CommandsRouting.cls` `TestProposeFixToolOnly` :442 is the sibling test.

**R7 notes block:**
- `Data/DailyNote.cls` (Lane B) -- `LINEDECISION` :32, `LINEMESSAGE` :38; `Messages` fills `{channel}` with `row.Channel` :150; `Decisions` uses the turn's channel :168 (else `UsageChannel` :219 → `Ownership.DecisionChannel`, contended, not reached for a turn's decision); `Clean` :274 strips control characters only; `Fill` :281 substitutes verbatim. Nothing refuses or maps a channel value (`Turn.Channel` is a free `%String(MAXLEN = 32)`, `Data/Turn.cls:18`; `Msg/Enum.cls:36` CHANNEL already holds `slack`), so `slack` renders as `(slack)` with no DailyNote edit. `Build` :63 returns "" for the literal `eval` owner (`Literal` :95). `Test/Data/DailyNote.cls` `TestMessageLines` :105, `TestDecisionLines` :153, private `SetChannel` (used :115).
- `Agent/Input.cls` (Lane A, read-only) -- `NotesPart` :133 renders the notes only with `sessionStart` (:135); `Render(item, context)`.
- `Eval/In.cls` (Lane A; edited by the R7 knob only) -- `Start` :295 (run-level `preset`/`language`, the knob's precedent), case members doc :15-91, session rule :457 (`session` only on `command` cases), `SessionUp`/`SessionDown` :763-866, `TurnRequest` :1088-1098 (Item owner `eval`, `Render(item)` with no context, so today no case ever renders notes), case folders listed non-recursively :382-387.
- `eval/run.sh` (Lane A) -- usage :1-11, `--personas` mode (arguments around :80-142) is the precedent for a run-level variant mode; one attempt runs, attempts 2-3 only on a missed target. `eval/persona-cases/` is the precedent subfolder (outside the main set). `docker/tests/test-eval-set.sh` -- main-set lint excludes `held-out|mock-wrong|persona-cases` at :966; the other-folder variants at :2607.
- No eval case renders a notes block today (0 notes-bearing session-start cases), so the R7 A/B adds 4 mirrors.

**Live/CI:**
- `docker/tests/lib-live.sh` -- compose list `LIVE_FILES` :97, `live_add_file` :163, `live_pop_file` :923, `iris_script` :487, `check_session` :769, `session_value` :777, `LIVE_SESSION_ENV` :484-489. Per-unit env precedents: `test-production.sh:56-57` (`$tmp/compose.tz.yml`), `lib-online.sh:56-77`, `live_no_bot_token` :928-931; recreate-on-same-volume precedent `test-production-restart.sh:187-212`.
- `ci/compose.ci.yml:21-31` -- the global CI env (Telegram dummies). NOT edited (R9).
- `docker/tests/test-online-demo.sh` -- hook curl :485 (`-w '%{http_code}'`), `log_hits` :1744-1746, `check_records_clean` :1766-1790 (searches `Ens_Util.Log`, `OcuTalon_Live.Event`, `%SYS.Audit`), `console_lines` :675. Turn count SQL `test-online-allowance.sh:116`.
- `ci/units.sh` -- `live:<name>` → `docker/tests/test-<name>.sh` (:29-30); `shards-3` :158; `NO_WEB_BUNDLE_UNITS` :277 (leave out); Channel classes run in `shard:lane-a@Channel` (group `production`, :153), Data classes in `shard:lane-b@Contract,Core,Data,Live` (`image`, :157), Eval classes in `shard:lane-a@Install,Digest,Eval` (`shards`, :155). `docker/tests/test-ci-config.sh` :44 (every script in one group), :56-61/:1246-1262 (files a script reads must be claimed); a `$tmp` file is invisible to `unit_reads`.
- `.env.example` -- 5 lines; lists `ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`.
- irislib `%CSP/Page.cls:73-79` (`CONVERTINPUTSTREAM = 0`: the JSON body arrives unconverted; measured in Task 0); irissys `%SYSTEM/Encryption.cls:965` `HMACSHA(256, text, key)`; irislib `%Library/ConstraintForeignKey.cls:53-58` (`cascade` generates `delete from <referencing table> where <key> = :key`), `%Dictionary/ForeignKeyDefinition.cls:29-30`.

## Tasks & Acceptance

**Execution (in this order):**
- **Task 0 -- the implement stage's FIRST task (R10).** Measure on a lane-B throwaway (never slot B) and write the results under `## Verification` › "Task 0 record" before any code relies on them:
  - (a) Raw body: in the hook (CSP) process, for `application/json` and `application/json; charset=utf-8`, `%request.Content`'s class, `IsCharacter()`, and whether its bytes equal the bytes sent; a non-ASCII body's `$SYSTEM.Encryption.HMACSHA(256, ...)` hex equals `openssl dgst -sha256 -hmac` over the same bytes.
  - (b) `$SYSTEM.Util.GetEnviron("SLACK_SIGNING_SECRET")` and `("SLACK_BOT_TOKEN")` in the hook process return the container's values (set by a `$tmp` compose override as R9 says).
  - (c) `SlackIn`, created by `CreateBusinessService` in the hook process under the `OcuTalonWebhook` role's EXISTING grants, can read `Data.SlackLink` and `Data.Session`, `$Increment` `^OcuTalonP.SlackE`, and `SendRequestAsync` to `Conversation` and `Intake`. If ANY new grant, role or resource would be needed: STOP, write nothing else, HALT `blocked` with blocking condition `intent gap: R10 new grant needed` naming the missing privilege.
  - (d) R8: with `Data.SlackLink`'s `ForeignKey ... [ OnDelete = cascade ]` compiled, a `Data.Session` `%DeleteId` (Purge's and DropEval's call) and an SQL `DELETE` each remove the session's link row. If either does not, use the fallback in Design Notes › Decided in-stage 11 and record which.
- `Channel/Slack/Signature.cls` (new) -- pure class methods: `Check(secret, timestamp, signature, rawBody, nowEpoch) As %String` returns "" or a reason (`missing`, `stale`, `mismatch`); `STALESECONDS` 300 (either direction); compare over the full length with no early exit (shape of `Data.Webhook.Matches`). No state, no I/O.
- `Channel/Slack/Event.cls` (new) -- plain `%RegisteredObject` (like `Webhook.Event`), never stored: EventId, EnvelopeType, EventType, ChannelType, Subtype, BotId, TeamId, MemberId, Text.
- `Channel/Slack/Ignored.cls` (new) -- `Ens.Request` with ONLY `Kind`, `Reason`, `EventId`. Fixed sets as parameters: Kind `message.im`, `message.channel`, `message.other`, `app_mention`, `other`; Reason `unlinked`, `other_team`, `bot`, `subtype`, `not_im`, `blank`, `no_sender`, `unhandled_type`. No text, member, team, channel id, name or email (R8, NFR-14).
- `Data/SlackLink.cls` (new, Lane B) -- `Ref` (22), `TeamId` `%String(COLLATION = "EXACT", MAXLEN = 32)`, `MemberId` (same), `SessionRef` `%String(MAXLEN = 22)` (typed as `Data.Session.Ref`), `CreatedAt`. `DEFAULTGLOBAL` `^OcuTalonP.SlackLink`; `EVENTGLOBAL` `^OcuTalonP.SlackE`. Indexes: `RefIndex` (Ref, unique), `MemberIndex` (TeamId, MemberId, unique), `SessionRefIndex` (SessionRef, unique). `ForeignKey SessionFK(SessionRef) References OcuTalon.Data.Session(RefIndex) [ OnDelete = cascade ]` (R8). Object access only.
  - `SessionFor(teamId, memberId) As %String` -- "" unless a row matches BOTH ids (R2) and its session row exists.
  - `Link(teamId, memberId, sessionRef, .sc)` / `Unlink(sessionRef)` -- the writers Story 27.3's SettingsOps command will call; no product caller here (tests set links up).
  - `ClaimEvent(eventId, now) As %Boolean` -- atomic `$Increment` claim in `EVENTGLOBAL`, bucketed by UTC hour; kills buckets older than 2 hours on each claim (R4 dedupe).
- `Channel/Slack/In.cls` (new, `SlackIn`, extends `Ens.BusinessService`, adapterless; shape of `Channel/Webhook/In.cls`) --
  - `On()` (ClassMethod) and the variable-name parameters are the single source of "Slack on": both `SLACK_*` non-empty via `$SYSTEM.Util.GetEnviron` at call time and the online-demo flag off.
  - `OnProcessInput`: refuses (error status, nothing sent) when off or the input is not a `Slack.Event`. Claims the event id; a repeat returns OK and sends nothing (R4). Classifies: only `message` + `channel_type` `im` + no `subtype` + no `bot_id` + a sender + non-blank text + `SessionFor(team, member)` ≠ "" becomes a turn (R1, R2), by Telegram's recipe (copy, U-177): Item Channel `slack`, Provenance `user`, `FromGuide` 0, only the text, `Trace.Join` first, `SendRequestAsync` to `Conversation` through a private `SendTurn` seam. Anything else: one `Ignored` sent asynchronously to `Intake` through a private `SendIgnored` seam with `%SessionId`/`%SuperSession` empty (its own trace session, AD-26). Logs nothing that holds content or an id other than the event id.
- `Web/Hook.cls` -- add `<Route Url="/slack/events" Method="POST" Call="Slack"/>` BEFORE `/:ref`; `ClassMethod Slack()` in the intent's check order: off → 404 (same as an unknown path); size over `BODYMAX` → 413; signature missing/wrong/stale → 401 (R3: before any JSON parse or `url_verification`); body not a JSON object → 400; `url_verification` → 200 `text/plain` challenge; else `SlackHand(event)` → 200 no body, or 503 on a hand-over error. 401/413/400 call `Rejected("slack", ...)` and store nothing from the body (R5): no parse, no claim, no hand-over, no log of headers or body. New private seams: `SlackOn()` (calls `SlackIn.On()`), `SlackSecret()`, `SlackHeader(name)`, `RawBody()` (bytes, undecoded), `SlackHand(event)` (`CreateBusinessService("SlackIn")` + `ProcessInput`). JSON is parsed from the UTF-8-decoded bytes only after the signature passes. Class doc: "two routes".
- `Core/Intake.cls` -- `OnRequest` returns `$$$OK` at once for an `OcuTalon.Channel.Slack.Ignored`, before `Refusal`: no warning, no Join, no decision. Class doc updated.
- `Production.cls` (CONTENDED, approved R11) -- one line `<Item Name="SlackIn" ClassName="OcuTalon.Channel.Slack.In" PoolSize="0" Enabled="true"/>` after `WebhookIn`, before `<!-- lane B: end -->`. `Test/Core/ProductionItems.cls` -- the matching Lane B oracle row.
- `src/short-names.tsv` (approved append) -- `SlackLink	^OcuTalonP.SlackLink	OcuTalon.Data.SlackLink	B`. `Test/Data/Tables.cls` (CONTENDED, approved append only) -- the `OcuTalon.Data.SlackLink` contract entry and its registry entry; nothing else changes.
- `Msg/Command/DraftTransform.cls` (new) -- the `Dismiss` shape (`IncidentRef`) with `<Subscript>"DraftTransform"`. `Core/CommandsIn.cls` -- Routes row `{"verb":"DraftTransform","owner":"IncidentManager","origins":"tool"}`, `TOOLVERBS` append, own-incident check widened to `(verb = "ProposeFix") || (verb = "DraftTransform")` at :128. `Test/Bridge/CodeRules.cls` `TOOLVERBS` copy; `Test/Msg/Contracts.cls` verbs list and contract entry; `Test/Core/CommandsRouting.cls` `TestDraftTransformToolOnly` (sibling `TestProposeFixToolOnly`). `IncidentManager` answers `failed` (5001) until Story 28.1; no Lane A edit.
- `.env.example` -- the three approved lines (gate a), verbatim.
- **R7 knob (tests and eval only; no product request path reaches it):**
  - `Data/Turn.cls` (Lane B) -- `ForEval(sessionRef, channel, createdAt, text, Output sc)`: writes one Turn row of a state `DailyNote.Messages` lists; refuses (error, no row) unless `OCUTALON_EVAL` is 1, `Data.Session.IsEval(sessionRef)` and `channel` is in `Msg.Enum` CHANNEL (precedent `Data.Session.ForEval` :136).
  - `Data/Session.cls` (Lane B) -- `DropEval` :165 also deletes the eval session's Turn rows before the session row, so `Eval.In`'s Finish and its start sweep leave none.
  - `Eval/In.cls` (Lane A, existing; gate item g) -- `Start` gains a last argument `notesChannel As %String = ""`. A turn case (all-clear, command) may carry `notes`: an array of 1 to 4 `{minutesAgo, text}` (minutesAgo 1-600, text 1-200 characters). When `notesChannel` is "" the member is ignored and every case sends exactly what it sends today (inert). When set (must be a CHANNEL value, else every notes case is skipped with a new `REASONNOTES`), a notes case gets an eval session (`SessionUp`, widening the rule at :457 for this case), one `Data.Turn.ForEval` row per note with Channel = `notesChannel`, and its `TurnRequest` uses that session as the Item's `SessionRef` and renders with `{"sessionStart":1}`; `SessionDown` drops it.
  - `eval/run.sh` (Lane A, existing; gate item g) -- mode `--notes <channel>`, alone (CI mock) or after `--release-candidate` (real model), modelled on `--personas`: starts the same stack its base mode starts, runs `Eval.In.Start` over `eval/notes-cases/` once with that channel, attempt 1 only, and saves `notes-<channel>.json` and `.md` (`{channel, cases:[{name, hit, fallback}]}`, a case is a hit only when the same per-case check `Eval.Report` applies to the main set passes, and a fallback is a miss) in the report folder; it writes nothing in `eval/`. Usage lines added to the header.
  - `docker/tests/test-eval-set.sh` (Lane A, existing; gate item g) -- add `notes-cases` to the excluded folders at :966 and lint `notes` (shape above; only in `eval/notes-cases/`), with one bad-shape variant.
  - `eval/notes-cases/<4 folders>/case.json` (new) -- the four cases pinned under `## Verification` › "R7 A/B cases", each a copy of its source case with a new `name`, `recordedBy` "Story 27.1 (R7 A/B)" and the fixed notes set (Design Notes › Decided in-stage 16). Same expectations, `heldOut` false.
- **Tests:** `Test/Channel/SlackSignature.cls`; `Test/Channel/SlackHook.cls` + `Test/Channel/SlackHookProbe.cls` (extends `Test.Web.HookProbe` with the Slack seams); `Test/Channel/SlackIn.cls` + `Test/Channel/SlackInProbe.cls` (overrides `SendTurn`/`SendIgnored`); `Test/Data/SlackLink.cls`; `Test/Data/DailyNote.cls` (`TestSlackChannelLines`); `Test/Eval/NotesKnob.cls`; `Test/Web/Hook.cls` `TestOtherPaths` gains POST `/slack/events` with Slack off → 404; `Test/Core/Intake.cls` `TestIgnoredIsSilent`. Live: `docker/tests/test-slack-hook.sh` (unit `live:slack-hook`, group `shards-3`, via `ci/units.sh`), phases under `## Verification` › "live:slack-hook phases". Each pin is named in the matrix table below.
- **Spine (R11, Rule 20), in the same change:** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- apply gate item (f) exactly. Each amended AD Rule (AD-1 :109-, AD-13 :489, AD-24 :1032, AD-26 :1126-) carries `[AMENDED 2026-11-16, Story 27.1, Contest Planner ruling]`; then `memlog.py append` and `lint_spine.py` (`"ok": true`) as Rule 20 says, and refresh `updated:`.

**R1-R12 pins (each row is one pinning test; R-ids as in the binding block):**

| Rule | Scenario | Pinning test |
|---|---|---|
| R1 | signed `im` event with `bot_id` → one `Ignored` (reason `bot`), no Item | `SlackIn.TestBotIdIgnored` |
| R1 | signed `message` with `subtype` `message_changed` → one `Ignored` (reason `subtype`), no Item | `SlackIn.TestMessageChangedIgnored` |
| R2 | linked member id with another `team_id` → one `Ignored` (reason `other_team`), no Item | `SlackIn.TestOtherTeamIgnored`; `SlackLink.TestSessionForNeedsBothIds` |
| R3 | unsigned `url_verification` → 401, no challenge echoed | `SlackHook.TestUnsignedChallenge401`; live phase 3 |
| R4 | linked DM answered 200 in under 3 s; turn sent async | live phase 3 (`curl` `time_total` < 3.0) |
| R4 | same `event_id` with `X-Slack-Retry-Num: 1` → 200, nothing sent | `SlackIn.TestRetryOnce`; live phase 3 (one Turn after two posts) |
| R5 | 401 / stale request with a marker in its body → count +1, ≤ 1 audit per 60 s, no hand-over, no `^OcuTalonP.SlackE` node, marker in no log, audit, trace or row | `SlackHook.TestRejectedStoresNothing`; live phase 4 |
| R6 | open approval request; linked member types "approve" → request stays `pending` (AnsweredAt empty), exactly one `user` Item, no `AnswersIn` message | `SlackIn.TestTypedApproveApprovesNothing`; live phase 3 |
| R7 | a Turn with Channel `slack` renders `hh:mm message (slack): ...`, its decision `decision (slack)` | `DailyNote.TestSlackChannelLines` |
| R7 | knob renders `(slack)` / `(telegram)` from the same notes; unset → input identical to today's | `NotesKnob.TestChannelLabel`, `NotesKnob.TestInertWhenUnset` |
| R8 | deleting the session (`%DeleteId` and SQL) deletes its link row | `SlackLink.TestLinkGoesWithSession` |
| R8 | no member id or team id in any trace body, console log, `Ens_Util.Log` row or audit entry; no text in an `Ignored` record or a log line | `SlackIn.TestRecordsHoldNoIds`; live phase 5 |
| R9 | a default throwaway answers 404 on POST `/ocutalon/hook/slack/events` | live phase 1 |
| R9 | env unset → `SlackIn.On()` 0, route 404, `SlackIn` refuses | `SlackIn.TestOffWhenUnset`; `Web/Hook.TestOtherPaths` |
| R10 | grants suffice | Task 0 (c) |
| off/demo | online-demo flag on with both vars set → 404, nothing counted | `SlackHook.TestOnlineDemo` |

**Acceptance Criteria:**
- Given the change, when it lands, then the spine carries every edit of gate item (f), each amended AD Rule (AD-1, AD-13, AD-24, AD-26) tagged `[AMENDED 2026-11-16, Story 27.1, Contest Planner ruling]`, and `lint_spine.py` reports `"ok": true`.
- Given the repo, when it is read, then `.env.example` lists `SLACK_BOT_TOKEN` and `SLACK_SIGNING_SECRET` by name with empty values, and after the live run no console line, audit entry, `Ens_Util.Log` row, Interoperability message body or test output holds either dummy value or the fixture's member id or team id, no `Ignored` record or log line holds any message text, and the text of an ignored event appears nowhere in IRIS (NFR-11, R8).
- Given a request to `/ocutalon/hook/slack/events`, when it arrives, then each row of the I/O matrix and each R1-R6 row above holds, through the real hook application on a throwaway (`live:slack-hook`) and through the probe classes (FR-46, AD-13, AD-17).
- Given a linked member's direct message, when `SlackIn` handles it, then exactly one Turn with channel `slack` and provenance `user` exists in the member's session, joined to the session's daily thread, and the session's next session-start notes show it as `(slack)` (FR-46, AD-14, AD-26, R7). Integration AC: `Conversation` (the consumer) reads the Item and records the Turn row the web chat lists (live phase 3, real production).
- Given any other event, when it arrives, then exactly one `Ignored` record reaches `Intake` in a trace session of its own, and no Item, Turn, decision, reply or warning exists (NFR-14, AD-26). Integration AC: `Intake` (the consumer) drops it silently (`Intake.TestIgnoredIsSilent`).
- Given a link row, when its session row is deleted by the AD-27 purge's `%DeleteId`, `DropEval` or SQL, then the link row is gone (R8).
- Given `OcuTalon.Msg.Command.DraftTransform` with an `IncidentRef`, when it is submitted through `Core.Commands.Submit`: from a non-tool origin it is refused `not_allowed`; from origin `tool` for an incident the session can't see it is refused `not_found`; for the session's own incident it is sent to `IncidentManager` (pinned through the `Send` override). Integration AC: Story 28.1's handler consumes it (AD-1, AD-29).
- Given Slack off (either variable empty, or the online demo), when any request reaches the route, then it is 404 with nothing counted or handed over, `SlackIn` refuses input, and every other hook and test stays green; every throwaway but `live:slack-hook`'s has Slack off (AD-25, R9).
- Given the R7 knob, when `eval/run.sh --notes <channel>` runs on the CI mock, then it sends exactly the four pinned cases with notes whose lines read `(<channel>)`, saves `notes-<channel>.json`, and leaves no eval session, Turn row or watch behind; the main set's run is unchanged (R7 ruling).

## Spec Change Log

- 2026-11-16 ~17:20Z, lead: R7 ruled option (a) (see the binding R7 RULING block). Adds the eval fixture knob + pinned A/B cases + the two exact side commands to this story's scope (tests/eval only). Status reset `blocked` -> `draft` for re-plan 3; the re-plan derives everything left undone by re-plan 2 (R1-R12 tasks with pinning tests, R8 mechanism, R9 CI line, spine/AD edits, the split recorded as decided).

- 2026-11-16 ~16:35Z, lead: Contest Planner gate rulings R1-R12 applied (Boundaries & Constraints, binding block; setup steps reordered under Planner gate items). Changes the plan must carry: R2 team_id in the link match; R3 signature before url_verification; R5 nothing stored from a rejected body; R6 approve-proof pin; R7 model-facing evidence (HALT if any agent instruction keys on the channel); R8 link rows deleted with the session/purge, pinned, in THIS story (prefer a mechanism inside the new `Data.SlackLink` class, e.g. an SQL foreign key with cascade or the session's own removal path; `Data/Purge.cls` is lane D's contended file: only a self-contained appended block, reported, if unavoidable); R9 dummy Slack env only for `live:slack-hook`'s throwaway + a default-throwaway 404 assertion (no global `ci/compose.ci.yml` env); R10 Task 0 hard gate on grants. Status stays `draft` for the re-plan (cycle_iteration 2).

- 2026-11-16, lead (epic-27 runner), unattended ruling on the plan's split proposal (doctrine U5: a split into a sibling planned next in this epic, 1 of 6, category decide): ACCEPTED as proposed. Story 27.1 is the narrowed scope in this spec and keeps `DraftTransform` (no 27.4: moving it would change Epic 28's dependency text, owner-only). New Story 27.3 "Link Slack members in Settings" takes, verbatim, "how an admin links a Slack member to an OcuTalon user" and the texts criterion; order 27.1, 27.3, 27.2. `epics.md` amended (27.1's first and fourth criteria, Story 27.3 inserted before Epic 28); tracker key `27-3-link-slack-members-in-settings` added. Status reset to `draft`: the re-plan runs after the Contest Planner rules this spec's gate items (public text, veto items, contended appends, spine edits and the AD-1/AD-13/AD-24/AD-26 amendments); the rulings will be recorded here and under Design Notes.

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 40 findings — high 0, medium 3, low 28, false 9, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind Hunter: `test-slack-hook.sh` takes two `date +%s` readings for the challenge header and its signature — real: a second boundary between them gives a 401; patched: one `ts` read once.
  - `[low]` `[reject]` BH: `LinkedInAnotherTeam` scans every link row — real but the link table holds one row per linked member; the fix adds an index and a storage change, and an unlinked DM costs one short scan.
  - `[low]` `[reject]` BH: `Event.EnvelopeType` is never read — Slack signs only `event_callback` envelopes with an event; other types carry no `event` and fall to `unhandled_type`; the fix is a new branch with changed fixtures.
  - `[low]` `[reject]` BH: an event with no usable `event_id` is recorded as `Ignored` `unhandled_type` — Slack's `event_callback` always has a short event id; a guard would add a reason and a branch for a case Slack does not produce.
  - `[low]` `[patch]` BH: claim retention worded as two hours — buckets are whole UTC hours, so a claim is kept two to three hours; `CLAIMSECONDS` and `ClaimEvent` comments reworded.
  - `[low]` `[reject]` BH: Slack's `&amp;`, `&lt;`, `&gt;` and `<@U...>` markup reaches the Item text — real but cosmetic for a model that reads it plainly; decoding is a text-transform decision the spec does not make (27.2 or 27.3 can take it); recorded under Residual risks.
  - `[low]` `[reject]` BH: no unit test for a failed `Trace.Join` or `Trace.Started` — the paths are one logged warning each; forcing the failures needs a seam that adds more code than the paths hold.
  - `[low]` `[reject]` BH: `notes_run` counts all Turn rows and duplicates the channel list — the run owns a fresh throwaway; the duplicate list is now pinned by the `test-eval-personas.sh` forms (a bogus channel is refused).
  - `[false]` `[reject]` BH: the `2030` claim buckets of `TestClaimEvent` stay in the global — `Test.Data.SlackLink` kills `^OcuTalonP.SlackE` before and after the class.
  - `[low]` `[reject]` Edge Case Hunter: an event id over 64 characters or not a string is dropped — same as the BH event-id row.
  - `[low]` `[reject]` ECH: the envelope type is not checked — same as the BH row.
  - `[low]` `[reject]` ECH: the claim is given back when an exception follows a successful send — after `SendTurn` returns OK only `Trace.Started` (a status, logged) remains; an exception there is not shown to occur.
  - `[low]` `[reject]` ECH: zero-width or Unicode spaces count as text — the harm is one model turn for a message that looks blank, and the message is the member's own.
  - `[low]` `[reject]` ECH: the unlinked scan — same as the BH row.
  - `[false]` `[reject]` ECH: `RawBody` re-encodes a character stream with another charset — Task 0 (a) measured a binary stream for `application/json` with and without a charset, and Slack sends no charset.
  - `[false]` `[reject]` ECH: an unparseable `Now` makes every request stale — `Now` is the system clock in the fixed UTC format.
  - `[low]` `[reject]` ECH: `DropEval` deletes turns and the row without a transaction — eval-only; a half-dropped session is swept by the next start's `SweepSessions`.
  - `[low]` `[reject]` ECH: notes on a case that is not a turn kind are ignored silently — the notes lint of `test-eval-set.sh` admits notes only on all-clear and command cases.
  - `[low]` `[patch]` ECH: the `Signature` comment says all characters of the longer value are compared — the loop runs over the fixed expected length and the length test covers a longer value; comments reworded.
  - `[medium]` `[patch]` Verification Gap: the `--notes` and `--release-candidate --notes` forms of `eval/run.sh` have no repository check (key handling, refused forms, print guard) — patched: `docker/tests/test-eval-personas.sh` pins the forms, the key drop and refusal, the print order, and six sample mutations that it flags.
  - `[medium]` `[patch]` VG: nothing observes the `Start` notes-channel plumbing; deleting `Set service.NotesChannel = notesChannel` leaves `--notes` green and the A/B vacuous — patched: `notes_run` counts the Turn rows in the channel before `Finish` and `run.sh` checks they equal the notes the cases declare; mutation recorded.
  - `[medium]` `[patch]` VG: `Web.Hook.RawBody` has no test with non-ASCII or multi-chunk bodies, which a decode change would reject with 401 — patched: live phase 3c posts a signed UTF-8 event and a signed 40,000-byte event; mutation recorded.
  - `[low]` `[patch]` VG: `TestWholeLengthIsCompared` claims an early exit would fail it — a timing property is not testable here; the test's doc now says per-position detection only.
  - `[false]` `[reject]` VG: the last assertion of `TestTypedApproveApprovesNothing` cannot fail — the real `SlackIn` runs (only the two sends are stubbed) and a defect that answered an approval would turn it red.
  - `[false]` `[reject]` VG: probe mode `real` has no unit host — live phase 3 runs the real `SlackHand` and `ProcessInput`.
  - `[low]` `[reject]` VG: `TestUnsigned`'s wrong signature differs in length only — same-length mismatch is pinned by `SlackSignature.TestMismatch` and `SlackHook.TestRawBytesAreSigned`.
  - `[low]` `[reject]` VG: sub-rows (R1 edit, R2, 413/400, stale, thread join, `.env.example`) have no `mutation:` line of their own — each AC has a recorded mutation, and the sub-rows share the code those mutations break; extra lines would be more runs for the same code.
  - `[low]` `[reject]` VG: the AC 1 mutation as planned (one deleted tag) stays green at 7 tags — the recorded mutation deletes the four tags of AD-1, AD-13, AD-24 and AD-26 and drops the count to 2; the fix would edit the spec's planned wording.
  - `[low]` `[reject]` VG: `Settle()` is a wall-clock `Hang 1` — recorded in decision 24; the audit timestamps have one-second granularity.
  - `[low]` `[reject]` VG: `sleep 5` before the negative Turn and Ignored checks — each is preceded by an awaited positive (the Turn, the 200s), and the work is asynchronous but local.
  - `[low]` `[reject]` VG: `notes_run` asserts absolute counts — the run owns a fresh throwaway; same as the BH row.
  - `[low]` `[reject]` VG: `SlackIn` unit tests carry no throwaway-only note — documentation only; the class restores what it changes.
  - `[low]` `[patch]` VG: `TestDraftTransformToolOnly` doc says "the sibling of DraftTransform" — reads "the sibling of ProposeFix".
  - `[low]` `[patch]` VG: claim retention two to three hours — same as the BH wording row.
  - `[false]` `[reject]` Intent Alignment: a form is answered 400 before the signature check — the matrix row "a form, text or JSON scalar → 400" and decision 18 (the web server keeps no raw bytes for a form).
  - `[low]` `[reject]` IA: "answers `failed` until 28.1" is not pinned at `IncidentManager` — AC 7 is pinned through the `Send` override and `Watch/IncidentManager.cls` is Lane A's, not to be edited; the generic unhandled-request error is the existing behaviour.
  - `[false]` `[reject]` IA: class-level tests use a probe subclass — the live unit covers the real web application surface (44 PASS lines).
  - `[false]` `[reject]` IA: R7 adds no product edit to `DailyNote` — `LINEMESSAGE` and `LINEDECISION` take the channel as a value and `Msg.Enum` `CHANNEL` already holds `slack`; `Test.Data.DailyNote` pins the `(slack)` lines.
  - `[false]` `[reject]` IA: additions outside the spec's list (`DropEval` turns, `Turn.ForEval`, boundary and compose-file test repairs) — gate items g and h and decisions 25 and 26.
  - `[low]` `[reject]` IA: an envelope with no event id is `Ignored` — same as the BH event-id row.

## Design Notes

**Governing ADs:**
- AD-1 (commands; the route writes only the existing counters; `DraftTransform` joins the tool-origin list: AMENDED, R11).
- AD-3 (private globals), AD-4 (identity only in its own row; messages carry `SessionRef`).
- AD-13 (the hook application: AMENDED, R11: a second route, its order, its 200).
- AD-14 (channel pair, provenance), AD-17 (the only audit writer, capped rejections), AD-19 (env-only secrets, endpoint overrides).
- AD-22 (the evaluation set: the R7 knob stays outside the main set and the held-out set).
- AD-24 (`OcuTalonWebhook` serves `SlackIn` with no new grant: AMENDED, R11), AD-25 (online demo).
- AD-26 (trace join; `Ignored` in a trace session of its own: AMENDED, R11), AD-27 (retention: links go with their session, R8).
- AD-29 and AD-33 (Lane B ownership; the cross-lane R7 knob edits are gate item (g)).
- No AC contradicts an AD Rule beyond the four approved amendments (AD-1, AD-13, AD-24, AD-26). AD-19 and AD-27 gain no Rule change: the Slack variable names go into AD-19's list as gate item (f) records, and the link deletion is stated in the Tables paragraph, not in AD-27's Rule.

**Already met on this branch (evidence):**
- `Msg.Enum` CHANNEL already holds `slack` (`Msg/Enum.cls:36`).
- The hook app is absent on the online demo (`Install/Step/Web.cls:306-317`, `RemoveHook`), so Slack is unreachable there regardless.
- `Data.Delivery`, `Web.History` and the usage view already accept `slack`.
- `Data.DailyNote` renders any channel value verbatim (Code Map › R7), so R7 option (a) needs no DailyNote edit, only its pin.

**Split (decided 2026-11-16, lead, unattended, decide; recorded in the Spec Change Log):** 27.1 is the narrowed scope in this spec and keeps `DraftTransform` (moving it would change Epic 28's dependency text, `epics.md:826` and Story 28.1, owner-only). Order 27.1, 27.3, 27.2. Moved-criteria record (verbatim, now Story 27.3 "Link Slack members in Settings"):
- from the first criterion: "and how an admin links a Slack member to an OcuTalon user (AD-14, AD-19, AD-29, AD-33)";
- the shipping half of the texts criterion: "the step 7 texts the UX doesn't give (the Slack channel's state and member-linking in Settings, and its setup steps) are proposed to the author as additions to `EXPERIENCE.md` (Message Catalog, and Later Steps), with their catalog keys in `OcuTalon.Msg.Catalog.Core`, and no story of this epic ships a text the author hasn't accepted (UX-DR117)". 27.1 keeps the proposal (gate item a).
- 27.3's scope: admin-only link/unlink through SettingsOps (audit, user names via `SecretHandoff`, AD-24), an admin REST class forwarded from `Web/Api.cls`, Settings › Channels Slack state and linking UI (lazy), catalog keys, the "via Slack" marker, the GUIDE setup section, and whether a linked session is kept by `Data/Purge.cls` `Keeps` (this story's cascade already deletes links with their session).

**Decided in-stage:**
1. Route address `POST /ocutalon/hook/slack/events`: two segments, so it never matches `/:ref`; `slack` fails `Data.Webhook.IsRef`. Webhook names are never in paths.
2. "On" needs both variables (stricter than "no token": without the signing secret nothing can be verified).
3. No install step and no `Data.Setting` key. `SlackIn` is enabled with PoolSize 0, as `WebhookIn` is; the route's `On()` gate is the switch.
4. Reuse `Data.Webhook.Reject`/`RecordRejection` with slot `slack` (extend, Rule 2). The audit action stays `webhook_rejected`.
5. Dedupe in `SlackIn`, not in the REST code (AD-1): a 2-hour, self-pruning global, `EVENTGLOBAL` on `Data.SlackLink` (precedent `Data.Webhook` `COUNTGLOBAL`).
6. The trace-only record is an `Ignored` message to `Intake`, which drops it silently; a new sink item would add a production item.
7. 200, not 202, for events (Slack's contract); the challenge is echoed as `text/plain`.
8. No allowance call (demo-only flag). A retried event leaves no second record.
9. Turn recipe copied from Lane A's `Telegram.In.Turn` (U-177: a Lane B story may not edit or extract from a Lane A class). `Hook.Slack` extends `Web.Hook`'s seams; `Signature`'s compare copies the shape of `Data.Webhook.Matches` (salted SHA-256 there, HMAC hex here). `SlackHookProbe` extends `Test.Web.HookProbe`; `SlackInProbe` follows `Test/Channel/TelegramInProbe.cls`'s seam-override shape.
10. "via Slack" marker: moves to 27.3 (`web/src/app/chat/**` is contended).
11. R8 mechanism: a cascading `ForeignKey` on `Data.SlackLink` to `Data.Session(RefIndex)`, inside the new class, so the AD-27 purge's `%DeleteId` (`Purge.cls:87`), `DropEval` and any SQL delete remove the links with no edit to `Data/Purge.cls`. `SessionRef` is typed exactly as `Session.Ref` so both sides compare in one collation. Fallback, only if Task 0 (d) shows a path the cascade misses: `Data.Session` (Lane B, not contended) gets `%OnDelete` plus an SQL `AFTER DELETE` trigger that deletes the session's links ("the session's own removal path"); still no `Purge.cls` edit. A session tied only by a Slack link is not kept by `Keeps`; it is purged by AD-27's rule and its link goes with it (27.3 may add a `Keeps` line at its gate).
12. R9 mechanism: `test-slack-hook.sh` writes `$tmp/slack.yml` (an `iris` `environment:` block with the two dummy values held in shell variables) and layers it with `live_add_file`, as `test-production.sh:56-57` and `lib-online.sh` do. A `$tmp` file, not a checked-in compose file: a file under `docker/tests/compose*.yml` matches `IRIS_INPUT` and would run every group. `ci/compose.ci.yml` is not edited, so every other throwaway, CI's included, has Slack off.
13. R9 default-404 assertion: phase 1 of `live:slack-hook` itself, on its own throwaway before the override is layered (recreate on the same volume, precedent `test-production-restart.sh:187-212`), so lane B keeps one throwaway at a time. An online-demo stack would prove nothing (its hook answers 404 anyway).
14. R6 needs no code: approvals are answered only through `Core/AnswersIn.cls` (web page route and Telegram buttons), never by a turn's text; `SlackIn` sends only an Item to `Conversation` and an `Ignored` to `Intake`. The pin proves it end to end.
15. R7 knob: no eval case renders notes today (Code Map), so the knob adds the smallest real path: Turn rows written through an eval-only writer and rendered by the product's own `DailyNote` and `Agent.Input.NotesPart`, instead of a text substitution that would test nothing. Run-level argument + case member + `run.sh` mode is the persona sweep's precedent (Story 40.7: `Start(..., preset, language)`, `--personas`, `eval/persona-cases/`). Story 0.35/0.37's A/Bs had no knob (they compared two checkouts), so they set only the run-command form. The four notes cases live in `eval/notes-cases/`, outside the main and held-out sets, so SM-1/SM-2, the held-out hashes and `rules-only.json` are unchanged. A notes case's Item has the case's eval session as `SessionRef` (so `NotesPart` reads it); the request's `OwnerRef` stays `eval`. Its input can differ from its source case by what an empty eval session adds to the persona and core blocks; both A/B sides share that, so the comparison isolates the channel label.
16. The fixed notes set (identical on both sides, no personal data, nothing actionable): `{"minutesAgo": 170, "text": "Good morning, I'm on shift until six."}`, `{"minutesAgo": 95, "text": "Thanks, that helps."}`, `{"minutesAgo": 40, "text": "Back from lunch now."}`.
17. The A/B verdict is computed by the Planner from the ten `notes-<channel>.json` files (command under `## Verification`); the pipeline never runs a side.
18. (implement stage) A form content type (`application/x-www-form-urlencoded`, `multipart/`) is answered 400 before the signature check, not after it. Measured in Task 0 (a): for a form the web server parses the body and leaves `%request.Content` unset, so no signature over its bytes can be computed, and a signed form would otherwise be 401 and never 400. It is a rejection counted like the others and Slack's events are never forms.
19. An envelope field longer than its limit (event id 64, team and member id 32, type 64, and so on) or not a string is read as empty (`Channel.Slack.Event`), so a long value never matches a row by its first characters and an event id is always a usable global subscript. An envelope with no usable event id is recorded as `Ignored` (kind `other`, reason `unhandled_type`, empty event id) and never claimed.
20. Claims are bucketed by UTC hour and a claim is kept at least 2 and at most 3 hours (the buckets from the hour of now minus 2 hours on); `UnclaimEvent` gives a claim back when the hand-over fails (a send error or a throw), so that Slack's retry after the 503 is processed instead of dropped.
21. `SlackIn.On(demo = "")` takes the online-demo flag as an optional argument so that the route passes its own seam (`Hook.OnlineDemo`) and stays the one source of "Slack on"; an `Ignored` reason for a member that is linked only in another workspace is found by `Data.SlackLink.LinkedInAnotherTeam` (object reads over the link rows by id: one row per linked person).
22. `eval/run.sh --notes` calls `Eval.In.Start`, `Wait`, `Report.Build` and `Finish` itself (all public) instead of adding an argument to `Eval.Report.Run`, so `Eval/Report.cls` is not edited. A case is a hit when `Report.Build` scores it right and it is not in `report.fallbacks`; a case that is skipped or not scored is a miss, so every run lists the same four names.
23. `live:slack-hook` runs the rejection burst (its phase 4) straight after the unsigned challenge of phase 3, before the events, so that all six rejections fall inside one 60-second audit window and the "one audit entry" check is exact; the phases are otherwise the plan's. Its leak scan uses `Test.Eval.KeyProof.GlobalHits` and `TraceHits` (existing helpers, any value) with a positive control for each, and a shell loop of `grep -cF` over the container's output, `messages.log` and the after-start log.
24. The unit tests use the real clock for the hook probe (a fixed time in 2030 let the web area's purge of the rejection counters, which writes an entry for a slot stamped in the future, interleave with a test) and wait 1 s (`Settle`) before taking an audit mark, because the audit entry of the previous test's first rejection can land after the next test's mark (seen 3 runs in 4 without it).
25. Two scripts outside the spec's file list needed a one-line change that the story's own change forces, both made and reported: `docker/tests/test-boundaries.sh` (the rule "ForEval and DropEval are called only by Eval/In.cls" names the definition line of `Data.Turn.ForEval`, the eval-only writer of gate item h, as it names those of `Data.Session`) and `docker/tests/test-compose-file.sh` (the `.env.example` check lists the two Slack lines the story ships, with no value).
26. `ci/units.sh` carries a comment for the new unit as earlier rebalances do. No `ci/compose.ci.yml`, workflow or `release/**` change.

**Integration ACs / Consumed-by / Consumes:**
- Consumes: `Conversation` (turns; Integration AC 4, real production in `live:slack-hook`), `Intake` (`Ignored`; Integration AC 5), `Core.Trace`, `Data.Session`, `Data.Webhook` counters, `Data.DailyNote` and `Agent.Input` (R7).
- Consumed-by:
  - Story 27.3: its SettingsOps link/unlink commands call `Data.SlackLink.Link`/`Unlink`; its Settings UI reads `SlackIn.On()`.
  - Story 27.2: `SlackOut` replies to the turns `SlackIn` makes; it reads `OCUTALON_SLACK_API_BASE`.
  - Story 28.1: handles `DraftTransform` in `IncidentManager`.
  - The Contest Planner's R7 A/B: runs `eval/run.sh --release-candidate --notes <channel>`.
- `Data.SlackLink`'s writers have no consumer in this story; the first is Story 27.3.

**R7 model-facing check (plan stage, 2026-11-16; result: model-facing channel text FOUND; ruled option (a) by the Contest Planner, see the binding R7 RULING block):**
- Searched from the worktree root, in `src/ocutalon/cls/OcuTalon/`:
  - `grep -niE "telegram|webchat|web_chat|web chat|slack|channel" Agent/*.cls`
  - `grep -rniE "telegram|webchat|web_chat|slack|\bemail\b|channel" Tools/ Memory/ Memory.cls Data/DailyNote.cls Digest/ Mcp/ Docs.cls Docs/ Fix/ Watch/EvidencePack.cls Watch/Summary.cls Agent/` (non-comment lines, then the `///` lines of `Tools/`, which are tool descriptions)
  - `grep -rniE "telegram|slack" Core/Conversation.cls Core/Intake.cls Msg/Catalog.cls Msg/Catalog/ Agent/Chat.cls`
- Findings (the first one is decisive):
  1. `Data/DailyNote.cls:38` `LINEMESSAGE = "{time} message ({channel}): {text}"`, filled with `Turn.Channel` at `:150`, and `:32` `LINEDECISION = "{time} decision ({channel}): {outcome}"`, filled with the turn's channel at `:168`. `Agent/Input.cls:67` adds `NotesPart` (`:133`, opening `NOTESOPENING` `:329`) to every user-provenance turn that starts a session (`Core/Conversation.cls:513`). A Slack turn is a `Turn` row with Channel `slack`, so from the next session start of that session, in any channel, the model reads lines such as `09:14 message (slack): ...`. The value `slack` therefore becomes model-facing. Today it reads `(web)` and `(telegram)` there.
  2. `Agent/Triage.cls:37` (INSTRUCTIONS XData): the triage instruction keys on channels: "A message that does not say which channel it arrived on and is not quoted is the user's own chat message". `:39` names the channel `heartbeat`. A Slack user turn renders with no channel label (`Agent/Input.cls:61-67`), so it takes this branch exactly as a web or Telegram turn does. Even so, it is an instruction that mentions channels.
  3. `Agent/Input.cls:75`: the code-written label "The message below arrived on the channel <channel>" goes on every non-user item. In 27.1 it cannot reach `slack`, because a Slack item is always `user`, and `Ignored` never reaches `Render`.
  4. Unreachable for `slack` under R6, because Slack never answers an approval:
     - `Watch/Summary.cls:36` `CHANNELNAMES` (a telegram branch in the `incident_summary` tool output, keyed on `AnsweredChannel`);
     - `Tools/RecentActivity.cls:65` (tool description "channel: where it was answered") and `:196-200`;
     - the precedent lines at `Agent/Input.cls:173-180`.
  5. No tool description, agent INSTRUCTIONS block or model-read catalog text names `telegram`, `webchat` or `slack`. `Tools/DigestTools.cls:23` says "digest channels" generically.
- For 27.1/27.2 (not part of R7): `Msg/Catalog.cls:46` `CHANNELS` refuses `slack` ("refused until their step adds them", `:32`, `:108`). Every user-facing render keyed on a Slack origin therefore fails until a story adds `slack` there. In 27.1, Notify sends a `slack` origin to the web chat only, so this is Story 27.2's.
- Ruling applied (R7 option (a)): `slack` becomes a channel value in the notes block's `LINEMESSAGE`/`LINEDECISION`; `DailyNote` already passes it through unchanged (Code Map › R7, no edit; pinned by `DailyNote.TestSlackChannelLines`); `Agent/Triage.cls:37` does not change; findings 3 and 4 stand (27.2 raises `Msg/Catalog.cls` `CHANNELS` at its gate). The merge of this story waits on the Planner's key-holder A/B (`## Verification` › R7 A/B).

### Planner gate items: ruled 2026-11-16 (R1-R12, R7 option a)

- (a) PUBLIC TEXT, proposed verbatim for EXPERIENCE.md. They ship in 27.3, keys in `Msg.Catalog.Core`:
  - `settings.slackHeading` "Slack"
  - `settings.slackNotSetUp` "Slack not set up. Add SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET to .env and restart OcuTalon."
  - `settings.slackHowTo` "How to set it up"
  - `settings.slackOn` "Slack on"
  - `settings.slackAddress` "Subscribe your Slack app's events to {address}."
  - `settings.slackOffOnDemo` "Slack is off on the online demo, so it has no public Slack address. It works on your own install."
  - `settings.slackMembersHeading` "Linked Slack members"
  - `settings.slackMembersHelp` "Only direct messages to the bot from a linked member become chat turns. Everything else from Slack is recorded in Visual Trace and goes no further."
  - `settings.slackMemberId` "Slack member ID"
  - `settings.slackMemberUser` "OcuTalon user"
  - `settings.slackLink` "Link member"
  - `settings.slackUnlink` "Unlink"
  - `settings.slackNoMembers` "No Slack members are linked yet."
  - `settings.slackBadMemberId` "Enter a Slack member ID such as U012AB3CDE: a U or W followed by letters and digits. Nothing was changed."
  - `settings.slackMemberTaken` "That Slack member is already linked to another user. Nothing was changed."
  - `settings.slackUserTaken` "{user} already has a linked Slack member. Unlink it first. Nothing was changed."
  - `settings.slackLinked` "Linked. Their direct messages to the bot now reach OcuTalon. Recorded in the audit log."
  - `settings.slackUnlinked` "Unlinked. Their messages no longer reach OcuTalon. Recorded in the audit log."
  - `chat.viaSlack` "via Slack"
  - Setup steps (Later Steps and the GUIDE's Slack section), as APPROVED and REORDERED by the Planner (R12):
    1. "Create a Slack app for your workspace at api.slack.com/apps. In App Home, turn on the Messages Tab and allow users to send messages from it. Give its bot the im:history scope, and install it to the workspace."
    2. "Copy the bot token and the signing secret into .env as SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET, then restart OcuTalon."
    3. "Under Event Subscriptions, set the request URL to https://<your public address>/ocutalon/hook/slack/events and subscribe the bot to the message.im event. OcuTalon answers Slack's check at once."
    4. "As an admin, open Settings › Channels › Slack and link each person's Slack member ID to their OcuTalon user. Only linked members' direct messages to the bot reach OcuTalon."
  - `.env.example` lines (this story):
    - "# Slack (optional): set both to turn Slack on. Leave empty to keep it off."
    - "SLACK_BOT_TOKEN="
    - "SLACK_SIGNING_SECRET="
- (b) Outward actions: none. The only traffic is OcuTalon's answer to Slack's own HTTP request: status lines and the URL-verification challenge echo. Nothing is sent to slack.com or any other service. CI and the pipeline use dummy values and curl to the throwaway only. The R7 A/B's real-model runs are the Planner's (key-holder), never the pipeline's.
- (c) Veto items (approved, R11), each with its online-demo behaviour:
  - New route `POST /ocutalon/hook/slack/events`. Demo: the hook app does not exist and the dispatch answers 404.
  - New table `Data.SlackLink` (Ref, TeamId, MemberId, SessionRef, CreatedAt; cascading foreign key to `Session`). Demo: exists, stays empty, never read.
  - New global `^OcuTalonP.SlackE` (event-id claims, kept 2 h, self-pruning). Demo: never written.
  - Retention of links (R8): a link row is deleted with its session row (AD-27 purge, `DropEval`, any delete) by the cascade; 27.3 adds unlink and decides `Keeps`.
  - Secrets: `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN`, env-only, read at use in the hook process, never stored. CI dummy values only in `live:slack-hook`'s own `$tmp` compose override (R9); `ci/compose.ci.yml` unchanged. Demo: unset, so Slack is off.
  - Privileges: no new role, resource or grant (R10). `SlackIn` runs under the existing `OcuTalonWebhook` grants; Task 0 (c) proves it or HALTs `intent gap: R10 new grant needed`.
  - New production item `SlackIn` (adapterless, PoolSize 0). Demo: present, unreachable.
  - `Intake` accepts `Ignored` silently.
  - No new dependency.
- (d) Model-facing text changes: one, ruled R7 option (a): a Slack turn's notes lines read `(slack)` at later session starts. No prompt, tool description, INSTRUCTIONS block or model-read catalog text changes, and `DraftTransform` gets no tool in this story. The merge waits on the Planner's A/B.
- (e) Contended paths (approved appends, R11):
  - `src/ocutalon/cls/OcuTalon/Production.cls`, Lane B's region: one line `<Item Name="SlackIn" ClassName="OcuTalon.Channel.Slack.In" PoolSize="0" Enabled="true"/>` inserted before `<!-- lane B: end -->` (sequenced within lane B).
  - `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` (Lane D): append the `OcuTalon.Data.SlackLink` contract entry and its registry entry; nothing else.
  - One-name appends, reported: `src/short-names.tsv`, `ci/units.sh` (`live:slack-hook` in `shards-3`, about 28.7 min planned).
  - Not edited: `Data/Purge.cls` (R8 uses the cascade), `ci/compose.ci.yml` (R9), any Telegram class, `Watch/IncidentManager.cls`.
- (f) Spine edits (implement-stage task; `ARCHITECTURE-SPINE.md`, read by line range):
  - Production-item table (:1540-): `| `SlackIn` (step 7), `SlackOut` (step 7, Story 27.2) | `OcuTalon.Channel.Slack.In`, `.Out` | B |`.
  - Tables paragraph (:1571): Lane B owns `SlackLink`, deleted with its session by a cascading foreign key (R8), with `^OcuTalonP.SlackE` claims written only by `SlackIn` and kept 2 h.
  - ER diagram: `Session ||--o| SlackLink : "has at most one"`.
  - REST surface (:1824-): a `POST /ocutalon/hook/slack/events` row.
  - AD-19 (:696-): Slack's variable names in its env-only list, and `OCUTALON_SLACK_API_BASE` joins the endpoint overrides (read by 27.2).
  - Setting keys: none. Slack is configured by environment only.
  - Member identity: lives only in the `SlackLink` row; messages carry `SessionRef` only (AD-4, AD-14). How an admin links one is 27.3's edit.
  - Deferred (:1894-) and AD-29 (:1191, "Step 7 ... moves to after the contest"): step 7 now runs (owner decision 2026-11-16).
  - AD amendments (approved, R11), each tagged `[AMENDED 2026-11-16, Story 27.1, Contest Planner ruling]`:
    - AD-13's Rule (:489): "One route, `POST /<ref>`" becomes two routes, adding `POST /slack/events` with its own order (404 off, 413, 401 by Slack signature (before `url_verification`), 400, 200 challenge, 200 or 503) and its answer of 200 rather than 202.
    - AD-24 (:1032): `OcuTalonWebhook` also serves `SlackIn`, with no new grant.
    - AD-26 (:1126-): an event with no session leaves an `Ignored` record in a trace session of its own.
    - AD-1 (:109-): `DraftTransform` joins the tool-origin list (own incident only, routed to `IncidentManager`).
- (g) Cross-lane edits for the R7 knob (Lane A's `OcuTalon.Eval` and `eval/`, AD-29; required by the R7 ruling's eval knob; reported here as the dispatch asked). Existing files edited: `src/ocutalon/cls/OcuTalon/Eval/In.cls` (`Start` argument, `notes` member, session rule, `TurnRequest`), `eval/run.sh` (`--notes` mode), `docker/tests/test-eval-set.sh` (`notes-cases` exclusion and lint). New files: `eval/notes-cases/*/case.json` (4), `src/ocutalon/cls/OcuTalon/Test/Eval/NotesKnob.cls`. No existing case, held-out file or main-set result changes. Not contended by any running epic.
- (h) Eval-only writers in Lane B data classes (R7 knob; precedent `Data.Session.ForEval`): `Data.Turn.ForEval` (refuses unless `OCUTALON_EVAL` is 1 and the session `IsEval`) and `Data.Session.DropEval` also dropping the eval session's Turn rows. No product request path calls either.

## Verification

LANE below means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=27 stage=implement'`. Every call runs in the foreground with `timeout: 600000` from the worktree root, one test-runner call per message, sized to about 150 s. Warm runs use tag `e27s1iw` after `LANE OCUTALON_RUN_TAG=e27s1iw ci/warm.sh up`; the stage ends with `LANE OCUTALON_RUN_TAG=e27s1iw ci/warm.sh down`, also after a failure. Never slot B.

**Task 0 record (R10), measured 2026-11-16 on lane-B throwaways tagged `e27s1t0` (two runs, same results; the second fixed a CRLF artefact of the probe's own comparison), with dummy `SLACK_*` values from a `$tmp` compose override, in a temporary `/e27probe` application built from `/ocutalon/hook`'s own properties (role `OcuTalonWebhook`, unauthenticated, user `UnknownUser`) and a scratch probe class; both were removed with the throwaway:**
- (a) Raw body: for `application/json` and for `application/json; charset=utf-8`, `%request.Content` is a `%CSP.BinaryStream`, `IsCharacter()` is 0, `Size` equals the bytes sent, and the characters read are all below 256. For a non-ASCII body (UTF-8 for `{"t":"caf<e-acute> <CJK> <u-umlaut>x"}`, 21 bytes) the bytes read equal the bytes sent (hex compare, both content types), and `$SYSTEM.Encryption.HMACSHA(256, "v0:<ts>:"_raw, secret)` as hex equals `openssl dgst -sha256 -hmac` over the same bytes (both content types). `%request.ContentType` shows `application/json` without the charset. A form content type leaves `%request.Content` unset (not an object), so `RawBody()` and `BodySize()` must test `$IsObject` (the existing `BodySize` and `BodyText` already do).
- (b) `$SYSTEM.Util.GetEnviron("SLACK_SIGNING_SECRET")` and `("SLACK_BOT_TOKEN")` in the hook process return the container's values (length and SHA-256 compared with the shell's, no value printed).
- (c) In the hook process, under the role's existing grants alone (`$Roles` = `OcuTalonWebhook`): `Data.Session` read OK; a read of a link-shaped table with a unique `(TeamId, MemberId)` index and a `SessionRef` index OK; `$Increment` of a `^OcuTalonP.*` node OK; `Core.Trace.Join` and `Started` (a read and a write of the Session row, with its lock) OK; `CreateBusinessService` of the existing `WebhookIn` item and `SendRequestAsync` from it to `Conversation` and to `Intake` OK (status OK each). `SlackIn` itself did not exist yet, so the stand-in is `WebhookIn`, whose item and hook role are the ones `SlackIn` will have; live phase 3 re-proves it with the real item. No new grant, role or resource is needed.
- (d) R8: with a `ForeignKey SessionFK(SessionRef) References OcuTalon.Data.Session(RefIndex) [ OnDelete = cascade ]` on a link-shaped scratch table compiled, `Data.Session` `%DeleteId` removed the session's link row, and an SQL `DELETE FROM OcuTalon_Data.Session` removed the other session's link row. The same key refuses a link whose `SessionRef` has no session. The cascade works; the Design Notes 11 fallback is not needed.

**Commands:**
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Channel.SlackSignature` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Channel.SlackHook` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Channel.SlackIn` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Data.SlackLink` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Data.DailyNote` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Web.Hook` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Core.Intake` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Core.CommandsRouting` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Eval.NotesKnob` -- expected: CLASS passed (the knob's own unit test: `(slack)` vs `(telegram)` from the same notes; inert when unset)
- (loop) `LANE OCUTALON_RUN_TAG=e27s1l ci/iris.sh live slack-hook` -- expected: exit 0 (fresh stack with one recreate; about 3 to 4 min locally, inference)
- (once) `LANE OCUTALON_RUN_TAG=e27s1o ci/iris.sh class OcuTalon.Test.Core.ProductionItems`, then separately `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Msg.Contracts` and `OcuTalon.Test.Bridge.CodeRules`, one per call, then `LANE OCUTALON_RUN_TAG=e27s1o ci/iris.sh teardown` -- expected: each CLASS passed
- (once) `LANE OCUTALON_RUN_TAG=e27s1n bash eval/run.sh --notes slack` -- expected: exit 0 on the CI mock (no key), `notes-slack.json` in the report folder lists exactly the four R7 A/B cases, and no eval session, Turn row or watch is left (about 4 to 6 min, inference)
- (once) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-eval-set.sh` and `bash ci/checks.sh`, one per call -- expected: pass
- (once) `grep -c "AMENDED 2026-11-16, Story 27.1, Contest Planner ruling" _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- expected: 4 or more; and `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`
- CI: no workflow and no `ci/compose.ci.yml` change. `live:slack-hook` (group `shards-3`) is the only unit whose throwaway has `SLACK_*` set, through its own `$tmp/slack.yml` layered by `live_add_file`; its phase 1 asserts that a default throwaway answers 404 on POST `/ocutalon/hook/slack/events` (R9). The new `Test.Channel.*` classes run in `shard:lane-a@Channel` (group `production`), `Test.Data.SlackLink` in `shard:lane-b@Contract,Core,Data,Live` (group `image`), `Test.Eval.NotesKnob` in `shard:lane-a@Install,Digest,Eval` (group `shards`). new_units: `live:slack-hook` → `shards-3` (about 25.2 + 3.5 = 28.7 min planned, inference; R11).

**Implement-stage results (2026-11-16, lane-B throwaways and the lane-B warm stack tagged `e27s1iw`, brought down at the end):**
- Classes, each `CLASS ... passed` on the warm stack, run singly and, after the last edit, again: `Test.Channel.SlackSignature`, `Test.Channel.SlackHook` (5 runs in a row), `Test.Channel.SlackIn`, `Test.Data.SlackLink`, `Test.Data.DailyNote`, `Test.Web.Hook`, `Test.Core.Intake`, `Test.Core.CommandsRouting`, `Test.Eval.NotesKnob`, `Test.Eval.In` (the existing class that the `Eval.In` edit could break), `Test.Install.Production`, `Test.Data.Tables`, `Test.Msg.Contracts` and `Test.Bridge.CodeRules`. `OcuTalon.Test.Core.ProductionItems` in the Commands above is the oracle of lane B's rows, not a test class (`ci/iris.sh class` refuses it): `Test.Install.Production` reads it and passes with the SlackIn row.
- `live:slack-hook` (`ci/iris.sh live slack-hook`): 44 PASS lines and `test-slack-hook: all checks passed`, in about 4 minutes 15 seconds on a developer machine (first start 108 s, the recreate 6 s of waiting). The linked direct message was answered in 0.03 s.
- `bash eval/run.sh --notes slack` on the CI mock (tag `e27s1n`): exit 0, six PASS lines, `notes-slack.json` lists exactly the four R7 A/B cases (each a miss on the mock, whose default chat script scores no turn case right, as for the main set), and no eval session, Turn row or watch was left. About 2 minutes 20 seconds with the stack's start.
- `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-eval-set.sh` (with the new notes lint and its variants) and `bash ci/checks.sh` (33 scripts) pass, after the two one-line repairs recorded under Design Notes 25; `bash docker/tests/test-boundaries.sh` passes.
- Spine: `grep -c "AMENDED 2026-11-16, Story 27.1, Contest Planner ruling"` is 7 (AD-1, AD-13 twice, AD-24, AD-26, AD-29 and Deferred). `lint_spine.py` reports `"ok": false` with 13 low `placeholder` findings (the `{time}`-style tokens of existing catalog text, lines 457 to 1391), and reports exactly the same 13 on the spine as it was at HEAD before this change: the change adds none. The memlog entry was appended (`.memlog.md` is gitignored and was created for it).

**live:slack-hook phases** (`docker/tests/test-slack-hook.sh`; dummy values in shell variables, never echoed; fixture ids `T0FIXTURE1`/`U0FIXTURE1`, other team `T0FIXTURE2`, unlinked `U0FIXTURE9`):
1. Default stack, no override: a signed POST `/ocutalon/hook/slack/events` → 404, nothing counted (R9).
2. Layer `$tmp/slack.yml`, recreate on the same volume, wait ready; seed through `iris_script` a session, a link (`Data.SlackLink.Link`) and an open approval request (`Test.Data.Fixture.Approval`).
3. Signed requests: `url_verification` → 200 `text/plain` challenge; the same unsigned → 401 (R3); a linked DM → 200 with `time_total` < 3.0 s and, after the wait, exactly one Turn with Channel `slack` (R4, Integration AC 4); the same `event_id` with `X-Slack-Retry-Num: 1` → 200, still one Turn (R4); a linked "approve" DM → the request is still `pending` (R6); unlinked member, other team, `bot_id`, `message_changed`, channel message → 200 each, no new Turn, one `Ignored` header each (R1, R2).
4. Rejections with a marker in each body: unsigned, wrong signature, timestamp 301 s old → 401; over 65,536 bytes → 413; a form body → 400. Slot `slack` counted; at most one `webhook_rejected` audit entry; no `^OcuTalonP.SlackE` node for their event ids (R5).
5. Leak scan (`dc logs`, `messages.log`, `Ens_Util.Log`, `%SYS.Audit`, the Interoperability message bodies): no dummy value, no `T0FIXTURE*`/`U0FIXTURE*`, no phase-4 marker, and no text of a phase-3 ignored event (R5, R8, NFR-11).

**Shared surfaces:**
- the production item list (`Test/Core/ProductionItems` oracle, the `Test/Install/Production` count);
- the table registry (`src/short-names.tsv`, `Test/Data/Tables`, `test-storage.sh`);
- the hook's path set (`Test/Web/Hook` `TestOtherPaths`);
- `Intake`'s refusal set (`Test/Core/Intake`);
- the command verb lists (`CommandsIn` `TOOLVERBS`, `Test/Bridge/CodeRules`, `Test/Msg/Contracts`);
- `ci/units.sh` groups (`test-ci-config.sh`, `test-ci-changes.sh`);
- the eval folder layout and its lint (`test-eval-set.sh`; the main set, held-out set and `rules-only.json` are unchanged);
- `Eval.In.Start`'s signature (a new optional last argument; every existing caller unchanged).

Every test added or changed passes on a fresh environment, in either order. The lead's fresh check (Rule 19) runs the new and changed classes forward and reversed on fresh throwaways, one per call.

**Mutations (one per AC; the implement stage applies each, observes red, reverts, confirms `git status --short`/`git diff --stat` unchanged, and records `mutation: ... → ...` here):**
- AC 1 (spine): delete one `[AMENDED 2026-11-16, Story 27.1, Contest Planner ruling]` tag → the spine grep count drops below 4.
- AC 2 (no secret or id): `SlackIn` logs the event's MemberId in its console line → live phase 5 and `SlackIn.TestRecordsHoldNoIds` red.
- AC 3 (route matrix): `Signature.Check` always returns "" → `SlackHook.TestUnsigned` and `TestUnsignedChallenge401` red.
- AC 4 (linked DM): Item Provenance `untrusted` → `SlackIn.TestLinkedDm` red.
- AC 5 (other events): drop the `bot_id` check → `SlackIn.TestBotIdIgnored` red.
- AC 6 (R8): remove the `ForeignKey` → `SlackLink.TestLinkGoesWithSession` red.
- AC 7 (DraftTransform): remove `DraftTransform` from the own-incident check → `CommandsRouting.TestDraftTransformToolOnly` red.
- AC 8 (off): `On()` ignores the online-demo flag → `SlackHook.TestOnlineDemo` red.
- AC 9 (R7 knob): `TurnRequest` writes the notes with Channel `telegram` whatever the knob → `NotesKnob.TestChannelLabel` red.
- Also recorded: `ClaimEvent` always returns 1 → `SlackIn.TestRetryOnce` red (R4); `Hang 4` before the hand-over → live phase 3 red (R4).

**Mutation record (implement stage, 2026-11-16; each applied to the file named, run on the lane-B warm stack, observed red, reverted byte-identical (`cmp` against the saved copy), and the class run green again):**
- mutation: AC 1 (spine): the `[AMENDED 2026-11-16, Story 27.1, Contest Planner ruling]` tags of AD-1, AD-13 (both lines), AD-24 and AD-26 deleted → the grep count 7 drops to 2 (below 4); restored to 7.
- mutation: AC 2 (no secret or id): `SlackIn.OnProcessInput` logs `event.MemberId` in an Ens log line → `SlackIn.TestRecordsHoldNoIds` red ("no event-log row after the events holds the text, a member id or a team id"). The live phase 5 scan reads the same rows.
- mutation: AC 3 (route matrix): `Signature.Check` ends `Quit ""` → `SlackHook.TestUnsigned` (wrong signature, counts, nothing handed over), `TestRawBytesAreSigned` and `TestRejectedStoresNothing` red.
- mutation: AC 4 (linked DM): Item Provenance `untrusted` → `SlackIn.TestLinkedDm` and `TestTypedApproveApprovesNothing` red.
- mutation: AC 5 (other events): the `bot_id` check dropped from `Classify` → `SlackIn.TestBotIdIgnored` red (reason, kind and the Item).
- mutation: AC 6 (R8): the `ForeignKey SessionFK` removed from `Data.SlackLink` → `SlackLink.TestLinkGoesWithSession` red (`%DeleteId` and `DropEval` leave the link row).
- mutation: AC 7 (DraftTransform): `DraftTransform` removed from the own-incident check of `CommandsIn` → `CommandsRouting.TestDraftTransformToolOnly` red (not_found cases and the context cases).
- mutation: AC 8 (off): `SlackIn.On()` ends `Quit 1` (ignores the demo flag) → `SlackHook.TestOnlineDemo` red (and `TestRejectedStoresNothing`, which counts on the demo flag being read).
- mutation: AC 9 (R7 knob): `Eval.In.NotesUp` writes the notes with Channel `"telegram"` whatever the knob → `NotesKnob.TestChannelLabel` and `TestNotesShape` red.
- mutation: `Eval.In` reads the `notes` member whatever the notes channel (the inert guard dropped) → `NotesKnob.TestInertWhenUnset` red.
- mutation: `ClaimEvent` always returns 1 (`Do $Increment(...)` then `Quit 1`) → `SlackIn.TestRetryOnce` red (R4).
- mutation: `Hang 4` at the start of `SlackIn.OnProcessInput` → `live:slack-hook` phase 3 red: "FAIL phase 3 (R4): status '200', 4.026283s" (run `e27s1l`, the other checks of that run passed but for a quoting bug of the unit's own marker check, fixed after); the file was restored and the unit run clean afterwards (44 PASS lines, `test-slack-hook: all checks passed`).
- mutation: review patch (RawBody, VG): `Web.Hook.RawBody` ends `Quit $ZConvert(raw, "I", "UTF8")` instead of `Quit raw` (decoding the bytes before the signature) -> `live:slack-hook` phase 3c red: "FAIL phase 3 (R3): a signed event whose text is UTF-8 ...: wanted 200, got '401'" and "1 new Ignored header(s) ... wanted 2" (run `e27s1l`); the file was restored byte-identical (`cmp` against the saved copy) and the unit run clean (all checks passed, 47 PASS lines).
- mutation: review patch (notes plumbing, VG): `Eval.In.Start` loses `Set service.NotesChannel = notesChannel` -> `bash eval/run.sh --notes slack` exit 1: "FAIL notes-slack: Turn rows in the channel slack while the run was up 0, notes declared by the cases 12"; restored byte-identical and the run clean (exit 0, 9 PASS lines, the 12 notes counted).
- mutation: review patch (forms, VG): six sample trees of `eval/run.sh` with one edit each (a bogus channel accepted, a bogus channel accepted after `--release-candidate`, the key kept for `--notes`, the key not needed for `--release-candidate --notes`, the notes report printed unchecked, and the persona sweep printed unchecked) are each flagged by `docker/tests/test-eval-personas.sh`; the real tree passes.

**R7 A/B cases (PINNED; the four notes-bearing session-start cases; no existing case carries notes):**
- `eval/notes-cases/notes-allclear-all-passing/case.json` -- mirrors `eval/allclear-all-passing/case.json`
- `eval/notes-cases/notes-allclear-orders-failing/case.json` -- mirrors `eval/allclear-orders-failing/case.json`
- `eval/notes-cases/notes-allclear-nothing-watched/case.json` -- mirrors `eval/allclear-nothing-watched/case.json`
- `eval/notes-cases/notes-command-run-shell/case.json` -- mirrors `eval/command-run-shell/case.json`
- Each: the source's kind, turn, checks and expectation unchanged, the fixed notes set of Design Notes item 16.

**R7 A/B side A** (planner) -- from the pushed `OCT-epic27` sha the lead sends, with `ANTHROPIC_API_KEY` in the Planner's own environment only, run k = 1..5:
`OCUTALON_RUN_TAG=e27r7a<k> OCUTALON_EVAL_REPORT_DIR=<planner evidence folder>/27.1-r7/A-<k> bash eval/run.sh --release-candidate --notes telegram`

**R7 A/B side B** (planner) -- same sha and key, k = 1..5:
`OCUTALON_RUN_TAG=e27r7b<k> OCUTALON_EVAL_REPORT_DIR=<planner evidence folder>/27.1-r7/B-<k> bash eval/run.sh --release-candidate --notes slack`

- Order A-1, B-1, A-2, B-2, ..., A-5, B-5, one stack at a time (each run removes its own stack on exit). Model: Haiku 5.5, fixed by `run.sh` (no override). `--notes` runs attempt 1 only. N = 5 per side.
- Verdict (rule (i)), per case hits with fallbacks counted as misses: `for s in A B; do jq -s '[.[].cases[]] | group_by(.name) | map({name: .[0].name, hits: (map(select(.hit and (.fallback | not))) | length)})' "<planner evidence folder>/27.1-r7/$s"-*/notes-*.json; done`. PASS only if every case's B hits ≥ its A hits.
- The pipeline never runs these (they need a real model key, which no stage has).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 27.1 adds the Slack Events API route and its adapterless service. `POST /ocutalon/hook/slack/events` is on only when both `SLACK_*` variables are set and the install is not the online demo (404 otherwise). It checks size, Slack's v0 signature over the raw bytes in constant time (401 for a missing, wrong or stale one, before any challenge), answers URL verification, and hands every other event to `SlackIn` before answering 200. `SlackIn` claims the event id (a retry does nothing), turns a linked member's plain direct message into one `user` Item on channel `slack` in the member's session, and leaves one content-free `Ignored` record for every other event. The story also creates the `DraftTransform` verb and its `CommandsIn` route (origin tool, own incidents), the R7 eval knob with its four pinned notes cases, and the spine amendments of gate item f.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Web/Hook.cls`: the `/slack/events` route and its helpers.
- `src/ocutalon/cls/OcuTalon/Channel/Slack/{Signature,Event,Ignored,In}.cls`: the signature check, the parsed event, the trace record and SlackIn.
- `src/ocutalon/cls/OcuTalon/Data/SlackLink.cls`, `src/short-names.tsv`, `Test/Data/Tables.cls`: the link table (cascading foreign key to the session) and the event-id claims.
- `src/ocutalon/cls/OcuTalon/Core/{Intake,CommandsIn}.cls`, `Msg/Command/DraftTransform.cls`, `Production.cls`: the silent drop of `Ignored`, the new verb and route, the SlackIn item.
- `src/ocutalon/cls/OcuTalon/{Data/Turn,Data/Session,Eval/In}.cls`, `eval/run.sh`, `eval/notes-cases/*`: the eval-only notes knob (inert when unset).
- `docker/tests/{test-slack-hook,test-eval-set,test-eval-personas,test-boundaries,test-compose-file}.sh`, `ci/units.sh`, `.env.example`: the live unit (`shards-3`), lints and the two `.env.example` lines.
- `src/ocutalon/cls/OcuTalon/Test/**`: the new and extended unit classes.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the AD-1, AD-13, AD-24, AD-26 amendments and their tags.

**Review (pass 1).** 40 findings from four layers: high 0, medium 3, low 28, false 9. Patched: 3 medium (the `--notes` forms of `eval/run.sh` pinned in `test-eval-personas.sh`; the Start notes plumbing observed by a Turn-row count in `notes_run`; non-ASCII and multi-chunk signed bodies in live phase 3c) and 6 low (the doubled timestamp read in the live unit, three comment corrections, the claim-retention wording, one typo). Deferred: none. Rejected, each with its reason in the Review Triage Log: 22 low findings (unlikely or cosmetic, or a fix larger than the defect) and 9 false findings.

**Verification performed.** On the lane-B warm stack (tag `e27s1iw`, down at the end), after the last patch: `Test.Channel.SlackSignature`, `SlackHook`, `SlackIn`, `Test.Data.SlackLink`, `Test.Data.DailyNote`, `Test.Web.Hook`, `Test.Core.Intake`, `Test.Core.CommandsRouting`, `Test.Eval.NotesKnob`, `Test.Install.Production`, `Test.Data.Tables`, `Test.Msg.Contracts`, `Test.Bridge.CodeRules` and `Test.Eval.In` all passed. `ci/iris.sh live slack-hook` passed (47 PASS lines, about 4 min). `bash eval/run.sh --notes slack` exited 0 (the 12 notes counted as Turn rows, nothing left). `test-ci-config.sh`, `test-eval-set.sh`, `test-eval-personas.sh`, `test-boundaries.sh` and `ci/checks.sh` (33 scripts) passed. The spine grep count is 7. `lint_spine.py` still reports the same 13 low `placeholder` findings of existing catalog text that HEAD had (the change adds none), so the spec's `"ok": true` is not reachable; this is not caused by this story. The `OcuTalon.Test.Core.ProductionItems` command is an oracle read by `Test.Install.Production`, which passed. The once-lines ran on the warm stack instead of fresh `e27s1o` throwaways (same code, no `teardown` needed).

**Residual risks.**
- Slack's text escaping (`&amp;`, `&lt;`, `&gt;`) and `<@U...>` mention markup reach the Item text unchanged; Story 27.2 or 27.3 can decide whether to decode them.
- `Data.SlackLink.LinkedInAnotherTeam` walks every link row for each direct message from an unlinked member; fine for a handful of links, to be indexed if the link table grows.
- The R7 merge is gated on the Planner's separate key-holder A/B; the pipeline did not run it and no key was used.
- `followup_review_recommended` is true: three medium patches (the live phase 3c cases, the `notes_run` Turn-row check, the `--notes` forms in `test-eval-personas.sh`) were added after the review layers read the diff and were not themselves reviewed; the unverified risk is a flake or false red in those three checks on another machine.
