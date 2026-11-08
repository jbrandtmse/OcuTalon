# Story 19.5: a reset leaves no visitor data (AC "a fresh online-demo install ready before any visitor")

Measured 2026-11-08 by the Story 19.5 implement stage (lane C, run tag e19s5ig), the recipe of `evidence/34-3-upload-reset.md`, with a scratch script that is not committed.

**What this shows.** On a throwaway online demo (the CI override and the test start values of docker/tests/lib-online.sh), a golden copy of the durable volume captured after a
fresh start holds no per-session table, class or global, no `OcuTalon.Data.Document` row and no `OcuTalon.Data.Memory` row. A visitor then added a document and a memory; the
golden copy was restored (stop IRIS, replace the durable volume with the golden copy, start); and the stack read as it did before any visitor. A turn for the old SessionRef
(`OcuTalon.Docs.TurnTools Tools`) gave no tool and made no table, class or global. The demo host's real reset scripts live outside this repository, so this emulates the restore
that AD-25 documents; that the host does the same is an inference, not measured here. The committed pin of the state the golden copy is captured from is the fresh-stack check
of `docker/tests/test-session-data.sh` (`live:session-data`).

**Reading.** `OcuTalon.Test.Docs.SessionLive Facts("")` prints `tables|classes|globals|documents|memories`: the SQL tables `OcuTalonKB.S<id>` and `_Config` that exist, their
compiled classes, their globals in OCUTALON_PRIVATE and OCUTALON_DATA (the names of `^$GLOBAL`, which carry the caret, starting with `OcuTalonP.KBS` and a digit), and the
rows of `Data.Document` and `Data.Memory`.

**Steps.**

- build and first start (ready at 181 s)
- golden copy: stop, copy the durable volume to the golden volume (at 189 s), start again (ready at 208 s)
- one visitor signs in, POST /v1/documents adds a Markdown runbook (200), and a chat turn of the CI mock saves a memory (202); both are in place (at about 240 s)
- reset: stop, restore the golden volume into the durable volume (at 249 s), start (ready at 268 s)
- the old SessionRef's turn, then the mutation run (below); done at 336 s

**CHK lines** (`Facts("")`):

```
CHK|fresh|0|0|0|0|0               before the golden copy
CHK|with-visitor|2|2|6|1|1        after the visitor added a document and a memory: two tables, two classes, six globals, one document, one memory
CHK|after-restore|0|0|0|0|0       after the restore
CHK|old-session-turn|1|0          Docs.TurnTools Tools for the old SessionRef: status OK, no tool
CHK|after-turn|0|0|0|0|0          the turn made nothing
```

**Mutation** (the reset check turns red): a fixture table `OcuTalonKB.S9001` (made by `Test.Memory.Fixture CreateTable`) was left in a second golden copy, which was restored the
same way; `Facts("")` then read `2|2|5|0|0` (two tables, two classes, five globals) instead of `0|0|0|0|0`, so the check `Facts("") = 0|0|0|0|0` fails. The fixture table was
dropped before the throwaway was removed.
