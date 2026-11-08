Include Ensemble

/// PrecedentOps, the business operation that is the only writer of a person's precedents (Data.Precedent; AD-1, AD-21 as amended 2026-11-08, AD-22; FR-72;
/// Story 41.2). It accepts six messages, each from one named sender, and answers each with a CommandResult. A message from any other sender, and a verb
/// whose Origin is not web_user, is refused with the outcome not_allowed and one warning, and writes nothing. Its messages are for the logs and are
/// never shown; the web routes and the channels have their own words.
///   - MarkNoise {DecisionRef, Channel}, from CommandsIn with Origin web_user. The Decision must be the session's own (Data.Ownership.Decision), of Kind
///     decide, with the Outcome tellnow or act. Its Item is found in the messages of the Decision's trace session by ItemId; an Item that is gone is
///     too_old. An Item of provenance user, and one that KeyFor gives no key, is not_found. One row is saved with the Answer noise: the outcomes are
///     marked (Ok 1, the row's Ref, Data {"answeredAt"}), already_marked (Ok 1, the first row's Ref and answeredAt; the first press wins through the
///     unique SourceRef), not_found, too_old and failed.
///   - ForgetPrecedent {PrecedentRef}, from CommandsIn with Origin web_user. The row must be the session's own and not a seeded one
///     (Data.Ownership.Precedent): forgotten (Ok 1, the row is deleted) or not_found.
///   - RecordPrecedent {ApprovalRef, Action, Channel, SessionRef}, from AnswerOps. The request must be visible to the session (Data.Ownership.Approval),
///     the Action approve or reject, and the request a fix or a tool_call: recorded (Ok 1, one row with the Answer approved or rejected),
///     already_recorded (Ok 1, nothing changed) or not_recorded (Ok 0: a setting request, a bad Action, an unknown request or session).
///   - EndSession {SessionRef}, from SessionOps: the session's rows are deleted (ended). Seeded rows stay.
///   - SeedPrecedent and RemoveSeededPrecedents, from EvalIn, and only while EvalOn() is 1 (the EvalIn item's Enabled System Default Setting, which the
///     production install step writes from OCUTALON_EVAL at every start). A seeded row has the owner eval, EvalRunRef set to the run and its own Ref as
///     SourceRef: seeded (Ok 1, the row's Ref), not_valid (a message that holds an empty RunRef or MatchKey, or a bad Answer, Channel, Outcome or time) and
///     removed (Ok 1, Data {"count"}: the rows of that run only).
/// A throw is logged and answers failed. The pool of the item is 1, so its messages are handled one at a time.
Class OcuTalon.Core.PrecedentOps Extends Ens.BusinessOperation
{

/// The only item that may send MarkNoise and ForgetPrecedent.
Parameter COMMANDSENDER = "CommandsIn";

/// The only item that may send RecordPrecedent.
Parameter ANSWERSENDER = "AnswerOps";

/// The only item that may send EndSession.
Parameter SESSIONSENDER = "SessionOps";

/// The only item that may send SeedPrecedent and RemoveSeededPrecedents, and only while EvalOn() is 1.
Parameter EVALSENDER = "EvalIn";

/// The Message of each outcome. The messages are for the logs and are never shown as written.
Parameter MESSAGEMARKED = "The notice is marked as noise.";

Parameter MESSAGEALREADYMARKED = "The notice was already marked as noise, so nothing was changed.";

Parameter MESSAGENOTFOUND = "That is not a notice that can be marked as noise, so nothing was written.";

Parameter MESSAGETOOOLD = "The notice's item is no longer kept, so nothing was written.";

Parameter MESSAGEFORGOTTEN = "The answer is forgotten.";

Parameter MESSAGEFORGETNOTFOUND = "That answer is not known, so nothing was forgotten.";

Parameter MESSAGERECORDED = "The answer is recorded as a precedent.";

Parameter MESSAGEALREADYRECORDED = "The answer was already recorded, so nothing was changed.";

Parameter MESSAGENOTRECORDED = "That answer is not recorded as a precedent.";

Parameter MESSAGEENDED = "The session's precedents are deleted.";

Parameter MESSAGESEEDED = "The precedent is seeded.";

Parameter MESSAGEREMOVED = "The seeded precedents are removed.";

Parameter MESSAGENOTVALID = "That precedent is not valid, so nothing was written.";

Parameter MESSAGENOTALLOWED = "PrecedentOps does not take that message from there, so nothing was changed.";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Set message = $Get(pRequest)
	Set class = $Select($IsObject(message): $ClassName(message), 1: "")
	If '$ListFind($ListBuild("OcuTalon.Msg.Command.MarkNoise", "OcuTalon.Msg.Command.ForgetPrecedent", "OcuTalon.Core.Msg.RecordPrecedent", "OcuTalon.Msg.Command.EndSession", "OcuTalon.Core.Msg.SeedPrecedent", "OcuTalon.Core.Msg.RemoveSeededPrecedents"), class) {
		$$$LOGERROR("OcuTalon.Core.PrecedentOps: it carries out no " _ $Select(class = "": "message that is not an object", 1: class))
		Quit $SYSTEM.Status.Error(5001, "PrecedentOps carries out only MarkNoise, ForgetPrecedent, RecordPrecedent, EndSession, SeedPrecedent and RemoveSeededPrecedents")
	}
	Try {
		Set pResponse = $Case(class,
			"OcuTalon.Msg.Command.MarkNoise": ..Mark(message),
			"OcuTalon.Msg.Command.ForgetPrecedent": ..Forget(message),
			"OcuTalon.Core.Msg.RecordPrecedent": ..Record(message),
			"OcuTalon.Msg.Command.EndSession": ..End(message),
			"OcuTalon.Core.Msg.SeedPrecedent": ..Seed(message),
			: ..Remove(message))
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set pResponse = ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// 1 only when the Enabled System Default Setting of the EvalIn item, as the running item resolves it (Ens.Config.DefaultSettings.%GetSetting, the most
/// specific matching row), holds 1. The install step writes the row (OcuTalon.Production, EvalIn, *, Enabled) at every start from OCUTALON_EVAL (AD-22);
/// no matching row means off.
ClassMethod EvalOn() As %Boolean
{
	Set value = ""
	If '##class(Ens.Config.DefaultSettings).%GetSetting(##class(OcuTalon.Install.Step.Production).#PRODUCTION, ##class(OcuTalon.Install.Step.Production).#EVALITEM, "OcuTalon.Eval.In", "", "Enabled", .value) Quit 0
	Quit (value = 1)
}

/// Carries out a MarkNoise (see the class description).
Method Mark(command As OcuTalon.Msg.Command.MarkNoise) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..FromVerb(command) Quit ..Refuse(command)
	Set ref = command.DecisionRef, sessionRef = command.SessionRef
	If (sessionRef = "") || '##class(OcuTalon.Bridge.Approval).IsRef(ref) Quit ..Result(0, "not_found", ..#MESSAGENOTFOUND)
	Set decision = ##class(OcuTalon.Data.Ownership).Decision(ref, sessionRef, .sc)
	If $$$ISERR(sc) Quit ..Failed("the decision could not be read", sc)
	If '$IsObject(decision) || (decision.Ref '= ref) || (decision.Kind '= "decide") || '$ListFind($ListBuild("tellnow", "act"), decision.Outcome) Quit ..Result(0, "not_found", ..#MESSAGENOTFOUND)
	Set known = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(ref)
	If $IsObject(known) && (known.SourceRef = ref) Quit ..Marked("already_marked", ..#MESSAGEALREADYMARKED, known)
	Set item = ..ItemOf(decision)
	If '$IsObject(item) Quit ..Result(0, "too_old", ..#MESSAGETOOOLD)
	Set key = ##class(OcuTalon.Data.Precedent).KeyFor(item)
	If key = "" Quit ..Result(0, "not_found", ..#MESSAGENOTFOUND)
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = sessionRef
	Set row.Channel = item.Channel
	Set row.MatchKey = key
	Set row.Summary = decision.Summary
	Set row.Outcome = decision.Outcome
	Set row.Answer = "noise"
	Set row.AnsweredAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.AnsweredChannel = ..ChannelOf(command.Channel)
	Set row.SourceRef = ref
	Set sc = ..SaveRow(row)
	If $$$ISERR(sc) {
		Set known = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(ref)
		If $IsObject(known) && (known.SourceRef = ref) Quit ..Marked("already_marked", ..#MESSAGEALREADYMARKED, known)
		Quit ..Failed("the precedent could not be saved", sc)
	}
	Quit ..Marked("marked", ..#MESSAGEMARKED, row)
}

/// Carries out a ForgetPrecedent (see the class description).
Method Forget(command As OcuTalon.Msg.Command.ForgetPrecedent) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..FromVerb(command) Quit ..Refuse(command)
	Set ref = command.PrecedentRef, sessionRef = command.SessionRef
	If (sessionRef = "") || (ref = "") Quit ..Result(0, "not_found", ..#MESSAGEFORGETNOTFOUND)
	Set row = ##class(OcuTalon.Data.Ownership).Precedent(ref, sessionRef, .sc)
	If $$$ISERR(sc) Quit ..Failed("the precedent could not be read", sc)
	If '$IsObject(row) || (row.Ref '= ref) Quit ..Result(0, "not_found", ..#MESSAGEFORGETNOTFOUND)
	Set id = row.%Id()
	Set row = ""
	Set sc = ##class(OcuTalon.Data.Precedent).%DeleteId(id)
	If $$$ISERR(sc) && '$SYSTEM.Status.Equals(sc, ##class(OcuTalon.Data.Precedent).#NOTFOUND) Quit ..Failed("the precedent could not be deleted", sc)
	Quit ..Result(1, "forgotten", ..#MESSAGEFORGOTTEN)
}

/// Carries out a RecordPrecedent (see the class description).
Method Record(request As OcuTalon.Core.Msg.RecordPrecedent) As OcuTalon.Msg.CommandResult [ Private ]
{
	If ..Source() '= ..#ANSWERSENDER Quit ..Refuse(request)
	Set answer = $Case(request.Action, "approve": "approved", "reject": "rejected", : "")
	Set ref = request.ApprovalRef, sessionRef = request.SessionRef
	If (answer = "") || (sessionRef = "") || '##class(OcuTalon.Bridge.Approval).IsRef(ref) Quit ..Result(0, "not_recorded", ..#MESSAGENOTRECORDED)
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)) Quit ..Result(0, "not_recorded", ..#MESSAGENOTRECORDED)
	Set approval = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
	If $$$ISERR(sc) Quit ..Failed("the approval request could not be read", sc)
	If '$IsObject(approval) || (approval.Ref '= ref) Quit ..Result(0, "not_recorded", ..#MESSAGENOTRECORDED)
	If ##class(OcuTalon.Data.Precedent).SourceRefIndexExists(ref) Quit ..Result(1, "already_recorded", ..#MESSAGEALREADYRECORDED)
	Set key = ##class(OcuTalon.Data.Precedent).KeyForRequest(approval, .channel, .summary)
	If key = "" Quit ..Result(0, "not_recorded", ..#MESSAGENOTRECORDED)
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = sessionRef
	Set row.Channel = channel
	Set row.MatchKey = key
	Set row.Summary = summary
	Set row.Outcome = ""
	Set row.Answer = answer
	Set row.AnsweredAt = $Select(approval.AnsweredAt '= "": approval.AnsweredAt, 1: ##class(OcuTalon.Data.Time).NowUtc())
	Set row.AnsweredChannel = ..ChannelOf(request.Channel)
	Set row.SourceRef = ref
	Set sc = ..SaveRow(row)
	If $$$ISERR(sc) {
		If ##class(OcuTalon.Data.Precedent).SourceRefIndexExists(ref) Quit ..Result(1, "already_recorded", ..#MESSAGEALREADYRECORDED)
		Quit ..Failed("the precedent could not be saved", sc)
	}
	Set result = ..Result(1, "recorded", ..#MESSAGERECORDED)
	Set result.Ref = row.Ref
	Quit result
}

/// Carries out an EndSession from SessionOps: the session's own rows are deleted.
Method End(command As OcuTalon.Msg.Command.EndSession) As OcuTalon.Msg.CommandResult [ Private ]
{
	If ..Source() '= ..#SESSIONSENDER Quit ..Refuse(command)
	Set sc = ##class(OcuTalon.Data.Precedent).DropSession(command.SessionRef)
	If $$$ISERR(sc) Quit ..Failed("the precedents of the session could not be deleted", sc)
	Quit ..Result(1, "ended", ..#MESSAGEENDED)
}

/// Carries out a SeedPrecedent from EvalIn while an evaluation runs.
Method Seed(message As OcuTalon.Core.Msg.SeedPrecedent) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..FromEval() Quit ..Refuse(message)
	Set at = message.AnsweredAt
	If (message.RunRef = "") || (message.MatchKey = "") Quit ..Result(0, "not_valid", ..#MESSAGENOTVALID)
	If '$ListFind($ListFromString(##class(OcuTalon.Data.Precedent).#ANSWERS), message.Answer) Quit ..Result(0, "not_valid", ..#MESSAGENOTVALID)
	If (message.Channel '= "") && '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#CHANNEL), message.Channel) Quit ..Result(0, "not_valid", ..#MESSAGENOTVALID)
	If (message.Outcome '= "") && '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#OUTCOME), message.Outcome) Quit ..Result(0, "not_valid", ..#MESSAGENOTVALID)
	If (at '= "") && (##class(OcuTalon.Data.Time).Seconds(at) = "") Quit ..Result(0, "not_valid", ..#MESSAGENOTVALID)
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set row.EvalRunRef = message.RunRef
	Set row.Channel = message.Channel
	Set row.MatchKey = message.MatchKey
	Set row.Summary = message.Summary
	Set row.Outcome = message.Outcome
	Set row.Answer = message.Answer
	Set row.AnsweredAt = $Select(at '= "": at, 1: ##class(OcuTalon.Data.Time).NowUtc())
	Set row.SourceRef = row.Ref
	Set sc = ..SaveRow(row)
	If $$$ISERR(sc) Quit ..Failed("the seeded precedent could not be saved", sc)
	Set result = ..Result(1, "seeded", ..#MESSAGESEEDED)
	Set result.Ref = row.Ref
	Quit result
}

/// Carries out a RemoveSeededPrecedents from EvalIn while an evaluation runs: the rows of that run are deleted, and no other row.
Method Remove(message As OcuTalon.Core.Msg.RemoveSeededPrecedents) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..FromEval() Quit ..Refuse(message)
	If message.RunRef = "" Quit ..Result(0, "not_valid", ..#MESSAGENOTVALID)
	Set sc = ##class(OcuTalon.Data.Precedent).RemoveRun(message.RunRef, .count)
	If $$$ISERR(sc) Quit ..Failed("the seeded precedents could not be removed", sc)
	Set result = ..Result(1, "removed", ..#MESSAGEREMOVED)
	Set result.Data = {"count": (count)}.%ToJSON()
	Quit result
}

/// 1 when the message of a verb comes from CommandsIn with Origin web_user.
Method FromVerb(command As OcuTalon.Msg.Command) As %Boolean [ Private ]
{
	Quit (..Source() = ..#COMMANDSENDER) && (command.Origin = "web_user")
}

/// 1 when the message comes from EvalIn and an evaluation is running (EvalOn).
Method FromEval() As %Boolean [ Private ]
{
	Quit (..Source() = ..#EVALSENDER) && ..EvalOn()
}

/// The item that sent the message being handled: the SourceConfigName of its header, else "".
Method Source() As %String [ Private ]
{
	Quit $Select($IsObject(..%RequestHeader): ..%RequestHeader.SourceConfigName, 1: "")
}

/// The refusal of a message from the wrong sender or origin, or while the evaluation switch is off: one warning and the outcome not_allowed. Nothing is written.
Method Refuse(message As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	$$$LOGWARNING("OcuTalon.Core.PrecedentOps: refused " _ $ClassName(message) _ " from '" _ ..Source() _ "'")
	Quit ..Result(0, "not_allowed", ..#MESSAGENOTALLOWED)
}

/// The Item that the Decision was made on, or "": the Msg.Item bodies of the messages of the Decision's trace session are opened, and the one whose
/// ItemId is the Decision's ItemId is returned. A Decision with no trace session, and an Item that is no longer kept, answer "". A failed read of the
/// headers throws, so the message answers failed rather than too_old. A seam for the tests.
Method ItemOf(decision As OcuTalon.Bridge.Data.Decision) As OcuTalon.Msg.Item [ Private ]
{
	If (decision.TraceSessionId = "") || (decision.ItemId = "") Quit ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'OcuTalon.Msg.Item' ORDER BY ID", decision.TraceSessionId)
	If result.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(result.%SQLCODE, result.%Message)
	While result.%Next() {
		Set item = ##class(OcuTalon.Msg.Item).%OpenId(result.%GetData(1))
		If $IsObject(item) && (item.ItemId = decision.ItemId) Quit
		Set item = ""
	}
	Quit $Get(item)
}

/// The one call that saves a Precedent row (a seam for the tests). The unique SourceRef makes the first save win.
Method SaveRow(row As OcuTalon.Data.Precedent) As %Status [ Private ]
{
	Quit row.%Save()
}

/// The answered channel of a row: the channel when it is a Msg.Enum CHANNEL value, else "".
ClassMethod ChannelOf(channel As %String) As %String [ Private ]
{
	Quit $Select($ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#CHANNEL), channel): channel, 1: "")
}

/// The marked or already_marked answer: Ok 1 with the row's Ref and Data {"answeredAt"}.
ClassMethod Marked(outcome As %String, message As %String, row As OcuTalon.Data.Precedent) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ..Result(1, outcome, message)
	Set result.Ref = row.Ref
	Set result.Data = {"answeredAt": (row.AnsweredAt)}.%ToJSON()
	Quit result
}

/// The failed answer: the reason is logged as a warning, with the status text, and the CommandResult is failed.
Method Failed(reason As %String, sc As %Status) As OcuTalon.Msg.CommandResult [ Private ]
{
	$$$LOGWARNING("OcuTalon.Core.PrecedentOps: " _ reason _ ": " _ $SYSTEM.Status.GetErrorText(sc))
	Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
}

/// A CommandResult with the outcome and the message.
ClassMethod Result(ok As %Boolean, outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = ok
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

}
