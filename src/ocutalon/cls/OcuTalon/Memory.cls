/// The memory area's entry points that other areas call (AD-21; Lane A): the read side of the memories (Search and List), the statistics step that
/// keeps the recall query on its index (Tune), and the sign-out deletion of a session's memories (DropSession, Story 19.5). Writes are MemoryOps' alone
/// (OcuTalon.Memory.Ops), except that deletion, which runs in SessionOps' job under MemoryOps' lock for the session. Every read is restricted to one owner, the SessionRef it is given, and no method here calls AI Hub or Python (AD-6): a
/// query is embedded only through OcuTalon.Memory.Embedding.Embed, which queues the work to a worker.
///   - Search: the memories of one session that answer a query. The query is embedded, and two lists are made, each restricted to the owner: the 20
///     nearest memories by VECTOR_COSINE (the HNSW index EmbeddingIdx, with the owner filter applied while the index is walked) and the 20 best
///     keyword hits of the %iFind index TextIdx, ranked by its rank procedure. The keyword query is the OR of the query's distinct runs of letters and
///     digits (at most 32), each in quotes (the word or with a backslash instead, because iFind on build 154 refuses a quoted or), so that the operators and
///     the punctuation of a question mean nothing. The two lists are merged by
///     reciprocal-rank fusion: a memory scores the sum of 1 / (RRFK + its rank) over the lists that hold it, ties go to the newer SavedAt and then
///     to the higher row id, and the best limit memories (1 to 5) come back in order as {memoryRef, text, savedAt, origin, source, pinned} (source is told or learned, and a row with no Source is told; pinned is 1 or 0). An empty query or a
///     failed embedding is an error status. A keyword query that iFind refuses leaves the nearest list alone, and writes one Type 3 warning (redacted).
///   - Fuse: the fusion of the two lists, on their own, so that the order, the ties and the cut are tested without a model.
///   - List: the owner's newest 20 memories (by SavedAt, then row id), newest first, in the same form, and the owner's count.
///   - Pinned (Story 41.12): the owner's pinned memories (COALESCE(Pinned, 0) = 1, so a row saved before Story 41.8 is not pinned), newest pin first (PinnedAt, then row id), in the
///     same form; an empty session is an error status.
///   - CoreBlock (Story 41.12): the core-memory block of the session as the model reads it, built from Pinned by OcuTalon.Agent.Input.CoreBlock (the only formatter), with an optional
///     candidate text counted first. The pin cap (PINCAPTOKENS * CHARSPERTOKEN = COREMAX characters, the heading and the quotes included) is checked on this block, and Agent.Input
///     renders this very block, so a pinned fact is never left out of the input.
///   - Tune: gathers the SQL statistics of the memory table when a saved row's id is a multiple of STATSEVERY. The planner reads HNSW's plan from the
///     table's statistics, and statistics taken while the table was small (or none) keep it on a scan of the owner's rows: measured in Story 19.3
///     (evidence/19-3-task0-memory-indexes.md). A gather on a table of a few hundred rows or more keeps the index plan up to 10,000 rows and beyond.
///   - DropSession: deletes the memories of one session on its sign-out, under MemoryOps' lock for the session.
Class OcuTalon.Memory Extends %RegisteredObject
{

/// The most memories Search returns.
Parameter MAXLIMIT = 5;

/// How many nearest and how many keyword hits each list holds before the fusion.
Parameter CANDIDATES = 20;

/// The constant of the reciprocal-rank fusion (AD-21).
Parameter RRFK = 60;

/// The most words the keyword query holds.
Parameter MAXWORDS = 32;

/// How many memories List returns at most.
Parameter LISTLIMIT = 20;

/// Tune gathers the table's statistics at every id that is a multiple of this.
Parameter STATSEVERY = 1000;

/// The most tokens the core-memory block holds (FR-74, NFR-27).
Parameter PINCAPTOKENS = 1000;

/// How many characters one token is estimated to be.
Parameter CHARSPERTOKEN = 4;

/// The most characters the rendered core-memory block holds, the heading, the quotes and the closing blank line included.
Parameter COREMAX = {..#PINCAPTOKENS * ..#CHARSPERTOKEN};

/// The SQL name of the table.
Parameter TABLE = "OcuTalon_Data.Memory";

/// The query of the nearest memories of one owner: parameters are the SessionRef and the query's vector as text. With the table's statistics gathered (Tune)
/// the planner reads EmbeddingIdx and applies the owner while it walks the index (Story 19.3, Task 0); Test.Memory.Volume explains this very text.
Parameter NEARESTSQL = {"SELECT TOP "_..#CANDIDATES_" ID, Ref, Text, SavedAt, Origin, Source, Pinned FROM "_..#TABLE_" WHERE SessionRef = ? ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC"};

/// The query of the best keyword hits of one owner: parameters are the rank argument (the keyword query), the SessionRef and the keyword query.
Parameter KEYWORDSQL = {"SELECT TOP "_..#CANDIDATES_" ID, Ref, Text, SavedAt, Origin, Source, Pinned, "_..#TABLE_"_TextIdxRank(%ID, ?) AS Hit FROM "_..#TABLE_" WHERE SessionRef = ? AND %ID %FIND search_index(TextIdx, ?, 0) ORDER BY Hit DESC"};

/// The memories of the session that answer the query, best first: rows(n) is {"memoryRef", "text", "savedAt", "origin", "source", "pinned"} and rows is a %DynamicArray
/// of at most limit of them (limit is clamped to 1 to MAXLIMIT). See the class description for the ranking. An error status for an empty query, an
/// empty session or a query that cannot be embedded; rows is then an empty array.
ClassMethod Search(sessionRef As %String, query As %String, limit As %Integer = 5, Output rows As %DynamicArray) As %Status
{
	Set rows = []
	Set text = $ZStrip($Get(query), "<>WC")
	If ($Get(sessionRef) = "") || (text = "") Quit $SYSTEM.Status.Error(5001, "A search needs a session and a query")
	Set sc = ##class(OcuTalon.Memory.Embedding).Embed(text, .vector)
	If $$$ISERR(sc) Quit sc
	Set sc = $$$OK
	Try {
		Set nearest = ..Hits(..#NEARESTSQL, sessionRef, ..ToText(vector))
		Set keyword = []
		Set words = ..Words(text)
		If words '= "" {
			Try {
				Set keyword = ..Hits(..#KEYWORDSQL, words, sessionRef, words)
			} Catch keywordFailure {
				Set keyword = []
				Do ##class(Ens.Util.Log).LogWarning($ClassName(), "Search", "The keyword search of the memories failed, so only the nearest memories were used: "_##class(OcuTalon.Bridge.Redact).Text(keywordFailure.DisplayString()))
			}
		}
		Set rows = ..Fuse(nearest, keyword, limit)
	} Catch exception {
		Set rows = []
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The reciprocal-rank fusion of two ranked lists of hits, best first: each hit is {"id", "memoryRef", "text", "savedAt", "origin", "source", "pinned"} with the row id.
/// A memory scores the sum of 1 / (RRFK + its rank, from 1) over the lists that hold it (a memory is the same in both lists when it has the same id).
/// The result is the best limit (clamped to 1 to MAXLIMIT) as {"memoryRef", "text", "savedAt", "origin", "source", "pinned"}, by score, then newer savedAt, then higher id.
ClassMethod Fuse(nearest As %DynamicArray, keyword As %DynamicArray, limit As %Integer = 5) As %DynamicArray
{
	Set limit = $Select(+limit < 1: 1, +limit > ..#MAXLIMIT: ..#MAXLIMIT, 1: +limit \ 1)
	Kill score, info, order
	For list = 1, 2 {
		Set iterator = $Select(list = 1: nearest, 1: keyword).%GetIterator()
		Set rank = 0
		While iterator.%GetNext(, .hit) {
			Set rank = rank + 1
			Set id = hit.id
			Set score(id) = $Get(score(id)) + (1 / (..#RRFK + rank))
			Set info(id) = hit
		}
	}
	Set id = ""
	For {
		Set id = $Order(score(id))
		Quit:id=""
		Set order(+$FNumber(score(id), "", 12), info(id).savedAt, id) = ""
	}
	Set rows = []
	Set total = ""
	For {
		Set total = $Order(order(total), -1)
		Quit:total=""
		Set savedAt = ""
		For {
			Set savedAt = $Order(order(total, savedAt), -1)
			Quit:savedAt=""
			Set id = ""
			For {
				Set id = $Order(order(total, savedAt, id), -1)
				Quit:id=""
				If rows.%Size() < limit {
					Set hit = info(id)
					Do rows.%Push(..Row(hit.memoryRef, hit.text, hit.savedAt, hit.origin, hit.source, hit.pinned))
				}
			}
		}
	}
	Quit rows
}

/// The owner's newest memories (at most LISTLIMIT), newest first, as {memoryRef, text, savedAt, origin, source, pinned} in the %DynamicArray rows, and the number of
/// memories the owner has in total.
ClassMethod List(sessionRef As %String, Output rows As %DynamicArray, Output total As %Integer) As %Status
{
	Set rows = []
	Set total = 0
	If $Get(sessionRef) = "" Quit $SYSTEM.Status.Error(5001, "A list needs a session")
	Set sc = $$$OK
	Try {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..#TABLE_" WHERE SessionRef = ?", sessionRef)
		If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The memories could not be counted: "_rs.%Message))
		If rs.%Next() Set total = rs.%GetData(1)
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP "_..#LISTLIMIT_" Ref, Text, SavedAt, Origin, Source, Pinned FROM "_..#TABLE_" WHERE SessionRef = ? ORDER BY SavedAt DESC, ID DESC", sessionRef)
		If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The memories could not be listed: "_rs.%Message))
		While rs.%Next() {
			Do rows.%Push(..Row(rs.%Get("Ref"), rs.%Get("Text"), rs.%Get("SavedAt"), rs.%Get("Origin"), rs.%Get("Source"), rs.%Get("Pinned")))
		}
	} Catch exception {
		Set rows = []
		Set total = 0
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The owner's pinned memories, newest pin first (PinnedAt, then row id), as {memoryRef, text, savedAt, origin, source, pinned} in the %DynamicArray rows. A row whose stored
/// Pinned is empty (saved before Story 41.8) is not pinned. An empty session is an error status; rows is then an empty array.
ClassMethod Pinned(sessionRef As %String, Output rows As %DynamicArray) As %Status
{
	Set rows = []
	If $Get(sessionRef) = "" Quit $SYSTEM.Status.Error(5001, "A list needs a session")
	Set sc = $$$OK
	Try {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Text, SavedAt, Origin, Source, Pinned FROM "_..#TABLE_" WHERE SessionRef = ? AND COALESCE(Pinned, 0) = 1 ORDER BY PinnedAt DESC, ID DESC", sessionRef)
		If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The memories could not be read: "_rs.%Message))
		While rs.%Next() {
			Do rows.%Push(..Row(rs.%Get("Ref"), rs.%Get("Text"), rs.%Get("SavedAt"), rs.%Get("Origin"), rs.%Get("Source"), rs.%Get("Pinned")))
		}
	} Catch exception {
		Set rows = []
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The core-memory block of the session in block (Agent.Input.CoreBlock of the pinned texts, newest pin first), with the text candidate, when it is not "", counted first
/// as the newest pin. The pin cap and Agent.Input.CorePart both call this method, so they cannot disagree. An empty session is an error status, with block "".
ClassMethod CoreBlock(sessionRef As %String, candidate As %String = "", Output block As %String) As %Status
{
	Set block = ""
	Set sc = ..Pinned(sessionRef, .rows)
	If $$$ISERR(sc) Quit sc
	Set texts = []
	If candidate '= "" Do texts.%Push(candidate)
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do texts.%Push(row.text)
	}
	Set block = ##class(OcuTalon.Agent.Input).CoreBlock(texts)
	Quit $$$OK
}

/// Gathers the SQL statistics of the memory table when id is a multiple of STATSEVERY, and returns 1 when it did, else 0. Throws what the gather
/// throws. A gather takes well under a second at 10,000 rows (Story 19.3, Task 0).
ClassMethod Tune(id As %Integer) As %Boolean
{
	If (+id < 1) || (id # ..#STATSEVERY) Quit 0
	Set sc = $SYSTEM.SQL.Stats.Table.GatherTableStats(..#TABLE)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Quit 1
}

/// Called by SessionOps.End on an online-demo sign-out, in the job of SessionOps: deletes the session's memories, and only those (Story 19.5). It takes
/// the lock that MemoryOps takes for the session (^OcuTalon.Memory(sessionRef), 5 seconds), so a save or a forget in progress is finished first. A lock that
/// is not free in time is an error status, and the sign-out stays resumable. It is idempotent: a session with no memory, an empty or unknown reference and a
/// second call are OK and change nothing.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	If sessionRef = "" Quit $$$OK
	Lock +^OcuTalon.Memory(sessionRef):5
	If '$Test Quit $SYSTEM.Status.Error(5001, "The memories of the session are busy: the lock was not free within 5 seconds")
	Set sc = $$$OK
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ ..#TABLE _ " WHERE SessionRef = ?", sessionRef)
		If result.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "The memories of the session cannot be deleted: " _ result.%Message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Memory(sessionRef)
	Quit sc
}

/// The rows of the SELECT as an array of {"id", "memoryRef", "text", "savedAt", "origin", "source", "pinned"} in the order of the result (its columns are ID, Ref, Text,
/// SavedAt, Origin, Source and Pinned first); throws when the statement fails.
ClassMethod Hits(sql As %String, args... As %String) As %DynamicArray [ Private ]
{
	Set hits = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, args...)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The memories could not be read: "_rs.%Message))
	While rs.%Next() {
		Do hits.%Push(..Row(rs.%Get("Ref"), rs.%Get("Text"), rs.%Get("SavedAt"), rs.%Get("Origin"), rs.%Get("Source"), rs.%Get("Pinned"), rs.%Get("ID")))
	}
	Quit hits
}

/// One memory as the callers read it: {"memoryRef", "text", "savedAt", "origin", "source", "pinned"}, preceded by {"id"} when id is given. source is learned
/// when the row says so and told otherwise, so a row saved before Story 41.8 (empty Source) is told; pinned is 1 or 0 (empty is 0).
ClassMethod Row(memoryRef As %String, text As %String, savedAt As %String, origin As %String, source As %String, pinned As %String, id As %String = "") As %DynamicObject [ Private ]
{
	Set row = {}
	If id '= "" Set row.id = id
	Set row.memoryRef = memoryRef
	Set row.text = text
	Set row.savedAt = savedAt
	Set row.origin = origin
	Set row.source = $Select(source = "learned": "learned", 1: "told")
	Set row.pinned = +pinned
	Quit row
}

/// The keyword query for the text: the OR of its distinct runs of letters and digits (distinct ignoring case), at most MAXWORDS, each in quotes, except
/// the word or (in any case), which is written with a backslash: on build 154 iFind refuses a quoted or with a syntax error, and a word with a backslash is
/// that word (measured in Story 19.3). "" when the text holds none. The words hold nothing but letters and digits, so no iFind operator or punctuation of
/// the text reaches the search.
ClassMethod Words(text As %String) As %String [ Private ]
{
	Set words = ""
	Set count = 0
	Set position = 1
	While (count < ..#MAXWORDS) && $Locate(text, "[\p{L}\p{N}]+", position, end, word) {
		Set position = end
		Set key = $ZConvert(word, "L")
		If $Data(seen(key)) Continue
		Set seen(key) = ""
		Set count = count + 1
		Set words = words _ $Select(words '= "": " OR ", 1: "") _ $Select(key = "or": "\" _ word, 1: """" _ word _ """")
	}
	Quit words
}

/// The values of a vector as comma-separated text, which TO_VECTOR(text, DOUBLE, 384) reads.
ClassMethod ToText(vector As %Vector) As %String [ Private ]
{
	Set text = ""
	For i = 1:1:$VOP("length", vector) {
		Set text = text _ $Select(i > 1: ",", 1: "") _ $VECTOR(vector, i)
	}
	Quit text
}

}
