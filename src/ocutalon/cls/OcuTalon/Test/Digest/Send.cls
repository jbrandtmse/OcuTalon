/// End-to-end tests of the Digest item over the running production (Story 17.6; AD-1, AD-5, AD-14, AD-18, AD-30, DW-696, U-268, Q1, Q5). THEY RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), except TestNoRecipient and the Tick-forward tests that need no production: the production must run, with the Digest item
/// enabled, and the CI override's environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) for the tests that make a model request. A SendDigest
/// is submitted the way Settings submits it (Commands.Submit, origin web_admin), the Digest item composes and sends to Notify, and the tests read what the real
/// consumers see: the Sent rows, the message headers and the mock's log.
///   - TestWebAdminSends (DW-696): the answer is Ok at once, Outcome sending and the fixed Message (never failed or not_built), and one Notification of the kind
///     digest goes from Digest to Notify for the session, with the AD-32 Slots, and one requested Sent row (DueAt empty) holds the key;
///   - TestRepeatKey (Q5 (a)): the same IdempotencyKey submitted twice before the first is composed, and again after it is sent, gives the same Ok answer each
///     time and one digest; another key gives another;
///   - TestRepeatKey also waits, for a bounded time, until the Composes of its session are finished, and counts only the Composes of its own session;
///   - TestComposeFailureInTrace (Q5 (c)): with a Digest whose Rows seam fails, the SendDigest is still answered Ok, no Notification and no Sent row follow, the
///     Compose's message header is an error and its trace session holds an Error entry;
///   - TestNoRecipient (U-268): SendDigest has exactly the properties of Msg.Command, and so has no recipient, channel or address;
///   - TestTickReachesDigest (Q1): a real Tick through Checks with a due session sends one Tick from Checks to Digest in the tick's session, adds no
///     BackgroundCheck row, and the session gets one scheduled digest;
///   - TestTickForwardFails (Q1): a Tick whose send to Digest answers an error or throws is still answered OK, with one warning;
///   - TestSavedSummaryThroughDecide, TestSavedFallback, TestNothingSavedNoRequest (AD-30): items saved in the window make exactly one untrusted turn through
///     Decide (the mock's log, and the body of the request that went from Digest to Decide: untrusted, fresh, no seed), whose 300-character text is cut to 240; a provider error gives digest.savedNoSummary with the Decision's fallback and one
///     information line; no item makes no request.
Class OcuTalon.Test.Digest.Send Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

/// The seconds to wait for a digest to be sent.
Parameter WAIT = 40;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// 1 once the entries of the runners are pointed at the mock.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The class the Digest item had before a test swapped it, as JSON, or "".
Property Swap As %String(MAXLEN = "");

/// The newest AI session mark when the test began.
Property SessionMark As %Integer;

/// The digest.channels row before the class (ProcessProbe ForgetChannels).
Property ChannelsWas As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..ChannelsWas = $ClassMethod(..#PROBE, "ForgetChannels")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..SessionMark = $Select($ClassMethod(..#FIXTURE, "Running"): $ClassMethod(..#FIXTURE, "SessionMark"), 1: 0)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Unswap()
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ?", ref)
	}
	Do $ClassMethod(..#PROBE, "Clean", ..Sessions)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = "", ..Sessions = ""
	If $ClassMethod(..#FIXTURE, "Running") Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do $ClassMethod(..#PROBE, "PutChannelsBack", ..ChannelsWas)
	Set sc = ..Unswap()
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#FIXTURE, "RestoreKeys"))
	}
	Quit sc
}

/// Puts back the class of the Digest item when a test swapped it.
Method Unswap() As %Status [ Private ]
{
	If ..Swap = "" Quit $$$OK
	Set saved = {}.%FromJSON(..Swap)
	Set ..Swap = ""
	Quit $ClassMethod(..#FIXTURE, "RestoreItemClass", "Digest", saved)
}

/// 1 when the production runs with every item and the CI environment; otherwise the test fails with the reason. withModel points the runners at the mock.
Method Ready(withModel As %Boolean = 0) As %Boolean [ Private ]
{
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	If withModel && '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(..#FIXTURE, "PointKeys")
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

Method Keep(ref As %String) [ Private ]
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

/// A fixture session; createdAt defaults to now.
Method Session(createdAt As %String = "") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsend")
	If createdAt '= "" {
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		Set row.CreatedAt = createdAt
		Do row.%Save()
	}
	Do ..Keep(ref)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// Submits a SendDigest the way Settings does; the CommandResult.
Method Submit(session As %String, key As %String = "", origin As %String = "web_admin") As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = key
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
	Do $$$AssertStatusOK(sc, "Submit returns OK")
	If '$IsObject($Get(result)) Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Quit result
}

/// Asserts that the answer is the one of an accepted request.
Method AssertSending(result As OcuTalon.Msg.CommandResult, label As %String) [ Private ]
{
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sending", label_": Ok at once, with the outcome sending")
	Do $$$AssertEquals(result.Message, $Parameter("OcuTalon.Digest.Process", "MESSAGESENDING"), label_": and the fixed message")
}

/// The number of Sent rows of the session.
Method SentCount(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// Waits until the session has count Sent rows (or WAIT seconds), and returns the number.
Method WaitSent(session As %String, count As %Integer) As %Integer [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..SentCount(session)
		If (found >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The newest Sent row of the session, as an object.
Method SentRow(session As %String) As %DynamicObject [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Kind, DueAt, ItemId, DecisionRef, CatalogKey, Slots, IdempotencyKey, AllClear FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC, ID DESC", session)
	If 'rs.%Next() Quit ""
	Quit {"kind": (rs.%Get("Kind")), "dueAt": (rs.%Get("DueAt")), "itemId": (rs.%Get("ItemId")), "decisionRef": (rs.%Get("DecisionRef")), "catalogKey": (rs.%Get("CatalogKey")), "slots": (rs.%Get("Slots")), "key": (rs.%Get("IdempotencyKey")), "allClear": (rs.%Get("AllClear"))}
}

/// The bodies of the Notifications from Digest to Notify after the header mark whose SessionRef is the session.
Method NoticesOf(mark As %Integer, session As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Digest' AND TargetConfigName = 'Notify' AND MessageBodyClassName = 'OcuTalon.Msg.Notification' ORDER BY ID", mark)
	While rs.%Next() {
		Set body = ##class(OcuTalon.Msg.Notification).%OpenId(rs.%GetData(1))
		If $IsObject(body) && (body.SessionRef = session) Do found.%Push({"kind": (body.Kind), "catalogKey": (body.CatalogKey), "decisionRef": (body.DecisionRef), "slots": (body.Slots)})
	}
	Quit found
}

/// The bodies of the requests from Digest to Decide after the header mark whose OwnerRef is the session.
Method RequestsOf(mark As %Integer, session As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Digest' AND TargetConfigName = 'Decide' AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' ORDER BY ID", mark)
	While rs.%Next() {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(rs.%GetData(1))
		If $IsObject(body) && (body.OwnerRef = session) Do found.%Push({"kind": (body.Kind), "provenance": (body.Provenance), "sessionMode": (body.SessionMode), "seedText": (body.SeedText), "ownerRef": (body.OwnerRef), "channel": (body.Channel)})
	}
	Quit found
}

Method HeaderMark() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

Method TestWebAdminSends()
{
	If '..Ready() Quit
	Set session = ..Session()
	Set mark = ..HeaderMark()
	Set key = "zzweb:"_session
	Set result = ..Submit(session, key)
	Do ..AssertSending(result, "web_admin")
	Do $$$AssertNotEquals(result.Outcome, "failed", "never failed")
	Do $$$AssertNotEquals(result.Outcome, "not_built", "and never not_built")
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "one digest is sent")
	Set notices = ..NoticesOf(mark, session)
	Do $$$AssertEquals(notices.%Size(), 1, "one Notification goes from Digest to Notify for the session")
	If notices.%Size() = 1 {
		Set notice = notices.%Get(0)
		Set slots = {}.%FromJSON(notice.slots)
		Do $$$AssertEquals(notice.kind_"|"_notice.catalogKey, "digest|checks.nothingWatched", "of the kind digest, with the key of nothing watched")
		Do $$$AssertEquals(slots.%GetTypeOf("parts")_"|"_slots.%GetTypeOf("lines")_"|"_slots.%GetTypeOf("rows"), "array|array|array", "with the Slots parts, lines and rows")
		Do $$$AssertEquals(slots.parts.%Get(slots.parts.%Size() - 1).key, "digest.cost", "the cost part is the last")
	}
	Set row = ..SentRow(session)
	Do $$$AssertEquals(row.kind_"|"_row.dueAt_"|"_row.key, "requested||"_key, "the Sent row is requested, with an empty DueAt and the key")
}

Method TestRepeatKey()
{
	If '..Ready() Quit
	Set session = ..Session()
	Set bystander = ..Session()
	Set mark = ..HeaderMark()
	Do ..AssertSending(..Submit(bystander, "zzrepeat:bystander"), "a digest of another session, which the counts below leave out")
	Set key = "zzrepeat:1"
	Set first = ..Submit(session, key)
	Set second = ..Submit(session, key)
	Do ..AssertSending(first, "the first")
	Do ..AssertSending(second, "the repeat before the first is composed")
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "one digest is sent")
	Do $$$AssertEquals(..WaitSent(bystander, 1), 1, "and one for the other session")
	Do $$$AssertEquals(..Composes(mark, session), 1, "the repeat before it was composed queued no Compose: one request was queued in all")
	Do ..WaitComposed(mark, session)
	Set third = ..Submit(session, key)
	Do ..AssertSending(third, "the repeat after the first is sent")
	Do $$$AssertEquals(..Composes(mark, session), 1, "the repeat after it was sent queued none either")
	Do ..WaitComposed(mark, session)
	Do $$$AssertEquals(..SentCount(session), 1, "still one digest")
	Do $$$AssertEquals(..NoticesOf(mark, session).%Size(), 1, "and one Notification")
	Set other = ..Submit(session, "zzrepeat:2")
	Do ..AssertSending(other, "another key")
	Do $$$AssertEquals(..WaitSent(session, 2), 2, "gives another digest")
	Do $$$AssertEquals(..Composes(mark, session), 2, "from a Compose of its own")
}

/// The number of Compose requests that Digest sent to itself after the header mark for the session; open is how many of them are not finished.
Method Composes(mark As %Integer, session As %String, Output open As %Integer) As %Integer [ Private ]
{
	Set total = 0, open = 0
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId, Status FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Digest.Msg.Compose' AND Type = 1 ORDER BY ID", mark)
	While rs.%Next() {
		Set body = ##class(OcuTalon.Digest.Msg.Compose).%OpenId(rs.%Get("MessageBodyId"))
		If '$IsObject(body) || (body.SessionRef '= session) Continue
		Set total = total + 1
		If rs.%Get("Status") < 8 Set open = open + 1
	}
	Quit total
}

/// Waits (at most WAIT seconds) until the session has a Compose request after the mark and every one of them is finished: handled or failed.
Method WaitComposed(mark As %Integer, session As %String) [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set total = ..Composes(mark, session, .open)
		If total && 'open Quit
		If $ZHorolog > end Quit
		Hang 0.25
	}
}

Method TestComposeFailureInTrace()
{
	If '..Ready() Quit
	Set session = ..Session()
	Set sc = $ClassMethod(..#FIXTURE, "UseItemClass", "Digest", "OcuTalon.Test.Digest.FailRowsDigest", .saved)
	If $IsObject(saved) Set ..Swap = saved.%ToJSON()
	Do $$$AssertStatusOK(sc, "a Digest whose Rows seam fails is put behind the item")
	If $$$ISERR(sc) Quit
	Set mark = ..HeaderMark()
	Set result = ..Submit(session, "zzfail:1")
	Do ..AssertSending(result, "the SendDigest")
	Set end = $ZHorolog + ..#WAIT
	Set header = ""
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Status, IsError, SessionId, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Digest.Msg.Compose' ORDER BY ID", mark)
		While rs.%Next() {
			Set body = ##class(OcuTalon.Digest.Msg.Compose).%OpenId(rs.%Get("MessageBodyId"))
			If '$IsObject(body) || (body.SessionRef '= session) Continue
			If rs.%Get("Status") = 8 Set header = {"id": (rs.%Get("ID")), "status": (rs.%Get("Status")), "isError": (rs.%Get("IsError")), "session": (rs.%Get("SessionId"))}
			Quit
		}
		If $IsObject(header) Quit
		If $ZHorolog > end Quit
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(header), "the Compose's message header is an error (status 8)")
	If $IsObject(header) {
		Set log = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE SessionId = ? AND Type = 2", header.session)
		Do log.%Next()
		Do $$$AssertTrue(log.%GetData(1) >= 1, "and its trace session holds an Error entry: "_log.%GetData(1))
	}
	Do $$$AssertEquals(..NoticesOf(mark, session).%Size(), 0, "no Notification follows")
	Do $$$AssertEquals(..SentCount(session), 0, "and no Sent row")
}

Method TestNoRecipient()
{
	Set own = ..PropertyNames("OcuTalon.Msg.Command.SendDigest")
	Set base = ..PropertyNames("OcuTalon.Msg.Command")
	Do $$$AssertEquals(own, base, "SendDigest has exactly the properties of Msg.Command: "_base)
	Do $$$AssertEquals(..PropertyNames("OcuTalon.Digest.Msg.Compose", "Ens.Request"), "DueAt,IdempotencyKey,Kind,SessionRef,WindowEnd,WindowStart", "and a Compose holds no recipient either")
}

/// The names of the properties of the class that the base class does not have (all of them for no base), sorted, comma-separated; the ones of %Persistent's family
/// (names that start with %) are left out.
ClassMethod PropertyNames(class As %String, base As %String = "") As %String [ Private ]
{
	Kill skip
	If base '= "" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ?", base)
		While rs.%Next() {
			Set skip(rs.%Get("Name")) = ""
		}
	}
	Set names = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND SUBSTRING(Name, 1, 1) <> '%' ORDER BY Name", class)
	While rs.%Next() {
		If $Data(skip(rs.%Get("Name"))) Continue
		Set names = names_$Select(names = "": "", 1: ",")_rs.%Get("Name")
	}
	Quit names
}

Method TestTickReachesDigest()
{
	If '..Ready() Quit
	Set session = ..Session(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -3 * 86400))
	Set checks = ..CheckRows()
	Set mark = ..HeaderMark()
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = $ClassMethod(..#FIXTURE, "Send", "Checks", tick, .response)
	Do $$$AssertStatusOK(sc, "the Tick is handled by Checks")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = 'Checks' AND MessageBodyClassName = 'OcuTalon.Msg.Tick' ORDER BY ID", mark)
	Do $$$AssertTrue(rs.%Next(), "the Tick has a header")
	Set traceSession = rs.%Get("SessionId")
	Set hops = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = 'Checks' AND TargetConfigName = 'Digest' AND MessageBodyClassName = 'OcuTalon.Msg.Tick'", traceSession)
	Do hops.%Next()
	Do $$$AssertEquals(hops.%GetData(1), 1, "one Tick goes from Checks to Digest in the tick's session")
	Do $$$AssertEquals(..CheckRows(), checks, "and the Tick added no BackgroundCheck row")
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "the session gets one digest")
	Set row = ..SentRow(session)
	Do $$$AssertEquals(row.kind, "scheduled", "which is scheduled")
	Do $$$AssertEquals(row.dueAt, $ClassMethod("OcuTalon.Digest.Process", "DueFor", tick.TickAt), "for the due time of the tick")
}

Method CheckRows() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck")
	Do rs.%Next()
	Quit rs.%GetData(1)
}

Method TestTickForwardFails()
{
	Kill ^||TickProbe
	For mode = 0, 1, 2 {
		Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Digest.TickProbe", .sc)
		Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
		If '$IsObject(host) Quit
		Set host.FailDigest = mode
		Set host.Only = ""
		Set host.OnlyIncidents = ""
		Set tick = ##class(OcuTalon.Msg.Tick).%New()
		Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set mark = $ClassMethod(..#FIXTURE, "EventMark")
		Kill response
		Do $$$AssertStatusOK(host.OnRequest(tick, .response), "mode "_mode_": the Tick is answered OK")
		Do $$$AssertEquals($Get(^||TickProbe("digest")), mode + 1, "mode "_mode_": the Tick was sent to Digest")
		Set count = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'Tick' AND Text [ 'zz the Digest item'", mark)
		Do count.%Next()
		Set warned = count.%GetData(1)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'Tick' AND Text [ 'zz the Digest item'", mark)
		Do $$$AssertEquals(warned, $Case(mode, 0: 0, : 1), "mode "_mode_": "_$Case(mode, 0: "no warning", : "one warning"))
	}
	Do $$$AssertEquals(^||TickProbe("digest", 1), $ListBuild("OcuTalon.Msg.Tick", 0), "the Tick goes with no answer wanted")
}

/// An item saved for later by the session, recorded now; summary is its stored summary.
Method Item(session As %String, summary As %String) [ Private ]
{
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row = ##class(OcuTalon.Digest.Data.Item).%New()
	Set row.SessionRef = session
	Set row.ItemId = itemId
	Set row.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Channel = "mailbox"
	Set row.Summary = summary
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "an item is saved for later")
}

/// The number of requests that the mock logged after the mark that carry the marker.
Method Requests(mark As %Integer, marker As %String) As %Integer [ Private ]
{
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set count = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && $Find(entry.%ToJSON(), """marker"":"""_marker_"""") Set count = count + 1
	}
	Quit count
}

Method TestSavedSummaryThroughDecide()
{
	If '..Ready(1) Quit
	Set session = ..Session()
	Do ..Item(session, "Partner mail [[mock:digest-summary]]")
	Do ..Item(session, "A newsletter")
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set headerMark = ..HeaderMark()
	Set result = ..Submit(session, "zzsummary:1")
	Do ..AssertSending(result, "the SendDigest")
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "one digest is sent")
	Do $$$AssertEquals(..Requests(mark, "digest-summary"), 1, "exactly one request reached the model, for the summary")
	Set asked = ..RequestsOf(headerMark, session)
	Do $$$AssertEquals(asked.%Size(), 1, "exactly one request went from Digest to Decide for the session")
	If asked.%Size() = 1 {
		Set request = asked.%Get(0)
		Do $$$AssertEquals(request.kind_"|"_request.provenance_"|"_request.sessionMode_"|"_request.seedText_"|"_request.ownerRef_"|"_request.channel, "turn|untrusted|fresh||"_session_"|system", "it is an untrusted, fresh turn with no seed, for the session, on the channel system")
	}
	Set row = ..SentRow(session)
	Set slots = {}.%FromJSON(row.slots)
	Set saved = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = "digest.saved" Set saved = part
	}
	Do $$$AssertTrue($IsObject(saved), "the digest holds digest.saved")
	If $IsObject(saved) {
		Do $$$AssertEquals(saved.slots.count, 2, "for the two items")
		Do $$$AssertEquals($Length(saved.slots.summary), 240, "and the 300 characters of the mock's text are cut to 240")
		Do $$$AssertEquals($Extract(saved.slots.summary, 1, 32), "Saved for later: two newsletters", "which are the first of them")
	}
	Do $$$AssertNotEquals(row.itemId, "", "the Sent row records the request's ItemId")
	Set decision = $ClassMethod(..#FIXTURE, "DecisionOf", row.itemId, "turn")
	Do $$$AssertTrue($IsObject(decision), "a Decision row of kind turn holds the request")
	If $IsObject(decision) Do $$$AssertEquals(decision.Ref_"|"_decision.OwnerRef, row.decisionRef_"|"_session, "which is the digest's DecisionRef, owned by the session")
}

Method TestSavedFallback()
{
	If '..Ready(1) Quit
	Set session = ..Session()
	Do ..Item(session, "Partner mail [[mock:provider-error]]")
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set log = $ClassMethod(..#FIXTURE, "EventMark")
	Set result = ..Submit(session, "zzfallback:1")
	Do ..AssertSending(result, "the SendDigest")
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "the digest still goes")
	Set row = ..SentRow(session)
	Set slots = {}.%FromJSON(row.slots)
	Set found = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = "digest.savedNoSummary" Set found = part
	}
	Do $$$AssertTrue($IsObject(found), "the digest holds digest.savedNoSummary")
	Set decision = $ClassMethod(..#FIXTURE, "DecisionOf", row.itemId, "turn")
	Do $$$AssertTrue($IsObject(decision) && decision.Fallback, "the Decision row carries the fallback")
	If $IsObject(found) && $IsObject(decision) Do $$$AssertEquals(found.slots.fallbackReason, decision.FallbackReason, "with the reason of the digest: "_decision.FallbackReason)
	Set lines = 0, position = 0
	Set rows = $ClassMethod(..#FIXTURE, "EventRows", log, "Digest")
	While $ListNext(rows, position, line) {
		If ($Extract(line, 1, 2) = "4:") && (line [ "The saved-for-later summary of a digest fell back") Set lines = lines + 1
	}
	Do $$$AssertEquals(lines, 1, "and one information line says so")
}

Method TestNothingSavedNoRequest()
{
	If '..Ready(1) Quit
	Set session = ..Session()
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set result = ..Submit(session, "zznothing:1")
	Do ..AssertSending(result, "the SendDigest")
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "the digest goes")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Do $$$AssertEquals(entries.%Size(), 0, "and the mock logged no request")
	Set slots = {}.%FromJSON(..SentRow(session).slots)
	Set none = 0
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = "digest.savedNone" Set none = 1
	}
	Do $$$AssertTrue(none, "with digest.savedNone")
}

}
