# Unattended inbox -- run 20261021T1347Z-1-16,29-32

Answer an item with `bash _bmad/scripts/unattended-inbox.sh <this directory> answer U-<n> "<answer>" --by owner`, or run `/epic-cycle --review`. This file is generated: a hand edit is saved aside and never applied.

## Veto window

### U-2 | veto | Story 1.1 | 2026-10-21T14:36:21Z
question: Credential handling: the bridge Config Store Merge accepts api_key only as exactly one @{env:NAME} placeholder (NAME [A-Za-z0-9_]+) and refuses a literal key or any other @{ in any field, failing with nothing written (spec decision 10; AD-19 tightened, not changed).
options: keep (ruled) | reverse: allow other api_key forms, e.g. a literal key or @{config:} (reversal: edit OcuTalon.Bridge.ConfigStore.Merge's validation and TestMergeRefused/TestMergePlaceholder)
recommendation: keep: only a placeholder can ever reach an entry's api_key, which is what AD-19 and NFR-11 want; Story 17.3 sends one placeholder
blocks: nothing (Story 1.1 proceeds as ruled)
answer: (none yet -- answer with the script or --review)

### U-3 | veto | Story 1.1 | 2026-10-21T14:36:21Z
question: Credential handling in a test: OcuTalon.Test.Agent.KeyScan sets a fake, non-key-like ANTHROPIC_API_KEY value (ocutalon-keyscan-<NewRef>) through embedded Python in the throwaway test process only, restores the previous value afterwards, and asserts the value is stored nowhere (spec decision 13).
options: keep (ruled) | reverse: prove the no-key-stored AC with a live unit that starts a container with a fake key (a Lane B docker/tests change)
recommendation: keep: the value is not key-like, lives only in one throwaway process, and the test is what proves NFR-11 for the stored-key surfaces
blocks: nothing (Story 1.1 proceeds as ruled)
answer: (none yet -- answer with the script or --review)

### U-4 | veto | AD-22 | 2026-10-21T16:58:52Z
question: AD-22's 'CI as built' bullet now names the six IRIS groups (install-fresh with live:install-start; install-upgrade with live:install-upgrade and live:audit; production; browser; shards; image) in place of five, as Story 32.1's criterion requires; the Rule text is otherwise unchanged and the old wording is quoted in the AMENDED marker. Rule 21's Groups bullet and a measured sixth-run record were updated with it.
options: keep (ruled) | reverse: restore the five-group sentence (reversal: edit AD-22's CI-as-built bullet back, and revert ci/units.sh and the ci.yml matrix to five groups, which undoes Story 32.1)
recommendation: keep: the bullet records what CI runs; the orchestrator's Epic 32 spawn note named this record as a criterion of 32.1
blocks: nothing; Epic 32's merge does not wait on it
answer: (none yet -- answer with the script or --review)

### U-5 | veto | Story 1.2 | 2026-10-21T19:26:15Z
question: Stored message schema: the bridge's Reply gains FinishReason (%String, MAXLEN 32, the provider's stop reason from Response.Extra, empty when none; storage regenerated), and a new message class OcuTalon.Bridge.Msg.ToolInventory lets a test read a running runner's live tool list (spec decisions 7 and 11).
options: keep (ruled) | reverse: copy Response.Extra whole, or drop FinishReason and classify stop reasons inside the runner only; read the tool list another way (reversal: remove the property/class, regenerate storage, adjust Test.Bridge.Contracts and the inventory test)
recommendation: keep: additive; only the one Extra field AD-8 classifies is stored, never more model output; Lane B's Ac.cls checks names exist, so nothing else moves
blocks: nothing (Story 1.2 proceeds as ruled)
answer: (none yet -- answer with the script or --review)

### U-6 | veto | Story 1.2 | 2026-10-21T19:26:15Z
question: Credential handling in tests: CI starts with no key on purpose, so the live runner tests Merge each runner's Config Store entry to api_key @{env:OCUTALON_MOCK_KEY_HEADER} (a non-secret CI-only variable, value 1) in the throwaway only, restart the runners, and restore the entries afterwards; in-process tests use the same placeholder inline (spec decision 12).
options: keep (ruled) | reverse: add a dummy key variable to the CI compose override (a Lane B ci/ change) and point the tests at it
recommendation: keep: it uses the product path (entry, @{config:}, provider), writes no literal key, touches no Lane B file, and never runs on a slot
blocks: nothing (Story 1.2 proceeds as ruled)
answer: (none yet -- answer with the script or --review)

### U-7 | veto | Story 32.3 | 2026-10-21T19:30:40Z
question: Your balance rule (U-1, 'a': no IRIS job more than about 25% over the mean of the six) is judged on the grouping, i.e. each group's unit time normalized to one host, because the repository cannot choose which runner host a job lands on. Raw job times, runners and hosts are recorded every run, and the host disparity (ocutalon-ci-c runs a stack 1.4 to 2 times as long as ocutalon-ci-b; the first six-group run was 1.33x raw, 1.21x normalized) goes to you as the CI-capacity item with any job over about 10 minutes.
options: keep (ruled) | reverse: judge the rule on raw job times (reversal: Story 32.3's criterion fails until ci-c matches ci-b or IRIS jobs are pinned to one host class, both owner capacity actions; the epic would wait on them)
recommendation: keep: grouping is the part the repository controls, and its measured balance is 1.18 to 1.21 on four datasets; the capacity item carries the raw spread to you
blocks: nothing; Epic 32's merge does not wait on it
answer: (none yet -- answer with the script or --review)

## Run reports

### U-8 | report | CI capacity | 2026-10-21T21:27:30Z
question: Measured CI on the new hosts (Epic 32): ocutalon-ci-c starts IRIS stacks too slowly. On run 39675383146 (commit e366e33, no other run on the runners) all three IRIS jobs on ci-c failed the 400 s first-start limit (install-start, production, production-restart, sign-in), while the three on ocutalon-ci-b passed. Run 39657913372 failed the same way with six stacks on ci-c. On the first six-group run (39633794167) a stack on ci-c ran 1.4 to 1.9 times as long as on ci-b, and the job holding install-start takes about 11 min even on ci-b. Re-runs of the failed jobs have passed so far, so both lanes see intermittent reds that a re-run clears.
options: for information: the CI-capacity item (resize, replace or cap the services of ocutalon-ci-c) reaches you at Epic 32's merge-gate decision sheet
recommendation: check ocutalon-ci-c (CPU class, steal time, leftover containers or memory pressure) and make it match ocutalon-ci-b per stack, or cap its services so fewer IRIS jobs land there
blocks: nothing blocks on it; red runs on ci-c are re-run as infrastructure
answer: (none yet -- answer with the script or --review)

## Resolved
- U-1 | parked | Story 32.3: Story 32.3 (split from 32.1's second criterion): how should 'no IRIS job runs longer than about 10 minutes' be met? 32.1's plan measured that moving whole units cannot meet it on the current hosts: on run 39594299887 (five IRIS stacks on ocutalon-ci-b) live:install-start alone took 681 s, so the job holding it takes about 12 min whatever the grouping (best six-group split 13.6 min); at the lightest load seen (two stacks on ci-b) the floor is 10.1 min and the best split 11.3 min (inference: scaled); on ocutalon-ci-c install-start took 847 s alone. -> (a) Restate the 10-minute IRIS-job ceiling as a balance rule: no IRIS job more than about 25% over the mean of the six, with each job's time, runner and host recorded; a slowest job over about 10 minutes goes to the owner as a CI-capacity item. 32.1 and 32.2 proceed. (by Contest Planner, 2026-10-21T15:49:47Z#6; quoting the owner: "a"); resolved by orchestrator, 2026-10-21T22:09:40Z -- epic 32 applied it (32.3 restated as the balance rule)

<!-- journal: 12 lines -->
