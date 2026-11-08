Include Ensemble

/// DocumentOps (AD-1, AD-4, AD-5, AD-12, AD-21, AD-33; Lane A): the business operation that keeps the documents of a local install. An adapterless operation,
/// like MemoryOps. It alone writes OcuTalon.Data.Document and the rows of OcuTalonKB.Docs (through OcuTalon.Docs.Store), and it is the single publisher of the
/// document live event (OcuTalon.Live.Payload.Document, on the instance stream). It answers AddDocument and RemoveDocument synchronously with an
/// OcuTalon.Msg.CommandResult, and indexes asynchronously: a message to itself (OcuTalon.Docs.Msg.Index) indexes BATCH passages at a time, so the commands that
/// queue meanwhile are handled between the batches.
///   - AddDocument: an unknown session answers no_session (Ok 0) and nothing is taken. On the online demo (setting onlineDemo 1) it answers not_built (Ok 0), takes
///     nothing and writes no row (Story 19.5). Otherwise the upload is taken once with the command's SessionRef (Upload.Take); an upload that is gone (taken, dropped
///     or another session's, DW-747) writes a failed row (reason failed) and answers failed (Ok 0) with the row's Ref. The bytes of a markdown or text document must
///     be UTF-8 without a NUL and not blank once a BOM is stripped, else the row is failed with the reason unreadable; a pdf or docx document is failed with the
///     reason not_built (Story 19.7 sends them through Docs.Extract at the Text seam). Every failed row is published and the answer is added (Ok 1) with its Ref
///     and the message MESSAGENOTINDEXED. An unexpected failure answers failed (Ok 0) with CommandsIn's failure text and logs one redacted warning.
///     Otherwise the row is saved with the state indexing (OwnerRef the literal instance, AddedBy the command's session, the text, KnowledgeBase OcuTalonKB.Docs),
///     published, and Index(Ref, 0) is sent to this operation; the answer is added (Ok 1) with the Ref.
///   - Index: nothing when the row is gone or is not indexing. Otherwise the text is split (Docs.Passages); at ChunkFrom 0 the section of each passage is stored in the
///     row (Sections) and the document's old rows are removed; then the passages from ChunkFrom are embedded and written, and either Index(Ref, ChunkFrom + BATCH) is sent
///     or, when the last passage was written, the state becomes ready and the row is published. An error removes the document's rows, sets the state failed with
///     the reason failed, publishes the row and logs one redacted warning.
///   - RemoveDocument: an unknown session answers no_session. A Ref that no document of the instance has answers not_found (Ok 0). Otherwise the rows of the
///     document leave the knowledge base, then the row is deleted, a last event with removed true is published, and the answer is removed (Ok 1). The next search
///     returns none of its passages, and a later Index finds no row and stops.
/// A publish that fails is one redacted warning and never changes an answer. Publish runs outside any transaction. A document is shared by every user of the
/// install: the commands come from CommandsIn from web_user only (AD-1).
Class OcuTalon.Docs.Ops Extends Ens.BusinessOperation
{

/// The passages one Index message writes.
Parameter BATCH = 8;

/// The owner of every document of a local install (AD-4).
Parameter OWNER = "instance";

Parameter MESSAGEADDED = "The document was added and is being indexed.";

Parameter MESSAGEREMOVED = "The document was removed.";

Parameter MESSAGENOTFOUND = "The install has no such document, so nothing was removed.";

Parameter MESSAGENOSESSION = "The command names no session, so nothing was done.";

Parameter MESSAGENOTBUILT = "Documents are not built for the online demo yet, so nothing was done.";

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

/// Makes the knowledge-base table on a local install, so that the first search and the first batch find it. A failure is one warning: Store.Attach and
/// Store.Write make the table again.
Method OnInit() As %Status
{
	If ..OnlineDemo() Quit $$$OK
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
	If ..OnlineDemo() Quit ..Answer(.response, 0, "not_built", ..#MESSAGENOTBUILT)
	Set sc = $$$OK
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
	Quit sc
}

/// Indexes one batch of the document, or stops when the document is gone or no longer indexing (see the class description).
Method OnIndex(request As OcuTalon.Docs.Msg.Index, Output response As Ens.Response) As %Status
{
	Set response = ""
	Set ref = request.Ref
	Try {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		If '$IsObject(row) || (row.State '= "indexing") Quit
		Do row.Text.Rewind()
		Set text = row.Text.Read($$$MaxLocalLength)
		Set name = ##class(OcuTalon.Docs.Store).DocumentName(row.Name)
		Set sc = ##class(OcuTalon.Docs.Passages).Split(text, row.ContentType, .passages)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		Set next = +request.ChunkFrom
		If next = 0 {
			Set sections = []
			Set i = 0
			While i < passages.%Size() {
				Do sections.%Push(passages.%Get(i).section)
				Set i = i + 1
			}
			Set row.Sections = sections.%ToJSON()
			Set sc = row.%Save()
			If $$$ISERR(sc) $$$ThrowStatus(sc)
			Set sc = ##class(OcuTalon.Docs.Store).Remove(ref)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		}
		Set sc = ##class(OcuTalon.Docs.Store).Write(ref, name, passages, next, ..#BATCH)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		If (next + ..#BATCH) < passages.%Size() {
			Set index = ##class(OcuTalon.Docs.Msg.Index).%New()
			Set index.Ref = ref
			Set index.ChunkFrom = next + ..#BATCH
			Set sc = ..SendRequestAsync(..%ConfigName, index)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		} Else {
			Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
			If $IsObject(row) && (row.State = "indexing") {
				Set row.State = "ready"
				Set sc = row.%Save()
				If $$$ISERR(sc) $$$ThrowStatus(sc)
				Do ..Publish(row, 0)
			} Else {
				Do ##class(OcuTalon.Docs.Store).Remove(ref)
			}
		}
	} Catch exception {
		Do ..Fail(ref, exception.AsStatus())
	}
	Quit $$$OK
}

/// Removes the command's document, or answers that there is none (see the class description).
Method OnRemove(request As OcuTalon.Msg.Command.RemoveDocument, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set sc = $$$OK
	Try {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(request.DocumentRef)
		If '$IsObject(row) || (row.OwnerRef '= ..#OWNER) {
			Set sc = ..Answer(.response, 0, "not_found", ..#MESSAGENOTFOUND)
		} Else {
			Set payload = ##class(OcuTalon.Live.Payload.Document).FromRow(row)
			Set payload.Removed = 1
			Set id = row.%Id()
			Set ref = row.Ref
			Set row = ""
			Set sc = ##class(OcuTalon.Docs.Store).Remove(ref)
			If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.Document).%DeleteId(id)
			If $$$ISOK(sc) {
				Do ..PublishPayload(payload, ref)
				Set sc = ..Answer(.response, 1, "removed", ..#MESSAGEREMOVED)
			} Else {
				Set sc = ..Failed(.response, sc)
			}
		}
	} Catch exception {
		Set sc = ..Failed(.response, exception.AsStatus())
	}
	Quit sc
}

/// The text of the bytes of a document of the content type, in text, or the reason in reason: markdown and text are UTF-8 (a BOM is dropped) with no NUL and
/// something that is not blank, else unreadable; pdf and docx are not built until Story 19.7 (not_built). Never throws; a text that is too long to hold is
/// failed.
Method Text(bytes As %Stream.Object, contentType As %String, Output text As %String, Output reason As %String) As %Boolean
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

/// 1 when the instance is the online demo.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1
}

/// Saves the row of the command's document with the state, and publishes it.
Method Save(request As OcuTalon.Msg.Command.AddDocument, size As %Integer, text As %String, state As %String, reason As %String) As OcuTalon.Data.Document [ Private ]
{
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = ..#OWNER
	Set row.AddedBy = request.SessionRef
	Set row.Name = request.Name
	Set row.ContentType = request.ContentType
	Set row.Size = size
	Set row.AddedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.State = state
	Set row.Reason = reason
	Set row.KnowledgeBase = ##class(OcuTalon.Docs.Store).#TABLE
	If text '= "" Do row.Text.Write(text)
	Set sc = row.%Save()
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Do ..Publish(row, 0)
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
		Do ##class(OcuTalon.Docs.Store).Remove(ref)
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		If $IsObject(row) && (row.State = "indexing") {
			Set row.State = "failed"
			Set row.Reason = "failed"
			If $$$ISOK(row.%Save()) Do ..Publish(row, 0)
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
}

/// Publishes the row as a document event on the instance stream; a failure is one warning.
Method Publish(row As OcuTalon.Data.Document, removed As %Boolean) [ Private ]
{
	Set payload = ##class(OcuTalon.Live.Payload.Document).FromRow(row)
	Set payload.Removed = removed
	Do ..PublishPayload(payload, row.Ref)
}

/// Publishes the payload on the instance stream; a failure is one warning and changes nothing else.
Method PublishPayload(payload As OcuTalon.Live.Payload.Document, ref As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Live.Publish).Publish(##class(OcuTalon.Live.Publish).#INSTANCE, "document", payload, .seq)
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
