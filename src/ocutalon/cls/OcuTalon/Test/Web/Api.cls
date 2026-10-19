/// Tests of the REST skeleton's classes (matrix rows 9 to 12), called with stand-in request and response objects so
/// that no web application is needed: the bodies of /state and /events, the browser-envelope check, the 12 routes,
/// and the shape of every error. The HTTP rows are test-sign-in.sh's.
/// The fixture users are zzapistate<n>, zzapievents<n> and zzapiother<n>, with n from ^OcuTalonTest("WebApi","n") (never reset). Their
/// sessions, events and counters are removed in OnBeforeAllTests and OnAfterAllTests. Nothing is published on the
/// instance stream, and ^OcuTalonTest("TelegramIncluded") is restored.
Class OcuTalon.Test.Web.Api Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// 1 when ^OcuTalonTest("TelegramIncluded") existed before the tests, and its value.
Property SavedDefined As %Boolean;

Property SavedValue As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("WebApi", "n"))
	Set ..SavedDefined = ''$Data(^OcuTalonTest("TelegramIncluded"), value)
	Set ..SavedValue = $Get(value)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	If ..SavedDefined {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedValue
	} Else {
		Kill ^OcuTalonTest("TelegramIncluded")
	}
	Quit $SYSTEM.Status.OK()
}

/// The snapshot has the version, the zone, the session's epoch, each stream's last Seq, and empty chat and rail.
Method TestStateBody()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzapistate"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session")
	Set instanceBefore = ##class(OcuTalon.Live.Publish).LastSeq("instance")
	Do ..PublishReminders(session.Ref, 3, "a")
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Set expectedVersion = ""
	If ##class(%Dictionary.ClassDefinition).%ExistsId("%IPM.Storage.Module") {
		Set module = $ClassMethod("%IPM.Storage.Module", "NameOpen", "ocutalon")
		If $IsObject(module) Set expectedVersion = module.VersionString
	}
	Do $$$AssertEquals(body.version, expectedVersion, "version is the IPM module's, empty without IPM")
	Do $$$AssertEquals(body.instanceZone, ##class(OcuTalon.Data.Time).Zone(), "instanceZone")
	Do $$$AssertEquals(body.epoch, session.Epoch, "epoch is the session row's")
	Do $$$AssertEquals(body.streams.session, 3, "streams.session is the session stream's last Seq")
	Do $$$AssertEquals(body.streams.instance, instanceBefore, "streams.instance is the instance stream's last Seq")
	Do $$$AssertEquals(body.%GetTypeOf("chat"), "array", "chat is an array")
	Do $$$AssertEquals(body.chat.%Size(), 0, "chat is empty")
	Do $$$AssertEquals(body.rail.%GetTypeOf("approvals")_body.rail.%GetTypeOf("checks")_body.rail.%GetTypeOf("reminders")_body.rail.%GetTypeOf("decisions"), "arrayarrayarrayarray", "rail has four arrays")
	Do $$$AssertEquals(body.rail.approvals.%Size() + body.rail.checks.%Size() + body.rail.reminders.%Size() + body.rail.decisions.%Size(), 0, "and they are empty")
	Set keys = ""
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "version,instanceZone,epoch,streams,chat,rail", "the snapshot's keys")
	Set keys = ""
	Set iterator = body.rail.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "approvals,checks,reminders,decisions", "the rail's keys")
}

/// The poll returns a session's events after its cursor, 200 at most, in order, each in the envelope; another
/// session's events never appear.
Method TestEventsBody()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzapievents"_..Number, .sc)
	Set other = ##class(OcuTalon.Data.Session).ForUser("zzapiother"_..Number, .sc)
	Do ..PublishReminders(session.Ref, 250, "m")
	Do ..PublishReminders(other.Ref, 5, "o")
	Set instance = ##class(OcuTalon.Live.Publish).LastSeq("instance")

	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 0, instance)
	Do $$$AssertEquals(body.epoch, session.Epoch, "epoch is set")
	Do $$$AssertEquals(body.events.%Size(), 200, "the first poll returns 200 events")
	Set prefix = "ZzApi"_..Number_"m"
	Set seqs = ""
	Set foreign = 0
	Set malformed = 0
	For i = 0:1:body.events.%Size() - 1 {
		Set event = body.events.%Get(i)
		If event.seq '= (i + 1) Set seqs = seqs_" "_(i + 1)
		If event.stream '= "session" Set malformed = malformed + 1
		If $Extract(event.payload.ref, 1, $Length(prefix)) '= prefix Set foreign = foreign + 1
		If (event.type '= "reminder") || (event.%GetTypeOf("payload") '= "object") || (event.ts '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z") Set malformed = malformed + 1
		If event.%Size() '= 5 Set malformed = malformed + 1
	}
	Do $$$AssertEquals(seqs, "", "the events are 1 to 200 in order")
	Do $$$AssertEquals(foreign, 0, "no other session's event appears")
	Do $$$AssertEquals(malformed, 0, "each event is {seq, stream, ts, type, payload} with an object payload")

	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 200, instance)
	Do $$$AssertEquals(body.events.%Size(), 50, "after 200, the other 50")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 248, instance)
	Do $$$AssertEquals(body.events.%Size(), 2, "after 248, two events")
	Do $$$AssertEquals(body.events.%Get(0).seq_","_body.events.%Get(1).seq, "249,250", "249 and 250")
	Do $$$AssertEquals(body.events.%Get(0).payload.ref, prefix_"249", "and their payloads")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 250, instance)
	Do $$$AssertEquals(body.events.%Size(), 0, "after 250, nothing")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(other, 0, instance)
	Do $$$AssertEquals(body.events.%Size(), 5, "the other session sees its own 5")
	Do $$$AssertEquals(body.epoch, other.Epoch, "with its own epoch")
}

/// The browser envelope: exempt methods, the valid request, and each rule in its order.
Method TestEnvelopeError()
{
	Set api = "OcuTalon.Web.Api"
	For method = "GET", "HEAD", "OPTIONS", "get" {
		Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", method, "text/plain", "", "http://evil.example", "h:1", 0), "", method_" is exempt whatever the headers")
	}
	For method = "POST", "PUT", "PATCH", "DELETE" {
		Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", method, "application/json; charset=utf-8", "1", "http://h:1", "h:1", 0), "", method_" with a valid envelope")
		Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", method, "text/plain", "1", "http://h:1", "h:1", 0), "not_json", method_" with text/plain")
	}
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "http://h:1", "h:1", 0), "", "application/json alone")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "Application/JSON ; charset=UTF-8", "1", "http://h:1", "h:1", 0), "", "the media type is compared without regard to case")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "", "1", "http://h:1", "h:1", 0), "not_json", "no Content-Type")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/jsonx", "1", "http://h:1", "h:1", 0), "not_json", "another media type")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "", "http://h:1", "h:1", 0), "no_request_header", "no X-OcuTalon-Request")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "0", "http://h:1", "h:1", 0), "no_request_header", "X-OcuTalon-Request 0")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "11", "http://h:1", "h:1", 0), "no_request_header", "X-OcuTalon-Request 11")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "", "h:1", 0), "wrong_origin", "no Origin")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "http://h:2", "h:1", 0), "wrong_origin", "another port")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "http://evil.example", "h:1", 0), "wrong_origin", "another site")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "https://h:1", "h:1", 0), "wrong_origin", "https over an http connection")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "http://h:1", "h:1", 1), "wrong_origin", "http over an https connection")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "https://h:1", "h:1", 1), "", "https over an https connection")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "HTTP://H:1", "h:1", 0), "", "the origin is compared without regard to case")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "1", "http://h:1", "", 0), "wrong_origin", "no Host")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "text/plain", "", "", "h:1", 0), "not_json", "the Content-Type is judged before the header")
	Do $$$AssertEquals($ClassMethod(api, "EnvelopeError", "POST", "application/json", "", "", "h:1", 0), "no_request_header", "and the header before the origin")
}

/// The URL map holds exactly the 12 routes, each with its call.
Method TestRoutes()
{
	Set found = ..Routes("OcuTalon.Web.Api")
	Set expected = $ListBuild("GET /v1/state State", "GET /v1/events Events", "POST /v1/messages NotBuilt", "POST /v1/approvals/:ref/answer NotBuilt", "POST /v1/incidents/:ref/dismiss NotBuilt", "POST /v1/demo/break-feed NotBuilt", "POST /v1/mailbox/incoming NotBuilt", "POST /v1/mailbox/samples/:name NotBuilt", "POST /v1/guide/markers NotBuilt", "POST /v1/session/end NotBuilt", "POST /v1/pairing/code Pairing", "DELETE /v1/pairing Pairing")
	Do $$$AssertEquals($ListLength(found), 12, "12 routes")
	Do $$$AssertEquals($ListToString(found, "|"), $ListToString(expected, "|"), "the routes, in order")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "HandleCorsRequest"), 0, "no CORS handling")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "CHARSET"), "utf-8", "utf-8")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "HTTP501NOTIMPLEMENTED"), "501 Not Implemented", "the 501 status line")
}

/// A request without a session is answered 401 signed_out in the API's error shape, by the public superclass, with
/// no WWW-Authenticate header.
Method TestSignedOut()
{
	Do $$$AssertTrue($ClassMethod("OcuTalon.Web.Api", "%Extends", "OcuTalon.Web.Public.ApiBase"), "Api extends the public base class that answers before sign-in")
	Set raw = $Replace(..Call("Login", .response, 1), $Char(13), "")
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "401")
	Do $$$AssertEquals($Piece(raw, $Char(10), 1), "HTTP/1.1 401 Unauthorized", "the status line is sent")
	Set header = $ZConvert($Piece(raw, $Char(10, 10), 1), "L")
	Do $$$AssertTrue(header '[ "www-authenticate", "no WWW-Authenticate header is sent")
	Do $$$AssertTrue(header [ "content-type: application/json", "the body is JSON")
	Do $$$AssertEquals($Piece(raw, $Char(10, 10), 2, *), "{""error"":{""code"":""signed_out"",""message"":""You were signed out. Sign in again to continue.""}}", "the body is the error shape")
}

/// Every error is {"error": {"code", "message"}} with its status; a 500 never shows its cause.
Method TestErrorShape()
{
	Set body = ..Call("Fail", .response, 403, "no_role", "A message")
	Do $$$AssertEquals(response.Status, "403 Forbidden", "Fail sets the status line")
	Do $$$AssertEquals(response.ContentType, "application/json", "and the content type")
	Do $$$AssertEquals(body, "{""error"":{""code"":""no_role"",""message"":""A message""}}", "and writes the error body")

	Set body = ..Call("ReportHttpStatusCode", .response, "404 Not Found")
	Do $$$AssertEquals(response.Status, "404 Not Found", "404")
	Do $$$AssertEquals(body, "{""error"":{""code"":""not_found"",""message"":""OcuTalon has nothing at this address.""}}", "not_found")

	Set body = ..Call("ReportHttpStatusCode", .response, "405 Method Not Allowed")
	Do $$$AssertEquals(response.Status, "405 Method Not Allowed", "405")
	Do $$$AssertEquals(response.ContentType, "application/json", "the content type that Http405 cleared is back")
	Do $$$AssertEquals(body, "{""error"":{""code"":""method_not_allowed"",""message"":""This address doesn't accept that kind of request.""}}", "method_not_allowed")

	Set body = ..Call("ReportHttpStatusCode", .response, "500 Internal Server Error", $SYSTEM.Status.Error(5001, "zz secret detail"))
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "500")
	Do $$$AssertEquals(body, "{""error"":{""code"":""server_error"",""message"":""Something went wrong inside OcuTalon. Try again.""}}", "server_error")
	Do $$$AssertTrue(body '[ "secret", "the cause is not in the body")

	Set body = ..Call("NotBuilt", .response, "zz")
	Do $$$AssertEquals(response.Status, "501 Not Implemented", "an unbuilt route answers 501")
	Do $$$AssertEquals(body, "{""error"":{""code"":""not_built"",""message"":""This part of OcuTalon isn't built yet.""}}", "not_built")

	Set body = ..Call("Events", .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a poll without cursors is refused")
	Do $$$AssertEquals($Piece($Piece(body, """code"":""", 2), """", 1), "bad_cursor", "with bad_cursor")
}

/// A cursor that is missing, negative, fractional, padded or not a number is refused with 400 bad_cursor.
Method TestBadCursors()
{
	For pair = "|", "0|", "|0", "-1|0", "0|-1", "1.5|0", "0|1.5", "a|0", "0|b", " 1|0", "0|1 ", "1e3|0", "1234567890123456|0" {
		Set body = ..Poll($Piece(pair, "|", 1), $Piece(pair, "|", 2), .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "'"_pair_"' is refused")
		Do $$$AssertTrue(body [ "bad_cursor", "'"_pair_"' says bad_cursor")
	}
}

/// The pairing routes answer 404 while Telegram is not included, and 501 once it is.
Method TestPairing()
{
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Set body = ..Call("Pairing", .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "404 while Telegram is not included")
	Do $$$AssertTrue(body [ "not_found", "with not_found")
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Set body = ..Call("Pairing", .response)
	Do $$$AssertEquals(response.Status, "501 Not Implemented", "501 when Telegram is included")
	Do $$$AssertTrue(body [ "not_built", "with not_built")
}

/// --- helpers ---
/// The routes of a dispatch class's URL map, as a list of "<Method> <Url> <Call>" in map order.
ClassMethod Routes(class As %String) As %List
{
	Set routes = ""
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class_"||UrlMap")
	Set sc = ##class(%XML.TextReader).ParseStream(xdata.Data, .reader)
	If $SYSTEM.Status.IsError(sc) Quit routes
	While reader.Read() {
		If (reader.NodeType = "element") && (reader.Name = "Route") {
			Set values = ""
			For name = "Method", "Url", "Call" {
				Do reader.MoveToAttributeName(name)
				Set values = values_$ListBuild(reader.Value)
				Do reader.MoveToElement()
			}
			Set routes = routes_$ListBuild($ListToString(values, " "))
		}
	}
	Quit routes
}

/// Calls a class method of Api with a stand-in request and response, and returns the body that it wrote.
Method Call(method As %String, Output response, args...) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzApiTest", 0)
	Set %response.ContentType = ""
	Quit ..Run(method, .response, args...)
}

/// Calls a class method of Api with the %request and %response that the caller has set, and returns what it wrote.
Method Run(method As %String, Output response, args...) As %String [ Private ]
{
	Set file = ##class(%File).TempFilename("json")
	Set io = $IO
	Open file:("NWS"):5
	If '$Test Quit ""
	Use file
	Try {
		Set sc = $ClassMethod("OcuTalon.Web.Api", method, args...)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Use io
	Close file
	Set response = %response
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set body = stream.Read(100000)
	Kill stream
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Quit body
}

/// Calls Events with the given cursors and a stand-in request, and returns the body that it wrote.
Method Poll(after As %String, afterInstance As %String, Output response) As %String [ Private ]
{
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %request.Data("after", 1) = after
	Set %request.Data("afterInstance", 1) = afterInstance
	Quit ..Run("Events", .response)
}

/// Publishes count reminders on a session's stream; the payload refs are ZzApi<n><prefix><i>.
Method PublishReminders(stream As %String, count As %Integer, prefix As %String) [ Private ]
{
	For i = 1:1:count {
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzApi"_..Number_prefix_i
		Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reminder", payload)
		If $SYSTEM.Status.IsError(sc) Quit
	}
	Do $$$AssertStatusOK(sc, count_" events are published")
}

/// Deletes the fixture sessions with their events and counters.
ClassMethod Clean() [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzapi'")
	Set result = statement.%Execute()
	While result.%Next() {
		Set stream = result.%Get("Ref")
		Set delete = ##class(%SQL.Statement).%New()
		Set sc = delete.%Prepare("DELETE FROM OcuTalon_Live.Event WHERE Stream = ?")
		Do delete.%Execute(stream)
		Kill ^OcuTalonP.LiveEventC(stream)
	}
	Set delete = ##class(%SQL.Statement).%New()
	Set sc = delete.%Prepare("DELETE FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzapi'")
	Do delete.%Execute()
}

}
