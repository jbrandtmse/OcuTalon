# Epic 1 Context: Every item gets an attention decision you can audit and afford

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Build the bridge's decision core (Lane A) on Epic 0's contracts. It has three declarative AI Hub agents on Claude Haiku 5.5, one agent-runner operation per agent on AI Hub's own adapter, and the `Decide` process. With it, every item gets exactly one recorded attention decision (outcome, reasons, confidence, four token counts and cost), and every model request and tool call is an agent step in Visual Trace. An unusable reply takes a fallback route that never acts, conversations survive restarts, and OcuTalon starts safely with no model key. The epic ends by keeping digest-outcome items in a durable per-session store, which the step-2 daily digest will summarise. Every later epic calls models only through this pipeline. The bridge must also run on its own, in a production with none of OcuTalon's channels or web app.

## Stories

- Story 1.1: Every agent runs on Claude Haiku 5.5 through the Config Store
- Story 1.2: Agent runners send every request under the model rules
- Story 1.3: Decide records exactly one attention decision per item
- Story 1.4: Every turn and decision carries its tokens and cost
- Story 1.5: Every model request and tool call is an agent step in Visual Trace
- Story 1.6: An unusable reply takes the fallback route, and OcuTalon starts with no key
- Story 1.7: Timeouts and rate limits end every decision on time
- Story 1.8: Conversations survive restarts
- Story 1.9: No model request goes over 100,000 tokens (compaction moved to Story 30.1)
- Story 1.10: The chat agent sets, lists and cancels reminders
- Story 1.12: Items saved for the digest are kept for it
- (Story 1.11 moved whole to Story 30.2.)

## Requirements & Constraints

- **Model rules.** With only `ANTHROPIC_API_KEY` in `.env`, every agent uses `claude-haiku-5-5`. No request sets `temperature`, `top_p` or `top_k`. The output cap is 8,000 tokens and never below 4,000. Tests run against the CI mock.
- **Keys** come only from the environment. A key never appears in a Config Store entry, a saved AI session, a setting, the event log, an agent step, a log line or an error detail. With no key, every production item still runs and every decision falls back with `no_key`.
- **One decision per item**, unique on (item, kind). A repeat returns the recorded decision and makes no model call. The outcomes are `ignore`, `digest`, `tellnow` and `act`. Confidence (0 to 1) is recorded but never changes the outcome. A user-written item answered `ignore` or `digest` is recorded as `tellnow`, so digest items only ever come from untrusted items.
- **Fallback and time.** An unusable reply is recorded as `tellnow` with `Fallback` and its reason, and it triggers no tool, fix or approval. Every decision finishes, or falls back, within `Decide`'s timer (60 s by default; a timer over 110 s is refused).
- **Size and cost.** No request goes over 100,000 input tokens: an oversized one takes `too_large` and is never sent. The tool results of one model step pass at most 10,000 tokens together, and a cut result says so. Tokens and cost are recorded per turn and per decision, never per step.
- **Prompt safety.** The user's text always reaches the model as a user-role message. Untrusted content is quoted and labelled with its source. Every request starts with a preamble giving the local time and zone. No tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL.
- **Durability.** AI sessions, conversation links and digest items survive restarts, in the private database on the durable volume. Decisions, and the digest items with them, are kept 90 days by default.
- **The digest store (Story 1.12).** When an item's decision is `digest`, the store keeps:
  - the session,
  - the item id,
  - the decision ref,
  - the source channel,
  - the code-written one-line summary,
  - the time.

  The store notifies nobody, publishes no live event and keeps each `ItemId` once. It is read for one session since a given time, newest first. That read is what the step-2 digest's "saved for later" part (digest items since the last digest, with a count and a summary) consumes.

## Technical Decisions

- **Pipeline.** The path is caller → `OcuTalon.Bridge.Process.Decide` → runner → answer to the caller only. `Decide` sends nothing else except `AgentStep` messages to `AgentSteps`. The request kinds go `decide` → `TriageAgent`, `diagnose` → `DiagnosisAgent` and `turn` → `ChatAgent`; `tool` uses no model. The `ReplyFilterClass` runs on model text before anything is recorded. HostSink events fire after commit, and a failed one is logged and never fails `Decide`.
- **Runners** are `OcuTalon.Bridge.Operation.AgentRunner` on `OcuTalon.Bridge.Adapter.Agent`. Only runners call `Chat`, and pool size is the concurrency cap. The session config is built in code from `OcuTalon.Bridge.Data.ModelFamily` and is never stored. The same config object is passed on create and on every `OpenSession`. Renderer, policy and tool classes make no `%AI` call beyond their base classes and run no Python; build 154 deadlocks or crashes otherwise.
- **Classification of failures** happens in one method, in a fixed order: precheck → timeout → rate limit or error → reply checks. Any case the platform can't tell apart is `unusable`. A late reply is never passed on, but the runner still writes its `Usage` row.
- **Agent step labels.** A tool's readable step label is a class parameter: `STEPLABEL<NAME>` for one tool of a multi-tool class, else `STEPLABEL` for the class, else the generic "Running a tool". A label never holds arguments or model text.
- **Tool classification (new convention).** A built-in tool declares its classification as class parameters, following the same naming rule as step labels:
  - `CLASSIFICATION<NAME>` (`safe` or `risky`);
  - `READONLY<NAME>` (1 or 0);
  - `TRUSTEDOUTPUT<NAME>` (1 or 0).

  A class with several tools uses the `<NAME>` forms per tool; otherwise the bare names apply to the whole class. The governance gate reads these, and an undeclared tool counts as unclassified, which is treated as risky.
- **Saved conversations.** The runner saves a linked AI session only after a `Chat` that completed with an untainted context, whether or not the reply was late. A tainted turn is never saved.
- **Tools** return a dynamic object or plain text through `OcuTalon.Tools.Result`, never a pre-encoded JSON string. They take no session argument: the `SessionRef` comes from the bridge context. They change state only through `OcuTalon.Core.Commands.Submit` (origin `tool`, with an `IdempotencyKey`).
- **Bridge boundary.** `OcuTalon.Bridge` references no other OcuTalon package, and a CI check enforces this. `src/bridge/` must load and run on its own.
- **DigestStore (Story 1.12).**
  - **The item.** `DigestStore` is `OcuTalon.Digest.Store`, a Lane A business operation. Today it is an Epic 0 stub (`Parameter STUB = 1`, answering "not implemented"), and this story makes it real. Production-class edits stay inside Lane A's region, between `<!-- lane A: begin -->` and `<!-- lane A: end -->`.
  - **The input** is Lane B's `OcuTalon.Msg.ItemDecision`. Its fields are `ItemId`, `SourceItemId`, `OwnerRef`, `Channel`, `Summary`, `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason`, plus the optional `CatalogKey` and `Slots`. Lane A never edits this class; ask Lane B to append any property it needs.
    - `OwnerRef` is a session's `Ref` or the literal `instance`. Evaluation decisions go to `EvalSink` and never reach this store.
    - `Summary` is code-written (at most 80 characters) and never model text.
  - **The table** is `OcuTalon.Digest.Data.Item`, which Lane A owns. The spine's ownership tables already list it, so it needs no spine update.
    - Like every non-bridge persistent class, it sets `Parameter DEFAULTGLOBAL` to `^OcuTalonP.<Short>`, registered in `src/short-names.tsv` (CI fails a duplicate).
    - It commits its compiler-generated `Storage` block. Storage is append-only: never rename, retype or remove a stored property, and CI diffs storage against the last release tag.
    - An SQL reserved-word property keeps its name and gets an `SqlFieldName`.
  - **Times and refs.** Times are stored as UTC ISO 8601 to the second (`YYYY-MM-DDThh:mm:ssZ`), so string order is time order. Times are rendered only through `OcuTalon.Data.Time`. Refs are 22-character base64url strings, and row ids never leave the server.
  - **References.** `OcuTalon.Digest` may reference `OcuTalon.Msg`, `OcuTalon.Data` and the bridge's shared APIs (bridge data is read-only). It must not reference `%AI` or `EnsLib.AI`.
  - **Retention** is declared through the area's `Purge(daysToKeep)` interface in the installer-step registry. A step class outside the run order only declares. The purge task that calls every declaration is Story 30.2's. Day counts come from the task property; no purge reads `OcuTalon.Data.Setting`.
  - **Logging and errors.** Hosts log with `$$$LOGINFO`, `$$$LOGWARNING` and `$$$LOGERROR`, use `%Status` throughout and `$$$ThrowOnError` inside methods, and log nothing secret.
- **Tests** are `%UnitTest` classes named `OcuTalon.Test.<Area>.<Subject>`. The spine's as-built shard split puts only Agent, Bridge and Install in `lane-a`, so check which shard a new `OcuTalon.Test.Digest` area lands in. Lane A extends the mock only by adding scenario files under `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- Chat speaks plain English in the first person. It uses no greeting, exclamation mark, emoji or hype word, and no class name, error code or stack trace unless asked. Asked to run a command, it says it can't and calls no tool.
- Each bridge `FallbackReason` maps to exactly one of the catalog's 11 fallback reasons. The bridge never renders user-facing text. Visual Trace shows decision fields and step summaries under plain names.

## Cross-Story Dependencies

- **Epic 0.** Epic 1 implements Epic 0's signatures and keeps `OcuTalon.Test.Contract.Ac`'s signature oracle green.
- **Story 1.12** needs only Epic 0's `ItemDecision` contract and the `DigestStore` stub; it doesn't call `Decide`. Its tests send a fixture `ItemDecision` straight to `DigestStore` until Lane B's Story 2.7 merges and `OutcomeRouter` forwards digest outcomes. Two later stories consume it:
  - Story 17.6 (the step-2 digest) reads the per-session "since" query;
  - Story 30.2's purge task calls its `Purge(daysToKeep)`.
- **Stand-ins until other epics merge:**
  - a fixture `OcuTalon.Tools.Watch`, until Story 5.4;
  - the pass-through reply guard, until Story 5.7;
  - the do-nothing HostSink, until Story 2.6;
  - a `CommandsIn` test double for the reminder verbs;
  - the reminder tools run as safe until Epic 3's gate lands.
- **Lane B consumes** `Busy`, `SessionBroken` and `Tainted` in `Conversation`, and Lane B's `SettingsOps` calls the Config Store merge method. Story 30.1 reads Story 1.9's compaction flag.
- **Before adding more time-zone tests,** fold Lane A's four copies of the process-zone save and restore into one test helper.
- **Lane B owns** `OcuTalon.Core`, `.Msg`, `.Schedule`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership` and the rest of `ci/`. Ask Lane B for changes there rather than editing them.
