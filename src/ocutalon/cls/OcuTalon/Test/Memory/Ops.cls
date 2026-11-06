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
///   - TestAnswerTime (DW-731, "Enabled owner"): a save through Commands.Submit is answered within 10 seconds, saved, not failed and not not_built;
///   - TestEmbedFailure: a save whose text cannot be embedded (the model folder of the process names a folder that holds no model) answers failed, Ok 0, with no
///     row, and the memory is saved again once the embedder works;
///   - TestTunedOnSave: a shadow instance (Test.Memory.OpsProbe) calls Tuned with the id of each new row, and with none for a repeat, an empty text or a text that is
///     too long.
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

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DropRows()
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

/// 1 when the test may run (the production runs and this is OcuTalon's image). Otherwise it fails with the reason or records the skip, and the test quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
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
	Do $$$AssertEquals(host.Tunes, $Select($IsObject(row): row.%Id(), 1: "none"), "calls Tuned no more")
	Do $$$AssertStatusOK(host.OnSave(..Save(session, "zzmemitem00000000002:1", "invoices are paid within thirty days"), .second), "a second memory")
	Set row2 = ##class(OcuTalon.Data.Memory).RefIndexOpen(second.Ref)
	Do $$$AssertEquals(host.Tunes, $Select($IsObject(row): row.%Id(), 1: "none")_","_$Select($IsObject(row2): row2.%Id(), 1: "none"), "and with the second row's id")
}

}
