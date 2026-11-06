/// MemoryOps (AD-1, AD-4, AD-21, AD-33; Lane A): the business operation that keeps a session's memories. An adapterless operation, like WatchOps. It alone
/// writes OcuTalon.Data.Memory; reads go through OcuTalon.Memory.Search and OcuTalon.Memory.List. It answers every command with an
/// OcuTalon.Msg.CommandResult whose messages are plain sentences for the model and the caller, never rendered from the catalog (AD-32).
///   - SaveMemory: the command's session must have a Data.Session row (otherwise no_session), and its text, trimmed, must not be empty (otherwise
///     empty_text, Ok 0). Under the session's lock a memory of the same session, ItemId and text (the natural key; ItemId is the part of the
///     idempotency key before its last colon, the turn's item) is not saved a second time: the answer is saved with the first row's Ref, so a
///     re-sent turn adds nothing. Otherwise the text is embedded through OcuTalon.Memory.Embedding, and a failure answers failed and stores nothing;
///     else one row is written with a new Ref, SavedAt (UTC to the second), ItemId, the command's Origin and the 384-value embedding, and the answer is
///     saved (Ok 1) with the Ref. A text over 2,000 characters cannot be saved and answers failed.
///   - ForgetMemory: the row is found by its Ref, and it is the command's session's own row or nothing: a Ref that no row has and a Ref of another
///     session's memory answer the same not_found (Ok 0) and delete nothing (DW-740). Otherwise the row is deleted, with its vector and keyword
///     entries, and the answer is forgotten (Ok 1).
///   - A lock on the session that cannot be taken within 5 seconds, a save or delete that fails and any exception answer failed.
///   - After a new row is saved, Tuned is called with its id, which has the SQL statistics of the table gathered at every STATSEVERY-th id
///     (OcuTalon.Memory.Tune), so that the recall query keeps using the HNSW index as the table grows.
/// The commands arrive from CommandsIn with origin tool only (AD-1), and the memory's Origin is the command's.
Class OcuTalon.Memory.Ops Extends Ens.BusinessOperation
{

/// The most characters a memory holds (the length of Data.Memory.Text).
Parameter MAXTEXT = 2000;

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
			Set sc = ##class(OcuTalon.Memory.Embedding).Embed(text, .vector)
			If $$$ISOK(sc) {
				Set row = ##class(OcuTalon.Data.Memory).%New()
				Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set row.SessionRef = request.SessionRef
				Set row.Text = text
				Set row.SavedAt = ##class(OcuTalon.Data.Time).NowUtc()
				Set row.ItemId = itemId
				Set row.Origin = request.Origin
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

/// Called with the id of each row that was just saved: gathers the table's statistics at every STATSEVERY-th id (OcuTalon.Memory.Tune). A seam for the
/// tests. A failure is ignored: the memory is saved, and a plan on older statistics only costs time.
Method Tuned(id As %Integer)
{
	Try {
		Do ##class(OcuTalon.Memory).Tune(id)
	} Catch exception {
	}
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
