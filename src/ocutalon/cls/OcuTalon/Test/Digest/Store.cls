/// Tests of DigestStore and the digest items it keeps (Story 1.12; AD-1, AD-3, AD-4, AD-5, AD-6, AD-22, AD-23, AD-27, AD-29, AD-30, AD-33):
/// OcuTalon.Digest.Store, the table OcuTalon.Digest.Data.Item with its read (Since) and purge, and the area OcuTalon.Install.Step.Digest.
/// THE TESTS THAT SAY LIVE RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they send fixture ItemDecisions to the running DigestStore through the
/// service ApprovalStartIn (RunnerFixture.Send, a stand-in for OutcomeRouter), so they need OcuTalon.Production running after the Production step,
/// and they fail with the reason where they do not have it. They need no model and no mock. The in-process tests need no production.
///   - TestKeeps and TestKeepsInstance (live; AC1): a digest ItemDecision for a session, or for instance, is answered OK with no response and
///     is kept as exactly one row with the owner as SessionRef, its DecisionRef, Channel and Summary and a RecordedAt in UTC between the clock before and
///     after the send; DigestStore sends no message (the only header with DigestStore as its source is its reply to the sender, ApprovalStartIn, with no
///     body) and publishes no live event (none since the test began holds the ItemId or the DecisionRef, and none is on a session's stream);
///   - TestRefuses (live; AC2): an outcome of tellnow, act or ignore, an owner of eval or none, and an empty ItemId each get an error status that
///     names the reason and the ItemId when there is one, with code 5001, no row and nothing sent on; an Ens.StringRequest gets code 5003, no response, no
///     row and nothing sent on;
///   - TestKeepsFields (live; AC1): for each channel of Msg.Enum CHANNEL, every field of the row is the field of the ItemDecision it came from
///     (a Summary of 80 characters with quotes, a backslash and a character beyond ASCII too), none of the message's other fields is taken for one, each send
///     adds exactly one row, and Item.Since gives the same values;
///   - TestOnce (live; AC4): the same ItemId sent twice is answered OK twice and keeps the first message's row; an ItemId that differs only in the case
///     of its letters is a second item;
///   - TestOnceUnchanged (live; AC4): a repeat from another owner, on another channel, with another summary and a later second, changes nothing
///     of the first row, its time included, and gives the other owner no row;
///   - TestKeepFailureIsAnError (in process; AC1): a decision whose save fails is an error that names the ItemId, with no row, never OK;
///   - TestUniqueItemId (in process; AC4): the table itself refuses a second row for an ItemId, whatever its session, and holds ItemIds that
///     differ in case as two;
///   - TestSince and TestSinceRefuses (AC3): one session's rows at or after a time, newest first (the ones of one second, the later saved first), with the
///     five keys only; another session whose Ref differs in the case of its letters is not mixed in; an unreadable time or an empty session is an error
///     with no items;
///   - TestSinceOrder (in process; AC3): the order is by time and then by save order, not by save order alone: rows saved out of time order
///     come back newest first, and a time after every row gives an empty array;
///   - TestPurgeByTheTask, TestPurgeDays and TestPurgeRefuses (AC6): the purge task with its default 90 days, and Registry.Purge(30), delete the rows
///     recorded before the cutoff and keep the others (one recorded exactly at the cutoff too, and, for the task, one an hour either side of 90 days),
///     through the declaration of OcuTalon.Install.Step.Digest; a day count that is not a whole number of at least 1 is an error and deletes nothing, and
///     one beyond the calendar's first date is OK and deletes nothing;
///   - TestPurgeOneDay (AC6): a day count of 1, the least that is accepted, deletes what is more than a day old and keeps the rest;
///   - TestPrivate (AC5): the data and index globals of the table are among the private storage globals of PrivateData and resolve to the private database.
/// The restart row of docker/tests/test-production.sh (AC5) calls RestartKeep, RestartRead and RestartClean around a restart of IRIS.
/// Every test makes its own rows with Refs that begin with zzDigest (or ZZdIGEST, the same Ref with the case of its letters swapped), and OnBeforeAllTests and
/// OnAfterOneTest delete every row whose ItemId or SessionRef begins so, also after a failure.
Class OcuTalon.Test.Digest.Store Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The item that keeps the digest items.
Parameter ITEM = "DigestStore";

/// The start of every fixture Ref.
Parameter PREFIX = "zzDigest";

/// The start of every fixture Ref with the case of its letters swapped.
Parameter SWAPPED = "ZZdIGEST";

/// The session of the restart row, with the start of its two items' Refs and of their decisions' Refs (a number from 1 follows).
Parameter RESTARTSESSION = "zzDigestRestart0000001";

Parameter RESTARTITEM = "zzDigestRestartItem00";

Parameter RESTARTDECISION = "zzDigestRestartDec000";

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ..Clean()
	Quit sc
}

/// A digest ItemDecision for the owner is answered OK with no response, kept as one row with the message's fields and a RecordedAt between the
/// clock before and after the send, and DigestStore sends nothing and publishes no live event.
Method TestKeeps()
{
	Do ..AssertKept(..NewRef())
}

/// The same with the owner instance.
Method TestKeepsInstance()
{
	Do ..AssertKept("instance")
}

/// For each channel of Msg.Enum CHANNEL, a digest ItemDecision with a Summary of the full 80 characters (quotes, a backslash and a character beyond ASCII
/// in it) and with every other field of the message filled with a value of its own is kept as one row whose six fields are the message's: the OwnerRef as the
/// SessionRef, the ItemId, the DecisionRef, the Channel and the Summary, and a RecordedAt in UTC to the second between the clock before and after the send.
/// The send adds exactly one row, and Item.Since gives the same values for the owner.
Method TestKeepsFields()
{
	Set reason = ..ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set channels = $Parameter("OcuTalon.Msg.Enum", "CHANNEL")
	Set count = $Length(channels, ",")
	Do $$$AssertTrue(count >= 2, "control: the channels are read from Msg.Enum: "_channels)
	For number = 1:1:count {
		Set channel = $Piece(channels, ",", number)
		Set label = "channel "_channel_": "
		Set owner = ..NewRef(), itemId = ..NewRef(), decisionRef = ..NewRef()
		Set summary = ..LongSummary(channel)
		Do $$$AssertEquals($Length(summary), 80, label_"control: the Summary is 80 characters")
		Set decision = ..Decision(itemId, owner, "digest", decisionRef, summary, channel)
		Set decision.SourceItemId = "source-"_itemId
		Set decision.CatalogKey = "catalog-"_itemId
		Set decision.Slots = "{""slot"": """_itemId_"""}"
		Set decision.Fallback = 1
		Set decision.FallbackReason = "reason-"_itemId
		Set rows = ..CountAll()
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, decision, .response)
		Set after = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertStatusOK(sc, label_"the decision is answered OK")
		Do $$$AssertEquals(..CountAll(), rows + 1, label_"the send adds exactly one row")
		Do $$$AssertEquals(..CountItem(itemId), 1, label_"one row holds the ItemId")
		Do $$$AssertEquals(..CountSession(owner), 1, label_"and it is the owner's only row")
		Set row = ..RowOf(itemId)
		Do $$$AssertTrue($IsObject(row), label_"the row is found")
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.SessionRef, owner, label_"its SessionRef is the OwnerRef")
		Do $$$AssertEquals(row.ItemId, itemId, label_"its ItemId is the message's")
		Do $$$AssertEquals(row.DecisionRef, decisionRef, label_"its DecisionRef is the message's")
		Do $$$AssertEquals(row.Channel, channel, label_"its Channel is the message's")
		Do $$$AssertEquals(row.Summary, summary, label_"its Summary is the message's, whole")
		Do $$$AssertTrue(row.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", label_"its RecordedAt is UTC to the second: "_row.RecordedAt)
		Do $$$AssertTrue((before '] row.RecordedAt) && (row.RecordedAt '] after), label_"and lies between the clock before the send ("_before_") and after it ("_after_")")
		Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(owner, "", .items), label_"Since gives the owner's items")
		Do $$$AssertEquals(items.%Size(), 1, label_"one entry")
		If items.%Size() = 1 {
			Set expected = {"itemId": (itemId), "decisionRef": (decisionRef), "channel": (channel), "summary": (summary), "recordedAt": (row.RecordedAt)}
			Do $$$AssertEquals(items.%Get(0).%ToJSON(), expected.%ToJSON(), label_"holding the message's values and the row's time")
		}
	}
}

/// An ItemDecision that DigestStore must not keep gets an error status that names the reason and the ItemId, writes no row and sends nothing; a message
/// of another class gets code 5003 and no response.
Method TestRefuses()
{
	Set reason = ..ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set cases = $ListBuild($ListBuild("tellnow", "session", 1, "outcome is 'tellnow'"), $ListBuild("act", "session", 1, "outcome is 'act'"), $ListBuild("ignore", "session", 1, "outcome is 'ignore'"), $ListBuild("digest", "eval", 1, "owner is eval"), $ListBuild("digest", "", 1, "owner is empty"), $ListBuild("digest", "session", 0, "no ItemId"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set outcome = $List(case, 1), ownerRef = $List(case, 2), hasItem = $List(case, 3), fragment = $List(case, 4)
		If ownerRef = "session" Set ownerRef = ..NewRef()
		Set itemId = $Select(hasItem: ..NewRef(), 1: "")
		Set label = "outcome '"_outcome_"', owner '"_$Select($Extract(ownerRef, 1, 8) = ..#PREFIX: "a session", 1: ownerRef)_"', "_$Select(hasItem: "an ItemId", 1: "no ItemId")
		Set decision = ..Decision(itemId, ownerRef, outcome)
		Set headers = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
		Set events = ..EventMark()
		Set rows = ..CountAll()
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, decision, .response)
		Do $$$AssertStatusNotOK(sc, label_": the decision is refused")
		Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, label_": with code 5001")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ ..#ITEM, label_": the error names DigestStore: "_text)
		Do $$$AssertTrue(text [ fragment, label_": the error names the reason ("_fragment_"): "_text)
		If hasItem Do $$$AssertTrue(text [ itemId, label_": the error names the ItemId: "_text)
		Do $$$AssertTrue('$IsObject(response), label_": there is no response")
		If hasItem Do $$$AssertEquals(..CountItem(itemId), 0, label_": no row for the ItemId")
		If ownerRef '= "" Do $$$AssertEquals(..CountSession(ownerRef), 0, label_": no row for the owner")
		Do $$$AssertEquals(..CountAll(), rows, label_": no row is written")
		Set session = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionOf(decision, headers)
		Do $$$AssertTrue(session '= "", label_": the send is found in a session")
		If session '= "" Do $$$AssertEquals(..SentOn(session), "[]", label_": DigestStore sent no message but its reply")
		Do $$$AssertEquals(..LiveEvents(ownerRef, $Select(itemId '= "": itemId, 1: decision.DecisionRef), decision.DecisionRef, events), 0, label_": and published no live event")
	}

	Set total = ..CountAll()
	Set request = ##class(Ens.StringRequest).%New("x")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, request, .response)
	Do $$$AssertStatusNotOK(sc, "a message of another class is refused")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "with code 5003")
	Do $$$AssertTrue('$IsObject(response), "and no response")
	Do $$$AssertEquals(..CountAll(), total, "and no row is written")
	Set session = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionOf(request, mark)
	Do $$$AssertTrue(session '= "", "the send of the other class is found in a session")
	If session '= "" Do $$$AssertEquals(..SentOn(session), "[]", "and DigestStore sent no message but its reply")
}

/// A digest decision whose save fails (a Summary of 81 characters, one more than the table holds) is an error that names the ItemId and the reason, never OK, and
/// leaves no row; the same decision with a Summary of 80 characters is kept. In process, through the handler of a shadow instance: the production cannot deliver
/// such a message, since the message class holds 80 characters at most.
Method TestKeepFailureIsAnError()
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Digest.Store", .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of DigestStore is made")
	If '$IsObject(host) Quit
	Set owner = ..NewRef(), itemId = ..NewRef()
	Set long = $Translate($Justify("", 81), " ", "s")
	Set decision = ..Decision(itemId, owner, "digest", "", long)
	Set rows = ..CountAll()
	Set sc = host.OnMessage(decision, .response)
	Do $$$AssertStatusNotOK(sc, "a decision whose Summary does not fit is not answered OK")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, "the code is 5001")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ ("could not keep the item "_itemId), "the error names the ItemId: "_text)
	Do $$$AssertTrue('$IsObject($Get(response)), "there is no response")
	Do $$$AssertEquals(..CountItem(itemId), 0, "no row holds the ItemId")
	Do $$$AssertEquals(..CountAll(), rows, "and no row is written")
	Set decision.Summary = $Extract(long, 1, 80)
	Do $$$AssertStatusOK(host.OnMessage(decision, .response), "control: the same decision with a Summary of 80 characters is kept")
	Do $$$AssertEquals(..CountItem(itemId), 1, "control: and has its row")
}

/// The same ItemId sent twice is answered OK twice and keeps the row of the first; an ItemId that differs in the case of a letter is another item.
Method TestOnce()
{
	Set reason = ..ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set owner = ..NewRef()
	Set itemId = ..NewRef()
	Set first = ..Decision(itemId, owner, "digest", ..NewRef(), "First summary")
	Set second = ..Decision(itemId, owner, "digest", ..NewRef(), "Second summary")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, first), "the first is answered OK")
	Set headers = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark(), events = ..EventMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, second), "the second is answered OK")
	Set session = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionOf(second, headers)
	Do $$$AssertTrue(session '= "", "the repeat is found in a session")
	If session '= "" Do $$$AssertEquals(..SentOn(session), "[]", "for the repeat, DigestStore sent no message but its reply")
	Do $$$AssertEquals(..LiveEvents(owner, itemId, second.DecisionRef, events), 0, "and published no live event")
	Do $$$AssertEquals(..CountItem(itemId), 1, "one row for the ItemId")
	Set row = ..RowOf(itemId)
	Do $$$AssertTrue($IsObject(row), "the row is found")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Summary, "First summary", "it holds the first message's Summary")
		Do $$$AssertEquals(row.DecisionRef, first.DecisionRef, "and the first message's DecisionRef")
	}
	Set other = ..SwapCase(itemId)
	Do $$$AssertTrue(other '= itemId, "control: the Ref has letters, so swapping their case makes another Ref")
	Set third = ..Decision(other, owner, "digest", ..NewRef(), "Third summary")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, third), "an ItemId that differs in case is answered OK")
	Do $$$AssertEquals(..CountItem(itemId), 1, "the first ItemId still has one row")
	Do $$$AssertEquals(..CountItem(other), 1, "the ItemId that differs in case is kept as an item of its own")
	Do $$$AssertEquals(..CountSession(owner), 2, "the session holds the two items")
}

/// A repeat of an ItemId changes nothing of the first row: with another owner, another channel, another summary, another DecisionRef and a later second, it
/// is answered OK, leaves the row as it was (the time of the keep and the row id included), and gives the other owner no row.
Method TestOnceUnchanged()
{
	Set reason = ..ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set itemId = ..NewRef()
	Set ownerA = ..NewRef(), ownerB = ..NewRef()
	Set first = ..Decision(itemId, ownerA, "digest", ..NewRef(), "First summary", "web")
	Set second = ..Decision(itemId, ownerB, "digest", ..NewRef(), "Second summary", "slack")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, first), "the first is answered OK")
	Set kept = ..Stored(itemId)
	Do $$$AssertTrue(kept '= "", "the first row is found")
	If kept = "" Quit
	Do ..WaitPast(kept.recordedAt)
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).NowUtc() ] kept.recordedAt, "control: the clock is past the second of the first row, so a repeat that rewrote the time would show")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, second), "the repeat from another owner is answered OK")
	Do $$$AssertEquals(..CountItem(itemId), 1, "one row holds the ItemId")
	Do $$$AssertEquals(..CountSession(ownerA), 1, "it is still the first owner's")
	Do $$$AssertEquals(..CountSession(ownerB), 0, "and the other owner has no row")
	Set again = ..Stored(itemId)
	Do $$$AssertTrue(again '= "", "the row is found again")
	If again '= "" Do $$$AssertEquals(again.%ToJSON(), kept.%ToJSON(), "and it is as it was, field for field, with its row id")
}

/// The table itself holds one row for an ItemId, whatever the session and the time of a second row: the save of the second fails and the first row stays.
/// ItemIds that differ only in the case of a letter are two items.
Method TestUniqueItemId()
{
	Set a = ..NewRef(), b = ..NewRef()
	Set itemId = ..NewRef()
	Set first = ..Add(a, itemId, ..AgoUtc(86400))
	Set second = ##class(OcuTalon.Digest.Data.Item).%New()
	Set second.SessionRef = b
	Set second.ItemId = itemId
	Set second.DecisionRef = ..NewRef()
	Set second.Channel = "web"
	Set second.Summary = "A second row for the ItemId"
	Set second.RecordedAt = ..AgoUtc(0)
	Do $$$AssertStatusNotOK(second.%Save(), "a second row for the ItemId, of another session and time, is not saved")
	Do $$$AssertEquals(..CountItem(itemId), 1, "one row holds the ItemId")
	Do $$$AssertEquals(..CountSession(b), 0, "and the other session has none")
	Set stored = ..Stored(itemId)
	Do $$$AssertTrue(stored '= "", "the row is found")
	If stored '= "" Do $$$AssertEquals(stored.%ToJSON(), ..Snapshot(first).%ToJSON(), "and it is the first, as it was")
	Set other = ..SwapCase(itemId)
	Do $$$AssertTrue(other '= itemId, "control: the Ref has letters, so swapping their case makes another Ref")
	Do ..Add(a, other, ..AgoUtc(0))
	Do $$$AssertEquals(..CountItem(itemId), 1, "the ItemId still has its one row")
	Do $$$AssertEquals(..CountItem(other), 1, "and the ItemId that differs in case has a row of its own")
}

/// Since: the session's rows at or after the time, newest first, the boundary included, and nothing of another session, even one whose Ref differs only
/// in the case of its letters; the entries have the five keys.
Method TestSince()
{
	Set a = ..NewRef()
	Set b = ..SwapCase(a)
	Do $$$AssertTrue(b '= a, "control: session B is session A with the case of its letters swapped")
	Set t1 = ..AgoUtc(3 * 86400), t2 = ..AgoUtc(2 * 86400), t3 = ..AgoUtc(86400)
	Set a1 = ..Add(a, ..NewRef(), t1)
	Set a2 = ..Add(a, ..NewRef(), t2)
	Set a3 = ..Add(a, ..NewRef(), t2)
	Set a4 = ..Add(a, ..NewRef(), t3)
	Set b1 = ..Add(b, ..NewRef(), t2)

	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, t2, .items), "Since(A, t2) is OK")
	Do $$$AssertEquals(..ItemIdsOf(items), a4.ItemId_" "_a3.ItemId_" "_a2.ItemId, "from t2: the t3 row, then the two t2 rows, the later saved first; the boundary is included and t1 is not")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, "", .items), "Since(A, empty) is OK")
	Do $$$AssertEquals(..ItemIdsOf(items), a4.ItemId_" "_a3.ItemId_" "_a2.ItemId_" "_a1.ItemId, "from the start: the four rows of A, newest first")
	Set expected = [{"itemId": (a4.ItemId), "decisionRef": (a4.DecisionRef), "channel": (a4.Channel), "summary": (a4.Summary), "recordedAt": (a4.RecordedAt)}]
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, ..AgoUtc(86400 + 3600), .items), "Since(A, an hour before t3) is OK")
	Do $$$AssertEquals(items.%Size(), 1, "only the t3 row is that late")
	If items.%Size() = 1 Do $$$AssertEquals(items.%Get(0).%ToJSON(), expected.%Get(0).%ToJSON(), "its entry holds the five fields of the row")
	Do $$$AssertEquals(..KeysOf(items), "itemId,decisionRef,channel,summary,recordedAt", "and these keys only")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, "", .items), "Since(A, empty) is OK again")
	Do $$$AssertEquals(..KeysOf(items), "itemId,decisionRef,channel,summary,recordedAt|itemId,decisionRef,channel,summary,recordedAt|itemId,decisionRef,channel,summary,recordedAt|itemId,decisionRef,channel,summary,recordedAt", "every entry has these keys only")
	Set rows = []
	For row = a4, a3, a2, a1 {
		Do rows.%Push({"itemId": (row.ItemId), "decisionRef": (row.DecisionRef), "channel": (row.Channel), "summary": (row.Summary), "recordedAt": (row.RecordedAt)})
	}
	Do $$$AssertEquals(items.%ToJSON(), rows.%ToJSON(), "and every entry holds the five fields of its row")

	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(b, "", .items), "Since(B, empty) is OK")
	Do $$$AssertEquals(..ItemIdsOf(items), b1.ItemId, "session B has its own row only")
	If items.%Size() = 1 Do $$$AssertEquals(items.%Get(0).recordedAt, t2, "with its time")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(..NewRef(), "", .items), "Since(an unused Ref, empty) is OK")
	Do $$$AssertEquals(items.%ToJSON(), "[]", "and gives an empty array")
}

/// Since orders by the time of the rows and then by the order they were saved, not by the order they were saved alone: rows saved out of time order come
/// back newest first, the two of one second the later saved first; a time after every row gives an OK status and an empty array.
Method TestSinceOrder()
{
	Set a = ..NewRef()
	Set t1 = ..AgoUtc(3 * 86400), t2 = ..AgoUtc(2 * 86400), t3 = ..AgoUtc(86400)
	Set r1 = ..Add(a, ..NewRef(), t2)
	Set r2 = ..Add(a, ..NewRef(), t3)
	Set r3 = ..Add(a, ..NewRef(), t1)
	Set r4 = ..Add(a, ..NewRef(), t2)
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, "", .items), "Since(A, empty) is OK")
	Do $$$AssertEquals(..ItemIdsOf(items), r2.ItemId_" "_r4.ItemId_" "_r1.ItemId_" "_r3.ItemId, "the t3 row, the two t2 rows (the later saved first), then the t1 row saved third")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, t2, .items), "Since(A, t2) is OK")
	Do $$$AssertEquals(..ItemIdsOf(items), r2.ItemId_" "_r4.ItemId_" "_r1.ItemId, "from t2: the same order without the t1 row")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, t3, .items), "Since(A, t3) is OK")
	Do $$$AssertEquals(..ItemIdsOf(items), r2.ItemId, "from t3: the t3 row only")
	Set items = [1]
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, ..AgoUtc(-3600), .items), "Since(A, a time after every row) is OK")
	Do $$$AssertEquals(items.%ToJSON(), "[]", "and gives an empty array")
}

/// An empty session and a time that Data.Time cannot read are errors with an empty array, while a session with rows and a good time are not.
Method TestSinceRefuses()
{
	Set a = ..NewRef()
	Do ..Add(a, ..NewRef(), ..AgoUtc(86400))
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, "2026-10-20T08:00:00Z", .items), "control: a UTC time is read")
	Do $$$AssertEquals(items.%Size(), 1, "control: and gives the row")
	For since = "2026-10-20 08:00:00", "yesterday", "2026-13-40T08:00:00Z", "2026-10-20T08:00:00", "2026-10-20" {
		Set items = [1]
		Set sc = ##class(OcuTalon.Digest.Data.Item).Since(a, since, .items)
		Do $$$AssertStatusNotOK(sc, "the time '"_since_"' is an error")
		Do $$$AssertEquals(items.%ToJSON(), "[]", "with an empty array")
	}
	Set items = [1]
	Set sc = ##class(OcuTalon.Digest.Data.Item).Since("", "", .items)
	Do $$$AssertStatusNotOK(sc, "an empty session is an error")
	Do $$$AssertEquals(items.%ToJSON(), "[]", "with an empty array")
	Set items = [1]
	Set sc = ##class(OcuTalon.Digest.Data.Item).Since("", "2026-10-20T08:00:00Z", .items)
	Do $$$AssertStatusNotOK(sc, "so is an empty session with a good time")
	Do $$$AssertEquals(items.%ToJSON(), "[]", "with an empty array")
}

/// The purge task with its default 90 days deletes the items recorded 91 days ago and 90 days and an hour ago, and keeps the ones of 90 days less an hour
/// ago, of 89 days ago and of now, through the declaration of the Digest area; the area is registered and is not one of the steps that run at a start.
Method TestPurgeByTheTask()
{
	Set a = ..NewRef()
	Set now = ..Add(a, ..NewRef(), ..AgoUtc(0))
	Set recent = ..Add(a, ..NewRef(), ..AgoUtc(89 * 86400))
	Set within = ..Add(a, ..NewRef(), ..AgoUtc(90 * 86400 - 3600))
	Set beyond = ..Add(a, ..NewRef(), ..AgoUtc(90 * 86400 + 3600))
	Set old = ..Add(a, ..NewRef(), ..AgoUtc(91 * 86400))
	Do $$$AssertTrue($ListFind(##class(OcuTalon.Install.Registry).Areas(), "OcuTalon.Install.Step.Digest") > 0, "the registry lists the Digest area")
	Do $$$AssertEquals($ListFind(##class(OcuTalon.Install.Registry).Order(), "Digest"), 0, "and the order of the steps does not name it")
	Set task = ##class(OcuTalon.Install.Task.Purge).%New()
	Do $$$AssertEquals(task.DaysToKeep, 90, "the purge task keeps 90 days by default")
	Do $$$AssertStatusOK(task.OnTask(), "the purge task runs")
	Do $$$AssertEquals(..CountItem(old.ItemId), 0, "the item of 91 days ago is gone")
	Do $$$AssertEquals(..CountItem(beyond.ItemId), 0, "so is the item of 90 days and an hour ago")
	Do $$$AssertEquals(..CountItem(within.ItemId), 1, "the item of 90 days less an hour ago is kept")
	Do $$$AssertEquals(..CountItem(recent.ItemId), 1, "the item of 89 days ago is kept")
	Do $$$AssertEquals(..CountItem(now.ItemId), 1, "and so is the item of now")
}

/// A day count of 1, the least that is accepted, is OK, deletes the item recorded more than a day ago and keeps the ones of less than a day ago.
Method TestPurgeOneDay()
{
	Set a = ..NewRef()
	Set old = ..Add(a, ..NewRef(), ..AgoUtc(25 * 3600))
	Set recent = ..Add(a, ..NewRef(), ..AgoUtc(23 * 3600))
	Set now = ..Add(a, ..NewRef(), ..AgoUtc(0))
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Digest).Purge(1), "a day count of 1 is OK")
	Do $$$AssertEquals(..CountItem(old.ItemId), 0, "the item of 25 hours ago is gone")
	Do $$$AssertEquals(..CountItem(recent.ItemId), 1, "the item of 23 hours ago is kept")
	Do $$$AssertEquals(..CountItem(now.ItemId), 1, "and so is the item of now")
}

/// Registry.Purge(30) deletes what was recorded before 30 days ago and keeps what was recorded later, an hour either side of the cutoff included.
Method TestPurgeDays()
{
	Set a = ..NewRef()
	Set late = ..Add(a, ..NewRef(), ..AgoUtc(31 * 86400))
	Set beyond = ..Add(a, ..NewRef(), ..AgoUtc(30 * 86400 + 3600))
	Set within = ..Add(a, ..NewRef(), ..AgoUtc(30 * 86400 - 3600))
	Set recent = ..Add(a, ..NewRef(), ..AgoUtc(29 * 86400))
	Set now = ..Add(a, ..NewRef(), ..AgoUtc(0))
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Registry).Purge(30), "Registry.Purge(30) is OK")
	Do $$$AssertEquals(..CountItem(late.ItemId), 0, "the item of 31 days ago is gone")
	Do $$$AssertEquals(..CountItem(beyond.ItemId), 0, "so is the item of 30 days and an hour ago")
	Do $$$AssertEquals(..CountItem(within.ItemId), 1, "the item of 30 days less an hour ago is kept")
	Do $$$AssertEquals(..CountItem(recent.ItemId), 1, "the item of 29 days ago is kept")
	Do $$$AssertEquals(..CountItem(now.ItemId), 1, "and the item of now")
	Set pinned = 0
	For attempt = 1:1:20 {
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set edge = ..Add(a, ..NewRef(), ..AgoUtc(30 * 86400))
		Set sc = ##class(OcuTalon.Digest.Data.Item).Purge(30)
		If before '= ##class(OcuTalon.Data.Time).NowUtc() Continue
		Set pinned = 1
		Do $$$AssertStatusOK(sc, "a purge within one second of the item's time is OK")
		Do $$$AssertEquals(..CountItem(edge.ItemId), 1, "the item recorded exactly at the cutoff is kept")
		Quit
	}
	Do $$$AssertTrue(pinned, "a purge ran within the second of the cutoff, so that the cutoff was the time of the item")
}

/// A day count that is not a whole number of at least 1 is an error and deletes nothing, through the area and through the table, and the registry names
/// the area.
Method TestPurgeRefuses()
{
	Set a = ..NewRef()
	Set old = ..Add(a, ..NewRef(), ..AgoUtc(91 * 86400))
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Digest).Purge(120), "control: a good day count is OK")
	Do $$$AssertEquals(..CountItem(old.ItemId), 1, "control: and the item of 91 days ago is kept for 120 days")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Digest).Purge(100000), "control: a day count that reaches back before the calendar's first date is OK")
	Do $$$AssertEquals(..CountItem(old.ItemId), 1, "control: and deletes nothing")
	Set bad = $ListBuild("", 0, -1, 1.5, "abc", "00")
	Set position = 0
	While $ListNext(bad, position, days) {
		Do $$$AssertStatusNotOK(##class(OcuTalon.Install.Step.Digest).Purge(days), "the area refuses '"_days_"'")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Digest.Data.Item).Purge(days), "the table refuses '"_days_"'")
		Do $$$AssertEquals(..CountItem(old.ItemId), 1, "and the item of 91 days ago is kept after '"_days_"'")
	}
	Set sc = ##class(OcuTalon.Install.Registry).Purge("")
	Do $$$AssertStatusNotOK(sc, "the registry refuses an empty day count")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Install.Step.Digest", "and names the Digest area: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..CountItem(old.ItemId), 1, "and keeps the item")
}

/// The table's data and index globals are among the private storage globals, resolve to the private database and pass the private-data check.
Method TestPrivate()
{
	Set table = "OcuTalon.Digest.Data.Item"
	Do $$$AssertEquals($Parameter(table, "DEFAULTGLOBAL"), "^OcuTalonP.DigestItem", "the table sets the global of its registry row")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Do $$$AssertEquals($Get(storage("OcuTalonP.DigestItemD")), table, "the data global is listed as the table's")
	Do $$$AssertEquals($Get(storage("OcuTalonP.DigestItemI")), table, "and so is the index global")
	Set private = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.Zz")
	Set compiled = ##class(%Dictionary.CompiledStorage).%OpenId(table_"||Default")
	Do $$$AssertTrue($IsObject(compiled), "the table has compiled storage")
	If $IsObject(compiled) {
		Do $$$AssertEquals(compiled.DataLocation, "^OcuTalonP.DigestItemD", "it stores its data in ^OcuTalonP.DigestItemD")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, compiled.DataLocation), private, "which resolves to the private database")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, compiled.IndexLocation), private, "and so does the index global")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the private-data check passes")
}

/// For the restart row of docker/tests/test-production.sh: keeps two items of one fixture session through the running DigestStore, and checks that
/// each is stamped with a UTC time between the UTC clock before and after the sends (that stack's TZ is not UTC, so a stamp from the item job's local
/// clock shows there). Returns 1, or the reason it could not.
ClassMethod RestartKeep() As %String
{
	Set reason = ..ReadyReason()
	If reason '= "" Quit reason
	Do ..Clean()
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	For number = 1, 2 {
		Set decision = ..Decision(..#RESTARTITEM_number, ..#RESTARTSESSION, "digest", ..#RESTARTDECISION_number, "Restart check "_number)
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, decision)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ##class(OcuTalon.Digest.Data.Item).Since(..#RESTARTSESSION, "", .items)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (before ] entry.recordedAt) || (entry.recordedAt ] after) Return "the item "_entry.itemId_" is stamped "_entry.recordedAt_", not between the UTC clock before ("_before_") and after ("_after_") the sends"
	}
	Quit 1
}

/// For the restart row: the items of the fixture session as the JSON text that Since gives, or the error text.
ClassMethod RestartRead() As %String
{
	Set sc = ##class(OcuTalon.Digest.Data.Item).Since(..#RESTARTSESSION, "", .items)
	Quit $Select($$$ISOK(sc): items.%ToJSON(), 1: "error: "_$SYSTEM.Status.GetErrorText(sc))
}

/// For the restart row: deletes the fixture session's items. Returns how many rows of the fixture are left.
ClassMethod RestartClean() As %Integer
{
	Do ..Clean()
	Quit ..CountSession(..#RESTARTSESSION)
}

/// The assertions of a kept item for the owner.
Method AssertKept(owner As %String) [ Private ]
{
	Set reason = ..ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set itemId = ..NewRef()
	Set decisionRef = ..NewRef()
	Set decision = ..Decision(itemId, owner, "digest", decisionRef)
	Set eventMark = ..EventMark()
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(..#ITEM, decision, .response)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(sc, "the decision is answered OK")
	Do $$$AssertTrue('$IsObject(response), "with no response object")
	Set problems = ..KeptProblems(itemId, owner, decisionRef, "mailbox", "Test "_itemId, before, after)
	Do $$$AssertEquals(problems, "", "one row holds the ItemId, with the message's SessionRef, DecisionRef, Channel and Summary and a RecordedAt between the clock before the send ("_before_") and after it ("_after_")")
	Set session = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionOf(decision, headerMark)
	Do $$$AssertTrue(session '= "", "the send is found in a session")
	If session '= "" Do $$$AssertEquals(..SentOn(session), "[]", "DigestStore sent no message but its reply")
	Do $$$AssertEquals(..LiveEvents(owner, itemId, decisionRef, eventMark), 0, "no live event is on the stream or holds the ItemId or the DecisionRef")
}

/// The problems of the one row that holds the ItemId, joined with "; ", else "": the count of rows with the ItemId (1), its SessionRef (the owner), DecisionRef,
/// Channel and Summary, and its RecordedAt (UTC to the second, between the clocks before and after).
ClassMethod KeptProblems(itemId As %String, owner As %String, decisionRef As %String, channel As %String, summary As %String, before As %String, after As %String) As %String
{
	Set problems = ""
	Set count = ..CountItem(itemId)
	If count '= 1 Quit count_" rows hold the ItemId "_itemId_", not 1"
	Set row = ..RowOf(itemId)
	If '$IsObject(row) Quit "the row of "_itemId_" is not found"
	If row.SessionRef '= owner Set problems = problems_$Select(problems = "": "", 1: "; ")_"SessionRef "_row.SessionRef_" is not the OwnerRef "_owner
	If row.DecisionRef '= decisionRef Set problems = problems_$Select(problems = "": "", 1: "; ")_"DecisionRef "_row.DecisionRef_" is not the message's "_decisionRef
	If row.Channel '= channel Set problems = problems_$Select(problems = "": "", 1: "; ")_"Channel "_row.Channel_" is not "_channel
	If row.Summary '= summary Set problems = problems_$Select(problems = "": "", 1: "; ")_"Summary "_row.Summary_" is not "_summary
	If '(row.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z") {
		Set problems = problems_$Select(problems = "": "", 1: "; ")_"RecordedAt "_row.RecordedAt_" is not UTC to the second"
	} ElseIf (before ] row.RecordedAt) || (row.RecordedAt ] after) {
		Set problems = problems_$Select(problems = "": "", 1: "; ")_"RecordedAt "_row.RecordedAt_" is not between "_before_" and "_after
	}
	Quit problems
}

/// "" when OcuTalon.Production runs with every item (the wait is a poll, up to the fixture's ceiling). Otherwise the reason.
ClassMethod ReadyReason() As %String
{
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "RunningReason")
	If reason '= "" Quit reason
	If '$ClassMethod(fixture, "WaitAllRun") Quit "not every item of "_..#PRODUCTION_" runs: "_##class(OcuTalon.Install.Step.Production).NotRunning()
	Quit ""
}

/// A fixture Ref of 22 characters: the prefix, then a number of this process's database.
ClassMethod NewRef() As %String
{
	Quit ..#PREFIX_$Translate($Justify($Increment(^OcuTalonTest("Digest", "n")), 14), " ", "0")
}

/// A decision for the item, as OutcomeRouter would forward it: channel mailbox unless one is given, a summary of "Test <ItemId>" unless one is given, and a
/// new DecisionRef unless one is given.
ClassMethod Decision(itemId As %String, ownerRef As %String, outcome As %String = "digest", decisionRef As %String = "", summary As %String = "", channel As %String = "mailbox") As OcuTalon.Msg.ItemDecision
{
	Set decision = ##class(OcuTalon.Msg.ItemDecision).%New()
	Set decision.ItemId = itemId
	Set decision.OwnerRef = ownerRef
	Set decision.Channel = channel
	Set decision.Outcome = outcome
	Set decision.DecisionRef = $Select(decisionRef '= "": decisionRef, 1: ..NewRef())
	Set decision.Summary = $Select(summary '= "": summary, 1: "Test "_itemId)
	Quit decision
}

/// Saves a row for the session and item recorded at the time (NewRow), asserts that it is saved, and returns it.
Method Add(sessionRef As %String, itemId As %String, recordedAt As %String) As OcuTalon.Digest.Data.Item
{
	Set row = ..NewRow(sessionRef, itemId, recordedAt, .sc)
	Do $$$AssertStatusOK(sc, "a fixture row is saved")
	Quit row
}

/// A row for the session and item recorded at the time, with a DecisionRef and a Summary of its own, saved; sc is the status of the save.
ClassMethod NewRow(sessionRef As %String, itemId As %String, recordedAt As %String, Output sc As %Status) As OcuTalon.Digest.Data.Item
{
	Set row = ##class(OcuTalon.Digest.Data.Item).%New()
	Set row.SessionRef = sessionRef
	Set row.ItemId = itemId
	Set row.DecisionRef = ..NewRef()
	Set row.Channel = "mailbox"
	Set row.Summary = "Summary "_itemId
	Set row.RecordedAt = recordedAt
	Set sc = row.%Save()
	Quit row
}

/// The UTC time that many seconds before now, YYYY-MM-DDThh:mm:ssZ, from the UTC clock and no zone.
ClassMethod AgoUtc(seconds As %Integer) As %String
{
	Set stamp = $ZTimeStamp
	Set total = ($Piece(stamp, ",", 1) * 86400) + $Piece($Piece(stamp, ",", 2), ".", 1) - seconds
	Quit $Translate($ZDateTime((total \ 86400)_","_(total # 86400), 3, 1), " ", "T")_"Z"
}

/// A Summary of exactly 80 characters for the channel, with single and double quotes, a backslash, a comma, a bar, markup and a character beyond ASCII
/// (e acute, written as its code), padded with x.
ClassMethod LongSummary(channel As %String) As %String
{
	Set text = "Digest "_channel_": 'single' ""double"" back\slash, caf"_$Char(233)_" <b>&amp;</b> | pipe "
	Quit $Extract(text_$Translate($Justify("", 80), " ", "x"), 1, 80)
}

/// The fields of an object that was saved, and its row id, as a dynamic object.
ClassMethod Snapshot(row As OcuTalon.Digest.Data.Item) As %DynamicObject
{
	Quit {"id": (+row.%Id()), "sessionRef": (row.SessionRef), "itemId": (row.ItemId), "decisionRef": (row.DecisionRef), "channel": (row.Channel), "summary": (row.Summary), "recordedAt": (row.RecordedAt)}
}

/// The first row saved with the ItemId, read from the table by SQL at the moment of the call (not through an object that this process holds open, which
/// would show what it read before), as a dynamic object of its row id and fields; "" when there is none.
ClassMethod Stored(itemId As %String) As %DynamicObject
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionRef, ItemId, DecisionRef, Channel, Summary, RecordedAt FROM OcuTalon_Digest_Data.Item WHERE ItemId = ? ORDER BY ID", itemId)
	If 'result.%Next() Quit ""
	Quit {"id": (+result.%Get("ID")), "sessionRef": (result.%Get("SessionRef")), "itemId": (result.%Get("ItemId")), "decisionRef": (result.%Get("DecisionRef")), "channel": (result.%Get("Channel")), "summary": (result.%Get("Summary")), "recordedAt": (result.%Get("RecordedAt"))}
}

/// Returns when the UTC clock is past the time (up to 5 seconds, polling every 50 ms).
ClassMethod WaitPast(time As %String)
{
	Set stop = $ZHorolog + 5
	While ($ZHorolog < stop) && '(##class(OcuTalon.Data.Time).NowUtc() ] time) {
		Hang 0.05
	}
}

/// The text with the case of its letters swapped.
ClassMethod SwapCase(text As %String) As %String
{
	Set swapped = ""
	For i = 1:1:$Length(text) {
		Set char = $Extract(text, i)
		Set swapped = swapped _ $Select(char ? 1U: $ZConvert(char, "L"), char ? 1L: $ZConvert(char, "U"), 1: char)
	}
	Quit swapped
}

/// The ItemIds of the entries of an array that Since gave, in order, separated by spaces.
ClassMethod ItemIdsOf(items As %DynamicArray) As %String
{
	Set order = ""
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set order = order _ $Select(order = "": "", 1: " ") _ entry.itemId
	}
	Quit order
}

/// The keys of the entries of an array that Since gave: each entry's keys separated by commas, the entries by bars.
ClassMethod KeysOf(items As %DynamicArray) As %String
{
	Set all = ""
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set keys = ""
		Set inner = entry.%GetIterator()
		While inner.%GetNext(.key) {
			Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
		}
		Set all = all _ $Select(all = "": "", 1: "|") _ keys
	}
	Quit all
}

/// The first row saved with the ItemId, compared exactly, or "".
ClassMethod RowOf(itemId As %String) As OcuTalon.Digest.Data.Item
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Digest_Data.Item WHERE ItemId = ? ORDER BY ID", itemId)
	If result.%Next() Quit ##class(OcuTalon.Digest.Data.Item).%OpenId(result.%GetData(1))
	Quit ""
}

/// The number of rows with the ItemId, compared exactly.
ClassMethod CountItem(itemId As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Item WHERE ItemId = ?", itemId)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of rows of the session, compared exactly.
ClassMethod CountSession(sessionRef As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Item WHERE SessionRef = ?", sessionRef)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of rows of the table.
ClassMethod CountAll() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Item")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The headers of the session that DigestStore is the source of, as the JSON of an array, without its reply to the service that sent the request (the sender
/// ApprovalStartIn, no message body): what it sent on. "[]" when it sent nothing.
ClassMethod SentOn(session As %Integer) As %String
{
	Set sent = []
	Set iterator = ##class(OcuTalon.Test.Agent.RunnerFixture).Headers(session, ..#ITEM).%GetIterator()
	While iterator.%GetNext(, .header) {
		If (header.target = "ApprovalStartIn") && (header.bodyClass = "") Continue
		Do sent.%Push(header)
	}
	Quit sent.%ToJSON()
}

/// The highest id of the live events: the mark that LiveEvents reads from.
ClassMethod EventMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Live.Event")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of live events after the mark that hold the ItemId or the DecisionRef in their payload, and, for a session's stream, that are on it
/// (the stream of a fresh fixture Ref has no other events). The stream instance is shared by every test, so only a payload counts there. -1 when the
/// query fails, so that a changed table cannot read as "no event".
ClassMethod LiveEvents(ownerRef As %String, itemId As %String, decisionRef As %String, mark As %Integer) As %Integer
{
	Set sql = "SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE ID > ? AND (Payload [ ? OR Payload [ ?"
	If ownerRef '= "instance" Set sql = sql_" OR Stream = ?"
	Set sql = sql_")"
	If ownerRef '= "instance" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, sql, mark, itemId, decisionRef, ownerRef)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, sql, mark, itemId, decisionRef)
	}
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Deletes every row whose ItemId or SessionRef begins with the fixture prefix, or with the prefix with the case of its letters swapped.
ClassMethod Clean()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE ItemId %STARTSWITH ? OR ItemId %STARTSWITH ? OR SessionRef %STARTSWITH ? OR SessionRef %STARTSWITH ?", ..#PREFIX, ..#SWAPPED, ..#PREFIX, ..#SWAPPED)
}

}
