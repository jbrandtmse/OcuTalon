/// Tests of the read side of the memories, OcuTalon.Memory (Story 19.3; AD-4, AD-21, AD-33). The fusion runs on lists of its own, so that its order, ties and cut
/// need no model; the searches embed through the product's endpoint (the Python package and the baked model are on OcuTalon's Docker image only), so they run
/// there and record one named skip elsewhere (a slot or a developer instance). The fixture owners are the strings zz-mem-sa and zz-mem-sb, which need no Session
/// row, and every row of them is deleted before and after the class.
///   - TestFuseOrder / TestFuseTies / TestFuseOnlyOneList / TestFuseLimit: the reciprocal-rank fusion with k = 60 over two ranked lists: a memory in both lists
///     beats one that is first in one list only; equal scores go to the newer SavedAt and then to the higher row id; a list may be empty (keyword hits alone,
///     meaning hits alone); at most 5 come back (limit 0 is 1, 9 is 5), a memory in both lists once, and a hit's row id never leaves;
///   - TestSearchByMeaning: a question that shares no wording with the memory finds it first, ahead of two memories about other things, and the answer is at most
///     5 rows of {memoryRef, text, savedAt, origin, source, pinned}, an old row (no Source) told and not pinned;
///   - TestSearchByKeyword: the word "Lee" finds the memories that hold it, and text that holds iFind operators, quotes, brackets or question marks finds the
///     same memory and is no error (the keyword query is the OR of the quoted runs of letters and digits);
///   - TestKeywordPromotes: a memory that holds the keyword is first although another memory is nearer to the query by meaning (the control reads the cosine
///     order itself), so the answer is the fusion and not the vector list;
///   - TestOwnerIsolation (AD-4): memories of two owners about the same thing, a search, a list and a count of one never hold the other's, and an owner with no
///     memories gets none;
///   - TestLimit: 8 memories, a search with limit 5, 2, 0 and 99 gives 5, 2, 1 and 5;
///   - TestEmptyQuery: an empty query, a blank one and an empty session are errors with no rows;
///   - TestList: an owner with 25 memories gets the newest 20, newest first, and total 25; each row has its source and pin (a learned row, a pinned row, old rows told and not pinned); another owner's list and an unknown owner's are their own;
///   - TestListTies (QA): 22 memories saved in the same second are listed newest first by row id, the total is 22, and the cut at 20 drops the two saved first;
///   - TestSearchAccentedKeyword (QA): a word with a letter outside ASCII (an u with a diaeresis) finds its memory first although another is nearer by meaning;
///   - TestIndexGlobals: every global that EmbeddingIdx and TextIdx write is in the private database (GetGlobalDest), ^IRIS.KNNIndex stays empty, OCUTALON_DATA
///     holds no ^IRIS.IF.* global, and the private-data check of the installer passes after a row is stored;
///   - TestTune: Tune gathers the table's statistics at an id that is a multiple of STATSEVERY and at no other, and an id of 0 or "" is not one.
Class OcuTalon.Test.Memory.Search Extends %UnitTest.TestCase
{

Parameter A = "zz-mem-sa";

Parameter B = "zz-mem-sb";

Parameter PREFIX = "zz-mem-s";

Method OnBeforeAllTests() As %Status
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
		Merge ^||OcuTalonTestMemorySearch = state
		Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
		Quit sc
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
		Merge state = ^||OcuTalonTestMemorySearch
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestMemorySearch
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// A hit of the fusion's input.
ClassMethod Hit(id As %Integer, ref As %String, savedAt As %String = "2026-11-05T10:00:00Z") As %DynamicObject [ Private ]
{
	Quit {"id": (id), "memoryRef": (ref), "text": ("text of "_ref), "savedAt": (savedAt), "origin": "tool", "source": "learned", "pinned": 1}
}

/// The memoryRef of each row, comma-separated.
ClassMethod Refs(rows As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set text = text _ $Select(text '= "": ",", 1: "") _ row.memoryRef
	}
	Quit text
}

/// A memory in both lists beats one that is first in one list only, and the fusion is not the first list.
Method TestFuseOrder()
{
	Set nearest = [(..Hit(1, "a")), (..Hit(2, "b")), (..Hit(3, "c"))]
	Set keyword = [(..Hit(3, "c"))]
	Set rows = ##class(OcuTalon.Memory).Fuse(nearest, keyword, 5)
	Do $$$AssertEquals(..Refs(rows), "c,a,b", "c, which both lists hold, is first, then the nearest in order")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [], 5)), "a,b,c", "control: the nearest list alone keeps its own order")
	Set first = rows.%Get(0)
	Set keys = ""
	Set iterator = first.%GetIterator()
	While iterator.%GetNext(.name) {
		Set keys = keys _ $Select(keys '= "": ",", 1: "") _ name
	}
	Do $$$AssertEquals(keys, "memoryRef,text,savedAt,origin,source,pinned", "and they are memoryRef, text, savedAt, origin, source and pinned: the row id never leaves")
	Do $$$AssertEquals(first.source_"|"_first.pinned, "learned|1", "the source and the pin of a hit are carried through")
	Set plain = ##class(OcuTalon.Memory).Fuse([{"id": 1, "memoryRef": "a", "text": "x", "savedAt": "2026-11-05T10:00:00Z", "origin": "tool"}], [], 5).%Get(0)
	Do $$$AssertEquals(plain.source_"|"_plain.pinned, "told|0", "a hit with no source and no pin is told and not pinned")
	Set nearest = [(..Hit(1, "a")), (..Hit(2, "b"))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [(..Hit(2, "b"))], 5)), "b,a", "a keyword hit lifts the second nearest above the first")
	Do $$$AssertEquals(##class(OcuTalon.Memory).#RRFK, 60, "the constant of the fusion is 60 (AD-21)")
}

/// Equal scores go to the newer SavedAt and then to the higher row id.
Method TestFuseTies()
{
	Set old = "2026-11-05T10:00:00Z"
	Set new = "2026-11-05T11:00:00Z"
	Set nearest = [(..Hit(5, "x", old)), (..Hit(6, "y", new))]
	Set keyword = [(..Hit(6, "y", new)), (..Hit(5, "x", old))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, keyword, 5)), "y,x", "x is first by the nearest list and second by the keyword list and y the other way round: a tie, and the newer y is first")
	Set nearest = [(..Hit(5, "x", new)), (..Hit(6, "y", old))]
	Set keyword = [(..Hit(6, "y", old)), (..Hit(5, "x", new))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, keyword, 5)), "x,y", "the same tie with x the newer: x is first")
	Set nearest = [(..Hit(5, "x", old)), (..Hit(6, "y", old))]
	Set keyword = [(..Hit(6, "y", old)), (..Hit(5, "x", old))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, keyword, 5)), "y,x", "a tie in SavedAt too goes to the higher row id: y")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse([(..Hit(1, "m", old))], [(..Hit(2, "k", new))], 5)), "k,m", "the first of each list scores alike: the newer is first")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse([(..Hit(2, "m", old))], [(..Hit(1, "k", old))], 5)), "m,k", "and with the same SavedAt the higher row id")
}

/// Keyword hits alone and meaning hits alone are returned in their own order; no list is no memory.
Method TestFuseOnlyOneList()
{
	Set rows = ##class(OcuTalon.Memory).Fuse([], [(..Hit(1, "k1")), (..Hit(2, "k2"))], 5)
	Do $$$AssertEquals(..Refs(rows), "k1,k2", "keyword hits alone keep the keyword order")
	Set rows = ##class(OcuTalon.Memory).Fuse([(..Hit(1, "m1")), (..Hit(2, "m2"))], [], 5)
	Do $$$AssertEquals(..Refs(rows), "m1,m2", "meaning hits alone keep the nearest order")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Fuse([], [], 5).%Size(), 0, "no hits give no memory")
}

/// At most 5 come back, limit is clamped to 1 to 5, and a memory in both lists is one row.
Method TestFuseLimit()
{
	Set nearest = []
	For i = 1:1:8 Do nearest.%Push(..Hit(i, "n"_i))
	Do $$$AssertEquals(##class(OcuTalon.Memory).Fuse(nearest, [], 5).%Size(), 5, "limit 5 gives 5 of 8")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Fuse(nearest, [], 2).%Size(), 2, "limit 2 gives 2")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Fuse(nearest, [], 0).%Size(), 1, "limit 0 is 1")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Fuse(nearest, [], 9).%Size(), 5, "limit 9 is 5")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Fuse(nearest, [], 5).%Get(0).memoryRef, "n1", "the best is first")
	Set both = ##class(OcuTalon.Memory).Fuse([(..Hit(1, "a")), (..Hit(2, "b"))], [(..Hit(2, "b")), (..Hit(1, "a"))], 5)
	Do $$$AssertEquals(both.%Size(), 2, "a memory in both lists is one row")
}

/// Pins the stored memory with the Ref (a fixture row saved with Pinned 1).
Method Pin(ref As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(ref)
	Set row.Pinned = 1
	Do $$$AssertStatusOK(row.%Save(), "the memory "_ref_" is pinned")
}

/// A question that shares no wording with a memory finds it first.
Method TestSearchByMeaning()
{
	If '..OnImage() Quit
	Set when = "2026-11-05T10:00:0"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "the warehouse closes at six on Fridays", when_"1Z"), "a memory about the warehouse is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa2", "invoices are paid by bank transfer within thirty days", when_"2Z", , , "learned"), "one about invoices")
	Do ..Pin("zzmsa2")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa3", "the Results partner's contact is Lee", when_"3Z"), "and the one about the contact")
	Set sc = ##class(OcuTalon.Memory).Search(..#A, "who do I call about Results?", 5, .rows)
	Do $$$AssertStatusOK(sc, "the search answers")
	Do $$$AssertEquals(rows.%Get(0).memoryRef, "zzmsa3", "the memory about the contact is first")
	Do $$$AssertEquals(rows.%Get(0).text_"|"_rows.%Get(0).savedAt_"|"_rows.%Get(0).origin_"|"_rows.%Get(0).source_"|"_rows.%Get(0).pinned, "the Results partner's contact is Lee|"_when_"3Z|tool|told|0", "with its text, the stored SavedAt, its origin, and (as an old row) the source told and no pin")
	Set learnedPin = ""
	For i = 0:1:rows.%Size() - 1 {
		If rows.%Get(i).memoryRef = "zzmsa2" Set learnedPin = rows.%Get(i).source_"|"_rows.%Get(i).pinned
	}
	Do $$$AssertEquals(learnedPin, "learned|1", "a stored learned memory that is pinned comes back from the search as learned and pinned 1")
	Set sc = ##class(OcuTalon.Memory).Search(..#A, "name of the person to phone regarding our external collaborator", 5, .rows)
	Do $$$AssertStatusOK(sc, "a question with other words answers")
	Do $$$AssertEquals(rows.%Get(0).memoryRef, "zzmsa3", "and finds the memory first by meaning")
}

/// The keyword Lee finds the memories that hold it, and operators and punctuation in the text mean nothing.
Method TestSearchByKeyword()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "the Results partner's contact is Lee", "2026-11-05T10:00:01Z", , , "learned"), "a memory that holds Lee is stored")
	Do ..Pin("zzmsa1")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa2", "the warehouse closes at six on Fridays", "2026-11-05T10:00:02Z"), "and one that does not")
	Set sc = ##class(OcuTalon.Memory).Search(..#A, "Lee", 5, .rows)
	Do $$$AssertStatusOK(sc, "the search answers")
	Do $$$AssertEquals(rows.%Get(0).memoryRef, "zzmsa1", "the memory with Lee is first")
	Do $$$AssertEquals(rows.%Get(0).source_"|"_rows.%Get(0).pinned, "learned|1", "and it is learned and pinned 1 (the keyword rows carry both)")
	For text = "Lee) OR (NOT lee", "lee* AND ""Lee", "Lee? NOT tea", "[Lee, x, 3] OR NOT", "tea or Lee", "OR or Or Lee", "lee" {
		Set sc = ##class(OcuTalon.Memory).Search(..#A, text, 5, .rows)
		Do $$$AssertStatusOK(sc, "the text '"_text_"' is no error")
		Do $$$AssertEquals($Select(rows.%Size() > 0: rows.%Get(0).memoryRef, 1: ""), "zzmsa1", "and it finds the same memory first")
	}
	Set sc = ##class(OcuTalon.Memory).Search(..#A, "?!( )", 5, .rows)
	Do $$$AssertStatusOK(sc, "a text with no letter or digit is no error")
	Do $$$AssertEquals(rows.%Size(), 2, "it has no keyword hit and is answered by meaning alone: both memories")
}

/// A memory that holds the keyword is first although another is nearer by meaning.
Method TestKeywordPromotes()
{
	If '..OnImage() Quit
	Set when = "2026-11-05T10:00:0"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "Leigh Rowe is our contact in sales", when_"1Z"), "a memory about a person with a name like Lee")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa2", "Morgan is the name of my manager", when_"2Z"), "another about a person's name")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa3", "my neighbour's name is Sam", when_"3Z"), "another about a name")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa4", "The quarterly board meeting agenda covers budgets, hiring plans, office moves and security audits, and ends with a thank you to Lee", when_"4Z"), "and the one that holds the word Lee in a long text about something else")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed("Lee", .vector), "the query Lee is embedded for the control")
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT TOP 1 Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ? ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC"), "the control query prepares")
	Set result = statement.%Execute(..#A, ##class(OcuTalon.Test.Memory.Fixture).ToString(vector))
	Do $$$AssertTrue(result.%Next(), "and runs")
	Do $$$AssertNotEquals(result.%Get("Ref"), "zzmsa4", "control: the memory with the word is not the nearest by meaning")
	Set sc = ##class(OcuTalon.Memory).Search(..#A, "Lee", 5, .rows)
	Do $$$AssertStatusOK(sc, "the search answers")
	Do $$$AssertEquals(rows.%Get(0).memoryRef, "zzmsa4", "and the memory with the word is first: the fusion, not the nearest list")
}

/// Two owners' memories about the same thing never cross.
Method TestOwnerIsolation()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "the Results partner's contact is Lee", "2026-11-05T10:00:01Z"), "A's memory is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#B, "zzmsb1", "the Results partner's contact is Kim", "2026-11-05T10:00:02Z"), "B's memory about the same thing")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#B, "zzmsb2", "Lee owes B a coffee", "2026-11-05T10:00:03Z"), "and another of B's with the word Lee")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, "who is the Results partner's contact?", 5, .rows), "A searches")
	Do $$$AssertEquals(..Refs(rows), "zzmsa1", "and sees only A's memory")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, "Lee", 5, .rows), "A searches for the keyword")
	Do $$$AssertEquals(..Refs(rows), "zzmsa1", "and still only A's, although B's holds the word too")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#B, "Lee", 5, .rows), "B searches for the keyword")
	Do $$$AssertTrue(rows.%Size() = 2, "B sees its two")
	Do $$$AssertEquals(rows.%Get(0).memoryRef, "zzmsb2", "the one with Lee first")
	Do $$$AssertTrue('(..Refs(rows) [ "zzmsa1"), "and not A's")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).List(..#A, .list, .total), "A lists")
	Do $$$AssertEquals(..Refs(list)_"|"_total, "zzmsa1|1", "and sees its one memory with total 1")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).List(..#B, .list, .total), "B lists")
	Do $$$AssertEquals(total, 2, "and sees its two")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search("zz-mem-snone", "Lee", 5, .rows), "an owner with no memories searches")
	Do $$$AssertEquals(rows.%Size(), 0, "and gets none")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).List("zz-mem-snone", .list, .total), "and lists")
	Do $$$AssertEquals(list.%Size()_"|"_total, "0|0", "and gets none and total 0")
}

/// The limit is 1 to 5.
Method TestLimit()
{
	If '..OnImage() Quit
	For i = 1:1:8 {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa"_i, "the project code word number "_i_" is saved", "2026-11-05T10:00:0"_i_"Z"), "memory "_i_" is stored")
	}
	Set expected = $ListBuild(5, 5, 2, 2, 0, 1, 99, 5)
	For i = 1:2:7 {
		Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, "project code word", $List(expected, i), .rows), "a search with limit "_$List(expected, i)_" answers")
		Do $$$AssertEquals(rows.%Size(), $List(expected, i + 1), "with "_$List(expected, i + 1)_" rows")
	}
}

/// An empty query, a blank one and an empty session are errors.
Method TestEmptyQuery()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "the Results partner's contact is Lee", "2026-11-05T10:00:01Z"), "a memory is stored")
	For query = "", "   ", $Char(9, 10) {
		Set sc = ##class(OcuTalon.Memory).Search(..#A, query, 5, .rows)
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "the query '"_$ZConvert(query, "O", "JSON")_"' is an error")
		Do $$$AssertEquals(rows.%Size(), 0, "with no rows")
	}
	Set sc = ##class(OcuTalon.Memory).Search("", "Lee", 5, .rows)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "an empty session is an error")
	Do $$$AssertEquals(rows.%Size(), 0, "with no rows")
	Do $$$AssertTrue($SYSTEM.Status.IsError(##class(OcuTalon.Memory).List("", .rows, .total)), "and so is listing for it")
}

/// The newest 20 of 25, newest first, with the total.
Method TestList()
{
	If '..OnImage() Quit
	For i = 1:1:25 {
		Do ##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa"_i, "list memory "_i, "2026-11-05T10:00:"_$Extract(100 + i, 2, 3)_"Z", , , $Select(i = 24: "learned", i = 23: "told", 1: ""))
	}
	Set pinned = ##class(OcuTalon.Data.Memory).RefIndexOpen("zzmsa23")
	Set pinned.Pinned = 1
	Do $$$AssertStatusOK(pinned.%Save(), "one memory is pinned")
	Set pinned = ""
	Do ##class(OcuTalon.Test.Memory.Fixture).Store(..#B, "zzmsb1", "list memory of B", "2026-11-05T10:01:00Z", "system")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).List(..#A, .rows, .total), "A lists")
	Do $$$AssertEquals(total, 25, "the total is 25")
	Do $$$AssertEquals(rows.%Size(), 20, "and 20 rows come back")
	Do $$$AssertEquals(rows.%Get(0).memoryRef_"|"_rows.%Get(19).memoryRef, "zzmsa25|zzmsa6", "the newest first and the 20th newest last")
	Do $$$AssertEquals(rows.%Get(0).text_"|"_rows.%Get(0).savedAt_"|"_rows.%Get(0).origin_"|"_rows.%Get(0).source_"|"_rows.%Get(0).pinned, "list memory 25|2026-11-05T10:00:25Z|tool|told|0", "a row holds text, savedAt, origin, source and pinned, and an old row (no Source) is told and not pinned")
	Do $$$AssertEquals(rows.%Get(1).memoryRef_"|"_rows.%Get(1).source_"|"_rows.%Get(1).pinned, "zzmsa24|learned|0", "a learned row is learned and not pinned")
	Do $$$AssertEquals(rows.%Get(2).memoryRef_"|"_rows.%Get(2).source_"|"_rows.%Get(2).pinned, "zzmsa23|told|1", "a told row that is pinned is told and pinned 1")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).List(..#B, .rows, .total), "B lists")
	Do $$$AssertEquals(rows.%Size()_"|"_total_"|"_rows.%Get(0).memoryRef_"|"_rows.%Get(0).origin_"|"_rows.%Get(0).source, "1|1|zzmsb1|system|told", "B has its one, with the origin it was stored with")
}

/// Memories saved in the same second are listed newest first by row id, and the cut at 20 keeps the last saved (QA; matrix "List").
Method TestListTies()
{
	If '..OnImage() Quit
	For i = 1:1:22 {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa"_$Extract(100 + i, 2, 3), "tied memory "_i, "2026-11-05T10:00:00Z"), "memory "_i_" is stored in the same second as the others")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).List(..#A, .rows, .total), "A lists")
	Do $$$AssertEquals(total_"|"_rows.%Size(), "22|20", "the total is 22 and 20 rows come back")
	Do $$$AssertEquals(rows.%Get(0).memoryRef_"|"_rows.%Get(1).memoryRef_"|"_rows.%Get(19).memoryRef, "zzmsa22|zzmsa21|zzmsa03", "with the same SavedAt the higher row id is first, and the two saved first are the ones cut")
}

/// A keyword with a letter outside ASCII finds its memory first, although another is nearer by meaning (QA): the words of the keyword query are runs of letters, not of ASCII letters.
Method TestSearchAccentedKeyword()
{
	If '..OnImage() Quit
	Set word = "M" _ $Char(252) _ "ller"
	Set when = "2026-11-05T10:00:0"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "Mueller is the name of my neighbour's dog", when_"1Z"), "a memory about a similar name is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa2", "Muller is a surname that is common in Germany", when_"2Z"), "another")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa3", "Moller and Miller are surnames too", when_"3Z"), "another")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa4", "The quarterly board meeting agenda covers budgets, hiring plans, office moves and security audits, and ends with a thank you to " _ word, when_"4Z"), "and the one that holds the word with the accented letter in a long text about something else")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(word, .vector), "the query is embedded for the control")
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT TOP 1 Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ? ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC"), "the control query prepares")
	Set result = statement.%Execute(..#A, ##class(OcuTalon.Test.Memory.Fixture).ToString(vector))
	Do $$$AssertTrue(result.%Next(), "and runs")
	Do $$$AssertNotEquals(result.%Get("Ref"), "zzmsa4", "control: the memory with the word is not the nearest by meaning")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, word, 5, .rows), "the search answers")
	Do $$$AssertEquals(rows.%Get(0).memoryRef, "zzmsa4", "and the memory with the word is first: the keyword leg took the word whole")
}

/// Every global of the indexes is in the private database, and the installer's check passes after a row is stored.
Method TestIndexGlobals()
{
	If '..OnImage() Quit
	Set private = ..PrivateDirectory()
	Do $$$AssertTrue(private '= "", "the private database is found: "_private)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmsa1", "the Results partner's contact is Lee", "2026-11-05T10:00:01Z"), "a memory is stored")
	For global = "^OcuTalonP.MemoryD", "^OcuTalonP.MemoryI", "^OcuTalonP.MemoryI(""EmbeddingIdx"")", "^OcuTalonP.MemoryI(""TextIdx"")" {
		Set resolved = ##class(%SYS.Namespace).GetGlobalDest($Namespace, global)
		Do $$$AssertEquals(##class(%File).NormalizeDirectory($Piece(resolved, "^", 2)), private, global_" resolves to the private database")
	}
	Do $$$AssertTrue($Data(^OcuTalonP.MemoryI("EmbeddingIdx", "G")) > 0, "the HNSW graph is under the index global")
	Do $$$AssertTrue($Data(^OcuTalonP.MemoryI("TextIdx")) > 0, "and so are the keyword entries")
	Do $$$AssertEquals($Data(^IRIS.KNNIndex), 0, "^IRIS.KNNIndex, the fallback of the HNSW index, holds nothing")
	Do $$$AssertEquals(..DataNames("IRIS.IF."), "", "the data database holds no ^IRIS.IF.* global")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "and the private-data check of the installer passes")
}

/// Tune gathers at multiples of STATSEVERY only.
Method TestTune()
{
	Set every = ##class(OcuTalon.Memory).#STATSEVERY
	Do $$$AssertTrue(every > 1, "STATSEVERY is more than 1: "_every)
	Do $$$AssertEquals(##class(OcuTalon.Memory).Tune(every - 1), 0, "an id before the multiple gathers nothing")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Tune(0), 0, "id 0 gathers nothing")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Tune(""), 0, "an empty id gathers nothing")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Tune(every + 1), 0, "nor an id after it")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Tune(every), 1, "the multiple gathers the statistics")
	Do $$$AssertEquals(##class(OcuTalon.Memory).Tune(2 * every), 1, "and so does the next")
}

/// The directory of OCUTALON_PRIVATE with its trailing slash, or "".
ClassMethod PrivateDirectory() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Config.Databases).Get("OCUTALON_PRIVATE", .properties) Quit ""
	Quit ##class(%File).NormalizeDirectory(properties("Directory"))
}

/// The globals of the data database that start with the prefix, comma-separated, "" when there is none. The data database is the one that the default mapping
/// of an unmapped global of the namespace names.
ClassMethod DataNames(prefix As %String) As %String [ Private ]
{
	Set data = ##class(%File).NormalizeDirectory($Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonZzUnmapped"), "^", 2))
	Set reference = "^^" _ data
	Set found = ""
	Set name = $Order(^$|reference|GLOBAL(""))
	While name '= "" {
		If $Extract(name, 2, $Length(prefix) + 1) = prefix Set found = found _ $Select(found '= "": ",", 1: "") _ name
		Set name = $Order(^$|reference|GLOBAL(name))
	}
	Quit found
}

}
