/// The citations of a turn (AD-10, AD-31, Story 19.4; Conventions "Citations and memories"): code builds HostData.citations from the results of the turn's
/// searches of the documents, never from model text. The step audit policy (Policy.StepAudit) calls Collect for every executed tool call, and Collect does
/// nothing unless the call is the knowledge-base call that the gate recognises (Policy.Gate RagCall: name documents, no origin_class, no mcp: toolref).
///   - The result text that the audit policy receives (Task 0, measured) is the array [{"id", "score", "text", "metadata": {"source", "chunk_index", "document",
///     "section"}}]; the object {"timing", "value": [...]} that a direct ExecuteTool returns is read alike. The characters of
///     the result text are added to the context's ToolResultChars, because a knowledge-base result never passes Tools.Result (NFR-3: the results of one model
///     step share one room, and the gate's next search reads it).
///   - Each item whose score is at or above CITEFLOOR is added to HostData.citations as {documentRef, document, section, passage, chunkIndex}, with
///     documentRef the metadata's source and passage the item's text. An item is added once: the pair (documentRef, chunkIndex) is distinct across all the
///     searches of the turn. The entries are in the order of the results, and there are at most MAXCITATIONS; the member is absent when nothing qualifies.
///   - A result that is not JSON of that shape adds nothing, and its characters are still counted.
/// CITEFLOOR is the measured score floor (Story 19.4, Task 0, M4; evidence/19-4-task0-documents.md): with the Results runbook and the embedding worker, the
/// best passage of an unrelated question scored at most 0.1132 and the best passage of a question the document answers scored at least 0.5671 (0.6892 or more
/// for the three wordings of the rotation question), so the floor is 0.4, about midway. It makes no AI Hub call, runs no Python and names no host package
/// (it runs inside AI Hub's callback, AD-6).
Class OcuTalon.Bridge.Citations
{

/// The lowest score of a passage that is cited.
Parameter CITEFLOOR = 0.4;

/// The most citations of a reply.
Parameter MAXCITATIONS = 5;

/// The HostData member that holds the citations.
Parameter MEMBER = "citations";

/// Handles the executed call and its result; returns OK always (the audit policy ignores the status).
ClassMethod Collect(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject) As %Status
{
	Try {
		If '$IsObject(call) || '##class(OcuTalon.Bridge.Policy.Gate).RagCall(call.%Get("name"), metadata) Quit
		If '##class(OcuTalon.Bridge.Context).Active() Quit
		Set json = $Select($IsObject(result) && (result.%GetTypeOf("result_json") = "string"): result.%Get("result_json"), 1: "")
		Set context = ##class(OcuTalon.Bridge.Context).Current()
		Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", +context.ToolResultChars + $Length(json))
		Do ..Add(json)
	} Catch exception {
	}
	Quit $$$OK
}

/// Adds the items of the result text that clear the floor to HostData.citations.
ClassMethod Add(json As %String) [ Private ]
{
	If json = "" Quit
	Try {
		Set parsed = {}.%FromJSON(json)
	} Catch {
		Quit
	}
	If '$IsObject(parsed) Quit
	If parsed.%IsA("%Library.DynamicArray") {
		Set items = parsed
	} ElseIf parsed.%GetTypeOf("value") = "array" {
		Set items = parsed.value
	} Else {
		Quit
	}
	Set existing = ##class(OcuTalon.Bridge.HostData).Get(..#MEMBER)
	Set citations = $Select($IsObject(existing) && (existing.%IsA("%Library.DynamicArray")): existing, 1: [])
	Set changed = 0
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(.key, .item) {
		If citations.%Size() '< ..#MAXCITATIONS Quit
		If '$IsObject(item) || (item.%GetTypeOf("score") '= "number") || (item.score < ..#CITEFLOOR) Continue
		Set meta = item.metadata
		If '$IsObject(meta) || (meta.%GetTypeOf("source") '= "string") Continue
		Set chunk = meta.%Get("chunk_index")
		If ..Has(citations, meta.source, chunk) Continue
		Do citations.%Push({"documentRef": (meta.source), "document": (meta.%Get("document")), "section": (meta.%Get("section")), "passage": (item.%Get("text")), "chunkIndex": (chunk)})
		Set changed = 1
	}
	If changed Do ##class(OcuTalon.Bridge.HostData).Put(..#MEMBER, citations)
}

/// 1 when the citations already hold the passage (documentRef, chunkIndex).
ClassMethod Has(citations As %DynamicArray, ref As %String, chunk As %String) As %Boolean [ Private ]
{
	Set iterator = citations.%GetIterator()
	While iterator.%GetNext(.key, .entry) {
		If (entry.documentRef = ref) && (entry.chunkIndex = chunk) Quit
		Set entry = ""
	}
	Quit $IsObject($Get(entry))
}

}
