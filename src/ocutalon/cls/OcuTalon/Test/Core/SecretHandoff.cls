/// Tests of OcuTalon.Core.SecretHandoff (Story 21.2; AD-1, AD-19): the in-memory hand-off of a secret by a reference. Safe on a slot: the
/// event resources are in memory, uniquely named, and every test deletes what it makes.
///   - TestRoundTrip: Put answers a reference of the form secret://handoff/<32 upper-case hex digits>, and Take of it answers the secret;
///   - TestSecondTakeFails: a second Take of the same reference fails, with an empty secret and no resource left;
///   - TestUnknownReference: a reference that names no resource, and every text that is not a reference of Put, fails with the one plain
///     text, which holds neither the reference nor a secret;
///   - TestDiscard: Take with timeoutSec 0 takes what is queued and deletes the resource, so that a later Take fails; on a reference that
///     was already taken it fails harmlessly;
///   - TestDiscardHelper: Discard deletes a secret nobody took, so that Take then fails with an empty secret, and Discard of a
///     reference already discarded, an empty one or a malformed one is not an error;
///   - TestEmptySecretRefused: Put of an empty value fails and creates no resource;
///   - TestWaitAndTimeout: a Take of a reference with no queued secret ends after its timeout and deletes the resource;
///   - TestCrossProcess: a second job takes the secret that this process put (the secret reaches another process), and the resource is gone;
///   - TestNothingPersisted: after a round trip no ^OcuTalon* global, no Ens.Util.Log row and no Ens.MessageHeader row holds the secret;
///   - TestTraceLeaksFinds (Story 21.14): TraceLeaks names ^Ens.Util.LogD for a text in a log row, ^Ens.MessageBodyD for a text in a SaveSettings message,
///     ^Ens.MessageHeaderD for one in a header and ^Ens.MessageBodyS for one in a stream node (the trace scan finds what it is meant to find), and names nothing once all are deleted.
/// Leaks(text) lists the ^OcuTalon* globals (OcuTalonTest excluded) whose data or subscripts hold the text; other test classes use it.
/// TraceLeaks(text) lists the trace globals (^Ens.MessageBodyD, ^Ens.MessageBodyS, ^Ens.MessageHeaderD and ^Ens.Util.LogD) that hold it: every OcuTalon message shares
/// the Ens.MessageBody extent, which Leaks (^OcuTalon* only) does not scan. Swap(body, uris) offers the address and user of a channels body to the hand-off, as the route does;
/// NewestChanges() is the parsed Changes of the newest stored SaveSettings message of the channels section.
Class OcuTalon.Test.Core.SecretHandoff Extends %UnitTest.TestCase
{

/// The class under test.
Parameter CLASS = "OcuTalon.Core.SecretHandoff";

/// The pattern of a reference.
Parameter REFERENCE = "^secret://handoff/[0-9A-F]{32}$";

/// The text that every failure holds.
Parameter FAILURE = "The secret hand-off failed.";

/// A secret that no other text holds: the process job and the clock make it unique.
ClassMethod NewSecret() As %String
{
	Quit "zzhand"_$Job_$Translate($ZHorolog, ".", "")_$Random(1000000)
}

/// The event resource of a reference.
ClassMethod Resource(uri As %String) As %String
{
	Quit ##class(OcuTalon.Core.SecretHandoff).#RESOURCE_$Piece(uri, "/", 4)
}

Method TestRoundTrip()
{
	Set secret = ..NewSecret()
	Set sc = $ClassMethod(..#CLASS, "Put", secret, .uri)
	Do $$$AssertStatusOK(sc, "Put accepts a secret")
	Do $$$AssertTrue($Match(uri, ..#REFERENCE), "the reference has the form secret://handoff/ and 32 hex digits")
	Do $$$AssertEquals($Find(uri, secret), 0, "the reference does not hold the secret")
	Set sc = $ClassMethod(..#CLASS, "Take", uri, .taken)
	Do $$$AssertStatusOK(sc, "Take of the reference succeeds")
	Do $$$AssertEquals(taken, secret, "and answers the secret that was put")
	Do $$$AssertEquals($SYSTEM.Event.Defined(..Resource(uri)), 0, "the resource is deleted")
	Set sc = $ClassMethod(..#CLASS, "Put", secret, .other)
	Do $$$AssertTrue(other '= uri, "a second Put makes a different reference")
	Do $ClassMethod(..#CLASS, "Take", other, .ignored, 0)
}

Method TestSecondTakeFails()
{
	Set secret = ..NewSecret()
	Do $ClassMethod(..#CLASS, "Put", secret, .uri)
	Do $ClassMethod(..#CLASS, "Take", uri, .first)
	Set sc = $ClassMethod(..#CLASS, "Take", uri, .second)
	Do $$$AssertStatusNotOK(sc, "a second Take of the same reference fails")
	Do $$$AssertEquals(second, "", "with an empty secret")
	Do $$$AssertEquals($SYSTEM.Event.Defined(..Resource(uri)), 0, "and no resource is left")
}

Method TestUnknownReference()
{
	Set secret = ..NewSecret()
	Set name = "00000000000000000000000000000000"
	Set bad = $ListBuild("", "x", "secret://handoff/", "secret://handoff/"_name_"0", "secret://handoff/"_$ZConvert(name, "L"), "secret://handoff/ZZ", "secret://other/"_name, "http://handoff/"_name, "OcuTalonHandoff"_name, "secret://handoff/"_name)
	Set position = 0
	While $ListNext(bad, position, uri) {
		Set sc = $ClassMethod(..#CLASS, "Take", uri, .taken, 0)
		Do $$$AssertStatusNotOK(sc, "Take of '"_uri_"' fails")
		Do $$$AssertEquals(taken, "", "with no secret")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue($Find(text, ..#FAILURE) > 0, "the text is the plain failure")
		Do $$$AssertEquals($Find(text, $Piece(uri, "/", 4)) && ($Piece(uri, "/", 4) '= ""), 0, "and does not name the reference")
	}
}

Method TestDiscard()
{
	Set secret = ..NewSecret()
	Do $ClassMethod(..#CLASS, "Put", secret, .uri)
	Set sc = $ClassMethod(..#CLASS, "Take", uri, .discard, 0)
	Do $$$AssertStatusOK(sc, "a Take with no wait takes what is queued")
	Do $$$AssertEquals(discard, secret, "the secret")
	Kill discard
	Do $$$AssertEquals($SYSTEM.Event.Defined(..Resource(uri)), 0, "and deletes the resource")
	Set sc = $ClassMethod(..#CLASS, "Take", uri, .again, 0)
	Do $$$AssertStatusNotOK(sc, "so that a later Take fails")
	Do $$$AssertEquals(again, "", "with no secret")
	Do $ClassMethod(..#CLASS, "Put", secret, .taken)
	Do $ClassMethod(..#CLASS, "Take", taken, .got)
	Set sc = $ClassMethod(..#CLASS, "Take", taken, .late, 0)
	Do $$$AssertStatusNotOK(sc, "the discard of a reference that was already taken fails harmlessly")
	Do $$$AssertEquals(late, "", "with no secret")
}

Method TestDiscardHelper()
{
	Do ##class(OcuTalon.Core.SecretHandoff).Put("zz-discard-secret-0123456789", .uri)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard(uri), "Discard")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .secret, 0), "the event is gone")
	Do $$$AssertEquals(secret, "", "and held nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard(uri), "a second Discard is not an error")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard(""), "nor an empty uri")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard("junk"), "nor a malformed one")
}

Method TestEmptySecretRefused()
{
	Set sc = $ClassMethod(..#CLASS, "Put", "", .uri)
	Do $$$AssertStatusNotOK(sc, "Put of an empty value fails")
	Do $$$AssertEquals(uri, "", "and answers no reference")
}

Method TestWaitAndTimeout()
{
	Set secret = ..NewSecret()
	Do $ClassMethod(..#CLASS, "Put", secret, .uri)
	Do $SYSTEM.Event.Clear(..Resource(uri))
	Set begun = $ZHorolog
	Set sc = $ClassMethod(..#CLASS, "Take", uri, .none, 1)
	Do $$$AssertStatusNotOK(sc, "a Take of a reference with no queued secret ends after its timeout")
	Do $$$AssertTrue(($ZHorolog - begun) < 4, "within a few seconds")
	Do $$$AssertEquals(none, "", "with no secret")
	Do $$$AssertEquals($SYSTEM.Event.Defined(..Resource(uri)), 0, "and the resource is deleted")
}

Method TestCrossProcess()
{
	Set secret = ..NewSecret()
	Do $ClassMethod(..#CLASS, "Put", secret, .uri)
	Set key = $Job_"x"_$Random(100000)
	Kill ^IRIS.Temp.OcuTalonHandoffTest(key)
	Set ^IRIS.Temp.OcuTalonHandoffTest(key, "uri") = uri
	Set ^IRIS.Temp.OcuTalonHandoffTest(key, "prefix") = $Extract(secret, 1, 6)
	Job ##class(OcuTalon.Test.Core.SecretHandoff).TakeIn(key)
	Set end = $ZHorolog + 20
	While ('$Data(^IRIS.Temp.OcuTalonHandoffTest(key, "done"))) && ($ZHorolog < end) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^IRIS.Temp.OcuTalonHandoffTest(key, "done")), 1, "the other job took the reference")
	Do $$$AssertEquals($Get(^IRIS.Temp.OcuTalonHandoffTest(key, "same")), 1, "and its value is the secret that this process put")
	Do $$$AssertEquals($SYSTEM.Event.Defined(..Resource(uri)), 0, "and the resource is gone")
	Kill ^IRIS.Temp.OcuTalonHandoffTest(key)
}

/// The job of TestCrossProcess: takes the reference that the test process stored under ^IRIS.Temp.OcuTalonHandoffTest(key) and records only
/// whether the secret it took starts with the test's prefix, never the secret.
ClassMethod TakeIn(key As %String)
{
	Set uri = $Get(^IRIS.Temp.OcuTalonHandoffTest(key, "uri"))
	Set sc = $ClassMethod(..#CLASS, "Take", uri, .taken, 10)
	Set ^IRIS.Temp.OcuTalonHandoffTest(key, "same") = ($$$ISOK(sc) && ($Extract(taken, 1, 6) = $Get(^IRIS.Temp.OcuTalonHandoffTest(key, "prefix"))) && (taken '= ""))
	Kill taken
	Set ^IRIS.Temp.OcuTalonHandoffTest(key, "done") = 1
}

Method TestNothingPersisted()
{
	Set secret = ..NewSecret()
	Do $ClassMethod(..#CLASS, "Put", secret, .uri)
	Do $ClassMethod(..#CLASS, "Take", uri, .taken)
	Do $$$AssertEquals(taken, secret, "the round trip works")
	Do $$$AssertEquals(..Leaks(secret), "", "no ^OcuTalon* global holds the secret")
	Do $$$AssertEquals(..TableHolds("Ens_Util.Log", "Text", secret), 0, "no Ens.Util.Log row holds it")
	Do $$$AssertEquals(..TableHolds("Ens.MessageHeader", "Description", secret), 0, "no Ens.MessageHeader row holds it")
	Kill taken
}

/// Story 21.14: the trace scan finds a text in each of its four globals (a log row, a SaveSettings message, a message header and a node of the body stream
/// global) and finds nothing once all are deleted. What a test makes is deleted even when it fails.
Method TestTraceLeaksFinds()
{
	Set text = "zztrace"_..NewSecret()
	Set (logId, bodyId, headerId, streamNode) = ""
	Do $$$AssertEquals(..TraceLeaks(text), "", "before anything holds the text, no trace global does")
	Do $$$AssertEquals(..TraceLeaks(""), "[empty text]", "an empty text is not a pass")
	Try {
		Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Core.SecretHandoff", "TestTraceLeaksFinds", text)
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens_Util.Log WHERE Text = ?", text)
		Set logId = $Select(result.%Next(): result.%GetData(1), 1: "")
		Do $$$AssertTrue(logId '= "", "the log row is written")
		Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
		Set command.Slug = "channels"
		Set command.Changes = "{""address"":"""_text_"""}"
		Set command.ActingUser = "zzadmin"
		Set command.Origin = "web_admin"
		Do $$$AssertStatusOK(command.%Save(), "the message is saved")
		Set bodyId = command.%Id()
		Set header = ##class(Ens.MessageHeader).%New()
		Set header.Description = text
		Do $$$AssertStatusOK(header.%Save(), "the header is saved")
		Set headerId = header.%Id()
		Set streamNode = "zztrace"_$Job_$Random(1000000)
		Set ^Ens.MessageBodyS(streamNode) = text
		Set found = ","_..TraceLeaks(text)_","
		Do $$$AssertTrue(found [ ",Ens.Util.LogD,", "TraceLeaks names Ens.Util.LogD for the log row")
		Do $$$AssertTrue(found [ ",Ens.MessageBodyD,", "and Ens.MessageBodyD for the message")
		Do $$$AssertTrue(found [ ",Ens.MessageHeaderD,", "and Ens.MessageHeaderD for the header")
		Do $$$AssertTrue(found [ ",Ens.MessageBodyS,", "and Ens.MessageBodyS for the stream node")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	If logId '= "" Do ##class(Ens.Util.Log).%DeleteId(logId)
	If bodyId '= "" Do ##class(OcuTalon.Msg.Command.SaveSettings).%DeleteId(bodyId)
	If headerId '= "" Do ##class(Ens.MessageHeader).%DeleteId(headerId)
	If streamNode '= "" Kill ^Ens.MessageBodyS(streamNode)
	Do $$$AssertEquals(..TraceLeaks(text), "", "all deleted, no trace global holds the text")
}

/// The ^OcuTalon* globals of this namespace (mappings included; OcuTalonTest and the empty ones excluded) whose data or subscripts hold the text,
/// as a comma list of names, or "" when none does.
ClassMethod Leaks(text As %String) As %String
{
	Set found = ""
	If text = "" Quit "[empty text]"
	Set statement = ##class(%SQL.Statement).%New()
	If $$$ISERR(statement.%PrepareClassQuery("%SYS.GlobalQuery", "NameSpaceList")) Quit "[the globals cannot be listed]"
	Set result = statement.%Execute($Namespace, "OcuTalon*", 0)
	While result.%Next() {
		Set name = result.%GetData(1)
		If name = "OcuTalonTest" Continue
		If ..Holds("^"_name, text) Set found = found_$Select(found = "": "", 1: ",")_name
	}
	Quit found
}

/// The trace globals (Ens.MessageBodyD, Ens.MessageBodyS, Ens.MessageHeaderD and Ens.Util.LogD, without the caret) whose data or subscripts hold the text,
/// as a comma list of names, or "" when none does. Every OcuTalon message is stored in the Ens.MessageBody extent, so a value in a command is found here.
ClassMethod TraceLeaks(text As %String) As %String
{
	If text = "" Quit "[empty text]"
	Set found = ""
	For name = "Ens.MessageBodyD", "Ens.MessageBodyS", "Ens.MessageHeaderD", "Ens.Util.LogD" {
		If ..Holds("^"_name, text) Set found = found_$Select(found = "": "", 1: ",")_name
	}
	Quit found
}

/// The Changes of the newest stored SaveSettings message of the channels section, parsed ({} when there is none): the body of the last save as the production holds it.
ClassMethod NewestChanges() As %DynamicObject
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Changes FROM OcuTalon_Msg_Command.SaveSettings WHERE Slug = 'channels' ORDER BY ID DESC")
	If (result.%SQLCODE < 0) || 'result.%Next() Quit {}
	Quit {}.%FromJSON(result.%GetData(1))
}

/// 1 when the global (its root, with the caret) holds the text in the data or in a subscript of any node.
ClassMethod Holds(root As %String, text As %String) As %Boolean [ Private ]
{
	Set hit = 0
	If $Data(@root) # 2 Set hit = (@root [ text)
	Set node = root
	For {
		Quit:hit
		Set node = $Query(@node, 1, data)
		Quit:node=""
		If (data [ text) || (node [ text) Set hit = 1
	}
	Quit hit
}

/// Offers each non-empty string member address and user of a channels body to the hand-off and puts the reference in its place, as the route does
/// (Story 21.14); each reference is appended to uris, so that the caller can take it back. Changes the body in place: pass a copy.
ClassMethod Swap(body As %DynamicObject, ByRef uris As %List) As %Status
{
	Set status = $$$OK
	If '$Data(uris) Set uris = ""
	For name = "address", "user" {
		If body.%GetTypeOf(name) '= "string" Continue
		Set value = body.%Get(name)
		If value = "" Continue
		Set sc = ##class(OcuTalon.Core.SecretHandoff).Put(value, .uri)
		Kill value
		If $$$ISERR(sc) {
			Set status = sc
			Continue
		}
		Set uris = uris_$ListBuild(uri)
		Do body.%Set(name, uri, "string")
	}
	Quit status
}

/// 1 when a row of the table holds the text in the column (a substring; a failed query counts as 1, so that it can never pass a check).
ClassMethod TableHolds(table As %String, column As %String, text As %String) As %Boolean
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_" WHERE "_column_" [ ?", text)
	If result.%SQLCODE < 0 Quit 1
	Do result.%Next()
	Quit (+result.%GetData(1) > 0)
}

}
