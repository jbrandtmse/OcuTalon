/// Tests of the precedent table (Story 41.2; AD-3, AD-5, AD-21, AD-27): KeyFor, KeyForRequest, Similar, View, Has, DropSession, RemoveRun and Purge of
/// OcuTalon.Data.Precedent, and the three Core.Msg contracts of the story. Safe on a slot: no production is needed. Each test saves its
/// rows directly (the one writer, PrecedentOps, is tested in Test.Core.PrecedentOps) and removes them by Ref in OnAfterOneTest.
///   - TestKeyFor: the KeyFor rows of the matrix (mail, webhook, slack, heartbeat, check finding; "" for a user item, no object and an unknown channel);
///   - TestKeyForCheckFinding: a finding keys through the one production check of the item's session with that display name, else "";
///   - TestKeyForRequest: the fix and tool_call forms of an approval request;
///   - TestSimilarBounds: newest first, at most min(limit, 3), [] for limit under 1 and for an empty argument, the view's members;
///   - TestSimilarKeepsOwnersApart: a person's rows, another person's and seeded rows are never mixed;
///   - TestHasAndDropSession: Has, DropSession (not another session's rows, not eval rows) and RemoveRun;
///   - TestPurge: the 100-day row (a seeded one too) goes and the 10-day row stays; a bad day count is an error and deletes nothing; the Core area's Purge
///     deletes a row answered in 1900;
///   - TestMessageContracts: the contracts of RecordPrecedent, SeedPrecedent and RemoveSeededPrecedents.
Class OcuTalon.Test.Data.Precedent Extends OcuTalon.Test.Contract
{

/// The run's number.
Property Number As %Integer;

/// The count of sessions and rows made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the Precedent rows of the test, comma-separated.
Property Rows As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("PrecedentTable", "n"))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Rows, ",") {
		Set ref = $Piece(..Rows, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Precedent).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Precedent).%DeleteId(row.%Id())
		}
	}
	Set ..Rows = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

/// The matrix rows of KeyFor: the address of a mail sender in any of its forms, the source of a webhook or a Slack message, heartbeat, and "" for an item
/// that is not untrusted, one that is no object and a channel with no key form.
Method TestKeyFor()
{
	Set key = "OcuTalon.Data.Precedent"
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("mailbox", "Zz <Zz.A@Example.com>")), "zz.a@example.com", "mailbox: Name <A@B.c> gives a@b.c")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("email", "Zz.A@Example.com ")), "zz.a@example.com", "email: a bare A@B.c with a blank gives a@b.c")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("mailbox", "  <Zz.B@Example.com>")), "zz.b@example.com", "mailbox: <A@B.c> alone gives a@b.c")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("mailbox", "Zz <Zz.First@Example.com> and <Zz.Last@Example.com>")), "zz.last@example.com", "mailbox: the last <...> wins")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("webhook", " Src ")), "src", "webhook: the Sender, trimmed and lowercased")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("slack", " Src ")), "src", "slack: the Sender, trimmed and lowercased")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("heartbeat", "")), "heartbeat", "heartbeat gives heartbeat")
	Do $$$AssertEquals($Length($ClassMethod(key, "KeyFor", ..Item("webhook", $Translate($Justify("", 600), " ", "a")))), 512, "a key is cut at 512 characters")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("mailbox", "Zz <Zz.A@Example.com>", "user")), "", "provenance user gives no key")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("mailbox", "Zz <Zz.A@Example.com>", "")), "", "an item that is not untrusted gives no key")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ""), "", "no object gives no key")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ##class(OcuTalon.Msg.ItemDecision).%New()), "", "an object that is no Item gives no key")
	For channel = "web", "phone", "telegram", "zz", "" {
		Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item(channel, "Zz <Zz.A@Example.com>")), "", "the channel '"_channel_"' has no key form")
	}
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", ..Item("mailbox", "  ")), "", "an empty sender gives no key")
}

/// A check finding (channel system) has Slots.production, the display name of a check. KeyFor finds the one production check of the item's session with that
/// display name, and answers production:<Namespace>/<Production>; zero matches and two matches answer "".
Method TestKeyForCheckFinding()
{
	Set key = "OcuTalon.Data.Precedent"
	Set session = ..Session("find"), other = ..Session("findother")
	Set check = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNSA", "Zz.ProdA", {"DisplayName": "Zz Orders A"})
	Set ..Refs = ..Refs_","_check
	Set otherCheck = ##class(OcuTalon.Test.Data.Fixture).Check(other, "ZZNSB", "Zz.ProdB", {"DisplayName": "Zz Orders B"})
	Set ..Refs = ..Refs_","_otherCheck
	Set item = ..Item("system", "", "untrusted", session, {"production": "Zz Orders A"}.%ToJSON())
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "production:ZZNSA/Zz.ProdA", "one matching check gives production:<Namespace>/<Production>")
	Set item = ..Item("system", "", "untrusted", session, {"production": "Zz Orders B"}.%ToJSON())
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "", "the display name of another session's check gives no key")
	Set item = ..Item("system", "", "untrusted", session, {"production": "Zz Nothing"}.%ToJSON())
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "", "no matching check gives no key")
	Set item = ..Item("system", "", "untrusted", session, {"other": "Zz Orders A"}.%ToJSON())
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "", "no Slots.production gives no key")
	Set item = ..Item("system", "", "untrusted", session, "zz not json")
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "", "Slots that are no JSON give no key")
	Set second = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNSC", "Zz.ProdC", {"DisplayName": "Zz Orders A"})
	Set ..Refs = ..Refs_","_second
	Set item = ..Item("system", "", "untrusted", session, {"production": "Zz Orders A"}.%ToJSON())
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "", "two matching checks give no key")
	Set item = ..Item("system", "", "untrusted", "instance", {"production": "Zz Orders A"}.%ToJSON())
	Do $$$AssertEquals($ClassMethod(key, "KeyFor", item), "", "an item of owner instance gives no key")
}

/// The key of an approval request: a fix is keyed by its incident's production, with channel system and the summary of the incident's Decision; a tool_call by
/// tool:<ToolName>, with no channel and the tool's name; a setting and an incomplete request have none.
Method TestKeyForRequest()
{
	Set key = "OcuTalon.Data.Precedent"
	Set session = ..Session("request")
	Set diagnose = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "diagnose", , {"Summary": "Zz order dates are in the wrong format"})
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , "ZZNS", "Zz.Production", {"DecisionRef": (diagnose)})
	Set bare = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , "ZZNS", "Zz.Bare")
	Set fix = ##class(OcuTalon.Test.Data.Fixture).Approval(session, incident)
	Set fixBare = ##class(OcuTalon.Test.Data.Fixture).Approval(session, bare)
	Set tool = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , , , {"Kind": "tool_call", "ToolName": "Zz.Tool"})
	Set toolNone = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , , , {"Kind": "tool_call"})
	Set setting = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , , , {"Kind": "setting"})
	Set unknown = ##class(OcuTalon.Test.Data.Fixture).Approval(session, "zzunknownincident")
	Set ..Refs = ..Refs_","_diagnose_","_incident_","_bare_","_fix_","_fixBare_","_tool_","_toolNone_","_setting_","_unknown
	Set found = $ClassMethod(key, "KeyForRequest", ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(fix), .channel, .summary)
	Do $$$AssertEquals(found_"|"_channel_"|"_summary, "production:ZZNS/Zz.Production|system|Zz order dates are in the wrong format", "a fix: the incident's production, system and the incident Decision's summary")
	Set found = $ClassMethod(key, "KeyForRequest", ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(fixBare), .channel, .summary)
	Do $$$AssertEquals(found_"|"_channel_"|"_summary, "production:ZZNS/Zz.Bare|system|production:ZZNS/Zz.Bare", "a fix whose incident has no Decision: the key is the summary")
	Set found = $ClassMethod(key, "KeyForRequest", ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(tool), .channel, .summary)
	Do $$$AssertEquals(found_"|"_channel_"|"_summary, "tool:Zz.Tool||Zz.Tool", "a tool_call: tool:<ToolName>, no channel, the tool's name")
	For case = toolNone, setting, unknown {
		Set found = $ClassMethod(key, "KeyForRequest", ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(case), .channel, .summary)
		Do $$$AssertEquals(found_"|"_channel_"|"_summary, "||", "a request with no key form gives nothing")
	}
	Do $$$AssertEquals($ClassMethod(key, "KeyForRequest", "", .channel, .summary), "", "no request gives nothing")
}

/// Five rows with one key: Similar answers the newest first, at most min(limit, 3), and [] for a limit under 1 and for an empty owner, channel or key. Each
/// item has exactly the seven members of the view.
Method TestSimilarBounds()
{
	Set owner = ..Session("bounds")
	For i = 1:1:5 {
		Do ..Make(owner, "mailbox", "zz.bounds@example.com", "noise", "2030-01-0"_i_"T10:00:00Z")
	}
	Set expected = $ListBuild("2030-01-05T10:00:00Z", "2030-01-04T10:00:00Z", "2030-01-03T10:00:00Z")
	For limit = 0, -1, "x", "" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.bounds@example.com", limit).%Size(), 0, "limit '"_limit_"' gives []")
	}
	Do $$$AssertEquals(..Times(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.bounds@example.com", 1)), "2030-01-05T10:00:00Z", "limit 1: the newest")
	Do $$$AssertEquals(..Times(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.bounds@example.com", 3)), $ListToString(expected), "limit 3: three, newest first")
	Do $$$AssertEquals(..Times(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.bounds@example.com", 7)), $ListToString(expected), "limit 7: still three")
	Do $$$AssertEquals(..Times(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.bounds@example.com")), $ListToString(expected), "the default limit: three")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar("", "mailbox", "zz.bounds@example.com").%Size(), 0, "an empty owner gives []")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(owner, "", "zz.bounds@example.com").%Size(), 0, "an empty channel gives []")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "").%Size(), 0, "an empty key gives []")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.other@example.com").%Size(), 0, "another key gives []")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(owner, "webhook", "zz.bounds@example.com").%Size(), 0, "another channel gives []")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "ZZ.BOUNDS@example.com").%Size(), 0, "a key is compared exactly")
	Set item = ##class(OcuTalon.Data.Precedent).Similar(owner, "mailbox", "zz.bounds@example.com", 1).%Get(0)
	Set names = ""
	Set iterator = item.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set names = names_$Select(names = "": "", 1: ",")_name
		Do $$$AssertEquals(item.%GetTypeOf(name), "string", name_" is a string")
	}
	Do $$$AssertEquals(names, "ref,answeredAt,channel,answeredChannel,summary,outcome,answer", "the view's members, in order")
	Do $$$AssertEquals(item.channel_"|"_item.answeredChannel_"|"_item.answer_"|"_item.outcome, "mailbox|phone|noise|tellnow", "and their values")
}

/// A person's rows, another person's and the seeded ones are separate: Similar answers a person's own, and the owner eval's seeded rows.
Method TestSimilarKeepsOwnersApart()
{
	Set a = ..Session("apartA"), b = ..Session("apartB"), run = ..RunRef()
	Set mine = ..Make(a, "mailbox", "zz.apart@example.com", "noise", "2030-01-01T10:00:00Z")
	Set theirs = ..Make(b, "mailbox", "zz.apart@example.com", "noise", "2030-01-02T10:00:00Z")
	Set seeded = ..Make("eval", "mailbox", "zz.apart@example.com", "noise", "2030-01-03T10:00:00Z", run)
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Precedent).Similar(a, "mailbox", "zz.apart@example.com")), mine, "A gets only its own row")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Precedent).Similar(b, "mailbox", "zz.apart@example.com")), theirs, "B gets only its own row")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Precedent).Similar("eval", "mailbox", "zz.apart@example.com")), seeded, "the owner eval gets only the seeded row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar("instance", "mailbox", "zz.apart@example.com").%Size(), 0, "the owner instance gets none")
	Set odd = ..Make(a, "mailbox", "zz.apart@example.com", "noise", "2030-01-04T10:00:00Z", run)
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Precedent).Similar(a, "mailbox", "zz.apart@example.com")), mine, "a session's row that has an EvalRunRef is not returned to the session")
}

/// Has is 1 for a session with rows of its own only; DropSession deletes that session's rows and no other session's, no seeded row, and is OK for an
/// empty session, instance and eval; RemoveRun deletes the rows of one run and no other row.
Method TestHasAndDropSession()
{
	Set a = ..Session("dropA"), b = ..Session("dropB"), runOne = ..RunRef(), runTwo = ..RunRef()
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Has(a), 0, "a session with no rows has none")
	Do ..Make(a, "mailbox", "zz.drop.a1@example.com", "noise", "2030-01-01T10:00:00Z")
	Do ..Make(a, "webhook", "zz.drop.a2", "noise", "2030-01-02T10:00:00Z")
	Do ..Make(b, "mailbox", "zz.drop.b@example.com", "noise", "2030-01-03T10:00:00Z")
	Do ..Make("eval", "mailbox", "zz.drop.e1@example.com", "noise", "2030-01-04T10:00:00Z", runOne)
	Do ..Make("eval", "mailbox", "zz.drop.e2@example.com", "noise", "2030-01-05T10:00:00Z", runOne)
	Do ..Make("eval", "mailbox", "zz.drop.e3@example.com", "noise", "2030-01-06T10:00:00Z", runTwo)
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Has(a)_"|"_##class(OcuTalon.Data.Precedent).Has(b), "1|1", "both sessions have rows")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Has("")_"|"_##class(OcuTalon.Data.Precedent).Has("eval")_"|"_##class(OcuTalon.Data.Precedent).Has("instance"), "0|0|0", "an empty session, eval and instance have none")
	For none = "", "eval", "instance" {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Precedent).DropSession(none), "DropSession('"_none_"') is OK")
	}
	Set before = ..Owned("eval")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Precedent).DropSession(a), "DropSession(A) is OK")
	Do $$$AssertEquals(..Owned(a)_"|"_..Owned(b)_"|"_..Owned("eval"), "0|1|"_before, "A's rows are gone, B's and the seeded rows stay")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Has(a), 0, "A has none")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Precedent).DropSession(a), "a second DropSession is OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Precedent).RemoveRun("", .count), "RemoveRun('') is OK")
	Do $$$AssertEquals(count, 0, "and finds nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Precedent).RemoveRun(runOne, .count), "RemoveRun(run one) is OK")
	Do $$$AssertEquals(count_"|"_..Owned("eval")_"|"_..Owned(b), "2|"_(before - 2)_"|1", "two rows of run one are gone, run two's and B's stay")
}

/// Purge(90) deletes a row answered 100 days ago, a seeded one too, and keeps one answered 10 days ago; Purge(0), Purge("x") and Purge("") are an error that
/// names the class and delete nothing; the Core area's Purge(36500) deletes a row answered in 1900.
Method TestPurge()
{
	Set owner = ..Session("purge"), run = ..RunRef()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set recent = ..Make(owner, "mailbox", "zz.purge.new@example.com", "noise", ##class(OcuTalon.Data.Time).AddSeconds(now, -10 * 86400))
	Set old = ..Make(owner, "mailbox", "zz.purge.old@example.com", "noise", ##class(OcuTalon.Data.Time).AddSeconds(now, -100 * 86400))
	Set oldSeed = ..Make("eval", "mailbox", "zz.purge.seed@example.com", "noise", ##class(OcuTalon.Data.Time).AddSeconds(now, -100 * 86400), run)
	For days = 0, "x", "", -3, "1.5" {
		Set sc = ##class(OcuTalon.Data.Precedent).Purge(days)
		Do $$$AssertStatusNotOK(sc, "Purge('"_days_"') is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Data.Precedent.Purge", "and names the class")
	}
	Do $$$AssertEquals(..Exists(recent)_..Exists(old)_..Exists(oldSeed), "111", "a refused Purge deletes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Precedent).Purge(90), "Purge(90) is OK")
	Do $$$AssertEquals(..Exists(recent)_..Exists(old)_..Exists(oldSeed), "100", "the 100-day rows (a seeded one too) are gone and the 10-day row stays")
	Set ancient = ..Make(owner, "mailbox", "zz.purge.ancient@example.com", "noise", "1900-01-01T10:00:00Z")
	Do $$$AssertEquals(..Exists(ancient), 1, "a row answered in 1900 exists")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Core).Purge(36500), "the Core area's Purge(36500) is OK")
	Do $$$AssertEquals(..Exists(ancient)_..Exists(recent), "01", "it deletes the row answered in 1900 and keeps the recent one")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Install.Step.Core).Purge(0), "the Core area's Purge(0) is an error")
}

/// The three messages that PrecedentOps takes besides the verbs have exactly their contracts, and the class sets its global.
Method TestMessageContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
	For class = "OcuTalon.Core.Msg.RecordPrecedent", "OcuTalon.Core.Msg.SeedPrecedent", "OcuTalon.Core.Msg.RemoveSeededPrecedents" {
		Do $$$AssertEquals($Parameter(class, "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", class_" is answered with a CommandResult")
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Data.Precedent", "DEFAULTGLOBAL"), "^OcuTalonP.Precedent", "the table's global")
	Do $$$AssertEquals($Parameter("OcuTalon.Data.Precedent", "ANSWERS"), "noise,approved,rejected", "the answers")
	Do $$$AssertEquals($Parameter("OcuTalon.Data.Precedent", "SIMILARMAX"), 3, "Similar returns at most three rows")
}

/// --- helpers ---
/// An unsaved Item of the channel, the sender and the provenance, for the session (default a fixture's) with the slots.
Method Item(channel As %String, sender As %String, provenance As %String = "untrusted", session As %String = "zzprecsession", slots As %String = "") As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = session
	Set item.Channel = channel
	Set item.Provenance = provenance
	Set item.Sender = sender
	Set item.Slots = slots
	Quit item
}

/// A fixture session, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzprecedent"_..Number_name_..Count)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A new run Ref, which no other run has.
Method RunRef() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ids).NewRef()
}

/// Saves a Precedent row and records it for the clean-up. Returns its Ref. A run Ref makes it a seeded row.
Method Make(owner As %String, channel As %String, key As %String, answer As %String, answeredAt As %String, run As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = owner
	Set row.Channel = channel
	Set row.MatchKey = key
	Set row.Summary = "zz summary"
	Set row.Outcome = "tellnow"
	Set row.Answer = answer
	Set row.AnsweredAt = answeredAt
	Set row.AnsweredChannel = "phone"
	Set row.SourceRef = row.Ref
	Set row.EvalRunRef = run
	Do $$$AssertStatusOK(row.%Save(), "a fixture row is saved")
	Set ..Rows = ..Rows_$Select(..Rows = "": "", 1: ",")_row.Ref
	Quit row.Ref
}

/// The AnsweredAt of each item, comma-separated.
Method Times(items As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	For i = 0:1:items.%Size() - 1 {
		Set text = text_$Select(text = "": "", 1: ",")_items.%Get(i).answeredAt
	}
	Quit text
}

/// The Refs of the items of Similar, comma-separated.
Method RefsOf(items As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	For i = 0:1:items.%Size() - 1 {
		Set text = text_$Select(text = "": "", 1: ",")_items.%Get(i).ref
	}
	Quit text
}

/// The number of Precedent rows of the owner.
Method Owned(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Precedent WHERE OwnerRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// 1 when the row with the Ref exists.
Method Exists(ref As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Precedent).RefIndexExists(ref)
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Core.Msg.RecordPrecedent": {
  "super": "Ens.Request",
  "props": {
   "ApprovalRef": "%String(MAXLEN=22)",
   "Action": "%String(MAXLEN=32)",
   "Channel": "%String(MAXLEN=32)",
   "SessionRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Core.Msg.SeedPrecedent": {
  "super": "Ens.Request",
  "props": {
   "RunRef": "%String(MAXLEN=22)",
   "Channel": "%String(MAXLEN=32)",
   "MatchKey": "%String(MAXLEN=512)",
   "Summary": "%String(MAXLEN=80)",
   "Outcome": "%String(MAXLEN=32)",
   "Answer": "%String(MAXLEN=32)",
   "AnsweredAt": "%String(MAXLEN=20)"
  }
 },
 "OcuTalon.Core.Msg.RemoveSeededPrecedents": {
  "super": "Ens.Request",
  "props": {
   "RunRef": "%String(MAXLEN=22)"
  }
 }
}
}

}
