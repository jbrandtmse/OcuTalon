---
title: "Story 41.2: The precedent table, its one writer, and the routes"
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: '2dc21d010f006e2b354402252b6cf4c0951cf6e5'
baseline_commit: '2dc21d010f006e2b354402252b6cf4c0951cf6e5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-41-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      The noise route's 200 success body (markedAt), its already_marked answer, the phone-versus-web body mapping and the 409 are not run over real HTTP.
    evidence: |-
      memory.spec.ts sends POST noise only for an unknown ref (404), as the spec's task list asks. The slot-safe tests pin the other answers through the SubmitMemory seam and the production test pins Commands.Submit. A Decision and Item fixture over HTTP would close it; Story 41.5 builds the notice-card press and can add it.
    location: >-
      web/e2e/api/memory.spec.ts
    severity: low
---

<intent-contract>

## Intent

**Problem:** Memory's first part needs Lane B's half: a table of a person's own answers, one operation that is its only writer, the two web verbs, the four routes, and the eval-seeding path that the 2026-11-08 AD-21 amendment gives Story 41.7. Without it, nothing can record "This was noise" or an approval answer, and nothing can guarantee that only a person's answers become precedents.

**Approach:** Add `OcuTalon.Data.Precedent` (with `KeyFor`, `Similar` and `Purge`), the `DailyNote.Build` stub, and the business operation `PrecedentOps`. `PrecedentOps` takes six message classes, each from one named sender: `MarkNoise` and `ForgetPrecedent` (from `CommandsIn`, origin `web_user`), `RecordPrecedent` (from `AnswerOps`), `EndSession` (from `SessionOps`), and `SeedPrecedent` and `RemoveSeededPrecedents` (from `EvalIn`, and only while the eval switch is on). Add the verbs' routes in `CommandsIn`, the drop step of `SessionOps.End`, two `Ownership` row kinds, and the four `Web.Api` routes. Prove it with slot-safe unit tests, one production test, and one Playwright API spec over real HTTP.

## Boundaries & Constraints

**Always:**
- **One writer.** Only `PrecedentOps` inserts or deletes `Precedent` rows. The one exception is `Precedent.Purge`, which the daily task runs through `Install.Step.Core.Purge` (AD-27).
- **Senders are checked.** Every message must come from its named sender (`..%RequestHeader.SourceConfigName`). The two verbs must also carry `Origin` `web_user`.
- **The eval guard.** The seed and remove messages also need `PrecedentOps.EvalOn()` to be 1. Anything refused writes nothing.
- **Eval rows are separate.** A seeded row has `OwnerRef` `eval` and `EvalRunRef` set to the run's Ref. `Similar` returns seeded rows only when it is asked for owner `eval`. `Ownership`'s precedent reads and every route return none of them.
- **Owner-scoped reads.** Routes read only through `Ownership` (AD-4, AD-13), using the session that `Ownership.SessionRef` resolves. A record the session can't see answers 404 before anything is submitted.
- **Storage and source rules.**
  - Storage is append-only, and every new persistent class and message class carries its compiler-generated `Storage` block (AD-5).
  - `DEFAULTGLOBAL` is `^OcuTalonP.Precedent`, and a row is added to `src/short-names.tsv` (AD-3).
  - Source is ASCII, and comments state the contract only (Rule 14).
- **Public text.** Every user-facing string is an existing one or is listed under PUBLIC TEXT in Design Notes. The `PrecedentOps` messages are for logs only, as `SessionOps` documents for its own.
- **Lane B files only.** The contended files are touched only as stated:
  - `Production.cls`: one item, in Lane B's region only.
  - `Test/Contract/Ac.cls`: one inserted block.
  - `src/short-names.tsv`: one appended row.
  - `Ownership.cls`: only after the Clarification below is cleared.

**Never:**
- Write a precedent from a decision, a model reply, a tool, an arriving item, `BridgeSink`, `Intake` or any route directly.
- Edit `Agent/**`, `Eval/**`, `Test/Agent/**`, `Test/Eval/**`, `Msg/Enum.cls`, `ci/units.sh`, `release/**`, `eval/run.sh`, IPM scripts, the spine or EXPERIENCE.md.
- Render any precedent or note into a request (that is Story 41.4), build the real daily note (Story 41.3), send `RecordPrecedent` from `AnswerOps` (Story 41.5), or build any web UI (Stories 41.5 and 41.6).
- Add an SQL prepare without the privilege check outside `Ownership.Rows`, and add no role or grant.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Noise marked | MarkNoise {DecisionRef of the session's own `decide` decision, outcome `tellnow` or `act`, untrusted mail Item `Zz <Zz.A@Example.com>`, Channel phone}, from CommandsIn, origin web_user | Ok 1 `marked`, Ref; Data `{"answeredAt"}`. One row: owner = the session, Channel mailbox, MatchKey `zz.a@example.com`, Summary and Outcome from the Decision, Answer noise, AnsweredChannel phone, SourceRef = the DecisionRef, EvalRunRef "" | No error expected |
| Noise repeat | the same DecisionRef again (also a lost unique-index race) | Ok 1 `already_marked`, the first row's Ref and answeredAt | no second row |
| Not markable | another session's decision; a `digest` or `ignore` decision; a `turn` decision; the decision of an Item with provenance `user`; a DecisionRef that is not a ref | Ok 0 `not_found` | nothing written |
| Item purged | the Decision exists, but no `OcuTalon.Msg.Item` with its ItemId is in its TraceSessionId | Ok 0 `too_old` | nothing written |
| Forget | ForgetPrecedent {PrecedentRef of the session's own row} | Ok 1 `forgotten`; the row is gone, and `Similar` and the list lose it at once (DW-921) | another session's row or an eval row: `not_found`, and the row stays |
| Approval answers | RecordPrecedent {ApprovalRef, Action approve or reject, Channel, SessionRef}, from AnswerOps. The request is visible to the session (`Ownership.Approval`) | `fix`: one row with MatchKey `production:<ns>/<name>` of its incident, Channel system, Summary = the incident Decision's Summary, Answer approved or rejected. `tool_call`: MatchKey `tool:<ToolName>`, Channel "", Summary = ToolName. For both: Outcome "", SourceRef = the request's Ref, AnsweredAt = the request's AnsweredAt (else now), AnsweredChannel = the message's Channel when it is a CHANNEL value | `setting`, a bad Action, an unknown request or session, or a repeat: no row (`not_recorded` / `already_recorded`) |
| Wrong sender or origin | a verb sent directly (not by CommandsIn) or with origin tool, timer, web_admin or ""; RecordPrecedent not from AnswerOps; EndSession not from SessionOps | Ok 0 `not_allowed`, and one warning is logged | nothing written |
| Unknown class | a Msg.Item, an ItemDecision, a GotIt, or a message that is not an object | an error status is logged | nothing written |
| Tool origin | MarkNoise or ForgetPrecedent through CommandsIn with origin tool, or with web_user inside a bridge context | `not_allowed` with MESSAGENOTFROMTOOL, and nothing reaches PrecedentOps | — |
| Seeding | SeedPrecedent {RunRef, Channel, MatchKey, Summary, Outcome, Answer, AnsweredAt} from EvalIn, with `EvalOn()` 1 | Ok 1 `seeded`, Ref. The row has owner eval, EvalRunRef = RunRef, SourceRef = its own Ref, and AnsweredAt as given (else now) | from another sender, with EvalOn 0, an empty RunRef or MatchKey, or a bad Answer, Channel or Outcome: `not_allowed` or `not_valid`, and nothing written |
| Seed removal | RemoveSeededPrecedents {RunRef} from EvalIn, with EvalOn 1 | Ok 1 `removed`, Data `{"count"}`. Only that run's rows are deleted | same guards as seeding |
| Person beside a run | seeded rows with the same Channel and MatchKey as a person's own row | `Similar(person, ch, key)` = only the person's row. `Similar(eval, ch, key)` = only the seeded rows. `Ownership.Precedents(person)` and `GET /v1/memory/precedents` show none of the seeded rows | — |
| Similar bounds | 5 rows with the same key; limit 0, 1, 3 or 7; an empty owner, channel or key | newest first, at most `min(limit, 3)`; [] for limit < 1 or any empty argument. Each item is `{ref, answeredAt, channel, answeredChannel, summary, outcome, answer}` | — |
| KeyFor | `mailbox`/`email`: `Name <A@B.c>` gives `a@b.c`, and a bare `A@B.c ` gives `a@b.c`. `webhook`/`slack` Sender ` Src ` gives `src`. `heartbeat` gives `heartbeat`. `system` with `Slots.production` = the DisplayName of exactly one of the item's session's production BackgroundChecks gives `production:<Namespace>/<Production>` | "" for provenance `user`, no object, an unknown channel, or a `system` item with zero or two matching checks | — |
| Sign-out drop | SessionOps.End for a session with rows | one EndSession to PrecedentOps; that session's rows are deleted, and another session's and eval rows stay | a failed drop counts as a failed step, so the resume hash is kept; no rows means nothing is sent |
| Purge | rows answered 10 and 100 days ago; `Purge(90)`; `Purge(0)`, `Purge("x")` | the 100-day row (eval included) is deleted, and the 10-day row stays | a bad day count is an error status, and nothing is deleted |
| Routes | signed out; GET precedents; DELETE `/precedents/:ref`; POST `/decisions/:ref/noise` with body `{"channel":"phone"}`, any other body, or none; GET `/notes?day=today`, `yesterday`, `zz` or no day | 401 `signed_out`. List: 200 `{"precedents":[...]}`, newest first, at most 100. Delete: 200 `{"result":"done"}`. Noise: 200 `{"result":"done","markedAt"}`, with channel phone only for that exact body and web otherwise. Notes: 200 `{"day","date","lines":[]}`, with `date` the instance-zone YYYY-MM-DD | an unseen ref or an unknown day: 404 `not_found` (MESSAGENOTFOUND). `too_old`: 409 `too_old` (PUBLIC TEXT). `not_built`: 501. Anything else: 500 `server_error` |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless given in full.

**New classes**
- `Data/Upload.cls`, `Data/Handled.cls`: the sibling tables to follow: EXACT-collation Refs, `DEFAULTGLOBAL`, `DropSession` by SQL, `DeleteAll`/`NOTFOUND` 5810, and the storage block shape.
- `Data/Pairing.cls:214-239` `Purge`: the day-count rule and date arithmetic to copy for `Precedent.Purge`.
- `Core/SessionOps.cls`: the operation pattern for `PrecedentOps`.
  - `OnMessage` class dispatch at 80-96.
  - `GotIt` at 251-276: `Ownership.Decision`, exact Ref compare, `Bridge.Approval.IsRef`, first-wins on a unique index, `Result` and `Failed`.
  - Messages documented as log-only at 51.
- `Core/AnswerOps.cls:35-45`: the sender check through `..%RequestHeader.SourceConfigName` and the `SENDER` parameter.
- `Install/Step/Production.cls:32-33,296-307`: `PRODUCTION` and `EVALITEM`. `SetEval` writes the System Default Setting row `(OcuTalon.Production, EvalIn, *, Enabled)` from `OCUTALON_EVAL` at every start, and line 179 reads such a row with `Ens.Config.DefaultSettings.%GetSetting(...)`. This is `EvalOn`'s source.
- `Msg/Command/GotIt.cls`, `ForgetMemory.cls`: the verb class shape. `Core/Msg/RunTurns.cls` is the `Core.Msg` message shape (extends `Ens.Request`).
- The data `PrecedentOps` reads:
  - `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls`: `Kind`, `ItemId`, `OwnerRef`, `Summary` (80), `Outcome`, `TraceSessionId`. `TraceSessionId` is Decide's `..%SessionId`, which is Intake's session, and Intake keeps the Item's inbound header session (`Core/Intake.cls:140-146`; inference, pinned by the production test).
  - `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls`: `Kind`, `IncidentRef`, `ToolName`, `AnsweredAt`.
  - `Data/Incident.cls`: `Namespace`, `Production`, `DecisionRef`.
  - `Data/BackgroundCheck.cls`: `SessionRef`, `Kind`, `Namespace`, `Production`, `DisplayName`.
- `Checks/Process.cls:594-606`: a finding Item is channel `system` with `Slots.production` holding the check's display name, not its namespace. That is why `KeyFor` looks up the check.
- `Channel/SimMailbox/In.cls:142-150`: a mail Item keeps the Sender as typed (for example `Name <addr>`).

**Changed files**
- `Core/CommandsIn.cls:186-210`: the `Routes` XData. Append two entries after line 208 (the comma goes on 208), and update the class comment and the Routes comment. Not contended.
- `Core/SessionOps.cls`:
  - `End` at 283-301. The step sum is at 298; add `EndPrecedents` after `EndHandled`.
  - The step pattern is `EndHandled`/`DropHandled` at 405-438, and `Carry` is at 464-482.
  - The class comment's EndSession bullet is at 16-24.
- `Web/Api.cls`:
  - Insert the routes after line 185 (`/v1/heartbeat/run`).
  - Add `MESSAGETOOOLD` after line 143.
  - Route patterns: `DismissIncident` at 661-693 (404 first, submit, map outcomes), `GetPersona` at 1266-1277, and the seam pattern `SubmitPersona`/`SubmitHeartbeat` at 1362, 1509.
  - Comments: the header bullets at 1-70.
- `Data/Ownership.cls`. Contended by Epic 17, which changes lines 40, 413-414 and 910-911; see the Clarification.
  - Insert a comment bullet after 46.
  - Add `Precedents` and `Precedent` after `FinishedToolCalls` (655-667).
  - Add two `Statement` kinds after the `upload` kind (976-979), before `Quit ""` at 980.
  - `Decision` (507) and `Approval` (518) are the find pattern.
- `Install/Step/Core.cls:8-11`: `Purge` also calls `Precedent.Purge`. Both run, and the first error is returned (the pattern of `Install/Step/Web.cls:124-132`).
- `Production.cls:94-95`: insert the item before `<!-- lane B: end -->`.
- `src/short-names.tsv`: append `Precedent	^OcuTalonP.Precedent	OcuTalon.Data.Precedent	B`.

**Tests to update (shared surfaces)**
- `Test/Web/Api.cls:953-957` `TestRoutes`: 25 routes become 29.
- `Test/Core/ProductionItems.cls:38`: append a row after PartnerTrigger.
- `Test/Data/Tables.cls`: a `Contracts` entry and a `Registry` row (`TestEveryTableIsRegistered` needs one for every `OcuTalon.Data` persistent class).
- `Test/Msg/Contracts.cls:42`: the verbs list, plus contract entries for the two verbs.
- `Test/Contract/Ac.cls:381-382` `Signatures`: insert one block between the `OcuTalon.Docs` and `OcuTalon.Memory` rows, so no existing line changes. Epic 19 edits line 361.

**Test patterns**
- `Test/Core/GotIt.cls` and `GotItProbe.cls`: probe seams and per-test fixture cleanup.
- `CommandsHeartbeat.cls`: the origins and tool-refusal oracle, through `CommandsInProbe` and `CommandsOwner`.
- `SessionOpsDropProbe.cls` and `SessionOpsDocuments.cls`: the End step.
- `InProduction.cls` and `GotItProduction.cls`: tests that need the running production.
- `Test/Data/Fixture.cls`: `Session`, `Decision(owner, kind, at, fields)`, `Approval`, `Incident`, `Check`, `Header`, `Clean`.
- `Test/Data/Ownership.cls:454-560` (isolation and `TestRowsRefuses`) and `OwnershipProbe.Call`.
- `Test/Web/PersonaApiProbe.cls` and `PersonaApi`: route tests with stand-in requests.
- `ci/mock/scenarios/B/mail-tell-now.json`: the marker `[[mock:mail-tell-now]]` makes the mock answer `tellnow`.
- `web/e2e/api/persona.spec.ts`: Rule 3 over real HTTP, with `signInOverHttp`, `envelope`, `expectError`, `irisScript`/`chk` and `support/persona.ts` `sessionRef()`. The spec joins the `chromium` project, which `live:sign-in` runs.

## Tasks & Acceptance

**Execution:**

**1. Messages and verbs**
- `src/ocutalon/cls/OcuTalon/Msg/Command/MarkNoise.cls` and `ForgetPrecedent.cls`: two new verbs, extending `OcuTalon.Msg.Command`.
  - `MarkNoise` has `DecisionRef` (22) and `Channel` (32).
  - `ForgetPrecedent` has `PrecedentRef` (22).
- `src/ocutalon/cls/OcuTalon/Core/Msg/RecordPrecedent.cls`, `SeedPrecedent.cls` and `RemoveSeededPrecedents.cls`: three new messages, each extending `Ens.Request` with `RESPONSECLASSNAME` `OcuTalon.Msg.CommandResult`.
  - `RecordPrecedent`: `ApprovalRef` (22), `Action` (32), `Channel` (32), `SessionRef` (22).
  - `SeedPrecedent`: `RunRef` (22), `Channel` (32), `MatchKey` (512), `Summary` (80), `Outcome` (32), `Answer` (32), `AnsweredAt` (20).
  - `RemoveSeededPrecedents`: `RunRef` (22).

**2. The table, the stub and the operation**
- `src/ocutalon/cls/OcuTalon/Data/Precedent.cls`: a new `%Persistent` class.
  - Properties: `Ref`, `OwnerRef`, `MatchKey`, `SourceRef` and `EvalRunRef` (EXACT collation), plus `Channel`, `Summary` (80), `Outcome`, `Answer`, `AnsweredAt` (20) and `AnsweredChannel`.
  - Indexes: `RefIndex` unique, `SourceRefIndex` unique, `OwnerRefIndex`, and `OwnerKeyIndex (OwnerRef, Channel, MatchKey)`.
  - Parameters: `ANSWERS` "noise,approved,rejected", `SIMILARMAX` 3, `NOTFOUND` 5810.
  - Methods:
    - `KeyFor(item)`, the matrix row. It is a read and runs in production jobs only.
    - `KeyForRequest(request)`, the fix and `tool_call` forms.
    - `Similar(ownerRef, channel, matchKey, limit = 3) As %DynamicArray`, a checked SQL prepare.
    - `View(row) As %DynamicObject`.
    - `Has(sessionRef)`.
    - `DropSession(sessionRef)` (it skips eval rows).
    - `RemoveRun(runRef)`.
    - `Purge(daysToKeep)`, using Pairing's rule.
  - The class comment names its writer and readers.
- `src/ocutalon/cls/OcuTalon/Data/DailyNote.cls`: a new class (not persistent). `ClassMethod Build(sessionRef As %String, day As %String) As %String` returns "" (a stub until Story 41.3), where `day` is a local YYYY-MM-DD.
- `src/ocutalon/cls/OcuTalon/Core/PrecedentOps.cls`: a new `Ens.BusinessOperation`.
  - Sender parameters: `COMMANDSENDER` CommandsIn, `ANSWERSENDER` AnswerOps, `SESSIONSENDER` SessionOps, `EVALSENDER` EvalIn.
  - Dispatch: `OnMessage` dispatches by class, as `SessionOps` does. Each handler implements the matrix and answers a `CommandResult`. A throw is logged and answers `failed`.
  - `ClassMethod EvalOn() As %Boolean`: 1 only when `%GetSetting(Install.Step.Production #PRODUCTION, #EVALITEM, "OcuTalon.Eval.In", "", "Enabled", .v)` finds a row and `v` = 1.
  - Private seams for the probe: `ItemOf(decision)` (the Ens.MessageHeader rows of the decision's `TraceSessionId` with `MessageBodyClassName` `OcuTalon.Msg.Item`, opened and compared by `ItemId`, else ""), `SaveRow(row)` and `Source()`.
  - The class comment lists the six accepted messages with their senders: AD-21 as amended (DW-921 for `ForgetPrecedent`), and AD-1.

**3. Wiring**
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`: add the routes `{"verb":"MarkNoise","owner":"PrecedentOps","origins":"web_user"}` and the same for `ForgetPrecedent`, plus their comment lines. They are not tool verbs.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls`: add `Parameter PRECEDENTITEM = "PrecedentOps"`.
  - `EndPrecedents(command)`: when `Precedent.Has` is 0 it does nothing; otherwise it sends one new EndSession {SessionRef, Origin} through the private seam `DropPrecedents(request)`, which calls `Carry`.
  - Add it to `End`'s sum and to the class comment.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`. This step waits for the Clarification below.
  - `Precedents(sessionRef, max = 100, .sc) As %ListOfObjects`: kind `precedents`, binds `ao`: `SELECT TOP ? p.ID FROM OcuTalon_Data.Precedent p WHERE p.OwnerRef = ? AND p.EvalRunRef IS NULL ORDER BY p.AnsweredAt DESC, p.ID DESC`.
  - `Precedent(ref, sessionRef, .sc)`: kind `precedent`, binds `ao`: `... WHERE p.Ref = ? AND p.OwnerRef = ? AND p.EvalRunRef IS NULL`.
  - One comment bullet.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: four routes.
  - `POST /v1/decisions/:ref/noise` calls `MarkNoise`.
  - `GET /v1/memory/precedents` calls `Precedents`.
  - `DELETE /v1/memory/precedents/:ref` calls `ForgetPrecedent`.
  - `GET /v1/memory/notes` calls `Notes`.
  - Each takes its session from `Ownership.SessionRef`. The noise route first checks `Ownership.Decision`, and the delete route first checks `Ownership.Precedent`.
  - Both writes go through one private seam, `SubmitMemory(command, .result)`, which calls `Commands.Submit` with origin `web_user`. The outcome mapping is the matrix row.
  - Add `Parameter MESSAGETOOOLD` (PUBLIC TEXT) and a header comment bullet.
- `src/ocutalon/cls/OcuTalon/Install/Step/Core.cls`: `Purge` also calls `Precedent.Purge(daysToKeep)`.
- `src/ocutalon/cls/OcuTalon/Production.cls`: insert `<Item Name="PrecedentOps" ClassName="OcuTalon.Core.PrecedentOps" PoolSize="1" Enabled="true"/>` before `<!-- lane B: end -->`.
- `src/short-names.tsv`: append the row.

**4. Existing tests to update**
- `Test/Web/Api.cls` `TestRoutes`: 29 routes, with the four inserted after `POST /v1/heartbeat/run RunHeartbeat`, in Url-map order.
- `Test/Core/ProductionItems.cls`: append the `PrecedentOps` row (pool 1, enabled 1, stub 0).
- `Test/Data/Tables.cls`: add the `Contracts` entry for `OcuTalon.Data.Precedent` and its `Registry` row.
- `Test/Msg/Contracts.cls`: append `"MarkNoise", "ForgetPrecedent"` to the line-42 list, and add their two contract entries.
- `Test/Contract/Ac.cls`: insert, before the `OcuTalon.Memory` row:
  - `{"class": "OcuTalon.Data.Precedent", "method": "KeyFor", "args": "item", "returns": "%String"},`
  - `{"class": "OcuTalon.Data.Precedent", "method": "Similar", "args": "ownerRef,channel,matchKey,limit", "returns": "%DynamicArray"},`
  - `{"class": "OcuTalon.Data.DailyNote", "method": "Build", "args": "sessionRef,day", "returns": "%String"},`

**5. New tests** (every test removes its own rows by Ref; nothing depends on run order)
- `Test/Data/Precedent.cls`, safe on a slot: the KeyFor, Similar bounds and Purge rows, `DropSession`, `RemoveRun`, `Has`, the stub, and `Install.Step.Core.Purge(36500)` deleting a row answered in 1900. It also extends `Test.Contract` to pin the three `Core.Msg` contracts with `AssertContract`.
- `Test/Data/OwnershipPrecedents.cls`, safe on a slot:
  - Two sessions read none of each other's rows through both kinds, and eval rows are never visible.
  - Both kinds refuse an empty owner and the owners `eval` and `instance` through `Test.Data.OwnershipProbe.Call`.
- `Test/Core/PrecedentOps.cls` with `PrecedentOpsProbe.cls`, safe on a slot: every `PrecedentOps` row of the matrix, the "Person beside a run" pin, and `EvalOn`.
  - The test sets the header's `SourceConfigName`.
  - For `EvalOn`, it writes the System Default Setting row to 1 and 0, deletes it, and puts back the row it found.
  - One test pins the real `ItemOf` with a saved fixture Item and an `Ens.MessageHeader` that it removes.
  - It also pins "a decision.recorded path writes no row": `BridgeSink.OnEvent("decision.recorded", owner, {"ref"})` for a tellnow decide decision leaves no row.
- `Test/Core/CommandsPrecedent.cls`, safe on a slot (the `CommandsHeartbeat` pattern): every origin, `zz` and "" for both verbs, and the tool and bridge-context refusal (the governance test of AD-1).
- `Test/Core/SessionOpsPrecedents.cls` with `SessionOpsPrecedentsProbe.cls`, safe on a slot: the Sign-out drop row. The probe's `DropPrecedents` records, then calls `##super`, errors or throws.
- `Test/Web/MemoryApi.cls` with `MemoryApiProbe.cls`, safe on a slot: every Routes row except signed out (the 401 comes from ApiBase), through the `SubmitMemory` seam, with real `Ownership` reads.
- `Test/Core/PrecedentOpsProduction.cls` (extends `InProduction`; throwaway stacks and CI only). It creates `SimMailboxIn` as `Web.Api` does and hands it a Mail from `Zz Prec <Zz.Prec@Example.com>` whose body holds `[[mock:mail-tell-now]]`. Then:
  - it waits for the session's decide Decision of that ItemId with outcome tellnow, and checks that the session has no Precedent row;
  - `Commands.Submit(MarkNoise, "web_user")` answers `marked`, and the row's MatchKey is `zz.prec@example.com` with Channel mailbox;
  - `Similar` and `Ownership.Precedents` return it;
  - a repeat answers `already_marked`;
  - `Commands.Submit(EndSession, "web_user")` leaves the session with no rows.
- `web/e2e/api/memory.spec.ts`, Rule 3 over real HTTP:
  - each route answers 401 when signed out;
  - signed in as the README account, GET lists a row seeded through `irisScript` and does not list a seeded row of owner eval;
  - DELETE of the listed row is 200, and the list is then empty;
  - DELETE and POST noise of an unknown ref are 404;
  - `notes?day=today` is 200 with `lines` [], and `day=zz` is 404;
  - in `finally` it removes the rows it seeded.

**Acceptance Criteria:**
1. **The table and the reads.** Given the compiled classes, when `Test.Data.Precedent`, `Test.Data.Tables` and `Test.Contract.Ac` run, then `Precedent` has its storage block, `DEFAULTGLOBAL` and registry row, and `KeyFor`, `Similar`, `Purge` and the stub behave as in the matrix (the KeyFor, Similar bounds and Purge rows), with their signatures pinned (AD-3, AD-5, AD-21, AD-27).
2. **The one writer.** Given `PrecedentOps`, when `Test.Core.PrecedentOps` sends each message class from each sender, then only the accepted senders, origins and switch state write. Every other combination answers `not_allowed`, or an error for an unknown class, and writes no row. A `decision.recorded` event and a tool-origin MarkNoise also leave no row (FR-72, AD-1, AD-21 as amended).
3. **The verbs.** Given `CommandsIn`, when `Test.Core.CommandsPrecedent` submits `MarkNoise` and `ForgetPrecedent` from every origin, then they reach `PrecedentOps` from `web_user` only. Origin `tool`, and `web_user` inside a bridge context, answer `not_allowed` with nothing sent (AD-1).
4. **Marking, recording and forgetting.** Given fixture decisions and approval requests, when `Test.Core.PrecedentOps` runs, then the rows Noise marked, Noise repeat, Not markable, Item purged, Forget (DW-921) and Approval answers hold (DW-922: `tool:<ToolName>`, never read in this release).
5. **The eval seeding.** Given seeded rows beside a person's rows, when `Test.Core.PrecedentOps` runs the Seeding, Seed removal and Person beside a run rows, then a person's `Similar`, `Ownership.Precedents` and `GET /v1/memory/precedents` see no seeded row, and `EvalOn()` follows the System Default Setting row (AD-21 amended 2026-11-08, AD-22).
6. **The routes.** Given a signed-in session, when `Test.Web.MemoryApi` runs and `web/e2e/api/memory.spec.ts` sends real HTTP requests, then every Routes row holds, and only the session's own non-eval rows are listed or deleted (AD-4, AD-13, Rule 3).
7. **Sign-out.** Given `SessionOps.End`, when `Test.Core.SessionOpsPrecedents` runs, then the Sign-out drop row holds. The existing `Test.Core.SessionOps`, `GotIt` and `SessionOpsDocuments` stay green, because a session with no rows sends nothing (AD-4).
8. **Integration.** Given the running production, when `Test.Core.PrecedentOpsProduction` puts a tell-now email through the real mail path, then:
   - the real decision writes no row;
   - the real `PrecedentOps` writes one noise row for `MarkNoise`, keyed by the sender's address, which proves `ItemOf` on the real `TraceSessionId`;
   - the consumers `Precedent.Similar` and `Ownership.Precedents` return it;
   - the real `SessionOps.End` removes it.
9. **The production item.** Given `Production.cls`, when `Test.Install.Production` and `Test.Core.ProductionItems` are read, then `PrecedentOps` is in Lane B's region and the oracle matches (AD-33).

### Review Findings

Code review 2026-11-08 (full mode; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; no AD mismatch, no HIGH; Rule 3 met by `memory.spec.ts` over real HTTP).

- [x] [Review][Patch] (med) `memory.spec.ts` asserted on the README account's whole precedent list (`toEqual([own])`, then `[]`) and on any eval row with the key, so other rows of the account turned it red (Rule 19 hermeticity): now only the test's own Refs are asserted on, and the seeded and deleted rows are checked by Ref [web/e2e/api/memory.spec.ts:103]
- [x] [Review][Patch] (low) `ItemOf` answered "" on a failed header read, so a read error reached the person as 409 `too_old`: it now throws, which `OnMessage` logs and answers `failed` [src/ocutalon/cls/OcuTalon/Core/PrecedentOps.cls:268]
- [x] [Review][Patch] (low) `EvalOn`'s comment claimed only the `(…, EvalIn, *, Enabled)` row counts: corrected to the item's resolved setting, as `%GetSetting` resolves it [src/ocutalon/cls/OcuTalon/Core/PrecedentOps.cls:91]
- [x] [Review][Patch] (low) `SessionOps.End`'s method comment did not list the precedents step [src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:284]
- [x] [Review][Patch] (low) no test showed the precedents step still runs after an earlier step fails, and the "a later step still ran" label named a step that runs first: added `TestDropAfterEarlierFailure` (the probe now extends `Test.Core.SessionOpsProbe` for `SettingsAnswer`) and relabelled the assertion [src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsPrecedents.cls]
- [x] [Review][Patch] (low) `TestSenders` did not count rows of the run, so a wrong-sender `SeedPrecedent` row was invisible to its "no row was written" check [src/ocutalon/cls/OcuTalon/Test/Core/PrecedentOps.cls:347]
- [x] [Review][Defer] (med) `Record` trusts `RecordPrecedent`'s Action and never compares it with the request's `AnsweredAction` [src/ocutalon/cls/OcuTalon/Core/PrecedentOps.cls:152] — deferred: DW-933, routed to 41-5 (its `AnswerOps` sender makes it reachable)
- [x] [Review][Defer] (med) a precedent written after sign-out survives End (`Has` is read before a queued write lands; `Record` accepts an ended session) [src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:429] — deferred: DW-934, routed to 41-5 (the async sender)
- [x] [Review][Defer] (low) `Similar("eval", …)` spans every run's seeded rows [src/ocutalon/cls/OcuTalon/Data/Precedent.cls] — deferred: DW-935 wontfix-accepted (the signature is pinned by the spec)
- [x] [Review][Defer] (low) `Install.Step.Core.Purge` returning the precedent purge's error is not pinned [src/ocutalon/cls/OcuTalon/Install/Step/Core.cls:9] — deferred: DW-936 wontfix-accepted (needs a failure seam)
- [x] [Review][Defer] (low) the notes route's call of `DailyNote.Build` is not pinned while `Build` is a stub [src/ocutalon/cls/OcuTalon/Web/Api.cls] — deferred: DW-937 wontfix-accepted (41.3 replaces the stub)
- [x] [Review][Defer] (low) the noise route's 200/409/phone mapping over real HTTP [web/e2e/api/memory.spec.ts] — deferred: DW-932 occurrence (owned by 41-5)
- [x] [Review][Defer] (low) `Precedent.Purge` repeats the day-count check and UTC cutoff of `Pairing.Purge` (Rule 2; the Code Map asks for the copy) [src/ocutalon/cls/OcuTalon/Data/Precedent.cls:216] — deferred: DW-371 occurrence

Rejected:
- (by-design) "This was noise" on a heartbeat or check notice older than the 7-day message retention answers `too_old`: the matrix's Item purged row and the approved text.
- (by-design) `KeyFor` gives "" for a finding whose check was renamed or duplicated: the matrix's KeyFor row.
- (low) `Alerts <>` and an unterminated `<` give odd keys: outside the spec's normalization rule, no realistic sender.
- (false) the class comment's "first seven steps" miscounts: it keeps the baseline's convention, where the documents step is documented on its own line.
- (false) `EvalOn` matching a wildcard or class-specific row: that is how the running item resolves its own Enabled (the same call as `Install.Step.Production:179`); the comment is patched above.
- (wontfix-theoretical) `Carry` takes `not_allowed` (Ok 0) as success: real only if `PrecedentOps` or `SessionOps` is renamed, which `Test.Core.ProductionItems` pins.
- (by-design) `Similar` never returns `tool:` rows with an empty channel: DW-922.
- (low) CRLF in note text: the builder is a stub; 41.3 owns the format.
- (false) the run Ref cut from `Date.now()` can collide: it only labels the seeded row, which is removed by Ref.
- (false) ACs whose named tests have no mutation of their own: each AC 1-9 has a recorded mutation, one per AC.
- (by-design) `TestPurge` purges across the namespace: the spec's own `Purge(90)` and `Purge(36500)` calls.
- (wontfix-theoretical) `PutBackEval` keeps a leftover row at 1: real only after a crashed run, on a stack that runs `EvalIn`.
- (low) `Fixture.Clean()` with no arguments: the repository's convention (68 uses).
- (low) `SessionOpsPrecedentsProbe` does not call `##super`: no production runs on a slot, and AC 8's production test runs the real `DropPrecedents` and `Carry`.
- (low) `SubmitMemory` and `DeleteWhere` resemble siblings: the spec states the reasons, and `SubmitMemory` is the class's one-line per-feature seam.

## Spec Change Log

- 2026-11-08 (rulings relayed by the orchestrator; Contest Planner under the owner's delegation):
  - **PUBLIC TEXT, APPROVED word for word:** `Web/Api.cls` `Parameter MESSAGETOOOLD = "This notice is too old to mark as noise. Nothing was changed.";`, the body of the noise route's 409 `too_old` answer. The same words are 41.5's notice-card catalog line (DW-923, one ruling). Pin it with a fixed string (a test-held copy compared with the parameter, and the route's 409 body asserted against that copy).
  - **`Data/Ownership.cls` RULED (decide):** the three insertions (comment bullet after line 46; `Precedents`/`Precedent` after line 667; two `Statement` kinds after line 979) are allowed. They are a plain union with Epic 17's hunks (lines 40, 413-414, 910-911), done by whichever epic merges second. The `## Clarification Needed` below is cleared; the step that waited on it proceeds.
  - **DW-921 closed `by-design`** (by owner ruling): the amendment's restated `ForgetPrecedent` and sign-out removal are consistent with AD-1. This story still builds the `ForgetPrecedent` handling its ACs require.
- 2026-11-08 (spec gate, lead): the AD-21 amendment (Contest Planner ruling under the owner's delegation; U7 step 2, light path) is written into the spine in the same bookkeeping commit as this spec: a third bullet under AD-21's "accepts only" list, marked `[AMENDED 2026-11-08, Story 41.7 (planned at 41.2), Contest Planner ruling under the owner's delegation; DW-920, DW-921]`, naming `SeedPrecedent` / `RemoveSeededPrecedents` from `EvalIn` only while `OCUTALON_EVAL=1`, the eval-seeded mark, removal through `PrecedentOps`, no product read of eval rows, and `PrecedentOps`' removals on `ForgetPrecedent` (`web_user`) and at sign-out. The two "Spine lines for the lead" (AD-29's "Epic 41's names, as built" sub-bullet and the cross-area row) are written verbatim beside it. Spine numstat `3 0`; lint findings equal the baseline (10 `placeholder low`). The implement stage does not edit the spine. The warm-up time in `## Verification` is corrected from a measurement.

## Review Triage Log

### 2026-11-08 - Review pass
- verdicts: 24 rows - high 0, medium 1, low 22, false 1, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: `Test.Web.BodyLimit.POSTROUTES` lacks the new noise route - added `/v1/decisions/zzRef/noise` and the count 18 (`BodyLimit` green).
  - `[low]` `[reject]` Blind: `PrecedentOps.Record` does not check the request State or Action - the spec's Approval answers row defines the inputs; the only sender (Story 41.5) sends after `Approval.Answer` returns `done`; a guard would add behavior the matrix does not state.
  - `[low]` `[patch]` Blind: the notes route's line splitting and 500 path are unreached because `Build` is a stub - added the private seam `Api.NoteText`, the probe override and `TestNoteLines` (mutation: dropping the empty-line filter turns it red).
  - `[medium]` `[patch]` Blind and Edge: `Precedent.Has` answers 0 when its SQL fails, so a failed read lets sign-out keep the person's precedents - `Has` now throws on a SQL error and `SessionOps.EndPrecedents` already counts a throw as a failed step; no test (a failing SQL is not reachable on the slot).
  - `[low]` `[reject]` Blind and Edge: an unclosed `<` in a sender keeps the whole text as the key - the spec's rule is "the address inside the last <...>, or the whole sender"; a malformed sender is outside it.
  - `[low]` `[reject]` Blind: no index for `RemoveRun` and `Purge` deletes - the table is small and both run at most daily or per eval run; the storage block would grow for no measured need.
  - `[low]` `[reject]` Blind: owner literals `eval` and `instance` repeated - cosmetic; no caller diverges today.
  - `[low]` `[reject]` Blind: test counters left in `^OcuTalonTest` - the same pattern as `InProduction`, which documents "never reset".
  - `[low]` `[reject]` Blind: `memory.spec.ts` expects the list to equal exactly `[own]` and covers no 200 noise over HTTP - the exact empty list is the spec's own task wording; the 200 noise success needs a Decision and Item fixture over HTTP that the spec does not ask for and the production test covers through `Commands.Submit` (deferred below as a gap for Story 41.5).
  - `[low]` `[patch]` Blind: the `CommandsIn` header comment is spliced mid-sentence - made its own clause.
  - `[low]` `[reject]` Edge: `Ownership.Precedents` with max below 1 - the only callers pass the constant 100.
  - `[low]` `[reject]` Edge: `Notes` with a zone that returns an empty local date - the zone read is existing code that falls back; not reachable.
  - `[low]` `[reject]` Edge: `KeyFor` for a check with an empty Namespace or Production - both are required properties of `BackgroundCheck`.
  - `[low]` `[reject]` Edge: `Seed` with an over-long RunRef or MatchKey answers failed instead of not_valid - the only sender is `EvalIn` (a later story) and the row is refused either way.
  - `[low]` `[reject]` Edge: CRLF in the note text - the builder is a stub; Story 41.3 owns the format (lines separated by line feeds per the spine line).
  - `[false]` `[reject]` Edge: `RemoveRun` could delete a person's row - a row with an `EvalRunRef` is by definition seeded; `Ownership` and `DropSession` also treat it so, and the session-owned odd row exists only in a test fixture.
  - `[low]` `[patch]` Verification-gap: the `decision.recorded` pin has an unused `total` - removed. The pin itself stays: the fixture Decision is visible to `Ownership.Decision`, so `Recorded` runs to its end.
  - `[low]` `[patch]` Verification-gap: the production test's absence check follows an unchecked `WaitDeliveries` - it now asserts the delivery exists first (green on a warm and a fresh stack).
  - `[low]` `[reject]` Verification-gap: the noise success path and its phone mapping are never run over real HTTP - not in the spec's task list for `memory.spec.ts`; the slot-safe route tests pin them through the seam and the production test pins `Commands.Submit`.
  - `[low]` `[patch]` Verification-gap: the route-test probe comment says it records the origin - comment corrected.
  - `[low]` `[reject]` Verification-gap: `Rule 19` sub-claims without their own mutation line - one pinning mutation per AC is the rule and each AC has one.
  - `[low]` `[reject]` Verification-gap: `TestPurge` is table-wide and the `EvalIn` setting row is flipped in place - both are the spec's own calls (`Purge(90)`, `Purge(36500)`, restore of the row), and the second only matters on a stack that runs `EvalIn`.
  - `[low]` `[reject]` Verification-gap: `TestNotes` hides the argument `Build` receives - closed by `TestNoteLines` (see the patch above).
  - `[low]` `[reject]` Intent audit: three readings, the diff implements the wide-code reading; its divergence notes (fixtures written through `irisScript`, senders supplied by headers) are the spec's own test design.

## Design Notes

**Architecture decisions:**
- AD-1 (origins, `CommandsIn`, the governance test)
- AD-3 (private globals)
- AD-4 (ownership API, sign-out drop)
- AD-5 (append-only storage)
- AD-13 (unchecked prepares only in `Ownership.Rows`)
- AD-21 (precedents and the one writer, as amended 2026-11-08 by the lead)
- AD-22 (the `EvalIn` switch row)
- AD-26 (`CommandsIn.Join`)
- AD-27 (the area's `Purge`)
- AD-29 (lanes, the names)
- AD-33 (the item, the table, the same-change rows)

No AC contradicts an AD's Rule as amended.

**Integration ACs:** AC 8 (the production test) and AC 6 (the routes over HTTP) are the in-story consumers.

**Consumed-by:**
- 41.3: replaces the `DailyNote.Build` stub, and the notes route.
- 41.4: `KeyFor` and `Similar`, read by `Agent.Input`.
- 41.5: the noise route and `markedAt`; `AnswerOps` sends `RecordPrecedent`.
- 41.6: the list, the delete and the notes routes.
- 41.7: `SeedPrecedent`, `RemoveSeededPrecedents`, `EvalOn`, `KeyFor` for its case Item, and `Similar("eval", ...)`. 41.7 pins its own "turn beside a run" side.

**Consumes:**
- Story 41.1's names
- `Ownership.Decision`, `Ownership.Approval` and `Ownership.SessionRef`
- `Commands.Submit`
- `Bridge.Ids.NewRef` and `Bridge.Approval.IsRef`
- `Data.Time`
- the `EvalIn` row that `Install.Step.Production.SetEval` writes

**Extend, don't copy:**
- `PrecedentOps` follows `SessionOps` (dispatch, `Result` and `Failed`) and `AnswerOps` (the sender check).
- The `End` step follows `EndHandled`/`DropHandled`, and the drop step reuses `SessionOps.Carry`.
- `Precedent` follows `Handled` and `Upload` (EXACT Refs, `DropSession`), and `Purge` follows `Pairing.Purge`.
- The routes follow `DismissIncident` and `GetPersona`.
- The two Ownership kinds follow `upload` and `document`.
- `SubmitMemory` is a copy of the `SubmitPersona`/`SubmitHeartbeat` seam shape, because each seam is typed and named per feature in this class.
- `DeleteAll` is copied per table, because the siblings keep it private and per table.

**Spine lines for the lead** (to add beside the AD-21 amendment):
1. A new sub-bullet directly after AD-29's "Epic 41's names" line:
   `    - **Epic 41's names, as built** [ADDED 2026-11-08, Story 41.2]: `MarkNoise` also carries `Channel` (`web` or `phone`). `PrecedentOps` also takes `OcuTalon.Core.Msg.SeedPrecedent` (`RunRef`, `Channel`, `MatchKey`, `Summary`, `Outcome`, `Answer`, `AnsweredAt`) and `OcuTalon.Core.Msg.RemoveSeededPrecedents` (`RunRef`), each answered synchronously with a `CommandResult`, from `EvalIn` only and only while `PrecedentOps.EvalOn()` finds the `EvalIn` `Enabled` System Default Setting at 1; a seeded row has owner `eval` and `EvalRunRef` set. It also takes an `EndSession` from `SessionOps`, which deletes the session's rows. A row keeps `Ref`, `OwnerRef`, `Channel`, `MatchKey`, `Summary`, `Outcome`, `Answer`, `AnsweredAt`, `AnsweredChannel`, `SourceRef` (unique: the Decision's or the request's Ref) and `EvalRunRef`. A fix precedent is keyed `production:<namespace>/<name>` with channel `system`; a `tool_call` precedent is keyed `tool:<ToolName>`, which no arriving item produces, so it is listed and forgettable but never read in this release (DW-922). `KeyFor` gives "" for an item that is not untrusted, and keys a check finding through the session's production check of that display name. `Similar` returns a `%DynamicArray` of `{ref, answeredAt, channel, answeredChannel, summary, outcome, answer}`, newest first, at most 3, with seeded rows only for owner `eval`. `DailyNote.Build(sessionRef, day)` takes a local `YYYY-MM-DD` and returns one `%String`, with lines separated by line feeds.`
2. A cross-area row at the end of the table:
   `| `OcuTalon.Core.Msg.SeedPrecedent` and `.RemoveSeededPrecedents` (AD-21 as amended 2026-11-08, AD-22), sent by `EvalIn` to `PrecedentOps` while `OCUTALON_EVAL=1` [ADDED 2026-11-08, Story 41.2] | B | Story 41.2 (classes and the guard), Story 41.7 (the sender) |`

**PUBLIC TEXT needed:**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`, a new line after line 143: `Parameter MESSAGETOOOLD = "This notice is too old to mark as noise. Nothing was changed.";`. It is the body of 409 `too_old`.
- DW-923 (owned by 41.5) is the same refusal. One ruling should give the route and the catalog line the same words.
- Every other route error reuses an existing text. The `PrecedentOps` messages are log text, never shown.

**Decided in-stage:**
- **No split.** The eval path reuses the save and delete code, so it adds about 60 product lines. One story holds it; a sibling story was weighed and not needed.
- **Check findings key through their check.** Finding Items carry only the display name, so `KeyFor` finds the item's session's production `BackgroundCheck` of that display name. It answers "" when zero or two checks match. A Lane A slot change would make this simpler, but that is not this lane's file.
- **KeyFor normalization.** The address inside the last `<...>`, or the whole sender, trimmed, lowercased and cut at 512. The fix and `tool_call` keys follow DW-922.
- **DW-922: tool keys are never read.**
  - The key is `tool:<ToolName>` with an empty channel, and it is never read in this release.
  - FR-72 matches only sender, source, production or heartbeat, so this is the AC's write with no promise changed.
  - The card's line "OcuTalon looks at these when it decides on similar items" is broader than `tool_call` rows. Story 41.6 may want to note or filter them.
- **Approval rows.** A fix row's Summary is the incident's diagnose Decision Summary (code-written). A `tool_call` row's Summary is the ToolName. "The outcome then" is empty for approval rows, because no decision outcome exists. The owner is the answering session.
- **MarkNoise keeps where it was pressed.** It carries `Channel` (AD-21: "where it was given"), so a spine line is needed. The route takes `phone` only from the exact body `{"channel":"phone"}`, and anything else is `web`. This needs no bad-body text.
- **Items by trace session.** The Item is found through its trace session's headers (indexed), not by a scan of the message extent.
- **Small decisions.**
  - A user-provenance decision is not markable.
  - An unknown notes day is a 404 with the existing text.
  - The list holds at most 100 rows.
  - The answers live in `Precedent.ANSWERS`, because `Msg.Enum` is contended and pinned exactly.
  - `End` sends to `PrecedentOps` only when the session has rows, so the existing End tests stay green.
- **The guard reads the System Default Setting row** that AD-22's install step writes from `OCUTALON_EVAL` at every start. A missing row means off.
- **No new CI unit.** The new classes are in the `lane-b` areas Core, Data and Web, and the spec joins the `chromium` project of `live:sign-in`. That adds a few seconds to `image` and `browser` (inference).

- **Implement-stage decisions (small, in the spec's room).**
  - `MarkNoise` and `RecordPrecedent` keep `AnsweredChannel` as the message's Channel when it is a Msg.Enum CHANNEL value, else empty. The route sends only `web` or `phone`.
  - `RecordPrecedent` answers `recorded` (Ok 1, the row's Ref), `already_recorded` (Ok 1) and `not_recorded` (Ok 0). It does not check the request's State: the sender (Story 41.5) sends it only after `Approval.Answer` returns `done`.
  - A fix row's Summary is the incident Decision's Summary, else the production key. The incident and its Decision are opened by Ref from the request the session can see (`KeyForRequest(request, .channel, .summary)`).
  - `Precedent.RemoveRun(runRef, .count)` has an optional output `count`, which `RemoveSeededPrecedents` answers as `{"count"}`.
  - `Similar` also leaves out a row with an `EvalRunRef` for any owner but `eval`.
  - `SeedPrecedent` is `not_valid` for a bad Answer, Channel or Outcome and for an AnsweredAt that is not a UTC time; the guard (sender and `EvalOn()`) is checked first.
  - `GET /notes` takes a missing `day` as `today`. `NoiseBodyIsPhone` is true only for a JSON object with exactly one member, `channel`, equal to the string `phone`.
  - `KeyFor` gives "" for an item whose Provenance is not `untrusted`, and finds a finding's check through `Ownership.Checks`.

**Ledger inbox:**
- DW-921 is addressed: the `ForgetPrecedent` handling (Execution, the Forget row, AC 4) plus the lead's amendment text.
- DW-922 is addressed (decided above, AC 4).

## Clarification Needed

**Cleared 2026-11-08 (orchestrator ruling, decide; the Contest Planner agrees): allowed as a plain union. See `## Spec Change Log`.**

`src/ocutalon/cls/OcuTalon/Data/Ownership.cls` is changed by Epic 17 (`origin/OCT-epic17` changes lines 40, 413-414 and 910-911). This story must add the route reads there, because AD-4 sends REST reads through the ownership API, and AD-13 allows unchecked prepares only in `Ownership.Rows`. Its additions are:
- one comment bullet after line 46;
- the methods `Precedents` and `Precedent` after line 667;
- two `Statement` kinds after line 979, before `Quit ""` at 980.

None of these overlaps or touches Epic 17's hunks, so a plain merge unions them. **Recommended:** allow these three insertions. If they are declined, implement waits until Epic 17 merges and is brought forward, because no other path is consistent with AD-4 and AD-13.

## Verification

Run every command from the worktree root, one per call.

**Rules for each kind of call:**
- **Bash:** `timeout: 600000`, sized to about 150 s.
- **IRIS MCP:**
  - Target `server` `ocutalon-slot-a` and `namespace` `OCUTALON` on every call, after `iris_server_info` shows build 154.
  - Load with `iris_doc_load`, using absolute paths and `baseDir` `<worktree>/src/ocutalon/cls`, then `iris_doc_compile` with `ck`.
  - One `iris_execute_tests` per message.
- **`ci/iris.sh` and `ci/warm.sh`:** prefix each with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=implement'`. The fresh tag is `e41s2impl` and the warm tag is `e41s2implw`.
- **The `short-names.tsv` edit:** make it before `ci/warm.sh up`, because a warm run refuses a stack input it did not start with.

**Commands:**
- (loop) `iris_execute_tests`, one class per message:
  - `OcuTalon.Test.Data.Precedent`
  - `OcuTalon.Test.Data.OwnershipPrecedents`
  - `OcuTalon.Test.Core.PrecedentOps`
  - `OcuTalon.Test.Core.CommandsPrecedent`
  - `OcuTalon.Test.Core.SessionOpsPrecedents`
  - `OcuTalon.Test.Web.MemoryApi`

  Expected: every assertion passes.
- (once) `iris_execute_tests`, one class per message: `OcuTalon.Test.Web.Api`, `.Data.Tables`, `.Msg.Contracts`, `.Contract.Ac`, `.Data.Ownership`, `.Core.SessionOps`, `.Core.GotIt`, `.Core.SessionOpsDocuments`, `.Core.CommandsHeartbeat`, `.Core.BridgeSink`. Expected: each passes.
- (once) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-storage.sh`, then `bash docker/tests/test-ci-config.sh`. Expected: every rule passes.
- (once) `cd web && npm run lint`. Expected: exit 0 (it type-checks the new spec).
- (once) The warm sequence: `ci/warm.sh up` (measured 397 s on lane A at 41.1's fresh check: the call is moved to the background at about 170 s, so wait for it to exit in bounded foreground polls before the next step), then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s2implw ci/iris.sh class OcuTalon.Test.Core.PrecedentOpsProduction`, then `... class OcuTalon.Test.Install.Production`, then `ci/warm.sh down`. Expected: `CLASS ... passed` for each.
- (once) `OCUTALON_RUN_TAG=e41s2impl ci/iris.sh class OcuTalon.Test.Core.PrecedentOpsProduction`, then `ci/iris.sh teardown`. Expected: passed on a fresh stack. If it does not finish within one call, it is left to CI.
- Left to CI, because each takes over 150 s locally: `live:sign-in` (which runs `web/e2e/api/memory.spec.ts`), the full `lane-b` shard, and the fresh-environment check in both orders.

**Mutations (Rule 19):** record one per AC in this section as `mutation: <change> -> <test red>`. Suggested targets:
- AC 2: drop the `Source()` check for `MarkNoise`.
- AC 3: add `tool` to the `MarkNoise` route's origins.
- AC 4: skip the `Outcome` check.
- AC 5: remove `EvalRunRef IS NULL` from `precedents`.
- AC 6: the delete route skips its `Ownership.Precedent` check.
- AC 7: `EndPrecedents` returns 0 always.
- AC 8: `ItemOf` reads the newest Item of any session.
- AC 1: `SIMILARMAX` 4.
- AC 9: pool 2 in the oracle.

**Mutations recorded (implement stage, on slot `ocutalon-slot-a`; each file was backed up in the scratchpad, mutated, loaded and compiled, observed red, restored from the backup, reloaded, and checked byte-identical):**
- mutation: `SIMILARMAX` 3 -> 4 in `Data/Precedent.cls` -> `Test.Data.Precedent` red (`TestSimilarBounds` "limit 7: still three", `TestMessageContracts`) (AC 1)
- mutation: `FromVerb` without the `Source()` = CommandsIn check in `Core/PrecedentOps.cls` -> `Test.Core.PrecedentOps:TestSenders` red (every MarkNoise and ForgetPrecedent from a wrong sender) (AC 2)
- mutation: `web_user,tool` as the origins of the `MarkNoise` route in `Core/CommandsIn.cls` -> `Test.Core.CommandsPrecedent:TestNeitherIsAToolVerb` red; `TestOrigins` and `TestToolRefused` stay green, because CommandsIn also refuses origin tool for any verb outside TOOLVERBS (AC 3)
- mutation: no `Set row.Outcome = decision.Outcome` in `Mark` -> `Test.Core.PrecedentOps:TestMarkNoise` red (AC 4)
- mutation: `p.EvalRunRef IS NULL` removed from the `precedents` statement in `Data/Ownership.cls` -> `Test.Data.OwnershipPrecedents:TestSeededRowsAreInvisible` red (AC 5; the seeded owner eval is also refused by `Rows`, so the test pins the EvalRunRef condition with a session-owned row that has an EvalRunRef)
- mutation: the delete route submits without its `Ownership.Precedent` check in `Web/Api.cls` -> `Test.Web.MemoryApi:TestForgetPrecedent` red (AC 6, the slot-safe side)
- mutation: `EndPrecedents` quits 0 first in `Core/SessionOps.cls` -> `Test.Core.SessionOpsPrecedents` red (`TestEndDropsRows`, `TestFailedDropFailsEnd`) (AC 7)
- mutation: pool 2 for `PrecedentOps` in `Test/Core/ProductionItems.cls` -> `Test.Install.Production:TestDefinition` red ("item 47 is PrecedentOps as the ownership table says") (AC 9)
- mutation: `ItemOf` in `Core/PrecedentOps.cls` binds `decision.OwnerRef` instead of `decision.TraceSessionId` (item restarted after the reload; a running host keeps its loaded code) -> `Test.Core.PrecedentOpsProduction:TestNoiseThroughTheProduction` red on a warm throwaway ("MarkNoise is marked", the row, `Similar`, `Ownership.Precedents`, the repeat); green again after the restore (AC 8)
- mutation: the empty-line filter dropped in `Web/Api.cls` `Notes` -> `Test.Web.MemoryApi:TestNoteLines` red ("two lines, no empty one") (AC 6, the notes route)
- The Playwright HTTP side of AC 6 (`web/e2e/api/memory.spec.ts`) runs in CI (`live:sign-in`, over 500 s locally); its slot-safe pin is the AC 6 mutation above.

**QA stage (2026-11-08, slot `ocutalon-slot-a`; each file backed up in the scratchpad, mutated, loaded and compiled `ck`, observed red, restored from the backup, reloaded, and checked byte-identical by `shasum` and `git status --short`):**
- Gap check: every AC 1-9 and every I/O & Edge-Case Matrix row has a pinning test; no gap needed a new test, so no test file was created or changed (QA): none.
- `MESSAGETOOOLD` is pinned with a fixed string: `Test.Web.MemoryApi` holds a copy (`TOOOLD`), `TestTooOldText` compares the parameter with the sentence written out in the test and with the copy, and `TestNoise` and `TestTooOldText` assert the 409 body against it.
- mutation (QA): the second sentence dropped from `Parameter MESSAGETOOOLD` in `Web/Api.cls` -> `Test.Web.MemoryApi:TestTooOldText` red (parameter, copy and 409 body) and `TestNoise` red ("too_old is mapped") (AC 6, the approved text)
- mutation (QA): `EvalOn` quits 1 instead of `(value = 1)` in `Core/PrecedentOps.cls` -> `Test.Core.PrecedentOps:TestEvalOn` ("the row at 0: off"), `TestSeedRefused` ("EvalOn 0: not_allowed") and `TestRemoveSeeded` red (AC 5, the switch half; the implement stage's AC 5 mutation covered the `EvalRunRef IS NULL` half)
- mutation (QA): `web_user,web_admin` as the origins of the `MarkNoise` route in `Core/CommandsIn.cls` -> `Test.Core.CommandsPrecedent:TestOrigins` ("MarkNoise from 'web_admin' is not_allowed") and `TestNeitherIsAToolVerb` red; `TestToolRefused` stays green, as for the implement stage's `tool` mutation (AC 3)
- mutation (QA): `BridgeSink.Recorded` saves a `Precedent` row after publishing the decision (temporary lines in `Core/BridgeSink.cls`) -> `Test.Core.PrecedentOps:TestDecisionRecordedWritesNoRow` red ("no row for the session or for the Decision") (AC 2, the `decision.recorded` half; the implement stage's AC 2 mutation covered the sender check)
- Slot run after the restores, one class per call, all green: `Test.Core.CommandsPrecedent` 3, `Test.Core.PrecedentOps` 18, `Test.Web.MemoryApi` 7, `Test.Data.Precedent` 9, `Test.Data.OwnershipPrecedents` 4, `Test.Core.SessionOpsPrecedents` 3, `Test.Web.Api` 38, `Test.Data.Tables` 5, `Test.Msg.Contracts` 6, `Test.Contract.Ac` 6. No `zz.%` Precedent row is left on the slot.
- Not run in this stage: `Test.Core.PrecedentOpsProduction` (the implement stage's warm and fresh runs stand; no lane-A throwaway was started) and `web/e2e/api/memory.spec.ts` (CI only; the noise route's 200/409/phone mapping over HTTP stays DW-932).

**Code review (2026-11-08, slot `ocutalon-slot-a`; the file was backed up in the scratchpad, mutated, loaded and compiled `ck`, observed red, restored from the backup and checked byte-identical by `shasum`):**
- mutation (CR): `End` runs `EndPrecedents` only when no earlier step failed (`If 'failed Set failed = ..EndPrecedents(command)`) in `Core/SessionOps.cls` -> `Test.Core.SessionOpsPrecedents:TestDropAfterEarlierFailure` red ("the drop was still called", "the session's rows are deleted") (AC 7, every step is tried)
- After the patches and the restore, one class per call, all green: `Test.Core.SessionOpsPrecedents` 4, `Test.Core.PrecedentOps` 18; `test-class-rules.sh` passes; `npm run lint` in `web` exits 0. The `memory.spec.ts` change is type-checked here and runs in CI (`live:sign-in`).

**Shared surfaces:**
- `Web.Api`'s Url map (`Test.Web.Api` `TestRoutes`)
- the production's Lane B items (`Test.Core.ProductionItems`, `Test.Install.Production`, and the live scripts that read `Items()`)
- the table registry (`Test.Data.Tables`, `src/short-names.tsv`, `test-storage.sh`, `Install.Step.PrivateData`)
- the verbs list and contracts (`Test.Msg.Contracts`)
- the `Signatures` oracle (`Test.Contract.Ac`; its count floor stays valid)
- `CommandsIn`'s Routes
- `SessionOps.End`'s steps
- the chromium project's spec list of `live:sign-in`

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

Summary: Story 41.2 adds `Data.Precedent` (table, `KeyFor`, `KeyForRequest`, `Similar`, `View`, `Has`, `DropSession`, `RemoveRun`, `Purge`), the `DailyNote.Build` stub, and `Core.PrecedentOps`, the one writer, with six accepted messages from their named senders and the eval guard `EvalOn()`. It adds the `MarkNoise` and `ForgetPrecedent` verbs and their `CommandsIn` routes, the `EndSession` precedent drop in `SessionOps.End`, two `Ownership` row kinds, the four `Web.Api` routes with `MESSAGETOOOLD`, the `Purge` hook, the `PrecedentOps` production item and the `Precedent` short-name row.

Files changed:
- New: `Data/Precedent.cls`, `Data/DailyNote.cls`, `Core/PrecedentOps.cls`, `Core/Msg/{RecordPrecedent,SeedPrecedent,RemoveSeededPrecedents}.cls`, `Msg/Command/{MarkNoise,ForgetPrecedent}.cls`, and the tests `Test/Data/{Precedent,OwnershipPrecedents}`, `Test/Core/{PrecedentOps,PrecedentOpsProbe,CommandsPrecedent,SessionOpsPrecedents,SessionOpsPrecedentsProbe,PrecedentOpsProduction}`, `Test/Web/{MemoryApi,MemoryApiProbe}`, `web/e2e/api/memory.spec.ts`.
- Changed: `Core/CommandsIn.cls`, `Core/SessionOps.cls`, `Data/Ownership.cls` (the three allowed insertions only), `Install/Step/Core.cls`, `Production.cls` (one item, Lane B region), `Web/Api.cls`, `src/short-names.tsv` (one row), and the shared-surface tests `Test/Web/Api`, `Test/Web/BodyLimit`, `Test/Core/ProductionItems`, `Test/Data/Tables`, `Test/Msg/Contracts`, `Test/Contract/Ac` (one block).

Review: 24 triage rows from four layers. Patches applied 7 (medium 1: `Precedent.Has` threw no error on a failed read; low 6: `BodyLimit` route list, the notes seam with `TestNoteLines`, the `CommandsIn` comment, the unused variable, the production test's delivery check, the probe comment). Deferred 1 (the noise success path over real HTTP, low, in the frontmatter). Rejected 17, each with its reason in the log above.

Follow-up review recommended: false (one medium patched, no high).

Verification performed:
- Slot (`ocutalon-slot-a`, build 154), after the last patch, one class per call, all green: `Test.Data.Precedent` 9, `OwnershipPrecedents` 4, `Test.Core.PrecedentOps` 18, `CommandsPrecedent` 3, `SessionOpsPrecedents` 3, `Test.Web.MemoryApi` 7, `Test.Web.Api` 38, `Data.Tables` 5, `Msg.Contracts` 6, `Contract.Ac` 6, `Data.Ownership` 32, `Core.SessionOps` 30, `GotIt` 12, `SessionOpsDocuments` 4, `CommandsHeartbeat` 3, `BridgeSink` 31, `Test.Web.BodyLimit` 4.
- Static: `test-class-rules.sh`, `test-storage.sh`, `test-ci-config.sh` and `test-boundaries.sh` pass; `npm run lint` in `web` exits 0.
- Throwaway stacks: on a warm stack (ready in 161 s) `Test.Core.PrecedentOpsProduction` and `Test.Install.Production` pass; on a fresh stack `PrecedentOpsProduction` passes (ready in 129 s). Both stacks are torn down.
- Mutations: one per AC 1-9 recorded in `## Verification`, plus the notes-line mutation; AC 8's mutation was run on the warm stack after restarting the item.

Residual risks: `live:sign-in` (which runs `memory.spec.ts`), the full `lane-b` shard and the fresh-environment check in both orders are left to CI. The Playwright spec was type-checked, not run. `Test.Core.PrecedentOps.TestPurge` deletes any slot Precedent rows older than 90 days.
