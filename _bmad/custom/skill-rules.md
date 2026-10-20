# BMAD Skill Rules

Loaded as `persistent_facts` by every BMAD skill on activation (via `_bmad/custom/<skill>.toml`). Project-specific rules are appended under "Project-specific rules" at the end, numbered after Rule 20.

## Rule 1 — Integration ACs (`bmad-build-auto` / `bmad-build` planning step)

Every story spec that introduces a service, module, or shared component MUST include at least one Integration AC — as a row in the spec's I/O & Edge-Case Matrix or an item under Tasks & Acceptance — of the form:

> *Consumer `X` reads from this service/module and produces observable effect `Y`.*

The integration AC must be testable by the consumer's automation tier (unit, integration, E2E, browser-MCP, API smoke), not by inspecting the introducing module's internal state.

A spec that introduces a service without naming any consumers must explicitly say so in an "Integration ACs" note under `## Design Notes` ("No consumers in this story; the first consumer will be Story X.Y."). Silence is not acceptable.

## Rule 2 — Consumed-by linkage and reuse (`bmad-build-auto` / `bmad-build` planning step; reuse also binds implement and `bmad-code-review`)

Every service-introducing spec carries a `Consumed-by:` list under `## Design Notes` naming downstream consumer stories by ID and purpose.

Every consumer spec carries a `Consumes:` list under `## Design Notes`, and its Integration ACs exercise the consumer against a real instance — not a mock. These live in the non-frozen Design Notes section so later amendments never fight the spec's frozen intent block.

**Extend, don't copy.** When a story adds a class, method, function, or helper that resembles an existing sibling, the spec names the sibling it extends under `## Design Notes`, or records why a copy is the better choice. The implementation prefers extending; a copy carries its stated reason in the spec or the commit message — never in a narrating code comment. Code review files an unjustified copy as a MED naming both locations, and a copy with a weak reason as a LOW; a copy the spec forces is `routed` to the named story that will unify it, never closed `by-design` (a terminal entry is never scheduled). A preference, not a ban: some copies are right. (Field report 2026-10-10: a blind quality scan across three model tiers found the same weakness under all of them — new code written as a near-copy of a sibling, one method repeating about 60 of its sibling's 70 lines — and review rarely flagged it, because each copy works.)

## Rule 3 — Real-runtime test evidence (`bmad-code-review`)

A code review MUST NOT approve a story whose code touches a user-facing surface unless the QA-generated test suite includes at least one test that exercises the deliverable against its real target runtime:

- UI / browser-deployed — browser-MCP or Playwright test asserting on observable DOM / render state.
- CLI / library — actual invocation with stdout / stderr / exit-code / produced-file assertions.
- Service / API — a real HTTP request with status code + response body + side-effect assertions.

This is distinct from the lead's manual per-story smoke, which runs *after* code review as a separate workflow gate. Rule 3 governs the *test artifacts* code review can inspect; the manual smoke is a later, independent check.

Pure non-user-facing stories (build pipeline, internal tooling, refactor) are exempt; note the exemption in the review. Missing real-runtime test evidence on a user-facing story is a HIGH finding.

## Rule 4 — Closing summary in the final message (`bmad-qa-generate-e2e-tests`, `bmad-code-review`, under `/epic-cycle`)

`bmad-build-auto` is exempt: its contract is the spec file itself — frontmatter `status` (`done` | `blocked` | `ready-for-dev`) plus the `## Auto Run Result` section (`Status:` / `Blocking condition:`). The lead reads the spec, never the agent's prose. Every other skill, when invoked under `/epic-cycle`, MUST end its final assistant message with these sections in order:

```markdown
## Files Modified
- <full path from repo root>
(or "(none)")

## Tests Added
- <full path from repo root>
(or "(none)")

## Decisions
- <one-line summary>
(or "(none)")

## Issues Encountered
- <one-line summary>
(or "(none)")
```

The closing summary is part of the agent's normal output. If the agent forgets the sections, the lead reconstructs the file list from `git status --short` — normal extraction.

If the skill cannot make confident progress for ANY reason — ambiguous ACs, missing prerequisite, a user-preference choice, an environment failure, or anything risking a stated constraint — halt BEFORE the closing summary and end with a `## Clarification Needed` section instead. State the question, what was tried, and what's blocking, in one paragraph.

Outside `/epic-cycle`, this rule does not apply — emit a normal completion summary.

## Rule 5 — NFR tripwire response (`bmad-build-auto`, `bmad-code-review`)

If an NFR is found to be unmeasurable, mathematically impossible, internally contradictory, or otherwise un-implementable as worded:

- **`bmad-build-auto`** cannot amend planning artifacts mid-run. HALT with status `blocked` and blocking condition `intent gap`, naming the NFR, why it is un-implementable, and the amendment you recommend. The lead amends the planning artifact (`prd.md`, `architecture.md`, or `epics.md`) in place, records original-vs-amended wording with rationale in the spec's `## Spec Change Log` and an inline `[AMENDED <date> — see the story change log]` marker at the amended text, re-runs the epic-context pre-warm (the amendment makes the planning artifacts newer than `epic-<N>-context.md`), resets the spec's `status` (`draft` to re-plan, `in-progress` to re-implement), commits, and re-dispatches on the spec path.
- **`bmad-code-review`** files an NFR worked around with code comments + `deferred-work.md` instead of a planning-artifact amendment as a HIGH finding.

**Who decides the amendment.** The lead — in a parallel run, the epic-runner IS the lead for its epic, and its own epic's story blocks in `epics.md` plus everything under `implementation-artifacts` are always within its authority (Rule 11 governs concurrency between epics, not this). Two tiers:

- **Apply and report** (no halt): an amendment that preserves the product promise — restating an observable or measurement so it is reachable/measurable while the intent is unchanged, correcting a wrong file/API/name the AC cites, and root-file bookkeeping another rule already mandates (an attribution row before a port lands, a shipped notices file kept consistent with `ATTRIBUTIONS.md`). Apply it under the discipline above and list it under `amendments:` in the story's `committed` entry (sequential) or the completion contract (runner) for post-hoc review.
- **Ask first** (`## Clarification Needed` / intent-gap halt to the user): anything that changes what the product does — narrowing, dropping, or deferring an AC or scope to another story/epic; touching another epic's story blocks, epic boundaries, or dependency statements; a new third-party dependency or licence; a numeric target with product meaning. These are the decisions a human owns; "I verified it is unreachable" is the evidence for the question, not a licence to answer it.

Either tier: if the amendment changes what an AD's Rule, a convention, or a Stack row says — or settles something the spine lists under `## Deferred` — the spine is updated in the same commit (Rule 20); a planning artifact that contradicts the spine is a conflict, not an amendment. If the amendment retitles a story, its sprint key changes: re-run `SPRINT_PLAN generate`, then `LEDGER slice <old key>` → `append … owner=<new key> by=<gate> note=retitled` for every entry, in the same commit (Rule 17 (1)).

Do NOT work around with code comments + `deferred-work.md`.

## Rule 6 — AD violations are HIGH severity (`bmad-build-auto`, `bmad-code-review`)

The project's architecture decisions are the `### AD-n — {decision}` blocks (**Binds / Prevents / Rule**, optionally tagged `[ADOPTED]`) of its **architecture spine** — `ARCHITECTURE-SPINE.md`, written by `bmad-architecture` under `{planning_artifacts}/architecture/<run-folder>/` — together with its Consistency Conventions and Stack tables. The spine is BMAD's decision registry; this method has no separate ADR folder, and `/epic-cycle` keeps none. The lead resolves *which file* is the spine once per epic — the newest `ARCHITECTURE-SPINE.md` with frontmatter `status: final`, else the newest spine, else (pre-spine projects) any `*architecture*.md` under the planning artifacts, else none — logs `spine_resolved`, and passes its path into every spawn prompt. That is a read-side lookup only; writes to the spine happen at the moment of each decision (Rule 20), never batched to epic end.

An AC implementation that violates an AD — wrong tool stack, wrong architectural pattern, a dependency in a forbidden direction, a contradicted Rule — is a HIGH-severity finding, not a LOW deferrable.

`bmad-build-auto` must consult the spine for any architectural or methodology decision referenced in the story's ACs / spec Design Notes — at planning time (record the governing `AD-n` ids under `## Design Notes`) and at implementation time (match the implementation to each AD's Rule).

`bmad-code-review` must:

1. Cross-check each AC against the spine's ADs — the ids recorded under `## Design Notes` first, then any AD whose `Binds:` covers the story's area.
2. Verify that AD-constrained implementations match the AD's Rule.
3. File mismatches as HIGH. Auto-resolve inline where reasonable; otherwise pause for the lead.

(The identifiers `adr_verifications_complete`, `adr_constrained_acs`, and the parallel kit's `adr_verifications` lock stage keep their spelling — read them as "architecture-decision verifications" — so existing logs and `parallel.yaml` files stay valid.)

## Rule 7 — Sub-agent tool inventory is harness-inherited (all skills)

Sub-agents spawned by `/epic-cycle` inherit whatever MCP namespaces and tools are mounted on the harness running the lead. There is no project-local mechanism to add a tool just for sub-agents.

**Implication:** AD-tooled AC verifications (browser-MCP smokes, performance traces, audits) are placed on the **lead**, not on sub-agents. Sub-agent MCP propagation is best-effort defense-in-depth, not the primary gate. Note that `bmad-build-auto` itself spawns an implementation subagent and parallel review subagents (one nesting level below the stage agent); they inherit the same harness inventory.

## Rule 8 — Test discoverability (`bmad-qa-generate-e2e-tests`)

Generated tests MUST be discoverable by the project's default test suite — (a) correct naming convention, (b) not excluded by ignore files, (c) not tagged in a way that opts them out of the default run.

A test that exists but does not run in the default suite is invisible to CI and to the next story's regression check. Undiscoverable tests are a HIGH finding on subsequent code review.

## Rule 9 — Unattended menu protocol (`bmad-code-review`, `bmad-qa-generate-e2e-tests`, under `/epic-cycle`)

Interactive BMAD skills contain checkpoints — numbered menus, "halt and wait for confirmation" steps (`bmad-code-review` has four on its happy path plus a large-diff chunking offer; `bmad-qa-generate-e2e-tests` opens by asking what to test). `bmad-build-auto` has none (it is the unattended variant by design — its only exits are the HALT statuses); `bmad-build` is never a pipeline stage. When an interactive skill is invoked under `/epic-cycle`:

- If the spawn prompt **pre-answers** a checkpoint, take the pre-answered option and continue without waiting for a human.
- If a checkpoint is **not** pre-answered, it is a genuine decision point — stop and emit `## Clarification Needed` (Rule 4). Never guess, and never sit waiting for input that cannot arrive.
- **Exception — `/bmad-retrospective`:** deliberately human-in-the-middle even under `/epic-cycle`. Its checkpoints, party-mode dialogue, and WAIT points are NEVER pre-answered, and it is never invoked with `-H` / `--headless`. It runs lead-side, so every elicitation reaches the user directly.

Outside `/epic-cycle`, checkpoints elicit the user normally.

## Rule 10 — Submodule worktree discipline (all skills, under `/epic-cycle`)

Inside a provisioned epic worktree: NEVER run `git submodule update` (it resets gitlink-mounted submodules to the recorded SHA and discards work in progress); NEVER create or remove git worktrees yourself (the orchestrator's `new-epic-worktree.sh` / `remove-epic-worktree.sh` own that lifecycle); commit early and push per story inside submodule branches so no work is ever unpushed at teardown time.

## Rule 11 — Footprint discipline: concurrency is not authority (epic-runners, under `/epic-cycle`)

The footprint (`paths_hint` + `submodules` in `_bmad/custom/epic-dependencies.yaml`) answers one question — **what might collide with another epic running at the same time** — and the orchestrator lists the **contended** paths (the footprints of every epic that could run concurrently with yours: any epic that neither depends on yours nor is depended on by it, transitively) in the spawn prompt. Authority is a different question, answered by the runner's role: **the runner is the lead for its epic**, and always owns its epic's durable artifacts — everything under `implementation-artifacts`, and its own epic's story blocks in `epics.md` (Rule 5 amendments, Story X.0 insertion, the burn-down story charter are all things this workflow requires the runner to do).

So: (a) your footprint and your epic's artifacts — edit freely; (b) a path outside your footprint that no contended epic owns — you may edit it, and you MUST report it under `footprint_extensions:` in the completion contract (the orchestrator re-checks overlap at the merge gate); (c) a contended path, an undeclared submodule, another epic's story blocks, epic boundaries or dependency statements — `## Clarification Needed`, never a judgment call. Amendments to planning artifacts follow Rule 5's two tiers (apply-and-report vs ask-first) and are listed under `amendments:` in the contract; the boundary is what forced orchestrator verification of each amendment and that verification stays — post-hoc, on the contract, instead of blocking.

(Field report 2026-08-29: five one-time "footprint widenings" in three stories, ~4 of 9 clarifications authorization-only — the concurrency footprint was being used to answer an authority question it was never designed for.)

## Rule 12 — Runtime lock (all skills, under `/epic-cycle`)

Stages named in `_bmad/custom/parallel.yaml` `runtime_locks[].stages` must hold the named lock for their duration (`all-runtime` is shorthand for every stage that executes project code against the shared runtime: `implement` — where `bmad-build-auto` runs the spec's Verification commands, its Matrix Test Audit, and its review layers' test runs — `qa`, `smoke`, `adr_verifications`): claim by creating `<worktree_base>/.coordination/locks/<name>.lock` (atomic create-new; content: `epic=<N> stage=<stage> acquired_at=<UTC>`), release by deleting it. If the lock exists, WAIT and retry with 30–90 s jitter — lock contention is normal, not an error. Never delete another epic's lock; a lock older than `stale_minutes` is reported to the orchestrator, which alone may sweep it after confirming the owner is dead. Log the lock lifecycle to the epic's cycle log — `runtime_lock_acquired` / `runtime_lock_released` on each transition, `runtime_lock_waiting` after the first minute of contention. A lock event that exists only in memory is invisible to telemetry and resume.

## Rule 13 — Working-directory, target, and read discipline (all skills and their internal subagents, under `/epic-cycle`)

Every spawned agent operates from the absolute working directory stated in its spawn prompt — in a parallel run that is the epic worktree root, never the main checkout. Verify `git rev-parse --show-toplevel` equals the stated path BEFORE reading state, editing files, or auditing. Skills that spawn internal subagents (`bmad-code-review`'s review layers `blind-hunter` / `edge-case-hunter` / `verification-gap` / `acceptance-auditor`, `bmad-build-auto`'s implementation-handoff subagent and its review layers, party-mode personas) must pass the path and the verification requirement — **together with every `🚫` prohibition in their own spawn prompt** (no `git commit` / `git push` / `git reset` / `git rebase`, nothing that mutates a remote or triggers CI or a deploy) — into every internal prompt, in the same breath. Only the layer that spawned a subagent commits; a subagent that reports having committed or pushed is a protocol violation — verify against `git log --branches --not --remotes` and `gh run list` instead of trusting the self-report, then halt to the layer above. (Incident 2026-08-28: a depth-3 handoff subagent received the working directory because Rule 13 mandated it and never received the git prohibition because nothing did; it committed, pushed, and triggered a live deploy.) Findings produced from the wrong checkout are invalid — discard and re-run; never report them. (Pilot 2026-07-10: an Acceptance Auditor defaulted to the main checkout, saw a clean tree, and reported a completed story as unimplemented — 5 false CRITICAL findings.)

**Runtime targets get the same discipline.** Every tool call and script that touches a runtime — a database, an app server, an emulator, a test instance — names its target explicitly; a tool that would silently fall back to a default target (a default connection profile, `localhost`, the first matching container) is configured to fail instead, because a misrouted call to a healthy, unrelated instance returns plausible results and no error. Verify the target's identity (name, port, version), not just its health, before acting. An agent stops, recreates, or tears down only runtime resources its own session created and can name from its own transcript; everything else is reported and left running — a banner or a generated file that looks like yours is not evidence. (Field report 2026-10-10: a call that named no target answered from an unrelated instance with the same namespace and credentials; a lead tore down the owner's second dev instance because a generated file's banner looked like its own.)

**Read once, then work from what you hold.** Read each document once and work from the copy in your context. Re-read only a file that may have changed since you read it — your own edit, a subagent's, a merge, or after your context was compacted — and then only the changed region, by line range, when you know it. Write a generated diff to one file and consult it by section rather than regenerating it. Large shared documents are read in the parts you need: the plan stage maps the story's `AD-n` blocks from the architecture spine; later stages read the ADs the spec's `## Design Notes` cites (and any whose `Binds:` covers the story's area), not the whole spine. Pass this rule into every subagent prompt with the working directory. (Field report 2026-10-10: a 115 KB spine was paged through by 59 agents in 36 hours, and stage contexts grew from about 57K tokens at spawn to 350K–450K. The saving is fewer agents reading each document, in the parts they need — few agents re-read anything.)

## Rule 14 — Source-text discipline: ASCII escapes, contract-only comments (`bmad-build-auto`, `bmad-qa-generate-e2e-tests`, `bmad-code-review`)

Author non-ASCII characters in source code via escape sequences (`'\u2026'`, `'\uFEFF'`), never as literal bytes — literal invisible or exotic characters are unreviewable in diffs and get silently normalized by editing tools. A literal non-ASCII byte in code is a review finding; the fix is the escape form. Prose files (markdown docs, comments where project convention allows) are exempt. (Pilot: a literal U+FEFF inside a BOM-strip regex and a raw U+2026 both required review patches; the reviewer's own Edit tool normalized the literal BOM away mid-patch.)

**Comments state the contract, never the history.** A doc comment says what the code promises and what it needs; review rounds, findings, and rework narration belong in the spec, never in code. Correct a wrong claim by replacing it, not by appending a correction. A test's header says what it pins and what it needs. A rework pass's `## Auto Run Result` covers only that pass, and once the spec carries the template's `oversized` warning, a re-open appends only the open items. (Field report 2026-10-10: one early story's spec reached 664 KB against a template that aims for 900–1,600 tokens; doc comments made up about a third of its classes' lines, about a hundred of them narrating review rounds — and reviewers then filed findings against the narration.)

## Rule 15 — Finding disposition bar (`bmad-code-review` + lead/runner, under `/epic-cycle`)

Every review finding is dispositioned AT REVIEW TIME — fix, or close with a named reason. "Deferred" is an explicit exception, never a default state. Each finding carries four fields: severity (high/med/low), **fix-risk** (low/med/high + one-line justification), footprint (in-story / in-epic / out-of-footprint), spec-status (clear / spec-bound). Disposition is a lookup, not a debate:

| Finding | Disposition |
| --- | --- |
| HIGH | Fix now (rework loop, at any review while iterations remain). Sole exception: explicit user waiver via `## Clarification Needed`, logged `high_waived`. |
| MED, fix-risk ≤ med, **in-story** | Fix now — by the reviewer, in the review pass, whenever it can (it may edit files; the unattended menu applies every patch). What it cannot patch re-opens the story for the ONE bounded MED iteration (shared with the Fix Pack) if this is the story's first review; on a re-review it is `routed owner=<a later story key in this epic that touches the area, else burndown>` with its `DW-n:` bullet — never a second re-open (exit condition below). "The story that will touch it later" is still not a disposition: routing under this row is a named owner with a planned bullet (Rule 17 (1b)). |
| MED, fix-risk ≤ med, **in-epic** (a file this story did not touch but a story of this epic owns) | `routed owner=<the story key in this epic that owns the file and has not yet reached cr_complete, else burndown>` with its `DW-n:` bullet now (Rule 17 (1b)) — that story's plan spawn receives it as inbox and its gate adjudicates it. Does not block story `done`. (Field report 2026-09-11: in-epic MEDs treated as fix-now were one of six rules that re-opened one story eight times.) |
| MED, fix-risk high OR out-of-footprint | `escalated` — ledgered (`owner=burndown` is the grammar's parking slot, not a promise of work) and decided by the user at this epic's **decision sheet** (SC-4). Does not block story `done`. |
| LOW two-way door (≈≤15 changed lines incl. its test, **in-footprint — in-story or in-epic**, spec-clear, suite green after) | Fix in-story: mechanical → reviewer patches; behavioral-but-trivial → `## Fix Pack`, ONE bounded dev iteration. Leftovers take the rows below. |
| LOW that is not a two-way door (bigger than a fix-pack item, or out-of-footprint) | Close `wontfix-accepted` at emission with `reopen_if=<observable probe>`. A LOW not worth 15 lines now is not worth a story later. **`burndown` never owns a LOW** (field report 2026-08-29: 17 of 30 burn-down entries were LOWs routed instead of closed). |
| Fix would alter AC'd/specified behavior (spec-bound) | Close `by-design` at emission; rationale recorded once. Reopens only via spec amendment (Rule 5 path or an X.0 product decision). |
| No realistic user-reachable failure (theoretical hardening) | Close `wontfix-theoretical` at emission + one line naming what would make it real. |
| Real MED/HIGH issue, out-of-footprint | `routed` — ONE canonical ledger entry per root cause; later sightings append an `occurrence`, never a new entry. Occurrence count is a priority signal. |
| Genuine product/preference call | `decision-pending` — batched to the user at this epic's **decision sheet** (SC-4), or earlier — as an `intent gap` at spec validation — the moment a later story's spec depends on it; decided once; terminal either way. |
| Closable only by a human (a playtest, a measurement on hardware the pipeline lacks, an authored asset, a ratification) | `decision-pending` with `note=human=<what>`. No story can close it, so it never takes `routed owner=burndown`; at the decision sheet it moves to `sprint-status.yaml` `action_items` (owner: the user) and the entry closes `dropped note=action_item`. |

**Exit condition (the loop must be able to end).** A story is re-opened by a HIGH, by a first review's unpatched in-story MED (one bounded iteration), by a Fix Pack (the same iteration), or by a failed smoke / red CI — nothing else. **A re-review that finds no HIGH closes the story:** the reviewer patches what it can, files every remaining MED with an owner under the rows above (`routed` / `escalated`), and sets `done`; MEDs alone never re-open a reworked story. A decision taken on a story that has already reviewed with no HIGH (a check-in answer, a decision-sheet call on one of its `escalated` / `decision-pending` entries) does not re-open it either: it lands as a `DW-n:` acceptance bullet on a named later story or the burn-down story. (Field report 2026-09-11: under "fix every in-footprint MED now" plus a whole-story re-review after every rework, "complete" was not a reachable state — 9 implement passes and 3 reviews on one story with zero HIGH since the third review.)

**Ledger grammar** (`_bmad-output/implementation-artifacts/deferred-work.md`). One entry per root cause:

```
### DW-<n>: <one-line summary>
- source: <spec file or stage> | severity: <high|med|low> | fix-risk: <low|med|high> | footprint: <in-story|in-epic|out-of-footprint>
- evidence: <why this is real — written once, at most 3 lines>
- <UTC> status=<status> owner=<story-key|burndown> by=<stage> note=<at most 120 chars>
- <UTC> occurrence=<story-key>
```

The body is written once. Everything after it is an append-only **trailer** of single-line, fixed-grammar annotations, and the **effective status and owner are whatever the LAST trailer line set** — an instrument reads the last line, never the prose, so an entry grows by one short line per transition and never by accretion. Statuses — non-terminal: `open | routed | escalated | decision-pending`; terminal: `by-design | wontfix-theoretical | wontfix-accepted | dropped | resolved-by:<story-key>`. `wontfix-accepted` = real and reachable but decided not worth pursuing; its `note=` MUST carry `reopen_if=<observable probe>`. `dropped` = invalid, duplicate, or not pipeline work (moved to `action_items` — the note says so). Every non-terminal entry has exactly one effective owner: a story key (the story that will close it) or `burndown` (this epic's burn-down gate, Rule 17 — for `routed` entries that is story-closable MED/HIGH work; for `escalated` / `decision-pending` entries it means "for the user at the decision sheet"); `owner=none` is illegal after the epic's `ledger_load` gate. All reads and writes go through `bash _bmad/scripts/ledger.sh <ledger> load | slice | show | new | append` — the lead and every agent use `slice`/`show`, never the whole file (a mature ledger is megabytes), and write only with `new` (canonical entry, next id) or `append` (one trailer line). Entries and trailer lines are only ever added, so the file stays union-merge safe. **Owners are validated on write:** `ledger.sh` refuses an `owner=` that is neither `burndown` nor a `development_status:` key in the sibling `sprint-status.yaml` (a retitled story changes its key; an entry on the old key is invisible to every gate — field report 2026-08-30: two entries orphaned with no error and no count anomaly). `LEDGER load` reports `owner_unknown=N` and marks such owners `UNKNOWN`; `LEDGER slice unknown` lists them; `LEDGER_OWNER_CHECK=off` exists for migration only. Consult `slice all` (grep the summaries) before filing: an adjudicated root cause gets an `occurrence=<story-key>` line, never a new entry. Terminal-entry notes are calibration context for future reviews. Anything the size of real work is a story, not a fix-pack item.

**Every entry is born with an owner.** (a) `bmad-build-auto` never writes the ledger — it records deferred findings in the spec frontmatter `deferred:` list. The **lead harvests** each new item after `dev_complete` via `ledger.sh new` with `by=harvest`: in-story footprint → `status=open owner=<this story key>` (adjudicated at this story's gate); in-epic → `status=routed owner=<the story key that will touch it>`; out-of-footprint → `status=routed owner=burndown`. (b) `bmad-code-review` files its `defer` findings the same way (`by=cr`) instead of the skill's default `## Deferred from:` bullets — the spawn prompt says so. (c) The lead/runner writes every disposition and occurrence. An item that never reaches the ledger is invisible to the drain — the harvest is mandatory, not best-effort.

## Rule 16 — Clean tree before every `bmad-build-auto` dispatch (lead/runner, under `/epic-cycle`)

`bmad-build-auto` requires a clean working tree at its step-01 version-control sanity check (HALT on a dirty tree / `version-control metadata not writable`) — that check runs on story-key and intent dispatches (the plan stage); a spec-path dispatch early-exits past it — and it commits only the reviewed-diff files at finalize, then verifies the whole tree is clean (HALT `finalization left repository dirty`). Either way, anything uncommitted when a dispatch starts ends the run. The lead's write-ahead bookkeeping (cycle log, `sprint-status.yaml`, `deferred-work.md`, a freshly planned spec, the epic-context cache, QA's test summary, saved patches) therefore MUST be committed before every dispatch: **write-ahead → bookkeeping commit → spawn.** Bookkeeping commits stage only `_bmad-output/implementation-artifacts/**` (cycle logs, `sprint-status.yaml`, `deferred-work.md`, `spec-*.md`, `epic-*-context.md`, `tests/test-summary.md`, `*.patch`) — never `.vscode/settings.json`, never source files — land on the epic branch under the SC-3 assertion, and use a `chore(epic-N): bookkeeping <story-id> <stage>` message. This requires `_bmad-output/implementation-artifacts` to be **tracked** (not gitignored) in the project — the pre-flight checks it. A `blocked` result naming either condition above is a missed bookkeeping commit until proven otherwise — fix the tree, do not re-spawn blindly.

**The one sanctioned source-file bookkeeping commit — the rework commit.** Before a rework re-dispatch (Rework Loop, Fix Pack, or a failed smoke that re-enters implement), QA's test files and the reviewer's applied patches are still uncommitted source changes (those spawns are forbidden to commit). The lead commits them together with the re-opened spec and the bookkeeping files as `chore(epic-N): rework <story-id> iteration <k>` on the epic branch (SC-3 assertion) so the tree is clean for the dispatch. That commit is part of the story's history, not a violation of this rule.

## Rule 17 — The drain is a stage, not a sentence (lead/runner, under `/epic-cycle`)

Every gate that files into the ledger is matched by a **logged stage that closes entries**; a ledger with writers and no drain is monotonic by construction (field report 2026-08-27: 0 → 1,588 entries in 114 days, never once shrinking, under a version of this workflow that filed at thirteen gates and read at one). The drain has four parts, each enforced by the cycle log:

1. **Born owned, and the owner exists** (Rule 15): a harvested or reviewer-filed entry carries `owner=<story-key>` or `owner=burndown` from its first trailer line, and the key is validated against the tracker at write time. The epic-start `ledger_load` gate re-owns any stray `owner=none` and repairs any `UNKNOWN` owner (`LEDGER slice unknown`): a retitle keeps the `<epic>-<story>-` prefix, so when exactly one tracker key shares the phantom's prefix the gate re-owns to it (`by=load note=retitle_repair`, logged `ledger_owner_repaired`); otherwise it HALTs — an entry no gate can reach is worse than a halt. A Rule 5 amendment that retitles a story re-owns that key's entries in the same commit.
1b. **Routed means planned.** Whenever an entry becomes `routed owner=<story key>` — at harvest, at `cr_complete`, at adjudication re-own, at the burn-down overflow, at the decision sheet — the party with authority over that story's block in `epics.md` (the lead/runner for its own epic; the sequential lead or the orchestrator, post-merge, for another epic) inserts `- DW-n: <summary> (ledger; routed by <gate> <date>)` under the receiving story's acceptance criteria, at most `routed_story_max` per story (default 6; `routed_max:` in `_bmad/custom/ledger.yaml`), the excess staying ledger-only and counted. The plan spawn for that story receives its full `LEDGER slice <key>` as an inbox and must address or decline each entry; spec validation checks that it did (`owned_ledger=`). Adjudication then checks a promise the story was shaped around instead of discovering a surprise it was never designed to fix (field report 2026-08-30: fifteen entries on one unplanned story; `ledger_adjudicated` can audit but not steer).
2. **Per-story adjudication** — `ledger_adjudicated`, mandatory between `cr_complete` and `smoke_complete`: every entry whose effective owner is this story's key is dispositioned against the story's DELIVERED scope (the diff since `baseline_revision` and its tests), never its title — `resolved-by:<key>` with evidence, re-owned to a named story key with the residual restated in the note, or terminal. `ledger.sh slice <key>` reads empty before smoke.
3. **Burn-down gate** — `ledger_burndown_complete|skipped`, mandatory after the epic's last `committed` and before `epic_status_done`. Its input is **story-closable work only**: the `routed`/`open` entries owned by `burndown` or by any of this epic's story keys. `escalated` and `decision-pending` entries are not work — they are counted (`to_decision_sheet=N`) and handed to the decision sheet (5), never re-owned or "decided" here. What remains is resolved or made terminal now, chartered into ONE burn-down story (**`N.<M+1>`, M = the highest existing story number under Epic N across BOTH `epics.md` and `sprint-status.yaml`** — the tracker can hold hotfix stories the epics file does not; gaps are irrelevant and `N.0` counts, so the number always sorts last and never collides. There is no conventional number: a fixed ninth-story number collided on every epic with nine or more stories, and "the next unused number" filled a gap below an existing story. An "Epic N burn-down" story that already exists — a resumed gate — is reused, never duplicated) of at most `burndown_story_max` entries (default 12) chosen by priority — severity, `occurrence=` count, low fix-risk first — that runs the full per-story pipeline before the epic closes, and the explicit **overflow** is re-owned to a SPECIFIC next-epic story key with the reason in the note and counted (`overflow=N`). "The next X.0" is not an owner; `burndown` ownership does not survive the gate. The gate reports the epic's drain ratio (`filed_this_epic` / `closed_this_epic`, from `LEDGER load` at `ledger_load` and now) so an under-sized drain is a number, not an inference.
4. **Story X.0 is a CLOSE, not a relabel:** its outcomes are `resolved-by`, own (X.0 itself or a named story key in this epic), or terminal. "Defer with rationale" does not exist.
5. **The epic-close decision sheet — `decision_sheet_recorded`, at the SC-4 merge gate.** Every `escalated` and `decision-pending` entry (any owner) is presented to the user in one sitting, each with a recommended disposition, and decided once: a product call becomes terminal or owned by a named story; a human-owned item (`note=human=`) moves to `sprint-status.yaml` `action_items` and closes `dropped note=action_item`. The human's decisions are written as trailer lines `by=merge_gate` — in the epic-branch checkout before the merge (sequential lead) or in the main checkout on the feature branch immediately after it (orchestrator; the ledger is union-merge, so ordering is irrelevant). A runner never decides these: it lists them under `decisions_for_user:` in its completion contract. This is the one place a human sees the ledger, and it is a gate the human already attends.

Resume refuses `smoke_complete` without (2) for that story and refuses `epic_status_done` without (3) for that epic; SC-4 does not ask the merge question until (5) has been presented. Planning sees the load: `ledger_load` runs before sprint planning and its counts go into the sprint-planning argument and the retrospective's context. A rule that says "periodic burn-down" with no stage that executes it never runs.

## Rule 18 — Containment: returned agents are finished, prohibitions reach every depth (all agents at all depths, under `/epic-cycle`)

1. **A returned agent is finished.** `SendMessage` to any agent whose `Agent` call has already returned is forbidden at every depth and in every direction — supervisor→stage, stage→its own internal subagent, peer→peer (the four named cases elsewhere are examples, not the list). To give a returned subagent more work, spawn a fresh one with the work written into the durable artifact. The single sanctioned `SendMessage` in the whole system is orchestrator→runner (parallel kit). On this harness `SendMessage` is not synchronous: a "re-engage the subagent with a synchronous message" instruction (e.g. `bmad-build-auto` step-04's patch handling) MUST be treated as "it cannot be re-engaged" — apply the patches yourself or spawn a fresh subagent.
2. **Return exactly once.** Every agent returns when its work is complete and never before; an interim or progress return while its own subagents are still working strands them as orphan writers whose supervisor has gone. If you cannot finish, HALT properly (blocked / `## Clarification Needed`) — that is a completion, not an interim.
3. **Every prohibition propagates to every depth that can violate it**, in the same breath as the working directory (Rule 13): the git/CI/deploy prohibitions, this rule, and any `🚫` in the spawn prompt go into every internal subagent prompt. The base kit additionally writes them into `bmad-build-auto`'s `implementation_handoff` and every review layer's `instruction` via `_bmad/custom/*.toml`, so depth-3 prompts carry them by construction. **Stateful test execution against a shared runtime is part of the propagated list:** one test class or suite per tool call (a suite that would not finish inside one call's cap, item 5, is split into classes or batches), wait for it to complete, never several test-runner calls in one message (they run concurrently and race on shared fixtures), never a re-submit on a client-side timeout. (Field report 2026-09-11: a depth-2 handoff subagent issued 18 test-runner calls in one message; an uninstall raced an install and left a database mounted with no file behind it, blocking seven test classes until a human restart. The project's own ledger had recorded the timeout re-submit race a day earlier — in a file no prompt reads.)
4. **Orphan protocol** — on evidence of a live writer whose supervisor has returned (two-point mtime sampling of the tree ~45 s apart; a stop/agent listing that shows a returned agent still running): do NOT re-spawn (that adds a writer); attempt `TaskStop` by the orphan's agent id or name; if it is refused, ask the top-level session — the sequential lead, or the orchestrator in a parallel run — to `TaskStop` it, because the main session can stop background agents that another agent spawned (Claude Code ≥ 2.1.203); only if that fails too, wait for quiescence (three consecutive unchanged samples). Then reconcile the tree into a single commit, log `protocol_violation` with what was observed, and escalate to the layer above. A completion notice for the orphan, wherever it surfaces, is a hint that it has stopped; the samples still decide.
5. **Synchronous is stated, never assumed.** The harness may run an `Agent` call in the background unless the call passes `run_in_background: false` — current Claude Code builds do, and the word "synchronously" in a prompt does not set the flag — so every `Agent` call at every depth passes `run_in_background: false` (several such calls in ONE message still run in parallel and resolve together). The one exception is the parallel kit's epic-runner spawn, whose orchestrator is built to wait on notifications. Every command, test run, and build runs in the foreground of its own tool call — never `run_in_background: true` on a shell call. A foreground call is capped by the harness's Bash timeout — 2 minutes by default and 10 minutes at most (`timeout: 600000`) unless the launch environment raises `BASH_MAX_TIMEOUT_MS` — and a call that reaches its timeout is not stopped but moved to the background, where it dies when the subagent that started it returns. So every test or build call passes `timeout: 600000` (or the raised maximum), and a run that would take longer is split into foreground calls that each finish inside the cap, never detached: one test class per call is always safe; a batch of classes is sized from the project's recorded per-class timings, if it keeps any (name the file under Project-specific rules), to finish in about 8 minutes. Nothing waits on `Monitor` or on a notification. The harness itself steers long waits to `Monitor`, and for a subagent that is the trap: a subagent that arms `Monitor` and stops has returned, whatever it meant — ending the turn IS returning, and that is item 2's interim return. No agent ends its turn while anything it started is still running. This item propagates to every depth exactly like item 3. (Field logs from one project, 2026-09-10 → 2026-10-08: 33 `protocol_violation` entries of one shape — a stage, handoff, review layer, or test sweep still running in the background after its owner returned — several of them "despite" a prompt that said synchronously; three full test sweeps died mid-run and two handoffs kept writing with no supervisor. The kit had never named the flag. Later the same day, with the flag stated, a handoff whose sweep could not fit in one 10-minute call ran it in the background, armed two `Monitor`s, and returned; the sweep died at 10 of 88 classes — foreground-only without a batching rule is an instruction that cannot be obeyed.)
6. `ListAgents` reports process liveness, not protocol state: a `SendMessage`-resumed agent shows `running` after it has returned. It is sufficient to tell whether a runner is alive or dead; it is NOT sufficient to establish that stage discipline holds — for that, ask the owning runner or sample mtimes.

(Incidents 2026-08-28, twice: a prohibition stated only at supervisor level was broken one level below it — first the git prohibition by a handoff subagent, then the `SendMessage` prohibition by a stage agent following the skill's own re-engage text. Each closed list was one direction short.)

## Rule 19 — Falsifiability and hermeticity: a test whose red has not been observed, or whose green depends on another test, is not evidence (`bmad-qa-generate-e2e-tests`, `bmad-build-auto` Matrix Test Audit, `bmad-code-review` `verification-gap`, the lead's ADR gate and pre-push check, under `/epic-cycle`)

For every acceptance criterion, its **pinning test** — the one assertion that stands for "this AC holds" — must be demonstrated to fail against a named **mutation**: state the smallest change to the code under test that would violate the AC, apply it, observe red, revert, confirm the working tree is byte-identical to before (`git status --short` and `git diff --stat` unchanged), and record it next to the test in the spec's `## Verification` as `mutation: <what was changed> → <which test went red>`. One demonstrated mutation per AC, not per assertion — the discipline scopes to the pinning test, not the suite.

Structurally unfalsifiable assertions are defects, not evidence: an expected value the type system makes the only possible value (`toEqual([])` against a `readonly never[]`), a subject that was never constructed (asserting a position with no ball spawned), two runs compared that both produce nothing, a test whose green depends on the defect it claims to guard against, a module with no executed test host. `verification-gap` flags every one of these and every AC whose pinning test has no recorded mutation. The lead's ADR gate may not record `result=pass` for an ADR-tooled AC without naming the mutation it applied — a pass with no mutation is `result=unverified` and is not a pass.

**Severity, and who writes the line (Rule 15 lookup).** An AC with **no pinning test**, or a pinning assertion that is **structurally unfalsifiable**, is a MED in-story finding with low fix-risk — the reviewer patches it in-pass or it takes the story's one MED iteration. A pinning test that **exists** but whose `mutation:` line is missing or stale is a **LOW the reviewer closes inside the review pass**: name the mutation, apply it, observe red, revert, and write or correct the line in the spec's `## Verification` (the one sanctioned spec edit in a review — it is a tracking section, not the intent) — it never re-opens a story. Whoever adds or materially changes a pinning test — QA, the implement stage, a rework pass — writes or updates its `mutation:` line in the same pass, so the next review finds nothing stale. (Field report 2026-09-11: 11 of 62 self-review mediums across nine implement passes were "no mutation line" on tests the previous rework had just changed — the loop manufacturing its own next round.)

**Hermeticity: a test passes for its own reasons.** Every test a story adds or changes creates and removes the state it asserts on, depends on no other test's leftovers and no run order, and waits for the system under test to signal that it is ready before acting. The plan names the shared surfaces the story changes — a `Shared surfaces:` line under `## Verification` listing any list, menu, roster, schema, or count that other tests assert on — and carries the standing criterion "every test added or changed passes on a fresh environment, in either order". The implement stage updates every existing test that asserts the old shape of a shared surface (search the test trees for it); QA writes self-contained tests; `verification-gap` and code review file a test that is not self-contained as a MED in-story finding. Before the story is pushed, the lead runs the story's added and changed tests on a fresh environment — rebuilt by the project's own recipe if it has one (record the recipe under Project-specific rules), else a clean checkout — once forward and once in reverse order; a red takes the failed-smoke path and is logged `fresh_check`. (Field report 2026-10-10: for a stretch, 6 of 7 stories' first CI runs went red on their own tests — stale shared-surface assertions, state the test never created, actions before the screen had loaded — each costing a rework cycle and a CI run of about 50 minutes; after this check, about 1 in 8.)

(Field report 2026-08-29: five classes of vacuous test across one epic — every one found by adversarial review or by a later story, none by a gate designed to catch it; the lead's own AD gate recorded `pass` for an assertion typed `readonly never[]`. Test count grew 518 → 659; discriminating power did not track it.)

## Rule 20 — Decisions with architectural weight go into the spine (lead/runner, under `/epic-cycle`)

The spine is the source of truth for architecture decisions, and the pipeline makes decisions: a clarification answer, a Rule 5 amendment, a decision-sheet call. A decision has **architectural weight** when it constrains more than the current story — a dependency direction or seam contract (a new or amended AD), a convention independent builders would drift on (a Consistency Conventions row), a pinned language / framework / dependency / licence (a Stack row), or a numeric invariant later stories assume (an AD's Rule). Such a decision is written into the spine **at the moment it is made** — in the same bookkeeping commit as the clarification answer, amendment, or decision-sheet line — by the lead, in the spine's own grammar. It is never held for the end of the epic, a completion contract, or a later gate: a decision that exists only in an agent's context is lost to a crash, a context compaction, or a mid-epic upgrade, and the write-ahead doctrine applies to it exactly as to a cycle-log entry. (Parallel runs: each runner writes into its own worktree's spine the same way; only the next `AD-n` comes from the orchestrator's counter — parallel kit.) Everything else stays where it lands today (spec change log, ledger trailer).

**Light path (default).** Add the next `AD-n` — ids ascend and are never reused or renumbered — with Binds / Prevents / Rule and `[ADOPTED]`; or amend an existing AD's Rule keeping its id; or add/edit a Conventions or Stack row; or move an item out of `## Deferred`. Then: `uv run --no-cache _bmad/scripts/memlog.py append --workspace <spine-dir> --type decision --text "<AD-n: what, and what it prevents>"` (the memlog is what `bmad-architecture` treats as the authority on what was decided); `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace <spine-dir>` and HALT on any `ad_id` / `ad_fields` / `placeholder` finding; refresh the spine's `updated:`; cite the AD id in the ledger trailer line, `## Spec Change Log`, or clarification record; bookkeeping-commit. The spine is a planning artifact, so the epic-context pre-warm re-runs before the next plan spawn and the decision reaches every later story. Log `spine_updated ad=<AD-n|conv|stack|deferred> reason=<clarification|rule5|decision_sheet> by=<lead|runner>`.

**Update intent (conflicts).** A decision that contradicts an existing AD is a re-architecture, not an amendment — never edit around it. Run `bmad-architecture`'s **Update** intent on the spine interactively (a human-in-the-middle run, like the retrospective) and let it resolve `conflicts_with_prior_decisions`; resume the pipeline only when the spine is `status: final` again and the pre-warm has re-run.

`decision-pending` entries with architectural weight are mirrored into the spine's `## Deferred` section with their DW id, so the spine also says what it has not decided yet. A spine written once and never updated is the failure mode BMAD's own docs warn about; a decision that lives only in a trailer line or a chat answer never reaches the next epic's plan stage (field case 2026-08-29: a licence decision and a tick-rate ratification recorded nowhere the plan stage reads).

## Project-specific rules (add below as retros surface them)

> Add additional rules here as retrospectives identify durable patterns. Number sequentially after Rule 20. Each rule should state what it applies to, the obligation, and (briefly) why.

## Rule 21 — OcuTalon runtime targets (all skills and their subagents, under `/epic-cycle`)

Each build runner has its own developer instance. The epic's `**Lane:**` line in `epics.md` picks it; Epic 0 has no lane and uses slot A.

| Lane | Container | MCP `server` profile | Superserver / web port |
| --- | --- | --- | --- |
| A, and Epic 0 | `ocutalon-slot-a` | `ocutalon-slot-a` | 1990 / 52790 |
| B | `ocutalon-slot-b` | `ocutalon-slot-b` | 1991 / 52791 |

- **What a slot is.** The build 154 base image on durable storage, with namespace `OCUTALON` created by the CPF merge file in the slot's `config/` folder: until Story 0.1 an interim one (Interoperability on, one code and one data database, `%Service_CallIn` enabled), from Story 0.1 a copy of `docker/merge.cpf`. It does not run the after-start script and has no `ocutalon` package installed: load and compile code into it with the IRIS MCP tools (`iris_doc_load`), and run installer steps or tests there explicitly. The after-start installer and the IPM install run in throwaway compose projects and in CI (the spine's environment table). Its health check is `iris qlist | grep -q '\^running'`, so `docker compose up -d --wait` returns once IRIS is up.
- **Recreating a slot.** Story 0.1 recreates both slots from empty data with `docker/merge.cpf` (its acceptance criteria say how). After that, a story that changes `docker/merge.cpf` copies it into its own slot's `config/` folder and restarts that slot (`iris-main` applies a changed merge file at start, after IRIS is up, so wait until the slot's `iris-data/iris/*.last_merge` matches `config/merge.cpf` before checking; slots run no after-start script, so an unchanged file is not re-merged), and the other lane's runner does the same for its slot at its next epic start. Otherwise no agent stops, wipes or recreates a slot (Rule 13).
- **Name the target on every call.** Pass `server` and `namespace` (`OCUTALON`, or `OCUORDERS` once it exists) on every MCP call; the profiles default to `HSCUSTOM`. Before a stage's first call, check the target's identity with `iris_server_info` (build 154, the profile's port).
- **No other target.** No other IRIS instance, container or MCP profile on this machine is a build or test target. If your slot doesn't answer, stop with a `TOOLING:` clarification; never fall back to another instance. If two epics of the same lane ever run at once, the second stops with a clarification.
- **Throwaway stacks for destructive work.** A destructive test (one that deletes or replaces namespaces, databases, security objects or data it did not create, or stops the instance) runs in a throwaway compose project (`docker compose -p <unique name>`), never on a slot (AD-22). Keep at most one throwaway IRIS stack per runner at a time, because the Docker VM's memory is shared with other long-running containers, and tear down only the projects you started.
- **The CI runner.** Two self-hosted runner services, `ocutalon-ci-1` and `ocutalon-ci-2`, labelled `self-hosted, Linux, X64, ocutalon`, share one x64 Linux host (4 vCPU, 8 GB memory plus 8 GB swap) and run as a user with Docker but without sudo. The base image is preloaded there as `ocutalon-iris-base:2026.3.0AI.154.0`: jobs build from it and never pull, push or cache it. Node 24 and Playwright 1.64.1's system packages are installed; a job installs the browser itself (`npx playwright install chromium`). Each job runs at most one IRIS stack at a time, so the two services can run two jobs at once (measured October 18 with the base image: about 1.5 GiB per stack, about 2 minutes to a ready Interoperability namespace on a first start). The repository secret `ANTHROPIC_API_KEY` holds the real key for release-candidate runs. Jobs that don't need IRIS run on GitHub-hosted runners, whose minutes are paid while the repository is private.
- **The CI recipe (Story 0.7).** Two workflows run per push: `ci` (the hosted `checks` and `web` jobs and the `iris` matrix on the runner) and `lane-a`. `ci/iris.sh` is the one recipe for the IRIS units, on the runner and on a developer machine. It always uses throwaway projects from `docker/tests/lib-live.sh` with the CI override `ci/compose.ci.yml`, and never a slot or another instance. `ci/units.sh` holds the one list of the check scripts, the shards and the groups.
  - **Commands.** Set one `OCUTALON_RUN_TAG` for the run (lower-case letters, digits and hyphens, at least 3 characters, no `slot`), then one piece per call: `ci/iris.sh build`; `ci/iris.sh shard lane-a`, `ci/iris.sh shard lane-b`, `ci/iris.sh class <Class>` (for example `OcuTalon.Test.Install.Users`) and `ci/iris.sh live <name>` (`compose-start`, `install-start`, `install-upgrade`, `production`, `production-restart`, `audit`, `demo-path`, `sign-in`, `bundle-folder`, `build-inputs`, `storage-roundtrip`); then `ci/iris.sh teardown` with the same tag, which removes only the projects (`ocutalon-<label>-<tag>-<epoch>-<pid>`), containers, volumes, networks and images of that tag (use a tag that does not end another run's tag). Under `/epic-cycle`, also set `OCUTALON_LOCK_OWNER='epic=<N> stage=<stage>'`: wherever the main checkout has `.worktrees/.coordination/locks/`, `lib-live.sh` holds `throwaway-iris.lock` while a stack runs, and that value names the owner in it (Rule 12); log its `LOCK` lines. `ci/iris.sh list` prints the units, `groups` the group names, and `group <name>` and `all` run groups. The base image must already be on the machine; it is never pulled.
  - **Fresh-environment check (Rule 19).** Run `ci/iris.sh shard lane-a` and `ci/iris.sh shard lane-b` forward, then both again with `--reverse`, one per call. Each starts a fresh throwaway and prints one `CLASS <name> passed|failed <s>s` line per test class (32 classes: 9 in `lane-a`, 23 in `lane-b`), with each failed or skipped assertion under it (`FAIL` or `SKIP`), and exits 1 when a class fails, runs no test or is not compiled. A class runs through `%UnitTest.Manager` with `/noload/nodelete/norecursive` from the installed package, after `^UnitTestRoot` is set to an existing folder of the throwaway, because the manager checks that folder even with no load. A new `Test.<Area>` must join a shard in `ci/units.sh`, or `test-ci-config.sh` fails.
  - **Hosted checks.** `bash ci/checks.sh` runs every static and hermetic script of `CHECK_SCRIPTS` (it needs bash, git, jq, Node and the Docker CLI; `demo-path-gate` runs the step summary on the hosted image's Node, because the `checks` job sets up none) and prints one block per script.
  - **Groups** (the matrix of `ci.yml`): `install` (install-start, install-upgrade), `production` (production, production-restart, audit), `browser` (demo-path, sign-in, bundle-folder), `shards` (lane-a, lane-b) and `image` (storage-roundtrip, build-inputs, compose-start). `image` is the IRIS checks job of AD-5. In CI each unit runs in its own project, and the web port of the browser units is 52810 plus the runner's number.
  - **Timings, measured October 19 on the developer machine (Apple silicon, ARM, Docker Desktop, warm layer cache); the runner is x64 and about three times as slow with two jobs at once (the first real run, below).** A ready stack takes 52 to 57 s (image build and first start). Per test class, every class takes under 0.4 s except `Install.Registry` (1.0 s), `Live.Publish` (1.3 s; slot A's history shows 4.4 s on average and one run of 125 s), `Msg.Catalog` (1.9 s after QA, Story 0.9) and `Contract.Checker` (1.9 s). Per shard, from the call's start to its teardown: `lane-a` 61 s and `lane-b` 64 s, almost all of it the stack start. Per live script: `compose-start` 80 s, `install-start` 151 s, `install-upgrade` 164 s, `production` 83 s, `production-restart` 87 s, `audit` 76 s, `demo-path` 60 s (the browser already installed; its first start printed `FIRST-START engine=aarch64 build=1s ready=53s`), `sign-in` 68 s (the browser already installed), `bundle-folder` 75 s, `storage-roundtrip` 66 s and `build-inputs` 4 s (layers cached). Per group: `install` 315 s, `production` 246 s, `browser` 143 s (before `demo-path` joined it; 203 s with its 60 s; on the runner 505 s with it, below), `shards` 126 s and `image` 150 s, 980 s in all (1040 s with `demo-path`); on the runner (below) the slowest group took about 15 minutes and the five groups about 50 runner-minutes. `bash ci/checks.sh` takes about 20 s.
  - **First real run (October 19, QA; the `ci` run of commit `7cf38e3`, run 39338702672, x64, two jobs at once).** Wall-clock 27 min 37 s from creation to the last job, so REL-4's 30 minutes holds with 2 min 23 s to spare. Per job: `checks` 23 s and `web` 29 s (hosted); `iris (install)` 14 min 35 s, `iris (production)` 12 min 57 s, `iris (image)` 7 min 59 s, `iris (browser)` 7 min 25 s and `iris (shards)` 6 min 45 s, about 50 runner-minutes in all. The matrix order is not the dispatch order: production and image started first, then shards, install and browser, the last two after waiting 13 and 16 minutes for a runner, and one runner stood idle for the last 4 minutes. A ready stack took 174 s (57 s on the developer machine). Per live script that starts a stack, 2.4 to 3.9 times the ARM figure: `install-start` 466 s, `install-upgrade` 388 s, `production` 271 s, `production-restart` 245 s, `audit` 237 s, `sign-in` 207 s, `bundle-folder` 216 s, `storage-roundtrip` 255 s, `compose-start` 192 s and `build-inputs` 7 s. Per shard 190 s and 193 s, all 27 classes passed, none over 7 s (`Contract.Checker` 6.8 s, `Install.Registry` 4.1 s). The `lane-a` run waited 8 minutes for a runner, its empty job took 4 s. No rebalance was applied, because the run is under 30 minutes.
  - **Second real run, with `demo-path` in the `browser` group (October 20, QA; the `ci` run of commit `fcdd9e9`, run 39359136309, x64, two jobs at once).** Wall-clock 23 min 39 s from creation to the last job, against 27 min 37 s and 24 min 12 s before, so REL-4's 30 minutes holds with 6 min 21 s to spare. Per job: `checks` 29 s and `web` 28 s (hosted); `iris (install)` 12 min 21 s, `iris (production)` 10 min 13 s, `iris (browser)` 8 min 43 s, `iris (image)` 6 min 2 s and `iris (shards)` 5 min 40 s, about 43 runner-minutes in all. The `browser` group took 505 s (`live:demo-path` 161 s, `live:sign-in` 173 s, `live:bundle-folder` 171 s), 2 min 15 s more than the 6 min 28 s job before `demo-path` joined it. The dispatch order was production, image, browser, install, shards; the last runner stood idle for the last 2 minutes. The unit printed `FIRST-START engine=x86_64 build=0s ready=150s` (no `WARN`; the layers were cached, so `build` is 0 s), and its floor test passed in 0.5 s. No rebalance was applied, because the run is under 30 minutes.

Why: other instances on this machine use the same namespace names and similar credentials, so a misrouted call answers plausibly and without an error (Rule 13).

## Rule 22 — Standing grant for unattended development (lead, orchestrator, runners and every stage, under `/epic-cycle`)

The owner is often away. The pipeline runs without them, and a human round trip per story is not available. The Contest Planner session (SendMessage `to: "Contest Planner"`) is the owner's relay. It takes the owner-only items, batches them for the owner with a recommendation, quotes the owner's answers back, and checks every reported sha on origin.

### 22.1 Decide and keep going

- **Clarifications and decision sheets.** Decide every `## Clarification Needed`, every `escalated` and `decision-pending` ledger entry, and the epic-close decision sheet (Rule 17 item 5) yourself, with `by=merge_gate`, using the product defaults in 22.2. Report the decisions afterwards (22.6). Never sit waiting for input that can't arrive.
- **Merging.** Merge each epic into the feature branch when CI is green on the exact head and the merge has no conflicts. Resolve conflicts yourself:
  - when both sides' intent is plain, keep both (a union of entries, keys, imports or tests);
  - when the conflict is a choice of behaviour, rule under 22.2 and log the ruling.
- **Retrospectives.** Skip them. Log `epic_retro_skipped reason=owner_directed`.
- **Pre-answered checkpoints (Rule 9).** A code-review or QA menu takes its recommended option. A model-tier offer to escalate, or to mix tiers, is declined. The retrospective is skipped.
- **Dispatch.** Dispatch the next epics and stories per the dependency graph in `epics.md`. Don't stop between them for approval.
- **Story splits.** An oversized story is split by you, at plan time or at review. Name the new story `N.<M+1>`, after the highest story number in the epic across `epics.md` and the sprint tracker. Re-record `epics_md_hash`, and add an `[AMENDED <date>, split for size, Rule 22]` marker.
- **No idle slot.** When a slot would otherwise wait (on the other lane's merge, a parked question or a CI queue), it takes the next independent story in its own lane. Failing that, it takes ledger burn-down items: CI flakes first, then security, then the most frequent. It never touches the other lane's files (Rule 11).

### 22.2 Product defaults for every call made alone

1. **The demo path comes first.** Prefer the option that keeps UJ-1 real and the demo-path test green.
2. **Never weaken a non-negotiable** (N1 to N15 in the scope brief, and every AD's "Prevents" line). In particular:
   - no false all-clear;
   - risky actions always wait for approval;
   - every demo step is generated live, with no canned replies;
   - no key or token in IRIS, a log, a commit or the trace;
   - the AI Hub image never goes to any registry, cache or artifact;
   - Claude Haiku 5.5 is the default, and no request sets temperature, top_p or top_k;
   - MCP tools are governed like built-in tools.
3. **Governed and honest.** When a choice trades safety for convenience, keep the safe behaviour and make it convenient. Text claims only what the product does. For example, tokens and cost are per turn and per decision, not per step.
4. **The spine is the contract.** Follow `ARCHITECTURE-SPINE.md` over preference. Where it is silent, choose the simplest option consistent with it. A decision with architectural weight goes into the spine when you make it (Rule 20), marked `[AMENDED <date>, Story <id>, Rule 22 ruling]`.
5. **Measure, don't guess.** Unknown platform behaviour gets a Task 0 that measures it on your slot or a throwaway. Anything not yet measured is labelled `(inference)`.
6. **Smaller is better.** Split rather than stretch a story. Defer a non-demo AC to a later story in the same release rather than block.

### 22.3 Decide now; the owner may veto before the next release

For these, rule so the slot keeps moving, then send the Contest Planner an FYI marked `VETO WINDOW`:
- security posture;
- secrets and credentials;
- privileges and roles, above all anything close to `%All` or any new grant to the demo, trace or public accounts;
- data loss, or a change to how stored data is kept (storage definitions are append-only);
- anything that weakens a guarantee in the PRD, the spine or the scope brief;
- public-facing text: README, splash, About, Telegram texts, and anything near the OpenClaw not-affiliated note;
- a new third-party dependency under a permissive licence (MIT, Apache-2.0, BSD, ISC), pinned to an exact version;
- moving an AC to a later story within the same release.

Each FYI states:
- the question;
- the ruling;
- the alternatives rejected, and why;
- why the ruling falls within this grant;
- the commit sha;
- what reversing it would take.

If the owner vetoes, take the ruling out before the next release.

### 22.4 Owner-only: park it with the Contest Planner, then continue with independent work

- **Releases:** cutting, tagging, release pull requests, and anything that lands on `main`. Implementation never commits to `main`. Story 11.5's sequence already stops for the owner before each outward step.
- **Anything outward-facing:**
  - publishing to IPM or Open Exchange;
  - posting anywhere, or filing bug reports with InterSystems;
  - DNS, servers and the online demo host;
  - Telegram bot settings and GitHub repository settings;
  - making anything public.
  Never push any image anywhere.
- **Scope and product promises:**
  - dropping scope from a release, or deferring it out of the release;
  - changing what UJ-1 does or says;
  - changing a number with product meaning (cost caps, allowances, timings, evaluation thresholds).
- **Money, accounts and licences:**
  - a dependency under a copyleft or unclear licence;
  - any paid service or spending;
  - accounts, keys and quota.
- **`CLAUDE.md` and everything under `.claude/`:** report the wording you need to the Contest Planner; don't edit them.
- **Containers you didn't start:**
  - Never stop, remove, recreate or `down` `ocutalon-aihub-test`, any `ocupilot*` container or `iris-community-edition`.
  - Slots follow Rule 21 only.
  - Tear down only throwaway projects you started and can name from your own transcript.

### 22.5 Stop conditions that survive this grant

Stop only the affected slot, message the Contest Planner at once, and keep the other slot running:
- a red CI head that isn't a known flake, and that you can't fix inside the story;
- a merge conflict you can't resolve under 22.1;
- runner liveness you can't establish;
- a tooling need you can't meet, such as a slot that doesn't answer (Rule 21, `TOOLING:`);
- a security incident: a secret in a commit, a log or the trace, or anything pushed somewhere public. Report it immediately and don't rewrite history without the owner.

### 22.6 Logging and reporting

- **Cycle log:**
  - `orchestrator_ruling`, with the question, the choice, the rejected options and why, and `authority=standing_grant(Rule 22)`;
  - `owner_decision`, with the owner's words quoted, as relayed;
  - `hold_ordered` and `hold_complete`.
- **Ledger:** trailers carry `by=merge_gate`, or `by=owner` for relayed decisions.
- **Spine and `epics.md`:** `[AMENDED ...]` markers.
- **Commit subjects** name the ruling, for example `chore(parallel): 2.4 ruling - <what was decided>`.
- **At every epic close, send the Contest Planner one short report:**
  - stories merged, each with its start and merge times in UTC (the Planner tracks pace against 3.5 stories per runner per day);
  - rulings made, each with its sha;
  - open VETO WINDOW items and parked owner-only items;
  - CI health (reruns, flakes);
  - anything the owner should know before the next release.
- Every reported sha must be pushed to origin. The Contest Planner checks it there.

### 22.7 When blocked

- **Red CI.** CI is a gate. Push one code head and confirm its run by `headSha` before any further push. The next story's plan and spec stages may run while CI runs. A red head reopens its story. A known flake gets one ledger entry per root cause, with an `occurrence=` count, and a rerun.
- **CI runner queue.** The two self-hosted services (Rule 21) can run two IRIS jobs at once. If a job queues for more than an hour, carry on locally with the next story's plan and implement. Never push the next story's code before the earlier head is green. If a head is blocked for more than about 6 hours, message the Contest Planner.
- **Quota or usage limit: the hold protocol.** Start it at the first usage-limit warning, or at about 90% if you can see the figure. A usage-limit 429 counts too.
  1. Start no new stage.
  2. Make `WIP(hold)` commits by path, and push bookkeeping only.
  3. Leave CI that's in flight running, and record which throwaways are still up.
  4. Write one complete resume prompt per slot to `.worktrees/.coordination/prompts/e<epic>-resume-<date>-prompt.md`. It must not depend on chat history, and it contains:
     - the role and the invocation;
     - Rule 22 and the owner-fixed values below;
     - the state, verified with git: the branch, the origin and local heads, each unpushed commit, the spec status, the slot's state and the ledger;
     - the next steps, in order;
     - "End only with `## Epic Runner Complete` or `## Clarification Needed`".
  5. Log `hold_complete` with every sha.
  6. Message the Contest Planner with the prompt paths and shas.
- **API rate limits.** Retry with backoff. Only a usage-limit 429 is the quota case.
- **Restarts.** Keep nothing you need after a restart in `/tmp`.

### 22.8 Containment (restating Rule 18, because unattended runs wedge on it)

- Every `Agent` call passes `run_in_background: false`, except the runner spawns.
- Test and build calls run in the foreground with `timeout: 600000`, in batches of about 8 minutes.
- Every agent returns exactly once.
- Never `SendMessage` an agent whose call has returned. Spawn a fresh one, with the work written to a file.

### 22.9 Owner-fixed decisions (don't re-derive or "fix" these)

- One IPM package, `ocutalon`, with the bridge inside it.
- Telegram is in Lane A, after Epic 11: 0.1.0 is cut at Epic 11, and Telegram ships as 0.1.1 before launch.
- Polling is the release-1 contract; the WebSocket comes second.
- Online-demo sessions resume until the reset (P10). The CSP session ends about 2 minutes after the page closes, or after 10 minutes idle.
- Online-demo capacity is about 6 visitors per instance (P12), with "Demo busy" beyond that and no scale-out work.
- The finish state appears only after an approved, resolved run (P24).
- Claude Haiku 5.5 is the default model, with `max_tokens` 8,000 and no sampling parameters.
- The demo allowance is 50 messages an hour per session, and 20 simulated emails an hour.
