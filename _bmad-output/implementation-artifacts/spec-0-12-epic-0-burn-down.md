---
title: 'Story 0.12: Epic 0 burn-down'
type: 'feature'
created: '2026-10-20'
status: 'done'
baseline_revision: '56ea3de33c333569fc041ee85b9a20cb614dd4c7'
baseline_commit: 56ea3de33c333569fc041ee85b9a20cb614dd4c7
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
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
    - it returns the note JSON `{"text","namespace","globals","routines"}`, filled from `Config.Namespaces`;
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
  - Until the owner fixes it, the note holds 0.10's fixed sentence, which names what was kept, and the facts the removal needs: the namespace, and its globals and routines databases.
  - 10.2 and 14.2 carry the owner's wording once it is given. Adding it later is one more field of the note.

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
- **Owner-only (Rule 22.4), for the Contest Planner.** The sentence that tells an administrator how to remove a kept OCUORDERS by hand; the note holds 0.10's fixed sentence and the facts that the removal needs until the owner gives it (10.2 and 14.2 carry it).
- **For the lead.** The spine updates listed under Design Notes ("Spine updates for the lead": AD-32, AD-3, AD-23, AD-18 and the cross-lane table), the three VETO WINDOW FYIs, and the epic-context pre-warm.
