---
title: 'Story 13.3: The bridge developer guide, proved on a clean instance'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The bridge now works alone (Stories 13.1 and 13.2), but a production developer can only learn how by reading its code and `release/standalone-bridge.sh`. Nothing tells them how to install it, what each setting does, what the messages hold or which rules govern their tools. Nothing proves that written instructions still work after the next change.

**Approach:**
- Write the bridge developer guide as a new public file, `docs/bridge-guide.md`. Story 31.3 links this path.
- The guide's install and run commands are marked ObjectScript blocks. `release/standalone-bridge.sh` reads them from the guide at run time and runs them verbatim, so the lane-a standalone-bridge job follows the guide and cannot drift from it.
- A new static check pins the guide to the code: the commands, every setting, field and enum value, and the public-text rules. The release checklist runs it as a new row.
- The README gains its third use item, which links the guide. The security overview gains the U-229 sentence.

## Boundaries & Constraints

**Always:**
- The guide is plain English and ASCII. It holds no key, local machine path, instance name, IP address, URL or private infrastructure detail. It never says "IRIS Couch", and it never names OpenClaw. It claims only what is merged: the bridge ships inside OcuTalon's one package, and a separate bridge package and listing are a follow-on (AD-2).
- The job runs each guide block's lines exactly as they are written. It runs the install section's blocks in the guide's order. It runs the two governance blocks before `start`, because their rows are read live and the order does not change the result. Between blocks it adds only the CI environment's lines (pointing the provider at the mock) and its own checks. No guide line is copied into the script (AD-2, AD-22, AD-29).
- The model key is only ever `@{env:ANTHROPIC_API_KEY}`. No guide block, row or log holds a key value (AD-19). No request sets `temperature`, `top_p` or `top_k`.
- Every check of Stories 13.1 and 13.2 keeps passing, the timer row included, with the guide's `Timeouts.Derive` `http_config` in place (DW-181, AD-8).
- The U-229 sentence appears word for word in the guide, where it documents `ToolClassification`, and in `docs/security-overview.md`, after the paragraph's first sentence. It makes no promise about a future release.
- Every "this release" statement in `docs/security-overview.md` stays true of 1.0.0 (U-223).

**Never:**
- No change to any ObjectScript class (`src/**`), to the mock, to `ci/compose.ci.yml`, to `docker/tests/lib-live.sh` or to `.github/workflows/ci.yml`. In `lane-a.yml`, change the header comment only. No new CI job and no new iris group.
- In `docs/security-overview.md`, add the one sentence and nothing else. Never hand-edit a generated section, and leave the `overviewdoc` pins unchanged. Never edit `docs/install-ipm.md` or `Msg/Enum.cls` (other epics own them).
- No README change beyond the one appended item. No mock marker, CI variable or test fixture is named in the guide.
- No real key, and no network call from any check.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Guide followed | The clean `OCUBRIDGE` namespace. The job runs the guide blocks `load`, `install`, `provider`, `tool-classification`, `approval-role`, `start` and `send` | Each block's `sc` is OK, and no line of a block raises an error. Within 60 s, the item that `send` sent has one `OcuTalon.Bridge.Msg.DecisionResponse` header and at least one `OcuTalon.Bridge.Msg.AgentStep` header to `AgentSteps` in its session | A failing block prints `FAIL` naming the block, and the script exits 1 |
| Command fails | A guide block with a wrong path or class, e.g. LoadDir of a missing folder | `FAIL the guide's <name> command ...`. The job exits 1 | `die` when later checks cannot run |
| Block missing | A marker is absent, repeated or empty, or its next line is not an `objectscript` fence | The script stops before any IRIS work, naming the block. `test-bridge-guide.sh` `blocks` fails | exit 1 |
| Drift by copy | The script holds a guide command line as its own literal, or extracts a name that the guide lacks | `test-bridge-guide.sh` `blocks` fails, naming the line or the name | exit 1 |
| DW-181 provider | The guide's `provider` block writes the `TriageAgent` `ProviderConfig` row: `model_provider` anthropic, `api_key` `@{env:ANTHROPIC_API_KEY}`, `http_config` = `Timeouts.Derive(60).http_config`. The job then adds the mock's `base_url` and header | The row's `api_key` is the placeholder, and its `http_config` keeps Derive's `request_timeout_secs` and `retry`. The timer row (12 s) still falls back `timeout` in 12-17.999 s, and 5d still passes | FAIL on a missing block or a changed `http_config` |
| Governance rows | The guide blocks `tool-classification` and `approval-role` | Check 4 still reads `ToolClassification` = the script's `tool_json` and `ApprovalRole` = `ExampleApprovers`. Every row of 5e passes | FAIL on any difference |
| Reference drift | A setting in `Decide`/`Adapter.Agent`/`AgentRunner` `SETTINGS`, a `REFUSED` name, a `Result`/`AgentStep` property, an `Enum` value, an `Answer` result or `MAXTIMER` that the guide does not name | `test-bridge-guide.sh` `reference` fails, naming each missing one | exit 1 |
| U-229 sentence | The sentence is missing or changed in the guide or in the overview's Approval and audit section | `test-bridge-guide.sh` `u229` fails, naming the file | exit 1 |
| Public text | The guide has a non-ASCII byte, a local path, a key-like string, a URL or IP, an instance name, "IRIS Couch" or "OpenClaw" | `test-bridge-guide.sh` `public` fails with file:line, never the text | exit 1 |
| Checklist | `docker/tests/test-bridge-guide.sh` fails on the candidate | The checklist row `bridge-guide` is FAIL, and the result is `fail` | exit 1 |
| README | The third item of "What you can use it for" | It is exactly `- **[An AI decision step you can audit, in your own production.](docs/bridge-guide.md)**`, and its link reaches the file | `test-readme.sh` `use-cases`/`readme-links` FAIL |

</intent-contract>

## Code Map

**The guide's sources** (all read-only):
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls:11-23` `Run`. It refuses a namespace that is not Interoperability. It does four things: `RegisterAudit` (the audit events); `SetUpApprovals`, which creates the Workflow role `OcuTalonApprovals` and its login-disabled user `OcuTalonWorkflow` (122); `SeedModelFamilies` (the anthropic, gpt-5 and default rows: cap key and effort key, 28-36); and `SeedPrices` (64). `CheckAudit` is at 102. It writes no System Default Settings row (Design Notes, Decided 8).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `SETTINGS` (108): HostSinkClass, ReplyFilterClass, ClassificationClass, TimerSeconds, DecisionTokenBudget, RequestTokenLimit, DailyCostCapUSD, GatewaySpendUSD, GatewaySpendDate, ServiceUser, ToolClassification and ApprovalRole;
  - `RUNNERS` (111), `MAXTIMER` 110 (114), `MINTIMER` 12 (117);
  - defaults (168-215): TimerSeconds 60, ApprovalRole `OcuTalonUser`, ServiceUser `OcuTalonService`, DecisionTokenBudget 0 (none), RequestTokenLimit 100000, DailyCostCapUSD 0, and the three `OcuTalon.Bridge.Ext.*` classes.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `SETTINGS` (64) Effort and AgentAllowList, and `REFUSED` (67) AuthPolicy, AuditPolicy, DiscoveryPolicy, IrisTools, AdditionalTools, IrisSkills, AdditionalSkills, SystemPrompt and SessionConfigString;
  - `CAP` 8000 (70);
  - the policy setters `ToolManager.SetAuthPolicy`/`SetAuditPolicy` (180-182), experimental (AD-9).
- AI Hub's own runner settings, from `irislib/EnsLib/AI/Agent/OutboundAdapter.cls:123`: AgentClass, ProviderName, ProviderConfig and Model. `irislib` is gitignored, so the check holds these four names as a fixed list.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls:18`: ReplyClass. `src/bridge/cls/OcuTalon/Bridge/Adapter/StepRenderer.cls:12` extends `%AI.Shell.StreamRenderer` (experimental, AD-9).
- `src/bridge/cls/OcuTalon/Bridge/Timeouts.cls`: `Derive(timer)` returns `{timeout_ms, http_config:{request_timeout_secs, retry{...}}}`, and `Apply(timer)` needs `@{config:<name>}` runner configs (doc lines 1-14 and the Apply doc).
- Messages:
  - `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls` (Kind, Provenance, OwnerRef, Input, Summary, ItemId, Channel, ThreadSessionId, SessionMode);
  - `Msg/Result.cls` (the decision fields of the AC) and `Msg/DecisionResponse.cls` (`Payload`);
  - `Msg/AgentStep.cls` (8 properties);
  - `Msg/DecisionPayload.cls` (outcome, reasons, confidence);
  - `Msg/Enum.cls` (OUTCOME, PROVENANCE, REQUESTKIND, FALLBACKREASON, APPROVALSTATE, APPROVALKIND and CHANNEL; Epic 40's file, never edited).
- Governance:
  - `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`: classification order (code, then setting, then extension), untrusted and taint, and the HELD and UNTRUSTED sentences;
  - `Approval.cls:277` `Answer(ref, action, channel, irisUser, sessionRef, .winner)` returns done, already_answered, expired, not_found or not_allowed;
  - `Ext/HostSink.cls:35`, `Ext/ReplyFilter.cls:9` and `Ext/Classification.cls:15` are the do-nothing bases.
- `src/bridge/cls/OcuTalon/BridgeExample/*`:
  - the production's twelve items;
  - `ItemIn.Send(subject, body, provenance, .itemId)` (40);
  - the agent (`MODEL` claude-haiku-5-5, `TOOLSETS`);
  - `Tools`/`ToolSet` (the developer-tool rules shown by example).
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls:244-266`. OcuTalon's install seeds `AgentAllowList` with its runners' agent classes. This is OcuTalon's seeding, not the bridge installer's.

**The job:**
- `release/standalone-bridge.sh`:
  - header check list (2-79);
  - check 2 (127-143, LoadDir and `Installer.Run`);
  - check 3: the `ProviderConfig` row (163-175), `tool_json` (182), and the two `row_set` calls (185, 189);
  - check 4 `StartProduction` (244);
  - section 5 and its helpers: `F_FIND` (291), `F_AWAIT` (297), `item_check` (330) and `provider_key` (339);
  - the timer row (520-542) and 5d (544-562).
- `docker/tests/lib-live.sh`, read-only:
  - `check_session` (485) prints its script arguments one per line, so a multi-line block is one argument;
  - `iris_script` (311) keeps only `CHK|` lines;
  - `compare_chk` (460) requires each expected line and ignores extra ones.
- `ci/compose.ci.yml`, read-only. The image copies `src/` to `/opt/ocutalon/src/` (`docker/Dockerfile:11`), so the guide's LoadDir path is the container's path.
- `.github/workflows/lane-a.yml:1-10`. The header comment only.

**The checks:**
- `docker/tests/test-bridge-example.sh` is the sibling pattern: rule functions, a synthetic break and keep sample per rule, and PASS/FAIL lines.
- `docker/tests/lib-scan.sh` (`local_path`) and `lib-keys.sh` (`key_like`) are reused, not copied.
- `ci/units.sh:6` `CHECK_SCRIPTS`. Every `docker/tests/test-*.sh` must be in exactly one list (`test-ci-config.sh`).
- `release/checklist.sh`: the header rows (9-30), `ck_pass_text` (70-82), `row_readme` (282-296) and the run order (566-577).
- `docker/tests/test-release-checklist.sh`: `stub` (87), `mkbase` (91-99), `expect_fail` (171) and the readme/boundaries cases (360-363); the tmpfail rule appears in the header at line 17.
- `README.md:22-25`. `docker/tests/test-readme.sh`: header 13, `ITEM1`/`ITEM2` (116-117), `chk_use_cases` (370-382) and its samples (801-811), one of which ("an audit item appended", 809) breaks today and must change.
- `docs/security-overview.md:100`. The paragraph is hand-written, outside the generated regions (5-81). `live:security-overview` compares only the generated regions. `overviewdoc` is `t_overviewdoc` in `docker/tests/test-release-sequence.sh:1922`. The file is an input of every iris group (`ci/units.sh:148`), so this push runs every group.

## Tasks & Acceptance

**Execution:**
- `docs/bridge-guide.md` (new). The guide, in this order:
  1. A title and a short opening. It says what the bridge is, and that OcuTalon installs the same bridge as part of its own package while a separate bridge package and listing are a follow-on.
  2. `## Install and run the example`, in the AC's order:
     - requirements: AI Hub build 154 on IRIS for Health or IRIS, and an Interoperability namespace (how to make one in the Management Portal, in prose);
     - where the source sits: the commands use `/opt/ocutalon/src/bridge`, where OcuTalon's image keeps it, and the reader uses their own folder;
     - block `load` (`$SYSTEM.OBJ.LoadDir`, no IPM);
     - block `install` (`OcuTalon.Bridge.Installer.Run()`), with what it sets up;
     - the key: `ANTHROPIC_API_KEY` in the IRIS process environment, read through `@{env:...}` and never stored. Then block `provider`: the `TriageAgent` `ProviderConfig` System Default Settings row, `{"model_provider":"anthropic","api_key":"@{env:ANTHROPIC_API_KEY}"}`, with `http_config` set from `##class(OcuTalon.Bridge.Timeouts).Derive(60).%Get("http_config")` (DW-181);
     - block `start` (`Ens.Director.StartProduction`);
     - block `send` (`OcuTalon.BridgeExample.ItemIn` `Send`, leaving `sc` and `iid` set);
     - opening the decision in Visual Trace (prose: the message viewer, the item's message, Trace).

     Each block is `<!-- guide-run: <name> -->` on the line right before a fence that opens with three backticks and `objectscript`. The block holds terminal commands, one per line, and exactly one command whose `%Status` is set to `sc`. The guide tells the reader what a good result prints.
  3. `## Govern the example's tools`:
     - block `tool-classification`, the `Decide` `ToolClassification` row whose `%ToJSON()` equals the script's `tool_json`;
     - block `approval-role`, the `Decide` `ApprovalRole` row `ExampleApprovers`;
     - creating that role and giving it to the people who answer (prose);
     - answering with `OcuTalon.Bridge.Approval.Answer` from a privileged session (an illustrative, unmarked snippet).
  4. Reference sections:
     - every setting in the Code Map, with its default and its item: the agent class; the allow-list, seeded with OcuTalon's three agents by OcuTalon's install, which a developer extends with their own class; the toolsets (the agent's `TOOLSETS`); the model per runner; the provider config; the token budget; the timeout and its 110-second ceiling; the fallback route; the approval role (OcuTalon seeds `OcuTalonUser`); the tool classifications; and the three extension classes with their do-nothing defaults;
     - the refused settings;
     - timeout advice: inline `Derive(timer).http_config`, or `@{config:}` with `Timeouts.Apply`; otherwise AI Hub's 30 s Retry-After cap and default request timeout apply (DW-181);
     - the message types and every enum value;
     - tool classification: read-only, risky, unclassified counting as risky, identity by source class and tool name, and untrusted content and taint. It includes the U-229 sentence where it documents `ToolClassification`;
     - the fallback route and its reasons;
     - Workflow approvals and why no person is a Workflow user;
     - developer tool rules: no `%AI` call and no embedded Python in a tool, results as a dynamic object or plain text, a step label, and no classification needed in code;
     - "Experimental": subclassing `StreamRenderer` and the policy setters.

  Rationale: FR-5, and the ACs.
- `docs/security-overview.md:100`. After "...which never changes a classification that code gives.", insert "In this release, changing this setting writes no OcuTalon audit entry; each tool call is still audited." Change nothing else (U-229; orchestrator-decided cross-epic edit; a footprint extension).
- `release/standalone-bridge.sh`:
  - Add `guide_block <name>`. It prints the lines of the guide's block between its fence lines, and it dies, naming the block, when the marker is missing, repeated or empty, or when the line after the marker is not the `objectscript` fence.
  - Add one runner, `guide_check <label> <name> <expected CHK lines> [<lines after>...]`. It runs, in `$NS`, an error counter set up before the block (for example `$ETRAP` incrementing a variable, an inference that the first run measures), then the block verbatim, then `CHK|guide-errors|0`, `CHK|guide-sc|1` and the caller's lines.
  - Check 2 runs `load` and `install` through it, keeping `audit`, `other-classes`, `running-before` and `active-before`.
  - Check 3 runs `provider`, then one CI-only line that adds the mock's `base_url` and the `x-ocutalon-mockkey` header to that row. To do this, extend `provider_key` into one row-edit helper; do not copy it. It runs only after the mock-flag check passes. Check 3 then checks that the row's `api_key` is the placeholder and that its `http_config.request_timeout_secs` and `retry` equal `Derive(60)`'s. `tool-classification` and `approval-role` replace the two `row_set` calls.
  - Check 4 runs `start` in place of its own `StartProduction` line, with `F_ALIVE` and the rest unchanged.
  - New check 5-guide, before 5a, runs `send`, then `F_FIND` and a poll of up to 60 s until the session holds one `DecisionResponse` header and at least one `AgentStep` header with target `AgentSteps`.
  - Update the header to say that the job follows the guide, and name the blocks.
- `.github/workflows/lane-a.yml`. In the header comment only, say that the job follows `docs/bridge-guide.md` and runs its commands verbatim.
- `docker/tests/test-bridge-guide.sh` (new; in `CHECK_SCRIPTS`). It starts nothing and needs only bash, awk, sed and grep. Each rule first runs on a synthetic break sample and a synthetic keep sample:
  - `blocks`: the install section holds `load`, `install`, `provider`, `start` and `send`, in that order, and every `objectscript` fence in it has a marker. Each marker appears once in the file and has a non-empty block with one `Set sc=`. The set of names that the script passes to `guide_block`/`guide_check` equals the guide's marker set. No guide command line appears as a line or literal in the script.
  - `reference`: each name or value in the Code Map's lists appears in the guide (read from the source files with sed; the four AI Hub names are a fixed list). This includes `MAXTIMER` as "<n> seconds", the five `Answer` results, `Timeouts.Derive`, `Timeouts.Apply`, `@{config:` and `@{env:ANTHROPIC_API_KEY}`, a line that holds both `StreamRenderer` and "experimental", the policy setters with "experimental", "embedded Python", the package sentence and the follow-on sentence.
  - `u229`: the sentence in the guide, and in the "## Approval and audit" section of `docs/security-overview.md`.
  - `public`: ASCII only, no `local_path`, no `key_like`, no `http://`/`https://`, no IPv4 address, none of `ocutalon-slot`, `aihub-test`, `ocutalon-ci`, `ocupilot`, `iris-community-edition`, no "IRIS Couch" (any case) and no "openclaw" (any case). It prints file:line only. Build the forbidden words and the break samples by concatenation or a bracket pattern (as `release/checklist.sh` does with `[o]pen[c]law`), so that the script itself passes the checklist's `name-only-in-note` row and `test-boundaries.sh`.
  - Each FAIL names what is missing. Rationale: drift becomes a red check (AC 3 and AC 6).
- `ci/units.sh`. Append `bridge-guide` to `CHECK_SCRIPTS` (a plain-union edit).
- `release/checklist.sh`. Add the automated row `bridge-guide`: `docker/tests/test-bridge-guide.sh` exits 0, meaning the guide matches the release's code. The live proof of its commands is the standalone-bridge job on the candidate. It goes in the header list, in `ck_pass_text` and in the run order after `readme`. Extend `row_readme` into one shared script-row helper used by `readme` and `bridge-guide`, with the same tmpfail behaviour; do not copy it. This is a footprint extension: no open epic edits the file.
- `docker/tests/test-release-checklist.sh`:
  - stub `docker/tests/test-bridge-guide.sh` (marker `bridge-guide`) in `mkbase`;
  - add an `expect_fail "test-bridge-guide.sh fails" "bridge-guide "` case;
  - add the row to the tmpfail rule and to the header.
  This is a footprint extension.
- `README.md`. Append exactly one line after item 2: `- **[An AI decision step you can audit, in your own production.](docs/bridge-guide.md)**`. This is an ordered footprint extension (`epics.md` L4075).
- `docker/tests/test-readme.sh`:
  - add `ITEM3` (that line);
  - `chk_use_cases` checks three items and three lines;
  - the header line 13 says three items;
  - sample 809 becomes "the audit item without its link" (it must fail), and a sample that drops the third item fails.
  This is a footprint extension: no open branch edits the file.

- **U-233 instance-wide audit (Task).** Before writing the guide's install section, list every instance-wide item the guide's steps and the example rely on (audit events and whether instance auditing must be on, the Workflow role and user and their Security user, `Decide`'s `ServiceUser` and any role or resource a step or tool checks, the default `ApprovalRole` value, SSL configurations, `%AI` or AI Hub prerequisites, anything `lib-live.sh` or OcuTalon's after-start install creates that the job's checks then use), and for each record under Design Notes ("U-233 audit") who creates it: `Installer.Run` (cite the method), the guide's own prose step (for example creating an approval role), or the platform. Where the guide relies on an item that only OcuTalon's own install creates, close the gap inside `src/bridge/cls/OcuTalon/Bridge/Installer.cls` (idempotent, creates only when missing, behaviour unchanged for OcuTalon's own install, which calls it as its first step) with a unit test in the Bridge area, and list the file as a footprint extension; a gap whose fix lies outside the bridge installer is an `intent gap` HALT naming it. Where instance auditing must be on for the audit entries, the guide says how a developer checks it (`Installer.InstanceAuditing`) and turns it on, without the job assuming OcuTalon's install did it.

**Acceptance Criteria:**
1. Given `docs/bridge-guide.md`, when a developer follows its install section, then it gives, in order: the requirements (AI Hub build 154, IRIS for Health or IRIS, an Interoperability namespace); LoadDir of `src/bridge/` with no IPM; `OcuTalon.Bridge.Installer` and what it sets up (Workflow role and user, audit events, model families, prices); `ANTHROPIC_API_KEY` read through `@{env:...}` and never stored; starting `OcuTalon.BridgeExample.Production`; sending an item; and opening its decision in Visual Trace. It also says that OcuTalon installs the same bridge in its package and that a separate bridge package and listing are a follow-on.
2. Given the guide's reference sections, when a developer looks up the configuration, then they cover every setting, the refused settings, the message types with every field and enum value, tool classification, the fallback route and reasons, Workflow approvals through `Approval.Answer`, the developer-tool rules, the experimental marks, the DW-181 timeout advice and the U-229 sentence. `test-bridge-guide.sh` `reference` and `u229` pass, and each fails when one item is removed.
3. Given a push, when lane-a's standalone-bridge job runs, then it runs the guide's blocks verbatim from the guide, on a fresh build 154 stack in a clean Interoperability namespace. It fails if a command fails, or if no `DecisionResponse` and `AgentStep` header for the sent item appear in `OCUBRIDGE`'s message headers. `test-bridge-guide.sh` `blocks` fails on any drift between the guide and the script.
4. Given the guide's `provider` row with `Derive(60).http_config` (DW-181), when the rest of the script runs, then every check of Stories 13.1 and 13.2 passes, the timer row and 5d included, and the script ends `standalone-bridge: all checks passed`.
5. Given the README, when a judge reads "What you can use it for", then its third item is the line of the matrix, linking `docs/bridge-guide.md`. `docs/bridge-guide.md` is the stable path that Story 31.3 links.
6. Given the release checklist on a candidate, when it runs, then its row `bridge-guide` passes only when `test-bridge-guide.sh` passes (the guide matches the code, and the public-text rules hold), and `test-release-checklist.sh` pins the row's failure.
7. Given `docs/security-overview.md`, when `overviewdoc`, `live:security-overview` and `test-bridge-guide.sh` `u229` run, then the U-229 sentence is in its Approval and audit section and everything else is unchanged.

## Spec Change Log

- 2026-11-03, runner: U-233 applied (Design Notes, Runner rulings) and a U-233 instance-wide audit Task added under Tasks & Acceptance.

- 2026-11-03, runner (Epic 13 lead), spec gate: runner rulings recorded under Design Notes (Decided 8 and 9, U-229, public text, footprint extensions). Nothing else changed.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: the standalone path, the guide that uses it, one package and the follow-on;
- AD-5 and AD-19: the settings homes, rows and the key placeholder;
- AD-6 and AD-7: the runner, the refused settings, the allow-list, the model and the cap;
- AD-8: the fallback reasons, the timer, the 110 s ceiling, Derive and Apply;
- AD-9: steps, labels, and the experimental `StreamRenderer` and policy setters;
- AD-10: classification, untrusted and taint;
- AD-11: Workflow approvals and `Answer`;
- AD-17: the audit;
- AD-20: tokens and cost per turn and per decision;
- AD-22 and AD-29: the lane-a job and the static checks;
- AD-26: the trace session;
- AD-31: the extension classes;
- AD-33: ownership.

No AC contradicts an AD's Rule. Both AD-2 and the AC say that the installer sets up "default settings", but `Installer.Run` writes model families and prices and no settings row. See Decided 8. A wording fix to AD-2 is the lead's call (Rule 5, apply-and-report tier).

**Integration ACs (Rule 1/2):**
- AC 3: the consumer `release/standalone-bridge.sh` (the lane-a job) reads the guide's blocks and turns a broken or drifted guide into a red build.
- AC 6: the consumer `release/checklist.sh` runs `test-bridge-guide.sh` as a row.
- **Consumed-by:**
  - Story 31.3 links `docs/bridge-guide.md` from the About dialog and the finish state;
  - the release checklist (row `bridge-guide`);
  - the README.
- **Consumes:** the example of Stories 13.1 and 13.2, `Installer`, `Timeouts.Derive`, `Approval.Answer`, the mock and `lib-live.sh`. All run for real in the throwaway.

**Extend, don't copy (Rule 2):**
- `test-bridge-guide.sh` follows `test-bridge-example.sh`'s rule pattern and sources `lib-scan.sh`/`lib-keys.sh`. It is a new file, because the checklist row runs it alone.
- The CI-only provider edit extends `provider_key`.
- The checklist row extends `row_readme` into one shared helper.
- `guide_check` wraps `check_session`.

**Ledger inbox:** DW-181 is addressed by the `provider` block, the timeout reference text, the matrix row "DW-181 provider" and AC 4.

**U-223 check.** These "this release" statements in `docs/security-overview.md` stay true:
- L156, "MCP servers, which this release can't make";
- L178, "This release can't connect to MCP servers";
- L134, "a release without those features writes none of them";
- L172, "in a release that has them".

The example's tools make no MCP call, and the guide documents no MCP. "Every built-in tool is safe" also stays true: the example's tools are a developer's own tools on the example's runner, not built-in tools on OcuTalon's runners. No fix is needed.

**Decided in-stage:**
1. The guide's path is `docs/bridge-guide.md`, a new file in `docs/**`.
2. Commands are shared by extraction at run time. The script reads each marked block from the guide and runs it, so the guide is the one copy. `blocks` makes it a red check if the script ever keeps its own copy, or if the two disagree on the block names.
3. The guide's LoadDir path is `/opt/ocutalon/src/bridge`, where OcuTalon's image keeps the source and where the job's container has it. The guide tells the reader to use their own folder. It is no local machine path (`local_path` does not match `/opt`).
4. The namespace and the key are prose, not blocks. Creating an Interoperability namespace is a requirement, which the job's check 1 makes. The key is an environment variable whose value no command may hold, which the job's compose overlay sets to a dummy. The row that reads the key, `provider`, is a block.
5. The job adds one CI-only edit after `provider`: the mock's `base_url` and header, behind the existing mock-flag check (owner-fixed value 11). This is the CI environment, not a change to the guide's lines.
6. `Derive(60)`, the default `TimerSeconds`, is written as a literal. The guide says to write the row again after a timer change, or to use `@{config:}` with `Timeouts.Apply`. The inline `retry` and `request_timeout_secs` are accepted by AI Hub's expansion of the inline JSON (`OutboundAdapter.OnInit` parses inline and Config Store JSON the same way). This is an inference: the first script run measures it. If it is refused, that is an intent gap on DW-181.
7. The governance rows are blocks (`tool-classification`, `approval-role`), so the guide's example values are proved by check 4 and 5e. The role and its two users stay script fixtures, and the guide describes creating a role in prose. The install section ends at Visual Trace, so stopping the production is not a block.
8. The guide describes what `Installer.Run` does: audit events, the Workflow role and user, model families and prices. It reads "default settings" in the AC and AD-2 as the model-family defaults (cap and effort keys), because a text may claim only what the product does (product default 3).
9. "A clean build 154 container" is read as AD-2's clean namespace in a stack built fresh from the build 154 base image with no cache. This is the recipe of Stories 1.3 and 13.1. Check 2 shows no other OcuTalon class in `OCUBRIDGE`, and check 7 no web application. The stack still runs OcuTalon's after-start install in `OCUTALON`, so the instance-wide audit events exist before `install` runs. Making the container bare would mean overriding the image's command, healthcheck and CPF merge file in the run's compose overlay (about +45 min with a measurement). That is for the runner to rule if it wants it.
10. The release checklist confirms the guide through a new automated row, which runs a hermetic script. No author row is added (that would change the seven confirmations). `release/checklist.sh` and `test-release-checklist.sh` are edited by no open branch (checked against OCT-epic12, 15, 31 and 40; there is no Epic 10 or 11 branch).
11. Errors inside a block are counted through an error trap set before the block. This is an inference: `$ZERROR` alone would also count errors that system code catches. The first script run measures it.

**Public-facing text for the runner's veto window:**
- the whole guide (content fixed by the ACs; wording drafted here);
- the README item (the ordered sentence, bold and linked, no other words);
- the overview sentence (the Planner's wording, verbatim);
- the checklist row's PASS and FAIL text.

**Footprint extensions to report:**
- `docs/security-overview.md` (the orchestrator's decision);
- `README.md`;
- `docker/tests/test-readme.sh`;
- `release/checklist.sh`;
- `docker/tests/test-release-checklist.sh`.

**Runner rulings (2026-11-03, Epic 13 lead):**
- Decided 9 ("a clean build 154 container"): kept, the recipe of Stories 1.3 and 13.1 (a clean `OCUBRIDGE` namespace in a stack built fresh from the build 154 base image). Veto U-233, answered and applied (below).
- **U-233 applied** (owner answer via the Contest Planner, at=2026-11-03T04:27:26Z#698), verbatim: "Keep the 1.3/13.1 recipe for the CI job. The 45-minute overlay would sit on the critical chain. To close the gap the recipe leaves (instance-wide audit events, the Workflow role and user already exist before the guide's install runs), the Planner adds a hand gate on rc1: follow docs/bridge-guide.md literally on a bare build 154 container with no OcuTalon install and no OCUTALON namespace, and record the result. A failure is fixed before the tag. So the guide must not rely on anything OcuTalon's own install creates instance-wide; the bridge installer creates what it needs itself." Consequences for this story: (a) the guide's steps must work on a bare build 154 container with no OcuTalon install and no `OCUTALON` namespace; they never assume that audit events, the Workflow role or user, a Security user or role, a resource, an SSL configuration or anything else OcuTalon's own install creates instance-wide already exists; where the guide relies on one, `OcuTalon.Bridge.Installer.Run` creates it (idempotently, when none exists) and the guide says so; (b) no new CI overlay: the Planner's rc1 hand gate covers the bare-container run; (c) AD-2's wording is not amended (it goes to the attended architecture update after the run).
- Decided 8 ("default settings"): kept. The guide states exactly what `Installer.Run` sets up (audit events, the Workflow role and user, model families with their default cap and effort, prices). No AD-2 amendment: "default settings" reads as those defaults, and nothing is weakened. Category decide.
- U-229 (owner answer via the Contest Planner, at=2026-11-03T01:19:45Z#690) is applied by this story: the guide's `ToolClassification` text and the one `docs/security-overview.md` sentence, as Tasks state. The overview edit is the orchestrator's decided cross-epic edit; reported under `footprint_extensions:`.
- Public text (the guide, the README item, the checklist row text): drafted within the ACs' content; the README item is `epics.md` L4075's ordered sentence; the overview sentence is the owner's answer. The guide's wording is reviewed at code review against the public-text rules; category decide within the AC-fixed content.
- Footprint extensions `README.md` (one appended item), `docker/tests/test-readme.sh`, `release/checklist.sh`, `docker/tests/test-release-checklist.sh`: no open epic branch edits them (checked by the plan stage against OCT-epic12, 15, 31, 40); allowed under Rule 11 (b), reported.

**Size and split.** The estimate is about 3.5 to 4 hours: the guide about 1.5 h, the script about 1 h with a 6-minute run, and the checks, checklist and README about 1 to 1.5 h. If the runner wants about 3 hours, the split I propose is:
- 13.3: AC 1, 3, 4, 5 and 7, plus the `blocks` and `u229` rules;
- a sibling: AC 2's `reference` and `public` rules, and AC 6's checklist row.

The split is the runner's decision.

**Risk.** With `request_timeout_secs` 25 and one retry, the late reply (25 s) can keep `TriageAgent` busy for up to about 52 s after the timer row. 5d already polls 90 s (inference; the run measures it).

## Verification

`<lane B>` = `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=13 stage=<stage>'`. `<tag>` is `e13s3` followed by the stage's letter (implement `i`, QA `q`, review `r`). Every IRIS run goes to a lane B throwaway; slot B is untouched (no class changes). Run each command in the foreground of its own call with `timeout: 600000`, and make one IRIS run per message.

**Commands:**
- `(loop)` `bash docker/tests/test-bridge-guide.sh`. Expected: `blocks`, `reference`, `u229` and `public` PASS, each after its break sample is flagged.
- `(loop)` `bash docker/tests/test-readme.sh`. Expected: every rule PASS (`use-cases` with three items, `readme-links` reaching the guide).
- `(loop)` `bash docker/tests/test-release-checklist.sh`. Expected: every rule PASS, with the `bridge-guide` case.
- `(loop)` `<lane B> OCUTALON_RUN_TAG=<tag> bash release/standalone-bridge.sh`, then `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh teardown`. Expected: every check PASS, the guide checks included; `standalone-bridge: all checks passed`; about 6 min on ARM.
- `(once)` `<lane B> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh live security-overview`, then teardown. Expected: PASS, with no DRIFT line.
- `(once)` `bash docker/tests/test-release-sequence.sh`. Expected: `overviewdoc` and every other rule PASS.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-bridge-example.sh`, then `bash ci/checks.sh`. Expected: all pass, and `bridge-guide` appears in the checks output.
- `(once)` `git diff --stat -- src ci/mock ci/compose.ci.yml docker/tests/lib-live.sh .github/workflows/ci.yml docs/install-ipm.md`. Expected: empty. `git diff docs/security-overview.md` shows one changed line, and `git diff README.md` one added line.

**Pinning mutations (Rule 19).** The implement stage applies each, records it as `mutation: ... -> ...` and reverts it, checking byte-identity with `git status --short` and `git diff --stat`.
- AC 1/3: the guide's `load` path becomes `/opt/ocutalon/src/bridgeX`. Expected red: the script's guide load check, exit 1.
- AC 3 (command fails): the guide's `send` calls `SendX(`. Expected red: `guide-errors` of the send check.
- AC 3 (headers): the 5-guide poll looks for `OcuTalon.Bridge.Msg.AgentStepX`. Expected red: that check. This is a test mutation, because the headers are the bridge's own output.
- AC 3 (drift): the script gets a literal copy of the guide's `start` line; and separately, the `start` marker is renamed in the guide. Expected red: `blocks` both times (and the script dies on the rename).
- AC 4 / DW-181: drop the `http_config` line from the guide's `provider`. Expected red: the check-3 `http_config` line.
- AC 2: remove `RequestTokenLimit` and the experimental word from the guide. Expected red: `reference`.
- AC 7: change one word of the overview sentence. Expected red: `u229`.
- AC 6: a stubbed `test-bridge-guide.sh` fails. Expected red: the checklist row in `test-release-checklist.sh`.
- AC 5: drop the link from the README item. Expected red: `test-readme.sh` `use-cases`.
- public: add a non-ASCII byte to the guide. Expected red: `public` with file:line.

**Shared surfaces:**
- the README use list (`test-readme.sh` `use-cases`; Epics 10 and 12 append to items 1 and 2 later);
- the checklist's automated rows (`test-release-checklist.sh`);
- `CHECK_SCRIPTS` (`test-ci-config.sh`);
- `release/standalone-bridge.sh`'s check list;
- the hand-written Approval and audit section of the overview (`overviewdoc`, `live:security-overview`);
- the bridge's `SETTINGS`, `REFUSED`, message properties and `Msg.Enum` values. From now on `reference` asserts these, so an epic that adds one updates the guide (Epic 40 owns `Enum.cls`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
