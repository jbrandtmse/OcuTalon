/// The methods behind OcuTalon.Tools.Watch (AD-7): the read tools of the Diagnosis agent. Each takes no argument, so the model chooses nothing: it
/// reads the incident whose Ref is the ItemId of the bridge context and whose OwnerRef is the context's (OcuTalon.Watch.EvidencePack.Scope), and
/// answers {"items": []} when there is none. The reads go through OcuTalon.Watch.EvidencePack, so the namespace, the production and the messages
/// are the incident's, never the model's. It extends OcuTalon.Tools.Result and returns only through Return, so that the model reads the answer as a
/// JSON object and the results of a model step are bounded (AD-10). A tool method runs inside AI Hub's callback, so it writes nothing and makes no
/// %AI call and no Python call (AD-6).
Class OcuTalon.Tools.WatchReads Extends OcuTalon.Tools.Result
{

/// The step labels of the three tools (AD-9), by the naming rule: STEPLABEL and the tool's name in upper case with _ and - removed.
Parameter STEPLABELREADFAILEDMESSAGES = "Reading the failed messages";

Parameter STEPLABELREADEVENTLOG = "Reading the event log";

Parameter STEPLABELREADITEMSETTINGS = "Reading the item settings";

/// The classification of the three tools for the gate (AD-10; Consistency Conventions: Tool classification), by the same naming rule. All three
/// are safe and read-only. None is trusted output: failed messages and the event log hold text from arriving messages, and item settings
/// are not OcuTalon's own records, so a result taints the turn.
Parameter CLASSIFICATIONREADFAILEDMESSAGES = "safe";

Parameter READONLYREADFAILEDMESSAGES = 1;

Parameter TRUSTEDOUTPUTREADFAILEDMESSAGES = 0;

Parameter CLASSIFICATIONREADEVENTLOG = "safe";

Parameter READONLYREADEVENTLOG = 1;

Parameter TRUSTEDOUTPUTREADEVENTLOG = 0;

Parameter CLASSIFICATIONREADITEMSETTINGS = "safe";

Parameter READONLYREADITEMSETTINGS = 1;

Parameter TRUSTEDOUTPUTREADITEMSETTINGS = 0;

/// The oldest failed messages of the incident, at most five: {count, items}, each item {headerId | logRef, item, at, bodyClass, body, error}.
ClassMethod ReadFailedMessages() As %DynamicObject
{
	Set incident = ##class(OcuTalon.Watch.EvidencePack).Scope()
	If '$IsObject(incident) Quit ..Return({"items": []})
	Quit ..Return(##class(OcuTalon.Watch.EvidencePack).FailedMessages(incident))
}

/// The event log of the sessions of those messages, at most twenty rows: {items}, each {logRef, at, type, item, text}.
ClassMethod ReadEventLog() As %DynamicObject
{
	Set incident = ##class(OcuTalon.Watch.EvidencePack).Scope()
	If '$IsObject(incident) Quit ..Return({"items": []})
	Quit ..Return(##class(OcuTalon.Watch.EvidencePack).EventLog(incident))
}

/// The settings of the failing item: {item, settings}.
ClassMethod ReadItemSettings() As %DynamicObject
{
	Set incident = ##class(OcuTalon.Watch.EvidencePack).Scope()
	If '$IsObject(incident) Quit ..Return({"items": []})
	Quit ..Return(##class(OcuTalon.Watch.EvidencePack).ItemSettings(incident))
}

}
