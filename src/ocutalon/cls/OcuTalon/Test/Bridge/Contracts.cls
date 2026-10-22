/// Tests of the bridge's message contracts and shared helpers (Story 0.4; Story 1.2 adds Reply.FinishReason and the ToolInventory
/// request; Story 1.5 adds Reply.Steps, which a busy reply leaves empty): every OcuTalon.Bridge.Msg class has
/// exactly its contract, a busy reply is only busy, NewRef gives 22-character base64url references, and the audit
/// writer's API names the six events and refuses any other type. Nothing is written to the audit log.
Class OcuTalon.Test.Bridge.Contracts Extends OcuTalon.Test.Contract
{

/// Every bridge message class has its superclass, properties, types and indexes, and shares the Ens.MessageBody extent.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
}

/// NewBusy sets Busy and nothing else: every flag is 0 and every other field is empty. The reply saves; the saved row is deleted again.
Method TestNewBusy()
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
	Do $$$AssertEquals(reply.Busy, 1, "Busy is 1")
	Do $$$AssertEquals(reply.Text, "", "Text is empty")
	Do $$$AssertEquals(reply.DecisionRef, "", "DecisionRef is empty")
	Do $$$AssertEquals(reply.Outcome, "", "Outcome is empty")
	Do $$$AssertEquals(reply.Reasons, "", "Reasons is empty")
	Do $$$AssertEquals(reply.Fallback, 0, "Fallback is 0")
	For name = "Tainted", "SessionRotated", "ToolsRun", "SessionBroken" {
		Do $$$AssertEquals($Property(reply, name), 0, name_" is 0")
	}
	For name = "HostData", "Steps", "FallbackReason", "Confidence", "InputTokens", "OutputTokens", "CacheReadTokens", "CacheWriteTokens", "AgentStepCount", "DurationMs", "CostUSD", "Model" {
		Do $$$AssertEquals($Property(reply, name), "", name_" is empty")
	}
	Set sc = reply.%Save()
	Do $$$AssertStatusOK(sc, "the busy reply saves")
	If $$$ISOK(sc) Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Msg.Reply).%DeleteId(reply.%Id()), "the saved busy reply is deleted")
}

/// The decision payload imports and exports JSON under the keys outcome, reasons (a list) and confidence.
Method TestDecisionPayloadJson()
{
	Set payload = ##class(OcuTalon.Bridge.Msg.DecisionPayload).%New()
	Do $$$AssertStatusOK(payload.%JSONImport({"outcome": "act", "reasons": ["a", "b"], "confidence": 0.9}), "the payload imports")
	Do $$$AssertEquals(payload.Outcome, "act", "outcome is read")
	Do $$$AssertEquals(payload.Reasons.Count(), 2, "reasons holds two items")
	Do $$$AssertEquals(payload.Reasons.GetAt(2), "b", "the second reason is read")
	Do $$$AssertEquals(payload.Confidence, 0.9, "confidence is read")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the payload exports")
	Set exported = {}.%FromJSON(json)
	Do $$$AssertEquals(exported.outcome, "act", "outcome is exported")
	Do $$$AssertEquals(exported.reasons.%Size(), 2, "reasons is exported as a list")
	Do $$$AssertEquals(exported.confidence, 0.9, "confidence is exported")
}

/// 10,000 references are unique, and each is 22 characters of A-Z, a-z, 0-9, - and _.
Method TestNewRef()
{
	Kill seen
	Set unique = 0
	Set valid = 0
	For i = 1:1:10000 {
		Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		If '$Data(seen(ref)) {
			Set seen(ref) = ""
			Set unique = unique + 1
		}
		If $Match(ref, "^[A-Za-z0-9_-]{22}$") Set valid = valid + 1
	}
	Do $$$AssertEquals(unique, 10000, "10,000 references are unique")
	Do $$$AssertEquals(valid, 10000, "10,000 references match ^[A-Za-z0-9_-]{22}$")
}

/// Events() names the six events in order. Write refuses a type that is not one of them, naming it, matching the case
/// exactly, and refuses data that is not a dynamic object before it writes anything.
Method TestAuditApi()
{
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Bridge.Audit).Events(), ","), "OcuTalon/Action/Action,OcuTalon/Approval/Approval,OcuTalon/Pairing/Pairing,OcuTalon/Settings/Settings,OcuTalon/MCP/MCP,OcuTalon/Tool/Tool", "the six events, in order")
	Set sc = ##class(OcuTalon.Bridge.Audit).Write("Zz", {})
	Do $$$AssertStatusNotOK(sc, "Write refuses an unknown type")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Zz", "the error names the type")
	Set sc = ##class(OcuTalon.Bridge.Audit).Write("action", {})
	Do $$$AssertStatusNotOK(sc, "Write matches a type exactly")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "'action'", "the error names the type as given")
	Set samples(1) = "not an object"
	Set samples(2) = []
	Set samples(3) = ##class(%Stream.TmpCharacter).%New()
	Set index = ""
	For {
		Set index = $Order(samples(index))
		Quit:index=""
		Set sc = ##class(OcuTalon.Bridge.Audit).Write("Action", samples(index))
		Do $$$AssertStatusNotOK(sc, "Write refuses data that is not a dynamic object (sample "_index_")")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "dynamic object", "the error says the data must be a dynamic object (sample "_index_")")
	}
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Bridge.Msg.Request": {
  "super": "Ens.Request",
  "props": {
   "Kind": "%String(MAXLEN=32)",
   "Provenance": "%String(MAXLEN=32)",
   "Input": "%String(MAXLEN=)",
   "ItemId": "%String(MAXLEN=22)",
   "Summary": "%String(MAXLEN=80)",
   "DecisionRef": "%String(MAXLEN=22)",
   "OwnerRef": "%String(MAXLEN=22)",
   "TraceRef": "%String(MAXLEN=22)",
   "Channel": "%String(MAXLEN=32)",
   "ThreadSessionId": "%Integer",
   "SessionMode": "%String(MAXLEN=32)",
   "SeedText": "%String(MAXLEN=)",
   "SystemNote": "%String(MAXLEN=)"
  },
  "sql": {
   "Input": "InputText"
  }
 },
 "OcuTalon.Bridge.Msg.Result": {
  "super": "Ens.Response",
  "abstract": 1,
  "props": {
   "DecisionRef": "%String(MAXLEN=22)",
   "Outcome": "%String(MAXLEN=32)",
   "Reasons": "%String(MAXLEN=)",
   "Confidence": "%Numeric(MAXVAL=1,MINVAL=0,SCALE=2)",
   "Fallback": "%Boolean",
   "FallbackReason": "%String(MAXLEN=32)",
   "InputTokens": "%Integer",
   "OutputTokens": "%Integer",
   "CacheReadTokens": "%Integer",
   "CacheWriteTokens": "%Integer",
   "AgentStepCount": "%Integer",
   "DurationMs": "%Integer",
   "CostUSD": "%Numeric(SCALE=6)",
   "Model": "%String(MAXLEN=128)"
  }
 },
 "OcuTalon.Bridge.Msg.DecisionResponse": {
  "super": "OcuTalon.Bridge.Msg.Result",
  "props": {
   "DecisionRef": "%String(MAXLEN=22)",
   "Outcome": "%String(MAXLEN=32)",
   "Reasons": "%String(MAXLEN=)",
   "Confidence": "%Numeric(MAXVAL=1,MINVAL=0,SCALE=2)",
   "Fallback": "%Boolean",
   "FallbackReason": "%String(MAXLEN=32)",
   "InputTokens": "%Integer",
   "OutputTokens": "%Integer",
   "CacheReadTokens": "%Integer",
   "CacheWriteTokens": "%Integer",
   "AgentStepCount": "%Integer",
   "DurationMs": "%Integer",
   "CostUSD": "%Numeric(SCALE=6)",
   "Model": "%String(MAXLEN=128)",
   "Payload": "%String(MAXLEN=)"
  }
 },
 "OcuTalon.Bridge.Msg.Reply": {
  "super": "OcuTalon.Bridge.Msg.Result",
  "props": {
   "DecisionRef": "%String(MAXLEN=22)",
   "Outcome": "%String(MAXLEN=32)",
   "Reasons": "%String(MAXLEN=)",
   "Confidence": "%Numeric(MAXVAL=1,MINVAL=0,SCALE=2)",
   "Fallback": "%Boolean",
   "FallbackReason": "%String(MAXLEN=32)",
   "InputTokens": "%Integer",
   "OutputTokens": "%Integer",
   "CacheReadTokens": "%Integer",
   "CacheWriteTokens": "%Integer",
   "AgentStepCount": "%Integer",
   "DurationMs": "%Integer",
   "CostUSD": "%Numeric(SCALE=6)",
   "Model": "%String(MAXLEN=128)",
   "Text": "%String(MAXLEN=)",
   "Tainted": "%Boolean",
   "SessionRotated": "%Boolean",
   "ToolsRun": "%Boolean",
   "SessionBroken": "%Boolean",
   "Busy": "%Boolean",
   "HostData": "%String(MAXLEN=)",
   "FinishReason": "%String(MAXLEN=32)",
   "Steps": "%String(MAXLEN=)"
  }
 },
 "OcuTalon.Bridge.Msg.ToolInventory": {
  "super": "Ens.Request",
  "props": {}
 },
 "OcuTalon.Bridge.Msg.DecisionPayload": {
  "super": "%RegisteredObject,%JSON.Adaptor",
  "props": {
   "Outcome": "%String(%JSONFIELDNAME=outcome,MAXLEN=32)",
   "Reasons": "list Of %String(%JSONFIELDNAME=reasons,MAXLEN=1000)",
   "Confidence": "%Numeric(%JSONFIELDNAME=confidence,MAXVAL=1,MINVAL=0,SCALE=2)"
  }
 },
 "OcuTalon.Bridge.Msg.AgentStep": {
  "super": "Ens.Request",
  "props": {
   "DecisionRef": "%String(MAXLEN=22)",
   "Position": "%Integer",
   "StepKind": "%String(MAXLEN=32)",
   "Label": "%String(MAXLEN=1000)",
   "Summary": "%String(MAXLEN=1000)",
   "DurationMs": "%Integer",
   "Status": "%String(MAXLEN=32)",
   "EstimatedTokens": "%Integer"
  }
 }
}
}

}
