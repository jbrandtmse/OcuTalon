/// A test double of OcuTalon.Eval.In (Test.Eval.In, Test.Eval.Cases): its sends are replaced, and none of them sends a message.
///   - Dispatch (an item case) records each Item it is given, with the SuperSession of the service, whether the case's row was open at that
///     moment and the number of watch rows of owner eval at that moment, under ^OcuTalonTest("EvalIn", "seen", n), and answers the error status that ^OcuTalonTest("EvalIn", "fail") holds, or OK when
///     that is empty; it throws an exception with the text that ^OcuTalonTest("EvalIn", "throw") holds when that is not empty.
///   - DispatchIncident (an incident case) records each IncidentCase it is given under ^OcuTalonTest("EvalIn", "incident", n) as a list: IncidentRef,
///     SourceItemId, the format of the snapshot text, the number of failures in it, 1 when the case's row was open at that moment (found by the IncidentRef),
///     the SuperSession of the service, and (position 7) the number of IncidentCases recorded before this one whose rows are still sent at that moment. It answers
///     and throws as Dispatch does, by the same "fail" and "throw" records.
///   - StillSent (EvalIn's check of the previous incident case's row) counts each check under ^OcuTalonTest("EvalIn", "checked") and ("checked", itemId), and
///     calls Answer first when the count of that ItemId equals ^OcuTalonTest("EvalIn", "late") (1 when it is undefined, so the previous row is answered at the
///     first check; "never" never matches). It then answers what EvalIn's own StillSent answers.
///   - Answer completes the sent row of an ItemId as Eval.Sink does (state decided, DecidedAt now); no row is OK.
///   - DispatchDigest (a digest case) records each DigestCase it is given under ^OcuTalonTest("EvalIn", "digest", n) as a list: ItemId, SourceItemId,
///     RecordedChecks, RecordedVitals, RecordedSaved, 1 when the case's row was open at that moment and the SuperSession of the service. It answers and
///     throws as Dispatch does, by the same "fail" and "throw" records.
///   - Ask (a turn case's call to Decide) records each request under ^OcuTalonTest("EvalIn", "asked", n) as a list: Kind, Provenance, OwnerRef,
///     ItemId, Input, Summary, TraceRef, Channel, ThreadSessionId, SessionMode, SeedText, SystemNote, 1 when the case's TurnResult exists,
///     its RecordedChecks, 1 when the case's row was open, and the SuperSession of the service. It answers what
///     ^OcuTalonTest("EvalIn", "reply", n) holds for its nth call: busy (a Busy Reply), error (an error status), throw (an exception), none (OK
///     and no response), nonreply (a response that is not a Reply), or the JSON of the fields of a Reply (Text, DecisionRef, ToolsRun, HostData,
///     Fallback, FallbackReason); with no script it answers a Reply with no text. A decide request (a user-turn case) is answered with a
///     DecisionResponse instead, whose fields the script sets in the same way (DecisionRef, Outcome, Reasons, Fallback, FallbackReason).
///   - Deliver (the TurnResult to EvalSink) records the fields of the TurnResult under ^OcuTalonTest("EvalIn", "delivered", n) as a list: ItemId,
///     SourceItemId, RecordedChecks, DecisionRef, ToolsRun, ReplyText, CatalogKey, CheckRows, Fallback, FallbackReason and the SuperSession of the
///     service. It answers the error status that ^OcuTalonTest("EvalIn", "deliverFail") holds, or OK when that is empty.
///   - DocumentsUp (a documents case's documents, Story 19.4) records the case's documents under ^OcuTalonTest("EvalIn", "documents", n) as a list: the names
///     of the documents and their files, comma-separated, and adds nothing; it answers the reason that ^OcuTalonTest("EvalIn", "documentsFail") holds, or ""
///     when that is empty, with a setup record of made-up refs for Finish.
///   - Seed (a case's SeedPrecedent, Story 41.7) records each message under ^OcuTalonTest("EvalIn", "seed", n) as a list: RunRef, Channel, MatchKey, Summary,
///     Outcome, Answer, AnsweredAt, 1 when the newest row of the run was open and marked (Precedents 1), and 1 when the Item of that row had already been
///     dispatched. It answers a CommandResult seeded with a made-up Ref, a CommandResult failed for its nth call when ^OcuTalonTest("EvalIn", "seedFail") holds n,
///     and an error status for its nth call when ^OcuTalonTest("EvalIn", "seedError") holds n.
///   - Unseed (Finish's removal of a run's seeded precedents) records each run under ^OcuTalonTest("EvalIn", "unseed", n) and sends nothing; it answers the
///     error status that ^OcuTalonTest("EvalIn", "unseedFail") holds, or OK when that is empty.
///   - RemoveRun (the removal of one run's seeded precedents, which Unseed and the start-of-run sweep share) records each run under ^OcuTalonTest("EvalIn", "remove", n)
///     and sends nothing; it answers OK for a run that ^OcuTalonTest("EvalIn", "removeOk", run) names and an error status for every other.
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
	Set sent = 0
	For n = 1:1:+$Get(^OcuTalonTest("EvalIn", "incident")) {
		If $IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending($ListGet($Get(^OcuTalonTest("EvalIn", "incident", n)), 1))) Set sent = sent + 1
	}
	Set ^OcuTalonTest("EvalIn", "incident", $Increment(^OcuTalonTest("EvalIn", "incident"))) = $ListBuild(incident.IncidentRef, incident.SourceItemId, snapshot.format, snapshot.failures.%Size(), open, ..%SuperSession, sent)
	Set throw = $Get(^OcuTalonTest("EvalIn", "throw"))
	If throw '= "" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, throw))
	Set fail = $Get(^OcuTalonTest("EvalIn", "fail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

Method DispatchDigest(digest As OcuTalon.Eval.Msg.DigestCase) As %Status [ Private ]
{
	Set open = ''$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(digest.ItemId))
	Set ^OcuTalonTest("EvalIn", "digest", $Increment(^OcuTalonTest("EvalIn", "digest"))) = $ListBuild(digest.ItemId, digest.SourceItemId, digest.RecordedChecks, digest.RecordedVitals, digest.RecordedSaved, open, ..%SuperSession)
	Set throw = $Get(^OcuTalonTest("EvalIn", "throw"))
	If throw '= "" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, throw))
	Set fail = $Get(^OcuTalonTest("EvalIn", "fail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

/// Completes the sent row of the ItemId as Eval.Sink does; OK when there is none.
ClassMethod Answer(itemId As %String) As %Status
{
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).Pending(itemId)
	If '$IsObject(row) Quit $$$OK
	Set row.State = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED
	Set row.DecidedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Quit row.%Save()
}

Method StillSent(itemId As %String) As %Boolean [ Private ]
{
	Do $Increment(^OcuTalonTest("EvalIn", "checked"))
	Set count = $Increment(^OcuTalonTest("EvalIn", "checked", itemId))
	If count = $Get(^OcuTalonTest("EvalIn", "late"), 1) Do ..Answer(itemId)
	Quit ##super(itemId)
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
	If request.Kind = "decide" {
		Set reply = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
		If script '= "" {
			Set fields = ##class(%DynamicAbstractObject).%FromJSON(script)
			Set iterator = fields.%GetIterator()
			While iterator.%GetNext(.key, .value) {
				Set $Property(reply, key) = value
			}
		}
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

Method DocumentsUp(case As %DynamicObject, folder As %String, Output documents As %DynamicObject) As %String
{
	Set documents = ""
	Set names = "", files = ""
	Set iterator = case.%Get("documents").%GetIterator()
	While iterator.%GetNext(, .one) {
		Set names = names _ $Select(names '= "": ",", 1: "") _ one.name
		Set files = files _ $Select(files '= "": ",", 1: "") _ one.file
	}
	Set ^OcuTalonTest("EvalIn", "documents", $Increment(^OcuTalonTest("EvalIn", "documents"))) = $ListBuild(names, files)
	Set fail = $Get(^OcuTalonTest("EvalIn", "documentsFail"))
	If fail '= "" Quit fail
	Set documents = {"refs": ["zzEvalDocRef0000000001"]}
	Quit ""
}

Method Seed(message As OcuTalon.Core.Msg.SeedPrecedent, Output result As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("EvalIn", "seed"))
	Set open = 0, dispatched = 0
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ItemId, Precedents FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ? ORDER BY ID DESC", ..RunRef)
	If rows.%Next() {
		Set open = (+rows.%Get("Precedents") = 1)
		For i = 1:1:+$Get(^OcuTalonTest("EvalIn", "seen")) {
			If $ListGet($Get(^OcuTalonTest("EvalIn", "seen", i)), 1) = rows.%Get("ItemId") Set dispatched = 1
		}
	}
	Set ^OcuTalonTest("EvalIn", "seed", n) = $ListBuild(message.RunRef, message.Channel, message.MatchKey, message.Summary, message.Outcome, message.Answer, message.AnsweredAt, open, dispatched)
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	If $Get(^OcuTalonTest("EvalIn", "seedError")) = n Quit $SYSTEM.Status.Error(5001, "PrecedentOps could not be reached")
	If $Get(^OcuTalonTest("EvalIn", "seedFail")) = n {
		Set result.Ok = 0, result.Outcome = "failed"
	} Else {
		Set result.Ok = 1, result.Outcome = "seeded", result.Ref = $Extract("zzSeed"_$Translate($Justify(n, 16), " ", "0"), 1, 22)
	}
	Quit $$$OK
}

ClassMethod Unseed(runRef As %String) As %Status
{
	Set ^OcuTalonTest("EvalIn", "unseed", $Increment(^OcuTalonTest("EvalIn", "unseed"))) = runRef
	Set fail = $Get(^OcuTalonTest("EvalIn", "unseedFail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

Method RemoveRun(runRef As %String) As %Status
{
	Set ^OcuTalonTest("EvalIn", "remove", $Increment(^OcuTalonTest("EvalIn", "remove"))) = runRef
	Quit $Select($Data(^OcuTalonTest("EvalIn", "removeOk", runRef)): $$$OK, 1: $SYSTEM.Status.Error(5001, "the removal of the run "_runRef_" failed"))
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
