/// A reply class for the tests of OcuTalon.Bridge.ReplyCheck (Story 7.1). It is a decision payload with one more field, Note, that Decide filters (FILTERED), so Decide
/// checks a reply of this class twice: once on import and once after filtering. Each check keeps what ReplyCheck shows at that moment in the process-private global
/// ^||ZzProbeReplyCheck(<check>) as a $ListBuild of Active and the four values Kind, ItemId, OwnerRef and Input, and counts the checks in ^||ZzProbeReplyCheck. It
/// throws while ^||ZzProbeReplyCheck("throwAt") is the number of the check. The test that uses it kills the global.
Class OcuTalon.Test.Bridge.ProbeReplyCheck Extends OcuTalon.Bridge.Msg.DecisionPayload
{

/// The properties that Decide filters.
Parameter FILTERED = "Note";

Property Note As %String(%JSONFIELDNAME = "note", MAXLEN = 100);

Method %OnValidateObject() As %Status [ Private, ServerOnly = 1 ]
{
	Set n = $Increment(^||ZzProbeReplyCheck)
	Set ^||ZzProbeReplyCheck(n) = $ListBuild(##class(OcuTalon.Bridge.ReplyCheck).Active(), ##class(OcuTalon.Bridge.ReplyCheck).Value("Kind"), ##class(OcuTalon.Bridge.ReplyCheck).Value("ItemId"), ##class(OcuTalon.Bridge.ReplyCheck).Value("OwnerRef"), ##class(OcuTalon.Bridge.ReplyCheck).Value("Input"))
	If $Get(^||ZzProbeReplyCheck("throwAt")) = n {
		Throw ##class(%Exception.General).%New("ZzProbeReplyCheck", 5001, , "The probe check throws")
	}
	Quit ##super()
}

}
