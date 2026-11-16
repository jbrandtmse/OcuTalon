---
title: 'Story 23.15: 1.0.12 cut: partner mail says what happened, and the docs say who approves'
type: 'bugfix'
created: '2026-11-16'
status: 'ready-for-dev'
baseline_revision: '543f8bdf520bf22d1a7eb28066e78a6bcf71c93a'
baseline_commit: '543f8bdf520bf22d1a7eb28066e78a6bcf71c93a'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-13-partner-warnings-go-to-the-settings-contacts.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 23.13 (DW-1415 and DW-1416), five 1.0.12 cut items remain:
1. `docs/security-overview.md` doesn't state the admin-only approval rule for partner warnings (DW-1423).
2. `GUIDE.md` line 12 says that without demo mode no notice is drafted, which is no longer true (DW-1425).
3. On a may-have-sent result, the approval card and the chat still read "Not sent: …" or "was not sent", while the timeline reads may-have-sent. EmailOut's MESSAGEUNREACHABLE and MESSAGEFAILED are ambiguous: for an approval send, a timeout during DATA answers MESSAGEUNREACHABLE.
4. A mail server that accepted the message (250 after DATA) and then fails the QUIT makes EmailOut answer MESSAGEREJECTED ("so it wasn't sent"), for every email kind (DW-1422).
5. CI's shards-2 takes 31.9 of its 32 minutes.

**Approach:** Make one classifier the only source of the sent / may-have-sent / not-sent decision, and use it for the timeline, the card and the chat. Fix EmailOut at the source so that its sentences say what they mean: QUIT after 250 is sent, and a failure after the data began answers MESSAGEMAYHAVESENT for every claim. Land the Planner-approved texts verbatim. Move one live unit from shards-2 to shards-3.

Binding source: `{coordination}/prompts/dw-1415-1416-rulings-20261116.md`, sections "1.0.12 CUT STORY for lane B" and "23.15 text rulings" (Contest Planner, Nov 16, about 11:00Z and 12:30Z).

## Boundaries & Constraints

**Always:**
- **Approved texts, verbatim.**
  - **DW-1423, `docs/security-overview.md`, "Who may answer":** add the bullet `- a partner warning to Settings contacts can be approved only by a user who holds `OcuTalonAdmin`;` directly after the email bullet.
  - **DW-1423, the audit types list:** the `Action` line becomes `- `Action`: a fix run, a resend, a replayed tool call, Break the feed or a refused approve of a partner warning;` (the old "or" before "Break the feed" becomes a comma).
  - `bash docker/tests/test-security-overview.sh` stays green.
  - **DW-1425, `GUIDE.md` line 12:** replace everything after "not to a real inbox; " in the Partner delay notices bullet with: `on your own install the notice goes only to the partner contacts an admin set for that production in Settings > Partner contacts, by email from the mailbox connected in Settings > Channels > Email, and only an OcuTalon admin can approve it. With no mailbox connected, the approved notice is kept as a draft and nothing is sent.` Use GUIDE's existing `>` separator, never `›`. The sentence that follows ("Try it: …") is unchanged.
  - **New catalog key `result.partnerMaySent`** (no slots): `The delay notice may have been sent. Check the mailbox's Sent folder before sending it again.` It goes in the server catalog (`Msg/Catalog/Watch.cls`, with source "Story 23.15, Public Text ruled by the Contest Planner 2026-11-16 (prompts/dw-1415-1416-rulings-20261116.md, 23.15 text rulings)") and in the web catalog if the card renders through it. Nothing goes in front of it, and it never ends with "It needs a new approval".
- **One mapping (Planner CONDITION).** One server-side method decides a partner warning's send outcome, either `sent`, `maysent`, `notsent` or `kept`. The timeline (`Watch.Summary`), the chat result (`Watch.Notice`, the Settings-contact branch that today gives `fix.emailNotSent` / `result.partnerNotSent`) and the card all take the outcome from that one method.
  - The card gets the outcome from the server: a field in the request's result, or the result key the server chose. The web never re-derives it from the reason sentence.
  - The mapping:
    - **sent:** the run completed.
    - **may-have-sent:** MESSAGEMAYHAVESENT; and a run interrupted by a restart **after the send began**. Decide "after the send began" from the run or claim record (for example, EmailOut's claim row exists or the SendEmail was submitted). An interruption before the send began is not sent.
    - **not sent:** MESSAGEREFUSED, MESSAGENOTCONNECTED, MESSAGEREJECTED, MESSAGEREFUSEDLOGIN, MESSAGESIGNIN and MESSAGEUNAVAILABLE.
    - **MESSAGEUNREACHABLE and MESSAGEFAILED** are may-have-sent ONLY where EmailOut (or the executor's send wrapper) can return them after the message data was handed over; otherwise they are not sent. After Task 2 below, EmailOut answers MESSAGEMAYHAVESENT for every failure that `Sender.MayHaveSent` says may have reached the server, so MESSAGEUNREACHABLE means "never reached" (not sent). For MESSAGEFAILED, trace every path that returns it for a partner send, both in `Out.cls` (lines ~162, 198, 204, 211, 215) and in `Fix/Executor.cls` (~420, ~636) and `Core/BridgeSink.cls` (~378–389). Then do one of two things. (a) Where a path can only fire before `Transmit`, it is not sent. (b) Where a path can fire after `Transmit` began (an exception after the hand-over, an exception of the send in the executor), either make that path answer MESSAGEMAYHAVESENT, or carry a "send began" marker that the classifier reads. Never classify by a sentence that means both.
  - Write the final table, one row per answer with its line on each surface, into `## Design Notes` as "Final mapping table". It goes into the PART READY.
- **DW-1422, for every email kind.** In `Channel/Email/Sender.cls`, a failed `SMTP.Send` status whose errors are ALL QUIT-stage errors counts as sent. These are `$$$SMTPResponse` with first param `QUIT` (`%Net.SMTP.Send` line ~514: a non-2xx or empty QUIT reply), and `$$$SMTPConnectionFailed` with first param `QUIT` (the SendError path while writing or reading QUIT). `%Net.SMTP` sends QUIT only after the data terminator's 2xx when no error came first, and it doesn't check the QUIT reply when an earlier error is set, so "all errors are QUIT-stage" means the server accepted the message. Put the decision in one Sender method (for example `Accepted(sc)`) that `Out.Transmit`/`Send` uses, so that kind email, partner warnings, the digest and tool sends all get MESSAGESENT and the sent bookkeeping (Delivery record, claim marked sent). A status that also holds any other error is unchanged.
- **Task 2 (EmailOut at the source).** In `Out.Send`, when `Sender.MayHaveSent(sc)` is 1, answer MESSAGEMAYHAVESENT for every claim, approval claims included. Today only keyed tool claims (ApprovalRef "") get it, and an approval claim answers MESSAGEUNREACHABLE. Keep each claim's existing mark rule (an approval claim stays marked failed unless you show a reason to change it, and the class doc says which). MESSAGEMAYHAVESENT is existing approved text, so this needs no new public text. Update the class docs of `Out.cls` and `Sender.cls`, and `PartnerWarning`'s `MAYHAVESENTSENTENCES` and its doc, to the final table.
- **shards-2 (tests only, no limit raise).** Measured on CI run 43823569610, shards-2 was READY lane-a@rest 296 s, `shard:lane-a@rest` 1,250 s, `live:session-data` 338 s and `live:install-script-live` 299 s, for a 31.9-minute job. shards-3 was `live:floor` 659 s and `live:demo-switch` 530 s, for a 20.2-minute job. Move ONE live unit (prefer `live:install-script-live`, else `live:session-data`) from shards-2 to shards-3 in `ci/units.sh`, and update its comment block with these figures and the planned result (shards-2 about 26.9 min, shards-3 about 25.2 min). `bash docker/tests/test-ci-config.sh` passes. No timeout or limit changes.
- **One commit per item, in this order:** (1) DW-1423, (2) DW-1425, (3) the card and chat may-have-sent wording plus the one mapping, Task 2 included, (4) DW-1422, (5) shards-2. Each commit message names its item and ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. If (3) and (4) touch the same file, commit (4) first, or split by hunk, so each commit builds and its tests pass. The spec's own edits go with the last commit.
- **Pins, each with a demonstrated mutation** (record each mutation and the red it produced in Verification):
  - DW-1422: a QUIT-stage `SMTPResponse` alone gives sent; the same QUIT error plus an earlier error does not; `SMTPConnectionFailed` QUIT alone gives sent; one kind-email send and one partner send through the stub/mock SMTP each end sent.
  - Task 2: an approval send that times out during DATA answers MESSAGEMAYHAVESENT; a connect or EHLO failure still answers MESSAGEUNREACHABLE.
  - The one mapping: for EVERY row of the final table, the timeline line, the chat result key/text and the card band agree. At least: sent; MESSAGEMAYHAVESENT; interrupted after the send began; interrupted before it; MESSAGEUNREACHABLE (connect); each MESSAGEFAILED path; one each of REJECTED and REFUSEDLOGIN.
  - The card: a web unit test (`web/src/app/approvals/*.spec.ts`) for the may-have-sent band text equal to `result.partnerMaySent`, with no "Not sent". Add a real-HTTP or e2e pin only if the payload field is new on `/api/v1/state`, as the standing route rule asks.
  - The catalog: `Test.Msg.Catalog` count pins and any web/server catalog parity test updated.
- Reuse existing test helpers (the EmailOut stub/mock SMTP in `Test.Channel.EmailOut` and `Test.Partner.*`). Where a helper is private to another class, call through a public seam, or note the copy for DW-1417 (Story 23.14), never a silent copy.

**Ask First (HALT and write `Blocking condition`):**
- Any public text other than the approved lines above, including a changed EmailOut sentence or a new card text.
- Raising any CI limit, or moving more than one unit between shards.
- A change to `/api/v1/state`'s shape beyond one additive field.

**Never:**
- Write `›` in GUIDE.md, or reword an approved line.
- Classify a partner outcome anywhere except the one method (no second copy in the web or in Summary).
- Re-send an email automatically, or put a contact name or address into a trace, log, audit entry or FixRun.Reason.
- Edit `irislib/` or `irissys/`, or load/compile anything into slot B or any dev slot (lane-B throwaways only).
- Write an absolute local path into a tracked file.

</intent-contract>

## Code Map

- `docs/security-overview.md:148-161`: "Who may answer" and the audit types.
- `GUIDE.md:12`: the Partner delay notices bullet.
- `src/ocutalon/cls/OcuTalon/Channel/Email/Sender.cls`: `Classify`, `MayHaveSent` (~150-175), and the new QUIT-stage decision.
- `src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls`: the MESSAGE* parameters (~120-140), `Handle`'s MESSAGEFAILED paths (~155-215), `Send` (~229-262).
- `irislib/%Net/SMTP.cls:496-517` (Send's DATA/QUIT) and `:520-545` (SendError): read only.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls`: `OUTSENTENCES`, `MAYHAVESENTSENTENCES`, `MayHaveSent` (~71-76, ~290-300). This is the natural home of the one classifier.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls:190-200`: the timeline key.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls`: KEYPARTNERNOTSENT, KEYEMAILNOTSENT, and the partner result branch (doc ~50-56).
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls:~410-425, ~610-640`: the send wrappers' MESSAGEFAILED.
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls:~365-390`: the reason sentence for a run.
- `web/src/app/approvals/approval-view.ts:~30-90, ~700-760`: `partnerResultView` and APPROVAL_TEXTS.partnerNotSent / the `fix.emailNotSent` band.
- `web/src/app/msg/catalog.ts`: the web catalog.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:~960-1090`: the partner keys.
- `ci/units.sh`: the shards-2 and shards-3 group lists and their comment.

## Tasks & Acceptance

**Execution (one commit per item, in this order):**
- [ ] (1) DW-1423: the two approved lines in `docs/security-overview.md`; the security-overview test stays green.
- [ ] (2) DW-1425: the approved replacement in `GUIDE.md:12`, with `>`; `bash docker/tests/test-readme.sh` and any GUIDE pin stay green.
- [ ] (4, committed before 3 if they share files) DW-1422: the Sender QUIT-stage decision used by `Out`, for every kind, with pins and mutations.
- [ ] (3) Task 2 (MESSAGEMAYHAVESENT for approval claims), the one classifier, `result.partnerMaySent`, and Summary, Notice and the card all reading the classifier; the final mapping table in Design Notes; pins and mutations for every row.
- [ ] (5) shards-2: move one live unit to shards-3, update the comment, and run `test-ci-config.sh`.

**Acceptance Criteria:**
- Given the security overview and GUIDE, when read, then they hold the approved lines verbatim (with `>` in GUIDE), and their doc tests pass.
- Given any partner-warning outcome, when the timeline, the chat and the card show it, then all three agree per the final mapping table, and none says "not sent" for an email that may have reached the server.
- Given any email kind whose server accepted the message and then failed the QUIT, when EmailOut answers, then it answers sent and records the delivery.
- Given CI, when it runs, then shards-2 has a unit fewer, no limit is raised, and `test-ci-config.sh` passes.

## Spec Change Log

## Design Notes

### Final mapping table
(The implementer fills this in: answer, then outcome, then the timeline key, the chat key/text and the card band, then the test that pins it.)

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`, each sized to about 150 s, never two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- Tags: fresh `e23b15i`, warm `e23b15iw`. At the end, also after a failure, run `ci/warm.sh down`, then `ci/iris.sh teardown` with each tag.
- Classes, at least: `Test.Channel.EmailOut`, `Test.Fix.Email`, `Test.Partner.PartnerMail`, `Test.Partner.PartnerApprove`, `Test.Fix.PartnerWarning`, `Test.Watch.Summary`, `Test.Watch.Notice` (if present), `Test.Msg.Catalog`, `Test.Channel.TelegramApproval`, plus any class that pins the touched docs; `npm --prefix web test`; `bash docker/tests/test-ci-config.sh`; `bash docker/tests/test-boundaries.sh`.

**Shared surfaces:** `Channel/Email/Out.cls` and `Sender.cls` serve every email kind, the digest and tool sends. Run `Test.Channel.EmailOut` (and the digest email test, if one exists) whole.
