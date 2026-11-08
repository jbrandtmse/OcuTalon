Include Ensemble

/// DocumentOps (AD-1, AD-4, AD-5, AD-12, AD-21, AD-33; Lane A): the business operation that keeps the documents of a local install and of each online-demo
/// session. An adapterless operation, like MemoryOps. It alone writes OcuTalon.Data.Document and the rows of the knowledge-base tables (through
/// OcuTalon.Docs.Store), with two exceptions: the evaluation path of this class (AddEval and RemoveEval, below), which writes only documents of the owner
/// eval in the caller's process, and the sign-out deletion of a session's documents and tables (OcuTalon.Docs DropSession, in SessionOps' job, under the
/// owner's exclusive lock); and it is the single publisher of the document live event (OcuTalon.Live.Payload.Document, on the stream of the document's owner:
/// the instance stream for a local install, the session's own stream on the online demo). Each owner has its own table (Docs.Store TableFor): OcuTalonKB.Docs
/// for the install, OcuTalonKB.S<id> for a session, OcuTalonKB.Eval for an evaluation run. The table of a session is made by its first AddDocument, and
/// OcuTalon.Docs DropSession drops it at sign-out. Every operation on a document's rows uses that row's own KnowledgeBase. It answers AddDocument and RemoveDocument synchronously with an
/// OcuTalon.Msg.CommandResult, and indexes asynchronously: a message to itself (OcuTalon.Docs.Msg.Index) indexes BATCH passages at a time, so the commands that
/// queue meanwhile are handled between the batches.
///   - AddDocument: an unknown session answers no_session (Ok 0) and nothing is taken. Otherwise the upload is taken once with the command's SessionRef
///     (Upload.Take); an upload that is gone (taken, dropped or another session's, DW-747) writes a failed row (reason failed) and answers failed (Ok 0) with
///     the row's Ref. The bytes of a markdown or text document must
///     be UTF-8 without a NUL and not blank once a BOM is stripped, else the row is failed with the reason unreadable; a pdf or docx document is failed with the
///     reason not_built (Story 19.7 sends them through Docs.Extract at the Text seam). Every failed row is published and the answer is added (Ok 1) with its Ref
///     and the message MESSAGENOTINDEXED. An unexpected failure answers failed (Ok 0) with CommandsIn's failure text and logs one redacted warning.
///     Otherwise the table of the owner (Docs.Store OwnerFor and TableFor: the session itself on the online demo, instance on a local install) is made when it
///     is missing, and the row is saved with the state indexing (OwnerRef the owner, AddedBy the command's session, the text, KnowledgeBase the owner's table),
///     published, and Index(Ref, 0) is sent to this operation; the answer is added (Ok 1) with the Ref. A table that cannot be made is a failed row with the
///     reason failed, as any other failure to index.
///   - Index: nothing when the row is gone or is not indexing. Otherwise the text is split (Docs.Passages); at ChunkFrom 0 the section of each passage is stored in the
///     row (Sections) and the document's old rows are removed; then the passages from ChunkFrom are embedded and written, and either Index(Ref, ChunkFrom + BATCH) is sent
///     or, when the last passage was written, the state becomes ready and the row is published. An error removes the document's rows, sets the state failed with
///     the reason failed, publishes the row and logs one redacted warning.
///   - RemoveDocument: an unknown session answers no_session. A Ref that no document of the session's owner has answers not_found (Ok 0). Otherwise the rows of
///     the document leave its knowledge base, then the row is deleted, a last event with removed true is published, and the answer is removed (Ok 1). The next search
///     returns none of its passages, and a later Index finds no row and stops.
///   - The evaluation path (AddEval, RemoveEval; AD-22): a documents case of the evaluation set indexes its files here without a command, a session, an Upload or
///     a message to this operation. AddEval writes a row with OwnerRef and AddedBy the literal eval (no route lists it: they list instance or a session) and
///     its passages go to OcuTalonKB.Eval, which no person's turn searches (DW-901). It runs the same IndexBatch that Index runs, batch after batch, in the caller's
///     process; it publishes no event. RemoveEval takes the passages and the row of an eval document away, from the table the row names, and refuses a document of
///     any other owner.
/// A publish that fails is one redacted warning and never changes an answer. Publish runs outside any transaction. A document belongs to its owner: the install,
/// one online-demo session or an evaluation run. The commands come from CommandsIn from web_user only (AD-1).
Class OcuTalon.Docs.Ops Extends Ens.BusinessOperation
{

/// The passages one Index message writes.
Parameter BATCH = 8;

Parameter MESSAGEADDED = "The document was added and is being indexed.";

Parameter MESSAGEREMOVED = "The document was removed.";

Parameter MESSAGENOTFOUND = "The install has no such document, so nothing was removed.";

Parameter MESSAGENOSESSION = "The command names no session, so nothing was done.";

/// The answer for a document whose row is written as failed (its Reason says why).
Parameter MESSAGENOTINDEXED = "The document was added, but it cannot be indexed: its row holds the reason.";

/// The answer when the upload is gone (taken, dropped or another session's).
Parameter MESSAGEFAILED = "The upload is gone, so the document was not indexed.";

Parameter LOGFAILED = "DocumentOps could not index a document: ";

Parameter LOGPUBLISH = "DocumentOps could not publish the document event of ";

Parameter LOGSTART = "DocumentOps could not make the table of the documents: ";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Command.AddDocument">
<Method>OnAdd</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.RemoveDocument">
<Method>OnRemove</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Docs.Msg.Index">
<Method>OnIndex</Method>
</MapItem>
</MapItems>
}

/// Makes the knowledge-base table on a local install, so that the first search and the first batch find it. A failure is one warning: the next AddDocument
/// makes the table again. The online demo makes no table here: a session's table is made by its first AddDocument.
Method OnInit() As %Status
{
	If ##class(OcuTalon.Docs.Store).OnlineDemo() Quit $$$OK
	Set sc = ##class(OcuTalon.Docs.Store).EnsureTable()
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGSTART_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
	Quit $$$OK
}

/// Adds the command's document, or answers why not (see the class description).
Method OnAdd(request As OcuTalon.Msg.Command.AddDocument, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set sc = $$$OK
	Set locked = 0
	Set owner = ##class(OcuTalon.Docs.Store).OwnerFor(request.SessionRef)
	Try {
		Set bytes = ##class(OcuTalon.Data.Upload).Take(request.UploadRef, request.SessionRef)
		If '$IsObject(bytes) {
			Set row = ..Reject(request, 0, "failed", "")
			Set sc = ..Answer(.response, 0, "failed", ..#MESSAGEFAILED, row.Ref)
		} Else {
			Set size = bytes.Size
			Set text = ""
			Set reason = ""
			Do ..Text(bytes, request.ContentType, .text, .reason)
			If reason = "" Set reason = ..Prepare(owner, .locked)
			If reason '= "" {
				Set row = ..Reject(request, size, reason, "")
				Set sc = ..Answer(.response, 1, "added", ..#MESSAGENOTINDEXED, row.Ref)
			} Else {
				Set row = ..Save(request, size, text, "indexing", "")
				Set sc = ..Answer(.response, 1, "added", ..#MESSAGEADDED, row.Ref)
				Set index = ##class(OcuTalon.Docs.Msg.Index).%New()
				Set index.Ref = row.Ref
				Set index.ChunkFrom = 0
				Set send = ..SendRequestAsync(..%ConfigName, index)
				If $$$ISERR(send) Do ..Fail(row.Ref, send)
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	If locked Do ##class(OcuTalon.Docs.Store).UnlockOwner(owner)
	Quit sc
}

/// Makes sure that the owner's knowledge-base table exists, holding the owner's shared lock (locked 1; the caller releases it with Store UnlockOwner) so that a
/// drop of the owner's documents cannot run between the table and the row that names it. "" when it exists, else the reason failed (one warning).
Method Prepare(owner As %String, Output locked As %Boolean) As %String [ Private ]
{
	Set locked = 0
	Set table = ##class(OcuTalon.Docs.Store).TableFor(owner)
	Set sc = $SYSTEM.Status.OK()
	If table = "" {
		Set sc = $SYSTEM.Status.Error(5001, "The owner " _ owner _ " has no knowledge-base table")
	} Else {
		Set sc = ##class(OcuTalon.Docs.Store).LockOwner(owner)
		If $$$ISOK(sc) {
			Set locked = 1
			Set sc = ##class(OcuTalon.Docs.Store).EnsureTable(table)
		}
	}
	If $$$ISOK(sc) Quit ""
	$$$LOGWARNING(..#LOGSTART_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	Quit "failed"
}

/// Indexes one batch of the document, or stops when the document is gone or no longer indexing (see the class description).
Method OnIndex(request As OcuTalon.Docs.Msg.Index, Output response As Ens.Response) As %Status
{
	Set response = ""
	Set ref = request.Ref
	Try {
		Set from = +request.ChunkFrom
		Set sc = ..IndexBatch(ref, from, .state, .row)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		If state = "more" {
			Set index = ##class(OcuTalon.Docs.Msg.Index).%New()
			Set index.Ref = ref
			Set index.ChunkFrom = from + ..#BATCH
			Set sc = ..SendRequestAsync(..%ConfigName, index)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		} ElseIf state = "ready" {
			Do ..Publish(row, 0)
		}
	} Catch exception {
		Do ..Fail(ref, exception.AsStatus())
	}
	Quit $$$OK
}

/// Splits the text of the document ref and writes the passages from chunk_index from, BATCH of them, into the table the row names (the one step of the indexing
/// that DocumentOps and the evaluation path share; it changes no state but the document's and publishes nothing). It holds the shared lock of the row's owner
/// from before it reads the row until it has written (Docs.Store LockOwner), so that a drop of the owner's documents waits for a batch and the next batch finds
/// no row. state is gone when the row is missing or is not indexing (nothing is
/// done), more when passages remain after this batch, and ready when the last passage was written: the row is then saved as ready and returned in row. At
/// from 0 the section of each passage is stored in the row and the document's old rows leave the table first. A document that is gone or no longer indexing once the
/// last batch is written has its rows removed again (state gone). Returns the first error and leaves the cleanup to the caller.
ClassMethod IndexBatch(ref As %String, from As %Integer, Output state As %String, Output row As OcuTalon.Data.Document) As %Status
{
	Set state = "gone"
	Set row = ""
	Set sc = $$$OK
	Set owner = ""
	Set locked = 0
	Try {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		If '$IsObject(row) Quit
		Set owner = row.OwnerRef
		Set row = ""
		Set sc = ##class(OcuTalon.Docs.Store).LockOwner(owner)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		Set locked = 1
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		If '$IsObject(row) || (row.State '= "indexing") {
			Set row = ""
			Quit
		}
		Set table = $Select(row.KnowledgeBase '= "": row.KnowledgeBase, 1: ##class(OcuTalon.Docs.Store).#TABLE)
		Do row.Text.Rewind()
		Set text = row.Text.Read($$$MaxLocalLength)
		Set name = ##class(OcuTalon.Docs.Store).DocumentName(row.Name)
		Set sc = ##class(OcuTalon.Docs.Passages).Split(text, row.ContentType, .passages)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		If from = 0 {
			Set sections = []
			Set i = 0
			While i < passages.%Size() {
				Do sections.%Push(passages.%Get(i).section)
				Set i = i + 1
			}
			Set row.Sections = sections.%ToJSON()
			Set sc = row.%Save()
			If $$$ISERR(sc) $$$ThrowStatus(sc)
			Set sc = ##class(OcuTalon.Docs.Store).Remove(ref, table)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		}
		Set sc = ##class(OcuTalon.Docs.Store).Write(ref, name, passages, from, ..#BATCH, table, owner)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		If ##class(OcuTalon.Docs.Store).Draining(owner) {
			Set row = ""
			Quit
		}
		If (from + ..#BATCH) < passages.%Size() {
			Set state = "more"
			Set row = ""
		} Else {
			Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
			If $IsObject(row) && (row.State = "indexing") {
				Set row.State = "ready"
				Set sc = row.%Save()
				If $$$ISERR(sc) $$$ThrowStatus(sc)
				Set state = "ready"
			} Else {
				Set row = ""
				Do ##class(OcuTalon.Docs.Store).Remove(ref, table)
			}
		}
	} Catch exception {
		Set row = ""
		Set sc = exception.AsStatus()
	}
	If locked Do ##class(OcuTalon.Docs.Store).UnlockOwner(owner)
	Quit sc
}

/// Adds the document of an evaluation case (AD-22) and indexes it to the end in the caller's process, giving up when wait seconds have passed at the start of a batch (a batch in progress is finished): the bytes are read as OnAdd reads them
/// (Text), the row has OwnerRef and AddedBy eval (Docs.Store EVALOWNER) and the table OcuTalonKB.Eval, and IndexBatch writes the passages. No command, session, upload, message or live event is involved. Returns "" with the
/// document ready (its Ref in ref), else the reason it is not (unreadable, failed, not_built, or timeout), after the document's passages and row are taken away again.
ClassMethod AddEval(bytes As %Stream.Object, name As %String, contentType As %String, wait As %Integer, Output ref As %String) As %String
{
	Set ref = ""
	If ##class(OcuTalon.Docs.Store).OnlineDemo() Quit "not_built"
	Do ..Text(bytes, contentType, .text, .reason)
	If reason '= "" Quit reason
	Set outcome = ""
	Set table = ##class(OcuTalon.Docs.Store).#EVALTABLE
	Try {
		Set sc = ##class(OcuTalon.Docs.Store).EnsureTable(table)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		Set row = ..NewRow(##class(OcuTalon.Docs.Store).#EVALOWNER, ##class(OcuTalon.Docs.Store).#EVALOWNER, name, contentType, bytes.Size, text, "indexing", "", table)
		Set ref = row.Ref
		Set row = ""
		Set deadline = $ZHorolog + wait
		Set from = 0
		Set state = "more"
		While state = "more" {
			If $ZHorolog '< deadline {
				Set outcome = "timeout"
				Quit
			}
			Set sc = ..IndexBatch(ref, from, .state, .row)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
			Set from = from + ..#BATCH
		}
		If outcome = "" Set outcome = $Select(state = "ready": "", 1: "failed")
	} Catch exception {
		Set outcome = "failed"
	}
	If outcome '= "" {
		Do ..RemoveEval(ref)
		Set ref = ""
	}
	Quit outcome
}

/// Takes the passages and the row of the evaluation document ref away. A document that is not there is no error; a document of any other owner is refused and
/// left as it is (an error status), so that this method can never remove a document that a person added.
ClassMethod RemoveEval(ref As %String) As %Status
{
	If ref = "" Quit $$$OK
	Set sc = $$$OK
	Try {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		If $IsObject(row) && (row.OwnerRef '= ##class(OcuTalon.Docs.Store).#EVALOWNER) {
			Set sc = $SYSTEM.Status.Error(5001, "The document " _ ref _ " is not an evaluation document, so it was not removed")
		} Else {
			Set table = $Select($IsObject(row) && (row.KnowledgeBase '= ""): row.KnowledgeBase, 1: ##class(OcuTalon.Docs.Store).#EVALTABLE)
			Set sc = ##class(OcuTalon.Docs.Store).Remove(ref, table)
			If $IsObject(row) {
				Set id = row.%Id()
				Set row = ""
				Set deleted = ##class(OcuTalon.Data.Document).%DeleteId(id)
				If $$$ISOK(sc) Set sc = deleted
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Removes the command's document, or answers that there is none (see the class description).
Method OnRemove(request As OcuTalon.Msg.Command.RemoveDocument, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set sc = $$$OK
	Set locked = 0
	Set owner = ""
	Try {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(request.DocumentRef)
		If '$IsObject(row) || (row.OwnerRef '= ##class(OcuTalon.Docs.Store).OwnerFor(request.SessionRef)) {
			Set sc = ..Answer(.response, 0, "not_found", ..#MESSAGENOTFOUND)
		} Else {
			Set payload = ##class(OcuTalon.Live.Payload.Document).FromRow(row)
			Set payload.Removed = 1
			Set id = row.%Id()
			Set ref = row.Ref
			Set owner = row.OwnerRef
			Set table = $Select(row.KnowledgeBase '= "": row.KnowledgeBase, 1: ##class(OcuTalon.Docs.Store).#TABLE)
			Set row = ""
			Set sc = ##class(OcuTalon.Docs.Store).LockOwner(owner)
			If $$$ISOK(sc) {
				Set locked = 1
				Set sc = ##class(OcuTalon.Docs.Store).Remove(ref, table)
				If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.Document).%DeleteId(id)
			}
			If $$$ISOK(sc) {
				Do ..PublishPayload(payload, ref, owner)
				Set sc = ..Answer(.response, 1, "removed", ..#MESSAGEREMOVED)
			} Else {
				Set sc = ..Failed(.response, sc)
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	If locked Do ##class(OcuTalon.Docs.Store).UnlockOwner(owner)
	Quit sc
}

/// The text of the bytes of a document of the content type, in text, or the reason in reason: markdown and text are UTF-8 (a BOM is dropped) with no NUL and
/// something that is not blank, else unreadable; pdf and docx are not built until Story 19.7 (not_built). Never throws; a text that is too long to hold is
/// failed.
ClassMethod Text(bytes As %Stream.Object, contentType As %String, Output text As %String, Output reason As %String) As %Boolean
{
	Set text = ""
	Set reason = ""
	If (contentType '= "markdown") && (contentType '= "text") {
		Set reason = "not_built"
		Quit 0
	}
	Try {
		If bytes.Size > $$$MaxLocalLength {
			Set reason = "failed"
			Quit
		}
		Do bytes.Rewind()
		Set raw = bytes.Read($$$MaxLocalLength)
		Set decoded = $ZConvert(raw, "I", "UTF8")
		If $ZConvert(decoded, "O", "UTF8") '= raw {
			Set reason = "unreadable"
		} Else {
			If $Extract(decoded, 1) = $Char(65279) Set decoded = $Extract(decoded, 2, *)
			If (decoded [ $Char(0)) || ($ZStrip(decoded, "*WC") = "") {
				Set reason = "unreadable"
			} Else {
				Set text = decoded
			}
		}
	} Catch exception {
		Set text = ""
		Set reason = $Select(exception.Name [ "MAXSTRING": "failed", 1: "unreadable")
	}
	Quit reason = ""
}

/// Saves the row of the command's document with the state, and publishes it.
Method Save(request As OcuTalon.Msg.Command.AddDocument, size As %Integer, text As %String, state As %String, reason As %String) As OcuTalon.Data.Document [ Private ]
{
	Set owner = ##class(OcuTalon.Docs.Store).OwnerFor(request.SessionRef)
	Set row = ..NewRow(owner, request.SessionRef, request.Name, request.ContentType, size, text, state, reason, ##class(OcuTalon.Docs.Store).TableFor(owner))
	Do ..Publish(row, 0)
	Quit row
}

/// Saves a new document row for the owner and the adder, naming the owner's knowledge-base table, and throws when it cannot be saved. It publishes nothing:
/// Save publishes, the evaluation path does not.
ClassMethod NewRow(owner As %String, addedBy As %String, name As %String, contentType As %String, size As %Integer, text As %String, state As %String, reason As %String, table As %String) As OcuTalon.Data.Document [ Private ]
{
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = owner
	Set row.AddedBy = addedBy
	Set row.Name = name
	Set row.ContentType = contentType
	Set row.Size = size
	Set row.AddedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.State = state
	Set row.Reason = reason
	Set row.KnowledgeBase = table
	If text '= "" Do row.Text.Write(text)
	Set sc = row.%Save()
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Quit row
}

/// Saves the failed row of the command's document (no text, no passage) and publishes it.
Method Reject(request As OcuTalon.Msg.Command.AddDocument, size As %Integer, reason As %String, text As %String) As OcuTalon.Data.Document [ Private ]
{
	Quit ..Save(request, size, text, "failed", reason)
}

/// Ends the indexing of the document in failure: its rows leave the knowledge base, the state is failed with the reason failed, the row is published and one
/// redacted warning is logged. A document that is gone is left alone.
Method Fail(ref As %String, cause As %Status) [ Private ]
{
	$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(cause)))
	Try {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		If $IsObject(row) Do ##class(OcuTalon.Docs.Store).Remove(ref, $Select(row.KnowledgeBase '= "": row.KnowledgeBase, 1: ##class(OcuTalon.Docs.Store).#TABLE))
		If $IsObject(row) && (row.State = "indexing") {
			Set row.State = "failed"
			Set row.Reason = "failed"
			If $$$ISOK(row.%Save()) Do ..Publish(row, 0)
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
}

/// Publishes the row as a document event on its owner's stream (the instance stream for a local install, the session's own on the online demo); a failure is
/// one warning.
Method Publish(row As OcuTalon.Data.Document, removed As %Boolean) [ Private ]
{
	Set payload = ##class(OcuTalon.Live.Payload.Document).FromRow(row)
	Set payload.Removed = removed
	Do ..PublishPayload(payload, row.Ref, row.OwnerRef)
}

/// Publishes the payload on the stream of the owner (instance is the instance stream; a session's Ref is its own stream); a failure is one warning and changes
/// nothing else.
Method PublishPayload(payload As OcuTalon.Live.Payload.Document, ref As %String, owner As %String) [ Private ]
{
	Set stream = $Select(owner = ##class(OcuTalon.Docs.Store).#OWNER: ##class(OcuTalon.Live.Publish).#INSTANCE, 1: owner)
	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "document", payload, .seq)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGPUBLISH_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// Builds the failed answer of an unexpected failure in response (CommandsIn's own failure text, as the other owners answer), after one Type 3 warning that
/// holds the status text (redacted).
ClassMethod Failed(ByRef response As OcuTalon.Msg.CommandResult, cause As %Status) As %Status [ Private ]
{
	$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(cause)))
	Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
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
