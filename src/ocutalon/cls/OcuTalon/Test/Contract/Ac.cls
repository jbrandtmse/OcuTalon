/// Pins of Story 0.4's acceptance criteria that the contract oracles do not state by themselves (QA). The oracles of
/// Test.Msg.Contracts, Test.Bridge.Contracts and Test.Data.Tables are copies of the spec's tables, and each one checks only
/// the classes it lists. These tests read the compiled class dictionary and take their names from the epics AC and the
/// ADs, not from an oracle:
///   - TestNamedPropertiesExist: every property that the epics AC and AD-6, AD-26 and AD-32 name exists under that name;
///   - TestAcClassesAreCompiledAndPinned: every class the AC names is compiled and has an entry in an oracle, so a class
///     cannot leave its contract check by losing its entry;
///   - TestEveryStorageGlobalIsPrivate: all four storage globals of every registry class (data, id, index and stream) are
///     the registry global plus D, D, I and S, and resolve to the private database, not only the data and index globals;
///   - TestIncidentNoticeIsEmptyUntilTheNotice: an incident saves without a notice time and reads it back empty, and
///     its open variant is stored beside its state;
///   - TestCrossLaneSignatures: the cross-lane methods keep their parameter names and order and their return type, which
///     the other lane's callers rely on (Delivery.Record and FindByApproval are named by the AC; the cross-lane APIs of
///     AD-29, the extension accessor and the extension bases of AD-31 are pinned from Story 0.6 on, and the catalog renderer
///     of AD-32 and Data.Time.ForMessage from Story 0.9, and the Orders partner's Send from Story 0.10);
///   - TestTelegramStubHasAnAdapter: the stub is an inbound service with an adapter class.
/// The incident fixtures use a per-run Zz reference, and every row is deleted in the test and again in OnAfterAllTests.
Class OcuTalon.Test.Contract.Ac Extends OcuTalon.Test.Contract
{

/// The run's number, from ^OcuTalonTest("ContractAc","n"), which is never reset.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("ContractAc", "n"))
	Do ..RemoveIncident()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveIncident()
	Quit $$$OK
}

/// Every property that the epics AC and the ADs name on a contract class exists on it, under that name.
Method TestNamedPropertiesExist()
{
	Set classes = 0
	Set iterator = ..Read("Named").%GetIterator()
	While iterator.%GetNext(.class, .names) {
		Set classes = classes + 1
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), class_" is compiled")
		For i = 1:1:$Length(names, ",") {
			Set name = $Piece(names, ",", i)
			Do $$$AssertTrue(##class(%Dictionary.CompiledProperty).%ExistsId(class_"||"_name), class_" has the property "_name)
		}
	}
	Do $$$AssertTrue(classes > 0, "the named properties are read")
}

/// Every class that the epics AC names is compiled and is listed in one of the three oracles.
Method TestAcClassesAreCompiledAndPinned()
{
	Kill pinned
	Set oracles = $ListFromString(..#ORACLES)
	Set position = 0
	While $ListNext(oracles, position, oracle) {
		Set iterator = ..Read("Contracts", oracle).%GetIterator()
		While iterator.%GetNext(.class) {
			Set pinned(class) = oracle
		}
	}
	Set count = 0
	Set iterator = ..Read("Classes").%GetIterator()
	While iterator.%GetNext(, .class) {
		Set count = count + 1
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), class_" is compiled")
		Do $$$AssertTrue($Data(pinned(class)), class_" has an entry in a contract oracle")
	}
	Do $$$AssertTrue(count >= 47, "the epics AC name at least 47 classes: "_count)
}

/// Every registry class keeps all four of its storage globals under its registry global, and they resolve to the private
/// database: the data, id, index and stream globals. The registry rows are those of Test.Data.Tables.
Method TestEveryStorageGlobalIsPrivate()
{
	Set private = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.Zz")
	Set data = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonZzUnmapped")
	Do $$$AssertTrue(private '= data, "the private and data databases differ")
	Set count = 0
	Set iterator = ..Read("Registry", "OcuTalon.Test.Data.Tables").%GetIterator()
	While iterator.%GetNext(, .row) {
		Set count = count + 1
		Set class = row.class
		Set storage = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default")
		If '$IsObject(storage) {
			Do $$$AssertTrue(0, class_" has a Storage Default block")
			Continue
		}
		Set locations("DataLocation") = row.global_"D"
		Set locations("IdLocation") = row.global_"D"
		Set locations("IndexLocation") = row.global_"I"
		Set locations("StreamLocation") = row.global_"S"
		Set kind = ""
		For {
			Set kind = $Order(locations(kind), 1, expected)
			Quit:kind=""
			Set actual = $Property(storage, kind)
			Do $$$AssertEquals(actual, expected, class_" "_kind_" is "_expected)
			Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, actual), private, class_" "_kind_" "_actual_" resolves to the private database")
		}
	}
	Do $$$AssertTrue(count >= 22, "the registry holds at least 22 rows: "_count)
}

/// An incident has no notice time until the notice: a new one has none, one saves without it and reads it back empty.
/// The open variant is stored beside the state.
Method TestIncidentNoticeIsEmptyUntilTheNotice()
{
	Set fresh = ##class(OcuTalon.Data.Incident).%New()
	Do $$$AssertEquals(fresh.NoticedAt, "", "a new incident has no notice time")
	Do $$$AssertEquals(fresh.OpenVariant, "", "a new incident has no open variant")
	Do $$$AssertEquals(fresh.ClosedAt, "", "a new incident is not closed")
	Set fresh.Ref = ..IncidentRef()
	Set fresh.State = "open"
	Set fresh.OpenVariant = "no_fix"
	Set sc = fresh.%Save()
	Do $$$AssertStatusOK(sc, "an incident without a notice time saves")
	Set id = fresh.%Id()
	Kill fresh
	If $$$ISOK(sc) {
		Set row = ##class(OcuTalon.Data.Incident).%OpenId(id)
		Do $$$AssertEquals(row.NoticedAt, "", "the notice time is still empty when it is read back")
		Do $$$AssertEquals(row.State, "open", "the state is stored")
		Do $$$AssertEquals(row.OpenVariant, "no_fix", "the open variant is stored beside the state")
		Set row.NoticedAt = "2026-10-19T06:57:07Z"
		Do $$$AssertStatusOK(row.%Save(), "the notice time is set when the notice is sent")
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).%OpenId(id)
		Do $$$AssertEquals(row.NoticedAt, "2026-10-19T06:57:07Z", "the notice time is stored in the UTC form")
		Kill row
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Incident).%DeleteId(id), "the incident is deleted")
	}
}

/// The cross-lane methods keep the names and the order of their parameters, which positional callers rely on, and their
/// return type. A method may gain optional parameters at the end.
Method TestCrossLaneSignatures()
{
	Set count = 0
	Set iterator = ..Read("Signatures").%GetIterator()
	While iterator.%GetNext(, .signature) {
		Set count = count + 1
		Set id = signature.class_"."_signature.method
		Set method = ##class(%Dictionary.CompiledMethod).%OpenId(signature.class_"||"_signature.method)
		If '$IsObject(method) {
			Do $$$AssertTrue(0, id_" exists")
			Continue
		}
		Do $$$AssertEquals(method.ClassMethod, 1, id_" is a class method")
		Set expected = $ListFromString(signature.args)
		Set actual = ..ParameterNames(method.FormalSpec)
		Set prefix = ""
		For i = 1:1:$ListLength(expected) {
			Set prefix = prefix _ $ListBuild($ListGet(actual, i))
		}
		Do $$$AssertEquals(..Join(prefix), ..Join(expected), id_" takes ("_signature.args_") in that order")
		Do $$$AssertEquals(..FullName(method.ReturnType), ..FullName(signature.returns), id_" returns "_signature.returns)
	}
	Do $$$AssertTrue(count >= 48, "the signatures are read: "_count)
}

/// The Telegram stub is an inbound service, and its adapter is a class (the Telegram epic replaces the value).
Method TestTelegramStubHasAnAdapter()
{
	Set adapter = $Parameter("OcuTalon.Channel.Telegram.In", "ADAPTER")
	Do $$$AssertTrue(adapter '= "", "the stub declares an adapter")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(adapter), "the adapter "_adapter_" is a class")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Channel.Telegram.In", "%Extends", "Ens.BusinessService"), "the stub is a business service")
}

/// The reference of this run's incident.
Method IncidentRef() As %String [ Private ]
{
	Quit "Zz"_..Number_"i"
}

/// Deletes this run's incident fixture, if a failed test left one.
Method RemoveIncident() [ Private ]
{
	If ##class(OcuTalon.Data.Incident).RefIndexExists(..IncidentRef(), .id) Do ##class(OcuTalon.Data.Incident).%DeleteId(id)
}

/// The elements of a list joined by commas; "" for an empty list.
ClassMethod Join(list As %List) As %String [ Private ]
{
	Quit $Select($ListLength(list) = 0: "", 1: $ListToString(list, ","))
}

/// The names of the parameters of a formal specification, in order, as a list.
ClassMethod ParameterNames(spec As %String) As %List [ Private ]
{
	Set names = ""
	For i = 1:1:$Length(spec, ",") {
		Set name = $Piece($Piece(spec, ",", i), ":", 1)
		If name '= "" Set names = names _ $ListBuild(name)
	}
	Quit names
}

/// The properties that the epics AC and the ADs name, by class (AD-6, AD-26, AD-32).
XData Named [ MimeType = application/json ]
{
{
 "OcuTalon.Msg.Item": "ItemId,SourceItemId,SessionRef,CatalogKey,Slots",
 "OcuTalon.Msg.ItemDecision": "ItemId,SourceItemId,OwnerRef,Channel,Summary,DecisionRef,Outcome,Fallback,FallbackReason,CatalogKey,Slots",
 "OcuTalon.Msg.Notification": "SessionRef,ChatRef,Kind,CatalogKey,Slots,ApprovalRef,IncidentRef,DecisionRef",
 "OcuTalon.Msg.Outbound": "SessionRef,ChatRef,OriginChannel",
 "OcuTalon.Msg.Command": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.IncidentCommand": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.SetReminder": "Origin,IdempotencyKey,SessionRef,Text,DueAt,DelaySeconds,LocalDueAt",
 "OcuTalon.Msg.Command.CancelReminder": "Origin,IdempotencyKey,SessionRef,ReminderRef",
 "OcuTalon.Msg.Command.ListReminders": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.StartWatch": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.StopWatch": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.Dismiss": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.SetDemoMode": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.Pair": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.Unpair": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Msg.Command.EndSession": "Origin,IdempotencyKey,SessionRef",
 "OcuTalon.Live.Payload.Decision": "ItemId,ItemSummary",
 "OcuTalon.Bridge.Msg.Request": "Input,Kind,Provenance,ItemId,Summary,DecisionRef,OwnerRef,TraceRef,Channel,ThreadSessionId,SessionMode,SeedText,SystemNote",
 "OcuTalon.Bridge.Msg.DecisionResponse": "DecisionRef,Outcome,Payload,Fallback,FallbackReason",
 "OcuTalon.Bridge.Msg.Reply": "Text,Tainted,SessionRotated,ToolsRun,SessionBroken,Busy,HostData,InputTokens,OutputTokens,CacheReadTokens,CacheWriteTokens,CostUSD,Model,AgentStepCount,DurationMs,DecisionRef,Outcome,Reasons,Confidence,Fallback,FallbackReason",
 "OcuTalon.Bridge.Data.Decision": "Summary,TraceSessionId",
 "OcuTalon.Bridge.Data.ApprovalRequest": "DryRun",
 "OcuTalon.Data.Incident": "NoticedAt,OpenVariant,State",
 "OcuTalon.Data.SimMessage": "ItemId"
}
}

/// The classes that the epics AC name for Story 0.4 (the enumeration classes are checked by Test.Msg.Contracts).
XData Classes [ MimeType = application/json ]
{
[
 "OcuTalon.Msg.Item",
 "OcuTalon.Msg.ItemDecision",
 "OcuTalon.Msg.Notification",
 "OcuTalon.Msg.Outbound",
 "OcuTalon.Msg.Tick",
 "OcuTalon.Msg.Command",
 "OcuTalon.Msg.IncidentCommand",
 "OcuTalon.Msg.CommandResult",
 "OcuTalon.Msg.Command.SetReminder",
 "OcuTalon.Msg.Command.CancelReminder",
 "OcuTalon.Msg.Command.ListReminders",
 "OcuTalon.Msg.Command.StartWatch",
 "OcuTalon.Msg.Command.StopWatch",
 "OcuTalon.Msg.Command.Dismiss",
 "OcuTalon.Msg.Command.SetDemoMode",
 "OcuTalon.Msg.Command.Pair",
 "OcuTalon.Msg.Command.Unpair",
 "OcuTalon.Msg.Command.EndSession",
 "OcuTalon.Live.Payload.Decision",
 "OcuTalon.Bridge.Msg.Request",
 "OcuTalon.Bridge.Msg.Result",
 "OcuTalon.Bridge.Msg.DecisionResponse",
 "OcuTalon.Bridge.Msg.Reply",
 "OcuTalon.Bridge.Msg.DecisionPayload",
 "OcuTalon.Bridge.Msg.AgentStep",
 "OcuTalon.Bridge.Data.Decision",
 "OcuTalon.Bridge.Data.ApprovalRequest",
 "OcuTalon.Bridge.Data.Usage",
 "OcuTalon.Bridge.Data.Price",
 "OcuTalon.Bridge.Data.ConversationLink",
 "OcuTalon.Bridge.Data.ModelFamily",
 "OcuTalon.Data.Session",
 "OcuTalon.Data.AddressCounter",
 "OcuTalon.Data.StatusMark",
 "OcuTalon.Data.GuideState",
 "OcuTalon.Data.BreakFeedRun",
 "OcuTalon.Data.Pairing",
 "OcuTalon.Data.Turn",
 "OcuTalon.Data.SimMessage",
 "OcuTalon.Data.Delivery",
 "OcuTalon.Data.Reminder",
 "OcuTalon.Data.Setting",
 "OcuTalon.Data.BackgroundCheck",
 "OcuTalon.Data.WatchMark",
 "OcuTalon.Data.Incident",
 "OcuTalon.Data.FailureGroup",
 "OcuTalon.Data.FixRun"
]
}

/// The cross-lane methods: class, method, the leading parameters in order, and the return type.
XData Signatures [ MimeType = application/json ]
{
[
 {"class": "OcuTalon.Data.Delivery", "method": "Record", "args": "ownerRef,channel,channelMessageId,approvalRef", "returns": "%Status"},
 {"class": "OcuTalon.Data.Delivery", "method": "FindByApproval", "args": "approvalRef,channel,ownerRef", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Msg.Reply", "method": "NewBusy", "args": "", "returns": "OcuTalon.Bridge.Msg.Reply"},
 {"class": "OcuTalon.Bridge.Ids", "method": "NewRef", "args": "", "returns": "%String"},
 {"class": "OcuTalon.Data.Time", "method": "NowUtc", "args": "", "returns": "%String"},
 {"class": "OcuTalon.Data.Time", "method": "ToLocal", "args": "utc", "returns": "%String"},
 {"class": "OcuTalon.Data.Time", "method": "Zone", "args": "", "returns": "%String"},
 {"class": "OcuTalon.Data.Time", "method": "ForMessage", "args": "utc,now", "returns": "%String"},
 {"class": "OcuTalon.Data.Setting", "method": "Get", "args": "key,default", "returns": "%String"},
 {"class": "OcuTalon.Data.Setting", "method": "Seed", "args": "key,value", "returns": "%Status"},
 {"class": "OcuTalon.Data.StatusMark", "method": "Record", "args": "mark,value", "returns": "%Status"},
 {"class": "OcuTalon.Data.StatusMark", "method": "Get", "args": "mark", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Audit", "method": "Write", "args": "type,data,description", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Audit", "method": "Events", "args": "", "returns": "%List"},
 {"class": "OcuTalon.Bridge.Audit", "method": "Record", "args": "type,data", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Audit", "method": "Shape", "args": "type", "returns": "%List"},
 {"class": "OcuTalon.Channel.Telegram.In", "method": "Included", "args": "", "returns": "%Boolean"},
 {"class": "OcuTalon.Bridge.Approval", "method": "Raise", "args": "request,*ref", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Approval", "method": "Answer", "args": "ref,action,channel,irisUser,sessionRef,*winner", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Approval", "method": "Expire", "args": "ref", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Approval", "method": "Cancel", "args": "ref,sinkClass,channel,irisUser,sessionRef", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Approval", "method": "StartExecution", "args": "ref", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Approval", "method": "FinishExecution", "args": "ref,result", "returns": "%Status"},
 {"class": "OcuTalon.Agent.Input", "method": "Render", "args": "item", "returns": "%String"},
 {"class": "OcuTalon.Checks.Render", "method": "Render", "args": "results,*rows", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Context", "method": "Begin", "args": "request,superSession", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Context", "method": "End", "args": "", "returns": ""},
 {"class": "OcuTalon.Bridge.Context", "method": "Active", "args": "", "returns": "%Boolean"},
 {"class": "OcuTalon.Bridge.Context", "method": "Current", "args": "", "returns": "OcuTalon.Bridge.Context"},
 {"class": "OcuTalon.Bridge.Context", "method": "Put", "args": "name,value", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Budget", "method": "State", "args": "", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Bridge.Keys", "method": "Status", "args": "agent", "returns": "%Boolean"},
 {"class": "OcuTalon.Bridge.Timeouts", "method": "Derive", "args": "timer", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Bridge.ConfigStore", "method": "Merge", "args": "entry,fields", "returns": "%Status"},
 {"class": "OcuTalon.Data.Session", "method": "Recipients", "args": "ownerRef,incidentRef", "returns": "%List"},
 {"class": "OcuTalon.Data.Ownership", "method": "TurnCost", "args": "turnRef", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Data.Ownership", "method": "RunCost", "args": "sessionRef,since", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Core.Commands", "method": "Submit", "args": "command,origin,*result", "returns": "%Status"},
 {"class": "OcuTalon.Core.Allowance", "method": "TryConsume", "args": "sessionRef,channel,text,*retryAt,*firstRefusal", "returns": "%Boolean"},
 {"class": "OcuTalon.Bridge.Ext.Accessor", "method": "ClassFor", "args": "setting,production,item,*sc", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Ext.Accessor", "method": "Check", "args": "setting,class", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Ext.HostSink", "method": "OnEvent", "args": "type,ownerRef,payload", "returns": "%Status"},
 {"class": "OcuTalon.Bridge.Ext.HostSink", "method": "RefPayload", "args": "ref", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Bridge.Ext.HostSink", "method": "TurnStepPayload", "args": "decisionRef,label", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Bridge.Ext.HostSink", "method": "BudgetCappedPayload", "args": "day", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Bridge.Ext.ReplyFilter", "method": "Filter", "args": "text", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Ext.Classification", "method": "Classify", "args": "source,name,arguments", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Operation.AgentRunner", "method": "ResolveModel", "args": "item,production", "returns": "%String"},
 {"class": "OcuTalon.Bridge.Compaction", "method": "Prompt", "args": "", "returns": "%String"},
 {"class": "OcuTalon.Msg.Catalog", "method": "Render", "args": "key,slots,channel,*sc", "returns": "%String"},
 {"class": "OcuTalon.Msg.Catalog", "method": "RenderAt", "args": "key,slots,channel,now,onlineDemo,*sc", "returns": "%String"},
 {"class": "OcuTalon.Msg.Catalog", "method": "Entry", "args": "key,*sc", "returns": "%DynamicObject"},
 {"class": "OcuTalon.Demo.Orders.Partner", "method": "Send", "args": "count,dateFormat,traceRef,orderDate", "returns": "%Status"}
]
}

}
