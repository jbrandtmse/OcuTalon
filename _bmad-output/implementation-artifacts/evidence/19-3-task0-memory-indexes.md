# Story 19.3, Task 0: where the memory indexes' globals land, what they cost, and when the planner uses HNSW

Measured 2026-11-06 on one fresh lane-C throwaway (run tag `e19s3i0`, started with `ci/warm.sh up` so that it stays up between calls, torn down with `ci/iris.sh teardown`): IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U), aarch64, the image built from this worktree, install and `PrivateData` check ended ready. `OcuTalon.Data.Memory` compiled with the two new indexes. The harness was a throwaway class loaded into the throwaway only (never in the repository). Vectors are synthetic: 384 doubles, 50 cluster centres plus noise, normalised.

Indexes as measured:

    Index EmbeddingIdx On (Embedding) As %SQL.Index.HNSW(Distance = "Cosine");
    Index TextIdx On (Text) As %iFind.Index.Basic(IFINDSHAREDDATALOCATION = "INDEX", INDEXOPTION = 0, LANGUAGE = "en", LOWER = 1);

The Storage block of the class did not change on compile (the indexes add no storage element).

## M1: the globals one insert writes, and where they resolve

Mapping of the namespace (`Config.MapGlobals`): `OcuTalonP.*`, `OcuTalonBP.*`, `IRIS.IF.*`, `AI.Agent.Session*` -> OCUTALON_PRIVATE. `GetGlobalDest` of `^OcuTalonP.MemoryI`, `^OcuTalonP.MemoryD`, `^IRIS.IF.Word`, `^IRIS.IF.WordI`, `^IRIS.IF.WordRI`, `^IRIS.IF.WordD`, `^IRIS.IF.WordCP`, `^IRIS.IF.TransfoB` is the private database; `^IRIS.KNNIndex` resolves to OCUTALON_DATA (the default), but it is never written.

After one insert (a snapshot of every global of OCUTALON_DATA, OCUTALON_PRIVATE and OCUTALON_CODE before and after):

- HNSW (`EmbeddingIdx`): `^OcuTalonP.MemoryI("EmbeddingIdx","G",...)` only (nodes `"G",-20,"<hash>@$vector",<id>`, `"G",-12`, `"G",-11`, `"G",0,<id>`, `"G","Ver"`, and `^OcuTalonP.MemoryI("$Memory",1)`). `^IRIS.KNNIndex` stays empty (`$Data` 0), so the storage address of the index (the class's `IndexLocation`) is used. Private.
- `%iFind` with the default shared location (the first measurement, without `IFINDSHAREDDATALOCATION`): the data goes to `^IRIS.IF.WordI`, `^IRIS.IF.WordRI`, `^IRIS.IF.WordD`, `^IRIS.IF.WordCP`, `^IRIS.IF.TransfoB` in OCUTALON_PRIVATE, as the mapping says. BUT the first write also leaves an empty global-directory entry for `^IRIS.IF.WordI` and `^IRIS.IF.WordRI` in OCUTALON_DATA (`$Data` 0, yet the directory lists them). `OcuTalon.Install.Step.PrivateData.Run()` then fails: "Database OCUTALON_DATA holds the private global ^IRIS.IF.WordI", so every later start would end with a failed private-data check. Reproduced three times: the entries come back each time the private `^IRIS.IF.*` globals are created from nothing (a kill of the directory entries clears the failure until the next creation).
- `%iFind` with `IFINDSHAREDDATALOCATION = "INDEX"`: the whole dictionary and the postings are under the index: `^OcuTalonP.MemoryI("TextIdx","$WI"|"$WRI"|"$WD"|"$WCP"|"$TB"|"L"|"P"|"W",...)`. Nothing is written under `^IRIS.IF.*`, OCUTALON_DATA lists no `^IRIS.IF.*` global (only the system's `^IRIS.Msg` and `^IRIS.MsgNames`), and `PrivateData.Run()` passes after the first insert, after a search and after a delete. This parameter moves the globals, so the stop rule's first clause is not tripped; the index is declared with it.
- A `%DeleteId` removes the row's `TextIdx` and `EmbeddingIdx` nodes; a following `Count` and the next search do not see it.

## M2: volume (10,000 rows of `zz-mem-volume` and 500 of `zz-mem-volume2`)

| Measurement | Result |
|---|---|
| 500 rows, row by row (`%Save` with the vector, both indexes) | 1.78 s (3.6 ms a row) |
| 10,000 rows, row by row | 49.1 s (4.9 ms a row); 10,500 rows with the 500: about 51 s. The harness' own vector generation is 3.6 s of that |
| 10,000 + 500 rows as `INSERT %NOINDEX` | 8.0 s + 0.3 s, then `%BuildIndices()` 40.1 s: 48.4 s in all, no gain over row by row (the HNSW build is the cost) |
| `DELETE FROM OcuTalon_Data.Memory WHERE SessionRef IN (...)` of the 10,500 rows | 50.4 s (`%KillExtent()`, which removes every row of every owner, takes 0.3 s) |
| `GatherTableStats` | 0.04 s at 1,000 rows, 0.22 s at 10,000, 0.45 s at 8,000 (noisy) |
| The recall query (`TOP 20`, owner filter, ORDER BY VECTOR_COSINE DESC) | 0.04 to 0.06 s with HNSW; 0.23 s for the brute-force form on the first call |

`PrivateData.Run()` passed after each phase.

### The plan, and when it names `EmbeddingIdx`

Recall SQL: `SELECT TOP 20 ID, Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ? ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC`. With `$SYSTEM.SQL.Explain`, when it uses the index:

    This plan uses the ACORN-1 algorithm for vector search.
    Module-B: Read index map OcuTalon_Data.Memory.EmbeddingIdx, looping on the 'VECTOR_COSINE' expression on Embedding and ID.
      For each row: Read master map OcuTalon_Data.Memory.IDKEY, using the given idkey value.
        Test the = condition on SessionRef and the NOT NULL condition on SessionRef.

The owner filter is applied during the walk (ACORN-1). Results are the owner's rows only (0 foreign rows in every run). An owner with 5 rows (and one with 3) among 10,000 other rows gets all 5 (3) back; an owner with 30 rows gets 20. The top 20 overlap a brute-force top 20 (`FROM %IGNOREINDEX EmbeddingIdx OcuTalon_Data.Memory`) in 19 of 20 for the owner of 10,000 rows and 20 of 20 for the owner of 500 (approximate nearest neighbours, as HNSW is).

Whether the planner picks the index depends on the table's statistics, not on the owner filter:

- A table that has never been queried while small, and has no gathered statistics, uses HNSW at once (the clone `Mem`, 10,000 rows, both with and without the owner filter).
- A table that was queried while it held a handful of rows (`Mem2`, `Mem3`: three rows, one `COUNT`, a `DELETE`) uses a full scan with the owner's bitmap index (`SessionRefSavedAtIndex`) at 10,000 rows, with or without a filter (`Mem2` cleared of its statistics still did; `OcuTalon.Data.Memory` itself showed the same in the first measurement, before any `GatherTableStats`). `%IGNOREINDEX`, `%NOINDEX` on the condition, a literal vector and the score in the select list did not change that; a manual `SetExtentSize` of 10,500 left the owner query on the scan.
- `$SYSTEM.SQL.Stats.Table.GatherTableStats` on the populated table (and the purge of the cached queries it does) flips both forms to `EmbeddingIdx`. Gathered at 50 rows: scan; at 100: scan; at 200: HNSW; at 500: HNSW. Gathered at 1,000 rows, the plan stays on HNSW through 2,000, 3,000 ... 10,000 rows without another gather (`Mem3`). Gathered on an empty table or at 3 rows and then filled to 3,000 rows: still the scan.
- So one gather on a table with a few hundred rows or more is enough, and a gather at a tiny size leaves the scan in place for good. A scan of an owner's rows is the right plan while an owner has few rows.

Result: at least one SQL form with the owner filter uses HNSW at 10,000 rows (the form above after a gather), so the stop rule's second clause is not tripped. The product gathers the statistics itself every 1,000th row id (see the story).

## M3: `%iFind`

- `%ID %FIND search_index(TextIdx, ?, 0)` with option 0 finds "Lee" for `lee`, `Lee`, `"lee"`, the OR of quoted words `"who" OR "do" OR "I" OR "call" OR "Lee"`, `"Lee" OR "tea"` and `"what?" OR "Lee"` (a quoted `?` is inert); the search is case-folded (`LOWER = 1`).
- `OcuTalon_Data.Memory_TextIdxRank(%ID, ?)` is the rank procedure and `ORDER BY` it DESC orders the hits: the shorter text "the Results partner's contact is Lee" ranked .62, the longer "Lee likes tea and the warehouse closes at six" .41 (.45 for `"Lee" OR "tea"`).
- After `%DeleteId` of the first memory, neither the `%FIND` search nor the cosine query returned it.

## Stop rule

Not tripped: no index global lands outside OCUTALON_PRIVATE once `TextIdx` has `IFINDSHAREDDATALOCATION = "INDEX"` (without it the first write leaves ^IRIS.IF.* entries in OCUTALON_DATA and fails the private-data check); an owner-filtered SQL form uses `EmbeddingIdx` at 10,000 rows once the table's statistics are gathered on a populated table; `%iFind` searches and ranks on build 154.

## Where `Test.Memory.Volume` runs

Insert about 51 s plus delete about 50 s is far over 60 s on a fresh ARM throwaway, so the class skips unless `^OcuTalonTest("Memory","volume")` is set, which `live:memory-offline` sets before it runs the class.
