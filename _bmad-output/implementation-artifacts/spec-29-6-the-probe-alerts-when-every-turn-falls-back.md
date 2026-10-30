---
title: 'Story 29.6: The probe alerts when every turn falls back'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: 'f2eec5c36636c4f6788224c98b34df9eb6ac71de'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized, multiple-goals]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The online demo's probe (Story 16.6) counts every decision except a `daily_cap` fallback as healthy. So a demo whose every turn is a `no_key`, `timeout` or `rate_limited` fallback reports healthy and never alerts the author; only the log line names the reason (DW-260). The gateway's HTTP 403 "daily cost cap reached" was also measured only in Anthropic's error-JSON shape. A plain-text body could therefore turn a reached cap into an `error` fallback (DW-94).

**Approach:** Give the probe one new alert-only outcome, `degraded`, for those three fallback reasons. It alerts, exits 1 and leaves the count of counted failures unchanged, like `busy` and `no_splash`, and every other outcome stays as it is. For DW-94, this plan measured AI Hub on a throwaway (Design Notes): a plain-text 403 that holds the text gives `daily_cap`, so the bridge needs no change. The repository pins that measurement with a plain-text mock scenario (a mock reply's `body` may now be a string) and a `Test.Agent.Decide` case. The release check list names the body the gateway must send and the new outcome.

## Boundaries & Constraints

**Always:**
- Owner decision `epic29_brief` binds. It is quoted under Design Notes.
- `degraded` covers exactly three fallback reasons, in the enum's spelling (`Msg.Enum` FALLBACKREASON): `no_key`, `timeout` and `rate_limited` (the owner's `rate_limit`). `daily_cap` stays `capped`: healthy, and it clears the count. Every other fallback reason stays `healthy`.
- `degraded` does three things: it calls the alert command with the outcome and the run's log line, exits 1, and changes neither the count of counted failures nor the busy count. Its log line is `<UTC time> degraded count=<n> fallback=<reason>`.
- Every other outcome keeps its effects and exit code. Only `auth_failed` and `no_decision` count. The probe's own decision wait (120 s) still ends as `no_decision`, which counts.
- Files under `docker/` stay ASCII. No tracked file holds a local path, host, address, image name or key.
- Each added test case creates and removes its own state. Changed test cases keep doing so.

**Never:**
- Connect to, configure or probe the demo host, or run `ocutalon-demo`, SSH or DNS commands.
- Change `src/bridge/**` (`Decide.Classify`, `DAILYCAPTEXT`). The measurement shows no change is needed.
- Make `degraded` count toward a reset or clear the count, or give it any reason but the three.
- Change `ci/mock/mock.mjs` (`send` already writes a string payload as is), any existing scenario file, or any contended path.
- Mark a release-check row as passing.

## I/O & Edge-Case Matrix

Rows 1 to 5 run in the hermetic `docker/tests/test-probe.sh` (a Node stub stands in for IRIS). Row 6 runs in the live probe phase of `docker/tests/test-online-demo.sh`, row 7 in `Test.Agent.Decide` and row 8 in the mock's node tests.

| # | Scenario | Input / State | Expected | Error handling |
|---|---|---|---|---|
| 1 | `no_key` (AC1) | Stored count 1. The turn's done decision carries `"fallbackReason":"no_key"` | `degraded count=1 fallback=no_key`, exit 1. One `alert degraded <the line>`, no reset. `counted-failures` still reads 1, and there is no `busy-per-day` | none |
| 2 | `timeout` (AC1) | Same as row 1, with `timeout` | `degraded count=1 fallback=timeout`, the same effects | none |
| 3 | `rate_limited` (AC1) | Same as row 1, with `rate_limited` | `degraded count=1 fallback=rate_limited`, the same effects | none |
| 4 | Never counted (AC1) | A fresh state runs `auth_failed`, then rows 1 to 3, then a run with no decision in the wait | `auth_failed count=1`; three `degraded count=1 ...` lines; `no_decision count=2 reset=0`. The reset runs once, at the last run: 5 alerts, 1 reset | none |
| 5 | Unchanged outcomes (AC1) | Every existing row, the QA paths and the QA sequence | All pass unchanged. This includes `healthy count=0 fallback=error` and `capped count=0 fallback=daily_cap` | none |
| 6 | Live `no_key` (AC2) | The live phase after P8 (stored count 1). The runners' keys are put back to the Provider step's placeholder (`keys_restore`), then P9 runs | `degraded count=1 fallback=no_key`, exit 1. The record gains one `alert degraded` line and no reset. Row 9 sees 9 log lines ending in `degraded`, plus 7 alert lines and 1 reset line | none |
| 7 | DW-94: a plain-text 403 (AC3) | Cap off, day unmarked, the sink swapped. A decide with `[[mock:daily-cap-text]]`, which answers 403 `Content-Type: text/plain` "daily cost cap reached" | A tellnow `daily_cap` fallback with every guarantee (`FallbackProblems` ""). One request reached the mock. The day is marked. The sink got `decision.recorded,budget.capped` | none |
| 8 | A string body in the mock (AC4) | A reply with `"body": "<text>"` and a `Content-Type` header | The reply loads and is served byte for byte, with that content type. A body that is a number is still refused, naming the file and the rule | none |

</intent-contract>

## Code Map

**The probe** (`docker/probe.sh`, 325 lines, bash 3.2)
- Header: :16-18 describe step 5 ("A fallback reason of daily_cap is capped, any other decision is healthy"); :37-41 give the outcomes table; :47-49 describe the log line.
- `run_checks` step 5, :240-247: `fallback` is the first non-empty `fallbackReason` token in the decision's event line (sed). The `case` matches `*'"fallbackReason":"daily_cap"'*` (capped), and anything else is healthy. The new branch goes after `daily_cap` and matches the same way.
- The state `case`, :297-313: `healthy | capped` clears the count, `busy` calls `add_busy`, `no_splash) ;;` does nothing, and `auth_failed | no_decision` counts and resets at 2. `degraded` joins `no_splash`'s branch.
- The exit, :319-325: `healthy | capped` exit 0; every other outcome alerts and exits 1, so `degraded` needs no change here.

**The probe's tests**
- `docker/tests/test-probe.sh`:
  - The header rows are at :8-13.
  - The stub's reason line, :154: `decision_daily_cap` gives daily_cap and `decision_error` gives error. The decision event at :156 carries the reason in the payload and in `decision`.
  - The helpers: `probe_run` :193, `expect_run` :236, `n_calls` :247, `stored_count` :249.
  - Row 13's fallback cases are at :422-435, the QA paths at :635-647 and the QA sequence (`seq_step`) at :709-743.
  - Row 15, :793, pins `docker/probe.sh` as ASCII.
- `docker/tests/test-online-demo.sh` (Story 16.6's live rows 1-9):
  - The header text is at :52-64 ("eight runs ... row 9: the eight log lines ..."), and the phase comment at :1190-1195.
  - The helpers: `probe_run` :1215, `probe_expect` :1229 (its pass text starts "Story 16.6,"), `probe_calls_ok` :1243, `keys_point`/`keys_restore` (`docker/tests/lib-online.sh:110-118`).
  - P8 is at :1498-1501. Row 9's outcome list is at :1504, its alert loop `for label in p2 p3 p4 p5 p6 p8` at :1510, and the final `keys_restore` at :1554-1560.
  - Story 29.5 (ready-for-dev) also edits this file (the counter helpers) and may land first. Anchor on these names, not on line numbers.
- Real events: Story 16.6 measured `healthy ... fallback=no_key` on a stack with no key (DW-260's evidence), and P7 gives `fallback=daily_cap`. So the real event carries the enum spellings that the token match reads. `Bridge.Keys`' `Absent` is Decide's live read, so after `keys_restore` the next turn is `no_key`.

**DW-94: the mock and the Decide pin**
- `ci/mock/scenarios.mjs`: the format header is at :11-15 (`"body": {...}`). `checkReply` at :125-131 refuses a body that is not an object or a list (:129-131).
- `ci/mock/mock.mjs` is read-only. `build` (:466-472) returns `reply.body` as the payload and keeps the reply's headers over the default `content-type: application/json` (case-insensitive). `send` (:244-249) writes a string payload as is.
- `ci/mock/scenarios/A/daily-cap.json` is Anthropic's error JSON. The new file is Lane B's, under `B/`.
- `ci/mock/test/scenarios.test.mjs`:
  - DEFECTS row :92 (`body: 'x'` gives "body is not a JSON object or list") must change;
  - the committed-tree test, :125-131;
  - the limits test, :162-181.
- `ci/mock/test/server.test.mjs`: `SHAPES` :48-56 and row 9 :352-373 ("a body reply is sent as written, and a reply header replaces a default one"); row 13 :524-545 (the committed error scenarios); `post` :67 returns `text` and `headers`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:
  - Header: :61-62 and :69-74.
  - `TestDailyCapBothPaths` is at :1369-1431, and its gateway block at :1379-1400 (`Prepare`; `Put("Decide","DailyCostCapUSD",0)`; `SwapSink`; the day unmarked and no sink call; the decide with the marker; `FallbackProblems`; `FindRequests(...).%Size()` = 1; the day marked; `Targets` = `ApprovalStartIn,Ens.Alarm,TriageAgent`; `EventTypes` = `decision.recorded,budget.capped`).
  - `OnAfterOneTest` kills today's mark (:200), so each test starts unmarked.
- Read-only: `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:124-126` (`DAILYCAPTEXT`) and `:666-694` (`Classify`: a failure text holding the phrase, in any case, gives daily_cap).

**The release check list** (`release/demo-host-checks.md`)
- H13 is at :52 and H20 at :59. The probe's host interface is at :65-74, with the outcomes at :72.
- `docker/tests/test-online-host.sh` pins the file: ASCII, no host detail, and H1-H24 each once with one of the three exact statuses (:870-910).

## Tasks & Acceptance

**Execution:**

**The mock and DW-94's pin**
- `ci/mock/scenarios.mjs`: a model reply's `body` may also be a string. The mock serves it as is, with the reply's headers (`Content-Type` included). A body that is not a string, an object or a list is refused with "body is not a string, a JSON object or a list". The format header says so. Telegram replies keep their JSON-object rule.
- `ci/mock/scenarios/B/daily-cap-text.json` (new): `{"name": "daily-cap-text", "match": {"marker": "daily-cap-text"}, "replies": [{"status": 403, "headers": {"Content-Type": "text/plain"}, "body": "daily cost cap reached"}]}`.
- `ci/mock/test/scenarios.test.mjs`:
  - the DEFECTS body row becomes `body: 5`, expecting the new rule text;
  - the limits test adds a `body-string` reply that loads.
- `ci/mock/test/server.test.mjs`:
  - row 9's `SHAPES` gains a fourth reply (403, `Content-Type: text/plain`, a string body). The case asserts the status, the exact text and `text/plain`;
  - row 13 also posts `[[mock:daily-cap-text]]` to the committed tree: 403, `text/plain`, exactly "daily cost cap reached".
- `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:
  - move the gateway block of `TestDailyCapBothPaths` into one private helper that takes the marker. `TestDailyCapBothPaths` calls it with `daily-cap` and keeps every assertion;
  - add `TestDailyCapPlainText`, which calls the helper with `daily-cap-text` (matrix row 7);
  - the class header names the new test.

**The probe (DW-260)**
- `docker/probe.sh`:
  - after the `daily_cap` branch, a decision whose event carries `"fallbackReason":"no_key"`, `"timeout"` or `"rate_limited"` sets `outcome=degraded`;
  - the state `case` puts `degraded` with `no_splash` (no count change);
  - the header's step 5, the outcomes table and the log-line text name `degraded` and its three reasons.
- `docker/tests/test-probe.sh`:
  - the stub takes the flags `decision_no_key`, `decision_timeout` and `decision_rate_limited`;
  - row 13 gets one case per flag over a stored count of 1 (rows 1-3: the line, the exit, one `alert degraded` with the run's line as its argument, no reset, the stored count, no busy-per-day);
  - a QA path per reason (one sign-out, no password anywhere);
  - a new QA sequence on a fresh state (row 4);
  - the header's row list says so.
- `docker/tests/test-online-demo.sh`:
  - after P8, `keys_restore` must print 1, then P9 runs `probe_run p9` (matrix row 6). Its pass and fail lines name Story 29.6;
  - row 9 expects nine log lines ending `degraded` and seven alert lines (p9 joins the loop);
  - the header and the phase comment describe P9;
  - the final `keys_restore` stays as it is.

**The release check list**
- `release/demo-host-checks.md`, H13: in "Script / repository", put "Story 29.6 (DW-94): `Test.Agent.Decide`". In "The Planner's check", replace "and the 403 body (Story 29.6)" with the measured rule. The body of the 403 must hold "daily cost cap reached": either as plain text or as Anthropic's error JSON (`{"type":"error","error":{"type":"permission_error","message":"daily cost cap reached"}}`), and both give `daily_cap`. An empty body gives `error`, so the day is not marked and no daily-cap notice shows. The Planner checks the body at the deploy. The status stays as it is.
- H20's check and the probe's host interface: list `degraded` (a `no_key`, `timeout` or `rate_limited` fallback). It alerts, exits 1 and changes no count. The host's alert command must deliver every outcome it is given, `degraded` included. ASCII only. H20's status stays as it is.

**Acceptance Criteria:**
- AC1: given `docker/tests/test-probe.sh`, when it runs, then matrix rows 1 to 5 hold and the test prints "all checks passed".
- AC2 (integration, a real IRIS stack): given `live:online-demo` on a fresh lane-C throwaway, when its probe phase runs P9 with the runners' keys at the placeholder, then matrix row 6 holds, and every Story 16.6 row passes as before.
- AC3: given `Test.Agent.Decide` on a fresh throwaway with the CI mock, when the class runs, then `TestDailyCapPlainText` holds matrix row 7 and `TestDailyCapBothPaths` passes unchanged.
- AC4: given `docker/tests/test-mock.sh`, when it runs, then matrix row 8 holds, and the committed tree, with `B/daily-cap-text.json`, loads with no problem.

## Spec Change Log

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 19 findings - high 0, medium 0, low 11, false 8, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: a string body with no Content-Type is served as application/json, which the format header hid - the header now says "application/json when the reply names none" (`ci/mock/scenarios.mjs`); Edge repeats it as a guard suggestion, rejected as a guard (the spec forbids touching `mock.mjs`).
  - `[low]` `[reject]` Blind: `degraded` alerts every 15 min while the cause lasts - spec-bound: the owner's ruling is an alert-only outcome like `busy`, which also repeats.
  - `[low]` `[reject]` Blind: the three reasons are an allow-list not tied to the enum - Decided in-stage 3 and 7 name the three; `Test.Msg.Contracts` pins the spellings; a new reason is a future story.
  - `[low]` `[reject]` Blind: no tests for `body: ""` or `null` - `null` is refused by the same branch as `5`, and the empty string is a string; the extra rows add nothing a user meets.
  - `[low]` `[reject]` Blind and Edge: "Story 29.6, row 6" labels beside Story 16.6's row 6, and row 9's text stays 16.6 - the spec says P9's lines name Story 29.6 and row 9 stays Story 16.6's.
  - `[false]` `[reject]` Blind and Edge: P9 runs before the runners record the restore - `Keys.Absent` is Decide's live read (Design Notes); `keys_restore` prints 1 only after `KeysAre` read the placeholder; the live unit passed, and with the match mutated P9 read `healthy ... fallback=no_key`, so the turn is a no_key fallback.
  - `[false]` `[reject]` Edge: the day's cap mark could survive P7 and make P9 `capped` - P7 removes the mark and row 9 reads it back as 0; the live unit passed with P9 `degraded`.
  - `[low]` `[reject]` Blind: the 150 s deadline guard and the phase time were not revisited - the phase starts under the same guard and the live unit passed inside the deadline; P9 adds one probe run.
  - `[low]` `[reject]` Blind: the probe header's table alignment and one long line - cosmetic.
  - `[low]` `[reject]` Blind: the spec's mutation lines mix expectation and result - Rule 19 asks for the mutation and the red observed on one line.
  - `[false]` `[reject]` Edge: the outcome follows a substring match while `fallback=` is the first token - the event line carries one reason, in the payload and in `decision`, and both are the same value.
  - `[low]` `[reject]` Edge: a future enum member reports healthy - the DW-260 ruling names three reasons; Decided in-stage 3.
  - `[low]` `[reject]` Edge: the stub takes the first of several `decision_*` flags - no test sets two.
  - `[false]` `[reject]` Edge (claim): "after keys_restore the next turn is no_key" is unverified - the live run measured exactly that (P9 `degraded count=1 fallback=no_key`).
  - `[false]` `[reject]` Verification-gap: no findings (all four ACs have `mutation:` lines; the hermetic suites passed when it ran them).
  - `[false]` `[reject]` Intent-alignment: it describes the diff as implementing reading A with live coverage for C; the divergences it lists (stub-level `timeout` and `rate_limited`, P9 results outside the diff) are Decided in-stage 7 and are covered by the live run.
  - `[false]` `[reject]` Intent-alignment: the `ci/mock/scenarios.mjs` change is not named in the Never list - it is in the spec's footprint_extensions and its Tasks.
  - `[false]` `[reject]` Intent-alignment: the spec file's own edits sit outside the listed surfaces - the mutation lines are the Rule 19 tracking section.
  - `[low]` `[reject]` Intent-alignment: DW-94 classification is shown only by `TestDailyCapPlainText` - that is the only test through the real AI Hub, and it passed on a fresh throwaway.

## Design Notes

**Owner decision for Epic 29** (`owner_decision id=epic29_brief`, 2026-10-30, decided by the Contest Planner under the owner's delegation; DW-260 is kept by veto ruling U-157). It binds, quoted:
> **DW-260 (veto U-157, kept):** the probe gets an alert-only outcome for `no_key`, timeout and `rate_limit` fallbacks. It alerts the author and never counts toward a reset, like busy.
> **DW-94:** fix it in the repository if it needs a repository-side change.

The brief's host rules also bind, as Story 29.4 quotes them: the demo host is the owner's, host-only criteria are release checks that are never faked as passing, and anything that needs a host action is an escalation.

**Measured in planning (Task 0, DW-94; 2026-10-30).**
- Setup: a lane-C warm throwaway (tag `e29s6planw`, build 154, the CI override), which this stage started and tore down. A one-off Node stand-in ran inside the stack's mock container on port 8081 and answered every `POST /v1/messages` with HTTP 403 and the variant's body. The shadow runner (`Test.Bridge.Runner.NewRunner("OcuTalon.Agent.Triage", "low", <ProviderConfig with base_url http://mock:8081/v1/>)`) sent one decide per variant. For each one, the record holds the Reply's `FailureText` and `Decide.Classify({"failure": <text>})`.
- Anthropic's error JSON (`permission_error`): `ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: Authentication failed: daily cost cap reached`. It gives `daily_cap`, the same text as Story 1.6's Task 0 (b).
- `text/plain` "daily cost cap reached": `... API error: Authentication failed (HTTP 403): daily cost cap reached`. It gives `daily_cap`.
- Each of these gives `... Authentication failed (HTTP 403): <the body as sent>` and `daily_cap`:
  - plain text with a trailing newline;
  - plain text sent as `application/json`;
  - an HTML page that holds the text;
  - `{"error":"daily cost cap reached"}`;
  - `{"message":"daily cost cap reached"}`.
- An empty body: `... Authentication failed (HTTP 403)`. It gives `error`.
- Each variant reached the stand-in exactly once, so AI Hub does not re-send a 403.
- So: when the body is not Anthropic's error JSON, AI Hub puts the raw body after `(HTTP 403): `, and Classify finds the text in any body that holds it. DW-94 needs no bridge change, and the lead guidance's bridge option does not arise. The one failing body is an empty one, and H13 now names that.

**Architecture decisions (Rule 6):**
- AD-25: the probe's outcomes, and only `auth_failed` and `no_decision` count. `degraded` is alert-only, so it extends the outcome list and contradicts nothing.
- AD-8: Classify and the fixed 403 text. Unchanged.
- AD-20: the day's cap mark and `budget.capped`.
- AD-22: the mock, its scenarios (one test's scenario never breaks another's: the new marker is its own, and the format change is additive), the throwaways and CI.
- AD-29: Epic 29's files and the lanes; `B/` is Lane B's scenario folder.

No AC contradicts an AD's Rule. **For the lead (Rule 20):** AD-25's probe bullet lists `busy`, `capped`, `auth_failed` and `no_decision`, and the code already has `no_splash`. The lead may amend that list on the light path, keeping the id, to add `no_splash` and `degraded` (both alert-only). This stage does not write the spine.

**Integration ACs (Rule 1).** This story introduces no service. The mock's string body is a small extension of a shared test component, and its consumer is in this story: `Test.Agent.Decide.TestDailyCapPlainText` runs through the real mock and AI Hub's provider (AC3). The probe's new outcome has a real-IRIS consumer check in AC2.
- **Consumed-by:**
  - the demo host's scheduler and alert command (the author's, outside the repository; H20 asks the Planner to check that `degraded` is delivered);
  - the Planner's pass on the host (H13, H20).
- **Consumes:**
  - Story 16.6's probe and its live phase;
  - Story 1.6's `Classify` and `daily-cap` scenario;
  - Story 16.9 and AD-20's day mark;
  - Story 0.11's mock;
  - Story 29.3's check list.

**Extend, don't copy (Rule 2):**
- `degraded` reuses `no_splash`'s state branch and the existing exit path. Its match follows the `daily_cap` branch.
- The stub's new flags extend its one reason line.
- `TestDailyCapPlainText` and `TestDailyCapBothPaths` share one helper for the gateway step, so the step is not copied.
- The mock's string body extends `checkReply`; the server's `send` already handles strings.
- The new server assertions extend row 9's `SHAPES` and row 13.

**Ledger inbox (Rule 17):**
- **DW-260:** addressed by matrix rows 1 to 6, AC1, AC2 and their mutations.
- **DW-94:** addressed by the planning measurement above, matrix rows 7 and 8, AC3, AC4 and H13. It settles with no product change; the repository pins the measurement.

**footprint_extensions:** `ci/mock/scenarios.mjs`, `ci/mock/test/scenarios.test.mjs`, `ci/mock/test/server.test.mjs`, `ci/mock/scenarios/B/daily-cap-text.json` (new), `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls` (one test, one helper). None of these is contended, and other epics only add files under `ci/mock/scenarios/A/`. The rest is in the footprint: `docker/probe.sh`, `docker/tests/test-probe.sh`, `docker/tests/test-online-demo.sh` and `release/demo-host-checks.md`. Nothing under `src/bridge/**` changes.

**CI.** The push changes `ci/` and `src/`, so every IRIS group runs, plus the hosted `checks` and `web` jobs. No unit is added and no group changes. `Test.Agent.Decide` (`shard:lane-a@rest`, `shards-2`) gains one decide, about 5 s (inference). `live:online-demo` (`install-upgrade`, 30.9 min) gains one probe run, about 5 to 10 s (inference), which stays inside REL-4's 35 minutes.

**Decided in-stage:**
1. The outcome name is `degraded`, in the probe's snake_case style. Its alert and log line follow the existing ones. It is author-facing (the alert command), not visitor-facing.
2. The owner's `rate_limit` is the enum's `rate_limited`.
3. Only the three named reasons are `degraded`. Every other reason (`error`, `refusal`, `cut_off`, `empty`, `invalid`, `unusable`, `budget`, `too_large`) stays `healthy`, because the ruling names three. Residual, for the lead's information: an `error` fallback stays healthy, and a gateway 403 with an empty body gives `error` (measured), which H13's host check closes.
4. `degraded` changes no busy count. "Like busy" in the ruling means alert-only and never counted. The busy count stays the proxy-side capacity signal of AD-25.
5. DW-94 was measured in this plan (product default 5), so the spec has no conditional bridge branch.
6. The pin is a new plain-text scenario rather than a changed `daily-cap.json`, because Story 16.6's P7 and Story 1.6's tests read the JSON one.
7. AC2's live case is `no_key`, reached by `keys_restore`. `timeout` and `rate_limited` need about 60 s of Decide's timer each, so they are pinned hermetically: the token match is the same for all three, and `Test.Msg.Contracts` pins the enum's spellings.

## Verification

Run every call in the foreground with `timeout: 600000`, one test call per message, against named lane-C targets. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`. A change under `ci/mock/` refuses a warm run (`ci/warm.sh down`, then `up`). Live units refuse warm mode. If a local live run dies of the deadline with no failed test, the deadline is the cause: re-run it once with `OCUTALON_LIVE_DEADLINE=900` on the call.

There is no shard run, for three reasons. The only IRIS class that changes is `Test.Agent.Decide`. The mock change is additive and pinned on the committed tree. `shard lane-a@rest` does not fit in one call locally (its part 3/3 alone took 568 s). The lead's fresh-environment check and CI cover the shards.

**Commands:**
- (loop) `bash -n docker/probe.sh && bash -n docker/tests/test-probe.sh && bash -n docker/tests/test-online-demo.sh`. Expected: no output.
- (loop) `bash docker/tests/test-probe.sh`. Expected: "test-probe: all checks passed" (under 2 min, inference).
- (loop) `bash docker/tests/test-mock.sh`. Expected: node reports no failure (under 15 s).
- (loop, optional) `LANE OCUTALON_RUN_TAG=e29s6iw bash ci/warm.sh up` once the `ci/mock/` files are final, then `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s6iw bash ci/iris.sh class OcuTalon.Test.Agent.Decide`. Expected: `CLASS ... passed`. At the stage's end, also after a failure, run `LANE OCUTALON_RUN_TAG=e29s6iw bash ci/warm.sh down`.
- (once) `LANE OCUTALON_RUN_TAG=e29s6i bash ci/iris.sh class OcuTalon.Test.Agent.Decide`, on a fresh throwaway. Expected: `CLASS OcuTalon.Test.Agent.Decide passed`, with `TestDailyCapPlainText` (about 3.5 min: a start of about 90 s and the class at about 105 s).
- (once, before the live unit) `LANE OCUTALON_RUN_TAG=e29s6i bash ci/iris.sh build`. Expected: the web bundle matches `web/src` (Rule 21).
- (once) `LANE OCUTALON_RUN_TAG=e29s6i bash ci/iris.sh live online-demo`. Expected: PASS, with P9 `degraded count=1 fallback=no_key` and row 9's nine lines (about 310 to 370 s).
- (once) `bash docker/tests/test-online-host.sh`. Expected: it passes, with H1-H24 present and ASCII.
- (once) `bash ci/checks.sh`. Expected: every block passes (about 4 min), `probe`, `online-host` and `boundaries` included.
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s6i bash ci/iris.sh teardown` and `LANE OCUTALON_RUN_TAG=e29s6iw bash ci/iris.sh teardown`. Expected: nothing tagged `e29s6i` or `e29s6iw` is left.

**Shared surfaces:**
- The probe's outcome set and log line:
  - `test-probe.sh`: its rows, QA paths and QA sequence;
  - `test-online-demo.sh`: row 9's outcome list and alert record;
  - `release/demo-host-checks.md`: the probe's host interface.
- The mock's reply `body` rule: `scenarios.test.mjs`'s DEFECTS body row and limits test, and `server.test.mjs`'s row 9 `SHAPES`.
- The committed scenario set, which gains `B/daily-cap-text.json`: the committed-tree load test and row 13.
- `TestDailyCapBothPaths`, refactored onto the shared helper with its assertions unchanged.
- The check list's H13 and H20 rows (`test-online-host.sh`'s format pins).

The implement stage searches `docker/tests`, `ci/mock/test`, `release/` and `src/ocutalon/cls/OcuTalon/Test` for each of these.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. Each probe case uses a fresh state folder. P9 runs inside the live phase's own state folder. `TestDailyCapPlainText` starts from an unmarked day, because `OnAfterOneTest` kills the mark. Each mock case makes its own fixture tree or reads the committed one.

**Mutations (Rule 19), one per AC.** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are byte-identical to before:
- AC1: mutation: drop `no_key` from the `degraded` match in `docker/probe.sh`. Expected red: row 13's `no_key` case (`healthy count=0 fallback=no_key` instead of `degraded count=1 fallback=no_key`). Second mutation: put `degraded` in the `auth_failed | no_decision` branch. Expected red: the new QA sequence (its first `degraded` run reads `count=2 reset=0` and runs the reset) and row 13's three cases (`count=2 reset=0`). Run in the implement stage: the first mutation gave 12 red checks (row 13's `no_key` case reads `healthy count=0 fallback=no_key`, the QA path and the QA sequence follow), the second gave 19 (row 13's three cases read `degraded count=2 ... reset=0`, with a reset and no stored count of 1); each was reverted from a backup and the tree was byte-identical.
- AC2: mutation: the same `no_key` drop. Expected red: `live online-demo`'s P9 (`healthy count=0 fallback=no_key`) and row 9's outcome list. Runs once, about 6 min. Run in the implement stage on a fresh throwaway: P9 read `healthy count=0 fallback=no_key` (exit 0, stored count 0, 6 alert lines) and row 9's outcome list and alert record went red (5 FAIL lines); reverted from a backup, the tree byte-identical, and the unmutated unit passed.
- AC3: mutation: `ci/mock/scenarios/B/daily-cap-text.json`'s body becomes "daily cost cap exceeded". Expected red: `TestDailyCapPlainText` (reason `error`, the day unmarked) on a fresh class run, and `server.test.mjs` row 13's committed check in `test-mock.sh`. Run in the implement stage on a warm throwaway restarted for the mock change: `test-mock.sh` failed only row 13 (1 of 117), and the class failed only `TestDailyCapPlainText` (three asserts: the fallback guarantees, the day marked, the sink events); reverted from a backup, the throwaway torn down and the tree byte-identical.
- AC4: mutation: `checkReply` refuses a string body again. Expected red: `test-mock.sh`'s committed-tree load test (it names `B/daily-cap-text.json` and the body rule) and the limits test. Run in the implement stage: the committed-tree load, the limits test and every server test that loads the committed tree went red (41 of 117); reverted from a backup and the tree was byte-identical.

**Manual checks:**
- H13 and H20 of `release/demo-host-checks.md` and its probe section read as the release-check task says. Both statuses are unchanged, and no row reads as a pass.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The probe has a new alert-only outcome, `degraded`, for `no_key`, `timeout` and `rate_limited` fallbacks (DW-260). It alerts, exits 1 and changes no count. DW-94 needed no bridge change; the repository pins the planning measurement with a plain-text mock scenario (a mock reply's `body` may now be a string) and `TestDailyCapPlainText`. The check list names the 403 body and the new outcome.

**Files changed.**
- `docker/probe.sh`: the `degraded` branch, its state branch beside `no_splash`, and the header text.
- `docker/tests/test-probe.sh`: the stub's three reason flags, row 13's three cases, a QA path per reason, and the degraded QA sequence.
- `docker/tests/test-online-demo.sh`: P9 after `keys_restore`, and row 9 at nine log lines and seven alert lines.
- `ci/mock/scenarios.mjs`: a string reply body is accepted.
- `ci/mock/scenarios/B/daily-cap-text.json`: the plain-text 403 scenario (new).
- `ci/mock/test/scenarios.test.mjs` and `ci/mock/test/server.test.mjs`: the string-body rule, the committed tree and row 13.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`: the `GatewayCap` helper and `TestDailyCapPlainText`.
- `release/demo-host-checks.md`: H13, H20 and the probe section.

**Review.** 19 findings from four layers: 1 patched (low: the mock format header now states the default Content-Type), 0 deferred, 18 rejected with their reasons in the triage log. Patched by verdict: high 0, medium 0, low 1. Follow-up review recommended: false.

**Verification.** `bash -n` of the three scripts clean. `test-probe.sh` all checks passed. `test-mock.sh` 117 of 117 (after the last edit too). `Test.Agent.Decide` on a fresh lane-C throwaway passed (106.7 s). `ci/iris.sh build` matched. `live online-demo` passed, with P9 `degraded count=1 fallback=no_key`, 7 alert lines, 1 reset line, and row 9's nine log lines. `test-online-host.sh` and `ci/checks.sh` passed. The four AC mutations each went red and were reverted byte-identical (AC2 on the live unit). The tags `e29s6i` and `e29s6iw` are torn down.

**Residual risks.** `timeout` and `rate_limited` are pinned only hermetically (Decided in-stage 7). An `error` fallback stays healthy, and H13's host check covers a gateway 403 with an empty body. The lead may amend AD-25's probe bullet to add `no_splash` and `degraded` (Design Notes).
