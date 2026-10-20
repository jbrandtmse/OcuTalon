---
title: 'Story 0.11: The CI model mock answers every scenario the stories need'
type: 'feature'
created: '2026-10-20'
status: 'done'
baseline_revision: '4089a09bba089622cb3bf7a56e8bffe8d4003cb8'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The failing path of the Rule 21 guard (OCUTALON_MODEL_BASE_URL is not the mock's) has no automated test: every provider test of Test.Contract.Mock then fails with row 23's text and no provider is built, but only a run under another value shows it, and CI always runs under the mock's.
    evidence: |-
      TestBaseUrlGuard pins CheckBaseUrl on seven values, and the mutation "CheckBaseUrl accepts any value" turns it red. The consequence was shown by hand in the v11a throwaway with `dc exec -e OCUTALON_MODEL_BASE_URL=https://api.anthropic.com/v1/` and with `http://mock:8080/v1`: the four provider tests failed with the text, TestBaseUrlGuard passed, and the mock's log gained 0 lines. An in-process test cannot change the process environment (%SYSTEM.Util has GetEnviron and no SetEnviron).
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls (OnBeforeAllTests, Guard, Provider)
    severity: low
---

<intent-contract>

## Intent

**Problem:** CI has no model mock, and no test may ever reach the real model API.
- `ci/compose.ci.yml` holds only the `OCUTALON_EVAL` passthrough. The `web` job's step "Mock tests: none until Story 0.11" runs nothing.
- Lane A's Epic 1 stories (1.2, 1.3 and 1.6 to 1.9) have nothing to send model requests to and no log to read.
- AD-22 names the mock's job and its scenario file format, but none of it exists: the selection order, the countdown, the summarizer path and the logs.

**Approach:**
- **The mock.** A Node 24 HTTP service in `ci/mock/` with no dependencies beyond the standard library. It answers `POST /v1/messages` and `GET /v1/models/<id>` the way the Anthropic API does.
  - It rejects sampling parameters and output caps under 4,000.
  - It picks each request's scenario in a fixed order: a `[[mock:<name>]]` marker, then a guide prompt's exact text, then the agent's `MOCKKEY`.
  - It answers summarizer requests (`OCUTALON-COMPACTION-V1`) in AI Hub's summary schema.
  - Its only state is a per-test countdown, set through a control endpoint.
  - It logs header names and the key's length, never a value.
- **The scenarios.** One JSON file each, under `ci/mock/scenarios/A/` and `B/`. This story writes the three default scripts and every scenario that Stories 1.6 to 1.9 need.
- **The wiring.** `ci/compose.ci.yml` gains the `mock` service and points `iris` at it through AD-19's `OCUTALON_MODEL_BASE_URL`, over plain HTTP on the compose network. The judges' compose file doesn't change (CON-3).
- **The tests.**
  - `node --test` runs in the hosted `web` job, through `docker/tests/test-mock.sh`.
  - The IRIS-side Integration test, `OcuTalon.Test.Contract.Mock`, rides the existing `lane-b` shard. It drives AI Hub's Anthropic provider at the mock.

## Boundaries & Constraints

**Always:**
- **No real model request, ever.**
  - Every request a test in this story sends goes to `http://mock:8080/v1/`.
  - `OcuTalon.Test.Contract.Mock` refuses any other base URL before it builds a provider.
  - It uses the dummy key `ocutalon-ci-mock-key` and never `@{env:ANTHROPIC_API_KEY}`.
- **AD-22's selection order:**
  - first a marker in the newest user message that has text;
  - then a `B/` guide prompt's exact text contained in that message (after the `Agent.Input` preamble);
  - then the `MOCKKEY` that the request carries in the header `x-ocutalon-mockkey`.

  Selection never uses wording. A summarizer request (`system` text starting `OCUTALON-COMPACTION-V1`) bypasses markers, except the `summary-*` ones.
- **Logs and state (AD-22).**
  - The mock logs header names and the `x-api-key` length, never a header value or a key.
  - Key-like text in a logged request body is redacted.
  - Its only state is the countdown map, keyed by the full marker.
- **The no-key start (0.6).** The CI override adds no key variable. `check_no_key` and `test-compose-file.sh`'s key ban stay green.
- **Source text.** Node's standard library only, as ES modules (`.mjs`). Every file is ASCII.
  - Comments state contracts (Rule 14).
  - No tracked file holds a local machine path or a key-like string. A key-like test fixture is built at run time, for example `'sk-' + 'ant-' + 'x'.repeat(20)`.
  - The mock's files never name the image's home folder, which `test-boundaries.sh`'s local-path rule flags.
- **REL-4.** No new compose stack, CI unit, group or restart. The Integration test is a class in the existing `Contract` area, so it rides shard `lane-b`.
- **Runtime targets (Rule 21).**
  - Slot A only loads the new IRIS class (a compile check).
  - Every IRIS run of it is in a throwaway, through `ci/iris.sh`, one stack at a time.

**Never:**
- **Files left unchanged:**
  - `docker-compose.yml`, `docker-compose.dev.yml`, `docker/Dockerfile`, `.dockerignore` and `docker/tests/compose.throwaway.yml`;
  - `.github/workflows/lane-a.yml` and `epics.md`;
  - every product class under `src/` (everything outside `OcuTalon.Test`). The `Provider` step stays a stub until 1.1.

  `docker/tests/lib-live.sh` needs no change: its file set, `up` and `down` already cover a second service. Change it only if Task 0 shows otherwise, and say why in the Spec Change Log.
- **Not built here:**
  - SSE streaming;
  - the Telegram Bot API side (10.3);
  - a reply that quotes an earlier tool result or depends on the history (1.10, 8.4, 1.8);
  - a default "pong" reply.
- **No npm dependency and no image built for the mock.** Nothing is pushed, and nothing signs in to a registry.
- **Forbidden output.** No `docker compose config` without `--quiet`, and no `docker inspect` or `docker image inspect` without `--format`.
- **Slots.** Never run `OcuTalon.Test.Contract.Mock` on a slot, and never set `OCUTALON_MODEL_BASE_URL` there. No slot agent is pointed at the mock.
- **Never touched.** `ocutalon-aihub-test`, `ocupilot*` and `iris-community-edition`. Never read `.env`.
- **Never edited.** `.claude/`, `CLAUDE.md`, `irislib/` and `irissys/`.

## I/O & Edge-Case Matrix

Where the rows run:
- **Rows 1–18:** `ci/mock/test/*.test.mjs`, through `bash docker/tests/test-mock.sh` in the hosted `web` job.
  - Each file starts its own in-process server on port 0. Row 18 spawns `server.mjs` instead.
  - Each writes its fixtures to a fresh temporary folder and removes it afterwards.
- **Rows 19–23:** `OcuTalon.Test.Contract.Mock`, shard `lane-b`, in throwaways only.

`<n>` is the mock's request number.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|---|
| 1 | Model lookup | `GET /v1/models/claude-haiku-5-5` with an `x-api-key` | 200 with the model object `{"type":"model","id":<id>,"display_name":<id>,"created_at":"2026-01-01T00:00:00Z","max_input_tokens":1000000,"max_tokens":128000,...}`, for any id | — |
| 2 | No key | `POST /v1/messages`, or the lookup, with no `x-api-key` or an empty one | 401 `authentication_error`, "CI mock: the request has no x-api-key header". The log shows `keyLength` 0. No scenario runs | — |
| 3 | Sampling parameter | A body with top-level `temperature`, `top_p` or `top_k`, with any value, `null` included | 400 `invalid_request_error`. The message names every such field and NFR-1, and the log line has `rejected` | — |
| 4 | Output cap | `max_tokens` absent, not an integer, or 3999 | 400 `invalid_request_error`, naming the value and NFR-2. 4000, 8000 and 8192 pass | — |
| 5 | Unsupported body | `stream: true`; a body that isn't JSON; `messages` that isn't a non-empty array | 400 `invalid_request_error`, saying which | — |
| 6 | Marker | The newest user message with text holds `[[mock:refusal]]` | 200, `stop_reason` `refusal`, scenario `refusal`. The message's first marker wins. A marker is ignored when it sits only in an older user message, a `tool_result` block, the system text or an assistant message. `[[mock:refusal:t-1]]` also picks `refusal` | An unknown name, or a `[[mock:` that doesn't parse: 500 `api_error` naming it |
| 7 | Guide prompt | No marker. The user text is a preamble followed by a `B/` prompt scenario's exact text | That scenario. A text that differs by one character, or by case, doesn't match | Two prompts match: 500 naming both |
| 8 | Mock key | No marker and no prompt; header `x-ocutalon-mockkey: triage` | Scenario `triage`. A marker in the same request wins over the header | The header is absent, or names no scenario: 500, "CI mock: no scenario: no marker, no guide prompt and no known mock key" |
| 9 | Turn step | `chat` (replies: a `list_productions` tool use, then a text). Request 1, then request 1 plus an assistant `tool_use` and a user `tool_result` | Request 1 gets one `tool_use` block (id `toolu_mock_<n>_1`, input `{}`, `stop_reason` `tool_use`). Request 2 gets the text, with `end_turn`. A step past the last reply gets the last reply again | — |
| 10 | Summarizer | `system` (a string or text blocks) starting `OCUTALON-COMPACTION-V1`. The transcript quotes `[[mock:refusal]]` and `[[mock:summary-off-schema:t-2]]` | The transcript's last `summary-*` marker picks `summary-off-schema` (prose). Without one, `summary` answers, with JSON in AI Hub's schema. No other marker fires. In a normal request, a `summary-*` marker is skipped, and selection goes on to the prompt, then the mock key | No `summary` scenario: 500 |
| 11 | Countdown | `POST /_mock/countdown {"marker":"rate-limited:t-3","remaining":2}`, then three requests carrying that marker | 429 (`Retry-After: 1`), 429, then the 200 text. `GET /_mock/countdown?marker=rate-limited:t-3` then gives `{"marker":"rate-limited:t-3","remaining":0}`. An unarmed `rate-limited:t-4` gets 429 every time. `"remaining": null` clears a countdown. No other marker's countdown changes | An unknown scenario, a malformed marker, or `remaining` that is not an integer from 0 to 1000: 400 |
| 12 | Delay | A fixture reply with `delayMs` 300, and a second request sent while it waits | The first answers after at least 300 ms, and the second is answered meanwhile. A client that hangs up first causes no error and no write | — |
| 13 | Error replies | `provider-error`, `invalid-input` and `overloaded` | 500 `api_error`; 400 `invalid_request_error`; 529 `overloaded_error` with `Retry-After`. Each body is `{"type":"error","error":{"type":...,"message":...}}` | — |
| 14 | Logs | Any request, with a key built at run time | One stdout line and one `requests.jsonl` line, both written before the reply and before any delay. The fields: `ts`, `id`, `method`, `path`, `status`, `scenario`, `selectedBy`, `marker`, `step`, `countdown`, `headerNames` (lower case), `keyLength`, `rejected`, `model` and `maxTokens`. The file's line adds `request`: the messages verbatim, `system` as `{chars, cacheControl}` and `tools` as `[{name, cacheControl}]`. Neither line holds a header value or the key. Key-like text in a message is logged as `[redacted]` | A log folder that can't be written: exit 1 at start |
| 15 | Scenario files | Every committed file under `A/` and `B/`, and fixture trees with one defect each | The committed files load. A file is refused, naming the file and the rule, when: its `name` isn't kebab-case or differs from its basename; it has an unknown field; `match` doesn't have exactly one key; `match` is `telegram` (reserved for Story 10.3); `marker` differs from `name`; it is a `prompt` scenario under `A/`; its name, mock key or prompt repeats one in either folder; its prompt contains another prompt; `replies` is empty; a reply doesn't hold exactly one of `text`, `toolUse` and `body`; `status` is outside 100–599; `stopReason` comes with `body` or an error status, or isn't an API value; `delayMs` is outside 0–600000; a `toolUse` has no `name`. Also refused: any non-`.json` file except a dotfile, and any folder other than `A` and `B` | The server lists every problem and exits 1 |
| 16 | Constants | `src/` and the committed scenarios | Each agent class's `MOCKKEY` has exactly one `mockkey` scenario, and each `mockkey` scenario names an agent. Every `toolUse` name in a `mockkey` scenario, and every `tool` in `summary`, is a value of `OcuTalon.Tools.Names`. The mock's summarizer prefix equals `Bridge.Compaction`'s `PREFIX`. `summary`'s text parses to the seven schema keys, with at least one `facts_learned` and at least one `tool_actions` entry, each with `tool`; `summary-off-schema`'s doesn't. Every file this test reads matches `WEB_INPUT_PATTERN` | — |
| 17 | Other paths | `POST /messages`, `GET /v1/models`, `GET /bot<x>/getMe` and `GET /_mock/health` | The first three get 404 `not_found_error` naming the path; the Bot API one names Story 10.3. Health gets 200 `{"ok":true,"scenarios":<count>}` | — |
| 18 | Shutdown | `server.mjs` with a held request open, sent SIGTERM | It exits 0 within 1 s | — |
| 19 | Through AI Hub, by mock key | `Provider(<OcuTalon.Agent.Triage's MOCKKEY>)`: the dummy key, the base URL from the environment, the full retry block and the `x-ocutalon-mockkey` header. Then `%Init` and a `Chat` with no marker | The reply is a JSON object whose `outcome` is in `OcuTalon.Bridge.Msg.Enum`'s `OUTCOME` and whose `confidence` is from 0 to 1. `Extra.finish_reason` is `end_turn`, and `GetStats().model_context_size` is 1000000. The new log lines hold a 200 `GET /v1/models/claude-haiku-5-5` and a POST with: scenario `triage`, `selectedBy` `mockkey`, `model` `claude-haiku-5-5`, `maxTokens` 8000, `keyLength` 20, and `x-api-key` among `headerNames`. The log file never holds `ocutalon-ci-mock-key` | — |
| 20 | By marker | `Chat(..., "... [[mock:refusal:<NewRef>]]")` | `finish_reason` `refusal`, and exactly one POST line with that marker and `selectedBy` `marker` | — |
| 21 | Rejections on the real path | A session with `extra_params: {"temperature": 0.5}`; then a session with `max_tokens` 3999 | Each `Chat` throws `<%AICore>ProviderError`. The text holds "Invalid input" and "temperature" (then "max_tokens"), and the log line has status 400 and `rejected` | — |
| 22 | Countdown and the back-off cap (S18) | `Arm("long-retry-after:<NewRef>", 1)`, then a `Chat` with that marker | The 200 text arrives in 1.5–10 s: `Retry-After` is 30, and `max_backoff_ms` 2000 caps the wait. `Remaining` gives 0, and the log shows 429 and then 200 for the marker | — |
| 23 | Not a throwaway | `CheckBaseUrl` of "", `https://api.anthropic.com/v1/`, `http://mock:8080/v1` and `http://mock:8080/v1/` | Only the last is OK. Wherever the environment holds another value, every test fails with "OCUTALON_MODEL_BASE_URL is not http://mock:8080/v1/: this class runs in throwaways and CI only (Rule 21)", and `Provider` throws before it builds anything | By design |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line:
  - **AD-22, L576–600:**
    - the override and the `base_url` path, L582;
    - what the mock serves, L583;
    - the selection order and the 0.6 constants, L584–588;
    - summaries, L589;
    - logs, state, the scenario files and the lanes, L590;
    - the Bot API side (10.3), L591;
    - CI as built, L598.
  - **AD-19, L484:** the endpoint overrides (`OCUTALON_MODEL_BASE_URL` ends in `/v1/`), and `custom_headers` replacing a same-named header (S2).
  - **AD-8, L261–271:** the timer (default 60 s, at most 110 s) and `Derive`'s full retry block. AI Hub waits `min(Retry-After, max_backoff_ms)`, retries 429 but never 500 or 529, and raises "Rate limit exceeded" for both 429 and 529, and "Invalid input" for a 400.
  - **AD-20, L537–541:** the compaction prompt and its schema (`user_goals`, `constraints`, `decisions`, `facts_learned`, `tool_actions` with a required `tool`, `open_questions` and `next_steps`). The summarizer's cap is 8,192 and it gets no retries.
  - **AD-7, L229–231:** no sampling parameters, and a cap of 8,000 (never below 4,000).
  - **AD-29 and AD-33, L761–777 and L830–839:** `ci/mock/scenarios/A/` is Lane A's; the mock and the rest of `ci/` are Lane B's.
  - **Other rows:** Stack, L898–921 (Node 24 LTS at L911); the throwaway row, L1132; the source tree, L1155; the spikes S2, S3 and S18 at L1216, L1217 and L1232.
- **Epics** (`_bmad-output/planning-artifacts/epics.md`):
  - **This story:** L1034–1049; the split from 0.7 is at L959.
  - **Consumers of the mock:**
    - 1.2's log check, L1108;
    - 1.3's request-log check, L1155;
    - 1.5's two tool calls, L1208;
    - 1.6, L1220 (the "never sent" log check at L1235);
    - 1.7, L1251;
    - 1.8, L1273;
    - 1.9, L1306 ("recorded by the mock" at L1337);
    - 1.10's list-then-cancel, L1358;
    - 4.4's guide prompts under `B/`, L2174;
    - 4.6's mailbox markers, L2248;
    - 8.4, L2927;
    - 10.3, L3186;
    - 12.1, L3458;
    - 13.1's example agent, L3704.
- **PRD** (`_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md`): NFR-1 L1143, NFR-2 L1144, NFR-5 L1154, CON-3 L1223 and REL-4 L1289.
- **Spike evidence** (`ARCHITECTURE-NOTES.md` §1; the S3 and S18 rows):
  - the URL ends `/v1/`;
  - AI Hub looks up the model at `%Init`;
  - the key travels in `x-api-key`;
  - "Invalid input" is a 400;
  - "Rate limit exceeded" covers 429 and 529;
  - a `Retry-After` of 30 under a 2,000 ms cap waited 2.01 s.
- **The spike prototype** (`../spikes/mock/mock.py` and its `README.md` from the repository root, outside the repository; Python; read only). It shows:
  - markers read from the newest user text message, with `tool_result` blocks ignored;
  - the tool step counted from the assistant messages after it;
  - the countdown per marker key;
  - the summarizer bypass;
  - the model object and the error bodies;
  - what AI Hub sends: `x-api-key`, `anthropic-version`, `anthropic-beta`, a body of `model`, `max_tokens`, `system` (a string, or one text block with `cache_control` when long) and `messages`, with no `stream`. 171 of the 172 recorded requests were non-streaming.

  The recorded S18 summarizer request shows that the custom prompt is the `system` string verbatim and the transcript is one user text block.
- **CI recipe (Story 0.7):**
  - `ci/compose.ci.yml`, L1–10: the only file this story's service joins.
  - `docker/tests/lib-live.sh`:
    - `LIVE_FILES` (the judges' file, a decoy, the throwaway override, then the CI override), L81, and `dc()`, L239–243;
    - `live_first_start` runs `dc up -d --no-build`, L384, and waits only for iris;
    - `live_cleanup` runs `dc down -v --rmi local`, L263, so a pulled image is kept;
    - `check_no_key`, L634–643;
    - `iris_script <ns>`, L303.
  - `ci/iris.sh`:
    - its header says "it never pulls", L4;
    - `preflight`, L61–69;
    - `test_classes` finds classes by folder and `^Method Test`, L78–95, so `Test/Contract/Mock.cls` joins `lane-b` with no list change;
    - `run_classes` runs `dc up -d --build --wait --wait-timeout`, L180, so it waits for the mock's health check;
    - `teardown` runs `down -v --rmi local --remove-orphans` and then matches the tag's leftovers (`$P-mock-1` and `${P}_mock-log` among them; never `node:`), L343–376.
  - `ci/units.sh`:
    - `WEB_SCRIPTS`, L9;
    - `WEB_INPUT_PATTERN`, L46. `ci/` already counts; `docker/tests/test-mock.sh` and the constant files don't yet.
  - `.github/workflows/ci.yml`: the `web` job's steps, L45–80, with the placeholder at L73–74.
- **Pins to change:**
  - **`docker/tests/test-compose-file.sh`:**
    - `ci_file_is_exact`, L210–216;
    - `ci_services_are_known`, L219–226, which already allows `mock`;
    - `ci_adds_no_port_file_or_key`, L229–230, which today forbids `image`, `volumes` and `command`;
    - the `config --quiet` parses, L237–239;
    - the CON-3 checks, L39–42 and L195.
  - **`docker/tests/test-ci-config.sh`:**
    - the header, L19–20;
    - the web wiring: each `WEB_SCRIPTS` entry needs `run: bash docker/tests/test-<name>.sh` gated `web == 'true'`, L486;
    - the placeholder pin `need_named("web", "Mock tests: none until Story 0.11", ...)`, L490;
    - the `mock` wiring sample, L522, and the sample list, L524;
    - the coverage rule, L549–600;
    - the stub docker of the browser-unit preflight, around L845.
  - **`docker/tests/test-ci-changes.sh`:** the `paths_case` rows, L100–118.
  - **`docker/tests/test-lib-live.sh`:** it pins `FILES=4` and the call order of `live_first_start`, L342–383, L423 and L461. Unchanged, because the mock lives inside the fourth file.
- **Scanners** (`docker/tests/test-boundaries.sh`):
  - `local_path`, L33–37: it flags `/home/<x>` other than `irisowner`, and `/Users/`;
  - `key_like`, L39–41: `sk-ant-` followed by eight or more characters, bot tokens, GitHub tokens and private keys;
  - the ASCII-only rule over `src`, `docker`, `ci`, `.github` and `web`, L30 and L191;
  - `risky_docker_calls`, L44–56.
- **0.6's constants:**
  - `src/ocutalon/cls/OcuTalon/Agent/{Triage,Diagnosis,Chat}.cls`, L6 and L9: `MODEL` `claude-haiku-5-5`, and `MOCKKEY` `triage`, `diagnosis` and `chat`. The classes have no provider of their own, so `%New(provider)` must be given one.
  - `src/ocutalon/cls/OcuTalon/Tools/Names.cls`: 11 snake_case parameters plus `RELEASE1`, the list of them.
  - `src/bridge/cls/OcuTalon/Bridge/Compaction.cls`: `PREFIX` = `OCUTALON-COMPACTION-V1`, and the `Prompt` XData.
- **IRIS-side reuse:**
  - `src/ocutalon/cls/OcuTalon/Test/Demo/Production.cls`: the `Missing` property, `OnBeforeAllTests`, L40–50, and the private `Guard()`, L228–235. This is the fail-never-skip pattern; a skip would count as passed in `ci/iris.sh`, L136–160.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls`: reads `MOCKKEY` with `$Parameter`.
  - `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`: `outcome` (`MAXLEN` 32), `reasons` (a list) and `confidence` (`MINVAL` 0, `MAXVAL` 1, `SCALE` 2).
  - `OcuTalon.Bridge.Msg.Enum`: `OUTCOME` = `ignore,digest,tellnow,act`.
  - `OcuTalon.Bridge.Ids.NewRef()`: the marker keys.
  - No class in `src/` uses `%Net.HttpRequest` yet.
- **AI Hub** (`irislib/%AI/`; read only):
  - `Provider.cls:69`: `Create(name, settings)`;
  - `Agent.cls`: `%OnNew(provider)` at L175, `Model` at L53, `SystemPrompt` at L56, `%Init()` at L197, `CreateSession(config)` at L639 and `Chat(session, input, feedback)` at L728;
  - `LLM/Response.cls`: `Content`, `Usage` and `Extra.finish_reason`;
  - `Agent/Session.cls:274`: `GetStats()`.

  All the HTTP work is native (`$ZF(-6, ...)`), so request details are known only from the spikes and from Task 0.
- **The image:**
  - `node:24.15.0-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d`;
  - measured at plan time, October 20: an OCI index with `linux/amd64` and `linux/arm64/v8`, base `debian:bookworm-slim`, created 2026-05-19;
  - Node v24.15.0, running as root, with a global `fetch`;
  - already on the developer machine.

## Tasks & Acceptance

- [ ] [Owner decision 5, October 20; added by the lead after implement] `ci/compose.ci.yml` gives `iris` the explicit CI-only setting `OCUTALON_MOCK_KEY_HEADER: "1"` beside `OCUTALON_MODEL_BASE_URL`, and `test-compose-file.sh` pins it there and its absence from the judges' compose file. Story 1.1's `Provider` step adds `x-ocutalon-mockkey` only when it is on (DW-39); `OCUTALON_MODEL_BASE_URL` alone never adds the header, and online-demo traffic never carries it (AD-19 as amended).

**Execution:**

**1. The mock (Lane B, `ci/mock/`).** ES modules, ASCII, Node's standard library only (`node:http`, `node:fs`, `node:path`, `node:url`, `node:child_process` in tests). Each module opens with a contract comment.
- **`ci/mock/scenarios.mjs` (new): `loadScenarios(dir)`, which returns `{scenarios, problems}`.**
  - It reads `dir/A/*.json` and `dir/B/*.json`, applies every rule of row 15 and reports all problems at once.
  - It builds the lookups: by name, by mock key, and the prompt list.
  - It exports the format constants for the tests: the match types, the reply fields, the API stop reasons (`end_turn`, `max_tokens`, `stop_sequence`, `tool_use`, `pause_turn`, `refusal`), the name grammar `^[a-z0-9]+(-[a-z0-9]+)*$` (at most 64 characters) and the marker grammar `[[mock:<name>]]` or `[[mock:<name>:<key>]]`, where the key matches `[A-Za-z0-9_-]{1,64}`.
- **`ci/mock/mock.mjs` (new): `createMock({scenarios, logDir, out})`, which returns `{handle(req, res), countdowns}`.**
  - **Order:** the path; the key (row 2); JSON and stream (row 5); sampling (row 3); the cap (row 4); the summarizer check; then the marker, the prompt and the mock key (rows 6–8, 10); then the reply (rows 9, 11–13).
  - **The key check covers only the `/v1/` paths.** `/_mock/` (health and countdown) takes no key, because the IRIS tests and the health check call it without one.
  - **The reply index:** see "The reply rule" in Design Notes.
  - **The message body:** `{"id":"msg_mock_<n>","type":"message","role":"assistant","model":<the request's>,"content":[...],"stop_reason":...,"stop_sequence":null,"usage":{"input_tokens":ceil(len(body)/4),"output_tokens":ceil(len(content JSON)/4) or 0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}`.
  - **Text replies:** `text: ""` gives `content: []`. For an error status, `text` becomes the API's error body, typed by status: 400 `invalid_request_error`, 401 `authentication_error`, 403 `permission_error`, 404 `not_found_error`, 413 `request_too_large`, 429 `rate_limit_error`, 500 `api_error`, 529 `overloaded_error`, anything else `api_error`.
  - **Headers:** `content-type: application/json`, `request-id: req_mock_<n>` and the scenario's own headers.
  - **The countdown map and its control endpoint** (row 11).
  - **The log** (row 14): it writes synchronously (`appendFileSync`) before any delay.
  - **The redaction regex:** a stated copy of `test-boundaries.sh`'s `key_like` alternatives.
  - **A delay:** a `setTimeout` cleared on `close`.
  - **The 404s** of row 17.
- **`ci/mock/server.mjs` (new): the entry point.** It takes `--port` (default 8080; with 0, the bound port is printed), `--log-dir` (absent means stdout only) and `--scenarios` (default: `scenarios/` beside the file).
  - On any problem it writes the list to stderr and exits 1.
  - It listens on all interfaces and prints `{"event":"listening","port":<p>,"scenarios":<n>}`.
  - On SIGTERM or SIGINT it exits 0 at once (row 18). As PID 1 in its container it must handle the signal itself, or teardown would wait out the grace period.
- **`ci/mock/health.mjs` (new): the health check.** It sends `GET http://127.0.0.1:8080/_mock/health` with a 1.5 s abort, and exits 0 or 1.

**2. The scenarios.** `ci/mock/scenarios/A/` holds 16 new files, each `{"name", "match", "replies"}` with two-space indentation; the reply rule is in Design Notes.

| File | `match` | `replies` |
|---|---|---|
| `triage.json` | `{"mockkey":"triage"}` | 200 `text` `{"outcome":"digest","reasons":["The CI mock keeps this item for the digest."],"confidence":0.5}` |
| `diagnosis.json` | `{"mockkey":"diagnosis"}` | 200 `toolUse` `{"name":"read_failed_messages","input":{}}`; 200 `text` `{"causeCategory":"data_format_change","elementAtFault":"OrderDate","fixKind":"repair_resend","reasons":["The CI mock read the failed messages."],"confidence":0.8}` |
| `chat.json` | `{"mockkey":"chat"}` | 200 `toolUse` `{"name":"list_productions","input":{}}`; 200 `text` "The CI mock looked at the productions." |
| `refusal.json` | `{"marker":"refusal"}` | 200, `stopReason` `refusal`, `text` "The CI mock refuses this request." |
| `max-tokens.json` | `{"marker":"max-tokens"}` | 200, `stopReason` `max_tokens`, `text` "This reply stops at the output cap before its answ" |
| `empty.json` | `{"marker":"empty"}` | 200, `text` "" |
| `provider-error.json` | `{"marker":"provider-error"}` | 500, `text` "CI mock: the provider failed." |
| `invalid-input.json` | `{"marker":"invalid-input"}` | 400, `text` "CI mock: messages: the stored conversation is not valid input." |
| `invalid-reply.json` | `{"marker":"invalid-reply"}` | 200, `text` `{"outcome":"maybe","reasons":"none","confidence":2}` |
| `held-past-timer.json` | `{"marker":"held-past-timer"}` | 200, `delayMs` 120000, `text` "This reply arrives after the bridge timer." |
| `rate-limited.json` | `{"marker":"rate-limited"}` | 429, `headers` `{"Retry-After":"1"}`, `text` "CI mock: rate limited."; 200 `text` "Answered after the rate limit." |
| `overloaded.json` | `{"marker":"overloaded"}` | 529, `headers` `{"Retry-After":"1"}`, `text` "CI mock: overloaded."; 200 `text` "Answered after the overload." |
| `long-retry-after.json` | `{"marker":"long-retry-after"}` | 429, `headers` `{"Retry-After":"30"}`, `text` "CI mock: rate limited for 30 seconds."; 200 `text` "Answered after a capped wait." |
| `tool-loop.json` | `{"marker":"tool-loop"}` | 200 `toolUse` `{"name":"list_productions","input":{}}`, which repeats until AI Hub's maximum iterations |
| `summary.json` | `{"marker":"summary"}` | 200 `text`: one line of JSON with all seven keys: `user_goals` "Keep the Orders production healthy.", `constraints` `[]`, `decisions` `["The CI mock summarized the earlier turns."]`, `facts_learned` `["check_status (toolu_mock_1) returned the CI mock's fixed status."]`, `tool_actions` `[{"tool":"check_status","input_summary":"no arguments","result_summary":"the CI mock's fixed status","state_change":"none"}]`, `open_questions` `[]` and `next_steps` `[]` |
| `summary-off-schema.json` | `{"marker":"summary-off-schema"}` | 200 `text` "The conversation was about the Orders production." |

`ci/mock/scenarios/B/.gitkeep` is new and empty. `B/` gets no scenario until 4.4.

**3. The hosted tests.**
- **`ci/mock/test/scenarios.test.mjs`, `server.test.mjs` and `constants.test.mjs` (new): rows 1–18.**
  - **Isolation:** each test makes its fixture tree in `fs.mkdtempSync(os.tmpdir() + ...)` and removes it. Each file starts its own server on `127.0.0.1:0` with its own log folder.
  - **`constants.test.mjs`:**
    - it reads `MOCKKEY` from `src/ocutalon/cls/OcuTalon/Agent/*.cls` and `src/bridge/cls/OcuTalon/BridgeExample/**/*.cls` (absent today; that is 13.1's folder);
    - it reads the tool names from the `Parameter X = "y";` lines of `src/ocutalon/cls/OcuTalon/Tools/Names.cls`, leaving out `RELEASE1`;
    - it reads `PREFIX` from `src/bridge/cls/OcuTalon/Bridge/Compaction.cls`;
    - it reads `WEB_INPUT_PATTERN` from `ci/units.sh` and checks, through `new RegExp`, that every file it read matches.
  - Each test's name names its row.
- **`docker/tests/test-mock.sh` (new).** From the repository root it runs `node --version`, then `node --test ci/mock/test/*.test.mjs`, and exits with node's status. It follows `test-web-build.sh`'s wrapper shape (header comment, `root`, `cd`).
- **`ci/units.sh`:**
  - `WEB_SCRIPTS="web-build mock"`;
  - `WEB_INPUT_PATTERN` gains `docker/tests/test-mock\.sh$`, `src/ocutalon/cls/OcuTalon/Agent/[^/]+\.cls$`, `src/bridge/cls/OcuTalon/BridgeExample/.+\.cls$`, `src/ocutalon/cls/OcuTalon/Tools/Names\.cls$` and `src/bridge/cls/OcuTalon/Bridge/Compaction\.cls$`;
  - the pattern's comment says the mock's tests read these.
- **`.github/workflows/ci.yml`:** the placeholder step is replaced, in place after "Unit tests", by:
  ```yaml
  - name: Mock tests
    if: steps.changes.outputs.web == 'true'
    run: bash docker/tests/test-mock.sh
  ```
  The header comment says the web job runs the mock's tests.
- **`docker/tests/test-ci-config.sh`:**
  - L490 pins the step name "Mock tests" with `bash docker/tests/test-mock.sh`;
  - L522's `mock` sample becomes one whose mock step runs `echo mock`, which the wiring rule must flag;
  - L524 keeps `mock`;
  - the header, L19–20, is updated.

  Task 5 makes this file's preflight changes.
- **`docker/tests/test-ci-changes.sh`:** new `paths_case` rows.
  - `web=true`: `ci/mock/scenarios/A/refusal.json`, `docker/tests/test-mock.sh`, `src/ocutalon/cls/OcuTalon/Agent/Chat.cls`, `src/ocutalon/cls/OcuTalon/Tools/Names.cls` and `src/bridge/cls/OcuTalon/Bridge/Compaction.cls`.
  - `web=false`: `src/ocutalon/cls/OcuTalon/Tools/Result.cls`.
  - The row for `docker/tests/lib-live.sh` stays false.

**4. The CI override and its pin.**
- **`ci/compose.ci.yml`:** exactly the following, under a header comment updated to say what the mock is and that the judges' file names neither it nor this file:
  ```yaml
  name: ocutalon-ci

  services:
    iris:
      environment:
        OCUTALON_EVAL: ${OCUTALON_EVAL:-0}
        OCUTALON_MODEL_BASE_URL: http://mock:8080/v1/
      volumes:
        - mock-log:/opt/ocutalon/mock-log:ro
    mock:
      image: node:24.15.0-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d
      pull_policy: missing
      command: ["node", "/mock/server.mjs", "--log-dir", "/log"]
      volumes:
        - ./ci/mock:/mock:ro
        - mock-log:/log
      healthcheck:
        test: ["CMD", "node", "/mock/health.mjs"]
        interval: 2s
        timeout: 2s
        retries: 15
      stop_grace_period: 2s

  volumes:
    mock-log:
  ```
- **`docker/tests/test-compose-file.sh`:**
  - `ci_file_is_exact` becomes the form above.
  - `ci_adds_no_port_file_or_key` is split into checks that pass only when:
    - there is no `ports`, `env_file`, `container_name`, `build`, `privileged`, `network_mode` or `extra_hosts` anywhere;
    - no key variable appears anywhere (`ANTHROPIC|TELEGRAM|API_KEY|_TOKEN`);
    - `image:` appears once, in the `mock` block, as `node:<x.y.z>-slim@sha256:<64 hex>`;
    - `command:` appears only in the `mock` block.
  - The service-name, top-level-name, `config --quiet` and CON-3 checks stay as they are.

**5. The recipe: `ci/iris.sh`.**
- **The comments.** The header (L4) and `preflight`'s comment now say: the IRIS base image is never pulled; the mock's public image is pulled once per machine and kept.
- **`preflight`:**
  - It reads the `image:` of the `mock` block of `ci/compose.ci.yml` with awk (never `docker compose config`).
  - When `docker image inspect --format '{{.Id}}' <ref>` fails, it runs `docker pull <ref>` up to 3 times, pausing `${OCUTALON_PULL_PAUSE:-10}` and then three times that between tries.
  - If every try fails, it prints `FAIL the mock image <ref> could not be pulled after 3 tries (Docker Hub); no stack was started` and exits 1.
  - Every subcommand that starts a stack runs `preflight` first; add the call wherever it is missing.
- **`docker/tests/test-ci-config.sh`:** the browser-unit preflight stub, around L845, answers the mock image's `image inspect`, so the existing case still passes.
- **The hermetic case in `test-ci-config.sh`,** with a stub docker and `OCUTALON_PULL_PAUSE=0`:
  - `inspect` fails and `pull` fails twice, then succeeds: it passes, with 3 pull calls;
  - `pull` always fails: the FAIL line, exit 1 and no `compose` call;
  - the image is present: no pull.

**Task 0: measure** (Rule 22.2.5). It runs once Tasks 1–5 exist, before Task 6 is final.
- **Setup.** Use one throwaway, tag `v11a`, held up by a scratch script outside the repository that sources `docker/tests/lib-live.sh` (`live_start`, `live_first_start`), as 0.10's Task 0 did. Probe it with `iris_script OCUTALON` and the mock's log (`dc exec -T iris cat /opt/ocutalon/mock-log/requests.jsonl`), then run `ci/iris.sh teardown`.
- **Recording.** Record every value under Verification, "Task 0 measurements", and label anything you didn't measure `(inference)`.

1. **The image.** Check that `docker image inspect --format '{{index .RepoDigests 0}}' node:24.15.0-slim` still reads the digest recorded in the Code Map.
2. **One turn from IRIS.** Run:
   - `%AI.Provider.Create("anthropic", {"api_key":"ocutalon-ci-mock-key","base_url":"http://mock:8080/v1/","http_config":{"request_timeout_secs":10,"retry":{"max_retries":1,"attempt_timeout_secs":10,"initial_backoff_ms":500,"max_backoff_ms":2000},"custom_headers":{"x-ocutalon-mockkey":"triage"}}})`;
   - `%AI.Agent.%New(p)`, with `Model` `claude-haiku-5-5`;
   - `%Init()`, `CreateSession({"max_tokens":8000})` and `Chat`.

   Record:
   - whether the model lookup comes at `%Init` or at the first `Chat`;
   - the POST's `headerNames` and `keyLength`;
   - that `x-ocutalon-mockkey` arrived;
   - the body's top-level keys;
   - whether `system` is a string or blocks;
   - `GetStats().model_context_size`.
3. **Error texts.** Record the exact `<%AICore>ProviderError` texts for the mock's 400 (sampling), 401 (no key), 500 (no scenario) and 529, and whether a 400 or a 401 is retried (count the log lines).
4. **An empty key.** With `api_key` "", is the request refused before it is sent, or sent without `x-api-key` (the mock's 401)? Record it for 1.6; nothing here asserts it.
5. **The log file.** IRIS, running as `irisowner`, can read `/opt/ocutalon/mock-log/requests.jsonl` with `%Stream.FileCharacter`, and a line longer than 32,000 characters comes back whole.
6. **The back-off cap.** With `long-retry-after` and the full retry block, record the elapsed time; S18 measured about 2 s.
7. **Time.** Record the wall-clock of `ci/iris.sh shard lane-b` with the mock (Rule 21's baseline is 64 s) and the teardown time.

**HALT** `blocked` with `intent gap` if:
- (i) AI Hub can't reach `http://mock:8080/v1/` over the compose network. This names AD-22 and S3. Report it; no amendment is recommended, since S3 passed.
- (ii) `custom_headers` don't reach the mock. This names AD-22's mock-key route. The recommended amendment is in Design Notes.

If the key travels in a header other than `x-api-key`, the 401 rule follows that header. That is not a HALT: record a Rule 22 ruling in the Spec Change Log.

**6. The Integration test (Lane B, area `Contract`, shard `lane-b`).**
- **`src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` (new):** extends `%UnitTest.TestCase`. Its doc comment states the contract of the helpers, which either lane's tests may call (reading, not copying).
- **Parameters:**
  - `BASEURL` = `http://mock:8080/v1/`;
  - `DUMMYKEY` = `ocutalon-ci-mock-key`;
  - `LOGFILE` = `/opt/ocutalon/mock-log/requests.jsonl`;
  - `MOCKKEYHEADER` = `x-ocutalon-mockkey`.
- **The guard:**
  - a `Missing` property;
  - `OnBeforeAllTests` sets `Missing` to row 23's text unless `CheckBaseUrl($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"))` is OK;
  - a private `Guard()` (`$$$AssertTrue(0, ..Missing)`), called first in every test except `TestBaseUrlGuard`.
- **Class methods:**
  - **`CheckBaseUrl(url) As %Status`:** OK only for `BASEURL`.
  - **`Provider(mockKey As %String, httpConfig As %DynamicObject = "") As %AI.Provider`:**
    - it throws unless `CheckBaseUrl` of the environment is OK;
    - it builds `{"api_key": DUMMYKEY, "base_url": BASEURL, "http_config": {...}}`;
    - the default `http_config` is `request_timeout_secs` 10 and the full retry block of row 22, with the mock-key header added.
  - **`Arm(marker, remaining) As %Status` and `Remaining(marker, Output remaining) As %Status`:** `%Net.HttpRequest` calls to `/_mock/countdown`, at the host and port parsed from `BASEURL`.
  - **`LogMark() As %Integer`:** the log's current line count, 0 when the file is absent.
  - **`LogSince(mark, Output entries As %DynamicArray) As %Status`:** the lines after `mark`, each read whole (`ReadLine($$$MaxLocalLength)`) and parsed.
- **Tests, one per row:**
  - `TestBaseUrlGuard` (row 23);
  - `TestDefaultScriptByMockKey` (row 19: the agent's `MODEL` and `MOCKKEY` read with `$Parameter` from `OcuTalon.Agent.Triage`);
  - `TestMarker` (row 20);
  - `TestSamplingAndCapRefused` (row 21);
  - `TestCountdownAndRetryAfterCap` (row 22: `$ZHOROLOG` around `Chat`).
- **Fixtures.** Each marker key comes from `##class(OcuTalon.Bridge.Ids).NewRef()`. Sessions are never `%Save`d, and nothing is written to IRIS.
- **Loading.** Compile it on slot A only (`iris_doc_load`); run it only through `ci/iris.sh`.

**7. Recipe text.**
- **`_bmad/custom/skill-rules.md`, Rule 21:**
  - the Commands sentence "The base image must already be on the machine; it is never pulled" gains: the mock's image, `node:24.15.0-slim` pinned by digest, is pulled once per machine by `preflight`, and teardown keeps it;
  - the fresh-environment counts become "33 classes: 9 in `lane-a`, 24 in `lane-b`";
  - Hosted checks: the `web` job runs `docker/tests/test-mock.sh`.

  The timing rows are QA's, after the first CI run.

**Acceptance Criteria:**
- **AC1 (the service).** Given a throwaway that `ci/iris.sh` starts (the judges' file, the throwaway override and `ci/compose.ci.yml`), when the stack is up:
  - its `mock` container runs the pinned image, is healthy, publishes no port and holds `./ci/mock` read-only;
  - `iris` has `OCUTALON_MODEL_BASE_URL=http://mock:8080/v1/`, holds the log volume read-only at `/opt/ocutalon/mock-log`, and has no key variable and no published port;
  - `ci/iris.sh teardown` removes the container and the volume and keeps the image.

  (NFR-1, NFR-2, REL-4, AD-19, AD-22)
- **AC2 (Integration AC, Rule 1).** Given shard `lane-b` in a throwaway, when `OcuTalon.Test.Contract.Mock` drives AI Hub's Anthropic provider at the mock, then rows 19–23 hold.
  - The consumer is the provider path that Stories 1.1 to 1.9 ship on.
  - It gets each request's scenario reply.
  - The mock records each request with header names and the key's length only.

  (REL-4's same path, AD-22)
- **AC3 (CON-3).** Given the judges' `docker-compose.yml` and `docker-compose.dev.yml`, when `test-compose-file.sh` runs:
  - no non-comment line of either says "mock" or names a file of `ci/`;
  - both parse with the CI override (`config --quiet`);
  - `ci/compose.ci.yml` equals its new exact form.

  (CON-3, AD-23)
- **AC4 (hosted tests).** Given a push or a pull request, when the `web` job runs:
  - the step "Mock tests" runs `bash docker/tests/test-mock.sh` whenever the classifier's `web` output is true: for any change under `ci/`, to `docker/tests/test-mock.sh` or to a file the constants test reads;
  - a failing mock test turns the job red;
  - otherwise the job's "Skipped" step reports the skip.

  (AD-22, 0.7's classifier)
- **AC5 (Lane A adds only files).** Given a new file under `ci/mock/scenarios/A/`, when the mock starts:
  - it serves a valid file with no code change;
  - an invalid one stops the mock at start, naming the file and the rule, and the hosted tests go red on it first.

  (AD-22, AD-33)
- **AC6 (the pull).** Given a machine without the pinned image, when a `ci/iris.sh` subcommand would start a stack:
  - `preflight` pulls the image by digest, with up to 3 tries, before any stack starts;
  - a failure gives the FAIL line of Task 5 and exit 1;
  - with the image present, no pull happens.
- **AC7 (slot A never sends).** Given an IRIS whose `OCUTALON_MODEL_BASE_URL` isn't `http://mock:8080/v1/`, when `OcuTalon.Test.Contract.Mock` runs, then every test fails with row 23's text, and no provider is built. (Rule 21)
- **AC8 (REL-4).** Given the mock in every throwaway, when a stack is torn down, then the mock adds no wait, because it exits on SIGTERM (row 18). On the developer machine, `shard lane-b`'s wall-clock stays within 10 s of the 64 s baseline plus the new class's own time. (REL-4)

## Spec Change Log

Implement stage, October 20. Each ruling is one the standing grant (Rule 22) lets the stage make; the measurements behind them are under Verification, "Task 0 measurements". Neither tripwire of Task 0 fired: AI Hub reaches `http://mock:8080/v1/` over the compose network, and `custom_headers` arrive (`x-ocutalon-mockkey` is among the POST's header names and picked the scenario `triage`). The key travels in `x-api-key`, so the 401 rule needed no ruling.

- Rule 22 ruling: when AI Hub makes the model lookup -> Task 0.2 measured it at the first `Chat` of a process for a model (not at `%Init`, not at `CreateSession`), concurrent with the first POST, and cached per model id for the rest of the process (five chats in one process: one lookup for `claude-haiku-5-5`, one for `claude-sonnet-5-5`). So row 19 reads "the new log lines hold a 200 `GET /v1/models/claude-haiku-5-5`" from the log since the class began (`ClassMark`, set in `OnBeforeAllTests`), and the POST's fields from the log since the test's own mark; a test that runs after another that chatted with the same model would otherwise find no lookup. Consumers that assert on the lookup (1.2, 1.3, 1.8, 1.9) must do the same, and must find the lookup and the POST by method and path, because their order in the log varies. (rejected: calling `provider.GetModel` explicitly, which would not test AI Hub's own start path; a model id of its own per test, which row 19 forbids.)
- Rule 22 ruling: the log's `request` object -> the body with every other top-level key verbatim (`model`, `max_tokens`, `output_config`, ...), `messages` verbatim, `system` as `{chars, cacheControl}` (`null` when the body has none; the cache control is that of the last block that has one) and `tools` as `[{name, cacheControl}]` (`[]` when none), because Consumed-by 1.2 and 1.8 read `request.output_config`. (rejected: only the three keys row 14 names.)
- Rule 22 ruling: the log fields that row 14 names but does not fix -> `id` is the integer request number (the `<n>` of `msg_mock_<n>`, `req_mock_<n>` and `toolu_mock_<n>_<i>`); `/_mock/` calls are neither numbered nor logged, because the 2 s health check would flood the log; the model lookup logs `scenario` "model"; `marker` is the full marker without brackets (`refusal:t-1`); `step` is `k`; `countdown` is the remaining count after this request, `null` for an unarmed marker; `selectedBy` is `marker`, `prompt`, `mockkey` or `summarizer` (a `summary-*` variant is `marker`); `rejected` is a short reason (`no-key`, `sampling`, `max_tokens`, `stream`, `not-json`, `messages`, `no-scenario`, `bad-marker`, `unknown-marker`, `ambiguous-prompt`, `not-found`) on every request that the mock turns away by its own rules, the 401, the 404s and the 500s of selection included, and `null` otherwise.
- Rule 22 ruling: a `mockkey` scenario's name as a marker -> a marker picks only a scenario whose match is `marker`: `[[mock:triage]]` is a 500 "no scenario named triage", and `POST /_mock/countdown` for it is a 400. (rejected: any name picking any scenario, which would let a marker stand in for a missing header.)
- Rule 22 ruling: loader strictness beyond row 15 -> also refused: a `toolUse` reply with an error status; an unknown reply field; a `headers` value that is not a string; a `body` that is not an object or a list; a mock key with white space; a file at the top of the scenarios folder (a dotfile excepted) and a folder inside `A/` or `B/`. Each would leave a scenario unserved or meaningless. (rejected: ignoring them.)
- Rule 22 ruling: row 14's leak test -> the request that looks for a leaked key sends a plain dummy `x-api-key`, because the redaction would hide a key-like value that the code logged by mistake (the mutation "log the x-api-key value" stayed green while the test used a key-like key); a second request with a key-like key covers the redaction as well.
- Rule 22 ruling: row 19's agent -> `%AI.Agent` with `Model` read from `OcuTalon.Agent.Triage` and that class's `MOCKKEY` in the header, not an instance of `OcuTalon.Agent.Triage`, so that Story 1.1's instructions and toolsets don't change what this test sends. (rejected: `OcuTalon.Agent.Triage.%New(provider)`.)
- Rule 22 ruling: what `preflight` prints -> `PULL the mock image <ref> (try n of 3)` before each pull, and the last 3 lines of Docker's output before the FAIL line; the pauses are `OCUTALON_PULL_PAUSE` (default 10) and then three times that, and a value that is not a number counts as 10. Every subcommand that starts a stack already called `preflight` (`run_classes`, `cmd_live`, `cmd_group`, `cmd_build`), so no call was added. (rejected: silent pulls.)
- Shared surfaces updated, not on the spec's list (Rule 19): `docker/tests/test-compose-start.sh` (its owner and mode walk over `/opt/ocutalon` now prunes `/opt/ocutalon/mock-log` as it prunes `eval`, and a new check says the image holds no such folder; the first run of `live compose-start` failed there) and `docker/tests/test-demo-path-gate.sh` (its scratch tree copies `ci/compose.ci.yml`, which `preflight` reads; the first `bash ci/checks.sh` failed there). `docker/tests/lib-live.sh` is unchanged, as predicted: the mock lives in the fourth file and `up --wait` covers its health check.
- Found by a mutation (Rule 19): the hermetic `preflight` case stayed green when `preflight` returned 0 after three failed pulls, because its stub wrote its call log to `$tmp`, which `live_start` rebinds, and the case did not look at what ran next. The stub now writes to its own variable, and the case also requires that no `STACK` line is printed.
- Task 0's scratch script started the stack with `dc up -d --build --wait` (as `run_classes` does) and left it up for the probes; `live_first_start` is covered by the `live compose-start` and `live demo-path` runs, which passed.

## Review Triage Log

### 2026-10-20 — Review pass
- verdicts: 39 findings — high 0, medium 10, low 24, false 5, maybe-false 0
- findings (layer: BH blind-hunter, EC edge-case-hunter, VG verification-gap, IA intent-alignment):
  - `[medium]` `[patch]` BH1: the hosted tests pin the committed scenario set (16 scenarios, three mock keys, 11 tool names, 17 after an added file), so a Lane A or Lane B file turns the web job red — real: `scenarios.test.mjs` and `constants.test.mjs` compared literals, and AC5 says Lane A adds only files. Patched: the tests check for the story's named scenarios and derive counts from the loaded tree (`committed + 1`).
  - `[low]` `[reject]` BH2: a failed stack start does not show the mock's output — real but an invalid scenario file turns the hosted tests red before any IRIS job (AC5), and the fix adds a log branch to `run_classes`.
  - `[low]` `[reject]` BH3: status 1xx, 204, 205 and 304 load but cannot be delivered with a body — row 15 fixes the range at 100-599, and no scenario needs such a reply; changing it alters specified behavior.
  - `[medium]` `[patch]` BH4: `toolUse` lists, `body` replies and a replacing reply header have no server test, and `server.mjs`'s argument failures have none — the first three are real (Story 1.5 needs the list form) and are patched with the row 9 shapes test; the argument failures are low and rejected (the compose command line is fixed; no matrix row).
  - `[low]` `[patch]` BH5: the class comment says every test fails off the mock while `TestBaseUrlGuard` passes — real; the comment now says every test except `TestBaseUrlGuard`.
  - `[low]` `[reject]` BH6: `OCUTALON_PULL_PAUSE` is missing from the header that `usage()` prints — it is a test seam documented at `preflight`, and a developer meets the default only.
  - `[low]` `[reject]` EC1: an invalid header name or value with `delayMs` above 0 makes `writeHead` throw in the timer — needs a scenario author to write an invalid header and a delay together; the fix adds validation branches.
  - `[low]` `[reject]` EC2: status 1xx/204/304 with a body — same as BH3.
  - `[low]` `[reject]` EC3: a scenarios folder with no `.json` file starts healthy with zero scenarios — the committed set is checked by name in the hosted tests, so it cannot happen unnoticed.
  - `[low]` `[reject]` EC4: a `mockkey` with characters a header cannot carry loads but is never selected — mock keys are agent constants that `constants.test.mjs` ties to the classes.
  - `[false]` `[reject]` EC5: a user message with `tool_result` blocks and text resets the turn step — AI Hub's tool-result message carries no text (the recorded requests of the spike prototype, and Task 0.2's `chat` script reaching its second reply through AI Hub).
  - `[low]` `[reject]` EC6: `appendFileSync` failing after the countdown decrement spends an armed failure — needs a full or vanished disk on a throwaway; wontfix-theoretical.
  - `[low]` `[patch]` EC7: `OCUTALON_PULL_PAUSE=08` aborts the retry loop in octal arithmetic — real (mutation run: exit 1 after one pull, no FAIL line); patched with `pause=$((10#$pause))` and three cases (unset or empty, `abc`, `08`).
  - `[low]` `[reject]` EC8: AI Hub's own summarizer request may hit the NFR checks before the summarizer branch — AD-20 gives it a cap of 8,192 and no sampling, the order is the spec's, and the summarizer through AI Hub is Story 1.9's test.
  - `[low]` `[patch]` EC9: `TestBaseUrlGuard` passes under any URL — same as BH5.
  - `[false]` `[reject]` EC10: a spawned `server.mjs` binds all interfaces — the spec requires it (the compose network); the in-process servers of the tests bind 127.0.0.1.
  - `[low]` `[reject]` EC11: duplicates involving a defective file are reported only after the file is fixed — cosmetic; the file's own defects are all listed at once.
  - `[medium]` `[patch]` VG1: nothing tests that teardown keeps the pinned node image (AC1's third bullet) — real: `--rmi local` to `--rmi all` stayed green. Patched: the teardown stub lists `node:24.15.0-slim` and records the `down` arguments, and a new check requires the CI override, `-v` and `--rmi local`.
  - `[medium]` `[patch]` VG2: the reply rule for an armed countdown is pinned only for two replies at step 0 — real: `Math.min(1 + k, last)` to `Math.min(1, last)` stayed green. Patched: a three-reply fixture driven at steps 0 to 5, unarmed and armed (row 11).
  - `[medium]` `[patch]` VG3: loader rules with no failing fixture (unknown reply field, `toolUse` shapes, `headers`, `body`, `text`, white space in a mock key, an empty match value, a file that is not an object) — real: deleting the unknown-field check stayed green. Patched: 12 rows in `DEFECTS`.
  - `[medium]` `[patch]` VG4: the two spawned-server tests go red only by hanging — real: removing `fail(problems)` left the child listening and the test waiting. Patched: `helpers.mjs` has `exitWithin` (a bounded wait that names the output), waits on `close`, and each test kills its child in `finally`.
  - `[low]` `[patch]` VG5: the preflight pause default and the non-numeric fallback are never observed — real: the default 10 to 0 stayed green. Patched with the three cases of EC7.
  - `[medium]` `[patch]` VG6: five of the seven redaction alternatives are never exercised — real: deleting the `gh[pousr]_` entry stayed green. Patched: one run-time sample per alternative in row 14. A drift check against `test-boundaries.sh` was not added, since it would put that script in `WEB_INPUT_PATTERN`; the comment names the source.
  - `[low]` `[defer]` VG7: AC7's refusal path (`OnBeforeAllTests`, `Guard()`, `Provider`'s throw) is checked by hand only, because IRIS cannot set its own environment — already in `deferred:` from the implement stage.
  - `[medium]` `[patch]` VG-other-1: tests tied to the committed scenario set — same as BH1.
  - `[low]` `[patch]` VG-other-2: the spawned-server tests read stdio after `exit` — fixed with VG4 (`close`).
  - `[medium]` `[patch]` VG-other-3: row 14's "a key-like `x-api-key` is not logged" assertion could not fail, because redaction hides the value — real (Rule 19). Patched: it asserts the line's `keyLength` and that the line holds no `[redacted]`, which a logged key-like value would add.
  - `[low]` `[reject]` VG-other-4: `Mock.cls`'s model-lookup assertion needs a fresh IRIS process per class — by design: the Spec Change Log ruling records it, `run_class` starts a session per class, and consumers are told.
  - `[medium]` `[patch]` VG-other-5: `build()`'s `body` and `toolUse` list branches have no test — same as BH4.
  - `[low]` `[reject]` VG-other-6: `health.mjs` has no hosted test — it runs as the healthcheck in every throwaway, and `up --wait` fails when it fails.
  - `[low]` `[patch]` VG-other-7: the mutation lines of AC1, AC5 and AC7 cover one bullet each — lines added for the teardown bullet and the server's start refusal (below); AC7's remainder is the deferred item.
  - `[low]` `[defer]` IA1: row 23's environment path is exercised through `CheckBaseUrl` only — same as VG7.
  - `[low]` `[reject]` IA2: row 19 reads the model lookup from the log since the class began — by design: the Spec Change Log ruling (the lookup comes once per process).
  - `[false]` `[reject]` IA3: `Provider` checks the environment but passes the constant `BASEURL` — Task 6 specifies exactly that, and the check requires the two to be equal.
  - `[low]` `[reject]` IA4: row 12's hang-up is tested with a stub request and response — it drives `handle()` and emits `close` as Node does; the concurrent-request half uses a real server.
  - `[low]` `[reject]` IA5: row 10's summarizer shape never comes from AI Hub — rows 19-23 define the IRIS side, and Story 1.9 is the summarizer's consumer.
  - `[low]` `[reject]` IA6: of the default scripts only `triage` runs through AI Hub — rows 19-22 define it; Task 0.2 ran a `chat` turn with a tool use through AI Hub.
  - `[false]` `[reject]` IA7: container start, healthcheck, PID 1 and volume permissions are shown only by throwaway runs — those runs were made (`class`, both shards, `compose-start`, `production`, `install-upgrade`, `demo-path`).
  - `[false]` `[reject]` IA8: choices the intent leaves open (control calls unlogged, a `mockkey` scenario named as a marker is a 500, the pull amending 0.7's wording, `WEB_INPUT_PATTERN`) — descriptive, all logged as Rule 22 rulings; the hard-coded key set is BH1.

## Design Notes

**ADs:**
- **AD-22:** the mock's whole contract (what it serves, the selection, summaries, logs and state, the files and the lanes) and CI as built.
- **AD-19:** `OCUTALON_MODEL_BASE_URL` is set only by the CI override; plain HTTP to `base_url` ending `/v1/`; `custom_headers`.
- **AD-20:** the compaction prefix and the summary schema; the summarizer's cap of 8,192 and its lack of retries.
- **AD-8:** the timer (at most 110 s, so the held reply waits 120 s); the full retry block; the failure texts the scenarios produce.
- **AD-7:** no sampling parameters; a cap of at least 4,000.
- **AD-29 and AD-33:** the mock is Lane B's; `A/` is Lane A's.
- **AD-2:** the `ai-allowlist` admits `OcuTalon.Test`.
- **AD-23:** every compose file has its own `name:`; the judges' file stays as it is.
- **Spikes:** S2, S3 and S18. **Requirements:** NFR-1, NFR-2, NFR-5, REL-4, CON-1, CON-3 and CON-5.

No AC contradicts an AD's Rule. NFR-1, NFR-2, REL-4 and CON-3 are measurable as worded, so no tripwire fires.

**The reply rule** (golden example). `k` is the number of assistant messages after the newest user message with text, and is 0 for a summarizer request. `last` is the index of the final reply.
```
unarmed marker, prompt or mock key:      reply = replies[min(k, last)]
armed, remaining > 0:                    reply = replies[0]; remaining -= 1
armed, remaining = 0 (the countdown ran out): reply = replies[min(1 + k, last)]
```
So `rate-limited` unarmed answers 429 every time, AI Hub's retries included, because a retry is the same request and `k` stays 0. Armed with 2, it answers 429, 429, then 200. AI Hub's per-attempt retry consumes the countdown too, so 1.7 can count its own retries with `Remaining`.

**Rule 22 rulings** (question → choice (rejected: …)):

*The runtime:*
- Rule 22 ruling: **The runtime** → Node 24.15.0's standard library, in the official `node:24.15.0-slim` image pinned by its index digest, with `ci/mock/` bind-mounted read-only. (Rejected:
  - a port of the spike's Python, because the lead set Node and the hosted tests run on the `web` job's Node 24;
  - a built image, which needs a build step and a tag to clean up, where a mount needs neither;
  - `alpine`, which isn't on the developer machine and runs musl.)
- Rule 22 ruling: **The pull** → `pull_policy: missing`.
  - Teardown keeps the image (`--rmi local` skips it, and the tag pattern never matches `node:`).
  - `preflight` pulls it once, with 3 tries.
  - A pull failure (Docker Hub's anonymous limit or an outage) fails the job before any stack starts, with one line naming Docker Hub. It is an `infra` red: ledgered once, as a CI flake, and rerun (Rule 22.7).
  - Whether the runner already holds the image is unknown, and it may not be read over SSH; the first CI run pulls it `(inference)`.

*How a request picks its scenario:*
- Rule 22 ruling: **How the `MOCKKEY` reaches the mock** → the request header `x-ocutalon-mockkey`. The `Provider` step (1.1) adds it to each agent entry's `http_config.custom_headers` whenever `OCUTALON_MODEL_BASE_URL` is set. (Rejected:
  - reading the system prompt, which is selection by wording;
  - the model id, which is the same for all three agents;
  - a new environment variable, which is not an AD-19 home.)
- Rule 22 ruling: **The marker grammar** → `[[mock:<name>]]` or `[[mock:<name>:<key>]]`. The countdown and the test's log filter are keyed by the whole marker, so a test keeps its own state with a `NewRef()` key and no file of its own. The message's first marker wins, and a `[[mock:` that doesn't parse is a 500. (Rejected:
  - one scenario file per test, which multiplies files;
  - a separate `[[tag:]]` grammar.)
- Rule 22 ruling: **No default reply** → a request with no marker, no guide prompt and no known mock key gets a 500 that says why. (Rejected: the spike's "pong", which lets a test pass by accident.)
- Rule 22 ruling: **A guide prompt** → exact, case-sensitive containment in the newest user text message. Prompt scenarios are allowed only under `B/` (AD-22), a prompt may not contain another, and two matches give a 500.
- Rule 22 ruling: **The countdown** → it arms the scenario's first reply, as the reply rule above says. (Rejected:
  - a `countdown` field on replies, a change to the format the AC fixes;
  - a request counter, which is more state.)

  The control endpoint is `POST /_mock/countdown {marker, remaining}`, where `remaining` is 0–1000 or `null` to clear, plus `GET /_mock/countdown?marker=`.
- Rule 22 ruling: **Summarizer scenarios** → `summary` is the default. The transcript's last `summary-*` marker picks a variant, and a `summary-*` marker never steers a normal request. (Rejected:
  - a marker in the compaction prompt, which is an Epic 0 constant;
  - a header, which can't vary per test.)

*What the mock rejects and refuses:*
- Rule 22 ruling: **The key** → a missing or empty `x-api-key` gets a 401, as the API gives. (Rejected: accepting any request, which would hide a key placeholder that never resolved.)
- Rule 22 ruling: **Streaming** → `stream: true` gets a 400 naming it. AI Hub sent `stream` in 1 of the 172 recorded spike requests `(inference: a hand probe)`. (Rejected: SSE, about 40 lines nobody needs yet.)
- Rule 22 ruling: **Paths** → only `POST /v1/messages`, `GET /v1/models/<id>` and `/_mock/`. `/messages` without `/v1` gets a 404, because a `base_url` without `/v1/` is a misconfiguration (AD-19).
- Rule 22 ruling: **The `telegram` match** → reserved: the loader refuses it, naming Story 10.3, so no scenario can sit there unserved.

*The log:*
- Rule 22 ruling: **A log tests can read** → the mock's request log goes to `requests.jsonl` in the throwaway's named volume `mock-log`, which `iris` mounts read-only. Stdout gets the same line without `request`.
  - Messages are kept verbatim, because 1.3 checks where the user's text sits.
  - System text is kept by size, and tools by name (1.2, 1.9).
  - Key-like text is redacted.
  - The file is a log, not state: nothing in it changes a reply.

  (Rejected:
  - a request read-back through the control endpoint, which contradicts AD-22's "its only state is a per-test countdown";
  - stdout only, which would leave Lane A's IRIS-side tests in 1.2, 1.3, 1.6, 1.8 and 1.9 needing Lane B's files to read it.)

*The scenarios:*
- Rule 22 ruling: **Where they live** → the 1.6–1.9 scenarios and the three default scripts go under `A/` (Lane A's after Epic 0). `B/` holds only `.gitkeep` until 4.4.
- Rule 22 ruling: **The default replies:**
  - `triage` keeps the item for the digest, the safe outcome;
  - `diagnosis` reads the failed messages, then answers the codes of `eval/orders-date-format/case.json`, which 5.4 may adopt or rename;
  - `chat` lists the productions, then answers.

  Only the default scripts must use `OcuTalon.Tools.Names`. A marker scenario may name a test tool (1.5).

*The tests:*
- Rule 22 ruling: **Where the hosted tests run** → `docker/tests/test-mock.sh` in `WEB_SCRIPTS`, gated like the other web steps. `WEB_INPUT_PATTERN` gains the script and the files the constants test reads. (Rejected:
  - an always-run step, which needs Node set up ungated;
  - a checks-job script, where no Node 24 is set up.)
- Rule 22 ruling: **Where the Integration test lives** → `OcuTalon.Test.Contract.Mock` in the existing `Contract` area, so it rides `lane-b`. (Rejected:
  - a new `Mock` area, which edits `ci/units.sh`'s shards;
  - a live-script row, which runs host-side only and is slower.)

*The service:*
- Rule 22 ruling: **The address** → port 8080, plain HTTP, no published port, no `depends_on`. IRIS's start dwarfs the mock's (about 0.3 s), and `run_classes`' `--wait` covers its health check.

**Recommended amendment for Task 0's HALT (ii)** (the lead decides; Rule 5): the `MOCKKEY` travels in the body as `metadata.user_id` = `mockkey:<MOCKKEY>`, through the runner's session `extra_params`, which AI Hub merges into the body (spike). The mock reads that in place of the header, and AD-22's route sentence and 1.2's session config change with it.

**Owner-only (Rule 22.4), parked for the Contest Planner:**
- Owner-only: **The image's base.** Node.js is MIT, and the Docker image's own files are MIT. Its Debian bookworm-slim base carries system packages under copyleft licences (GPL and LGPL: bash, coreutils, glibc), as the IRIS base image's Ubuntu does `(inference)`. The image runs only in CI and developer throwaways; nothing of it is shipped, linked or redistributed.
  - The plan proceeds with it, since any Linux container image carries such packages.
  - Reversing it means changing the one `image:` line and its pin in `test-compose-file.sh`.
- Owner-only: **Docker Hub's anonymous pulls.** They need no account, no sign-in and no spend; CI forbids registry sign-in anyway.

**VETO WINDOW FYIs (Rule 22.3):**
- **The image.** A new third-party runtime image (Node.js, MIT), pinned by digest.
- **The mock-key header.** 1.1 will send `x-ocutalon-mockkey` wherever `OCUTALON_MODEL_BASE_URL` is set, the online demo's gateway included. It is a public constant and reveals nothing.
- **The log.** Request bodies are kept in CI throwaways' log volume, with key-like text redacted, and the volume is removed at teardown.

**Integration ACs (Rule 1):** AC2. The consumer is AI Hub's Anthropic provider in IRIS. The effects are the scenario replies and the logged requests, which rows 19–23 assert.

**Consumed-by (Rule 2):**
- **1.1:**
  - The `Provider` step writes `base_url` from `OCUTALON_MODEL_BASE_URL`.
  - It adds `x-ocutalon-mockkey`, the agent's `MOCKKEY`, to `http_config.custom_headers`.
  - From then on every runner in a throwaway reaches the mock.
- **1.2:**
  - the default scripts `triage`, `diagnosis` and `chat`;
  - from the log (`LogMark` and `LogSince`): `model`, `maxTokens`, `request.output_config`, `request.system.cacheControl` and `request.tools[].cacheControl`.
- **1.3:**
  - its marker scenarios under `A/` (`act` with confidence 0.12, `ignore`, `digest`);
  - `request.messages` in the log, for NFR-6's user-text check.
- **1.4:** a 403 "daily cost cap reached" marker scenario, a file under `A/`.
- **1.5:** a two-step tool script for test tools, under `A/`.
- **1.6:**
  - `refusal`, `max-tokens`, `empty`, `provider-error`, `invalid-reply` and `tool-loop`;
  - "the mock's log shows the request was never sent" means no log line carries the test's marker;
  - Task 0.4 records what AI Hub does with an empty key.
- **1.7:** `held-past-timer` (120 s), `rate-limited`, `overloaded` and `long-retry-after`, with `Arm` and `Remaining`.
- **1.8:**
  - `invalid-input` (`SessionBroken`);
  - from the log: `maxTokens` and `request.output_config` for a resumed session, and `request.messages` for the restored history.

  A reply that depends on the history is new behaviour, asked of Lane B under AD-33.
- **1.9:** `summary` and `summary-off-schema`; `request.tools[].name` per agent, from the log.
- **1.10 and 8.4:** markers under `A/` (1.10), and a guide prompt and a marker under `B/` (8.4). "Lists, then cancels by `Ref`" needs a reply that quotes the previous tool result: new behaviour, asked of Lane B under AD-33. It is not built here.
- **4.4 and 4.6:** the two guide prompts' scenarios, and the mailbox's marker scenarios, under `B/`.
- **5.4:** the diagnosis scenarios under `A/`; Lane A may change `diagnosis.json`.
- **Epic 9 (9.1–9.5):** evaluation runs against the mock on every push (the `OCUTALON_EVAL=1` job in `lane-a.yml`), with scenarios under `A/`.
- **10.3:**
  - the `telegram` match type, the Bot API endpoints and `OCUTALON_TELEGRAM_API_BASE`;
  - it lifts the loader's refusal, and loosens `test-compose-file.sh`'s `TELEGRAM` ban for that one variable.
- **11.1:** the demo path against the mock; specific outcomes are asserted only there.
- **12.1:** Lane A's Telegram scenarios, in 10.3's form.
- **13.1:** the bridge example agent's own `MOCKKEY` scenario under `A/`. The constants test already reads `src/bridge/cls/OcuTalon/BridgeExample/`.

**Consumes:**
- **0.6:** the `MOCKKEY` values, `OcuTalon.Tools.Names`, and `Bridge.Compaction`'s `PREFIX` and `Prompt`; the no-key start.
- **0.7:**
  - `ci/compose.ci.yml`, `ci/units.sh`, `ci/changes.sh`, `ci/iris.sh`, `lib-live.sh` and the `web` job;
  - the pins in `test-compose-file.sh`, `test-ci-config.sh` and `test-ci-changes.sh`.
- **0.4:** `Bridge.Ids.NewRef()`, `DecisionPayload` and `OUTCOME`.
- **0.10:** the throwaway mount pattern, and `Test.Demo.Production`'s guard pattern.
- **The spikes:** S2, S3 and S18, and the prototype.

**Reuse (Rule 2):**
- **The mock ports the spike's prototype** (`../spikes/mock/mock.py`): the marker reading, the tool step, the countdown, the summarizer bypass, the model object and the error bodies. It is a rewrite, not a copy: the lead set Node, and the prototype is outside the repository, in another language.
- **Extended or reused:**
  - `test-mock.sh` follows `test-web-build.sh`'s wrapper;
  - the three pins are extended in place;
  - `NewRef()` is reused for the marker keys.
- **Stated copies:**
  - `Test.Contract.Mock`'s `Missing` and `Guard()` repeat `Test.Demo.Production`'s 8 lines with another condition. The original is private, and a base class shared across areas for 8 lines would tie Demo to Contract.
  - The redaction regex copies `test-boundaries.sh`'s `key_like`, because one is a bash ERE and the other JavaScript.
- **New:** no HTTP helper exists in `src/`, so `Test.Contract.Mock`'s helpers are the shared ones.

**Ledger inbox:** the slice for this key is empty (checked at plan time).

**Spine updates for the lead (Rule 20; each `[AMENDED 2026-10-20, Story 0.11, Rule 22 ruling]`).** These make the planning artifacts newer than `epic-0-context.md`, so the pre-warm re-runs before the next plan.
- **AD-22 "What the mock serves":** add the 401 for a missing key, the 400s for streaming and for a body that isn't JSON, and the 404 for every other path except `/_mock/`.
- **AD-22 "How a request picks its scenario":**
  - the marker grammar with an optional test key, the first marker winning, and `summary-*` markers excluded;
  - the `MOCKKEY` in `x-ocutalon-mockkey`, added by the `Provider` step whenever `OCUTALON_MODEL_BASE_URL` is set;
  - no default reply (a 500);
  - the reply rule.
- **AD-22 "Summaries":** `summary`, plus `summary-*` variants picked by the transcript's last `summary-*` marker.
- **AD-22 "Logs and state":**
  - per request: the header names, the key's length, and the request with system text and tools reduced to size and names;
  - written to stdout and to `requests.jsonl` in the `mock-log` volume, read-only in `iris` at `/opt/ocutalon/mock-log/`;
  - key-like text redacted;
  - the countdown's endpoint and rule.
- **AD-22's file format:**
  - `status` is required, with exactly one of `text`, `toolUse` (`{name, input}` or a list) and `body`;
  - `headers`, `delayMs` (0–600,000) and `stopReason` are optional;
  - `prompt` scenarios go only under `B/`;
  - `telegram` is reserved until 10.3.
- **AD-22 "CI as built":**
  - the `mock` service, from the digest-pinned `node:24.15.0-slim`, with `ci/mock/` mounted and no build;
  - pulled once by `preflight` and kept by teardown;
  - `docker/tests/test-mock.sh` in the `web` job;
  - `OcuTalon.Test.Contract.Mock` in `lane-b`.
- **AD-19 "Endpoint overrides":** the `x-ocutalon-mockkey` sentence.
- **Stack, a new row:** "CI model mock runtime (Story 0.11; CI and developer throwaways only, never shipped) | Node.js 24.15.0 in `node:24.15.0-slim@sha256:4e6b70dd…` (Node.js MIT; the Debian bookworm-slim base packages under their own licences)".

**Time budget (REL-4; inference until Task 0.7 and the first CI run measure it):**
- **Per throwaway.** One more container from a local image, about 0.5–1 s, alongside IRIS's 52–57 s start (ARM) or 150–177 s (x64). `run_classes`' `--wait` covers the health check, about 2 s, inside IRIS's start. Teardown is unchanged: the mock exits on SIGTERM, and `down` stops the containers in parallel. Across 12 throwaways that is about 0 s of wall-clock.
- **The first runner run.** One pull, about 75 MB compressed for amd64, taking about 10–30 s; then it is cached.
- **New work.** The `lane-b` shard gains `Test.Contract.Mock`: about 3–5 s on ARM with its 2 s back-off, about 10–15 s on x64. The `web` job gains about 5 s.
- **The run.** It stays at about 25 minutes against REL-4's 30, and DW-21 is unchanged. No regrouping.
- **Developer throwaways.** Every one now starts a mock, at about 1 s, from the local image.

**Size and split line:**
- **Scope.** 4 small JavaScript modules (about 550 lines), 3 test files (about 500 lines), 16 JSON files, 1 IRIS test class (about 200 lines), 1 new script, and edits to 7 shell or YAML files.
- **The estimate.** One implement pass, comparable to 0.7.
- **The split, if the lead rules one.** Story 0.12 takes `OcuTalon.Test.Contract.Mock` (AC2, AC7, rows 19–23). 0.11 keeps everything else, the log volume included. 0.12's first consumer stays 1.1.

## Verification

**Runtime targets:**
- **Hosted-tier tests.** Run them on the host's Node, and once in the pinned image (Node 24.15.0) with `docker run --rm --network none` and a read-only mount of the repository.
- **Slot A**, `ocutalon-slot-a`: MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call. First, `iris_server_info` must show build 154.
  - Only `iris_doc_load` of `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls`, with flags `ck`.
  - Never `iris_execute_tests` of that class, and never `OCUTALON_MODEL_BASE_URL` on a slot.
- **Throwaways**, only through `ci/iris.sh` and Task 0's scratch script on `lib-live.sh`:
  - tag `v11a` (QA `v11q`, review `v11r`);
  - `OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`;
  - one stack at a time, then `ci/iris.sh teardown` with the same tag.
- **Nothing else.** No push and no `gh workflow run`. `ocutalon-aihub-test`, `ocupilot*` and `iris-community-edition` are never touched.

Every command finishes inside one foreground call (`timeout: 600000`). The environment below is `OCUTALON_RUN_TAG=v11a OCUTALON_LOCK_OWNER='epic=0 stage=implement'`.

**Commands:**
- `(loop)` `bash docker/tests/test-mock.sh`. Expected: exit 0, with every test of rows 1–18 passing in under about 15 s.
- `(loop)` `bash ci/checks.sh`. Expected: exit 0, including compose-file's new form, ci-config's wiring and preflight case, ci-changes' new rows, and boundaries' ASCII, path and key scans over `ci/mock/`.
- `(loop)` **Slot A load.** `iris_doc_load` of the new class, with no error or warning.
- `(loop)` **Build.** `bash ci/iris.sh build`, with the environment above. Expected: exit 0; `preflight` finds the image, or pulls it.
- **Throwaway units**, each `(loop)` with the same environment, one call each:
  - `bash ci/iris.sh class OcuTalon.Test.Contract.Mock`. Expected: `CLASS OcuTalon.Test.Contract.Mock passed`, 5 tests, no `SKIP`.
  - `bash ci/iris.sh shard lane-b`. Expected: exit 0, 24 classes passed.
  - `bash ci/iris.sh teardown`. Expected: nothing of `-v11a-` is left, and `docker image inspect --format '{{.Id}}'` of the pinned reference still succeeds.
- `(once)` **The pinned image.** `docker run --rm --network none -v "$PWD:/repo:ro" -w /repo node:24.15.0-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d bash docker/tests/test-mock.sh`. Expected: exit 0 on Node v24.15.0.
- `(once)` **Both orders.** `node --test --test-concurrency=1 ci/mock/test/*.test.mjs`, then `node --test --test-concurrency=1 $(ls -r ci/mock/test/*.test.mjs)`. Expected: both exit 0.
- `(once)` **Task 0**, steps 1–7, each its own call.
- `(once)` **Other units with the mock present:**
  - `bash ci/iris.sh shard lane-a`: 9 classes, unchanged;
  - `live compose-start`, `live production`, `live install-upgrade` and `live demo-path`: each exits 0. The recreates keep the mock and `check_no_key` holds. Record `FIRST-START`.
- `(once)` **Fresh-environment check** (Rules 19 and 21), one per call: `shard lane-b`, then `shard lane-b --reverse`; then `teardown`.
- `(once)` **The mutations below.**

**Shared surfaces:**
- **`ci/compose.ci.yml`,** in every throwaway: the `mock` service, `OCUTALON_MODEL_BASE_URL` and the log volume on `iris`. `test-compose-file.sh` pins it exactly.
- **The scenario folders** `ci/mock/scenarios/A/` and `B/`. Names, mock keys and prompts are unique across both folders, and Lane A adds files.
- **The control endpoint's countdown state,** keyed by the full marker and test-unique through `NewRef()` keys.
- **The mock's `requests.jsonl`,** one per throwaway. A test reads only the lines after its own `LogMark()`, or the lines carrying its own marker.
- **`ci/units.sh`** (`WEB_SCRIPTS`, `WEB_INPUT_PATTERN`) and its pins in `test-ci-config.sh` and `test-ci-changes.sh`.
- **The `web` job's step list.**
- **`ci/iris.sh`'s `preflight`** and its stubs in `test-ci-config.sh`.
- **Rule 21's counts:** 33 classes, 9 in `lane-a` and 24 in `lane-b`.

No test depends on another. A test's countdown is keyed by its own marker, so tests never share mock state. Each hosted test file starts its own server on port 0 with its own temporary folder.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, observe red, revert, and confirm `git status --short` and `git diff --stat` are unchanged):
- **AC1:** drop `./ci/mock:/mock:ro` from `ci/compose.ci.yml` → `test-compose-file.sh` red at the exact form. `class OcuTalon.Test.Contract.Mock` is red too, because the stack fails `--wait` when the mock can't start.
- **AC2:** have `mock.mjs` read the mock key from `x-mock-key` → `TestDefaultScriptByMockKey` red (500, no scenario), and row 8 red.
- **AC3:** add a `  mock:` service to `docker-compose.yml` → "compose: no non-comment line says mock" red.
- **AC4:**
  - drop `mock` from `WEB_SCRIPTS` → `test-ci-config.sh` red (units and wiring);
  - drop the `Compaction` alternative from `WEB_INPUT_PATTERN` → `test-ci-changes.sh` red at its new row, and row 16's pattern check red.
- **AC5:** let the loader accept `telegram` → row 15's reserved case red.
- **AC6:** have `preflight` return 0 after three failed pulls → the new `test-ci-config.sh` preflight case red.
- **AC7:** let `CheckBaseUrl` accept any value → `TestBaseUrlGuard` red.
- **AC8:** remove the SIGTERM handler → row 18 red.
- **Key rows:**
  - remove the sampling check → row 3 and `TestSamplingAndCapRefused` red;
  - make the countdown never decrease → row 11 and `TestCountdownAndRetryAfterCap` red;
  - check the summarizer after the markers → row 10 red;
  - log the `x-api-key` value → row 14 red, and `TestDefaultScriptByMockKey`'s no-key-in-the-file assertion red.

### Mutations observed (implement stage, October 20)

Each was applied, observed red, reverted, and `git status --short`, `git diff --stat` and the SHA-256 of every changed or new file were compared with a snapshot taken just before: byte-identical every time. The hosted ones run against the files of the working tree; the IRIS ones ran in a throwaway tagged v11a (`Test.Contract.Mock` loaded and run in it, the mock restarted after each change).

- mutation: AC1: dropped `./ci/mock:/mock:ro` from `ci/compose.ci.yml` → `test-compose-file.sh` FAIL "ci: the file is exactly the mock's wiring"; and `ci/iris.sh class OcuTalon.Test.Contract.Mock` → "container ... mock-1 exited (1)", "FAIL OcuTalon.Test.Contract.Mock: the stack did not become ready".
- mutation: AC2: `MOCKKEY_HEADER` of `mock.mjs` changed to `x-mock-key` → `server.test.mjs` row 8 red; in the throwaway `TestDefaultScriptByMockKey` red with "API error: [api_error] CI mock: no scenario: no marker, no guide prompt and no known mock key".
- mutation: AC3: added a `  mock:` service to `docker-compose.yml` → `test-compose-file.sh` FAIL "compose: no non-comment line says mock".
- mutation: AC4: dropped `mock` from `WEB_SCRIPTS` → `test-ci-config.sh` FAIL "units: the test scripts, the shards and the areas" (the wiring rule stays green, because `ci.yml` still has the step); dropped the `Compaction` alternative from `WEB_INPUT_PATTERN` → `test-ci-changes.sh` FAIL "classifier: the compaction prompt runs web and iris", and `constants.test.mjs` red at "row 16: every file that these tests read matches WEB_INPUT_PATTERN".
- mutation: AC5: `if (type === 'telegram') {` of the loader changed to `if (false) {` → `scenarios.test.mjs` red at "row 15: the reserved telegram match is refused".
- mutation: AC6: `preflight` changed to `return 0` after the third failed pull → `test-ci-config.sh` FAIL "preflight: pulls that always fail gave exit 1, 3 pull(s), 5 docker call(s) ...; wanted the FAIL line, exit 1, 3 pulls, no stack" (the first version of the case stayed green; see the Spec Change Log).
- mutation: AC7: `CheckBaseUrl` changed to accept any value (`Quit $$$OK`) → `TestBaseUrlGuard` red on every refusal it expects ("'' is refused", "'http://mock:8080/v1' is refused", and the rest).
- mutation: AC8: removed the SIGTERM handler from `server.mjs` → `server.test.mjs` row 18 red (the child ends by the signal, not with status 0).
- mutation: key rows: `if (sampling.length > 0) {` changed to `if (false) {` → row 3 red, and `TestSamplingAndCapRefused` red ("a sampling parameter raises a provider error", "which says Invalid input", "and names temperature", and the log check).
- mutation: key rows: `countdowns.set(label, remaining - 1)` changed to leave the count → row 11 red, and `TestCountdownAndRetryAfterCap` red ("Rate limit exceeded: CI mock: rate limited for 30 seconds").
- mutation: key rows: the summarizer check made to yield to a non-summary marker of the transcript → row 10 red.
- mutation: key rows: `x-api-key`'s value added to the log entry → row 14 red, and `TestDefaultScriptByMockKey` red at "the log file never holds the key".

### Task 0 measurements (implement stage, October 20; throwaways tagged v11a, one at a time)

The scratch scripts (outside the repository) started one throwaway with `ci/compose.ci.yml` through `ci/iris.sh`'s functions (`preflight`, `live_start`, then `dc up -d --build --wait`), left it up, probed it with `iris_script OCUTALON`, `dc exec` and the mock's log, and `ci/iris.sh teardown` removed it. Provider settings are those of Task 0.2 (dummy key, `http://mock:8080/v1/`, the full retry block, `x-ocutalon-mockkey: triage`). Measured on the developer machine (Apple silicon, Docker 29.7.2, Node 26.8.1 on the host, 24.15.0 in the image).

1. **The image.** `docker image inspect --format '{{index .RepoDigests 0}}' node:24.15.0-slim` reads `node@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d`, the digest of the Code Map. `docker image inspect --format '{{.Id}}'` of the full pinned reference succeeds locally, so `preflight` pulled nothing. In the stack: the mock container's `Config.Image` is the pinned reference, it is healthy when `up --wait` returns (51 s, the IRIS start), publishes no port (`PortBindings` is `{}`), mounts `./ci/mock` at `/mock` with `rw=false` and the volume at `/log` rw, runs `node /mock/server.mjs --log-dir /log` as PID 1 and uid 0 on Node v24.15.0. The `iris` container has `OCUTALON_MODEL_BASE_URL=http://mock:8080/v1/`, 0 key variables, no published port, and the volume at `/opt/ocutalon/mock-log` with `rw=false` (`touch` there fails with "Read-only file system"). Teardown removed the containers, the volume and the network and kept the image (2.2 s).
2. **One turn from IRIS.**
   - The model lookup comes with the first `Chat` of the process for that model, concurrent with the POST (their order in the log varies): `%Init` made no request, and the lookup arrived after `CreateSession` had returned and 1 ms before the POST `(inference: the first Chat sends it)`. Within one process, five agents with new providers sent one lookup for `claude-haiku-5-5` and one for `claude-sonnet-5-5`: the lookup is cached per model id.
   - The POST's `headerNames`: `x-api-key`, `anthropic-version`, `content-type`, `accept`, `anthropic-beta`, `x-ocutalon-mockkey`, `host`, `content-length`; the lookup's are the same without `content-length`. `keyLength` 20. `x-ocutalon-mockkey` arrived, and the scenario `triage` was picked by `mockkey`. A capture listener inside the mock container (port 8081, not the mock) showed `anthropic-version: 2023-06-01` and `anthropic-beta: prompt-caching-2024-07-31`.
   - The body's top-level keys: `max_tokens`, `messages`, `model`, plus `system` when the agent has a system prompt, plus `temperature` when `extra_params` holds it (it is merged at the top level); no `stream`, no `tools` without tools, no `metadata`. The user message is one text block.
   - `system` is a string for a 27-character prompt, and one text block with `cache_control` `{"type":"ephemeral"}` for a 29,200-character prompt.
   - `GetStats().model_context_size` is 1000000 (`{"current_context_tokens":50,"model_context_size":1000000,...,"total_interactions":1}`); `Extra.finish_reason` is `end_turn`; a `refusal` scenario gives `finish_reason` `refusal` with no exception.
   - With no tool registered, a `Chat` with the `chat` default script sent two POSTs (the `list_productions` tool use, then one for the text) and returned "The CI mock looked at the productions." `(inference: AI Hub gave the unknown tool an error result itself and sent it back as the second request's tool_result)`
3. **Error texts** (the exception's `Name` is `<%AICore>ProviderError`; each case sent one POST, so no 400, 401, 500 or 529 was retried):
   - 400, sampling: `ERROR <%AICore>ProviderError: Provider 'anthropic' error: Invalid input: CI mock: sampling parameters are not allowed (NFR-1): temperature`;
   - 400, cap: `... Invalid input: CI mock: max_tokens must be an integer of at least 4000 (NFR-2), got 3999`;
   - 401: `... error: API error: Authentication failed: CI mock: the request has no x-api-key header`;
   - 500: `... error: API error: [api_error] CI mock: no scenario: no marker, no guide prompt and no known mock key`;
   - 529 (`Retry-After: 1`): `... error: Rate limit exceeded: CI mock: overloaded.`
4. **An empty key.** With `api_key` "" the provider is created and the request is sent, with an empty `x-api-key` header (the name is in `headerNames`, `keyLength` 0). The mock answered 401 to the POST and to the model lookup, and AI Hub raised the 401 text above; nothing was refused before sending. For Story 1.6: an unresolved key placeholder fails at the first `Chat`, as "Authentication failed", after a request.
5. **The log file.** As `irisowner` (uid 51773), `%Stream.FileCharacter` `LinkToFile` and `ReadLine($ZUtil(96,39))` read the file (mode 0644, root's); a chat with a 55,092-character input made a line of 55,625 characters that came back whole and parsed with the input intact.
6. **The back-off cap.** `long-retry-after` armed with 1, the full retry block: the `Chat` took 2.0057 s and returned "Answered after a capped wait."; the log shows the 429 at :53.171 and the 200 at :55.175; `Remaining` was 0 afterwards. S18 measured about 2 s.
7. **Time.**
   - `ci/iris.sh shard lane-b` with the mock: 65.3 s wall-clock (the SHARD line says 63 s; READY at 51 s), reversed 65.4 s; Rule 21's baseline is 64 s, and the new class took 2.05 s, so the shard is within 10 s of the baseline plus the class. `shard lane-a` 56.0 s, 9 classes. `ci/iris.sh class OcuTalon.Test.Contract.Mock` 56.0 s (READY 52 s).
   - The teardown of a held stack, `ci/iris.sh teardown`: 2.2 s (the mock exits on SIGTERM; `stop_grace_period` is 2 s and was not used). A shard's own cleanup adds about 2 s.
   - `live demo-path` printed `FIRST-START engine=aarch64 build=1s ready=53s` (53 s before).
   - The hosted tests: 58 tests in 1.9 s of node time, about 2 s for `bash docker/tests/test-mock.sh`, on the host and in the pinned image.

### Implement stage results (October 20)

- `bash docker/tests/test-mock.sh`: exit 0, 58 tests. In the pinned image, `docker run --rm --network none -v "$PWD:/repo:ro" -w /repo node:24.15.0-slim@sha256:4e6b70dd... bash docker/tests/test-mock.sh`: exit 0 on Node v24.15.0, 58 tests. Both orders with `--test-concurrency=1`: exit 0 (58 tests each).
- `bash ci/checks.sh`: exit 0, all 12 scripts.
- Slot A (`server: ocutalon-slot-a`, `namespace: OCUTALON`, build 154, port 52790): `iris_doc_load` of `Test/Contract/Mock.cls` with flags `ck`: no error or warning (twice, the second time on the final file). Nothing else ran on a slot.
- `ci/iris.sh build`: exit 0 (preflight found the image). `ci/iris.sh class OcuTalon.Test.Contract.Mock`: passed, 5 test methods, no SKIP. `shard lane-b`: 24 classes passed, forward and `--reverse`. `shard lane-a`: 9 classes passed (the existing SKIP of `Install.Production` `TestStepHelpers` is unchanged). `teardown` after each: nothing of `-v11a-` left, and the pinned image still inspects.
- Live units with the mock present, each exit 0: `compose-start` (after the fix of its `/opt/ocutalon` walk), `production`, `install-upgrade`, `demo-path` (`FIRST-START engine=aarch64 build=1s ready=53s`), and also `build-inputs`, `storage-roundtrip`, `production-restart`, `audit`, `install-start`, `sign-in` and `bundle-folder`. `check_no_key` held in all of them.
- AC7 by hand in the throwaway: `OcuTalon.Test.Contract.Mock` run with `OCUTALON_MODEL_BASE_URL` set to `https://api.anthropic.com/v1/` and to `http://mock:8080/v1`: the four provider tests failed with "OCUTALON_MODEL_BASE_URL is not http://mock:8080/v1/: this class runs in throwaways and CI only (Rule 21)", `TestBaseUrlGuard` passed, and the mock's log gained 0 lines (see `deferred:`).

### Review patch pass (October 20)

The patches of the review are tests, a one-line fix in `ci/iris.sh` and a comment, so Task 0's measurements stand. Each new or changed pinning test was shown red against a mutation (applied, observed, reverted; `git status --short`, `git diff --stat` and the SHA-256 of every changed or new file were identical to a snapshot taken before each one).

- mutation: AC1 (teardown keeps the pulled image): `--rmi local` changed to `--rmi all` in `cmd_teardown` of `ci/iris.sh` → `test-ci-config.sh` FAIL "teardown: a project did not come down with 'down -v --rmi local --remove-orphans' and the CI override".
- mutation: AC5 (an invalid file stops the mock at start): `if (problems.length > 0) fail(problems);` of `server.mjs` removed → `scenarios.test.mjs` row 15 "the server lists every problem on stderr and exits 1" red after its 8 s bound, with "the server was still running after 8000 ms" and the output, and no child left running.
- mutation: AC5 (the loader names the rule): the unknown-reply-field check of `scenarios.mjs` made inert → `scenarios.test.mjs` "row 15: a reply with an unknown field is refused, naming the file and the rule" red.
- mutation: AC6 (the pause): `pause=$((10#$pause))` of `preflight` removed → `test-ci-config.sh` FAIL "preflight: OCUTALON_PULL_PAUSE='08' gave exit 1, 1 pull(s), pauses '08 '"; the default `10` changed to `0` → FAIL "OCUTALON_PULL_PAUSE='' gave exit 1, 3 pull(s), pauses '0 0 '".
- mutation: row 11 (the reply rule of an armed countdown): `Math.min(1 + k, last)` changed to `Math.min(1, last)` in `pickReply` → `server.test.mjs` "row 11: an armed countdown answers the first reply while it counts, then the reply of the turn step plus one" red.
- mutation: row 9 (a toolUse list): `build()` made to answer the first item of a list only → `server.test.mjs` "row 9: a toolUse list gives one block per item, a body reply is sent as written, and a reply header replaces a default one" red.
- mutation: row 14 (redaction): the `gh[pousr]_` alternative of `KEY_LIKE` deleted → `server.test.mjs` row 14 red at "each key-like alternative is redacted".

Results after the patches:
- `bash docker/tests/test-mock.sh`: exit 0, 72 tests (58, plus 12 loader rows, the shapes test and the steps test), on the host, in the pinned `node:24.15.0-slim` (Node v24.15.0, `--network none`), and in both file orders with `--test-concurrency=1`.
- `bash ci/checks.sh`: exit 0, all 12 scripts.
- Slot A `iris_doc_load` of `Test/Contract/Mock.cls`, flags `ck`: no error or warning. `ci/iris.sh build`: exit 0. `class OcuTalon.Test.Contract.Mock`: passed, no `SKIP`. `shard lane-b`: 24 classes passed in 66 s, and with `--reverse` 24 classes in 65 s. `shard lane-a`: 9 classes. `live compose-start`, `production`, `install-upgrade` and `demo-path` (`FIRST-START engine=aarch64 build=1s ready=53s`): each exit 0. `teardown`: nothing of `-v11a-` left, and the pinned image inspects.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 0.11 adds the CI model mock and wires it into every throwaway.
- `ci/mock/` is a Node 24 service with no dependencies. It answers `POST /v1/messages` and `GET /v1/models/<id>`, rejects sampling parameters and a cap under 4,000, and picks a scenario by marker, then guide prompt, then `x-ocutalon-mockkey`. It answers summarizer requests in AI Hub's schema, keeps a per-marker countdown behind a control endpoint, and logs header names and the key's length only.
- Sixteen scenario files sit under `ci/mock/scenarios/A/` (the three default scripts and the marker scenarios of Stories 1.6 to 1.9), and `B/` holds a `.gitkeep`.
- `ci/compose.ci.yml` adds the `mock` service (the digest-pinned `node:24.15.0-slim`, `ci/mock` mounted read-only, no port) and the `mock-log` volume that `iris` reads at `/opt/ocutalon/mock-log`; `ci/iris.sh` `preflight` pulls the image once per machine with up to 3 tries.
- 72 hosted node tests run through `docker/tests/test-mock.sh` in the `web` job; `OcuTalon.Test.Contract.Mock` (5 tests) drives AI Hub's Anthropic provider at the mock and rides shard `lane-b`.
- Neither Task 0 tripwire fired: AI Hub reaches the mock over the compose network, and `custom_headers` arrive. The measurements are under Verification.

**Files changed.**
- `ci/mock/mock.mjs`, `scenarios.mjs`, `server.mjs`, `health.mjs`: the handler, the scenario loader, the entry point and the container health check.
- `ci/mock/scenarios/A/*.json` (16 files) and `B/.gitkeep`: the scenarios.
- `ci/mock/test/scenarios.test.mjs`, `server.test.mjs`, `constants.test.mjs` and `helpers.mjs`: the hosted tests and their spawned-server helper.
- `docker/tests/test-mock.sh`: the web job's wrapper.
- `ci/compose.ci.yml`, `ci/iris.sh`, `ci/units.sh`, `.github/workflows/ci.yml`: the service and volume, the image pull, the web scripts and input pattern, the "Mock tests" step.
- `docker/tests/test-compose-file.sh`, `test-ci-config.sh`, `test-ci-changes.sh`: the pins of the new form, the preflight and teardown cases, and the classifier rows.
- `docker/tests/test-compose-start.sh`, `test-demo-path-gate.sh`: the owner and mode walk skips `mock-log`, and the gate's scratch tree copies `ci/compose.ci.yml` (found by the first runs; logged in the Spec Change Log).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls`: the Integration test and its helpers.
- `_bmad/custom/skill-rules.md`: Rule 21's three items (the mock image pull, 33 classes, the web job's mock tests).

**Review findings.** 39 findings from four layers, all in `## Review Triage Log`.
- **Patched (11 entries, 8 of them medium):** the hosted tests no longer pin the committed scenario set; `toolUse` list, `body` reply and header replacement are tested; the armed-countdown reply rule is tested with three replies; 12 loader defect rows; bounded waits, `close` and a kill in the spawned-server tests; a falsifiable key-like `x-api-key` check and a sample per redaction alternative; the teardown keeps-the-image check; the preflight pause read in decimal and its default and fallback cases; the `Mock.cls` comment; mutation lines for the new pins.
- **Deferred (1, low, already in `deferred:`):** AC7's refusal path is checked by hand only, since IRIS cannot set its own environment.
- **Rejected, with reasons on their rows:**
  - BH2 (mock output on a failed start; the hosted tests catch a bad file first), BH3 and EC2 (status 1xx/204/304, which row 15's range allows), BH6 (the pause knob is documented at `preflight`), EC1 (an invalid header with a delay), EC3 (an empty scenarios folder), EC4 (a header-unsafe mock key), EC6 (a full disk), EC8 (the summarizer through AI Hub is 1.9's), EC11 (cosmetic ordering of duplicate reports), VG-other-4 (the lookup needs a fresh process, by ruling), VG-other-6 (`health.mjs` is run by every healthcheck), IA2, IA4, IA5 and IA6 (the test surface the spec's rows 10, 12, 19 and 22 define);
  - false: EC5 (AI Hub's tool-result message carries no text), EC10 (the spec requires all interfaces), IA3, IA7 and IA8 (the spec or the throwaway runs settle them).

**Follow-up review recommended: true.** Eight medium entries were patched (two or more), all in new test code that only its author has read since the patch: `ci/mock/test/helpers.mjs`, the shapes and steps tests, the 12 `DEFECTS` rows, the redaction samples and the teardown and preflight cases of `test-ci-config.sh`. Each is shown red by a mutation above. The unverified risk is a test that passes for the wrong reason, not product code.

**Verification performed.** The `(loop)` lines and the `(once)` lines of `## Verification` ran after the last patch, as listed under "Review patch pass". The IRIS-side mutations of the implement stage (the dropped mount, `x-mock-key`, `CheckBaseUrl`) were not repeated, because `Mock.cls` changed in a comment only. The first CI run on the self-hosted runner is the platform evidence and is the lead's.

**Residual risks.**
- The first CI run pulls `node:24.15.0-slim` on the runner once `(inference)`; a Docker Hub failure is an infra red with the `FAIL the mock image` line.
- Stories 1.2, 1.3, 1.8 and 1.9 that assert on the model lookup must read it from a class-level log mark and find it by method and path (the lookup comes at a process's first `Chat` and is cached).
- Rule 21's timing rows are QA's, after the first CI run.
