---
title: 'Story 4.12: The demo guide''s document tip promises only what 1.0.4 shows'
type: 'bugfix'
created: '2026-11-08'
status: 'done'
baseline_revision: '6ea174e78ff9152e6dbef91cd0aa0ba6a82621c9'
baseline_commit: '6ea174e78ff9152e6dbef91cd0aa0ba6a82621c9'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-4-context.md']
warnings: []
deferred:
  - summary: >-
      The Documents page's empty state still promises citations ("No documents yet. Add a runbook to get cited answers."), the same unbuilt Story 20.2 promise, on the page the tip opens.
    evidence: |-
      web/src/app/documents/documents-view.ts:21 (also the documents-page.ts doc comment); pinned in documents-view.test.mjs, documents.spec.ts and ux-strings.test.mjs; sourced from epics.md Story 3.x/FR-42 and EXPERIENCE.md. Out of this story's four-place scope and a separate public string, so it needs its own Planner ruling.
    location: >-
      web/src/app/documents/documents-view.ts:21
    severity: medium

---

<intent-contract>

## Intent

**Problem:** The "Other things to try" panel's item 6 ("Ask about a document") tells the visitor to "look for the citation under the answer". The 1.0.4 web chat draws no citation (Story 20.2, not built), so a judge who follows the tip looks for something that is not there.

**Approach:** Swap the one `lookFor` string for the Planner's ruled public text (ruling `guide_documents_citation_promise`, 2026-11-08) in the source and in the three places that pin it. EXPERIENCE.md already carries the ruled string and is not touched.

## Boundaries & Constraints

**Always:** The new string is byte for byte: `On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat, and look for the answer that comes from your file.` Plain ASCII, a single-quoted literal like the old one, a comma after "in the chat". Exactly four files change, each hunk a one-string swap.

**Never:** Change any label, button, comment, other string or other file under `web/`. Edit EXPERIENCE.md or any planning file. Touch `release/**`, tags, `main`, `.claude/`, `_bmad/`. Add a ledger entry (Story 20.2 owns the citation line's return, DW-975).

</intent-contract>

## Code Map

- `web/src/app/guide/more-to-try-view.ts` (line 59) -- the `documents` item's `lookFor`; the source.
- `web/e2e/guide/more-to-try.spec.ts` (line 97) -- pinned `documents.lookFor` (runs in CI only).
- `web/scripts/more-to-try-view.test.mjs` (line 66) -- pinned `documents.lookFor`.
- `web/scripts/ux-strings.test.mjs` (line 433) -- entry in the `ux` SOURCES list; it reads EXPERIENCE.md's item 6, already holding the ruled string.

## Tasks & Acceptance

**Execution:**
- `web/src/app/guide/more-to-try-view.ts` -- replace the whole `documents.lookFor` string with the ruled one -- the source of the tip.
- `web/e2e/guide/more-to-try.spec.ts` -- same swap in the pin -- keeps the CI e2e green.
- `web/scripts/more-to-try-view.test.mjs` -- same swap in the pin.
- `web/scripts/ux-strings.test.mjs` -- same swap in the `ux` SOURCES entry.

**Acceptance Criteria:**
- Given item 6 of the panel, when its look-for line shows, then it reads the ruled string verbatim.
- Given the three pins, when the tests run, then each matches the ruled string byte for byte (and `ux-strings.test.mjs` matches EXPERIENCE.md).
- Given the diff, when the story merges, then exactly those four files under `web/` changed, each by one string.

## Spec Change Log

- 2026-11-08 orchestrator ruling under the Contest Planner's one-commit fix-forward: one build-auto stage plans and implements; no separate QA stage (the change IS the pins); no separate code-review stage (the lead reviews the 4-file diff). Story 20.2 restores a citation line when it ships (DW-975).

## Review Triage Log

### 2026-11-08 — Review pass
- verdicts: 8 findings — high 0, medium 3, low 5, false 0, maybe-false 0
- findings:
  - `[medium]` `[defer]` (3 members, one root cause) Documents page empty state "Add a runbook to get cited answers." repeats the unbuilt citation promise (blind-hunter, edge-case-hunter x2, grouped) -- verified at `web/src/app/documents/documents-view.ts:21`; a separate public string outside the ruled four-place scope, so deferred in the frontmatter for the lead (needs its own Planner ruling).
  - `[low]` `[reject]` Verification grep too narrow (blind-hunter) -- same root cause as the row above; the grep is the spec-prescribed check for the ruled string, and widening it is the lead's call with that row.
  - `[low]` `[reject]` New tip wording not verifiable in the chat (blind-hunter, intent-alignment reading D) -- the string is the Planner's ruled public text, byte for byte; not changeable here.
  - `[low]` `[reject]` e2e pin of `documents.lookFor` is never asserted (verification-gap) -- verified true (`more-to-try.spec.ts:252` covers items 1 to 4 only); adding an assertion makes that hunk more than the one-string swap the charter fixes, so spec-bound; `by-design`, and the unit tests pin the rendered string.
  - `[low]` `[patch]` Mutation line recorded as planned, not observed; criterion 3 (four files, one string each) has no mutation line (verification-gap, one finding) -- the mutation was applied, observed red, reverted and recorded in `## Verification`; criterion 3 is a diff property checked by the lead's 4-file diff review, and no pinning test can exist for it.
  - `[low]` `[reject]` Intent-alignment readings A to D (intent-alignment) -- descriptive; the diff implements reading A exactly (4 files, 4 insertions, 4 deletions); readings B to D point to the row above and the ruled text.

## Design Notes

- service_introducing=false: a string fix; no service, module or shared component, so Rules 1 and 2 (Integration ACs, Consumed-by) do not apply.
- Governing ADs: none bind; string-only change (public-text rules only).
- Ledger inbox for this key: (none).
- Decided in-stage: none needed.

## Verification

**Commands:**
- (loop) `cd web && node --test scripts/more-to-try-view.test.mjs scripts/ux-strings.test.mjs` -- expected: all pass.
- (once) `cd web && node --test scripts/*.test.mjs` -- expected: the web unit suite passes, as `web/package.json`'s "test" runs it.
- (once) `grep -rn "citation under the answer" web/src web/e2e web/scripts` -- expected: no output.

**Manual checks:** the e2e spec runs in CI only.

Shared surfaces: none (one string). Every test changed passes on a fresh environment, in either order.

mutation: drop the comma after "in the chat" in `more-to-try-view.ts` -> `more-to-try-view.test.mjs` (the ruled strings, the registry order) and `ux-strings.test.mjs` (every inventory string has an entry, no entry without an inventory string) went red, 4 of 36; reverted, `git diff --stat` identical to before, 36 of 36 green again.

Results: `(loop)` 36 of 36 pass; `(once)` the web unit suite 1587 of 1587 pass; the `grep` prints nothing. The e2e spec runs in CI only.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: the `documents.lookFor` string now reads the ruled text ("...in the chat, and look for the answer that comes from your file.") in the source and the three pins.
- Files changed (4 under `web/`, one string each): `web/src/app/guide/more-to-try-view.ts`, `web/e2e/guide/more-to-try.spec.ts`, `web/scripts/more-to-try-view.test.mjs`, `web/scripts/ux-strings.test.mjs`. EXPERIENCE.md and planning files untouched.
- Review: 0 high; patches applied 1 (mutation evidence recorded); deferred 1 (Documents page empty state "cited answers", medium, for the lead's ruling); rejected 4 rows with reasons in the triage log.
- Follow-up review recommended: false.
- Verification: `(loop)` 36 of 36; `(once)` 1587 of 1587; grep for the old string prints nothing; mutation observed red and reverted (see Verification). The e2e spec was not run (CI only).
- Residual risk: the Documents page's empty state still says "cited answers" (deferred above).
