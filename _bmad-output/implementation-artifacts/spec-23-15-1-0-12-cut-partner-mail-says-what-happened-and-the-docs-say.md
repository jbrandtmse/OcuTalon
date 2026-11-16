---
title: 'Story 23.15: 1.0.12 cut: partner mail says what happened, and the docs say who approves'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
baseline_revision: '377fa9c1674bfd9135d7bee9f63ed30b33d43ed0'
baseline_commit: '5d7e693e90f8c6283c2214bf3ee1c9bb7dda87eb'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-13-partner-warnings-go-to-the-settings-contacts.md'
warnings: []
deferred:
  - summary: >-
      Out.Began's read-error branch (answers 1, the safe default) has no test and no mutation.
    evidence: |-
      A forced SQL error in the claim lookup is hard to inject; the branch only chooses the safe answer when the claim row cannot be read.
    location: >-
      src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls (Began)
    severity: low
  - summary: >-
      The new MESSAGEMAYHAVESENT use for an internal exception after the hand-over reads "The mail server stopped answering", which is not true of that case; the sentence is existing approved text and the spec forbids changing it.
    evidence: |-
      Out.SendClaimed's catch and the executor wrappers (Fix.Kind.Email Unfinished/FailedMessage) answer MESSAGEMAYHAVESENT for an error that is not a server timeout. A wording that fits both needs a Planner text ruling (Ask First).
    location: >-
      src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls (MESSAGEMAYHAVESENT)
    severity: low
  - summary: >-
      web/e2e/cards/approval-card.spec.ts A13 (the may-have-sent card over GET /api/v1/state) was type-checked but not run.
    evidence: |-
      live:cards takes about 459 s beside a stack start; the first green run of A13 is CI's live:cards. The unit pins (approval-view.test.mjs, Test.Live.Payloads, Test.Watch.Summary) ran and have mutation lines.
    location: >-
      web/e2e/cards/approval-card.spec.ts
    severity: medium (unverified)
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
- [x] (1) DW-1423: the two approved lines in `docs/security-overview.md`; the security-overview test stays green.
- [x] (2) DW-1425: the approved replacement in `GUIDE.md:12`, with `>`; `bash docker/tests/test-readme.sh` and any GUIDE pin stay green.
- [x] (4, committed before 3 if they share files) DW-1422: the Sender QUIT-stage decision used by `Out`, for every kind, with pins and mutations.
- [x] (3) Task 2 (MESSAGEMAYHAVESENT for approval claims), the one classifier, `result.partnerMaySent`, and Summary, Notice and the card all reading the classifier; the final mapping table in Design Notes; pins and mutations for every row.
- [x] (5) shards-2: move one live unit to shards-3, update the comment, and run `test-ci-config.sh`.

**Rework iteration 1 (lead ruling on DW-1429; the Planner's CONDITION "a connect or EHLO failure keeps not sent" binds):**
- [x] [DW-1429] Make "may have reached the server" step-aware, for every email kind. Today `Sender.MayHaveSent` counts EVERY `$$$SMTPTimeout`, which names no step, so since 23.15 a timeout at the greeting, EHLO, STARTTLS, AUTH, MAIL FROM or RCPT TO answers MESSAGEMAYHAVESENT (claim maysent; card and chat `result.partnerMaySent`). The likeliest trigger is an implicit-TLS port (465) set without TLS. Fix: add a small subclass of `%Net.SMTP` in our own package (for example `OcuTalon.Channel.Email.SMTP`; never edit `irislib`), used wherever `Sender` makes its SMTP object. It overrides the Private `SendMessage(msg)` (`irislib/%Net/SMTP.cls:503`, called only after DATA's 354) to set a public property `DataBegan = 1` and then call `##super(msg)`, and it resets `DataBegan = 0` at the start of `Send`. `Sender.MayHaveSent(sc)` becomes 1 only when `DataBegan` is 1 AND the status is a timeout or a lost connection (keep the existing DATA-param check as a second reason). Any failure before the data began is not sent (MESSAGEUNREACHABLE, claim failed, `fix.emailNotSent`), and DW-1422's `Accepted` is unchanged. If `MayHaveSent` is a ClassMethod that takes only `sc`, give it the SMTP object's flag via the Sender instance (keep one decision method). The test stub/mock that stands in for `%Net.SMTP` must model `DataBegan` (the CI mock SMTP can stall at the greeting or after DATA's 354; reuse its existing modes, or add one `stall-greeting` mode only if none fits). Pins, each with a demonstrated mutation: a timeout at the greeting or EHLO answers MESSAGEUNREACHABLE and reads not sent on the timeline, the card and the chat; a timeout after the data began still answers MESSAGEMAYHAVESENT and reads may-have-sent; a keyed tool send behaves the same way (`TestToolKeySendsOnce` or its neighbour). Update the final mapping table's MESSAGEMAYHAVESENT and MESSAGEUNREACHABLE rows, `Out.cls`/`Sender.cls` class docs and `PartnerWarning`'s doc. Close DW-1429 in the spec's review records (the lead adjudicates it). Commit as ONE commit `fix(23.15): may-have-sent only once the message data began (DW-1429)`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; the spec goes in the same commit.

**Acceptance Criteria:**
- Given the security overview and GUIDE, when read, then they hold the approved lines verbatim (with `>` in GUIDE), and their doc tests pass.
- Given any partner-warning outcome, when the timeline, the chat and the card show it, then all three agree per the final mapping table, and none says "not sent" for an email that may have reached the server.
- Given any email kind whose server accepted the message and then failed the QUIT, when EmailOut answers, then it answers sent and records the delivery.
- Given CI, when it runs, then shards-2 has a unit fewer, no limit is raised, and `test-ci-config.sh` passes.

### Review Findings

Code review (cr stage, 2026-11-16; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 29 raw findings, 18 entries after grouping). Code review complete: 0 `decision-needed`, 9 `patch` (all applied), 2 `defer` (ledgered), 7 rejected.

- [x] [Review][Patch] (high) A13's real-HTTP pin had never run, and it was red: it looked for `outcome` in `GET /api/v1/state`, which holds no incident payload [web/e2e/cards/approval-card.spec.ts:585] — it now reads the published incident event over `GET /api/v1/events` (the route that serves it) for `outcome: maysent` on the may-have-sent request and none on the sent one; `ci/iris.sh live cards` green, mutation in Verification.
- [x] [Review][Patch] (medium) The card and the chat still worked out sent, not sent and kept from the counts and the reason; only maysent came from `SendOutcome` (intent Never: no second copy in the web) [web/src/app/approvals/approval-view.ts:733, src/ocutalon/cls/OcuTalon/Watch/Notice.cls:445] — the card's band now follows the server's `outcome` for all four values (the counts and the reason only pick the text of that answer), and `Notice.ResultKey` gives fix.emailSent from outcome sent; no row of the final table changes.
- [x] [Review][Patch] (medium) `SubmitApproved` turning an answered MESSAGEFAILED into MESSAGEMAYHAVESENT when the claim shows the send began had no test (row "MESSAGEFAILED: a pending claim") [src/ocutalon/cls/OcuTalon/Fix/Kind/Email.cls:224] — `Test.Fix.Email:TestAnsweredFailureAfterTheSendBegan` added.
- [x] [Review][Patch] (low) The card's agreement with the server was pinned only for maysent and two not-sent cases [web/scripts/approval-view.test.mjs] — new web test for sent, skipped, kept and not sent taken from `outcome`.
- [x] [Review][Patch] (low) `Sender`'s class doc and `Accepted`'s doc said %Net.SMTP sends QUIT only after the 2xx to the end of the message; it writes QUIT after any step past the greeting and checks its answer only when no error came first [src/ocutalon/cls/OcuTalon/Channel/Email/Sender.cls:24,159] — corrected, and the docs say the QUIT-stage SMTPConnectionFailed does not occur in this build.
- [x] [Review][Patch] (low) Stale docs: `Out.Send`, `Out`'s class doc (Began counts a sent claim too), `Fix.Kind.Email.Execute` and `Data.Delivery.FallbackReason` still said an approval's failed claim is always marked failed or that a command with no answer is always MESSAGEFAILED [Out.cls, Fix/Kind/Email.cls:202, Data/Delivery.cls:45] — corrected.
- [x] [Review][Patch] (low) Stale test texts: catalog.test.mjs titles said "nineteen result keys" (23 now); `Test.Fix.PartnerWarning.DropClaims` named a test that does not exist [web/scripts/catalog.test.mjs:132,142, Test/Fix/PartnerWarning.cls:818] — corrected.
- [x] [Review][Patch] (low) `Test.Partner.PartnerMail.ClaimId` is a silent copy of `Test.Channel.EmailOut`'s private ClaimId [Test/Partner/PartnerMail.cls:309] — noted for DW-1417 (Story 23.14) in its doc, as the intent asks.
- [x] [Review][Patch] (low) `Test.Watch.Summary:TestSettingsContactMayHaveSent` ignored the status of the claim it writes, so the row "the claim marked failed" passed whether or not the claim existed [Test/Watch/Summary.cls:854] — asserted.
- [x] [Review][Defer] (medium) DW-1422 remainder: a connection lost on QUIT reads `SMTPConnectionFailed` with step DATA in this %Net.SMTP (its `cmd` is never QUIT, and SendError overwrites an earlier error), so it is may-have-sent, not sent; `quitlost`/`quitafter` are synthesized statuses [Channel/Email/Sender.cls Accepted] — deferred: routed to 23.14 under DW-1422, per the Planner's "anything left over stays in 23.14".
- [x] [Review][Defer] (medium) An approval or partner send whose greeting, EHLO, MAIL FROM or RCPT TO times out now answers MESSAGEMAYHAVESENT (SMTPTimeout names no step), so "it may have gone out" and "may have been sent" are shown for a message the server never received [Channel/Email/Sender.cls MayHaveSent, Out.cls Send] — deferred: DW-1429, decision-pending for the Planner with the MESSAGEMAYHAVESENT wording item; Task 2 requires the rule, and it errs safe. CLOSED (rework iteration 1): `Sender.MayHaveSent` now needs the message data to have begun (`Channel.Email.SMTP` `DataBegan`), so a timeout at the greeting, EHLO, STARTTLS, AUTH, MAIL FROM, RCPT TO or DATA answers MESSAGEUNREACHABLE and reads not sent; a timeout after the data began is still may-have-sent.

Rejected:
- (low) "Send began" is coarser than the hand-over: `SendBegan` is set just before `Deliver`, and a pending claim counts as begun before `Transmit` builds the message, so an internal exception or a stop in that window reads maysent — errs safe, needs an internal exception or a stop inside microseconds; a finer marker adds state.
- (low) A cut-short run, or a wrapper failure, after EmailOut marked the claim sent reads maysent, not sent — the final table groups pending, maysent and sent claims as maysent (spec-bound), and "may have been sent" is not false for a sent email.
- (low) A cut-short run's maysent is recomputed from the claim, so a claim purged by retention would turn it notsent — needs an incident still open past the Delivery retention with a cut-short partner run; persisting the decision adds a write path.
- (low) `BridgeSink.EmailReason` gives an interrupted plain email MESSAGEFAILED without reading `Began` — out of the spec's scope, and MESSAGEFAILED's text ("may not have finished") is not false.
- (low) A13 cannot fail on the server's computation, since it publishes the outcome itself — the server half is pinned against real IRIS by `Test.Watch.Summary` and `Test.Live.Payloads`; A13 pins the member over real HTTP and the card.
- (low) `approval-view.test.mjs` re-renders `result.partnerMaySent` with the same renderer — redundant, not vacuous: the literal text in the `deepEqual` above it is the pin.
- (low) `SendBegan` stays 1 after a definite failure, so an exception in the claim bookkeeping after it would answer maysent — errs safe; nothing there realistically throws.
- (low) The spec's `deferred:` A13 entry uses `severity: medium (unverified)` — the fix edits the spec under review (and A13 has now run).

Code review, rework re-review (cr stage, 2026-11-16, iteration 1 of 3, `377fa9c16..HEAD`, DW-1429; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 15 raw findings, 12 entries after grouping). 0 `decision-needed`, 4 `patch` (all applied), 1 `defer` (ledgered), 7 rejected. No high. Checklist: `Channel.Email.SMTP`'s `Send` and `SendMessage` match `%Net.SMTP`'s signatures (`irislib/%Net/SMTP.cls:360`, `:550`), `##super` reaches the parent (over the wire, and the `SendMessage` mutation re-run here turns `Test.Fix.Email:TestSmtpKnowsWhenTheDataBegan` red), `SendMessage` runs only after DATA's 354 (`:503`, and the nested message of `SendMultiPart`), and `Send` clears the flag; the parent adapter builds its client with `SMTPNewObject()` from the declared type, and `Sender` is the only product class that touches `..SMTP` (SSL, STARTTLS, identity check and the OAuth2 authenticator unchanged); `Out.Send` is the only product caller of `Sender.MayHaveSent` and passes `..DataBegan()`; `Accepted` is unchanged; the mock's stall modes are set only by `Test.Fix.Email` (its `Setup` resets the stub, the test resets it at its end), each lane's stack has its own mock.
- [x] [Review][Patch] (medium) The mock's `stall-greeting` node test read the connection count after a fixed sleep without waiting for the client's connect (Rule 19 readiness) [ci/mock/test/smtp.test.mjs] — it now awaits `connect` before the sleep; `node --test ci/mock/test` 192 passed.
- [x] [Review][Patch] (low) `TestOutReadsTheAdaptersDataBegan`'s "a host with no adapter" check ran with an adapter (a shadow instance gets one from `ADAPTER`), so `Out.DataBegan`'s `$IsObject(..Adapter)` guard was run by no test [Test/Channel/EmailOut.cls:1433] — the probe's `Adapter` is now emptied first; mutation in Verification.
- [x] [Review][Patch] (low) `Test.Channel.EmailOut`'s class doc did not list `TestOutReadsTheAdaptersDataBegan` [Test/Channel/EmailOut.cls:69] — listed (the final table's "Pinned by" cells are left as they are: a spec edit).
- [x] [Review][Patch] (low) `Test.Channel.EmailOut`'s `TestNoDoubleSend` doc bullet still said a timeout is may-have-sent without "once the message data began" [Test/Channel/EmailOut.cls:66] — corrected.
- [x] [Review][Defer] (low) A claimed send whose server greeted and then timed out before the 354 reads MESSAGEUNREACHABLE "OcuTalon couldn't reach the mail server", which is coarse (the not-sent outcome is the ruled one; only the wording) — DW-1431, `wontfix-accepted` with `reopen_if`; changing the sentence is Ask First.

Rejected (re-review):
- (low) `DataBegan` is set before `##super` writes the headers, so a connection lost mid-body reads may-have-sent although the message was never terminated — the lead's DW-1429 item says "set DataBegan = 1 and then call ##super" and keeps the DATA-param check; it errs safe, and a write error on a TCP device rarely surfaces before the read.
- (low) An exception from `Deliver` before the 354 still answers MESSAGEMAYHAVESENT (`SendBegan`) — the final table's "exception after Transmit began" row; carried from both earlier passes.
- (low) Two mock modes where the item allowed one — decided in-stage: `stall-data` is what lets the wire test show a timeout after the data began; CI mock only.
- (low) The commit message says every failure before the data answers MESSAGEUNREACHABLE with the claim marked failed (a keyed claim is deleted; refused and rejected keep their sentences) — commit history is not rewritten; the code and the class docs are right.
- (low) The final table's "Pinned by" cells and the triage log's reject count — the fix edits the spec under review.
- (false) An EHLO timeout is pinned only with a synthetic status — `%Net.SMTP` gives the same `SMTPTimeout` with no step for every timeout, and the outcome depends only on `DataBegan`, which no step before the 354 sets.
- (false) The implementer closed DW-1429 in the review records — the item told it to; the lead adjudicates the ledger entry.

## Spec Change Log

- 2026-11-16 ~11:20Z (lead, rework iteration 1 of 3, trigger: code review DW-1429, decision-pending → lead ruling under the Planner CONDITION): step-aware may-have-sent.

## Design Notes

### Final mapping table

One method decides the outcome: `Fix.Kind.PartnerWarning.SendOutcome(ref, state, completed, skipped, interrupted, reason, simulated)` gives `sent`, `maysent`, `notsent` or `kept`. `Watch.Summary.RunEvents` (the timeline), `Watch.Notice.ResultKey` (the chat) and `Live.Payload.Incident` (the request result's `outcome` member, through `PartnerWarning.ResultOutcome`; the card's band follows it) all take it from there. The web never works it out from a reason sentence. "Chat" is the key `Watch.Notice.ResultKey` gives for a Settings contact (simulated 0); its text is the catalog's. The timeline lines are `summary.*`, the chat and the card are `result.*` or `fix.*`.

How an answer gets to the classifier. EmailOut answers `MESSAGEMAYHAVESENT` for every claimed send (an approval's claim as a keyed tool send's) whose failure `Sender.MayHaveSent` says may have reached the server (a timeout or a connection lost during DATA, once the message data began: DW-1429, `Channel.Email.SMTP` `DataBegan`, which is 1 only from the server's 354 answer to DATA on), and for an exception after `Transmit` handed the message to `Deliver` (`SendBegan`); the claim is then marked `maysent`, and a repeat answers the same. `Fix.Kind.Email.SubmitApproved` and the executor's two exception paths (`Executor.SendEmail`, `Executor.SendPartner`) turn a `MESSAGEFAILED` that did not come from EmailOut into `MESSAGEMAYHAVESENT` when the approval's claim shows that the send began (`Out.Began`: a claim that is pending, maysent or sent). So a `MESSAGEFAILED` that reaches the classifier says that nothing was handed over, and a `MESSAGEUNREACHABLE` says that the message data never began (the server was never reached, or it never answered the greeting, EHLO, STARTTLS, AUTH, MAIL FROM, RCPT TO or DATA). A send with no claim (a tool send with no key) keeps its class's sentence; it is never a partner notice. DW-1422: a status whose errors are all about QUIT (`Sender.Accepted`) is `MESSAGESENT`, for every kind of email and the digest.

| Answer (run) | Outcome | Timeline (`Watch.Summary`) | Chat (`Watch.Notice.ResultKey`) | Card band (`outcome` and the result) | Pinned by |
|---|---|---|---|---|---|
| Run completed, every recipient sent (MESSAGESENT) | sent | `summary.fixEnded` with the counts | `fix.emailSent` | `fix.emailSent` | `Test.Watch.Summary:TestSettingsContactMayHaveSent` row "sent"; `approval-view.test.mjs` |
| Done, some recipients skipped | sent | `summary.fixEnded` | `result.partnerSkipped` | `result.partnerSkipped` | same, row "sent to some"; `approval-view.test.mjs` |
| Done, every recipient skipped | notsent | `summary.partnerNotSent` | `result.partnerSkipped` (sent 0) | `result.partnerSkipped` | same, row "every recipient skipped" |
| Failed with the kind's NOTSETUP reason (no mailbox) | kept | `summary.partnerKept` | `result.partnerKept` | `result.partnerKept` | same, row "kept as a draft" |
| MESSAGEMAYHAVESENT (a timeout or a lost connection during DATA once the message data began (`DataBegan`), an exception after the hand-over, or a MESSAGEFAILED turned by the wrappers because the claim shows the send began) | maysent | `summary.partnerMaySent` | `result.partnerMaySent` | `result.partnerMaySent` (outcome maysent, whatever the reason) | `Test.Channel.EmailOut:TestNoDoubleSend` (the Out answers and claims), `:TestMayHaveSentNeedsTheDataBegan`, `Test.Partner.PartnerMail:TestTimeoutIsMayHaveSentOnlyOnceTheDataBegan`, `Test.Fix.Email:TestSmtpKnowsWhenTheDataBegan` (over the wire), `Test.Fix.PartnerWarning:TestSettingsContactsSendFailed`, `:TestFailedMessageKnowsWhetherTheSendBegan`, `Test.Watch.Summary` row "MESSAGEMAYHAVESENT"; `approval-view.test.mjs` |
| Run interrupted by a restart after the send began (EmailOut's claim pending, maysent or sent) | maysent | `summary.partnerMaySent` | `result.partnerMaySent` | `result.partnerMaySent` | `Test.Watch.Summary` rows "cut short after the send began"; `Test.Fix.PartnerWarning:TestSendOutcome` |
| Run interrupted by a restart before the send began (no claim, or a claim marked failed) | notsent | `summary.partnerNotSent` | `result.interrupted` (as before, no new text) | no band (no reason to give) | `Test.Watch.Summary` rows "cut short before the send began" and "the claim marked failed" |
| MESSAGEUNREACHABLE (the message data never began: connect, TLS, a timeout or a lost connection at the greeting, EHLO, STARTTLS, AUTH, MAIL FROM, RCPT TO or DATA before the 354) | notsent | `summary.partnerNotSent` | `fix.emailNotSent` {reason} | `fix.emailNotSent` | `Test.Channel.EmailOut:TestNoDoubleSend` (unreachable, lost, timeoutearly and droppedearly answer MESSAGEUNREACHABLE, claim failed), `:TestToolKeyFailureClasses` (the keyed send), `Test.Partner.PartnerMail:TestTimeoutIsMayHaveSentOnlyOnceTheDataBegan` (a partner send, the classifier and the chat); `Test.Watch.Summary` row (the timeline, the card and the chat) |
| MESSAGEFAILED: `Out.OnSendEmail` catch, the lock not taken, the claim not written, a repeat of a claim marked failed, an exception in `SendClaimed` before `Transmit` | notsent | `summary.partnerNotSent` | `fix.emailNotSent` | `fix.emailNotSent` | `Test.Channel.EmailOut:TestNoDoubleSend`, `Test.Watch.Summary` row |
| MESSAGEFAILED: an exception in `SendClaimed` after `Transmit` began | maysent (Out answers MESSAGEMAYHAVESENT, claim maysent) | `summary.partnerMaySent` | `result.partnerMaySent` | `result.partnerMaySent` | `Test.Channel.EmailOut:TestNoDoubleSend` (approval) and `TestToolKeySendsOnce` (key) |
| MESSAGEFAILED: a pending claim, CommandsIn's failure or empty answer, an exception of the executor's send (`SubmitApproved`, `Executor.SendEmail`, `Executor.SendPartner`) | maysent when the claim shows the send began (the wrappers answer MESSAGEMAYHAVESENT), else notsent | as the two rows above | as the two rows above | as the two rows above | `Test.Fix.PartnerWarning:TestFailedMessageKnowsWhetherTheSendBegan`, `:TestSettingsContactsSendFailed` (throw with a pending claim, and without a claim); `Test.Fix.Email:TestCommandsInGivesNoAnswerEndsFailed` (no claim stays MESSAGEFAILED) |
| MESSAGEREFUSED, MESSAGENOTCONNECTED, MESSAGEREJECTED, MESSAGEREFUSEDLOGIN, MESSAGESIGNIN, MESSAGEUNAVAILABLE | notsent | `summary.partnerNotSent` | `fix.emailNotSent` {reason} | `fix.emailNotSent` | `Test.Watch.Summary` rows (one each); `Test.Fix.PartnerWarning:TestSendOutcome` |
| A failure that is only the answer to QUIT (the server took the message; DW-1422) | sent (MESSAGESENT) | `summary.fixEnded` | `fix.emailSent` | `fix.emailSent` | `Test.Channel.EmailOut:TestAccepted`, `:TestQuitStageIsSent`; `Test.Partner.PartnerMail:TestQuitStageIsSent`; `Test.Fix.Email:TestQuitFailureAfterTheMailIsSent` |
| The demo's simulated contact (any answer) | sent, kept or notsent (never maysent) | `summary.partnerSent`, `summary.partnerKept` or `summary.partnerNotSent` | the 23.5 keys | the 23.5 bands (the card has no `outcome` for it) | `Test.Watch.Summary:TestSettingsContactMayHaveSent` (the simulated half, kept as before), `Test.Fix.PartnerWarning:TestSendOutcome` |

`MESSAGEFAILED` paths traced: `Channel/Email/Out.cls` (`OnSendEmail` catch, `SendClaimed` lock, claimed failed/pending, `Record` error and catch), `Fix/Executor.cls` (`SendEmail` catch, `SendPartner` catch and default), `Fix/Kind/Email.cls` (`SubmitApproved` default, no answer, error status) and `Core/CommandsIn.cls` (a failed or empty answer, which the executor's wrapper reads through the claim). `Core/BridgeSink.cls` only lists the sentences that a standalone email's notice may show as its reason (`EmailReasons`); it classifies nothing and is unchanged.

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`, each sized to about 150 s, never two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- Tags: fresh `e23b15i`, warm `e23b15iw`. At the end, also after a failure, run `ci/warm.sh down`, then `ci/iris.sh teardown` with each tag.
- Classes, at least: `Test.Channel.EmailOut`, `Test.Fix.Email`, `Test.Partner.PartnerMail`, `Test.Partner.PartnerApprove`, `Test.Fix.PartnerWarning`, `Test.Watch.Summary`, `Test.Watch.Notice` (if present), `Test.Msg.Catalog`, `Test.Channel.TelegramApproval`, plus any class that pins the touched docs; `npm --prefix web test`; `bash docker/tests/test-ci-config.sh`; `bash docker/tests/test-boundaries.sh`.

**Shared surfaces:** `Channel/Email/Out.cls` and `Sender.cls` serve every email kind, the digest and tool sends. Run `Test.Channel.EmailOut` (and the digest email test, if one exists) whole.

### Implement stage record (Story 23.15; warm stack `e23b15iw`, fresh stack `e23b15i`, lane B; each change reverted from a backup in the scratch folder, `git diff --stat` unchanged afterwards, the class green again)

Item 1 (DW-1423) and item 2 (DW-1425), `docker/tests/test-readme.sh` rules `docs` and `guide` (new pins, each with an `st` self-test that applies a mutation to a copy and must turn the rule red; all rules passed):
- mutation: the admin-only bullet removed from `docs/security-overview.md` -> rule `docs` red; the same bullet reworded (`approved only by` -> `approved by`) -> red; moved to the end of the list -> red; the Action line without the refused approve -> red.
- mutation: the Partner delay notices bullet of `GUIDE.md` back to "no notice is drafted" -> rule `guide` red; a `\u203a` in its path -> red; without its admin clause -> red.
- `bash docker/tests/test-security-overview.sh` all checks passed.

Item 4 (DW-1422):
- mutation: `Out.Transmit` without its `Sender.Accepted` line -> `Test.Channel.EmailOut:TestQuitStageIsSent` red (tool, keyed tool, approved and digest sends, for a QUIT answer and for a QUIT connection failure), `Test.Partner.PartnerMail:TestQuitStageIsSent` red (the partner send) and, over the real `%Net.SMTP` wire against the CI mock's new failure mode `quit` (QUIT answered 421 after the mail was kept), `Test.Fix.Email:TestQuitFailureAfterTheMailIsSent` red (the production restarted with the mutated class: a fresh warm stack).
- mutation: `Sender.Accepted` accepts any status that holds a QUIT error, whatever else it holds -> `Test.Channel.EmailOut:TestAccepted` red (a QUIT answer after an RCPT TO error, and after a lost connection during DATA, are not accepted) and `TestQuitStageIsSent` red (the "quitafter" answer, a QUIT error after an earlier error, must stay a failed send).
- The QUIT-stage `SMTPConnectionFailed` (first parameter QUIT) is pinned on a synthesized status only: in this build `%Net.SMTP` never sets its `cmd` to QUIT, so a connection that fails while QUIT is written reads `DATA` and counts as may-have-sent (the safe answer), not as sent. The `SMTPResponse` QUIT status (a non-2xx or empty answer) is what the mock produces and the only one that occurs.

Item 3 (the one mapping, Task 2, `result.partnerMaySent`):
- mutation: `Out.Send` marks a claim maysent only for a keyed tool send (the old rule) -> `Test.Channel.EmailOut:TestNoDoubleSend` red (timeout and dropped answer MESSAGEMAYHAVESENT, claim maysent, `Began` 1, a repeat answers the same).
- mutation: `Out.SendClaimed`'s catch ignores `SendBegan` -> `TestNoDoubleSend` red (an exception after the hand-over) and `TestToolKeySendsOnce` red (the keyed send).
- mutation: `PartnerWarning.SendOutcome` calls a cut-short run maysent without reading the claim -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red (rows "cut short before the send began" and "the claim marked failed", for the timeline, the chat and the card).
- mutation: `Summary.RunEvents` maps maysent to `summary.partnerNotSent` -> `TestSettingsContactMayHaveSent` red (the end lines in order, and "the may-have-sent line has slots").
- mutation: `Notice.ResultKey` without its maysent line -> `TestSettingsContactMayHaveSent` red (row "MESSAGEMAYHAVESENT": the chat reads `result.partnerMaySent`); with the interrupted line back to `result.interrupted` for every cut-short run -> red (rows "cut short after the send began").
- mutation: `Live.Payload.Incident` never sets the result's `outcome` -> `TestSettingsContactMayHaveSent` red (every row's card outcome).
- mutation: `MAYHAVESENTSENTENCES` with `MESSAGEUNREACHABLE` added -> `Test.Fix.PartnerWarning:TestMayHaveSent`, `:TestSendOutcome` and `:TestSettingsContactsSendFailed` red.
- mutation: `Fix.Kind.Email.FailedMessage` without its claim check -> `Test.Fix.PartnerWarning:TestFailedMessageKnowsWhetherTheSendBegan` red and `:TestSettingsContactsSendFailed` red (a send that threw with a pending claim must end MESSAGEMAYHAVESENT).
- mutation: the text of `result.partnerMaySent` with " It needs a new approval." added -> `Test.Msg.Catalog:TestEveryKeyOnEveryChannel` red (every channel's text is the fixture's).
- mutation: `approval-view.ts` never reads the result's `outcome` (the may-have-sent branch made `false`) -> `node --test web/scripts/approval-view.test.mjs` red ("reads the may-have-sent band from the server's outcome, with the text of result.partnerMaySent and no \"Not sent\"").
- Real-HTTP pin: the incident payload's request result gains one additive member, `outcome`, so `web/e2e/cards/approval-card.spec.ts` A13 now publishes a Settings-contact request whose result says maysent, reads `GET /api/v1/state` for the member and expects the band text of `result.partnerMaySent` on the card. Not run here: the `cards` unit takes about 459 s on CI beside the start of a stack, and the spec compiles under `tsc -p web/tsconfig.e2e.json`; left to CI (`live:cards`).

Item 5 (shards-2):
- mutation: `live:install-script-live` put back in shards-2 (and out of shards-3) in `ci/units.sh` -> `bash docker/tests/test-ci-config.sh` red (rule `inputs`, whose expected group for that script's declared input is now shards-3). `docker/tests/test-ci-config.sh` and `docker/tests/test-ci-changes.sh` pass with the move, and `docker/tests/test-boundaries.sh` all rules passed.

Runs, all passed unless noted. Warm `e23b15iw`: `Test.Channel.EmailOut`, `Test.Partner.PartnerMail`, `Test.Fix.PartnerWarning`, `Test.Watch.Summary`, `Test.Msg.Catalog`, `Test.Live.Payloads`, `Test.Fix.Email` (whole, with the new wire test), `Test.Partner.PartnerApprove`, `Test.Partner.PartnerTurns` (whole, 155 s), `Test.Channel.TelegramApproval`, `Test.Core.BridgeSink`, `Test.Fix.Executor`, `Test.Fix.PartnerDraft`; fresh `e23b15i`: `Test.Partner.PartnerTurns:TestSettingsContactsSentOnce`. `npm --prefix web test` 2186 passed; `node --test ci/mock/test/smtp.test.mjs` (with the new `quit` mode) passed; `bash docker/tests/test-readme.sh` all rules passed. Initial web bundle: 897.10 kB of JS and CSS (the Angular build's own figure), under the 1 MB cap.

### Review pass record (Story 23.15; warm stack `e23b15iw`, lane B; each change restored from a backup in the scratch folder, `git status --short` identical afterwards, the class green again)

Patches made after the review, each with its mutation:
- mutation: `Out.Transmit` without `Set ..SendBegan = 1` before `Deliver` -> `Test.Channel.EmailOut:TestNoDoubleSend` red (an error after the message was handed over answers MESSAGEMAYHAVESENT, marks the claim maysent, and a repeat answers the same) and `:TestToolKeySendsOnce` red. The flag moved from `Send` into `Transmit`, so an error while the message is built keeps the claim failed.
- mutation: `Fix.Kind.Email.SubmitApproved` answers MESSAGEFAILED for an error status or no answer (the old line) -> `Test.Fix.Email:TestCommandsInGivesNoAnswerAfterTheSendBegan` red (fail and empty answers, claim pending: MESSAGEMAYHAVESENT expected; a claim marked failed stays MESSAGEFAILED).
- mutation: `Executor.SendEmail`'s catch back to the literal MESSAGEFAILED result -> `Test.Fix.Executor:TestEmailSendThatFailsAfterTheClaimEndsMayHaveSent` red.
- mutation: `Out.Send` marks a maysent claim for every failed send (`If 1`) -> `Test.Channel.EmailOut:TestNoDoubleSend` red (a connect or EHLO failure must still answer MESSAGEUNREACHABLE, claim failed).
- mutation: `Sender.Accepted` without the `SMTPConnectionFailed` alternative -> `TestAccepted` red and `TestQuitStageIsSent` red (quitlost); without the `QUIT` first-parameter check -> `TestAccepted` red (an answer to RCPT TO or a lost connection during DATA, alone, is not accepted) and `TestDigestFailures` red. The `count > 0` guard cannot be pinned (`DecomposeStatus` gives at least one error for any failed status); `TestAccepted` asserts that a failed status of 0 is not accepted.
- mutation: `PartnerWarning.SendOutcome`'s closing `Quit "notsent"` made `Quit "sent"` -> `Test.Fix.PartnerWarning:TestSendOutcome` red and `Test.Watch.Summary:TestSettingsContactLines` and `:TestSettingsContactMayHaveSent` red (every notsent row: skipped every recipient, MESSAGEFAILED before the hand-over, MESSAGEUNREACHABLE, MESSAGEREFUSED, MESSAGENOTCONNECTED).
- mutation: `MAYHAVESENTSENTENCES` with `MESSAGEFAILED` added -> `TestSettingsContactMayHaveSent` red (MESSAGEFAILED before the hand-over: card outcome and chat key); with `MESSAGEREJECTED,MESSAGEREFUSEDLOGIN` added -> red (their card outcome and chat key).
- mutation: `SendOutcome` without its kept line -> `Test.Watch.Summary:TestPartnerLines` and `:TestSettingsContactLines` red; without its `completed > 0` line -> `TestPartnerLines` and `TestSettingsContactLines` red (sent, and sent to some).
- mutation: `Live.Payload.Incident` sets `outcome` for every kind -> `Test.Live.Payloads:TestFromRowRequestResult` red; `PartnerWarning.ResultOutcome` without its simulated guard -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red (the demo's incident payload holds no `outcome` member).
- mutation: the CI mock's `quit` mode answering `221 bye` -> `node --test ci/mock/test/smtp.test.mjs` red ("failure mode quit keeps the mail and answers QUIT with a 421").
- `Test.Fix.PartnerWarning:TestSettingsContactsSendFailed` sets `host.MailIs` to `throw` itself before its claim case.
- `docker/tests/test-readme.sh` writes the single angle quote of its guide pin as an octal escape (`test-boundaries.sh` ascii rule).

Runs after the patches (warm `e23b15iw`, all passed): `Test.Channel.EmailOut`, `Test.Partner.PartnerMail`, `Test.Fix.Email`, `Test.Fix.PartnerWarning`, `Test.Fix.Executor`, `Test.Watch.Summary`, `Test.Live.Payloads`, `Test.Partner.PartnerApprove`, `Test.Partner.PartnerTurns` (155 s), `Test.Channel.TelegramApproval`; `npm --prefix web test` 2186, `node --test ci/mock/test`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-readme.sh`, `test-security-overview.sh` and `test-boundaries.sh` all passed. The warm stack and the `e23b15i` tag are torn down.

### Code review record (Story 23.15, cr stage; fresh `e23b15cr`, warm `e23b15crw`, lane B; each mutation restored from a backup in the scratch folder, compared byte for byte, the class or unit green again)

- A13 first run, as committed: `ci/iris.sh live cards` red (31 passed, A13 failed: "the state carries the outcome of the request's result"; `GET /api/v1/state` holds no incident payload). Patched to read the incident event over `GET /api/v1/events`; then green (32 passed).
- mutation: `approval-view.ts` may-have-sent branch made `false` (bundle rebuilt with `ci/iris.sh build`) -> `ci/iris.sh live cards` A13 red ("the may-have-sent band is the catalog's text": the card read EmailOut's sentence), after its new real-HTTP assertions (`outcome` maysent on the event, none on the sent request) had passed; restored, rebuilt, 32 passed.
- mutation: `approval-view.ts` outcome branches for kept and for sent/notsent made `false` -> `node --test web/scripts/approval-view.test.mjs` red ("takes sent, not sent and kept from the server's outcome too, never from the counts or the reason").
- mutation: `Notice.ResultKey`'s `If outcome = "sent" Quit ..#KEYEMAILSENT` made `If 0` -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red ("sent: the chat reads fix.emailSent").
- mutation: `Fix.Kind.Email.SubmitApproved`'s answered failure back to `(answered.Message)` -> `Test.Fix.Email:TestAnsweredFailureAfterTheSendBegan` red ("failed/pending: the reason is MESSAGEMAYHAVESENT only for MESSAGEFAILED with a claim that began").

Runs after the patches, all passed: warm `e23b15crw` `Test.Channel.EmailOut`, `Test.Fix.PartnerWarning`, `Test.Watch.Summary`, `Test.Fix.Email` (37 to 39 s), `Test.Live.Payloads`, `Test.Partner.PartnerMail`; fresh `ci/iris.sh live cards` 32 passed; `npm --prefix web test` 2187; `tsc -p web/tsconfig.e2e.json`; `test-ci-config.sh`; `test-boundaries.sh`. Both tags are torn down.

### Rework iteration 1 record (DW-1429, step-aware may-have-sent; warm `e23b15r1w`, lane B; each mutation restored from a backup in the scratch folder, compared byte for byte, `git status --short` identical afterwards, the class green again)

The decision: `Channel.Email.SMTP` (a `%Net.SMTP` subclass of ours, the type of the adapter's `SMTP` property in `Sender`) sets `DataBegan` to 1 in its override of the private `SendMessage` (called only after DATA's 354) and to 0 when `Send` starts; `Sender.SendMail` also resets it, and `Sender.DataBegan()` reads it. `Sender.MayHaveSent(sc, dataBegan)` is the one decision: 1 only when `dataBegan` is 1 and the status is a timeout or a connection lost during DATA; `Out.Send` passes `..DataBegan()`. `Accepted` (DW-1422) is unchanged. The CI mock's SMTP stub gained two failure modes, `stall-greeting` (the connection is accepted and no greeting is sent) and `stall-data` (the end of the message is never answered), because none of its modes stalls; its node tests pin them.
- mutation: `Sender.MayHaveSent` without its `If '$Get(dataBegan) Quit 0` line -> `Test.Channel.EmailOut:TestMayHaveSentNeedsTheDataBegan` red (a timeout and a connection lost during DATA with the data not begun, and with no flag, are never may-have-sent), `:TestNoDoubleSend` red (`timeoutearly` and `droppedearly` answer MESSAGEUNREACHABLE, claim failed, a repeat MESSAGEFAILED), `:TestToolKeyFailureClasses` red (the keyed send of both: the sentence of its class, no claim, the key sent again), `Test.Partner.PartnerMail:TestTimeoutIsMayHaveSentOnlyOnceTheDataBegan` red (`timeoutearly`: MESSAGEUNREACHABLE, claim failed, the classifier says notsent, the chat `fix.emailNotSent`) and `Test.Fix.Email:TestSmtpKnowsWhenTheDataBegan` red (stall-greeting: MayHaveSent 0).
- mutation: `Out.Send` calls `MayHaveSent(sc)` with no flag (a timeout after the data began is no longer may-have-sent) -> `Test.Channel.EmailOut:TestNoDoubleSend` red (`timeout` and `dropped` of an approval: MESSAGEMAYHAVESENT, claim maysent, `Began` 1, a repeat answers the same), `:TestToolKeyFailureClasses` red (the keyed tool send, the same) and `Test.Partner.PartnerMail:TestTimeoutIsMayHaveSentOnlyOnceTheDataBegan` red (`timeout`: MESSAGEMAYHAVESENT, claim maysent, the classifier says maysent, the chat `result.partnerMaySent`).
- mutation: `Channel.Email.SMTP.SendMessage` without `Set ..DataBegan = 1` -> `Test.Fix.Email:TestSmtpKnowsWhenTheDataBegan` red over the wire (`none` and `stall-data`: DataBegan 1 expected; `stall-data`: MayHaveSent 1 expected).
- mutation: `Channel.Email.SMTP.Send` without `Set ..DataBegan = 0` -> `Test.Fix.Email:TestSmtpKnowsWhenTheDataBegan` red (one SMTP object for every mode: `stall-greeting` and `error`, after a send whose data began, keep DataBegan 1).
- mutation: `Sender.SendMail` without its `Set ..SMTP.DataBegan = 0` line -> `Test.Channel.EmailOut:TestMayHaveSentNeedsTheDataBegan` red ("and does not keep the flag of the send before it": a send that fails before the SMTP object is used after a send whose data began).
- `node --test ci/mock/test` passed (192, with the new `stall-greeting` and `stall-data` modes); the tests also pin that each mode keeps no mail.
- Runs, warm `e23b15r1w`, all passed after the restores: `Test.Channel.EmailOut` (the digest email's tests are in it), `Test.Fix.Email` (with the wire test), `Test.Partner.PartnerMail`, `Test.Fix.PartnerWarning`, `Test.Watch.Summary`, `Test.Fix.Executor`, `Test.Partner.PartnerApprove`. The final-table rows MESSAGEMAYHAVESENT and MESSAGEUNREACHABLE are updated; the Summary rows (timeline, card, chat) for both answers are the ones of the table and are unchanged, since the classifier reads the answer EmailOut gives and a greeting timeout now gives MESSAGEUNREACHABLE.

Rework iteration 1, review-pass patches (warm `e23b15r1w`, lane B; each change restored from a backup in the scratch folder, compared byte for byte, the class green again):
- mutation: `Out.DataBegan` made `Quit 0` -> `Test.Channel.EmailOut:TestOutReadsTheAdaptersDataBegan` red (a timeout with the adapter's data begun answers MESSAGEMAYHAVESENT, and its claim is marked maysent); every probe-based test alone had stayed green, since the probe replaced the method. The probe now answers Out's own `DataBegan` when `realflag` is set, and after a send through a real sender it answers that sender's flag, so it never reads a flag left by an earlier answer.
- mutation: `Sender.DataBegan` made `Quit 0` -> `TestMayHaveSentNeedsTheDataBegan` red ("the adapter's flag is the SMTP object's (1)") and `TestOutReadsTheAdaptersDataBegan` red.
- mutation: `Sender`'s `Property SMTP` back to `%Net.SMTP` -> `TestSenderInit` red ("the SMTP client is the one that knows when the message data began").
- mutation: the CI mock's `if (failure === 'stall-data') return;` removed -> `node --test ci/mock/test` red (1 failed of 192); the `stall-greeting` guard removed -> red (1 failed of 192).
- Runs after the patches, warm `e23b15r1w`, all passed: `Test.Channel.EmailOut`, `Test.Partner.PartnerMail`, `Test.Fix.PartnerWarning`, `Test.Fix.Email`, `Test.Watch.Summary` (and, earlier in the pass, `Test.Fix.Executor`, `Test.Partner.PartnerApprove`); `node --test ci/mock/test` 192 passed; `test-boundaries.sh` and `test-ci-config.sh` passed. The warm tag is torn down.

### Code review, rework re-review record (DW-1429; warm `e23b15cr2w`, lane B; each mutation restored from a backup in the scratch folder, compared byte for byte, `git status --short` identical afterwards, the class green again)

- mutation: `Out.DataBegan` without its `$IsObject(..Adapter) &&` guard -> `Test.Channel.EmailOut:TestOutReadsTheAdaptersDataBegan` red ("a host with no adapter has no data begun: a timeout answers MESSAGEUNREACHABLE"), now that the probe's `Adapter` is emptied first.
- mutation (re-run of the rework's): `Channel.Email.SMTP.SendMessage` without `Set ..DataBegan = 1` -> `Test.Fix.Email:TestSmtpKnowsWhenTheDataBegan` red over the wire (`none` and `stall-data`: DataBegan 1; `stall-data`: MayHaveSent 1).
- Runs, warm `e23b15cr2w`, all passed after the patches and restores: `Test.Channel.EmailOut`, `Test.Fix.Email`, `Test.Partner.PartnerMail`; `node --test ci/mock/test` 192 passed. The warm tag is torn down.

## Review Triage Log

### 2026-11-16 - Review pass
- verdicts: 32 findings - high 0, medium 3, low 22, false 7, maybe-false 0
- findings:
  - `[medium]` `patch` Blind/Edge: `SendBegan` set before `Transmit` builds the message, so an error before `Deliver` marks the claim maysent - real but narrow; moved the flag into `Transmit` before `Deliver`, mutation recorded above.
  - `[low]` `reject` Blind/Edge: MESSAGEMAYHAVESENT says the server stopped answering for an internal exception after the hand-over - the sentence is approved text and the intent forbids changing it (Ask First); filed in `deferred:` for a Planner text ruling.
  - `[false]` `reject` Blind: `partnerResultView` checks `outcome` before `simulated === false` - the server sets `outcome` only for a Settings-contact notice, and may-have-sent claims nothing was sent.
  - `[low]` `reject` Blind: a QUIT-only failure turned into OK is not logged - the server's QUIT behaviour is not actionable and a log line adds a branch; not worth fixing.
  - `[false]` `reject` Blind/Verification-gap: the cut-short rows use request state failed - Fix.Run closes a cut-off request failed (Fix/Run.cls class doc), and the demo half still uses interrupted.
  - `[medium]` `patch` Blind/Verification-gap: no test drives `Executor.SendEmail`'s catch or `SubmitApproved` with a claim present - added `TestCommandsInGivesNoAnswerAfterTheSendBegan` and `TestEmailSendThatFailsAfterTheClaimEndsMayHaveSent`, mutations recorded.
  - `[low]` `patch` Blind: no test that the simulated notice's payload has no `outcome` - added the demo-payload assertion in `TestSettingsContactMayHaveSent`, mutation recorded.
  - `[low]` `reject` Blind: catalog.test title says "nineteen result keys" - stale before this story (the count was 22), not caused by it.
  - `[low]` `reject` Blind: `Began` is keyed on ApprovalRef alone and the docs do not say how may-have-sent is decided - a keyed tool send never reaches a partner warning, and the user-facing text is ruled.
  - `[low]` `reject` Edge: a connection lost while QUIT is written reads DATA in this %Net.SMTP build, so `Accepted` returns 0 - the spec requires the branch, the answer is the safe one (maysent), documented in Verification; the real QUIT answer is pinned over the wire.
  - `[low]` `reject` Edge: stored pre-1.0.12 runs whose reason is MESSAGEUNREACHABLE or MESSAGEFAILED now read notsent - the spec's table defines MESSAGEUNREACHABLE as never reached after Task 2; by design.
  - `[false]` `reject` Edge: an interrupted run with reason MESSAGEMAYHAVESENT and no claim reads notsent - a run with that reason has a maysent claim, so Began is 1.
  - `[low]` `patch` Verification-gap: Task 2's negative half (connect or EHLO failure still MESSAGEUNREACHABLE) has no mutation line - recorded.
  - `[low]` `patch` Verification-gap: DW-1422 branch pins (ConnectionFailed alternative, QUIT parameter, count guard) have no mutation lines - recorded; the count guard cannot be pinned.
  - `[low]` `patch` Verification-gap: mapping rows (skipped, kept, partial, REJECTED, REFUSEDLOGIN, MESSAGEFAILED before the hand-over) have no mutation lines - recorded.
  - `[low]` `defer` Verification-gap: Began's read-error branch has no test - hard to inject, in `deferred:`.
  - `[low]` `patch` Verification-gap: Incident's partner-only gate and the mock's quit mode have no mutation lines - recorded.
  - `[medium]` `defer` Verification-gap: the A13 e2e pin was not run - left to CI live:cards, in `deferred:`.
  - `[low]` `patch` Verification-gap: `TestSettingsContactsSendFailed` relies on the previous block's `MailIs` - set it in the block.
  - `[false]` `reject` Verification-gap: TestQuitFailureAfterTheMailIsSent skips the run assertion when no run exists - its State and claim assertions still fail the test.
  - `[false]` `reject` Verification-gap: the Record status in the summary test is unchecked - a failed Record turns the maysent rows red.
  - `[low]` `reject` Intent audit: the card reads the server's outcome only for maysent (reading D) - the intent's one additive field is delivered, the other bands are the 23.13 ones; recorded as a divergence, not a defect.
  - `[low]` `reject` Intent audit: the classifier still reads a reason sentence for a failed run - after Task 2 only MESSAGEMAYHAVESENT means may-have-sent, so no ambiguous sentence is read.
  - `[low]` `reject` Intent audit: the e2e A13 reads a state value the test injected - the server half is pinned by Test.Watch.Summary and Test.Live.Payloads; the run itself is in `deferred:`.
  - `[low]` `reject` Intent audit: the "sent = the run completed" case with every recipient skipped maps to notsent - the table lists it explicitly and the card keeps result.partnerSkipped.
  - `[low]` `reject` Intent audit: DW-1422 over the wire is covered for the approved email only - the other kinds share Transmit and are pinned with the probe statuses.
  - `[false]` `reject` Intent audit: the chat's rendered text is checked only for the claimed row - TestSettingsContactMayHaveSent asserts ResultKey for every row and the catalog parity test pins the text.
  - `[false]` `reject` Intent audit: the may-have-sent decision is taken in three places - the executor wrappers only turn MESSAGEFAILED into MESSAGEMAYHAVESENT from EmailOut's own claim; SendOutcome is the one classifier.
  - `[low]` `reject` Intent audit: surface 5 repeats the DW-1422 note above.
  - `[low]` `reject` Intent audit: the diff widens a keyed tool send's exception after the hand-over to MESSAGEMAYHAVESENT - the spec's Task 2 says every claim.
  - `[low]` `reject` Blind: the simulated notice test relies on state "interrupted" - see the cut-short state row above.
  - `[low]` `reject` Verification-gap: the e2e A13 has no mutation line - not run; see the deferred A13 entry.

### 2026-11-16 - Rework iteration 1 review pass (DW-1429)
- verdicts: 20 findings - high 0, medium 1, low 16, false 3, maybe-false 0
- findings:
  - `[low]` `reject` Edge: an exception thrown from Deliver before the 354, with SendBegan 1, still answers MESSAGEMAYHAVESENT - carried from the first pass ("Send began is coarser than the hand-over", errs safe; %Net.SMTP turns its own errors into statuses, so only an internal exception reaches the catch).
  - `[low]` `reject` Edge: the probe's real-sender branch left `databegan` stale - same root as the Blind and Verification-gap rows below; fixed once (see the patch row).
  - `[low]` `reject` Edge: no pin for the OAuth2-refused or no-transport early exits of SendMail resetting the flag - the reset is the first line of SendMail, before every exit, and the missing-credential exit is pinned with a mutation.
  - `[low]` `reject` Edge: the mock's stall-data keeps the stalled envelope and data on its connection - test infrastructure; the next mail on that connection stalls in the same mode, and the mode is reset between tests.
  - `[low]` `reject` Edge: stall-data reads the failure mode at the end of the data, not at DATA - test infrastructure; a mode change mid-message is not a case any test makes.
  - `[false]` `reject` Edge (claim): "an exception after SendBegan answers MESSAGEMAYHAVESENT whatever DataBegan says" contradicts the item - the item names failures before the data, which arrive as statuses; the exception path is the spec's "after Transmit began" row (first pass).
  - `[false]` `reject` Edge (claim): the keyed tool send's after-data case is pinned only by older tests - removing the flag in Out.Send turns `TestToolKeyFailureClasses` red (mutation 2 of the record), so the older cases do gate the new flag.
  - `[low]` `reject` Edge (claim): two mock modes where the item allowed one - decided in-stage: stall-data is what lets the wire test cover a timeout after the data began; the modes only exist on the CI mock.
  - `[low]` `reject` Blind: `MayHaveSent`'s flag defaults to 0 (errs toward not sent) and the hook is `[ Internal, Private ]` - the item fixes the one-method design; `TestSmtpKnowsWhenTheDataBegan` runs the real subclass over the wire and turns red if a build stops calling SendMessage; a required argument would change the item's signature.
  - `[medium]` `patch` Blind/Verification-gap: `Out.DataBegan` and its call to the adapter were run by no test (the probe replaced it) - added `TestOutReadsTheAdaptersDataBegan` (a real Out holding a real Sender whose SMTP object's flag is set) and the probe's `realflag`; mutation recorded.
  - `[low]` `reject` Blind: no mock mode that closes the socket after the 354 - the connection-lost-during-DATA branch is pinned on a synthetic status, and the item says to reuse the existing modes.
  - `[low]` `reject` Blind: stall-greeting still answers a client's EHLO sent before the greeting - the mode stands in for a server that never greets, which is the item's case; an implicit-TLS port is the likely cause, not a thing the mock must reproduce byte for byte.
  - `[low]` `reject` Blind/Verification-gap: the two mock tests assert absence after 300 ms - the stall-greeting test also asserts one connection and the stall-data test asserts no kept mail; both turn red when their guard is removed (mutations recorded).
  - `[low]` `patch` Blind/Verification-gap: the probe's real-sender branch returned before `databegan` was set, so a later `DataBegan()` read a stale flag - the branch now sets it from the adapter after SendMail.
  - `[low]` `reject` Blind: docs say MESSAGEUNREACHABLE means "the server was never reached" in places and "the message data never began" in others - `Classify`'s class already reads "could not be reached or used", and the sentence is approved text (Ask First to change).
  - `[low]` `patch` Verification-gap: the mock's two new modes, `Sender.DataBegan` and the `SMTP` property type had no mutation lines - mutations run and recorded above.
  - `[low]` `reject` Verification-gap: `EmailOutSmtp`'s status line and the probe's `timeoutearly`/`droppedearly` answers have no mutation of their own - test stand-ins, exercised by every row that uses them and by the mutations above; a stand-in that ignored its input turns the rows for both flags red.
  - `[low]` `reject` Verification-gap: `TestMayHaveSentNeedsTheDataBegan` assumes the credential `ZzNoSuchCredential` does not exist and code 6167 - the assertion on the code is what proves the early exit; no test or installer creates that name.
  - `[false]` `reject` Intent: the early-timeout pin does not reach the timeline and the card - `PartnerWarning.SendOutcome` is the one classifier and `Test.Watch.Summary` rows for MESSAGEUNREACHABLE (green again in this pass) assert the timeline, the chat and the card as notsent; the new `PartnerMail` test pins the classifier and the chat key for both timeouts.
  - `[low]` `reject` Intent: a wire test through the production's whole EmailOut with a stall was not run - 20 to 40 s per case at the production timeouts; the wire test drives the real SMTP subclass and the new test drives the real Out and Sender, so each hop is pinned.

## Auto Run Result

Status: done
Blocking condition: none

### Rework iteration 1 (DW-1429, step-aware may-have-sent; this pass only)

**Summary.** "May have reached the server" now needs the message data to have begun. `Channel.Email.SMTP` (a `%Net.SMTP` subclass of ours) sets `DataBegan` in its override of the private `SendMessage` (called only after DATA's 354) and clears it when `Send` starts; `Sender`'s `SMTP` property is that type, `Sender.SendMail` clears the flag too, and `Sender.MayHaveSent(sc, dataBegan)` is 1 only when the data began and the status is a timeout or a connection lost during DATA. `Out.Send` passes the adapter's flag. A timeout at the greeting, EHLO, STARTTLS, AUTH, MAIL FROM, RCPT TO or DATA answers MESSAGEUNREACHABLE (claim failed, `fix.emailNotSent`); a timeout after the data began answers MESSAGEMAYHAVESENT as before. `Accepted` is unchanged. The CI mock gained `stall-greeting` and `stall-data`.

**Files changed.** `src/ocutalon/cls/OcuTalon/Channel/Email/{SMTP (new),Sender,Out}.cls`, `Data/Delivery.cls` and `Fix/Kind/PartnerWarning.cls` (docs), `ci/mock/smtp.mjs` and its test, the test stand-ins `Test/Channel/{EmailOutProbe,EmailOutSmtp}.cls`, and the tests in `Test/Channel/EmailOut.cls`, `Test/Partner/PartnerMail.cls` and `Test/Fix/Email.cls`; the spec (the table rows, the record, the review records).

**Review.** Patches applied: 3 (medium 1: `Out.DataBegan` run by no test; low 2: the probe's stale flag, mutation lines). Deferred: 0 new. Rejected: 17, each with its reason in the triage log.

**Follow-up review recommended:** false. This was a follow-up pass and it patched no `high` (patched counts: high 0, medium 1, low 2); the work has converged.

**Verification.** `Test.Channel.EmailOut`, `Test.Fix.Email`, `Test.Partner.PartnerMail`, `Test.Fix.PartnerWarning`, `Test.Watch.Summary`, `Test.Fix.Executor` and `Test.Partner.PartnerApprove` passed on a lane-B warm stack; `node --test ci/mock/test` 192 passed; `test-boundaries.sh` and `test-ci-config.sh` passed; mutation lines are in Verification. No web code changed: the initial bundle stays 897.10 kB (the first pass's measurement).

**Residual risks.** `SendMessage` is `[ Internal, Private ]` in `%Net.SMTP`; the wire test turns red if a later build stops calling it. No test drives the production's whole EmailOut against a stall at the production timeouts.

### First pass

**Summary.** The security overview and GUIDE hold the approved texts (DW-1423, DW-1425). `Sender.Accepted` makes a QUIT-only failure a sent email for every kind (DW-1422). `Out.Send` answers MESSAGEMAYHAVESENT for every claimed send that may have reached the server, `PartnerWarning.SendOutcome` is the one classifier for the timeline, the chat and the card, the card reads the server's `outcome` member, and `result.partnerMaySent` is in both catalogs. `live:install-script-live` moved from shards-2 to shards-3.

**Files changed.** See the diff of the five commits: docs (`docs/security-overview.md`, `GUIDE.md`), `Channel/Email/{Out,Sender}.cls`, `Fix/Kind/{Email,PartnerWarning}.cls`, `Fix/Executor.cls`, `Watch/{Summary,Notice}.cls`, `Live/Payload/Incident.cls` and `Part/IncidentRequestResult.cls`, `Msg/Catalog/Watch.cls`, the web catalog, `approval-view.ts`, `payloads.ts`, the CI mock's SMTP, `ci/units.sh`, and their tests (`docker/tests/test-readme.sh`, `test-ci-config.sh`, `Test.Channel.EmailOut`, `Test.Fix.{Email,Executor,PartnerWarning}`, `Test.Watch.Summary`, `Test.Live.Payloads`, `Test.Msg.Catalog`, `Test.Partner.PartnerMail`, web unit tests, `web/e2e/cards/approval-card.spec.ts`).

**Review.** Patches applied: 8 (high 0, medium 2: the early `SendBegan` and the untested send paths; low 6, tests and mutation lines). Deferred: 3 (Began's read-error branch, the MESSAGEMAYHAVESENT wording for an internal exception, the unrun A13 e2e). Rejected: 22, each with its reason in the triage log.

**Follow-up review recommended:** true. Two mediums were patched (the early `SendBegan`, the untested executor send paths), so the rule's first-pass bar is met; the unverified risk is the executor wrappers' `Fix.Kind.Email` `Unfinished` and `FailedMessage` turning MESSAGEFAILED into MESSAGEMAYHAVESENT for a plain approved email, whose only tests are the two new ones.

**Verification.** All classes, web unit tests, CI-config, boundaries, readme and security-overview scripts passed after the patches; mutation lines are in Verification. Initial web bundle 897.10 kB.

**Residual risks.** The A13 e2e pin runs first in CI's `live:cards`; the MESSAGEMAYHAVESENT sentence says the server stopped answering for the rare internal exception after the hand-over.
