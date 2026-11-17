/// Tests of the fading of unused memories (Story 28.2; AD-19, AD-21, FR-43). The fusion runs on lists of its own (no model), and the searches embed through the product's endpoint
/// (the Python package and the baked model are on OcuTalon's Docker image only), so they run there and record one named skip elsewhere. The fixture owners are the strings
/// zz-mem-fa and zz-mem-fb, which need no Session row (the forgetting test makes a Session row of its own), and every row of them is deleted before and after the class. The
/// product setting memory.fadeDays is put back as the test found it.
///   - TestFuseFadesOnlyTheUnused: a memory last used (else saved) before fadeBefore ranks below one that is not, though it was the better match; a memory last used inside the
///     period is not weighted although it was saved before it; an empty LastUsedAt reads as SavedAt, and a hit with no lastUsedAt at all too;
///   - TestFuseEqualMatchRecentFirst: two unpinned memories of the same fused score, the older one never used and the other used recently: the recently used one is first (control: with
///     no fadeBefore the newer SavedAt wins the tie);
///   - TestFuseOnlyMatchStillReturned: when only faded memories match, they are all returned, in the order of their scores, so fading never drops a memory;
///   - TestFusePinnedNeverFades: a pinned memory is not weighted down however old it is (control: unpinned, it ranks below the other);
///   - TestFuseNothingFadedIsUnchanged (the equivalence pin without a model): hard-coded lists give the same refs in the same order with no fadeBefore and with a fadeBefore that is
///     before every memory, and the order keys, ties and cut are those of the fusion before this story;
///   - TestFadeDays: the setting memory.fadeDays is read through Data.Setting, and an absent, empty, non-numeric, zero, negative or fractional value is 90 days;
///   - TestSearchFadedRanksBelow: with stored memories, the exact match that was never used and was saved 100 days ago comes back second after a memory that was last used a day
///     ago, with the period at 90 days; with the period at 3650 days it is first (the setting is read by Search); both are returned;
///   - TestSearchOnlyFadedMatchReturned: with the period at 90 days, a memory saved 400 days ago and never used is returned when nothing else matches; a forgotten one (a Ref new to the
///     run, so that a run that stopped before its clean-up leaves nothing in the way of the next) is never returned again;
///   - TestSearchPinnedNeverFades: the pinned memory that was never used and was saved 100 days ago stays first at 90 days;
///   - TestEquivalenceHardCoded: over a fixed set of five memories (mixed LastUsedAt, one pinned, all saved inside the period, which the test sets to 90 days), Search returns the hard-coded refs in the hard-coded
///     order, the same as the fusion with no fadeBefore;
///   - TestEquivalenceEvalFixtures: over the memories that the eval's memory cases seed (the folder eval/ as mounted in a throwaway or CI stack: the facts that a session's
///     forgotten member holds and the turns of the memory cases), stored with a mix of empty and recent LastUsedAt, a pin and SavedAt inside the period (set to 90 days), Search returns for each question of
///     those cases exactly the refs, order and texts that the fusion with no fadeBefore returns over the same two lists.
Class OcuTalon.Test.Memory.Fade Extends %UnitTest.TestCase
{

Parameter A = "zz-mem-fa";

Parameter B = "zz-mem-fb";

Parameter PREFIX = "zz-mem-f";

/// The text that the ranking tests search for and store.
Parameter EXACT = "the Results partner's contact is Lee";

/// The setting's state before the class: "" when it had no row, else the value, in ^||OcuTalonTestMemoryFade.
Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTestMemoryFade
	Set key = ##class(OcuTalon.Memory).#FADEKEY
	If ##class(OcuTalon.Data.Setting).KeyIndexExists(key) Set ^||OcuTalonTestMemoryFade = $ListBuild(1, ##class(OcuTalon.Data.Setting).Fresh(key))
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
		Merge ^||OcuTalonTestMemoryFade("state") = state
		Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
		Quit sc
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..PutSetting($Get(^||OcuTalonTestMemoryFade, ""))
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
		Merge state = ^||OcuTalonTestMemoryFade("state")
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestMemoryFade
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..PutSetting($Get(^||OcuTalonTestMemoryFade, ""))
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// Puts the setting memory.fadeDays as it was before the class (saved is "" for no row, else $ListBuild(1, value)).
Method PutSetting(saved As %List) [ Private ]
{
	Do ##class(OcuTalon.Test.Memory.Fixture).PutFade(saved)
}

/// Gives the setting memory.fadeDays the value (a row with an empty value for "").
Method SetDays(value As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(##class(OcuTalon.Memory).#FADEKEY, value), "memory.fadeDays is '"_value_"'")
}

/// The UTC time that many days before now.
ClassMethod Ago(days As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -days * 86400)
}

/// A hit of the fusion's input, unpinned and never used unless the arguments say so.
ClassMethod Hit(id As %Integer, ref As %String, savedAt As %String, lastUsedAt As %String = "", pinned As %Boolean = 0) As %DynamicObject [ Private ]
{
	Quit {"id": (id), "memoryRef": (ref), "text": ("text of "_ref), "savedAt": (savedAt), "origin": "tool", "source": "told", "pinned": (pinned), "lastUsedAt": (lastUsedAt)}
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

/// A memory last used (else saved) before fadeBefore ranks below one that is not, though it was the better match, and only the unused one is weighted.
Method TestFuseFadesOnlyTheUnused()
{
	Set before = ..Ago(90)
	Set old = ..Ago(100)
	Set recent = ..Ago(1)
	Set nearest = [(..Hit(1, "a", old)), (..Hit(2, "b", recent))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [], 5)), "a,b", "control: with no fadeBefore the better match a is first")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [], 5, before)), "b,a", "a, saved 100 days ago and never used, is weighted down by 0.5 and falls below b, which is inside the period")
	Set nearest = [(..Hit(1, "a", old, recent)), (..Hit(2, "b", recent))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [], 5, before)), "a,b", "a, saved 100 days ago and used yesterday, is not weighted")
	Set nearest = [{"id": 1, "memoryRef": "a", "text": "x", "savedAt": (old), "origin": "tool"}, (..Hit(2, "b", recent))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [], 5, before)), "b,a", "a hit with no lastUsedAt and no pinned member reads as saved 100 days ago and unpinned: weighted")
	Set nearest = [(..Hit(1, "a", recent, old)), (..Hit(2, "b", recent))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [], 5, before)), "b,a", "a was last used 100 days ago, whatever its SavedAt: weighted")
	Set rows = ##class(OcuTalon.Memory).Fuse([(..Hit(1, "a", old)), (..Hit(2, "b", recent))], [], 5, before)
	Set keys = ""
	Set iterator = rows.%Get(0).%GetIterator()
	While iterator.%GetNext(.name) {
		Set keys = keys _ $Select(keys '= "": ",", 1: "") _ name
	}
	Do $$$AssertEquals(keys, "memoryRef,text,savedAt,origin,source,pinned", "the output has the keys it had before fading: no id and no lastUsedAt")
	Do $$$AssertEquals(+##class(OcuTalon.Memory).#FADEWEIGHT, 0.5, "the weight is 0.5")
}

/// Equal fused score, one never used and saved 100 days ago, the other used a day ago: the recent one is first.
Method TestFuseEqualMatchRecentFirst()
{
	Set before = ..Ago(90)
	Set a = ..Hit(1, "a", ..Ago(100))
	Set b = ..Hit(2, "b", ..Ago(200), ..Ago(1))
	Set nearest = [(a), (b)]
	Set keyword = [(b), (a)]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, keyword, 5)), "a,b", "control: the two score alike, and with no fadeBefore the newer SavedAt a wins the tie")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, keyword, 5, before)), "b,a", "with the period, the recently used b is first")
}

/// Only faded memories match: all of them are returned, in the order of their scores.
Method TestFuseOnlyMatchStillReturned()
{
	Set before = ..Ago(90)
	Set rows = ##class(OcuTalon.Memory).Fuse([(..Hit(1, "a", ..Ago(400)))], [], 5, before)
	Do $$$AssertEquals(..Refs(rows), "a", "the only match, 400 days old and never used, is returned")
	Set nearest = [(..Hit(1, "a", ..Ago(400))), (..Hit(2, "b", ..Ago(300))), (..Hit(3, "c", ..Ago(200)))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(nearest, [(..Hit(3, "c", ..Ago(200)))], 5, before)), "c,a,b", "all faded: all three come back, by their scores")
}

/// A pinned memory is not weighted down however old it is.
Method TestFusePinnedNeverFades()
{
	Set before = ..Ago(90)
	Set recent = ..Ago(1)
	Set pinned = [(..Hit(1, "a", ..Ago(400), "", 1)), (..Hit(2, "b", recent))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(pinned, [], 5, before)), "a,b", "the pinned a, 400 days old and never used, stays first")
	Set unpinned = [(..Hit(1, "a", ..Ago(400))), (..Hit(2, "b", recent))]
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(unpinned, [], 5, before)), "b,a", "control: unpinned, a is weighted down below b")
}

/// With nothing faded the fusion is the one that this story found: hard-coded refs in order, with no fadeBefore and with a fadeBefore before every memory.
Method TestFuseNothingFadedIsUnchanged()
{
	Set early = "2000-01-01T00:00:00Z"
	Set old = "2026-11-05T10:00:00Z"
	Set new = "2026-11-05T11:00:00Z"
	Set cases(1, "nearest") = [(..Hit(1, "a", old)), (..Hit(2, "b", old)), (..Hit(3, "c", old))], cases(1, "keyword") = [(..Hit(3, "c", old))], cases(1) = "c,a,b"
	Set cases(2, "nearest") = [(..Hit(5, "x", old)), (..Hit(6, "y", new))], cases(2, "keyword") = [(..Hit(6, "y", new)), (..Hit(5, "x", old))], cases(2) = "y,x"
	Set cases(3, "nearest") = [(..Hit(5, "x", new)), (..Hit(6, "y", old))], cases(3, "keyword") = [(..Hit(6, "y", old)), (..Hit(5, "x", new))], cases(3) = "x,y"
	Set cases(4, "nearest") = [(..Hit(5, "x", old)), (..Hit(6, "y", old))], cases(4, "keyword") = [(..Hit(6, "y", old)), (..Hit(5, "x", old))], cases(4) = "y,x"
	Set cases(5, "nearest") = [(..Hit(1, "m", old))], cases(5, "keyword") = [(..Hit(2, "k", new))], cases(5) = "k,m"
	Set cases(6, "nearest") = [], cases(6, "keyword") = [(..Hit(1, "k1", old)), (..Hit(2, "k2", old))], cases(6) = "k1,k2"
	Set cases(7, "nearest") = [(..Hit(1, "m1", new)), (..Hit(2, "m2", old))], cases(7, "keyword") = [], cases(7) = "m1,m2"
	For n = 1:1:7 {
		Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(cases(n, "nearest"), cases(n, "keyword"), 5)), cases(n), "case "_n_": no fadeBefore gives "_cases(n))
		Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(cases(n, "nearest"), cases(n, "keyword"), 5, early)), cases(n), "case "_n_": a fadeBefore before every memory gives the same")
	}
	Set many = []
	For i = 1:1:8 {
		Do many.%Push(..Hit(i, "m"_i, old))
	}
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Memory).Fuse(many, [], 5, early)), "m1,m2,m3,m4,m5", "the cut at five is unchanged")
}

/// The setting is read through Data.Setting; anything but a whole number of 1 or more is 90.
Method TestFadeDays()
{
	Do $$$AssertEquals(##class(OcuTalon.Memory).#FADEKEY_"|"_##class(OcuTalon.Memory).#FADEDAYS, "memory.fadeDays|90", "the key and the default")
	Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(##class(OcuTalon.Memory).#FADEKEY)
	Kill ^||OcuTalon.Setting(##class(OcuTalon.Memory).#FADEKEY)
	Do $$$AssertEquals(##class(OcuTalon.Memory).FadeDays(), 90, "with no row: 90")
	Set values = $ListBuild("", "abc", "0", "-3", "1.5", "1e2", "45", " 30 ", "007", "1")
	Set expected = $ListBuild(90, 90, 90, 90, 90, 90, 45, 30, 7, 1)
	For i = 1:1:$ListLength(values) {
		Do ..SetDays($List(values, i))
		Do $$$AssertEquals(##class(OcuTalon.Memory).FadeDays(), $List(expected, i), "the value '"_$List(values, i)_"' is "_$List(expected, i)_" days")
	}
}

/// The exact match that was never used and was saved 100 days ago falls below a memory used a day ago once the period is 90 days; at 3650 days it is first.
Method TestSearchFadedRanksBelow()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmfa1", ..#EXACT, ..Ago(100)), "the exact match, saved 100 days ago and never used, is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmfa2", ..#EXACT_", who works in Berlin", ..Ago(200), , , , ..Ago(1)), "and a longer one, saved 200 days ago and used yesterday")
	Do ..SetDays(3650)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, ..#EXACT, 5, .rows), "a search with a period of 3650 days answers")
	Do $$$AssertEquals(..Refs(rows), "zzmfa1,zzmfa2", "the exact match is first: nothing has faded")
	Do ..SetDays(90)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, ..#EXACT, 5, .rows), "a search with a period of 90 days answers")
	Do $$$AssertEquals(..Refs(rows), "zzmfa2,zzmfa1", "the memory used yesterday is first and the faded one is still returned")
	Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(##class(OcuTalon.Memory).#FADEKEY)
	Kill ^||OcuTalon.Setting(##class(OcuTalon.Memory).#FADEKEY)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, ..#EXACT, 5, .rows), "a search with no setting answers")
	Do $$$AssertEquals(..Refs(rows), "zzmfa2,zzmfa1", "and the period is 90 days")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#B, "zzmfb1", ..#EXACT, ..Ago(100)), "another owner's memory of the same text is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, ..#EXACT, 5, .rows), "A searches again")
	Do $$$AssertEquals(..Refs(rows), "zzmfa2,zzmfa1", "and fading never brings in another owner's memory")
}

/// A faded memory that is the only match is returned, and a forgotten one never comes back.
Method TestSearchOnlyFadedMatchReturned()
{
	If '..OnImage() Quit
	Do ..SetDays(90)
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzfadeforget")
	Set forgotten = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmfa1", ..#EXACT, ..Ago(400)), "a memory saved 400 days ago and never used is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, "Lee", 5, .rows), "a search answers")
	Do $$$AssertEquals(..Refs(rows), "zzmfa1", "the faded memory is the only match and is returned")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, forgotten, ..#EXACT, ..Ago(400)), "the same for a session that has a row")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(session, "Lee", 5, .rows), "it is found")
	Do $$$AssertEquals(..Refs(rows), forgotten, "when it is faded")
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Memory.Ops", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of MemoryOps is made")
	Set command = ##class(OcuTalon.Msg.Command.ForgetMemory).%New()
	Set command.SessionRef = session
	Set command.MemoryRef = forgotten
	Do $$$AssertStatusOK(host.OnForget(command, .response), "the owner forgets it")
	Do $$$AssertEquals(response.Outcome, "forgotten", "and it is forgotten")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(session, "Lee", 5, .rows), "a search answers")
	Do $$$AssertEquals(rows.%Size(), 0, "the forgotten memory never comes back, faded or not")
	Do ##class(OcuTalon.Test.Memory.Fixture).Purge(session)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(session)
}

/// A pinned memory that was never used and was saved 100 days ago stays first at 90 days.
Method TestSearchPinnedNeverFades()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmfa1", ..#EXACT, ..Ago(100), , , , , 1), "the pinned exact match, saved 100 days ago and never used, is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzmfa2", ..#EXACT_", who works in Berlin", ..Ago(200), , , , ..Ago(1)), "and a longer one used yesterday")
	Do ..SetDays(90)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, ..#EXACT, 5, .rows), "a search answers")
	Do $$$AssertEquals(..Refs(rows), "zzmfa1,zzmfa2", "the pinned memory is not weighted down and stays first")
	Do $$$AssertEquals(rows.%Get(0).pinned, 1, "and it is a pinned row")
}

/// The reference of the equivalence pins: the fusion of the two lists that Search builds, with no fadeBefore (the fusion as it was before this story). rows is its result.
Method Reference(owner As %String, query As %String, Output rows As %DynamicArray) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(query, .vector), "the query '"_query_"' is embedded for the reference")
	Set nearest = ##class(OcuTalon.Memory).Hits(##class(OcuTalon.Memory).#NEARESTSQL, owner, ##class(OcuTalon.Memory).ToText(vector))
	Set words = ##class(OcuTalon.Memory).Words(query)
	Set keyword = $Select(words = "": [], 1: ##class(OcuTalon.Memory).Hits(##class(OcuTalon.Memory).#KEYWORDSQL, words, owner, words))
	Set rows = ##class(OcuTalon.Memory).Fuse(nearest, keyword, 5)
}

/// Stores the texts as the memories of the owner, with a mix of states, all inside the period: memory i is saved i + 1 days ago, every second one is used a day ago, every third is
/// told, and the third is pinned. Returns the number stored. The refs are <prefix>1, <prefix>2, ...
Method StoreMixed(owner As %String, prefix As %String, texts As %List) As %Integer [ Private ]
{
	Set position = 0
	Set n = 0
	While $ListNext(texts, position, text) {
		Set n = n + 1
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(owner, prefix_n, text, ..Ago(n + 1), , , $Select(n # 3 = 0: "told", 1: "learned"), $Select(n # 2 = 0: ..Ago(1), 1: ""), (n = 3)), "memory "_n_" is stored")
	}
	Quit n
}

/// Over a fixed set of five memories Search returns the hard-coded refs in the hard-coded order, which is the fusion's own with no fadeBefore.
Method TestEquivalenceHardCoded()
{
	If '..OnImage() Quit
	Do ..SetDays(90)
	Set texts = $ListBuild("the Results partner's contact is Lee", "the warehouse closes at six on Fridays", "Morgan is the name of my manager", "the quarterly board meeting agenda covers budgets and hiring", "my neighbour's name is Sam")
	Do ..StoreMixed(..#A, "zzmfa", texts)
	Set expected = $ListBuild("who is the Results partner's contact?|zzmfa1,zzmfa3,zzmfa5,zzmfa2,zzmfa4", "when does the warehouse close?|zzmfa2,zzmfa1,zzmfa4,zzmfa3,zzmfa5")
	Set position = 0
	While $ListNext(expected, position, pair) {
		Set query = $Piece(pair, "|", 1)
		Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, query, 5, .rows), "'"_query_"' is searched")
		Do $$$AssertEquals(..Refs(rows), $Piece(pair, "|", 2), "'"_query_"' gives the hard-coded refs in the hard-coded order, not "_..Refs(rows))
		Do ..Reference(..#A, query, .reference)
		Do $$$AssertEquals(rows.%ToJSON(), reference.%ToJSON(), "and the very rows, texts included, of the fusion with no fadeBefore: "_..Refs(reference))
	}
}

/// Over the memories that the eval's memory cases seed, Search returns the refs, order and texts of the fusion with no fadeBefore.
Method TestEquivalenceEvalFixtures()
{
	If '..OnImage() Quit
	Do ..SetDays(90)
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Do $$$AssertTrue(##class(%File).DirectoryExists(folder), "the repository's eval/ is mounted at "_folder_" (a throwaway or CI stack)")
	If '##class(%File).DirectoryExists(folder) Quit
	Set names = ##class(OcuTalon.Eval.In).CaseNames(folder, "")
	Set texts = ""
	Set queries = ""
	Set position = 0
	While $ListNext(names, position, name) {
		Set file = ##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name))
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
		If '$IsObject(case) || ('$IsObject(case.session) && ($Extract(name, 1, 7) '= "memory-")) Continue
		If $IsObject(case.session) && $IsObject(case.session.forgotten) {
			Set iterator = case.session.forgotten.%GetIterator()
			While iterator.%GetNext(, .fact) {
				Set texts = texts _ $ListBuild(fact)
			}
		}
		If $IsObject(case.turn) && (case.turn.text '= "") {
			Set texts = texts _ $ListBuild(case.turn.text)
			Set queries = queries _ $ListBuild(case.turn.text)
		}
	}
	Do $$$AssertTrue($ListLength(texts) '< 3, "the memory cases of eval/ hold at least three memory texts: "_$ListLength(texts))
	Do $$$AssertTrue($ListLength(queries) '< 2, "and at least two questions: "_$ListLength(queries))
	Set stored = ..StoreMixed(..#A, "zzmfe", texts)
	Do $$$AssertEquals(stored, $ListLength(texts), "every text is stored as a memory of the owner")
	Set queries = queries _ $ListBuild("Lee", "who is the contact?", "what is the on-call contact of the Orders partner")
	Set position = 0
	While $ListNext(queries, position, query) {
		Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(..#A, query, 5, .rows), "'"_query_"' is searched")
		Do ..Reference(..#A, query, .reference)
		Do $$$AssertTrue(rows.%Size() > 0, "it finds memories")
		Do $$$AssertEquals(..Refs(rows), ..Refs(reference), "'"_query_"' returns the refs of the fusion with no fadeBefore, in its order: "_..Refs(rows)_" and "_..Refs(reference))
		Do $$$AssertEquals(rows.%ToJSON(), reference.%ToJSON(), "and the same texts")
	}
}

}
