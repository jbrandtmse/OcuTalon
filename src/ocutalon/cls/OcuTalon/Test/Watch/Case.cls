Include Ensemble

/// The base of the Story 5.1 test classes that run over the running production (Test.Watch.Reader, Grant, Ops, Tools and Turns). THEY RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), with demo mode on: they need the running OcuTalon.Production and the Orders demo production in OCUORDERS, and fail
/// with the reason where they do not have them (Reason), so that a broken start can never give a green shard. It extends Test.Core.InProduction (Guard,
/// the fixture sessions, the clean-up of the run's messages) and adds what the watch tests share:
///   - Reason: "" when OCUORDERS exists, demo mode is on and the Orders production is current there;
///   - the changes that a test makes to the instance, each put back by OnAfterOneTest, also after a failure: SetOnlineDemo (the public flag), GrantRole
///     and RevokeRole (a resource of the service role), and Described (a production's description in a namespace's definition table);
///   - UseDouble and UseReal (Test.Tools.CommandsDouble behind the CommandsIn item, and the real service back), Begin (a bridge context for a turn), Calls (what the double
///     recorded), Rows and Row (the BackgroundCheck rows of a session) and Watch (a fixture session's watch of Orders);
///   - OnAfterOneTest and OnAfterAllTests delete the BackgroundCheck rows of the run's sessions, so a row that a test made through WatchOps is gone too;
///   - for the tests of the failure reading (Story 5.2): Fail (failing orders in OCUORDERS through the partner), WaitFailed, LateHeader and LateError (a
///     header that enters the error status later), HeaderlessLog (an event-log row with no session), Since and Batches (the FailureBatch messages that
///     IncidentManager holds, as plain objects), WaitBatched and Ids, StopPoller and StartPoller (the item's temporary stop), StopOrders, StartOrders and
///     OrdersRunning, and ClearMark. Every message and row that they make in OCUORDERS (the headers after the first Fail, the fixture headers and log
///     rows) and every batch that the poller sent is removed by OnAfterOneTest and OnAfterAllTests, and the poller and Orders are started again if a test
///     stopped them.
///   - for the tests of the incidents (Story 5.3): SendBatch (a FailureBatch from an adapterless host, as the poller sends it, with synthetic header ids), Item (a
///     run's own item name), Incidents and Group (the rows of IncidentManager as plain objects; Group also lists every group, Story 5.8), Stream (a session's events
///     of any type in Seq order) and NoticeBodies (the Notification messages of an incident's Ref as plain objects, of one kind when given), WaitIncident, WaitCount
///     and WaitNoticeCount, Notifications, and (Story 5.4) WaitDiagnosed, which returns once the incident holds its diagnosis or its fallback; (Story 5.8) WaitNotices,
///     and WaitAnswered, which returns once IncidentManager has handled Decide's answer,
///     so that the notice step, or its absence, is done. OnAfterOneTest and OnAfterAllTests delete the Incident and FailureGroup
///     rows that the run's sessions own, and the instance incidents made after the test (the class) began, with their groups, so the instance incidents that the
///     untagged failures of the poller tests make are gone too.
///   - for the tests of the checks (Story 5.6, moved here by Story 5.7): Tick, which sends a Tick from the HeartbeatIn service to the Checks item
///     synchronously and waits for the answer, with the parameters HEARTBEAT, CHECKS and TICKWAIT.
///   - for tests that a real Tick must never change (Story 5.10): Watch makes its row due at Ahead() (AHEADSECONDS from now), so that only a Tick that a test sends at
///     the row's NextDueAt runs it; SendTick is the one sender (synchronously, or asynchronously as HeartbeatIn sends it, waiting for the Tick's request to
///     complete), Tick asserts on the synchronous send and RealTick on an asynchronous one at the clock's now, which a test or a one-off run uses to prove that
///     a real Tick leaves a test's rows as they are; and Rows leaves out, on request, the fields that Checks owns.
///   - for the tests that raise approval requests (Story 7.2): ApprovalReady (the production is ready, the ANSWERER account holds OcuTalonUser and the ApprovalRole
///     default of Decide is set aside; OnAfterOneTest puts it back), and DropIncidentRows, which tracks every ApprovalRequest that names a dropped incident
///     under ^OcuTalonTest("Approval","refs") and then calls Test.Bridge.Approval.Clean, which ends the holds and tasks and deletes the rows, so that
///     Test.Bridge.Approval's instance-wide row and hold counts stay its own; Requests, HeadersBetween and HoldInSession read the request rows and the trace
///     session; AssertDelivered waits for WebChatOut's Delivery row of a kind and a request's Ref, StateIncident gives the incident as /state lists it, and Listed
///     the requests that an incident payload lists (Listed reads the index-th one, the first by default).
///   - for the tests that start from a raised request (Story 7.2, lifted here by Story 7.6): Raised (S watches Orders and failing orders tagged with S's trace Ref become an
///     incident that is noticed with its fix and one pending request; its trailing argument is the number of orders, 3 by default), Noticed (waits for the diagnosis, the
///     answer and the notifications), Answered (the answered Notification of an incident) and NoticeSessionOf (the trace session of a Notification).
///   - for the tests that carry an approved request out (Story 7.3): RaisedTwo (Raised, then two more failing orders of S and a second request over them; WAITLATER, lifted
///     here from Test.Fix.Later), Runs and RunOf (the FixRun rows of an incident as plain objects), WaitRun (a run with copies registered), WaitState (a request in a
///     state) and WaitIncidentState (an incident in a state), Header (a message header of a namespace with its body's stored properties as plain objects), WaitCompleted (copies that completed), WaitSettled (sessions with no header still
///     created, queued or delivered, before a snapshot), ExecutesOf and FixResultsOf (the
///     Execute and FixResult headers of the incident's trace session), SetOrderDate (lifted here
///     from Test.Fix.DryRun) and SendExecute (an Execute to the real FixExecutor from the SimMailboxIn service, whose session is removed after the test).
///     DropIncidentRows also deletes the FixRun rows of a dropped incident.
///   - for the tests that read the end of a run (Story 7.4): ResultOf (the result that an incident payload lists for a request), LastIncident (the newest incident
///     event of a session's stream), Deliveries and AssertDeliveredIn (a channel's Delivery rows of a kind for a request), Posts (the model requests in the mock's log
///     since a mark), CompletedCount (the headers among some ids that are Completed), and Joined and Originals (the ids of a run's copies, and the originals they
///     were made of);
///   - for the tests that end a run (Story 7.4): AskDryRun (a DryRun sent to FixExecutor from SimMailboxIn, whose sessions
///     OnAfterOneTest removes), TempStopItem and TempStartItem (an item of the Orders production stopped with TempStopConfigItem and started again, also by
///     PutBack) and SetFixParameters (the parameters of a pending request's row).
/// It has no Test methods.
Class OcuTalon.Test.Watch.Case Extends OcuTalon.Test.Core.InProduction [ Abstract, DependsOn = (OcuTalon.Install.Step.Demo, OcuTalon.Install.Step.Users) ]
{

Parameter SESSIONPREFIX = "zzwatch";

/// The test double of CommandsIn and the item that it sits behind.
Parameter DOUBLE = "OcuTalon.Test.Tools.CommandsDouble";

Parameter ITEM = "CommandsIn";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter ROLE = {##class(OcuTalon.Install.Step.Users).#SERVICEROLE};

/// The namespace and the production of the Orders demo, from the Demo step's own parameters.
Parameter ORDERS = {##class(OcuTalon.Install.Step.Demo).#NAMESPACE};

Parameter ORDERSPRODUCTION = {##class(OcuTalon.Install.Step.Demo).#PRODUCTION};

/// The data database resource of OCUORDERS and of OCUTALON.
Parameter ORDERSDATA = {"%DB_"_##class(OcuTalon.Install.Step.Demo).#DATADB};

Parameter ORDERSCODE = {"%DB_"_##class(OcuTalon.Install.Step.Demo).#CODEDB};

Parameter HOMEDATA = "%DB_OCUTALON_DATA";

/// The README account that answers an approval request (Install.Step.Users USER), the local install's real approver.
Parameter ANSWERER = "ocutalon";

/// The sentence of a failing order of Fail, as ErrorText.Sentence gives it.
Parameter ORDERDATETEXT = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'.";

/// The item that picks up failures, and the item that receives its batches.
Parameter POLLER = "FailurePoller";

Parameter MANAGER = "IncidentManager";

/// The longest a test waits for an incident or its settle to end (a test bound, not NFR-7), in seconds, and the same for a trickle that runs past the
/// settle maximum.
Parameter WAITINCIDENT = 20;

Parameter WAITTRICKLE = 45;

/// The longest a test waits for the diagnosis of an incident, from the moment the incident exists (the settle rule runs up to 30 seconds first), in seconds.
Parameter WAITDIAGNOSIS = 90;

/// The first synthetic header id of the failures that SendBatch makes (above any real header id of a throwaway).
Parameter SYNTHFIRST = 900000000;

/// The longest a test waits for a batch, in seconds (a test bound, not NFR-7), and the pause that proves no further batch comes: two polls.
Parameter WAITBATCH = 30;

/// The longest a test waits for the end of a hold, and for an outcome to be handled, in seconds (a test bound, not NFR-7).
Parameter WAITHOLD = 20;

Parameter QUIET = 7;

/// The longest a test waits for the later request after the failures, in seconds (a test bound, not NFR-7): the quiet time, the dry run and the raise.
Parameter WAITLATER = 30;

/// The longest a test waits for an approved request's run to register its copies, and for the copies to complete, in seconds (test bounds, not NFR-7).
Parameter WAITRUN = 30;

Parameter WAITCOPY = 30;

/// The service that sends an Execute to FixExecutor in the tests, and the item that handles it.
Parameter SENDER = "SimMailboxIn";

Parameter EXECUTOR = "FixExecutor";

/// The longest a test waits for FixExecutor's answer to a DryRun, in seconds.
Parameter SENDWAIT = 60;

/// The service that sends the Tick, and the item that handles it.
Parameter HEARTBEAT = "HeartbeatIn";

Parameter CHECKS = "Checks";

/// The longest a Tick is waited for, in seconds.
Parameter TICKWAIT = 60;

/// How far ahead of now a row is due, in seconds (see Ahead).
Parameter AHEADSECONDS = 86400;

/// The ApprovalRole rows of Decide before ApprovalReady set them aside (RunnerFixture.RememberDefault), with ApprovalRoleSaved 1 while they are set aside.
Property ApprovalRoleRows As %List;

Property ApprovalRoleSaved As %Boolean [ InitialExpression = 0 ];

/// What the CommandsIn item had before the double was put behind it, as JSON text, or "" while the double is not behind it.
Property Swap As %String(MAXLEN = "");

/// The resources of the service role before a test changed them, or "" with RoleSaved 0 when it did not.
Property RoleBefore As %String(MAXLEN = "");

Property RoleSaved As %Boolean [ InitialExpression = 0 ];

/// The value of the public flag onlineDemo before a test set it, with OnlineSaved 1 while it is changed.
Property OnlineBefore As %String;

Property OnlineSaved As %Boolean [ InitialExpression = 0 ];

/// The definitions that a test made or changed: JSON text of [{"namespace","production","existed","description"}, ...], or "".
Property Definitions As %String(MAXLEN = "");

/// The ItemIds of the turns that a test made, for the clean-up of their steps.
Property ItemIds As %List;

/// The entries of the runners point at the mock's key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The SessionMark of the saved AI sessions when a test began.
Property SessionMark As %Integer;

/// The newest header id and log id of OCUORDERS before the first failing order of a test, "" before it.
Property OrdersFloor As %Integer;

Property OrdersLogFloor As %Integer;

/// The newest header id of OCUTALON before the test first asked for it (Since), "" before it.
Property HomeFloor As %Integer;

/// The ids of the fixture headers and log rows that a test made in OCUORDERS.
Property FixtureHeaders As %List;

Property FixtureLogs As %List;

/// 1 while the test has the FailurePoller item temporarily stopped, and while it has stopped the Orders production.
Property PollerStopped As %Boolean [ InitialExpression = 0 ];

/// The newest Incident ID before the class began and before the test began: the instance incidents above it are the run's.
Property ClassFloor As %Integer;

Property IncidentFloor As %Integer;

Property OrdersStopped As %Boolean [ InitialExpression = 0 ];

/// The sessions of the Executes that SendExecute sent, comma-separated, for the clean-up.
Property ExecuteSessions As %String(MAXLEN = "");

/// The sessions of the DryRuns that AskDryRun sent, comma-separated, for the clean-up.
Property DrySessions As %String(MAXLEN = "");

/// The item of the Orders production that TempStopItem stopped, "" when none.
Property StoppedItem As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..ClassFloor = ..Top("OcuTalon_Data.Incident", $Namespace)
	Quit ##super()
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..IncidentFloor = ..Top("OcuTalon_Data.Incident", $Namespace)
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set ..OrdersFloor = ""
	Set ..OrdersLogFloor = ""
	Set ..HomeFloor = ""
	Set ..FixtureHeaders = ""
	Set ..FixtureLogs = ""
	If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	If ..ApprovalRoleSaved {
		Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..ApprovalRoleRows)
		Set ..ApprovalRoleSaved = 0
		Set ..ApprovalRoleRows = ""
	}
	Set sc = ..PutBack()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE IncidentRef = ?", itemId)
	}
	Set ..ItemIds = ""
	If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() && (..SessionMark '= "") Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do ..DropRows()
	Do ..DropIncidents(..IncidentFloor)
	Do ..DropMessages()
	Do ..DropExecuteSessions()
	Do ..DropDrySessions()
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set sc = ..PutBack()
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..Unswap())
	If ..Pointed && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..Pointed = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys())
	}
	Do ..DropRows()
	Do ..DropIncidents(..ClassFloor)
	Do ..DropMessages()
	Do ..DropExecuteSessions()
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// "" when the test may run: OCUORDERS exists, demo mode is on and the Orders production is the current production of OCUORDERS. Otherwise the reason.
ClassMethod Reason() As %String
{
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	If '##class(%SYS.Namespace).Exists(orders) Quit "Namespace "_orders_" does not exist: these tests run in a throwaway with demo mode on"
	If ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) '= 1 Quit "Demo mode is off: these tests run in a throwaway with demo mode on"
	Set entries = ##class(OcuTalon.Watch.Reader).Productions()
	Set found = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.namespace = orders) && (entry.production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION) Set found = 1
	}
	If 'found Quit "The Orders production is not listed by Watch.Reader: "_entries.%ToJSON()
	Quit ""
}

/// 1 when the test may run (Guard and Reason). Otherwise it fails with the reason, and the test quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set reason = ..Reason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Quit 1
}

/// The set-up of the tests that raise approval requests: 1 when the production is ready and the ANSWERER account holds OcuTalonUser (else the test fails with
/// the reason, and this gives 0), with the ApprovalRole default of Decide set aside so that the role setting is the product's own (OnAfterOneTest puts it back).
Method ApprovalReady() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertEquals(reason, "", "the production is ready")
		Quit 0
	}
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(..#ANSWERER, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_..#ANSWERER_" holds OcuTalonUser")
	If 'holds Quit 0
	If '..ApprovalRoleSaved {
		Set rows = ""
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "Decide", "ApprovalRole")
		Set ..ApprovalRoleRows = rows
		Set ..ApprovalRoleSaved = 1
	}
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(##class(OcuTalon.Test.Agent.RunnerFixture).DefaultId("Decide", "ApprovalRole"))
	Quit 1
}

/// The ApprovalRequest rows that name the incident, by ID, as a dynamic array of {"ref", "kind", "incidentRef", "ownerRef", "state", "resultTarget", "traceRef", "fixKind",
/// "fixParameters", "fixTargets", "dryRun", "answeredChannel", "answeredAt", "expiresAt"}.
ClassMethod Requests(incidentRef As %String) As %DynamicArray
{
	Set requests = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE IncidentRef = ? ORDER BY ID", incidentRef)
	While rs.%Next() {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%OpenId(rs.%GetData(1))
		If '$IsObject(row) Continue
		Do requests.%Push({"ref": (row.Ref), "kind": (row.Kind), "incidentRef": (row.IncidentRef), "ownerRef": (row.OwnerRef), "state": (row.State), "resultTarget": (row.ResultTarget), "traceRef": (row.TraceRef), "fixKind": (row.FixKind), "fixParameters": (row.FixParameters), "fixTargets": (row.FixTargets), "dryRun": (row.DryRun), "answeredChannel": (row.AnsweredChannel), "answeredAt": (row.AnsweredAt), "expiresAt": (row.ExpiresAt)})
	}
	Quit requests
}

/// The number of headers in the trace session of the type (1 request, 2 response) from the source item to the target item whose body class is bodyClass
/// ("" for any class).
ClassMethod HeadersBetween(session As %String, type As %Integer, source As %String, target As %String, bodyClass As %String = "") As %Integer
{
	If session = "" Quit 0
	Set found = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(session), type, source, target)
	Set count = 0
	For i = 0:1:found.%Size() - 1 {
		If (bodyClass = "") || (found.%Get(i).bodyClass = bodyClass) Set count = count + 1
	}
	Quit count
}

/// 1 when the hold of the request started in the trace session: one ApprovalStart for the Ref went from ApprovalStartIn to ApprovalHold in it.
ClassMethod HoldInSession(session As %String, ref As %String) As %Boolean
{
	If session = "" Quit 0
	Set found = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(session), 1, "ApprovalStartIn", "ApprovalHold")
	Set held = 0
	For i = 0:1:found.%Size() - 1 {
		If found.%Get(i).bodyClass '= "OcuTalon.Bridge.Msg.ApprovalStart" Continue
		Set body = ##class(OcuTalon.Bridge.Msg.ApprovalStart).%OpenId(found.%Get(i).bodyId)
		If $IsObject(body) && (body.Ref = ref) Set held = 1
	}
	Quit held
}

/// Sets the public flag onlineDemo for the test; OnAfterOneTest puts it back.
Method SetOnlineDemo(value As %String) [ Private ]
{
	If '..OnlineSaved {
		Set ..OnlineBefore = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
		Set ..OnlineSaved = 1
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", value), "onlineDemo is set to '"_value_"'")
}

/// The resources of the service role, as the role has them ("resource:permission,..."), read in %SYS.
ClassMethod RoleResources() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill props
	Set sc = ##class(Security.Roles).Get(..#ROLE, .props)
	Quit $Select($$$ISOK(sc): $Get(props("Resources")), 1: "<no role>")
}

/// Writes the resources of the service role, in %SYS.
ClassMethod WriteRole(resources As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill props
	Set props("Resources") = resources
	Quit ##class(Security.Roles).Modify(..#ROLE, .props)
}

/// Gives the service role Read on the resource (it keeps its other entries); OnAfterOneTest puts the role back as it was.
Method GrantRole(resource As %String) [ Private ]
{
	Set current = ..RoleResources()
	If '..RoleSaved {
		Set ..RoleBefore = current
		Set ..RoleSaved = 1
	}
	Set kept = ..Without(current, resource)
	Do $$$AssertStatusOK(..WriteRole(kept_$Select(kept = "": "", 1: ",")_resource_":R"), "the service role is given Read on "_resource)
}

/// Takes the resource from the service role (it keeps its other entries); OnAfterOneTest puts the role back as it was.
Method RevokeRole(resource As %String) [ Private ]
{
	Set current = ..RoleResources()
	If '..RoleSaved {
		Set ..RoleBefore = current
		Set ..RoleSaved = 1
	}
	Do $$$AssertStatusOK(..WriteRole(..Without(current, resource)), "the service role no longer holds "_resource)
}

/// The resource list without the entries of the resource.
ClassMethod Without(resources As %String, resource As %String) As %String
{
	Set result = ""
	For i = 1:1:$Length(resources, ",") {
		Set entry = $Piece(resources, ",", i)
		If (entry = "") || ($Piece(entry, ":", 1) = resource) Continue
		Set result = result_$Select(result = "": "", 1: ",")_entry
	}
	Quit result
}

/// The Description of the production in the namespace's definition table, "<none>" when it has no row. In the namespace itself.
ClassMethod DescriptionIn(namespace As %String, production As %String) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set row = ##class(Ens.Config.Production).%OpenId(production)
	Quit $Select($IsObject(row): row.Description, 1: "<none>")
}

/// Makes sure the namespace's definition table has a row for the production, loaded from its class, and remembers what it did for OnAfterOneTest: a row
/// that the test made is deleted again. Returns the description that the row holds.
Method Defined(namespace As %String, production As %String) As %String [ Private ]
{
	If ..DescriptionIn(namespace, production) = "<none>" {
		Do $$$AssertStatusOK(..LoadDefinition(namespace, production), "the definition of "_production_" is loaded in "_namespace)
		Set list = $Select(..Definitions = "": [], 1: {}.%FromJSON(..Definitions))
		Do list.%Push({"namespace": (namespace), "production": (production)})
		Set ..Definitions = list.%ToJSON()
	}
	Quit ..DescriptionIn(namespace, production)
}

/// Loads the definition of the production from its class in the namespace. Calls only Ens classes while it is there.
ClassMethod LoadDefinition(namespace As %String, production As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Quit ##class(Ens.Config.Production).LoadFromClass(production)
}

/// Puts back what the test changed: the service role, onlineDemo, and the definitions that it made.
Method PutBack() As %Status [ Private ]
{
	Set sc = $$$OK
	If ..PollerStopped {
		Set ..PollerStopped = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(Ens.Director).TempStopConfigItem(..#POLLER, 0, 1))
	}
	If ..OrdersStopped {
		Set ..OrdersStopped = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..StartOrdersNow())
	}
	If ..StoppedItem '= "" {
		Set item = ..StoppedItem
		Set ..StoppedItem = ""
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..TempItem(item, 0))
	}
	If ..RoleSaved {
		Set ..RoleSaved = 0
		Set sc = ..WriteRole(..RoleBefore)
	}
	If ..OnlineSaved {
		Set ..OnlineSaved = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineBefore))
	}
	If ..Definitions '= "" {
		Set list = {}.%FromJSON(..Definitions)
		Set ..Definitions = ""
		Set iterator = list.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteDefinition(entry.namespace, entry.production))
		}
	}
	Quit sc
}

/// Deletes the definition row of the production in the namespace, and returns to the namespace of the tests.
ClassMethod DeleteDefinition(namespace As %String, production As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Quit ##class(Ens.Config.Production).%DeleteId(production)
}

/// Puts the double Test.Tools.CommandsDouble behind the CommandsIn item; OnAfterAllTests puts the real service back.
Method UseDouble() As %Boolean [ Private ]
{
	If ..Swap '= "" Quit 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemClass(..#ITEM, ..#DOUBLE, .saved)
	If $IsObject(saved) Set ..Swap = saved.%ToJSON()
	Do $$$AssertStatusOK(sc, "the double is put behind the "_..#ITEM_" item")
	Quit $$$ISOK(sc)
}

/// Puts the real CommandsIn class back behind the item when the double is there; OK when it was not.
Method Unswap() As %Status [ Private ]
{
	If ..Swap = "" Quit $$$OK
	Set saved = {}.%FromJSON(..Swap)
	Set ..Swap = ""
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass(..#ITEM, saved)
}

/// For a test that needs the real service behind the item: puts it back if an earlier test of the class put the double there (UseDouble puts the double
/// there again).
Method UseReal() As %Boolean [ Private ]
{
	Set sc = ..Unswap()
	Do $$$AssertStatusOK(sc, "the real "_..#ITEM_" is behind the item")
	Quit $$$ISOK(sc)
}

/// Points the entries of the runners at the mock's key variable, for a turn through ChatAgent; OnAfterAllTests puts them back.
Method PointKeys() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If ..Pointed Quit 1
	Set ..Pointed = 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
	Quit $$$ISOK(sc)
}

/// Begins a bridge context in the test process for a turn of the owner with the ItemId and the provenance, as the runner does before Chat.
Method Begin(owner As %String, itemId As %String, provenance As %String = "user") [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = provenance
	Set request.ItemId = itemId
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the turn of '"_owner_"'")
}

/// The commands that the double recorded, in order, as a dynamic array of {"class","origin","sessionRef","key","fields"}.
ClassMethod Calls() As %DynamicArray
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("CommandsDouble", "calls", n))
		Quit:n=""
		Set call = ^OcuTalonTest("CommandsDouble", "calls", n)
		Do calls.%Push({"class": ($List(call, 1)), "origin": ($List(call, 2)), "sessionRef": ($List(call, 3)), "key": ($List(call, 4)), "fields": ({}.%FromJSON($List(call, 5)))})
	}
	Quit calls
}

/// The BackgroundCheck rows of the session, by ID, as a dynamic array of {"ref","kind","namespace","production","displayName","askedBy","nextDueAt",
/// "lastRunAt","result","createdAt"}; with runFields 0 the rows leave out nextDueAt, lastRunAt and result, the fields that Checks owns.
ClassMethod Rows(sessionRef As %String, runFields As %Boolean = 1) As %DynamicArray
{
	Set rows = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Kind, Namespace, Production, DisplayName, AskedBy, NextDueAt, LastRunAt, Result, CreatedAt FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ? ORDER BY ID", sessionRef)
	While rs.%Next() {
		Set row = {"ref": (rs.%GetData(1)), "kind": (rs.%GetData(2)), "namespace": (rs.%GetData(3)), "production": (rs.%GetData(4)), "displayName": (rs.%GetData(5)), "askedBy": (rs.%GetData(6))}
		If runFields {
			Do row.%Set("nextDueAt", rs.%GetData(7))
			Do row.%Set("lastRunAt", rs.%GetData(8))
			Do row.%Set("result", rs.%GetData(9))
		}
		Do row.%Set("createdAt", rs.%GetData(10))
		Do rows.%Push(row)
	}
	Quit rows
}

/// The number of BackgroundCheck rows of the whole table.
ClassMethod RowCount() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck")
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// A fixture row: the session watches the production of OCUORDERS under the display name Orders, created now (CreatedAt, as WatchOps writes it) and due at
/// Ahead(), so that a Tick runs it only when its time is the row's NextDueAt. The Ref of the row is given back.
Method Watch(sessionRef As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(sessionRef, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"DisplayName": "Orders", "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc()), "NextDueAt": (..Ahead())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The time AHEADSECONDS from now, as a UTC stamp.
ClassMethod Ahead() As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), ..#AHEADSECONDS)
}

/// Sends a Tick of the time from the HEARTBEAT service to Checks, as HeartbeatIn sends it. Synchronously (async 0) it waits at most TICKWAIT seconds for the
/// answer. Asynchronously it sends and then waits at most TICKWAIT seconds until the Tick's request, in the service's session, is Completed, so that a later
/// Tick cannot overtake it. The id of the service's session, the Tick's trace session, or "" with sc set to the error.
ClassMethod SendTick(tickAt As %String, async As %Boolean = 0, Output sc As %Status) As %Integer
{
	Set sc = ##class(Ens.Director).CreateBusinessService(..#HEARTBEAT, .service)
	If $$$ISERR(sc) Quit ""
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = tickAt
	If 'async {
		Set sc = service.SendRequestSync(..#CHECKS, tick, .response, ..#TICKWAIT)
	} Else {
		Set sc = service.SendRequestAsync(..#CHECKS, tick)
	}
	If $$$ISERR(sc) Quit ""
	If async {
		Set session = service.%SessionId
		Set end = $ZHorolog + ..#TICKWAIT
		Set status = ""
		For {
			Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status FROM Ens.MessageHeader WHERE SessionId = ? AND Type = 1 AND TargetConfigName = ?", session, ..#CHECKS)
			If rs.%Next() Set status = rs.%GetData(1)
			If status = $$$eMessageStatusCompleted Quit
			If $ZHorolog > end {
				Set sc = $SYSTEM.Status.Error(5001, "The Tick to "_..#CHECKS_" in session "_session_" was not Completed in "_..#TICKWAIT_" seconds (status '"_status_"')")
				Quit
			}
			Hang 0.25
		}
		If $$$ISERR(sc) Quit ""
	}
	Quit service.%SessionId
}

/// Sends a Tick of the time from HeartbeatIn to Checks and waits for the answer; the id of the service's session, the Tick's trace session, or "" with a failed
/// assertion.
Method Tick(tickAt As %String) As %Integer [ Private ]
{
	Set session = ..SendTick(tickAt, 0, .sc)
	Do $$$AssertStatusOK(sc, "the "_..#HEARTBEAT_" service sends the Tick at "_tickAt_" and Checks answers it")
	Quit session
}

/// Sends a Tick at the clock's now asynchronously, as HeartbeatIn does, and waits for it to complete; the id of the Tick's session, or "" with a failed
/// assertion. A test that sends it asserts only what holds whichever Tick, this one or a real one, acts first.
Method RealTick() As %Integer [ Private ]
{
	Set session = ..SendTick(##class(OcuTalon.Data.Time).NowUtc(), 1, .sc)
	Do $$$AssertStatusOK(sc, "the real-shaped Tick is handled")
	Quit session
}

/// Deletes the BackgroundCheck rows of the sessions of the run (the rows that WatchOps made).
Method DropRows() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", ref)
	}
}

/// The newest id of the table of the namespace, 0 when it is empty. In the namespace, calling only SQL while it is there.
ClassMethod Top(table As %String, namespace As %String) As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM "_table)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Sends count orders dated 2026-10-16 in the date format that fails (MM/DD/YYYY), so that each one fails with the sentence ORDERDATETEXT, every message tagged
/// with the trace reference (none when empty), through the Orders partner of OCUORDERS (a copy of the Demo test's private three-line Send, which is Epic 4's). Asserts that the partner accepts them.
Method Fail(count As %Integer, traceRef As %String = "") As %Boolean [ Private ]
{
	If ..OrdersFloor = "" {
		Set ..OrdersFloor = ..Top("Ens.MessageHeader", ..#ORDERS)
		Set ..OrdersLogFloor = ..Top("Ens_Util.Log", ..#ORDERS)
	}
	Set sc = ..SendOrders(count, traceRef)
	Do $$$AssertStatusOK(sc, count_" failing orders are sent"_$Select(traceRef '= "": " with a trace reference", 1: " with none"))
	Quit $$$ISOK(sc)
}

ClassMethod SendOrders(count As %Integer, traceRef As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(OcuTalon.Demo.Orders.Partner).Send(count, "MM/DD/YYYY", traceRef, "2026-10-16")
}

/// The failed headers (Status 8) of OCUORDERS after the first Fail of the test, as a dynamic array of {"id", "superSession", "at", "sessionId", "source",
/// "bodyClass"}, by id.
ClassMethod Failed(floor As %Integer) As %DynamicArray
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set failed = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SuperSession, TimeProcessed, SessionId, SourceConfigName, MessageBodyClassName FROM Ens.MessageHeader WHERE ID > ? AND Status = 8 ORDER BY ID", floor)
	While rs.%Next() {
		Do failed.%Push({"id": (rs.%GetData(1)), "superSession": (rs.%GetData(2)), "at": (rs.%GetData(3)), "sessionId": (rs.%GetData(4)), "source": (rs.%GetData(5)), "bodyClass": (rs.%GetData(6))})
	}
	Quit failed
}

/// Waits up to WAITBATCH seconds, polling every half second, for count failed headers in OCUORDERS after the test's first Fail; the failed headers.
Method WaitFailed(count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set failed = ..Failed(..OrdersFloor)
		If (failed.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(failed.%Size(), count, count_" orders are in the error status in OCUORDERS")
	Quit failed
}

/// The ids of the headers as a comma-separated list, in the order given.
ClassMethod HeaderIds(failed As %DynamicArray) As %String
{
	Set ids = ""
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set ids = ids_$Select(ids = "": "", 1: ",")_failure.id
	}
	Quit ids
}

/// An incident row of the owner over the failed headers (their ids, in order, are the keys of its group; kind l makes them log keys), and its group. The members of fields
/// (an object; none by default) are set on the incident before it is saved, as properties of that name. The row is cleaned up by Case.
Method Fixture(owner As %String, ids As %String, namespace As %String = {..#ORDERS}, production As %String = {..#ORDERSPRODUCTION}, kind As %String = "h", fields As %DynamicObject = "") As OcuTalon.Data.Incident [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).%New()
	Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set incident.OwnerRef = owner
	Set incident.Namespace = namespace
	Set incident.Production = production
	Set incident.State = "open"
	Set incident.Count = $Length(ids, ",")
	Set incident.NoticeCount = incident.Count
	Set incident.FirstAt = "2026-10-25T08:00:00Z"
	Set incident.LastAt = "2026-10-25T08:00:05Z"
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Set $Property(incident, name) = value
		}
	}
	Do $$$AssertStatusOK(incident.%Save(), "a fixture incident is saved")
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident.Ref
	Set group.Seq = 1
	Set group.ItemName = "OrdersFromPartner"
	Set group.ErrorPattern = ##class(OcuTalon.Watch.Settle).Pattern(..#ORDERDATETEXT)
	Set keys = ""
	For i = 1:1:$Length(ids, ",") {
		Set keys = keys _ $Select(keys = "": "", 1: ",") _ kind _ $Piece(ids, ",", i)
	}
	Set group.Seen = keys
	Do $$$AssertStatusOK(group.%Save(), "and its group")
	Quit incident
}

/// A failed header (Status 8) in OCUORDERS in the SuperSession, an hour old so that the poller never reads it, whose body is a PartnerOrder dated 10/16/2026: the
/// sample of an incident whose failures the test delivers as a FailureBatch (SendBatch, with the id on the first failure). Its id is given back; it and its body are
/// removed with the test.
Method SampleOrder(superSession As %String) As %Integer [ Private ]
{
	Set id = ..MakeSampleOrder(superSession)
	Do $$$AssertTrue(id '= "", "a failed fixture order is made for the sample")
	If id '= "" Set ..FixtureHeaders = ..FixtureHeaders_$ListBuild(id)
	Quit id
}

ClassMethod MakeSampleOrder(superSession As %String) As %Integer [ Private ]
{
	Set earlier = ##class(OcuTalon.Watch.Mark).Shift(##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc()), -3600)
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set body = ##class(OcuTalon.Demo.Orders.PartnerOrder).%New()
	Set body.OrderNumber = "PO-ZZ"
	Set body.OrderDate = "10/16/2026"
	Set body.Sku = "ZZ-1"
	Set body.Quantity = 1
	If $$$ISERR(body.%Save()) Quit ""
	Quit ..MakeHeader(superSession, earlier, 8, "OcuTalon.Demo.Orders.PartnerOrder", body.%Id())
}

/// A header in OCUORDERS that has not failed yet: a request from zzPollerSource to zzPollerTarget in the SuperSession, Status 3 (delivered), created and
/// processed five minutes ago, in a session of its own. LateError moves it to the error status later. Its id is given back, and removed with the test.
Method LateHeader(superSession As %String) As %Integer [ Private ]
{
	Set earlier = ##class(OcuTalon.Watch.Mark).Shift(##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc()), -300)
	Set id = ..MakeHeader(superSession, earlier)
	Set ..FixtureHeaders = ..FixtureHeaders_$ListBuild(id)
	Quit id
}

/// A request header in OCUORDERS from zzPollerSource to zzPollerTarget in the SuperSession, created and processed at the stamp, in a session of its own: in the
/// status (3, delivered, by default; 8 is an error, with IsError set), with the body when its class and id are given. Its id is given back, or "".
ClassMethod MakeHeader(superSession As %String, stamp As %String, status As %Integer = 3, bodyClass As %String = "", bodyId As %String = "") As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SuperSession = superSession
	Set header.TimeCreated = stamp
	Set header.TimeProcessed = stamp
	Set header.SourceConfigName = "zzPollerSource"
	Set header.TargetConfigName = "zzPollerTarget"
	Set header.Type = 1
	Set header.Status = status
	Set header.IsError = (status = 8)
	Set header.MessageBodyClassName = bodyClass
	Set header.MessageBodyId = bodyId
	Set sc = header.%Save()
	If $$$ISOK(sc) {
		Set header.SessionId = header.%Id()
		Set sc = header.%Save()
	}
	Quit $Select($$$ISOK(sc): header.%Id(), 1: "")
}

/// Moves the fixture header to the error status (SetStatus, which sets its TimeProcessed to now).
ClassMethod LateError(id As %Integer) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_id)
	Do header.SetStatus(8)
	Quit $$$OK
}

/// A header in OCUORDERS from zzPollerSource to zzPollerTarget for the fields (an object; all optional): Status (8), Type (1), IsError (0), ErrorStatus (a status
/// text, "" for none) and SessionId (its own id). TimeProcessed is now; removed with the test. Its id is given back.
Method FixtureHeader(fields As %DynamicObject) As %Integer [ Private ]
{
	Set id = ..MakeFixtureHeader(fields)
	Set ..FixtureHeaders = ..FixtureHeaders_$ListBuild(id)
	Quit id
}

ClassMethod MakeFixtureHeader(fields As %DynamicObject) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set now = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.TimeCreated = now
	Set header.TimeProcessed = now
	Set header.SourceConfigName = "zzPollerSource"
	Set header.TargetConfigName = "zzPollerTarget"
	Set header.Type = $Select(fields.%IsDefined("Type"): fields.Type, 1: 1)
	Set header.Status = $Select(fields.%IsDefined("Status"): fields.Status, 1: 8)
	Set header.IsError = $Select(fields.%IsDefined("IsError"): fields.IsError, 1: 0)
	If fields.ErrorStatus '= "" Set header.ErrorStatus = $SYSTEM.Status.Error(5001, fields.ErrorStatus)
	Set sc = header.%Save()
	If $$$ISOK(sc) {
		Set header.SessionId = $Select(fields.%IsDefined("SessionId"): fields.SessionId, 1: header.%Id())
		Set sc = header.%Save()
	}
	Quit $Select($$$ISOK(sc): header.%Id(), 1: "")
}

/// A Type 2 event-log row of OCUORDERS in the session, naming the message id (may be empty) and the ConfigName; removed with the test. Its id is given back.
Method FixtureLog(sessionId As %Integer, messageId As %Integer, config As %String, text As %String) As %Integer [ Private ]
{
	Set id = ..MakeSessionLog(sessionId, messageId, config, text)
	Set ..FixtureLogs = ..FixtureLogs_$ListBuild(id)
	Quit id
}

ClassMethod MakeSessionLog(sessionId As %Integer, messageId As %Integer, config As %String, text As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set log = ##class(Ens.Util.Log).%New()
	Set log.Type = 2
	Set log.ConfigName = config
	Set log.SessionId = sessionId
	Set log.MessageId = messageId
	Set log.Text = text
	Set log.TimeLogged = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set sc = log.%Save()
	Quit $Select($$$ISOK(sc): log.%Id(), 1: "")
}

/// An event-log row of OCUORDERS with no session, of the type (2 error, 6 alert) and the ConfigName; removed with the test. Its id is given back.
Method HeaderlessLog(type As %Integer, config As %String) As %Integer [ Private ]
{
	Set id = ..MakeLog(type, config)
	Set ..FixtureLogs = ..FixtureLogs_$ListBuild(id)
	Quit id
}

ClassMethod MakeLog(type As %Integer, config As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set log = ##class(Ens.Util.Log).%New()
	Set log.Type = type
	Set log.ConfigName = config
	Set log.Text = "A fixture row with no session: "_config
	Set log.TimeLogged = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set sc = log.%Save()
	Quit $Select($$$ISOK(sc): log.%Id(), 1: "")
}

/// The newest header id of OCUTALON, where the poller's batches arrive; the first call of a test also fixes the floor that the clean-up removes from.
Method Since() As %Integer [ Private ]
{
	Set top = ..Top("Ens.MessageHeader", $Namespace)
	If ..HomeFloor = "" Set ..HomeFloor = top
	Quit top
}

/// The FailureBatch messages that IncidentManager holds after the header id since, as a dynamic array in id order of {"id", "status", "sessionId",
/// "superSession", "namespace", "production", "ownerRef", "polledAt", "failures": [{"kind", "headerId", "sessionId", "item", "source", "bodyClass",
/// "errorText", "failedAt", "logId"}]}.
ClassMethod Batches(since As %Integer) As %DynamicArray
{
	Set batches = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Status, SessionId, SuperSession, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = ? AND MessageBodyClassName = 'OcuTalon.Watch.Msg.FailureBatch' ORDER BY ID", since, ..#MANAGER)
	While rs.%Next() {
		Set body = ##class(OcuTalon.Watch.Msg.FailureBatch).%OpenId(rs.%GetData(5))
		If '$IsObject(body) Continue
		Set failures = []
		For i = 1:1:body.Failures.Count() {
			Set failure = body.Failures.GetAt(i)
			Do failures.%Push({"kind": (failure.Kind), "headerId": (failure.HeaderId), "sessionId": (failure.SessionId), "item": (failure.ItemName), "source": (failure.SourceName), "bodyClass": (failure.BodyClass), "errorText": (failure.ErrorText), "failedAt": (failure.FailedAt), "logId": (failure.LogId)})
		}
		Do batches.%Push({"id": (rs.%GetData(1)), "status": (rs.%GetData(2)), "sessionId": (rs.%GetData(3)), "superSession": (rs.%GetData(4)), "namespace": (body.Namespace), "production": (body.Production), "ownerRef": (body.OwnerRef), "polledAt": (body.PolledAt), "failures": (failures)})
	}
	Quit batches
}

/// The number of failures in the batches, of the owner when it is not empty.
ClassMethod Count(batches As %DynamicArray, owner As %String = "") As %Integer
{
	Set count = 0
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		If (owner = "") || (batch.ownerRef = owner) Set count = count + batch.failures.%Size()
	}
	Quit count
}

/// Waits up to WAITBATCH seconds, polling every half second, until the batches after since hold at least count failures (of the owner, when it is
/// not empty); the batches then. A shortfall is the caller's assertion.
Method WaitBatched(since As %Integer, count As %Integer, owner As %String = "") As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set batches = ..Batches(since)
		If (..Count(batches, owner) '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit batches
}

/// The header ids of the failures of the batches (of the owner when it is not empty), ascending, each as many times as it appears.
ClassMethod Ids(batches As %DynamicArray, owner As %String = "") As %String
{
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		If (owner '= "") && (batch.ownerRef '= owner) Continue
		Set at = batch.failures.%GetIterator()
		While at.%GetNext(, .failure) {
			Set key = $Select(failure.headerId '= "": failure.headerId, 1: "l"_failure.logId)
			Set seen(key) = $Get(seen(key)) + 1
		}
	}
	Set ids = ""
	Set key = ""
	For {
		Set key = $Order(seen(key))
		Quit:key=""
		For i = 1:1:seen(key) {
			Set ids = ids_$Select(ids = "": "", 1: ",")_key
		}
	}
	Quit ids
}

/// Waits the pause that two polls take (QUIET seconds).
ClassMethod Settle()
{
	Hang ..#QUIET
}

/// Deletes the WatchMark rows of the namespace (the poller is the only writer of the mark; a test that needs a reading from the watch's CreatedAt on
/// begins by clearing it).
ClassMethod ClearMark(namespace As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.WatchMark WHERE Namespace = ?", namespace)
}

/// The WatchMark row of the production as {"exists", "markAt", "seen"}.
ClassMethod Mark(namespace As %String, production As %String) As %DynamicObject
{
	Set row = ##class(OcuTalon.Data.WatchMark).NamespaceProductionIndexOpen(namespace, production)
	If '$IsObject(row) Quit {"exists": 0, "markAt": "", "seen": ""}
	Quit {"exists": 1, "markAt": (row.MarkAt), "seen": (row.Seen)}
}

/// Waits up to WAITBATCH seconds for the WatchMark row of the production (the poller saves it just after it sends); its state as Mark gives it.
Method WaitMark(namespace As %String, production As %String) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set mark = ..Mark(namespace, production)
		If mark.exists || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit mark
}

/// Stops the FailurePoller item for the test (TempStopConfigItem, which leaves the definition as it is); OnAfterOneTest starts it again.
Method StopPoller() As %Boolean [ Private ]
{
	Set ..PollerStopped = 1
	Set sc = ##class(Ens.Director).TempStopConfigItem(..#POLLER, 1, 1)
	Do $$$AssertStatusOK(sc, "the "_..#POLLER_" item is stopped for the test")
	Quit $$$ISOK(sc)
}

/// Starts the FailurePoller item again.
Method StartPoller() As %Boolean [ Private ]
{
	Set sc = ##class(Ens.Director).TempStopConfigItem(..#POLLER, 0, 1)
	Do $$$AssertStatusOK(sc, "the "_..#POLLER_" item is started again")
	If $$$ISOK(sc) Set ..PollerStopped = 0
	Quit $$$ISOK(sc)
}

/// Stops an item of the Orders production in OCUORDERS for the test (TempStopConfigItem, which leaves the definition as it is); PutBack, so OnAfterOneTest too, starts it
/// again.
Method TempStopItem(item As %String) As %Boolean [ Private ]
{
	Set ..StoppedItem = item
	Set sc = ..TempItem(item, 1)
	Do $$$AssertStatusOK(sc, "the item "_item_" of the Orders production is stopped for the test")
	Quit $$$ISOK(sc)
}

/// Starts the item that TempStopItem stopped again.
Method TempStartItem(item As %String) As %Boolean [ Private ]
{
	Set sc = ..TempItem(item, 0)
	Do $$$AssertStatusOK(sc, "the item "_item_" of the Orders production is started again")
	If $$$ISOK(sc) Set ..StoppedItem = ""
	Quit $$$ISOK(sc)
}

/// Stops (1) or starts (0) the item for the time of the test in the production of OCUORDERS.
ClassMethod TempItem(item As %String, stop As %Boolean) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(Ens.Director).TempStopConfigItem(item, stop, 1)
}

/// Stops the Orders production in OCUORDERS for the test; OnAfterOneTest starts it again.
Method StopOrders() As %Boolean [ Private ]
{
	Set ..OrdersStopped = 1
	Set sc = ..StopOrdersNow()
	Do $$$AssertStatusOK(sc, "the Orders production is stopped")
	Quit $$$ISOK(sc)
}

/// Starts the Orders production in OCUORDERS again, and asserts that it runs.
Method StartOrders() As %Boolean [ Private ]
{
	Set sc = ..StartOrdersNow()
	Do $$$AssertStatusOK(sc, "the Orders production is started again")
	Do $$$AssertTrue(..OrdersRunning(), "and it runs")
	If $$$ISOK(sc) Set ..OrdersStopped = 0
	Quit $$$ISOK(sc)
}

ClassMethod StopOrdersNow() As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(Ens.Director).StopProduction(10, 1)
}

ClassMethod StartOrdersNow() As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	If ##class(Ens.Director).IsProductionRunning() Quit $$$OK
	Quit ##class(Ens.Director).StartProduction(..#ORDERSPRODUCTION)
}

/// 1 when the Orders production runs in OCUORDERS.
ClassMethod OrdersRunning() As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ''##class(Ens.Director).IsProductionRunning(.name) && (name = ..#ORDERSPRODUCTION)
}

/// Removes what the test made in OCUORDERS (the headers after the floor, with their bodies and the log rows of their sessions, the tagged messages of the
/// run, the fixture headers and log rows) and the FailureBatch messages that the poller sent to IncidentManager after the test's floor.
Method DropMessages() [ Private ]
{
	If (..OrdersFloor '= "") || (..FixtureHeaders '= "") || (..FixtureLogs '= "") {
		If ..OrdersFloor '= "" Do ..DropOrders(..OrdersFloor, ..OrdersLogFloor)
		Do ..DropFixtures(..FixtureHeaders, ..FixtureLogs)
		If (..OrdersFloor '= "") && (..Supers.%Size() > 0) Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers, ..#ORDERS)
	}
	If ..HomeFloor '= "" Do ..DropBatches(..HomeFloor)
	Set ..OrdersFloor = ""
	Set ..HomeFloor = ""
	Set ..FixtureHeaders = ""
	Set ..FixtureLogs = ""
}

/// The headers of OCUORDERS after the floor, their bodies and the log rows of their sessions, and the log rows after the log floor that have no
/// session and a type of error or alert. In the namespace, calling only Ens, % and the message bodies' classes while it is there.
ClassMethod DropOrders(floor As %Integer, logFloor As %Integer) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ?", floor)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = $ListBuild(rs.%GetData(3), rs.%GetData(4))
		If rs.%GetData(2) '= "" Set sessions(rs.%GetData(2)) = ""
	}
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, body)
		Quit:id=""
		If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	Set session = ""
	For {
		Set session = $Order(sessions(session))
		Quit:session=""
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", session)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SessionId IS NULL AND Type IN (2, 6) AND ConfigName LIKE 'zz%'", logFloor)
}

/// The fixture headers and log rows of OCUORDERS by id.
ClassMethod DropFixtures(headers As %List, logs As %List) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set position = 0
	While $ListNext(headers, position, id) {
		Set header = ##class(Ens.MessageHeader).%OpenId(id)
		If $IsObject(header) && (header.MessageBodyClassName = "OcuTalon.Demo.Orders.PartnerOrder") && (header.MessageBodyId '= "") Do ##class(OcuTalon.Demo.Orders.PartnerOrder).%DeleteId(header.MessageBodyId)
		Set header = ""
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	Set position = 0
	While $ListNext(logs, position, id) {
		Do ##class(Ens.Util.Log).%DeleteId(id)
	}
}

/// The FailureBatch messages after the header id in OCUTALON (the header and the body of each).
ClassMethod DropBatches(floor As %Integer) [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = ? AND MessageBodyClassName = 'OcuTalon.Watch.Msg.FailureBatch'", floor, ..#MANAGER)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = rs.%GetData(2)
	}
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, body)
		Quit:id=""
		Do ##class(OcuTalon.Watch.Msg.FailureBatch).%DeleteId(body)
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
}

/// A failure item name of this run: zzIncidents, the run's number and the suffix, so that a group never matches a real failure of Orders.
Method Item(suffix As %String) As %String [ Private ]
{
	Quit "zzIncidents"_..Number_suffix
}

/// Sends IncidentManager a FailureBatch of the production in the namespace for the owner (a fixture session's Ref, or instance) from an adapterless host in
/// the test process, as the poller does: its SuperSession is the owner's TraceRef (none for instance), and PolledAt is now. failures is a dynamic array of
/// {"item", "text", "at"} and, optionally, "id" (a header id; one of the run's own range is made when it is absent) and "kind" and "logId" (a log row is
/// then sent with no header id). The ids of the failures are given back, in order, as a dynamic array of keys.
Method SendBatch(namespace As %String, production As %String, ownerRef As %String, failures As %DynamicArray, Output keys As %DynamicArray) As %Status [ Private ]
{
	Set keys = []
	If ..HomeFloor = "" Do ..Since()
	Set batch = ##class(OcuTalon.Watch.Msg.FailureBatch).%New()
	Set batch.Namespace = namespace
	Set batch.Production = production
	Set batch.OwnerRef = ownerRef
	Set batch.PolledAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set iterator = failures.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set failure = ##class(OcuTalon.Watch.Msg.Failure).%New()
		Set failure.Kind = $Select(entry.kind '= "": entry.kind, 1: "header")
		If failure.Kind = "header" {
			Set failure.HeaderId = $Select(entry.id '= "": entry.id, 1: ..#SYNTHFIRST + $Increment(^OcuTalonTest("WatchCase", "synthetic")))
			Set failure.SessionId = failure.HeaderId
			Set failure.SourceName = "zzIncidentsSource"
		} Else {
			Set failure.LogId = $Select(entry.logId '= "": entry.logId, 1: ..#SYNTHFIRST + $Increment(^OcuTalonTest("WatchCase", "synthetic")))
		}
		Set failure.ItemName = entry.item
		Set failure.ErrorText = entry.text
		Set failure.FailedAt = entry.at
		Do batch.Failures.Insert(failure)
		Do keys.%Push(##class(OcuTalon.Watch.Mark).KeyOf(failure.Kind, failure.HeaderId, failure.LogId))
	}
	Set super = $Select(ownerRef = "instance": "", 1: ##class(OcuTalon.Data.Session).RefIndexOpen(ownerRef).TraceRef)
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set service.%SuperSession = super
	Quit service.SendRequestAsync(..#MANAGER, batch)
}

/// The Incident rows of the owner for the production, by ID, as a dynamic array of {"id", "ref", "ownerRef", "namespace", "production", "state", "openVariant",
/// "noticedAt", "count", "noticeCount", "firstAt", "lastAt", "closedAt", "traceHeaderId", "firstHeaderId", "sampleHeaderId", "sampleError", "requestRefs", "decisionRef",
/// "fallback", "fallbackReason", "causeCategory", "laterSince", "askingSince"}.
ClassMethod Incidents(ownerRef As %String, production As %String) As %DynamicArray
{
	Set incidents = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = ? AND Production = ? ORDER BY ID", ownerRef, production)
	While rs.%Next() {
		Set row = ##class(OcuTalon.Data.Incident).%OpenId(rs.%GetData(1))
		If '$IsObject(row) Continue
		Do incidents.%Push({"id": (row.%Id()), "ref": (row.Ref), "ownerRef": (row.OwnerRef), "namespace": (row.Namespace), "production": (row.Production), "state": (row.State), "openVariant": (row.OpenVariant), "noticedAt": (row.NoticedAt), "count": (row.Count), "noticeCount": (row.NoticeCount), "firstAt": (row.FirstAt), "lastAt": (row.LastAt), "closedAt": (row.ClosedAt), "traceHeaderId": (row.TraceHeaderId), "firstHeaderId": (row.FirstHeaderId), "sampleHeaderId": (row.SampleHeaderId), "sampleError": (row.SampleError), "requestRefs": (row.RequestRefs), "decisionRef": (row.DecisionRef), "fallback": (+row.Fallback), "fallbackReason": (row.FallbackReason), "causeCategory": (row.CauseCategory), "laterSince": (row.LaterSince), "askingSince": (row.AskingSince)})
	}
	Quit incidents
}

/// The failure groups of the incident as {"count", "itemName", "errorPattern", "seen", "groups"}: the number of groups, the first one's fields, and "groups", a
/// dynamic array of every group in ID order as {"seq", "itemName", "errorPattern", "seen", "count", "firstAt", "lastAt", "noticeCount", "errorSummary"}.
ClassMethod Group(ref As %String) As %DynamicObject
{
	Set group = {"count": 0, "itemName": "", "errorPattern": "", "seen": "", "groups": []}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.FailureGroup WHERE IncidentRef = ? ORDER BY ID", ref)
	While rs.%Next() {
		Set row = ##class(OcuTalon.Data.FailureGroup).%OpenId(rs.%GetData(1))
		If '$IsObject(row) || (row.IncidentRef '= ref) Continue
		Set group.count = group.count + 1
		Do group.groups.%Push({"seq": (row.Seq), "itemName": (row.ItemName), "errorPattern": (row.ErrorPattern), "seen": (row.Seen), "count": (row.Count), "firstAt": (row.FirstAt), "lastAt": (row.LastAt), "noticeCount": (row.NoticeCount), "errorSummary": (row.ErrorSummary)})
		If group.count = 1 {
			Set group.itemName = row.ItemName
			Set group.errorPattern = row.ErrorPattern
			Set group.seen = row.Seen
		}
	}
	Quit group
}

/// Waits up to seconds (WAITINCIDENT by default), polling every half second, for count Incident rows of the owner for the production; the rows as Incidents gives
/// them. A shortfall is the caller's assertion.
Method WaitIncident(ownerRef As %String, production As %String, count As %Integer = 1, seconds As %Integer = {..#WAITINCIDENT}) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set incidents = ..Incidents(ownerRef, production)
		If (incidents.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit incidents
}

/// Waits up to seconds (WAITINCIDENT by default), polling every half second, until the incident's NoticeCount is set; the NoticeCount then. "" when the
/// incident is gone.
Method WaitNoticeCount(ref As %String, seconds As %Integer = {..#WAITINCIDENT}) As %Integer [ Private ]
{
	Quit ..WaitRow(ref, "NoticeCount", "", seconds)
}

/// Waits up to seconds (WAITINCIDENT by default), polling every half second, until the incident's Count is at least count; the Count then. "" when the incident
/// is gone.
Method WaitCount(ref As %String, count As %Integer, seconds As %Integer = {..#WAITINCIDENT}) As %Integer [ Private ]
{
	Quit ..WaitRow(ref, "Count", count, seconds)
}

/// Waits up to seconds, polling every half second, until the incident's property is set (least "") or at least least; the property's value then, "" when
/// the incident is gone. The row is opened afresh each time, as an object that is still held would show the values it was opened with: so the caller
/// holds no object of the row either, or the open gives back that object.
Method WaitRow(ref As %String, property As %String, least As %Integer, seconds As %Integer) As %String [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If '$IsObject(row) Quit
		Set value = $Property(row, property)
		If $Select(least = "": value '= "", 1: value '< least) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit $Select($IsObject(row): $Property(row, property), 1: "")
}

/// Waits up to seconds (WAITDIAGNOSIS by default), polling every half second, until the incident holds its diagnosis or the fallback of it: DecisionRef is set or
/// Fallback is 1. The row is opened afresh each time. 1 when it does; 0 when the time has passed or the incident is gone.
Method WaitDiagnosed(ref As %String, seconds As %Integer = {..#WAITDIAGNOSIS}) As %Boolean [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If '$IsObject(row) Quit
		If (row.DecisionRef '= "") || row.Fallback || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit $IsObject(row) && ((row.DecisionRef '= "") || row.Fallback)
}

/// The events on the session's stream, of any type, in Seq order, as the envelopes {seq, stream, ts, type, payload}.
ClassMethod Stream(session As %String) As %DynamicArray
{
	Quit ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
}

/// The Notification messages that carry the incident's Ref (only those of the kind, when one is given), oldest first, as a dynamic array of {"id", "sessionRef",
/// "kind", "catalogKey", "slots" (the parsed object, {} when empty), "approvalRef", "incidentRef", "decisionRef"}.
ClassMethod NoticeBodies(ref As %String, kind As %String = "") As %DynamicArray
{
	Set bodies = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Msg.Notification WHERE IncidentRef = ? ORDER BY ID", ref)
	While rs.%Next() {
		Set note = ##class(OcuTalon.Msg.Notification).%OpenId(rs.%GetData(1))
		If '$IsObject(note) Continue
		If (kind '= "") && (note.Kind '= kind) Continue
		Set slots = {}
		If note.Slots '= "" Set slots = {}.%FromJSON(note.Slots)
		Do bodies.%Push({"id": (note.%Id()), "sessionRef": (note.SessionRef), "kind": (note.Kind), "catalogKey": (note.CatalogKey), "slots": (slots), "approvalRef": (note.ApprovalRef), "incidentRef": (note.IncidentRef), "decisionRef": (note.DecisionRef)})
	}
	Quit bodies
}

/// Waits up to WAITINCIDENT seconds, polling every quarter second, for WebChatOut to record the Delivery row of the web chat for the session, the kind and the
/// request's Ref (Integration AC of Story 7.2), then asserts that there is exactly one.
Method AssertDelivered(session As %String, kind As %String, approvalRef As %String) [ Private ]
{
	Do ..AssertDeliveredIn(session, ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL, kind, approvalRef)
}

/// AssertDelivered for any channel: waits up to WAITINCIDENT seconds, polling every quarter second, for the channel's Delivery row for the session, the kind and the
/// request's Ref, then asserts that there is exactly one.
Method AssertDeliveredIn(session As %String, channel As %String, kind As %String, approvalRef As %String) [ Private ]
{
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set count = ..Deliveries(session, channel, kind, approvalRef)
		If count || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(count, 1, "the "_channel_" channel recorded one "_kind_" Delivery row with the request's Ref")
}

/// The requests that an incident payload (an incident event's, or /state's) lists, as "<count>|<Ref>|<State>" of the request at the index (the first by default);
/// "0||" when it lists none.
ClassMethod Listed(payload As %DynamicObject, index As %Integer = 0) As %String
{
	Set requests = payload.requests
	If '$IsObject(requests) || (requests.%Size() = 0) Quit "0||"
	Set entry = requests.%Get(index)
	Quit requests.%Size()_"|"_$Select($IsObject(entry): entry.ref_"|"_entry.state, 1: "|")
}

/// The incident's payload as /state (Web.Api.StateBody) lists it for the session, or "" when /state does not list it.
ClassMethod StateIncident(session As %String, ref As %String) As %DynamicObject
{
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	If '$IsObject(body) Quit ""
	Set found = ""
	Set iterator = body.chat.%GetIterator()
	While iterator.%GetNext(, .each) {
		If (each.type = "incident") && (each.payload.ref = ref) Set found = each.payload
	}
	Quit found
}

/// The result that an incident payload (an incident event's, or /state's) lists for the request at the index (the first by default) as
/// "total|resent|completed|failedAgain|skipped|interrupted|reason" (Story 7.4); "none" when the request has no result or the payload lists no such request.
ClassMethod ResultOf(payload As %DynamicObject, index As %Integer = 0) As %String
{
	Set requests = payload.requests
	If '$IsObject(requests) || (requests.%Size() '> index) Quit "none"
	Set result = requests.%Get(index).result
	If '$IsObject(result) Quit "none"
	Quit result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped_"|"_result.interrupted_"|"_result.reason
}

/// The payload of the newest incident event of the incident on the session's stream, or "" when there is none.
ClassMethod LastIncident(session As %String, ref As %String) As %DynamicObject
{
	Set events = ..Stream(session)
	Set found = ""
	For i = 0:1:events.%Size() - 1 {
		Set event = events.%Get(i)
		If (event.type = "incident") && (event.payload.ref = ref) Set found = event.payload
	}
	Quit found
}

/// The number of Delivery rows of the owner in the channel, of the kind, for the request's Ref.
ClassMethod Deliveries(owner As %String, channel As %String, kind As %String, approvalRef As %String) As %Integer
{
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(owner)
	Set count = 0
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If $IsObject(row) && (row.Channel = channel) && (row.Kind = kind) && (row.ApprovalRef = approvalRef) Set count = count + 1
	}
	Quit count
}

/// The number of model requests (POST /v1/messages) in the mock's request log after its first mark lines; -1 when the log cannot be read.
ClassMethod Posts(mark As %Integer) As %Integer
{
	If $$$ISERR(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Quit -1
	Set posts = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") Set posts = posts + 1
	}
	Quit posts
}

/// The number of Notification messages that carry the incident's Ref.
ClassMethod Notifications(ref As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Msg.Notification WHERE IncidentRef = ?", ref)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Waits up to WAITINCIDENT seconds, polling every half second, until count Notification messages carry the incident's Ref (the send follows the save
/// of NoticedAt).
Method WaitNotices(ref As %String, count As %Integer) [ Private ]
{
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		If (..Notifications(ref) '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
}

/// Waits up to seconds (WAITINCIDENT by default), polling every half second, until IncidentManager has handled Decide's answer to the incident's diagnose
/// request: the answer's header in the trace session (the incident's TraceHeaderId when session is empty) is Completed, which the framework sets once
/// OnResponse has returned, so the notice step that follows the stored diagnosis has run. 1 when it is handled; 0 when the time has passed or there is no
/// trace session.
Method WaitAnswered(ref As %String, session As %String = "", seconds As %Integer = {..#WAITINCIDENT}) As %Boolean [ Private ]
{
	If session = "" {
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		Set session = $Select($IsObject(row): row.TraceHeaderId, 1: "")
		Kill row
	}
	If session = "" Quit 0
	Set end = $ZHorolog + seconds
	For {
		Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(session), 2, "Decide", ..#MANAGER)
		Set handled = 0
		For i = 0:1:answers.%Size() - 1 {
			If answers.%Get(i).status = $$$eMessageStatusCompleted Set handled = 1
		}
		If handled || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit handled
}

/// The set-up of a test with a raised request of session S: the production is ready, the mock is pointed to, the approval role is ready, S watches Orders and
/// orders failing orders (3 by default) tagged with S's trace Ref become an incident that is noticed with its fix. a is S, ref the incident and request the request, as
/// Case.Requests gives it. 1 when the set-up is done.
Method Raised(name As %String, Output a As %String, Output ref As %String, Output request As %DynamicObject, orders As %Integer = 3) As %Boolean [ Private ]
{
	Set (a, ref, request) = ""
	If '..Ready() Quit 0
	If '..PointKeys() Quit 0
	If '..ApprovalReady() Quit 0
	Set a = ..Session(name)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	If '..Fail(orders, trace) Quit 0
	Set failed = ..WaitFailed(orders)
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident for the burst of S")
	If rows.%Size() < 1 Quit 0
	Set ref = rows.%Get(0).ref
	If '..Noticed(ref, 1) Quit 0
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident")
	If requests.%Size() '= 1 Quit 0
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.state, "pending", "and it is pending")
	Quit (request.state = "pending")
}

/// Waits for the diagnosis of the incident to be handled and the notice to be sent: IncidentManager has handled Decide's answer, NoticedAt is set and count
/// Notifications carry the incident's Ref. 1 when all three are, else 0 with a failed assertion.
Method Noticed(ref As %String, count As %Integer) As %Boolean [ Private ]
{
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertTrue(..WaitAnswered(ref), "and IncidentManager has handled the answer")
	Set noticed = (..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "")
	Do $$$AssertTrue(noticed, "the notice follows: NoticedAt is set")
	If 'noticed Quit 0
	Do ..WaitNotices(ref, count)
	Quit 1
}

/// The answered Notification of the incident once count of them exist: {"id", "sessionRef", "kind", "catalogKey", "slots", "approvalRef", "incidentRef",
/// "decisionRef"}, or "" with a failed assertion when there are not exactly count.
Method Answered(ref As %String, count As %Integer) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set found = ..NoticeBodies(ref, "answered")
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(found.%Size(), count, count_" answered notification(s) carry the incident's Ref")
	If found.%Size() '= count Quit ""
	Quit found.%Get(0)
}

/// The trace session of the header that carried the Notification.
ClassMethod NoticeSessionOf(id As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Msg.Notification' AND MessageBodyId = ? ORDER BY ID", id)
	If rs.%Next() Quit rs.%GetData(1)
	Quit ""
}

/// Deletes the Incident rows that the run's sessions own and the instance incidents with an ID above the floor, with their failure groups and their diagnose
/// decisions (and the usage and steps of those).
Method DropIncidents(floor As %Integer) [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" Do ..DropIncidentRows("SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = ?", ref)
	}
	If floor '= "" Do ..DropIncidentRows("SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = 'instance' AND ID > ?", floor)
}

/// Deletes the Incident rows that the select (one bound value, an ID column) gives, with their failure groups, fix runs, diagnose decisions, usage and steps.
/// Every ApprovalRequest that names a deleted incident is tracked under ^OcuTalonTest("Approval","refs") first, and Test.Bridge.Approval.Clean then ends the
/// holds and tasks and deletes the rows (Story 7.2).
/// Public: the Demo tests that cause real incidents (Test.Demo.Production) call it too.
ClassMethod DropIncidentRows(select As %String, value As %String)
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, select, value)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = ""
	}
	Set id = ""
	For {
		Set id = $Order(ids(id))
		Quit:id=""
		Set row = ##class(OcuTalon.Data.Incident).%OpenId(id)
		If '$IsObject(row) Continue
		If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(row.Ref)
		Set requests = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE IncidentRef = ?", row.Ref)
		While requests.%Next() {
			Set ^OcuTalonTest("Approval", "refs", requests.%Get("Ref")) = ""
			Set tracked = 1
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", row.Ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", row.Ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FailureGroup WHERE IncidentRef = ?", row.Ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE IncidentRef = ?", row.Ref)
		Do ##class(OcuTalon.Data.Incident).%DeleteId(id)
	}
	If $Get(tracked) Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
}

/// The set-up of a test with two raised requests of session S (Story 7.3, Story 7.6): Raised (S's incident is noticed with its fix and the pending request first),
/// then two more failing orders tagged with S's trace Ref, and the wait for the second request over them (WAITLATER seconds), whose notice is waited for too.
/// first and second are the requests as Case.Requests gives them. 1 when the set-up is done.
Method RaisedTwo(name As %String, Output a As %String, Output ref As %String, Output first As %DynamicObject, Output second As %DynamicObject) As %Boolean [ Private ]
{
	Set second = ""
	If '..Raised(name, .a, .ref, .first) Quit 0
	If '..Fail(2, ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef) Quit 0
	Set failed = ..WaitFailed(5)
	If failed.%Size() '= 5 Quit 0
	Set end = $ZHorolog + ..#WAITLATER
	For {
		Set requests = ..Requests(ref)
		If (requests.%Size() '< 2) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(requests.%Size(), 2, "a second request names the incident")
	If requests.%Size() '= 2 Quit 0
	Do ..WaitNotices(ref, 2)
	Set second = requests.%Get(1)
	Quit 1
}

/// The FixRun rows of the incident, by ID, as a dynamic array of {"id", "approvalRef", "incidentRef", "startedAt", "copies" (an array of the registered header ids),
/// "resentAt", "endedAt", "total", "resent", "completed", "failedAgain", "skipped", "interrupted", "reason" (the run's stored result; empty before it ended)}.
ClassMethod Runs(incidentRef As %String) As %DynamicArray
{
	Set runs = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.FixRun WHERE IncidentRef = ? ORDER BY ID", incidentRef)
	While rs.%Next() {
		Set row = ##class(OcuTalon.Data.FixRun).%OpenId(rs.%GetData(1))
		If '$IsObject(row) Continue
		Set copies = []
		For i = 1:1:row.Copies.Count() {
			Do copies.%Push(row.Copies.GetAt(i))
		}
		Do runs.%Push({"id": (row.%Id()), "approvalRef": (row.ApprovalRef), "incidentRef": (row.IncidentRef), "startedAt": (row.StartedAt), "copies": (copies), "resentAt": (row.ResentAt), "endedAt": (row.EndedAt), "total": (row.Total), "resent": (row.Resent), "completed": (row.Completed), "failedAgain": (row.FailedAgain), "skipped": (row.Skipped), "interrupted": (row.Interrupted), "reason": (row.Reason)})
	}
	Quit runs
}

/// The FixRun of the request among the incident's runs as Runs gives it, "" when there is none.
ClassMethod RunOf(incidentRef As %String, approvalRef As %String) As %DynamicObject
{
	Set runs = ..Runs(incidentRef)
	For i = 0:1:runs.%Size() - 1 {
		If runs.%Get(i).approvalRef = approvalRef Return runs.%Get(i)
	}
	Quit ""
}

/// Waits up to seconds (WAITRUN by default), polling every half second, until the request's FixRun holds at least count copies; the run as Runs gives it, or ""
/// when the time has passed without a run. A shortfall of copies is the caller's assertion.
Method WaitRun(incidentRef As %String, approvalRef As %String, count As %Integer, seconds As %Integer = {..#WAITRUN}) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set run = ..RunOf(incidentRef, approvalRef)
		If ($IsObject(run) && (run.copies.%Size() '< count)) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit run
}

/// Waits up to seconds (WAITRUN by default), polling every half second, until the request of the incident is in the state; the state then ("" when there is no such request).
Method WaitState(incidentRef As %String, approvalRef As %String, state As %String, seconds As %Integer = {..#WAITRUN}) As %String [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set found = ""
		Set requests = ..Requests(incidentRef)
		For i = 0:1:requests.%Size() - 1 {
			If requests.%Get(i).ref = approvalRef Set found = requests.%Get(i).state
		}
		If (found = state) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit found
}

/// Waits up to seconds (WAITRUN by default), polling every half second, until the incident's State is the given one; the state then ("" when the incident is gone).
/// The row is opened afresh each time (see WaitRow).
Method WaitIncidentState(ref As %String, state As %String, seconds As %Integer = {..#WAITRUN}) As %String [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If '$IsObject(row) Quit
		If (row.State = state) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit $Select($IsObject(row): row.State, 1: "")
}

/// A message header of the namespace with its body, as {"id", "sessionId", "superSession", "description", "resent", "status" (the code: 8 error, 9 completed), "type",
/// "source", "target", "bodyClass", "bodyId", "body" (the stored datatype properties of the body, by name)}, or "" when there is no such header. In the namespace,
/// calling only Ens, % and the body's class while it is there.
ClassMethod Header(namespace As %String, id As %String) As %DynamicObject
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit ""
	Set body = {}
	Set bodyClass = header.MessageBodyClassName
	If (bodyClass '= "") && (header.MessageBodyId '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(bodyClass) && $ClassMethod(bodyClass, "%Extends", "%Library.Persistent") {
		Set object = $ClassMethod(bodyClass, "%OpenId", header.MessageBodyId)
		If $IsObject(object) {
			Set props = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND Private = 0 AND Calculated = 0 AND Transient = 0 AND MultiDimensional = 0 AND Relationship = 0 ORDER BY SequenceNumber", bodyClass)
			While props.%Next() {
				Set name = props.%Get("Name")
				If ##class(%Dictionary.CompiledProperty).%OpenId(bodyClass_"||"_name).Collection '= "" Continue
				Set type = ##class(%Dictionary.CompiledClass).%OpenId(##class(%Dictionary.CompiledProperty).%OpenId(bodyClass_"||"_name).Type)
				If '$IsObject(type) || (type.ClassType '= "datatype") Continue
				Do body.%Set(name, $Property(object, name))
			}
		}
	}
	Quit {"id": (header.%Id()), "sessionId": (header.SessionId), "superSession": (header.SuperSession), "description": (header.Description), "resent": (header.Resent), "status": (header.Status), "type": (header.Type), "source": (header.SourceConfigName), "target": (header.TargetConfigName), "bodyClass": (bodyClass), "bodyId": (header.MessageBodyId), "body": (body)}
}

/// Waits up to seconds (WAITCOPY by default), polling every half second, until every header of the comma-separated ids in the namespace is Completed (status 9);
/// 1 when they all are, 0 when the time has passed.
Method WaitCompleted(namespace As %String, ids As %String, seconds As %Integer = {..#WAITCOPY}) As %Boolean [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set done = 1
		For i = 1:1:$Length(ids, ",") {
			Set header = ..Header(namespace, $Piece(ids, ",", i))
			If '$IsObject(header) || (header.status '= $$$eMessageStatusCompleted) Set done = 0
		}
		If done || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit done
}

/// The number of headers among the ids (comma-separated) in the namespace that are Completed (status 9), read from the stored status only.
ClassMethod CompletedCount(namespace As %String, ids As %String) As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set count = 0
	For i = 1:1:$Length(ids, ",") {
		If ##class(Ens.MessageHeader).StatusGetStored($Piece(ids, ",", i)) = $$$eMessageStatusCompleted Set count = count + 1
	}
	Quit count
}

/// Waits up to seconds (WAITCOPY by default), polling every quarter second, until no header of the sessions (comma-separated session ids) in the namespace is
/// still created, queued or delivered, so that a snapshot taken then holds no header whose status is about to change; 1 when they have settled, 0 when the time
/// has passed. In the namespace, calling only %SQL there.
ClassMethod WaitSettled(namespace As %String, sessions As %String, seconds As %Integer = {..#WAITCOPY}) As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set end = $ZHorolog + seconds
	For {
		Set busy = 0
		For i = 1:1:$Length(sessions, ",") {
			Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND Status IN (?, ?, ?)", $Piece(sessions, ",", i), $$$eMessageStatusCreated, $$$eMessageStatusQueued, $$$eMessageStatusDelivered)
			If rs.%SQLCODE < 0 Return 0
			Do rs.%Next()
			Set busy = busy + rs.%GetData(1)
		}
		If (busy = 0) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit busy = 0
}

/// The Execute headers from IncidentManager to FixExecutor in the trace session whose body carries the request's Ref, once there is one (up to seconds), as header objects.
Method ExecutesOf(trace As %String, approvalRef As %String, seconds As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set found = []
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(trace), 1, ..#MANAGER, ..#EXECUTOR)
		For i = 0:1:sent.%Size() - 1 {
			If sent.%Get(i).bodyClass '= "OcuTalon.Fix.Msg.Execute" Continue
			Set body = ##class(OcuTalon.Fix.Msg.Execute).%OpenId(sent.%Get(i).bodyId)
			If $IsObject(body) && (body.ApprovalRef = approvalRef) Do found.%Push(sent.%Get(i))
		}
		If (found.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The FixResult bodies that FixExecutor sent to IncidentManager in the trace session, once there are count of them (up to WAITINCIDENT seconds), as FixResult objects.
Method FixResultsOf(trace As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set found = []
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(trace), 1, ..#EXECUTOR, ..#MANAGER)
		For i = 0:1:sent.%Size() - 1 {
			If sent.%Get(i).bodyClass = "OcuTalon.Fix.Msg.FixResult" Do found.%Push(##class(OcuTalon.Fix.Msg.FixResult).%OpenId(sent.%Get(i).bodyId))
		}
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// Sets the OrderDate of the order that the header holds, in OCUORDERS. The test edits only the orders it made.
ClassMethod SetOrderDate(headerId As %Integer, value As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_headerId)
	Set order = ##class(OcuTalon.Demo.Orders.PartnerOrder).%OpenId(header.MessageBodyId)
	If '$IsObject(order) Quit $SYSTEM.Status.Error(5001, "No order for header "_headerId)
	Set order.OrderDate = value
	Quit order.%Save()
}

/// Sends an Execute for the request's Ref to the item FixExecutor by name, synchronously, from the SimMailboxIn service (an adapterless host, in a session of its own),
/// and waits for the answer. The session of the send is kept for the clean-up and given in session. The status of the send.
Method SendExecute(approvalRef As %String, Output session As %Integer) As %Status [ Private ]
{
	Set session = ""
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SENDER, .service)
	If $$$ISERR(sc) Quit sc
	Set request = ##class(OcuTalon.Fix.Msg.Execute).%New()
	Set request.ApprovalRef = approvalRef
	Set sc = service.SendRequestSync(..#EXECUTOR, request, .response, 60)
	Set session = service.%SessionId
	Set ..ExecuteSessions = ..ExecuteSessions _ $Select(..ExecuteSessions = "": "", 1: ",") _ session
	Quit sc
}

/// Removes the headers, bodies and log rows of the sessions that SendExecute used, in the home namespace.
Method DropExecuteSessions() [ Private ]
{
	For i = 1:1:$Length(..ExecuteSessions, ",") {
		Set session = $Piece(..ExecuteSessions, ",", i)
		If session = "" Continue
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ?", session)
		Kill ids
		While rs.%Next() {
			Set ids(rs.%GetData(1)) = $ListBuild(rs.%GetData(2), rs.%GetData(3))
		}
		Set id = ""
		For {
			Set id = $Order(ids(id), 1, body)
			Quit:id=""
			If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
			Do ##class(Ens.MessageHeader).%DeleteId(id)
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", session)
	}
	Set ..ExecuteSessions = ""
}

/// Sets the FixParameters of the approval request's row to the JSON text (a fixture, before any answer: the request's parameters are not a product input a test may
/// change otherwise). 1 when the row is saved.
Method SetFixParameters(ref As %String, json As %String) As %Boolean [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the request "_ref_" has a row")
		Quit 0
	}
	Set row.FixParameters = json
	Set sc = row.%Save()
	Do $$$AssertStatusOK(sc, "the request's FixParameters are "_json)
	Quit $$$ISOK(sc)
}

/// Sends a Fix.Msg.DryRun from the SimMailboxIn service, in the trace session of the super session, to the item FixExecutor by name, and waits for the answer.
/// The answer (a DryRunResult, or "") is given back; the session of the request is kept for the clean-up and given in session.
Method AskDryRun(incidentRef As %String, kind As %String, parameters As %String, super As %String, Output session As %Integer, Output sc As %Status) As OcuTalon.Fix.Msg.DryRunResult [ Private ]
{
	Set session = ""
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SENDER, .service)
	If $$$ISERR(sc) Quit ""
	Set service.%SuperSession = super
	Set request = ##class(OcuTalon.Fix.Msg.DryRun).%New()
	Set request.IncidentRef = incidentRef
	Set request.FixKind = kind
	Set request.Parameters = parameters
	Set sc = service.SendRequestSync(..#EXECUTOR, request, .response, ..#SENDWAIT)
	Set session = service.%SessionId
	Set ..DrySessions = ..DrySessions _ $Select(..DrySessions = "": "", 1: ",") _ session
	Quit $Select($$$ISOK(sc) && $IsObject($Get(response)): response, 1: "")
}

/// Removes the headers, bodies and log rows of the sessions that AskDryRun used, in the home namespace.
Method DropDrySessions() [ Private ]
{
	For i = 1:1:$Length(..DrySessions, ",") {
		If $Piece(..DrySessions, ",", i) '= "" Do ..DropSession($Piece(..DrySessions, ",", i))
	}
	Set ..DrySessions = ""
}

/// Removes the headers and the bodies of a session of the home namespace, and its log rows.
ClassMethod DropSession(session As %String) [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ?", session)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = $ListBuild(rs.%GetData(2), rs.%GetData(3))
	}
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, body)
		Quit:id=""
		If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", session)
}

/// The header ids of the copies (a dynamic array of ids), comma-separated.
ClassMethod Joined(copies As %DynamicArray) As %String
{
	Set text = ""
	For i = 0:1:copies.%Size() - 1 {
		Set text = text _ $Select(text = "": "", 1: ",") _ copies.%Get(i)
	}
	Quit text
}

/// The originals that the copies (a dynamic array of header ids, in OCUORDERS) were made of, the id that each copy's Description names, comma-separated, in the order
/// of the copies; "?" for a copy that cannot be read.
ClassMethod Originals(copies As %DynamicArray) As %String
{
	Set text = ""
	For i = 0:1:copies.%Size() - 1 {
		Set copy = ..Header(..#ORDERS, copies.%Get(i))
		Set text = text _ $Select(text = "": "", 1: ",") _ $Select($IsObject(copy): +$Piece(copy.description, " ", 2), 1: "?")
	}
	Quit text
}

/// The names of the keys of the object, sorted, comma-separated.
ClassMethod SortedKeys(object As %DynamicObject) As %String
{
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set sorted(key) = ""
	}
	Set names = ""
	Set key = ""
	For {
		Set key = $Order(sorted(key))
		Quit:key=""
		Set names = names _ $Select(names = "": "", 1: ",") _ key
	}
	Quit names
}

/// Asserts that the answer (a dynamic object, or the JSON text that the model got) has the fields of the expected flat object with its values and types,
/// and no other. A field that holds an array or an object is compared by its JSON text.
Method AssertObject(actual As %Any, expected As %DynamicObject, label As %String) [ Private ]
{
	If '$IsObject(actual) {
		Set text = actual
		Set actual = ""
		Try {
			Set actual = {}.%FromJSON(text)
		} Catch {
			Set actual = ""
		}
		If '$IsObject(actual) {
			Do $$$AssertTrue(0, label_": the result is a JSON object: "_$Extract(text, 1, 200))
			Quit
		}
	}
	Do $$$AssertEquals(..SortedKeys(actual), ..SortedKeys(expected), label_": the fields")
	Set iterator = expected.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do $$$AssertEquals(actual.%GetTypeOf(key), expected.%GetTypeOf(key), label_": "_key_" is a "_expected.%GetTypeOf(key))
		If $IsObject(value) {
			Do $$$AssertEquals(actual.%Get(key).%ToJSON(), value.%ToJSON(), label_": "_key_" is "_value.%ToJSON())
		} Else {
			Do $$$AssertEquals(actual.%Get(key), value, label_": "_key_" is '"_value_"'")
		}
	}
}

}
