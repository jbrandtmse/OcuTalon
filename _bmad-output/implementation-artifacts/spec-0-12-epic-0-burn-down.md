---
title: 'Story 0.12: Epic 0 burn-down'
type: 'feature'
created: '2026-10-20'
status: 'in-progress'
baseline_revision: '5047cd2e90c8e651aa58e05854e94a160c092c60'
baseline_commit: 5047cd2e90c8e651aa58e05854e94a160c092c60
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      Stories 10.2 and 14.2 carry no acceptance criterion for the how-to-remove sentence that EXPERIENCE.md says the README and the security overview carry.
    evidence: |-
      EXPERIENCE.md (owner forms table, row "Demo mode off, OCUORDERS kept") says the README and the security overview carry the same sentence as the demoKept note. A search of the repo for "left the OCUORDERS" finds it only in Demo.cls, test-install-start.sh and this spec, and neither story's block in epics.md names it.
    location: >-
      epics.md, Stories 10.2 and 14.2
    severity: low
---

<intent-contract>

## Intent

**Problem:** Epic 0 leaves three ledger items open before the lanes split. They are Story 0.12's acceptance criteria (`epics.md` L1052–1064).
- **DW-41 (owner decision 1).** The catalog renders plural-only texts where the owner fixed count-of-one forms on October 20, and 9 entries still carry a `gap` field. The late press has only its approved form. The sign-in labels "User name", "Password" and "Show password" sit outside the catalog, so `Test.Web.PublicTexts` can't compare them.
- **DW-42 (owner decision 2).** With demo mode off, an OCUORDERS that OcuTalon didn't create is left alone silently. One that holds another production fails the start (`STEP Demo FAILED`, no ready marker; 0.10's review patch A4). The owner wants it kept, with a warning and a status note, and the start must end ready.
- **DW-9 (flake).** `OcuTalon.Test.Install.Users:TestEnsureCreates` read an empty password hash once in 7 slot A runs. Its fixture is always `ZzUsers1`, because `Clean()` kills the counter.

**Approach:**
- **Catalog.** An entry may carry one count-of-one form, `"one": {"slot", "text", "web"}`, and `Render` uses it when that count slot is 1. The owner's texts go into 8 Watch entries, 3 new `answered.*` keys and 3 new `signIn.*` keys in Core, and every `gap` goes.
- **Demo off keeps.** The step leaves such an OCUORDERS in place and removes only OcuTalon's own access to it (AD-24). It warns through a new registry warning line, records the status mark `demoKept`, and returns OK, so the start ends ready.
- **DW-9.** A fixture name that is never reused, and a read that re-opens the account until its hash is there. It closes on a fresh-environment `lane-a` run in both orders.

## Boundaries & Constraints

**Always:**
- **The owner's texts, verbatim** (EXPERIENCE.md L688–701, copied under Design Notes). No other new product text. Where none is fixed, the step reuses 0.10's fixed sentences (Design Notes, Owner-only).
- **Render's contract stays.** It is pure and returns the whole text, or "" with a named error. It fills in one pass, and slots are validated by type. The form's count slot is validated like any count slot: missing, null, negative, fractional or text is refused, naming the slot, whether or not the form is used.
- **AD-3 as amended, and AD-24.** The off path never deletes, stops, starts or changes anything inside a kept OCUORDERS: its namespace, databases and files, mappings, Interoperability markers and role, productions, and its other web applications. It never fails the start over it. It removes only OcuTalon's own access: the application `/ocutalon/trace/ocuorders`, the trace role's OCUORDERS database grants, and the trace role's SQL privileges in OCUORDERS. The on path's refusal is unchanged.
- **Lanes (AD-29, AD-33).** The late-press and sign-in keys go in `Catalog.Core`; the one-forms go in `Catalog.Watch`'s own entries. Only Epic 0 edits both lanes' files.
- **Source text (Rule 14).** ASCII, with any non-ASCII character as an escape. Comments state contracts.
- **REL-4.** No new stack, restart, CI unit, group or test class. The live checks ride `test-install-start.sh`'s existing restarts, and the unit tests ride existing classes in `lane-a` and `lane-b`.
- **Runtime targets (Rule 21).**
  - Slot A gets loads, compiles and unit tests only (`server: ocutalon-slot-a`, `namespace: OCUTALON`, one `%UnitTest` class per call).
  - The Demo step's `Run()`, OCUORDERS and `test-install-start.sh` run only in throwaways, through `ci/iris.sh`.

**Never:**
- **Files left unchanged:**
  - `OcuTalon.Web.Public.*` (its copies already hold the texts);
  - `docker/after-start.sh`, `docker/after-start.cos` and `docker/tests/lib-live.sh`;
  - `ci/units.sh`, the compose files and `epics.md`.
- **No new status surface for the kept namespace:** no AD-12 status condition, no `^OcuTalonPublic` key and no page banner.
- **No other home for the note or the warning:** no `Data.Setting` row for the note, and no step that `Write`s its warning to the device itself.
- **No storage change.** `StatusMark` gains methods only.
- **Never on a slot:** `Install.Step.Demo.Run()`, `Test.Demo.Production` or any live script.
- **Never touched:** `ocutalon-aihub-test`, `ocupilot*` and `iris-community-edition`. Never read `.env`.
- **Never edited:** `.claude/`, `CLAUDE.md`, `irislib/` and `irissys/`.

## I/O & Edge-Case Matrix

Where the rows run:
- **Rows 1–10:** `OcuTalon.Test.Msg.Catalog` and `.Test.Web.PublicTexts`, in `lane-b` and on slot A.
  - The fixture clock is 2026-10-16T18:20:00Z in America/New_York, with the online-demo flag on.
  - `itemNoun` is `{"one":"order","other":"orders"}`, and `failReason` is "the order date still wasn't accepted".
- **Rows 11–15:** `docker/tests/test-install-start.sh`, in a throwaway.
- **Rows 16–18:** `Test.Install.Registry`, `Test.Data.Tables` and `Test.Install.Users`, in `lane-a` and `lane-b` and on slot A.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|---|
| 1 | Dry run, one copy | `incident.withFix`: count 1, time 18:12Z, cause "The partner changed its date format.", fixSummary "repair and resend it", field "order date", before "10/16/2026", after "2026-10-16", resendCount 1 | On the message channels: "1 order failed since 14:12 ET. The partner changed its date format. I can repair and resend it. Approve?\n\nDry run: 1 order affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page." On `web`, the same without " Approve?". `incident.laterRequest` with count 1, time 18:20Z and resendCount 1: "1 more order failed since 14:20 ET, with the same cause. I can repair and resend it. Approve?\n\nDry run: 1 order affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.", and its `web` without " Approve?" | resendCount missing, null, -1, 2.5 or "5": "" and an error naming 'resendCount' |
| 2 | All went through, one | `result.allThrough`, count 1 | "The order went through." on all four channels | — |
| 3 | Failed again, one | `result.failedAgain`: count 50, completed 49, failedAgain 1 | "49 of 50 orders went through. 1 failed again (the order date still wasn't accepted). I won't retry it without a new approval." | — |
| 4 | Skipped, one | `result.skipped`: count 50, completed 49, skipped 1 | "49 of 50 orders went through. 1 had changed since the dry run, so I skipped it; it needs a new approval." | — |
| 5 | Failed and skipped, one skipped | `result.failedAndSkipped`: count 50, completed 47, failedAgain 2, skipped 1 | "47 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 1 had changed since the dry run, so I skipped it. I won't retry any of them without a new approval." | — |
| 6 | Still resending, one | `result.stillResending`: count 50, completed 1 | "Still resending: 1 of 50 orders has gone through so far. I'll tell you when it's done." | — |
| 7 | Cut off, one left | `result.interrupted`: count 50, completed 49, remaining 1 | "The resend stopped when OcuTalon restarted: 49 of 50 orders went through. The other one needs a new approval." | — |
| 8 | Not one | Rows 1–7 with the form's slot at 0 and at 2 | The entry's own text, holding: "I'll resend 2 repaired copies; the originals stay unchanged."; "All 0 orders went through." and "All 2 orders went through."; "I won't retry them"; "so I skipped them; they need"; "so I skipped them. I won't"; "orders have gone through"; "The other 2 need a new approval." | — |
| 9 | The late press | `answered.alreadyRejected` {telegram, 18:15Z}; `answered.alreadyApprovedBy` {sam, phone, 18:15Z}; `answered.alreadyRejectedBy` {sam, web, 18:15Z} | "Already answered: rejected from Telegram at 14:15 ET."; "Already answered: approved by sam from the simulated phone at 14:15 ET."; "Already answered: rejected by sam from the web chat at 14:15 ET." The same on `web`: no web wording, as for `answered.alreadyApproved` | Each declared slot is refused when missing or of the wrong type |
| 10 | Catalog shape and sign-in labels | Both catalog classes; `Web.Public.Login`'s `USERLABEL`, `PASSWORDLABEL` and `SHOWPASSWORD` | Core holds 63 keys and Watch 22. No entry has `gap`, and `Gaps` is empty. Exactly the 8 entries of rows 1–7 carry a well-formed `one`. The three parameters equal `signIn.userLabel` ("User name"), `signIn.passwordLabel` ("Password") and `signIn.showPassword` ("Show password"): 11 compared, 0 not in the UX, 19 not texts | `TestEntries` fails on a malformed `one`, naming the key: an unknown field; a slot that is not a declared count slot; a text whose placeholders differ from the declared slots less the form's own slot; a `web` without the entry's `web`, or the other way round |
| 11 | Off, a foreign OCUORDERS | demo.mode 0; OCUORDERS on `OCUFOREIGN_DATA` and `OCUFOREIGN_CODE` | `Run()` returns OK and changes nothing of the namespace. One warning: "Namespace OCUORDERS exists and uses databases that OcuTalon did not create, so the Demo step leaves it alone." The mark `demoKept` is `{"text":<that sentence>,"namespace":"OCUORDERS","globals":"OCUFOREIGN_DATA","routines":"OCUFOREIGN_CODE"}`. At a start: the log line after `STEP Demo OK <s>s` is `WARN Demo <sentence>`, the STEP and RESULT lines are row 3's as before, and the ready marker equals the image's version | — |
| 12 | Off, OcuTalon's OCUORDERS with another production defined and stopped | `ZzOcuForeign.Production` defined in OCUORDERS, nothing running | `Run()` returns OK. Kept, with nothing stopped or started: the namespace, both databases and their files, the mappings, and both productions' definitions. Gone: `/ocutalon/trace/ocuorders`, the trace role's OCUORDERS grants, and the trace role's SQL privileges in OCUORDERS. The warning: "The production ZzOcuForeign.Production is in namespace OCUORDERS, so the Demo step leaves it alone." The mark has globals `OCUORDERS_DATA` and routines `OCUORDERS_CODE`. At a start: the WARN line and the ready marker | — |
| 13 | Off, another production running | `ZzOcuForeign.Production` running, the Orders production stopped | As row 12, with "The production ZzOcuForeign.Production is in namespace OCUORDERS and is not stopped, so the Demo step leaves it alone.", and the foreign production still runs | — |
| 14 | On, a foreign OCUORDERS or another production running | As in 0.10 | Unchanged: 0.10's error and nothing touched. The mark is left as it was | The start ends without the marker, as before |
| 15 | The mark clears | An off run that removes (OCUORDERS absent, or the step's own with no other production), or an on run that creates | `demoKept` is absent, and there is no warning | — |
| 16 | A step's warning | A registry run over a fixture step that calls `Warn("Fixture warning <n>")` and returns OK, then a plain step | `STEP <step> OK <s>s`, then `WARN <step> Fixture warning <n>` on the next line. The plain step has no WARN line, and `TakeWarnings()` is empty afterwards | A failing step's warnings follow its FAILED line |
| 17 | Status marks | `Record(m, "v")`, `Record(m, "w")`, `Get(m)`, then `Record(m, "")`, with a fixture mark `ZzStatusMark<n>` | One row with value "w" and `RecordedAt` in UTC to the second; afterwards `Get` is "" and there is no row | `Record("", "v")` gives an error status naming the empty mark |
| 18 | The account read | `TestEnsureCreates` | The fixture is `ZzUsers<n>`, with an `n` never used before on the instance. The hash read after the create is non-empty within a bounded wait | The wait ends after about 2 s, and the assertion then fails |

</intent-contract>

## Code Map

- **Planning, by line:**
  - `epics.md`: Story 0.12, L1052–1064.
  - EXPERIENCE.md (`ux-designs/ux-OcuTalon-2026-10-16/`): the owner's table, L688–701; the answered statuses, L659–671; the Results, L673–686.
  - Spine (`architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
    - AD-3's OCUORDERS rule as amended, L142;
    - AD-12's closed status conditions, L338;
    - `StatusMark` (AD-18), L473;
    - AD-19's `Data.Setting` home, L498;
    - AD-23's step list, L615–628, and its STEP log sentence, L631;
    - AD-24's "OCUORDERS grants … exist only with demo mode on", L659–660;
    - AD-32 "as built", L828;
    - the cross-lane API table, L1053.
- **The renderer and catalog (0.9, Lane B; `Watch` is Lane A's):**
  - `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls`:
    - the entry grammar comment, L4–9;
    - `Build`, L87–101, where the form is chosen, after `ParseSlots` and before `Fill`;
    - `Fill`, L104;
    - `Noun`, which picks by `count`, L177–188;
    - `Count`, L220–225, which validates the form's slot.
  - `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`: the 8 gap entries, L78–208.
  - `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`:
    - the entry comment, L4–8;
    - `answered.*`, L78–129, with `alreadyApproved`'s gap at L128;
    - `signIn.*`, L309–348.
  - `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`:
    - the header counts, L3;
    - `ENTRYFIELDS`, L26;
    - `TestEntries`, L69–108;
    - `TestEveryKeyOnEveryChannel` (the "79 keys" label), L112–136;
    - `TestNoun`, L164–178, whose `skipped`-with-total-1 case still passes (first sentence only);
    - `TestWebWording`, L440–464;
    - `TestTypography`, L468–494;
    - `TestNounForms`, L498–516, where the count goes to 1 for `allThrough`, whose form keeps the noun;
    - `TestEverySlotIsValidated`, L568–605;
    - `Problems`, L688–719;
    - `Placeholders`, L722;
    - `Keys`, L818–905;
    - `Gaps`, L908–921;
    - `Fixtures`, L956–1038.
  - `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`: the counts at L32 and L83–85; `Classified`, L120–145.
  - `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls`, L16–20: `USERLABEL`, `PASSWORDLABEL` and `SHOWPASSWORD` already hold the owner's texts. Read only.
  - Only these five files name the affected keys or `notInUx`; a repository search found no other copy.
- **The Demo step (0.10, Lane B):** `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls`.
  - The class comment, L3–22.
  - `Run`, L56–74.
  - `Plan`, L81–93; the foreign sentence is at L86.
  - `WithOrders`, L113.
  - `Owned`, L146.
  - `System`:
    - the names computed before the switch, L157–164;
    - the off branch, L254–381: the applications at L255–272, the role at L273–287 and the SQL privileges at L301–310.
  - `Orders`:
    - the not-stopped check shared by on and off, L408–410;
    - the defined-other check, L461–463.
- **Its test and its live fixtures:**
  - `src/ocutalon/cls/OcuTalon/Test/Demo/Step.cls`: the header, L8; `TestPlan`, L101–116.
  - `docker/tests/test-install-start.sh`:
    - the header, L17–33;
    - the end of row 2, L171–176;
    - row 3's recreate, L178–197 (`check_demo_off "row 3"` at L196);
    - the row 15 fixture, L244–247, and the row 6 fixture, L249–274;
    - the foreign fixture: built at L276–286, off at L287–293, on and removal at L294–306;
    - the partial state, L308–331;
    - `check_demo_off`, L332;
    - row 4's recreate, L337–347;
    - `ZzOcuForeign`, L357–367;
    - the running-foreign fixture, off, L412–418;
    - the stopped fixture, L420–431;
    - the final restart, L483–495.
    - Helpers to reuse: `demo_run` (L207), `fixture_class` (L210), `foreign_state` (L218), `settle_scheduler` (lib-live.sh L662), `check_session`, `start_log`, and `log_steps`, which keeps only STEP and RESULT lines (lib-live.sh L570).
- **The registry and the step contract (0.2, Lane A):**
  - `src/ocutalon/cls/OcuTalon/Install/Registry.cls`, `Run`, L39–56.
  - `src/ocutalon/cls/OcuTalon/Install/Step.cls`.
  - `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`:
    - `TestStepDefaults`, L220–232;
    - `TestRun`, L250–300;
    - `RunProbe`, L305, which captures the probe's output;
    - `Create`, L343, which replaces `@N@` before `@BODY@`;
    - `FixtureRunStep`, L501.
  - `docker/after-start.sh`, L85–88: the whole session transcript goes into the log, and only STEP and RESULT lines go to stdout. Unchanged.
- **Status marks (0.4, Lane B):**
  - `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls`: `Mark` (unique), `Value` (`MAXLEN` 1000) and `RecordedAt`; no methods yet.
  - `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`: `TestDeliveryStubs`, L86, the place for a table's method test.
  - `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`: `Signatures`, L289; the floor of 48, L162.
  - `OcuTalon.Data.Time.NowUtc()` stamps `RecordedAt`.
- **DW-9 (Lane A):**
  - `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls`: the fixture name, L13–20; `TestEnsureCreates`, L29–41; `Account`, L84–94; `Clean`, L128–144.
  - `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls`, `Ensure`: one `Security.Users.Create` call with the password.
  - `irissys/Security/Users.cls` (read only): `Exists(Username, .User)` returns an object handle (L405); the `Password` hash is set from `PasswordExternal` (L160–181).
  - The never-reset counter pattern: `Test.Msg.Catalog`'s `^OcuTalonTest("MsgCatalog","n")`, L34 and L44.

## Tasks & Acceptance

- [ ] [CI] iris (browser): `web/e2e/sign-in/sign-in.spec.ts` row 13 ("sign-in at a deep link redirects to that URL, which serves the shell") failed on run 39534434817 attempt 1 (head 811102f) and run 39540054243 (head fae0f9e): `toHaveURL(/\/ocutalon\/index\.html\?x=1$/)` received `/ocutalon/#/`. Cause (lead's diagnosis, confirm it): the shell boots Angular with `withHashLocation()` and `<base href="/ocutalon/">`, and the router's initial navigation calls `history.replaceState` with `#/`, which resolves against the base to `/ocutalon/#/`; the assertion reads a transient pre-boot URL and passes only when Playwright checks before Angular boots. Fix the TEST, not the product: keep the 303 location check, then assert that the document navigation to `/ocutalon/index.html?x=1` answered 200 with the shell (`<app-root`), and the title; drop the post-boot URL assertion. Prove it: a mutation that breaks the redirect target turns row 13 red, and `ci/iris.sh live sign-in` passes repeatedly (three runs). DW-47. https://github.com/jbrandtmse/OcuTalon/actions/runs/39540054243

- [x] [Rework, DW-44 (code review's HIGH); the owner's approval through the Contest Planner, October 21] The `demoKept` status note gains a `how` field holding exactly "OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal.", with `{what was kept}` filled from the same facts the note's kept sentence names (EXPERIENCE.md, the owner forms table). Write it as ASCII with escapes where needed. `test-install-start.sh`'s `kept_note` check pins the exact sentence for both keep fixtures, and a mutation that drops or alters it goes red. The after-start `WARN Demo` line keeps Story 0.10's sentence. No other change.

**Execution:**

*Task 0 (measure first; each command is under Verification):*
- [x] **0.1** Check slot A's identity with `iris_server_info`: build 154, port 1990.
- [x] **0.2 (DW-9, before the fix).** Run `OcuTalon.Test.Install.Users` on slot A 10 times, one call each. Record each result and the fixture number (`^OcuTalonTest("Users","n")`, read-only). The cause is `(inference)` until then: either two runs sharing `ZzUsers1`, or a read soon after the create.
- [x] **0.3 (DW-42).** In the first throwaway run of `live install-start`, confirm that `Ens.Config.Production.LoadFromClass("ZzOcuForeign.Production")` in OCUORDERS defines the production without starting it, so that the off path's `Ens_Config.Production` query finds it `(inference)`. If it doesn't, stage task 14's last fixture with the existing start-then-stop sequence (L391–431), and record that in the Spec Change Log.

*DW-41: the catalog.*
- [x] `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- choose the count-of-one form.
  - In `Build`, between `ParseSlots` and `Fill`: when the entry has `one`, read `one.slot` with `Count`, so the slot is validated even when the form isn't used.
  - When it is 1, fill `one.web` (on channel `web`, where the entry has `web`) or `one.text`, in place of the entry's text.
  - A `one` that isn't an object, or whose `slot` isn't a declared `count` slot, is an error naming the key.
  - Add `one` to the entry grammar in the class comment: the form used when that slot is 1, whose text holds every declared slot but its own.
  - Rationale: `Render` picks the form, so producers pass the slots as they are (AD-32).
- [x] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- remove the `gap` field from the 8 entries and give each its `one` (Design Notes, "The forms").
  - `incident.withFix` and `.laterRequest` also get `one.web`: their `web`, with the same sentence replaced.
  - Rationale: owner decision 1.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- the new keys.
  - Remove `answered.alreadyApproved`'s `gap`.
  - After it, add `answered.alreadyRejected`, `answered.alreadyApprovedBy` and `answered.alreadyRejectedBy`.
  - After `signIn.signedOut`, add `signIn.userLabel`, `signIn.passwordLabel` and `signIn.showPassword`.
  - Texts, slots and `source` strings are under Design Notes, "The new Core entries". Add `one` to the class comment's entry shape.
  - Rationale: owner decision 1; each key in its producer's lane's class.
- [x] `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- rows 1–10; `TestCountOfOneForms` is the pinning test of the forms.
  - **The entry rules:**
    - `ENTRYFIELDS` gains `one`, and `Problems` checks row 10's `one` rules;
    - `TestEntries` expects 63 and 22 keys and "0 keys carry a gap", with `Gaps` emptied to `[]`.
  - **The expectations:**
    - `Keys` gains the 6 Core keys;
    - `Fixtures` gains their fixtures (row 9, and the three label texts with no slots);
    - the header counts and the "79 keys" label become 85.
  - **The checks of the forms' texts:**
    - `TestWebWording`: a `one.web` is `one.text` without " Approve?";
    - `TestTypography` also sweeps `one.text` and `one.web`.
  - **New `TestCountOfOneForms`, with a new XData `OneForms` (rows 1–8):**
    - for each of the 8 keys, the slots with the form's slot at 1, and the exact text (and the web text for the incident keys) on the four channels;
    - for the slot at 0 and at 2, the plural fragment row 8 names;
    - exactly 8 entries carry `one`;
    - row 1's refusals of `resendCount`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` -- row 10.
  - Move `USERLABEL`, `PASSWORDLABEL` and `SHOWPASSWORD` from `notInUx` to `compared` under `OcuTalon.Web.Public.Login`, as `signIn.userLabel`, `signIn.passwordLabel` and `signIn.showPassword`. `notInUx` becomes `{}`.
  - The counts become 11 compared, 0 not in the UX and 19 not texts.
  - Rationale: the public package itself is unchanged.

*DW-42: keep, warn, note, ready.*
- [x] `src/ocutalon/cls/OcuTalon/Install/Step.cls` -- add `ClassMethod Warn(text As %String)` and `ClassMethod TakeWarnings() As %List`.
  - `Warn` records one warning line of the running step in a process-private global, with CR and LF made spaces.
  - `TakeWarnings` returns the recorded lines in order and clears them.
  - The contract comment says that the registry prints them, and that outside the registry they stay with the caller until taken.
  - Rationale: the one warning path for steps; 3.7 reuses it for DW-10.
- [x] `src/ocutalon/cls/OcuTalon/Install/Registry.cls` -- in `Run`, print each step's warnings.
  - Discard any warnings before each step.
  - After the step's `STEP <name> OK <s>s` or `FAILED` line, write one `WARN <name> <text>` line per warning taken.
  - Update the method comment.
  - Rationale: row 16. The after-start log keeps the whole transcript, and `log_steps` reads only STEP and RESULT lines, so every existing log pin holds.
- [x] `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls` -- add `ClassMethod Record(mark As %String, value As %String) As %Status` and `ClassMethod Get(mark As %String) As %String`.
  - `Record` creates or replaces the row, with `RecordedAt` = `OcuTalon.Data.Time.NowUtc()`. An empty value deletes the row, and an empty mark is an error status.
  - `Get` returns the value, or "" when there is no row.
  - Methods only; the storage block is unchanged.
  - Rationale: the note's home (Rule 22 ruling); 10.3 builds `RecordTelegram` on `Record`.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` -- rows 11–15 (AD-3 as amended, AD-24).
  - **`Parameter KEPTMARK = "demoKept"`.**
  - **`Plan(on, exists, owned, Output sc, Output kept)`:**
    - off with a namespace the step doesn't own gives `keep`, with `kept` the foreign sentence;
    - that sentence is the on refusal's own text, built once and used by both;
    - every other row is as now, with `kept` "".
  - **`Orders(0, Output kept)`:**
    - where the off path now returns an error for another production (the not-stopped check and the defined-other check), it sets `kept` to that same sentence and returns OK, having done nothing;
    - the on path's refusal is unchanged.
  - **`System` gains a keep mode,** in %SYS:
    - it deletes the trace application, if present. Its name comes from `Web.TraceApp(..#NAMESPACE)`, computed before the switch as `role` is;
    - it removes the trace role's OCUORDERS grants (`WithOrders(current, 0)`);
    - it deletes the namespace's `Security.SQLPrivileges` rows whose grantee is the trace role;
    - it returns the note JSON `{"text","namespace","globals","routines","how"}`, filled from `Config.Namespaces` and, for `how`, from the owner's sentence (DW-44);
    - it does nothing else.
  - **`Run`:**
    - when `kept` is set, by `Plan` or by `Orders(0)`, it runs the keep mode in place of `System(0)`, then calls `..Warn(kept)` and `StatusMark.Record(..#KEPTMARK, note)`, and returns OK;
    - after a create or a remove that succeeds, it calls `Record(..#KEPTMARK, "")`;
    - an error leaves the mark as it was.
  - **Comments.** Update the class comment and those of `Plan` and `Orders`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Demo/Step.cls` -- in `TestPlan`, the row `0,1,0` is `keep`, with `kept` the foreign sentence; every other row has `kept` "". Update the header.
  - Rationale: row 11's decision, tested on a slot.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls` -- row 16.
  - **`TestRun`:**
    - a fixture step `ZzRunWarn<n>` whose body calls `Warn("Fixture warning <n>")` and returns OK, with the number written into the body (`@N@` is replaced before `@BODY@`);
    - it runs as `$ListBuild(warn, last)`, and the test checks row 16's lines and their order, then that `TakeWarnings()` is "";
    - the fixture step is deleted with the others.
  - **`TestStepDefaults`:** `Warn("a")` and `Warn("b")`, then `TakeWarnings()` gives `$ListBuild("a","b")`, and then "".
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- new `TestStatusMarkRecord` for row 17.
  - Its fixture mark is `ZzStatusMark<n>`, from a counter `^OcuTalonTest("StatusMark","n")` that is never reset.
  - It deletes any `ZzStatusMark*` rows first, and its own row at the end.
- [x] `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls` -- add two rows to `Signatures`:
  - `{"class": "OcuTalon.Data.StatusMark", "method": "Record", "args": "mark,value", "returns": "%Status"}`;
  - `{"class": "OcuTalon.Data.StatusMark", "method": "Get", "args": "mark", "returns": "%String"}`.
  - Rationale: Lane A's `TelegramIn` calls `Record` (spine L473).
- [x] `docker/tests/test-install-start.sh` -- rows 11–15, with no new restart.
  - **Header (L17–33):** the foreign states are kept with a warning and a note, and the start ends ready.
  - **Local helpers:**
    - `check_kept_log <label> <sentence>`: in `start_log`, the line right after `STEP Demo OK …` is exactly `WARN Demo <sentence>`, and it is the only `WARN Demo` line;
    - an ObjectScript snippet that prints `CHK|note|<text>|<namespace>|<globals>|<routines>`, or `CHK|note|<absent>`;
    - one that prints `CHK|own|<trace app exists>|<trace role names OCUORDERS>|<trace role's SQL privileges in OCUORDERS>`.
  - **Row 3 (row 11 across a real start):**
    - move the foreign build (L276–286) to right after row 2's checks (after L176), so row 3's recreate starts with it;
    - after row 3's `check_ready_state`, check the kept log, the note (`OCUFOREIGN_DATA`, `OCUFOREIGN_CODE`) and an unchanged `foreign_state`;
    - move `check_demo_off "row 3"` (L196) to after the fixture's removal (L306);
    - run the row 15 fixture (L244–247) and the row 6 fixture (L249–274) after it, since both need OCUORDERS absent.
  - **The in-session off run (L287–293):** `CHK|run|1|`, the warning taken with `TakeWarnings()`, the note, and the state unchanged.
  - **The partial-state off run (L322–331):** `demoKept` is also absent (row 15).
  - **Row 4, another production running, off (L412–418):** `CHK|run|1|`; the running sentence as the warning; the note (`OCUORDERS_DATA`, `OCUORDERS_CODE`); kept: the namespace, the databases and the foreign production, still running; and `CHK|own|0|0|0` (row 13).
  - **Row 4, stopped (L420–431):** the same, with the stopped sentence (row 12).
  - **Before the final restart (L484–486):**
    - in OCUORDERS, load `/tmp/ZzOcuForeign.cls` again and define it with `LoadFromClass`, without starting it (Task 0.3), then `set_demo_mode 0`;
    - after `check_ready_state "row 4"`: the kept log with the stopped sentence, the note, OCUORDERS and the foreign definition kept, and `CHK|own|0|0|0`.
  - **Unchanged:** every row's expected STEP and RESULT lines.

*DW-9.*
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` -- the fixture and the read.
  - `Clean()` keeps `^OcuTalonTest("Users","n")` and kills only the class's other nodes, so each run's fixture is new.
  - `Account(user, wait)`: `TestEnsureCreates` alone passes `wait` 1. It re-opens the account (killing the handle, then `Exists` again) up to 20 times, 0.1 s apart, until the hash is non-empty.
  - Update the comments.
  - Rationale: DW-9 (row 18).

**Acceptance Criteria:**
- **Fresh environment (Rule 19).** Given a fresh throwaway, when `ci/iris.sh shard lane-a` and `shard lane-b` run forward and then with `--reverse`, then all 33 classes pass in both orders, and every test added or changed passes on a fresh environment, in either order.
- **DW-9 closed on evidence.** Given the fix, when `Test.Install.Users` runs 10 times on slot A and `lane-a` runs fresh in both orders, then no run reads an empty hash, and each slot A run uses a new `ZzUsers<n>`.
- **The foreign namespace (Integration AC, Rule 1).** Given `test-install-start.sh` in a throwaway, when row 3's recreate starts with demo mode off and a foreign OCUORDERS, then Docker reports healthy, the marker equals the image's version, and the log line and the note are row 11's. Here the after-start (the registry, and `after-start.sh`'s log and marker) is the consumer of the step's warning and of its OK.
- **The other production.** Given row 4's final restart, with demo mode off and a stopped other production defined in OcuTalon's OCUORDERS, when the start ends, then the same holds, with row 12's warning, note and removed access.
- **The sign-in page (Integration AC, Rule 1).** Given `Test.Web.PublicTexts`, when it renders the three label keys, then the sign-in page's copies equal them. The sign-in page's copy set is the consumer.
- **Hosted checks.** Given the whole tree, when `bash ci/checks.sh` runs, then it passes (ASCII, storage, class rules, boundaries).

### Review Findings

Code review, October 20 (`bmad-code-review`, tier `full-opus`; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all on this checkout with no change by any layer; 33 rows, 8 entries after grouping: 1 high, 2 medium, 5 low). Each entry gives severity / fix-risk / Rule 15 disposition. Every patch is in-story, with fix-risk low; the runtime results and mutations are under Verification, "Code review".

- [x] [Review][Decision, resolved by the lead: the owner approved the sentence through the Contest Planner on October 21, and the rework added it (5cba5e0)] The `demoKept` note does not say how to remove a kept OCUORDERS by hand. The owner's words (cycle log, owner decision 2) are "show a status note saying how to remove it by hand", and AD-3 as amended says the same; the note holds 0.10's kept sentence and the namespace's two databases, which say what was kept, not how to remove it. Design Notes park the how-to sentence for the Contest Planner, but no outbox item and no ledger row carries it, so nothing tracks it. The fix is product text, which this review may not write. Filed DW-44 `decision-pending owner=0-12-epic-0-burn-down` for the lead (Rule 22). Recommendation: the lead drafts the sentence under Rule 22.3 (admin-facing text; VETO WINDOW FYI), and the rework adds it as a `how` field of the note (`Demo.cls` L356) with a `kept_note` check in `test-install-start.sh`; the alternative is to move this part of the AC to a named later story of the same release under 22.3 with its DW bullet and an outbox item for the wording. high (Rule 6) / low / decision-pending.
- [x] [Review][Patch] The stopped-foreign keep fixture asserted on the running fixture's leftovers: `CHK|grantee|1` counted the running fixture's seed, and `CHK|own|0|0|0` was already true before the run. Each keep fixture now seeds and removes its own `ZzOcuGrantee` (the separate removal session is folded in), and the stopped fixture's label says that OcuTalon's access stays removed (the last restart shows the removal at a real start) [docker/tests/test-install-start.sh:522, :549]. med (Rule 19) / low / fixed.
- [x] [Review][Patch] Four mark assertions of the live script read a mark that the session neither set nor checked: the off run while the Orders production runs expected `<absent>` for a mark that was already absent; row 3's on refusal and the Troubled recovery relied on the note an earlier session wrote; and the in-session foreign off run cleared the mark without checking the clear. Each now seeds `demoKept = stale` itself (row 3's on refusal reads it back raw and clears it), or prints `CHK|cleared|1|` [docker/tests/test-install-start.sh:340, :354, :586, :621]. med (Rule 19) / low / fixed.
- [x] [Review][Patch] `inside_state` counted the package mappings only, so a keep that deleted the public global mapping or retargeted a mapping stayed green. The fingerprint now lists every package and global mapping of OCUORDERS with its database [docker/tests/test-install-start.sh:233]. low / low / fixed.
- [x] [Review][Patch] `TestStatusMarkRecord` could not tell a replace that keeps the first `RecordedAt` from one that stamps it again. The row's stamp is set back to 2000 before the replace, so the existing time check now covers the replace [src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:105]. low / low / fixed.
- [x] [Review][Patch] `Install.Step`'s class comment listed `Warn` among the methods "an area overrides"; an override would drop its warnings from the registry. The comment now names `Warn` and `TakeWarnings` as shared helpers that an area calls and never overrides [src/ocutalon/cls/OcuTalon/Install/Step.cls:2]. low / low / fixed.
- [x] [Review][Patch] `StatusMark.Record`'s comment read "a mark that has none is an error status", which can be read as an empty value. It now says that an empty mark name is the error and that a replace stamps `RecordedAt` again [src/ocutalon/cls/OcuTalon/Data/StatusMark.cls:19]. low / low / fixed.
- [x] [Review][Patch] Stale comments in the live script: the header's demo-mode timeline stopped at row 4's recreate (the last restart switches it off again), the grantee note described one seed across both keeps, and the 0.10 block's helper list left out `inside_state`, `foreign_grant` and `check_kept_log` [docker/tests/test-install-start.sh:18, :36, :317]. low / low / fixed.

Rejected (no ledger entry):
- The keep path deletes the trace role's privilege row with `Security.SQLPrivileges.%DeleteId` and not `RevokePrivilege`, so the privilege might survive (EC). False, measured: `$SYSTEM.SQL.Security.CheckPrivilege("OcuTalonTraceViewer",1,"Ens.MessageHeader","s","OCUORDERS")` reads 1 before each keep and 0 after it in the review's live run. `own_access` now prints that check as a fourth field, so the AD-24 pin covers the privilege as SQL checks it, not only the row.
- The keep filter compares `Grantee` case-sensitively (EC). False: OcuTalon grants with the same constant, and the live run reads 1 row before and 0 after.
- The Orders production keeps running when another production is only defined (EC), and WARN lines do not reach `docker logs` (EC, VG). Spec-bound, by-design: Design Notes "What keep removes" (no production stopped or started) and "How a step warns" (`after-start.sh` unchanged, the whole transcript in the after-start log).
- Demo mode off still deletes another grantee's privileges and web applications inside OcuTalon's own OCUORDERS when no other production is there (AA). Spec-bound: the owner's own triggers for keeping (a namespace OcuTalon did not create, or another production) and matrix row 15; the remove path deletes the namespace, so those rows would point at nothing.
- The step's own leftover databases stay when a foreign OCUORDERS is kept (EC). Low: a foreign namespace may map them, so keeping them is the safe side of owner decision 2; the fix adds a branch.
- `Test.Install.Registry`, `Test.Web.Shell` and `Test.Web.Install` kill their counter in `Clean()`, so the new `ZzRunWarn<n>` is always `ZzRunWarn1` (BH). Low: each run creates and removes its fixtures, and Rule 18 never runs two test classes at once on an instance; two of the classes are outside this story.
- `incident.noFixUnknown` reads "the failed messages and their errors" at a count of 1 (BH). False: the text is EXPERIENCE.md L827 verbatim, a failed order has several messages, and the owner's table of October 20 is the complete set of count-of-one forms.
- The `TestEnsureCreates` comment rests on a cause QA ruled out (BH). False: it states what the test does (it reads the account back, for up to 2 s), and QA kept the bounded wait on purpose.
- `Account`'s wait gives up at once when `Exists` is 0 (EC). False in effect: the cause of DW-9 was the "|" in the hash (QA), and `Ensure` is asserted OK before the read.
- The forms' `source` does not cite the owner's table (BH). Spec-bound: the grammar of `one` is `{slot, text, web}`, and the entry's `source` names its UX section.
- The live script's labels mix 0.10's and 0.12's matrix rows (BH). Low: each label also states the check in words; relabelling every check is not a direct correction.
- `StatusMark.Record` has no lock (EC), and untaken warnings could pile up in a pooled process (EC). Theoretical: the start is the only writer and the only caller today; 4.1 is specified to call `TakeWarnings`.
- `TestWebWording` and `TestTypography` throw on a `one` that is not an object, and `TestCountOfOneForms` on an unknown key (EC). Low: `TestEntries` names such an entry, and a throw fails the method.
- "The account has a password hash" cannot be turned red through `Ensure` (VG). False: the implement stage recorded why (the instance refuses an empty password), and QA's `Line` mutation turns it red.
- Two assertions count the test's own XData (VG), and `result.allThrough`'s "only another count is 1" case repeats the slot-at-2 case (VG). Low and false: the spec dictates the counts, the assertions next to them tie them to the catalog, and QA scoped the case to the other 7 keys.
- The Review-pass ruling on the counter pin lists "calling `Clean()` mid-class" as rejected, which QA's `TestCleanKeepsTheCounter` now does (AA). Low: the fix edits the spec under review; QA's section under Verification explains the change.
- AD-23's step list says Demo off "removes them" with no keep (AA). False: "them" is the trace application and the trace role's grants, which the keep path removes too; the keep is in AD-3.
- The diff changes `_bmad/custom/skill-rules.md` (AA). False: it is Rule 21's run record, the one entry QA may write.

### Review Findings (re-review)

Code review re-review, October 21 (`bmad-code-review`, tier `full-opus`), scoped to the rework's diff `git diff 5047cd2 5cba5e0 -- . ':(exclude)_bmad-output'` (DW-44; 2 files, +44 -26). Layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all on this checkout, none changed anything; 11 raw findings, 9 entries after grouping: 0 high, 0 medium, 2 low patched, 7 rejected. Each entry gives severity / fix-risk / Rule 15 disposition.

- [x] [Review][Patch] `Run`'s doc comment did not parse: "recorded as the mark demoKept, with the fact that it holds in the note's "how" sentence". It now reads "recorded as the mark demoKept, whose "how" sentence names what the namespace holds" (comment only) [src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls:68]. low / low / fixed.
- [x] [Review][Patch] The rework's last two mutation lines began `mutation (review pass, ...):`, so a search for `mutation:` missed the only records for the "drops" clause and for "the `WARN Demo` line keeps Story 0.10's sentence". Both now begin `mutation:`, with the review-pass note after them; what they record is unchanged [this spec, `### Rework, DW-44` under Verification]. low / low / fixed (Rule 19's sanctioned Verification edit).

Checks the lead asked for:
- **The sentence, byte for byte.** A script compared `EXPERIENCE.md` L702's quoted sentence with `System`'s template (`ns`, `CODEDB`, `DATADB` = OCUORDERS, OCUORDERS_CODE, OCUORDERS_DATA) and with `foreign_how`, `running_how` and `defined_how`: the template equals the owner's text, and each expected string is the owner's prefix and suffix around its fill. The fills are "databases that OcuTalon did not create" (`Plan`), "the production <name>, which is not stopped" and "the production <name>" (`Orders(0)`), the three keep paths, each the fact that its kept sentence names.
- **`WARN Demo`.** `Do ..Warn(kept)` is unchanged, so the after-start line keeps Story 0.10's sentence. `check_kept_log` at rows 3 and 4 and the in-session `CHK|warn` values pin it, and the `Warn(what)` mutation turned them red.
- **`kept_note`.** It prints `how` as a seventh field, and `compare_chk` matches whole lines (`grep -qxF`). All five note checks (row 3's start, the in-session foreign run, the running and the stopped keep fixtures, the last restart) expect the sentence in full. Four demonstrated mutations stand behind them: alter, fill, drop, and `Warn(what)`.
- **Nothing else changed.** The diff adds the `what` output to `Plan` and `Orders(0)`, passes it through `Run` to `System`, and adds the `how` key. `System` and `Orders` are private, with `Run` their only caller, and `Test.Demo.Step:TestPlan`'s five-argument call is still valid. `Warn`, `Record`, the on path and the clear path are untouched.
- **ASCII and paths.** Neither file has a byte above 127, and the diff names no local machine path.
- **The foreign case, judged acceptable as the owner's exact text.** For a foreign OCUORDERS, the `how` sentence names OCUORDERS_CODE and OCUORDERS_DATA, but the note's `globals` and `routines` fields name the namespace's real default databases. They come from `Config.Namespaces`, and row 3 and the in-session run pin them as OCUFOREIGN_DATA and OCUFOREIGN_CODE. It does not mislead into harm:
  - The owner approved this one sentence for the row's whole trigger, "OCUORDERS was not created by OcuTalon, or holds another production".
  - The fixed names never tell an administrator to delete a database that OcuTalon did not name. A sentence that named the namespace's own databases could name a shared one, such as USER.
  - This is a closed owner decision, so it is not `decision-pending`.

Rejected (no ledger entry):
- The foreign OCUORDERS's `how` names databases it does not use, and nothing asks the owner (BH, EC, AA). Low, spec-bound and owner-decided (above). The AC says "exactly", the owner's approval covers "not created by OcuTalon", and the note's `globals` and `routines` name the real databases. by-design. It reopens only through an owner form for the foreign case.
- For a production that is not stopped, the sentence leaves out stopping it before the namespace is deleted, and the Portal's `NamespaceDelete.SaveData` checks no production (BH). The Portal claim is true, and the finding is low. The fix is new owner text. The fill already says "which is not stopped", and the removal is the administrator's own deliberate act. by-design.
- Nothing reads the `how` field, and no log line points to the mark (BH). True, but spec-bound: the intent's Never rules out a new status surface. The after-start log carries the `WARN Demo` line, and DW-45 and DW-46 put the sentence in the README and the security overview. The rework did not cause it.
- `Orders` reads `rs.%Get("Name")` twice in the defined branch (BH). False: both reads take the same column of the same current row, so `kept` and `what` cannot diverge.
- With two or more other productions defined, `SELECT TOP 1` names only one in `what` (EC). Low and pre-existing: the kept sentence has named one since the first pass. Deleting the namespace removes every production, so the removal advice stays complete. A fix adds a loop and changes Story 0.10's fixed sentence, and two other productions in the demo namespace is not an everyday case.
- The five changed note checks depend on the script's staging, not on state they create (VG). Pre-existing and spec-bound: REL-4 allows no new restart, and the rework's triage (VG 3) rejected the same point. Run out of order, they go red, never falsely green.
- Matrix rows 11 to 13 still give the four-key mark (AA). The fix would edit the spec's frozen intent block. The rework task supersedes those rows.

## Spec Change Log

**Task 0 measurements** (implement stage, October 20; `(inference)` where stated):
- **0.1, slot A's identity.** `iris_server_info` on `ocutalon-slot-a` reports `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U)`, and the profile roster reports the web port 52790. The call does not report the superserver port, so 1990 is Rule 21's figure `(inference)`.
- **0.2, DW-9 before the fix.** Ten calls of `OcuTalon.Test.Install.Users` on slot A (run indexes 637 to 646) all passed, with no empty hash. `^OcuTalonTest("Users","n")` read as undefined after every run, because `Clean()` killed it in `OnAfterAllTests`: so the fixture was `ZzUsers1` in every run, by the code. The flake did not reproduce in ten runs, and its cause stays `(inference)`: a read soon after the create, or two runs sharing `ZzUsers1`.
- **0.3, DW-42, the stopped-foreign fixture.** In the first `live install-start` run, `Ens.Config.Production.LoadFromClass("ZzOcuForeign.Production")` in OCUORDERS returned OK, `SELECT COUNT(*) FROM Ens_Config.Production WHERE Name = ?` found the production (1), and the Orders production kept running, so the foreign production was defined and not started. The last fixture before row 4's final restart uses `LoadFromClass`; the start-then-stop fallback was not needed.

**Rule 22 rulings** (implementation choices that the spec leaves open):
- Rule 22 ruling: **How `Demo.Run` reaches the keep mode** -> `System(on, keep = "", Output note)`: `keep` is the warning sentence (non-empty means the keep mode) and `note` is the JSON for the mark. The keep mode is the off path of `System` with two filters, so the trace application is deleted by name, the SQL privileges are those of the trace role (a `Continue` in the existing loop), and the namespace, marker and role deletions are skipped. (Rejected: a second %SYS method, which copies the grant and privilege code (Rule 2); parameterized SQL filters such as `(? = '' OR Name = ?)`, whose empty-string and NULL semantics are not measured.)
- Rule 22 ruling: **Where the form is chosen in `Catalog`** -> a private `Template(context, entry, field, values)` that `Build` calls in place of `entry.%Get(field)`: it reads the form's slot with `Count` first, and returns the form's `text` or `web` when that slot is 1. (Rejected: inline code in `Build`, which grows past a screen; a public method, which widens AD-32's API for tests.) Its three refusals (a `one` that is not an object, a slot that is not a declared count slot, a form with no text for the channel) are defensive: the shipped catalog cannot reach them because `TestEntries` refuses such an entry, and a private method has no test of its own.
- Rule 22 ruling: **What pins `TestEntries`' rules for a one form** -> `TestCountOfOneForms` also copies two real entries, sets one fault at a time (an unknown field, an undeclared slot, a slot that is not a count, a text that holds the form's own slot, a text that lacks a declared slot, an empty text, a `web` where the entry has none, a `web` with a placeholder of its own, a form with no `web` where the entry has one, a `one` that is not an object) and asserts that `Problems` names it. (Rejected: leaving the rules unpinned, since a checker that has never been seen red proves nothing.)
- Rule 22 ruling: **Row 16's failing-step line** -> the fixture step `ZzRunWarn<n>` fails on a flag (`^OcuTalonTest("Registry",n,"warnFails")`) that the test sets for the second run, so one compiled class pins both the WARN line after `STEP ... OK` and the WARN line after `STEP ... FAILED`. (Rejected: a second fixture class, one more compile.)
- Rule 22 ruling: **`check_demo_off "row 3"` in `test-install-start.sh`** -> it runs after `set_demo_mode 0`, because the on-path refusal fixture leaves demo mode on, and `check_demo_off` reads `demo.mode`. (Rejected: dropping the setting check.)
- Rule 22 ruling: **Rows 14 and 15 in the live script** -> the first partial-state session records a sentinel mark `demoKept = stale` before the on-path error and expects it unchanged after (row 14); the next off run, which removes, expects the mark absent (row 15); the Troubled-recovery run (a create) expects it absent after a keep had set it. Each session that keeps checks OcuTalon's own access before (`CHK|own-before|1|1|1`) and after (`CHK|own|0|0|0`), so the removal is shown and not assumed. (Rejected: checking only the final absence, which an earlier run could already have caused.)
- Rule 22 ruling: **The helpers of the live script** -> `demo_run`, `fixture_class` and `foreign_state` move to a new helper section before row 3 (the foreign build now runs before row 3's recreate), beside the new `kept_note`, `own_access` and `check_kept_log` and the three fixed sentences; `foreign_state`'s body is unchanged. (Rejected: copies in both places.)
- Rule 22 ruling: **`Clean()` of `Test.Install.Users`** -> it kills every node of `^OcuTalonTest("Users")` but the counter `"n"`, as the spec says; the class writes no other node today, so the loop kills nothing yet. (Rejected: dropping the loop, which leaves a later node to survive.)

**Review-pass rulings** (Rule 22; the review patches, October 20):
- Rule 22 ruling: **Which post-create reads of `Test.Install.Users` wait** -> `TestEnsureCreates` and the `before` read of `TestEnsureKeepsAnExistingAccount` pass `wait` 1; the later reads, which follow a `Modify` of an account whose hash was already read, do not. The task text said `TestEnsureCreates` alone, and the intent contract says "a read that re-opens the account until its hash is there"; the cause of DW-9 is still `(inference)`, so a second create-then-read in the same class has the same exposure, and the wait returns on the first read when the hash is there. (Rejected: the wait as the default of `Account`, which also waits after a hand-made `Modify`; leaving the sibling read unguarded.)
- Rule 22 ruling: **How the counter's survival is pinned** -> `Clean()` calls a new `ClearNodes()` (the loop that kills every node but `"n"`), and a new `TestClearKeepsTheCounter` seeds a probe node, calls `ClearNodes()` and expects the probe gone and `"n"` equal to the run's number. (Rejected: calling `Clean()` mid-class, which would delete the run's own roles; a cross-run comparison, which one run cannot make.)
- Rule 22 ruling: **What proves that keep leaves the inside of OCUORDERS alone** -> `inside_state <variable>` in `test-install-start.sh` sets a fingerprint (databases, resources and files, package mappings, Interoperability marker and role, web applications but the trace application, portal folder) before and after the run in both keep fixtures that hold OcuTalon's own OCUORDERS, and prints `CHK|inside|<before = after>|<the portal application is still there>`. (Rejected: literal expected fingerprints, which would need a measurement per machine; a foreign web application seeded into the foreign fixture, which is a new object type for a boundary that the owned-namespace fixtures already pin.)
- Rule 22 ruling: **Where a stale warning is pinned** -> `TestRun` records a warning before the third run and expects the run's output to hold no such text. (Rejected: a separate test method, one more compile of the fixture steps.)

**Rework rulings** (Rule 22; DW-44, October 21):
- Rule 22 ruling: **What fills `{what was kept}`** -> the fact that the note's kept sentence names, as a phrase: "databases that OcuTalon did not create" for a foreign OCUORDERS, "the production <name>" for a production that is only defined, and "the production <name>, which is not stopped" for one that is not stopped (the running sentence names that fact too). (Rejected: "the production <name>" for both, which drops a fact the kept sentence states.)
- Rule 22 ruling: **How the phrase reaches the note** -> `Plan` and `Orders(0)` return it in a new `Output what` beside `kept`, `Run` passes it to `System(0, kept, what, .note)`, and `System` builds the `how` sentence from the owner's text with the namespace and database names taken from `NAMESPACE`, `CODEDB` and `DATADB`. (Rejected: parsing the phrase out of `kept`, which ties the note to the wording of three sentences; a second write of the note from `Run`.)
- Rule 22 ruling: **The databases in the sentence** -> OCUORDERS_CODE and OCUORDERS_DATA exactly as the owner's text has them, for a foreign OCUORDERS too, whose own default databases are in the note's `globals` and `routines` fields. (Rejected: the foreign namespace's databases in the sentence, which edits the owner's text.)
- Rule 22 ruling: **What `kept_note` pins** -> `kept_note` prints the `how` field as a seventh value, and each of the five note checks expects the owner's sentence written out in full (`foreign_how`, `running_how`, `defined_how`), so that a change to the step's wording goes red. (Rejected: a sentence composed from a template in the script, which follows a change of the step's template.) `Test.Demo.Step` is unchanged: no test of it pins the note's shape, and `TestPlan` still passes with the added output.


**Rework pass** (DW-44, October 21):
- Baseline: the story's `baseline_revision` was `56ea3de33c333569fc041ee85b9a20cb614dd4c7` before this pass. Step 3 captures a baseline per pass, so the frontmatter now holds this pass's `5047cd2e90c8e651aa58e05854e94a160c092c60`; the story's delivered scope is `git diff 56ea3de33c333569fc041ee85b9a20cb614dd4c7..HEAD`.
- Rule 22 ruling: **The review pass's two mutations ran in one live run** -> the `how` key dropped and `Warn(what)` in place of `Warn(kept)`, because they fail different checks: the first only the five `CHK|note` checks (`1 of 2` and `1 of 3` values at rows 3 and 4), the second only `check_kept_log` at rows 3 and 4 and the `CHK|warn` values of the in-session fixtures. (Rejected: two runs of about 3 minutes each for the same attribution.)
- Rule 22 ruling: **The foreign case keeps the owner's exact sentence** -> the review layers noted that the sentence names OCUORDERS_CODE and OCUORDERS_DATA for a foreign OCUORDERS too, whose own databases are in the note's `globals` and `routines`. The task says "exactly", so the code and the pins follow the owner's text; the triage log rejects the finding as spec-bound. If the owner wants a different sentence for a foreign namespace, that is one more owner form, and the change is the `how` line of `System` and `foreign_how`.

Lead, after code review (October 21):
- Correction: the review-pass ruling that rejected "calling `Clean()` mid-class" is superseded by QA's `TestCleanKeepsTheCounter`, which does exactly that on purpose to pin DW-9's never-reset counter; the test creates and removes its own state, so it stays.
- DW-44 (code review's HIGH, the note had no how-to sentence) is decided: the owner approved the sentence through the Contest Planner on October 21, and the rework task above adds it.
## Review Triage Log

### 2026-10-20 — Review pass
- verdicts: 33 findings — high 0, medium 9, low 18, false 6, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind Hunter 1: `TestEnsureKeepsAnExistingAccount` reads its `before` hash straight after the create, without the DW-9 wait — the same create-then-read as `TestEnsureCreates`, and the cause of DW-9 is `(inference)`, so the exposure is the same; the read now passes `wait` 1 (Rule 22 ruling above).
  - `[low]` `[reject]` Blind Hunter 2: `Demo.Run` does not clear the process-private warnings on entry — by design: `Step.Warn`'s contract says an untaken warning stays with the caller, 4.1 is specified to call `TakeWarnings`, and clearing at entry would drop a caller's untaken lines; the registry clears before each step.
  - `[low]` `[reject]` Blind Hunter 3: a failing `StatusMark.Record` after `Warn` fails the step — a failing write to the private database is a failure of the install, not a kept-namespace condition; the note is about 150 characters against the 1000 of `Value`; fixing it adds a branch for no reachable case.
  - `[low]` `[reject]` Blind Hunter 4: a running Orders production with a foreign production only defined is untested and not mentioned by the note — the behavior is the spec's ruling ("stops and starts no production"), it is not a matrix row, and one more fixture costs REL-4 time.
  - `[medium]` `[patch]` Blind Hunter 5: `TestCountOfOneForms` cannot tell the validation cases apart — every invalid `resendCount` is also refused by the plural text's own placeholder, so no test pinned `Template`'s own `Count`; the slot of every form is now also refused as the text 1 and as true, which would select the form if the slot were compared raw (mutation recorded). Its three defensive refusals stay untested, as the Rule 22 ruling says (`TestEntries` refuses such an entry first).
  - `[low]` `[reject]` Blind Hunter 6: `StatusMark.Record` has no lock and does not document the 1000-character limit — its writers are single (the start, one heartbeat); a clash or an over-long value is not reachable today, and a lock is new surface for 10.3 to decide.
  - `[low]` `[reject]` Blind Hunter 7: rows 1 and 2 do not assert that an ordinary start has no WARN line or mark — the in-session runs that remove or create assert `CHK|warn|0|` and `CHK|note|<absent>`, and the Demo step warns only on the keep path.
  - `[low]` `[reject]` Edge Case Hunter 1: `Account`'s wait quits on the first miss of `Exists` — the DW-9 symptom was an existing account with an empty hash, and `Ensure` is asserted OK before the read.
  - `[medium]` `[patch]` Edge Case Hunter 2: the post-create read of `TestEnsureKeepsAnExistingAccount` has no wait — same root cause as Blind Hunter 1, patched together.
  - `[low]` `[reject]` Edge Case Hunter 3: `StatusMark.Record` race — same root cause as Blind Hunter 6.
  - `[low]` `[reject]` Edge Case Hunter 4: `Demo.Run` outside the registry leaves warnings — same root cause as Blind Hunter 2.
  - `[low]` `[reject]` Edge Case Hunter 5: the row 3 recreate no longer is a real start with demo mode off and OCUORDERS absent — the spec moves the foreign build to row 3's recreate, and the no-op is still checked in-session (`check_demo_off "row 3"` after the fixture's removal) and by row 2's start.
  - `[medium]` `[patch]` Verification Gap 1: "removes only OcuTalon's own access" was observed in one direction — a keep that deleted `/csp/ocuorders` stayed green; both owned-namespace keep fixtures now compare a fingerprint of the inside of OCUORDERS before and after, and the portal application must remain (mutation recorded).
  - `[medium]` `[patch]` Verification Gap 2: the registry's "discard warnings before each step" had no test — `TestRun` now records a stale warning first and expects it absent (mutation recorded).
  - `[medium]` `[patch]` Verification Gap 3: DW-9's counter half was unpinned and the recorded mutation went red at `Ensure`, not at the fix — `ClearNodes` and `TestClearKeepsTheCounter` pin the counter (mutation recorded). The wait half cannot be forced to fail: closed as accepted, with the 10-run evidence recorded as weak (the flake did not reproduce before the fix either).
  - `[low]` `[reject]` Verification Gap 4: three assertions count the test's own literals (`Gaps` size 0, `notInUx` 0, 8 forms) — the spec dictates them, and the assertions that tie them to the real catalog sit next to them.
  - `[low]` `[reject]` Verification Gap 5: the stopped-foreign fixture's `CHK|own|0|0|0` has no `own-before` — the removal is pinned by the running-foreign fixture and by the last restart, which both read `own-before 1|1|1`.
  - `[low]` `[patch]` Verification Gap 6: the in-session foreign note equals the note row 3's start wrote — the session now clears the mark first, so the check shows that the run records it.
  - `[medium]` `[patch]` Verification Gap 7: `TestStepDefaults` expects an empty warning global without clearing it, which depends on `TestRun` — it takes the warnings first.
  - `[low]` `[reject]` Verification Gap 8: no `mutation:` line for the fresh-environment AC — the AC is shown by the four shard runs, and there is no pinning assertion to mutate.
  - `[low]` `[patch]` Verification Gap 9: the DW-9 AC's one mutation line does not touch the fix — the counter mutation is recorded under the review pass.
  - `[low]` `[patch]` Verification Gap 10: no `mutation:` line for the foreign-namespace AC — `Run` without its `Warn` goes red at row 3's `check_kept_log` (recorded).
  - `[low]` `[reject]` Verification Gap 11: no `mutation:` line for the hosted-checks AC and for matrix rows 14 and 15 — the hosted gate is its own check, and rows 14 and 15 are matrix rows with in-session pins, not ACs.
  - `[medium]` `[patch]` Verification Gap 12: `TestEnsureKeepsAnExistingAccount` reads without the wait — same root cause as Blind Hunter 1.
  - `[low]` `[reject]` Verification Gap 13: `Template`'s three refusals have no test — same root cause as the second half of Blind Hunter 5; unreachable on a shipped catalog.
  - `[low]` `[reject]` Intent Alignment 1: the product's `Template` validates less than the test's `Problems` — the product refuses what it cannot render, and `TestEntries` gates the shape of the shipped catalog (row 10).
  - `[false]` `[reject]` Intent Alignment 2: no product code consumes the new keys yet — the spec says so under Integration ACs; 7.2 and 6.3 are the first consumers.
  - `[false]` `[reject]` Intent Alignment 3: the sign-in test compares the parameters, not the rendered page — the spec leaves `Login` unchanged, and `Test.Web.SignIn` pins the page.
  - `[false]` `[reject]` Intent Alignment 4: the keep branch is reached only by the live script — the spec's Rule 21 split; slot A never runs `Demo.Run()`.
  - `[medium]` `[patch]` Intent Alignment 5: the owned-namespace keep fixtures do not cover the inside of OCUORDERS — same root cause as Verification Gap 1; its other parts (row 13 at a start, the on-path refusal of a running production) share the `Quit sc` path that two other error fixtures already pin.
  - `[false]` `[reject]` Intent Alignment 6: the WARN line is in the after-start log and not on stdout — the spec's ruling; `after-start.sh` is not to change.
  - `[false]` `[reject]` Intent Alignment 7: the note holds the facts, not the how-to-remove sentence — the sentence is owner-only (Rule 22.4) and parked in Design Notes for the Contest Planner.
  - `[false]` `[reject]` Intent Alignment 8: DW-9 changes the test surface only — the spec closes it on evidence and on the test fix; `Users.Ensure` is not at fault.

### 2026-10-21 — Review pass (rework, DW-44)
- verdicts: 21 findings — high 0, medium 0, low 20, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind Hunter 1: the `how` sentence names OCUORDERS_CODE and OCUORDERS_DATA for a foreign OCUORDERS too, whose own databases are in the note's `globals` and `routines` — spec-bound: the task says "exactly" and the owner approved this text for "not created by OcuTalon, or holds another production"; a foreign OCUORDERS needs a user-made namespace of that name, and the note's other fields name its databases. Reopens only by an owner form for the foreign case (Spec Change Log, Rule 22 ruling).
  - `[low]` `[reject]` Blind Hunter 2: `Plan`'s new `what` has no unit assertion — `TestPlan` still passes with the added output, and the live script pins `what` for all three kept cases (the rework's mutation 2 turned `Plan`'s `what` empty and went red); a unit assertion is a change beyond the task's "No other change".
  - `[low]` `[reject]` Blind Hunter 3: the spec still describes the pre-rework shape in places (matrix rows 11 to 13, the Code Map signatures, an earlier ruling, the Auto Run Result, a stale "below") — the fix is to edit the spec, and rows 11 to 13 are in the frozen intent block; the Auto Run Result and the stale pointer were corrected at finalize.
  - `[low]` `[defer]` Blind Hunter 4: Stories 10.2 and 14.2 have no acceptance criterion for the sentence the README and the security overview carry — not caused by this change (the UX row predates it) and `epics.md` is not this build's to edit; deferred in the frontmatter.
  - `[low]` `[reject]` Blind Hunter 5: `baseline_revision` now holds this pass's baseline — step 3 captures one per pass; the story's baseline is recorded in the Spec Change Log, and the fix would edit the spec.
  - `[low]` `[reject]` Blind Hunter 6: `System` writes "holds . To remove it" if called with `keep` and no `what` — unreachable: `System` is private, `Run` is its only caller, and `Plan` and both kept branches of `Orders(0)` always set `what`; a guard adds a branch.
  - `[low]` `[reject]` Edge Case Hunter 1: the foreign databases in the sentence — same root cause as Blind Hunter 1.
  - `[low]` `[reject]` Edge Case Hunter 2: `System` with `keep` and an empty `what` — same root cause as Blind Hunter 6.
  - `[low]` `[reject]` Edge Case Hunter 3: `TestPlan` does not assert `what` — same root cause as Blind Hunter 2.
  - `[low]` `[reject]` Edge Case Hunter 4: the Tasks bullets give the old signatures of `Plan` and `Orders(0)` — those bullets belong to done, reviewed tasks and the fix would edit the spec; the code and its comments carry the new signatures.
  - `[low]` `[patch]` Verification Gap 1: the AC "the after-start `WARN Demo` line keeps Story 0.10's sentence" has no rework mutation line — applied `Do ..Warn(what)` in place of `Do ..Warn(kept)`, observed red at `check_kept_log` of rows 3 and 4 and at the in-session `CHK|warn` values, reverted byte-identical, line written in `## Verification`.
  - `[low]` `[patch]` Verification Gap 2: only "alters" is demonstrated, not "drops" — applied the note built without its `how` key in the same run, observed red at the five note checks, reverted, line written in `## Verification`.
  - `[low]` `[reject]` Verification Gap 3: the changed note checks sit in a staged, order-dependent live script — pre-existing and spec-bound (REL-4 forbids a new restart; the staging is the existing design); the diff changes expected strings only.
  - `[low]` `[reject]` Verification Gap 4: the foreign fixture pins the sentence with OCUORDERS_CODE and OCUORDERS_DATA — same root cause as Blind Hunter 1.
  - `[low]` `[reject]` Verification Gap 5: the Auto Run Result was not updated for the rework — written at finalize, as the workflow orders; not a defect of the change.
  - `[low]` `[reject]` Intent Alignment 1: no admin-visible surface for the note beyond the status mark — the intent's Never: "no new status surface"; the README and the security overview (10.2, 14.2) are the surfaces, tracked by the deferred item.
  - `[low]` `[reject]` Intent Alignment 2: the pin on `how` exists only at the live layer — same root cause as Blind Hunter 2; `System`'s keep branch runs only through `Run()`, which Rule 21 bars from slot A.
  - `[low]` `[reject]` Intent Alignment 3: the `what` phrases repeat the kept sentences' facts in three places — a drift would turn the five `CHK|note` checks red (mutation 2 shows it), and deriving one from the other adds a parser or a structure.
  - `[low]` `[reject]` Intent Alignment 4: the foreign case (verbatim databases against functional ones) — same root cause as Blind Hunter 1.
  - `[low]` `[reject]` Intent Alignment 5: the matrix rows 11 and 12, the `kept_note` description of Design Notes and the AD-3 spine-update entry still give the four-field mark — the fix is to edit the spec, and the rows are in the frozen intent block; the code, its comments and the live script give the five fields.
  - `[false]` `[reject]` Intent Alignment 6: the note may pass the `Value` limit of 1000 — the longest note (a 220-character production name, not stopped, and 30-character database names) is 891 characters.

## Design Notes

**ADs:**
- **AD-32:** the renderer as built, and the entry grammar.
- **AD-3:** the off path as amended by owner decision 2.
- **AD-24:** the OCUORDERS grants and the trace application exist only with demo mode on.
- **AD-23:** the step contract, the registry's log lines and the ready marker.
- **AD-19:** the configuration homes; why the note is not a `Data.Setting` row.
- **AD-18:** `StatusMark`.
- **AD-12:** the closed status conditions, not extended.
- **AD-29 and AD-33:** the lanes.
- **AD-22:** the shards and the throwaways.
- **AD-5:** storage is append-only.

No AC contradicts an AD's Rule. DW-42's "left in place", read with AD-24, means the namespace stays and OcuTalon's own access to it goes (ruling below). No NFR is touched, and REL-4 is measurable as worded, so no tripwire fires.

**The owner's table** (EXPERIENCE.md L688–701; owner decision 1, October 20), verbatim:

| Where | When | Text |
| --- | --- | --- |
| Dry run | resend count = 1 | "I'll resend 1 repaired copy; the original stays unchanged." (in place of "I'll resend {resend count} repaired copies; the originals stay unchanged.") |
| All went through | count = 1 | "The {item noun, one} went through." For example, "The order went through." |
| Some failed again | failed again = 1 | "... 1 failed again ({fail reason}). I won't retry it without a new approval." |
| Some skipped | skipped = 1 | "... 1 had changed since the dry run, so I skipped it; it needs a new approval." |
| Some failed again and some skipped | skipped = 1 | "... so I skipped it." The rest is unchanged: "any of them" stays, since there are always at least two. |
| Still running after the wait | completed = 1 | "Still resending: 1 of {count} {item noun} has gone through so far. I'll tell you when it's done." |
| Cut off by a restart | remaining = 1 | "The other one needs a new approval." |
| Already answered (a late press) | rejected | "Already answered: rejected from {channel} at {time}." |
| Already answered, with a user | a local install with more than one user | "Already answered: approved by {user} from {channel} at {time}." and "Already answered: rejected by {user} from {channel} at {time}." |
| Sign-in page labels | always | "User name", "Password" and "Show password" are catalog texts. |

**The forms** (`Catalog.Watch`; `one.slot`, then `one.text`; "…" is the entry's own text, unchanged):

| Key | `one.slot` | `one.text` |
| --- | --- | --- |
| `incident.withFix`, `incident.laterRequest` | `resendCount` | the entry's `text` with "I'll resend {resendCount} repaired copies; the originals stay unchanged." replaced by "I'll resend 1 repaired copy; the original stays unchanged."; `one.web` is the entry's `web` with the same replacement |
| `result.allThrough` | `count` | "The {itemNoun} went through." |
| `result.failedAgain` | `failedAgain` | "{completed} of {count} {itemNoun} went through. 1 failed again ({failReason}). I won't retry it without a new approval." |
| `result.skipped` | `skipped` | "{completed} of {count} {itemNoun} went through. 1 had changed since the dry run, so I skipped it; it needs a new approval." |
| `result.failedAndSkipped` | `skipped` | "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}), and 1 had changed since the dry run, so I skipped it. I won't retry any of them without a new approval." |
| `result.stillResending` | `completed` | "Still resending: 1 of {count} {itemNoun} has gone through so far. I'll tell you when it's done." |
| `result.interrupted` | `remaining` | "The resend stopped when OcuTalon restarted: {completed} of {count} {itemNoun} went through. The other one needs a new approval." |

**The new Core entries** (each `source` starts "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / "):

| Key | Text | Slots | Source suffix |
| --- | --- | --- | --- |
| `answered.alreadyRejected` | "Already answered: rejected from {channel} at {time}." | channel, time | "Already answered, rejected" |
| `answered.alreadyApprovedBy` | "Already answered: approved by {user} from {channel} at {time}." | user (text), channel, time | "Already answered, with a user" |
| `answered.alreadyRejectedBy` | "Already answered: rejected by {user} from {channel} at {time}." | user (text), channel, time | "Already answered, with a user" |
| `signIn.userLabel` | "User name" | none | "Sign-in page labels" |
| `signIn.passwordLabel` | "Password" | none | "Sign-in page labels" |
| `signIn.showPassword` | "Show password" | none | "Sign-in page labels" |

**Rule 22 rulings** (question → choice (rejected: …)):

*The catalog:*
- Rule 22 ruling: **The shape of a count-of-one form** → one optional `one` object per entry, `{"slot", "text", "web"}`, which `Render` uses when that count slot is 1. No entry needs two forms: in `failedAndSkipped` a `failedAgain` of 1 reads correctly as it is. (Rejected:
  - a map of forms per slot, which is more shape than any entry needs;
  - separate keys such as `result.allThroughOne`, which would make producers choose by count, against "`Render` picks the form";
  - an ICU-style plural syntax inside the text, which is a new grammar.)
- Rule 22 ruling: **The form's own count slot** → the form's text doesn't hold it, and writes "1", "The", "it" or "one" as the owner's texts do. Every other declared slot appears. (Rejected: keeping `{slot}` in the text, which the owner's "1 repaired copy" and "The other one" contradict.)
- Rule 22 ruling: **The `gap` field and the `Gaps` list** → both stay in the grammar and in the test, with no entry left. AD-32 still names the field, and a later lane may need it. (Rejected: dropping the field from the grammar.)
- Rule 22 ruling: **The late-press keys** → `answered.alreadyRejected`, `answered.alreadyApprovedBy` and `answered.alreadyRejectedBy`, named as `approvedBy` and `rejectedBy` are. Like `answered.alreadyApproved`, they have no `web` text, because the UX's web-and-phone example ends with its period. The producer picks the `By` forms on a local install with more than one user, as for `answered.approvedBy`. (Rejected: a web wording without the period.)
- Rule 22 ruling: **The sign-in keys** → `signIn.userLabel`, `signIn.passwordLabel` and `signIn.showPassword`, after `Login`'s parameter names, as `signIn.logoAlt` is. `Login` is unchanged. (Rejected: renaming the parameters, which edits the public package for nothing.)

*DW-42:*
- Rule 22 ruling: **Where the status note lives** → the status mark `demoKept` in `OcuTalon.Data.StatusMark` (Lane B, the step's own lane), written through a new `StatusMark.Record(mark, value)`, where "" removes the mark, and read through `Get(mark)`. The after-start log's `WARN Demo` line goes with it. The README (10.2) and the security overview (14.2) point to the mark; an admin reads it with `Write ##class(OcuTalon.Data.StatusMark).Get("demoKept")` or in SQL. 3.7's audit-off status (DW-10) uses the same `Warn` and `Record`. (Rejected:
  - a `Data.Setting` row, because settings are seed values that `SettingsOps` owns after the install (AD-19), and a note is a status;
  - a `^OcuTalonPublic` key or an AD-12 status condition, both closed sets, and the condition would need a banner with owner text;
  - the after-start log alone, which an IPM install doesn't have and which no README can point to as a status.)
- Rule 22 ruling: **How a step warns** → `Install.Step.Warn(text)`. The registry writes `WARN <step> <text>` right after the step's own line, so the line lands in the after-start log and in an IPM install's output. (Rejected:
  - the step `Write`ing the line itself, which would land on whatever device 4.1's caller has;
  - the IRIS console log, which the after-start log doesn't hold;
  - widening `after-start.sh`'s stdout filter, which isn't needed because the log keeps the whole transcript.)
- Rule 22 ruling: **What keep removes** → only OcuTalon's own access: the trace application by name, the trace role's OCUORDERS database grants, and its SQL privileges in OCUORDERS. That keeps AD-24's "exist only with demo mode on" true. It stops and starts no production, so the Orders production, if it runs in a kept namespace, keeps running. (Rejected:
  - leaving the access, which contradicts AD-24;
  - stopping the Orders production, which would be more than "left in place" and isn't the owner's ask.)
- Rule 22 ruling: **The ready-marker assertions** → staged across the existing restarts: row 3's recreate for the foreign namespace, and row 4's final restart for the stopped other production. (Rejected:
  - the in-session `Run()` status alone, because the AC names the marker;
  - a new restart, against REL-4.)
- Rule 22 ruling: **The mark's life** → recorded on every keep, removed on every create or remove that succeeds, and left as it was on an error. So it always describes the last successful run.

*DW-9:*
- Rule 22 ruling: **DW-9** → fix it (a counter that is never reset, and a re-opening read with a bounded wait) and also close it on evidence. (Rejected: evidence only, because 1 in 7 is too rare for two shard runs to rule out.)

**Owner-only (Rule 22.4), for the Contest Planner:**
- Owner-only: **the sentence that tells an administrator how to remove a kept OCUORDERS by hand.** It belongs in the `demoKept` note, and in the README and security-overview text that points to it.
  - The owner approved it through the Contest Planner on October 21 (EXPERIENCE.md, the owner forms table), and the note's `how` field holds it (DW-44).
  - 10.2 and 14.2 carry the same sentence in the README and the security overview.

**VETO WINDOW FYIs (Rule 22.3):**
- **Security posture.** Keep removes OcuTalon's own trace access to a kept OCUORDERS. Reversing it means leaving that access, which contradicts AD-24.
- **Public-facing text.** The WARN line and the note reuse 0.10's error sentences, which are already in the window.
- **Data.** A kept OCUORDERS is never deleted (owner decision 2).

**Integration ACs (Rule 1):**
- **DW-42.** The after-start is the consumer of the step's warning and status: the registry's lines and `after-start.sh`'s log and marker. It is exercised at real starts in rows 11 and 12.
- **DW-41.** The sign-in page's copies consume the three label keys, through `Test.Web.PublicTexts`. No `*Out` operation in this story consumes the count-of-one or late-press keys; the first consumers are 7.2 and 6.3, below.

**Consumed-by (Rule 2):**
- **7.2:** the dry run's one-copy form in `incident.withFix` and `.laterRequest`.
- **7.4:** `result.allThrough`'s form.
- **7.5:** the forms of `failedAgain`, `skipped`, `failedAndSkipped`, `stillResending` and `interrupted`.
- **6.3:** `answered.alreadyRejected`, and the `By` forms on a local install with more than one user, on the web and the phone.
- **12.7:** the same late-press keys in Telegram's press alert ("every copy shows who answered").
- **The sign-in page (0.3):** its three label copies are now compared.
- **4.1:** reruns `Demo.Run()`, reads `TakeWarnings()` and the `demoKept` mark to tell the admin, and gets OK for a kept namespace.
- **15.2:** an IPM install has demo mode off, so a kept namespace shows the WARN line in the install output.
- **10.2 and 14.2:** point to the `demoKept` mark, with the owner's how-to sentence.
- **3.7 (DW-10):** the audit-off warning and status, through `Warn` and `StatusMark.Record`.
- **10.3:** `Record("telegramPaused", until)`, and `RecordTelegram` built on `Record`.
- **2.x `/state` and `StatusMonitor`:** `StatusMark.Get`.

**Consumes:**
- **0.9:** the renderer, both catalog classes and their tests.
- **0.3:** `Login`'s copies.
- **0.10:** the Demo step and `test-install-start.sh`'s fixtures.
- **0.2:** the registry, the step contract and the after-start log.
- **0.4:** `StatusMark`, `Data.Time` and the signature oracle.
- **0.7:** `ci/iris.sh` and the shards.

**Reuse (Rule 2):**
- The form's selection reuses `Count` and `Fill`; there is no second fill path.
- The keep sentences are 0.10's literals, each built once and shared by the refusal and the warning.
- The keep mode is a branch of `System`'s %SYS block: `WithOrders`, and the SQL-privilege row delete of L301–310.
- `TestStatusMarkRecord` sits beside `TestDeliveryStubs`, and `TestCountOfOneForms` uses `RenderAt` and `WithSlot`.
- The never-reset counters follow `Test.Msg.Catalog`'s.
- The live fixtures reuse `check_session`, `foreign_state`, `demo_run`, `fixture_class` and `settle_scheduler`.
- **No copy is made.**

**Ledger inbox (Rule 17), each addressed:**
- **DW-41:** the catalog tasks and rows 1–10.
- **DW-42:** the Step, Registry, StatusMark, Demo and live-fixture tasks, and rows 11–17.
- **DW-9:** Task 0.2, the Users task, row 18 and the fresh-environment AC.

None is declined. DW-20 (escalated) isn't in this story's inbox; it goes to the decision sheet.

**Spine updates for the lead** (Rule 20; each marked `[AMENDED 2026-10-20, Story 0.12, Rule 22 ruling]`). They make the planning artifacts newer than `epic-0-context.md`, so the pre-warm re-runs before Epic 1's first plan.
- **AD-32 "as built" (L828):** an entry may carry `one` `{slot, text, web}`, which `Render` uses when that count slot is 1, and whose text holds every declared slot but its own. Epic 0's gaps are retired.
- **AD-3 (L142):** keep removes only OcuTalon's own access (the trace application, the trace role's grants and its SQL privileges in OCUORDERS), warns with 0.10's sentence, and records the mark `demoKept`.
- **AD-23 (L631):** `Install.Step.Warn(text)` and `TakeWarnings()`; the registry writes `WARN <step> <text>` after the step's line, in the after-start log but not on stdout.
- **AD-18 (L473):** `StatusMark.Record(mark, value)`, where "" removes the mark, and `Get(mark)`, built in 0.12; the Demo step writes `demoKept`.
- **The Structural Seed's cross-lane table (L1053):** `OcuTalon.Data.StatusMark.Record` and `.Get`, Lane B, Story 0.12.

**Time budget** (REL-4; `(inference)` until QA's CI run):
- **`live install-start`:**
  - it gains about 8 sessions and one `LoadFromClass`, and no restart;
  - about +12 s on ARM (151 s → about 165 s), and about +35–45 s on the x64 runner (452–470 s → about 510 s);
  - the `install` group goes to about 14 min 10 s.
- **The run.** Its worst case over the 120 dispatch orders goes from 33 min 7 s to about 33 min 50 s, under 35 minutes.
- **The unit classes** gain a few milliseconds.
- **No rebalance.**

**Size and split line:**
- **Scope.** 15 files: about 120 lines of class code, about 200 lines of tests and JSON, and about 60 lines of shell. That is one implement pass, comparable to 0.9's QA pass.
- **If the lead splits for size** (Rule 22.1), Story 0.13 takes DW-42 (the Step, Registry, StatusMark, Demo, Test.Demo.Step, Test.Install.Registry, Test.Data.Tables, Test.Contract.Ac and live tasks), and 0.12 keeps DW-41 and DW-9.

## Verification

**Runtime targets:**
- **Slot A**, `ocutalon-slot-a`: MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call, after `iris_server_info` shows build 154 on port 1990.
  - Only `iris_doc_load` of the changed classes, with flags `ck`.
  - `iris_execute_tests` of one class per call, waiting for each to finish.
  - Never `Install.Step.Demo.Run()`, `Test.Demo.Production`, or any OCUORDERS work.
- **Throwaways**, only through `ci/iris.sh`, one stack at a time:
  - tag `v12a` (QA uses `v12q`, review `v12r`);
  - `OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`;
  - `ci/iris.sh teardown` with the same tag at the end.
- **Nothing else.** No push and no `gh workflow run`. `ocutalon-aihub-test`, `ocupilot*` and `iris-community-edition` are never touched.

Every command finishes inside one foreground call (`timeout: 600000`). The environment below is `OCUTALON_RUN_TAG=v12a OCUTALON_LOCK_OWNER='epic=0 stage=implement'`.

**Commands:**
- `(once)` **Task 0.1:** `iris_server_info` on slot A. Expected: build 154, port 1990.
- `(once)` **Task 0.2:** `iris_execute_tests` of `OcuTalon.Test.Install.Users` on slot A, 10 calls one after another, with `iris_global_get` of `^OcuTalonTest("Users","n")` after each. Record the failures and the numbers.
- `(loop)` **Slot A load:** `iris_doc_load` of every changed class, with no compile error or warning.
- **Slot A units**, each `(loop)`, one call each: `OcuTalon.Test.Msg.Catalog`, `.Test.Web.PublicTexts`, `.Test.Demo.Step`, `.Test.Data.Tables`, `.Test.Contract.Ac`, `.Test.Install.Registry` and `.Test.Install.Users`. Expected: each passes with no failed or skipped assertion.
- `(once)` **DW-9 after the fix:** `OcuTalon.Test.Install.Users` 10 more times on slot A. Expected: 10 passes, and the counter rises by 1 per run.
- `(loop)` **Hosted checks:** `bash ci/checks.sh`. Expected: exit 0, in about 20 s.
- `(loop)` **Build:** `bash ci/iris.sh build`. Expected: exit 0.
- `(loop)` **The live test:** `bash ci/iris.sh live install-start`. Expected: exit 0 with every PASS line, the new kept checks of rows 3 and 4 among them. About 165 s on ARM, under 10 minutes.
- `(once)` **The upgrade:** `bash ci/iris.sh live install-upgrade`. Expected: exit 0. The registry's change touches every start.
- `(once)` **Fresh-environment check** (Rules 19 and 21), one call each: `bash ci/iris.sh shard lane-a`, `shard lane-a --reverse`, `shard lane-b` and `shard lane-b --reverse`. Expected: 9 and 24 classes passed in each order, with no `FAIL` or `SKIP` line.
- `(loop)` **Teardown:** `bash ci/iris.sh teardown`. Expected: nothing tagged `-v12a-` is left.
- `(once)` **The mutations below.**

**Shared surfaces:**
- **The catalog's key sets and entry grammar:** `Test.Msg.Catalog`'s `Keys`, `Gaps`, `Fixtures` and `ENTRYFIELDS`, with 63, 22 and 85 keys.
- **The public-text classification:** `Test.Web.PublicTexts`' counts, 11, 0 and 19.
- **The Demo step's plan table:** `Test.Demo.Step.TestPlan`, where "leave" becomes "keep".
- **The after-start log's line kinds:** a new `WARN` line. `log_steps` keeps only STEP and RESULT lines, so the `check_log` of every live script stays as it is.
- **`test-install-start.sh`:** its foreign fixtures, and the order of row 3's checks.
- **`StatusMark` rows:** `demoKept`, and the fixture marks `ZzStatusMark<n>`.
- **`Test.Contract.Ac`'s signatures:** the floor stays 48.
- **The counters `^OcuTalonTest("Users","n")` and `("StatusMark","n")`,** which are never reset.
- **Rule 21's counts:** 33 classes, 9 in `lane-a` and 24 in `lane-b`, unchanged.

The implement stage searches the test trees for each old shape before changing it: "leave", "79 keys", `notInUx`, `"gap"`, and the off refusal sentences.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged):
- **DW-41, the forms:** `Build` ignores `one` → `TestCountOfOneForms` red at rows 1–7.
- **DW-41, the gaps:** put a `gap` back on `result.allThrough` → `TestEntries` red.
- **DW-41, the late press:** make `answered.alreadyRejected` say "approved" → `TestEveryKeyOnEveryChannel` red.
- **DW-41, the labels:** make `signIn.showPassword` "Show the password" → `PublicTexts.TestCopiesEqualTheCatalog` red.
- **DW-42, keep** (the pinning test is `test-install-start.sh`'s row 4):
  - `Orders(0)` returns its old error → `live install-start` red at the stopped-foreign fixture (`CHK|run|0`), and dead at "row 4 the restart did not end ready";
  - `Plan` returns "leave" with no `kept` → `Test.Demo.Step.TestPlan` red, on slot A.
- **DW-42, AD-24:** the keep mode skips the trace application's delete → `live install-start` red at `CHK|own|` (a separate run).
- **DW-42, the warning:** `Registry.Run` writes no WARN line → `Test.Install.Registry.TestRun` red.
- **DW-42, the mark:** `Record` ignores an empty value → `Test.Data.Tables.TestStatusMarkRecord` red.
- **DW-9:** `Ensure` creates the account with an empty password → `TestEnsureCreates` red at "the account has a password hash", on slot A.

**Implement-stage results** (October 20, all on this checkout; tag `v12a`, `OCUTALON_LOCK_OWNER='epic=0 stage=implement'`):
- **Slot A, load and units.** `iris_doc_load` with `ck` of the 15 changed classes: no error or warning. `Test.Msg.Catalog` 22 of 22, `Test.Web.PublicTexts` 2 of 2, `Test.Demo.Step` 6 of 6, `Test.Data.Tables` 6 of 6, `Test.Contract.Ac` 6 of 6, `Test.Install.Registry` 11 of 11 and `Test.Install.Users` 4 of 4, each in its own call, none failed or skipped.
- **DW-9 after the fix (once).** `Test.Install.Users` 10 more times on slot A (run indexes 671 to 680): 10 passes, and `^OcuTalonTest("Users","n")` read 3 before the first and then 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 after each run. No run read an empty hash, and each used a new `ZzUsers<n>`. Both `lane-a` orders below ran on a fresh environment.
- **Hosted checks and build.** `bash ci/checks.sh` exit 0 (35 s on this machine; every pass), `bash ci/iris.sh build` exit 0.
- **The live test.** `bash ci/iris.sh live install-start` exit 0 with 94 PASS lines and no FAIL, twice (216 s on the first pass, 181 s on the last; the two mutation runs took 168 s and 188 s). The new checks pass: row 3's kept log, note and unchanged foreign state; the in-session off run; the on refusal with the mark left as it was; the partial-state sentinel; row 4's two keeps with `own-before 1|1|1` and `own 0|0|0`; the Troubled recovery clearing the mark; and the last restart (kept log, note, definition and OCUORDERS kept, access gone). Against the 151 s of Rule 21 this is 30 to 65 s more on this machine `(inference: it includes the machine's variation, and only QA's CI run measures the runner)`; 3 sessions are new and the others grew by lines.
- **The upgrade (once).** `bash ci/iris.sh live install-upgrade` exit 0, 34 PASS, 168 s.
- **Fresh-environment check (once).** `shard lane-a` 9 of 9 passed in 55 s and `--reverse` 9 of 9 in 54 s; `shard lane-b` 24 of 24 in 65 s and `--reverse` 24 of 24 in 64 s. No `FAIL` or `SKIP` line.
- **Teardown.** `bash ci/iris.sh teardown` after each live or shard call: 0 projects, containers, volumes, networks and images left for `-v12a-`.

**Mutations** (Rule 19; each was applied, run, observed red and reverted, and a digest of `git status --short`, `git diff --stat` and `git diff` was equal before and after):
- mutation: `Build` ignores `one` (`Fill` gets `entry.%Get(field)`) -> `Test.Msg.Catalog:TestCountOfOneForms` red for all 8 keys on all 4 channels (rows 1 to 7); reverted.
- mutation: `gap` put back on `result.allThrough` -> `TestEntries` red at "0 keys carry a gap"; reverted.
- mutation: `answered.alreadyRejected` says "approved" -> `TestEveryKeyOnEveryChannel` red on the four channels and the JSON render; reverted.
- mutation: `signIn.showPassword` is "Show the password" -> `Test.Web.PublicTexts:TestCopiesEqualTheCatalog` red at `Login.SHOWPASSWORD`; reverted.
- mutation: `Plan` returns "leave" with no `kept` for off, exists, not owned -> `Test.Demo.Step:TestPlan` red at "on 0, exists 1, owned 0 is keep"; reverted.
- mutation: `Orders(0)` returns its old errors (the not-stopped and the defined-other checks) -> `live install-start` red at both keep fixtures of row 4 (`wanted 'CHK|run|1|'`, `CHK|warn`, `CHK|note` and `CHK|own` missing) and dead at "row 4 the restart did not end ready within 200 s" (`STEP Demo FAILED`, `RESULT FAILED`); reverted.
- mutation: the keep mode skips the trace application's delete (`If 0 Set apps(traceApp) = ""`) -> `live install-start` red at `CHK|own|0|0|0` in the three keep checks (a separate run); reverted.
- mutation: `Registry.Run` writes no WARN line -> `Test.Install.Registry:TestRun` red at the three WARN assertions; reverted.
- mutation: `StatusMark.Record` ignores an empty value (`If 0 {`) -> `Test.Data.Tables:TestStatusMarkRecord` red at "an empty value deletes the row"; reverted.
- mutation: `Install.Step.Users:Ensure` creates the account with an empty password -> `Test.Install.Users:TestEnsureCreates` red: `Ensure creates the account` fails (ERROR #845, the instance refuses an empty password), so no account has a hash and "the account has a password hash" fails as well; reverted. The spec's wording, red at the hash assertion alone, needs an account that is created without a hash, which the instance does not allow.
- mutation: `OneProblems` skips the placeholder comparison of the form's text and web (`ElseIf 0 {`) -> `TestCountOfOneForms` red at "a text that holds the form's own slot", "a text that lacks a declared slot" and "a web with a placeholder of its own"; reverted.

### Review pass (October 20; same checkout, tag `v12a`, `OCUTALON_LOCK_OWNER='epic=0 stage=implement'`)

**Mutations of the review patches** (each applied, run, observed red and reverted; `git status --short`, `git diff --stat` and `git diff` were digested before and after, and equal):
- mutation: `Registry.Run` no longer takes the warnings before each step -> `Test.Install.Registry:TestRun` red at "a warning recorded before the run belongs to no step and is discarded"; reverted.
- mutation: `Test.Install.Users:ClearNodes` kills every node, the counter included -> `Test.Install.Users:TestClearKeepsTheCounter` red at "the counter keeps this run's number"; reverted. The mutated run also killed the counter on slot A, so the ten runs below start at 1.
- mutation: `Catalog:Template` compares the raw slot value (`values.%Get(slot) '= 1`) in place of `Count` -> `Test.Msg.Catalog:TestCountOfOneForms` red at the text 1 and at true for 7 of the 8 forms (`result.allThrough` is still refused, because its form holds the noun, which validates the count); reverted.
- mutation: the keep mode lists every web application of the namespace (`If 0 {` in place of `If keep '= "" {`) -> `live install-start` red at `CHK|inside` in both owned-namespace keep fixtures ("1 of 7 values differ"; "wanted 'CHK|inside|1|1', got 'CHK|inside|1|0'"); reverted.
- mutation: `Demo.Run` does not call `Warn(kept)` -> `live install-start` red at row 3's and row 4's `check_kept_log`, at the three in-session `CHK|warn` checks (5 FAIL lines); reverted.

**Results after the last patch:**
- **Slot A.** `iris_doc_load` with `ck` of the changed classes: no error or warning. After the patches `Test.Install.Users` 5 of 5, `Test.Install.Registry` 11 of 11 and `Test.Msg.Catalog` 22 of 22, each in its own call. The other four classes are unchanged by the patches and passed in the implement pass.
- **DW-9 after the fix (once).** `Test.Install.Users` 10 more times on slot A (run indexes 694 to 703): 10 passes; `^OcuTalonTest("Users","n")` was undefined before the first (the counter mutation had killed it) and read 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 after each run. No run read an empty hash, and each used a new `ZzUsers<n>`.
- **Hosted checks and build.** `bash ci/checks.sh` exit 0 ("checks: all scripts passed"), `bash ci/iris.sh build` exit 0.
- **The live test.** `bash ci/iris.sh live install-start` exit 0, 94 PASS and 0 FAIL, the two keep fixtures with 7 and 8 values.
- **The upgrade (once).** `bash ci/iris.sh live install-upgrade` exit 0, 34 PASS.
- **Fresh-environment check (once).** `shard lane-a` 9 of 9 and `--reverse` 9 of 9; `shard lane-b` 24 of 24 and `--reverse` 24 of 24; no `FAIL` or `SKIP` line. One call ran a teardown and then a shard in sequence (nothing was up to remove).
- **Teardown.** `bash ci/iris.sh teardown`: 0 projects, containers, volumes, networks and images left for `-v12a-`.

### QA stage (October 20; same checkout, tag `v12q`, `OCUTALON_LOCK_OWNER='epic=0 stage=qa'`)

Runtime: slot A (`server: ocutalon-slot-a`, `namespace: OCUTALON`, build 154, web port 52790 from the profile roster) took `iris_doc_load` with `ck`, `iris_execute_tests` (one class per call), read-only `iris_global_get` and `iris_sql_query`, and four `iris_execute_command` probes that create and delete `ZzQaProbe<n>` accounts in %SYS (about 4,700 in all; none is left, and no namespace, database, mapping, web application, role or resource was touched). Every IRIS run was `ci/iris.sh` in a throwaway of tag `v12q`, one at a time, each cleaned up (`teardown`: nothing left). No push, commit, `gh workflow run` or SSH.

**DW-9 is closed on its cause, not on evidence.** The cause was `(inference)` until now and was neither of the two guesses. A run of `Test.Install.Users` on slot A failed with the fix in place (run 713, `TestEnsureCreates`: "the account has a password hash"; every earlier assertion of that test passed, so the account existed with the right flags and roles, and the 2 s wait did not help).
- **Cause.** `Security.Users` keeps `Password` as a 64-byte binary hash and `Salt` as 64 more. The test's `Account` joined them to the flags with "|" and `TestEnsureCreates` read `$Piece(account, "|", 6)`. When the hash begins with "|" that piece is empty, though the hash is not.
- **Measured.** In 4,000 creates with the same `Security.Users.Create` call as `Ensure`, 0 hashes were empty and 16 began with "|" (0.4%, 1 in 250); two creates that did were read back with a hash of length 64 and an empty sixth piece. A wait, a fresh name and a counter cannot touch that: the bounded re-read and the never-reset counter stay, and the read is fixed. (The observed 2 failures in about 45 runs is more than 1 in 250 per run would give, about a 2% chance `(inference: chance, or the first byte of the hash is not uniform)`; the mechanism itself reproduced deterministically.)
- **Fix.** `Account` returns `...|roles|<length of the hash>|<hash and salt>` through a new `Line`, and `TestEnsureCreates` reads the length (field 6, decimal, never a "|").

**Gaps found and closed.**
- **DW-9, the counter had no pin of its own.** `TestClearKeepsTheCounter` calls `ClearNodes`, so putting the original `Kill ^OcuTalonTest("Users")` back into `Clean()` (the two hooks' call) left every test green: the counter is read before `Clean` runs and killed after the last test. Run alone under that mutation `TestClearKeepsTheCounter` passes. New `TestCleanKeepsTheCounter` creates the fixture account, calls the real `Clean()`, and expects the account gone and the counter equal to this run's number; it re-creates the fixture roles that `Clean` removes, so the other tests find them in either order.
- **DW-9, the delimiter.** New `TestAccountLineKeepsAPipeHash` builds a line from a hash that begins with "|" and from an empty hash and expects the length 64 and 0 and the whole hash and salt after it.
- **DW-41, a form belongs to its own slot only.** Every count-of-one case had the form's slot at 1 or at 0 and 2 with the other counts at their fixture values (49, 50, 20), so a `Template` that chose the form when any count slot is 1 stayed green for the five result keys. `TestCountOfOneForms` now renders each form with its slot at 2 and every other count slot at 1 and expects the entry's own text, without a `singular` marker that the OneForms block gives for each form ("has gone through", "The other one needs a new approval.", ...). A result of 1 of 50 orders with 49 left is the real case.
- **DW-42, the privileges of others.** Keep deleted "the trace role's SQL privileges", and the inside fingerprint holds no SQL privilege. With the filter that spares other grantees removed, `live install-start` stayed green. `test-install-start.sh` now seeds a role `ZzOcuGrantee` with SQL SELECT on `Ens.MessageHeader` in OCUORDERS before the first keep fixture, expects `CHK|grantee|1` after both keep fixtures, and removes the role and the grant again (`CHK|grantee-removed|1|1|0`). One more session and a few lines: the script took 191 s on this machine.
- **Texts, byte for byte.** An independent extraction (a script outside the repository that reads only `EXPERIENCE.md` L688 to L701 and the two catalog classes' XData) found the 10 rows of the owner's table, built the count-of-one and late-press texts and the 3 labels from the owner's quoted sentences, and compared them with the shipped `Catalog.Core` and `Catalog.Watch` entries (38 checks) and with `OneForms` and the six new `Fixtures` of `Test.Msg.Catalog` (14 checks): 52 checks, 0 differences (the renderer's collapse of a cause's own final period, which 0.9 pins, is applied to the incident texts). It also finds no `gap`, exactly the 8 `one` entries, 63 and 22 keys, and no `web` on the three late-press keys. The script is falsifiable (it went red on three of the mutations below) but is not committed: a hosted check would be a new unit in `ci/units.sh`, which this story leaves unchanged.
- **Already pinned, no change.** The form is never used for a missing, null, negative, fractional or text count (`TestEverySlotIsValidated` sweeps every declared slot of the 8 keys and the 6 new ones), the `Gaps` list is empty (`TestEntries`), the by-user late-press variants and the labels are fixtures on four channels, the sign-in labels are compared (`PublicTexts`: 11, 0 and 19), CR and LF in a warning (`TestStepDefaults`), the stale warning and the WARN after FAILED (`TestRun`), `StatusMark` (`TestStatusMarkRecord`), the two signature rows (`Test.Contract.Ac`).

**Tests added or extended (QA).** No new test file and no new class, so Rule 8's discoverability carries over from the implement stage: `Test.Install.Users` is in the `Install` area of shard `lane-a`, `Test.Msg.Catalog` in the `Msg` area of `lane-b`, and the live script is in the `install` group.
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` (QA, +2 tests, 7 in all): `TestCleanKeepsTheCounter` and `TestAccountLineKeepsAPipeHash`; `Account` returns its line through the new `Line`, and `TestEnsureCreates` asserts the length field.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` (QA): `TestCountOfOneForms` also renders each form with its slot at 2 and the other counts at 1, and the OneForms XData has a `singular` marker per form.
- `docker/tests/test-install-start.sh` (QA): the helper `foreign_grant` (seed, count, remove), two new expected lines in each of the two owned keep fixtures, and one new fixture session; 95 PASS lines (94 before).

**Mutations (QA).** Each was applied, observed red, reverted, and `git status --short`, `git diff --stat`, a SHA-256 of `git diff` and one of every changed file were equal to a snapshot taken just before. The mutated product classes were loaded into slot A only for the run and loaded again from the reverted file after it.
- mutation: AC fresh environment (Rule 19): `Clean()` of `Test.Install.Users` kills the whole test global (`Kill ^OcuTalonTest("Users")`) → `ci/iris.sh shard lane-a` on a fresh throwaway red, "1 of 9 classes" failed, `TestCleanKeepsTheCounter` (and, collaterally, `TestClearKeepsTheCounter`) FAIL; reverted.
- mutation: AC DW-9 (the counter): the same change, on slot A → `TestCleanKeepsTheCounter` red at "Clean keeps the counter, so no later run reuses this run's fixture name"; the older `TestClearKeepsTheCounter` run alone under it passed; reverted.
- mutation: AC DW-9 (the read): `Line` puts the hash in field 6 again (no length field) → `TestAccountLineKeepsAPipeHash` red at its three assertions, and `TestEnsureCreates` red at "the account has a password hash"; reverted.
- mutation: AC DW-41, the forms: `Catalog:Template` chooses the form when any count slot is 1 → `TestCountOfOneForms` red at "does not use the form when only another count is 1" for all 7 keys that have another count slot, and (for the two incident keys) at the older 0 and 2 assertions; reverted.
- mutation: AC DW-41, the owner's texts: `result.interrupted`'s form says "The other 1 needs a new approval." → `TestCountOfOneForms` red on the four channels, and the independent extraction red at "result.interrupted form ends with the owner's sentence"; reverted.
- mutation: AC DW-41, the gaps: a `gap` field on `result.allThrough` → `TestEntries` red at "0 keys carry a gap", and the independent extraction red at "no entry has gap"; reverted.
- mutation: AC DW-41, the late press: `answered.alreadyApprovedBy` says "approved by {user} on {channel}" → `TestEveryKeyOnEveryChannel` red on the four channels and the JSON render, `TestLocalInstallEveryKey` red, and the independent extraction red at "answered.alreadyApprovedBy text"; reverted.
- mutation: AC the sign-in page (Integration AC): `Login.USERLABEL` is "Username" → `Test.Web.PublicTexts:TestCopiesEqualTheCatalog` red at "Login.USERLABEL equals the catalog key signIn.userLabel"; reverted.
- mutation: AC the foreign namespace (Integration AC): the note's `routines` is filled from the namespace's `Globals` → `live install-start` red at "row 3: the start recorded the note of the kept OCUORDERS ... (matrix row 11)" (1 of 2 values), at the in-session foreign run and the on refusal's note, at both keep fixtures and at the last restart's note (6 FAIL lines); reverted.
- mutation: AC the other production (and the ready marker): the defined-other check of `Orders(0)` returns an error (`Quit $$$ERROR($$$GeneralError, kept)`) → `live install-start` red at the stopped-foreign fixture (3 of 9 values: `CHK|run|1|`, `CHK|warn` and `CHK|note`) and dead at "row 4 the restart did not end ready within 200 s"; reverted.
- mutation: DW-42, AD-24 (own access): the keep mode skips the trace application's delete (`If 0 Set apps(traceApp) = ""`) → `live install-start` red at `CHK|own|0|0|0` in both keep fixtures and at the last restart; reverted.
- mutation: DW-42, the privileges of others (the new pin): the keep mode deletes every grantee's SQL privileges (`If (keep '= "") && 0 Continue`) → `live install-start` red at `CHK|grantee|1` in both keep fixtures; reverted. The note, application and privilege mutations ran together in one `live install-start` (6 FAIL lines; each owned keep fixture shows 3 of 9 values differing, one each of `CHK|note`, `CHK|own` and `CHK|grantee`), because they fail disjoint checks; the defined-other check ran alone.
- mutation: DW-42, the warning: the registry's WARN line leaves out the step name (`Write !, "WARN ", line`) → `Test.Install.Registry:TestRun` red at "the WARN line is the next line after the step's line ..." and "the failing step's WARN line follows its FAILED line"; reverted.
- mutation: DW-42, the mark: `StatusMark.Record` stamps `RecordedAt` with `$ZDateTime($ZTimeStamp, 3, 1, 3)` → `Test.Data.Tables:TestStatusMarkRecord` red (ERROR #5802 on `RecordedAt`, then the shape and "one row holds the mark"); reverted.
- mutation: DW-42, the plan: `Plan` returns "keep" without `kept` → `Test.Demo.Step:TestPlan` red at "kept is the refusal's sentence for keep and empty otherwise"; reverted.
- mutation: the signature rows: `StatusMark.Get`'s parameter renamed `name` → `Test.Contract.Ac:TestCrossLaneSignatures` red at "OcuTalon.Data.StatusMark.Get takes (mark) in that order"; reverted.
- mutation: AC hosted checks: a literal U+00E9 in a string of `Test/Install/Users.cls` → `bash ci/checks.sh` exit 1, `boundaries` "FAIL ascii: only printable ASCII, spaces and tabs"; reverted.

`mutations_demonstrated=17` (16 distinct changes; the `Clean` change ran at two tiers).

**Results.**
- **Slot A, final tree, one class per call.** `Test.Msg.Catalog` 22 of 22, `Test.Web.PublicTexts` 2 of 2, `Test.Demo.Step` 6 of 6, `Test.Data.Tables` 6 of 6, `Test.Contract.Ac` 6 of 6, `Test.Install.Registry` 11 of 11, `Test.Install.Users` 7 of 7; no failed or skipped assertion.
- **DW-9 (QA).** `Test.Install.Users` 11 times in a row on slot A (run indexes 729 to 739): 11 passes, and `^OcuTalonTest("Users","n")` rose from 9 to 20, one per run, so each run used a new `ZzUsers<n>`. The read no longer depends on the hash's first byte. The earlier QA series (indexes 708 to 713) failed once, at run 713, before the fix of the read.
- **Hosted checks.** `bash ci/checks.sh` exit 0, all scripts, 33 s.
- **The live test.** `bash ci/iris.sh live install-start`: exit 0, 95 PASS and 0 FAIL, both owned keep fixtures with 9 values; 191 s on this machine (181 to 216 s before).
- **Fresh-environment check.** `shard lane-a` 9 of 9 in 54 s and `--reverse` 9 of 9 in 54 s; `shard lane-b` 24 of 24 in 65 s and `--reverse` 24 of 24 in 65 s; no `FAIL`. Both `lane-a` runs print `SKIP TestStepHelpers: OcuTalon.Production runs in this namespace, so NotRunning cannot say that it does not` (`Test.Install.Production`, Story 0.6's, unchanged here; the CI shard job printed it too), so "no `SKIP`" in the earlier results holds only when that production is not running.
- **Teardown.** `bash ci/iris.sh teardown` after each call: 0 projects, containers, volumes, networks and images left for `-v12q-`.

**CI evidence (the `ci` run of `294f81f`, run 39523373710, x64, two jobs at once; `lane-a` run 39523373715 passed).** `headSha` `294f81f80bb7439afe8b84552bc7db0933517127`, conclusion success.
- **Wall-clock** 28 min 7 s (00:46:51Z to 01:14:58Z), against 35 minutes (owner decision 7), 6 min 53 s to spare (29 min 39 s on the run before). Per job: `checks` 42 s and `web` 7 s (hosted); `iris (install)` 13 min 54 s, `iris (production)` 10 min 47 s, `iris (browser)` 9 min 39 s, `iris (image)` 7 min 4 s and `iris (shards)` 5 min 58 s, 47 min 22 s of runner time (about 50 before).
- **Per group and unit** (seconds): `install` 814 (`install-start` 461, against 470 before and 151 on ARM in Rule 21; `install-upgrade` 353), `production` 624 (245, 211 and 168), `browser` 532 (`demo-path` 165 with `FIRST-START engine=x86_64 build=1s ready=153s`, `sign-in` 179, `bundle-folder` 188), `image` 400 (233, 6 and 161), `shards` 338 (`lane-a` 159 with `READY` at 149 and 9 classes, `lane-b` 179 with `READY` at 148 and 24 classes).
- **The story's cost on the runner.** `install-start` took 461 s with the keep fixtures against 470 s in the run before, so the 8 sessions and the `LoadFromClass` that the plan priced at +35 to +45 s are lost in runner variance (`install` was 14 min 8 s and is 13 min 54 s); QA's own fixture (3 sessions) is not in this run and adds about 5 s on ARM.
- **Dispatch.** `image` and `production` started at once; `shards` (00:55:05Z, after `image`), `browser` (00:58:42Z, after `production`) and `install` (01:01:04Z, after `shards`) waited 8 min 14 s, 11 min 51 s and 14 min 13 s for a runner, so `install` ran last again and the chain `image`, `shards`, `install` set the wall-clock (27 min 59 s from the start of `image` to the end of `install`, with gaps of 62 s and 1 s between the jobs); the other runner stood idle for the last 6 min 37 s.
- **Rebalance.** None, because the run is under 35 minutes. Over the 120 dispatch orders on two runners, with this run's job durations and a 60 s gap, the five groups take 25 min 41 s at best, 28 min 3 s on average and 32 min 37 s at worst (31 min 37 s with 30 s, 30 min 41 s with 2 s); no order exceeds 35 minutes, and the worst case holds REL-4 by 2 min 23 s (1 min 53 s in the run before).

### Code review (October 20; same checkout, tag `v12r`, `OCUTALON_LOCK_OWNER='epic=0 stage=code-review'`)

Runtime: slot A (`server: ocutalon-slot-a`, `namespace: OCUTALON`; `iris_server_info` reports build 154U, the profile roster web port 52790, and no OCUORDERS) took `iris_doc_load` with `ck` of the three changed classes, `iris_execute_tests` one class or method per call, and read-only queries. Every IRIS run of the live script was `ci/iris.sh` in a throwaway of tag `v12r`, one at a time, each followed by `teardown` in its own call (nothing left). No push, commit, `gh workflow run` or SSH. The four review layers changed nothing (`git status --short` and the diff were identical before and after them, and no commit was unpushed).

**Results.**
- **Slot A.** `iris_doc_load` with `ck` of `Install.Step`, `Data.StatusMark` and `Test.Data.Tables`: compiled, no error or warning. `Test.Data.Tables` 6 of 6 (run index 741).
- **Slot A hygiene (read-only).** 0 `ZzQaProbe*` accounts, 0 `ZzUsers*` accounts, 0 roles starting `Zz`, and no `OcuTalon_Data.StatusMark` row.
- **The live test.** `bash ci/iris.sh build`, then `bash ci/iris.sh live install-start`: exit 0, 94 PASS and 0 FAIL in 198 s on this machine (QA's 95 less the grantee-removal session, which is folded into the two keep fixtures; 181 to 216 s before). The running keep fixture has 10 values and the stopped one 11; `own_access` reads `1|1|1|1` before the keeps and `0|0|0|0` after them.
- **Hosted checks.** `bash ci/checks.sh` exit 0, "checks: all scripts passed", 37 s.
- **REL-4.** The patches add a few lines to five sessions of `live install-start` and remove one session; no stack, restart, unit, group or class is added, so QA's simulated worst case of 32 min 37 s stands `(inference: the next CI run measures it)`.

**Mutations (code review).** Each was applied, observed red and reverted; `git status --short`, `git diff --stat` and `git diff` had the same SHA-256 before and after (`470c6b09...`). The mutated `StatusMark` was loaded into slot A only for its run and loaded again from the reverted file after it, and that method passed again (run index 743). The four `Demo` mutations ran together in one `live install-start`, because they fail disjoint checks (6 FAIL lines, 88 PASS); `Demo.cls` was restored from a copy and equals HEAD.
- mutation: `StatusMark.Record` stamps `RecordedAt` only on a create (`If row.%Id() = ""`) -> `Test.Data.Tables:TestStatusMarkRecord` red at "RecordedAt is the time of the last call, a replace included: 2000-01-01T00:00:00Z" (run index 742); reverted.
- mutation: an error of `Demo.Run` clears the mark (`If $$$ISERR(sc) Do ...Record(..#KEPTMARK, "") Quit sc`) -> `live install-start` red at row 3's on refusal (`CHK|mark-left|stale`, now seeded in the session) and at the partial-state session; reverted.
- mutation: a create or a remove no longer clears the mark (`Quit $$$OK` in place of `Record(..#KEPTMARK, "")`) -> `live install-start` red at the off run while the Orders production runs and at the Troubled recovery (`CHK|note|<absent>`, both now seeded with `stale`); reverted.
- mutation: the keep mode deletes every grantee's SQL privileges (`If (keep '= "") && 0 Continue`) -> `live install-start` red at `CHK|grantee|1` in both keep fixtures, the stopped one now on its own seed; reverted.
- mutation: the keep mode deletes the public global mapping of OCUORDERS -> `live install-start` red at `CHK|inside|1|1` in the running keep fixture (the new mapping fingerprint); reverted.

### Rework, DW-44 (October 21; same checkout, tag `v12b`, `OCUTALON_LOCK_OWNER='epic=0 stage=implement'`)

Runtime: slot A (`server: ocutalon-slot-a`, `namespace: OCUTALON`; `iris_server_info` reports build 154U) took `iris_doc_load` with `ck` of `OcuTalon.Install.Step.Demo` and one `iris_execute_tests` call. The live script ran only through `ci/iris.sh` in throwaways of tag `v12b`, one at a time, each followed by `teardown` in its own call. No push, commit or `gh` call; `Demo.Run()` never ran on the slot, and the mutated classes were never loaded into it.

**Results.**
- **Slot A.** `iris_doc_load` with `ck` of `Install.Step.Demo`: compiled, no error or warning. `Test.Demo.Step` 6 of 6 (run index 744).
- **Hosted checks and build.** `bash ci/checks.sh` exit 0, "checks: all scripts passed" (run again after the spec edits, same result). `bash ci/iris.sh build`: the web bundle is built.
- **The live test.** `bash ci/iris.sh live install-start` exit 0, 94 PASS and 0 FAIL. The five note checks pass with the `how` sentence: row 3's start, the in-session foreign off run, the running and the stopped keep fixtures, and the last restart. The after-start `WARN Demo` line (`check_kept_log`, rows 3 and 4) still holds Story 0.10's sentence.
- **Teardown.** `bash ci/iris.sh teardown`: 0 projects, containers, volumes, networks and images left for `-v12b-`.

**Mutations (rework).** Each was applied, run, observed red and reverted. Before each, a SHA-256 of `git status --short`, `git diff --stat` and `git diff` and one of `Demo.cls` and `test-install-start.sh` were taken; after the revert both were equal, and `git status --short` and `git diff --stat` were unchanged.
- mutation: the `how` sentence ends "in the Management Console." (`Demo.cls`, `System`) -> `live install-start` red at all five note checks (5 FAIL, 89 PASS: row 3's start, the in-session foreign off run, the running keep fixture, the stopped keep fixture and the last restart, each "1 of n values differ"); reverted.
- mutation: the fill of `{what was kept}` changes in three places (`Plan`'s `what` is empty, `Orders(0)`'s not-stopped phrase loses ", which is not stopped", its defined phrase loses "the") -> `live install-start` red at the same five checks (5 FAIL, 89 PASS): the foreign ones (row 3's start and the in-session run), the running fixture, and the stopped fixture with the last restart, each fixture failing on its own change; reverted.
- mutation: the note is built without its `how` key (`, "how": (how)` removed from the JSON in `System`) -> `live install-start` red at the five note checks, alone at row 3's start (`1 of 2 values differ`) and the last restart (`1 of 3`); reverted. (Review pass, tag `v12d`; this and the next mutation ran in one run, 87 PASS and 7 FAIL.)
- mutation: the after-start warning carries the fill in place of the kept sentence (`Do ..Warn(what)` in `Run`) -> `live install-start` red at `check_kept_log` of row 3 (`WARN Demo databases that OcuTalon did not create`) and of row 4 (`WARN Demo the production ZzOcuForeign.Production`) and at the `CHK|warn` values of the in-session fixtures; reverted. (Review pass, same run.) Before and after, a SHA-256 of `git status --short`, `git diff --stat` and `git diff` was equal, and so were those of `Demo.cls` and `test-install-start.sh`; `ci/iris.sh teardown` for `-v12d-` left nothing.

### Code review re-review (October 21; same checkout, tag `v12e`, `OCUTALON_LOCK_OWNER='epic=0 stage=code-review'`)

Runtime:
- **Slot A.** `server: ocutalon-slot-a`, `namespace: OCUTALON`. `iris_server_info` reports build 154U, with OCUTALON present and no OCUORDERS. It took one `iris_doc_load` with `ck` and one `iris_execute_tests` call.
- **The live script.** It ran only through `ci/iris.sh`, in one throwaway of tag `v12e`, followed by `teardown` in its own call.
- **Nothing else.** No push, commit or `gh` call. `Demo.Run()` never ran on the slot.
- **The review layers.** All four changed nothing: the tree was clean after them, and the one unpushed commit, `b2dbcd8`, predates the review.

**Results after the patches** (the `Run` comment, and the two mutation-line prefixes above):
- **Slot A.** `iris_doc_load` with `ck` of `Install.Step.Demo` compiled with no error or warning. `Test.Demo.Step` passed 6 of 6 (run index 746).
- **Hosted checks.** `bash ci/checks.sh` exit 0, "checks: all scripts passed", in 37 s.
- **Build and the live test.** `bash ci/iris.sh build` exit 0. `bash ci/iris.sh live install-start` exit 0, with 94 PASS and 0 FAIL in 199 s on this machine. All five note checks pass with the `how` sentence, and so do both `check_kept_log` lines ("the line after STEP Demo OK is WARN Demo with the kept sentence") at rows 3 and 4.
- **Teardown.** `bash ci/iris.sh teardown` left 0 projects, containers, volumes, networks and images for `-v12e-`.
- **Mutations.** None was re-run. The patches change a comment and two line prefixes, and the rework's four mutation lines (alter, fill, drop, `Warn(what)`) still cover every clause of the task. They were checked against the comparator: `compare_chk` matches whole lines with `grep -qxF`, and `kept_note` prints `how` as its seventh field.

## Auto Run Result

Status: done
Blocking condition: none

**Summary of the implemented change.**
- **DW-41, the catalog.** `Render` uses an entry's count-of-one form (`one`) when its count slot is 1 and validates that slot either way. The 8 Watch entries carry the owner's forms, 3 `answered.*` and 3 `signIn.*` keys are in Core (63 and 22 keys), and every `gap` is gone. `Test.Web.PublicTexts` compares the three sign-in labels (11 compared, 0 not in the UX, 19 not texts).
- **DW-42, keep.** With demo mode off, a foreign OCUORDERS, or OcuTalon's own with another production defined or not stopped, is kept. The step removes only OcuTalon's own access (the trace application, the trace role's OCUORDERS grants and SQL privileges), warns through the new `Install.Step.Warn` (the registry writes `WARN <step> <text>` after the step's line), records the status mark `demoKept` through the new `StatusMark.Record` and `Get`, and returns OK, so the start ends ready. The on path's refusal is unchanged.
- **DW-9.** `Test.Install.Users` keeps its counter, so each run has a new `ZzUsers<n>`, and re-reads a just-created account for up to about 2 s until the hash is there.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls`: `Template` chooses the form; the grammar comment names `one`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`, `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: the owner's forms and the 6 new Core keys; the gaps are removed.
- `src/ocutalon/cls/OcuTalon/Install/Step.cls`, `src/ocutalon/cls/OcuTalon/Install/Registry.cls`: `Warn`, `TakeWarnings` and the `WARN` line.
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls`: `Record` and `Get`, methods only.
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls`: the keep mode, `KEPTMARK`, and `Plan` and `Orders` returning `kept`.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`, `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`, `src/ocutalon/cls/OcuTalon/Test/Demo/Step.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`, `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`, `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls`: the rows 1 to 18 tests, the two new signature rows and the review pass's pins.
- `docker/tests/test-install-start.sh`: the keep fixtures of rows 11 to 15, staged across the existing restarts, and the `inside_state` fingerprint.
- This spec: tasks, Task 0 results, rulings, the triage log, mutation lines and results.

**Review findings breakdown.** 33 findings from the four layers: high 0, medium 9, low 18, false 6.
- **Patched (6 medium entries, 3 low rows).**
  - The post-create reads of `Test.Install.Users` now wait.
  - A new `TestClearKeepsTheCounter` and `ClearNodes` pin the counter.
  - Every form's slot is refused as the text 1 and as true.
  - The stale-warning pin in `TestRun`, and `TestStepDefaults` takes the warnings first.
  - `inside_state` pins that keep leaves the inside of OCUORDERS alone.
  - The foreign-note session clears the mark first.
  - Mutation lines for the patches are in `## Verification`.
- **Deferred:** none (`deferred:` is empty).
- **Rejected, each with its reason in the triage log:**
  - by design or spec-bound: `Demo.Run` and untaken warnings, the running-Orders-with-defined-foreign case, the spec-dictated literal-count assertions, the row 3 restage, the no-WARN-at-start check, the unreachable defensive refusals of `Template`, and the descriptive audit items (no consumers yet, the log-only warning, the owner-only how-to sentence);
  - unlikely, with a fix that adds a branch: a `Record` failure after `Warn`, a `Record` race or the 1000-character limit, and the first-miss quit of the wait.

**Follow-up review recommendation:** `true`. Six medium entries were patched on this first pass. The unverified risk is that the new live checks (`CHK|inside`, the cleared-mark session) and the wider keep fixtures have run only on the ARM developer machine; their cost on the x64 runner and REL-4's 35 minutes are measured by QA's CI run.

**Verification performed.**
- Slot A, `ocutalon-slot-a` build 154: load with `ck`; `Test.Msg.Catalog` 22, `Test.Web.PublicTexts` 2, `Test.Demo.Step` 6, `Test.Data.Tables` 6, `Test.Contract.Ac` 6, `Test.Install.Registry` 11 and `Test.Install.Users` 5, all passed, one class per call.
- DW-9: 10 runs before the fix (indexes 637 to 646) and 10 after it (694 to 703) all passed.
- `bash ci/checks.sh` and `bash ci/iris.sh build`: exit 0.
- `live install-start` 94 PASS, `live install-upgrade` 34 PASS.
- Shards `lane-a` 9 of 9 and `lane-b` 24 of 24, each forward and `--reverse`.
- 16 mutations applied, red, reverted, with a digest of the tree unchanged.
- Every throwaway of tag `v12a` was torn down.

**Residual risks.**
- **REL-4.** `live install-start` took 181 to 216 s on ARM against Rule 21's 151 s `(inference: includes machine variation)`; at the ratio of 3 on the runner the worst-case run could pass 35 minutes. The `install` group is the first to rebalance if QA's run is over.
- **DW-9's cause is still `(inference)`.** The flake did not reproduce in 10 runs before the fix, and 10 clean runs after it are weak evidence (about a 21% chance without a fix at 1 in 7). The fix removes the two candidate causes; the wait cannot be forced to fail. `Clean()` still deletes every `ZzUsers*` fixture, so two runs at once on one instance would remove each other's accounts.
- **Owner-only (Rule 22.4).** The how-to-remove sentence was given on October 21 and the note holds it (the `### Rework, DW-44` block under Verification); 10.2 and 14.2 carry it in the README and the security overview.
- **For the lead.** The spine updates listed under Design Notes ("Spine updates for the lead": AD-32, AD-3, AD-23, AD-18 and the cross-lane table), the three VETO WINDOW FYIs, and the epic-context pre-warm.

**Rework pass, DW-44 (October 21; this pass only).**

*Summary of the implemented change.* The `demoKept` note gains a `how` field holding the owner's sentence, "OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal." `{what was kept}` is "databases that OcuTalon did not create", "the production <name>" or "the production <name>, which is not stopped", the fact that the kept sentence names, returned by `Plan` and `Orders(0)` in a new `Output what`. The after-start `WARN Demo` line keeps Story 0.10's sentence.

*Files changed.*
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls`: `what` from `Plan` and `Orders(0)`, passed by `Run` to `System`, which builds `how` and writes it into the note.
- `docker/tests/test-install-start.sh`: `kept_note` prints `how`; the five note checks expect the sentence in full (`foreign_how`, `running_how`, `defined_how`).
- This spec: the task ticked, rulings, the Verification block with four mutation lines, the triage entry, one deferred item, and corrections of the stale note-shape claims in Design Notes.

*Review findings breakdown.* 21 findings from the four layers: high 0, medium 0, low 20, false 1.
- **Patched (2 low entries):** the mutation line for "the `WARN Demo` line keeps 0.10's sentence", and the line for a note built without `how`; both were run, observed red and reverted (they need no code change).
- **Deferred (1):** Stories 10.2 and 14.2 have no acceptance criterion for the sentence the README and the security overview carry (`deferred:` in the frontmatter).
- **Rejected (18), each with its reason in the triage log:**
  - spec-bound or by design: the owner's sentence for a foreign OCUORDERS (4 sightings), no new status surface, the staged live script (REL-4);
  - the fix would edit the spec: stale descriptions of the note's shape, the baseline, the Auto Run Result (5);
  - unreachable or covered by a live pin: `System` with an empty `what` (2), no unit assertion on `what` (3), the `what` phrases repeating the kept sentences;
  - false: the `Value` limit (the longest note is 891 of 1000 characters).

*Follow-up review recommendation:* `false`. Two low entries were patched on this first pass, no high and no medium.

*Verification performed.*
- Slot A, `ocutalon-slot-a` build 154: `iris_doc_load` of `Install.Step.Demo` with `ck`, no error or warning; `Test.Demo.Step` 6 of 6.
- `bash ci/checks.sh` exit 0.
- `bash ci/iris.sh live install-start` (tag `v12c`) exit 0, 94 PASS and 0 FAIL, with the five note checks and the `WARN Demo` checks among them; the implement stage's run (tag `v12b`) gave the same.
- Four mutations (two in the implement stage, two in the review pass, tag `v12d`): each red at the checks named in `## Verification`, reverted byte-identical.
- Throwaways of tags `v12b`, `v12c` and `v12d` were torn down. Not run in this pass: `live install-upgrade`, the shards and the DW-9 series, which this change does not touch.

*Residual risks.*
- **The foreign case.** The owner's sentence names OCUORDERS_CODE and OCUORDERS_DATA also when the kept OCUORDERS is a foreign one on other databases (they are in the note's `globals` and `routines`). The lead may ask the owner through the Contest Planner whether that case needs its own sentence; the change would be one line of `System` and `foreign_how`.
- **REL-4.** The five note checks add one field to existing lines, so the live script's runtime does not change `(inference)`; the next CI run measures it.
- The `[Review][Decision]` entry about the missing how-to sentence under `### Review Findings` stays unchecked for the lead to close.
