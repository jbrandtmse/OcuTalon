# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 finishes the Lane A parts of the demo-path stories that were moved past the demo, each landing before 1.0.0. Part 1 (Stories 30.2 to 30.6) is merged. This re-open is part 2. Story 30.1 makes long conversations keep working: a flagged turn is compacted through AI Hub's guarded fork-and-summarize path, or rotated to a seeded fresh session, so no request goes over the size limit and a conversation whose history has outgrown the limit is no longer stuck answering `too_large`. A burn-down story (30.7) then clears the ledger entries kept for this epic. Both merge together.

## Stories

- Story 30.1: Long conversations are compacted under the limit (backlog; spec re-planned as draft)
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got (done)
- Story 30.6: The invalid-reply warning names what failed, never the reply (done)
- Story 30.7: Burn-down of the ledger entries kept for Epic 30 (chartered at part 2's gate, after 30.1)

## Requirements & Constraints

- **Request size.** No request the runner shapes is sent above the request-size limit: not the summarizer's, not the turn's first. A mock conversation long enough to compact keeps its largest request under 100,000 tokens. With turns above 40,000 tokens compacted, a 4-iteration tool loop stays near 94,000 (40,000 + 3 x 10,000 tool results + 3 x 8,000 output). A first request between 40,000 and the limit can still exceed 100,000 later in its loop. That residual is open and goes to the lead/owner (refuse in favour of the seed, refuse such turns as `too_large`, or accept with a `reopen_if`).
- **Failures stay internal.** A compaction failure is one redacted warning (runner item, OwnerRef, DecisionRef, failed step). It never becomes the turn's fallback reason or the reply's failure text.
- **Time budget.** A flagged turn that continues a linked conversation gets 20 more seconds on its timer, never above 110 seconds in total.
- **Cost honesty.** Every summarizer call, including one that throws, writes one `Usage` row with agent `compaction` and `Estimated` true, priced at about 4 characters per token at the summarizer model's rate. It must count in the turn, run and day totals.
- **Release-candidate smoke.** A live thinking-history smoke runs only in release-candidate runs on the real model: three turns across jobs, a compaction and a tool change, with Claude 5.5's thinking-history rule forced. Push and `--on-mock` runs report it as not run. This run never uses a real key.
- **Burn-down conditions (30.7), each kept unchanged.**
  - DW-386 (U-184): `Bridge.Redact` replaces every key-like shape (DigitalOcean `dop_v1_`, PEM private-key headers, `sk-ant-` keys, Telegram bot tokens), one test per shape, before 1.0.0.
  - DW-448 (U-185): the key proof's globals walk decodes `$List` elements. Measure on a throwaway whether a message body can store a key in a compressed or split `%Stream.Global*` chunk. If it can, decode it. If not, close that half wontfix-accepted with the evidence.
  - DW-541: chip 1 ("Which productions are running?") gets a code-built running or stopped state from `list_productions` (trusted fields only), or the chip's text becomes "Which productions can you watch?". Only at no date cost: if it would push this merge past Epic 13 (the critical path to rc1), re-own it to the first daily release after 1.0.0.
  - Also: DW-444 (a crashed mid-replay `tool_call` stays executing with no result), DW-470 (a replay failed for a missing key or an unreachable provider says so in catalog words, and that nothing was changed; no public text claims a replay works offline), DW-462 and DW-549 (flakes), DW-371 (the remaining `Purge` copies adopt the shared day cutoff).
- **Stored data.** 30.1 makes no stored-data change. Any new column in 30.7 is append-only, a veto item of its own, and gets its own `Test.Data.Tables` entry.
- **Tests** run on throwaway stacks. New mock scenarios go only under `ci/mock/scenarios/A/`. Fixtures use only the existing fixture names (the repository is public).

## Technical Decisions

- **Where compaction runs.** Only in the runner's job, in the adapter's linked path, under the conversation lock, after the session is opened and before `Chat`. It never runs in a callback, and no AI Hub call runs inside one. Only a `Compact` turn that continues a linked conversation is compacted. Untrusted, fresh, `decide`/`diagnose` and first turns never are.
- **The guarded path.** `ForkAndSummarize(summarizerProvider, "", k, <compaction prompt>, 0)`. `k` keeps the last user turn whole and is computed from `GetContext()` outside callbacks. With nothing older, there is no compaction. The prompt is the existing Epic 0 constant starting `OCUTALON-COMPACTION-V1`, asking for AI Hub's summary schema with every tool result in `facts_learned`. Don't change its text. Never use `Summarize` in place, and never `Fork` without summarizing.
- **The switch.** Check the fork first: the first non-system message must be a user message (not a tool result), and every tool result must follow its call. Then save the fork, release the original, reopen the fork with `OpenSession` (a freshly composed config, so cap, effort and `timeout_ms` apply), and point the link at it. Saving the fork before `Chat` is the one exception to "save only after a completed `Chat`". A tainted turn is never saved.
- **Seeded fallback.** Any `ForkAndSummarize` exception (it arrives as `<%AICore>InternalError`), a failed check, a failed save or reopen, or a request still over the limit gives a fresh session seeded with a code-written summary of the stored user and assistant texts (the shape of Lane B's recap, bounded in size, no tool text). It is saved and linked after a completed, untainted `Chat`. The over-limit and save/reopen triggers go beyond AD-20's two named triggers. They need a spine amendment, which is a veto item for the lead.
- **Summarizer provider.** The runner's own provider settings plus `extra_config.output_config.effort` `low`, a 20-second request timeout and a full retry block with `max_retries` 0 (never a partial block). It is built in memory only: never logged, stored or put in a warning. No sampling parameter.
- **Decide.** For a flagged turn that continues a linked conversation, `too_large` is judged on the most the runner will send after compaction or rotation. The flag itself still uses the full estimate. The runner reads the same limit through one shared method, not a copy.
- **Boundaries.** Bridge classes name no other OcuTalon package. Pure compaction helpers (cut, check, seed, settings) take dynamic objects and make no `%AI` call. The session-call allow-list gains `forkandsummarize`. Old sessions and unlinked forks are removed by Story 30.2's `Bridge.Purge`.
- **Keep part 1 consistent.** Warnings name IDs and counts, go through `Bridge.Redact`, and never quote reply content (30.6). An approved call replays once with no model request, and the row is the truth (30.3). `Bridge.Time.DaysCutoff` is the shared day rule (30.2).

## Cross-Story Dependencies

- **Order.** 30.1, then 30.7. Both merge in part 2. Story 31.2 (Lane B) waits on this epic's merge.
- **30.1 consumes** Story 1.9 (`Request.Compact`, the estimate and the limit), Story 1.8 (the link, the lock, `OpenSession` with a composed config), Story 30.2 (purging unlinked sessions) and Story 9.5 (`eval/run.sh`, `Eval.Gate`, the release-candidate run that reads the smoke). Lane B's `Core.Conversation` and `Data.Ownership` totals benefit with no change.
- **30.1's own ledger entries:** DW-125 (stuck conversation), DW-130 (in-loop size), DW-93 (`Precheck` cost of `Budget.State` over unindexed Usage) and DW-483 (one retry on an invalid reply). The spec predates later `Decide.cls` changes (Stories 5.12 and 30.6, DW-544), so re-plan against today's code.
- **Lane ownership.** Lane B's `Core.Conversation`, `Data.Ownership`, `Msg.Catalog`, `Data.Time` and `web/**` are read-only. Never touch `.github/workflows/lane-a.yml` or `ci/units.sh`. `eval/run.sh` and `docker/tests/test-eval-set.sh` are Lane A's (Epic 9's). Before editing a shared file, check what Epic 11's branch has changed.
- **Environment.** This run uses runner B's slot `ocutalon-slot-b` (lane-b locks), for load and compile only. Production-bound tests run on throwaways.
