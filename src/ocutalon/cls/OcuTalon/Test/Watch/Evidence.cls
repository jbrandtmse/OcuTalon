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
///   - TestCredentialsLeftOut (row Credentials): the settings Credentials, SMTPPassword, BotToken, ApiKey and TargetConfigName of a snapshot item reach the pack as
///     TargetConfigName alone, and Reader.CredentialName keeps only that name;
///   - TestRedaction: a secret planted in a snapshot's body value, error text, non-credential setting value and trace entry is replaced by the redactor's mark
///     in the pack;
///   - TestLogKeys: an incident whose group holds a log key gives the log row as the sample and as the failed message, the tools redact its text, and
///     Evidence reads the row by its id;
///   - TestToolsReadTheIncident (rows Tools in scope and out of scope): in the context of the incident and its owner the three tools give at most five failed
///     messages with their ids, sentence and body, the sessions' log rows and the item's settings; with no context, another ItemId or another owner each gives
///     {"items":[]}.
Class OcuTalon.Test.Watch.Evidence Extends OcuTalon.Test.Watch.Case
{

Parameter PACK = "OcuTalon.Watch.EvidencePack";

Parameter SNAPSHOT = "/opt/ocutalon/eval/orders-date-format/snapshot.json";

Parameter TOOLS = "OcuTalon.Tools.WatchReads";

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
	Do $$$AssertEquals(snapshot.items.%Get(1).name, "OrdersFromPartner", "the item that gets the settings is the failing one")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", snapshot, .pack), "the pack is built")
	If '$IsObject($Get(pack)) Quit
	Do $$$AssertEquals(..SortedKeys(pack.settings), "TargetConfigName", "only TargetConfigName reaches the pack")
	Do $$$AssertTrue(pack.%ToJSON() '[ "hunter2", "and no secret value is in it")
	Set rule = "OcuTalon.Watch.Reader"
	Set kept = ""
	For name = "Credentials", "SMTPPassword", "BotToken", "ApiKey", "TargetConfigName", "apikey", "MyPassWord", "TOKENS" {
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
	Set first.error = first.error_" Bearer "_$Piece(secret, "-", 3)
	Do snapshot.items.%Get(1).settings.%Set("Endpoint", secret)
	Do snapshot.trace.%Get(0).%Set("sourceConfigName", secret)
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", snapshot, .pack), "the pack is built")
	If '$IsObject($Get(pack)) Quit
	Do $$$AssertEquals(pack.sample.body.OrderNumber, mark, "a body value goes through the redactor")
	Do $$$AssertEquals(pack.settings.Endpoint, mark, "so does a value of a setting that is not a credential")
	Do $$$AssertEquals(pack.trace.%Get(0).sourceConfigName, mark, "and a trace entry")
	Do $$$AssertTrue(pack.sample.error '[ $Piece(secret, "-", 3), "and an error text: "_pack.sample.error)
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
		Do $$$AssertEquals(pack.sample.logId_"|"_pack.sample.bodyClass, id_"|", "its sample is the log row, with no body class")
		Do $$$AssertTrue(pack.%ToJSON() '[ "ABCDEFGHIJ", "and the secret of its text is not in the pack")
	}
	Do ..Begin(owner, incident.Ref, "untrusted")
	Set result = $ClassMethod(..#TOOLS, "ReadFailedMessages")
	Do $$$AssertEquals(result.count_"|"_result.items.%Size(), "1|1", "read_failed_messages gives the log row as the failed message")
	If result.items.%Size() = 1 {
		Do $$$AssertEquals(result.items.%Get(0).logId, id, "with its id")
		Do $$$AssertTrue(result.items.%Get(0).error '[ "ABCDEFGHIJ", "and its text redacted")
	}
	Set result = $ClassMethod(..#TOOLS, "ReadEventLog")
	Do $$$AssertEquals(result.items.%Size(), 1, "read_event_log gives the row")
	If result.items.%Size() = 1 Do $$$AssertTrue((result.items.%Get(0).text [ mark) && (result.items.%Get(0).text '[ "ABCDEFGHIJ"), "with its text redacted: "_result.items.%Get(0).text)
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
	If result.items.%Size() > 0 Do $$$AssertEquals(..SortedKeys(result.items.%Get(0)), "at,item,logId,text,type", "each with its fields")
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
