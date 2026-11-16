---
title: 'DW-1378: The result band of a setting rollback or undo names the value that the chat result line names'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
baseline_revision: 'd355ebdd7f5e435f116c5aa5f19957f70649df54'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-3-name-the-setting-change-behind-an-incident-and-offer-its-rol.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-dw-1373-a-suspend-or-resume-that-could-not-be-applied-is-not-reported-as-nothing-changed.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-dw-1376-a-saved-but-not-applied-run-has-an-ended-line-in-the-summary.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1378, MED, fix-risk med; filed by the 23.3 rework review):** after a done `undo_rollback`, the web result band can name a different value from the chat's result line for the same run.
- The band reads the value from the incident's recorded `settingChange`. `settingResultView` (`web/src/app/approvals/approval-view.ts:702`) takes `change?.newValue` for an undo and `change?.oldValue` for a rollback.
- The chat's result line reads the value from the approved request's dry run. `Watch.IncidentManager.ResultExtra` (`Watch/IncidentManager.cls:1770-1790`) puts the dry run's `after` into the extra. `Watch.SettingCause.ResultSlots` (`Watch/SettingCause.cls:336-355`) then shows it through `Shown` (`Bridge.Redact`).
- The two values differ in the DW-1366 case. A System Default Setting moved from 7 to 9 while the rollback's item-level value hid it. The undo's dry run After is then the current default, 9, from `UndoRollback.Undoable` (`Fix/Kind/UndoRollback.cls:72`). The run re-checks that value and fails if it moved (`Plan`, L132). So the item and the chat say "is back to 9", while the card says "is back to 7".
- `IncidentRequest`, the request part of the `incident` payload and of `/api/v1/state` (`Live/Payload/Part/IncidentRequest.cls`), carries no dry-run value, so the page cannot read the chat's value.

**Ruling (Contest Planner, 2026-11-15, `prompts/story-234-rulings-20261115.md`, "23.3 follow-ups"; ledger DW-1378 `routed` 2026-11-15T14:11:08Z):**
- "DW-1378: ACCEPTED as a follow-up, with the new /api/v1/state field."
- "CONDITION: the web band must not contradict the chat's result line."
- "If the band can't show the actual value, it shows the catalog result text instead."
- The Planner's lane C order puts DW-1378 after DW-1376.

**Approach:**
- **New field.** The request part gains one field, `After` (JSON `after`, string). It is filled for the two setting kinds only, from the request's stored dry run. It goes through the same function that gives the chat's `{after}`: a new `Watch.SettingCause.ShownAfter`, which is `Shown` (trim, then `Bridge.Redact.Text`) of the dry run's `after`.
- **Same builder.** `Live.Payload.Incident.FromRow` builds both the live `incident` event and `/api/v1/state`, so the one change covers both.
- **Web.** The generated `payloads.ts` gains `after?: string` on `IncidentRequest`. `settingResultView` names `request.after` for both setting kinds, and never the `settingChange` values. A done run whose request has no `after` gets no band, as a result that lacks the value its text names gets none today.
- **The rest.** The setting, the item and the band's catalog keys are unchanged. So the band text is the chat line's text: same key, same `{setting}` and `{target}`, same `{after}`.

## Boundaries & Constraints

**Always:**
- **Footprint.** Lane C makes the edits under the run's DW-1378 assignment.
  - Lane A (`Live/`, `Watch/`):
    - `src/ocutalon/cls/OcuTalon/Live/Payload/Part/IncidentRequest.cls`: the property and the class doc.
    - `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls`: `Chosen` and its doc.
    - `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls`: `ShownAfter` and the class doc.
  - Web:
    - `web/src/app/live/payloads.ts`: generated, never edited by hand.
    - `web/src/app/approvals/approval-view.ts`: `settingResultView` and two doc comments.
  - Tests:
    - `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`;
    - `src/ocutalon/cls/OcuTalon/Test/Watch/SettingCause.cls`;
    - `src/ocutalon/cls/OcuTalon/Test/Watch/Rollback.cls`;
    - `web/scripts/approval-view.test.mjs` and `web/scripts/incident-view.test.mjs`;
    - `web/e2e/cards/approval-card.spec.ts` and `web/e2e/rail/step5-cards.spec.ts`.
  - The architecture spine: one `[ADDED]` sub-bullet under AD-12 (Veto item 4).
  - This spec.
- **One redactor, on the server** (24.4a redactor ruling, 2026-11-15). The field's value comes from `Watch.SettingCause.Shown`, the function that fills the chat's `{after}`. No second redactor, and no redaction or trim in `web/`.
- **Stored data stays raw.** The stored `ApprovalRequest.DryRun` and the value a run writes stay raw. Nothing writes to any row.
- **AD-13.** `Chosen` runs in `/state` as a user with no SQL grant, so `ShownAfter` reads only its argument: no SQL, no row and no namespace switch.
- **One source for the value.** The band takes `{after}` only from `request.after`. It takes `{setting}` and `{target}` from `settingChange.setting` and `settingChange.item`, as today.
- **Generated file.** `payloads.ts` is regenerated with `npm --prefix web run payloads`, and `node web/scripts/payloads.mjs --check` exits 0.
- **Code style.** ObjectScript stays ASCII. Comments state the contract, not review history.

**Never:**
- Add, change or reword a catalog entry, slot, web form, `EXPERIENCE.md` line or `docs/` page.
- Change `Watch.IncidentManager` (`ResultExtra`, `ResultNotice`), `Watch.Notice`, `Fix.Kind.*`, `Fix.Executor`, any `Data.*` or `Bridge.*` class, `Live.Payload.Approval`, `Part.SettingChange` or `Part.DryRun`.
- Give `after` to a request of any other kind. A suspend's dry run also has an `after` ("disabled"), and it must not reach the part.
- Fall back to `settingChange.oldValue` or `settingChange.newValue` when `request.after` is missing.
- Change the band of any other kind (DW-1373's `itemResultView`, the partner bands, the resend bands), or the not-applied, changed-since and not-changed setting bands.
- Delete, skip or weaken a test. Fixtures of done setting requests gain `after`, the value the server now sends. No assertion is removed.

## I/O & Edge-Case Matrix

These are the request parts of an incident payload whose `settingChange` names the change (item `OrdersFromPartner`, setting `PoolSize`, oldValue `1`, newValue `7`, unless the row says otherwise). The "chat line" is the result notice that `IncidentManager.ResultNotice` sends for the same run, rendered by `Msg.Catalog`. "Band" is the band's text on the request card and on the closed card, and in the chat's announcement (`bandTexts`).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Done rollback | `rollback_setting`, done, Completed 1. Dry run after `1` (RollbackSetting `Restored` = the change's old value). Part `after` `1` | Band `result.settingRestored`: "PoolSize on OrdersFromPartner is back to 1. To undo it, ask me to undo the rollback.", which equals the chat line. The text is the same as before DW-1378, except that a value with spaces at either end is now trimmed, as the chat trims it. | none |
| 2 Done undo, after = recorded new value | `undo_rollback`, done, Completed 1. The change's Source is production, so the dry run after is `7` = newValue. Part `after` `7` | Band `result.rollbackUndone`: "The rollback is undone: PoolSize on OrdersFromPartner is back to 7.", which equals the chat line. Unchanged. | none |
| 3 Done undo, DW-1366 | The change came from a System Default Setting that moved to 9 while the item's own value hid it. Undo dry run after `9`, run done (Plan's re-check passed). newValue still `7`. Part `after` `9` | Band: "The rollback is undone: PoolSize on OrdersFromPartner is back to 9.", which equals the chat line. Never "back to 7". | none |
| 4 Value with a token | The dry run after is a URL with `token=...`, raw in the stored dry run | Part `after` is the URL with `[redacted]` in place, the value of the chat's `{after}`. The band shows it as given. The payload JSON, `/state` and the page hold no token. The stored dry run stays raw. | none |
| 5 No dry-run after | The dry run can't be read, or it has no `after` or an empty one | The part has no `after` key. A done run has no band, as the chat has no result line: `ResultSlots` refuses an empty `{after}`, and `ResultNotice` logs `LOGRESULT` and sends nothing. The band never shows `settingChange` values. | none |
| 6 Not applied | Completed 0, Unreached 1, reason the production's error | Unchanged: `result.settingSavedNotApplied` (setting, target, reason). `after` is not read. | none |
| 7 Not changed | Skipped 1 with a reason that ends as CHANGEDAGAIN: `result.settingChangedSince`. Any other reason: `result.itemNotChanged` | Unchanged, with or without `after`. | none |
| 8 Running or interrupted | state `executing`, or Interrupted above 0 | Unchanged: no band. | none |
| 9 No settingChange | The incident names no change: no `SettingChangeRef`, or the row is gone | Unchanged: no setting band, because `{setting}` and `{target}` are missing. The chat line, if sent, is not contradicted. | none |
| 10 Pending or answered setting request | Any state before a run ends | The part carries `after` (the dry run's, redacted). The approval payload already shows the same value as the dry run's After. No band, because there is no result. | none |
| 11 Other kinds | `suspend_item` or `resume_item` (DW-1373), `reroute`, `repair_resend`, `partner_warning`, `email` | No `after` on the part, even when the dry run has one. Their bands are unchanged. | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `cb69bbeb1` (DW-1376's head `5f9b7e3c7`, which holds DW-1373, plus the plan log).

**Web:**
- `web/src/app/approvals/approval-view.ts`:
  - `resultView` doc L552-578. Its setting clause is L571-574.
  - The dispatch to `settingResultView` L587-589.
  - `itemResultView` L654-692 (DW-1373, unchanged).
  - `settingResultView` doc L695, function L696-717. The value is L702 (`textOf(request.fixKind === 'undo_rollback' ? change?.newValue : change?.oldValue)`).
  - `textOf` L207 (trims; '' for a non-string).
- `web/src/app/live/payloads.ts`: `IncidentRequest` L96-103 (generated).
- `web/scripts/payloads.mjs`: the generator. Fields follow the class file's property order. `--check` runs in `package.json`'s `build` and in `payloads.test.mjs` ("the real tree's check").
- The two callers. Both pass the incident payload's request part, so both get the field with no change of their own:
  - `web/src/app/approvals/approval-request-card.ts` L531-535 (`band`, input `result`);
  - `web/src/app/incidents/incident-view.ts` `bandsOf` L515-524 (the closed card's compact bands, and `bandTexts`, the chat's announcement).

**Server:**
- `Live/Payload/Part/IncidentRequest.cls`: class doc L1, `Item` L14-15, `Count` L17-18, `Result` L20-21.
- `Live/Payload/Incident.cls`:
  - `FromRow` doc L75-87.
  - `Change` L135-154 (the settingChange part, redacted with `Bridge.Redact.Text`, untrimmed).
  - `Details` L184-207.
  - `Chosen` doc L210-211 and method L212-225. Its setting branch is L216-219.
- `Watch/SettingCause.cls`:
  - Class doc L13-16, the list of the notice and summary helpers.
  - `ResultKey` L319.
  - `ResultSlots` L336-355 (the chat's `{after}` = `Shown(extra.after)`, L352).
  - `Text` L387 and `Shown` L394, both Private.
- `Watch/IncidentManager.cls` (read only): `ResultNotice` L1757-1766 and `ResultExtra` L1770-1790. The setting branch of `ResultExtra` (L1775-1781) gives setting `change.Setting`, target `change.Item` and after the dry run's raw `after`.
- `Fix/Kind/UndoRollback.cls` (read only):
  - `DryRun` L40-55;
  - `Undoable` L61-75 (after: `Restored` for Source production, else the current default);
  - `Plan` L123-143 (the run-time re-check, L132).
- `Fix/Kind/RollbackSetting.cls` (read only): `Restored` L101-104 (the change's old value).
- `Live/Payload/Approval.cls` (read only): the dry run part's `After` = `Bridge.Redact.Text(dry.after)`, L151.

**Tests:**
- `Test/Live/Payloads.cls`:
  - Class doc L1-8.
  - `TestContracts` L77-96: the count stays 40 classes.
  - `TestFromRowRequestKinds` L343-370.
  - `TestIncidentFromRowReadsNoSql` L439-466.
  - XData `Contracts`, `Part.IncidentRequest` L1644-1654.
- `Test/Watch/SettingCause.cls`:
  - Class doc L1-26.
  - `Drop` L53-62 (it deletes the `ApprovalRequest` and `FixRun` rows of `#INCIDENT`).
  - `Change` L77, `Incident` L97, `TestPayload` L378, `TokenUrl` L399, `Token` L405 and `TestShownRedacted` L413.
- `Test/Watch/Rollback.cls`:
  - Class doc L1-28.
  - `Run` L436-475.
  - `RollBackDefault` L747-768: the fixture incident has no `SettingChangeRef`.
  - `TestUndoSystemDefaultChanged` L771-790.
  - `TestTokenValueRestoredRaw` L1012-1089 (the incident payload L1037-1041, the result notice L1052-1060).
- `Test/Watch/Case.cls`: `NoticeBodies` L1594 and `WaitResultNotices` L2130.
- `Test/Data/Fixture.cls`: `Approval` L137 and `FixRun` L155.
- `web/scripts/approval-view.test.mjs`: the setting describe L109-191 (`CHANGE` L113, `band` L116; the success bands L135-150).
- `web/scripts/incident-view.test.mjs`:
  - the closed rollback band L196-198;
  - the closed-card describe L817-909 (`asked` L820-824 with done `RB1` and `UN1`).
- `web/e2e/cards/approval-card.spec.ts`:
  - imports L9-25 (no `seedFixRun` yet);
  - `refOf` L65, `incidentCard` L95, `open` L106;
  - A14 L462-510, the real-HTTP pin of a setting rollback.
- `web/e2e/rail/step5-cards.spec.ts`:
  - `ROLLBACK` and `UNDO` dry runs L87-88 (after `OLD` and `NEW`);
  - `Entry` L294-301;
  - the done setting entries L346, L528, L550, L562, L563 and L718.

**Contract pins checked:**
- AD-12's incident payload bullets (spine L453-455) list the request part's fields, so this change gets an `[ADDED]` sub-bullet (Veto item 4).
- The `/api/v1/state` REST row (spine L1787) lists no incident payload field, so it is unchanged.
- There is no OpenAPI or JSON schema file in the repo. The contracts are `Test.Live.Payloads` XData `Contracts` and the generated `payloads.ts`.
- `Test.Web.*Api` pin no `requests` field.

## Tasks & Acceptance

**Task 0 (measure first, before any product edit; record each result under `## Verification`; lane C only, never a dev slot, Rule 21):**
1. **Baseline, no stack.**
   - Record `git rev-parse HEAD`.
   - Check that `node web/scripts/payloads.mjs --check` exits 0.
   - Check that `node --test web/scripts/approval-view.test.mjs web/scripts/incident-view.test.mjs web/scripts/payloads.test.mjs` passes.
   - Check that `node --test web/scripts/initial-bundle.test.mjs` passes, and record the initial total if the run prints it.
2. **Baseline classes.** On a lane C warm throwaway, run `OcuTalon.Test.Watch.SettingCause` and `OcuTalon.Test.Live.Payloads`, one call each. Record that each passes.
3. **The defect, through the real DW-1366 run.**
   - Use a scratch subclass of `Test.Watch.Rollback` in your scratchpad (e.g. `ZzScratch.Dw1378`, with the same `DependsOn`). Load it into the throwaway only and never commit it.
   - Give it one Test method that runs `TestUndoSystemDefaultChanged`'s body, then records:
     - (a) `..WaitResultNotices(incident, 2)`: the undo's notice `catalogKey` and `slots.after` (expect `result.rollbackUndone`, `9`);
     - (b) the fixture incident's `SettingChangeRef` (expect "");
     - (c) with `SettingChangeRef` set to the change and saved, `Live.Payload.Incident.FromRow(row)`: `SettingChange.NewValue` (expect `7`) and the undo part's JSON (expect no `after` key);
     - (d) `Msg.Catalog.Render("result.rollbackUndone", <slots>, "web", .sc)` twice. First with the notice's slots: the chat line, expected "... is back to 9.". Then with `{setting, target}` of the payload's `SettingChange` and `after` = `NewValue`: today's band, expected "... is back to 7.".
   - Run it on a fresh lane C throwaway, or on the warm one after a production restart (it is production code).
   - If (b) is not "", or (c) is not `7`, adjust AC 3's test setup to what you saw and say so here.

**Execution:**
- [ ] `Watch/SettingCause.cls`:
  - Add after `ResultSlots` (after L355):
    ```
    /// The value that a setting kind's request gives the setting after its run, as a person sees it: Shown of the after of its stored dry run (dryRun, the JSON text), "" when the
    /// dry run can't be read or has no after. The result texts' {after} (ResultSlots, from IncidentManager ResultExtra) and the request part of the incident payload
    /// (Live.Payload.Incident) both show this value, so the card names what the chat names. It reads nothing else (AD-13: /state runs it with no SQL grant).
    ClassMethod ShownAfter(dryRun As %String) As %String
    {
    	Set after = ""
    	Try {
    		Set after = ..Text({}.%FromJSON(dryRun).%Get("after"))
    	} Catch {
    		Set after = ""
    	}
    	If after = "" Quit ""
    	Quit ..Shown(after)
    }
    ```
  - Class doc L13: "IsSetting, RollbackSlots, UndoSlots, ResultKey, ResultSlots, Names and the summary keys" becomes "IsSetting, RollbackSlots, UndoSlots, ResultKey, ResultSlots, ShownAfter, Names and the summary keys".
  - Append to the sentence that ends "...stay raw." (L16): " ShownAfter gives the incident payload's request part the same {after} as the result texts."
- [ ] `Live/Payload/Part/IncidentRequest.cls`:
  - Insert after `Count` (after L18), before `Result`:
    ```

    /// The value that the dry run of a setting kind's request (rollback_setting, undo_rollback; Story 23.3, DW-1378) gives the setting after the run, as the result notice's {after}
    /// shows it (Watch.SettingCause ShownAfter: redacted by Bridge.Redact); empty for any other kind and when the dry run has none.
    Property After As %String(%JSONFIELDNAME = "after", MAXLEN = 1000);
    ```
  - Class doc L1 becomes: "/// One approval request of an incident: its Ref, state, fix kind, the item, count and after of the kinds that name them, and its result. Lane A."
- [ ] `Live/Payload/Incident.cls`:
  - `Chosen`'s setting branch (L216-219) becomes:
    ```
    		If (request.FixKind = "rollback_setting") || (request.FixKind = "undo_rollback") {
    			Set part.Item = {}.%FromJSON(request.DryRun).%Get("item")
    			Set part.After = ##class(OcuTalon.Watch.SettingCause).ShownAfter(request.DryRun)
    			Quit
    		}
    ```
  - `Chosen`'s doc (L210-211) becomes: "/// Fills the item, the count and the after of a request part for the fix kinds the user asks for in the chat and the setting kinds: the item of a suspend or resume, the target item of a reroute and the count of its dry run, and the item and the after of a setting kind's dry run (Story 23.3; the after as Watch.SettingCause ShownAfter gives it, the value of the result notice's {after}, DW-1378). Any other kind, and a request whose parameters or dry run can't be read, leave them empty."
- [ ] Regenerate `web/src/app/live/payloads.ts` with `npm --prefix web run payloads`. The diff is one line, `  after?: string;`, after `count?: number;` in `IncidentRequest`.
- [ ] `web/src/app/approvals/approval-view.ts`:
  - L702 becomes `const after = textOf(request.after);`.
  - `settingResultView`'s doc (L695) becomes: "/** The band of a rollback or an undo of a setting (Story 23.3): see resultView. The setting and its item are the incident's settingChange; the value it has again is the request's `after`, the After of its approved dry run that the chat's result line names (DW-1378), never the settingChange's recorded old or new value. */"
  - `resultView`'s setting clause (L571-574):
    - "(fixKind rollback_setting, undo_rollback, Story 23.3; setting, item and value of the incident's settingChange)" becomes "(fixKind rollback_setting, undo_rollback, Story 23.3; setting and item of the incident's settingChange, and the request's `after`, the value that the chat's result line names, DW-1378)".
    - Its last sentence gains: "; the band never names the settingChange's recorded values".
- [ ] The architecture spine: insert the sub-bullet of Veto item 4, word for word, after the "**The incident payload's step 5 fields**" bullet (L455). Use the same four-space indent.
- [ ] Tests (below), each with its class-doc bullet added or changed.
- [ ] This spec: `## Verification`, with the Task 0 records and the mutation lines.

**Tests:**
- **`Test/Watch/SettingCause.cls`: new `TestRequestAfter` (AC 1, AC 2, AC 4, AC 5).** It runs on a slot or a throwaway, warm.
  - Setup:
    - `..Snapshot("2026-11-01T00:00:00Z")`.
    - `change = ..Change("2026-11-10T11:56:00Z", "Fails", "PoolSize", "1", "7")`, then `incident = ..Incident("Fails", change)`.
    - Six requests through `##class(OcuTalon.Test.Data.Fixture).Approval("zzowner", ..#INCIDENT, "done", , fields)`, with `fields` `{"FixKind", "FixParameters": {"change": (change)}.%ToJSON(), "DryRun"}`:
      - (a) rollback_setting `{"item": "Fails", "field": "PoolSize", "before": "7", "after": "1"}`;
      - (b) undo_rollback `{... "before": "1", "after": "7"}`;
      - (c) undo_rollback `{... "before": "1", "after": "9"}` (DW-1366);
      - (d) undo_rollback with `"after": (..TokenUrl())`;
      - (e) undo_rollback with no `after`;
      - (f) suspend_item with `FixParameters` `{"item": "Fails"}` and dry run `{"item": "Fails", "before": "enabled", "after": "disabled"}`.
    - Give each a done run with `##class(OcuTalon.Test.Data.Fixture).FixRun(..#INCIDENT, ref, {"Total": 1, "Completed": 1})`.
    - Set `incident.RequestRefs` to the six Refs in order and save.
  - Build `payload = ##class(OcuTalon.Live.Payload.Incident).FromRow(incident)` and export it to `json`. `object` is the parsed JSON.
  - Assert:
    - The six parts' `after` are `1`, `7`, `9`, the shown URL, absent and absent: "each setting request carries its dry run's after; a dry run with none, and another kind's request, carry none".
    - `$Find(json, ..Token()) = 0`: "the payload holds no token", and the request row's `DryRun` still holds it.
    - **The CONDITION**, for (a) to (d):
      - key = `result.settingRestored` for (a), else `result.rollbackUndone`;
      - chat = `Msg.Catalog.Render(key, ResultSlots(key, {"setting": <change row>.Setting, "target": <change row>.Item, "after": <dry run>.after}, .sc), "web", .sc)`: the chat line, as `IncidentManager.ResultExtra` and `ResultNotice` build it;
      - band = `Msg.Catalog.Render(key, {"setting": payload.SettingChange.Setting, "target": payload.SettingChange.Item, "after": <part>.After}, "web", .sc)`: the band's slots, as the page takes them;
      - assert band = chat: "the band names what the chat names".
    - For (c), also:
      - band [ "is back to 9.";
      - the same render with `after` = `payload.SettingChange.NewValue` gives "is back to 7.", not the chat line: "the recorded new value would contradict the chat".
    - For (e), `ResultSlots` with `after` "" gives an error status: "with no after the chat has no result line either".
  - Put a class-doc bullet after `TestShownRedacted`'s: "TestRequestAfter (DW-1378): the incident payload's request part of a setting kind carries the after of its dry run, redacted as the result notice's {after}, and the band's slots render to the chat's result line, the DW-1366 case included; a dry run with no after, and another kind, carry none."
- **`Test/Watch/Rollback.cls`: the real run (AC 3, AC 4).** Fresh, or warm after a production restart.
  - `TestUndoSystemDefaultChanged`, after its existing asserts:
    - `notes = ..WaitResultNotices(incident, 2)`. Assert size 2. The undo's note (`notes.%Get(1)`) has `catalogKey` `result.rollbackUndone` and `slots.after` `9`.
    - Open the incident and set `SettingChangeRef = change`, as `IncidentManager.Answered` names a diagnosed change. Save it, asserting OK.
    - `payload = Live.Payload.Incident.FromRow(row)`. The part whose `FixKind` is `undo_rollback` has `After` `9`, and `payload.SettingChange.NewValue` is `7`: "the request part names the value the item has, and the recorded new value is stale".
    - `Render(note.catalogKey, {setting, target from payload.SettingChange, after: part.After}, "web")` equals `Render(note.catalogKey, note.slots, "web")`, and it contains "is back to 9.": "the band's text is the chat's result line (the CONDITION)".
    - The method doc gains: "...; the incident payload's request part names 9 too, and the band's slots render to the chat's result line (DW-1378). mutation: the part's after from the change's recorded new value."
  - `TestTokenValueRestoredRaw`:
    - After L1040, the part of `payload.Requests` whose `Ref` is `request.ref` has `After` = `shown`: "and its request part shows the after redacted (DW-1378)".
    - After L1058, `result.slots.after` equals that `After`: "the result notice's {after} is the request part's after".
  - The class doc's DW-1366 bullet (L9-10) and 24.4a bullet (L18-19) gain the matching clause.
- **`Test/Live/Payloads.cls` (AC 6).**
  - XData `Contracts`: in `Part.IncidentRequest`, insert `"After": "%String(%JSONFIELDNAME=after,MAXLEN=1000)",` after `"Count"`.
  - `TestFromRowRequestKinds`: each of its three asserts adds `_"|"_one.%IsDefined("after")`, expected `0`: "and no after".
  - Class doc: add "and the after of a setting kind's request (DW-1378; Test.Watch.SettingCause TestRequestAfter)" after "(Story 23.2)".
- **`web/scripts/approval-view.test.mjs` (AC 1, AC 2, AC 5, AC 7).**
  - The `band` helper (L116) gains `after: AFTER[fixKind]`, with `const AFTER = { rollback_setting: 'OrdersToWarehouse', undo_rollback: 'OrdersToWarehous' };`, the dry runs' afters at L111-112. Every existing assertion stays as written.
  - New describe, "the value that the band of a done setting run names (DW-1378)":
    - `it('names the request\'s after, the value the chat\'s result line names, and never the incident\'s recorded values')`. Use a table of `[fixKind, change, dryRunAfter]`:
      - rollback with `CHANGE`;
      - undo with `CHANGE`;
      - undo with `{ ...CHANGE, setting: 'PoolSize', oldValue: '1', newValue: '7' }` and after `'9'`;
      - undo with after `'https://feed.example.test/orders?token=[redacted]'`.
    - For each row, the band of `{ ref, state: 'done', fixKind, item, after: dryRunAfter, result: ran() }` with the row's change has `.text` equal to `renderPageText(key, { setting: change.setting, target: change.item, after: dryRunAfter })`. That is the chat's line: same key, setting and target from the change row, `{after}` from the approved dry run. Also assert the DW-1366 row's text is exactly "The rollback is undone: PoolSize on OrdersFromPartner is back to 9." and does not contain "back to 7".
    - `it('gives a done run with no after no band, for both kinds, though the incident has both recorded values')`: `after` absent, `''` and `'  '`, each `undefined`.
    - `it('keeps the not-applied, changed-since and not-changed bands whatever the after')`: the three partial bands of L152-183 with `after: '9'` deep-equal those without it.
  - The file's header comment gains "DW-1378: the value a done setting band names".
- **`web/scripts/incident-view.test.mjs` (AC 7).**
  - Fixture updates. The band text and the keys are unchanged:
    - L196: the done rollback gains `after: 'OrdersToWarehouse'`;
    - `asked` L821: `RB1` gains `after: '4'`;
    - `asked` L822: `UN1` gains `after: '8'`.
  - New `it` in the closed-card describe: "names the request's after in a done undo's compact band and in the chat's announcement, not the recorded new value (DW-1378)". Use `closed({ requests: [{ ref: 'UN9', state: 'done', fixKind: 'undo_rollback', item: 'OrdersToWarehouse', after: '9', result: done }] })` with `change.newValue` `'8'`:
    - `seen(...).results[0].text` and `bandTexts(..., context(withChange)).UN9` are both "The rollback is undone: PoolSize on OrdersToWarehouse is back to 9.";
    - with no `after`, `bandTexts(...)` has no `UN9`.
- **`web/e2e/cards/approval-card.spec.ts`: new A15 (AC 8), project `cards`.**
  - Name: "A15: a done undo carries its dry run's after over real HTTP, and the closed card's band names it, not the recorded new value (DW-1378)".
  - Add `seedFixRun` to the imports.
  - Setup, as the unprivileged cards user over `http`:
    - `change = seedSettingChange({ item: 'OrdersFromPartner', setting: 'PoolSize', oldValue: '1', newValue: '7', detectedAt: today('14:08:00') })`;
    - `undo = refOf('A15u')`;
    - `incident = seedIncident(user, { state: 'closed', closedAt: today('14:20:00'), firstAt: today('14:12:00'), settingChangeRef: change, requestRefs: undo })`;
    - `seedApproval(user, { ref: undo, fixKind: 'undo_rollback', state: 'done', incidentRef: incident, requiredRole: 'OcuTalonUser', dryRun: { item: 'OrdersFromPartner', field: 'PoolSize', before: '1', after: '9' }, answeredAction: 'approve', answeredChannel: 'web', answeredBy: user, answeredAt: today('14:18:00') })`;
    - `seedFixRun(incident, undo, { total: 1, resent: 0, completed: 1 })`.
  - Over HTTP: `GET /api/v1/state`'s chat item of the incident has `requests` `[{ ref: undo, state: 'done', fixKind: 'undo_rollback', item: 'OrdersFromPartner', after: '9', ... }]` (toMatchObject) and `settingChange.newValue` `'7'`.
  - In the page (`open(page)`), `incidentCard(page, incident).locator('[data-part="result"] .text')` has the text "The rollback is undone: PoolSize on OrdersFromPartner is back to 9." and does not contain "back to 7".
  - In `finally`: `cleanFixtureRows([incident, undo])` and `dropSettingChange(change)`.
  - The header comment's list gains A15.
- **`web/e2e/rail/step5-cards.spec.ts` (fixtures, AC 7).**
  - `Entry` (L294-301) gains `after?: string;`.
  - Each done setting entry gains the after that its dry run gives, which the server now sends: `after: OLD` for `rollback_setting` (L346, L562) and `after: NEW` for `undo_rollback` (L528, L550, L563, L718).
  - The expected band texts are unchanged.

**Acceptance Criteria:**
1. Given a setting request with a stored dry run, when the incident payload is built (`incident` event or `/api/v1/state`), then the request part carries `after`, the dry run's after shown as the chat's `{after}` is. A rollback or undo whose after is the recorded value reads as before.
   - mutation: the `Set part.After = ...` line of `Chosen` removed -> `Test.Watch.SettingCause:TestRequestAfter` red ("each setting request carries its dry run's after").
2. Given another kind's request whose dry run has an `after` (a suspend), then its part has no `after`.
   - mutation: the `Set part.After = ...` line moved above the kind test of `Chosen` -> `TestRequestAfter` red (row f), and `Test.Live.Payloads:TestFromRowRequestKinds` red ("and no after").
3. Given the DW-1366 run (a System Default moved to 9 while hidden; recorded new value 7), when the undo is done, then the request part's after is 9 and the band's slots render to the chat's result line "...is back to 9.".
   - mutation: `Chosen` sets `part.After` from the change row's `NewValue` (through `Bridge.Redact.Text`) -> `Test.Watch.Rollback:TestUndoSystemDefaultChanged` red ("the band's text is the chat's result line") and `TestRequestAfter` red (row c).
4. Given a dry run whose after holds a token, then the part's after is redacted exactly as the chat's `{after}`. No token is in the payload's JSON, and the stored dry run stays raw.
   - mutation: `ShownAfter` returns `after` without `..Shown` -> `TestRequestAfter` red ("the payload holds no token") and `Test.Watch.Rollback:TestTokenValueRestoredRaw` red ("its request part shows the after redacted").
5. Given a dry run with no after, then the part has no after, and a done run has no band, as the chat has no result line.
   - mutation: `settingResultView` takes `textOf(request.after) || textOf(request.fixKind === 'undo_rollback' ? change?.newValue : change?.oldValue)` -> `approval-view.test.mjs` red ("gives a done run with no after no band").
6. Given the payload contracts, then `Part.IncidentRequest` holds exactly its seven properties, and `payloads.ts` is the generator's output.
   - mutation: the property `After` taken out of `IncidentRequest.cls` -> `Test.Live.Payloads:TestContracts` red (the contract names a property the class lacks).
   - mutation: the regenerated `after?: string;` line taken out of `payloads.ts` -> `node web/scripts/payloads.mjs --check` exits 1, and `payloads.test.mjs` is red ("the real tree's check").
7. Given a done setting band on the request card, on the closed card or in the chat's announcement, then it names `request.after`, and its text equals the chat's result line for the same run. The DW-1366 case says 9.
   - mutation: `settingResultView`'s L702 put back to `textOf(request.fixKind === 'undo_rollback' ? change?.newValue : change?.oldValue)` -> `approval-view.test.mjs` red (the DW-1366 row: "back to 7" is not the chat's line), and `incident-view.test.mjs` red (UN9's band and announcement).
8. Given a seeded closed incident with a done undo over real HTTP, then `/api/v1/state` carries the request's `after` 9 next to `settingChange.newValue` 7, and the page's band says "back to 9".
   - mutation: the `Set part.After = ...` line of `Chosen` removed (compiled into the stack) -> A15 red (the state has no `after`; the band is absent).
9. Every other band and payload field is as before. These pass:
   - `Test.Watch.SettingCause` and `Test.Live.Payloads` (whole classes);
   - `Test.Watch.Rollback`: `TestUndoSystemDefaultChanged`, `TestUndoDefaultMovesAfterDryRun`, `TestUndoDefaultGone`, `TestTokenValueRestoredRaw`, `TestUndoRequestTokenRedacted` and `TestUpdateFailureNotApplied`;
   - `npm --prefix web test`, the 921 kB initial-bundle test included;
   - A14, A11 and A12 of `approval-card.spec.ts`, and F6 and F6b of `step5-cards.spec.ts`.

## Design Notes

**Which value is "the actual value".** The ruling's fallback sentence reads: "If the band can't show the actual value, it shows the catalog result text instead". This spec reads it as follows:
- The page cannot read the item's live effective value, so the band shows the catalog result text that the chat shows: the same key with the approved dry run's After.
- After a done run, that is the actual value. `UndoRollback.Plan` skips the run with CHANGEDAGAIN when the value would differ from the approved After (DW-1366's run-time re-check). A rollback writes its After itself.
- When the request has no `after` at all (matrix row 5), no band shows. The chat sends no result line then either: `ResultSlots` refuses an empty `{after}`. So nothing contradicts the chat.
- A done rollback or undo has no approved catalog result text without a value. Writing one would be new public text, which this item does not add.
- If the Planner meant a value-free band for row 5, that is a new key for a later ruling. It does not change this design.

**Why `ShownAfter` and not the approval payload's dry run.**
- The page has the approval payload's `dryRun.after` only while the request is in the store. After a reload, the rail holds pending requests only (`Web.Api.RailBody`). A done undo on a closed card has only the incident payload's request part. The incident-view path (`bandsOf`, `bandTexts`) never has the approval payload.
- `Live.Payload.Approval` redacts without trimming (`Bridge.Redact.Text(dry.after)`). The chat trims first (`Shown` = `Redact.Text(Text(value))`). `ShownAfter` uses `Shown` itself, so the two strings are the same function's output, not two copies of a rule.

**Both setting kinds.** The chat names the dry run's after for a rollback as well (`ResultExtra` does not look at the kind). For a rollback that after is the change's old value (`RollbackSetting.Restored`). So reading `request.after` for both kinds changes no rollback text, except that it trims spaces at either end, as the chat does. The band then has one rule.

**No fallback to the recorded values.** A fallback would bring DW-1378 back whenever the field is missing. With this server the field is missing only when the chat has no line (matrix row 5). So "no band" is the reading that cannot contradict the chat.

**Setting and target.** They stay `settingChange.setting` and `settingChange.item`. The chat takes `change.Setting` and `change.Item` of the row that the request's `change` parameter names. For a diagnosed rollback, that is the incident's `SettingChangeRef` (`IncidentManager.Answered` sets both from `named.ref`). An undo's `change` is that rollback's change (`Fix.Run.RolledBack`). So they are the same row. Taking them from the request too would widen the field set, and no case needs it.

**The CONDITION, and how it is pinned.** The band's text equals the chat's result line because each slot comes from the same source: the same catalog key, the same row's setting and item, and the same `Shown` of the same dry run's after. It is pinned in three layers:
- **Server, unit (`TestRequestAfter`).** The band's slots, as the page takes them from the payload, render to the chat's line, as `ResultExtra` and `ResultSlots` build it. This covers rows 1 to 4, the DW-1366 row included, and a control shows that the recorded value would not.
- **Server, real run (`TestUndoSystemDefaultChanged`).** The same comparison for the result notice that `IncidentManager` really sent after the DW-1366 run.
- **Page (node tests and A15).** The band renders `renderPageText(key, {setting, target, after: request.after})`, and `catalog.mjs --check` pins that the page's `result.settingRestored` and `result.rollbackUndone` texts are the server's. A15 shows "back to 9" in a real page from `/api/v1/state`.

The mutation that makes them disagree is AC 7's: `settingResultView` reading `change?.newValue` again. It turns the DW-1366 rows red in `approval-view.test.mjs` and `incident-view.test.mjs`. AC 3's server mutation does the same in `TestRequestAfter` and `TestUndoSystemDefaultChanged`.

**Why the chat line is not on the web page.** A fix's result notice records its web Delivery row only: `WebChat.Out` `INCIDENTKINDS` holds `result`. On the web the band itself is the result line, and `bandTexts` announces it. The chat's result line is the phone, Telegram and mailbox text of the same notice. That is why the comparisons render the notice's key and slots on the server.

**MAXLEN.** It is 1000, as `Part.DryRun.After`. `%JSON.Adaptor` checks MAXLEN only on import, never on export (`irislib/%JSON/Generator.cls`: `IsValid` is generated for import only). So a longer System Default value, or one lengthened by `[redacted]`, still exports, as the dry run part's `After` does today.

**Bundle.** `approval-view.ts` is in the eager chat code and cannot move to a lazy chunk. The change replaces one expression with a shorter one (about minus 40 bytes). `payloads.ts` is types only. The 921 kB test is run once, and no new web module is added.

**Merge.**
- Feature has moved to `9019fe772` (DW-1426 merged). DW-1426 edits `web/e2e/rail/step5-cards.spec.ts` (pending-undo entries and the F6b announcement tests) and `incident-card.ts`. This item's step5-cards hunks only add `after` to done setting entries.
- At the integrate-forward, keep both sides. Any done setting entry that arrives from feature also gains its `after`.
- No other open worktree branch touches the footprint's product files.

**AD:** no new AD. AD-12 gains a sub-bullet (Veto item 4). AD-13 holds: `ShownAfter` reads no row and runs no SQL, and A15 runs `/state` as the unprivileged user. The 24.4a redactor ruling holds: one server redactor, and the stored dry run is raw.

**Ledger:** DW-1378 (this spec). Its status line is recorded at merge, through `ledger.sh append`, per the run's DW process.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. The band keeps its catalog keys `result.settingRestored` and `result.rollbackUndone` and their approved texts. Only the source of `{after}` changes: from the incident's `settingChange` to the request's `after`, the value that the chat's result line already names. No catalog entry, slot, web form, `EXPERIENCE.md` or `docs/` line changes. A done run with no `after` keeps today's rule (no band), as the chat has no line then. | Approve (no text to rule). |
| 2 | (b) Cross-lane edits | Lane A: `Live/Payload/Part/IncidentRequest.cls`, `Live/Payload/Incident.cls` (`Chosen`), `Watch/SettingCause.cls` (`ShownAfter`), and `Test.Live.Payloads`, `Test.Watch.SettingCause` and `Test.Watch.Rollback`. Web: `approval-view.ts`, the generated `payloads.ts`, `approval-view.test.mjs`, `incident-view.test.mjs`, and the e2e specs `approval-card.spec.ts` (new A15) and `step5-cards.spec.ts` (fixtures gain `after`). Lane C makes all of them under the run's DW-1378 assignment, per the Planner's lane C order. Overlap: DW-1426 (merged to feature) edits `step5-cards.spec.ts`, so it is a plain union at the integrate-forward (Design Notes). | Grant. |
| 3 | (c) Stored data or schema | None. No persistent class, property, index or global changes. `Part.IncidentRequest` is a `%RegisteredObject` payload part, not stored, and `Live.Event` rows hold the payload as text. Events published before the change lack `after`, and the page then shows no done setting band for them until the next `incident` event or `/state` load. The stored `ApprovalRequest.DryRun` stays raw. | Approve, with no migration. |
| 4 | (d) Architecture change | AD-12's incident payload gains one field. Insert, word for word, after the "**The incident payload's step 5 fields**" bullet: `    - **A setting request's after** [ADDED 2026-11-16, DW-1378, Contest Planner ruling 2026-11-15 ("23.3 follow-ups")]. Each entry of the `incident` payload's `Requests` of a setting kind (`rollback_setting`, `undo_rollback`) also carries `After`: the value that its stored dry run gives the setting after the run, shown through `Bridge.Redact` as every shown setting value is (`Watch.SettingCause.ShownAfter`, the value of the result notice's `{after}`). The result band of a done run names that value and never the `SettingChange` values, so the card says what the chat's result line says; a request with no `After` has no done band. `/api/v1/state` carries it through the same builder (`Live.Payload.Incident.FromRow`).` The REST row of `GET /api/v1/state` lists no incident payload field and is unchanged. | Approve the AD-12 amendment. |
| 5 | (e) Product behaviour change | The result band of a done `undo_rollback` names the After of the approved dry run, the value that the item has and that the chat's result line names. It no longer names the change's recorded new value. In the DW-1366 case the card now says "back to 9" where it said "back to 7". A done `rollback_setting` reads as before. Spaces at either end of a value are trimmed, as in the chat. A done setting run whose request carries no `after` shows no band. Other kinds, and the not-applied, changed-since and not-changed setting bands, are unchanged. The request part of a setting kind also carries `after` while pending, the same redacted value that the approval payload's dry run already shows. | Approve. |

## Public text

None new. Read for consistency, unchanged:
- `result.settingRestored`: "{setting} on {target} is back to {after}. To undo it, ask me to undo the rollback."
- `result.rollbackUndone`: "The rollback is undone: {setting} on {target} is back to {after}."

## Spec gate rulings (Contest Planner, Nov 16, BINDING): APPROVED; 1.0.12 CUT ITEM

- APPROVED. The AD-12 sub-bullet is approved VERBATIM as given in this spec. The fallback reading is CONFIRMED (the band shows the catalog result text with the approved dry run's After; a request with no `after` shows no band).
- PIN that a done run means the setting equals the dry run's After, with a mutation where the run succeeds despite a moved value (the band must not claim a value the run did not reach).
- A no-`after` request shows NO band and NO error; cover it in the node tests.
- Order: implement now, ahead of DW-1421.
- Note for implement: the branch merged feature (DW-1416's summary.partnerMaySent); the Watch catalog count is now 147 (both keys); re-run Test.Msg.Catalog and Test.Watch.Summary.

## Implement-stage overrides (Contest Planner, Nov 16, BINDING; pre-answered)

- **The change** is exactly this spec's (`Watch.SettingCause.ShownAfter`; `IncidentRequest.After`; `Incident.Chosen`, setting kinds only; the regenerated `payloads.ts`; `settingResultView` reading `request.after` and never the `settingChange` values; the AD-12 sub-bullet VERBATIM as Veto item 4 gives it). No new public text.
- **Pin A (a done run means the setting equals the dry run's After).** Add a test and a `mutation:` line: make the undo's run-time re-check (`Fix/Kind/UndoRollback.cls`, `Plan`, about L132) pass when the value moved, so the run succeeds despite a moved value, and show a test goes red because the band and the chat would claim a value the item does not have. The pin is in the Rollback tests (a done undo whose default moved after the dry run does not report done with the old After: `TestUndoDefaultMovesAfterDryRun` or a new method beside it). The production edit is for the mutation only and is reverted byte for byte.
- **Pin B (no `after`).** A request with no `after` shows NO band and NO error. Cover it in `approval-view.test.mjs` and `incident-view.test.mjs`.
- **Pin C (the CONDITION).** The band never contradicts the chat: the three layers of Design Notes, each with its mutation.
- **Rule 19.** Every pin has a `mutation:` line in `## Verification`, shown red and then reverted byte for byte (`cmp` against a copy taken before).
- **Runs.** Warm: `Test.Watch.SettingCause`, `Test.Watch.Rollback` (after a production restart), `Test.Live.Payloads`, and any `Test.Web.*` state API class. Node: `cd web && npm ci && npm test`, `web/scripts/initial-bundle.test.mjs`, `npm run lint`, and the payloads `--check`. Browser: `ci/iris.sh build`, then `ci/iris.sh live cards`, and the project or part that holds `web/e2e/rail/step5-cards.spec.ts` (find it with `web/scripts/e2e-part.mjs` or the playwright config). A fresh `lane-a@Fix` shard is not required unless a `Fix/*` file is touched (the Pin A mutation is reverted, so none stays touched). Also `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` and the spine lint (baseline 12 low; add none).
- **Merge resolution check (done at entry, by the lead).** The branch merged feature at `80a3cf02c`. Warm `Test.Msg.Catalog` (Watch count 147) and `Test.Watch.Summary` both pass on the entry tree: no fix to the union was needed.

## Verification

Use a lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`. Fresh runs leave `OCUTALON_WARM` unset.
- `Test.Watch.Rollback` needs the production's jobs to hold the new code: the incident event is built in `IncidentManager`'s job. So it runs fresh, or warm after a production restart.
- One test class (or `Class:Method`) per foreground call, `timeout: 600000`, each under about 3 minutes. Never run two test calls in one message. A browser unit that would pass about 9 minutes is split, as its script allows. The cap is never raised.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag. Then Task 0, before any product edit.
- (loop) Warm, each expected to pass:
  - `ci/iris.sh class OcuTalon.Test.Watch.SettingCause:TestRequestAfter`;
  - `ci/iris.sh class OcuTalon.Test.Live.Payloads`;
  - `node web/scripts/payloads.mjs --check`;
  - `node --test web/scripts/approval-view.test.mjs web/scripts/incident-view.test.mjs web/scripts/payloads.test.mjs`.
- (once) Warm, after a production restart, one per call:
  - `ci/iris.sh class OcuTalon.Test.Watch.Rollback:TestUndoSystemDefaultChanged`;
  - then `:TestTokenValueRestoredRaw`;
  - then `:TestUndoDefaultMovesAfterDryRun`, `:TestUndoDefaultGone`, `:TestUndoRequestTokenRedacted` and `:TestUpdateFailureNotApplied`.
- (once) Warm, whole class: `OcuTalon.Test.Watch.SettingCause`.
- (once) Fresh, each expected to pass: `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Watch.SettingCause`, and `OcuTalon.Test.Watch.Rollback` (whole class, or split by method).
- (once) `npm --prefix web test`: every node test, `initial-bundle.test.mjs` (921 kB) and `catalog.test.mjs` included.
- (once) Browser, after `ci/iris.sh build`:
  - `ci/iris.sh live cards` for `approval-card.spec.ts`: A15 new, A11, A12 and A14;
  - `ci/iris.sh live sign-in-2` for `web/e2e/rail/step5-cards.spec.ts` (F6, F6b). Split it as `docker/tests/test-sign-in-2.sh` allows if it runs long.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call. Each exits 0.
- (once) The spine lint: `.claude/skills/bmad-architecture/scripts/lint_spine.py --workspace` with the spine folder. No finding is new against the baseline's 12 low.
- (once) `git diff --name-only cb69bbeb1` lists only the footprint files. No added line holds a non-ASCII character or an absolute local path.
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag.

**Mutations (Rule 19):**
- Write one `mutation:` line per mutation under AC 1 to 8, as `mutation: <change> -> <test that went red>`.
- Revert each byte for byte (`cmp` against a copy taken before it), and check that `git status --short` and `git diff --stat` are as before.
- A15's mutation runs on the browser stack once. If a second `ci/iris.sh build` does not fit the run, record the node and IRIS mutations of AC 1 and AC 7 as covering the same line, and say so.

**Task 0 records** (lane C warm throwaway, tag e21dw1378iw, started by the lead; scratch class `ZzScratch.Dw1378` extending `Test.Watch.Rollback`, loaded into the throwaway only, deleted from it, never in the tree):
1. Baseline, no stack: `git rev-parse HEAD` d355ebdd7f5e435f116c5aa5f19957f70649df54. `node web/scripts/payloads.mjs --check` exit 0 ("generated files are current"). `node --test web/scripts/approval-view.test.mjs web/scripts/incident-view.test.mjs web/scripts/payloads.test.mjs`: 189 tests, 189 pass. `node --test web/scripts/initial-bundle.test.mjs`: 2 pass (the run prints no total).
2. Baseline classes, warm, one call each: `OcuTalon.Test.Watch.SettingCause` passed (63.4 s); `OcuTalon.Test.Live.Payloads` passed (0.7 s).
3. The defect through the real DW-1366 run (the scratch method runs `TestUndoSystemDefaultChanged`'s steps, on the production as it was at the baseline, which holds no changed code):
   - (a) `WaitResultNotices(incident, 2)`: 2 notices. The rollback's is `result.settingRestored`, slots `{"setting":"RetryInterval","target":"OrdersFromPartner","after":"5"}`. The undo's is `result.rollbackUndone`, slots `{"setting":"RetryInterval","target":"OrdersFromPartner","after":"9"}`.
   - (b) The fixture incident's `SettingChangeRef` is "" (as expected); its `RequestRefs` lists the two requests.
   - (c) With `SettingChangeRef` set to the change and saved: `FromRow(row)`: `SettingChange.NewValue` 7 and `OldValue` 5 (as expected). The undo part's JSON is `{"ref":...,"state":"done","fixKind":"undo_rollback","item":"OrdersFromPartner","result":{...}}`: no `after` key (the defect: the part cannot carry the chat's value).
   - (d) The chat line (the notice's slots): "The rollback is undone: RetryInterval on OrdersFromPartner is back to 9." Today's band (`{setting, target}` of the payload's `SettingChange` and `after` = `NewValue`): "The rollback is undone: RetryInterval on OrdersFromPartner is back to 7." The two differ, as the spec reads. Nothing to adjust in AC 3's test setup (the setting of the fixture is RetryInterval, the change's NewValue 7, not PoolSize as TestRequestAfter's own fixture names it).

**Mutations** (Rule 19; each applied, the named test run warm and shown red, then reverted from a copy taken before it and checked with `cmp`; the class or script green again after the revert):
- mutation (AC 1): the `Set part.After = ...` line of `Chosen` removed -> `Test.Watch.SettingCause:TestRequestAfter` red ("each setting request carries its dry run's after", and the band-names-what-the-chat-names asserts of all four rows).
- mutation (AC 2): the `Set part.After = ...` line moved above the kind test of `Chosen` -> `TestRequestAfter` red ("each setting request carries its dry run's after; a dry run with none, and another kind's request, carry none": the suspend of row f) and `Test.Live.Payloads:TestFromRowRequestKinds` red ("the suspend names its item and gives no count, and no after", and "the repair request names no item and gives no count, and no after").
- mutation (AC 3): `Chosen` sets `part.After` from the change row's `NewValue` through `Bridge.Redact.Text` -> `Test.Watch.Rollback:TestUndoSystemDefaultChanged` red ("the request part names the value the item has, and the recorded new value is stale", and "the band's text is the chat's result line (the CONDITION)", which read "back to 7") and `TestRequestAfter` red (row c: "the DW-1366 band says 9").
- mutation (AC 4): `ShownAfter` returns `after` without `..Shown` -> `TestRequestAfter` red ("the payload holds no token") and `Test.Watch.Rollback:TestTokenValueRestoredRaw` red ("and its request part shows the after redacted (DW-1378)", "the result notice's {after} is the request part's after", and "no live event payload holds the token": the unredacted part leaked the token into the live event).
- mutation (AC 5): `settingResultView` takes `textOf(request.after) || textOf(request.fixKind === 'undo_rollback' ? change?.newValue : change?.oldValue)` -> `approval-view.test.mjs` red ("gives a done run with no after no band and no error"), and `incident-view.test.mjs` red (the no-after half of the DW-1378 closed-card test).
- mutation (AC 6): the property `After` taken out of `IncidentRequest.cls` -> `Test.Live.Payloads:TestContracts` red ("property After is missing").
- mutation (AC 6): the generated `after?: string;` line taken out of `payloads.ts` -> `node web/scripts/payloads.mjs --check` exits 1 ("payloads.ts is stale"), and `payloads.test.mjs` red ("has a current payloads.ts", "the copy of the real tree is current").
- mutation (AC 7): `settingResultView`'s line put back to `textOf(request.fixKind === 'undo_rollback' ? change?.newValue : change?.oldValue)` -> `approval-view.test.mjs` red ("names the request's after, the value the chat's result line names, and never the incident's recorded values": the DW-1366 row says "back to 7"; and the no-after test) and `incident-view.test.mjs` red (UN9's compact band and announcement).
- mutation (Planner's Pin A, a done run means the setting equals the dry run's After): `Fix/Kind/UndoRollback.cls` `Plan`'s comparison `(after '= ..Approved(run))` made `0`, so that the run succeeds although the default moved to 11 after the dry run (the production restarted so that FixExecutor held it) -> `Test.Watch.Rollback:TestUndoDefaultMovesAfterDryRun` red ("no run that changed the setting names a value that the item does not have": the undo ran, the part's After was 9 and the item had 11; also "Skipped 1, nothing changed", "nothing was written", "the undo's is result.settingChangedSince" and "Completed 0, Skipped 1"). Reverted from a copy (`cmp` identical, no `Fix/` file in `git status`), the production restarted, the method green again.
- mutation (AC 8): the `Set part.After = ...` line of `Chosen` removed, compiled into a fresh lane C browser stack (`ci/iris.sh live cards`, tag e21dw1378ib) -> `approval-card.spec.ts` A15 red (the state has no `after`; 1 failed, 32 passed). Reverted from a copy (`cmp` identical, `git diff --stat` as before); `live cards` was green before the mutation (33 passed, A15, A11, A12 and A14 among them).

**Command results** (warm tag e21dw1378iw, lane C, one call each; the production restarted before the Rollback runs):
- `TestRequestAfter` passed; `Test.Live.Payloads` passed; `Test.Watch.SettingCause` passed (whole, 63 s); `Test.Web.Api` passed.
- After a production restart: `Test.Watch.Rollback:TestUndoSystemDefaultChanged`, `:TestTokenValueRestoredRaw`, `:TestUndoDefaultMovesAfterDryRun`, `:TestUndoDefaultGone`, `:TestUndoRequestTokenRedacted` and `:TestUpdateFailureNotApplied` passed; the whole class `Test.Watch.Rollback` passed (104 s), after the Pin A mutation was reverted and the production restarted again.
- Spec gate note: `Test.Msg.Catalog` passed (Watch count 147) and `Test.Watch.Summary` passed, on the implemented tree.
- `cd web && npm ci && npm test`: 2190 tests, 2190 pass. `npm run lint` passed. `node web/scripts/payloads.mjs --check` exit 0. `node --test web/scripts/initial-bundle.test.mjs`: 2 pass (the 921 kB cap).
- `web/scripts/playwright-projects.test.mjs` pins the cards project at 32 cases and A2 to A14; A15 made it fail, so its pin is now 33 cases and A2 to A15 (a footprint file the spec did not list; the pin follows the new case and no assertion is removed).
- The diff holds no added non-ASCII character and no absolute local path. The spine sub-bullet is Veto item 4 word for word.

- mutation (review patch, the done band's setting and item guard): `settingResultView`'s `if (setting === '' || target === '' || after === '')` cut to `if (after === '')` -> `approval-view.test.mjs` red ("gives a done run that has an after but no setting or no item in the incident's change no band"). Reverted from a copy (`cmp` identical); the node files green again (174 passed).
- mutation (review patch, `ShownAfter` on a dry run that can't be read): the Catch branch of `ShownAfter` setting `after` to "x" -> `Test.Watch.SettingCause:TestRequestAfter` red ("ShownAfter gives empty for a dry run that can't be read, one with no after and a blank one, and the trimmed value otherwise"). Reverted from a copy (`cmp` identical); `TestRequestAfter` green again, then the warm stack was torn down.
- After the review patches: `Test.Watch.SettingCause` (whole class) passed warm on a rebuilt warm stack; `npm test` 2191 of 2191; `npm run lint` and `payloads.mjs --check` pass; `test-class-rules.sh` exit 0.

**Lead's runs (lane C, fresh stacks, tag e21dw1378ib):**
- `ci/iris.sh build` ok; `ci/iris.sh live cards`: 33 passed (A15 new; A11, A12 and A14 pass). `step5-cards.spec.ts` is in the `sign-in-2` project, part 3/5 of `web/scripts/e2e-part.mjs` (57 tests, 8 spec files): `ci/iris.sh live sign-in-2 --part 3/5` passed (57 passed; F6 and every F6b case pass).
- `bash docker/tests/test-boundaries.sh` exit 0; `bash docker/tests/test-class-rules.sh` exit 0.
- Spine lint (`lint_spine.py --workspace`): 13 low against the baseline's 12. The one new finding is the slot name `{after}` inside the AD-12 sub-bullet. Veto item 4 and the Planner's gate ruling approve that text word for word, so it cannot change; the check is a false positive on a catalog slot name in a code span, and it lists `{time}`, `{cause}` and others in the spine's existing text.
- Merge resolution check (Planner's override d): warm `Test.Msg.Catalog` (Watch count 147) and `Test.Watch.Summary` pass on the entry tree and on the implemented tree.

## QA Records (bmad-qa-generate-e2e-tests, 2026-11-16)

Gaps checked against the ACs and the I/O matrix. Already pinned by the implement stage, no test added: a token or URL value redacted as in the chat (`TestRequestAfter` row d, `TestTokenValueRestoredRaw`); a padded value trimmed (the direct `ShownAfter` assertion); the not-applied, changed-since and not-changed bands whatever the after (`approval-view.test.mjs`); an undo with no `after` shows no band and no error (both node files); other kinds carry no `after` (`TestRequestAfter` row f, `TestFromRowRequestKinds`). No product change; no new public text, stored-data shape or posture change; the approved AD-12 text and the catalog are untouched.

Tests added (real gaps):
- `Test.Watch.SettingCause:TestRequestAfterStates` (matrix row 10, row 1 trim): a pending, approved, executing, not-applied (failed) and done setting request each carry the dry run's after, trimmed; only the ended runs have a result; the padded done undo's band slots render to the chat's line.
  - mutation: the `Set part.After = ...` line of `Chosen` made `If request.State = "done" Set part.After = ...` -> `TestRequestAfterStates` red ("every state of a setting request carries its dry run's after, trimmed, and only an ended run has a result"). Reverted from a copy (`cmp` identical); the method and the whole class green again.
- `approval-view.test.mjs`, "gives a setting request that has not ended no band, whatever its after" (row 10: the pending card shows no result).
  - mutation: `resultView`'s `const result = request.result` made `request.result ?? (textOf(request.after) !== '' ? { completed: 1 } : undefined)` -> that test red. Reverted from a copy (`cmp` identical).
- `approval-view.test.mjs`, "keeps the band of a suspend or resume (DW-1373) as it is, though its request carries an after" (row 11 / DW-1373 unchanged): four results for both kinds, with and without a stray `after`.
  - mutation: the suspend/resume dispatch of `resultView` routed to `settingResultView` when the request has an `after` -> that test red. Reverted from a copy (`cmp` identical).
- `incident-view.test.mjs`, "an incident event with no after, as published before DW-1378, on the live page" (Veto item 3, the live event path through the real `applyEvents`, not only `/state`): the pre-change closed incident is applied and drawn with no error, a done rollback and undo give no band and a not-applied undo keeps its own band; the event that then carries `after` replaces the card in place and the band names it.
  - mutation: the live store's in-place replace `i === at ? item : entry` made `entry` -> "is replaced in place by the event that carries the after, and the band then names it" red.
  - mutation: `settingResultView` returns undefined first when the request has no `after` (the guard hoisted above the not-applied branch) -> "is applied and drawn with no error" red. Both reverted from copies (`cmp` identical).

Runs (lane C, tag e21dw1378qw, warm, torn down): `TestRequestAfterStates` passed; the whole `Test.Watch.SettingCause` passed (63.7 s). `cd web && npm test`: 2195 of 2195 (the 2191 of the implement stage plus four new). `npm run lint` passed; `test-class-rules.sh` exit 0. No browser spec touched, so no browser run. `git diff` holds no added non-ASCII character or absolute local path.

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 27 findings — high 0, medium 2, low 20, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the card's After and the chat's {after} come from two code paths (`ResultExtra` raw, `ShownAfter` own) — the spec forbids changing `IncidentManager`; both end in `Shown` of the same dry run's after, and `TestRequestAfter`, `TestUndoSystemDefaultChanged` and `TestTokenValueRestoredRaw` pin the equality.
  - `[low]` `[reject]` Blind: `TestRequestAfter`'s chat side is built from the dry run, not a real notice — by the spec's three layers; the real notices are compared in the Rollback tests.
  - `[low]` `[reject]` Blind: the Pin A `claimed` assertion is conditional and vacuous on the green path — it went red under the Pin A mutation, and the unconditional counts assertion (Completed 0, Skipped 1) carries the green path; grouped with the Verification-gap row on the same line.
  - `[false]` `[reject]` Blind: `RequestPart` reads an undefined `i` with no requests — ObjectScript's `For i = 1:1:0` sets `i` to 1 before the loop and the caller asserts `$IsObject(part)` first.
  - `[low]` `[reject]` Blind: the spine lint is 13 against a baseline of 12 although the override says add none — the new finding is the slot name `{after}` in the verbatim AD-12 sub-bullet that Veto item 4 and the gate approve word for word; no code fix exists, reported to the Planner.
  - `[false]` `[reject]` Blind: band and chat can disagree when the change row is missing — matrix row 9: no setting band, and the chat line is not contradicted.
  - `[low]` `[reject]` Blind: `ShownAfter` swallows a parse error silently and `Shown` sits outside its Try — an unreadable dry run means no band, as no chat line; `Redact.Text` does not throw; the Catch is now pinned by a direct assertion (see the patch below).
  - `[low]` `[reject]` Blind: a blank after has no server-side test — `Text` trims it to empty; the direct `ShownAfter` assertion added in the patch below covers it.
  - `[false]` `[reject]` Blind: a pending request publishes `After` — matrix row 10 says so.
  - `[low]` `[reject]` Blind: the AD-12 sub-bullet is silent on a missing `SettingChange` — the text is approved verbatim; the code's guard and the new test cover it.
  - `[false]` `[reject]` Blind: `Chosen`'s doc is one long line — the spec gives that text word for word.
  - `[low]` `[reject]` Blind: comment wording differs across three class docs — cosmetic.
  - `[low]` `[reject]` Blind: the case count of `playwright-projects.test.mjs` is hand-bumped — a pre-existing pattern; the file follows the new case.
  - `[low]` `[reject]` Edge: setting and target come from the incident's change, not the request's — Design Notes "Setting and target": the same row; a field for it would widen the part.
  - `[low]` `[reject]` Edge: `part.Result` may not be an object in the Pin A loop — the test would fail loudly, not hide a defect; the fixture run is ended.
  - `[low]` `[reject]` Edge: events published before the change give no done band until the next event or reload — Veto item 3, approved, no migration.
  - `[false]` `[reject]` Edge: `Plan`'s comparison applies to System Default undos only — a production-source undo writes its own After, so the item equals it; Pin A covers the branch that can differ.
  - `[medium]` `[patch]` Verification gap: no test reaches the setting/item guard with an `after` present — patched: a node test for no change, no setting and no item, for both kinds, with its mutation line.
  - `[low]` `[patch]` Verification gap: `assert.ok(!bandOf('rollback_setting', POOL, '1')?.text.includes('back to 7'))` cannot fail — patched: the line is deleted (it was this run's own addition).
  - `[low]` `[reject]` Verification gap: rows 1 and 2 of the table are green under the old code — the spec's rows; rows 3 and 4 discriminate.
  - `[medium]` `[patch]` Verification gap: `TestRequestAfter` compares two renders that could both be empty — patched: each row asserts the Render status, a non-empty text and the part's after in it.
  - `[low]` `[reject]` Verification gap: the Pin A `claimed` check is conditional — same row as the Blind finding above.
  - `[low]` `[patch]` Verification gap: the Catch branch of `ShownAfter` has no assertion — patched: a direct assertion on an unreadable, empty, blank and padded dry run, with its mutation line.
  - `[low]` `[reject]` Verification gap: no mutation line for AC 5's server half or AC 9 — AC 5 has its line on the pinning node test; AC 9 restates existing suites.
  - `[low]` `[reject]` Verification gap, other: the lint finding — same row as the Blind finding above.
  - `[low]` `[reject]` Verification gap, other: `playwright-projects.test.mjs` is outside the listed footprint — recorded; the file follows the new case and no assertion is removed.
  - `[low]` `[reject]` Intent alignment (descriptive): readings R1 to R5; the diff implements R1 with "no band" for a missing after; the layers are the spec's own three; no divergence from the intent.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The request part of a setting kind's `incident` payload (and `/api/v1/state`) carries `after`, the stored dry run's after through `Watch.SettingCause.ShownAfter` (`Shown`, the value of the chat's `{after}`). The done setting band names `request.after`, never the incident's recorded values, so the card says what the chat's result line says (the DW-1366 case says 9). A done run with no `after` has no band and no error.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls`: new `ShownAfter` and the class doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/IncidentRequest.cls`: new `After` property.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls`: `Chosen` fills `After` for the two setting kinds.
- `web/src/app/live/payloads.ts`: regenerated (`after?: string`).
- `web/src/app/approvals/approval-view.ts`: `settingResultView` reads `request.after`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the AD-12 sub-bullet, word for word.
- Tests: `Test/Watch/SettingCause.cls` (`TestRequestAfter`), `Test/Watch/Rollback.cls` (DW-1366 and token checks, Pin A), `Test/Live/Payloads.cls`, `web/scripts/approval-view.test.mjs`, `web/scripts/incident-view.test.mjs`, `web/e2e/cards/approval-card.spec.ts` (A15), `web/e2e/rail/step5-cards.spec.ts` (fixtures), `web/scripts/playwright-projects.test.mjs` (the cards case count, an unlisted file that follows A15).
- This spec.

**Review.** 27 findings: high 0, medium 2, low 20, false 5. Patched: 2 medium and 2 low (the done-band guard test, the unfalsifiable render comparison, a vacuous assertion removed, a direct `ShownAfter` assertion). Deferred: none. Every rejected finding and its reason is in the triage log. Follow-up review recommended: false (no high was patched, per the run's Rule 14 override; two medium test gaps were patched and each has a red-shown mutation).

**Verification.** See `## Verification`: warm classes (`SettingCause`, `Live.Payloads`, `Watch.Rollback` whole and per method after a production restart, `Web.Api`, `Msg.Catalog` 147 and `Watch.Summary`), `npm test` 2191 of 2191 with the bundle cap, lint, payloads `--check`, `live cards` 33 passed (A15 new), `sign-in-2` part 3/5 (F6, F6b) 57 passed, the two docker scripts exit 0, every mutation red then reverted with `cmp`.

**Residual risks.**
- The spine lint shows 13 low against the baseline's 12: the slot name `{after}` in the verbatim AD-12 sub-bullet (a false positive; the text is approved word for word).
- Events published before this change carry no `after`, so a done setting band is absent for them until the next `incident` event or state load (Veto item 3).
- `Test.Watch.Rollback` needs the production to hold the new code (a production restart on a warm stack).
