/// A test double of OcuTalon.Eval.In (Test.Eval.In, Test.Eval.Cases): its sends are replaced, and none of them sends a message.
///   - Dispatch (an item case) records each Item it is given, with the SuperSession of the service, whether the case's row was open at that
///     moment and the number of watch rows of owner eval at that moment, under ^OcuTalonTest("EvalIn", "seen", n), and answers the error status that ^OcuTalonTest("EvalIn", "fail") holds, or OK when
///     that is empty; it throws an exception with the text that ^OcuTalonTest("EvalIn", "throw") holds when that is not empty.
///   - DispatchIncident (an incident case) records each IncidentCase it is given under ^OcuTalonTest("EvalIn", "incident", n) as a list: IncidentRef,
///     SourceItemId, the format of the snapshot text, the number of failures in it, 1 when the case's row was open at that moment (found by the IncidentRef)
///     and the SuperSession of the service. It answers and throws as Dispatch does, by the same "fail" and "throw" records.
///   - Ask (a turn case's call to Decide) records each request under ^OcuTalonTest("EvalIn", "asked", n) as a list: Kind, Provenance, OwnerRef,
///     ItemId, Input, Summary, TraceRef, Channel, ThreadSessionId, SessionMode, SeedText, SystemNote, 1 when the case's TurnResult exists,
///     its RecordedChecks, 1 when the case's row was open, and the SuperSession of the service. It answers what
///     ^OcuTalonTest("EvalIn", "reply", n) holds for its nth call: busy (a Busy Reply), error (an error status), throw (an exception), none (OK
///     and no response), nonreply (a response that is not a Reply), or the JSON of the fields of a Reply (Text, DecisionRef, ToolsRun, HostData,
///     Fallback, FallbackReason); with no script it answers a Reply with no text.
///   - Deliver (the TurnResult to EvalSink) records the fields of the TurnResult under ^OcuTalonTest("EvalIn", "delivered", n) as a list: ItemId,
///     SourceItemId, RecordedChecks, DecisionRef, ToolsRun, ReplyText, CatalogKey, CheckRows, Fallback, FallbackReason and the SuperSession of the
///     service. It answers the error status that ^OcuTalonTest("EvalIn", "deliverFail") holds, or OK when that is empty.
///   - Pause (the wait before a Busy turn is asked again) records the seconds under ^OcuTalonTest("EvalIn", "paused", n) and waits for none.
/// DeleteBodies deletes the TurnResult bodies of the ItemIds that Ask and Deliver recorded: EvalIn saves a TurnResult before it asks, and the
/// double's Deliver sends nothing, so no purge would ever remove it. The tests call it before they clear the records.
Class OcuTalon.Test.Eval.ZzIn Extends OcuTalon.Eval.In
{

Method Dispatch(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set open = ''$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(item.ItemId))
	Set watches = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", ##class(OcuTalon.Data.Ownership).#EVAL)
	If result.%Next() Set watches = +result.%GetData(1)
	Set ^OcuTalonTest("EvalIn", "seen", $Increment(^OcuTalonTest("EvalIn", "seen"))) = $ListBuild(item.ItemId, item.SourceItemId, item.SessionRef, item.Channel, item.Provenance, item.Sender, item.Subject, item.Text, item.CatalogKey, item.Slots, ..%SuperSession, open, watches)
	Set throw = $Get(^OcuTalonTest("EvalIn", "throw"))
	If throw '= "" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, throw))
	Set fail = $Get(^OcuTalonTest("EvalIn", "fail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

Method DispatchIncident(incident As OcuTalon.Eval.Msg.IncidentCase) As %Status [ Private ]
{
	Set open = ''$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(incident.IncidentRef))
	Set snapshot = ##class(%DynamicAbstractObject).%FromJSON(incident.Snapshot)
	Set ^OcuTalonTest("EvalIn", "incident", $Increment(^OcuTalonTest("EvalIn", "incident"))) = $ListBuild(incident.IncidentRef, incident.SourceItemId, snapshot.format, snapshot.failures.%Size(), open, ..%SuperSession)
	Set throw = $Get(^OcuTalonTest("EvalIn", "throw"))
	If throw '= "" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, throw))
	Set fail = $Get(^OcuTalonTest("EvalIn", "fail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

Method Ask(request As OcuTalon.Bridge.Msg.Request, Output reply As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("EvalIn", "asked"))
	Set recorded = "", exists = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT RecordedChecks FROM OcuTalon_Eval_Msg.TurnResult WHERE ItemId = ? ORDER BY ID DESC", request.ItemId)
	If result.%Next() Set exists = 1, recorded = result.%Get("RecordedChecks")
	Set open = ''$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(request.ItemId))
	Set ^OcuTalonTest("EvalIn", "asked", n) = $ListBuild(request.Kind, request.Provenance, request.OwnerRef, request.ItemId, request.Input, request.Summary, request.TraceRef, request.Channel, request.ThreadSessionId, request.SessionMode, request.SeedText, request.SystemNote, exists, recorded, open, ..%SuperSession)
	Set script = $Get(^OcuTalonTest("EvalIn", "reply", n))
	Set reply = ""
	If script = "error" Quit $SYSTEM.Status.Error(5001, "the call to Decide failed")
	If script = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "the call to Decide threw"))
	If script = "none" Quit $$$OK
	If script = "nonreply" {
		Set reply = ##class(Ens.StringContainer).%New("this is not a Reply")
		Quit $$$OK
	}
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	If script = "busy" {
		Set reply.Busy = 1
	} ElseIf script '= "" {
		Set fields = ##class(%DynamicAbstractObject).%FromJSON(script)
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Set $Property(reply, key) = value
		}
	}
	Quit $$$OK
}

Method Deliver(result As OcuTalon.Eval.Msg.TurnResult) As %Status [ Private ]
{
	Set ^OcuTalonTest("EvalIn", "delivered", $Increment(^OcuTalonTest("EvalIn", "delivered"))) = $ListBuild(result.ItemId, result.SourceItemId, result.RecordedChecks, result.DecisionRef, result.ToolsRun, result.ReplyText, result.CatalogKey, result.CheckRows, result.Fallback, result.FallbackReason, ..%SuperSession)
	Set fail = $Get(^OcuTalonTest("EvalIn", "deliverFail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

Method Pause(seconds As %Integer) [ Private ]
{
	Set ^OcuTalonTest("EvalIn", "paused", $Increment(^OcuTalonTest("EvalIn", "paused"))) = seconds
}

/// Deletes the TurnResult bodies of the ItemIds that Ask and Deliver recorded.
ClassMethod DeleteBodies()
{
	Kill ids
	For key = "asked", "delivered" {
		For n = 1:1:+$Get(^OcuTalonTest("EvalIn", key)) {
			Set itemId = $ListGet($Get(^OcuTalonTest("EvalIn", key, n)), $Select(key = "asked": 4, 1: 1))
			If itemId '= "" Set ids(itemId) = ""
		}
	}
	Set itemId = ""
	For {
		Set itemId = $Order(ids(itemId))
		If itemId = "" Quit
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Eval_Msg.TurnResult WHERE ItemId = ?", itemId)
		Kill bodies
		While result.%Next() {
			Set bodies(result.%Get("ID")) = ""
		}
		Set id = ""
		For {
			Set id = $Order(bodies(id))
			If id = "" Quit
			Do ##class(OcuTalon.Eval.Msg.TurnResult).%DeleteId(id)
		}
	}
}

}
