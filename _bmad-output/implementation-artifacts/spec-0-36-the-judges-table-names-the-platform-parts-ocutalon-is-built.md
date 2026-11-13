---
title: "Story 0.36: The judges' table names the platform parts OcuTalon is built from"
type: 'docs'
created: '2026-11-13'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** README.md's "### For judges: where to look" table (line 38) has a Complexity row that says what OcuTalon does but not which InterSystems platform parts it is built from, so a judge scoring complexity and use of the platform cannot see that OcuTalon extends AI Hub's own classes and uses Interoperability's own mechanisms.

**Approach (the Contest Planner's 1.0.9 doc story, owner-approved, 2026-11-13; binding):** replace ONLY the `| Complexity | ... |` row with exactly this line (the approved PUBLIC TEXT, verbatim):

```
| Complexity | One Interoperability production of over 40 items runs three AI Hub agents, each an `%AI.Agent`: attention decisions, diagnosis and chat ([Production.cls](src/ocutalon/cls/OcuTalon/Production.cls)). It is built from the platform's own parts. OcuTalon's outbound adapter extends AI Hub's `EnsLib.AI.Agent.OutboundAdapter` ([Agent.cls](src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls)), and the gate that checks every tool call before it runs is an `%AI.Policy.Authorization` ([Gate.cls](src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls)). Each Visual Trace step comes from an `%AI.Policy.Audit` and an `%AI.Shell.StreamRenderer`, documents use AI Hub's RAG knowledge base over IRIS vector search, and the model and its timeouts are AI Hub Config Store entries. On the Interoperability side, approvals are `EnsLib.Workflow` tasks, a fix resends with `Ens.MessageHeader.ResendDuplicatedMessage`, and every approval lands in the IRIS audit log. Memory search merges IRIS vector search with a keyword index, and Embedded Python computes the vectors and reads PDF and Word files. |
```

Update, in the same commit, every test pin the new row trips. If a pin would force a WORDING change to the approved text, stop and send the exact diff to the Planner as PUBLIC TEXT before committing.

## Boundaries & Constraints

**Always:** change only README.md line 38 and `docker/tests/test-readme.sh` (plus bookkeeping: epics.md Story 0.36, the tracker, this spec, the cycle log). README stays at or under 2,300 words by `wc -w` (2,175 before). Every link resolves (readme-links, readme-anchors).

**Never:** no other README line changes; no product change (no ObjectScript, Python, web, Dockerfile, compose, CI-workflow edit); never change code to make a claim true — a false claim stops the story. Never weaken a test-readme rule beyond a word-for-word exemption of the approved row.

</intent-contract>

## I/O & Edge-Case Matrix

| Case | Input | Expected |
| --- | --- | --- |
| The row | README.md line 38 after the change | byte-identical to the approved line above; `git diff` shows one changed line in README.md |
| Word cap | `wc -w README.md` | at most 2,300 (2,175 before) |
| Links | the row's three links (Production.cls, Agent.cls, Gate.cls) | each a tracked file; readme-links passes |
| dev-only rule | the approved row (holds `%AI.Agent`, `EnsLib.AI.Agent.OutboundAdapter` and other class names, which the rule flags outside "For admins and developers") | exempt word for word, as the IPM load line is; any other class name above the admin section is still flagged |
| dev-only rule, mutated row | the approved row with one word changed | flagged (the exemption is word for word) |

## Code Map

- `README.md` line 38 — the Complexity row of "### For judges: where to look".
- `docker/tests/test-readme.sh` — `dev_names` (~line 1381) flags a dotted capitalised name (`%?[A-Z][A-Za-z0-9]*(\.[A-Z]...)+`) on any line outside the two admin H2 sections, exempting only `IPM_LOAD` word for word; `rule_dev_only` (~line 2686) holds its broken-copy rows. No rule pins the old Complexity text (searched: `rg 'Complexity'`, the old row's phrases, across docker/, ci/, web/ and src/).

## Tasks & Acceptance

- [ ] Replace README.md line 38 with the approved line, byte for byte.
- [ ] `test-readme.sh`: add a `COMPLEXITY_ROW` constant holding the approved line word for word; `dev_names` skips a line equal to it (as it skips `IPM_LOAD`); the header comment of the dev-only rule names the exemption; add broken-copy rows to `rule_dev_only`: the Complexity row with one class name changed is flagged, and a class name on its own line next to it is still flagged.
- [ ] Verify every claim in the row against the code at 7865c322 (the Planner's list under Design Notes); a false claim stops the story.
- [ ] Demonstrate the mutations (Rule 19) and record them under `## Verification`.

## Design Notes

- Governing ADs: none binds README prose directly; the claims cite AD-backed code (AD-7 agents, AD-19 Config Store, the gate and audit classes). The text is public-facing and owner-approved through the Planner (policy `veto_window` "public-facing text" is satisfied by that approval).
- Planner's claim list (verified at 7865c322 by the Planner; re-checked by the lead and the review layer): Agent/Chat, Diagnosis and Triage extend %AI.Agent; Bridge/Adapter/Agent.cls:116 extends EnsLib.AI.Agent.OutboundAdapter; Bridge/Policy/Gate.cls:97 extends %AI.Policy.Authorization; Bridge/Policy/StepAudit.cls:12 extends %AI.Policy.Audit and Bridge/Adapter/StepRenderer.cls:12 extends %AI.Shell.StreamRenderer; Docs/Embedding extends %AI.RAG.Embedding and Docs/Store is the knowledge base; Bridge/ConfigStore.cls covers the AI Hub LLM entries and timeouts; Fix/Executor.cls:1097/1126 calls Ens.MessageHeader.ResendDuplicatedMessage; approvals are EnsLib.Workflow tasks; every approval lands in the IRIS audit log; memory search merges vector search with a keyword index; Embedded Python computes the vectors and reads PDF/Word; the production has over 40 items.
- Decided in-stage (lead ruling, decide): the dev-only rule (no class name in judge-facing README text) flags the approved row. The Planner approved class names in this row deliberately, so the rule gets a word-for-word exemption for that one line, exactly as it has for the IPM load line; the approved wording is unchanged and the rule still holds for every other line. A changed row is flagged again, so the exemption also pins the row's wording.
- Rule 2 (extend, don't copy): the exemption reuses `dev_names`'s existing `ipmload` skip pattern.
- Integration AC: not service-introducing (docs and test only). No consumers.
- Ledger inbox: (none) — `LEDGER slice 0-36-the-judges-table-names-the-platform-parts-ocutalon-is-built` is empty.
- Plan spawn skipped: lean path like 0.34 (the dispatch allows a lead-written spec); QA skipped (the deliverable is the text plus its pins).

## Spec Change Log

- 2026-11-13: written by the lead from the Contest Planner's 1.0.9 doc-story dispatch.

## Verification

Shared surfaces: README.md's judges table (the judges-usability rule reads the same table; its Usability row is untouched); test-readme.sh's dev-only rule (one exemption added). No web test reads the Complexity row.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands**, from the worktree root, one per call, with `timeout: 600000`. No IRIS runtime and no MCP target is needed.
- `bash docker/tests/test-readme.sh` (loop): every rule passes.
- `bash docker/tests/test-boundaries.sh` (once).
- `wc -w README.md` (once): at most 2,300.
- `npm --prefix web test` (once), or its doc tests.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
