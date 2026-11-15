/// Tests of MemoryOps, OcuTalon.Memory.Ops (Story 19.3; AD-1, AD-4, AD-21, AD-33; DW-731, DW-740). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they send
/// the commands to the item MemoryOps of the running production (RunnerFixture.Send) and through Commands.Submit (origin tool, no bridge context), and they embed
/// through the product's endpoint, so they run on OcuTalon's Docker image and record one named skip elsewhere. The fixture sessions are made by the base class
/// (zz-mem-ops<n><name>) and the rows of the run are deleted after every test.
///   - TestSave (matrix "Save from a user's turn"): one row with the session, the text, SavedAt (UTC to the second, between the times before and after), ItemId (the
///     part of the key before its last colon), Origin tool and a 384-value embedding; the answer is Ok, saved, with the row's Ref; the keyword index finds it and
///     it is the nearest to its own text; and the same through Commands.Submit as origin tool;
///   - TestRepeat ("Repeat save"): the same session, ItemId and text again, also under another position of the key, adds no row and answers saved with the first
///     Ref; another ItemId or another text is a new memory; the same text of another session is its own;
///   - TestEmptyText ("Bad save"): a text of blanks and line breaks answers empty_text, Ok 0, and no row; a text over 2,000 characters, handed to the handler, answers
///     failed with no row;
///   - TestNoSession: a session with no row answers no_session for a save and for a forget, with no row;
///   - TestForget ("Forget"): the owner's forget answers forgotten, Ok 1, deletes the row, and the memory is missing from the next search; a second forget answers
///     not_found;
///   - TestForgetOther (DW-740): another session's forget of the Ref answers not_found, Ok 0, with the same outcome and message as for an unknown Ref, and the
///     memory stays and is found;
///   - TestIndexesFollowTheTable: after a save the keyword index and the nearest search return the memory at once, and after a forget neither does;
///   - TestForgetPinned (Story 41.14; FR-41, FR-74): two pinned memories (a PinMemory of origin web_user through the item), then one forgotten through the item: its row is gone, the vector index (the layer-0 node of the HNSW
///     index global for its id, because a nearest query joins the row and hides a stale entry; and a %ID-only nearest query by its own vector) and the keyword index (the generated TextIdxFind, which reads the index alone) no longer list its id, a search by its text returns no row with
///     its Ref, the core-memory block holds only the other pin, and the input of a user item of the session at its start (Agent.Input.Render with sessionStart) holds the other pin and not the forgotten one;
///   - TestAnswerTime (DW-731, "Enabled owner"): a save through Commands.Submit is answered within 10 seconds, saved, not failed and not not_built;
///   - TestEmbedFailure: a save whose text cannot be embedded (the model folder of the process names a folder that holds no model) answers failed, Ok 0, with no
///     row, and the memory is saved again once the embedder works;
///   - TestSource (Story 41.8; AD-21): a shadow instance (Test.Memory.OpsProbe) saves with the ItemId of a Data.Turn of the session: a turn whose text holds one of
///     the fixed phrases (also in capitals and with U+2019 as the apostrophe) gives the row Source told, one that holds none (also "remembered") gives learned, and an
///     ItemId with no turn of the session, or only a turn of another session, gives learned; the RetryItemId of a running turn that asks gives told, and of another
///     session's turn learned (code review); every new row has Pinned 0 and PinnedAt empty; a repeat keeps the first
///     row's Source and does not read the turn;
///   - TestPhotoSourceLearned (Story 26.3): a save of origin photo is learned whatever the turn's text says, and without reading the turn; origin tool on the same turn is told;
///   - TestSourceReadFails: while the turn cannot be read (the probe fails TurnOf, so MemoryOps' own Source handles the error), the answer is failed, Ok 0,
///     and no row is stored;
///   - TestSourceIgnoresSavedText (QA): the Source follows the turn's text, never the text that is saved (a saved text with phrases under a plain turn is learned,
///     a plain saved text under a turn that asks is told);
///   - TestSourceReadFailsLogged (QA): the failed answer of an unreadable turn is one warning of type 3 whose key-shaped value is redacted, and no text of the memory or the
///     turn is logged;
///   - TestTunedOnSave: a shadow instance (Test.Memory.OpsProbe) calls Tuned with the id of each new row, and with none for a repeat, an empty text or a text that is
///     too long;
///   - TestTuned: the real Tuned of MemoryOps (not the probe's) gathers the table's statistics at an id that is a multiple of STATSEVERY and answers 1, and
///     answers 0 at any other id, so the step that the probe stands in for is the one the item runs.
Class OcuTalon.Test.Memory.Ops Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-mem-ops";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter ITEM = "MemoryOps";

/// The probe whose statistics step is recorded.
Parameter PROBE = "OcuTalon.Test.Memory.OpsProbe";

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state))
		Merge ^||OcuTalonTestMemoryOps = state
		Do ##class(OcuTalon.Memory.Embedding).Embed("warm the embedder", .vector)
	}
	Quit sc
}

/// The Refs of the Data.Turn fixture rows of the running test, comma-separated.
Property TurnRefs As %String(MAXLEN = "") [ Transient ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DropRows()
	If ..TurnRefs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..TurnRefs)
	Set ..TurnRefs = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..DropRows()
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Merge state = ^||OcuTalonTestMemoryOps
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestMemoryOps
	Quit ##super()
}

/// 1 when the test may run (the production runs with every item, RunnerFixture.ReadyReason, and this is OcuTalon's image). Otherwise it fails with the reason or
/// records the skip, and the test quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit 0
	}
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Quit 1
}

/// Deletes the memories of the run's fixture sessions, with their index entries.
Method DropRows() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Memory.Fixture).Purge($Piece(..Sessions, ",", i))
	}
}

/// A SaveMemory of the session with the idempotency key and the text, origin tool.
ClassMethod Save(session As %String, key As %String, text As %String) As OcuTalon.Msg.Command.SaveMemory [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveMemory).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = key
	Set command.Text = text
	Set command.Origin = "tool"
	Quit command
}

/// A ForgetMemory of the session for the memory, origin tool.
ClassMethod Forget(session As %String, ref As %String) As OcuTalon.Msg.Command.ForgetMemory [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ForgetMemory).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = "zzmemitem00000000009:1"
	Set command.MemoryRef = ref
	Set command.Origin = "tool"
	Quit command
}

/// The answer of the item MemoryOps to the command, as a CommandResult, with the assertion that it answered.
Method Ask(command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sc = $ClassMethod(..#FIXTURE, "Send", ..#ITEM, command, .response)
	Do $$$AssertStatusOK(sc, "MemoryOps answers the "_$Piece($ClassName(command), ".", *))
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Msg.CommandResult") {
		Do $$$AssertTrue(0, "with a CommandResult")
		Quit ##class(OcuTalon.Msg.CommandResult).%New()
	}
	Quit response
}

/// A PinMemory of the session for the memory, origin web_user, as the web layer sends it.
ClassMethod Pin(session As %String, ref As %String) As OcuTalon.Msg.Command.PinMemory [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.PinMemory).%New()
	Set command.SessionRef = session
	Set command.MemoryRef = ref
	Set command.Origin = "web_user"
	Quit command
}

/// A ForgetMemory of the session for the memory, origin web_user, as the web layer sends it.
ClassMethod ForgetFromUser(session As %String, ref As %String) As OcuTalon.Msg.Command.ForgetMemory [ Private ]
{
	Set command = ..Forget(session, ref)
	Set command.Origin = "web_user"
	Quit command
}

/// 1 when the vector index (the HNSW index EmbeddingIdx) itself holds the id: its layer-0 node ("G", 0, id) under the index's own subscript of the table's index global. The nearest query cannot show this, because
/// it joins each id it finds to the row and drops an id whose row is gone, so a stale entry is invisible to it.
ClassMethod VectorIndexHas(id As %Integer) As %Boolean [ Private ]
{
	Quit ''$Data(^OcuTalonP.MemoryI("EmbeddingIdx", "G", 0, id))
}

/// 1 when a %ID-only nearest query by the vector, with no filter on the session, lists the id (the query joins to the row, so it shows what a recall by the vector would return).
ClassMethod VectorQueryHas(id As %Integer, vector As %Vector) As %Boolean [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 5 %ID AS RowId FROM OcuTalon_Data.Memory ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC", ##class(OcuTalon.Test.Memory.Fixture).ToString(vector))
	Set found = 0
	While rs.%Next() {
		If rs.%Get("RowId") = id Set found = 1
	}
	Quit found
}

/// 1 when the keyword index lists the id for the word: the generated TextIdxFind returns the index's own search, and ContainsItem reads the index alone.
ClassMethod KeywordIndexHas(id As %Integer, word As %String) As %Boolean [ Private ]
{
	Set find = ##class(OcuTalon.Data.Memory).TextIdxFind(""""_word_"""")
	Quit ''find.ContainsItem(id)
}

/// The number of memories of the session.
ClassMethod Count(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Memory WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The refs of the memories that the keyword index finds for the word in the session, comma-separated.
ClassMethod KeywordHits(session As %String, word As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ? AND %ID %FIND search_index(TextIdx, ?, 0)", session, """"_word_"""")
	Set refs = ""
	While rs.%Next() {
		Set refs = refs _ $Select(refs '= "": ",", 1: "") _ rs.%Get("Ref")
	}
	Quit refs
}

/// The refs of the nearest memories of the session to the text by the vector index, comma-separated.
ClassMethod NearestTo(session As %String, text As %String) As %String [ Private ]
{
	Do ##class(OcuTalon.Memory.Embedding).Embed(text, .vector)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 5 Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ? ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC", session, ##class(OcuTalon.Test.Memory.Fixture).ToString(vector))
	Set refs = ""
	While rs.%Next() {
		Set refs = refs _ $Select(refs '= "": ",", 1: "") _ rs.%Get("Ref")
	}
	Quit refs
}

/// One memory of a session, saved through the item.
Method TestSave()
{
	If '..Ready() Quit
	Set session = ..Session("save")
	Set text = "the Results partner's contact is Lee"
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set response = ..Ask(..Save(session, "zzmemitem00000000001:1", text))
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|saved", "the answer is Ok, saved: "_response.Message)
	Do $$$AssertEquals($Length(response.Ref), 22, "with a Ref of 22 characters")
	Do $$$AssertEquals(..Count(session), 1, "there is one memory")
	Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(response.Ref)
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the answer's Ref is a row")
		Quit
	}
	Do $$$AssertEquals(row.SessionRef_"|"_row.Text_"|"_row.ItemId_"|"_row.Origin, session_"|"_text_"|zzmemitem00000000001|tool", "the row has the session, the text, the ItemId (the key before its last colon) and the origin")
	Do $$$AssertTrue('(before ] row.SavedAt) && '(row.SavedAt ] after) && (row.SavedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z"), "SavedAt is the time of the save, UTC to the second: "_row.SavedAt)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Embedding FROM OcuTalon_Data.Memory WHERE Ref = ?", response.Ref)
	Do rs.%Next()
	Do $$$AssertEquals($VOP("length", ##class(OcuTalon.Test.Memory.Fixture).ToVector(rs.%GetData(1))), 384, "the embedding has 384 values")
	Do $$$AssertEquals(..KeywordHits(session, "Lee"), response.Ref, "the keyword index finds it")
	Do $$$AssertEquals(..NearestTo(session, text), response.Ref, "and the vector index has it as the nearest to its own text")
	Set row = ""
	Set command = ..Save(session, "zzmemitem00000000002:1", "invoices are paid within thirty days")
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .result)
	Do $$$AssertStatusOK(sc, "Commands.Submit takes the SaveMemory as origin tool")
	Do $$$AssertEquals($Select($IsObject(result): result.Ok_"|"_result.Outcome, 1: "none"), "1|saved", "and CommandsIn routes it to MemoryOps, which saves it")
	Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen($Select($IsObject(result): result.Ref, 1: ""))
	Do $$$AssertEquals($Select($IsObject(row): row.Origin_"|"_row.ItemId, 1: "none"), "tool|zzmemitem00000000002", "its row has the origin tool")
}

/// A repeat adds nothing.
Method TestRepeat()
{
	If '..Ready() Quit
	Set a = ..Session("repeatA")
	Set b = ..Session("repeatB")
	Set text = "the warehouse closes at six on Fridays"
	Set first = ..Ask(..Save(a, "zzmemitem00000000001:1", text))
	Do $$$AssertEquals(first.Ok_"|"_first.Outcome, "1|saved", "the first save: "_first.Message)
	Set again = ..Ask(..Save(a, "zzmemitem00000000001:1", text))
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Ref, "1|saved|"_first.Ref, "the same command again answers saved with the first Ref")
	Set position = ..Ask(..Save(a, "zzmemitem00000000001:2", text))
	Do $$$AssertEquals(position.Ref, first.Ref, "the same ItemId and text at another position of the key is the same memory")
	Do $$$AssertEquals(..Count(a), 1, "and there is still one row")
	Set other = ..Ask(..Save(a, "zzmemitem00000000002:1", text))
	Do $$$AssertTrue(other.Ok && (other.Ref '= first.Ref), "another ItemId is a new memory")
	Set changed = ..Ask(..Save(a, "zzmemitem00000000001:3", text_" and on Saturdays at noon"))
	Do $$$AssertTrue(changed.Ok && (changed.Ref '= first.Ref), "and so is another text of the first ItemId")
	Do $$$AssertEquals(..Count(a), 3, "three rows in all")
	Set upper = ..Ask(..Save(a, "zzmemitem00000000001:4", $ZConvert(text, "U")))
	Do $$$AssertTrue(upper.Ok && (upper.Ref '= first.Ref), "the text is compared exactly: the same words in capitals are a new memory")
	Set mine = ..Ask(..Save(b, "zzmemitem00000000001:1", text))
	Do $$$AssertTrue(mine.Ok && (mine.Ref '= first.Ref), "the same text and ItemId of another session is that session's own")
	Do $$$AssertEquals(..Count(b), 1, "with one row")
}

/// An empty text and a text that is too long save nothing.
Method TestEmptyText()
{
	If '..Ready() Quit
	Set session = ..Session("empty")
	For text = "", "   ", $Char(9, 10, 13, 32) {
		Set response = ..Ask(..Save(session, "zzmemitem00000000001:1", text))
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "0|empty_text|", "a text of "_$Length(text)_" blank characters answers empty_text: "_response.Message)
	}
	Do $$$AssertEquals(..Count(session), 0, "and no row is saved")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set sc = host.OnSave(..Save(session, "zzmemitem00000000001:1", $Translate($Justify("", 2001), " ", "x")), .response)
	Do $$$AssertStatusOK(sc, "the handler answers a text of 2,001 characters")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "with failed")
	Do $$$AssertEquals(..Count(session), 0, "and saves nothing")
}

/// A session with no row.
Method TestNoSession()
{
	If '..Ready() Quit
	Set ghost = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set response = ..Ask(..Save(ghost, "zzmemitem00000000001:1", "the warehouse closes at six on Fridays"))
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "a save answers no_session")
	Do $$$AssertEquals(..Count(ghost), 0, "and writes no row")
	Set response = ..Ask(..Forget(ghost, "zzMemoryForget00000001"))
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "and so does a forget")
}

/// The owner forgets its own memory.
Method TestForget()
{
	If '..Ready() Quit
	Set session = ..Session("forget")
	Set saved = ..Ask(..Save(session, "zzmemitem00000000001:1", "the Results partner's contact is Lee"))
	Do $$$AssertEquals(saved.Outcome, "saved", "a memory is saved")
	Set response = ..Ask(..Forget(session, saved.Ref))
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|forgotten", "the forget answers forgotten, Ok: "_response.Message)
	Do $$$AssertEquals(..Count(session), 0, "the row is gone")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(session, "Lee", 5, .rows), "a search at once")
	Do $$$AssertEquals(rows.%Size(), 0, "does not return it")
	Set response = ..Ask(..Forget(session, saved.Ref))
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_found", "a second forget answers not_found")
}

/// Another session's forget changes nothing and answers as for an unknown Ref (DW-740).
Method TestForgetOther()
{
	If '..Ready() Quit
	Set a = ..Session("ownerA")
	Set b = ..Session("ownerB")
	Set saved = ..Ask(..Save(a, "zzmemitem00000000001:1", "the Results partner's contact is Lee"))
	Do $$$AssertEquals(saved.Outcome, "saved", "A saves a memory")
	Set other = ..Ask(..Forget(b, saved.Ref))
	Set unknown = ..Ask(..Forget(b, "zzMemoryForget00000001"))
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome, "0|not_found", "B's forget of A's Ref answers not_found, Ok 0")
	Do $$$AssertEquals(other.Message_"|"_other.Ref_"|"_other.Data, unknown.Message_"|"_unknown.Ref_"|"_unknown.Data, "exactly as for a Ref that no memory has")
	Do $$$AssertEquals(..Count(a), 1, "A's memory is still there")
	Do $$$AssertEquals(..KeywordHits(a, "Lee"), saved.Ref, "and found by the keyword index")
	Do $$$AssertEquals(..NearestTo(a, "the Results partner's contact is Lee"), saved.Ref, "and by the vector index")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(a, "Lee", 5, .rows), "A searches")
	Do $$$AssertEquals(rows.%Size(), 1, "and finds it")
}

/// The keyword and vector indexes follow the table.
Method TestIndexesFollowTheTable()
{
	If '..Ready() Quit
	Set session = ..Session("indexes")
	Set saved = ..Ask(..Save(session, "zzmemitem00000000001:1", "the Results partner's contact is Lee"))
	Do $$$AssertEquals(..KeywordHits(session, "Lee"), saved.Ref, "after a save the keyword index returns the memory")
	Do $$$AssertEquals(..NearestTo(session, "who is the contact at the Results partner?"), saved.Ref, "and the vector index too")
	Set response = ..Ask(..Forget(session, saved.Ref))
	Do $$$AssertEquals(response.Outcome, "forgotten", "the memory is forgotten")
	Do $$$AssertEquals(..KeywordHits(session, "Lee"), "", "and the keyword index no longer returns it")
	Do $$$AssertEquals(..NearestTo(session, "who is the contact at the Results partner?"), "", "nor does the vector index")
}

/// A pinned memory that is forgotten leaves nothing behind (Story 41.14; FR-41, FR-74): the index entries are read from the indexes themselves, not from the row, which the filter on SessionRef of
/// KeywordHits and NearestTo would hide. The two pins are made through the item as the web layer makes them; the forget is the web layer's too (origin web_user).
Method TestForgetPinned()
{
	If '..Ready() Quit
	Set session = ..Session("forgetpinned")
	Set textA = "The Orders partner escalation phone is 5550111 and it rings in Berlin"
	Set textB = "The Claims desk closes at noon on Fridays in Boston"
	Set a = ..Ask(..Save(session, "zzmemitem00000000001:1", textA))
	Set b = ..Ask(..Save(session, "zzmemitem00000000002:1", textB))
	Do $$$AssertEquals(a.Outcome_"|"_b.Outcome, "saved|saved", "two memories are saved: "_a.Message_" "_b.Message)
	Set idA = ##class(OcuTalon.Data.Memory).RefIndexOpen(a.Ref).%Id()
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Embedding FROM OcuTalon_Data.Memory WHERE Ref = ?", a.Ref)
	Do rs.%Next()
	Set vectorA = ##class(OcuTalon.Test.Memory.Fixture).ToVector(rs.%GetData(1))
	Do $$$AssertEquals($VOP("length", vectorA), 384, "A's stored vector has 384 values")
	Do $$$AssertEquals(..Ask(..Pin(session, a.Ref)).Outcome_"|"_..Ask(..Pin(session, b.Ref)).Outcome, "pinned|pinned", "both are pinned")
	Do $$$AssertEquals(..VectorIndexHas(idA)_..VectorQueryHas(idA, vectorA), "11", "control: before the forget the vector index holds A's id and the nearest query by A's vector finds it")
	Do $$$AssertEquals(..KeywordIndexHas(idA, "escalation"), 1, "and the keyword index lists it for escalation")
	Do $$$AssertEquals(..KeywordIndexHas(idA, "Boston"), 0, "but not for a word of B's text")
	Set response = ..Ask(..ForgetFromUser(session, a.Ref))
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|forgotten", "A is forgotten: "_response.Message)
	Do $$$AssertEquals(##class(OcuTalon.Data.Memory).RefIndexExists(a.Ref)_"|"_..Count(session), "0|1", "A's row is gone and B's stays")
	Do $$$AssertEquals(..VectorIndexHas(idA), 0, "the vector index itself no longer holds A's id (its layer-0 node is read, not a query that joins the row)")
	Do $$$AssertEquals(..VectorQueryHas(idA, vectorA), 0, "and the nearest query by A's own vector, with no filter on the session, no longer finds it")
	Do $$$AssertEquals(..KeywordIndexHas(idA, "escalation"), 0, "and the keyword index no longer lists it, read from the index alone")
	Do $$$AssertEquals(..KeywordIndexHas(idA, "Berlin"), 0, "for any word of its text")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Search(session, textA, 5, .rows), "a search by A's text")
	Set refs = ""
	For i = 0:1:rows.%Size() - 1 {
		Set refs = refs_$Select(refs = "": "", 1: ",")_rows.%Get(i).memoryRef
	}
	Do $$$AssertEquals(refs, b.Ref, "returns no row with A's Ref, only B")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, "", .block), "the core-memory block")
	Do $$$AssertTrue((block [ textB) && (block '[ textA), "holds B's text and not A's")
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef(), item.SessionRef = session, item.Channel = "web", item.Provenance = "user", item.Text = "Hello there"
	Set input = ##class(OcuTalon.Agent.Input).Render(item, , {"sessionStart": 1})
	Do $$$AssertTrue((input [ textB) && (input '[ textA), "the input of a user item at the session's start holds B's text and not A's")
	Do $$$AssertEquals(..Ask(..Forget(session, a.Ref)).Outcome, "not_found", "a second forget of A answers not_found")
}

/// A save is answered in seconds, not after the owner's 120-second wait (DW-731).
Method TestAnswerTime()
{
	If '..Ready() Quit
	Set session = ..Session("time")
	Set command = ..Save(session, "zzmemitem00000000001:1", "the warehouse closes at six on Fridays")
	Set start = $ZHorolog
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .result)
	Set seconds = $ZHorolog - start
	Do $$$AssertStatusOK(sc, "the command is answered")
	Do $$$AssertTrue(seconds < 10, "within 10 seconds: "_seconds)
	Do $$$AssertTrue($IsObject(result) && (result.Outcome '= "failed") && (result.Outcome '= "not_built"), "and the outcome is neither failed nor not_built: "_$Select($IsObject(result): result.Outcome_" "_result.Message, 1: "no result"))
	Do $$$AssertEquals($Select($IsObject(result): result.Ok_"|"_result.Outcome, 1: "none"), "1|saved", "it is saved")
}

/// A text that cannot be embedded is not stored.
Method TestEmbedFailure()
{
	If '..Ready() Quit
	Set session = ..Session("embedfail")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set variable = ##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE
	Set previous = $SYSTEM.Util.GetEnviron(variable)
	Set environ = ##class(%SYS.Python).Import("os").environ
	Do environ."__setitem__"(variable, "/dev/null/zz-memory-no-model/")
	Set sc = host.OnSave(..Save(session, "zzmemitem00000000003:1", "the dock opens at seven"), .failed)
	Do ##class(OcuTalon.Test.Memory.Fixture).PutVariable(environ, previous)
	Do $$$AssertStatusOK(sc, "the handler answers although the text cannot be embedded")
	Do $$$AssertEquals(failed.Ok_"|"_failed.Outcome_"|"_failed.Ref, "0|failed|", "failed, Ok 0, with no Ref")
	Do $$$AssertEquals(..Count(session), 0, "and no row is stored")
	Do $$$AssertEquals(host.Tunes, "", "and Tuned is not called")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000003:1", "the dock opens at seven"), .saved), "the same save with a working embedder")
	Do $$$AssertEquals(saved.Ok_"|"_saved.Outcome, "1|saved", "is saved")
	Do $$$AssertEquals(..Count(session), 1, "as one row")
}

/// A turn of the session with the text, as the person's chat turn is stored; its ItemId, which a save of that turn names.
Method TurnItem(session As %String, text As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Turn(session, , "running", text)
	Set ..TurnRefs = ..TurnRefs _ $Select(..TurnRefs '= "": ",", 1: "") _ ref
	Quit ##class(OcuTalon.Data.Turn).RefIndexOpen(ref).ItemId
}

/// The Source, Pinned and PinnedAt of the row with the Ref, as Source|Pinned|PinnedAt, or "none".
ClassMethod SourceOf(ref As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.Source_"|"_row.Pinned_"|"_row.PinnedAt, 1: "none")
}

/// A new memory takes its Source from the person's own text of the saving turn.
Method TestSource()
{
	If '..Ready() Quit
	Set session = ..Session("source")
	Set other = ..Session("sourceOther")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set told = ..TurnItem(session, "Remember that the VPN host is vpn.example")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, told_":1", "the VPN host is vpn.example"), .first), "a save of a turn that asks for it")
	Do $$$AssertEquals(..SourceOf(first.Ref), "told|0|", "is told, with Pinned 0 and PinnedAt empty")
	Set texts(1) = "keep in mind the VPN host", texts(2) = "Note that the VPN host is vpn.example", texts(3) = "DON'T FORGET the VPN host", texts(4) = "don"_$Char(8217)_"t forget the VPN host"
	Set texts(5) = "the VPN host is vpn.example, remember it", texts(6) = "REMEMBER"
	For i = 1:1:6 {
		Set item = ..TurnItem(session, texts(i))
		Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the VPN host is vpn.example"), .response), "a save of the turn "_i)
		Do $$$AssertEquals(..SourceOf(response.Ref), "told|0|", "is told: "_$Translate(texts(i), $Char(8217), "`"))
	}
	Set texts(1) = "Our VPN host is vpn.example.", texts(2) = "I remembered the host", texts(3) = "Remembering the VPN host", texts(4) = "dont forget the host", texts(5) = ""
	For i = 1:1:5 {
		Set item = ..TurnItem(session, texts(i))
		Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the VPN host is vpn.example"), .response), "a save of the turn "_i_" that does not ask")
		Do $$$AssertEquals(..SourceOf(response.Ref), "learned|0|", "is learned: "_$Translate(texts(i), $Char(8217), "`"))
	}
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000077:1", "the VPN host is vpn.example"), .noTurn), "a save whose ItemId has no turn")
	Do $$$AssertEquals(..SourceOf(noTurn.Ref), "learned|0|", "is learned")
	Set foreign = ..TurnItem(other, "Remember that the VPN host is vpn.example")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, foreign_":1", "the VPN host is vpn.example"), .elsewhere), "a save whose ItemId is only another session's turn")
	Do $$$AssertEquals(..SourceOf(elsewhere.Ref), "learned|0|", "is learned: the other session's text is not read")
	Set retried = ..TurnItem(session, "Remember that the dock opens at seven")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, ##class(OcuTalon.Core.Conversation).RetryItemId(retried)_":1", "the dock opens at seven"), .retry), "a save of the retry of a running turn that asks for it")
	Do $$$AssertEquals(..SourceOf(retry.Ref), "told|0|", "is told: the retry's turn is read")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, ##class(OcuTalon.Core.Conversation).RetryItemId(foreign)_":1", "the dock opens at seven"), .retryElsewhere), "a save of the retry of another session's turn")
	Do $$$AssertEquals(..SourceOf(retryElsewhere.Ref), "learned|0|", "is learned: the other session's turn is not read")
	Set host.SourceFails = 1
	Do $$$AssertStatusOK(host.OnSave(..Save(session, told_":2", "the VPN host is vpn.example"), .again), "a repeat of the first save, while the turn cannot be read")
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Ref, "1|saved|"_first.Ref, "answers saved with the first Ref, without reading the turn")
	Set host.SourceFails = 0
	Do $$$AssertEquals(..SourceOf(first.Ref), "told|0|", "and the first row keeps its Source")
	Do $$$AssertEquals(..Count(session), 16, "and there are 16 rows")
}

/// The caption of a photo is learned whatever the turn's text says (Story 26.3; AD-21): a save of origin photo whose ItemId is the turn of a person who wrote "Remember that" is
/// learned, with the origin photo, Pinned 0 and PinnedAt empty, and the turn is not read; the same save from origin tool is told, so that it is the origin that decides.
Method TestPhotoSourceLearned()
{
	If '..Ready() Quit
	Set session = ..Session("photo")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set item = ..TurnItem(session, "Remember that the dock opens at seven")
	Set command = ..Save(session, item_":caption", "A small red square on a white background.")
	Set command.Origin = "photo"
	Set host.SourceFails = 1
	Do $$$AssertStatusOK(host.OnSave(command, .photo), "a save of origin photo, while the turn cannot be read")
	Set host.SourceFails = 0
	Do $$$AssertEquals(photo.Ok_"|"_photo.Outcome, "1|saved", "is saved: the turn is never read for a caption")
	Do $$$AssertEquals(..SourceOf(photo.Ref), "learned|0|", "and is learned, with Pinned 0 and PinnedAt empty, though the turn's text holds a told phrase")
	Do $$$AssertEquals(##class(OcuTalon.Data.Memory).RefIndexOpen(photo.Ref).Origin, "photo", "with the origin photo")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the dock opens at seven"), .tool), "a save of origin tool on the same turn")
	Do $$$AssertEquals(..SourceOf(tool.Ref), "told|0|", "is told, so that the origin decides")
}

/// The source comes from the turn, never from the text that the model saves (QA; AD-21: code decides, the model's arguments never carry it).
Method TestSourceIgnoresSavedText()
{
	If '..Ready() Quit
	Set session = ..Session("sourcetext")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set item = ..TurnItem(session, "Our VPN host is vpn.example.")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "Remember that the VPN host is vpn.example, and don't forget it. Note that it is told."), .learned), "a turn that asks for nothing, saved with a text that holds three phrases")
	Do $$$AssertEquals(..SourceOf(learned.Ref), "learned|0|", "is learned: the saved text is not read")
	Set item = ..TurnItem(session, "Remember that the dock opens at seven")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the dock opens at seven"), .told), "a turn that asks, saved with a text that holds no phrase")
	Do $$$AssertEquals(..SourceOf(told.Ref), "told|0|", "is told: the turn's text is read")
}

/// A turn that cannot be read fails the save.
Method TestSourceReadFails()
{
	If '..Ready() Quit
	Set session = ..Session("sourcefails")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set item = ..TurnItem(session, "Remember that the VPN host is vpn.example")
	Set host.SourceFails = 1
	Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the VPN host is vpn.example"), .response), "the handler answers although the turn cannot be read")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "0|failed|", "failed, Ok 0, with no Ref")
	Do $$$AssertEquals(..Count(session), 0, "and no row is stored")
	Do $$$AssertEquals(host.Tunes, "", "and Tuned is not called")
	Set host.SourceFails = 0
	Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the VPN host is vpn.example"), .saved), "the same save once the turn can be read")
	Do $$$AssertEquals(saved.Ok_"|"_saved.Outcome, "1|saved", "is saved")
	Do $$$AssertEquals(..SourceOf(saved.Ref), "told|0|", "as told")
}

/// The failed answer of an unreadable turn is logged once, redacted (QA; matrix "Turn read fails": one Type 3 warning, redacted).
Method TestSourceReadFailsLogged()
{
	If '..Ready() Quit
	Set session = ..Session("sourcelog")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set item = ..TurnItem(session, "Remember that the VPN host is vpn.example")
	Set secret = "sk-ant-"_$Translate($Justify("", 30), " ", "x")
	Set host.SourceFails = 1
	Set host.SourceFailText = "refused "_secret
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Do $$$AssertStatusOK(host.OnSave(..Save(session, item_":1", "the VPN host is vpn.example"), .response), "the handler answers although the turn cannot be read")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "failed, Ok 0")
	Set class = ..#PROBE
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, class, "Failed"), 1, "one warning (type 3) is logged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, class, "Failed", $ListBuild($Parameter("OcuTalon.Memory.Ops", "LOGFAILED"), "could not be read", "refused [redacted]")), 1, "which holds the sentence of the turn and the status text with the key redacted")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, "sk-ant"), 0, "and no part of the key shows anywhere in the event log")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, "vpn.example"), 0, "nor the text of the memory or of the turn")
	Do $$$AssertEquals(..Count(session), 0, "and no row is stored")
}

/// Tuned is called with the id of each new row only.
Method TestTunedOnSave()
{
	If '..Ready() Quit
	Set session = ..Session("tuned")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000001:1", "the warehouse closes at six on Fridays"), .first), "the handler answers a save")
	Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(first.Ref)
	Do $$$AssertEquals(host.Tunes, $Select($IsObject(row): row.%Id(), 1: "none"), "Tuned was called with the id of the new row")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000001:1", "the warehouse closes at six on Fridays"), .again), "a repeat")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000001:2", "   "), .empty), "an empty text")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000001:3", $Translate($Justify("", 2001), " ", "x")), .long), "a text that is too long")
	Do $$$AssertEquals(host.Tunes, $Select($IsObject(row): row.%Id(), 1: "none"), "calls Tuned no more")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000002:1", "invoices are paid within thirty days"), .second), "a second memory")
	Set row2 = ##class(OcuTalon.Data.Memory).RefIndexOpen(second.Ref)
	Do $$$AssertEquals(host.Tunes, $Select($IsObject(row): row.%Id(), 1: "none")_","_$Select($IsObject(row2): row2.%Id(), 1: "none"), "and with the second row's id")
}

/// The real Tuned of MemoryOps gathers at a multiple of STATSEVERY only.
Method TestTuned()
{
	If '..Ready() Quit
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Memory.Ops", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of MemoryOps is made")
	If '$IsObject(host) Quit
	Set every = ##class(OcuTalon.Memory).#STATSEVERY
	Do $$$AssertEquals(host.Tuned(every), 1, "Tuned gathers the table's statistics at id "_every)
	Do $$$AssertEquals(host.Tuned(every * 2), 1, "and at id "_(every * 2))
	Do $$$AssertEquals(host.Tuned(every - 1), 0, "and not at id "_(every - 1))
	Do $$$AssertEquals(host.Tuned(every + 1), 0, "nor at id "_(every + 1))
}

}
