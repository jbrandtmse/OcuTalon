/// QA tests of the order of the diagnosis checks (Story 7.1, AC 2; AD-7, AD-8, AD-16): the kind's check of the fix parameters is the last check in
/// OcuTalon.Watch.Msg.DiagnosisPayload, so every earlier refusal keeps its own reason, and a refusal by the kind names the problem. They need no production and
/// no namespace, so they run anywhere, a slot included. Each test begins a ReplyCheck (as Decide does) over an evidence pack whose sample body is an order, and
/// ends it afterwards.
///   - TestKindCheckIsLast: a repair whose field is not in the sample AND that has one earlier defect (a blank cause, no fix summary, a blank noun form, a time of
///     day, no element) is refused with the reason of the earlier defect, never with the kind's; with none of those defects the same repair is refused with the
///     kind's reason, and the repair with the right field is accepted;
///   - TestKindRefusalsNameTheProblem: a fix kind that is not registered is refused with an error that names the registered kinds (DiagnosisPayload's check); a
///     source and a target format that are not registered are refused with an error that names the parameter and the value; formats of two families and one format
///     twice are refused for that reason; an extra parameter is refused (at import, #9404).
Class OcuTalon.Test.Fix.Validation Extends %UnitTest.TestCase
{

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

Parameter PAYLOAD = "OcuTalon.Watch.Msg.DiagnosisPayload";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.ItemId = "zzfixvalidation"
	Set request.OwnerRef = "instance"
	Set request.Input = ##class(OcuTalon.Test.Fix.Kind).PackInput(##class(OcuTalon.Test.Fix.Kind).OrderBody())
	Quit ##class(OcuTalon.Bridge.ReplyCheck).Begin(request)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Quit $$$OK
}

/// A usable repair as a dynamic object (Test.Fix.Kind's).
ClassMethod Repair() As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Test.Fix.Kind).Repair()
}

/// The text of the error of Decide.CheckReply for the reply, or "" when the reply is accepted.
ClassMethod ErrorOf(reply As %DynamicObject) As %String [ Private ]
{
	Set sc = $ClassMethod(..#DECIDE, "CheckReply", reply.%ToJSON(), ..#PAYLOAD, .payload)
	Quit $Select($$$ISOK(sc): "", 1: $SYSTEM.Status.GetErrorText(sc))
}

Method TestKindCheckIsLast()
{
	Do $$$AssertEquals(..ErrorOf(..Repair()), "", "the repair with the right field is accepted")
	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "is not a field of the sample message", "with no other defect, a field that the sample does not have is refused by the kind: "_$Extract(text, 1, 300))

	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Set reply.cause = "  "
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "The cause is blank", "a blank cause is reported before the field: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "not a field", "and the kind's reason is not given")

	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Set reply.fixSummary = ""
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "has a fixSummary", "a missing fix summary is reported before the field: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "not a field", "and the kind's reason is not given")

	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Set reply.elementAtFault = ""
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "elementAtFault", "a missing element is reported before the field: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "not a field", "and the kind's reason is not given")

	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Set reply.itemNoun.other = ""
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "itemNoun has a blank form", "a blank noun form is reported before the field: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "not a field", "and the kind's reason is not given")

	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Set reply.cause = "The orders failed since 14:12."
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "time of day", "a time of day is reported before the field: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "not a field", "and the kind's reason is not given")

	Set reply = ..Repair()
	Set reply.fixParameters.sourceFormat = "MM-DD-YY"
	Set reply.cause = ""
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "The cause is blank", "a blank cause is reported before a format that is not registered: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "not a registered format", "and the kind's reason is not given")
}

Method TestKindRefusalsNameTheProblem()
{
	Set reply = ..Repair()
	Set reply.fixKind = "rollback"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "fixKind of repair_resend", "a fix kind that is not registered is refused, and the error names the registered kinds: "_$Extract(text, 1, 300))
	Set reply = ..Repair()
	Set reply.fixParameters.sourceFormat = "MM-DD-YY"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "sourceFormat 'MM-DD-YY' is not a registered format", "a source format that is not registered is named: "_$Extract(text, 1, 300))
	Set reply = ..Repair()
	Set reply.fixParameters.targetFormat = "iso"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "targetFormat 'iso' is not a registered format", "a target format that is not registered is named: "_$Extract(text, 1, 300))
	Set reply = ..Repair()
	Set reply.fixParameters.targetFormat = "1234.56"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "not of one family", "formats of two families are refused for that reason: "_$Extract(text, 1, 300))
	Set reply = ..Repair()
	Set reply.fixParameters.targetFormat = "MM/DD/YYYY"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text [ "are one format", "one format twice is refused for that reason: "_$Extract(text, 1, 300))
	Set reply = ..Repair()
	Set reply.fixParameters.rounding = "2"
	Set text = ..ErrorOf(reply)
	Do $$$AssertTrue(text '= "", "an extra parameter is refused: "_$Extract(text, 1, 300))
}

}
