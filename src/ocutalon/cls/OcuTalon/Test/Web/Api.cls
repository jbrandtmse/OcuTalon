/// Tests of the REST skeleton's classes (matrix rows 9 to 12), called with stand-in request and response objects so
/// that no web application is needed: the bodies of /state and /events, the browser-envelope check, the 12 routes,
/// and the shape of every error; and (Story 2.2) the snapshot's sections, the resolution of the caller's session from the
/// CSP session, the sign-out call and the 404 of a record the session can't see. The HTTP rows are test-sign-in.sh's.
/// The rows of the Story 2.2 tests come from Test.Data.Fixture, and so do the decisions, usage rows and check rows of
/// TestStateChatDecision (Story 2.6) and the notice cards of TestStateChatNotices and TestStateChatNoticeCardFields (Story 2.7).
/// The fixture users are zzapistate<n>, zzapievents<n> and zzapiother<n>, with n from ^OcuTalonTest("WebApi","n") (never reset), and
/// zzapistateinstance<n> and zzapieventsinstance<n>, whose streams stand in for the instance stream. Their
/// sessions, events and counters are removed in OnBeforeAllTests and OnAfterAllTests. Nothing is published on the
/// instance stream, and ^OcuTalonTest("TelegramIncluded") is restored. The tests of the snapshot's flags write the
/// public setting onlineDemo and the demo.mode row, which OnBeforeAllTests saves and OnAfterAllTests puts back; the row
/// goes through Test.Demo.Step's row helpers. Capture, Collect and Written are shared with the other web tests that call
/// a class method and read what it wrote.
/// Story 2.9: a turn's chat entry and a decision of the rail carry traceUrl (Web.TraceLink), the turn's with the PAGE of its
/// position for the user's page size and choice of events, and a check in a namespace with no trace application carries none; the
/// chat.message of EventsBody carries it too. The user's own ^EnsPortal.Settings($Username,"VisualTrace") is saved before the
/// tests (in a process-private global), unset before each test and put back after them.
/// Story 2.13: a rail decision of a chat turn, and the decision nested in the turn's entry, carry the turn's target and position
/// (the same traceUrl as the turn's own), and an approval whose incident has a trace carries the incident's.
/// Story 4.2: with demo mode on the snapshot's last key is guide (Demo.Guide.Compute's view), and with it off there is no guide key
/// (TestStateBody, TestStateFlags); the markers route is GuideMarkers (TestRoutes; Test.Web.GuideApi has the endpoint).
/// Story 2.10: the snapshot's status holds the active conditions that Status.Active computes, member for member (TestStateBody).
Class OcuTalon.Test.Web.Api Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// 1 when ^OcuTalonTest("TelegramIncluded") existed before the tests, and its value.
Property SavedDefined As %Boolean;

Property SavedValue As %String;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// 1 when the demo.mode row existed before the tests.
Property SavedModeFound As %Boolean;

/// The value of the demo.mode row before the tests.
Property SavedModeValue As %String(MAXLEN = 1000);

/// The UpdatedAt of the demo.mode row before the tests.
Property SavedModeUpdatedAt As %String(MAXLEN = 20);

/// 1 when the user had Visual Trace settings before the tests.
Property SavedTraceSettings As %Boolean;

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTest.WebApi
	Set ..SavedTraceSettings = $Data(^EnsPortal.Settings($Username, "VisualTrace")) \ 10
	If ..SavedTraceSettings Merge ^||OcuTalonTest.WebApi = ^EnsPortal.Settings($Username, "VisualTrace")
	Kill ^OcuTalonTest("ApiProbe")
	Do ..Clean()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("WebApi", "n"))
	Set ..SavedDefined = ''$Data(^OcuTalonTest("TelegramIncluded"), value)
	Set ..SavedValue = $Get(value)
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .modeValue, .modeUpdatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = modeValue, ..SavedModeUpdatedAt = modeUpdatedAt
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^EnsPortal.Settings($Username, "VisualTrace")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^EnsPortal.Settings($Username, "VisualTrace")
	If ..SavedTraceSettings Merge ^EnsPortal.Settings($Username, "VisualTrace") = ^||OcuTalonTest.WebApi
	Kill ^||OcuTalonTest.WebApi
	Kill ^OcuTalonTest("ApiProbe")
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Do ..Clean()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("WebApi", "job")
	If ..SavedDefined {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedValue
	} Else {
		Kill ^OcuTalonTest("TelegramIncluded")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Quit $SYSTEM.Status.OK()
}

/// The snapshot has the version, the zone, the session's epoch, each stream's last Seq, empty chat and rail for a session
/// with no rows, the session row's user, the models' display names, the Telegram block and the status conditions, which
/// are the active ones that Status.Active computes (Story 2.10). A fixture session's stream stands in for the instance stream.
Method TestStateBody()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzapistate"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session")
	Set instance = ##class(OcuTalon.Data.Session).ForUser("zzapistateinstance"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session whose stream stands in for the instance stream")
	Do ..PublishReminders(session.Ref, 3, "a")
	Do ..PublishReminders(instance.Ref, 2, "b")
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Set body = ##class(OcuTalon.Web.Api).StateBody(session, instance.Ref)
	Set expectedVersion = ""
	If ##class(%Dictionary.ClassDefinition).%ExistsId("%IPM.Storage.Module") {
		Set module = $ClassMethod("%IPM.Storage.Module", "NameOpen", "ocutalon")
		If $IsObject(module) Set expectedVersion = module.VersionString
	}
	Do $$$AssertEquals(body.version, expectedVersion, "version is the IPM module's, empty without IPM")
	Do $$$AssertEquals(body.instanceZone, ##class(OcuTalon.Data.Time).Zone(), "instanceZone")
	Do $$$AssertEquals(body.epoch, session.Epoch, "epoch is the session row's")
	Do $$$AssertEquals(body.streams.session, 3, "streams.session is the session stream's last Seq")
	Do $$$AssertEquals(body.streams.instance, 2, "streams.instance is the instance stream's last Seq")
	Do $$$AssertEquals(body.%GetTypeOf("chat"), "array", "chat is an array")
	Do $$$AssertEquals(body.chat.%Size(), 0, "chat is empty")
	Do $$$AssertEquals(body.rail.%GetTypeOf("approvals")_body.rail.%GetTypeOf("checks")_body.rail.%GetTypeOf("reminders")_body.rail.%GetTypeOf("decisions"), "arrayarrayarrayarray", "rail has four arrays")
	Do $$$AssertEquals(body.rail.approvals.%Size() + body.rail.checks.%Size() + body.rail.reminders.%Size() + body.rail.decisions.%Size(), 0, "and they are empty")
	Set keys = ""
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "version,instanceZone,epoch,streams,chat,rail,user,onlineDemo,demoMode,models,telegram,status,phone,guide", "the snapshot's keys, with the phone and then the guide last while demo mode is on")
	Do $$$AssertEquals(body.%GetTypeOf("phone")_"|"_body.phone.%Size(), "array|0", "phone is an empty array for a session with no phone message")
	Do ##class(OcuTalon.Demo.Guide).Compute(session.Ref).%JSONExportToString(.guideJson)
	Do $$$AssertEquals(body.guide.%ToJSON(), guideJson, "the guide is Demo.Guide.Compute's view")
	Do $$$AssertEquals(body.user, session.IrisUser, "user is the session row's")
	Do $$$AssertEquals(body.user, "zzapistate"_..Number, "and the fixture session's user")
	Do $$$AssertEquals(body.%GetTypeOf("onlineDemo")_body.%GetTypeOf("demoMode"), "booleanboolean", "the two flags are booleans")
	Set keys = ""
	Set iterator = body.models.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "triage,diagnosis,chat", "the models' keys")
	Do $$$AssertEquals(body.models.triage_"|"_body.models.diagnosis_"|"_body.models.chat, "Claude Haiku 5.5|Claude Haiku 5.5|Claude Haiku 5.5", "every agent's model is Claude Haiku 5.5")
	Set keys = ""
	Set iterator = body.rail.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "approvals,checks,reminders,decisions", "the rail's keys")
	Do $$$AssertEquals(body.%GetTypeOf("status"), "array", "status is an array")
	Set expected = ##class(OcuTalon.Live.Payload.Status).Active(session.Ref)
	Do $$$AssertEquals(body.status.%Size(), expected.%Size(), "status holds as many conditions as Status.Active computes")
	For i = 0:1:expected.%Size() - 1 {
		Do $$$AssertEquals(body.status.%Get(i).%ToJSON(), expected.%Get(i).%ToJSON(), "status member "_i_" is the computed condition")
		Do $$$AssertEquals(body.status.%Get(i).active, 1, "and it is active")
	}
	Set keys = ""
	Set iterator = body.telegram.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "included,state,botUserName,paired,displayName,pausedUntil", "the Telegram block's keys")
	Do $$$AssertEquals(body.telegram.state_"|"_body.telegram.botUserName_"|"_body.telegram.pausedUntil, "off||", "the bot state is off, with no bot name and no pause")
	Do $$$AssertEquals(body.telegram.%GetTypeOf("included")_body.telegram.%GetTypeOf("paired"), "booleanboolean", "included and paired are booleans")
	Do $$$AssertEquals(body.telegram.paired_"|"_body.telegram.displayName, "0|", "a session with no pairing is not paired")
}

/// onlineDemo is true only when the public setting is 1, and demoMode only when the demo.mode row is "1": the four
/// combinations, and an absent row or setting reads false.
Method TestStateFlags()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzapistate"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session")
	For online = 0, 1 {
		For mode = 0, 1 {
			Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", online)
			Do ##class(OcuTalon.Test.Demo.Step).Put(mode, ##class(OcuTalon.Data.Time).NowUtc())
			Set body = ##class(OcuTalon.Web.Api).StateBody(session)
			Set label = "onlineDemo "_online_", demo.mode "_mode
			Do $$$AssertEquals(body.onlineDemo, online, label_": onlineDemo")
			Do $$$AssertEquals(body.demoMode, mode, label_": demoMode")
			Do $$$AssertEquals(body.%GetTypeOf("onlineDemo")_body.%GetTypeOf("demoMode"), "booleanboolean", label_": both are booleans")
			Do $$$AssertEquals(body.%IsDefined("guide"), mode, label_": guide is present exactly when demoMode is true")
			Do $$$AssertEquals(body.%IsDefined("phone"), mode, label_": phone is present exactly when demoMode is true")
		}
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(body.onlineDemo_body.demoMode, "00", "an absent setting and an absent row are both false")
	Do $$$AssertEquals(body.%IsDefined("guide")_body.%IsDefined("phone"), "00", "and the snapshot has no guide and no phone")
	Do ##class(OcuTalon.Test.Demo.Step).Put("yes", ##class(OcuTalon.Data.Time).NowUtc())
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(body.demoMode, 0, "demo mode is on only for the value 1")
	Do $$$AssertEquals(body.%IsDefined("guide")_body.%IsDefined("phone"), "00", "and the snapshot has no guide and no phone for another value")
}

/// The snapshot's phone holds the session's own simulated-phone messages (Kind phone) as Phone payloads, the newest PHONEMAX,
/// oldest first; a mailbox message, another session's messages and (with demo mode off) every message are not in it.
Method TestStatePhone()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapiphone"_..Number)
	Set theirs = $ClassMethod(fixture, "Session", "zzapiphoneother"_..Number)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(mine)
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Set m1 = $ClassMethod(fixture, "SimMessage", mine, {"CreatedAt": "2030-01-01T10:00:01Z", "Text": ("zz first"_$Char(10)_"second line")})
	Set m2 = $ClassMethod(fixture, "SimMessage", mine, {"CreatedAt": "2030-01-01T10:00:02Z", "Text": "zz second"})
	Set m3 = $ClassMethod(fixture, "SimMessage", mine, {"CreatedAt": "2030-01-01T10:00:02Z", "Text": "zz third"})
	Do $ClassMethod(fixture, "SimMessage", mine, {"CreatedAt": "2030-01-01T10:00:09Z", "Kind": "mailbox", "Text": "zz mail"})
	Do $ClassMethod(fixture, "SimMessage", theirs, {"CreatedAt": "2030-01-01T10:00:09Z", "Text": "zz theirs"})
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(body.phone.%Size(), 3, "the session's three phone messages")
	Set refs = ""
	For i = 0:1:body.phone.%Size() - 1 {
		Set refs = refs_$Select(refs = "": "", 1: ",")_body.phone.%Get(i).ref
	}
	Do $$$AssertEquals(refs, m1_","_m2_","_m3, "oldest first, the later ID last at the same second")
	Set first = body.phone.%Get(0)
	Set keys = ""
	Set iterator = first.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "ref,direction,text,createdAt", "a message is a Phone payload, which leaves out its empty approvalRef")
	Do $$$AssertEquals(first.direction_"|"_first.text_"|"_first.approvalRef_"|"_first.createdAt, "out|zz first"_$Char(10)_"second line||2030-01-01T10:00:01Z", "with its direction, text and time")
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(body.%IsDefined("phone"), 0, "with demo mode off the snapshot has no phone")
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	For i = 1:1:##class(OcuTalon.Web.Api).#PHONEMAX {
		Do $ClassMethod(fixture, "SimMessage", mine, {"CreatedAt": "2030-01-01T11:00:00Z"})
	}
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(body.phone.%Size(), ##class(OcuTalon.Web.Api).#PHONEMAX, "at most PHONEMAX messages")
	Do $$$AssertEquals(body.phone.%Get(0).createdAt, "2030-01-01T11:00:00Z", "the newest ones: the three older messages are cut")
}

/// Every section of the snapshot comes from the session's own rows through Ownership, in its order and with its
/// filters: the chat merges the turns and the visible noticed incidents by time (a turn before an incident of the same
/// time), the rail holds the pending requests, every check, the pending reminders and the 20 newest decide decisions,
/// telegram holds the release switch and the pairing. Another session's rows are not in it.
Method TestStateSections()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapisections"_..Number)
	Set theirs = $ClassMethod(fixture, "Session", "zzapisectionsother"_..Number)
	Set production = "Zz.Api"_..Number_".Watched"
	Set check1 = $ClassMethod(fixture, "Check", mine, "ZZNS", production)
	Set check2 = $ClassMethod(fixture, "Check", mine, "ZZNS", "Zz.Api"_..Number_".Second")
	Set turn1 = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:00:01Z")
	Set turnRow = ##class(OcuTalon.Data.Turn).RefIndexOpen(turn1)
	Set turnRow.TraceHeaderId = 9001, turnRow.TraceItemIndex = 46, turnRow.TraceItemIndexNoEvents = 30
	Do $$$AssertStatusOK(turnRow.%Save(), "the first turn has a trace target at position 46 (30 without events)")
	Set turn2 = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:00:03Z", "queued")
	Set own = $ClassMethod(fixture, "Incident", mine, "2030-01-01T10:00:02Z", , , {"TraceHeaderId": 777})
	Set unnoticed = $ClassMethod(fixture, "Incident", mine, "")
	Set instance = $ClassMethod(fixture, "Incident", "instance", "2030-01-01T10:00:03Z", "ZZNS", production)
	Set theirTurn = $ClassMethod(fixture, "Turn", theirs)
	Set theirIncident = $ClassMethod(fixture, "Incident", theirs)
	Set approval1 = $ClassMethod(fixture, "Approval", mine, own, "pending", "2030-01-01T12:00:00Z")
	Set approval2 = $ClassMethod(fixture, "Approval", "instance", instance, "pending", "2030-01-01T11:00:00Z")
	Set answered = $ClassMethod(fixture, "Approval", mine, own, "answered")
	Set theirApproval = $ClassMethod(fixture, "Approval", theirs)
	Set reminder1 = $ClassMethod(fixture, "Reminder", mine, "2030-01-01T12:00:00Z")
	Set reminder2 = $ClassMethod(fixture, "Reminder", mine, "2030-01-01T11:00:00Z")
	Set fired = $ClassMethod(fixture, "Reminder", mine, "2030-01-01T10:00:00Z", "fired")
	Set expectedDecisions = ""
	For i = 1:1:22 {
		Set ref = $ClassMethod(fixture, "Decision", mine, "decide", "2030-01-01T10:00:"_$Extract(100 + i, 2, 3)_"Z", $Select(i = 21: {"ItemId": (turnRow.ItemId)}, 1: ""))
		If i > 2 Set expectedDecisions = ref_$Select(expectedDecisions = "": "", 1: ",")_expectedDecisions
	}
	Set turnDecision = $ClassMethod(fixture, "Decision", mine, "turn", "2030-01-01T11:00:00Z")
	Set pairing = $ClassMethod(fixture, "Pairing", mine, "Zz chat")
	Set checkRow = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(check1)
	Set checkRow.DisplayName = "Zz display", checkRow.NextDueAt = "2030-03-01T00:00:00Z", checkRow.LastRunAt = "2030-02-01T00:00:00Z"
	Set checkRow.Result = "failed", checkRow.Finding = "zz finding", checkRow.LastRunHeaderId = 31
	Do $$$AssertStatusOK(checkRow.%Save(), "the first check has a run")
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")

	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(mine)
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Set localJson = body.%ToJSON()
	Set chat = body.chat
	Do $$$AssertEquals(chat.%Size(), 4, "the chat holds two turns and two visible incidents")
	Do $$$AssertEquals(..Items(chat), "chat.message:"_turn1_",incident:"_own_",chat.message:"_turn2_",incident:"_instance, "by time, a turn before an incident of the same time, and no unnoticed or foreign item")
	Set first = chat.%Get(0).payload
	Do $$$AssertEquals(first.channel_"|"_first.state_"|"_first.createdAt_"|"_first.fromGuide, "web|done|2030-01-01T10:00:01Z|0", "a turn's payload is ChatMessage.FromRow")
	Do $$$AssertEquals(chat.%Get(0).payload.%GetTypeOf("fromGuide"), "boolean", "fromGuide is a boolean")
	Set incident = chat.%Get(1).payload
	Do $$$AssertEquals(incident.state_"|"_incident.count_"|"_incident.cause, "open|3|zz cause", "an incident's payload is Incident.FromRow")

	Set rail = body.rail
	Do $$$AssertEquals(..Refs(rail.approvals), approval2_","_approval1, "approvals: pending only, by RaisedAt, with the visible instance incident's")
	Set request = rail.approvals.%Get(1)
	Do $$$AssertEquals(request.state_"|"_request.incidentRef_"|"_request.kind, "pending|"_own_"|fix", "an approval's payload is Approval.FromRow")
	Do $$$AssertEquals(request.dryRun.affected_"|"_request.dryRun.field_"|"_request.dryRun.itemNoun.one_"|"_request.dryRun.itemNoun.other, "4|OrderDate|order|orders", "its dry run is parsed")
	Do $$$AssertEquals(request.traceHeaderId_"|"_request.traceNamespace, "777|"_$Namespace, "an approval of an incident with a trace carries the incident's TraceHeaderId")
	Do $$$AssertEquals(request.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=777", "and its trace URL, with no PAGE")
	Set watched = rail.approvals.%Get(0)
	Do $$$AssertEquals(watched.%IsDefined("traceHeaderId")_watched.%IsDefined("traceUrl"), "00", "an approval of an incident with no trace carries none")
	Do $$$AssertEquals(..Refs(rail.checks), check1_","_check2, "checks: all of them, by ID")
	Set view = rail.checks.%Get(0)
	Do $$$AssertEquals(view.kind_"|"_view.namespace_"|"_view.production_"|"_view.displayName, "production|ZZNS|"_production_"|Zz display", "a check's payload is CheckView's")
	Do $$$AssertEquals(view.nextDueAt_"|"_view.lastRunAt_"|"_view.result_"|"_view.finding, "2030-03-01T00:00:00Z|2030-02-01T00:00:00Z|failed|zz finding", "with its run")
	Do $$$AssertEquals(view.traceHeaderId_"|"_view.traceNamespace, "31|ZZNS", "a check with a run carries its trace")
	Do $$$AssertEquals(view.%IsDefined("traceUrl"), 0, "but a namespace with no trace application gives it no traceUrl")
	Set bare = rail.checks.%Get(1)
	Do $$$AssertEquals(bare.traceHeaderId_"|"_bare.traceNamespace, "|", "a check with no run carries none")
	Do $$$AssertEquals(..Refs(rail.reminders), reminder2_","_reminder1, "reminders: pending only, by DueAt")
	Do $$$AssertEquals(rail.reminders.%Get(0).state_"|"_rail.reminders.%Get(0).dueAt, "pending|2030-01-01T11:00:00Z", "a reminder's payload is Reminder.FromRow")
	Do $$$AssertEquals(rail.decisions.%Size(), 20, "decisions: the 20 newest of the 22")
	Do $$$AssertEquals(..Refs(rail.decisions), expectedDecisions, "of kind decide only, newest first")
	Set decision = rail.decisions.%Get(0)
	Do $$$AssertEquals(decision.model_"|"_decision.traceHeaderId_"|"_decision.traceNamespace, "Claude Haiku 5.5|42|"_$Namespace, "a decision's payload is Decision.FromRow")
	Do $$$AssertTrue(decision.itemSummary [ "zz summary", "its summary is the row's")
	Do $$$AssertEquals(decision.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=42", "and it carries its trace URL, with no PAGE")
	Do $$$AssertEquals(decision.%IsDefined("traceItemIndex")_decision.%IsDefined("traceItemIndexNoEvents"), "00", "a decision of an Item that is no turn has no item index")
	Set ofTurn = rail.decisions.%Get(1)
	Do $$$AssertEquals(ofTurn.itemId, turnRow.ItemId, "the decision made from the first turn's Item is the second newest")
	Do $$$AssertEquals(ofTurn.traceHeaderId_"|"_ofTurn.traceItemIndex_"|"_ofTurn.traceItemIndexNoEvents, "9001|46|30", "a rail decision of a chat turn carries the turn's header and positions, not its TraceSessionId")
	Do $$$AssertEquals(ofTurn.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=9001&PAGE=2", "and its trace URL opens the day's thread at page 2, where the turn is")
	Do $$$AssertEquals(ofTurn.traceUrl, chat.%Get(0).payload.traceUrl, "which is the turn's own trace URL")

	Do $$$AssertEquals(body.telegram.included_"|"_body.telegram.paired_"|"_body.telegram.displayName_"|"_body.telegram.state, "1|1|Zz chat|off", "telegram: included, paired, the chat's name")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(body.telegram.included, 0, "telegram.included follows the release switch")
	Do $$$AssertEquals(body.%GetTypeOf("status"), "array", "status is an array")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(..Items(body.chat), "chat.message:"_turn1_",incident:"_own_",chat.message:"_turn2, "with onlineDemo on, the instance incident leaves the chat")
	Do $$$AssertEquals(..Refs(body.rail.approvals), approval1, "and its request leaves the rail")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	For json = localJson, body.%ToJSON() {
		Do $$$AssertTrue(('$Find(json, theirTurn)) && ('$Find(json, theirIncident)) && ('$Find(json, theirApproval)), "no row of the other session is in the snapshot, with or without the instance records")
	}
}

/// DW-65: the snapshot's chat holds the newest 100 entries, oldest first, merged as before. A session with 103 done turns
/// one second apart (10:00:01 to 10:01:43) and two noticed incidents of its own, one older than every turn (10:00:00) and one
/// at the second of turn 50 (10:00:50), has 105 entries; the chat drops the oldest five (the first incident and turns 1 to
/// 4) and keeps turns 5 to 50, the second incident, then turns 51 to 103. Another session's rows are not in it.
Method TestStateChatCapped()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapicap"_..Number)
	Set theirs = $ClassMethod(fixture, "Session", "zzapicapother"_..Number)
	Set oldest = $ClassMethod(fixture, "Incident", mine, "2030-01-01T10:00:00Z")
	Set middle = $ClassMethod(fixture, "Incident", mine, "2030-01-01T10:00:50Z")
	Set theirTurn = $ClassMethod(fixture, "Turn", theirs, "2030-01-01T10:00:30Z")
	Set refs = mine_","_theirs_","_oldest_","_middle_","_theirTurn
	Set expected = ""
	For i = 1:1:103 {
		Set turn = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:"_$Extract(100 + (i \ 60), 2, 3)_":"_$Extract(100 + (i # 60), 2, 3)_"Z")
		Set refs = refs_","_turn
		If i < 5 Continue
		Set expected = expected_$Select(expected = "": "", 1: ",")_"chat.message:"_turn
		If i = 50 Set expected = expected_",incident:"_middle
	}
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(body.chat.%Size(), 100, "the chat holds 100 entries of the 105")
	Do $$$AssertEquals(..Items(body.chat), expected, "turns 5 to 50, the second incident, then turns 51 to 103: the newest 100, oldest first, merged by time")
	Do $$$AssertTrue(('$Find(..Items(body.chat), oldest)), "the incident older than every turn is dropped")
	Do $$$AssertTrue(('$Find(body.%ToJSON(), theirTurn)), "the other session's turn is not in the snapshot")
	Do $ClassMethod(fixture, "Clean", refs)
}

/// Story 2.6: the snapshot's chat entry for a turn carries what chat.message carries, so a reload rebuilds every strip: the
/// shown decision (the triage decision of a reply, the reply decision of a fallback), the turn's cost over both decisions'
/// usage rows, and the check key and rows. A turn with no decision has none of them, and another session's decision and usage
/// rows are not read into the entry.
Method TestStateChatDecision()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapidecision"_..Number)
	Set theirs = $ClassMethod(fixture, "Session", "zzapidecisionother"_..Number)
	Set triage = $ClassMethod(fixture, "Decision", mine, "decide", "2030-01-01T10:00:00Z", {"Outcome": "act", "Reasons": "zz one\nzz two", "Confidence": 0.92, "Model": "claude-haiku-5-5"})
	Set reply = $ClassMethod(fixture, "Decision", mine, "turn", "2030-01-01T10:00:05Z", {"Outcome": "tellnow", "Fallback": 1, "FallbackReason": "timeout"})
	Do $ClassMethod(fixture, "Usage", triage, mine, {"InputTokens": 1000, "OutputTokens": 300, "CostUSD": 0.0003})
	Do $ClassMethod(fixture, "Usage", reply, mine, {"InputTokens": 84, "OutputTokens": 12, "CostUSD": 0.0005})
	Do $ClassMethod(fixture, "Usage", triage, theirs, {"InputTokens": 7000, "OutputTokens": 7000, "CostUSD": 0.7})
	Set replied = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:00:01Z")
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(replied)
	Set decisionRow = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(triage)
	Set decisionRow.ItemId = row.ItemId
	Do $$$AssertStatusOK(decisionRow.%Save(), "the triage decision is the decision of the first turn's Item")
	Set row.TriageDecisionRef = triage
	Set row.TurnDecisionRef = reply
	Set row.CheckKey = "checks.allPassed"
	Set row.CheckRows = "[{""result"":""passed"",""entry"":""Orders production"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""},{""result"":""failed"",""entry"":""Warehouse queue"",""finding"":""zz finding"",""checkedAt"":""2030-01-01T10:01:00Z""}]"
	Set row.TraceHeaderId = 9001
	Set row.TraceItemIndex = 41
	Set row.TraceItemIndexNoEvents = 30
	Do $$$AssertStatusOK(row.%Save(), "the first turn has both decisions, two check rows and a trace target at position 41 (30 without events)")
	Set fallback = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:00:02Z")
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(fallback)
	Set row.TriageDecisionRef = triage
	Set row.TurnDecisionRef = reply
	Set row.ReplyCatalogKey = "conversation.turnFallback"
	Set row.FallbackReason = "timeout"
	Do $$$AssertStatusOK(row.%Save(), "the second turn is a fallback with the same decisions")
	Set bare = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:00:03Z", "queued")

	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(..Items(body.chat), "chat.message:"_replied_",chat.message:"_fallback_",chat.message:"_bare, "the chat holds the three turns")
	Set first = body.chat.%Get(0).payload
	Do $$$AssertEquals(first.decision.ref_"|"_first.decision.outcome_"|"_first.decision.reasons, triage_"|act|zz one"_$Char(10)_"zz two", "a reply: the triage decision, with its outcome and reasons")
	Do $$$AssertEquals(+first.turnCost.inputTokens_"|"_+first.turnCost.outputTokens_"|"_+first.turnCost.costUSD, "1084|312|.0008", "and the turn's cost, the sum of both decisions and no other session's")
	Do $$$AssertEquals(first.checkKey_"|"_first.checks.%Size(), "checks.allPassed|2", "and the check key with its two rows")
	Do $$$AssertEquals(first.checks.%Get(1).result_"|"_first.checks.%Get(1).entry_"|"_first.checks.%Get(1).finding_"|"_first.checks.%Get(1).checkedAt, "failed|Warehouse queue|zz finding|2030-01-01T10:01:00Z", "each row with its result, entry, finding and time")
	Do $$$AssertEquals(first.traceItemIndex_"|"_first.traceItemIndexNoEvents, "41|30", "the entry carries both positions of its trace target")
	Do $$$AssertEquals(first.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=9001&PAGE=2", "and its trace URL, at the page of position 41 for 40 items a page")
	Do $$$AssertEquals(first.decision.traceUrl, first.traceUrl, "the nested decision of the turn's Item opens where the turn does")
	Do $$$AssertEquals(first.decision.traceHeaderId_"|"_first.decision.traceItemIndex_"|"_first.decision.traceItemIndexNoEvents, "9001|41|30", "with the turn's header and positions")
	Set second = body.chat.%Get(1).payload
	Do $$$AssertEquals(second.%IsDefined("traceUrl")_"|"_second.%IsDefined("traceItemIndex"), "0|0", "a turn with no trace target has no traceUrl and no position")
	Do $$$AssertEquals(second.decision.ref_"|"_second.decision.fallbackReason_"|"_+second.turnCost.costUSD, reply_"|timeout|.0008", "a fallback: the reply decision and the same cost")
	Do $$$AssertEquals(second.decision.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=42", "its decision is of no turn's Item, so it opens its own TraceSessionId, with no PAGE")
	Do $$$AssertEquals(second.%IsDefined("checkKey")_"|"_second.%IsDefined("checks"), "0|0", "with no check rows")
	Set third = body.chat.%Get(2).payload
	Do $$$AssertEquals(third.%IsDefined("decision")_"|"_third.%IsDefined("turnCost"), "0|0", "a turn with no decision has neither decision nor cost")
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(10)
	Do ##class(EnsPortal.VisualTrace).SetShowEvents(0)
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(body.chat.%Get(0).payload.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=9001&PAGE=3", "with 10 items a page and events hidden, position 30 is page 3: the viewer's own settings")
	Do $$$AssertEquals(body.chat.%Get(0).payload.decision.traceUrl, body.chat.%Get(0).payload.traceUrl, "and the nested decision opens on the same page")
	Do $ClassMethod(fixture, "Clean", mine_","_theirs_","_triage_","_reply_","_replied_","_fallback_","_bare)
}

/// DW-65: where the cut falls inside a group of entries with the same time, the chat keeps the later rows, and the entries
/// of one time stay in the merge's order: turns before incidents, each by row ID. A session with three turns and two noticed
/// incidents, all at 10:01:00, and 96 turns after them one second apart (10:02:00 to 10:03:35) has 101 entries; the chat
/// drops the oldest, the first of the three turns, and keeps the second and third turn, the two incidents in row order, then
/// the 96 turns.
Method TestStateChatCappedTies()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapicapties"_..Number)
	Set tied = "2030-01-01T10:01:00Z"
	Set refs = mine
	For i = 1:1:3 {
		Set turn(i) = $ClassMethod(fixture, "Turn", mine, tied)
		Set refs = refs_","_turn(i)
	}
	For i = 1:1:2 {
		Set incident(i) = $ClassMethod(fixture, "Incident", mine, tied)
		Set refs = refs_","_incident(i)
	}
	Set expected = "chat.message:"_turn(2)_",chat.message:"_turn(3)_",incident:"_incident(1)_",incident:"_incident(2)
	For i = 0:1:95 {
		Set later = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:"_$Extract(102 + (i \ 60), 2, 3)_":"_$Extract(100 + (i # 60), 2, 3)_"Z")
		Set refs = refs_","_later
		Set expected = expected_",chat.message:"_later
	}
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(body.chat.%Size(), 100, "the chat holds 100 entries of the 101")
	Do $$$AssertEquals(..Items(body.chat), expected, "the first of the tied turns is the one dropped; the rest of the tie stay in row order, turns before incidents")
	Do $$$AssertTrue(('$Find(body.%ToJSON(), turn(1))), "the dropped turn is not in the snapshot")
	Do $ClassMethod(fixture, "Clean", refs)
}

/// StateBody reads the stream cursors before any section, so that whatever changes after the cursors is an event the page
/// applies. A job takes the snapshot while the session's stream is locked by this process; once the job waits on that lock,
/// this process adds a turn, publishes its event and releases the lock. The cursor the job read includes the event, so the
/// turn must be in the chat; a job that read the sections before the cursors waits on the lock only after them, and misses it.
Method TestCursorsAreReadBeforeTheSections()
{
	Set mine = ##class(OcuTalon.Test.Data.Fixture).Session("zzapicursor"_..Number)
	Set key = "cursor"_..Number
	Kill ^OcuTalonTest("WebApi", "job", key)
	Lock +^OcuTalonP.LiveEventC(mine)
	Job ##class(OcuTalon.Test.Web.Api).StateJob(mine, key)
	Set child = $ZChild
	Do ..WaitFor($Name(^OcuTalonTest("WebApi", "job", key, "started")), 1, 30)
	Do $$$AssertTrue(..WaitsOnLock(child, 30), "the job waits on the stream's lock")
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(mine)
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(##class(OcuTalon.Data.Turn).RefIndexOpen(turn))
	Set sc = ##class(OcuTalon.Live.Publish).Publish(mine, "chat.message", payload, .seq)
	Lock -^OcuTalonP.LiveEventC(mine)
	Do $$$AssertStatusOK(sc, "the turn's event is published")
	Do ..WaitFor($Name(^OcuTalonTest("WebApi", "job", key, "done")), 1, 30)
	Do $$$AssertEquals($Get(^OcuTalonTest("WebApi", "job", key, "error")), "", "the job took the snapshot")
	Set body = ##class(%DynamicObject).%FromJSON($Get(^OcuTalonTest("WebApi", "job", key, "body"), "{}"))
	Do $$$AssertEquals(body.streams.session, seq, "the cursor includes the published event")
	Do $$$AssertEquals(..Items(body.chat), "chat.message:"_turn, "and so the chat holds its turn")
	Kill ^OcuTalonTest("WebApi", "job", key)
}

/// A read that fails is an error, never an empty section: StateBody on a session with no Ref throws, and State with no CSP
/// session answers an error status (a 500 on the wire).
Method TestStateFailsLoudly()
{
	New %session
	Set threw = 0
	Try {
		Do ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).%New())
	} Catch exception {
		Set threw = 1
	}
	Do $$$AssertTrue(threw, "StateBody throws when a section can't be read")
	Set %session = ""
	Do $$$AssertStatusNotOK(##class(OcuTalon.Web.Api).State(), "State with no CSP session is an error status")
}

/// DW-15: the caller is resolved from the CSP session, never from the user name. Two OcuTalon sessions of one IRIS user
/// (the online demo's case) are two CSP sessions bound to two rows of one user name: State and Events through Call each
/// hold only their own session's epoch, cursors and events.
Method TestPollsResolveTheCspSession()
{
	Set one = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set two = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set rowOne = ##class(OcuTalon.Data.Session).RefIndexOpen(one)
	Set rowTwo = ##class(OcuTalon.Data.Session).RefIndexOpen(two)
	Do ..PublishReminders(one, 1, "p")
	Do ..PublishReminders(two, 2, "q")
	Set cspOne = ##class(%CSP.Session).%New("ZzApiOne", 0)
	Set cspTwo = ##class(%CSP.Session).%New("ZzApiTwo", 0)
	Set cspOne.Data("OcuTalon.SessionRef") = one
	Set cspTwo.Data("OcuTalon.SessionRef") = two
	Do $$$AssertTrue(rowOne.Epoch '= rowTwo.Epoch, "the two rows have their own epochs")

	Set body = ##class(%DynamicObject).%FromJSON(..CallSession(cspOne, "State", .response))
	Do $$$AssertEquals(response.Status, "200 OK", "State answers the first CSP session")
	Do $$$AssertEquals(body.epoch_"|"_body.streams.session_"|"_body.user, rowOne.Epoch_"|1|"_$Username, "with the first row's epoch and cursor")
	Set body = ##class(%DynamicObject).%FromJSON(..CallSession(cspTwo, "State", .response))
	Do $$$AssertEquals(body.epoch_"|"_body.streams.session_"|"_body.user, rowTwo.Epoch_"|2|"_$Username, "State answers the second with the second row's")

	Set first = ##class(%DynamicObject).%FromJSON(..PollSession(cspOne, 0, 999999999999999, .response))
	Do $$$AssertEquals(first.epoch, rowOne.Epoch, "Events answers the first CSP session with its epoch")
	Do $$$AssertEquals(first.events.%Size(), 1, "and its one event")
	Do $$$AssertEquals(first.events.%Get(0).payload.ref, "ZzApi"_..Number_"p1", "which is its own")
	Set second = ##class(%DynamicObject).%FromJSON(..PollSession(cspTwo, 0, 999999999999999, .response))
	Do $$$AssertEquals(second.epoch, rowTwo.Epoch, "the second gets the second epoch")
	Do $$$AssertEquals(second.events.%Size(), 2, "and its two events")
	Do $$$AssertEquals(second.events.%Get(0).payload.ref_","_second.events.%Get(1).payload.ref, "ZzApi"_..Number_"q1,ZzApi"_..Number_"q2", "which are its own")
}

/// POST /v1/session/end logs the CSP session out, ends it, and answers 204 with no body.
Method TestEndSession()
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzApiEnd", 0)
	Set %session.EventClass = "OcuTalon.Test.Web.LogoutProbe"
	Set %response.ContentType = ""
	Kill ^||OcuTalonLogoutProbe
	Do $$$AssertEquals(%session.EndSession, 0, "the session is open")
	Set body = ..Run("EndSession", .response)
	Do $$$AssertEquals(response.Status, "204 No Content", "204")
	Do $$$AssertEquals(body, "", "with no body")
	Do $$$AssertEquals($Get(^||OcuTalonLogoutProbe), 1, "the CSP session was logged out")
	Do $$$AssertEquals(%session.EndSession, 1, "and is to end")
	Kill ^||OcuTalonLogoutProbe
}

/// The two routes that name a record answer 404 not_found, with the error body, for a ref the session can't see: another
/// session's, an unnoticed incident, an eval record, an unwatched instance incident, a missing ref. A visible ref answers
/// 501 not_built. The CSP session is bound to the second of two rows of the user name, so a handler that took the session
/// from the user name would resolve the first row and answer 404 for the visible refs.
Method TestUnseenRefIs404()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do $ClassMethod(fixture, "Session", $Username)
	Set mine = $ClassMethod(fixture, "Session", $Username)
	Set theirs = $ClassMethod(fixture, "Session", "zzapiunseenother"_..Number)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set watched = "Zz.Unseen"_..Number_".Watched"
	Do $ClassMethod(fixture, "Check", mine, "ZZNS", watched)
	Set ownIncident = $ClassMethod(fixture, "Incident", mine)
	Set ownApproval = $ClassMethod(fixture, "Approval", mine, ownIncident)
	Set instanceWatched = $ClassMethod(fixture, "Incident", "instance", now, "ZZNS", watched)
	Set instanceApproval = $ClassMethod(fixture, "Approval", "instance", instanceWatched)
	Set unseenIncidents = $ListBuild($ClassMethod(fixture, "Incident", theirs), $ClassMethod(fixture, "Incident", mine, ""), $ClassMethod(fixture, "Incident", "eval"), $ClassMethod(fixture, "Incident", "instance", now, "ZZNS", "Zz.Unseen"_..Number_".Unwatched"), "zzmissing"_..Number)
	Set unseenApprovals = $ListBuild($ClassMethod(fixture, "Approval", theirs), $ClassMethod(fixture, "Approval", "eval"), $ClassMethod(fixture, "Approval", "instance", $ClassMethod(fixture, "Incident", "instance", now, "ZZNS", "Zz.Unseen"_..Number_".Unwatched")), "zzmissing"_..Number)
	Set csp = ##class(%CSP.Session).%New("ZzApiUnseen", 0)
	Set csp.Data("OcuTalon.SessionRef") = mine
	Set notFound = "{""error"":{""code"":""not_found"",""message"":""OcuTalon has nothing at this address.""}}"
	Set notBuilt = "{""error"":{""code"":""not_built"",""message"":""This part of OcuTalon isn't built yet.""}}"
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")

	Set position = 0
	While $ListNext(unseenIncidents, position, ref) {
		Set body = ..CallSession(csp, "DismissIncident", .response, ref)
		Do $$$AssertEquals(response.Status, "404 Not Found", "dismissing incident "_ref_" is 404")
		Do $$$AssertEquals(body, notFound, "with the error body")
	}
	Set position = 0
	While $ListNext(unseenApprovals, position, ref) {
		Set body = ..CallSession(csp, "AnswerApproval", .response, ref)
		Do $$$AssertEquals(response.Status, "404 Not Found", "answering approval "_ref_" is 404")
		Do $$$AssertEquals(body, notFound, "with the error body")
	}
	Set body = ..CallSession(csp, "AnswerApproval", .response, ownIncident)
	Do $$$AssertEquals(response.Status, "404 Not Found", "an incident's ref is not an approval's")
	For ref = ownIncident, instanceWatched {
		Set body = ..CallSession(csp, "DismissIncident", .response, ref)
		Do $$$AssertEquals(response.Status, "501 Not Implemented", "dismissing the visible incident "_ref_" is 501")
		Do $$$AssertEquals(body, notBuilt, "not_built")
	}
	For ref = ownApproval, instanceApproval {
		Set body = ..CallSession(csp, "AnswerApproval", .response, ref)
		Do $$$AssertEquals(response.Status, "501 Not Implemented", "answering the visible approval "_ref_" is 501")
		Do $$$AssertEquals(body, notBuilt, "not_built")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ..CallSession(csp, "DismissIncident", .response, instanceWatched)
	Do $$$AssertEquals(response.Status, "404 Not Found", "with onlineDemo on, an instance incident is 404")
	Set body = ..CallSession(csp, "AnswerApproval", .response, instanceApproval)
	Do $$$AssertEquals(response.Status, "404 Not Found", "and so is its request")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// The display names of the two known models, an unknown id as it is, and "" as "".
Method TestModelName()
{
	Set api = "OcuTalon.Web.Api"
	Do $$$AssertEquals($ClassMethod(api, "ModelName", "claude-haiku-5-5"), "Claude Haiku 5.5", "claude-haiku-5-5")
	Do $$$AssertEquals($ClassMethod(api, "ModelName", "claude-sonnet-5-5"), "Claude Sonnet 5.5", "claude-sonnet-5-5")
	Do $$$AssertEquals($ClassMethod(api, "ModelName", "claude-opus-9-9"), "claude-opus-9-9", "an unknown id is returned as it is")
	Do $$$AssertEquals($ClassMethod(api, "ModelName", ""), "", "an empty id stays empty")
}

/// The poll returns a session's events after its cursor, 200 at most, in order, each in the envelope; another
/// session's events never appear. The instance stream has a cap of its own, counted from its own cursor, and comes
/// after the session's events. A fixture session's stream with 205 events stands in for the instance stream.
Method TestEventsBody()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzapievents"_..Number, .sc)
	Set other = ##class(OcuTalon.Data.Session).ForUser("zzapiother"_..Number, .sc)
	Set stream = ##class(OcuTalon.Data.Session).ForUser("zzapieventsinstance"_..Number, .sc).Ref
	Do ..PublishReminders(session.Ref, 250, "m")
	Do ..PublishReminders(other.Ref, 5, "o")
	Do ..PublishReminders(stream, 205, "i")
	Set instance = 205

	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 0, instance, stream)
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

	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 200, instance, stream)
	Do $$$AssertEquals(body.events.%Size(), 50, "after 200, the other 50")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 248, instance, stream)
	Do $$$AssertEquals(body.events.%Size(), 2, "after 248, two events")
	Do $$$AssertEquals(body.events.%Get(0).seq_","_body.events.%Get(1).seq, "249,250", "249 and 250")
	Do $$$AssertEquals(body.events.%Get(0).payload.ref, prefix_"249", "and their payloads")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 250, instance, stream)
	Do $$$AssertEquals(body.events.%Size(), 0, "after 250, nothing")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(other, 0, instance, stream)
	Do $$$AssertEquals(body.events.%Size(), 5, "the other session sees its own 5")
	Do $$$AssertEquals(body.epoch, other.Epoch, "with its own epoch")

	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 10, instance, stream)
	Do $$$AssertEquals(body.events.%Size(), 200, "after 10, the cap counts from the cursor: 200 events")
	Do $$$AssertEquals(body.events.%Get(0).seq_","_body.events.%Get(199).seq, "11,210", "they are 11 to 210")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 251, instance, stream)
	Do $$$AssertEquals(body.events.%Size(), 0, "a cursor past the last Seq is an empty poll")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 0, 999999999999999, stream)
	Do $$$AssertEquals(body.events.%Size(), 200, "the instance cursor does not move the session's")
	Do $$$AssertEquals(body.events.%Get(0).seq, 1, "the session's events still start at 1")

	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 0, 0, stream)
	Set events = body.events
	Do $$$AssertEquals(events.%Size(), 400, "with both streams behind, 200 of each")
	Do $$$AssertEquals(events.%Get(0).stream_":"_events.%Get(0).seq_" "_events.%Get(199).stream_":"_events.%Get(199).seq_" "_events.%Get(200).stream_":"_events.%Get(200).seq_" "_events.%Get(399).stream_":"_events.%Get(399).seq, "session:1 session:200 instance:1 instance:200", "the session's 200 first, then the instance stream's 200")
	Do $$$AssertEquals(events.%Get(200).payload.ref, "ZzApi"_..Number_"i1", "the instance events are the stand-in stream's")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 250, 3, stream)
	Set events = body.events
	Do $$$AssertEquals(events.%Size(), 200, "the instance stream's cap counts from its own cursor")
	Do $$$AssertEquals(events.%Get(0).stream_":"_events.%Get(0).seq_" "_events.%Get(199).stream_":"_events.%Get(199).seq, "instance:4 instance:203", "they are 4 to 203")

	Set tracer = ##class(OcuTalon.Data.Session).ForUser("zzapieventstrace"_..Number, .sc)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Turn(tracer.Ref, , "done", "zz traced")
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
	Set turn.TraceHeaderId = 9002
	Set turn.TraceItemIndex = 81
	Set turn.TraceItemIndexNoEvents = 70
	Do $$$AssertStatusOK(turn.%Save(), "a turn with a trace target at position 81")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(tracer.Ref, "chat.message", ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(turn)), "its chat.message is published")
	Set empty = ##class(OcuTalon.Data.Session).ForUser("zzapieventsempty"_..Number, .sc).Ref
	Set body = ##class(OcuTalon.Web.Api).EventsBody(tracer, 0, 0, empty)
	Do $$$AssertEquals(body.events.%Size(), 1, "the poll holds the event")
	Set payload = body.events.%Get(0).payload
	Do $$$AssertEquals(payload.traceItemIndex_"|"_payload.traceItemIndexNoEvents, "81|70", "the chat.message carries both positions")
	Do $$$AssertEquals(payload.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=9002&PAGE=3", "and its trace URL, at the page of position 81")
	Do $$$AssertEquals(body.events.%Get(0).%IsDefined("traceUrl"), 0, "while the event envelope itself gets none")
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

/// A signed-in user without the OcuTalon user role is refused before the envelope and the route are looked at: 403
/// no_role with the sign-in page's text, whatever the method and the headers, and the session is not ended, because
/// the trace applications share it. The test process holds no OcuTalon role, so the check refuses it; a process that
/// holds the role is let through, and the test says so and stops.
Method TestNoRoleIsRefusedFirstAndKeepsTheSession()
{
	If ##class(OcuTalon.Web.Public.Shell).HasRole() {
		Do $$$LogMessage("skipped: this process holds the OcuTalon user role, which the check lets through")
		Quit
	}
	Set text = ##class(OcuTalon.Web.Public.Login).#ERRORNOROLE
	Set wanted = {"error": {"code": "no_role", "message": (text)}}.%ToJSON()
	Set cases = $ListBuild($ListBuild("a GET with no envelope", "GET", "", "", "", ""), $ListBuild("a POST with the whole envelope", "POST", "application/json", 1, "http://h:1", "h:1"), $ListBuild("a POST with no envelope at all", "POST", "text/plain", "", "", "h:1"), $ListBuild("a DELETE with the wrong origin", "DELETE", "application/json", 1, "http://evil.example", "h:1"))
	Set position = 0
	While $ListNext(cases, position, row) {
		Set label = $List(row, 1)
		Set body = ..PreDispatch($List(row, 2), $List(row, 3), $List(row, 4), $List(row, 5), $List(row, 6), .response, .continue, .ended)
		Do $$$AssertEquals(response.Status, "403 Forbidden", label_": 403")
		Do $$$AssertEquals(body, wanted, label_": no_role with the sign-in page's text, not an envelope code")
		Do $$$AssertEquals(continue, 0, label_": the dispatch stops")
		Do $$$AssertEquals(ended, 0, label_": the session is not ended")
	}
}

/// Every error text of the API is the plain-English one of the spec's table.
Method TestErrorTexts()
{
	Set api = "OcuTalon.Web.Api"
	Do $$$AssertEquals($Parameter(api, "MESSAGEBADCURSOR"), "The after and afterInstance values must be whole numbers of zero or more.", "bad_cursor")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.ApiBase", "MESSAGESIGNEDOUT"), "You were signed out. Sign in again to continue.", "signed_out")
	Do $$$AssertEquals($Parameter(api, "MESSAGENOTJSON"), "OcuTalon refused this request because it wasn't sent as JSON.", "not_json")
	Do $$$AssertEquals($Parameter(api, "MESSAGENOHEADER"), "OcuTalon refused this request because it didn't come from the OcuTalon page.", "no_request_header")
	Do $$$AssertEquals($Parameter(api, "MESSAGEWRONGORIGIN"), "OcuTalon refused this request because it came from another site.", "wrong_origin")
	Do $$$AssertEquals($Parameter(api, "MESSAGEBADMESSAGE"), "A message needs a clientId and some text.", "bad_message")
	Do $$$AssertEquals($Parameter(api, "MESSAGENOTFOUND"), "OcuTalon has nothing at this address.", "not_found")
	Do $$$AssertEquals($Parameter(api, "MESSAGENOTALLOWED"), "This address doesn't accept that kind of request.", "method_not_allowed")
	Do $$$AssertEquals($Parameter(api, "MESSAGESERVERERROR"), "Something went wrong inside OcuTalon. Try again.", "server_error")
	Do $$$AssertEquals($Parameter(api, "MESSAGENOTBUILT"), "This part of OcuTalon isn't built yet.", "not_built")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).#ERRORNOROLE, "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.", "no_role is the sign-in page's text")
}

/// The URL map holds exactly the 12 routes, each with its call.
Method TestRoutes()
{
	Set found = ..Routes("OcuTalon.Web.Api")
	Set expected = $ListBuild("GET /v1/state State", "GET /v1/events Events", "POST /v1/messages Messages", "POST /v1/approvals/:ref/answer AnswerApproval", "POST /v1/incidents/:ref/dismiss DismissIncident", "POST /v1/demo/break-feed BreakFeed", "POST /v1/mailbox/incoming NotBuilt", "POST /v1/mailbox/samples/:name NotBuilt", "POST /v1/guide/markers GuideMarkers", "POST /v1/session/end EndSession", "POST /v1/pairing/code Pairing", "DELETE /v1/pairing Pairing")
	Do $$$AssertEquals($ListLength(found), 12, "12 routes")
	Do $$$AssertEquals($ListToString(found, "|"), $ListToString(expected, "|"), "the routes, in order")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "HandleCorsRequest"), 0, "no CORS handling")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "CHARSET"), "utf-8", "utf-8")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "HTTP501NOTIMPLEMENTED"), "501 Not Implemented", "the 501 status line")
}

/// POST /v1/messages with a valid body answers 202 {"clientId"} and hands WebChatIn a Post for the CSP session's own session
/// (a sessionRef in the body is ignored), with the clientId, the text and fromGuide, which is true only for the JSON true.
/// The call goes to Test.Web.ApiProbe, whose Post makes a shadow WebChatIn that records what it sends.
Method TestMessagesAccepted()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ##class(%CSP.Session).%New("ZzApiMessages", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Set cases = $ListBuild($ListBuild("true", "{""clientId"":""zzc1"",""text"":""zz hello"",""fromGuide"":true,""sessionRef"":""zzsomeoneelse""}", "zz hello", 1), $ListBuild("false", "{""clientId"":""zzc2"",""text"":""zz second"",""fromGuide"":false}", "zz second", 0), $ListBuild("absent", "{""clientId"":""zzc3"",""text"":""zz third""}", "zz third", 0), $ListBuild("the string true", "{""clientId"":""zzc4"",""text"":""zz fourth"",""fromGuide"":""true""}", "zz fourth", 0), $ListBuild("the number 1", "{""clientId"":""zzc5"",""text"":"" zz fifth\n"",""fromGuide"":1}", " zz fifth"_$Char(10), 0))
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set ^OcuTalonTest("ApiProbe", "run") = ..Number
		Set json = $List(case, 2)
		Set body = ..PostMessage(csp, json, .response)
		Set label = "fromGuide "_$List(case, 1)
		Do $$$AssertEquals(response.Status, "202 Accepted", label_": 202")
		Do $$$AssertEquals(response.ContentType, "application/json", label_": the content type")
		Do $$$AssertEquals(body, "{""clientId"":"""_##class(%DynamicObject).%FromJSON(json).clientId_"""}", label_": the body is the clientId")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("WebChatIn", ..Number)), 2, label_": the allowance is asked and one request is sent")
		Do $$$AssertEquals($Get(^OcuTalonTest("WebChatIn", ..Number, 2, "target"))_"|"_$Get(^OcuTalonTest("WebChatIn", ..Number, 2, "class")), "Conversation|OcuTalon.Msg.Item", label_": an Item goes to Conversation")
		Do $$$AssertEquals($Get(^OcuTalonTest("WebChatIn", ..Number, 2, "sessionRef")), session, label_": for the CSP session's own session, never the body's")
		Do $$$AssertEquals($Get(^OcuTalonTest("WebChatIn", ..Number, 2, "clientId"))_"|"_$Get(^OcuTalonTest("WebChatIn", ..Number, 2, "text"))_"|"_$Get(^OcuTalonTest("WebChatIn", ..Number, 2, "fromGuide")), ##class(%DynamicObject).%FromJSON(json).clientId_"|"_$List(case, 3)_"|"_$List(case, 4), label_": the clientId, the text and fromGuide")
	}
}

/// A body arrives as the UTF-8 bytes that the page sent, and text outside ASCII reaches WebChatIn as the characters that were
/// typed: an accented letter, a dash, a curly apostrophe and an emoji (a surrogate pair). A clientId's length is counted in
/// characters, so 127 ASCII characters and one accented letter are accepted.
Method TestMessagesUtf8Body()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ##class(%CSP.Session).%New("ZzApiUtf8", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Set text = "zz caf"_$Char(233)_" "_$Char(8212)_" it"_$Char(8217)_"s "_$Char(55357, 56832)
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set ^OcuTalonTest("ApiProbe", "run") = ..Number
	Set body = ..PostMessage(csp, "{""clientId"":""zzutf8"_..Number_""",""text"":"""_text_""",""fromGuide"":false}", .response, , 1)
	Do $$$AssertEquals(response.Status, "202 Accepted", "a UTF-8 body: 202")
	Do $$$AssertEquals(body, "{""clientId"":""zzutf8"_..Number_"""}", "with the clientId")
	Do $$$AssertEquals($Get(^OcuTalonTest("WebChatIn", ..Number, 2, "text")), text, "the text reaches WebChatIn as it was typed")
	Set long = $Translate($Justify("", 127), " ", "c")_$Char(233)
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set body = ..PostMessage(csp, "{""clientId"":"""_long_""",""text"":""zz""}", .response, , 1)
	Do $$$AssertEquals(response.Status, "202 Accepted", "a clientId of 128 characters, one of them outside ASCII, is accepted")
	Do $$$AssertEquals($Get(^OcuTalonTest("WebChatIn", ..Number, 2, "clientId")), long, "and reaches WebChatIn as it was sent")
}

/// A clientId that the session already has a turn for answers 202 again with its clientId, and nothing is sent.
Method TestMessagesRepeat()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(session, , "done", "zz first", "zzrepeat"_..Number)
	Set csp = ##class(%CSP.Session).%New("ZzApiRepeat", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set ^OcuTalonTest("ApiProbe", "run") = ..Number
	Set body = ..PostMessage(csp, "{""clientId"":""zzrepeat"_..Number_""",""text"":""zz again"",""fromGuide"":false}", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "a repeat answers 202")
	Do $$$AssertEquals(body, "{""clientId"":""zzrepeat"_..Number_"""}", "with the clientId")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("WebChatIn", ..Number)), 0, "and nothing is sent")
}

/// Any other body is 400 bad_message with the plain-English text, and nothing is sent: not JSON, no body, an array, an object
/// without a clientId or text, a clientId that is not a string, empty or over 128 characters, a text that is not a string,
/// empty or only white space.
Method TestMessagesBadBody()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ##class(%CSP.Session).%New("ZzApiBad", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Set long = $Translate($Justify("", 129), " ", "c")
	Set bodies = $ListBuild("not json", "", "[]", "[{""clientId"":""a"",""text"":""b""}]", "{}", "{""text"":""zz""}", "{""clientId"":""zz""}", "{""clientId"":123,""text"":""zz""}", "{""clientId"":"""",""text"":""zz""}", "{""clientId"":"""_long_""",""text"":""zz""}", "{""clientId"":""zz"",""text"":5}", "{""clientId"":""zz"",""text"":""""}", "{""clientId"":""zz"",""text"":""   ""}", "{""clientId"":""zz"",""text"":"" \t\n ""}", "{""clientId"":null,""text"":""zz""}", "{""clientId"":""zz"",""text"":null}", "{""clientId"":[""zz""],""text"":""zz""}", "{""clientId"":""zz"",""text"":{""a"":1}}")
	Set position = 0
	While $ListNext(bodies, position, json) {
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set ^OcuTalonTest("ApiProbe", "run") = ..Number
		Set body = ..PostMessage(csp, json, .response)
		Set label = "'"_$Extract(json, 1, 40)_"'"
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_": 400")
		Do $$$AssertEquals(body, "{""error"":{""code"":""bad_message"",""message"":""A message needs a clientId and some text.""}}", label_": bad_message with its text")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("WebChatIn", ..Number)), 0, label_": nothing is sent")
	}
	Set ok = ..PostMessage(csp, "{""clientId"":"""_$Extract(long, 1, 128)_""",""text"":""zz""}", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "a clientId of 128 characters is accepted")
}

/// A session that can't be resolved, a production that can't take the message and an error of WebChatIn answer 500
/// server_error with the plain-English text, and the cause is not in the body.
Method TestMessagesServerError()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ##class(%CSP.Session).%New("ZzApiError", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Set wanted = "{""error"":{""code"":""server_error"",""message"":""Something went wrong inside OcuTalon. Try again.""}}"
	Set valid = "{""clientId"":""zzc"",""text"":""zz hello"",""fromGuide"":false}"
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set ^OcuTalonTest("ApiProbe", "run") = ..Number
	Set ^OcuTalonTest("ApiProbe", "mode") = "fail"
	Set body = ..PostMessage(csp, valid, .response)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a production that can't take the message: 500")
	Do $$$AssertEquals(body, wanted, "with server_error and no cause")
	Kill ^OcuTalonTest("ApiProbe", "mode")
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", valid)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ""
	Set %response.ContentType = ""
	Set body = ..Written(.sc, "OcuTalon.Test.Web.ApiProbe", "Messages")
	Do $$$AssertStatusOK(sc, "Messages returns OK")
	Do $$$AssertEquals(%response.Status, "500 Internal Server Error", "no CSP session to take the session from: 500")
	Do $$$AssertEquals(body, wanted, "with server_error")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("WebChatIn", ..Number)), 0, "and nothing is sent")
	Set ^OcuTalonTest("ApiProbe", "mode") = ""
	Set csp.Data("OcuTalon.SessionRef") = session
	Set refused = ..PostMessage(csp, valid, .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "the same message is accepted once the production takes it")
}

/// With no production running, the real Post cannot create WebChatIn and the message is not taken: 500 server_error with the
/// plain-English text and no cause in the body. Skipped where a production runs, because the real Post would then take the
/// message (the API spec and ConversationProduction cover that path).
Method TestMessagesNoProductionIs500()
{
	If ##class(Ens.Director).IsProductionRunning() {
		Do $$$AssertSkipped("A production runs in "_$Namespace_": the real Post would queue a turn, which the API spec tests")
		Quit
	}
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ##class(%CSP.Session).%New("ZzApiNoProduction", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Set body = ..PostMessage(csp, "{""clientId"":""zznoproduction"_..Number_""",""text"":""zz hello"",""fromGuide"":false}", .response, "OcuTalon.Web.Api")
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a message that cannot reach WebChatIn: 500")
	Do $$$AssertEquals(body, "{""error"":{""code"":""server_error"",""message"":""Something went wrong inside OcuTalon. Try again.""}}", "with server_error and no cause")
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
	Quit ..CallSession(##class(%CSP.Session).%New("ZzApiTest", 0), method, .response, args...)
}

/// Calls a class method of Api as Call does, with the given CSP session as %session.
Method CallSession(session As %CSP.Session, method As %String, Output response, args...) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
	Set %response.ContentType = ""
	Quit ..Run(method, .response, args...)
}

/// Calls a class method of Api with the %request and %response that the caller has set, and returns what it wrote.
Method Run(method As %String, Output response, args...) As %String [ Private ]
{
	Set body = ..Written(.sc, "OcuTalon.Web.Api", method, args...)
	Set response = %response
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Quit body
}

/// Runs OnPreDispatch for a stand-in request (see StubRequest.MakeCall) and returns the body that it wrote. continue
/// is the dispatch flag that it left, and ended is the stand-in session's EndSession.
Method PreDispatch(method As %String, contentType As %String, header As %String, origin As %String, host As %String, Output response, Output continue, Output ended) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, contentType, header, origin, host)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzApiTest", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set sc = ..Capture(.capture)
	If $SYSTEM.Status.IsOK(sc) {
		Try {
			Set sc = ##class(OcuTalon.Web.Api).OnPreDispatch("/v1/messages", method, .continue)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
	}
	Set body = ..Collect(.capture)
	Set response = %response
	Set ended = %session.EndSession
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit body
}

/// Calls Messages of Test.Web.ApiProbe (or of the class given) with a stand-in request whose body is json (with binary 1, its
/// UTF-8 bytes, as the CSP server hands a body over) and the given CSP session, and returns the body that it wrote.
Method PostMessage(session As %CSP.Session, json As %String, Output response, class As %String = "OcuTalon.Test.Web.ApiProbe", binary As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json, binary)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
	Set %response.ContentType = ""
	Set body = ..Written(.sc, class, "Messages")
	Set response = %response
	Do $$$AssertStatusOK(sc, "Messages returns OK")
	Quit body
}

/// Calls a class method with the device sent to a temporary file, and returns what it wrote. sc is the method's
/// status, or the error that it threw or that the capture met.
ClassMethod Written(Output sc As %Status, class As %String, method As %String, args...) As %String
{
	Set sc = ..Capture(.capture)
	If $SYSTEM.Status.IsOK(sc) {
		Try {
			Set sc = $ClassMethod(class, method, args...)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
	}
	Quit ..Collect(.capture)
}

/// Sends what the process writes to a temporary file until Collect; capture holds the file and the device to return
/// to. An error when the file can't be opened, and then nothing is captured.
ClassMethod Capture(Output capture) As %Status
{
	Kill capture
	Set capture("io") = $IO
	Set capture("file") = ##class(%File).TempFilename("out")
	Open capture("file"):("NWS"):5
	If '$Test Quit $SYSTEM.Status.Error(5001, "The temporary file "_capture("file")_" could not be opened")
	Set capture("open") = 1
	Use capture("file")
	Quit $SYSTEM.Status.OK()
}

/// Ends a Capture: returns to the earlier device, removes the file, and returns what was written, at most 100000
/// characters.
ClassMethod Collect(ByRef capture) As %String
{
	If '$Get(capture("open")) Quit ""
	Use capture("io")
	Close capture("file")
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(capture("file"))
	Set written = stream.Read(100000)
	Kill stream
	Do ##class(%File).Delete(capture("file"))
	Kill capture
	Quit written
}

/// Calls Events with the given cursors and a stand-in request, and returns the body that it wrote.
Method Poll(after As %String, afterInstance As %String, Output response) As %String [ Private ]
{
	Quit ..PollSession(##class(%CSP.Session).%New("ZzApiTest", 0), after, afterInstance, .response)
}

/// Calls Events as Poll does, with the given CSP session as %session.
Method PollSession(session As %CSP.Session, after As %String, afterInstance As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
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

/// The job body of TestCursorsAreReadBeforeTheSections: takes the snapshot of the session and records its JSON.
ClassMethod StateJob(ref As %String, key As %String)
{
	Set run = $Name(^OcuTalonTest("WebApi", "job", key))
	Try {
		Set @run@("started") = 1
		Set @run@("body") = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(ref)).%ToJSON()
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// 1 once the process waits on a lock (its state is LOCK in five samples 20 ms apart), 0 if it does not within seconds.
ClassMethod WaitsOnLock(pid As %Integer, seconds As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	Set run = 0
	While (run < 5) && ($ZHorolog < deadline) {
		Set run = $Select($Extract($SYSTEM.Process.State(pid), 1, 4) = "LOCK": run + 1, 1: 0)
		Hang 0.02
	}
	Quit run = 5
}

/// DW-62: the snapshot's chat holds the web notice cards that WebChatOut kept (the tell-now and reminder Delivery rows of the
/// session) among its turns and incidents, so a reload shows them where they arrived.
///   - A session with a turn of 2024, a card now and a turn of 2099 has the chat turn, card, turn; the card's entry is the
///     notification payload of its row. Another session's card, a card of another channel, a row of another kind and a reply's
///     row (kind empty) are not in it;
///   - at the same second a turn comes first, then an incident, then a card, whatever the order they were made in;
///   - the cap of 100 counts all three: 40 turns, 40 incidents and 40 cards one second apart in turn, incident, card order have
///     120 entries, and the chat keeps the newest 100, from the 7th card to the last.
Method TestStateChatNotices()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapinotice"_..Number)
	Set theirs = $ClassMethod(fixture, "Session", "zzapinoticeother"_..Number)
	Set before = $ClassMethod(fixture, "Turn", mine, "2024-01-01T10:00:00Z")
	Set card = $ClassMethod(fixture, "Delivery", mine, {"Text": ("zz card text"_$Char(10)_"Why now: zz why."), "Kind": "tellnow"})
	Set after = $ClassMethod(fixture, "Turn", mine, "2099-01-01T10:00:00Z")
	Set refs = mine_","_theirs_","_before_","_card_","_after
	Set refs = refs_","_$ClassMethod(fixture, "Delivery", theirs)
	Set refs = refs_","_$ClassMethod(fixture, "Delivery", mine, {"Channel": "telegram"})
	Set refs = refs_","_$ClassMethod(fixture, "Delivery", mine, {"Kind": "incident"})
	Set refs = refs_","_$ClassMethod(fixture, "Delivery", mine, {"Kind": "", "ChannelMessageId": ""})
	Set refs = refs_","_$ClassMethod(fixture, "Delivery", "instance")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(..Items(body.chat), "chat.message:"_before_",notification:"_card_",chat.message:"_after, "the card sits between the turn of 2024 and the turn of 2099, and no other row is in the chat")
	Set entry = body.chat.%Get(1).payload
	Do $$$AssertEquals(entry.kind_"|"_entry.text_"|"_entry.whyNow, "tellnow|zz card text|Why now: zz why.", "the card's entry is its notification payload, split at the Why now line")
	Do $$$AssertTrue(entry.createdAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "with its time: "_entry.createdAt)
	Do $ClassMethod(fixture, "Clean", refs)

	Set tied = "2030-01-01T10:00:00Z"
	Set mine = $ClassMethod(fixture, "Session", "zzapinoticeties"_..Number)
	Set card = $ClassMethod(fixture, "Delivery", mine, {"RecordedAt": (tied)})
	Set incident = $ClassMethod(fixture, "Incident", mine, tied)
	Set turn = $ClassMethod(fixture, "Turn", mine, tied)
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(..Items(body.chat), "chat.message:"_turn_",incident:"_incident_",notification:"_card, "at the same second: the turn, the incident, then the card, whatever the order they were made in")
	Do $ClassMethod(fixture, "Clean", mine_","_card_","_incident_","_turn)

	Set mine = $ClassMethod(fixture, "Session", "zzapinoticecap"_..Number)
	Set refs = mine
	Set expected = ""
	For i = 1:1:40 {
		Set second = 3 * i
		Set turn = $ClassMethod(fixture, "Turn", mine, "2030-01-01T10:"_$Extract(100 + (second \ 60), 2, 3)_":"_$Extract(100 + (second # 60), 2, 3)_"Z")
		Set incident = $ClassMethod(fixture, "Incident", mine, "2030-01-01T10:"_$Extract(100 + ((second + 1) \ 60), 2, 3)_":"_$Extract(100 + ((second + 1) # 60), 2, 3)_"Z")
		Set card = $ClassMethod(fixture, "Delivery", mine, {"RecordedAt": ("2030-01-01T10:"_$Extract(100 + ((second + 2) \ 60), 2, 3)_":"_$Extract(100 + ((second + 2) # 60), 2, 3)_"Z")})
		Set refs = refs_","_turn_","_incident_","_card
		If i > 7 Set expected = expected_",chat.message:"_turn_",incident:"_incident
		If i >= 7 Set expected = expected_",notification:"_card
		If i = 7 Set expected = $Piece(expected, ",", 2, *)
	}
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(body.chat.%Size(), 100, "the chat holds 100 entries of the 120")
	Do $$$AssertEquals(..Items(body.chat), expected, "the newest 100 across turns, incidents and cards, from the 7th card to the last")
	Do $ClassMethod(fixture, "Clean", refs)
}

/// DW-62: after a reload the snapshot draws each card as it was sent. A card of the chat carries what its strip and caption need:
///   - a tell-now card with a decision of the session's own embeds that decision with its cost, and has no fallback reason;
///   - a fallback card carries its fallback reason and embeds no decision;
///   - a reminder card carries its due time and no Why now line;
///   - a card whose DecisionRef is another session's decision keeps the Ref and embeds nothing.
Method TestStateChatNoticeCardFields()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = $ClassMethod(fixture, "Session", "zzapicardfields"_..Number)
	Set theirs = $ClassMethod(fixture, "Session", "zzapicardfieldsother"_..Number)
	Set decision = $ClassMethod(fixture, "Decision", mine, "decide", , {"Outcome": "tellnow", "Reasons": "zz first.", "Confidence": 0.9, "CostUSD": 0.0003})
	Set foreign = $ClassMethod(fixture, "Decision", theirs, "decide")
	Set shown = $ClassMethod(fixture, "Delivery", mine, {"RecordedAt": "2030-01-01T10:00:01Z", "DecisionRef": (decision), "Text": ("zz shown"_$Char(10)_"Why now: zz first.")})
	Set fallback = $ClassMethod(fixture, "Delivery", mine, {"RecordedAt": "2030-01-01T10:00:02Z", "FallbackReason": "refusal", "Text": ("zz fallback"_$Char(10)_"Why now: the model declined to answer")})
	Set reminder = $ClassMethod(fixture, "Delivery", mine, {"RecordedAt": "2030-01-01T10:00:03Z", "Kind": "reminder", "DueAt": "2030-01-01T09:30:00Z", "Text": "Reminder: stretch."})
	Set stranger = $ClassMethod(fixture, "Delivery", mine, {"RecordedAt": "2030-01-01T10:00:04Z", "DecisionRef": (foreign), "Text": ("zz stranger"_$Char(10)_"Why now: zz why.")})
	Set refs = mine_","_theirs_","_decision_","_foreign_","_shown_","_fallback_","_reminder_","_stranger
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(mine))
	Do $$$AssertEquals(..Items(body.chat), "notification:"_shown_",notification:"_fallback_",notification:"_reminder_",notification:"_stranger, "the four cards, in time order")
	If body.chat.%Size() = 4 {
		Set card = body.chat.%Get(0).payload
		Do $$$AssertEquals(card.kind_"|"_card.text_"|"_card.whyNow_"|"_card.decisionRef, "tellnow|zz shown|Why now: zz first.|"_decision, "the tell-now card: its text, its Why now line and its decision's Ref")
		Do $$$AssertEquals(card.decision.ref_"|"_card.decision.outcome_"|"_card.decision.reasons_"|"_card.decision.costUSD, decision_"|tellnow|zz first.|.0003", "with the decision embedded, and its own cost")
		Do $$$AssertEquals(card.%IsDefined("fallbackReason"), 0, "and no fallback reason")
		Set card = body.chat.%Get(1).payload
		Do $$$AssertEquals(card.fallbackReason_"|"_card.whyNow, "refusal|Why now: the model declined to answer", "the fallback card: its fallback reason and its Why now line")
		Do $$$AssertEquals(card.%IsDefined("decision"), 0, "and no decision")
		Set card = body.chat.%Get(2).payload
		Do $$$AssertEquals(card.kind_"|"_card.text_"|"_card.dueAt_"|"_card.whyNow, "reminder|Reminder: stretch.|2030-01-01T09:30:00Z|", "the reminder card: its due time, its whole text and no Why now line")
		Set card = body.chat.%Get(3).payload
		Do $$$AssertEquals(card.decisionRef, foreign, "the card of another session's decision keeps the Ref")
		Do $$$AssertEquals(card.%IsDefined("decision"), 0, "and embeds nothing of it")
	}
	Do $ClassMethod(fixture, "Clean", refs)
}

/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The Refs of an array of payload objects, comma-separated, in order.
ClassMethod Refs(array As %DynamicArray) As %String [ Private ]
{
	Set refs = ""
	For i = 0:1:array.%Size() - 1 {
		Set refs = refs_$Select(refs = "": "", 1: ",")_array.%Get(i).ref
	}
	Quit refs
}

/// The type and Ref of each live item of the chat, as type:ref, comma-separated, in order.
ClassMethod Items(chat As %DynamicArray) As %String [ Private ]
{
	Set items = ""
	For i = 0:1:chat.%Size() - 1 {
		Set items = items_$Select(items = "": "", 1: ",")_chat.%Get(i).type_":"_chat.%Get(i).payload.ref
	}
	Quit items
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
