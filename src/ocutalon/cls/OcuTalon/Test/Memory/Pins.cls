/// Tests of the pin handlers of MemoryOps, OcuTalon.Memory.Ops OnPin and OnUnpin, and of the reads under them, OcuTalon.Memory Pinned and CoreBlock (Story 41.12; AD-1, AD-4, AD-21,
/// AD-33; FR-74, NFR-27; DW-740, DW-1014). Safe on a slot: the handlers run on a shadow instance of MemoryOps in this process, and the fixture sessions hold rows saved directly with
/// a vector that has no meaning, so no embedder and no production are needed. Every test removes its sessions and their memories. The expected lengths are held arithmetic, never
/// read from the code under test: the opening line is 36 characters, each single-line pin adds 3 and its length (a line feed and the quote prefix), and the closing blank line adds 2,
/// so pins of 2,000 and 1,956 characters make exactly 4,000.
///   - TestMessageMap: the message map of MemoryOps sends PinMemory to OnPin and UnpinMemory to OnUnpin (the production dispatches by the map; the tests that call the handlers do not);
///   - TestPin: an own unpinned memory is pinned within the cap: Pinned 1, PinnedAt now (UTC to the second), pinned, Ok 1, the Ref, an empty Message;
///   - TestCap: the pin that would make the rendered block 4,001 characters is over_cap and changes nothing; the one that makes exactly 4,000 is pinned; one more character is over_cap;
///   - TestCapRendered: the cap is measured on the rendered block (line breaks add a quote prefix each), not on the sum of the texts;
///   - TestAlreadyPinned: a pinned memory answers pinned, keeps its PinnedAt and is not checked against the cap again;
///   - TestOldRow (DW-1014): a row whose stored Pinned is empty is not pinned, is not in the block, and can be pinned;
///   - TestUnpin: an own memory, pinned or not, gets Pinned 0 and PinnedAt empty and answers unpinned;
///   - TestOtherSession (DW-740): another session's Ref and an unknown Ref answer the same not_found for a pin and an unpin, and change nothing;
///   - TestNoSession: a command whose session has no row answers no_session;
///   - TestLockBusy: a session whose lock is not free answers failed for a pin and an unpin, and changes nothing;
///   - TestForgetPinned: forgetting a pinned memory deletes it, and it is gone from Pinned and from the block;
///   - TestPinnedOrder: Memory.Pinned answers the session's pinned rows only, newest pin first and then the higher row id first, and an empty session is an error status.
Class OcuTalon.Test.Memory.Pins Extends %UnitTest.TestCase
{

/// The Refs of the fixture sessions of the test, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The count of sessions made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The run's number.
Property Number As %Integer;

/// The shadow instance of MemoryOps that the test calls.
Property Host As OcuTalon.Memory.Ops [ Transient ];

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("MemoryPins", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Memory.Ops", .sc)
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||PinsProbe
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Memory.Fixture).Purge($Piece(..Sessions, ",", i))
	}
	If ..Sessions '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
	Set ..Sessions = ""
	Set ..Host = ""
	Quit $$$OK
}

/// The compiled message map of MemoryOps names OnPin for PinMemory and OnUnpin for UnpinMemory, so that the production delivers the two commands to their handlers.
Method TestMessageMap()
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Memory.Ops||MessageMap")
	Do $$$AssertTrue($IsObject(xdata), "the class has a message map")
	If '$IsObject(xdata) Quit
	Set map = xdata.Data.Read($$$MaxLocalLength)
	Set pairs = $ListBuild($ListBuild("PinMemory", "OnPin"), $ListBuild("UnpinMemory", "OnUnpin"), $ListBuild("SaveMemory", "OnSave"), $ListBuild("ForgetMemory", "OnForget"), $ListBuild("SearchMemory", "OnSearch"))
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Set pattern = "<MapItem\s+MessageType=""OcuTalon\.Msg\.Command\."_$List(pair, 1)_"""\s*>\s*<Method>"_$List(pair, 2)_"</Method>\s*</MapItem>"
		Do $$$AssertTrue($Locate(map, pattern) > 0, $List(pair, 1)_" goes to "_$List(pair, 2))
	}
}

/// An own unpinned memory is pinned: Pinned 1, PinnedAt now, Ok 1, pinned, with the memory's Ref and an empty Message.
Method TestPin()
{
	Set session = ..Session()
	Set ref = ..Memory(session, ..Text(10, "a"))
	Do $$$AssertEquals(..State(ref), "0|", "the memory starts unpinned with no PinnedAt")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, ref), .response), "the handler answers OK")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message_"|"_response.Ref, "1|pinned||"_ref, "Ok 1, pinned, no message, the memory's Ref")
	Do $$$AssertEquals(+$Piece(..State(ref), "|", 1), 1, "Pinned is 1")
	Set at = $Piece(..State(ref), "|", 2)
	Do $$$AssertTrue(at ?4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "PinnedAt is a UTC time to the second: "_at)
	Do $$$AssertTrue((at = before) || (at ] before), "and not before the call began")
	Do $$$AssertTrue('(at ] after), "and not after it ended")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read answers OK")
	Do $$$AssertEquals(rows.%Size()_"|"_rows.%Get(0).memoryRef_"|"_rows.%Get(0).pinned, "1|"_ref_"|1", "and the memory is in it")
}

/// The pin that would make the block 4,001 characters is refused with nothing changed; the one that makes exactly 4,000 is pinned; one more character is refused.
Method TestCap()
{
	Set session = ..Session()
	Set a = ..Memory(session, ..Text(2000, "a"))
	Set b1 = ..Memory(session, ..Text(1957, "b"))
	Set b2 = ..Memory(session, ..Text(1956, "c"))
	Set c = ..Memory(session, "d")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, a), .response), "pin A (2,000 characters)")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|pinned", "A is pinned: the block is 36 + 3 + 2,000 + 2 = 2,041")
	Set atA = $Piece(..State(a), "|", 2)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, ..Text(1957, "b"), .block), "the block with the candidate B1 (one over)")
	Do $$$AssertEquals($Length(block), 4001, "is 4,001 characters: 36 + 3 + 2,000 + 3 + 1,957 + 2")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, b1), .response), "pin B1")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|over_cap|", "B1 is over_cap, Ok 0, with no message (the web layer has the text)")
	Do $$$AssertEquals(..State(a)_"|"_..State(b1), "1|"_atA_"|0|", "and A and B1 are unchanged")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, b2), .response), "pin B2 (1,956 characters)")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|pinned", "B2 is pinned: the block is exactly 4,000")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, "", .block), "the block of the session")
	Do $$$AssertEquals($Length(block), 4000, "is 4,000 characters")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, c), .response), "pin a memory of one character")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|over_cap", "one more character is over_cap")
	Do $$$AssertEquals(..State(c), "0|", "and it stays unpinned")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read")
	Do $$$AssertEquals(rows.%Size(), 2, "and nothing was unpinned to make room")
}

/// The cap is the length of the rendered block: a candidate whose texts sum under 4,000 but whose quoted lines do not fit is refused.
Method TestCapRendered()
{
	Set session = ..Session()
	Set a = ..Memory(session, ..Text(2000, "a"))
	Set lines = ..Text(324, "x")_$Char(10)_..Text(324, "y")_$Char(10)_..Text(324, "z")_$Char(10)_..Text(324, "u")_$Char(10)_..Text(324, "v")_$Char(10)_..Text(325, "w")
	Do $$$AssertEquals($Length(lines), 1950, "the candidate has 1,950 characters, 5 of them line feeds")
	Set b = ..Memory(session, lines)
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, a), .response), "pin A")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|pinned", "A is pinned")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, lines, .block), "the block with the candidate")
	Do $$$AssertEquals($Length(block), 4004, "is 4,004 characters: 36 + 3 + 2,000 + 1 + 1,950 + 6 * 2 + 2, the texts alone sum to 3,950")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, b), .response), "pin the candidate")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|over_cap", "it is over_cap")
	Do $$$AssertEquals(..State(b), "0|", "and unchanged")
}

/// A pinned memory answers pinned and keeps its PinnedAt; no cap check is made, even when the pins are over the cap.
Method TestAlreadyPinned()
{
	Set session = ..Session()
	Set a = ..Memory(session, ..Text(2000, "a"), 1, "2030-01-01T10:00:00Z")
	Set b = ..Memory(session, ..Text(2000, "b"), 1, "2030-01-02T10:00:00Z")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, "", .block), "the block of two pins written directly")
	Do $$$AssertTrue($Length(block) > 4000, "is over the cap ("_$Length(block)_")")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, a), .response), "pin A again")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "1|pinned|"_a, "Ok 1, pinned, with the Ref")
	Do $$$AssertEquals(..State(a)_"|"_..State(b), "1|2030-01-01T10:00:00Z|1|2030-01-02T10:00:00Z", "and the PinnedAt of both is unchanged")
}

/// DW-1014: a row saved before Story 41.8 (stored Pinned empty) is not pinned, is not in the block, and can be pinned under the cap rule.
Method TestOldRow()
{
	Set session = ..Session()
	Set a = ..Memory(session, ..Text(2000, "a"), 1, "2020-01-01T10:00:00Z")
	Set old = ..Memory(session, ..Text(1956, "o"))
	Do ..Blank(old)
	Do $$$AssertEquals(..Stored(old), "", "the row's stored Pinned is empty")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read")
	Do $$$AssertEquals(rows.%Size()_"|"_rows.%Get(0).memoryRef, "1|"_a, "only A is pinned: the old row is not")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, "", .block), "the block")
	Do $$$AssertEquals($Length(block), 2041, "and it does not hold the old row (36 + 3 + 2,000 + 2)")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, old), .response), "pin the old row")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|pinned", "it is pinned: the block is exactly 4,000")
	Do $$$AssertEquals(+$Piece(..State(old), "|", 1), 1, "its Pinned is 1")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read")
	Do $$$AssertEquals(rows.%Size()_"|"_rows.%Get(0).memoryRef, "2|"_old, "and it is now the newest pin")
}

/// An own memory, pinned or not, is unpinned: Pinned 0, PinnedAt empty, unpinned, Ok 1.
Method TestUnpin()
{
	Set session = ..Session()
	Set pinned = ..Memory(session, ..Text(10, "a"), 1, "2030-01-01T10:00:00Z")
	Set plain = ..Memory(session, ..Text(10, "b"))
	Do $$$AssertStatusOK(..Host.OnUnpin(..Unpin(session, pinned), .response), "unpin a pinned memory")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message_"|"_response.Ref, "1|unpinned||"_pinned, "Ok 1, unpinned, no message, the Ref")
	Do $$$AssertEquals(..State(pinned), "0|", "Pinned 0 and PinnedAt empty")
	Do $$$AssertStatusOK(..Host.OnUnpin(..Unpin(session, plain), .response), "unpin an unpinned memory")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|unpinned", "also unpinned, Ok 1")
	Do $$$AssertEquals(..State(plain), "0|", "and unchanged")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read")
	Do $$$AssertEquals(rows.%Size(), 0, "no memory is pinned")
}

/// DW-740: another session's Ref and an unknown Ref answer the same not_found, for a pin and an unpin, and change nothing.
Method TestOtherSession()
{
	Set mine = ..Session(), theirs = ..Session()
	Set own = ..Memory(theirs, ..Text(10, "a"))
	Set owned = ..Memory(theirs, ..Text(10, "b"), 1, "2030-01-01T10:00:00Z")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(mine, own), .other), "pin another session's memory")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(mine, "zzMemoryPin0000000001"), .unknown), "pin an unknown Ref")
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome, "0|not_found", "another session's Ref is not_found")
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome_"|"_other.Message_"|"_other.Ref, unknown.Ok_"|"_unknown.Outcome_"|"_unknown.Message_"|"_unknown.Ref, "the same answer as an unknown Ref")
	Do $$$AssertStatusOK(..Host.OnUnpin(..Unpin(mine, owned), .other), "unpin another session's memory")
	Do $$$AssertStatusOK(..Host.OnUnpin(..Unpin(mine, "zzMemoryPin0000000001"), .unknown), "unpin an unknown Ref")
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome, "0|not_found", "another session's Ref is not_found for an unpin")
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome_"|"_other.Message_"|"_other.Ref, unknown.Ok_"|"_unknown.Outcome_"|"_unknown.Message_"|"_unknown.Ref, "the same answer as an unknown Ref")
	Do $$$AssertEquals(..State(own)_"|"_..State(owned), "0||1|2030-01-01T10:00:00Z", "and the other session's memories are unchanged")
}

/// A command whose session has no row answers no_session, for a pin and an unpin, and changes nothing.
Method TestNoSession()
{
	Set session = ..Session()
	Set ref = ..Memory(session, ..Text(10, "a"))
	Set ghost = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(ghost, ref), .response), "pin for a session with no row")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "no_session")
	Do $$$AssertStatusOK(..Host.OnUnpin(..Unpin(ghost, ref), .response), "unpin for a session with no row")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "no_session")
	Do $$$AssertEquals(..State(ref), "0|", "and the memory is unchanged")
}

/// A session whose lock is not free answers failed (Ok 0) for a pin and an unpin, and the memory is unchanged; with the lock free again the pin goes through.
Method TestLockBusy()
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Memory.PinsProbe", .sc)
	Do $$$AssertStatusOK(sc, "the probe instance of MemoryOps")
	Set session = ..Session()
	Set ref = ..Memory(session, ..Text(10, "a"))
	Set ^||PinsProbe("busy") = 1
	Do $$$AssertStatusOK(host.OnPin(..Pin(session, ref), .response), "pin with the lock busy")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "failed")
	Do $$$AssertEquals(..State(ref), "0|", "and the memory is unchanged")
	Do $$$AssertStatusOK(host.OnUnpin(..Unpin(session, ref), .response), "unpin with the lock busy")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "failed")
	Kill ^||PinsProbe("busy")
	Do $$$AssertStatusOK(host.OnPin(..Pin(session, ref), .response), "pin with the lock free")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|pinned", "pinned")
}

/// Forgetting a pinned memory deletes it: it is gone from Pinned and from the block, and its room is free again.
Method TestForgetPinned()
{
	Set session = ..Session()
	Set a = ..Memory(session, ..Text(2000, "a"))
	Set b = ..Memory(session, ..Text(1956, "b"))
	Set c = ..Memory(session, ..Text(1956, "c"))
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, a), .response), "pin A")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, b), .response), "pin B")
	Do $$$AssertEquals(response.Outcome, "pinned", "the block is exactly 4,000")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, c), .response), "pin C")
	Do $$$AssertEquals(response.Outcome, "over_cap", "C does not fit")
	Set command = ##class(OcuTalon.Msg.Command.ForgetMemory).%New()
	Set command.SessionRef = session
	Set command.MemoryRef = a
	Set command.Origin = "web_user"
	Do $$$AssertStatusOK(..Host.OnForget(command, .response), "forget the pinned A")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|forgotten", "forgotten")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Memory).RefIndexOpen(a)), 0, "the row is deleted")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read")
	Do $$$AssertEquals(rows.%Size()_"|"_rows.%Get(0).memoryRef, "1|"_b, "only B is pinned")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, "", .block), "the block")
	Do $$$AssertEquals($Length(block), 36 + 3 + 1956 + 2, "holds only B")
	Do $$$AssertStatusOK(..Host.OnPin(..Pin(session, c), .response), "pin C again")
	Do $$$AssertEquals(response.Outcome, "pinned", "C fits now")
}

/// Memory.Pinned: the session's pinned rows only, newest pin first, then the higher row id first; a row with an empty or 0 Pinned and another session's rows are not in it.
Method TestPinnedOrder()
{
	Set session = ..Session(), other = ..Session()
	Set p1 = ..Memory(session, "p1", 1, "2030-01-01T10:00:00Z")
	Set p2 = ..Memory(session, "p2", 1, "2030-01-03T10:00:00Z")
	Set p3 = ..Memory(session, "p3", 1, "2030-01-03T10:00:00Z")
	Set p4 = ..Memory(session, "p4", 1, "2030-01-02T10:00:00Z")
	Do ..Memory(session, "plain")
	Set old = ..Memory(session, "old", 1, "2030-01-09T10:00:00Z")
	Do ..Blank(old)
	Do ..Memory(other, "theirs", 1, "2030-01-10T10:00:00Z")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).Pinned(session, .rows), "the pinned read")
	Set order = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set order = order_$Select(order = "": "", 1: ",")_row.memoryRef
	}
	Do $$$AssertEquals(order, p3_","_p2_","_p4_","_p1, "newest pin first, a tie by the higher row id, and only the session's own pinned rows")
	Do $$$AssertEquals(rows.%Get(0).text_"|"_rows.%Get(0).pinned_"|"_rows.%Get(0).source, "p3|1|told", "each row has the shape of List")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).CoreBlock(session, "", .block), "the block")
	Set lf = $Char(10)
	Do $$$AssertEquals(block, "Your core memory (facts you pinned):"_lf_"> p3"_lf_"> p2"_lf_"> p4"_lf_"> p1"_lf_lf, "is the heading and the pins, each quoted, newest first, and a blank line")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Memory).Pinned("", .none)), "an empty session is an error status")
	Do $$$AssertEquals(none.%Size(), 0, "with no rows")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Memory).CoreBlock("", "x", .empty)), "and no block either")
	Do $$$AssertEquals(empty, "", "which is empty")
}

/// A fixture session, recorded for the clean-up.
Method Session() As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpins"_..Number_"n"_..Count)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A text of the length: the character repeated.
ClassMethod Text(length As %Integer, char As %String) As %String [ Private ]
{
	Quit $Translate($Justify("", length), " ", char)
}

/// Saves a memory of the session directly, with a vector that has no meaning (no embedder); pinned memories get the PinnedAt. Returns its Ref.
Method Memory(session As %String, text As %String, pinned As %Boolean = 0, pinnedAt As %String = "") As %String [ Private ]
{
	Set ones = ""
	For i = 1:1:384 {
		Set ones = ones_$Select(i > 1: ",", 1: "")_"1"
	}
	Set row = ##class(OcuTalon.Data.Memory).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = session
	Set row.Text = text
	Set row.SavedAt = "2030-01-01T09:00:00Z"
	Set row.ItemId = "zzmemorypins"
	Set row.Origin = "tool"
	Set row.Source = "told"
	Set row.Pinned = pinned
	If pinned Set row.PinnedAt = pinnedAt
	Set row.Embedding = ##class(OcuTalon.Test.Memory.Fixture).ToVector(ones)
	Do $$$AssertStatusOK(row.%Save(), "a fixture memory is saved")
	Quit row.Ref
}

/// Makes the stored Pinned of the row empty, as a row saved before Story 41.8 has it.
Method Blank(ref As %String) [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Memory SET Pinned = NULL WHERE Ref = ?", ref)
	Do $$$AssertEquals(result.%SQLCODE, 0, "the stored Pinned is made empty")
}

/// The stored Pinned of the row as it is (empty stays empty).
ClassMethod Stored(ref As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Pinned FROM OcuTalon_Data.Memory WHERE Ref = ?", ref)
	If result.%Next() Quit result.%GetData(1)
	Quit "none"
}

/// "Pinned|PinnedAt" of the row, read fresh (Pinned 0 for an empty one).
ClassMethod State(ref As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Pinned, PinnedAt FROM OcuTalon_Data.Memory WHERE Ref = ?", ref)
	If result.%Next() Quit +result.%GetData(1)_"|"_result.%GetData(2)
	Quit "none"
}

/// A PinMemory of the session for the memory, origin web_user.
ClassMethod Pin(session As %String, ref As %String) As OcuTalon.Msg.Command.PinMemory [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.PinMemory).%New()
	Set command.SessionRef = session
	Set command.MemoryRef = ref
	Set command.Origin = "web_user"
	Quit command
}

/// An UnpinMemory of the session for the memory, origin web_user.
ClassMethod Unpin(session As %String, ref As %String) As OcuTalon.Msg.Command.UnpinMemory [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.UnpinMemory).%New()
	Set command.SessionRef = session
	Set command.MemoryRef = ref
	Set command.Origin = "web_user"
	Quit command
}

}
