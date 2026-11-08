# Story 19.4, Task 0: the documents search through a real ChatAgent turn, the gate's view of the call, the top_k rewrite, the score floor and the self-message

Measured 2026-11-07, 17:30 to 17:55 UTC, on one lane-C throwaway (run tag `e19s4i0`, started with `ci/warm.sh up`, ready in 114 s, torn down with `ci/warm.sh down`): IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U), aarch64, the image built from this worktree with the CI mock (restarted once after the new scenario files were added). The product classes `OcuTalon.Docs.Passages`, `Docs.Embedding`, `Docs.Store`, `Docs.Ops`, the Chat agent's `%OnInit` and the Gate/StepAudit/Citations classes were loaded from the mounted tree; the harness was a scratch test class (`ZE19.Task0`, a subclass of `Test.Memory.Turns`, so the turns are the real ones: `Decide` -> `ChatAgent` -> the CI mock) plus two scratch copies of `Policy.Gate` and `Docs.Embedding` with a recording line, all loaded into the throwaway only and never in the repository. The scratch folder holds the sources. The fixture is `eval/documents-runbook-rotate/results-runbook.md` (5 passages: the intro, "Rotating the certificate" with 3 steps, "Clearing the queue", "Restarting the Results production", "Contacting the lab"). Scratch deviation from the spec: the "scratch Chat override" was not needed, because the product's `Agent.Chat` `%OnInit` block is the attach; it stays out of the product if M1 fails.

## Verdict

**The stop rule does not fire.** M1 passes. M2 shows a knowledge-base call without `origin_class` and a toolset call with it. M3: a change inside the arguments object has no effect, but setting the call's `arguments` member again does (an object or a JSON text), so a rewrite exists and the product uses it (see "In-stage decision" below). M4's scores do not overlap: `CITEFLOOR` is 0.4.

## M1: the query path in a real ChatAgent turn

- The knowledge base was built with `Docs.Embedding`, so AI Hub calls `EmbedBatch` from inside its tool execution and that calls `Memory.Embedding.Embed`.
- Three `documents` turns (`[[mock:documents-runbook]]`, the query "how do I rotate the Results certificate?") and one `search_memories` turn (`memory-recall-meaning`) on one session: each `documents` turn answered with the scenario's last text, `Tainted` 1, `ToolsRun` 1, no fallback; the model's second request carried 5 passages (2,110 characters), the best being `{"id":"<ref>:1","score":0.73243797,...,"metadata":{"chunk_index":1,"document":"Results runbook","section":"Rotating the certificate","source":"<ref>"}}`.
- The embedding ran in the Embedder worker's job: the recording copy of `Docs.Embedding` logged `caller job 4115 worker job 3766` for each of the three queries (the caller is the runner's job, the worker's `$JOB` is the Embedder's).
- The ChatAgent runner's job was 4115 before the first turn and after every turn, including the `search_memories` turn. No S11 crash, no deadlock, no recycle; the four turns took under 12 s in all.
- Before the `ToolClassification` entry was in the production the same call was held for approval (`Tool access denied: held for your approval`), as the near-miss rule says.

## M2: what the real adapter's gate receives

Recorded in `Check` for every call (`$Job` 4115, the runner's):

| Call | `toolref` | `metadata` | `call.arguments` |
|------|-----------|-----------|------------------|
| `documents` | `documents` | `{"requires_auth":false}` (no `origin_class`) | an object (`%Library.DynamicObject`): `{"query":"how do I rotate the Results certificate?"}`; with a `top_k` it holds `"top_k":9` as a number |
| `search_memories` (a toolset call) | `search_memories` | `{"origin_class":"OcuTalon.Tools.MemoryTools","requires_auth":false}` | an object |

So only the knowledge-base tool lacks `origin_class`; the toolset call carries it. The tool's catalog entry is `source:"rag"` (plan-stage measurement); no source class reaches the gate for it, so `Gate.RagCall` (name exactly `documents`, a toolref that does not start `mcp:`, no `origin_class`) is the one test.

Two facts the product code was built on, measured on the stack of the story's tests (not part of Task 0's five measurements):

- The result text that the audit policy receives (`result.result_json`) for a `documents` call is the bare array `[{"id","score","text","metadata":{...}}]`, the same text the model reads; a direct `%AI.ToolMgr.ExecuteTool` returns the object `{"timing","value":[...]}`. `Bridge.Citations` reads both. The spec's Code Map names the object form.
- The step label of the call is the generic "Running a tool", and the call's Visual Trace step is `documents` with the source `%AI.RAG.KnowledgeBase` (`StepProblems` empty).

## M3: does a gate rewrite of `top_k` from 9 to 5 take effect

A document of 12 passages plus the runbook's 5, the scenario `documents-topk` (`"top_k":9`), 17 rows in the table; items in the result the model reads:

| Rewrite in `Check` | `after` (what the call holds when `%CanExecute` returns) | Items the model got | `ReportStep` runs |
|--------------------|----------------------------------------------------------|---------------------|-------------------|
| none | `top_k` 9 | 9 | 1 |
| `call.arguments.%Set("top_k", 5)` (inside the object) | `top_k` 5 | **9 (no effect)** | 1 |
| `call.arguments.%Remove("top_k")` (inside the object) | none | **9 (no effect)** | 1 |
| `call.%Set("arguments", <a new object with top_k 5>)` | `top_k` 5 | **5** | 2 |
| `call.%Set("arguments", <the JSON text with top_k 5>)` | `top_k` 5 | **5** | 2 |

- A bare `%AI.ToolMgr.ExecuteTool("documents", {"query":...,"top_k":n})` returned 1, 3, 5, 9 items for n = 1, 3, 5, 9 and 17 for 50 (all rows): the argument is honoured by the tool, with no upper bound of its own, so the clamp is needed.
- The gate's own doc ("AI Hub runs the call with whatever its arguments object holds after %CanExecute") is true only for the member as the call holds it: a change inside the object does not reach the tool.
- When the `arguments` member is set again, AI Hub runs the policy a second time on the changed call (two `Check` calls for one execution, the second with `top_k` 5 and, for a JSON text, the arguments parsed back to an object); the audit policy ran once. With no guard that fires `turn.step` twice (`ReportStep` ran twice). The product's rewrite therefore marks the rewritten call in `^||OcuTalonBP.RagRewrite` (the context's ItemId and the new arguments) and the second run skips `ReportStep` and clears the mark; measured with the real `Gate`: items 5, `ReportStep` 1, `Tainted` 1, `StepProblems` empty, in both of two turns.

### In-stage decision (recorded in the spec)

The spec's task text says to rewrite "in the arguments object (or the JSON string, re-set) per Task 0 M2/M3". M3's in-place rewrite of the object has no effect, so the product sets the `arguments` member to a changed copy of the object (or to the changed JSON text), which M3 shows takes effect. The stop rule's wording ("the rewrite has no effect") is read as no working rewrite at all; a working one exists, so the story proceeds, and this is raised in the report for the lead.

## M4: the floor, with the real embedder

`OcuTalonKB.Docs` held only the runbook's 5 passages (embedded through `Docs.Embedding` / `Memory.Embedding.Embed`, the section heading in the embedded text); each query ran through AI Hub's knowledge-base tool (`top_k` 5). Scores of the passages by `chunk_index` (0 intro, 1 Rotating the certificate, 2 Clearing the queue, 3 Restarting, 4 Contacting the lab):

| Kind | Query | Top score (chunk) | The rest |
|------|-------|-------------------|----------|
| relevant | how do I rotate the Results certificate? | 0.7324 (1) | 0.3081, 0.2724, 0.2496, 0.1747 |
| relevant | what are the steps to renew the TLS certificate of the Results feed? | 0.6892 (1) | 0.3638, 0.3337, 0.314, 0.2547 |
| relevant | the Results certificate is about to expire, what do I do? | 0.7410 (1) | 0.4099, 0.3980, 0.3599, 0.3273 |
| near-miss (other section) | how do I clear the Results queue when it keeps growing? | 0.6859 (2) | 0.4932, 0.3898, 0.2554, 0.1513 |
| near-miss (other section) | when may I restart the Results production? | 0.5671 (3) | 0.4329, 0.4284, 0.3975, 0.3135 |
| unrelated | what is the capital of France? | -0.0077 | all below 0 |
| unrelated | how do I reset my password? | 0.0969 | |
| unrelated | what is the weather like in Paris today? | 0.0157 | |
| unrelated | how do I bake sourdough bread? | 0.0943 | |
| unrelated | who won the football world cup in 2018? | 0.1132 | |

Note on the unrelated queries: "what is the capital of France?" scored below 0 for every passage, so a floor of 0 would not tell it from a cited passage; the mock scenario `documents-none` therefore asks "how do I reset my password?" (top score 0.0969), and a floor of 0 makes `Test.Docs.Turns:TestNotCovered` red (a mutation recorded in the spec).

- Highest unrelated top score 0.1132; lowest relevant top score 0.6892 (the three relevant queries) or 0.5671 (counting the near-misses, which the document does answer). They do not overlap. `CITEFLOOR` = midway = (0.1132 + 0.6892) / 2 = 0.4012, used as **0.4**. Both near-misses clear it (0.5671, 0.6859); at 0.4 the passage that answers each relevant query is the only one cited for the rotation questions, and a restart question also cites chunks 1 and 0 (0.4329, 0.4284) - the floor is a floor, not a precision cut.
- An unrelated query still returns every passage (scores near 0); an empty table returns `[]` (plan-stage measurement).

## M5: `SendRequestAsync` from `DocumentOps` to itself

With the real `DocumentOps` in the running production (pool 1), a 86,592-byte text document A (100 paragraphs, 108 passages), then a small Markdown B, then `RemoveDocument` A, all through `Commands.Submit` as `web_user`:

- Message headers of `DocumentOps` in id order: 409 `AddDocument` A (handled 0.05 s), 410 `Index(A,0)` (created when 409 finished; handled after it), 412 `AddDocument` B (created while 410 ran; handled after 410 ended), 413 `Index(A,32)` and 414 `Index(B,0)` (created while 410 and 412 ran; handled in that order after them), 416 `RemoveDocument` A (queued while 413 ran; handled after 413 and 414), 417 `Index(A,64)` (created by 413; handled after 416). So a self-message is handled after the current message, in FIFO order with the commands.
- After the remove, 417 found no row and stopped: the table held 0 rows of A and 2 of B; B ended `ready` with `Sections` `["","Part"]`; the instance stream's `document` events were A `indexing`, B `indexing`, B `ready`, A `removed` true.
- A batch of 32 passages took about 10.6 s: `Memory.Embedding.Embed` costs a steady 0.33 s a call through the Embedder worker (900-character and short texts alike; six calls 0.312 to 0.337 s), so `AddDocument` B waited 11.1 s behind A's first batch. The product therefore indexes `BATCH` = 8 passages per message (about 2.7 s), so that a command waits for at most one short batch. A 1,000-passage document takes about 5.5 minutes to index.

## Cleanup

The scratch classes (`ZE19.*`) and the two recording copies lived only in the throwaway, which was removed with `ci/warm.sh down`; the repository holds none of them. The table `OcuTalonKB.Docs` rows of the scratch refs were deleted before the end of each run.
