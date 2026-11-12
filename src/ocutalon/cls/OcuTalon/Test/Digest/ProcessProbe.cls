/// OcuTalon.Digest.Process with its seams under test control (test only; Story 17.6). It is not an item of any production, and the product never
/// refers to it. A test makes a shadow instance and calls OnRequest and OnResponse as the framework would. It records every send in the
/// process-private global ^||DigestProbe and overrides:
///   - SendCompose saves the Compose (a queued digest is a body that the due check and the key check read) and records it, in order, as
///     ^||DigestProbe("compose", n) = $ListBuild(session, kind, dueAt, key, windowStart, windowEnd, id);
///   - SendNotice records the Notification as ^||DigestProbe("notice", n) = $ListBuild(session, kind, catalogKey, decisionRef, slots, item, superSession), item
///     being the item it was sent to (Notify) and superSession the host's %SuperSession at the send, and fails when FailNotice is set or when the item is one of FailItems (comma-separated), and throws instead when the item is one of ThrowItems;
///   - Reachable gives the channels from OwnChannels (comma-separated, the channels available to the session) that digest.channels names, in the order of
///     OwnChannels, when it is set, else the product's (Product always gives the product's);
///   - SendSummary records the request as ^||DigestProbe("summary", n) with the fields kind, provenance, sessionMode, seedText, ownerRef, itemId, input,
///     channel, systemNote, summary and traceRef, and fails when FailSummary is set;
///   - Rows records its window as ^||DigestProbe("rows", n) = $ListBuild(fromUtc, toUtc) and gives the rows of Test.Digest.CoverageProbe (healthy vital
///     signs and the fed reads), and an error status when FailRows is set. After Feed, it gives instead the five vital rows that Feed was given and the
///     watched rows, with one coverage line for each;
///   - SendResult (Story 17.7) records the DigestResult as ^||DigestProbe("result", n) = $ListBuild(itemId, sourceItemId, catalogKey, allClear, named, checked,
///     decisionRef, fallback, fallbackReason), and fails when FailResult is set; Cost and Channels count their calls under ^||DigestProbe("cost") and
///     ^||DigestProbe("channels") and then do the product's own work;
///   - Schedule works only for the sessions of Only (comma-separated), so that a tick queues nothing for a session the test does not own;
///   - Covered records each answer of the product's check, in order, as ^||DigestProbe("covered", n) = 0 or 1.
/// Cost and NeedsYou are the product's own: the tests feed them with fixture rows. LOCKSECONDS is 1, so that a held lock costs the test a second.
/// Hold and Held take and test the lock of a session's digest from another job; Hold can write a Sent row that covers a due time just before it lets go.
/// ForgetChannels and PutChannelsBack take the digest.channels row out of the way of a test that sends and put it back, so that a row left by another
/// test cannot narrow the channels of a digest.
Class OcuTalon.Test.Digest.ProcessProbe Extends OcuTalon.Digest.Process
{

Parameter LOCKSECONDS = 1;

Parameter PROBE = "OcuTalon.Test.Digest.CoverageProbe";

/// The trace session id a test gives the host (%SessionId), so that the Ens.Rule.Log rows that Digest might write are its own: RouteRows reads them and
/// Clean deletes them.
Parameter TRACESESSION = -770017;

/// The sessions that Schedule works for, comma-separated.
Property Only As %String(MAXLEN = "") [ Transient ];

/// The channels available to the session, comma-separated; empty for the product's own reading.
Property OwnChannels As %String [ Transient ];

Property FailNotice As %Boolean [ InitialExpression = 0, Transient ];

/// The items whose send fails, comma-separated.
Property FailItems As %String [ Transient ];

/// The items whose send throws, comma-separated.
Property ThrowItems As %String [ Transient ];

Property FailSummary As %Boolean [ InitialExpression = 0, Transient ];

Property FailRows As %Boolean [ InitialExpression = 0, Transient ];

Property FailResult As %Boolean [ InitialExpression = 0, Transient ];

/// Forgets what the probe recorded.
ClassMethod Reset()
{
	Kill ^||DigestProbe
}

/// Makes Rows give the five vital-sign rows of vitals (an object {"rows": [...], "figures": {...}}, Healthy by default) followed by the watched rows (an
/// array of {result, entry, finding, checkedAt}), each with its coverage line. Reset ends it.
ClassMethod Feed(watched As %DynamicArray, vitals As %DynamicObject = "")
{
	Set ^||DigestProbe("fed") = {"watched": (watched), "vitals": ($Select($IsObject(vitals): vitals, 1: ..Healthy()))}.%ToJSON()
}

/// The vital signs of five passed rows with the figures 3 days up, 60% full and 20% in use.
ClassMethod Healthy() As %DynamicObject
{
	Set rows = []
	For entry = "IRIS instance", "database space", "journal space", "license use", "system log" {
		Do rows.%Push({"result": "passed", "entry": (entry), "finding": "", "checkedAt": "2030-06-01T12:00:00Z"})
	}
	Quit {"rows": (rows), "figures": {"upDays": 3, "databasesFull": 60, "licenseUse": 20}}
}

/// The number of records of a kind (compose, notice or summary).
ClassMethod Count(kind As %String) As %Integer
{
	Quit +$Get(^||DigestProbe(kind))
}

/// The record n of a kind.
ClassMethod Record(kind As %String, n As %Integer) As %List
{
	Quit $Get(^||DigestProbe(kind, n))
}

/// The summary request n as an object of its fields.
ClassMethod Summary(n As %Integer) As %DynamicObject
{
	Set object = {}
	Set field = ""
	For {
		Set field = $Order(^||DigestProbe("summary", n, field), 1, value)
		Quit:field=""
		Do object.%Set(field, value)
	}
	Quit object
}

/// The Ens.Rule.Log rows of the trace session TRACESESSION, in order, each as {rule, activity, reason, returnValue, errorMsg, isError}.
ClassMethod RouteRows() As %DynamicArray
{
	Set list = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT RuleName, ActivityName, Reason, ReturnValue, ErrorMsg, IsError FROM Ens_Rule.Log WHERE SessionId = ? ORDER BY ID", ..#TRACESESSION)
	While rs.%Next() {
		Do list.%Push({"rule": (rs.%Get("RuleName")), "activity": (rs.%Get("ActivityName")), "reason": (rs.%Get("Reason")), "returnValue": (rs.%Get("ReturnValue")), "errorMsg": (rs.%Get("ErrorMsg")), "isError": (+rs.%Get("IsError"))})
	}
	Quit list
}

/// The Composes recorded so far, in order, each as an object of its fields; the ones from the record number after on.
ClassMethod Composes(after As %Integer = 0) As %DynamicArray
{
	Set list = []
	For n = after + 1:1:..Count("compose") {
		Set record = ..Record("compose", n)
		Do list.%Push({"session": ($List(record, 1)), "kind": ($List(record, 2)), "dueAt": ($List(record, 3)), "key": ($List(record, 4)), "windowStart": ($List(record, 5)), "windowEnd": ($List(record, 6)), "id": ($List(record, 7))})
	}
	Quit list
}

/// Delivers the Compose of record n to a host, as the framework would: its saved body, handled by OnRequest. The status is OnRequest's.
Method DeliverCompose(n As %Integer) As %Status
{
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%OpenId($List(..Record("compose", n), 7))
	Quit ..OnRequest(compose, .response)
}

/// Deletes the Compose bodies and the Sent rows of the sessions (comma-separated), and the Ens.Rule.Log rows of TRACESESSION.
ClassMethod Clean(sessions As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Rule.Log WHERE SessionId = ?", ..#TRACESESSION)
	For i = 1:1:$Length(sessions, ",") {
		Set ref = $Piece(sessions, ",", i)
		If ref = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Msg.Compose WHERE SessionRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE SessionRef = ?", ref)
	}
}

/// Holds the lock of the session's digest for seconds, in a job of its own. With coverDue, the job writes a scheduled Sent row for that due time
/// just before it lets go, as a digest that was sent while the lock was held.
ClassMethod Hold(sessionRef As %String, seconds As %Numeric, coverDue As %String = "")
{
	Lock +^OcuTalon.Digest.Due(sessionRef):10
	If $Test {
		Set ^||DigestProbe("held") = 1
		Hang seconds
		If coverDue '= "" Do ..Cover(sessionRef, coverDue)
		Lock -^OcuTalon.Digest.Due(sessionRef)
	}
}

/// Writes a scheduled Sent row of the session for the due time.
ClassMethod Cover(sessionRef As %String, due As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Digest.Data.Sent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Kind = "scheduled"
	Set row.DueAt = due
	Set row.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(due, -86400)
	Set row.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.CatalogKey = "checks.nothingWatched"
	Set row.Slots = "{}"
	Do row.%Save()
}

/// Deletes the digest.channels row, so that the default applies, and drops this process's cached value; the row as it was, $ListBuild(existed, value).
ClassMethod ForgetChannels() As %List
{
	Set key = ..#CHANNELSSETTING
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Set was = $ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: ""))
	If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
	Kill ^||OcuTalon.Setting(key)
	Quit was
}

/// Puts the digest.channels row back as ForgetChannels found it (was is its answer).
ClassMethod PutChannelsBack(was As %List)
{
	If $Get(was) = "" Quit
	Set key = ..#CHANNELSSETTING
	If $List(was, 1) {
		Do ##class(OcuTalon.Data.Setting).Set(key, $List(was, 2))
	} Else {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
	}
	Kill ^||OcuTalon.Setting(key)
}

/// 1 when another job holds the lock of the session's digest.
ClassMethod Held(sessionRef As %String) As %Boolean
{
	Lock +^OcuTalon.Digest.Due(sessionRef):0
	If $Test {
		Lock -^OcuTalon.Digest.Due(sessionRef)
		Quit 0
	}
	Quit 1
}

Method Schedule(sessionRef As %String, due As %String, now As %String) As %Status [ Private ]
{
	If '$ListFind($ListFromString(..Only), sessionRef) Quit $$$OK
	Quit ##super(sessionRef, due, now)
}

Method Covered(sessionRef As %String, due As %String) As %Boolean [ Private ]
{
	Set covered = ##super(sessionRef, due)
	Set ^||DigestProbe("covered", $Increment(^||DigestProbe("covered"))) = covered
	Quit covered
}

Method SendCompose(compose As OcuTalon.Digest.Msg.Compose) As %Status [ Private ]
{
	Set sc = compose.%Save()
	If $$$ISERR(sc) Quit sc
	Set n = $Increment(^||DigestProbe("compose"))
	Set ^||DigestProbe("compose", n) = $ListBuild(compose.SessionRef, compose.Kind, compose.DueAt, compose.IdempotencyKey, compose.WindowStart, compose.WindowEnd, compose.%Id())
	Quit $$$OK
}

Method SendResult(result As OcuTalon.Eval.Msg.DigestResult) As %Status [ Private ]
{
	Set n = $Increment(^||DigestProbe("result"))
	Set ^||DigestProbe("result", n) = $ListBuild(result.ItemId, result.SourceItemId, result.CatalogKey, result.AllClear, result.Named, result.Checked, result.DecisionRef, result.Fallback, result.FallbackReason)
	If ..FailResult Quit $SYSTEM.Status.Error(5001, "zz the DigestResult could not be sent")
	Quit $$$OK
}

Method Cost(sessionRef As %String, at As %String, Output sc As %Status) As %Numeric [ Private ]
{
	Do $Increment(^||DigestProbe("cost"))
	Quit ##super(sessionRef, at, .sc)
}

Method Channels(sessionRef As %String, Output channels As %List) As %Status [ Private ]
{
	Do $Increment(^||DigestProbe("channels"))
	Quit ##super(sessionRef, .channels)
}

Method Reachable(sessionRef As %String) As %List [ Private ]
{
	If ..OwnChannels = "" Quit ##super(sessionRef)
	Set channels = ""
	Set position = 0
	Set available = $ListFromString(..OwnChannels)
	While $ListNext(available, position, channel) {
		If ##class(OcuTalon.Core.Rule.Functions).DigestNamed(channel) Set channels = channels_$ListBuild(channel)
	}
	Quit channels
}

/// The product's own reading of the channels a digest of the session goes to, whatever OwnChannels says.
Method Product(sessionRef As %String) As %List
{
	Set was = ..OwnChannels
	Set ..OwnChannels = ""
	Set channels = ..Reachable(sessionRef)
	Set ..OwnChannels = was
	Quit channels
}

Method SendNotice(notification As OcuTalon.Msg.Notification, item As %String) As %Status [ Private ]
{
	Set n = $Increment(^||DigestProbe("notice"))
	Set ^||DigestProbe("notice", n) = $ListBuild(notification.SessionRef, notification.Kind, notification.CatalogKey, notification.DecisionRef, notification.Slots, item, ..%SuperSession)
	If $ListFind($ListFromString(..ThrowItems), item) Throw ##class(%Exception.General).%New("zz the Notification threw", 5001, , "zz the Notification threw for "_item)
	If ..FailNotice || $ListFind($ListFromString(..FailItems), item) Quit $SYSTEM.Status.Error(5001, "zz the Notification could not be sent to "_item)
	Quit $$$OK
}

Method SendSummary(request As OcuTalon.Bridge.Msg.Request) As %Status [ Private ]
{
	Set n = $Increment(^||DigestProbe("summary"))
	For field = "Kind", "Provenance", "SessionMode", "SeedText", "OwnerRef", "ItemId", "Input", "Channel", "SystemNote", "Summary", "TraceRef" {
		Set ^||DigestProbe("summary", n, $ZConvert($Extract(field), "L")_$Extract(field, 2, *)) = $Property(request, field)
	}
	If ..FailSummary Quit $SYSTEM.Status.Error(5001, "zz the summary request could not be sent")
	Quit $$$OK
}

Method Rows(sessionRef As %String, fromUtc As %String, toUtc As %String, Output rows As %DynamicArray, Output lines As %DynamicArray, Output vitals As %DynamicObject) As %Status [ Private ]
{
	Set ^||DigestProbe("rows", $Increment(^||DigestProbe("rows"))) = $ListBuild(fromUtc, toUtc)
	If ..FailRows Quit $SYSTEM.Status.Error(5001, "zz the rows could not be built")
	If $Data(^||DigestProbe("fed")) {
		Set fed = {}.%FromJSON(^||DigestProbe("fed"))
		Set vitals = fed.vitals
		Set rows = [], lines = []
		Set iterator = vitals.rows.%GetIterator()
		While iterator.%GetNext(, .row) {
			Do ..Add(rows, lines, row)
		}
		Set iterator = fed.watched.%GetIterator()
		While iterator.%GetNext(, .row) {
			Do ..Add(rows, lines, row)
		}
		Quit $$$OK
	}
	Quit $ClassMethod(..#PROBE, "Build", sessionRef, fromUtc, toUtc, .rows, .lines, .vitals)
}

/// Adds the row and its coverage line.
ClassMethod Add(rows As %DynamicArray, lines As %DynamicArray, row As %DynamicObject) [ Private ]
{
	Do rows.%Push(row)
	If row.result = "passed" {
		Do lines.%Push({"key": "digest.passed", "slots": {"entry": (row.entry), "time": (row.checkedAt)}})
	} ElseIf row.result = "failed" {
		Do lines.%Push({"key": "digest.failed", "slots": {"entry": (row.entry), "finding": (row.finding), "time": (row.checkedAt)}})
	} Else {
		Do lines.%Push({"key": "digest.notCheckedError", "slots": {"entry": (row.entry), "time": (row.checkedAt)}})
	}
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
