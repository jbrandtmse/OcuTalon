/// Tests of how NoticesIn joins and forwards a notification (Story 6.3; AD-26, AD-31, AD-32). Safe on a slot: no production runs
/// there, so the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.NoticesInProbe, which records its forward
/// instead of sending. The real Interoperability path is the job of OcuTalon.Test.Core.NoticesInProduction.
///   - TestOutsideAContext: with no bridge context the send is a session of its own, whose SuperSession is the TraceRef of the
///     notification's Session row, to Notify; an empty or unknown session, and the literal instance, give no SuperSession;
///   - TestInsideAContext: inside a context the send is in the thread session of the context's ThreadSessionId, with the
///     context's SuperSession;
///   - TestNoThreadSession: a ThreadSessionId of 0, or none, is a session of its own that still carries the SuperSession;
///   - TestNotANotification: an input that is not a Notification is an error status and nothing is sent;
///   - TestSendNeedsAProduction: where no production runs, Send is an error status.
/// The context of the test process is ended before and after the tests; the fixture rows are removed by Test.Data.Fixture.Clean.
Class OcuTalon.Test.Core.NoticesIn Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("NoticesIn", "n"))
	Set ..Refs = ""
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// With no context the notification goes to Notify in a session of its own, and its SuperSession is the TraceRef of the Session
/// row of its SessionRef; with no SessionRef, an unknown one or the literal instance there is no SuperSession.
Method TestOutsideAContext()
{
	Set session = ..Session("outside")
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do $$$AssertTrue(traceRef '= "", "the fixture session has a TraceRef: "_traceRef)
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnProcessInput(..Notification(session), .output), "the notification is accepted")
	Do $$$AssertEquals(probe.Sends, 1, "it is forwarded once")
	Do $$$AssertEquals(probe.SeenTarget, "Notify", "to Notify")
	Do $$$AssertEquals(probe.SeenSessionId, "", "in a session of its own")
	Do $$$AssertEquals(probe.SeenSuperSession, traceRef, "whose SuperSession is the TraceRef of the notification's session")
	For ref = "", "zzmissing"_..Number, "instance" {
		Set probe = ..NewProbe()
		Do $$$AssertStatusOK(probe.OnProcessInput(..Notification(ref), .output), "the notification of session '"_ref_"' is accepted")
		Do $$$AssertEquals(probe.Sends_"|"_probe.SeenSessionId_"|"_probe.SeenSuperSession, "1||", "and sent with no SuperSession")
	}
}

/// Inside a context the send is in the thread session of the context's ThreadSessionId, with the context's SuperSession, whatever
/// the notification's session says.
Method TestInsideAContext()
{
	Set session = ..Session("inside")
	Set super = "zzss"_..Number
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.ThreadSessionId = 424242
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "a context with a thread session begins")
	Try {
		Set probe = ..NewProbe()
		Do $$$AssertStatusOK(probe.OnProcessInput(..Notification(session), .output), "the notification is accepted")
		Do $$$AssertEquals(probe.Sends, 1, "it is forwarded once")
		Do $$$AssertEquals(probe.SeenTarget, "Notify", "to Notify")
		Do $$$AssertEquals(probe.SeenSessionId, 424242, "in the thread session of the context")
		Do $$$AssertEquals(probe.SeenSuperSession, super, "with the SuperSession of the context")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// A context with no ThreadSessionId, or with 0 (which no trace session has), sends in a session of its own that still carries
/// the SuperSession.
Method TestNoThreadSession()
{
	Set session = ..Session("nothread")
	Set super = "zzss"_..Number
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "a context with no thread session begins")
	Try {
		Set probe = ..NewProbe()
		Do $$$AssertStatusOK(probe.OnProcessInput(..Notification(session), .output), "the notification is accepted")
		Do $$$AssertEquals(probe.Sends, 1, "it is forwarded once")
		Do $$$AssertEquals(probe.SeenSessionId, "", "with no ThreadSessionId the send starts a session of its own")
		Do $$$AssertEquals(probe.SeenSuperSession, super, "which still carries the SuperSession")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.ThreadSessionId = 0
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "a context whose ThreadSessionId is 0 begins")
	Try {
		Set probe = ..NewProbe()
		Do $$$AssertStatusOK(probe.OnProcessInput(..Notification(session), .output), "the notification is accepted")
		Do $$$AssertEquals(probe.Sends, 1, "it is forwarded once")
		Do $$$AssertEquals(probe.SeenSessionId, "", "a ThreadSessionId of 0 is no thread: the send starts a session of its own")
		Do $$$AssertEquals(probe.SeenSuperSession, super, "which still carries the SuperSession")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// An input that is not a Notification (a command, a string, nothing) is an error status that names what the service takes, and
/// nothing is sent.
Method TestNotANotification()
{
	Set probe = ..NewProbe()
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	For input = command, "zz"_..Number, "" {
		Set sc = probe.OnProcessInput(input, .output)
		Do $$$AssertStatusNotOK(sc, "'"_$Select($IsObject(input): $ClassName(input), 1: input)_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Msg.Notification", "the error names what it takes: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Set sc = probe.OnProcessInput(, .output)
	Do $$$AssertStatusNotOK(sc, "an omitted input is refused")
	Do $$$AssertEquals(probe.Sends, 0, "nothing was sent")
}

/// Where no production runs, Send is an error status and sends nothing (a slot never has one; on a stack the case is skipped).
Method TestSendNeedsAProduction()
{
	If ##class(Ens.Director).IsProductionRunning() {
		Do $$$AssertSkipped("A production runs in "_$Namespace_": the case is for namespaces with none")
		Quit
	}
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.NoticesIn).Send(..Notification("")), "Send is an error status")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zznotice"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe.
Method NewProbe() As OcuTalon.Test.Core.NoticesInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.NoticesInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Quit probe
}

/// A tell-now Notification for the session.
Method Notification(session As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "tellnow"
	Set notification.CatalogKey = "notice.tellNow"
	Set notification.Slots = {"whatHappened": "zz summary", "reason": "zz reason."}.%ToJSON()
	Quit notification
}

}
