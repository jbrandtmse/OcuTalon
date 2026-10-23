# Test Automation Summary

## Story 1.9: No model request goes over 100,000 tokens

The project's framework is `%UnitTest` (`src/ocutalon/cls/OcuTalon/Test/<Area>/`), run through `ci/iris.sh` in throwaway stacks (tag `e1s9q`). The scope is the diff since `1d77b31`; the criteria are the spec's Tasks & Acceptance and I/O & Edge-Case Matrix.

### Generated Tests (QA)

#### API and service tests (in process, the recorder `Test.Bridge.ZzDecide`)
- [x] `Test.Bridge.Decide.TestResendTooLargeSendsNothing` (AC1): the key resend over the limit sends no request and sets no timer.
- [x] `Test.Bridge.Decide.TestRequestLimitThroughOnRequest` (AC7): the limit that `OnRequest` and the key resend apply, for an empty row, 5000, 0, -1, abc, 1.5 and 100001.
- [x] `Test.Bridge.CodeRules.TestToolsReturnThroughResult` (AC5, strengthened): a JSON text passed to `..Return(` is flagged.

#### Live tests (production and CI mock)
- [x] `Test.Tools.Result.TestStepCapManyTools` (AC4): four tools of one model step share one room; the next step has its own. Scenario `ci/mock/scenarios/A/result-cap-steps.json`.
- [x] `Test.Agent.RequestSize.TestLimitIsNeverOff` (AC7): rows 0, abc and 100001 with `Decide` restarted; a turn at 100,001 tokens is a `too_large` fallback and never reaches the mock.

### Coverage
- Acceptance criteria with a pinning test: 7 of 7 (AC1 to AC7), each with a demonstrated mutation (the implement stage's 19 and QA's 4, in the spec's Verification).
- I/O matrix rows with a pinning test: all 14. The re-send row and the limit-setting row now also have a test through `OnRequest` and the running production.

### Runs
- `class` for `Tools.Result`, `Bridge.Decide`, `Agent.RequestSize` and `Bridge.CodeRules`: passed.
- `shard lane-a` forward and `--reverse`: passed (37 classes; the one SKIP is `TestStepHelpers`).
- `docker/tests/test-mock.sh`: 94 tests passed. `bash ci/checks.sh`: all scripts passed.

### Next Steps
- The lead runs `shard lane-b` forward and reverse (QA changed no test of Lane B).
- Gaps left as specified: `..Return(` of a string that merely looks like JSON is plain text to `Result`; a request that passes the check can still send a later request above 100,000 tokens until Story 30.1 compacts (deferred in the spec).
