/// Tests of the Chat agent's watch tools (Story 5.1; AD-1, AD-3, AD-4, AD-9, AD-10, AD-18): start_watch, stop_watch, list_productions, dismiss_incident (Story 5.9) and check_status (Story 5.7), the toolset
/// OcuTalon.Tools.Watching, its provider OcuTalon.Tools.WatchTools and its helper OcuTalon.Tools.WatchAnswers. TestDeclarations, TestJoined, TestDecide,
/// TestIncidentsNotRead, TestDismissedData and TestCheckStatusDescription need no production; THE OTHER TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case: the tools read the real
/// Watch.Reader and submit to Test.Tools.CommandsDouble, which sits behind the CommandsIn item and records every command. The tests call the tool
/// methods in this process, with a bridge context begun for the turn, as Test.Tools.Reminders does.
///   - TestDeclarations: Chat's TOOLSETS names both toolsets; Watching offers exactly start_watch, stop_watch, list_productions, dismiss_incident and
///     check_status of Tools.Names, each once, from WatchTools, and (Story 5.13) recent_activity from RecentActivity; each has its own step label and the flags of the spec (all safe and trusted output, only
///     list_productions, check_status and recent_activity read-only); the inputs are name (required) and namespace for start and stop, none for list, check_status and recent_activity, and incident
///     and production (none required) for dismiss, and none names a session, an owner or an origin;
///   - TestCheckStatus, TestCheckStatusHostData and TestCheckStatusNotRead (Story 5.7; matrix "check_status", "HostData kept", "Refused"): check_status gives the
///     session's own production rows by ID with the time in the instance zone, copies them to HostData with the UTC time, keeps the other members of a JSON
///     object HostData and replaces an earlier checks, submits nothing, and leaves HostData as it was when it is refused; each asserts the whole answer and the
///     whole HostData, so a field added later fails;
///   - TestCheckStatusDescription (Story 5.7, QA; no production): the description of check_status for the model says when to call it, what a not_checked and an empty result mean, that OcuTalon
///     shows the results itself, and not to list them or say that everything passed;
///   - TestStart and TestStop (matrix "Start", "Stop"): one command with origin tool, the session of the turn, the key <ItemId>:1 and the namespace, the
///     production and (for a start) the display name, and no other field; the answer is the owner's message, ok, ref, the outcome and the production's name;
///   - TestNameForms: the name is trimmed, case-insensitive, may end in " production" and may be the class name, and the namespace argument narrows it;
///   - TestUnknownName ("Unknown name, not the demo") and TestOnlyOrders ("Online demo, another name"): nothing is submitted, and the answer is
///     unknown_production with the name, the list and the productions, or only_orders with the README link; Orders still starts on the online demo;
///   - TestDecide and TestJoined (pure): ambiguous with each match's name and namespace, the other refusals, and the list joined with ", " and " and ";
///   - TestListProductions: the list of the productions, as the reader gives it, and nothing is submitted;
///   - TestDismissOne ("One", "Resolved"), TestDismissPicks ("By production", "Ambiguous", "By ref"), TestDismissUnknown ("Unknown"), TestDismissNone
///     ("None") and TestDismissInstance ("Instance") (Story 5.9): which incident dismiss_incident submits a Dismiss for, against the double, with the
///     recorded commands (origin tool, the session, the key <ItemId>:<n>, the IncidentRef and no other field) and the whole answer; an incident that is
///     not open or resolved, not noticed or not the session's is never submitted, and a production of white space alone is not given;
///   - TestIncidentsNotRead and TestDismissedData (Story 5.9, QA; pure, no production): WatchAnswers.ResolveIncident answers INCIDENTSNOTREAD and offers nothing
///     to submit when Ownership cannot read the incidents (the owners instance and eval and an empty one are refused), and WatchAnswers.Dismissed adds state and
///     openVariant only for a Data that is a JSON object with a string state, and never raises for any other Data;
///   - TestNoSession ("No session"): no context, an owner that is not a session's Ref or no ItemId answers NOSESSION and submits nothing, before anything
///     is looked up (also with a name that no production has);
///   - TestSubmitFails and TestSubmitEmpty ("Submit fails", also for dismiss_incident): a failed submit, and one answered with no CommandResult, answer NOTSENT with one redacted
///     warning of CommandCall.Run that names the verb's class; the double still recorded the command;
///   - TestSubmitKeepsTheJobSession (DW-74): the event-log session of the job is as it was after an answered submit and after a failed one, and the
///     warning of the failed one is logged in it;
///   - TestRefusal: the owner's refusal reaches the model as ok false with the owner's message, the outcome and the production (for dismiss_incident
///     also the ref);
///   - TestResolveStop (Story 5.2, DW-222): stop_watch resolves from the session's own watches first, with the reader's matching rule: an own row that
///     the reader does not list is stopped, two own matches are ambiguous (the namespace argument picks one), another session's rows and a name that no own row
///     matches take the reader's path as before, and the answers carry the display name of the row;
///   - TestStopWatchOfAnUnlistedProduction (AC 5; no double): session A watches Orders, the service role loses Read on its data, the reader no longer lists
///     Orders, and stop_watch("Orders") through the real CommandsIn and WatchOps answers stopped and removes the row;
///   - TestKeys: the keys of a turn's commands are <ItemId>:1, :2, ... in the order of the calls, and a call that submits nothing takes no position.
Class OcuTalon.Test.Watch.Tools Extends OcuTalon.Test.Watch.Case
{

Parameter TOOLS = "OcuTalon.Tools.WatchTools";

Parameter TOOLSET = "OcuTalon.Tools.Watching";

Parameter ANSWERS = "OcuTalon.Tools.WatchAnswers";

Parameter CALL = "OcuTalon.Tools.CommandCall";

Parameter READER = "OcuTalon.Watch.Reader";



Method TestDeclarations()
{
	Set names = "OcuTalon.Tools.Names"
	Do $$$AssertEquals($Parameter("OcuTalon.Agent.Chat", "TOOLSETS"), "OcuTalon.Tools.Reminders,"_..#TOOLSET, "Chat's TOOLSETS names both toolsets")
	Set want("start_watch") = $ListBuild("safe", 0, 1, "Starting a watch", "name,namespace", "name")
	Set want("stop_watch") = $ListBuild("safe", 0, 1, "Stopping a watch", "name,namespace", "name")
	Set want("list_productions") = $ListBuild("safe", 1, 1, "Listing the productions", "", "")
	Set want("dismiss_incident") = $ListBuild("safe", 0, 1, "Dismissing an incident", "incident,production", "")
	Set want("check_status") = $ListBuild("safe", 1, 1, "Reading the check results", "", "")
	Set want("recent_activity") = $ListBuild("safe", 1, 1, "Reading recent activity", "", "")
	Set expected = $ListBuild($Parameter(names, "STARTWATCH"), $Parameter(names, "STOPWATCH"), $Parameter(names, "LISTPRODUCTIONS"), $Parameter(names, "DISMISSINCIDENT"), $Parameter(names, "CHECKSTATUS"), $Parameter(names, "RECENTACTIVITY"))
	Set tools = $ClassMethod(..#TOOLSET, "%New").%Discover().tools
	Do $$$AssertEquals(tools.%Size(), 6, "the toolset offers six tools")
	Set found = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set found = found _ $ListBuild(tool.name)
		Set name = tool.name
		Set provider = $Select(name = $Parameter(names, "RECENTACTIVITY"): "OcuTalon.Tools.RecentActivity", 1: ..#TOOLS)
		Do $$$AssertEquals(tool.provider, provider, name_" is a method of "_provider)
		If '$Data(want(name)) {
			Do $$$AssertTrue(0, name_" is not one of the six tools")
			Continue
		}
		Set upper = $ZConvert($Translate(name, "_-"), "U")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, name), $List(want(name), 4), name_" has its own step label")
		Do $$$AssertEquals($Parameter(tool.provider, "STEPLABEL"_upper), $List(want(name), 4), name_"'s label is the class parameter STEPLABEL"_upper)
		Do $$$AssertEquals($Parameter(tool.provider, "CLASSIFICATION"_upper), $List(want(name), 1), name_" is classified "_$List(want(name), 1))
		Do $$$AssertEquals($Parameter(tool.provider, "READONLY"_upper), $List(want(name), 2), name_" has READONLY "_$List(want(name), 2))
		Do $$$AssertEquals($Parameter(tool.provider, "TRUSTEDOUTPUT"_upper), $List(want(name), 3), name_" has TRUSTEDOUTPUT "_$List(want(name), 3))
		Set inputs = ..SortedKeys(tool.parameters.properties)
		Do $$$AssertEquals(inputs, $List(want(name), 5), name_" takes the inputs '"_$List(want(name), 5)_"'")
		Set required = ""
		Set at = tool.parameters.required.%GetIterator()
		While at.%GetNext(, .value) {
			Set required = required _ $Select(required = "": "", 1: ",") _ value
		}
		Do $$$AssertEquals(required, $List(want(name), 6), name_" requires '"_$List(want(name), 6)_"'")
		For input = 1:1:$Length(inputs, ",") {
			Set one = $Piece(inputs, ",", input)
			If one = "" Continue
			Do $$$AssertTrue(tool.parameters.properties.%Get(one).description '= "", name_"'s input "_one_" has a description for the model")
			For forbidden = "session", "owner", "origin" {
				Do $$$AssertNotTrue($ZConvert(one, "L") [ forbidden, name_"'s input "_one_" does not name a "_forbidden)
			}
		}
		Do $$$AssertEquals(tool.metadata."origin_class", provider, name_" says that it originates in "_provider)
	}
	Set position = 0
	While $ListNext(expected, position, name) {
		Set seen = 0
		Set at = 0
		While $ListNext(found, at, discovered) {
			If discovered = name Set seen = seen + 1
		}
		Do $$$AssertEquals(seen, 1, name_" is offered once")
	}
	Do $$$AssertEquals($ListLength(found), $ListLength(expected), "and nothing else is offered")
	Set own = $ClassMethod(..#TOOLS, "%New").%Discover().tools
	Set ownNames = ""
	Set iterator = own.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set ownNames = ownNames _ $ListBuild(tool.name)
	}
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Agent.Runners).Sorted(ownNames)), "CheckStatus,DismissIncident,ListProductions,StartWatch,StopWatch", ..#TOOLS_" offers its five methods and none of Result's")
	Set definition = ##class(%Dictionary.XDataDefinition).%OpenId(..#TOOLSET_"||Definition")
	Set xml = $Select($IsObject(definition): definition.Data.Read(32000), 1: "")
	Do $$$AssertTrue(xml '= "", "the toolset has its Definition")
	Do $$$AssertTrue(xml '[ "Requirement", "and holds no Requirement element: the class parameters are the one declaration")
	Do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%OpenId(..#TOOLSET).DependsOn, ..#TOOLS_",OcuTalon.Tools.RecentActivity", "and it depends on both tool classes")
	Do $$$AssertEquals($Parameter(..#TOOLS, "READMELINK"), "https://github.com/jbrandtmse/OcuTalon#readme", "the README link is the project's")
}

Method TestStart()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set session = ..Session("start")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(session, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders")
	Do ..AssertObject(answer, {"ok": true, "message": "The CI double started the watch.", "ref": ($Parameter(..#DOUBLE, "WATCHREF")), "outcome": "started", "production": "Orders"}, "start_watch('Orders')")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Set call = calls.%Get(0)
		Do $$$AssertEquals(call.class_"|"_call.origin_"|"_call.sessionRef_"|"_call.key, "OcuTalon.Msg.Command.StartWatch|tool|"_session_"|"_itemId_":1", "a StartWatch, origin tool, the session of the turn, the key <ItemId>:1")
		Do $$$AssertEquals(..SortedKeys(call.fields), "DisplayName,IdempotencyKey,Namespace,Origin,Production,SessionRef", "it sets those fields and no other")
		Do $$$AssertEquals(call.fields.Namespace_"|"_call.fields.Production_"|"_call.fields.DisplayName, ..#ORDERS_"|"_..#ORDERSPRODUCTION_"|Orders", "the namespace, the production and the display name of the reader")
	}
	Do $$$AssertEquals(..Rows(session).%Size(), 0, "the tool wrote no row: the owner does")
}

Method TestStop()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set session = ..Session("stop")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(session, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).StopWatch("Orders")
	Do ..AssertObject(answer, {"ok": true, "message": "The CI double stopped the watch.", "ref": ($Parameter(..#DOUBLE, "WATCHREF")), "outcome": "stopped", "production": "Orders"}, "stop_watch('Orders')")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Set call = calls.%Get(0)
		Do $$$AssertEquals(call.class_"|"_call.origin_"|"_call.sessionRef_"|"_call.key, "OcuTalon.Msg.Command.StopWatch|tool|"_session_"|"_itemId_":1", "a StopWatch, origin tool, the session of the turn, the key <ItemId>:1")
		Do $$$AssertEquals(..SortedKeys(call.fields), "IdempotencyKey,Namespace,Origin,Production,SessionRef", "it sets those fields and no other")
		Do $$$AssertEquals(call.fields.Namespace_"|"_call.fields.Production, ..#ORDERS_"|"_..#ORDERSPRODUCTION, "the namespace and the production")
	}
}

Method TestNameForms()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set session = ..Session("forms")
	Do ..Begin(session, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set count = 0
	For name = "orders", "  ORDERS ", "Orders production", "orders Production", ..#ORDERSPRODUCTION {
		Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch(name)
		Set count = count + 1
		Do $$$AssertEquals(answer.outcome_"|"_answer.production, "started|Orders", "'"_name_"' starts Orders")
	}
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders", "ocuorders")
	Set count = count + 1
	Do $$$AssertEquals(answer.outcome, "started", "the namespace argument, in any case, still finds it")
	Do $$$AssertEquals(..Calls().%Size(), count, "each of those submitted one command")
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders", "OCUTALON")
	Do $$$AssertEquals(answer.outcome, "unknown_production", "another namespace finds nothing")
	Do $$$AssertEquals(..Calls().%Size(), count, "and submits nothing")
}

Method TestUnknownName()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set session = ..Session("unknown")
	Do ..Begin(session, ##class(OcuTalon.Bridge.Ids).NewRef())
	For tool = "start", "stop" {
		Set answer = $Select(tool = "start": ##class(OcuTalon.Tools.WatchTools).StartWatch("Billing"), 1: ##class(OcuTalon.Tools.WatchTools).StopWatch("Billing"))
		Do ..AssertObject(answer, {"ok": false, "outcome": "unknown_production", "name": "Billing", "list": "Orders", "productions": [{"name": "Orders", "namespace": (..#ORDERS)}]}, tool_"_watch('Billing')")
	}
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("")
	Do $$$AssertEquals(answer.outcome_"|"_answer.name, "unknown_production|", "an empty name is unknown too")
	Do $$$AssertEquals(..Calls().%Size(), 0, "and submits nothing")
}

Method TestOnlyOrders()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Do ..SetOnlineDemo(1)
	Set session = ..Session("online")
	Do ..Begin(session, ##class(OcuTalon.Bridge.Ids).NewRef())
	For tool = "start", "stop" {
		Set answer = $Select(tool = "start": ##class(OcuTalon.Tools.WatchTools).StartWatch("Billing"), 1: ##class(OcuTalon.Tools.WatchTools).StopWatch("Billing"))
		Do ..AssertObject(answer, {"ok": false, "outcome": "only_orders", "readmeLink": "https://github.com/jbrandtmse/OcuTalon#readme"}, tool_"_watch('Billing') on the online demo")
	}
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders")
	Do $$$AssertEquals(answer.outcome, "started", "Orders still starts on the online demo")
	Do $$$AssertEquals(..Calls().%Size(), 1, "and its command is submitted")
}

Method TestDecide()
{
	Set a = {"displayName": "Orders", "namespace": "NSA", "production": "A.Orders"}
	Set b = {"displayName": "Orders", "namespace": "NSB", "production": "B.Orders"}
	Set none = []
	Set one = ..Array(a)
	Set two = ..Array(a, b)
	Set refusal = $ClassMethod(..#ANSWERS, "Decide", "Orders", one, 0, none, .match)
	Do $$$AssertEquals(refusal, "", "one match is no refusal")
	Do $$$AssertEquals($Select($IsObject(match): match.namespace, 1: "<none>"), "NSA", "and it is the match")
	Set refusal = $ClassMethod(..#ANSWERS, "Decide", "Orders", two, 0, none, .match)
	Do ..AssertObject(refusal, {"ok": false, "outcome": "ambiguous", "name": "Orders", "matches": [{"name": "Orders", "namespace": "NSA"}, {"name": "Orders", "namespace": "NSB"}]}, "two matches are ambiguous, with each one's name and namespace")
	Do $$$AssertEquals(match, "", "with no match")
	Set refusal = $ClassMethod(..#ANSWERS, "Decide", "Orders", two, 1, none, .match)
	Do $$$AssertEquals(refusal.outcome, "ambiguous", "also on the online demo")
	Set refusal = $ClassMethod(..#ANSWERS, "Decide", "Billing", none, 1, none, .match)
	Do ..AssertObject(refusal, {"ok": false, "outcome": "only_orders", "readmeLink": "https://github.com/jbrandtmse/OcuTalon#readme"}, "no match on the online demo is only_orders")
	Set refusal = $ClassMethod(..#ANSWERS, "Decide", "Billing", none, 0, two, .match)
	Do ..AssertObject(refusal, {"ok": false, "outcome": "unknown_production", "name": "Billing", "list": "Orders", "productions": [{"name": "Orders", "namespace": "NSA"}, {"name": "Orders", "namespace": "NSB"}]}, "no match is unknown_production, with the list and the productions")
}

Method TestJoined()
{
	Do $$$AssertEquals($ClassMethod(..#ANSWERS, "Joined", []), "no productions", "no name")
	Do $$$AssertEquals($ClassMethod(..#ANSWERS, "Joined", ..Named("Orders")), "Orders", "one name")
	Do $$$AssertEquals($ClassMethod(..#ANSWERS, "Joined", ..Named("Orders,Billing")), "Orders and Billing", "two names are joined with and")
	Do $$$AssertEquals($ClassMethod(..#ANSWERS, "Joined", ..Named("Orders,Billing,Stock")), "Orders, Billing and Stock", "three are joined with a comma and, before the last, and")
	Do $$$AssertEquals($ClassMethod(..#ANSWERS, "Joined", ..Named("Orders,Billing,Stock,Mail")), "Orders, Billing, Stock and Mail", "and four")
	Do $$$AssertEquals($ClassMethod(..#ANSWERS, "Joined", ..Named("Orders,Orders")), "Orders", "a name that two namespaces share is said once")
}

Method TestListProductions()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set session = ..Session("list")
	Do ..Begin(session, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).ListProductions()
	Do ..AssertObject(answer, {"ok": true, "list": "Orders", "productions": [{"name": "Orders", "namespace": (..#ORDERS)}]}, "list_productions")
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set answer = ##class(OcuTalon.Tools.WatchTools).ListProductions()
	Do $$$AssertEquals(answer.list, "Orders", "it needs no session: it reads and starts nothing")
	Do ..GrantRole(..#HOMEDATA)
	Set answer = ##class(OcuTalon.Tools.WatchTools).ListProductions()
	Do $$$AssertEquals(answer.productions.%Size(), 2, "with OCUTALON readable the list holds two productions: "_answer.%ToJSON())
	Do $$$AssertTrue((answer.list = "Orders and OcuTalon.Production") || (answer.list [ " and "), "joined with and: "_answer.list)
}

Method TestNoSession()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set owner = ..Session("nosession")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(owner, "open", "Zz.Production", "2030-01-01T10:00:00Z")
	Set cases = $ListBuild(
		$ListBuild("no context", 0, "", ""),
		$ListBuild("the owner instance", 1, "instance", itemId),
		$ListBuild("the owner eval", 1, "eval", itemId),
		$ListBuild("an empty owner", 1, "", itemId),
		$ListBuild("an owner that is not a Ref", 1, "zzOwnerTooShort", itemId),
		$ListBuild("an empty ItemId", 1, owner, ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ##class(OcuTalon.Bridge.Context).End()
		If $List(case, 2) Do ..Begin($List(case, 3), $List(case, 4))
		For name = "Orders", "Billing" {
			Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch(name)
			Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, $List(case, 1)_": start_watch('"_name_"') answers NOSESSION")
			Set answer = ##class(OcuTalon.Tools.WatchTools).StopWatch(name)
			Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, $List(case, 1)_": stop_watch('"_name_"') answers NOSESSION")
		}
		Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, $List(case, 1)_": dismiss_incident() answers NOSESSION")
		If $List(case, 2) Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""zz"":1}")
		Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, $List(case, 1)_": check_status() answers NOSESSION")
		If $List(case, 2) Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""zz"":1}", $List(case, 1)_": and leaves HostData as it was")
		Do $$$AssertEquals(..Calls().%Size(), 0, $List(case, 1)_": the double recorded nothing")
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders")
	Do $$$AssertEquals(answer.ok, 1, "control: with a session's turn the same call is answered by the double")
	Do $$$AssertEquals(..Calls().%Size(), 1, "and the double recorded it")
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do $$$AssertEquals(answer.ok, 1, "and so is dismiss_incident")
	Do $$$AssertEquals(..Calls().%Size(), 2, "which the double recorded too")
}

/// check_status (matrix "check_status"): session A has a passed, a failed and a not-run production row, and a row of another Kind between them; session B
/// has a row. The production rows are due a day ahead, so that no real Tick runs them. The answer holds A's three production rows by ID with the time in the instance zone, HostData holds them with the UTC time, and nothing is
/// submitted.
Method TestCheckStatus()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("checks-a")
	Set b = ..Session("checks-b")
	Set passedAt = "2030-01-01T10:00:00Z"
	Set failedAt = "2030-01-01T10:01:00Z"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.Passed", {"DisplayName": "Orders", "Result": "passed", "LastRunAt": (passedAt), "NextDueAt": (..Ahead())})
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.Other", {"Kind": "zzother", "DisplayName": "Other", "Result": "failed", "Finding": "Other kind", "LastRunAt": (passedAt)})
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.Failed", {"DisplayName": "Billing", "Result": "failed", "Finding": "3 new failures", "LastRunAt": (failedAt), "NextDueAt": (..Ahead())})
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.NotRun", {"DisplayName": "Shipping", "NextDueAt": (..Ahead())})
	Do ##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", "Zz.B", {"DisplayName": "Belongs to B", "Result": "failed", "Finding": "B's failure", "LastRunAt": (passedAt), "NextDueAt": (..Ahead())})
	Do ..Begin(a, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Set seen = [{"result": "passed", "entry": "Orders production", "finding": "", "checked": (##class(OcuTalon.Data.Time).ForMessage(passedAt))}, {"result": "failed", "entry": "Billing production", "finding": "3 new failures", "checked": (##class(OcuTalon.Data.Time).ForMessage(failedAt))}, {"result": "", "entry": "Shipping production", "finding": "", "checked": ""}]
	Do ..AssertObject(answer, {"ok": true, "checks": (seen)}, "check_status()")
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).ForMessage(passedAt) '= "", "the time that the model reads is not empty")
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).ForMessage(passedAt) '[ "2030-01-01T", "and is not the UTC stamp")
	Set kept = [{"result": "passed", "entry": "Orders production", "finding": "", "checkedAt": (passedAt)}, {"result": "failed", "entry": "Billing production", "finding": "3 new failures", "checkedAt": (failedAt)}, {"result": "", "entry": "Shipping production", "finding": "", "checkedAt": ""}]
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, {"checks": (kept)}.%ToJSON(), "HostData holds the rows of A's production watches, with the UTC time")
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
	Do $$$AssertEquals(..Rows(a).%Size(), 4, "and no row is written")
}

/// check_status keeps HostData (matrix "HostData kept"): a JSON object keeps its other members, anything else becomes {"checks": ...}, and a second call
/// replaces checks. A watches nothing at first.
Method TestCheckStatusHostData()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("hostdata")
	Do ..Begin(a, ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "", "HostData starts empty")
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do ..AssertObject(answer, {"ok": true, "checks": []}, "check_status() with nothing watched")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""checks"":[]}", "an empty HostData becomes checks alone, also for no results")
	Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""zz"":1}")
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do ..AssertObject(answer, {"ok": true, "checks": []}, "check_status() with a JSON object HostData")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""zz"":1,""checks"":[]}", "a JSON object keeps its other members")
	Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""zz"":1,""checks"":[""old""]}")
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do ..AssertObject(answer, {"ok": true, "checks": []}, "check_status() with an earlier checks")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""zz"":1,""checks"":[]}", "and an earlier checks is replaced")
	Set others = $ListBuild("not json", "[1]", "7", """text""")
	Set position = 0
	While $ListNext(others, position, text) {
		Do ##class(OcuTalon.Bridge.Context).Put("HostData", text)
		Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
		Do ..AssertObject(answer, {"ok": true, "checks": []}, "check_status() with HostData "_text)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""checks"":[]}", "HostData "_text_" becomes checks alone")
	}
	Set passedAt = "2030-01-01T10:00:00Z"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.Passed", {"DisplayName": "Orders", "Result": "passed", "LastRunAt": (passedAt), "NextDueAt": (..Ahead())})
	Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""checks"":[]}")
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do ..AssertObject(answer, {"ok": true, "checks": [{"result": "passed", "entry": "Orders production", "finding": "", "checked": (##class(OcuTalon.Data.Time).ForMessage(passedAt))}]}, "a second call after a watch exists answers the row")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, {"checks": [{"result": "passed", "entry": "Orders production", "finding": "", "checkedAt": (passedAt)}]}.%ToJSON(), "and replaces checks")
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
}

/// QA (Story 5.7; no production): the description that the model reads for check_status (the doc of CheckStatus) says when to call it, that not_checked
/// means the last run could not check and an empty result that the check has not run yet, and that OcuTalon shows the results itself, so the model lists
/// none and says no all-clear.
Method TestCheckStatusDescription()
{
	Set tools = $ClassMethod(..#TOOLSET, "%New").%Discover().tools
	Set description = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		#; The doc's line breaks are spaces to the model.
		If tool.name = "check_status" Set description = $Replace($Replace(tool.description, $Char(13), ""), $Char(10), " ")
	}
	Do $$$AssertTrue(description '= "", "check_status has a description for the model")
	Do $$$AssertTrue(description [ "when the user asks whether everything is fine, OK or working", "it says when to call it")
	Do $$$AssertTrue(description [ "not_checked when the last run could not check", "not_checked means that the last run could not check")
	Do $$$AssertTrue(description [ "empty when the check has not run yet", "an empty result means that the check has not run yet")
	Do $$$AssertTrue(description [ "OcuTalon shows the results itself", "OcuTalon shows the results itself")
	Do $$$AssertTrue(description [ "do not list them and do not say that everything passed", "so the model lists none and says no all-clear")
}

/// check_status not read (matrix "Refused"): the owners instance and eval and an empty one cannot be read, so CheckResults answers CHECKSNOTREAD with no
/// results. TestNoSession covers the calls that are not a session's turn, with HostData untouched.
Method TestCheckStatusNotRead()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set owners = $ListBuild("instance", "eval", "")
	Set position = 0
	While $ListNext(owners, position, owner) {
		Set refusal = ##class(OcuTalon.Tools.WatchAnswers).CheckResults(owner, .results)
		Do ..AssertObject(refusal, {"ok": false, "message": ($Parameter(..#ANSWERS, "CHECKSNOTREAD"))}, "CheckResults('"_owner_"')")
		Do $$$AssertEquals(results.%ToJSON(), "[]", "'"_owner_"' leaves no results")
	}
	Set a = ..Session("notread")
	Set refusal = ##class(OcuTalon.Tools.WatchAnswers).CheckResults(a, .results)
	Do $$$AssertEquals(refusal, "", "a session with no watch is read")
	Do $$$AssertEquals(results.%ToJSON(), "[]", "and has no results")
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
}

Method TestSubmitFails()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set owner = ..Session("fails")
	Do ..Seed(owner, "open", "Zz.Production", "2030-01-01T10:00:00Z")
	Set ^OcuTalonTest("CommandsDouble", "fail") = 1
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set verbs("start_watch") = "OcuTalon.Msg.Command.StartWatch"
	Set verbs("stop_watch") = "OcuTalon.Msg.Command.StopWatch"
	Set verbs("dismiss_incident") = "OcuTalon.Msg.Command.Dismiss"
	For tool = "start_watch", "stop_watch", "dismiss_incident" {
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answer = ..CallTool(tool)
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOTSENT"))}, tool_" answers NOTSENT")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild(verbs(tool), "The CI double was set to fail")), 1, tool_" logged one warning of Run that names "_verbs(tool)_" and the status")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, "", ..#CALL), 1, "and no other warning of "_..#CALL)
	}
	Do $$$AssertEquals(..Calls().%Size(), 3, "the double still recorded the three commands")
}

Method TestSubmitEmpty()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set owner = ..Session("empty")
	Do ..Seed(owner, "open", "Zz.Production", "2030-01-01T10:00:00Z")
	Set ^OcuTalonTest("CommandsDouble", "empty") = 1
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	For tool = "start_watch", "stop_watch", "dismiss_incident" {
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answer = ..CallTool(tool)
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOTSENT"))}, tool_" answers NOTSENT when the answer is no CommandResult")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild("not an OcuTalon.Msg.CommandResult")), 1, tool_" logged one warning of Run that says the answer is no CommandResult")
	}
}

Method TestSubmitKeepsTheJobSession()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set had = $Data(%Ensemble("SessionId"), was)
	Set session = 900000000 + $Random(99999999)
	Try {
		Set owner = ..Session("jobsession")
		Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
		Set %Ensemble("SessionId") = session
		For tool = "start_watch", "stop_watch" {
			Set answer = ..CallTool(tool)
			Do $$$AssertEquals(answer.ok, 1, tool_" is answered by the double")
			Do $$$AssertEquals($Get(%Ensemble("SessionId")), session, tool_" leaves the job's session as it was")
		}
		Set ^OcuTalonTest("CommandsDouble", "fail") = 1
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		For tool = "start_watch", "stop_watch" {
			Set answer = ..CallTool(tool)
			Do $$$AssertEquals(answer.ok, 0, "control: the failed "_tool_" answers ok false")
			Do $$$AssertEquals($Get(%Ensemble("SessionId")), session, "a failed "_tool_" leaves the job's session as it was too")
		}
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass = ? AND SourceMethod = 'Run'", mark, ..#CALL)
		Set sessions = ""
		While rows.%Next() {
			Set sessions = sessions _ $ListBuild(rows.%GetData(1))
		}
		Do $$$AssertEquals($ListToString(sessions), session_","_session, "and the two warnings of Run are logged in the job's session")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test ran to its end")
	}
	If had # 2 {
		Set %Ensemble("SessionId") = was
	} Else {
		Kill %Ensemble("SessionId")
	}
}

Method TestRefusal()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set owner = ..Session("refusal")
	Set ref = ..Seed(owner, "open", "Zz.Production", "2030-01-01T10:00:00Z")
	Set ^OcuTalonTest("CommandsDouble", "refuse", "Dismiss") = "The owner says no to the dismissal."
	Set ^OcuTalonTest("CommandsDouble", "refuse", "StartWatch") = "The owner says no."
	Set ^OcuTalonTest("CommandsDouble", "refuse", "StopWatch") = "The owner says no again."
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders")
	Do ..AssertObject(answer, {"ok": false, "message": "The owner says no.", "outcome": "refused", "production": "Orders"}, "the owner's refusal of a start")
	Set answer = ##class(OcuTalon.Tools.WatchTools).StopWatch("Orders")
	Do ..AssertObject(answer, {"ok": false, "message": "The owner says no again.", "outcome": "refused", "production": "Orders"}, "and of a stop")
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": false, "message": "The owner says no to the dismissal.", "outcome": "refused", "ref": (ref), "production": "Zz.Production"}, "and of a dismissal, with no state")
}

Method TestDismissOne()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("dismissOne")
	Set b = ..Session("dismissOneB")
	Set open = ..Seed(a, "open", "Zz.Production", "2030-01-01T10:00:00Z")
	Do ..Seed(a, "closed", "Zz.Production", "2030-01-01T11:00:00Z")
	Do ..Seed(a, "open", "Zz.Production", "", {"Production": "Zz.Unnoticed"})
	Do ..Seed(b, "open", "Zz.Production", "2030-01-01T10:30:00Z")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(a, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": true, "message": "The CI double dismissed the incident.", "ref": (open), "outcome": "closed", "production": "Zz.Production", "state": "closed", "openVariant": ""}, "dismiss_incident() with one open incident")
	Do ..AssertDismissals(a, itemId, open)
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("  ")
	Do $$$AssertEquals(answer.ok_"|"_answer.ref, "1|"_open, "a production of white space alone is not given: the one candidate is dismissed")
	Do ..AssertDismissals(a, itemId, open, 2)
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble", "calls")
	Set r = ..Session("dismissResolved")
	Do ..Watching(r, "Zz.Production")
	Set resolved = ..Seed(r, "resolved", "Zz.Production", "2030-01-01T10:00:00Z", {"OpenVariant": ""})
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(r, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": true, "message": "The CI double dismissed the incident.", "ref": (resolved), "outcome": "closed", "production": "Zz Zz.Production", "state": "closed", "openVariant": ""}, "a resolved incident is submitted too, with the display name of the session's watch")
	Do ..AssertDismissals(r, itemId, resolved)
}

Method TestDismissPicks()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("picks")
	Do ..Watching(a, "Zz.Orders")
	Do ..Watching(a, "Zz.Billing")
	Set orders = ..Seed(a, "open", "Zz.Orders", "2030-01-01T10:00:00Z")
	Set billing = ..Seed(a, "open", "Zz.Billing", "2030-01-01T11:00:00Z")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(a, itemId)
	Set both = [(..Entry(orders, "Zz Zz.Orders")), (..Entry(billing, "Zz Zz.Billing"))]
	Set n = 0
	For name = "Zz.Billing", "Zz Zz.Billing" {
		Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident(name)
		Set n = n + 1
		Do $$$AssertEquals(answer.ok_"|"_answer.ref_"|"_answer.production, "1|"_billing_"|Zz Zz.Billing", "production '"_name_"' dismisses the Billing incident")
		Do ..AssertDismissals(a, itemId, billing, n)
	}
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": false, "outcome": "ambiguous", "incidents": (both)}, "two candidates and no argument are ambiguous, in NoticedAt order")
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("Zz")
	Do $$$AssertEquals(answer.outcome, "unknown_incident", "a name that neither production has is unknown_incident")
	Do $$$AssertEquals(..Calls().%Size(), n, "and nothing more was submitted")
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("", billing)
	Do $$$AssertEquals(answer.ok_"|"_answer.ref, "1|"_billing, "by ref: the ref picks the second one")
	Set n = n + 1
	Do ..AssertDismissals(a, itemId, billing, n)
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("Zz.Orders", billing)
	Do $$$AssertEquals(answer.ok_"|"_answer.ref, "1|"_billing, "the ref wins over the production")
	Set n = n + 1
	Do ..AssertDismissals(a, itemId, billing, n)
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble", "calls")
	Set p = ..Session("picksSame")
	Set first = ..Seed(p, "open", "Zz.Orders", "2030-01-01T10:00:00Z")
	Set second = ..Seed(p, "resolved", "Zz.Orders", "2030-01-01T11:00:00Z")
	Do ..Begin(p, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("Zz.Orders")
	Do ..AssertObject(answer, {"ok": false, "outcome": "ambiguous", "incidents": [(..Entry(first, "Zz.Orders")), (..Entry(second, "Zz.Orders", "resolved"))]}, "a production that both candidates match is ambiguous")
	Do $$$AssertEquals(..Calls().%Size(), 0, "and nothing is submitted")
}

Method TestDismissUnknown()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("unknownIncident")
	Set b = ..Session("unknownIncidentB")
	Set open = ..Seed(a, "open", "Zz.Production", "2030-01-01T10:00:00Z")
	Set closed = ..Seed(a, "closed", "Zz.Production", "2030-01-01T11:00:00Z")
	Set waiting = ..Seed(a, "awaiting_approval", "Zz.Production", "2030-01-01T12:00:00Z")
	Set unnoticed = ..Seed(a, "open", "Zz.Production", "")
	Set other = ..Seed(b, "open", "Zz.Production", "2030-01-01T10:30:00Z")
	Do ..Begin(a, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set expected = {"ok": false, "outcome": "unknown_incident", "incidents": [(..Entry(open, "Zz.Production"))], "others": [(..Entry(waiting, "Zz.Production", "awaiting_approval"))]}
	For ref = other, closed, waiting, unnoticed, "zzMadeUpRef0000000001" {
		Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("", ref)
		Do ..AssertObject(answer, expected, "dismiss_incident(incident '"_ref_"')")
	}
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("Zz.Nothing")
	Do ..AssertObject(answer, expected, "dismiss_incident('Zz.Nothing'): a production that no candidate has")
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
}

Method TestDismissNone()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("noIncident")
	Set waiting = ..Seed(a, "awaiting_approval", "Zz.Production", "2030-01-01T10:00:00Z")
	Set fixing = ..Seed(a, "fixing", "Zz.Production", "2030-01-01T11:00:00Z")
	Do ..Seed(a, "closed", "Zz.Production", "2030-01-01T12:00:00Z")
	Do ..Begin(a, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": false, "outcome": "no_incident", "others": [(..Entry(waiting, "Zz.Production", "awaiting_approval")), (..Entry(fixing, "Zz.Production", "fixing"))]}, "only a waiting and a fixing incident: no_incident, with both as others")
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident("", waiting)
	Do $$$AssertEquals(answer.outcome, "no_incident", "a busy incident's ref does not make it a candidate")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set empty = ..Session("noIncidentAtAll")
	Do ..Begin(empty, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": false, "outcome": "no_incident", "others": []}, "no incident at all: no_incident with no others")
	Do $$$AssertEquals(..Calls().%Size(), 0, "nothing is submitted")
}

Method TestDismissInstance()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Do ..SetOnlineDemo(0)
	Set a = ..Session("instanceA")
	Set c = ..Session("instanceC")
	Set production = "Zz.Instance"_..Number
	Do ..Watching(a, production)
	Set ref = ..Seed("instance", "open", production, "2030-01-01T10:00:00Z")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(a, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": true, "message": "The CI double dismissed the incident.", "ref": (ref), "outcome": "closed", "production": ("Zz "_production), "state": "closed", "openVariant": ""}, "a local install: the instance incident of a production that A watches")
	Do ..AssertDismissals(a, itemId, ref)
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble", "calls")
	Do ..Begin(c, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Do ..AssertObject(answer, {"ok": false, "outcome": "no_incident", "others": []}, "a session that watches nothing: no_incident")
	Do $$$AssertEquals(..Calls().%Size(), 0, "and nothing is submitted")
}

Method TestIncidentsNotRead()
{
	// QA (Story 5.9): the failed-read answer, reached through the helper with the owners that Ownership refuses to read for (no seam, no contended change).
	Set expected = {"ok": false, "message": ($Parameter(..#ANSWERS, "INCIDENTSNOTREAD"))}
	Do $$$AssertEquals(expected.message, "The incidents of this conversation could not be read, so nothing was dismissed.", "the text of the failed-read answer")
	For owner = "instance", "eval", "" {
		Set answer = $ClassMethod(..#ANSWERS, "ResolveIncident", "", "", owner, .match)
		Do ..AssertObject(answer, expected, "ResolveIncident for the owner '"_owner_"' cannot read the incidents, so it refuses")
		Do $$$AssertEquals(match, "", "and offers nothing to submit")
	}
}

Method TestDismissedData()
{
	// QA (Story 5.9): the answer of a Dismiss that the owner answered, with each shape of the owner's Data (the guarded branch of Dismissed).
	Set entry = {"ref": "zzRef", "production": "Zz.P"}
	Set cases = $ListBuild(
		$ListBuild("a state and a variant", "{""state"":""closed"",""openVariant"":""fix""}", "closed", "fix"),
		$ListBuild("a state and no variant", "{""state"":""closed""}", "closed", ""),
		$ListBuild("a state and a variant that is not a string", "{""state"":""closed"",""openVariant"":7}", "closed", ""),
		$ListBuild("a state that is not a string", "{""state"":5,""openVariant"":""fix""}", "", ""),
		$ListBuild("no state", "{""openVariant"":""fix""}", "", ""),
		$ListBuild("an empty object", "{}", "", ""),
		$ListBuild("an array of numbers", "[5]", "", ""),
		$ListBuild("an array whose first element is a string", "[""closed""]", "", ""),
		$ListBuild("a string", """closed""", "", ""),
		$ListBuild("text that is not JSON", "not json", "", ""),
		$ListBuild("no Data", "", "", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = 1
		Set result.Outcome = "closed"
		Set result.Message = "Dismissed."
		Set result.Ref = "zzOtherRef"
		Set result.Data = $List(case, 2)
		Set expected = {"ok": true, "message": "Dismissed.", "ref": "zzRef", "outcome": "closed", "production": "Zz.P"}
		If $List(case, 3) '= "" {
			Set expected.state = $List(case, 3)
			Set expected.openVariant = $List(case, 4)
		}
		Set answer = ""
		Try {
			Set answer = $ClassMethod(..#ANSWERS, "Dismissed", result, entry)
		} Catch exception {
			Do $$$AssertTrue(0, $List(case, 1)_": Dismissed raised "_exception.DisplayString())
		}
		If $IsObject(answer) Do ..AssertObject(answer, expected, "Data is "_$List(case, 1))
	}
}

Method TestKeys()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set owner = ..Session("keys")
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Do ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders")
	Do ##class(OcuTalon.Tools.WatchTools).StartWatch("Billing")
	Do ##class(OcuTalon.Tools.WatchTools).StopWatch("Orders")
	Do ##class(OcuTalon.Tools.WatchTools).ListProductions()
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "the double recorded the two commands that were submitted")
	If calls.%Size() = 2 {
		Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(1).key, itemId_":1|"_itemId_":2", "numbered from 1: a refused call and a list take no position")
	}
}

Method TestResolveStop()
{
	If '..Ready() Quit
	If '..UseDouble() Quit
	Set a = ..Session("resolveA")
	Set b = ..Session("resolveB")
	Set created = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..UnlistedWatch(a, "ZZNS1", "Zz.Orders", "Zz Orders")
	Do ##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS3", "Zz.Other", {"DisplayName": "Zz Other", "AskedBy": "zzfixture", "CreatedAt": (created)})
	Do $$$AssertEquals($ClassMethod(..#READER, "Find", "Zz Orders").%Size(), 0, "control: the reader lists no production named Zz Orders")
	Set refusal = $ClassMethod(..#ANSWERS, "ResolveStop", "zz orders production", "", a, .match)
	Do $$$AssertEquals(refusal, "", "an own watch that the reader does not list is resolved")
	Do $$$AssertEquals($Select($IsObject(match): match.namespace_"|"_match.production_"|"_match.displayName, 1: "<none>"), "ZZNS1|Zz.Orders|Zz Orders", "to the row's namespace, production and display name")
	Set refusal = $ClassMethod(..#ANSWERS, "ResolveStop", "Zz Other", "", a, .match)
	Do $$$AssertEquals($Select($IsObject(refusal): refusal.outcome, 1: "<none>"), "unknown_production", "another session's watch is not an own match: the reader's path refuses it")
	Set refusal = $ClassMethod(..#ANSWERS, "ResolveStop", "Orders", "", a, .match)
	Do $$$AssertEquals(refusal, "", "a name that no own row matches is resolved by the reader, as before")
	Do $$$AssertEquals(match.namespace_"|"_match.production, ..#ORDERS_"|"_..#ORDERSPRODUCTION, "to Orders")
	Do ..UnlistedWatch(a, "ZZNS2", "Zz.Orders", "Zz Orders")
	Set refusal = $ClassMethod(..#ANSWERS, "ResolveStop", "Zz Orders", "", a, .match)
	Do ..AssertObject(refusal, {"ok": false, "outcome": "ambiguous", "name": "Zz Orders", "matches": [{"name": "Zz Orders", "namespace": "ZZNS1"}, {"name": "Zz Orders", "namespace": "ZZNS2"}]}, "two own matches are ambiguous, with each one's name and namespace")
	Set refusal = $ClassMethod(..#ANSWERS, "ResolveStop", "Zz Orders", "zzns2", a, .match)
	Do $$$AssertEquals(refusal_"|"_match.namespace, "|ZZNS2", "the namespace argument picks one")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(a, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).StopWatch("Zz Orders", "ZZNS1")
	Do ..AssertObject(answer, {"ok": true, "message": "The CI double stopped the watch.", "ref": ($Parameter(..#DOUBLE, "WATCHREF")), "outcome": "stopped", "production": "Zz Orders"}, "stop_watch of an own watch that the reader does not list")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Set call = calls.%Get(0)
		Do $$$AssertEquals(call.class_"|"_call.sessionRef_"|"_call.fields.Namespace_"|"_call.fields.Production, "OcuTalon.Msg.Command.StopWatch|"_a_"|ZZNS1|Zz.Orders", "a StopWatch of the session for the own row's namespace and production")
	}
	Set answer = ##class(OcuTalon.Tools.WatchTools).StopWatch("Zz Orders")
	Do $$$AssertEquals(answer.outcome, "ambiguous", "without the namespace the two own rows are ambiguous")
	Do $$$AssertEquals(..Calls().%Size(), 1, "and nothing more is submitted")
}

Method TestStopWatchOfAnUnlistedProduction()
{
	If '..Ready() Quit
	If '..UseReal() Quit
	Set a = ..Session("realstop")
	Set ref = ..Watch(a)
	Do $$$AssertEquals(..Rows(a).%Size(), 1, "session A watches Orders")
	Do ..RevokeRole(..#ORDERSDATA)
	Do $$$AssertEquals($ClassMethod(..#READER, "Find", "Orders").%Size(), 0, "the service role cannot read Orders any more, so the reader no longer lists it")
	Do ..Begin(a, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ##class(OcuTalon.Tools.WatchTools).StopWatch("Orders")
	Do ..AssertObject(answer, {"ok": true, "message": ($Parameter("OcuTalon.Watch.Ops", "MESSAGESTOPPED")), "ref": (ref), "outcome": "stopped", "production": "Orders"}, "stop_watch('Orders') through the real CommandsIn and WatchOps")
	Do $$$AssertEquals(..Rows(a).%Size(), 0, "A's row is gone")
}

/// An own watch of the session on a production that no reader lists: the row, made now.
Method UnlistedWatch(session As %String, namespace As %String, production As %String, displayName As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, namespace, production, {"DisplayName": (displayName), "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// --- helpers ---
/// An incident of the owner on ZZNS: noticed at the given time ("" for one that is not noticed), in the state, with the fields set after the defaults. Its
/// Ref is kept for the clean-up.
Method Seed(owner As %String, state As %String, production As %String, noticedAt As %String, fields As %DynamicObject = "") As %String [ Private ]
{
	If '$IsObject(fields) Set fields = {}
	Do fields.%Set("State", state)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, noticedAt, "ZZNS", production, fields)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A watch of the session on ZZNS and the production, with the display name "Zz "_production.
Method Watching(session As %String, production As %String) [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, {"AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

/// The entry of an incident that Seed made, as the answers carry it: the fixture's first time, count and variant.
ClassMethod Entry(ref As %String, production As %String, state As %String = "open", variant As %String = "fix") As %DynamicObject [ Private ]
{
	Quit {"ref": (ref), "production": (production), "state": (state), "openVariant": (variant), "since": (##class(OcuTalon.Data.Time).ForMessage("2030-01-01T09:00:00Z")), "count": 3}
}

/// Asserts that the double's last command is the nth Dismiss: origin tool, the session of the turn, the key <ItemId>:<n> and the incident's Ref, and no other
/// field than the common ones; and that the double recorded n commands in all.
Method AssertDismissals(session As %String, itemId As %String, ref As %String, n As %Integer = 1) [ Private ]
{
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), n, "the double recorded "_n_" command(s)")
	If calls.%Size() '= n Quit
	Set call = calls.%Get(n - 1)
	Do $$$AssertEquals(call.class_"|"_call.origin_"|"_call.sessionRef_"|"_call.key, "OcuTalon.Msg.Command.Dismiss|tool|"_session_"|"_itemId_":"_n, "a Dismiss, origin tool, the session of the turn, the key <ItemId>:"_n)
	Do $$$AssertEquals(..SortedKeys(call.fields), "IdempotencyKey,IncidentRef,Origin,SessionRef", "it sets those fields and no other")
	Do $$$AssertEquals(call.fields.IncidentRef, ref, "for the incident "_ref)
}

/// Calls the tool (by its name) in process with a name that Orders matches (dismiss_incident with no argument), and gives its answer.
ClassMethod CallTool(tool As %String) As %DynamicObject [ Private ]
{
	If tool = "start_watch" Quit ##class(OcuTalon.Tools.WatchTools).StartWatch("Orders")
	If tool = "dismiss_incident" Quit ##class(OcuTalon.Tools.WatchTools).DismissIncident()
	Quit ##class(OcuTalon.Tools.WatchTools).StopWatch("Orders")
}

/// A dynamic array of the entries.
ClassMethod Array(first As %DynamicObject, second As %DynamicObject = "") As %DynamicArray [ Private ]
{
	Set array = [(first)]
	If $IsObject(second) Do array.%Push(second)
	Quit array
}

/// A dynamic array of {"name", "namespace"} for the comma-separated names, each in a namespace of its own, for TestJoined.
ClassMethod Named(list As %String) As %DynamicArray [ Private ]
{
	Set array = []
	For i = 1:1:$Length(list, ",") {
		Do array.%Push({"name": ($Piece(list, ",", i)), "namespace": ("NS"_i)})
	}
	Quit array
}

}
