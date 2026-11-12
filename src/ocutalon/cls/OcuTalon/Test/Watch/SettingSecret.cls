Include Ensemble

/// The leak scan of the setting history (Story 36.1; Planner ruling V3, AD-15, AD-17; NFR-11). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), through
/// Test.Watch.Case, over the running production and the Orders demo production in OCUORDERS.
///   - TestSecretAppearsNowhere: the item's ApiKey setting is given a secret, a Tick takes the production's first snapshot, the setting is given a second secret and
///     a Tick records the change, whose row has both values blank. Neither secret, and not the salted hash that the newest snapshot keeps to tell the next change, is
///     then in the stored data of OcuTalon (every ^OcuTalon* global but the hash's own table), the trace (Ens.MessageHeader), the event log (Ens_Util.Log), the answer of
///     any GET route of the web API (including /v1/state), a requested digest (the model request and the notices), an incident's notice (its slots and their
///     rendering) or the evidence an evaluation capture writes (snapshot.json and case.json). The hash is in the globals of SettingSnapshot and in no other.
///     Every read is also asserted to have produced output, so that a read that returned nothing cannot pass.
Class OcuTalon.Test.Watch.SettingSecret Extends OcuTalon.Test.Watch.Case [ DependsOn = (OcuTalon.Test.Watch.OrdersDefinition, OcuTalon.Test.Watch.SettingHistory) ]
{

Parameter DEFINITION = "OcuTalon.Test.Watch.OrdersDefinition";

Parameter HISTORY = "OcuTalon.Test.Watch.SettingHistory";

Parameter HANDOFF = "OcuTalon.Test.Core.SecretHandoff";

Parameter DEMO = "OcuTalon.Test.Demo.Production";

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

/// The dispatch classes whose GET routes are read.
Parameter ROUTECLASSES = "OcuTalon.Web.Api,OcuTalon.Web.History,OcuTalon.Web.Usage,OcuTalon.Web.Documents,OcuTalon.Web.HookSettings,OcuTalon.Web.Public.Status";

/// The folder of the evaluation capture, below the temporary folder of the instance.
Parameter TMP = "/tmp/zz-setting-secret/";

/// 1 while the Orders failures are held (HoldFailures), until OnAfterOneTest releases them.
Property Held As %Boolean [ InitialExpression = 0 ];

/// The folder of the evaluation capture, "" before the test makes it.
Property Folder As %String(MAXLEN = 200);

/// The sessions of the digest, comma-separated, for the clean-up.
Property DigestSessions As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $ClassMethod(..#HISTORY, "DropHistory")
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#DEFINITION, "Put", 0))
	Do $ClassMethod(..#HISTORY, "DropHistory")
	If ..Held Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#DEMO, "ReleaseFailures"))
	Set ..Held = 0
	If ..Folder '= "" Do ##class(%File).RemoveDirectoryTree(..Folder)
	Set ..Folder = ""
	If ..DigestSessions '= "" Do $ClassMethod(..#PROBE, "Clean", ..DigestSessions)
	Do $ClassMethod(..#PROBE, "Reset")
	Set ..DigestSessions = ""
	Quit sc
}

/// The text of every surface, one entry for each, as a dynamic object of name to text: each is asserted to be non-empty.
Method Surfaces(session As %String, headerKey As %String) As %DynamicObject [ Private ]
{
	Set surfaces = {}
	Do ..AddRoutes(session, surfaces)
	Do ..AddDigest(session, surfaces)
	Do ..AddNotice(session, surfaces)
	Do ..AddEval(headerKey, surfaces)
	Quit surfaces
}

/// The answers of the GET routes of ROUTECLASSES, as the CSP session of the session. A route with a :ref parameter is read for each ref that its list route gave.
Method AddRoutes(session As %String, surfaces As %DynamicObject) [ Private ]
{
	New %request, %response, %session
	Set %session = ##class(%CSP.Session).%New("ZzSettingSecret", 0)
	Set %session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY) = session
	Set refs = ""
	For c = 1:1:$Length(..#ROUTECLASSES, ",") {
		Set class = $Piece(..#ROUTECLASSES, ",", c)
		Set routes = ##class(OcuTalon.Test.Web.Api).Routes(class)
		Set position = 0
		While $ListNext(routes, position, route) {
			If $Piece(route, " ", 1) '= "GET" Continue
			Set method = $Piece(route, " ", 3)
			Set url = $Piece(route, " ", 2)
			Set name = class_" "_route
			Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
			Set %response = ##class(%CSP.Response).%New()
			Set %response.ContentType = ""
			If method = "Events" {
				Set %request.Data("after", 1) = 0
				Set %request.Data("afterInstance", 1) = 0
			}
			If url [ ":ref" {
				For i = 1:1:$Length(refs, ",") {
					Set ref = $Piece(refs, ",", i)
					If ref = "" Continue
					Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, class, method, ref)
					Do $$$AssertStatusOK(sc, name_" for "_ref_" returns OK")
					Do surfaces.%Set(name_" "_ref, body)
				}
				Continue
			}
			Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, class, method)
			Do $$$AssertStatusOK(sc, name_" returns OK")
			Do surfaces.%Set(name, body)
			If (class = "OcuTalon.Web.Documents") && (url = "") {
				Try {
					Set iterator = {}.%FromJSON(body).documents.%GetIterator()
					While iterator.%GetNext(, .document) {
						Set refs = refs_document.ref_","
					}
				} Catch {
					Set refs = ""
				}
			}
		}
	}
	Do $$$AssertTrue(surfaces.%Get("OcuTalon.Web.Api GET /v1/state State") '= "", "/v1/state is among the routes that were read")
	Set state = surfaces.%Get("OcuTalon.Web.Api GET /v1/state State")
	Do $$$AssertTrue($Extract(state) = "{", "and it answered a JSON object")
}

/// A requested digest of the session on a shadow of the digest process with its seams under test control: the model request, and the notices once the answer comes.
Method AddDigest(session As %String, surfaces As %DynamicObject) [ Private ]
{
	Set ..DigestSessions = ..DigestSessions_$Select(..DigestSessions = "": "", 1: ",")_session
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set item = $ClassMethod("OcuTalon.Test.Digest.Store", "NewRef")
	Do $ClassMethod("OcuTalon.Test.Digest.Store", "NewRow", session, item, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60), .sc)
	Do $$$AssertStatusOK(sc, "a digest item is saved")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the digest process is made")
	If '$IsObject(host) Quit
	Set host.%SessionId = $Parameter(..#PROBE, "TRACESESSION")
	Set host.OwnChannels = "web"
	Set host.Only = session
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = session
	Set compose.Kind = "requested"
	Set compose.IdempotencyKey = session_":settingsecret"
	Set compose.WindowEnd = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 60)
	Set compose.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowEnd, -86400)
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(compose, .response), "the digest is requested")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "summary"), 1, "and one request goes to the model")
	Do surfaces.%Set("digest model request", $ClassMethod(..#PROBE, "Summary", 1).%ToJSON())
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "One saved item."
	Set reply.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Kill response
	Do $$$AssertStatusOK(host.OnResponse(compose, .response, "", reply, "summary"), "the answer is handled")
	Do $$$AssertTrue($ClassMethod(..#PROBE, "Count", "notice") > 0, "and the digest is sent")
	For n = 1:1:$ClassMethod(..#PROBE, "Count", "notice") {
		Set record = $ClassMethod(..#PROBE, "Record", "notice", n)
		Set slots = {}.%FromJSON($List(record, 5))
		Do surfaces.%Set("digest notice "_n, $List(record, 5))
		Set text = ""
		Set parts = slots.parts.%GetIterator()
		While parts.%GetNext(, .part) {
			Set text = text_##class(OcuTalon.Msg.Catalog).Render(part.key, part.slots, "telegram")_$Char(10)
		}
		Set lines = slots.lines.%GetIterator()
		While lines.%GetNext(, .line) {
			Set text = text_##class(OcuTalon.Msg.Catalog).Render(line.key, line.slots, "telegram")_$Char(10)
		}
		Do surfaces.%Set("digest rendering "_n, text)
	}
}

/// The notice of a fixture incident on the Orders production: its slots and the Telegram rendering of its catalog key.
Method AddNotice(session As %String, surfaces As %DynamicObject) [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(session, now, ..#ORDERS, ..#ORDERSPRODUCTION, {"FirstAt": (now), "LastAt": (now), "Cause": "The order date was not in the expected format."})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set key = ##class(OcuTalon.Watch.Notice).Key(incident)
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.Seq = 1
	Set group.ItemName = $ClassMethod(..#DEFINITION, "%GetParameter", "ITEM")
	Set group.Count = 1
	Set group.NoticeCount = 1
	Set group.ErrorSummary = "The order date was not in the expected format."
	Set group.FirstAt = now
	Set groups = ##class(%ListOfObjects).%New()
	Do groups.Insert(group)
	Set slots = ##class(OcuTalon.Watch.Notice).Slots(incident, groups, .sc)
	Do $$$AssertStatusOK(sc, "the incident has a notice")
	Do $$$AssertTrue(key '= "", "with the catalog key "_key)
	If $IsObject(slots) {
		Do surfaces.%Set("incident notice slots", slots.%ToJSON())
		Do surfaces.%Set("incident notice rendering", ##class(OcuTalon.Msg.Catalog).Render(key, slots, "telegram", .sc))
	}
}

/// The evidence that an evaluation capture of one failing Orders batch writes: snapshot.json and case.json. The failing orders are sent while the Orders failures
/// are held, so that the poller makes no incident of them.
Method AddEval(headerKey As %String, surfaces As %DynamicObject) [ Private ]
{
	Set case = {"name": "zz-setting-secret", "description": "A synthetic case for the leak scan.", "expectation": {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"}}
	Do case.%Set("heldOut", 0, "boolean")
	Set ..Folder = ##class(%File).NormalizeDirectory(##class(%File).SubDirectoryName(..#TMP, ##class(OcuTalon.Bridge.Ids).NewRef()))
	Set sc = ##class(OcuTalon.Eval.Record).Capture(case, ..#ORDERS, ..#ORDERSPRODUCTION, $ClassMethod(..#DEFINITION, "%GetParameter", "ITEM"), headerKey, ..Folder, .pack)
	Do $$$AssertStatusOK(sc, "Capture records the failing batch")
	Set directory = ##class(%File).SubDirectoryName(..Folder, "zz-setting-secret")
	For file = ##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(OcuTalon.Eval.Record).#CASEFILE {
		Set stream = ##class(%Stream.FileCharacter).%New()
		Do $$$AssertStatusOK(stream.LinkToFile(##class(%File).NormalizeFilename(file, directory)), file_" was written")
		Do surfaces.%Set("eval "_file, stream.Read(10000000))
	}
	If $IsObject($Get(pack)) Do surfaces.%Set("eval pack", pack.%ToJSON())
}

Method TestSecretAppearsNowhere()
{
	If '..Ready() Quit
	Set a = "zz-leak-a-"_$Random(1000000000)_"-"_$Random(1000000000)
	Set b = "zz-leak-b-"_$Random(1000000000)_"-"_$Random(1000000000)
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_session
	Do ..Watch(session)
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, a, , "ApiKey"), "the item's ApiKey setting is given the first secret")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, b, , "ApiKey"), "and then the second")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set changes = $ClassMethod(..#HISTORY, "Changes", "ApiKey")
	Do $$$AssertEquals(changes.%Size(), 1, "the change is recorded")
	If changes.%Size() = 1 Do $$$AssertEquals(changes.%Get(0).oldValue_"|"_changes.%Get(0).newValue_"|"_changes.%Get(0).credential, "||1", "with both values blank")
	Set entry = $ClassMethod(..#HISTORY, "Entry", $ClassMethod(..#HISTORY, "Newest"), $ClassMethod(..#DEFINITION, "%GetParameter", "ITEM"), "ApiKey")
	Do $$$AssertTrue($IsObject(entry), "the newest snapshot holds the setting")
	If '$IsObject(entry) Quit
	Set hash = entry.hash
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(hash, b), "with a hash of the second secret")

	// the stored data
	Set handoff = ..#HANDOFF
	Do $$$AssertEquals($ClassMethod(handoff, "Leaks", a), "", "no ^OcuTalon* global holds the first secret")
	Do $$$AssertEquals($ClassMethod(handoff, "Leaks", b), "", "or the second")
	Set own = $Extract(##class(OcuTalon.Data.SettingSnapshot).#DEFAULTGLOBAL, 2, *)
	Set holding = $ClassMethod(handoff, "Leaks", hash)
	Do $$$AssertTrue(holding [ own, "the hash is where it is kept: "_holding)
	Set stray = ""
	For i = 1:1:$Length(holding, ",") {
		Set name = $Piece(holding, ",", i)
		If $Extract(name, 1, $Length(own)) '= own Set stray = stray_name_" "
	}
	Do $$$AssertEquals(stray, "", "and in the globals of SettingSnapshot alone")

	// the trace and the log
	For text = a, b, hash {
		Do $$$AssertEquals($ClassMethod(handoff, "TableHolds", "Ens.MessageHeader", "Description", text), 0, "no trace header holds it")
		Do $$$AssertEquals($ClassMethod(handoff, "TableHolds", "Ens_Util.Log", "Text", text), 0, "no event-log row holds it")
	}

	// the surfaces
	Set floor = ..HoldAndFail()
	If floor = "" Quit
	Set surfaces = ..Surfaces(session, floor)
	Set iterator = surfaces.%GetIterator()
	Set count = 0
	While iterator.%GetNext(.name, .text) {
		Set count = count + 1
		Do $$$AssertTrue(text '= "", name_" produced output")
		Do $$$AssertEquals($Find(text, a), 0, name_" does not hold the first secret")
		Do $$$AssertEquals($Find(text, b), 0, name_" does not hold the second secret")
		Do $$$AssertEquals($Find(text, hash), 0, name_" does not hold the hash")
	}
	Do $$$AssertTrue(count > 15, count_" surfaces were read")
}

/// Holds the Orders failures, sends one failing batch and waits for it to be in the error status; the key of its header (h<id>), or "" with a failed assertion.
Method HoldAndFail() As %String [ Private ]
{
	Do $$$AssertStatusOK($ClassMethod(..#DEMO, "HoldFailures"), "the Orders failures are held, so that the poller makes no incident of the batch")
	Set ..Held = 1
	If '..Fail(1) Quit ""
	Set failed = ..WaitFailed(1)
	If failed.%Size() '= 1 Quit ""
	Quit "h"_failed.%Get(0).id
}

}
