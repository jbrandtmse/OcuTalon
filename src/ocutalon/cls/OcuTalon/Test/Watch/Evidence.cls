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
///     {"items":[]};
///   - TestInFlightHeader (DW-1205, DW-494; AC 4, AC 5): a Completed header that a (fake) job of OCUORDERS holds as its active message (Ensemble.inc's EnsActiveMessage) is given by
///     Reader.Evidence with inFlight 1, a JSON boolean, and one that is not held with inFlight 0; Fix.Executor Read carries inFlight and Tally counts the held copy as running (completed 0,
///     failed again 1, running 1); once the entry is killed the copy is completed (completed 1, failed again 1, running 0);
///   - TestInFlightEntryReadFails (DW-1205, DW-494; condition 2): when the read of the active-message entries fails (the reader's test seam ^||OcuTalonFlightSeam, a status number that
///     stands for the first read's status), the second read of the status decides: a seeded Error (8) against a Completed row is in flight, and Executor Read and Tally count the copy
///     as running, not completed; a seeded status equal to the row's is not in flight; a Completed header that nothing holds is not in flight;
///   - TestBusinessProcessHoldsACopy (DW-1410; AC 1): a Completed header whose business process instance is not complete (an Ens.BusinessProcess row of its session whose
///     %PrimaryRequestHeader it is and whose %IsCompleted is 0) is given with inFlight 1, a JSON boolean; an Error header is final whatever its instance; Fix.Executor Read carries
///     it and Tally counts the copy as running; a Completed copy whose session is another header's (a resent copy keeps its original's) is held by its own unfinished instance;
///     once the instance is complete, or gone, it is completed, and another header's unfinished instance in the session does not hold it;
///   - TestReplyInHandHoldsACopy (DW-1410; AC 2): a Completed header with no instance is in flight while a (fake) job's active message is a response (Type 2) of its session addressed
///     to its target, and is not while that message is a reply of another session, a reply of its session addressed to another target, a request of its session, or none;
///   - TestBusinessProcessReadFails (DW-1410; AC 3): when the read of the instances or of the replies fails (the reader's test seam ^||OcuTalonFlightSeam("process")), Evidence still
///     reads and the Completed header is in flight, and Executor Read and Tally count it as running, never completed;
///   - TestBusinessProcessOfAnyKindHoldsACopy (DW-1410, QA; the extent is shared): an unfinished instance of a BPL business process (Ens.BusinessProcessBPL) and one of a
///     hand-coded subclass (EnsLib.MsgRouter.RoutingEngine) hold a Completed header as a bare Ens.BusinessProcess row does, and a completed one does not;
///   - TestReadOrderStatusInstanceReplyEntry (DW-1410, QA; AC 5): the data-only seams show the order of the reads: the block of the instances and the replies runs only for a header
///     whose first read is Completed, and before the entry check, which runs only when that block did not hold the header (a held header leaves the status seam unread);
///   - TestReplyInHandJudgesEachCopy (DW-1410, QA; matrix 10): in one read of four Completed copies, several jobs' replies and an entry that names no header, the copies of the session
///     whose reply is in hand are held (a sibling copy of the same session and target too: the approved one-pass false hold), the others are not, and the hold ends when the job
///     lets go of the reply; an entry whose header cannot be read holds nothing.
Class OcuTalon.Test.Watch.Evidence Extends OcuTalon.Test.Watch.Case [ DependsOn = OcuTalon.Test.Watch.OrdersDefinition ]
{

Parameter PACK = "OcuTalon.Watch.EvidencePack";

Parameter SNAPSHOT = "/opt/ocutalon/eval/orders-date-format/snapshot.json";

Parameter TOOLS = "OcuTalon.Tools.WatchReads";

/// The plain fixture setting that TestReaderDropsCredentialSettings adds, beside the four credential settings of OrdersDefinition, to the failing item's definition.
Parameter NOTE = {##class(OcuTalon.Test.Watch.OrdersDefinition).#NOTE};

/// The value of every fixture setting.
Parameter FIXTUREVALUE = "fixture-value-9d31";

/// 1 while the fixture settings may be in the definition of the Orders production in OCUORDERS; OnAfterOneTest takes them out.
Property SettingsAdded As %Boolean [ InitialExpression = 0 ];

/// The key of the fake active-message entry in OCUORDERS that TestInFlightHeader sets; "" when there is none. A test that needs several entries adds ":1" to ":4" to it.
/// OnAfterOneTest kills them all.
Property EntryKey As %String;

/// The ids, comma separated, of the Ens.BusinessProcess rows that FixtureProcess made in OCUORDERS and that are still there. OnAfterOneTest deletes them.
Property Processes As %String;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Kill ^||OcuTalonFlightSeam
	If ..Processes '= "" {
		Do ..DropProcesses(..Processes)
		Set ..Processes = ""
	}
	If ..EntryKey '= "" {
		For n = 0:1:4 Do ..KillEntry(..EntryKey_$Select(n: ":"_n, 1: ""))
		Set ..EntryKey = ""
	}
	If ..SettingsAdded {
		Set ..SettingsAdded = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Watch.OrdersDefinition).Put(0))
	}
	Quit sc
}

/// Sets the active-message entry of a job of the key to the header id, in OCUORDERS. The key names no system and no job of IRIS, so no job of the production reads it as its own.
ClassMethod SetEntry(key As %String, id As %Integer) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set $$$EnsActiveMessage(key) = id
}

/// Gives the fixture header another TargetConfigName, in OCUORDERS.
Method Retarget(id As %Integer, target As %String) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Ens.MessageHeader SET TargetConfigName = ? WHERE ID = ?", target, id)
	Do $$$AssertEquals(result.%SQLCODE, 0, "the header "_id_" is addressed to "_target)
}

/// Kills the active-message entry of the key, in OCUORDERS.
ClassMethod KillEntry(key As %String) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Kill $$$EnsActiveMessage(key)
}

/// Saves a bare row of Ens.BusinessProcess (or of the subclass named, which shares its extent) in OCUORDERS for the header (its %PrimaryRequestHeader) in the session, with %IsCompleted as given, and remembers its id for
/// OnAfterOneTest. Its id is given back, "" when it could not be saved.
Method FixtureProcess(header As %Integer, session As %Integer, completed As %Boolean = 0, class As %String = "Ens.BusinessProcess") As %String [ Private ]
{
	Set id = ..MakeProcess(header, session, completed, class)
	If id '= "" Set ..Processes = ..Processes_$Select(..Processes = "": "", 1: ",")_id
	Quit id
}

ClassMethod MakeProcess(header As %Integer, session As %Integer, completed As %Boolean, class As %String = "Ens.BusinessProcess") As %String [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set process = $ClassMethod(class, "%New", "zzPollerTarget")
	If '$IsObject(process) Quit ""
	Do process.%PrimaryRequestHeaderSetObjectId(header)
	Set process.%SessionId = session
	Set process.%IsCompleted = completed
	Quit $Select($$$ISOK(process.%Save()): process.%Id(), 1: "")
}

/// Sets %IsCompleted of the business process row in OCUORDERS to 1.
ClassMethod CompleteProcess(id As %String) As %Boolean [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Ens.BusinessProcess SET %IsCompleted = 1 WHERE ID = ?", id)
	Quit result.%SQLCODE = 0
}

/// Deletes the business process row from OCUORDERS (the ids that are not there are skipped).
ClassMethod DropProcess(id As %String) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens.BusinessProcess WHERE ID = ?", id)
}

/// Deletes the business process rows of the comma-separated ids.
ClassMethod DropProcesses(ids As %String) [ Private ]
{
	For i = 1:1:$Length(ids, ",") Do ..DropProcess($Piece(ids, ",", i))
}

/// What Reader.Evidence gives for the header, as status|inFlight, or "none" when the read gives no failure for it.
Method ReadOf(id As %Integer) As %String [ Private ]
{
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", "h"_id, .snapshot)
	Set failure = ..FailureOf(snapshot, id)
	Quit $Select((outcome = "read") && $IsObject(failure): failure.status_"|"_failure.inFlight, 1: "none")
}

/// The failure of the header in a reader snapshot, "" when there is none.
ClassMethod FailureOf(snapshot As %DynamicObject, id As %Integer) As %DynamicObject [ Private ]
{
	Set found = ""
	If '$IsObject($Get(snapshot)) || '$IsObject(snapshot.failures) Quit found
	For i = 0:1:snapshot.failures.%Size() - 1 {
		If snapshot.failures.%Get(i).headerId = id {
			Set found = snapshot.failures.%Get(i)
			Quit
		}
	}
	Quit found
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
	Set id2 = ..FixtureLog("", "", "OrdersFromPartner", "The order failed again")
	Do $$$AssertTrue((id '= "") && (id2 '= ""), "two log rows are made")
	If (id = "") || (id2 = "") Quit
	Set incident = ..Fixture(owner, id_","_id2, , , "l")
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "l"_id, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads a log key")
	Do $$$AssertEquals(snapshot.failures.%Size()_"|"_snapshot.eventLog.%Size(), "0|1", "it gives the row as an event-log row and no failure")
	If snapshot.eventLog.%Size() = 1 Do $$$AssertEquals(snapshot.eventLog.%Get(0).id, id, "the row of the key")
	Do $$$AssertStatusOK($ClassMethod(..#PACK, "Build", incident, .pack), "the pack is built from the incident")
	If $IsObject($Get(pack)) {
		Do $$$AssertEquals(pack.sample.logRef_"|"_pack.sample.bodyClass, "1|", "its sample is the log row, by its position in the event log (logRef), with no body class")
		Do $$$AssertEquals(pack.sample.%IsDefined("logId"), 0, "and no log row id")
		Do $$$AssertTrue(pack.%ToJSON() '[ """logId""", "nor anywhere in the pack")
		Do $$$AssertTrue(pack.%ToJSON() '[ "ABCDEFGHIJ", "and the secret of its text is not in the pack")
	}
	Do ..Begin(owner, incident.Ref, "untrusted")
	Set result = $ClassMethod(..#TOOLS, "ReadFailedMessages")
	Do $$$AssertEquals(result.count_"|"_result.items.%Size(), "2|2", "read_failed_messages gives the two log rows as the failed messages")
	If result.items.%Size() = 2 {
		Do $$$AssertEquals(result.items.%Get(0).logRef_","_result.items.%Get(1).logRef, "1,2", "with their logRefs 1 and 2, their positions in the event log")
		Do $$$AssertEquals(result.items.%Get(0).%IsDefined("logId"), 0, "and no log row id")
		Do $$$AssertTrue(result.items.%Get(0).error '[ "ABCDEFGHIJ", "and its text redacted")
	}
	Do $$$AssertTrue(result.%ToJSON() '[ """logId""", "no log row id anywhere in the answer")
	Set result = $ClassMethod(..#TOOLS, "ReadEventLog")
	Do $$$AssertEquals(result.items.%Size(), 2, "read_event_log gives the two rows")
	If result.items.%Size() = 2 Do $$$AssertEquals(result.items.%Get(0).logRef_","_result.items.%Get(1).logRef_"|"_result.items.%Get(0).%IsDefined("logId"), "1,2|0", "as logRefs 1 and 2, the same as read_failed_messages gave, and with no log row id")
	If result.items.%Size() = 2 Do $$$AssertTrue((result.items.%Get(0).text [ mark) && (result.items.%Get(0).text '[ "ABCDEFGHIJ"), "with the first row's text redacted: "_result.items.%Get(0).text)
	Do $$$AssertTrue(result.%ToJSON() '[ """logId""", "and no log row id anywhere in that answer")
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
	Set before = ##class(OcuTalon.Test.Watch.OrdersDefinition).Defined()
	Do $$$AssertTrue(before '[ "Credentials", "the definition holds no fixture setting before the test: "_before)
	Set ..SettingsAdded = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.OrdersDefinition).Put(1, ..#FIXTUREVALUE, ..#FIXTUREVALUE), "the fixture settings are added to the definition of OrdersFromPartner")
	Set held = ##class(OcuTalon.Test.Watch.OrdersDefinition).Defined()
	Do $$$AssertTrue((held [ "Credentials") && (held [ "SMTPPassword") && (held [ "BotToken") && (held [ "ApiKey") && (held [ "ZzFixtureNote"), "the definition holds all five, so that the reader has something to leave out: "_held)
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "", .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the Orders production")
	Do $$$AssertEquals(snapshot.items.%Size(), 1, "its items hold the named item")
	If snapshot.items.%Size() = 1 {
		Set settings = snapshot.items.%Get(0).settings
		Do $$$AssertEquals(..SortedKeys(settings), "TargetConfigName,"_..#NOTE, "only the settings that are no credentials leave Reader.Evidence")
		Do $$$AssertEquals(settings.%Get(..#NOTE), ..#FIXTUREVALUE, "and keep their values")
	}
	Set text = snapshot.%ToJSON()
	Set leaked = 0
	For name = "Credentials", "SMTPPassword", "BotToken", "ApiKey" {
		If text [ ("""" _ name _ """") Set leaked = leaked + 1
	}
	Do $$$AssertEquals(leaked, 0, "no credential name is anywhere in the snapshot")
	Set ..SettingsAdded = 0
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.OrdersDefinition).Put(0), "the fixture settings are taken out again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.OrdersDefinition).Defined(), before, "the definition holds the settings it held before")
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

Method TestInFlightHeader()
{
	If '..Ready() Quit
	Set owner = ..Session("inflight")
	Set held = ..FixtureHeader({"Status": 9})
	Set failed = ..FixtureHeader({})
	Do $$$AssertTrue((held '= "") && (failed '= ""), "a Completed header and an Error header are made")
	If (held = "") || (failed = "") Quit
	Set ..EntryKey = "zzOcuTalonTest:"_$Job
	Do ..SetEntry(..EntryKey, held)
	Set keys = "h"_held_",h"_failed
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", keys, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the two headers")
	Set heldFailure = ..FailureOf(snapshot, held)
	Set failedFailure = ..FailureOf(snapshot, failed)
	Do $$$AssertTrue($IsObject(heldFailure) && $IsObject(failedFailure), "each header has its failure")
	If '$IsObject(heldFailure) || '$IsObject(failedFailure) Quit
	Do $$$AssertEquals(heldFailure.status_"|"_heldFailure.inFlight, "Completed|1", "inFlight 1 while a job holds it")
	Do $$$AssertEquals(heldFailure.%GetTypeOf("inFlight"), "boolean", "inFlight is a JSON boolean")
	Do $$$AssertEquals(failedFailure.status_"|"_failedFailure.inFlight, "Error|0", "a header that no job holds has inFlight 0")
	Do $$$AssertEquals(failedFailure.%GetTypeOf("inFlight"), "boolean", "also a JSON boolean")

	Set incident = ..Fixture(owner, held_","_failed)
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Do run.Copies.Insert(held)
	Do run.Copies.Insert(failed)
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Do $$$AssertEquals(read, "read", "Executor Read reads the copies")
	Do $$$AssertTrue($IsObject(statuses.%Get(held)) && $IsObject(statuses.%Get(failed)), "Read gives both copies")
	If '$IsObject(statuses.%Get(held)) || '$IsObject(statuses.%Get(failed)) Quit
	Do $$$AssertEquals(statuses.%Get(held).inFlight_"|"_statuses.%Get(failed).inFlight, "1|0", "Read carries inFlight")
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, statuses)
	Do $$$AssertEquals(tally.completed_"|"_tally.failedAgain_"|"_tally.running, "0|1|1", "Tally gives completed 0, failed again 1, running 1")

	Do ..KillEntry(..EntryKey)
	Set ..EntryKey = ""
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", keys, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads them again")
	Set heldFailure = ..FailureOf(snapshot, held)
	Do $$$AssertEquals($Select($IsObject(heldFailure): heldFailure.status_"|"_heldFailure.inFlight, 1: "none"), "Completed|0", "inFlight 0 once the job lets go of it")
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, statuses)
	Do $$$AssertEquals(tally.completed_"|"_tally.failedAgain_"|"_tally.running, "1|1|0", "Tally gives completed 1, failed again 1, running 0")
}

Method TestInFlightEntryReadFails()
{
	If '..Ready() Quit
	Set owner = ..Session("entryfails")
	Set quiet = ..FixtureHeader({"Status": 9})
	Set changing = ..FixtureHeader({"Status": 9})
	Do $$$AssertTrue((quiet '= "") && (changing '= ""), "two Completed headers are made")
	If (quiet = "") || (changing = "") Quit

	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", "h"_quiet, .snapshot)
	Set failure = ..FailureOf(snapshot, quiet)
	Do $$$AssertTrue(outcome = "read" && $IsObject(failure), "a Completed header that nothing holds is read")
	Do $$$AssertEquals($Select($IsObject(failure): failure.status_"|"_failure.inFlight, 1: "none"), "Completed|0", "it is not in flight")

	// the read of the active-message entries fails, and the seam stands for a first read that gave Error (8) while the row reads Completed: only the second read can tell
	Set ^||OcuTalonFlightSeam = 8
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", "h"_changing, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence still reads when the read of the entries fails")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam), 0, "the seam ran once")
	Set failure = ..FailureOf(snapshot, changing)
	Do $$$AssertEquals($Select($IsObject(failure): failure.status_"|"_failure.inFlight, 1: "none"), "Completed|1", "a failed read of the entries does not make it done: the second read of the status gives another status, so it is in flight")

	// control: a failed read of the entries whose second read gives the same status is not in flight
	Set ^||OcuTalonFlightSeam = 9
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", "h"_quiet, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the quiet header with the seam set")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam), 0, "the seam ran once again")
	Set failure = ..FailureOf(snapshot, quiet)
	Do $$$AssertEquals($Select($IsObject(failure): failure.status_"|"_failure.inFlight, 1: "none"), "Completed|0", "a failed read of the entries with the same status at the second read is not in flight")

	// the count: with the entry read failing and the status changed, Executor Read and Tally count the copy as running, not completed
	Set incident = ..Fixture(owner, changing)
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Do run.Copies.Insert(changing)
	Set ^||OcuTalonFlightSeam = 8
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Do $$$AssertEquals(read, "read", "Executor Read reads the copy with the seam set")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam), 0, "the seam ran in Read")
	Set entry = $Select(read = "read": statuses.%Get(changing), 1: "")
	Do $$$AssertEquals($Select($IsObject(entry): entry.status_"|"_entry.inFlight, 1: "none"), "Completed|1", "Read carries the copy as Completed and in flight")
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, $Get(statuses))
	Do $$$AssertEquals(tally.completed_"|"_tally.failedAgain_"|"_tally.running, "0|0|1", "Tally counts the copy as running, not completed")
}

Method TestBusinessProcessHoldsACopy()
{
	If '..Ready() Quit
	Set owner = ..Session("bpheld")
	Set held = ..FixtureHeader({"Status": 9})
	Set sibling = ..FixtureHeader({"Status": 9, "SessionId": (held)})
	Set failed = ..FixtureHeader({"Status": 8, "IsError": 1, "ErrorStatus": (..#ORDERDATETEXT)})
	Do $$$AssertTrue((held '= "") && (sibling '= "") && (failed '= ""), "two Completed headers (one in the session of the first) and an Error header are made")
	If (held = "") || (sibling = "") || (failed = "") Quit
	Set heldProcess = ..FixtureProcess(held, held)
	Set siblingProcess = ..FixtureProcess(sibling, held)
	Set failedProcess = ..FixtureProcess(failed, failed)
	Do $$$AssertTrue((heldProcess '= "") && (siblingProcess '= "") && (failedProcess '= ""), "an unfinished business process instance is made for each: the header's, the sibling's in the header's session, and the Error header's")
	If (heldProcess = "") || (siblingProcess = "") || (failedProcess = "") Quit

	Set keys = "h"_held_",h"_failed
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", keys, .snapshot)
	Do $$$AssertEquals(outcome, "read", "Evidence reads the two headers")
	Set heldFailure = ..FailureOf(snapshot, held)
	Set failedFailure = ..FailureOf(snapshot, failed)
	Do $$$AssertTrue($IsObject(heldFailure) && $IsObject(failedFailure), "each header has its failure")
	If '$IsObject(heldFailure) || '$IsObject(failedFailure) Quit
	Do $$$AssertEquals(heldFailure.status_"|"_heldFailure.inFlight, "Completed|1", "a Completed header whose business process is not complete is in flight")
	Do $$$AssertEquals(heldFailure.%GetTypeOf("inFlight"), "boolean", "inFlight is a JSON boolean")
	Do $$$AssertEquals(failedFailure.status_"|"_failedFailure.inFlight, "Error|0", "an Error header is final, whatever its instance")
	Do $$$AssertEquals(..ReadOf(sibling), "Completed|1", "a Completed copy in another header's session (a resent copy keeps its original's) is held by its own unfinished instance")

	Set incident = ..Fixture(owner, held_","_failed)
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Do run.Copies.Insert(held)
	Do run.Copies.Insert(failed)
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Do $$$AssertEquals(read, "read", "Executor Read reads the copies")
	Do $$$AssertTrue($IsObject(statuses.%Get(held)) && $IsObject(statuses.%Get(failed)), "Read gives both copies")
	If '$IsObject(statuses.%Get(held)) || '$IsObject(statuses.%Get(failed)) Quit
	Do $$$AssertEquals(statuses.%Get(held).inFlight_"|"_statuses.%Get(failed).inFlight, "1|0", "Read carries inFlight")
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, statuses)
	Do $$$AssertEquals(tally.completed_"|"_tally.failedAgain_"|"_tally.running, "0|1|1", "Tally gives completed 0, failed again 1, running 1")

	Do $$$AssertTrue(..CompleteProcess(heldProcess), "the header's instance is completed")
	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "a completed instance does not hold it")
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, $Get(statuses))
	Do $$$AssertEquals(tally.completed_"|"_tally.failedAgain_"|"_tally.running, "1|1|0", "Tally gives completed 1, failed again 1, running 0")

	Do ..DropProcess(heldProcess)
	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "another header's unfinished instance in its session does not hold it")
}

Method TestReplyInHandHoldsACopy()
{
	If '..Ready() Quit
	Set held = ..FixtureHeader({"Status": 9})
	Do $$$AssertTrue(held '= "", "a Completed header with no business process instance is made")
	If held = "" Quit
	Set reply = ..FixtureHeader({"Type": 2, "Status": 3, "SessionId": (held)})
	Set otherReply = ..FixtureHeader({"Type": 2, "Status": 3})
	Set request = ..FixtureHeader({"Type": 1, "Status": 3, "SessionId": (held)})
	Set elsewhere = ..FixtureHeader({"Type": 2, "Status": 3, "SessionId": (held)})
	Do $$$AssertTrue((reply '= "") && (otherReply '= "") && (request '= "") && (elsewhere '= ""), "a reply of its session, a reply of a session of its own, a request of its session and a reply of its session to another target are made")
	If (reply = "") || (otherReply = "") || (request = "") || (elsewhere = "") Quit
	Do ..Retarget(elsewhere, "zzElsewhereTarget")
	Set ..EntryKey = "zzOcuTalonTest:"_$Job

	Do ..SetEntry(..EntryKey, reply)
	Do $$$AssertEquals(..ReadOf(held), "Completed|1", "a job that handles a reply of its session to its target holds it")
	Do ..SetEntry(..EntryKey, otherReply)
	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "a reply of another session does not")
	Do ..SetEntry(..EntryKey, request)
	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "a request of its session is not a reply in hand")
	Do ..SetEntry(..EntryKey, elsewhere)
	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "a reply of its session addressed to another target does not")
	Do ..SetEntry(..EntryKey, reply)
	Do ..KillEntry(..EntryKey)
	Set ..EntryKey = ""
	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "once the job lets go of the reply, it is completed")
}

Method TestBusinessProcessReadFails()
{
	If '..Ready() Quit
	Set owner = ..Session("bpfails")
	Set held = ..FixtureHeader({"Status": 9})
	Do $$$AssertTrue(held '= "", "a Completed header with no instance and nothing held is made")
	If held = "" Quit

	Set ^||OcuTalonFlightSeam("process") = 1
	Do $$$AssertEquals(..ReadOf(held), "Completed|1", "a failed read of the business process instances never makes it done: it is in flight")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam("process")), 0, "the seam ran once")

	Set incident = ..Fixture(owner, held)
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Do run.Copies.Insert(held)
	Set ^||OcuTalonFlightSeam("process") = 1
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Do $$$AssertEquals(read, "read", "Executor Read reads the copy with the seam set")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam("process")), 0, "the seam ran in Read")
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, $Get(statuses))
	Do $$$AssertEquals(tally.running_"|"_tally.completed, "1|0", "Tally counts the copy as running, never completed")

	Do $$$AssertEquals(..ReadOf(held), "Completed|0", "without the seam it is completed")
}

/// What Reader.Evidence gives for the headers (ids, comma separated), as status|inFlight for each, comma separated ("none" for one that gives no failure).
Method ReadsOf(ids As %String) As %String [ Private ]
{
	Set keys = ""
	For i = 1:1:$Length(ids, ",") Set keys = keys_$Select(keys = "": "", 1: ",")_"h"_$Piece(ids, ",", i)
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "zzPollerTarget", keys, .snapshot)
	Set out = ""
	For i = 1:1:$Length(ids, ",") {
		Set failure = ..FailureOf(snapshot, $Piece(ids, ",", i))
		Set out = out_$Select(out = "": "", 1: ",")_$Select((outcome = "read") && $IsObject(failure): failure.status_"|"_failure.inFlight, 1: "none")
	}
	Quit out
}

Method TestBusinessProcessOfAnyKindHoldsACopy()
{
	If '..Ready() Quit
	Set bpl = ..FixtureHeader({"Status": 9})
	Set routed = ..FixtureHeader({"Status": 9})
	Set bare = ..FixtureHeader({"Status": 9})
	Do $$$AssertTrue((bpl '= "") && (routed '= "") && (bare '= ""), "three Completed headers are made")
	If (bpl = "") || (routed = "") || (bare = "") Quit
	Set bplProcess = ..FixtureProcess(bpl, bpl, 0, "Ens.BusinessProcessBPL")
	Set routedProcess = ..FixtureProcess(routed, routed, 0, "EnsLib.MsgRouter.RoutingEngine")
	Do $$$AssertTrue((bplProcess '= "") && (routedProcess '= ""), "an unfinished instance of a BPL business process and one of a hand-coded subclass are made")
	If (bplProcess = "") || (routedProcess = "") Quit
	Do $$$AssertEquals(..ReadsOf(bpl_","_routed_","_bare), "Completed|1,Completed|1,Completed|0", "an unfinished instance of a BPL process holds its header, and so does one of a subclass of the extent; a header with no instance is not held")
	Do $$$AssertTrue(..CompleteProcess(bplProcess) && ..CompleteProcess(routedProcess), "both instances are completed")
	Do $$$AssertEquals(..ReadsOf(bpl_","_routed), "Completed|0,Completed|0", "completed instances of either kind do not hold their headers")
}

Method TestReadOrderStatusInstanceReplyEntry()
{
	If '..Ready() Quit
	Set viaProcess = ..FixtureHeader({"Status": 9})
	Set viaReply = ..FixtureHeader({"Status": 9})
	Set quiet = ..FixtureHeader({"Status": 9})
	Set failed = ..FixtureHeader({"Status": 8, "IsError": 1, "ErrorStatus": (..#ORDERDATETEXT)})
	Do $$$AssertTrue((viaProcess '= "") && (viaReply '= "") && (quiet '= "") && (failed '= ""), "three Completed headers and an Error header are made")
	If (viaProcess = "") || (viaReply = "") || (quiet = "") || (failed = "") Quit
	Set reply = ..FixtureHeader({"Type": 2, "Status": 3, "SessionId": (viaReply)})
	Do $$$AssertTrue(reply '= "", "a reply of the second header's session is made")
	If reply = "" Quit
	Set viaProcessInstance = ..FixtureProcess(viaProcess, viaProcess)
	Set failedInstance = ..FixtureProcess(failed, failed)
	Do $$$AssertTrue((viaProcessInstance '= "") && (failedInstance '= ""), "an unfinished instance of the first header and one of the Error header are made")
	If (viaProcessInstance = "") || (failedInstance = "") Quit

	// the entry check runs after the instance: a header that an instance holds is never read for its entry, so the status seam of the entry check stays unread
	Set ^||OcuTalonFlightSeam = 8
	Do $$$AssertEquals(..ReadOf(viaProcess), "Completed|1", "an unfinished instance holds the Completed header")
	Do $$$AssertEquals($Get(^||OcuTalonFlightSeam), 8, "the entry check did not run for a header that the instance held")

	// and after the reply in hand: a header that a reply holds is not read for its entry either
	Set ..EntryKey = "zzOcuTalonTest:"_$Job
	Do ..SetEntry(..EntryKey, reply)
	Do $$$AssertEquals(..ReadOf(viaReply), "Completed|1", "a reply in hand holds the Completed header")
	Do $$$AssertEquals($Get(^||OcuTalonFlightSeam), 8, "the entry check did not run for a header that the reply in hand held")
	Do ..KillEntry(..EntryKey)
	Set ..EntryKey = ""

	// a header that nothing holds does reach the entry check, which takes the seam
	Do $$$AssertEquals(..ReadOf(quiet), "Completed|1", "with nothing holding it, the entry check runs: the seam stands for another first status, so the second read finds it changed")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam), 0, "the entry check took the seam")

	// a failed read of the instances holds the header before the entry check, and the whole seam global is killed only by the entry check
	Set ^||OcuTalonFlightSeam = 8
	Set ^||OcuTalonFlightSeam("process") = 1
	Do $$$AssertEquals(..ReadOf(quiet), "Completed|1", "a failed read of the instances holds the header")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam("process")), 0, "the instance read took its own seam")
	Do $$$AssertEquals($Get(^||OcuTalonFlightSeam), 8, "and the entry check did not run after it")
	Kill ^||OcuTalonFlightSeam

	// the block runs only for a first read of Completed: an Error header with an instance never reads, so its seam stays
	Set ^||OcuTalonFlightSeam("process") = 1
	Do $$$AssertEquals(..ReadOf(failed), "Error|0", "an Error header is not held by its instance")
	Do $$$AssertEquals($Data(^||OcuTalonFlightSeam("process")), 1, "the block of the instances did not run for it")
}

Method TestReplyInHandJudgesEachCopy()
{
	If '..Ready() Quit
	Set owner = ..Session("bpreplies")
	Set copyA = ..FixtureHeader({"Status": 9})
	Set siblingA = ..FixtureHeader({"Status": 9, "SessionId": (copyA)})
	Set copyC = ..FixtureHeader({"Status": 9})
	Set copyD = ..FixtureHeader({"Status": 9})
	Do $$$AssertTrue((copyA '= "") && (siblingA '= "") && (copyC '= "") && (copyD '= ""), "four Completed copies are made: two of one session, and one each of two more")
	If (copyA = "") || (siblingA = "") || (copyC = "") || (copyD = "") Quit
	Set replyA = ..FixtureHeader({"Type": 2, "Status": 3, "SessionId": (copyA)})
	Set replyC = ..FixtureHeader({"Type": 2, "Status": 3, "SessionId": (copyC)})
	Do $$$AssertTrue((replyA '= "") && (replyC '= ""), "a reply of the first session and a reply of the third are made")
	If (replyA = "") || (replyC = "") Quit
	Set ..EntryKey = "zzOcuTalonTest:"_$Job
	Do ..SetEntry(..EntryKey_":1", replyA)
	Do ..SetEntry(..EntryKey_":2", replyC)
	Do ..SetEntry(..EntryKey_":3", 2000000000)
	Do ..SetEntry(..EntryKey_":4", "no-such-header")
	Set ids = copyA_","_siblingA_","_copyC_","_copyD
	Do $$$AssertEquals(..ReadsOf(ids), "Completed|1,Completed|1,Completed|1,Completed|0", "each copy is judged by its own session: the copy and its sibling are held by the reply of their session, the third by its own, the fourth by none; an entry whose header cannot be read holds nothing")

	Set incident = ..Fixture(owner, ids)
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	For i = 1:1:$Length(ids, ",") Do run.Copies.Insert($Piece(ids, ",", i))
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, $Get(statuses))
	Do $$$AssertEquals(read_"|"_tally.completed_"|"_tally.failedAgain_"|"_tally.running, "read|1|0|3", "Tally counts the three held copies as running and the fourth as completed")

	// the first job lets go of its reply: the hold of the copy and of its sibling ends with it, one pass later at most, and the other job's reply still holds its copy
	Do ..KillEntry(..EntryKey_":1")
	Do $$$AssertEquals(..ReadsOf(ids), "Completed|0,Completed|0,Completed|1,Completed|0", "once the job lets go of the reply, the copy and its sibling are not held, and the other reply still holds its copy")
	Do ..KillEntry(..EntryKey_":2")
	Do $$$AssertEquals(..ReadsOf(ids), "Completed|0,Completed|0,Completed|0,Completed|0", "with no reply in hand, no copy is held")
	Set read = ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, read, $Get(statuses))
	Do $$$AssertEquals(read_"|"_tally.completed_"|"_tally.failedAgain_"|"_tally.running, "read|4|0|0", "Tally counts the four as completed")
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
