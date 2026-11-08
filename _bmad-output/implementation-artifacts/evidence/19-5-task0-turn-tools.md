# Story 19.5, Task 0: composing a tool manager per request

Measured 2026-11-08 on the lane-C warm throwaway (run tag e19s5iw, build 154U, ARM64, the CI mock), with scratch classes that were
removed afterwards: a scratch agent (`%AI.Agent`, TOOLSETS `OcuTalon.Test.Bridge.StepsTools`, MODEL claude-haiku-5-5), a scratch adapter
subclass of `OcuTalon.Bridge.Adapter.Agent` and a scratch runner, driven through `OnMessage` with real requests of kind `turn` (provenance
user, owner given). Two scratch tables `OcuTalonKB.S9001` and `OcuTalonKB.S9002` came from `Test.Memory.Fixture.CreateTable`, each with one
passage. The new manager was `%AI.ToolMgr.%New()` with the agent's toolset registered, `Gate` and `StepAudit` set and a
`%AI.RAG.KnowledgeBase` named `documents` added; it was assigned to `Agent.ToolManager` before the session opened.

## M1: the session takes the assigned manager

| Turn | Manager | Session opened by | Offered tools (mock log) | Result |
|------|---------|-------------------|--------------------------|--------|
| 1 | the agent's own | `CreateSession` | zz_steps_card, zz_steps_note, zz_steps_text | untainted, session saved |
| 2 | assigned (S9001) | `ResumeSession` of turn 1's session | documents, zz_steps_card, zz_steps_note, zz_steps_text | the `documents` call returned the S9001 passage; Tainted 1; three steps recorded (model, tool, model); 490 ms; text of the scenario |
| 3 | the agent's own, put back | `ResumeSession` | zz_steps_card, zz_steps_note, zz_steps_text | `Agent.ToolManager` is the object it was before turn 2 |
| 4 | assigned (S9002), new owner | `CreateSession` | documents + the three | the result holds only the S9002 passage |
| 5 | assigned (S9001), new owner | `CreateSession` | documents + the three | the result holds only the S9001 passage |

The job id was the same across the five turns (no crash, no deadlock; the longest turn took 0.5 s). The gate decided the call: the tool step
is recorded and the turn is tainted, as for any `documents` call. The chat after `ResumeSession` uses the manager assigned to the agent at
the time (`Chat` passes `ToolManager.%token`), and a manager put back takes effect on the next request. AD-21 "Attaching per turn" and AD-6
hold: no stop rule trips.

## M2: cost

Composing the manager (new manager, toolset, policies, knowledge base added): median 0.1 ms over 10 runs (all under 0.2 ms). Dropping the
reference to a manager (`%OnClose`): under 0.1 ms each, no error. Building the knowledge base itself (embedding registration, vector store
`Build`, knowledge base `Build`): 57 ms once, which is the per-request cost of `Docs.Store.Knowledge`.

## M3: isolation on one job

Owners A (S9001), B (S9002), A on one job: each `documents` result held only the source of its own table.

## M4: `DROP TABLE` after a knowledge base was built over the table

Read with the scan that lists the globals of both databases by name (`^$|"^^"_directory|GLOBAL`, whose names carry the caret). A table made by
`Test.Memory.Fixture.CreateTable` with one passage, and a knowledge base built over it, held 2 tables, 2 classes and 5 globals in OCUTALON_PRIVATE
and none in OCUTALON_DATA. `DROP TABLE IF EXISTS OcuTalonKB.S9001_Config` then `OcuTalonKB.S9001` (what `Docs.Store.Drop` runs) left 0 tables, 0
classes and 0 globals in either database, with the knowledge base built before the drop still referenced. So `Docs.Store.Drop` needs no `Kill` of a
global. A search through that knowledge base answers an error to the model (`Statement not prepared`) and re-creates nothing: after it, still 0 tables,
0 classes, 0 globals, and `TableExists` and the compiled class are false. The stop rule on a re-created table does not trip.

The first reading of this measurement (the scratch class, removed) scanned the databases without the caret and so saw nothing in either; the
reading above replaces it, and `Test.Docs.SessionLive Facts` and `Test.Docs.TurnTools DataDatabase` use the corrected scan.
