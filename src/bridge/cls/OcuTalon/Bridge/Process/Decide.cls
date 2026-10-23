Include Ensemble

/// Decide, the business process that every model use passes through (AD-6, AD-30).
///   - A Request is admitted (Admit): a message of another class, and kind tool (the replay of an approved call), get "not
///     implemented", and a kind, provenance, ItemId, OwnerRef or Input that is missing or unknown gets an error that names the
///     field, before anything is sent.
///   - One decision per item (AD-6): a decide or diagnose request for an item that has a Decision row is answered from the
///     row, and a turn for an item that has one is refused, because the row keeps no reply text.
///   - Otherwise Decide checks its settings (CheckSettings), allocates the DecisionRef and prechecks the request (Precheck, AD-8, AD-20):
///     no model key (Keys.Status), the daily cost cap reached (Budget.State) or an estimate over DecisionTokenBudget. A request that fails
///     a precheck is never sent: RecordFallback records it as a fallback decision and the answer is given from OnRequest, with no runner
///     request and no timer. Otherwise Decide sends a clone of the request that carries the DecisionRef to the runner of the kind
///     (RUNNERS) and sets the timer of TimerSeconds, a whole number of seconds from 1 to MAXTIMER (AD-5). Besides the runner request and
///     the timer, Decide sends only the agent steps (below); it answers only its caller.
///   - The steps (AD-9, AD-30): when the runner's reply arrives in time, and before anything reads it, EmitSteps sends each step record of
///     the reply's Steps to the AgentSteps operation (STEPSITEM) as an OcuTalon.Bridge.Msg.AgentStep, in order, so that the steps sit in
///     the caller's trace session after the runner's reply and before Decide's answer (StepMessages builds the messages). The reply of a
///     call whose Chat threw carries its steps like any other. A Steps value that does not parse and a send that fails are warnings that
///     name the DecisionRef and never change the answer. An answer from a recorded row, a precheck fallback, a timer that fired and a
///     late reply send no steps. Decide's answer to a turn leaves Steps empty.
///   - The classification (AD-8): Classify picks the one FallbackReason, or "" for a usable reply, from the facts of a request, in AD-8's
///     order: the prechecks (no_key, daily_cap, budget), the text of a failure (daily_cap, no_key, timeout, rate_limited, unusable for the
///     agent's maximum iterations, otherwise error), the provider's finish reason (refusal, cut_off), an empty text (empty, or unusable
///     when the provider reports no finish reason) and a reply that fails its check (invalid). Its literals are the class parameters
///     DAILYCAPTEXT, NOKEYTEXT, TIMEOUTTEXT, RATELIMITTEXT and ITERATIONCODES, each with its source.
///   - The runner's reply goes to Conclude, with the text of the runner's failure when it failed (OnError keeps a runner's error status,
///     and a call whose Chat threw is answered with a failure Reply that holds FailureText). Conclude works out the facts and calls
///     Classify once. A reply that is usable is checked (CheckReply: one JSON object that the ReplyClass setting of the runner accepts,
///     for decide and diagnose; non-empty text for a turn), the model-written text is filtered once by the ReplyFilterClass, the user
///     rule is applied, one Decision row is recorded, the event decision.recorded is fired after the commit (FireEvent) and the answer
///     is built. For a user's decide request an ignore or digest becomes tellnow.
///   - Any other reply is a fallback (RecordFallback): one Decision row with the outcome tellnow, Fallback true and the reason, and no
///     reasons, confidence or payload, so that no model text is kept; decision.recorded after the commit; and, for daily_cap, the day is
///     marked as capped once (Budget.MarkCapped). A decide or diagnose request is answered with the row's DecisionResponse, and a turn
///     with a new Reply that holds no text, host data, steps or failure text. A fallback triggers no tool, fix or approval (AD-8, AD-30).
///   - The row and the answer carry the decision's totals (AD-20): the token counts, the cost and the model are the sums over the
///     Usage rows of its DecisionRef, which the runner wrote (Usage.Totals); the step count is the runner's, and the duration is
///     the time from the moment Decide began to handle the request to Conclude. CarryTotals copies the eight fields between a
///     row and an answer, so an answer built from a recorded row carries the row's totals. A decision with no Usage row has empty
///     totals, and one with a row of unknown cost has an empty cost.
///   - A request that is refused (Admit, the settings) and the timer end with an error status, and no row is recorded; the late
///     reply of a runner after the timer is discarded by the business process framework.
/// The three extension settings name the classes through which the bridge reaches its host (AD-31); the production definition
/// sets the first two, and OcuTalon.Bridge.Ext.Accessor reads them in any job. The three budget settings (AD-19, AD-20) are
/// System Default Settings that OcuTalon.Bridge.Budget reads through the same accessor; DecisionTokenBudget is a setting of Decide
/// itself. FireEvent delivers every event of the bridge to the host sink. This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Process.Decide Extends Ens.BusinessProcess
{

Parameter SETTINGS = "HostSinkClass:Extensions,ReplyFilterClass:Extensions,ClassificationClass:Extensions,TimerSeconds:Bridge,DecisionTokenBudget:Bridge,DailyCostCapUSD:Bridge,GatewaySpendUSD:Bridge,GatewaySpendDate:Bridge";

/// The runner item of each request kind, as kind:item pairs (AD-6).
Parameter RUNNERS = "decide:TriageAgent,diagnose:DiagnosisAgent,turn:ChatAgent";

/// The longest timer, in seconds (AD-5, AD-8).
Parameter MAXTIMER = 110;

/// The operation that records the agent steps (AD-9).
Parameter STEPSITEM = "AgentSteps";

/// The first reason line of a user's decide request whose outcome was ignore or digest (AD-6).
Parameter USERANSWERED = "The outcome was changed because a message the user writes is always answered.";

/// The words of the online demo gateway's HTTP 403 for a reached daily cost cap, which Classify finds in a failure text: daily_cap
/// (source: AD-8; Story 1.6 Task 0 (b) measured the text that AI Hub raises for it). Matched without regard to case.
Parameter DAILYCAPTEXT = "daily cost cap reached";

/// The two pieces of the provider error for a key placeholder whose variable is not set, both held by a failure text: no_key (source:
/// Story 1.2's measurement of "@{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given"). Matched without regard to case.
Parameter NOKEYTEXT = "@{env:|has no value";

/// The words of the provider's timeout error: timeout (source: AD-8, S2). Matched without regard to case.
Parameter TIMEOUTTEXT = "operation timed out";

/// The words of the provider's error for HTTP 429 and 529: rate_limited (source: AD-8, S2; Story 0.11 measured the 529 text). Matched
/// without regard to case.
Parameter RATELIMITTEXT = "Rate limit exceeded";

/// The codes of the errors that end a turn in AI Hub's tool loop, comma-separated, each found in a failure text: unusable (source: Story 1.6
/// Task 0 (a), measured on build 154: MaxIterationsReached when the agent's iterations are used up, and LoopDetected when the loop stalls
/// on tool results that bring nothing new). Matched without regard to case.
Parameter ITERATIONCODES = "<%AICore>MaxIterationsReached,<%AICore>LoopDetected";

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

/// The token budget per decision (AD-19, AD-20, FR-40): a request whose estimate (EstimateTokens) is above it takes the fallback route
/// with the reason budget, and is never sent. 0 means off. A value that is not a whole number of 0 or more counts as 0, and the
/// precheck logs it (AssignOneSetting, OnRequest).
Property DecisionTokenBudget As %Integer [ InitialExpression = 0 ];

/// The error status that a runner ended its call with, kept by OnError for OnResponse (the key reply). Not stored.
Property RunnerError As %Status [ InitialExpression = 1, Internal, Transient ];

/// Assigns a setting as Ens.Settings does, except for the four budget settings (AD-20, DW-76). A value of DailyCostCapUSD,
/// GatewaySpendUSD or GatewaySpendDate that its property's datatype refuses, and a DecisionTokenBudget that is not made of digits only,
/// is assigned as "", so that the process can still be saved before OnRequest and the setting counts as off. The value as written
/// is still reported: Budget.State names the faults of the cap and of the gateway's spend, and OnRequest gives Precheck the text of a
/// DecisionTokenBudget that was not assigned.
Method AssignOneSetting(pProperty As %String, pValue As %String, pName As %String) As %Status
{
	Set sc = ##super(pProperty, pValue, pName)
	If $$$ISERR(sc) || '$ListFind($ListBuild("DecisionTokenBudget", "DailyCostCapUSD", "GatewaySpendUSD", "GatewaySpendDate"), pProperty) Quit sc
	If $$$ISERR($ClassMethod($ClassName(), pProperty_"IsValid", $Property($this, pProperty))) || ((pProperty = "DecisionTokenBudget") && (pValue '? 1.N)) {
		Set $Property($this, pProperty) = ""
	}
	Quit sc
}

/// Admits the request, finds the decision that is recorded for its item, prechecks it, or sends it to the runner of its kind and sets
/// the timer. The answer for a recorded decide or diagnose request, and the fallback answer of a request that fails a precheck
/// (Precheck), are given here (response): the second is recorded (RecordFallback) and nothing is sent, no runner request and no timer.
/// Otherwise the answer comes from OnResponse. The settings are checked first, so that a misconfigured Decide stays an error status and
/// is never hidden behind a fallback.
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
	Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tokenBudget = ..DecisionTokenBudget
	If tokenBudget = "" Set tokenBudget = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("DecisionTokenBudget", "", ..%ConfigName)
	Set reason = ..Precheck(request, runner, tokenBudget)
	If reason '= "" {
		Quit ..RecordFallback(request, decisionRef, reason, "", ..HostSinkClass, ..%SessionId, .response, ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated))
	}
	Set clone = request.%ConstructClone()
	Set clone.DecisionRef = decisionRef
	Set sc = ..SendRequestAsync(runner, clone, 1, "reply")
	If $$$ISERR(sc) Quit sc
	Quit ..SetTimer(+..TimerSeconds, "timer")
}

/// An error status of the runner's call (the completion key reply) is kept in RunnerError, and OK is returned, so that Ens calls
/// OnResponse next and the failure is classified there (AD-8); the process then ends with the fallback answer. An error of any
/// other call keeps its status.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If pCompletionKey = "reply" {
		Set ..RunnerError = pErrorStatus
		Quit $$$OK
	}
	Quit pErrorStatus
}

/// The timer ends Decide with an error that names it and the runner; the runner's reply ends in Conclude. For the reply, the steps are
/// sent first (EmitSteps), so that a reply that is then refused, or a call that failed, still shows its steps in the trace; Conclude
/// then gets the text of the runner's failure: the runner's error status (RunnerError, cut by StepBuffer.Part to Reply.#MAXFAILURE) or
/// the FailureText of its failure Reply.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set kind = request.Kind
	Set runner = ..RunnerFor(kind)
	If pCompletionKey = "timer" {
		Quit $$$ERROR($$$GeneralError, "The timer of "_..TimerSeconds_" seconds ended before "_runner_" answered the "_kind_" request for item "_request.ItemId)
	}
	If pCompletionKey '= "reply" Quit $$$ERROR($$$GeneralError, "Decide got a response with the unknown completion key '"_pCompletionKey_"'")
	Do ..EmitSteps(callrequest.DecisionRef, callresponse)
	Set failure = ""
	If $$$ISERR(..RunnerError) {
		Set failure = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part($SYSTEM.Status.GetErrorText(..RunnerError), ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
		Set ..RunnerError = $$$OK
	} ElseIf $IsObject(callresponse) && callresponse.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Set failure = callresponse.FailureText
	}
	Set replyClass = ""
	If kind '= "turn" {
		Set replyClass = ..ReplyClassOf(runner, .sc)
		If $$$ISERR(sc) Quit sc
	}
	Quit ..Conclude(request, callrequest.DecisionRef, callresponse, replyClass, ..ReplyFilterClass, ..HostSinkClass, ..%SessionId, .response, ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated), failure)
}

/// Sends each step record of the runner's reply to the AgentSteps operation, in order, without waiting for an answer: the sends
/// inherit this process's session and super session, so that the steps sit in the caller's trace session (AD-26). A send that fails
/// is a warning that names the step, the DecisionRef and the codes of its error, never the content (the text of a validation error
/// echoes the value that failed), and so is a Steps value that does not parse; nothing changes the answer.
Method EmitSteps(decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply)
{
	Try {
		Set messages = ..StepMessages(decisionRef, reply)
		For i = 1:1:messages.Count() {
			Set sc = ..SendRequestAsync(..#STEPSITEM, messages.GetAt(i), 0)
			If $$$ISERR(sc) {
				$$$LOGWARNING("Step "_i_" of the decision "_decisionRef_" was not sent to "_..#STEPSITEM_" (error codes "_$SYSTEM.Status.GetErrorCodes(sc)_")")
			}
		}
	} Catch exception {
		$$$LOGWARNING("The steps of the decision "_decisionRef_" were not sent: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// The AgentStep messages for the step records in the reply's Steps, as a list of messages in the order of the records. Position is the
/// place in the array, from 1, and DecisionRef is the one given. No Steps, a reply of another class and a Steps value that is not a
/// JSON array give an empty list; the last also logs a warning that names the DecisionRef and not the content. A record that is not
/// an object is skipped with the same warning.
ClassMethod StepMessages(decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply) As %ListOfObjects
{
	Set messages = ##class(%ListOfObjects).%New()
	Try {
		If $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply") && ($ZStrip(reply.Steps, "*WC") '= "") {
			Set records = ""
			Try {
				Set records = ##class(%Library.DynamicAbstractObject).%FromJSON(reply.Steps)
			} Catch {
				Set records = ""
			}
			If '$IsObject(records) || 'records.%IsA("%Library.DynamicArray") {
				$$$LOGWARNING("The steps of the decision "_decisionRef_" are not a JSON array of step records, so none is sent")
			} Else {
				Set iterator = records.%GetIterator()
				While iterator.%GetNext(.index, .record, .type) {
					If type '= "object" {
						$$$LOGWARNING("Step "_(index + 1)_" of the decision "_decisionRef_" is not a step record, so it is not sent")
						Continue
					}
					Set message = ##class(OcuTalon.Bridge.Msg.AgentStep).%New()
					Set message.DecisionRef = decisionRef
					Set message.Position = index + 1
					Set message.StepKind = $Extract(record.%Get("kind"), 1, 32)
					Set message.Label = $Extract(record.%Get("label"), 1, 1000)
					Set message.Summary = $Extract(record.%Get("summary"), 1, 1000)
					Set message.DurationMs = record.%Get("durationMs")
					Set message.Status = $Extract(record.%Get("status"), 1, 32)
					Set message.EstimatedTokens = record.%Get("estimatedTokens")
					Do messages.Insert(message)
				}
			}
		}
	} Catch exception {
		$$$LOGWARNING("The steps of the decision "_decisionRef_" cannot be read: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit messages
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

/// The FallbackReason of a request that must not be sent, or "" (AD-8, AD-20). The facts are the model key (Keys.Status of the runner
/// item), the daily cost cap (Budget.State: capped) and the estimate of the request against tokenBudget (the DecisionTokenBudget
/// setting as it is), and Classify picks the reason. Each fault that State names (DW-76) is logged as one warning, and so is a
/// tokenBudget that is not a whole number of 0 or more, which counts as 0 (off); empty is 0 too. Nothing is sent or recorded here.
ClassMethod Precheck(request As OcuTalon.Bridge.Msg.Request, runner As %String, tokenBudget As %String) As %String
{
	Set facts = {}
	Do facts.%Set("noKey", '##class(OcuTalon.Bridge.Keys).Status(runner), "boolean")
	Set state = ##class(OcuTalon.Bridge.Budget).State(, .faults)
	Do facts.%Set("capped", +state.%Get("capped"), "boolean")
	Set iterator = faults.%GetIterator()
	While iterator.%GetNext(, .fault) {
		$$$LOGWARNING("The daily cost cap may count less than it was set to: "_fault)
	}
	Set budget = 0
	If tokenBudget '= "" {
		If tokenBudget ? 1.N {
			Set budget = +tokenBudget
		} Else {
			$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The setting DecisionTokenBudget of Decide is '"_$Extract(tokenBudget, 1, 40)_"'; it must be a whole number of 0 or more, so the token budget counts as 0 (off)"))
		}
	}
	Do facts.%Set("overBudget", (budget > 0) && (..EstimateTokens(request) > budget), "boolean")
	Quit ..Classify(facts)
}

/// The estimated size of the request in tokens (AD-20): the lengths of its Input, SeedText and SystemNote added together, at
/// StepBuffer.CHARSPERTOKEN characters a token, rounded up. The system prompt, the tool schemas and the history are not counted yet.
ClassMethod EstimateTokens(request As OcuTalon.Bridge.Msg.Request) As %Integer
{
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens($Length(request.Input) + $Length(request.SeedText) + $Length(request.SystemNote))
}

/// The one classification (AD-8): "" when the request and the reply are usable, otherwise exactly one value of Msg.Enum FALLBACKREASON.
/// It is pure: it reads the facts and nothing else, and a fact that is missing counts as false or empty, so that no facts give "". The facts
/// of a dynamic object:
///   - noKey, capped and overBudget: booleans from the precheck;
///   - failure: the redacted text of a runner failure;
///   - finishReason and text: the runner's Reply;
///   - invalid: a boolean, true when the reply failed its ReplyClass check or nothing was left of it once the filter had run.
/// The first rule that holds wins:
///   1. noKey gives no_key, then capped gives daily_cap, then overBudget gives budget;
///   2. a failure is matched by its text, without regard to case: DAILYCAPTEXT gives daily_cap; NOKEYTEXT (both pieces) gives no_key;
///      TIMEOUTTEXT gives timeout; RATELIMITTEXT gives rate_limited (taken at once, no re-send yet); one of ITERATIONCODES gives
///      unusable; anything else gives error;
///   3. finishReason refusal gives refusal, and max_tokens gives cut_off, because a cut-off reply is never an answer (NFR-5);
///   4. a text fact that is blank once white space and control characters are removed gives empty when finishReason is not empty,
///      and unusable when it is, because a provider that reports no stop reason cannot tell an empty reply from a refusal or a cut-off
///      (with no text fact at all there is no reply to judge, so the rule does not apply);
///   5. invalid gives invalid.
ClassMethod Classify(facts As %DynamicObject) As %String
{
	If '$IsObject($Get(facts)) Quit ""
	If +facts.%Get("noKey") Quit "no_key"
	If +facts.%Get("capped") Quit "daily_cap"
	If +facts.%Get("overBudget") Quit "budget"
	Set failure = $ZConvert(facts.%Get("failure"), "L")
	If failure '= "" {
		If failure [ $ZConvert(..#DAILYCAPTEXT, "L") Quit "daily_cap"
		If ..HoldsAll(failure, ..#NOKEYTEXT) Quit "no_key"
		If failure [ $ZConvert(..#TIMEOUTTEXT, "L") Quit "timeout"
		If failure [ $ZConvert(..#RATELIMITTEXT, "L") Quit "rate_limited"
		Set iterations = 0
		For i = 1:1:$Length(..#ITERATIONCODES, ",") {
			Set code = $ZConvert($ZStrip($Piece(..#ITERATIONCODES, ",", i), "<>W"), "L")
			If (code '= "") && (failure [ code) Set iterations = 1
		}
		If iterations Quit "unusable"
		Quit "error"
	}
	Set finishReason = facts.%Get("finishReason")
	If finishReason = "refusal" Quit "refusal"
	If finishReason = "max_tokens" Quit "cut_off"
	If facts.%IsDefined("text") && ($ZStrip(facts.%Get("text"), "*WC") = "") Quit $Select(finishReason '= "": "empty", 1: "unusable")
	If +facts.%Get("invalid") Quit "invalid"
	Quit ""
}

/// 1 when the (lower case) text holds every piece of the pieces, which are separated by | and compared in lower case.
ClassMethod HoldsAll(text As %String, pieces As %String) As %Boolean [ Private ]
{
	Set holds = 1
	For i = 1:1:$Length(pieces, "|") {
		If text '[ $ZConvert($Piece(pieces, "|", i), "L") Set holds = 0
	}
	Quit holds
}

/// Turns the runner's reply into the recorded decision and the answer, in this order:
///   1. works out the facts of Classify: the failure (the text the runner failed with; with none, a reply that is not a Reply is the
///      failure "The runner gave no Reply"), the reply's finishReason and text, and invalid, which is true when the reply fails its check
///      or nothing is left of it once the filter has run. For decide and diagnose, the check is CheckReply against replyClass; for a
///      turn, the text itself;
///   2. calls Classify once. A reason goes to RecordFallback, which records the fallback and answers (below);
///   3. otherwise, the reply is usable and each model-written text was filtered once with filterClass (each reason; a turn's reply text),
///      never the code-written line; each reason is one line of the row: its line breaks (CR LF, CR, LF, vertical tab, form feed, NEL and
///      the Unicode line and paragraph separators) become spaces, and a reason that is blank once trimmed of white space and control
///      characters is dropped; a decision with no reason left, and a turn with no text left, once filtered, are invalid;
///   4. applies the user rule: for a decide request with provenance user, an ignore or digest becomes tellnow, and the first
///      reason line says so (USERANSWERED);
///   5. answers from the row that another call saved first for the item and kind, if there is one, and fires no event;
///   6. saves one Decision row (Record), with the confidence rounded to two decimals, traceSessionId as TraceSessionId and the
///      totals of the decision: the sums of the Usage rows of decisionRef (Usage.Totals), the reply's AgentStepCount and
///      durationMs (whole milliseconds, "" when unknown);
///   7. fires decision.recorded after the save (FireEvent);
///   8. builds the DecisionResponse, or a clone of the Reply with the filtered Text, the DecisionRef, the outcome tellnow and the
///      row's totals (CarryTotals), and with no Steps (Decide sent them) and no FailureText.
/// An unusable reply is recorded and answered by RecordFallback; only a filter class that fails its check, a row that cannot be saved
/// and a payload that cannot be exported end with an error status.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply, replyClass As %String, filterClass As %String, sinkClass As %String, traceSessionId As %Integer, Output response As %Persistent, durationMs As %Integer = "", failure As %String = "") As %Status
{
	Set response = ""
	Set kind = request.Kind
	Set turn = (kind = "turn")
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("ReplyFilterClass", filterClass)
	If $$$ISERR(sc) Quit sc
	Set isReply = $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply")
	If (failure = "") && 'isReply Set failure = "The runner gave no Reply"
	Set facts = {}
	Do facts.%Set("failure", failure)
	Set text = ""
	Set outcome = "tellnow"
	Set reasons = ""
	Set confidence = ""
	Set json = ""
	If isReply {
		Do facts.%Set("finishReason", reply.FinishReason)
		Do facts.%Set("text", reply.Text)
		Set invalid = 0
		If $ZStrip(reply.Text, "*WC") '= "" {
			If turn {
				Set text = $ClassMethod(filterClass, "Filter", reply.Text)
				If $ZStrip(text, "*WC") = "" Set invalid = 1
			} Else {
				Set invalid = '..Interpret(request, reply.Text, replyClass, filterClass, .outcome, .reasons, .confidence, .json, .sc)
			}
		}
		Do facts.%Set("invalid", invalid, "boolean")
	}
	If $$$ISERR(sc) Quit sc
	Set reason = ..Classify(facts)
	If reason '= "" {
		Quit ..RecordFallback(request, decisionRef, reason, reply, sinkClass, traceSessionId, .response, durationMs)
	}
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set row = ..NewRow(request, decisionRef, reply, traceSessionId, durationMs)
	Set row.Outcome = outcome
	Set row.Reasons = reasons
	Set row.Confidence = confidence
	Set row.Fallback = 0
	Set row.FallbackReason = ""
	Set row.Payload = json
	Set sc = ..Record(row, .saved, .response)
	If $$$ISERR(sc) || 'saved Quit sc
	Do ..FireEvent(sinkClass, request.OwnerRef, decisionRef)
	If turn {
		Set response = reply.%ConstructClone()
		Set response.Text = text
		Set response.DecisionRef = decisionRef
		Set response.Outcome = outcome
		Set response.Steps = ""
		Set response.FailureText = ""
		Do ..CarryTotals(row, response)
		Quit $$$OK
	}
	Quit ..ResponseFromRow(row, .response)
}

/// Checks the text of a decide or diagnose reply against the replyClass (CheckReply) and filters each reason once with filterClass. 1
/// when the reply is a decision: outcome, reasons (one line each, with the code-written line first when the user rule changed the
/// outcome), confidence (two decimals) and json (the payload as JSON) are set. 0 when it fails the check or no reason is left of it once
/// filtered (invalid). sc is an error only when the payload cannot be exported.
ClassMethod Interpret(request As OcuTalon.Bridge.Msg.Request, text As %String, replyClass As %String, filterClass As %String, Output outcome As %String, Output reasons As %String, Output confidence As %String, Output json As %String, Output sc As %Status) As %Boolean [ Private ]
{
	Set sc = $$$OK
	Set outcome = "tellnow"
	Set reasons = ""
	Set confidence = ""
	Set json = ""
	If $$$ISERR(..CheckReply(text, replyClass, .payload)) Quit 0
	Set lines = ""
	For i = 1:1:payload.Reasons.Count() {
		Set filtered = $ClassMethod(filterClass, "Filter", payload.Reasons.GetAt(i))
		Do payload.Reasons.SetAt(filtered, i)
		Set line = $ZStrip($Translate($Replace(filtered, $Char(13, 10), " "), $Char(10, 11, 12, 13, 133, 8232, 8233), "       "), "<>WC")
		If line '= "" Set lines = lines _ $ListBuild(line)
	}
	If lines = "" Quit 0
	Set outcome = payload.Outcome
	If (request.Kind = "decide") && (request.Provenance = "user") && ((outcome = "ignore") || (outcome = "digest")) {
		Set outcome = "tellnow"
		Set lines = $ListBuild(..#USERANSWERED) _ lines
	}
	Set reasons = $ListToString(lines, $Char(10))
	Set confidence = $Number(payload.Confidence, 2)
	Set sc = payload.%JSONExportToString(.json)
	Quit 1
}

/// Records an unusable request or reply as a fallback decision and answers it (AD-8, AD-20, AD-26, AD-31). reason is one value of
/// Msg.Enum FALLBACKREASON, and reply is the runner's Reply, or "" when nothing was sent. The Decision row is NewRow with the outcome
/// tellnow, Fallback true and the reason; Reasons, Confidence and Payload stay empty, so that no model text is kept. A row that another
/// call saved first for the item and kind is answered instead (the row of a turn is refused as ResponseFromRow says), and fires nothing.
/// When this call saved the row, decision.recorded is fired after the save (FireEvent) and, for daily_cap only, the day is marked as
/// capped (Budget.MarkCapped), outside any transaction. The answer to a decide or diagnose request is the DecisionResponse of the row;
/// the answer to a turn is a new Reply, never a clone of the runner's: it holds the DecisionRef, the outcome tellnow, Fallback, the
/// reason, the totals of the row and the runner's Tainted, and no text, host data, steps, failure text or finish reason. Nothing else is
/// sent: a fallback triggers no tool, fix or approval request.
ClassMethod RecordFallback(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reason As %String, reply As %RegisteredObject, sinkClass As %String, traceSessionId As %Integer, Output response As %Persistent, durationMs As %Integer = "") As %Status
{
	Set response = ""
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, request.Kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set row = ..NewRow(request, decisionRef, reply, traceSessionId, durationMs)
	Set row.Outcome = "tellnow"
	Set row.Reasons = ""
	Set row.Confidence = ""
	Set row.Fallback = 1
	Set row.FallbackReason = reason
	Set row.Payload = ""
	Set sc = ..Record(row, .saved, .response)
	If $$$ISERR(sc) || 'saved Quit sc
	Do ..FireEvent(sinkClass, request.OwnerRef, decisionRef)
	If reason = "daily_cap" Do ##class(OcuTalon.Bridge.Budget).MarkCapped("", sinkClass)
	If request.Kind '= "turn" Quit ..ResponseFromRow(row, .response)
	Set response = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set response.DecisionRef = decisionRef
	Set response.Outcome = "tellnow"
	Set response.Fallback = 1
	Set response.FallbackReason = reason
	If $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply") Set response.Tainted = reply.Tainted
	Do ..CarryTotals(row, response)
	Quit $$$OK
}

/// A new Decision row for the request: Ref, Kind, ItemId, OwnerRef, Summary, traceSessionId as TraceSessionId, RecordedAt (now, UTC), the
/// totals of the decision (the sums of the Usage rows of decisionRef, Usage.Totals), AgentStepCount from the reply (0 when there is none)
/// and durationMs as DurationMs. The caller sets the outcome, the reasons, the confidence, the fallback and the payload.
ClassMethod NewRow(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reply As %RegisteredObject, traceSessionId As %Integer, durationMs As %Integer = "") As OcuTalon.Bridge.Data.Decision
{
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = decisionRef
	Set row.Kind = request.Kind
	Set row.ItemId = request.ItemId
	Set row.OwnerRef = request.OwnerRef
	Set row.Summary = request.Summary
	Set row.TraceSessionId = traceSessionId
	Set row.RecordedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set totals = ##class(OcuTalon.Bridge.Data.Usage).Totals(decisionRef)
	Set row.InputTokens = totals.inputTokens
	Set row.OutputTokens = totals.outputTokens
	Set row.CacheReadTokens = totals.cacheReadTokens
	Set row.CacheWriteTokens = totals.cacheWriteTokens
	Set row.CostUSD = totals.costUSD
	Set row.Model = totals.model
	Set row.AgentStepCount = $Select($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"): reply.AgentStepCount, 1: 0)
	Set row.DurationMs = durationMs
	Quit row
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
<Value name="8">
<Value>DecisionTokenBudget</Value>
</Value>
</Data>
<DefaultData>DecideDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
