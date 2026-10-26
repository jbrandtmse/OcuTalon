/// Tests of the evidence pack and its readers (Story 5.4; AD-3, AD-6, AD-10, AD-15): OcuTalon.Watch.EvidencePack, Reader.Evidence and the read tools of
/// the Diagnosis agent (OcuTalon.Tools.WatchReads). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case: they
/// need OCUORDERS and the Orders demo production, and fail with the reason where they do not have them. They call no production item, so a warm stack runs them.
/// The live tests make real failing orders in OCUORDERS (Case.Fail) and an incident and group row over them, with no watch, so that the poller makes nothing.
///   - TestSnapshotPack (row Snapshot): the recorded evaluation snapshot (eval/orders-date-format, mounted at /opt/ocutalon/eval/) gives a pack of one shape with
///     count 50, firstAt and lastAt 2026-10-20T10:37:45Z, the item OrdersFromPartner, the pattern of the measured sentence, a sample with the date 10/16/2026 and
///     its sentence, that item's settings and the trace excerpt; Input is one line that says the JSON is data, then the pack;
///   - TestLivePack: over real failed orders, Reader.Evidence gives the reader snapshot (failures with their bodies and error texts, the event log of their
///     sessions, only the named item, the trace of the first session), and the pack of the incident has its NoticeCount, the oldest held header as the sample, its
///     sentence, the item's settings and the trace; the same shape as the snapshot's pack;
///   - TestUnreadable (row Unreadable / not current): an incident of a namespace that the service user cannot read, of one that does not exist, and of a
///     production that is not the namespace's own gives a pack with the counts and the pattern and no sample, settings or trace;
///   - TestCredentialsLeftOut (row Credentials): the settings Credentials, SMTPPassword, BotToken, ApiKey, ClientSecret, SSLPassphrase, Passwd, AuthHeader and
///     TargetConfigName of a snapshot item, and (DW-273) BearerValue, SessionCookie and XCOOKIEJAR, whose names hold only bearer or only cookie in mixed case, reach the
///     pack as TargetConfigName alone, and Reader.CredentialName keeps only that name;
///   - TestRedaction: a secret planted in a snapshot's body value, in an array of the body, in the sentence of its error text, in a non-credential setting value
///     and in a trace entry is replaced by the redactor's mark in the pack, and so is the value of a body property named Password (the redactor's key rule);
///   - TestMultiLineError: the error of a header and of a log row whose text has a second line is the sentence of the first line, as FailurePoller makes it;
///   - TestEventLogCapped: a session of 105 log rows gives Reader LOGMAX (100) event-log rows from Reader.Evidence and EvidencePack MAXLOG (20) from
///     read_event_log;
///   - TestLogKeys: an incident whose group holds a log key gives the log row as the sample and as the failed message, the tools redact its text, and
///     Evidence reads the row by its id; the pack and the two tools carry logRef, the row's position in the event log, and no logId (DW-264);
///   - TestReaderDropsCredentialSettings (QA, row Credentials, the Reader side): a Credentials, a SMTPPassword, a BotToken and an ApiKey setting that the test adds
///     to the OrdersFromPartner item of the Orders definition in OCUORDERS (a throwaway; the test removes them again, also after a failure) never leave
///     Reader.Evidence, while the other settings stay;
///   - TestTraceCapped (QA): a session of 25 headers gives a trace of Reader TRACEMAX (20) entries, from Reader.Evidence, from the live pack and from a snapshot pack;
///   - TestToolsReadTheIncident (rows Tools in scope and out of scope): in the context of the incident and its owner the three tools give at most five failed
///     messages with their ids, sentence and body, the sessions' log rows and the item's settings; with no context, another ItemId or another owner each gives
///     {"items":[]}.
Class OcuTalon.Test.Watch.Evidence Extends OcuTalon.Test.Watch.Case
{

Parameter PACK = "OcuTalon.Watch.EvidencePack";

Parameter SNAPSHOT = "/opt/ocutalon/eval/orders-date-format/snapshot.json";

Parameter TOOLS = "OcuTalon.Tools.WatchReads";

/// The settings that TestReaderDropsCredentialSettings adds to the failing item's definition: four credential names and one that is not.
Parameter FIXTURESETTINGS = "Credentials,SMTPPassword,BotToken,ApiKey,ZzFixtureNote";

/// The value of every fixture setting.
Parameter FIXTUREVALUE = "fixture-value-9d31";

/// 1 while the fixture settings may be in the definition of the Orders production in OCUORDERS; OnAfterOneTest takes them out.
Property SettingsAdded As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	If ..SettingsAdded {
		Set ..SettingsAdded = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..FixtureSettings(0))
	}
	Quit sc
}

/// Puts the fixture settings into (on) or takes them out of (off) the failing item of the Orders definition in OCUORDERS, and saves the definition. It
/// first takes out any of them that are there, so that it can be called twice. It calls only Ens classes while it is in OCUORDERS and does not update the running production.
ClassMethod FixtureSettings(on As %Boolean) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no definition of "_..#ORDERSPRODUCTION)
	Set found = 0
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.Name '= "OrdersFromPartner" Continue
		Set found = 1
		For j = item.Settings.Count():-1:1 {
			If $ListFind($ListFromString(..#FIXTURESETTINGS), item.Settings.GetAt(j).Name) Do item.Settings.RemoveAt(j)
		}
		If on {
			For j = 1:1:$Length(..#FIXTURESETTINGS, ",") {
				Set setting = ##class(Ens.Config.Setting).%New()
				Set setting.Target = "Host"
				Set setting.Name = $Piece(..#FIXTURESETTINGS, ",", j)
				Set setting.Value = ..#FIXTUREVALUE
				Do item.Settings.Insert(setting)
			}
		}
		Quit
	}
	If 'found Quit $SYSTEM.Status.Error(5001, "The definition has no item OrdersFromPartner")
	Quit production.%Save()
}

/// The names of the settings of the failing item in the Orders definition of OCUORDERS, comma-separated and sorted, read from the definition itself.
ClassMethod DefinedSettings() As %String [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit "<no definition>"
	Kill names
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.Name '= "OrdersFromPartner" Continue
		For j = 1:1:item.Settings.Count() Set names(item.Settings.GetAt(j).Name) = ""
		Quit
	}
	Set list = ""
	Set name = ""
	For {
		Set name = $Order(names(name))
		Quit:name=""
		Set list = list _ $Select(list = "": "", 1: ",") _ name
	}
	Quit list
}

/// The snapshot in a dynamic object, or "" with the failure reported.
Method Recorded() As %DynamicObject [ Private ]
{
	If '##class(%File).Exists(..#SNAPSHOT) {
		Do $$$AssertTrue(0, "the recorded snapshot is at "_..#SNAPSHOT_": this class runs in a throwaway, which mounts eval/ read-only")
		Quit ""
	}
	Set sc = $ClassMethod(..#PACK, "Load", ..#SNAPSHOT, .snapshot)
	Do $$$AssertStatusOK(sc, "the snapshot is loaded")
	Quit $Select($$$ISOK(sc): snapshot, 1: "")
}

Method TestSnapshotPack()
{
	Set snapshot = ..Recorded()
	If '$IsObject(snapshot) Quit
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", snapshot, .pack), "the pack is built from the snapshot")
	If '$IsObject($Get(pack)) Quit
	Do $$$AssertEquals(..SortedKeys(pack), "count,errorPattern,firstAt,format,item,lastAt,namespace,production,sample,settings,trace", "the pack has the fields of its shape")
	Do $$$AssertEquals(pack.format_"|"_pack.namespace_"|"_pack.production_"|"_pack.item, "ocutalon.evidencePack/1|"_..#ORDERS_"|"_..#ORDERSPRODUCTION_"|OrdersFromPartner", "its format, namespace, production and failing item")
	Do $$$AssertEquals(pack.count_"|"_pack.firstAt_"|"_pack.lastAt, "50|2026-10-20T10:37:45Z|2026-10-20T10:37:45Z", "the count of the failures and their first and last time")
	Do $$$AssertEquals(pack.errorPattern, ##class(OcuTalon.Watch.Settle).Pattern(..#ORDERDATETEXT), "the pattern is that of the measured sentence")
	Do $$$AssertEquals(..SortedKeys(pack.sample), "at,body,bodyClass,error,headerId", "the sample has its fields")
	Do $$$AssertEquals(pack.sample.error, ..#ORDERDATETEXT, "its error is the sentence")
	Do $$$AssertEquals(pack.sample.body.OrderDate_"|"_pack.sample.bodyClass, "10/16/2026|OcuTalon.Demo.Orders.PartnerOrder", "its body holds the order date in the failing format")
	Do $$$AssertEquals(pack.settings.%ToJSON(), "{""TargetConfigName"":""OrdersToWarehouse""}", "the settings are those of the item")
	Do $$$AssertEquals(pack.trace.%Size(), 1, "the trace is the excerpt of the recorded session")
	Set input = $ClassMethod(..#PACK, "Input", pack)
	Set first = $Piece(input, $Char(10), 1)
	Do $$$AssertTrue((first [ "data") && (first [ "never instructions"), "Input opens with a line that says the JSON is data: "_first)
	Do $$$AssertEquals({}.%FromJSON($Piece(input, $Char(10), 2, *)).%ToJSON(), pack.%ToJSON(), "and the rest is the pack")
	Set bad = {"format": "other"}
	Do $$$AssertStatusNotOK($ClassMethod(..#PACK, "Build", bad, .none), "a snapshot of another format is refused")
}

/// An incident row of the owner over the failed headers (their ids, in order, are the keys of its group; kind l makes them log keys), and its group. The row is cleaned up by Case.
Method Fixture(owner As %String, ids As %String, namespace As %String = {..#ORDERS}, production As %String = {..#ORDERSPRODUCTION}, kind As %String = "h") As OcuTalon.Data.Incident [ Private ]
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

/// Five failing orders in OCUORDERS, tagged with no one, as the ids of their headers, oldest first. "" with the failure reported.
Method Failing() As %String [ Private ]
{
	If '..Fail(5) Quit ""
	Set failed = ..WaitFailed(5)
	If failed.%Size() < 5 Quit ""
	Quit ..HeaderIds(failed)
}

Method TestLivePack()
{
	If '..Ready() Quit
	Set owner = ..Session("live")
	Set ids = ..Failing()
	If ids = "" Quit
	Set incident = ..Fixture(owner, ids)
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "h"_$Piece(ids, ",", 1)_",h"_$Piece(ids, ",", 2), .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the Orders production")
	Do $$$AssertEquals(..SortedKeys(snapshot), "eventLog,failures,format,items,source,trace", "its snapshot has the shape of the reader snapshot")
	Do $$$AssertEquals(snapshot.format, "ocutalon.readerSnapshot/1", "of that format")
	Do $$$AssertEquals(snapshot.failures.%Size(), 2, "two failures for the two keys")
	If snapshot.failures.%Size() = 2 {
		Set failure = snapshot.failures.%Get(0)
		Do $$$AssertEquals(failure.headerId_"|"_failure.targetConfigName_"|"_failure.bodyClass, $Piece(ids, ",", 1)_"|OrdersFromPartner|OcuTalon.Demo.Orders.PartnerOrder", "the first is the first key's header")
		Do $$$AssertEquals(failure.body.OrderDate_"|"_(failure.body.OrderNumber '= ""), "10/16/2026|1", "its body holds the stored properties")
		Do $$$AssertTrue(failure.error [ "The order date was not in the expected format", "its error text is the log text: "_$Extract(failure.error, 1, 120))
		Do $$$AssertEquals(snapshot.failures.%Get(1).headerId, $Piece(ids, ",", 2), "the second is the second key's")
	}
	Do $$$AssertTrue(snapshot.eventLog.%Size() > 0, "the event log holds the rows of their sessions")
	Do $$$AssertEquals(snapshot.items.%Size()_"|"_snapshot.items.%Get(0).name, "1|OrdersFromPartner", "items holds the named item only")
	Do $$$AssertTrue(snapshot.trace.%Size() > 0, "the trace is the first failure's session")
	Do $$$AssertEquals($ClassMethod(..#PACK, "Read", incident, 3, .three), "read", "Read reads the incident's group")
	Do $$$AssertEquals(three.failures.%Size(), 3, "three failures for a maximum of three")
	If three.failures.%Size() = 3 Do $$$AssertEquals(three.failures.%Get(0).headerId_","_three.failures.%Get(1).headerId_","_three.failures.%Get(2).headerId, $Piece(ids, ",", 1, 3), "the oldest held keys first")
	Do $$$AssertEquals($ClassMethod(..#PACK, "Read", incident, 1, .one), "read", "Read reads one failure")
	Do $$$AssertEquals(one.failures.%Size(), 1, "for a maximum of one")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", incident, .pack), "the pack is built from the incident")
	If '$IsObject($Get(pack)) Quit
	Do $$$AssertEquals(..SortedKeys(pack), "count,errorPattern,firstAt,format,item,lastAt,namespace,production,sample,settings,trace", "it has the fields of the shape")
	Do $$$AssertEquals(pack.count_"|"_pack.firstAt_"|"_pack.lastAt_"|"_pack.item, "5|"_incident.FirstAt_"|"_incident.LastAt_"|OrdersFromPartner", "the count is the NoticeCount, the times and the item are the rows'")
	Do $$$AssertEquals(pack.sample.headerId_"|"_pack.sample.error_"|"_pack.sample.body.OrderDate, $Piece(ids, ",", 1)_"|"_..#ORDERDATETEXT_"|10/16/2026", "the sample is the oldest held header, with its sentence and its body")
	Do $$$AssertEquals(pack.settings.%ToJSON(), "{""TargetConfigName"":""OrdersToWarehouse""}", "the settings are the item's own")
	Do $$$AssertTrue((pack.trace.%Size() > 0) && (pack.trace.%Size() '> 20), "the trace holds the sample's session headers, at most 20")
}

Method TestUnreadable()
{
	If '..Ready() Quit
	Set owner = ..Session("unread")
	Set ids = "1,2,3"
	Set home = $Namespace
	For each = $ListBuild(home, ..#ORDERSPRODUCTION), $ListBuild("ZZNONE", ..#ORDERSPRODUCTION), $ListBuild(..#ORDERS, "Zz.Other") {
		Set namespace = $List(each, 1)
		Set production = $List(each, 2)
		Set label = production_" in "_namespace
		Set incident = ..Fixture(owner, ids, namespace, production)
		Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(namespace, production, "OrdersFromPartner", "h1", .snapshot)
		Do $$$AssertEquals(outcome, $Select(namespace = ..#ORDERS: "not_current", 1: "unreadable"), label_": the outcome of Evidence")
		Do $$$AssertEquals(snapshot.failures.%Size() + snapshot.items.%Size() + snapshot.trace.%Size(), 0, label_": nothing was read")
		Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", incident, .pack), label_": the pack is built")
		If '$IsObject($Get(pack)) Continue
		Do $$$AssertEquals(..SortedKeys(pack), "count,errorPattern,firstAt,format,item,lastAt,namespace,production", label_": it has the counts and the pattern and no sample, settings or trace")
		Do $$$AssertEquals(pack.count_"|"_pack.item, "3|OrdersFromPartner", label_": with the count and the item")
	}
}

Method TestCredentialsLeftOut()
{
	Set snapshot = ..Recorded()
	If '$IsObject(snapshot) Quit
	Set settings = snapshot.items.%Get(1).settings
	Do settings.%Set("Credentials", "user:secret")
	Do settings.%Set("SMTPPassword", "hunter2")
	Do settings.%Set("BotToken", "123456:abc")
	Do settings.%Set("ApiKey", "k-1")
	Do settings.%Set("ClientSecret", "cs-1")
	Do settings.%Set("SSLPassphrase", "pp-1")
	Do settings.%Set("Passwd", "pw-1")
	Do settings.%Set("AuthHeader", "ah-1")
	Do settings.%Set("BearerValue", "bv-1")
	Do settings.%Set("SessionCookie", "sc-1")
	Do settings.%Set("XCOOKIEJAR", "xc-1")
	Do $$$AssertEquals(snapshot.items.%Get(1).name, "OrdersFromPartner", "the item that gets the settings is the failing one")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", snapshot, .pack), "the pack is built")
	If '$IsObject($Get(pack)) Quit
	Do $$$AssertEquals(..SortedKeys(pack.settings), "TargetConfigName", "only TargetConfigName reaches the pack")
	Do $$$AssertTrue(pack.%ToJSON() '[ "hunter2", "and no secret value is in it")
	Do $$$AssertTrue((pack.%ToJSON() '[ "bv-1") && (pack.%ToJSON() '[ "sc-1") && (pack.%ToJSON() '[ "xc-1"), "nor the value of a setting whose name holds bearer or cookie, in any case")
	Set rule = "OcuTalon.Watch.Reader"
	Set kept = ""
	For name = "Credentials", "SMTPPassword", "BotToken", "ApiKey", "TargetConfigName", "apikey", "MyPassWord", "TOKENS", "ClientSecret", "SSLPassphrase", "Passwd", "AuthHeader", "Credential", "BearerValue", "SessionCookie", "XCOOKIEJAR", "bearer", "Cookie" {
		If '$ClassMethod(rule, "CredentialName", name) Set kept = kept _ $Select(kept = "": "", 1: ",") _ name
	}
	Do $$$AssertEquals(kept, "TargetConfigName", "the name rule of Reader keeps only that name, in any case")
}

Method TestRedaction()
{
	Set snapshot = ..Recorded()
	If '$IsObject(snapshot) Quit
	Set secret = "sk-"_"ant-api03-ABCDEFGHIJKLMNOPQRSTUV"
	Set mark = ##class(OcuTalon.Bridge.Redact).#REDACTED
	Set first = snapshot.failures.%Get(0)
	Do first.body.%Set("OrderNumber", secret)
	Do first.body.%Set("Notes", ["see", (secret)])
	Do first.body.%Set("Password", "hunter2")
	Set first.error = "ERROR #5001: The partner key "_secret_" was refused."_$Char(13, 10)_"  > ERROR #5001: again"
	Do snapshot.items.%Get(1).settings.%Set("Endpoint", secret)
	Do snapshot.trace.%Get(0).%Set("sourceConfigName", secret)
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", snapshot, .pack), "the pack is built")
	If '$IsObject($Get(pack)) Quit
	Do $$$AssertEquals(pack.sample.body.OrderNumber, mark, "a body value goes through the redactor")
	Do $$$AssertEquals(pack.sample.body.Password, mark, "and a body property named Password is redacted by the redactor's key rule")
	Do $$$AssertEquals(pack.sample.body.Notes.%Get(1), mark, "and so is a value inside an array of the body")
	Do $$$AssertEquals(pack.settings.Endpoint, mark, "so does a value of a setting that is not a credential")
	Do $$$AssertEquals(pack.trace.%Get(0).sourceConfigName, mark, "and a trace entry")
	Do $$$AssertEquals(pack.sample.error, "The partner key "_mark_" was refused.", "and the sentence of an error text: "_pack.sample.error)
	Do $$$AssertTrue(pack.%ToJSON() '[ "ABCDEFGHIJ", "no part of the secret is in the pack")
}

Method TestLogKeys()
{
	If '..Ready() Quit
	Set owner = ..Session("logkey")
	Set secret = "sk-"_"ant-api03-ABCDEFGHIJKLMNOPQRSTUV"
	Set mark = ##class(OcuTalon.Bridge.Redact).#REDACTED
	Set id = ..FixtureLog("", "", "OrdersFromPartner", "The order failed: the key "_secret_" was refused")
	Do $$$AssertTrue(id '= "", "a log row is made")
	If id = "" Quit
	Set incident = ..Fixture(owner, id, , , "l")
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "l"_id, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads a log key")
	Do $$$AssertEquals(snapshot.failures.%Size()_"|"_snapshot.eventLog.%Size(), "0|1", "it gives the row as an event-log row and no failure")
	If snapshot.eventLog.%Size() = 1 Do $$$AssertEquals(snapshot.eventLog.%Get(0).id, id, "the row of the key")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", incident, .pack), "the pack is built from the incident")
	If $IsObject($Get(pack)) {
		Do $$$AssertEquals(pack.sample.logRef_"|"_pack.sample.bodyClass, "1|", "its sample is the log row, by its position in the event log (logRef), with no body class")
		Do $$$AssertEquals(pack.sample.%IsDefined("logId"), 0, "and no log row id")
		Do $$$AssertTrue(pack.%ToJSON() '[ "ABCDEFGHIJ", "and the secret of its text is not in the pack")
	}
	Do ..Begin(owner, incident.Ref, "untrusted")
	Set result = $ClassMethod(..#TOOLS, "ReadFailedMessages")
	Do $$$AssertEquals(result.count_"|"_result.items.%Size(), "1|1", "read_failed_messages gives the log row as the failed message")
	If result.items.%Size() = 1 {
		Do $$$AssertEquals(result.items.%Get(0).logRef, 1, "with its logRef, the position in the event log")
		Do $$$AssertEquals(result.items.%Get(0).%IsDefined("logId"), 0, "and no log row id")
		Do $$$AssertTrue(result.items.%Get(0).error '[ "ABCDEFGHIJ", "and its text redacted")
	}
	Set result = $ClassMethod(..#TOOLS, "ReadEventLog")
	Do $$$AssertEquals(result.items.%Size(), 1, "read_event_log gives the row")
	If result.items.%Size() = 1 Do $$$AssertEquals(result.items.%Get(0).logRef_"|"_result.items.%Get(0).%IsDefined("logId"), "1|0", "as logRef 1, the same as read_failed_messages gave, and with no log row id")
	If result.items.%Size() = 1 Do $$$AssertTrue((result.items.%Get(0).text [ mark) && (result.items.%Get(0).text '[ "ABCDEFGHIJ"), "with its text redacted: "_result.items.%Get(0).text)
}

Method TestMultiLineError()
{
	If '..Ready() Quit
	Set owner = ..Session("multiline")
	Set header = ..FixtureHeader({})
	Do $$$AssertTrue(header '= "", "a failed header is made")
	If header = "" Quit
	Do $$$AssertTrue(..FixtureLog(header, header, "zzPollerTarget", "ERROR #5001: The first line of the header's error."_$Char(13, 10)_"The second line.") '= "", "with an error text of two lines")
	Set log = ..FixtureLog("", "", "OrdersFromPartner", "The first line of the log row."_$Char(10)_"The second line.")
	Do $$$AssertTrue(log '= "", "and a log row of two lines")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", ..Fixture(owner, header), .pack), "the pack of the header is built")
	If $IsObject($Get(pack)) Do $$$AssertEquals(pack.sample.error, "The first line of the header's error.", "its error is the sentence of the first line")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", ..Fixture(owner, log, , , "l"), .pack), "the pack of the log row is built")
	If $IsObject($Get(pack)) Do $$$AssertEquals(pack.sample.error, "The first line of the log row.", "its error is the sentence of the first line too")
}

Method TestEventLogCapped()
{
	If '..Ready() Quit
	Set owner = ..Session("logcap")
	Set header = ..FixtureHeader({})
	Do $$$AssertTrue(header '= "", "a failed header is made")
	If header = "" Quit
	Set made = 0
	For i = 1:1:105 Set made = made + (..FixtureLog(header, $Select(i = 1: header, 1: ""), "zzPollerTarget", "Log row "_i_" of the session.") '= "")
	Do $$$AssertEquals(made, 105, "105 log rows of its session are made")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", "h"_header, .snapshot), "read", "Evidence reads the header")
	Do $$$AssertEquals(snapshot.eventLog.%Size(), ##class(OcuTalon.Watch.Reader).#LOGMAX, "its event log holds Reader LOGMAX (100) rows")
	Set incident = ..Fixture(owner, header)
	Do ..Begin(owner, incident.Ref, "untrusted")
	Set result = $ClassMethod(..#TOOLS, "ReadEventLog")
	Do $$$AssertEquals(result.items.%Size(), $Parameter(..#PACK, "MAXLOG"), "read_event_log gives EvidencePack MAXLOG (20) rows")
	Set refs = ""
	Set expected = ""
	For i = 0:1:result.items.%Size() - 1 {
		Set refs = refs_","_result.items.%Get(i).logRef
		Set expected = expected_","_(i + 1)
	}
	Do $$$AssertEquals(refs, expected, "the rows carry logRef 1 to n, each its position in the event log (DW-264)")
}

Method TestReaderDropsCredentialSettings()
{
	If '..Ready() Quit
	Set before = ..DefinedSettings()
	Do $$$AssertTrue(before '[ "Credentials", "the definition holds no fixture setting before the test: "_before)
	Set ..SettingsAdded = 1
	Do $$$AssertStatusOK(..FixtureSettings(1), "the fixture settings are added to the definition of OrdersFromPartner")
	Set held = ..DefinedSettings()
	Do $$$AssertTrue((held [ "Credentials") && (held [ "SMTPPassword") && (held [ "BotToken") && (held [ "ApiKey") && (held [ "ZzFixtureNote"), "the definition holds all five, so that the reader has something to leave out: "_held)
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "", .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the Orders production")
	Do $$$AssertEquals(snapshot.items.%Size(), 1, "its items hold the named item")
	If snapshot.items.%Size() = 1 {
		Set settings = snapshot.items.%Get(0).settings
		Do $$$AssertEquals(..SortedKeys(settings), "TargetConfigName,ZzFixtureNote", "only the settings that are no credentials leave Reader.Evidence")
		Do $$$AssertEquals(settings.ZzFixtureNote, ..#FIXTUREVALUE, "and keep their values")
	}
	Set text = snapshot.%ToJSON()
	Set leaked = 0
	For name = "Credentials", "SMTPPassword", "BotToken", "ApiKey" {
		If text [ ("""" _ name _ """") Set leaked = leaked + 1
	}
	Do $$$AssertEquals(leaked, 0, "no credential name is anywhere in the snapshot")
	Set ..SettingsAdded = 0
	Do $$$AssertStatusOK(..FixtureSettings(0), "the fixture settings are taken out again")
	Do $$$AssertEquals(..DefinedSettings(), before, "the definition holds the settings it held before")
}

Method TestTraceCapped()
{
	If '..Ready() Quit
	Set owner = ..Session("tracecap")
	Set first = ..FixtureHeader({})
	Do $$$AssertTrue(first '= "", "a failed header is made")
	If first = "" Quit
	For i = 1:1:24 Do $$$AssertTrue(..FixtureHeader({"SessionId": (first)}) '= "", "header "_(i + 1)_" of its session is made")
	Set cap = ##class(OcuTalon.Watch.Reader).#TRACEMAX
	Do $$$AssertEquals(cap, 20, "the cap of the trace is 20")
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", "h"_first, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the header")
	Do $$$AssertEquals(snapshot.trace.%Size(), cap, "a session of 25 headers gives a trace of 20 from Reader.Evidence")
	Set incident = ..Fixture(owner, first)
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", incident, .live), "the live pack is built")
	If $IsObject($Get(live)) Do $$$AssertEquals(live.trace.%Size(), cap, "and its trace holds 20 entries")
	Set recorded = ..Recorded()
	If '$IsObject(recorded) Quit
	Set entry = recorded.trace.%Get(0).%ToJSON()
	For i = 1:1:24 Do recorded.trace.%Push({}.%FromJSON(entry))
	Do $$$AssertEquals(recorded.trace.%Size(), 25, "a recorded snapshot with 25 trace entries")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", recorded, .pack), "the pack is built from it")
	If $IsObject($Get(pack)) Do $$$AssertEquals(pack.trace.%Size(), cap, "its trace holds 20 entries")
}

Method TestToolsReadTheIncident()
{
	If '..Ready() Quit
	Set owner = ..Session("tools")
	Set other = ..Session("toolsother")
	Set ids = ..Failing()
	If ids = "" Quit
	Set incident = ..Fixture(owner, ids)
	Do ..Begin(owner, incident.Ref, "untrusted")
	Set result = $ClassMethod(..#TOOLS, "ReadFailedMessages")
	Do $$$AssertTrue($IsObject(result) && result.%IsA("%Library.DynamicObject"), "read_failed_messages returns a dynamic object")
	Do $$$AssertEquals(result.count_"|"_result.items.%Size(), "5|5", "the count of the incident and at most five items")
	If result.items.%Size() = 5 {
		Set item = result.items.%Get(0)
		Do $$$AssertEquals(..SortedKeys(item), "at,body,bodyClass,error,headerId,item", "an item has its fields")
		Do $$$AssertEquals(item.headerId_"|"_item.item_"|"_item.error_"|"_item.body.OrderDate, $Piece(ids, ",", 1)_"|OrdersFromPartner|"_..#ORDERDATETEXT_"|10/16/2026", "the oldest failed order, with its sentence and body")
	}
	Set result = $ClassMethod(..#TOOLS, "ReadEventLog")
	Do $$$AssertTrue(result.items.%Size() > 0, "read_event_log gives the log rows of the sessions")
	If result.items.%Size() > 0 Do $$$AssertEquals(..SortedKeys(result.items.%Get(0)), "at,item,logRef,text,type", "each with its fields, a logRef and no log row id")
	If result.items.%Size() > 0 Do $$$AssertEquals(result.items.%Get(0).logRef, 1, "the first row is logRef 1, its position in the event log of the read")
	Do $$$AssertTrue(result.items.%Size() '> 20, "at most twenty")
	Set result = $ClassMethod(..#TOOLS, "ReadItemSettings")
	Do $$$AssertEquals(result.item_"|"_result.settings.%ToJSON(), "OrdersFromPartner|{""TargetConfigName"":""OrdersToWarehouse""}", "read_item_settings gives the failing item and its settings")

	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..AssertEmpty("no context")
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef(), "untrusted")
	Do ..AssertEmpty("an unknown ItemId")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin(other, incident.Ref, "untrusted")
	Do ..AssertEmpty("another owner")
}

/// Asserts that the three tools give {"items":[]}.
Method AssertEmpty(label As %String) [ Private ]
{
	For tool = "ReadFailedMessages", "ReadEventLog", "ReadItemSettings" {
		Set result = $ClassMethod(..#TOOLS, tool)
		Do $$$AssertEquals($Select($IsObject(result): result.%ToJSON(), 1: result), "{""items"":[]}", label_": "_tool_" gives {""items"":[]}")
	}
}

}
