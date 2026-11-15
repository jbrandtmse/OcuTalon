Include Ensemble

/// Paging over the running production (Story 23.4; AD-5, AD-14, AD-15, AD-18, AD-19). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (the production's jobs hold the
/// code), with demo mode on, against the CI mock and its dummy token: they extend Test.Watch.Case and drive the Telegram items through Test.Channel.TelegramPageFixture.
///   - TestManagedAlerts (Task 0 a): an Ens.Alert item (Ens.Alerting.AlertManager) and AlertOnError 1 on OrdersFromPartner, added to the saved Orders definition and applied; three orders
///     are broken; the Ens_Alerting.ManagedAlert rows and their timing are printed; removing both leaves the definition and the job list as they were;
///   - TestPageReachesTelegram (Task 0 b): a real incident's notice, through IncidentManager, Notify and TelegramOut, reaches the mock for the paired session's chat;
///   - TestEscalationAsk (Task 0 c): Core.Commands.Submit of a SetReminder of Kind escalation, origin system, answers not_built, and how long it takes;
///   - TestHandledCopies (Task 0 d): the log lines that WebChatOut and SimPhoneOut write for a page copy that has a bare Delivery row, when a handled notification follows;
///   - TestRealBreakPagesTelegram (AC6, AC12, AC13): a real break of OCUORDERS pages the on-call user's paired Telegram chat through the real IncidentManager,
///     Notify and TelegramOut; a fixture Escalation pages the backup once; Got it pressed from another chat, then from the paired chat (the page is acknowledged on telegram and the message is
///     edited in place), then again, and an AckPage over the web channel for the backup's page edits the backup's Telegram copy; the paged people, the chat ids and the display names are in no message of the page, no audit entry, no log line, no live event and no /state payload;
///   - TestSessionBreakNeverPages (DW-1396): with another on-call user and backup set, a break tagged with a session's trace Ref is that session's incident and pages nobody;
///   - TestManagedAlertsBesidePaging (AC8): with an AlertManager fixture in OCUORDERS, a break pages the on-call user, Managed Alerts hold the failures, and no setting of any item changed;
///   - TestSettingsSaysPagesBuilt (AC10): over real HTTP, as an admin, GET /api/v1/settings has pagesBuilt true.
/// Measured figures are printed as SKIP lines (a status 2 never fails a class).
Class OcuTalon.Test.Watch.PagingLive Extends OcuTalon.Test.Watch.Case [ DependsOn = (OcuTalon.Test.Watch.OrdersDefinition, OcuTalon.Test.Watch.SettingHistory, OcuTalon.Test.Watch.Rollback, OcuTalon.Test.Channel.TelegramPageFixture) ]
{

Parameter DEFINITION = "OcuTalon.Test.Watch.OrdersDefinition";

/// The failing item of the demo failures.
Parameter FAILING = {##class(OcuTalon.Test.Watch.OrdersDefinition).#ITEM};

/// The item name of the AlertManager and the host setting that sends it an alert.
Parameter ALERTITEM = "Ens.Alert";

Parameter ALERTSETTING = "AlertOnError";

/// The Notification Manager item and the production setting that names it, which the AlertManager needs (measured).
Parameter NOTIFYITEM = "Ens.Alerting.NotificationManager";

Parameter NOTIFYSETTING = "AlertNotificationManager";

/// The fixture chat of the paired session (the first of the page fixtures' chat range).
Parameter CHAT = "84017734130";

/// The backup's chat, and a chat that is paired with no session (the fixture chats of the page fixtures).
Parameter CHATB = "84017734131";

Parameter CHATX = "84017734132";

/// The display names of the three chats.
Parameter NAMEA = "Zz Pager";

Parameter NAMEB = "Zz Backup";

Parameter NAMEX = "Zz Other";

/// The longest, in seconds, to wait for a managed alert.
Parameter WAITALERT = 30;

/// The fixture admin of TestSettingsSaysPagesBuilt, and the web port of the instance.
Parameter ADMIN = "ZzPagingAdmin";

Parameter PORT = 52773;

/// The longest, in seconds, to wait for a page, a message of the mock or an acknowledgement.
Parameter WAITPAGE = 40;

/// 1 while the alerting fixture is in the saved Orders definition.
Property AlertSet As %Boolean [ InitialExpression = 0 ];

/// What Test.Channel.TelegramPageFixture.Start saved, for Finish; "" when Telegram was not started.
Property Saved As %String(MAXLEN = "");

/// The chat that the next fixture session is paired with ("" for none).
Property PairChat As %String;

/// The first ManagedAlert id of the test's own rows.
Property AlertFloor As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Watch.Paging).SaveKeys()
	Quit ##super()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..AlertOff())
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..TelegramOff())
	Do ##class(OcuTalon.Test.Watch.Paging).PutKeysBack()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ..DropAdmin()
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set sc = ..AlertOff()
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..TelegramOff())
	Do ##class(OcuTalon.Test.Watch.Paging).PutKeysBack()
	Kill ^OcuTalonTest("WatchPaging", "saved")
	Do ..DropAdmin()
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// Puts the Orders definition back (no alerting fixture), applies it when the fixture was there, and deletes the managed alerts that the test made.
Method AlertOff() As %Status [ Private ]
{
	Set sc = $$$OK
	If ..AlertSet {
		Set ..AlertSet = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Watch.SettingHistory).DropItems())
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..PutNotifier(0))
		Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#DEFINITION, "Put", 0, "", "", ..#ALERTSETTING))
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..UpdateOrders())
	}
	If ..AlertFloor '= "" {
		New $NAMESPACE
		Set $NAMESPACE = ..#ORDERS
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Alerting.ManagedAlert WHERE ID > ?", ..AlertFloor)
		Set ..AlertFloor = ""
	}
	Quit sc
}

/// Stops the Telegram items and puts back what the start saved.
Method TelegramOff() As %Status [ Private ]
{
	If ..Saved = "" Quit $$$OK
	Set saved = ..Saved
	Set ..Saved = ""
	Set ..PairChat = ""
	Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Finish(saved)
	Quit $Select(reason = "": $$$OK, 1: $SYSTEM.Status.Error(5001, "Telegram was not put back: "_reason))
}

/// Applies the saved Orders definition to the running production, in OCUORDERS.
ClassMethod UpdateOrders() As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(Ens.Director).UpdateProduction(##class(Ens.Director).GetRunningProductionUpdateTimeout())
}

/// Puts the production setting that names the Notification Manager into (on) or out of (off) the saved Orders definition, and saves it.
ClassMethod PutNotifier(on As %Boolean) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no definition of "_..#ORDERSPRODUCTION)
	For i = production.Settings.Count():-1:1 {
		If production.Settings.GetAt(i).Name = ..#NOTIFYSETTING Do production.Settings.RemoveAt(i)
	}
	If on {
		Set setting = ##class(Ens.Config.Setting).%New()
		Set setting.Target = "Production"
		Set setting.Name = ..#NOTIFYSETTING
		Set setting.Value = ..#NOTIFYITEM
		Do production.Settings.Insert(setting)
	}
	Quit production.%Save()
}

/// The saved Orders definition's items as "name|class|pool|enabled|settings" joined by newlines, in definition order, so that two states can be compared.
ClassMethod Shape() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit "<no definition>"
	Set text = ""
	For i = 1:1:production.Settings.Count() {
		Set one = production.Settings.GetAt(i)
		Set text = text_$Select(text = "": "", 1: $Char(10))_"production|"_one.Target_":"_one.Name_"="_one.Value
	}
	For i = 1:1:production.Items.Count() {
		Set each = production.Items.GetAt(i)
		Set settings = ""
		For j = 1:1:each.Settings.Count() {
			Set setting = each.Settings.GetAt(j)
			Set settings = settings_$Select(settings = "": "", 1: ",")_setting.Target_":"_setting.Name_"="_setting.Value
		}
		Set text = text_$Select(text = "": "", 1: $Char(10))_each.Name_"|"_each.ClassName_"|"_each.PoolSize_"|"_each.Enabled_"|"_settings
	}
	Quit text
}

/// The managed alerts of OCUORDERS after the floor, as a dynamic array of {"id", "source", "open", "text"} (the text cut to 100 characters).
ClassMethod Alerts(floor As %Integer) As %DynamicArray
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rows = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SourceConfigName, IsOpen, AlertText FROM Ens_Alerting.ManagedAlert WHERE ID > ? ORDER BY ID", floor)
	While rs.%Next() {
		Do rows.%Push({"id": (rs.%GetData(1)), "source": (rs.%GetData(2)), "open": (rs.%GetData(3)), "text": ($Extract(rs.%GetData(4), 1, 100))})
	}
	Quit rows
}

/// Waits up to WAITBATCH seconds for count failed headers (Status 8) sent by the source in OCUORDERS after the test's first send; how many there are.
Method WaitFailedAt(source As %String, count As %Integer) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND Status = 8 AND SourceConfigName = ?", ..OrdersFloor, source)
		Do rs.%Next()
		Set found = +rs.%GetData(1)
		If (found '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit found
}

/// The headers of OCUORDERS after the floor, counted by "status source>target", as one line.
ClassMethod HeaderSummary(floor As %Integer) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, SourceConfigName, TargetConfigName, COUNT(*) FROM Ens.MessageHeader WHERE ID > ? GROUP BY Status, SourceConfigName, TargetConfigName", floor)
	Set text = ""
	While rs.%Next() {
		Set text = text_$Select(text = "": "", 1: "; ")_rs.%GetData(4)_" x status "_rs.%GetData(1)_" "_rs.%GetData(2)_">"_rs.%GetData(3)
	}
	Quit text
}

/// The error and warning rows of OCUORDERS' event log after the floor that name the AlertManager item or an alert, as "config: text" joined by " / ", each text cut to 400 characters.
ClassMethod AlertLog(floor As %Integer) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ConfigName, Type, Text FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 3) ORDER BY ID", floor)
	Set text = "", count = 0
	While rs.%Next() && ($Increment(count) < 6) {
		Set text = text_$Select(text = "": "", 1: " / ")_rs.%GetData(1)_" t"_rs.%GetData(2)_": "_$Extract(rs.%GetData(3), 1, 400)
	}
	Quit text
}

/// Waits up to WAITALERT seconds for at least count managed alerts after the floor; the alerts, and the seconds it took in seconds.
Method WaitAlerts(floor As %Integer, count As %Integer, Output seconds As %Numeric) As %DynamicArray [ Private ]
{
	Set start = $ZHorolog
	Set end = start + ..#WAITALERT
	For {
		Set rows = ..Alerts(floor)
		If (rows.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Set seconds = $ZHorolog - start
	Quit rows
}

/// Makes a measured value visible in the output of a run that passes (a status 2 assert is printed as SKIP by ci/iris.sh).
Method Timing(text As %String) [ Private ]
{
	Do $$$LogMessage(text)
	Do ..Manager.LogAssert(2, "Timing", text)
}

/// Task 0 (a): Managed Alerts keep working beside OcuTalon. The AlertManager item and AlertOnError 1 on OrdersFromPartner go into the saved definition and are applied; three orders
/// are broken; the managed alerts are counted and timed; the AlertManager needs no other setting; and taking both out leaves the definition and the jobs as they were.
Method TestManagedAlerts()
{
	If '..Ready() Quit
	Set item = ..#FAILING
	Set shapeBefore = ..Shape()
	Set jobsBefore = ##class(OcuTalon.Test.Watch.Rollback).Jobs()
	Set ..AlertFloor = ..Top("Ens_Alerting.ManagedAlert", ..#ORDERS)
	Set floor = ..AlertFloor
	Set ..AlertSet = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).AddItem(..#ALERTITEM, 1, 0, "", "Ens.Alerting.AlertManager"), "the "_..#ALERTITEM_" item (Ens.Alerting.AlertManager) is in the saved definition")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).AddItem(..#NOTIFYITEM, 1, 0, "", "Ens.Alerting.NotificationManager"), "the "_..#NOTIFYITEM_" item is in it")
	Do $$$AssertStatusOK(..PutNotifier(1), "and the production setting "_..#NOTIFYSETTING_" names it")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(item, 1, "Host", ..#ALERTSETTING, 1), ..#ALERTSETTING_" is 1 on "_item)
	Set start = $ZHorolog
	Do $$$AssertStatusOK(..UpdateOrders(), "the production applies the definition")
	Do ..Timing("Task 0 (a): UpdateProduction with the AlertManager item took "_$FNumber($ZHorolog - start, "", 2)_" s")
	Set during = ##class(OcuTalon.Test.Watch.Rollback).Jobs()
	Do ..Timing("Task 0 (a): jobs with the AlertManager: "_during)
	Do ..Timing("Task 0 (a): settings stored on the AlertManager item: '"_##class(OcuTalon.Test.Watch.Rollback).Stored(..#ALERTITEM)_"' (none needed)")
	Set sentAt = $ZHorolog
	If '..Fail(3) Quit
	Set failed = ..WaitFailedAt("PartnerOrdersIn", 3)
	Do $$$AssertEquals(failed, 3, "3 orders are in the error status at OrdersFromPartner")
	Do ..Timing("Task 0 (a): headers after the break: "_..HeaderSummary(..OrdersFloor))
	Do ..Timing("Task 0 (a): log of "_..#ALERTITEM_" and of the alert errors: "_..AlertLog(..OrdersLogFloor))
	Set rows = ..WaitAlerts(floor, 3, .seconds)
	Set seconds = $ZHorolog - sentAt
	Do ..Timing("Task 0 (a): "_rows.%Size()_" managed alert(s) for 3 broken orders "_$FNumber(seconds, "", 2)_" s after the orders were sent; the first: "_$Select(rows.%Size(): rows.%Get(0).%ToJSON(), 1: "none"))
	Do $$$AssertTrue(rows.%Size() '< 1, "an Ens_Alerting.ManagedAlert row exists after the failures")
	Set sources = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If sources '[ ("|"_row.source_"|") Set sources = sources_"|"_row.source_"|"
	}
	Do ..Timing("Task 0 (a): sources of the managed alerts: "_sources)
	Do $$$AssertStatusOK(..AlertOff(), "the AlertManager item and "_..#ALERTSETTING_" are taken out and the production applies it")
	Do $$$AssertEquals(..Shape(), shapeBefore, "the definition is as it was")
	Set jobsAfter = ##class(OcuTalon.Test.Watch.Rollback).Jobs()
	Do ..Timing("Task 0 (a): jobs before "_jobsBefore_" and after "_jobsAfter)
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Rollback).OtherJobs(jobsAfter) [ ..#ALERTITEM, 0, "the AlertManager job is gone")
}

/// Task 0 (b): a notice of a real incident, through IncidentManager and Notify, reaches TelegramOut and the mock for the session's paired chat, in a stack of the Watch area.
Method TestPageReachesTelegram()
{
	If '..Ready() Quit
	Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Start(.saved, "", 1)
	Set ..Saved = saved
	Do $$$AssertEquals(reason, "", "TelegramIn and TelegramOut are running against the mock")
	If reason '= "" Quit
	Set ..PairChat = ..#CHAT
	For key = "oncall.primary.user", "oncall.primary.email", "oncall.backup.user", "oncall.backup.email" {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.Paging).Write(key, ""), "the key "_key_" has no value")
	}
	Set start = $ZHorolog
	If '..RaisedShared("pg", .a, .ref) Quit
	Set sent = ##class(OcuTalon.Test.Channel.LiveCase).WaitCalls("sendMessage", 1, 30)
	Do ..Timing("Task 0 (b): the incident's notice reached the mock "_$FNumber($ZHorolog - start, "", 2)_" s after the break; sendMessage calls: "_sent.%Size())
	Do $$$AssertTrue(sent.%Size() '< 1, "the mock recorded a sendMessage for the paired chat")
	Set texts = ##class(OcuTalon.Test.Channel.LiveCase).TextsTo(..#CHAT)
	Do $$$AssertTrue(texts.%Size() '< 1, "the paired chat got a text")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Pages(ref), 0, "with no on-call person configured, the incident has no page")
	If texts.%Size() Do ..Timing("Task 0 (b): the chat's first text: "_$Extract(texts.%Get(texts.%Size() - 1), 1, 80))
}

/// Task 0 (c): Commands.Submit of an escalation SetReminder from origin system answers not_built, with no deadlock. The in-job ask is made by TestRealBreakPagesTelegram in the real run.
Method TestEscalationAsk()
{
	If '..Ready() Quit
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.Kind = "escalation"
	Set command.IncidentRef = "zzpagelive-incident"
	Set command.PageRef = "zzpagelive-page"
	Set command.DelaySeconds = 900
	Set start = $ZHorolog
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "system", .result)
	Set took = $ZHorolog - start
	Do ..Timing("Task 0 (c): Submit of the escalation SetReminder answered in "_$FNumber(took, "", 3)_" s")
	Do $$$AssertStatusOK(sc, "the command reached CommandsIn")
	If $$$ISERR(sc) || '$IsObject(result) Quit
	Do ..Timing("Task 0 (c): Ok "_result.Ok_", outcome "_result.Outcome_", ref '"_result.Ref_"'")
	Do $$$AssertEquals(result.Outcome, "not_built", "the escalation kind is not built in ReminderOps")
	Do $$$AssertEquals(result.Ok, 0, "and it answers Ok 0")
}

/// Task 0 (d): what WebChatOut and SimPhoneOut log for a page copy with a bare Delivery row, when a handled notification for its Ref follows.
Method TestHandledCopies()
{
	If '..Ready() Quit
	Set a = ..Session("hc")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set floor = ..Top("Ens_Util.Log", $Namespace)
	Set page = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = ##class(OcuTalon.Msg.Notification).%New()
	Set one.SessionRef = a
	Set one.Kind = "page"
	Set one.CatalogKey = "page.onCall"
	Set one.DecisionRef = page
	Set one.Slots = {"count": 3}.%ToJSON()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Channel.LiveCase).SendToNotify(one, trace), "a page Notification goes to Notify")
	Do ..WaitDeliveries(a, page, "page", 2)
	Set two = ##class(OcuTalon.Msg.Notification).%New()
	Set two.SessionRef = a
	Set two.Kind = "handled"
	Set two.DecisionRef = page
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Channel.LiveCase).SendToNotify(two, trace), "then a handled Notification for its Ref")
	Do ..WaitDeliveries(a, page, "handled", 2)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Type, ConfigName, Text FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 3) AND ConfigName IN ('WebChatOut', 'SimPhoneOut', 'Notify') ORDER BY ID", floor)
	Set lines = ""
	While rs.%Next() {
		Set lines = lines_$Select(lines = "": "", 1: " / ")_"type "_rs.%GetData(1)_" "_rs.%GetData(2)_": "_$Extract(rs.%GetData(3), 1, 160)
	}
	Do ..Timing("Task 0 (d): warnings and errors of WebChatOut, SimPhoneOut and Notify: "_$Select(lines = "": "none", 1: lines))
	Do $$$AssertEquals(lines, "", "the page copies and their handled notification log no warning")
}

/// Waits up to WAITCOPY seconds for count Delivery rows of the kind with the Ref, in the session's channels (web and phone).
Method WaitDeliveries(session As %String, ref As %String, kind As %String, count As %Integer) As %Integer [ Private ]
{
	Set end = $ZHorolog + ..#WAITCOPY
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND DecisionRef = ? AND Kind = ?", session, ref, kind)
		Do rs.%Next()
		Set found = +rs.%GetData(1)
		If (found '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(found, count, count_" "_kind_" Delivery row(s) of the Ref, one for each of the web and phone channels")
	Quit found
}

/// A fixture session, paired with the chat of PairChat through the real /start path when one is set.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##super(name)
	If ..PairChat '= "" Do ..Pair(ref, ..PairChat, "Zz Pager")
	Quit ref
}

/// Pairs the chat with the session through the real /start path: a code row for the session, then the chat's /start update; 1 when the chat's row is linked to the session.
Method Pair(session As %String, chatId As %String, name As %String) As %Boolean [ Private ]
{
	Set code = "zzpg"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set expires = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, ##class(OcuTalon.Data.Pairing).HashCode(code), expires), "a pairing code is stored for the session")
	Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Send(chatId, name, "/start "_code, .queuedAt)
	Do $$$AssertEquals(reason, "", "the chat's /start update is queued")
	Set end = $ZHorolog + ..#WAITCOPY
	Set linked = 0
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE ChatId = ? AND SessionRef = ?", chatId, session)
		Do rs.%Next()
		Set linked = +rs.%GetData(1)
		If linked || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue(linked, "the chat is paired with the session")
	Quit linked
}

/// Writes the on-call keys for the primary and backup users and the minutes, and leaves the addresses and both channel keys without a row.
Method SetKeys(primaryUser As %String, backupUser As %String, minutes As %Integer) [ Private ]
{
	For key = "oncall.primary.email", "oncall.backup.email", "oncall.primary.channels", "oncall.backup.channels" {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.Paging).Write(key, ""), key_" has no row")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.Paging).Write("oncall.primary.user", primaryUser), "the on-call user is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.Paging).Write("oncall.backup.user", backupUser), "the backup user is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.Paging).Write("oncall.escalationMinutes", minutes), "the minutes are set")
}

/// Waits up to WAITPAGE seconds for the page row of the incident and the role; the row, or "" with a failed assertion.
Method WaitPage(incident As %String, role As %String) As OcuTalon.Data.Page [ Private ]
{
	Set end = $ZHorolog + ..#WAITPAGE
	For {
		Set page = ##class(OcuTalon.Test.Watch.Paging).Page(incident, role)
		If $IsObject(page) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(page), "the "_role_" page row exists")
	Quit page
}

/// Sends the Escalation message to IncidentManager from the host service, as ReminderTimer will (Story 24.3), under the trace.
Method SendEscalation(incident As %String, page As %String, trace As %String) [ Private ]
{
	Set message = ##class(OcuTalon.Msg.Escalation).%New()
	Set message.IncidentRef = incident
	Set message.PageRef = page
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $$$ISOK(sc) {
		Set service.%SuperSession = trace
		Set sc = service.SendRequestAsync("IncidentManager", message)
	}
	Do $$$AssertStatusOK(sc, "the Escalation message is sent to IncidentManager")
}

/// The sendMessage calls of the mock to the chat whose text is the text.
ClassMethod Messages(chat As %String, text As %String) As %DynamicArray
{
	Set found = []
	Set iterator = ##class(OcuTalon.Test.Channel.LiveCase).CallsOf("sendMessage").%GetIterator()
	While iterator.%GetNext(, .call) {
		If (call.params."chat_id" = chat) && (call.params.text = text) Do found.%Push(call)
	}
	Quit found
}

/// Waits up to WAITPAGE seconds for count sendMessage calls to the chat with the text; the calls.
Method WaitMessages(chat As %String, text As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITPAGE
	For {
		Set found = ..Messages(chat, text)
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// Waits up to WAITPAGE seconds for count editMessageText calls to the chat; the params of the calls.
Method WaitEdits(chat As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITPAGE
	For {
		Set found = ##class(OcuTalon.Test.Channel.LiveCase).EditsTo(chat)
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The expected text of a page Notification of the ref, for the telegram channel: the stored Notification's key and slots, with the name added as the key's text needs.
Method Expected(incident As %String, kind As %String, extraName As %String, extra As %String) As %String [ Private ]
{
	Set end = $ZHorolog + ..#WAITPAGE
	For {
		Set notes = ..NoticeBodies(incident, "page")
		Set found = ""
		For i = 0:1:notes.%Size() - 1 {
			If notes.%Get(i).catalogKey = kind Set found = notes.%Get(i)
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(found), "the Notification with the key "_kind_" is in the trace")
	If '$IsObject(found) Quit ""
	Set slots = found.slots
	Do slots.%Set(extraName, extra, "string")
	Set text = ##class(OcuTalon.Msg.Catalog).Render(kind, slots, "telegram", .sc)
	Do $$$AssertStatusOK(sc, "and renders")
	Quit text
}

/// The exported bodies of the messages after the header mark that a page makes: the page and handled Notifications, the Escalation, AckPage and SetReminder messages, with
/// their headers' fields, as one text (the Ens trace of paging).
ClassMethod PageTrace(mark As %Integer) As %String
{
	Set text = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SourceConfigName, TargetConfigName, MessageBodyClassName, MessageBodyId, SessionId, SuperSession FROM Ens.MessageHeader WHERE ID > ?", mark)
	While rs.%Next() {
		Set class = rs.%GetData(4)
		Set id = rs.%GetData(5)
		If (class = "") || (id = "") || '$ListFind($ListBuild("OcuTalon.Msg.Notification", "OcuTalon.Msg.Escalation", "OcuTalon.Msg.Command.AckPage", "OcuTalon.Msg.Command.SetReminder", "OcuTalon.Msg.Command.CancelReminder"), class) Continue
		Set body = $ClassMethod(class, "%OpenId", id)
		If '$IsObject(body) Continue
		If (class = "OcuTalon.Msg.Notification") && (body.Kind '= "page") && (body.Kind '= "handled") Continue
		Set xml = ""
		Do body.XMLExportToString(.xml)
		Set text = text_rs.%GetData(2)_">"_rs.%GetData(3)_" "_rs.%GetData(6)_" "_rs.%GetData(7)_" "_xml_$Char(10)
	}
	Quit text
}

/// The first of the names (a $ListBuild list) that the text holds, "" when it holds none.
ClassMethod Holds(text As %String, names As %List) As %String
{
	Quit ##class(OcuTalon.Test.Watch.Paging).Holds(text, names)
}

/// AC6, AC8, AC12 and AC13 over the running production, the CI mock and real routes: see the class description.
Method TestRealBreakPagesTelegram()
{
	If '..Ready() Quit
	Set live = "OcuTalon.Test.Channel.LiveCase"
	Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Start(.saved, "", 1)
	Set ..Saved = saved
	Do $$$AssertEquals(reason, "", "TelegramIn and TelegramOut are running against the mock")
	If reason '= "" Quit
	Set ..PairChat = ..#CHATB
	Set sessionB = ..Session("bk")
	Set ..PairChat = ..#CHAT
	Set userA = ..#SESSIONPREFIX_..Number_"pg"
	Set userB = ..#SESSIONPREFIX_..Number_"bk"
	Do ..SetKeys(userA, userB, 15)
	Set headerMark = ##class(OcuTalon.Test.Channel.LiveCase).HeaderMark()
	Set liveMark = ##class(OcuTalon.Test.Channel.LiveCase).LiveMark()
	Set logMark = ..Top("Ens_Util.Log", $Namespace)
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	If '..RaisedShared("pg", .a, .ref) Quit
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef

	// the on-call page
	Set page = ..WaitPage(ref, "oncall")
	If '$IsObject(page) Quit
	Do $$$AssertEquals(page.Person_"|"_page.Channels_"|"_page.AcknowledgedAt, userA_"|telegram,email|", "the on-call page is the user's, unacknowledged")
	Set expected = ..Expected(ref, "page.onCall", "backup", userB)
	Set sent = ..WaitMessages(..#CHAT, expected, 1)
	Do $$$AssertEquals(sent.%Size(), 1, "the mock recorded one sendMessage with the page's text, with the backup's name")
	If sent.%Size() '= 1 Quit
	Set params = sent.%Get(0).params
	Set button = params."reply_markup"."inline_keyboard".%Get(0).%Get(0)
	Do $$$AssertEquals(button."callback_data"_"|"_button.text_"|"_params.%IsDefined("parse_mode"), "gotit:"_page.Ref_"|Got it|0", "with the Got it button, whose data is gotit and the page's Ref, and no parse mode")
	Set incidentState = ..StateIncident(a, ref)
	Do $$$AssertEquals($Select($IsObject(incidentState): incidentState.page.state, 1: "none"), "paged", "/state lists the page as paged")

	// the escalation, twice
	Do ..SendEscalation(ref, page.Ref, trace)
	Set backup = ..WaitPage(ref, "backup")
	If '$IsObject(backup) Quit
	Do $$$AssertEquals(backup.Person_"|"_backup.EscalationRef, userB_"|", "the backup's page is the backup's, with no timer of its own")
	Set expectedB = ..Expected(ref, "page.backup", "person", userA)
	Set sentB = ..WaitMessages(..#CHATB, expectedB, 1)
	Do $$$AssertEquals(sentB.%Size(), 1, "the backup's chat got the backup page once")
	Do ..SendEscalation(ref, page.Ref, trace)
	Hang 4
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Pages(ref)_"|"_..Messages(..#CHATB, expectedB).%Size(), "2|1", "a repeated Escalation adds no row and no message")
	Do $$$AssertEquals(..StateIncident(a, ref).page.state, "escalated", "/state lists the page as escalated")

	// Got it from a chat of no session, from the backup's chat, then from the paired chat, then again
	Set answers = ##class(OcuTalon.Test.Channel.LiveCase).PressAnswers(0).%Size()
	Set data = "gotit:"_page.Ref
	Do $$$AssertEquals(##class(OcuTalon.Test.Channel.TelegramPageFixture).Press(..#CHATX, ..#NAMEX, data, .queued), "", "a press from a chat that is paired with no session is queued")
	Do ##class(OcuTalon.Test.Channel.LiveCase).WaitAnswers(answers, 1, 20)
	Do $$$AssertEquals(##class(OcuTalon.Test.Channel.TelegramPageFixture).Press(..#CHATB, ..#NAMEB, data, .queued), "", "a press from the backup's chat is queued")
	Do ##class(OcuTalon.Test.Channel.LiveCase).WaitAnswers(answers, 2, 20)
	Hang 2
	Set page = ##class(OcuTalon.Test.Watch.Paging).Page(ref)
	Do $$$AssertEquals(page.AcknowledgedAt_"|"_##class(OcuTalon.Test.Channel.LiveCase).EditsTo(..#CHAT).%Size(), "|0", "neither acknowledged the page or edited its message")
	Do $$$AssertEquals(##class(OcuTalon.Test.Channel.TelegramPageFixture).Press(..#CHAT, ..#NAMEA, data, .queued), "", "the press from the paired chat is queued")
	Set edits = ..WaitEdits(..#CHAT, 1)
	Do $$$AssertEquals(edits.%Size(), 1, "the page's message is edited once")
	Set page = ##class(OcuTalon.Test.Watch.Paging).Page(ref)
	Do $$$AssertEquals(page.AcknowledgedChannel_"|"_(page.AcknowledgedAt '= ""), "telegram|1", "the page is acknowledged on the telegram channel")
	If edits.%Size() = 1 {
		Set marked = ##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (page.AcknowledgedAt)}, "telegram", .sc)
		Do $$$AssertEquals(edits.%Get(0).text, expected_$Char(10, 10)_marked, "to its text, a blank line and 'Marked as handled at' with the time")
		Do $$$AssertEquals(edits.%Get(0).%IsDefined("reply_markup"), 0, "with no button")
	}
	Set at = page.AcknowledgedAt
	Do $$$AssertEquals(##class(OcuTalon.Test.Channel.TelegramPageFixture).Press(..#CHAT, ..#NAMEA, data, .queued), "", "a second press is queued")
	Do ##class(OcuTalon.Test.Channel.LiveCase).WaitAnswers(answers, 4, 20)
	Hang 3
	Set page = ##class(OcuTalon.Test.Watch.Paging).Page(ref)
	Do $$$AssertEquals(page.AcknowledgedAt_"|"_##class(OcuTalon.Test.Channel.LiveCase).EditsTo(..#CHAT).%Size(), at_"|1", "it changes nothing and edits nothing more")
	Do $$$AssertEquals(..StateIncident(a, ref).page.state, "acknowledged", "/state lists the page as acknowledged")
	Set published = 0
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%GetIterator()
	While events.%GetNext(, .event) {
		If event.payload.%IsDefined("page") && (event.payload.page.state = "paged") Set published = published + 1
	}
	Do $$$AssertTrue(published '< 1, "the incident event that follows the timer's ask (which returned: no deadlock) says paged")

	// an AckPage over the web channel edits the backup's Telegram copy
	Set command = ##class(OcuTalon.Msg.Command.AckPage).%New()
	Set command.Ref = backup.Ref
	Set command.Channel = "web"
	Set command.SessionRef = sessionB
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result), "the web AckPage is submitted")
	Do $$$AssertEquals($Select($IsObject($Get(result)): result.Outcome, 1: "none"), "handled", "and handled")
	Set editsB = ..WaitEdits(..#CHATB, 1)
	Do $$$AssertEquals(editsB.%Size(), 1, "the backup's Telegram copy is edited")
	Set backup = ##class(OcuTalon.Test.Watch.Paging).Page(ref, "backup")
	If editsB.%Size() = 1 {
		Set markedB = ##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (backup.AcknowledgedAt)}, "telegram", .sc)
		Do $$$AssertEquals(editsB.%Get(0).text_"|"_backup.AcknowledgedChannel, expectedB_$Char(10, 10)_markedB_"|web", "to its text and the marker, with the web channel recorded")
	}

	// no warning of the hosts that carry a page, and no name in any record
	Set hosts = "('IncidentManager', 'Notify', 'WebChatOut', 'SimPhoneOut', 'TelegramOut', 'TelegramIn')"
	Set warned = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT ConfigName||': '||Text FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 3) AND ConfigName IN "_hosts, logMark)
	Do $$$AssertEquals(warned, "", "no host of a page logged an error or a warning")
	Set names = $ListBuild(userA, userB, ..#CHAT, ..#CHATB, ..#CHATX, ..#NAMEA, ..#NAMEB, ..#NAMEX)
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(auditMark, "OcuTalon", "Action").%ToJSON()
	Do $$$AssertTrue((audit [ page.Ref) && (audit [ backup.Ref) && (audit [ "page_acknowledged"), "the audit entries name both pages and their acknowledgements")
	Do $$$AssertEquals(..Holds(audit, names), "", "the audit entries hold no user, chat id or display name")
	Set pageTrace = ..PageTrace(headerMark)
	Do $$$AssertTrue((pageTrace [ page.Ref) && (pageTrace [ backup.Ref) && (pageTrace [ "AckPage"), "the trace of paging holds both pages' Refs and the AckPage, so its search is not over empty text")
	Do $$$AssertEquals(..Holds(pageTrace, names), "", "the messages of paging hold no user, chat id or display name")
	Set logText = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT Text FROM Ens_Util.Log WHERE ID > ?", logMark)
	Do $$$AssertEquals(..Holds(logText, names), "", "the event log holds none")
	Set eventText = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ? AND Type = 'incident'", liveMark)
	Do $$$AssertTrue((eventText [ ref) && (eventText [ "paged"), "the incident events hold the incident's Ref and the paged state, so their search is not over empty text")
	Do $$$AssertEquals(..Holds(eventText, names), "", "the incident events hold none")
	Set stateText = ..StateIncident(a, ref).%ToJSON()
	Do $$$AssertTrue((stateText [ ref) && (stateText [ "acknowledged"), "the state's incident holds its Ref and the acknowledged page, so its search is not over empty text")
	Do $$$AssertEquals(..Holds(stateText, names), "", "and the state's incident holds none")
	Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Watch.PagingLive", "TestRealBreakPagesTelegram", "control line for "_userA)
	Do $$$AssertEquals(..Holds(##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT Text FROM Ens_Util.Log WHERE ID > ?", logMark), names), userA, "control: the same search of the event log finds a line that holds a name")
}

/// The set-up of a break of the shared, watched production: the production is ready, the mock is pointed to, the approval role is ready, a session S watches Orders, and untagged failing
/// orders (3) become an incident of the instance that is noticed to S. a is S and ref the incident, the one made since the test began. 1 when the set-up is done.
Method RaisedShared(name As %String, Output a As %String, Output ref As %String) As %Boolean [ Private ]
{
	Set (a, ref) = ""
	If '..Ready() Quit 0
	If '..PointKeys() Quit 0
	If '..ApprovalReady() Quit 0
	Set a = ..Session(name)
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	If '..Fail(3, "") Quit 0
	Set failed = ..WaitFailed(3)
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set rows = ..Above(..Incidents("instance", ..#ORDERSPRODUCTION), ..IncidentFloor)
		If (rows.%Size() > 0) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(rows.%Size(), 1, "one incident of the instance for the untagged break")
	If rows.%Size() < 1 Quit 0
	Set ref = rows.%Get(0).ref
	Quit ..Noticed(ref, 1)
}

/// The rows of incidents (Case.Incidents) whose ID is above floor: the incidents made since the floor was read, so that an incident another test left is never taken.
ClassMethod Above(incidents As %DynamicArray, floor As %Integer) As %DynamicArray [ Private ]
{
	Set above = []
	For i = 0:1:incidents.%Size() - 1 {
		If incidents.%Get(i).id > floor Do above.%Push(incidents.%Get(i))
	}
	Quit above
}

/// DW-1396: with an on-call user and a backup set, both other users than S, a break tagged with S's trace Ref (that user's own Break the feed) is an incident of S (Raised finds it by
/// S's Ref), and it pages nobody: the notice reaches S, and no page row and no page Notification follow.
Method TestSessionBreakNeverPages()
{
	If '..Ready() Quit
	Do ..Session("sx"), ..Session("sy")
	Do ..SetKeys(..#SESSIONPREFIX_..Number_"sx", ..#SESSIONPREFIX_..Number_"sy", 15)
	If '..Raised("so", .a, .ref, .request) Quit
	Hang 5
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Pages(ref), 0, "no page row exists for the session's incident")
	Do $$$AssertEquals(..NoticeBodies(ref, "page").%Size(), 0, "no page Notification carries its Ref")
}

/// AC8: with the AlertManager fixture in the Orders definition and an on-call user configured, a real break pages the user, an Ens_Alerting.ManagedAlert row exists for the failing item,
/// and every setting of every item of the definition reads as it did before the break.
Method TestManagedAlertsBesidePaging()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	If '..ApprovalReady() Quit
	Set a = ..Session("al")
	Set user = ..#SESSIONPREFIX_..Number_"al"
	Do ..SetKeys(user, "", 15)
	Set ..AlertFloor = ..Top("Ens_Alerting.ManagedAlert", ..#ORDERS)
	Set ..AlertSet = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).AddItem(..#ALERTITEM, 1, 0, "", "Ens.Alerting.AlertManager"), "the AlertManager item is in the Orders definition")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).AddItem(..#NOTIFYITEM, 1, 0, "", "Ens.Alerting.NotificationManager"), "with its Notification Manager")
	Do $$$AssertStatusOK(..PutNotifier(1), "named by the production setting")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#ALERTSETTING, 1), ..#ALERTSETTING_" is 1 on "_..#FAILING)
	Do $$$AssertStatusOK(..UpdateOrders(), "and the production applies it")
	Set shape = ..Shape()
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set sentAt = $ZHorolog
	If '..Fail(3, "") Quit
	Set paged = ""
	Set end = $ZHorolog + ..#WAITPAGE + 60
	For {
		Set incidents = ..Above(..Incidents("instance", ..#ORDERSPRODUCTION), ..IncidentFloor)
		For i = 0:1:incidents.%Size() - 1 {
			If ##class(OcuTalon.Test.Watch.Paging).Pages(incidents.%Get(i).ref) Set paged = incidents.%Get(i).ref
		}
		If (paged '= "") || ($ZHorolog > end) Quit
		Hang 1
	}
	Do $$$AssertTrue(paged '= "", "an incident of the break is paged")
	If paged '= "" Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Page(paged).Person, user, "the user is the one paged")
	Set rows = ..WaitAlerts(..AlertFloor, 1, .seconds)
	Set from = ""
	For i = 0:1:rows.%Size() - 1 {
		If rows.%Get(i).source = ..#FAILING Set from = rows.%Get(i).id
	}
	Do $$$AssertTrue(from '= "", "after the page, an Ens_Alerting.ManagedAlert row exists for "_..#FAILING)
	Do $$$AssertEquals(..Shape(), shape, "every setting of every item reads as before the page")
	Do ..Timing("AC8: "_rows.%Size()_" managed alert(s) and a page "_$FNumber($ZHorolog - sentAt, "", 1)_" s after the break")
}

/// AC10: over real HTTP, as a signed-in admin, GET /api/v1/settings says that pages are built, because OcuTalon.Data.Page is compiled.
Method TestSettingsSaysPagesBuilt()
{
	If '..Ready() Quit
	Set running = ##class(Ens.Director).IsProductionRunning(.name)
	Set missing = ##class(OcuTalon.Test.Core.AnswersInWebRoles).Reason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"), running, $Get(name))
	Do $$$AssertEquals(missing, "", "the stack is a throwaway with the web server")
	If missing '= "" Quit
	Do ..DropAdmin()
	Set password = "Zz"_$TR($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "abc")_"xY9"
	New $Namespace
	Set home = $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.Users).Delete(..#ADMIN)
	Set sc = ##class(Security.Users).Create(..#ADMIN, "OcuTalonUser,OcuTalonAdmin", password, "OcuTalon test fixture", , , , 0, 1)
	Set $Namespace = home
	Do $$$AssertStatusOK(sc, "the fixture admin is created")
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = ..#PORT
	Set request.FollowRedirect = 0
	Do request.Get("/ocutalon/")
	Do request.InsertFormData("IRISUsername", ..#ADMIN)
	Do request.InsertFormData("IRISPassword", password)
	Do request.InsertFormData("IRISLogin", "Login")
	Do $$$AssertStatusOK(request.Post("/ocutalon/"), "the admin signs in")
	Set sc = request.Get("/ocutalon/api/v1/settings")
	Do $$$AssertStatusOK(sc, "GET /api/v1/settings is sent")
	If $$$ISERR(sc) || '$IsObject(request.HttpResponse) Quit
	Do $$$AssertEquals(request.HttpResponse.StatusCode, 200, "and answers 200")
	Set body = ##class(%DynamicAbstractObject).%FromJSON(request.HttpResponse.Data.Read(3000000))
	Set found = $Select($IsObject(body.sections): body.sections."on-call", 1: "")
	Do $$$AssertTrue($IsObject(found), "the settings list the On call section")
	If $IsObject(found) Do $$$AssertEquals(found.pagesBuilt, 1, "and pagesBuilt is true")
}

/// Deletes the fixture admin.
ClassMethod DropAdmin() [ Private ]
{
	New $Namespace
	Set home = $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.Users).Delete(..#ADMIN)
	Set $Namespace = home
}

}
