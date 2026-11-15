/// MemoryOps (AD-1, AD-4, AD-21, AD-33; Lane A): the business operation that keeps a session's memories. An adapterless operation, like WatchOps. It alone
/// writes OcuTalon.Data.Memory; reads go through OcuTalon.Memory.Search and OcuTalon.Memory.List. It answers every command with an
/// OcuTalon.Msg.CommandResult whose messages are plain sentences for the model and the caller, never rendered from the catalog (AD-32).
///   - SaveMemory: the command's session must have a Data.Session row (otherwise no_session), and its text, trimmed, must not be empty (otherwise
///     empty_text, Ok 0). Under the session's lock a memory of the same session, ItemId and text (the natural key; ItemId is the part of the
///     idempotency key before its last colon, the turn's item) is not saved a second time: the answer is saved with the first row's Ref, so a
///     re-sent turn adds nothing and keeps the first row's Source. Otherwise Source is learned for the origin photo (the caption of a photo, whatever the turn's text says), else it is decided from the person's own text of the saving turn (the Source
///     method: told when it holds a phrase of OcuTalon.Tools.MemorySource PHRASES, else learned; learned when the session has no such turn; the saving turn is the turn with the ItemId, or the running turn whose retry
///     after a rejected history has it), and a turn
///     that cannot be read answers failed and stores nothing. The text is then embedded through OcuTalon.Memory.Embedding, and a failure answers failed and
///     stores nothing; else one row is written with a new Ref, SavedAt (UTC to the second), ItemId, the command's Origin, Source, Pinned 0, PinnedAt empty
///     and the 384-value embedding, and the answer is saved (Ok 1) with the Ref. A text over 2,000 characters cannot be saved and answers failed.
///   - ForgetMemory: the row is found by its Ref, and it is the command's session's own row or nothing: a Ref that no row has and a Ref of another
///     session's memory answer the same not_found (Ok 0) and delete nothing (DW-740). Otherwise the row is deleted, with its vector and keyword
///     entries, and the answer is forgotten (Ok 1).
///   - SearchMemory (Story 41.9; a read, from origin web_user): OcuTalon.Memory.Search runs for the command's own SessionRef, never another, with the query and at most
///     OcuTalon.Memory MAXLIMIT items, and the answer is Ok 1, Outcome done, with the items as the JSON array [{ref, text, savedAt, source, pinned}] (pinned a
///     boolean, no origin) in Data. It changes no row and takes no lock. A search that fails (an empty query or session, a query that cannot be embedded) answers failed.
///   - PinMemory (Story 41.12; from origin web_user only, as 41.9's gate decides): the memory is found as ForgetMemory finds it, so a Ref that no row has and a Ref of another
///     session's memory answer the same not_found (Ok 0, an empty Message) and change nothing. A memory that is already pinned answers pinned (Ok 1) and keeps its PinnedAt. Otherwise, under the
///     session's lock, the core-memory block that the session would have with this memory pinned (OcuTalon.Memory.CoreBlock with the memory's text as the newest pin; the block
///     is formatted by OcuTalon.Agent.Input.CoreBlock and read from Memory.Pinned, where a row saved before Story 41.8 is not pinned) must be at most OcuTalon.Memory COREMAX
///     characters, heading, quotes and closing blank line included: if it is longer the answer is over_cap (Ok 0, the existing text of the web layer) and nothing changes, and nothing
///     is ever unpinned to make room. A memory of origin photo (the caption of a photo, Story 26.3) is never pinned: before the pinned and cap checks the answer is
///     pin_photo (Ok 0, an empty Message) and nothing changes. Otherwise Pinned is 1, PinnedAt is now (UTC to the second), and the answer is pinned (Ok 1, an empty Message) with the Ref.
///   - UnpinMemory (Story 41.12; origin web_user only): an own memory, pinned or not, gets Pinned 0 and PinnedAt empty, and the answer is unpinned (Ok 1, an empty Message); another
///     session's memory and an unknown Ref answer not_found (Ok 0, an empty Message).
///   - ListPinnedMemories (Story 41.13; a read, from origin web_user): the command's own SessionRef's pinned memories (OcuTalon.Memory.Pinned), newest pin first, as the same items as a search, and
///     used, the tokens of the core-memory block: ceil($Length of OcuTalon.Memory.CoreBlock / OcuTalon.Memory CHARSPERTOKEN), the cap's own computation, 0 with no pin. Data is {items, used}. It changes
///     no row and takes no lock; a failure answers failed.
///   - Who may ask (DW-1029): SaveMemory comes from origin tool, or photo (Story 26.3: Agent.Content saves the caption of a photo); ForgetMemory from tool or web_user; PinMemory, UnpinMemory, SearchMemory and ListPinnedMemories from web_user only (CommandsIn).
///   - A lock on the session that cannot be taken within 5 seconds, a save or delete that fails and any exception answer failed.
///   - After a new row is saved, Tuned is called with its id, which has the SQL statistics of the table gathered at every STATSEVERY-th id
///     (OcuTalon.Memory.Tune), so that the recall query keeps using the HNSW index as the table grows.
/// The commands arrive from CommandsIn (AD-1; the origins are listed above), and the memory's Origin is the command's.
Class OcuTalon.Memory.Ops Extends Ens.BusinessOperation
{

/// The most characters a memory holds (the length of Data.Memory.Text).
Parameter MAXTEXT = 2000;

/// The origin of a photo's caption (AD-21): a caption is learned whatever the turn's text says, so Source is not asked.
Parameter PHOTOORIGIN = "photo";

Parameter MESSAGESAVED = "The memory was saved.";

Parameter MESSAGEFORGOTTEN = "The memory was forgotten.";

Parameter MESSAGENOTFOUND = "The session has no such memory, so nothing was forgotten.";

Parameter MESSAGENOSESSION = "The command names no session, so nothing was done.";

Parameter MESSAGEEMPTY = "The text to remember is empty, so nothing was saved.";

/// The answer when the session's memories are busy (another command holds them), the text cannot be embedded, or the row cannot be saved or removed.
Parameter MESSAGEFAILED = "The memory could not be saved or forgotten just now, so nothing was done.";

Parameter LOGFAILED = "MemoryOps could not carry out a command: ";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Command.SaveMemory">
<Method>OnSave</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.ForgetMemory">
<Method>OnForget</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.SearchMemory">
<Method>OnSearch</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.ListPinnedMemories">
<Method>OnListPinned</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.PinMemory">
<Method>OnPin</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.UnpinMemory">
<Method>OnUnpin</Method>
</MapItem>
</MapItems>
}

/// Saves the command's text as a memory of its session, or answers why not (see the class description).
Method OnSave(request As OcuTalon.Msg.Command.SaveMemory, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set text = $ZStrip(request.Text, "<>WC")
	If text = "" Quit ..Answer(.response, 0, "empty_text", ..#MESSAGEEMPTY)
	If $Length(text) > ..#MAXTEXT Quit ..Failed(.response, $SYSTEM.Status.Error(5001, "The text is over "_..#MAXTEXT_" characters"))
	Set itemId = $Piece(request.IdempotencyKey, ":", 1, $Length(request.IdempotencyKey, ":") - 1)
	Set lock = ..Lock(request.SessionRef)
	If 'lock Quit ..Failed(.response, $SYSTEM.Status.Error(5001, "The memories of the session are busy"))
	Set sc = $$$OK
	Try {
		Set ref = ..RefOf(request.SessionRef, itemId, text)
		If ref '= "" {
			Set sc = ..Answer(.response, 1, "saved", ..#MESSAGESAVED, ref)
		} Else {
			If request.Origin = ..#PHOTOORIGIN {
				Set source = ##class(OcuTalon.Tools.MemorySource).#LEARNED
			} Else {
				Set sc = ..Source(request.SessionRef, itemId, .source)
			}
			If $$$ISOK(sc) Set sc = ##class(OcuTalon.Memory.Embedding).Embed(text, .vector)
			If $$$ISOK(sc) {
				Set row = ##class(OcuTalon.Data.Memory).%New()
				Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set row.SessionRef = request.SessionRef
				Set row.Text = text
				Set row.SavedAt = ##class(OcuTalon.Data.Time).NowUtc()
				Set row.ItemId = itemId
				Set row.Origin = request.Origin
				Set row.Source = source
				Set row.Embedding = vector
				Set sc = row.%Save()
			}
			If $$$ISOK(sc) {
				Set sc = ..Answer(.response, 1, "saved", ..#MESSAGESAVED, row.Ref)
				Do ..Tuned(row.%Id())
			} Else {
				Set sc = ..Failed(.response, sc)
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	Lock -^OcuTalon.Memory(request.SessionRef)
	Quit sc
}

/// Decides the source of a memory that the session's turn with this ItemId is saving: in source, OcuTalon.Tools.MemorySource TOLD when the person's own text of
/// that turn (Data.Turn.Text, of the turn that TurnOf finds) holds a phrase of PHRASES, else LEARNED; LEARNED also when the session has no such turn. An
/// error status when the turn cannot be read, with source empty.
Method Source(sessionRef As %String, itemId As %String, Output source As %String) As %Status
{
	Set source = ""
	Set turn = ..TurnOf(sessionRef, itemId, .sc)
	If $$$ISERR(sc) Quit sc
	Set source = $Select($IsObject(turn): ##class(OcuTalon.Tools.MemorySource).Of(turn.Text), 1: ##class(OcuTalon.Tools.MemorySource).#LEARNED)
	Quit $$$OK
}

/// The session's turn that a save with this ItemId belongs to, or "": TurnOfItem. A seam for the tests.
Method TurnOf(sessionRef As %String, itemId As %String, Output sc As %Status) As OcuTalon.Data.Turn
{
	Quit ..TurnOfItem(sessionRef, itemId, .sc)
}

/// The session's turn that was made from the Item with this ItemId, or "": the turn with the ItemId (Data.Ownership.TurnOfItem), else the session's queued or
/// running turn whose retry has it (a turn that Conversation sends again after the provider rejected the session's history carries
/// OcuTalon.Core.Conversation RetryItemId of its ItemId). sc is an error status when the turns cannot be read. Agent.Content reads the photo turn through it.
ClassMethod TurnOfItem(sessionRef As %String, itemId As %String, Output sc As %Status) As OcuTalon.Data.Turn
{
	Set turn = ##class(OcuTalon.Data.Ownership).TurnOfItem(itemId, sessionRef, .sc)
	If $$$ISERR(sc) || $IsObject(turn) || (itemId = "") Quit turn
	Set queue = ##class(OcuTalon.Data.Ownership).TurnQueue(sessionRef, .sc)
	If $$$ISERR(sc) Quit ""
	For i = 1:1:queue.Count() {
		If ##class(OcuTalon.Core.Conversation).RetryItemId(queue.GetAt(i).ItemId) = itemId {
			Set turn = queue.GetAt(i)
			Quit
		}
	}
	Quit turn
}

/// Forgets the command's memory if it is the command's session's own, or answers that there is none.
Method OnForget(request As OcuTalon.Msg.Command.ForgetMemory, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set lock = ..Lock(request.SessionRef)
	If 'lock Quit ..Failed(.response, $SYSTEM.Status.Error(5001, "The memories of the session are busy"))
	Set sc = $$$OK
	Try {
		Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(request.MemoryRef)
		If '$IsObject(row) || (row.SessionRef '= request.SessionRef) {
			Set sc = ..Answer(.response, 0, "not_found", ..#MESSAGENOTFOUND)
		} Else {
			Set id = row.%Id()
			Set row = ""
			Set sc = ##class(OcuTalon.Data.Memory).%DeleteId(id)
			If $$$ISOK(sc) {
				Set sc = ..Answer(.response, 1, "forgotten", ..#MESSAGEFORGOTTEN)
			} Else {
				Set sc = ..Failed(.response, sc)
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	Lock -^OcuTalon.Memory(request.SessionRef)
	Quit sc
}

/// Pins the command's memory if it is the command's session's own and the core-memory block with it stays within COREMAX characters (see the class description).
Method OnPin(request As OcuTalon.Msg.Command.PinMemory, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set lock = ..Lock(request.SessionRef)
	If 'lock Quit ..Failed(.response, $SYSTEM.Status.Error(5001, "The memories of the session are busy"))
	Set sc = $$$OK
	Try {
		Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(request.MemoryRef)
		If '$IsObject(row) || (row.SessionRef '= request.SessionRef) {
			Set sc = ..Answer(.response, 0, "not_found", "")
		} ElseIf row.Origin = ..#PHOTOORIGIN {
			Set sc = ..Answer(.response, 0, "pin_photo", "")
		} ElseIf +row.Pinned = 1 {
			Set sc = ..Answer(.response, 1, "pinned", "", row.Ref)
		} Else {
			Set sc = ##class(OcuTalon.Memory).CoreBlock(request.SessionRef, row.Text, .block)
			If $$$ISERR(sc) {
				Set sc = ..Failed(.response, sc)
			} ElseIf $Length(block) > ##class(OcuTalon.Memory).#COREMAX {
				Set sc = ..Answer(.response, 0, "over_cap", "")
			} Else {
				Set row.Pinned = 1
				Set row.PinnedAt = ##class(OcuTalon.Data.Time).NowUtc()
				Set sc = row.%Save()
				If $$$ISOK(sc) {
					Set sc = ..Answer(.response, 1, "pinned", "", row.Ref)
				} Else {
					Set sc = ..Failed(.response, sc)
				}
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	Lock -^OcuTalon.Memory(request.SessionRef)
	Quit sc
}

/// Unpins the command's memory if it is the command's session's own, or answers that there is none.
Method OnUnpin(request As OcuTalon.Msg.Command.UnpinMemory, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set lock = ..Lock(request.SessionRef)
	If 'lock Quit ..Failed(.response, $SYSTEM.Status.Error(5001, "The memories of the session are busy"))
	Set sc = $$$OK
	Try {
		Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(request.MemoryRef)
		If '$IsObject(row) || (row.SessionRef '= request.SessionRef) {
			Set sc = ..Answer(.response, 0, "not_found", "")
		} Else {
			Set row.Pinned = 0
			Set row.PinnedAt = ""
			Set sc = row.%Save()
			If $$$ISOK(sc) {
				Set sc = ..Answer(.response, 1, "unpinned", "", row.Ref)
			} Else {
				Set sc = ..Failed(.response, sc)
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	Lock -^OcuTalon.Memory(request.SessionRef)
	Quit sc
}

/// Searches the command's session's memories for its query and answers the items in Data (see the class description).
Method OnSearch(request As OcuTalon.Msg.Command.SearchMemory, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	Try {
		Set sc = ##class(OcuTalon.Memory).Search(request.SessionRef, request.Query, ##class(OcuTalon.Memory).#MAXLIMIT, .rows)
		If $$$ISERR(sc) Quit
		Set items = ..Items(rows)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) Quit ..Failed(.response, sc)
	Set sc = ..Answer(.response, 1, "done", "")
	Set response.Data = items.%ToJSON()
	Quit sc
}

/// Lists the command's own session's pinned memories, newest pin first, with the tokens they use (see the class description). It changes no row and takes no lock:
/// this operation runs one job, and that job is the only writer of a pin.
Method OnListPinned(request As OcuTalon.Msg.Command.ListPinnedMemories, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	Try {
		Set sc = ##class(OcuTalon.Memory).Pinned(request.SessionRef, .rows)
		If $$$ISERR(sc) Quit
		Set sc = ##class(OcuTalon.Memory).CoreBlock(request.SessionRef, "", .block)
		If $$$ISERR(sc) Quit
		Set perToken = ##class(OcuTalon.Memory).#CHARSPERTOKEN
		Set data = {}
		Set data.items = ..Items(rows)
		Set data.used = ($Length(block) + perToken - 1) \ perToken
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) Quit ..Failed(.response, sc)
	Set sc = ..Answer(.response, 1, "done", "")
	Set response.Data = data.%ToJSON()
	Quit sc
}

/// The rows of Memory.Search or Memory.Pinned as the JSON array [{ref, text, savedAt, source, pinned}] (pinned a boolean, no origin).
ClassMethod Items(rows As %DynamicArray) As %DynamicArray [ Private ]
{
	Set items = []
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set item = {}
		Set item.ref = row.memoryRef
		Set item.text = row.text
		Set item.savedAt = row.savedAt
		Set item.source = row.source
		Do item.%Set("pinned", (row.pinned = 1), "boolean")
		Do items.%Push(item)
	}
	Quit items
}

/// Called with the id of each row that was just saved: gathers the table's statistics at every STATSEVERY-th id (OcuTalon.Memory.Tune), and returns 1
/// when it gathered them, else 0. A seam for the tests. A failure is ignored (0): the memory is saved, and a plan on older statistics only costs time.
Method Tuned(id As %Integer) As %Boolean
{
	Set tuned = 0
	Try {
		Set tuned = ##class(OcuTalon.Memory).Tune(id)
	} Catch exception {
		Set tuned = 0
	}
	Quit tuned
}

/// Builds the failed answer in response, after one Type 3 warning that holds the status text (redacted).
ClassMethod Failed(ByRef response As OcuTalon.Msg.CommandResult, cause As %Status) As %Status [ Private ]
{
	$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(cause)))
	Quit ..Answer(.response, 0, "failed", ..#MESSAGEFAILED)
}

/// The Ref of the session's memory with the ItemId and exactly the text (its natural key), or "" when it has none.
ClassMethod RefOf(sessionRef As %String, itemId As %String, text As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Ref FROM OcuTalon_Data.Memory WHERE SessionRef = ? AND ItemId = ? AND %EXACT(Text) = ? ORDER BY ID", sessionRef, itemId, text)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "MemoryOps could not read the memories of the session: "_rs.%Message))
	If 'rs.%Next() Quit ""
	Quit rs.%Get("Ref")
}

/// Takes the lock that serialises the commands of one session; 1 when it is held. The caller releases it.
ClassMethod Lock(sessionRef As %String) As %Boolean [ Private ]
{
	Lock +^OcuTalon.Memory(sessionRef):5
	Quit $Test
}

/// Builds the CommandResult in response and returns OK.
ClassMethod Answer(ByRef response As OcuTalon.Msg.CommandResult, ok As %Boolean, outcome As %String, message As %String, ref As %String = "") As %Status [ Private ]
{
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	Set response.Ok = ok
	Set response.Outcome = outcome
	Set response.Message = message
	Set response.Ref = ref
	Quit $$$OK
}

}
