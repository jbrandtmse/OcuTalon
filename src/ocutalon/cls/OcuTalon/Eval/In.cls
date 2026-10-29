/// EvalIn, the adapterless service that sends the recorded cases of eval/ through the product's own path (AD-22, AD-30). Lane A.
/// The product keeps it disabled; the Production install step enables it only when OCUTALON_EVAL is 1, and Start reaches it only through
/// Ens.Director.CreateBusinessService, so a disabled EvalIn sends nothing. It uses neither EnsLib.Testing.Service nor the production's
/// testing switch. An item case goes to Intake; a turn case goes to Decide and its result to EvalSink, and nothing else is ever a target.
///   - Start is the run entry: it creates the service, mints the run's Ref and sends each named case, or each case folder under the
///     folder, once. It returns the run's Ref, how many cases were sent, and the cases that were not, each with its reason.
///   - Start sends the turn cases first (SendOrder), then the others, each group in the order of the case list. ChatAgent has one job,
///     so the Decide timer of a turn case would otherwise be spent behind the act turns of earlier item cases.
///   - A case is a folder with a case.json (the shape of the eval/ cases): name, kind, heldOut, description, expectation and
///     recordedBy, and for a kind of item or injection an item {itemId, channel, provenance, sender, subject, text, catalogKey, slots},
///     and for a kind of all-clear or command a turn {text} (and, for an all-clear, checks: the array of the recorded check rows).
///     A case that is not sent is logged as a warning and goes into the skipped list with its reason: a kind that is not sent (an
///     incident), no case.json or one that is not a JSON object, no item.itemId, a recorded provenance other than untrusted, no
///     turn.text, or an all-clear case whose checks is not an array. The other cases still run.
///   - A sent case is an OcuTalon.Msg.Item with a fresh ItemId (OcuTalon.Bridge.Ids.NewRef), SourceItemId set to the recorded
///     item.itemId, owner eval (OcuTalon.Data.Ownership EVAL), provenance untrusted, and the channel, sender, subject, text, catalog key
///     and slots of the record. Before the send EvalIn opens the case's OcuTalon.Eval.Data.CaseResult row, which EvalSink completes;
///     a send that fails deletes the row and skips the case with the error text.
///   - A turn case (SendTurn) is a user turn of owner eval: a fresh ItemId, a request of Kind turn, Provenance user, Channel web,
///     SessionMode fresh (so that no case shares a conversation with another) and no SeedText, with the Input that Agent.Input renders from
///     an unsaved Item of the case's turn.text. Before the send EvalIn saves the case's OcuTalon.Eval.Msg.TurnResult (ItemId,
///     SourceItemId and RecordedChecks, the case's checks as JSON for an all-clear case), which the eval branch of check_status reads by
///     the request's ItemId, and opens the case's row. It sends the request to Decide and waits for the Reply: a Busy reply is asked
///     again BUSYWAIT seconds later, BUSYMAX times at most, and then the case ends as a fallback with the reason rate_limited. The Reply's
///     DecisionRef, ToolsRun, Text, Fallback and FallbackReason go into the TurnResult, and so do the catalog key and rows that
///     Checks.Render gives the Reply's HostData checks. EvalIn then sends the TurnResult to EvalSink, which completes the row. A Decide
///     that gives no Reply (an error, a timeout or an answer that is not a Reply) deletes the row and the TurnResult and skips the case.
///   - A case of kind item or injection may declare a watch {namespace, production}: the production that the case's email talks about, with a
///     watch of it set up for the run. Before the case's row is opened and its Item is sent, EvalIn calls OcuTalon.Watch.Ops.EvalWatch (the
///     watch of owner eval, never polled, never due, no CheckChanged). A watch that is not an object with a non-blank namespace and production
///     skips the case with REASONWATCHSHAPE, and one that cannot be set up skips it with REASONWATCH and the status text; neither leaves a row.
///     A row that cannot be opened and a send that fails remove the watch again. A sent case's record {case, watch}, watch being
///     OcuTalon.Watch.Ops.Fields of the row, goes into the Watches of the service, and Start returns the records in its last output. Finish
///     removes exactly the rows of the records it is given, through OcuTalon.Watch.Ops.RemoveEvalWatch.
///   - The trace: each case is its own trace session, and every message of the run carries the run's Ref as its SuperSession (AD-26).
/// Wait polls the rows of a run until none is still sent, or the seconds have passed.
Class OcuTalon.Eval.In Extends Ens.BusinessService
{

/// The folder of the recorded cases in a throwaway stack: the repository's eval/ mounted read-only.
Parameter FOLDER = "/opt/ocutalon/eval/";

/// The item that takes every Item.
Parameter TARGET = "Intake";

/// The item that answers a turn case.
Parameter DECIDE = "Decide";

/// The item that completes the rows, and takes the TurnResult of a turn case.
Parameter SINK = "EvalSink";

/// The kinds of case that EvalIn sends, comma-separated.
Parameter KINDS = "item,injection,all-clear,command";

/// The kinds of case that hold a recorded Item, and go to Intake.
Parameter ITEMKINDS = "item,injection";

/// The kinds of case that are a user turn, and go to Decide.
Parameter TURNKINDS = "all-clear,command";

/// The kind of turn case that holds recorded check rows.
Parameter ALLCLEARKIND = "all-clear";

/// The channel of a turn case: the user asks in the chat.
Parameter TURNCHANNEL = "web";

/// The seconds to wait for Decide's Reply: above the longest timer of Decide (110) and its 2-second conversation probe.
Parameter TURNWAIT = 150;

/// Seconds to wait before a Busy turn is asked again, and how many times it is asked again before the fallback rate_limited: the numbers
/// of Core.Conversation (a test pins them equal), kept here so that the turn path reads no Lane B class.
Parameter BUSYWAIT = 3;

Parameter BUSYMAX = 5;

/// The name of the file that holds a case.
Parameter CASEFILE = "case.json";

Parameter REASONINPUT = "EvalIn takes the folder of a case from Start and nothing else.";

Parameter REASONNOCASEFILE = "the folder has no case.json";

Parameter REASONNOTJSON = "case.json is not a JSON object";

Parameter REASONKIND = "its kind is '{kind}', and only the kinds {kinds} are sent";

Parameter REASONNOITEMID = "it has no item.itemId";

Parameter REASONPROVENANCE = "its recorded provenance is '{provenance}', not untrusted";

Parameter REASONNOTEXT = "it has no turn.text";

Parameter REASONNOCHECKS = "its checks is not an array";

Parameter REASONNOREPLY = "Decide gave no Reply";

Parameter REASONWATCHSHAPE = "its watch is not an object with a namespace and a production";

/// {why} is the text of the status that WatchOps.EvalWatch returned.
Parameter REASONWATCH = "its watch could not be set up: {why}";

/// The start of the warning for a case that is not sent; the case's name and its reason follow it.
Parameter LOGSKIPPED = "EvalIn did not send the case ";

/// The start of the warning for a TurnResult that could not be sent to EvalSink; the case's name and the error follow it.
Parameter LOGNOTDELIVERED = "EvalIn could not send the TurnResult of the case ";

/// The start of the warning for check rows in a Reply that Checks.Render could not take; the error follows it.
Parameter LOGCHECKS = "EvalIn could not render the check rows of the Reply: ";

/// The Ref of the run that this service instance sends; Start sets it.
Property RunRef As %String(MAXLEN = 22);

/// The setup records of the run's watches, a dynamic array of {"case", "watch"}: one for each sent case that declared a watch. Start sets it.
Property Watches As %DynamicArray;

/// Starts a run: creates EvalIn, mints the run's Ref and sends each case once.
///   - folder holds the case folders. names is a comma-separated list of case folder names; "" means every subfolder that holds a
///     case.json, in name order.
///   - runRef is the run's Ref, 22 characters, "" when the run did not start. sent is the number of cases sent. skipped is a dynamic
///     array of {"case", "reason"} for each case that was not sent.
///   - watches is always a dynamic array: the setup records {"case", "watch"} of the sent cases that declared a watch (empty when the run
///     did not start). The run's end passes it to Finish.
///   - The status is the director's error when EvalIn cannot be created, which a disabled EvalIn is (the text says disabled); then
///     nothing was sent and there is no run Ref. Otherwise OK.
ClassMethod Start(folder As %String = {..#FOLDER}, names As %String = "", Output runRef As %String, Output sent As %Integer, Output skipped As %DynamicArray, Output watches As %DynamicArray) As %Status
{
	Set runRef = "", sent = 0, skipped = [], watches = []
	Set sc = ##class(Ens.Director).CreateBusinessService("EvalIn", .service)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(service) || 'service.%IsA("OcuTalon.Eval.In") Quit $SYSTEM.Status.Error(5001, "The item EvalIn is not an OcuTalon.Eval.In")
	Set folder = ##class(%File).NormalizeDirectory(folder)
	Set list = ..SendOrder(folder, ..CaseNames(folder, names))
	Set service.RunRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set service.Watches = watches
	Set runRef = service.RunRef
	Set position = 0
	While $ListNext(list, position, name) {
		Set input = ##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(folder, name))
		Kill output
		Set sc = service.ProcessInput(input, .output)
		Set reason = $Select($$$ISERR(sc): $SYSTEM.Status.GetOneStatusText(sc), $IsObject($Get(output)): output.StringValue, 1: "")
		If reason = "" {
			Set sent = sent + 1
		} Else {
			Do skipped.%Push({"case": (name), "reason": (reason)})
		}
	}
	Quit $SYSTEM.Status.OK()
}

/// Waits, polling every 0.25 seconds and for at most the seconds, until none of the run's rows is still sent. Returns how many are.
ClassMethod Wait(runRef As %String, seconds As %Integer) As %Integer
{
	Set end = $ZHorolog + seconds
	For {
		Set open = ##class(OcuTalon.Eval.Data.CaseResult).Unanswered(runRef)
		If (open = 0) || ($ZHorolog '< end) Quit
		Hang 0.25
	}
	Quit open
}

/// Removes the watch rows of the records that Start returned in watches, each through OcuTalon.Watch.Ops.RemoveEvalWatch, and nothing else. A
/// row that is already gone is no error. Every record is tried; the status is the first error, and Finish never throws.
ClassMethod Finish(watches As %DynamicArray) As %Status
{
	Set result = $$$OK
	Try {
		If $IsObject($Get(watches)) && watches.%IsA("%Library.DynamicArray") {
			Set iterator = watches.%GetIterator()
			While iterator.%GetNext(, .record) {
				Set sc = ..Unwatch($Select($IsObject(record) && record.%IsA("%Library.DynamicObject"): record.%Get("watch"), 1: ""))
				If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
			}
		}
	} Catch exception {
		If $$$ISOK(result) Set result = exception.AsStatus()
	}
	Quit result
}

/// The case folder names to send, as a list: the names given, each once, in the order given, or, with no names, every subfolder of the
/// folder that holds a case.json, in name order.
ClassMethod CaseNames(folder As %String, names As %String) As %List
{
	Set list = ""
	If $ZStrip(names, "*W") '= "" {
		For i = 1:1:$Length(names, ",") {
			Set name = $ZStrip($Piece(names, ",", i), "<>W")
			If (name '= "") && '$ListFind(list, name) Set list = list_$ListBuild(name)
		}
		Quit list
	}
	Set rows = ##class(%ResultSet).%New("%File:FileSet")
	If $$$ISERR(rows.Execute(folder, "*", "Name", 1)) Quit ""
	While rows.Next() {
		If rows.Get("Type") '= "D" Continue
		Set name = rows.Get("ItemName")
		If ##class(%File).Exists(##class(%File).NormalizeFilename(..#CASEFILE, ##class(%File).SubDirectoryName(folder, name))) Set list = list_$ListBuild(name)
	}
	Quit list
}

/// The case list in the order Start sends it: the cases of the turn kinds first, then every other, each group in the order of the list. A
/// case whose kind cannot be read goes with the others.
ClassMethod SendOrder(folder As %String, list As %List) As %List
{
	Set turns = "", others = ""
	Set position = 0
	While $ListNext(list, position, name) {
		If $ListFind($ListFromString(..#TURNKINDS), ..KindOf(folder, name)) {
			Set turns = turns_$ListBuild(name)
		} Else {
			Set others = others_$ListBuild(name)
		}
	}
	Quit turns_others
}

/// The kind of the case in the folder's subfolder of that name, or "" when its case.json cannot be read.
ClassMethod KindOf(folder As %String, name As %String) As %String [ Private ]
{
	Set kind = ""
	Try {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename(..#CASEFILE, ##class(%File).SubDirectoryName(folder, name)))
		If $IsObject(case) && case.%IsA("%Library.DynamicObject") Set kind = ..Scalar(case, "kind")
	} Catch exception {
		Set kind = ""
	}
	Quit kind
}

/// Sends the case in the folder; pOutput is an Ens.StringContainer whose StringValue is "" when the case was sent, and otherwise the
/// reason it was not.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ##class(Ens.StringContainer).%New("")
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("Ens.StringContainer") || (..RunRef = "") {
		Set pOutput.StringValue = ..#REASONINPUT
		Quit $$$OK
	}
	Set folder = pInput.StringValue
	Set name = ##class(%File).GetFilename($ZStrip(folder, ">", "/"))
	Set reason = ""
	Try {
		Set reason = ..Send(folder, name)
	} Catch exception {
		Set reason = exception.DisplayString()
	}
	If reason '= "" $$$LOGWARNING(..#LOGSKIPPED_name_": "_reason)
	Set pOutput.StringValue = reason
	Quit $$$OK
}

/// The steps for one case; the reason it was not sent, or "" when it was.
Method Send(folder As %String, name As %String) As %String [ Private ]
{
	Set file = ##class(%File).NormalizeFilename(..#CASEFILE, folder)
	If '##class(%File).Exists(file) Quit ..#REASONNOCASEFILE
	Set case = ""
	Try {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
	} Catch exception {
		Set case = ""
	}
	If '$IsObject(case) || 'case.%IsA("%Library.DynamicObject") Quit ..#REASONNOTJSON
	Set kind = ..Scalar(case, "kind")
	If '$ListFind($ListFromString(..#KINDS), kind) Quit $Replace($Replace(..#REASONKIND, "{kind}", $Extract(kind, 1, 40)), "{kinds}", ..KindsText())
	If $ListFind($ListFromString(..#TURNKINDS), kind) Quit ..SendTurn(case, kind, name)
	Set record = case.item
	If '$IsObject(record) || 'record.%IsA("%Library.DynamicObject") || (..Scalar(record, "itemId") = "") Quit ..#REASONNOITEMID
	Set provenance = ..Scalar(record, "provenance")
	If (provenance '= "") && (provenance '= "untrusted") Quit $Replace(..#REASONPROVENANCE, "{provenance}", $Extract(provenance, 1, 40))
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SourceItemId = ..Scalar(record, "itemId")
	Set item.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set item.Channel = ..Scalar(record, "channel")
	Set item.Provenance = "untrusted"
	Set item.Sender = ..Scalar(record, "sender")
	Set item.Subject = ..Scalar(record, "subject")
	Set item.Text = ..Scalar(record, "text")
	Set item.CatalogKey = ..Scalar(record, "catalogKey")
	Set item.Slots = $Select($IsObject(record.slots): record.slots.%ToJSON(), 1: ..Scalar(record, "slots"))
	Set watch = ""
	If case.%IsDefined("watch") {
		Set reason = ..WatchUp(case.%Get("watch"), .watch)
		If reason '= "" Quit reason
	}
	Set opened = 0
	Try {
		Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, item.SourceItemId, item.ItemId)
		If $$$ISOK(sc) {
			Set opened = 1
			Set ..%SuperSession = ..RunRef
			Set sc = ..Dispatch(item)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		If opened Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
		Do ..Unwatch(watch)
		Quit $SYSTEM.Status.GetOneStatusText(sc)
	}
	If $IsObject(watch) {
		If '$IsObject(..Watches) Set ..Watches = []
		Do ..Watches.%Push({"case": (name), "watch": (watch)})
	}
	Quit ""
}

/// Sets up the watch that a case declares: the reason it was not set up, or "" when it was, with the watch's stored fields in fields. A watch
/// that is not an object with a non-blank namespace and production is REASONWATCHSHAPE; one that WatchOps.EvalWatch refuses is REASONWATCH.
Method WatchUp(declared As %DynamicObject, Output fields As %DynamicObject) As %String [ Private ]
{
	Set fields = ""
	If '$IsObject(declared) || 'declared.%IsA("%Library.DynamicObject") Quit ..#REASONWATCHSHAPE
	Set namespace = ..Scalar(declared, "namespace"), production = ..Scalar(declared, "production")
	If ($ZStrip(namespace, "<>WC") = "") || ($ZStrip(production, "<>WC") = "") Quit ..#REASONWATCHSHAPE
	Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch(namespace, production, .fields)
	If $$$ISERR(sc) {
		Set fields = ""
		Quit $Replace(..#REASONWATCH, "{why}", $SYSTEM.Status.GetOneStatusText(sc))
	}
	Quit ""
}

/// Removes the watch row of the stored fields (WatchOps.Fields of the row); "" is no watch. The status of WatchOps.RemoveEvalWatch.
ClassMethod Unwatch(fields As %DynamicObject) As %Status [ Private ]
{
	If '$IsObject(fields) Quit $$$OK
	Quit ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(fields.%Get("Ref"))
}

/// The kinds that EvalIn sends, as the text of a reason: joined with a comma, and with "and" before the last one.
ClassMethod KindsText() As %String [ Private ]
{
	Set count = $Length(..#KINDS, ",")
	If count < 2 Quit ..#KINDS
	Quit $Replace($Piece(..#KINDS, ",", 1, count - 1), ",", ", ")_" and "_$Piece(..#KINDS, ",", count)
}

/// The one send of an item case: the Item to the target item, asynchronously, with no answer. Private; a test subclass overrides it.
Method Dispatch(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#TARGET, item)
}

/// The steps for one turn case (see the class description); the reason it was not sent, or "" when it was. A case that has no turn.text,
/// or an all-clear case whose checks is not an array, is refused before anything is saved. Otherwise the case's TurnResult and row are
/// saved, and a case that gets no Reply from Decide (or whose send throws) loses both again. A row that cannot be opened (the run already
/// has a row of that case) is refused with the error text, and only the case's own TurnResult is deleted: the row that is there stays.
Method SendTurn(case As %DynamicObject, kind As %String, name As %String) As %String [ Private ]
{
	Set turn = case.turn
	Set text = $Select($IsObject(turn) && turn.%IsA("%Library.DynamicObject"): ..Scalar(turn, "text"), 1: "")
	If $ZStrip(text, "*WC") = "" Quit ..#REASONNOTEXT
	Set recorded = ""
	If kind = ..#ALLCLEARKIND {
		Set checks = case.checks
		If '$IsObject(checks) || 'checks.%IsA("%Library.DynamicArray") Quit ..#REASONNOCHECKS
		Set recorded = checks.%ToJSON()
	}
	Set result = ##class(OcuTalon.Eval.Msg.TurnResult).%New()
	Set result.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set result.SourceItemId = name
	Set result.RecordedChecks = recorded
	Set sc = result.%Save()
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, name, result.ItemId)
	If $$$ISERR(sc) {
		Do ##class(OcuTalon.Eval.Msg.TurnResult).%DeleteId(result.%Id())
		Quit $SYSTEM.Status.GetOneStatusText(sc)
	}
	Set ..%SuperSession = ..RunRef
	Set reason = ""
	Try {
		Set reason = ..Converse(result, text, name)
	} Catch exception {
		Set reason = exception.DisplayString()
	}
	If reason '= "" Do ..Discard(result, name)
	Quit reason
}

/// Asks Decide for the turn, again after a Busy reply, then keeps the Reply in the TurnResult and sends the TurnResult to EvalSink. The
/// reason there was no Reply to keep, or "". The turn is asked at most BUSYMAX + 1 times, BUSYWAIT seconds apart; a Decide that is busy
/// every time ends the case as a fallback with the reason rate_limited, with no DecisionRef.
Method Converse(result As OcuTalon.Eval.Msg.TurnResult, text As %String, name As %String) As %String [ Private ]
{
	Set reply = ""
	For asks = 1:1:..#BUSYMAX + 1 {
		Kill reply
		Set sc = ..Ask(..TurnRequest(result.ItemId, text), .reply)
		If $$$ISERR(sc) Quit
		If '$IsObject($Get(reply)) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") Quit
		If 'reply.Busy Quit
		If asks '> ..#BUSYMAX Do ..Pause(..#BUSYWAIT)
	}
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	If '$IsObject($Get(reply)) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") Quit ..#REASONNOREPLY
	If reply.Busy {
		Set result.Fallback = 1
		Set result.FallbackReason = "rate_limited"
	} Else {
		Set result.DecisionRef = reply.DecisionRef
		Set result.ToolsRun = +reply.ToolsRun
		Set result.ReplyText = reply.Text
		Set result.Fallback = +reply.Fallback
		Set result.FallbackReason = reply.FallbackReason
		Do ..Render(result, reply.HostData)
	}
	Set sc = result.%Save()
	If $$$ISOK(sc) Set sc = ..Deliver(result)
	If $$$ISERR(sc) $$$LOGWARNING(..#LOGNOTDELIVERED_name_": "_$SYSTEM.Status.GetOneStatusText(sc))
	Quit ""
}

/// The request to Decide for a turn case (AD-6): a user turn of owner eval, in a fresh conversation, with no recap. The Input is what
/// Agent.Input renders from an Item of the same fields as a user's turn in the chat, so the model sees the turn as the product sends it.
Method TurnRequest(itemId As %String, text As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = itemId
	Set item.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set item.Channel = ..#TURNCHANNEL
	Set item.Provenance = "user"
	Set item.Text = text
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.Input = ##class(OcuTalon.Agent.Input).Render(item)
	Set request.ItemId = itemId
	Set request.Summary = ..FirstLine(text)
	Set request.OwnerRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set request.TraceRef = ..RunRef
	Set request.Channel = ..#TURNCHANNEL
	Set request.ThreadSessionId = ..%SessionId
	Set request.SessionMode = "fresh"
	Quit request
}

/// The first line of the text that is not blank, without the white space at its ends, cut to the 80 characters of a Summary.
ClassMethod FirstLine(text As %String) As %String [ Private ]
{
	Set text = $Translate(text, $Char(13), $Char(10))
	Set line = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $ZStrip($Piece(text, $Char(10), i), "<>WC")
		If line '= "" Quit
	}
	Quit $Extract(line, 1, 80)
}

/// Puts the catalog key and the rows that Checks.Render gives the check rows of the Reply's HostData in the TurnResult. A HostData that is
/// not a JSON object with an array checks, or that renders neither a key nor a row, adds nothing; one that cannot be read is logged.
Method Render(result As OcuTalon.Eval.Msg.TurnResult, hostData As %String) [ Private ]
{
	If hostData = "" Quit
	Try {
		Set data = ##class(%DynamicAbstractObject).%FromJSON(hostData)
		If ($ClassName(data) '= "%Library.DynamicObject") || (data.%GetTypeOf("checks") '= "array") Quit
		Set key = ##class(OcuTalon.Checks.Render).Render(data.checks, .rows)
		Set size = $Select($IsObject($Get(rows)): rows.%Size(), 1: 0)
		If (key = "") && (size = 0) Quit
		Set result.CatalogKey = key
		Set result.CheckRows = $Select(size > 0: rows.%ToJSON(), 1: "")
	} Catch exception {
		$$$LOGWARNING(..#LOGCHECKS_exception.DisplayString())
	}
}

/// Deletes the case's row and its TurnResult.
Method Discard(result As OcuTalon.Eval.Msg.TurnResult, name As %String) [ Private ]
{
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
	If $IsObject(result) && (result.%Id() '= "") Do ##class(OcuTalon.Eval.Msg.TurnResult).%DeleteId(result.%Id())
}

/// The call of a turn case to Decide: synchronous, for at most TURNWAIT seconds. A call that times out answers OK with no response. Private;
/// a test subclass overrides it.
Method Ask(request As OcuTalon.Bridge.Msg.Request, Output reply As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestSync(..#DECIDE, request, .reply, ..#TURNWAIT)
}

/// The send of a turn case's TurnResult to EvalSink, asynchronously, with no answer. Private; a test subclass overrides it.
Method Deliver(result As OcuTalon.Eval.Msg.TurnResult) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#SINK, result)
}

/// The wait before a Busy turn is asked again. Private; a test subclass overrides it.
Method Pause(seconds As %Integer) [ Private ]
{
	Hang seconds
}

/// The text of a string, number or boolean member of a JSON object; "" for a member that is missing, null, an object or an array. EvalSink
/// reads a Decision payload with it too.
ClassMethod Scalar(object As %DynamicObject, key As %String) As %String
{
	Set type = object.%GetTypeOf(key)
	Quit $Select((type = "string") || (type = "number") || (type = "boolean"): object.%Get(key), 1: "")
}

}
