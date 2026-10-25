/// Tests of the cross-lane message contracts (Story 0.4): every OcuTalon.Msg class and the decision live payload has
/// exactly its contract, the enumerations equal the conventions row, the decision payload exports camelCase keys,
/// and the Telegram stub's Included() follows ^OcuTalonTest("TelegramIncluded"). The test global is saved in
/// OnBeforeAllTests and restored in OnAfterAllTests.
Class OcuTalon.Test.Msg.Contracts Extends OcuTalon.Test.Contract
{

/// 1 when ^OcuTalonTest("TelegramIncluded") existed before the tests.
Property SavedDefined As %Boolean;

/// The value of ^OcuTalonTest("TelegramIncluded") before the tests.
Property SavedValue As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedDefined = ''$Data(^OcuTalonTest("TelegramIncluded"), value)
	Set ..SavedValue = $Get(value)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..SavedDefined {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedValue
	} Else {
		Kill ^OcuTalonTest("TelegramIncluded")
	}
	Quit $$$OK
}

/// Every message class has its superclass, properties, types and indexes, and shares the Ens.MessageBody extent.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
}

/// Each command verb and IncidentCommand inherit Origin, IdempotencyKey and SessionRef from Msg.Command.
Method TestVerbsInheritTheCommonFields()
{
	Set classes = $ListBuild("IncidentCommand")
	Set verbs = $ListBuild("SetReminder", "CancelReminder", "ListReminders", "StartWatch", "StopWatch", "Dismiss", "SetDemoMode", "Pair", "Unpair", "EndSession")
	Set position = 0
	While $ListNext(verbs, position, verb) {
		Set classes = classes _ $ListBuild("Command."_verb)
	}
	Set position = 0
	While $ListNext(classes, position, name) {
		Set class = "OcuTalon.Msg."_name
		For field = "Origin", "IdempotencyKey", "SessionRef" {
			Set property = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_field)
			Do $$$AssertEquals($Select($IsObject(property): property.Origin, 1: ""), "OcuTalon.Msg.Command", class_" inherits "_field)
		}
	}
	Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Msg.Command").Abstract, 1, "Msg.Command is abstract")
	Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command", "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", "a command is answered with a CommandResult")
	Do $$$AssertEquals($Parameter("OcuTalon.Msg.IncidentCommand", "VERBS"), "dismiss,closeForReplay,closeQuiet", "the incident verbs")
	Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command.SetReminder", "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", "a verb is answered with a CommandResult")
}

/// The twelve parameters of Msg.Enum equal the conventions row exactly, and there are no others.
Method TestEnumerations()
{
	Set expected("OUTCOME") = "ignore,digest,tellnow,act"
	Set expected("PROVENANCE") = "user,untrusted"
	Set expected("REQUESTKIND") = "decide,diagnose,turn,tool"
	Set expected("FALLBACKREASON") = "no_key,daily_cap,budget,too_large,timeout,rate_limited,error,refusal,cut_off,empty,invalid,unusable"
	Set expected("INCIDENTSTATE") = "open,awaiting_approval,fixing,resolved,closed"
	Set expected("INCIDENTOPENVARIANT") = "fallback,no_fix,rejected,expired"
	Set expected("APPROVALSTATE") = "pending,approved,rejected,expired,cancelled,executing,done,failed"
	Set expected("APPROVALKIND") = "fix,tool_call"
	Set expected("NOTIFICATIONKIND") = "tellnow,incident,approval,answered,result,reminder,fallback,allowance,pairing,status,digest"
	Set expected("CHECKRESULT") = "passed,failed,not_checked"
	Set expected("CHANNEL") = "web,phone,mailbox,telegram,email,webhook,slack,system"
	Set expected("ORIGIN") = "web_user,web_admin,telegram,tool,timer,system"
	Set name = ""
	For {
		Set name = $Order(expected(name), 1, values)
		Quit:name=""
		Do $$$AssertEquals($Parameter("OcuTalon.Msg.Enum", name), values, name_" equals the conventions row")
	}
	Do $$$AssertEquals(..ParameterNames("OcuTalon.Msg.Enum"), "APPROVALKIND APPROVALSTATE CHANNEL CHECKRESULT FALLBACKREASON INCIDENTOPENVARIANT INCIDENTSTATE NOTIFICATIONKIND ORIGIN OUTCOME PROVENANCE REQUESTKIND", "Msg.Enum has exactly these twelve parameters")
}

/// The bridge's seven enumerations equal OcuTalon's, and there are no others.
Method TestBridgeEnumerationsEqualOcuTalons()
{
	Set names = ..ParameterNames("OcuTalon.Bridge.Msg.Enum")
	Do $$$AssertEquals(names, "APPROVALKIND APPROVALSTATE CHANNEL FALLBACKREASON OUTCOME PROVENANCE REQUESTKIND", "Bridge.Msg.Enum has exactly these seven parameters")
	For i = 1:1:$Length(names, " ") {
		Set name = $Piece(names, " ", i)
		Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Msg.Enum", name), $Parameter("OcuTalon.Msg.Enum", name), name_" equals OcuTalon's")
	}
}

/// The decision payload exports each property under its name with a lower-case first letter, and nothing else.
Method TestDecisionPayloadKeys()
{
	Set payload = ##class(OcuTalon.Live.Payload.Decision).%New()
	Set payload.Ref = "ref", payload.Kind = "decide", payload.ItemId = "item", payload.ItemSummary = "summary"
	Set payload.Outcome = "act", payload.Reasons = "a"_$Char(10)_"b", payload.Confidence = 0.9, payload.Fallback = 1
	Set payload.FallbackReason = "timeout", payload.InputTokens = 1, payload.OutputTokens = 2, payload.CacheReadTokens = 3
	Set payload.CacheWriteTokens = 4, payload.AgentStepCount = 5, payload.DurationMs = 6, payload.CostUSD = 0.5
	Set payload.Model = "model", payload.RecordedAt = "2026-10-19T06:57:07Z", payload.TraceHeaderId = 7, payload.TraceNamespace = "OCUTALON"
	Set payload.TraceItemIndex = 8, payload.TraceItemIndexNoEvents = 9
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the payload exports")
	Set exported = {}.%FromJSON(json)
	Set expected = $ListBuild("ref", "kind", "itemId", "itemSummary", "outcome", "reasons", "confidence", "fallback", "fallbackReason", "inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "agentStepCount", "durationMs", "costUSD", "model", "recordedAt", "traceHeaderId", "traceNamespace", "traceItemIndex", "traceItemIndexNoEvents")
	Set found = ""
	Set iterator = exported.%GetIterator()
	While iterator.%GetNext(.key) {
		Set found = found _ $ListBuild(key)
	}
	Do $$$AssertEquals($ListLength(found), $ListLength(expected), "the payload exports "_$ListLength(expected)_" keys")
	Set position = 0
	While $ListNext(expected, position, key) {
		Do $$$AssertTrue($ListFind(found, key), "the payload exports the key "_key)
	}
	Do $$$AssertEquals(exported.%GetTypeOf("fallback"), "boolean", "fallback is a boolean")
	Do $$$AssertEquals(exported.fallback, 1, "fallback is true")
	Do $$$AssertEquals(exported.traceHeaderId, 7, "traceHeaderId is the trace session id")
	Do $$$AssertEquals(exported.traceItemIndex_"|"_exported.traceItemIndexNoEvents, "8|9", "the two item indexes are the turn's positions")
}

/// Included() is 1 only when the test-only global is 1: absent, 0, 2 and 1.
Method TestTelegramIncluded()
{
	Kill ^OcuTalonTest("TelegramIncluded")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.In).Included(), 0, "an absent global gives 0")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.In).Included(), 0, "0 gives 0")
	Set ^OcuTalonTest("TelegramIncluded") = 2
	Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.In).Included(), 0, "2 gives 0")
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.In).Included(), 1, "1 gives 1")
	Do $$$AssertTrue(##class(OcuTalon.Channel.Telegram.In).%Extends("Ens.BusinessService"), "the stub is a business service")
}

/// The names of the parameters that a class declares itself, sorted and joined by spaces.
ClassMethod ParameterNames(class As %String) As %String [ Private ]
{
	Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(class)
	Set names = ""
	Set key = ""
	For {
		Set parameter = compiled.Parameters.GetNext(.key)
		Quit:key=""
		If parameter.Origin = class Set names(parameter.Name) = ""
	}
	Set name = ""
	Set text = ""
	For {
		Set name = $Order(names(name))
		Quit:name=""
		Set text = text_$Select(text = "": "", 1: " ")_name
	}
	Quit text
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Msg.Item": {
  "super": "Ens.Request",
  "props": {
   "ItemId": "%String(MAXLEN=22)",
   "SourceItemId": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Channel": "%String(MAXLEN=32)",
   "Provenance": "%String(MAXLEN=32)",
   "Text": "%String(MAXLEN=)",
   "Sender": "%String(MAXLEN=1000)",
   "Subject": "%String(MAXLEN=1000)",
   "FromGuide": "%Boolean",
   "CatalogKey": "%String(MAXLEN=128)",
   "Slots": "%String(MAXLEN=)",
   "ClientId": "%String(MAXLEN=128)"
  }
 },
 "OcuTalon.Msg.ItemDecision": {
  "super": "Ens.Request",
  "props": {
   "ItemId": "%String(MAXLEN=22)",
   "SourceItemId": "%String(MAXLEN=128)",
   "OwnerRef": "%String(MAXLEN=22)",
   "Channel": "%String(MAXLEN=32)",
   "Summary": "%String(MAXLEN=80)",
   "DecisionRef": "%String(MAXLEN=22)",
   "Outcome": "%String(MAXLEN=32)",
   "Fallback": "%Boolean",
   "FallbackReason": "%String(MAXLEN=32)",
   "CatalogKey": "%String(MAXLEN=128)",
   "Slots": "%String(MAXLEN=)"
  }
 },
 "OcuTalon.Msg.Notification": {
  "super": "Ens.Request",
  "props": {
   "SessionRef": "%String(MAXLEN=22)",
   "ChatRef": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "CatalogKey": "%String(MAXLEN=128)",
   "Slots": "%String(MAXLEN=)",
   "ApprovalRef": "%String(MAXLEN=22)",
   "IncidentRef": "%String(MAXLEN=22)",
   "DecisionRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Outbound": {
  "super": "Ens.Request",
  "props": {
   "SessionRef": "%String(MAXLEN=22)",
   "ChatRef": "%String(MAXLEN=22)",
   "OriginChannel": "%String(MAXLEN=32)",
   "Text": "%String(MAXLEN=)",
   "CatalogKey": "%String(MAXLEN=128)",
   "Slots": "%String(MAXLEN=)",
   "CheckRows": "%String(MAXLEN=)",
   "DecisionRef": "%String(MAXLEN=22)",
   "CheckKey": "%String(MAXLEN=128)"
  }
 },
 "OcuTalon.Msg.Tick": {
  "super": "Ens.Request",
  "props": {
   "TickAt": "%String(MAXLEN=20)",
   "PreviousTickAt": "%String(MAXLEN=20)",
   "CatchUp": "%Boolean"
  }
 },
 "OcuTalon.Msg.Command": {
  "super": "Ens.Request",
  "abstract": 1,
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.IncidentCommand": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Verb": "%String(MAXLEN=32)",
   "IncidentRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.SetReminder": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Text": "%String(MAXLEN=1000)",
   "DueAt": "%String(MAXLEN=20)",
   "DelaySeconds": "%Integer",
   "LocalDueAt": "%String(MAXLEN=19)"
  }
 },
 "OcuTalon.Msg.Command.CancelReminder": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "ReminderRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.ListReminders": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.StartWatch": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Namespace": "%String(MAXLEN=128)",
   "Production": "%String(MAXLEN=128)",
   "DisplayName": "%String(MAXLEN=128)"
  }
 },
 "OcuTalon.Msg.Command.StopWatch": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Namespace": "%String(MAXLEN=128)",
   "Production": "%String(MAXLEN=128)"
  }
 },
 "OcuTalon.Msg.Command.Dismiss": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "IncidentRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.SetDemoMode": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "DemoMode": "%Boolean"
  }
 },
 "OcuTalon.Msg.Command.Pair": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "CodeHash": "%String(MAXLEN=128)",
   "ChatRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.Unpair": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "ChatRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.EndSession": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.CommandResult": {
  "super": "Ens.Response",
  "props": {
   "Ok": "%Boolean",
   "Message": "%String(MAXLEN=1000)",
   "Outcome": "%String(MAXLEN=32)",
   "Ref": "%String(MAXLEN=22)",
   "DueAt": "%String(MAXLEN=20)",
   "Data": "%String(MAXLEN=)"
  }
 },
 "OcuTalon.Live.Payload.Decision": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Ref": "%String(%JSONFIELDNAME=ref,MAXLEN=22)",
   "Kind": "%String(%JSONFIELDNAME=kind,MAXLEN=32)",
   "ItemId": "%String(%JSONFIELDNAME=itemId,MAXLEN=22)",
   "ItemSummary": "%String(%JSONFIELDNAME=itemSummary,MAXLEN=80)",
   "Outcome": "%String(%JSONFIELDNAME=outcome,MAXLEN=32)",
   "Reasons": "%String(%JSONFIELDNAME=reasons,MAXLEN=)",
   "Confidence": "%Numeric(%JSONFIELDNAME=confidence,MAXVAL=1,MINVAL=0,SCALE=2)",
   "Fallback": "%Boolean(%JSONFIELDNAME=fallback)",
   "FallbackReason": "%String(%JSONFIELDNAME=fallbackReason,MAXLEN=32)",
   "InputTokens": "%Integer(%JSONFIELDNAME=inputTokens)",
   "OutputTokens": "%Integer(%JSONFIELDNAME=outputTokens)",
   "CacheReadTokens": "%Integer(%JSONFIELDNAME=cacheReadTokens)",
   "CacheWriteTokens": "%Integer(%JSONFIELDNAME=cacheWriteTokens)",
   "AgentStepCount": "%Integer(%JSONFIELDNAME=agentStepCount)",
   "DurationMs": "%Integer(%JSONFIELDNAME=durationMs)",
   "CostUSD": "%Numeric(%JSONFIELDNAME=costUSD,SCALE=6)",
   "Model": "%String(%JSONFIELDNAME=model,MAXLEN=128)",
   "RecordedAt": "%String(%JSONFIELDNAME=recordedAt,MAXLEN=20)",
   "TraceHeaderId": "%Integer(%JSONFIELDNAME=traceHeaderId)",
   "TraceNamespace": "%String(%JSONFIELDNAME=traceNamespace,MAXLEN=128)",
   "TraceItemIndex": "%Integer(%JSONFIELDNAME=traceItemIndex)",
   "TraceItemIndexNoEvents": "%Integer(%JSONFIELDNAME=traceItemIndexNoEvents)"
  }
 }
}
}

}
