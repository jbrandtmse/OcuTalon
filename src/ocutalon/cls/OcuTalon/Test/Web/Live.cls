/// Tests of the live-events WebSocket (Story 31.1; AD-12, AD-13): the checks that run before Server() (Refusal and OnPreServer),
/// the loop's decision (Next), the frames (Frame), and the shell's non-upgrade answer (Accept). The socket itself is covered
/// end to end by web/e2e/live/socket.spec.ts. Each test makes its own session rows and streams (fresh references), records the
/// streams in ^OcuTalonTest("LiveSocket","streams") and removes them, and the wake resources they create, after the test, also
/// after a failure; onlineDemo is saved and put back.
Class OcuTalon.Test.Web.Live Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// Every Refusal case: each check alone fails with its own code, the checks are made in their order, and a good request is "".
Method TestRefusals()
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set good = $ListBuild(1, 0, "http://host.example", "host.example", 0, ref, 5, 7)
	Do $$$AssertEquals(..Refuse(good), "", "a good request is not refused")

	Do $$$AssertEquals(..Refuse(good, 1, 0), "no_role", "no role")
	Do $$$AssertEquals(..Refuse(good, 2, 1), "online_demo", "the online demo")
	Do $$$AssertEquals(..Refuse(good, 2, ""), "", "the flag empty is off")
	Do $$$AssertEquals(..Refuse(good, 3, "http://evil.example"), "wrong_origin", "another origin")
	Do $$$AssertEquals(..Refuse(good, 3, ""), "wrong_origin", "an empty origin")
	Do $$$AssertEquals(..Refuse(good, 3, "https://host.example"), "wrong_origin", "the right host over another scheme")
	Do $$$AssertEquals(..Refuse(good, 3, "http://other.example"), "wrong_origin", "the right scheme to another host")
	Do $$$AssertEquals(..Refuse(good, 3, "HTTP://HOST.EXAMPLE"), "", "the origin is compared without regard to case")
	Do $$$AssertEquals(..Refuse(good, 3, "https://host.example", 5, 1), "", "an https origin on a secure connection")
	Do $$$AssertEquals(..Refuse(good, 3, "http://host.example", 5, 1), "wrong_origin", "an http origin on a secure connection")
	Do $$$AssertEquals(..Refuse(good, 6, ""), "no_session", "no session")
	For cursor = "x", "", "1234567890123456", "-1", "1.5", " 1" {
		Do $$$AssertEquals(..Refuse(good, 7, cursor), "bad_cursor", "after '"_cursor_"'")
		Do $$$AssertEquals(..Refuse(good, 8, cursor), "bad_cursor", "afterInstance '"_cursor_"'")
	}
	For cursor = 0, 123456789012345 {
		Do $$$AssertEquals(..Refuse(good, 7, cursor), "", "after "_cursor_" is allowed")
		Do $$$AssertEquals(..Refuse(good, 8, cursor), "", "afterInstance "_cursor_" is allowed")
	}
	Set all = $ListBuild(0, 1, "http://evil.example", "host.example", 0, "", "x", "x")
	Do $$$AssertEquals(..Refuse(all), "no_role", "with every check failing, the role is first")
	Set $List(all, 1) = 1
	Do $$$AssertEquals(..Refuse(all), "online_demo", "then the online demo")
	Set $List(all, 2) = 0
	Do $$$AssertEquals(..Refuse(all), "wrong_origin", "then the origin")
	Set $List(all, 3) = "http://host.example"
	Do $$$AssertEquals(..Refuse(all), "no_session", "then the session")
	Set $List(all, 6) = ref
	Do $$$AssertEquals(..Refuse(all), "bad_cursor", "then the cursors")
}

/// OnPreServer's checks on a stand-in request and CSP session: a good upgrade keeps the cursors, the ref and the sign-out mark and
/// creates the wake resources; a wrong or empty Origin, a missing session, a bad cursor and the online demo each return an error
/// status and keep nothing.
Method TestOnPreServer()
{
	New %request, %session
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
		Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
		Set ^OcuTalonTest("LiveSocket", "streams", ref) = ""
		Set instance = ..NewStream()
		Do ##class(OcuTalon.Data.Session).MarkSignedOut(ref)
		Do ##class(OcuTalon.Data.Session).MarkSignedOut(ref)
		Set %session = ##class(%CSP.Session).%New("ZzLiveSocket", 0)
		Set %session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY) = ref

		Set %request = ..Request("http://host.example", "host.example", 12, 34)
		Set live = ..Socket(instance)
		Do $$$AssertStatusOK(live.Admit(1), "a good upgrade opens")
		Do $$$AssertEquals(live.SessionRef, ref, "it keeps the CSP session's ref")
		Do $$$AssertEquals(live.After_"|"_live.AfterInstance, "12|34", "and the cursors")
		Do $$$AssertEquals(live.Mark, 2, "and the sign-out mark")
		Do $$$AssertTrue(live.StartedAt > 0, "and the time it opened")
		Do $$$AssertEquals(live.SentAt, live.StartedAt, "the quiet time starts then")
		For name = ##class(OcuTalon.Live.Publish).WakeName(ref), ##class(OcuTalon.Live.Publish).WakeName(instance) {
			Do $$$AssertEquals($SYSTEM.Event.Defined(name), 1, "the wake resource "_name_" exists")
		}

		Do $$$AssertStatusNotOK(..Socket(instance).Admit(0), "a user without the role is refused")
		Set %request = ..Request("http://evil.example", "host.example", 12, 34)
		Set refused = ..Socket(instance)
		Do $$$AssertStatusNotOK(refused.Admit(1), "a wrong Origin is refused")
		Do $$$AssertEquals(refused.SessionRef, "", "and keeps nothing")
		Set %request = ..Request("", "host.example", 12, 34)
		Do $$$AssertStatusNotOK(..Socket(instance).Admit(1), "an empty Origin is refused")
		Set %request = ..Request("http://host.example", "host.example", "x", 34)
		Do $$$AssertStatusNotOK(..Socket(instance).Admit(1), "a bad cursor is refused")
		Set %request = ..Request("http://host.example", "host.example", 12, "")
		Do $$$AssertStatusNotOK(..Socket(instance).Admit(1), "a missing instance cursor is refused")
		Set %request = ..Request("http://host.example", "host.example", 12, 34)
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do $$$AssertStatusNotOK(..Socket(instance).Admit(1), "the online demo is refused")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// Next decides in its order: a changed sign-out mark ends the socket before anything is sent, the lifetime ends it, a stream that
/// is ahead sends, 25 quiet seconds give a heartbeat, otherwise it waits. A shortened lifetime is the seam.
Method TestNext()
{
	Set class = "OcuTalon.Web.Live"
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 101, 100, 0, 60), "wait", "nothing to do waits")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 1, 100, 101, 100, 1, 60), "end", "a changed mark ends before a send")
	Do $$$AssertEquals($ClassMethod(class, "Next", 3, 4, 100, 101, 100, 0, 60), "end", "a changed mark ends")
	Do $$$AssertEquals($ClassMethod(class, "Next", 3, 3, 100, 101, 100, 1, 60), "send", "an unchanged mark and a stream ahead sends")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 160, 150, 1, 60), "end", "the lifetime ends it, a stream ahead or not")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 159.9, 150, 0, 60), "wait", "just before the lifetime it waits")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 103, 100, 1, 3), "end", "a shortened lifetime of 3 seconds ends at 3")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 102.9, 100, 0, 3), "wait", "and not before")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 125, 100, 0, 60), "heartbeat", "25 quiet seconds give a heartbeat")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 124.9, 100, 0, 60), "wait", "24.9 do not")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 150, 140, 0, 60), "wait", "the quiet time counts from the last frame")
	Do $$$AssertEquals($ClassMethod(class, "Next", 0, 0, 100, 125, 100, 1, 60), "send", "a send comes before a heartbeat")
}

/// Frames are the body of /events: more than MAXEVENTS events give successive frames in Seq order, the streams are labelled
/// session and instance, a trace URL is added, the epoch is the session's, and no frame holds the stored SessionRef or a row id.
Method TestFrames()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set instance = ..NewStream()
	Set ^OcuTalonTest("LiveSocket", "streams", ref) = ""
	Set max = ##class(OcuTalon.Live.Event).#MAXEVENTS
	Set total = max + 5
	For i = 1:1:total {
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzLiveR"_i
		If i = 1 {
			Set payload.TraceHeaderId = 42
			Set payload.TraceNamespace = "OCUTALON"
		}
		Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(ref, "reminder", payload), "reminder "_i)
	}
	For i = 1:1:2 {
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzLiveI"_i
		Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(instance, "reminder", payload), "instance reminder "_i)
	}

	Set live = ..Socket(instance)
	Set live.SessionRef = ref
	Set live.After = 0
	Set live.AfterInstance = 0
	Set heads = $ListBuild(##class(OcuTalon.Live.Publish).LastSeq(ref), ##class(OcuTalon.Live.Publish).LastSeq(instance))
	Do $$$AssertEquals(heads, $ListBuild(total, 2), "the heads are the published counts")
	Set first = live.Frame($List(heads, 1), $List(heads, 2))
	Do $$$AssertEquals(first.epoch, session.Epoch, "the epoch is the session's")
	Do $$$AssertEquals(first.events.%Size(), max + 2, "the first frame holds MAXEVENTS session events and the instance events")
	Do $$$AssertEquals(live.After_"|"_live.AfterInstance, max_"|2", "the cursors moved to the highest Seq of each stream in the frame")
	Set seqs = "", labels = "", last = 0, ordered = 1
	Set iterator = first.events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If event.stream = "session" {
			If event.seq '= (last + 1) Set ordered = 0
			Set last = event.seq
		}
		If '$ListFind(labels, event.stream) Set labels = labels_$ListBuild(event.stream)
		If event.type '= "reminder" Set ordered = 0
	}
	Do $$$AssertEquals(ordered, 1, "session events run 1, 2, 3 ... in Seq order")
	Do $$$AssertEquals($ListToString(labels), "session,instance", "the streams are labelled session and instance")
	Set one = first.events.%Get(0)
	Do $$$AssertEquals(one.payload.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=42", "the trace URL is added")
	Do $$$AssertEquals(one.seq_"|"_one.stream, "1|session", "an envelope holds seq and stream")
	Set text = first.%ToJSON()
	Do $$$AssertEquals($Find(text, ref), 0, "no frame holds the stored SessionRef")
	Do $$$AssertEquals($Find(text, instance), 0, "nor the instance seam stream's reference")
	Do $$$AssertEquals($Find(text, """id"""), 0, "nor a row id")

	Set second = live.Frame(total, 2)
	Do $$$AssertEquals(second.events.%Size(), 5, "the second frame holds the five that are left")
	Do $$$AssertEquals(second.events.%Get(0).seq_","_second.events.%Get(4).seq, (max + 1)_","_total, "in Seq order")
	Do $$$AssertEquals(live.After, total, "and the cursor is at the head")
	Do $$$AssertEquals(live.Frame(total, 2), "", "caught up: nothing to send")
	Do $$$AssertEquals(live.After_"|"_live.AfterInstance, total_"|2", "and the cursors stay")

	Set live.After = 0
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", ref)
	Do $$$AssertEquals(live.Frame(total, 2), "", "events that the purge removed leave nothing to send")
	Do $$$AssertEquals(live.After, total, "and the cursor moves to the head that was read, so the loop cannot spin")
}

/// A request that is no upgrade (no WebSocket id) is answered 404 with no body, and Accept answers OK.
Method TestAccept()
{
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/", "GET", "", "", "", "host.example")
	Set %response = ##class(%CSP.Response).%New()
	Set file = ##class(%File).TempFilename("txt")
	Set io = $IO
	Open file:("NWS"):5
	Do $$$AssertTrue($Test, "the capture file opens")
	If '$Test Quit
	Use file
	Try {
		Set sc = ##class(OcuTalon.Web.Live).Accept()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Use io
	Close file
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(file)
	Set body = stream.Read(1000)
	Kill stream
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK(sc, "Accept answers OK")
	Do $$$AssertEquals(%response.Status, "404 Not Found", "404")
	Do $$$AssertEquals(body, "", "and writes no body")
}

/// --- helpers ---
/// Refusal for a list of the good arguments (hasRole, onlineDemo, origin, host, secure, sessionRef, after, afterInstance) with the
/// argument at position replaced by value, and the optional second replacement.
ClassMethod Refuse(arguments As %List, position As %Integer = 0, value As %String = "", position2 As %Integer = 0, value2 As %String = "") As %String [ Private ]
{
	If position Set $List(arguments, position) = value
	If position2 Set $List(arguments, position2) = value2
	Quit ##class(OcuTalon.Web.Live).Refusal($List(arguments, 1), $List(arguments, 2), $List(arguments, 3), $List(arguments, 4), $List(arguments, 5), $List(arguments, 6), $List(arguments, 7), $List(arguments, 8))
}

/// A stand-in upgrade request with the Origin and Host headers and the two cursors ("" leaves the cursor out).
ClassMethod Request(origin As %String, host As %String, after As %String, afterInstance As %String) As OcuTalon.Test.Web.StubRequest [ Private ]
{
	Set request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/", "GET", "", "", origin, host)
	If after '= "" Set request.Data("after", 1) = after
	If afterInstance '= "" Set request.Data("afterInstance", 1) = afterInstance
	Quit request
}

/// A socket object that serves the instance seam stream.
ClassMethod Socket(instance As %String) As OcuTalon.Web.Live [ Private ]
{
	Set live = ##class(OcuTalon.Web.Live).%New()
	Set live.InstanceStream = instance
	Quit live
}

/// A fresh stream, recorded for the clean-up.
ClassMethod NewStream() As %String [ Private ]
{
	Set stream = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("LiveSocket", "streams", stream) = ""
	Quit stream
}

/// Deletes the events, counters and wake resources of every stream that a test recorded, in this or an earlier run, and the rows of
/// Test.Data.Fixture.
ClassMethod Clean() [ Private ]
{
	Set stream = ""
	For {
		Set stream = $Order(^OcuTalonTest("LiveSocket", "streams", stream))
		Quit:stream=""
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", stream)
		Kill ^OcuTalonP.LiveEventC(stream), ^OcuTalonP.SessionM(stream)
		Do $SYSTEM.Event.Delete(##class(OcuTalon.Live.Publish).WakeName(stream))
	}
	Kill ^OcuTalonTest("LiveSocket")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
}

}
