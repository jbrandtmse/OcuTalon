Include Ensemble

/// Decide, the business process that every model use passes through (AD-6, AD-30).
///   - A Request is admitted (Admit): a message of another class, and kind tool (the replay of an approved call), get "not
///     implemented", and a kind, provenance, ItemId, OwnerRef or Input that is missing or unknown gets an error that names the
///     field, before anything is sent.
///   - One decision per item (AD-6): a decide or diagnose request for an item that has a Decision row is answered from the
///     row, and a turn for an item that has one is refused, because the row keeps no reply text.
///   - Otherwise Decide checks its settings (CheckSettings), allocates the DecisionRef, sends a clone of the request that
///     carries it to the runner of the kind (RUNNERS) and sets the timer of TimerSeconds, a whole number of seconds from 1 to
///     MAXTIMER (AD-5). These are the only two messages Decide sends; it answers only its caller.
///   - The runner's reply goes to Conclude: the reply is checked (CheckReply: one JSON object that the ReplyClass setting of the
///     runner accepts, for decide and diagnose; non-empty text for a turn), the model-written text is filtered once by the
///     ReplyFilterClass, the user rule is applied, one Decision row is recorded, the event decision.recorded is fired after the
///     commit (FireEvent) and the answer is built. For a user's decide request an ignore or digest becomes tellnow.
///   - The row and the answer carry the decision's totals (AD-20): the token counts, the cost and the model are the sums over the
///     Usage rows of its DecisionRef, which the runner wrote (Usage.Totals); the step count is the runner's, and the duration is
///     the time from the moment Decide began to handle the request to Conclude. CarryTotals copies the eight fields between a
///     row and an answer, so an answer built from a recorded row carries the row's totals. A decision with no Usage row has empty
///     totals, and one with a row of unknown cost has an empty cost.
///   - A runner error, a reply that fails its check and the timer end with an error status, and no row is recorded; the late
///     reply of a runner after the timer is discarded by the business process framework.
/// The three extension settings name the classes through which the bridge reaches its host (AD-31); the production definition
/// sets the first two, and OcuTalon.Bridge.Ext.Accessor reads them in any job. The three budget settings (AD-19, AD-20) are
/// System Default Settings that OcuTalon.Bridge.Budget reads through the same accessor. FireEvent delivers every event of the
/// bridge to the host sink. This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Process.Decide Extends Ens.BusinessProcess
{

Parameter SETTINGS = "HostSinkClass:Extensions,ReplyFilterClass:Extensions,ClassificationClass:Extensions,TimerSeconds:Bridge,DailyCostCapUSD:Bridge,GatewaySpendUSD:Bridge,GatewaySpendDate:Bridge";

/// The runner item of each request kind, as kind:item pairs (AD-6).
Parameter RUNNERS = "decide:TriageAgent,diagnose:DiagnosisAgent,turn:ChatAgent";

/// The longest timer, in seconds (AD-5, AD-8).
Parameter MAXTIMER = 110;

/// The first reason line of a user's decide request whose outcome was ignore or digest (AD-6).
Parameter USERANSWERED = "The outcome was changed because a message the user writes is always answered.";

/// The class that receives the bridge's events; it extends OcuTalon.Bridge.Ext.HostSink.
Property HostSinkClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.HostSink" ];

/// The class that filters model-written text before a result leaves Decide; it extends OcuTalon.Bridge.Ext.ReplyFilter.
Property ReplyFilterClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.ReplyFilter" ];

/// The class that classifies tools beyond code and settings; it extends OcuTalon.Bridge.Ext.Classification.
Property ClassificationClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.Classification" ];

/// How long Decide waits for the runner's reply, in whole seconds from 1 to MAXTIMER (AD-5, AD-8).
Property TimerSeconds As %Integer [ InitialExpression = 60 ];

/// The daily cost cap in US dollars; 0 means off. A value that is not a number of 0 or more counts as 0 (OcuTalon.Bridge.Budget).
Property DailyCostCapUSD As %Numeric [ InitialExpression = 0 ];

/// The spend that the online demo's outbound gateway reports for GatewaySpendDate, in US dollars (AD-19, AD-20).
Property GatewaySpendUSD As %Numeric;

/// The instance-zone date, YYYY-MM-DD, that GatewaySpendUSD counts.
Property GatewaySpendDate As %String(MAXLEN = 10);

/// Admits the request, finds the decision that is recorded for its item, or sends it to the runner of its kind and sets the
/// timer. The answer for a recorded decide or diagnose request is given here (response); otherwise the answer comes from
/// OnResponse.
Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	Set sc = ..Admit(request)
	If $$$ISERR(sc) Quit sc
	Set kind = request.Kind
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set runner = ..RunnerFor(kind)
	Set replyClass = ""
	If kind '= "turn" {
		Set replyClass = ..ReplyClassOf(runner, .sc)
		If $$$ISERR(sc) Quit sc
	}
	Set sc = ..CheckSettings(kind, runner, replyClass, ..ReplyFilterClass, ..TimerSeconds)
	If $$$ISERR(sc) Quit sc
	Set clone = request.%ConstructClone()
	Set clone.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..SendRequestAsync(runner, clone, 1, "reply")
	If $$$ISERR(sc) Quit sc
	Quit ..SetTimer(+..TimerSeconds, "timer")
}

/// The timer ends Decide with an error that names it and the runner; the runner's reply ends in Conclude.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set kind = request.Kind
	Set runner = ..RunnerFor(kind)
	If pCompletionKey = "timer" {
		Quit $$$ERROR($$$GeneralError, "The timer of "_..TimerSeconds_" seconds ended before "_runner_" answered the "_kind_" request for item "_request.ItemId)
	}
	If pCompletionKey '= "reply" Quit $$$ERROR($$$GeneralError, "Decide got a response with the unknown completion key '"_pCompletionKey_"'")
	Set replyClass = ""
	If kind '= "turn" {
		Set replyClass = ..ReplyClassOf(runner, .sc)
		If $$$ISERR(sc) Quit sc
	}
	Quit ..Conclude(request, callrequest.DecisionRef, callresponse, replyClass, ..ReplyFilterClass, ..HostSinkClass, ..%SessionId, .response, ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated))
}

/// OK when the message is a Request that Decide serves. A message of another class, and a request of kind tool, give "not
/// implemented"; any other problem is an error that names the field: Kind (not one of Msg.Enum REQUESTKIND), Provenance (not
/// one of PROVENANCE), ItemId, OwnerRef, or Input (empty once white space and control characters are removed).
ClassMethod Admit(request As %Library.Persistent) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Bridge.Msg.Request") Quit $$$ERROR($$$NotImplemented)
	Set kinds = ##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND
	If '$ListFind($ListFromString(kinds), request.Kind) Quit $$$ERROR($$$GeneralError, "The Kind '"_request.Kind_"' of the request is not one of "_kinds)
	If request.Kind = "tool" Quit $$$ERROR($$$NotImplemented)
	Set provenances = ##class(OcuTalon.Bridge.Msg.Enum).#PROVENANCE
	If '$ListFind($ListFromString(provenances), request.Provenance) Quit $$$ERROR($$$GeneralError, "The Provenance '"_request.Provenance_"' of the request is not one of "_provenances)
	If request.ItemId = "" Quit $$$ERROR($$$GeneralError, "The ItemId of the request is empty")
	If request.OwnerRef = "" Quit $$$ERROR($$$GeneralError, "The OwnerRef of the request is empty")
	If $ZStrip(request.Input, "*WC") = "" Quit $$$ERROR($$$GeneralError, "The Input of the request is empty, so nothing is sent")
	Quit $$$OK
}

/// The runner item of the request kind (RUNNERS), or "".
ClassMethod RunnerFor(kind As %String) As %String
{
	Set runner = ""
	Set pairs = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		If $Piece(pair, ":", 1) = kind Set runner = $Piece(pair, ":", 2)
	}
	Quit runner
}

/// The ReplyClass setting of the runner item in the active production (OcuTalon.Bridge.Ext.Accessor.ValueFor), or "" with an error
/// in sc when it cannot be read. An empty value is returned as "" with OK; CheckSettings refuses it.
ClassMethod ReplyClassOf(runner As %String, Output sc As %Status) As %String
{
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ReplyClass", "", runner, .sc)
	If $$$ISERR(sc) {
		Set sc = $$$ERROR($$$GeneralError, "The ReplyClass setting of "_runner_" cannot be read: "_$SYSTEM.Status.GetErrorText(sc))
		Quit ""
	}
	Quit class
}

/// OK when the settings allow the request to be sent; otherwise an error that names the setting:
///   - timer (TimerSeconds): a whole number from 1 to MAXTIMER;
///   - filterClass (ReplyFilterClass): passes OcuTalon.Bridge.Ext.Accessor.Check, so that no text is ever recorded unfiltered;
///   - replyClass (the ReplyClass setting of the runner), for kind decide and diagnose: a compiled %JSON.Adaptor class. A
///     runner with no ReplyClass cannot answer these kinds. A turn needs no ReplyClass.
ClassMethod CheckSettings(kind As %String, runner As %String, replyClass As %String, filterClass As %String, timer As %String) As %Status
{
	If (timer '? 1.N) || (+timer < 1) || (+timer > ..#MAXTIMER) {
		Quit $$$ERROR($$$GeneralError, "The setting TimerSeconds of Decide is '"_timer_"'; it must be a whole number of seconds from 1 to "_..#MAXTIMER)
	}
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("ReplyFilterClass", filterClass)
	If $$$ISERR(sc) Quit sc
	If kind = "turn" Quit $$$OK
	If replyClass = "" {
		Quit $$$ERROR($$$GeneralError, "The runner "_runner_" has no ReplyClass setting, so a "_kind_" request cannot be sent: ReplyClass names the %JSON.Adaptor class that the reply is checked against")
	}
	If '##class(%Dictionary.CompiledClass).%ExistsId(replyClass) || '$ClassMethod(replyClass, "%Extends", "%JSON.Adaptor") {
		Quit $$$ERROR($$$GeneralError, "The ReplyClass setting of "_runner_" names '"_replyClass_"', which is not a compiled %JSON.Adaptor class")
	}
	Quit $$$OK
}

/// Checks the reply text against the class: one JSON object that the class imports (%JSONImport, with exceptions caught) and
/// validates (%ValidateObject). Only surrounding white space, or one surrounding Markdown code fence, is removed first.
/// payload is the validated object, or "" with an error that names the reply check.
ClassMethod CheckReply(text As %String, replyClass As %String, Output payload As %RegisteredObject) As %Status
{
	Set payload = ""
	Try {
		Set object = $ClassMethod(replyClass, "%New")
		Set sc = object.%JSONImport(..Unfenced(text))
		If $$$ISOK(sc) Set sc = object.%ValidateObject()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		Quit $$$ERROR($$$GeneralError, "The reply check failed: the reply is not one JSON object that "_replyClass_" accepts: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 400))
	}
	Set payload = object
	Quit $$$OK
}

/// The text without surrounding white space, and without one surrounding Markdown code fence: three backticks and an optional
/// language word on the first line, and three backticks at the end.
ClassMethod Unfenced(text As %String) As %String
{
	Set trimmed = $ZStrip(text, "<>WC")
	Set fence = $Char(96, 96, 96)
	Set length = $Length(trimmed)
	If (length < 6) || ($Extract(trimmed, 1, 3) '= fence) || ($Extract(trimmed, length - 2, length) '= fence) Quit trimmed
	Set inner = $Extract(trimmed, 4, length - 3)
	Set lines = $Length(inner, $Char(10))
	If lines > 1 {
		Set first = $ZStrip($Piece(inner, $Char(10), 1), "<>WC")
		If first ? .(1A,1N,1"-",1"_") Set inner = $Piece(inner, $Char(10), 2, lines)
	}
	Quit $ZStrip(inner, "<>WC")
}

/// OK when the runner's reply is usable as an answer: it did not end in a refusal or at the output cap (the provider's
/// finish reasons refusal and max_tokens), and a turn's text is not empty.
ClassMethod CheckReplyShape(kind As %String, reply As OcuTalon.Bridge.Msg.Reply) As %Status
{
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Quit $$$ERROR($$$GeneralError, "The runner gave no Reply to the "_kind_" request")
	}
	If $ListFind($ListBuild("refusal", "max_tokens"), reply.FinishReason) {
		Quit $$$ERROR($$$GeneralError, "The reply to the "_kind_" request is unusable: the provider ended it with the finish reason "_reply.FinishReason)
	}
	If (kind = "turn") && ($ZStrip(reply.Text, "*WC") = "") {
		Quit $$$ERROR($$$GeneralError, "The reply to the turn is empty, which is not an answer")
	}
	Quit $$$OK
}

/// Turns the runner's reply into the recorded decision and the answer, in this order:
///   1. interprets the reply: for decide and diagnose, CheckReply against replyClass; for a turn, its text;
///   2. filters each model-written text once with filterClass (each reason; a turn's reply text), never the code-written line;
///      each reason is one line of the row: its line breaks (CR LF, CR, LF, vertical tab, form feed, NEL and the Unicode line
///      and paragraph separators) become spaces, and a reason that is blank once trimmed of white space and control characters
///      is dropped; a decision with no reason left, and a turn with no text left, once filtered, are not answers;
///   3. applies the user rule: for a decide request with provenance user, an ignore or digest becomes tellnow, and the first
///      reason line says so (USERANSWERED);
///   4. answers from the row that another call saved first for the item and kind, if there is one, and fires no event;
///   5. saves one Decision row (Record), with the confidence rounded to two decimals, traceSessionId as TraceSessionId and the
///      totals of the decision: the sums of the Usage rows of decisionRef (Usage.Totals), the reply's AgentStepCount and
///      durationMs (whole milliseconds, "" when unknown);
///   6. fires decision.recorded after the save (FireEvent);
///   7. builds the DecisionResponse, or a clone of the Reply with the filtered Text, the DecisionRef, the outcome tellnow and the
///      row's totals (CarryTotals).
/// A reply that fails a step ends with an error status and records nothing.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply, replyClass As %String, filterClass As %String, sinkClass As %String, traceSessionId As %Integer, Output response As %Persistent, durationMs As %Integer = "") As %Status
{
	Set response = ""
	Set kind = request.Kind
	Set turn = (kind = "turn")
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("ReplyFilterClass", filterClass)
	If $$$ISOK(sc) Set sc = ..CheckReplyShape(kind, reply)
	If $$$ISERR(sc) Quit sc
	If turn {
		Set text = $ClassMethod(filterClass, "Filter", reply.Text)
		If $ZStrip(text, "*WC") = "" {
			Quit $$$ERROR($$$GeneralError, "The reply check failed: no text is left of the turn's reply once "_filterClass_" has filtered it")
		}
		Set outcome = "tellnow"
		Set reasons = ""
		Set confidence = ""
		Set json = ""
	} Else {
		Set sc = ..CheckReply(reply.Text, replyClass, .payload)
		If $$$ISERR(sc) Quit sc
		Set lines = ""
		For i = 1:1:payload.Reasons.Count() {
			Set filtered = $ClassMethod(filterClass, "Filter", payload.Reasons.GetAt(i))
			Do payload.Reasons.SetAt(filtered, i)
			Set line = $ZStrip($Translate($Replace(filtered, $Char(13, 10), " "), $Char(10, 11, 12, 13, 133, 8232, 8233), "       "), "<>WC")
			If line '= "" Set lines = lines _ $ListBuild(line)
		}
		If lines = "" {
			Quit $$$ERROR($$$GeneralError, "The reply check failed: no reason is left of the reply once "_filterClass_" has filtered the reasons")
		}
		Set outcome = payload.Outcome
		If (kind = "decide") && (request.Provenance = "user") && ((outcome = "ignore") || (outcome = "digest")) {
			Set outcome = "tellnow"
			Set lines = $ListBuild(..#USERANSWERED) _ lines
		}
		Set reasons = $ListToString(lines, $Char(10))
		Set confidence = $Number(payload.Confidence, 2)
		Set sc = payload.%JSONExportToString(.json)
		If $$$ISERR(sc) Quit sc
	}
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = decisionRef
	Set row.Kind = kind
	Set row.ItemId = request.ItemId
	Set row.OwnerRef = request.OwnerRef
	Set row.Summary = request.Summary
	Set row.Outcome = outcome
	Set row.Reasons = reasons
	Set row.Confidence = confidence
	Set row.Fallback = 0
	Set row.FallbackReason = ""
	Set row.Payload = json
	Set row.TraceSessionId = traceSessionId
	Set row.RecordedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set totals = ##class(OcuTalon.Bridge.Data.Usage).Totals(decisionRef)
	Set row.InputTokens = totals.inputTokens
	Set row.OutputTokens = totals.outputTokens
	Set row.CacheReadTokens = totals.cacheReadTokens
	Set row.CacheWriteTokens = totals.cacheWriteTokens
	Set row.CostUSD = totals.costUSD
	Set row.Model = totals.model
	Set row.AgentStepCount = reply.AgentStepCount
	Set row.DurationMs = durationMs
	Set sc = ..Record(row, .saved, .response)
	If $$$ISERR(sc) || 'saved Quit sc
	Do ..FireEvent(sinkClass, request.OwnerRef, decisionRef)
	If turn {
		Set response = reply.%ConstructClone()
		Set response.Text = text
		Set response.DecisionRef = decisionRef
		Set response.Outcome = outcome
		Do ..CarryTotals(row, response)
		Quit $$$OK
	}
	Quit ..ResponseFromRow(row, .response)
}

/// Saves the row. The unique index on ItemId and Kind refuses a row for an item that another call recorded first: then nothing
/// is saved (saved is 0) and response is the answer for the row that won, or the error of ResponseFromRow when that row is a
/// turn's. Any other save error is returned as it is.
ClassMethod Record(row As OcuTalon.Bridge.Data.Decision, Output saved As %Boolean, Output response As %Persistent) As %Status
{
	Set saved = 0
	Set response = ""
	Set sc = row.%Save()
	If $$$ISOK(sc) {
		Set saved = 1
		Quit $$$OK
	}
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(row.ItemId, row.Kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Quit sc
}

/// Fires an event to the host sink: OnEvent(type, ownerRef, payload), by default decision.recorded with {"ref": ref}. Every event
/// of the bridge goes through this method (AD-31). Call it after the change it reports has committed. An error status, an
/// exception and a sink class that fails OcuTalon.Bridge.Ext.Accessor.Check (then no event is sent) are logged as a warning that
/// names the class, the event and the subject, and never fail the caller. 1 when OnEvent returned OK.
///   - type: one of OcuTalon.Bridge.Ext.HostSink EVENTS; empty means decision.recorded;
///   - ref: the subject of the event for the warning: the Ref of the decision, or the day of budget.capped;
///   - payload: the payload object; empty means HostSink.RefPayload(ref).
ClassMethod FireEvent(sinkClass As %String, ownerRef As %String, ref As %String, type As %String = "", payload As %DynamicObject = "") As %Boolean
{
	Set event = $Select(type = "": ##class(OcuTalon.Bridge.Ext.HostSink).#DECISIONRECORDED, 1: type)
	Set delivered = 0
	Try {
		If '$IsObject(payload) Set payload = ##class(OcuTalon.Bridge.Ext.HostSink).RefPayload(ref)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", sinkClass)
		If $$$ISOK(sc) {
			Set sc = $ClassMethod(sinkClass, "OnEvent", event, ownerRef, payload)
		}
		If $$$ISOK(sc) {
			Set delivered = 1
		} Else {
			$$$LOGWARNING("The host sink "_sinkClass_" did not take the event "_event_" for "_ref_": "_$SYSTEM.Status.GetErrorText(sc))
		}
	} Catch exception {
		Set delivered = 0
		$$$LOGWARNING("The host sink "_sinkClass_" threw on the event "_event_" for "_ref_": "_exception.DisplayString())
	}
	Quit delivered
}

/// The answer for the Decision row with this id.
ClassMethod ResponseFromId(id As %String, Output response As %Persistent) As %Status
{
	Set response = ""
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%OpenId(id, , .sc)
	If $$$ISERR(sc) Quit sc
	Quit ..ResponseFromRow(row, .response)
}

/// The DecisionResponse for a recorded decide or diagnose row: its Ref as DecisionRef, outcome, reasons, confidence,
/// fallback flag and reason, payload and totals (CarryTotals). The row of a turn keeps no reply text, so a turn is refused with an
/// error that names the item and the Ref.
ClassMethod ResponseFromRow(row As OcuTalon.Bridge.Data.Decision, Output response As %Persistent) As %Status
{
	Set response = ""
	If row.Kind = "turn" {
		Quit $$$ERROR($$$GeneralError, "The item "_row.ItemId_" already has the turn decision "_row.Ref_"; the row keeps no reply text, and a second answer would answer the message twice")
	}
	Set response = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set response.DecisionRef = row.Ref
	Set response.Outcome = row.Outcome
	Set response.Reasons = row.Reasons
	Set response.Confidence = row.Confidence
	Set response.Fallback = row.Fallback
	Set response.FallbackReason = row.FallbackReason
	Set response.Payload = row.Payload
	Do ..CarryTotals(row, response)
	Quit $$$OK
}

/// Copies the eight total fields (InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens, CostUSD, Model, AgentStepCount and
/// DurationMs) from a Decision row to an answer, or the other way: both hold them under these names (AD-20, AD-26).
ClassMethod CarryTotals(from As %RegisteredObject, to As %RegisteredObject)
{
	For name = "InputTokens", "OutputTokens", "CacheReadTokens", "CacheWriteTokens", "CostUSD", "Model", "AgentStepCount", "DurationMs" {
		Set $Property(to, name) = $Property(from, name)
	}
}

Storage Default
{
<Data name="DecideDefaultData">
<Subscript>"Decide"</Subscript>
<Value name="1">
<Value>HostSinkClass</Value>
</Value>
<Value name="2">
<Value>ReplyFilterClass</Value>
</Value>
<Value name="3">
<Value>ClassificationClass</Value>
</Value>
<Value name="4">
<Value>TimerSeconds</Value>
</Value>
<Value name="5">
<Value>DailyCostCapUSD</Value>
</Value>
<Value name="6">
<Value>GatewaySpendUSD</Value>
</Value>
<Value name="7">
<Value>GatewaySpendDate</Value>
</Value>
</Data>
<DefaultData>DecideDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
