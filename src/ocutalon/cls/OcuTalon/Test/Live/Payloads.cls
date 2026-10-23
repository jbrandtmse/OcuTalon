/// Tests of the live-event payload classes (matrix rows 4 to 6): the event table, the contracts of the 27 payload
/// and part classes (Story 0.5 adds 25, Story 2.6 the parts Cost and CheckRow), every JSON key, the incident payload with its
/// nested shapes and its FromRow builder, the FromRow builders of the chat message, reminder, approval and decision payloads
/// (Story 2.2), which build from unsaved rows, and the chat message's shown decision, turn cost and check rows (Story 2.6),
/// which build from fixture rows, and which decision a turn shows (from unsaved rows). The fixture incident rows are ZzPay<n> rows of Data.Incident, with n from
/// ^OcuTalonTest("LivePayloads","n") (never reset); OnBeforeAllTests and OnAfterAllTests delete every row of that name.
Class OcuTalon.Test.Live.Payloads Extends OcuTalon.Test.Contract
{

/// The event table of the spine: each type and the short name of its payload class.
Parameter EXPECTED = "chat.message:ChatMessage,notification:Notification,phone:Phone,mailbox:Mailbox,decision:Decision,approval:Approval,turn.step:TurnStep,reminder:Reminder,pairing:Pairing,status:Status,reset:Reset,breakfeed.progress:BreakFeedProgress,guide.state:GuideState,incident:Incident,watch.progress:WatchProgress,check:Check";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("LivePayloads", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// Publish's TYPES is exactly the spine's 16 types, each mapped to its class, and the direct classes of
/// OcuTalon.Live.Payload are exactly those 16, each a %RegisteredObject and %JSON.Adaptor.
Method TestEventTable()
{
	Set expected = $ListFromString(..#EXPECTED)
	Do $$$AssertEquals($ListLength(expected), 16, "the spine has 16 types")
	Do $$$AssertEquals($Length($Parameter("OcuTalon.Live.Publish", "TYPES"), ","), 16, "TYPES holds 16 pairs")
	Do $$$AssertEquals($Parameter("OcuTalon.Live.Publish", "TYPES"), ..#EXPECTED, "TYPES is the spine's event table")
	Set position = 0
	While $ListNext(expected, position, pair) {
		Set type = $Piece(pair, ":", 1)
		Set class = "OcuTalon.Live.Payload."_$Piece(pair, ":", 2)
		Do $$$AssertEquals(##class(OcuTalon.Live.Publish).PayloadClass(type), class, type_" maps to "_class)
		Set wanted(class) = ""
	}
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).PayloadClass("zz.type"), "", "an unknown type maps to nothing")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).PayloadClass(""), "", "an empty type maps to nothing")

	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT ID FROM %Dictionary.CompiledClass WHERE ID %STARTSWITH 'OcuTalon.Live.Payload.'"), "the query is prepared")
	Set result = statement.%Execute()
	While result.%Next() {
		Set class = result.%GetData(1)
		If $Length(class, ".") '= 4 Continue
		Set found(class) = ""
		Do $$$AssertTrue($ClassMethod(class, "%Extends", "%RegisteredObject") && $ClassMethod(class, "%Extends", "%JSON.Adaptor"), class_" is a %RegisteredObject and a %JSON.Adaptor")
		Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(class)
		Do $$$AssertEquals(..FullNames(compiled.Super), "%Library.RegisteredObject,%JSON.Adaptor", class_" extends exactly those two")
	}
	Set class = ""
	For {
		Set class = $Order(wanted(class))
		Quit:class=""
		Do $$$AssertTrue($Data(found(class)), class_" is in the package")
	}
	Set class = ""
	For {
		Set class = $Order(found(class))
		Quit:class=""
		Do $$$AssertTrue($Data(wanted(class)), class_" is one of the 16")
	}
}

/// Every payload and part class has exactly its contract, every JSON key is the property name with a lower-case
/// first letter, and the two closed lists are the spine's.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Set classes = 0
	Set iterator = ..Read("Contracts").%GetIterator()
	While iterator.%GetNext(.class) {
		Set classes = classes + 1
		Set key = ""
		For {
			Set property = ##class(%Dictionary.CompiledClass).%OpenId(class).Properties.GetNext(.key)
			Quit:key=""
			If ..Inherited(property.Origin) Continue
			Set name = property.Name
			Do $$$AssertEquals(property.Parameters.GetAt("%JSONFIELDNAME"), $ZConvert($Extract(name), "L")_$Extract(name, 2, *), class_"."_name_" has a camelCase JSON key")
		}
	}
	Do $$$AssertEquals(classes, 27, "the contracts hold the 27 payload and part classes")
	Do $$$AssertEquals($Parameter("OcuTalon.Live.Payload.WatchProgress", "STAGES"), "noticed,settling,diagnosing", "the watch stages")
	Do $$$AssertEquals($Parameter("OcuTalon.Live.Payload.Status", "CONDITIONS"), "allowance,dailyCap,noModelKey,heartbeatStalled,telegramPaused,resetSoon", "the six status conditions")
}

/// A fully set incident payload exports the AC's keys, nested as the contracts give.
Method TestIncidentPayload()
{
	Set payload = ##class(OcuTalon.Live.Payload.Incident).%New()
	Set payload.Ref = "ZzPay"_..Number
	Set payload.State = "awaiting_approval"
	Set payload.OpenVariant = "fallback"
	Set payload.Count = 9
	Set payload.NoticeCount = 7
	Set payload.FirstAt = "2026-10-19T10:00:00Z"
	Set payload.LastAt = "2026-10-19T10:00:30Z"
	Set payload.ItemNoun = ##class(OcuTalon.Live.Payload.Part.ItemNoun).%New()
	Set payload.ItemNoun.One = "order"
	Set payload.ItemNoun.Other = "orders"
	Set payload.Cause = "A bad field"
	Set payload.FixSummary = "Fix the field"
	Set payload.CauseCategory = "data"
	Set payload.Element = "OrderIn"
	Set payload.Fallback = 1
	Set payload.FallbackReason = "timeout"
	Set payload.DecisionRef = "ZzDec"_..Number
	For i = 1:1:2 {
		Set group = ##class(OcuTalon.Live.Payload.Part.IncidentGroup).%New()
		Set group.ItemName = "Item "_i
		Set group.Count = i
		Set group.ErrorSummary = "Error "_i
		Set group.FirstAt = "2026-10-19T10:00:0"_i_"Z"
		Do payload.Groups.Insert(group)
	}
	Set request = ##class(OcuTalon.Live.Payload.Part.IncidentRequest).%New()
	Set request.Ref = "ZzReq"_..Number
	Set request.State = "done"
	Set request.Result = ##class(OcuTalon.Live.Payload.Part.IncidentRequestResult).%New()
	Set request.Result.Total = 6
	Set request.Result.Resent = 5
	Set request.Result.Completed = 3
	Set request.Result.FailedAgain = 2
	Set request.Result.Skipped = 1
	Set request.Result.Interrupted = 0
	Set request.Result.Reason = "none"
	Do payload.Requests.Insert(request)
	Set payload.Evidence = ##class(OcuTalon.Live.Payload.Part.IncidentEvidence).%New()
	Set payload.Evidence.SampleHeaderId = 4711
	Set payload.Evidence.SampleError = "Sample error"
	For i = 1:1:2 {
		Set item = ##class(OcuTalon.Live.Payload.Part.IncidentEvidenceItem).%New()
		Set item.ItemName = "Item "_i
		Set item.Count = i
		Set item.FirstAt = "2026-10-19T10:00:0"_i_"Z"
		Set item.LastAt = "2026-10-19T10:00:1"_i_"Z"
		Do payload.Evidence.Items.Insert(item)
	}
	Set payload.TraceTargets = ##class(OcuTalon.Live.Payload.Part.IncidentTraceTargets).%New()
	For name = "Diagnosis", "Sample", "FirstFailure" {
		Set target = ##class(OcuTalon.Live.Payload.Part.TraceTarget).%New()
		Set target.TraceHeaderId = $Length(name)
		Set target.TraceNamespace = "OCUORDERS"
		Set $Property(payload.TraceTargets, name) = target
	}

	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the payload exports")
	Set object = ##class(%DynamicObject).%FromJSON(json)
	Do $$$AssertEquals(object.ref, "ZzPay"_..Number, "ref")
	Do $$$AssertEquals(object.openVariant, "fallback", "openVariant")
	Do $$$AssertEquals(object.noticeCount, 7, "noticeCount")
	Do $$$AssertEquals(object.count, 9, "count")
	Do $$$AssertEquals(object.firstAt, "2026-10-19T10:00:00Z", "firstAt")
	Do $$$AssertEquals(object.itemNoun.one, "order", "itemNoun.one")
	Do $$$AssertEquals(object.itemNoun.other, "orders", "itemNoun.other")
	Do $$$AssertEquals(object.fixSummary, "Fix the field", "fixSummary")
	Do $$$AssertEquals(object.causeCategory, "data", "causeCategory")
	Do $$$AssertEquals(object.fallback, 1, "fallback is true")
	Do $$$AssertEquals(object.%GetTypeOf("fallback"), "boolean", "fallback is a JSON boolean")
	Do $$$AssertEquals(object.fallbackReason, "timeout", "fallbackReason")
	Do $$$AssertEquals(object.decisionRef, "ZzDec"_..Number, "decisionRef")
	Do $$$AssertEquals(object.groups.%Size(), 2, "two groups")
	Do $$$AssertEquals(object.groups.%Get(1).errorSummary, "Error 2", "groups[1].errorSummary")
	Do $$$AssertEquals(object.requests.%Size(), 1, "one request")
	Do $$$AssertEquals(object.requests.%Get(0).state, "done", "requests[0].state")
	Do $$$AssertEquals(object.requests.%Get(0).result.failedAgain, 2, "requests[0].result.failedAgain")
	Do $$$AssertEquals(object.requests.%Get(0).result.interrupted, 0, "requests[0].result.interrupted")
	Do $$$AssertEquals(object.evidence.sampleHeaderId, 4711, "evidence.sampleHeaderId")
	Do $$$AssertEquals(object.evidence.items.%Size(), 2, "two evidence items")
	Do $$$AssertEquals(object.evidence.items.%Get(1).lastAt, "2026-10-19T10:00:12Z", "evidence.items[1].lastAt")
	Do $$$AssertEquals(object.traceTargets.firstFailure.traceHeaderId, 12, "traceTargets.firstFailure.traceHeaderId")
	Do $$$AssertEquals(object.traceTargets.diagnosis.traceNamespace, "OCUORDERS", "traceTargets.diagnosis.traceNamespace")
	Do $$$AssertEquals(object.traceTargets.sample.traceHeaderId, 6, "traceTargets.sample.traceHeaderId")
}

/// FromRow copies every row-backed field of a Data.Incident row, reads the item noun from its JSON, and leaves
/// groups, requests, evidence and traceTargets absent. A row without an item noun, or with a broken one, gives
/// no itemNoun.
Method TestFromRow()
{
	Set row = ##class(OcuTalon.Data.Incident).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = "ZzPay"_..Number
	Set row.Namespace = "OCUORDERS"
	Set row.Production = "Zz.Production"
	Set row.State = "open"
	Set row.OpenVariant = "no_fix"
	Set row.Count = 12
	Set row.NoticeCount = 10
	Set row.FirstAt = "2026-10-19T09:00:00Z"
	Set row.LastAt = "2026-10-19T09:01:00Z"
	Set row.ItemNoun = {"one": "claim", "other": "claims"}.%ToJSON()
	Set row.Cause = "A cause"
	Set row.CauseCategory = "config"
	Set row.Element = "ClaimsIn"
	Set row.FixSummary = "A fix"
	Set row.Fallback = 1
	Set row.FallbackReason = "model_error"
	Set row.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceHeaderId = 99
	Do $$$AssertStatusOK(row.%Save(), "the fixture row is saved")

	Set payload = ##class(OcuTalon.Live.Payload.Incident).FromRow(row)
	Do $$$AssertEquals($ClassName(payload), "OcuTalon.Live.Payload.Incident", "FromRow builds an incident payload")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "it exports")
	Set object = ##class(%DynamicObject).%FromJSON(json)
	Do $$$AssertEquals(object.ref, row.Ref, "ref")
	Do $$$AssertEquals(object.state, "open", "state")
	Do $$$AssertEquals(object.openVariant, "no_fix", "openVariant")
	Do $$$AssertEquals(object.count, 12, "count")
	Do $$$AssertEquals(object.noticeCount, 10, "noticeCount")
	Do $$$AssertEquals(object.firstAt, "2026-10-19T09:00:00Z", "firstAt")
	Do $$$AssertEquals(object.lastAt, "2026-10-19T09:01:00Z", "lastAt")
	Do $$$AssertEquals(object.cause, "A cause", "cause")
	Do $$$AssertEquals(object.fixSummary, "A fix", "fixSummary")
	Do $$$AssertEquals(object.causeCategory, "config", "causeCategory")
	Do $$$AssertEquals(object.element, "ClaimsIn", "element")
	Do $$$AssertEquals(object.fallback, 1, "fallback")
	Do $$$AssertEquals(object.fallbackReason, "model_error", "fallbackReason")
	Do $$$AssertEquals(object.decisionRef, row.DecisionRef, "decisionRef")
	Do $$$AssertEquals(object.itemNoun.one, "claim", "itemNoun.one")
	Do $$$AssertEquals(object.itemNoun.other, "claims", "itemNoun.other")
	For key = "groups", "requests", "evidence", "traceTargets" {
		Do $$$AssertEquals(object.%IsDefined(key), 0, key_" is not in the payload")
	}

	Set row.ItemNoun = ""
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Incident).FromRow(row).ItemNoun, "", "no item noun in the row gives none")
	Set row.ItemNoun = "not json"
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Incident).FromRow(row).ItemNoun, "", "a broken item noun gives none")
}

/// A turn's chat message carries its shown decision (the triage decision, or the reply decision of a fallback) as the decision
/// payload, the turn's cost as the sum of both decisions' usage, and the check key and rows: the rows of the JSON that are
/// objects, in order, and none for text that is not a JSON array. A decision the session does not own, and a row with no
/// session, give no decision and no cost.
Method TestChatMessageCarriesItsDecision()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set session = $ClassMethod(fixture, "Session", "zzpay"_..Number)
	Set other = $ClassMethod(fixture, "Session", "zzpayother"_..Number)
	Set triage = $ClassMethod(fixture, "Decision", session, "decide", "2030-01-01T10:00:00Z", {"Outcome": "act", "Reasons": "zz reason", "Confidence": 0.92, "InputTokens": 1000, "OutputTokens": 300, "CostUSD": 0.0003, "Model": "claude-haiku-5-5"})
	Set reply = $ClassMethod(fixture, "Decision", session, "turn", "2030-01-01T10:00:05Z", {"Outcome": "tellnow", "Fallback": 1, "FallbackReason": "timeout", "CostUSD": 0.0005})
	Set theirs = $ClassMethod(fixture, "Decision", other, "decide")
	Do $ClassMethod(fixture, "Usage", triage, session, {"InputTokens": 1000, "OutputTokens": 300, "CacheReadTokens": 20, "CacheWriteTokens": 4, "CostUSD": 0.0003})
	Do $ClassMethod(fixture, "Usage", reply, session, {"InputTokens": 84, "OutputTokens": 12, "CostUSD": 0.0005})
	Set ref = $ClassMethod(fixture, "Turn", session, "2030-01-01T10:00:00Z")
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
	Set row.TriageDecisionRef = triage
	Set row.TurnDecisionRef = reply
	Set row.CheckKey = "checks.everythingElsePassed"
	Set row.CheckRows = "[{""result"":""passed"",""entry"":""Orders production"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""},""skipped"",5,null,[1],{""result"":""failed"",""entry"":""Warehouse queue"",""finding"":""zz 12 waiting"",""checkedAt"":""2030-01-01T10:01:00Z"",""other"":""ignored""}]"
	Do $$$AssertStatusOK(row.%Save(), "the turn has both decisions and its check rows")

	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Set expected = ##class(OcuTalon.Live.Payload.Decision).FromRow(##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(triage))
	Do expected.%JSONExportToString(.expectedJson)
	Do payload.Decision.%JSONExportToString(.actualJson)
	Do $$$AssertEquals(actualJson, expectedJson, "the decision is Decision.FromRow of the triage decision")
	Do $$$AssertEquals(payload.Decision.Ref_"|"_payload.Decision.Outcome, triage_"|act", "which is the row ShownDecisionRef names")
	Do $$$AssertEquals(payload.TurnCost.InputTokens_"|"_payload.TurnCost.OutputTokens_"|"_payload.TurnCost.CacheReadTokens_"|"_payload.TurnCost.CacheWriteTokens_"|"_payload.TurnCost.CostUSD, "1084|312|20|4|.0008", "the turn's cost is the sum of both decisions' usage")
	Do $$$AssertEquals(payload.CheckKey_"|"_payload.Checks.Count(), "checks.everythingElsePassed|2", "the check key and the two rows that are objects")
	Set first = payload.Checks.GetAt(1), second = payload.Checks.GetAt(2)
	Do $$$AssertEquals(first.Result_"|"_first.Entry_"|"_first.Finding_"|"_first.CheckedAt, "passed|Orders production||2030-01-01T10:00:00Z", "the first row")
	Do $$$AssertEquals(second.Result_"|"_second.Entry_"|"_second.Finding_"|"_second.CheckedAt, "failed|Warehouse queue|zz 12 waiting|2030-01-01T10:01:00Z", "the second row, without the member it does not know")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the payload exports")
	Set exported = ##class(%DynamicObject).%FromJSON(json)
	Do $$$AssertEquals(exported.decision.ref_"|"_exported.turnCost.inputTokens_"|"_exported.checkKey_"|"_exported.checks.%Size(), triage_"|1084|checks.everythingElsePassed|2", "the JSON nests the decision, the cost and the rows under their own names")

	Set row.ReplyCatalogKey = "conversation.turnFallback"
	Set row.FallbackReason = "timeout"
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Do $$$AssertEquals(payload.Decision.Ref_"|"_payload.Decision.Fallback_"|"_payload.Decision.FallbackReason, reply_"|1|timeout", "a fallback reply shows the reply decision")
	Do $$$AssertEquals(payload.TurnCost.CostUSD, .0008, "with the same turn cost")

	Set row.TriageDecisionRef = theirs
	Set row.ReplyCatalogKey = ""
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Do $$$AssertEquals($IsObject(payload.Decision)_"|"_$IsObject(payload.TurnCost), "0|0", "a decision of another session is not shown, nor a cost for it")
	Set row.TriageDecisionRef = "zzmissing"_..Number
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Do $$$AssertEquals($IsObject(payload.Decision)_"|"_$IsObject(payload.TurnCost), "0|0", "nor one that does not exist")
	Do $$$AssertEquals(payload.CheckKey_"|"_payload.Checks.Count(), "checks.everythingElsePassed|2", "while the check rows stay")

	For text = "not json", "{""result"":""passed""}", "[", "" {
		Set row.CheckRows = text
		Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
		Do $$$AssertEquals(payload.Checks.Count(), 0, "check rows of '"_text_"' give no row")
	}

	Set bare = ##class(OcuTalon.Data.Turn).%New()
	Set bare.Ref = "ZzBare"_..Number
	Set bare.TriageDecisionRef = triage
	Set bare.TurnDecisionRef = reply
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(bare)
	Do $$$AssertEquals($IsObject(payload.Decision)_"|"_$IsObject(payload.TurnCost)_"|"_payload.CheckKey_"|"_payload.Checks.Count(), "0|0||0", "a row with no session gives no decision, cost, key or rows")
	Do $ClassMethod(fixture, "Clean", session_","_other_","_triage_","_reply_","_theirs_","_ref)
}

/// The decision a turn shows (Turn.ShownDecisionRef): the reply decision for a fallback reply and the triage decision for any
/// other reply, and the other one when the first is empty. The rows are not saved.
Method TestShownDecisionRef()
{
	Set turn = ##class(OcuTalon.Data.Turn).%New()
	Do $$$AssertEquals(turn.ShownDecisionRef(), "", "a turn with no decision shows none")
	Set turn.TriageDecisionRef = "ZzTriage"
	Do $$$AssertEquals(turn.ShownDecisionRef(), "ZzTriage", "a reply with only the triage decision shows it")
	Set turn.TriageDecisionRef = ""
	Set turn.TurnDecisionRef = "ZzReply"
	Do $$$AssertEquals(turn.ShownDecisionRef(), "ZzReply", "a reply with only the reply decision shows it")
	Set turn.TriageDecisionRef = "ZzTriage"
	Do $$$AssertEquals(turn.ShownDecisionRef(), "ZzTriage", "a reply with both shows the triage decision")
	Set turn.ReplyCatalogKey = "conversation.turnFallback"
	Do $$$AssertEquals(turn.ShownDecisionRef(), "ZzReply", "a fallback with both shows the reply decision")
	Set turn.TurnDecisionRef = ""
	Do $$$AssertEquals(turn.ShownDecisionRef(), "ZzTriage", "a fallback with only the triage decision shows it")
	Set turn.TriageDecisionRef = ""
	Do $$$AssertEquals(turn.ShownDecisionRef(), "", "a fallback with none shows none")
}

/// The FromRow builders of the snapshot's payloads copy each row property to its own field: every value below differs
/// from the others, so a field copied from the wrong property is caught. The rows are not saved. A turn's payload has every
/// field from the row, and the trace target only when the row has a TraceHeaderId. An approval's dry run is parsed; an empty one, a broken one and one without an item noun give a
/// payload without the part that is missing.
Method TestFromRowBuilders()
{
	Set turn = ##class(OcuTalon.Data.Turn).%New()
	Set turn.Ref = "ZzTurnRef"_..Number
	Set turn.Channel = "telegram"
	Set turn.FromGuide = 1
	Set turn.State = "queued"
	Set turn.CreatedAt = "2026-10-19T09:00:01Z"
	Set turn.TriageDecisionRef = "ZzTriageDecision"
	Set turn.TurnDecisionRef = "ZzTurnDecision"
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(turn)
	Do $$$AssertEquals(payload.Ref_"|"_payload.Channel_"|"_payload.FromGuide_"|"_payload.State_"|"_payload.CreatedAt, "ZzTurnRef"_..Number_"|telegram|1|queued|2026-10-19T09:00:01Z", "a turn: ref, channel, fromGuide, state, createdAt")
	Do $$$AssertEquals(payload.ClientId_"|"_payload.Text_"|"_payload.ReplyText_"|"_payload.CatalogKey_"|"_payload.FallbackReason_"|"_payload.TraceHeaderId_"|"_payload.TraceNamespace, "||||||", "a row with none of them gives empty fields, and no trace target")
	Set turn.ClientId = "ZzClient"_..Number
	Set turn.Text = "ZzUserText"
	Set turn.ReplyText = "ZzReplyText"
	Set turn.ReplyCatalogKey = "zz.catalog.key"
	Set turn.FallbackReason = "zz_reason"
	Set turn.TraceHeaderId = 31337
	Set turn.ItemId = "ZzItemId"
	Set turn.Tainted = 1
	Set turn.Attempt = 7
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(turn)
	Do $$$AssertEquals(payload.ClientId, "ZzClient"_..Number, "a turn: clientId")
	Do $$$AssertEquals(payload.Text, "ZzUserText", "a turn: text")
	Do $$$AssertEquals(payload.ReplyText, "ZzReplyText", "a turn: replyText")
	Do $$$AssertEquals(payload.CatalogKey, "zz.catalog.key", "a turn: catalogKey is the row's ReplyCatalogKey")
	Do $$$AssertEquals(payload.FallbackReason, "zz_reason", "a turn: fallbackReason")
	Do $$$AssertEquals(payload.TraceHeaderId_"|"_payload.TraceNamespace, "31337|"_$Namespace, "a turn: the trace target is the row's TraceHeaderId in the running namespace")
	Do $$$AssertEquals(payload.Ref_"|"_payload.Channel_"|"_payload.FromGuide_"|"_payload.State_"|"_payload.CreatedAt, "ZzTurnRef"_..Number_"|telegram|1|queued|2026-10-19T09:00:01Z", "and the other fields are as before")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the turn's payload exports")
	Set exported = ##class(%DynamicObject).%FromJSON(json)
	Do $$$AssertEquals(exported.clientId_"|"_exported.text_"|"_exported.replyText_"|"_exported.catalogKey_"|"_exported.fallbackReason_"|"_exported.traceHeaderId_"|"_exported.traceNamespace, "ZzClient"_..Number_"|ZzUserText|ZzReplyText|zz.catalog.key|zz_reason|31337|"_$Namespace, "and the JSON carries each of them under its own name")

	Set reminder = ##class(OcuTalon.Data.Reminder).%New()
	Set reminder.Ref = "ZzRemRef"_..Number
	Set reminder.Text = "Call the warehouse"
	Set reminder.DueAt = "2030-02-03T04:05:06Z"
	Set reminder.State = "pending"
	Set reminder.Late = 1
	Set reminder.CreatedAt = "2026-10-19T09:00:02Z"
	Set payload = ##class(OcuTalon.Live.Payload.Reminder).FromRow(reminder)
	Do $$$AssertEquals(payload.Ref_"|"_payload.Text_"|"_payload.DueAt_"|"_payload.State_"|"_payload.Late, "ZzRemRef"_..Number_"|Call the warehouse|2030-02-03T04:05:06Z|pending|1", "a reminder: ref, text, dueAt, state, late")
	Do $$$AssertEquals(payload.TraceHeaderId_"|"_payload.TraceNamespace, "|", "and it has no trace")

	Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set request.Ref = "ZzAppRef"_..Number
	Set request.Kind = "fix"
	Set request.IncidentRef = "ZzIncRef"_..Number
	Set request.OwnerRef = "ZzOwnerRef"
	Set request.State = "answered"
	Set request.ToolName = "tool.fix"
	Set request.RaisedAt = "2026-10-19T09:10:00Z"
	Set request.ExpiresAt = "2026-10-19T09:20:00Z"
	Set request.AnsweredAction = "approve"
	Set request.AnsweredChannel = "phone"
	Set request.AnsweredBy = "someone"
	Set request.AnsweredAt = "2026-10-19T09:11:00Z"
	Set request.Result = "fixed"
	Set request.FinishedAt = "2026-10-19T09:12:00Z"
	Set request.DryRun = {"affected": 4, "resend": 3, "leftOut": 1, "field": "OrderDate", "before": "16/10/2026", "after": "2026-10-16", "itemNoun": {"one": "order", "other": "orders"}}.%ToJSON()
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(request)
	Do $$$AssertEquals(payload.Ref_"|"_payload.Kind_"|"_payload.State_"|"_payload.IncidentRef_"|"_payload.ToolName, "ZzAppRef"_..Number_"|fix|answered|ZzIncRef"_..Number_"|tool.fix", "an approval: ref, kind, state, incidentRef, toolName")
	Do $$$AssertEquals(payload.RaisedAt_"|"_payload.ExpiresAt_"|"_payload.AnsweredAction_"|"_payload.AnsweredChannel, "2026-10-19T09:10:00Z|2026-10-19T09:20:00Z|approve|phone", "raisedAt, expiresAt, answeredAction, answeredChannel")
	Do $$$AssertEquals(payload.AnsweredBy_"|"_payload.AnsweredAt_"|"_payload.Result_"|"_payload.FinishedAt, "someone|2026-10-19T09:11:00Z|fixed|2026-10-19T09:12:00Z", "answeredBy, answeredAt, result, finishedAt")
	Do $$$AssertEquals(payload.Reason_"|"_payload.TraceHeaderId_"|"_payload.TraceNamespace, "||", "the reason and the trace have no source in the row")
	Do $$$AssertEquals(payload.DryRun.Affected_"|"_payload.DryRun.Resend_"|"_payload.DryRun.LeftOut_"|"_payload.DryRun.Field_"|"_payload.DryRun.Before_"|"_payload.DryRun.After, "4|3|1|OrderDate|16/10/2026|2026-10-16", "the dry run is parsed")
	Do $$$AssertEquals(payload.DryRun.ItemNoun.One_"|"_payload.DryRun.ItemNoun.Other, "order|orders", "with its item noun")
	Set request.DryRun = {"affected": 2}.%ToJSON()
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(request)
	Do $$$AssertEquals($IsObject(payload.DryRun) && (payload.DryRun.Affected = 2) && ('$IsObject(payload.DryRun.ItemNoun)), 1, "a dry run without an item noun gives a part without one")
	Set request.DryRun = ""
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Approval).FromRow(request).DryRun, "", "no dry run in the row gives none")
	Set request.DryRun = "not json"
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Approval).FromRow(request).DryRun, "", "a broken dry run gives none")

	Set decision = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set decision.Ref = "ZzDecRef"_..Number
	Set decision.Kind = "decide"
	Set decision.ItemId = "ZzItemId"_..Number
	Set decision.Summary = "A summary"
	Set decision.Outcome = "notify"
	Set decision.Reasons = "a reason"
	Set decision.Confidence = 0.85
	Set decision.Fallback = 1
	Set decision.FallbackReason = "model_error"
	Set decision.InputTokens = 101
	Set decision.OutputTokens = 202
	Set decision.CacheReadTokens = 303
	Set decision.CacheWriteTokens = 404
	Set decision.AgentStepCount = 5
	Set decision.DurationMs = 6000
	Set decision.CostUSD = 0.012345
	Set decision.Model = "claude-sonnet-5-5"
	Set decision.TraceSessionId = 77
	Set decision.RecordedAt = "2026-10-19T09:30:00Z"
	Set payload = ##class(OcuTalon.Live.Payload.Decision).FromRow(decision)
	Do $$$AssertEquals(payload.Ref_"|"_payload.Kind_"|"_payload.ItemId_"|"_payload.ItemSummary_"|"_payload.Outcome_"|"_payload.Reasons, "ZzDecRef"_..Number_"|decide|ZzItemId"_..Number_"|A summary|notify|a reason", "a decision: ref, kind, itemId, itemSummary, outcome, reasons")
	Do $$$AssertEquals(payload.Confidence_"|"_payload.Fallback_"|"_payload.FallbackReason, ".85|1|model_error", "confidence, fallback, fallbackReason")
	Do $$$AssertEquals(payload.InputTokens_"|"_payload.OutputTokens_"|"_payload.CacheReadTokens_"|"_payload.CacheWriteTokens, "101|202|303|404", "the four token counts")
	Do $$$AssertEquals(payload.AgentStepCount_"|"_payload.DurationMs_"|"_payload.CostUSD_"|"_payload.RecordedAt, "5|6000|.012345|2026-10-19T09:30:00Z", "agentStepCount, durationMs, costUSD, recordedAt")
	Do $$$AssertEquals(payload.Model_"|"_payload.TraceHeaderId_"|"_payload.TraceNamespace, "Claude Sonnet 5.5|77|"_$Namespace, "the model's display name, the trace of the decision's session")
}

/// --- helpers ---
/// Deletes every fixture incident row.
ClassMethod Clean() [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Data.Incident WHERE OwnerRef %STARTSWITH 'ZzPay'")
	Do statement.%Execute()
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Live.Payload.Approval": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Kind": "%String(%JSONFIELDNAME=kind,MAXLEN=32)",
   "State": "%String(%JSONFIELDNAME=state,MAXLEN=32)",
   "IncidentRef": "%String(%JSONFIELDNAME=incidentRef,MAXLEN=22)",
   "ToolName": "%String(%JSONFIELDNAME=toolName,MAXLEN=128)",
   "Reason": "%String(%JSONFIELDNAME=reason,MAXLEN=1000)",
   "DryRun": "OcuTalon.Live.Payload.Part.DryRun(%JSONFIELDNAME=dryRun)",
   "RaisedAt": "%String(%JSONFIELDNAME=raisedAt,MAXLEN=20)",
   "ExpiresAt": "%String(%JSONFIELDNAME=expiresAt,MAXLEN=20)",
   "AnsweredAction": "%String(%JSONFIELDNAME=answeredAction,MAXLEN=32)",
   "AnsweredChannel": "%String(%JSONFIELDNAME=answeredChannel,MAXLEN=32)",
   "AnsweredBy": "%String(%JSONFIELDNAME=answeredBy,MAXLEN=128)",
   "AnsweredAt": "%String(%JSONFIELDNAME=answeredAt,MAXLEN=20)",
   "Result": "%String(%JSONFIELDNAME=result,MAXLEN=32)",
   "FinishedAt": "%String(%JSONFIELDNAME=finishedAt,MAXLEN=20)",
   "TraceHeaderId": "%Integer(%JSONFIELDNAME=traceHeaderId)",
   "TraceNamespace": "%String(%JSONFIELDNAME=traceNamespace,MAXLEN=128)"
  }
 },
 "OcuTalon.Live.Payload.BreakFeedProgress": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "State": "%String(%JSONFIELDNAME=state,MAXLEN=32)",
   "StartedAt": "%String(%JSONFIELDNAME=startedAt,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.ChatMessage": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "ClientId": "%String(%JSONFIELDNAME=clientId,MAXLEN=128)",
   "Channel": "%String(%JSONFIELDNAME=channel,MAXLEN=32)",
   "FromGuide": "%Boolean(%JSONFIELDNAME=fromGuide)",
   "State": "%String(%JSONFIELDNAME=state,MAXLEN=32)",
   "Text": "%String(%JSONFIELDNAME=text,MAXLEN=)",
   "ReplyText": "%String(%JSONFIELDNAME=replyText,MAXLEN=)",
   "CatalogKey": "%String(%JSONFIELDNAME=catalogKey,MAXLEN=128)",
   "FallbackReason": "%String(%JSONFIELDNAME=fallbackReason,MAXLEN=32)",
   "CreatedAt": "%String(%JSONFIELDNAME=createdAt,MAXLEN=20)",
   "TraceHeaderId": "%Integer(%JSONFIELDNAME=traceHeaderId)",
   "TraceNamespace": "%String(%JSONFIELDNAME=traceNamespace,MAXLEN=128)",
   "Decision": "OcuTalon.Live.Payload.Decision(%JSONFIELDNAME=decision)",
   "TurnCost": "OcuTalon.Live.Payload.Part.Cost(%JSONFIELDNAME=turnCost)",
   "CheckKey": "%String(%JSONFIELDNAME=checkKey,MAXLEN=128)",
   "Checks": "list Of OcuTalon.Live.Payload.Part.CheckRow(%JSONFIELDNAME=checks)"
  }
 },
 "OcuTalon.Live.Payload.Check": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Kind": "%String(%JSONFIELDNAME=kind,MAXLEN=32)",
   "Namespace": "%String(%JSONFIELDNAME=namespace,MAXLEN=128)",
   "Production": "%String(%JSONFIELDNAME=production,MAXLEN=128)",
   "DisplayName": "%String(%JSONFIELDNAME=displayName,MAXLEN=128)",
   "Stopped": "%Boolean(%JSONFIELDNAME=stopped)",
   "NextDueAt": "%String(%JSONFIELDNAME=nextDueAt,MAXLEN=20)",
   "LastRunAt": "%String(%JSONFIELDNAME=lastRunAt,MAXLEN=20)",
   "Result": "%String(%JSONFIELDNAME=result,MAXLEN=32)",
   "Finding": "%String(%JSONFIELDNAME=finding,MAXLEN=1000)",
   "TraceHeaderId": "%Integer(%JSONFIELDNAME=traceHeaderId)",
   "TraceNamespace": "%String(%JSONFIELDNAME=traceNamespace,MAXLEN=128)"
  }
 },
 "OcuTalon.Live.Payload.GuideState": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "RunEpoch": "%Integer(%JSONFIELDNAME=runEpoch)",
   "Step": "%Integer(%JSONFIELDNAME=step)",
   "Finished": "%Boolean(%JSONFIELDNAME=finished)"
  }
 },
 "OcuTalon.Live.Payload.Incident": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "State": "%String(%JSONFIELDNAME=state,MAXLEN=32)",
   "OpenVariant": "%String(%JSONFIELDNAME=openVariant,MAXLEN=32)",
   "Count": "%Integer(%JSONFIELDNAME=count)",
   "NoticeCount": "%Integer(%JSONFIELDNAME=noticeCount)",
   "FirstAt": "%String(%JSONFIELDNAME=firstAt,MAXLEN=20)",
   "LastAt": "%String(%JSONFIELDNAME=lastAt,MAXLEN=20)",
   "ItemNoun": "OcuTalon.Live.Payload.Part.ItemNoun(%JSONFIELDNAME=itemNoun)",
   "Cause": "%String(%JSONFIELDNAME=cause,MAXLEN=1000)",
   "FixSummary": "%String(%JSONFIELDNAME=fixSummary,MAXLEN=1000)",
   "CauseCategory": "%String(%JSONFIELDNAME=causeCategory,MAXLEN=32)",
   "Element": "%String(%JSONFIELDNAME=element,MAXLEN=128)",
   "Fallback": "%Boolean(%JSONFIELDNAME=fallback)",
   "FallbackReason": "%String(%JSONFIELDNAME=fallbackReason,MAXLEN=32)",
   "DecisionRef": "%String(%JSONFIELDNAME=decisionRef,MAXLEN=22)",
   "Groups": "list Of OcuTalon.Live.Payload.Part.IncidentGroup(%JSONFIELDNAME=groups)",
   "Requests": "list Of OcuTalon.Live.Payload.Part.IncidentRequest(%JSONFIELDNAME=requests)",
   "Evidence": "OcuTalon.Live.Payload.Part.IncidentEvidence(%JSONFIELDNAME=evidence)",
   "TraceTargets": "OcuTalon.Live.Payload.Part.IncidentTraceTargets(%JSONFIELDNAME=traceTargets)"
  }
 },
 "OcuTalon.Live.Payload.Mailbox": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Direction": "%String(%JSONFIELDNAME=direction,MAXLEN=32)",
   "ItemId": "%String(%JSONFIELDNAME=itemId,MAXLEN=22)",
   "Sender": "%String(%JSONFIELDNAME=sender,MAXLEN=1000)",
   "Subject": "%String(%JSONFIELDNAME=subject,MAXLEN=1000)",
   "Text": "%String(%JSONFIELDNAME=text,MAXLEN=)",
   "Unread": "%Boolean(%JSONFIELDNAME=unread)",
   "CreatedAt": "%String(%JSONFIELDNAME=createdAt,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Notification": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Kind": "%String(%JSONFIELDNAME=kind,MAXLEN=32)",
   "Text": "%String(%JSONFIELDNAME=text,MAXLEN=)",
   "WhyNow": "%String(%JSONFIELDNAME=whyNow,MAXLEN=1000)",
   "DecisionRef": "%String(%JSONFIELDNAME=decisionRef,MAXLEN=22)",
   "IncidentRef": "%String(%JSONFIELDNAME=incidentRef,MAXLEN=22)",
   "ApprovalRef": "%String(%JSONFIELDNAME=approvalRef,MAXLEN=22)",
   "DueAt": "%String(%JSONFIELDNAME=dueAt,MAXLEN=20)",
   "CreatedAt": "%String(%JSONFIELDNAME=createdAt,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Pairing": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Paired": "%Boolean(%JSONFIELDNAME=paired)",
   "DisplayName": "%String(%JSONFIELDNAME=displayName,MAXLEN=128)"
  }
 },
 "OcuTalon.Live.Payload.Phone": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Direction": "%String(%JSONFIELDNAME=direction,MAXLEN=32)",
   "Text": "%String(%JSONFIELDNAME=text,MAXLEN=)",
   "ApprovalRef": "%String(%JSONFIELDNAME=approvalRef,MAXLEN=22)",
   "CreatedAt": "%String(%JSONFIELDNAME=createdAt,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Reminder": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Text": "%String(%JSONFIELDNAME=text,MAXLEN=1000)",
   "DueAt": "%String(%JSONFIELDNAME=dueAt,MAXLEN=20)",
   "State": "%String(%JSONFIELDNAME=state,MAXLEN=32)",
   "Late": "%Boolean(%JSONFIELDNAME=late)",
   "TraceHeaderId": "%Integer(%JSONFIELDNAME=traceHeaderId)",
   "TraceNamespace": "%String(%JSONFIELDNAME=traceNamespace,MAXLEN=128)"
  }
 },
 "OcuTalon.Live.Payload.Reset": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "NextReset": "%String(%JSONFIELDNAME=nextReset,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Status": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Condition": "%String(%JSONFIELDNAME=condition,MAXLEN=32)",
   "Active": "%Boolean(%JSONFIELDNAME=active)",
   "Slots": "OcuTalon.Live.Payload.Part.StatusSlots(%JSONFIELDNAME=slots)"
  }
 },
 "OcuTalon.Live.Payload.TurnStep": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "TurnRef": "%String(%JSONFIELDNAME=turnRef,MAXLEN=22)",
   "DecisionRef": "%String(%JSONFIELDNAME=decisionRef,MAXLEN=22)",
   "Label": "%String(%JSONFIELDNAME=label,MAXLEN=1000)"
  }
 },
 "OcuTalon.Live.Payload.WatchProgress": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Stage": "%String(%JSONFIELDNAME=stage,MAXLEN=32)"
  }
 },
 "OcuTalon.Live.Payload.Part.CheckRow": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Result": "%String(%JSONFIELDNAME=result,MAXLEN=32)",
   "Entry": "%String(%JSONFIELDNAME=entry,MAXLEN=1000)",
   "Finding": "%String(%JSONFIELDNAME=finding,MAXLEN=1000)",
   "CheckedAt": "%String(%JSONFIELDNAME=checkedAt,MAXLEN=32)"
  }
 },
 "OcuTalon.Live.Payload.Part.Cost": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "InputTokens": "%Integer(%JSONFIELDNAME=inputTokens)",
   "OutputTokens": "%Integer(%JSONFIELDNAME=outputTokens)",
   "CacheReadTokens": "%Integer(%JSONFIELDNAME=cacheReadTokens)",
   "CacheWriteTokens": "%Integer(%JSONFIELDNAME=cacheWriteTokens)",
   "CostUSD": "%Numeric(%JSONFIELDNAME=costUSD,SCALE=6)"
  }
 },
 "OcuTalon.Live.Payload.Part.DryRun": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Affected": "%Integer(%JSONFIELDNAME=affected)",
   "Resend": "%Integer(%JSONFIELDNAME=resend)",
   "LeftOut": "%Integer(%JSONFIELDNAME=leftOut)",
   "Field": "%String(%JSONFIELDNAME=field,MAXLEN=128)",
   "Before": "%String(%JSONFIELDNAME=before,MAXLEN=1000)",
   "After": "%String(%JSONFIELDNAME=after,MAXLEN=1000)",
   "ItemNoun": "OcuTalon.Live.Payload.Part.ItemNoun(%JSONFIELDNAME=itemNoun)"
  }
 },
 "OcuTalon.Live.Payload.Part.IncidentEvidence": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "SampleHeaderId": "%Integer(%JSONFIELDNAME=sampleHeaderId)",
   "SampleError": "%String(%JSONFIELDNAME=sampleError,MAXLEN=1000)",
   "Items": "list Of OcuTalon.Live.Payload.Part.IncidentEvidenceItem(%JSONFIELDNAME=items)"
  }
 },
 "OcuTalon.Live.Payload.Part.IncidentEvidenceItem": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "ItemName": "%String(%JSONFIELDNAME=itemName,MAXLEN=128)",
   "Count": "%Integer(%JSONFIELDNAME=count)",
   "FirstAt": "%String(%JSONFIELDNAME=firstAt,MAXLEN=20)",
   "LastAt": "%String(%JSONFIELDNAME=lastAt,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Part.IncidentGroup": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "ItemName": "%String(%JSONFIELDNAME=itemName,MAXLEN=128)",
   "Count": "%Integer(%JSONFIELDNAME=count)",
   "ErrorSummary": "%String(%JSONFIELDNAME=errorSummary,MAXLEN=1000)",
   "FirstAt": "%String(%JSONFIELDNAME=firstAt,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Part.IncidentRequest": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "State": "%String(%JSONFIELDNAME=state,MAXLEN=32)",
   "Result": "OcuTalon.Live.Payload.Part.IncidentRequestResult(%JSONFIELDNAME=result)"
  }
 },
 "OcuTalon.Live.Payload.Part.IncidentRequestResult": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Total": "%Integer(%JSONFIELDNAME=total)",
   "Resent": "%Integer(%JSONFIELDNAME=resent)",
   "Completed": "%Integer(%JSONFIELDNAME=completed)",
   "FailedAgain": "%Integer(%JSONFIELDNAME=failedAgain)",
   "Skipped": "%Integer(%JSONFIELDNAME=skipped)",
   "Interrupted": "%Integer(%JSONFIELDNAME=interrupted)",
   "Reason": "%String(%JSONFIELDNAME=reason,MAXLEN=1000)"
  }
 },
 "OcuTalon.Live.Payload.Part.IncidentTraceTargets": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Diagnosis": "OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME=diagnosis)",
   "Sample": "OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME=sample)",
   "FirstFailure": "OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME=firstFailure)"
  }
 },
 "OcuTalon.Live.Payload.Part.ItemNoun": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "One": "%String(%JSONFIELDNAME=one,MAXLEN=128)",
   "Other": "%String(%JSONFIELDNAME=other,MAXLEN=128)"
  }
 },
 "OcuTalon.Live.Payload.Part.StatusSlots": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Limit": "%Integer(%JSONFIELDNAME=limit)",
   "Cap": "%Numeric(%JSONFIELDNAME=cap,SCALE=6)",
   "Time": "%String(%JSONFIELDNAME=time,MAXLEN=20)"
  }
 },
 "OcuTalon.Live.Payload.Part.TraceTarget": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "TraceHeaderId": "%Integer(%JSONFIELDNAME=traceHeaderId)",
   "TraceNamespace": "%String(%JSONFIELDNAME=traceNamespace,MAXLEN=128)"
  }
 }
}
}

}
