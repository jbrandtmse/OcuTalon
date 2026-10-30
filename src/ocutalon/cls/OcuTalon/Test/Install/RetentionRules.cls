/// Source and declaration pins of the purge (Story 30.2 QA; AD-27, AD-3, AD-17, AD-23). These tests read class source and declarations only: they run no
/// task, delete nothing and need no clock, so they pass on any stack, warm ones included (Test.Install.Retention is the destructive class).
///   - TestWatchAreaOnlyPurges: Install.Step.Watch declares no task, Install.Step.Retention and Install.Step.Watch are areas the registry finds but
///     not steps in its order, and the Watch area's Purge hands its day count to the incident purge;
///   - TestNoHandWrittenInteropPurge (AD-27 "Prevents"): neither Bridge.Purge, Install.Step.Retention nor Install.Step.Watch names a message header,
///     a message body, the event log, the rule log, the I/O log, a business process or an Ens purge class, as a class or as a table; the
///     Interoperability data goes only through the standard task that Retention declares, its only Ens task class;
///   - TestStaysInItsNamespace (the owner's rule) and TestAuditNotNamed (AD-17): neither Bridge.Purge nor the two areas switches namespace, uses an
///     extended global reference, or names the IRIS audit log or its purge task.
Class OcuTalon.Test.Install.RetentionRules Extends %UnitTest.TestCase
{

/// The class that scans source.
Parameter SOURCE = "OcuTalon.Test.Bridge.Source";

/// The classes of the purge: the bridge's part and the two areas.
Parameter PURGECLASSES = "OcuTalon.Bridge.Purge,OcuTalon.Install.Step.Retention,OcuTalon.Install.Step.Watch";

/// 1 when no class of the purge matches the pattern; the scanner is first shown to flag the sample and to pass the clean line.
Method AssertNone(pattern As %String, flagged As %String, clean As %String, what As %String)
{
	Do $$$AssertTrue($ClassMethod(..#SOURCE, "Matches", $Char(9)_flagged, pattern), "the scanner flags "_what)
	Do $$$AssertTrue('$ClassMethod(..#SOURCE, "Matches", "/// "_flagged_$Char(10)_$Char(9)_clean, pattern), "and passes a comment line and "_clean)
	For i = 1:1:$Length(..#PURGECLASSES, ",") {
		Set class = $Piece(..#PURGECLASSES, ",", i)
		Do $$$AssertStatusOK($ClassMethod(..#SOURCE, "Text", class, .text), class_" has source")
		Do $$$AssertEquals($ListToString($ClassMethod(..#SOURCE, "Lines", text, pattern), " | "), "", class_" names "_what_" nowhere")
	}
}

Method TestWatchAreaOnlyPurges()
{
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Watch).Tasks().%Size(), 0, "the Watch area declares no task")
	Set order = ##class(OcuTalon.Install.Registry).Order()
	Set areas = ##class(OcuTalon.Install.Registry).Areas()
	For class = "OcuTalon.Install.Step.Retention", "OcuTalon.Install.Step.Watch" {
		Do $$$AssertTrue($ListFind(areas, class) > 0, class_" is an area the registry finds")
		Do $$$AssertEquals($ListFind(order, $Piece(class, ".", 4)), 0, class_" is not a step in the order")
	}
	Do $$$AssertStatusOK($ClassMethod(..#SOURCE, "Text", "OcuTalon.Install.Step.Watch", .text), "the Watch area has source")
	Do $$$AssertTrue($ClassMethod(..#SOURCE, "Matches", text, "IncidentManager\)\.Purge\(daysToKeep\)"), "its Purge hands the day count to the incident purge")
}

Method TestNoHandWrittenInteropPurge()
{
	Do ..AssertNone("\bens[._](messageheader|messagebody|purge|businessprocess|util[._](messagepurge|log|iolog)|rule[._]log)\b|ens_messageheader", "Do ##class(Ens.MessageHeader).%DeleteId(id)", "Quit ##class(OcuTalon.Bridge.Purge).Run(daysToKeep)", "an Interoperability message, log, process or purge class")
	Do $$$AssertTrue($ClassMethod(..#SOURCE, "Matches", $Char(9)_"Do ##class(%SQL.Statement).%ExecDirect(, ""DELETE FROM Ens_Util.Log WHERE TimeLogged < ?"", cutoff)", "\bens[._]util[._]log\b"), "the scanner flags a hand-written event-log delete")
	For class = "OcuTalon.Bridge.Purge", "OcuTalon.Install.Step.Watch" {
		Do $$$AssertStatusOK($ClassMethod(..#SOURCE, "Text", class, .text), class_" has source")
		Do $$$AssertEquals($ClassMethod(..#SOURCE, "Matches", text, "ens\.util\.tasks\.purge"), 0, class_" does not even name the standard purge task: only Retention declares it")
	}
	Do $$$AssertStatusOK($ClassMethod(..#SOURCE, "Text", "OcuTalon.Install.Step.Retention", .text), "Retention has source")
	Do $$$AssertEquals($ListLength($ClassMethod(..#SOURCE, "Lines", text, "\""taskClass\"": \""ens\.util\.tasks\.purge\""")), 2, "Retention declares the standard purge task twice (7 and 90 days)")
	Do $$$AssertEquals($ListLength($ClassMethod(..#SOURCE, "Lines", text, "\""taskClass\"": \""ens\.")), 2, "and no other Ens task class")
}

Method TestStaysInItsNamespace()
{
	Do ..AssertNone("\$namespace|\$znspace|\$zu\(5|\bznspace\b|\bzn\b|\$system\.process\.namespace|\^\||\^\[", "ZN ""OCUORDERS""", "Quit ##class(OcuTalon.Bridge.Purge).Run(daysToKeep)", "a namespace switch or an extended global reference")
	Do $$$AssertTrue($ClassMethod(..#SOURCE, "Matches", $Char(9)_"Kill ^|""OCUORDERS""|Ens.MessageHeaderD", "\^\||\^\["), "the scanner flags an extended global reference")
}

Method TestAuditNotNamed()
{
	Do ..AssertNone("%sys\.audit|%sys\.task\.purgeaudit|\^sys\(""audit", "Do ##class(%SYS.Audit).Delete()", "Quit ##class(OcuTalon.Bridge.Purge).Run(daysToKeep)", "the IRIS audit log")
}

}
