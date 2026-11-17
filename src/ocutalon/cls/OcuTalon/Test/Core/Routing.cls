/// Tests of the routing rules of Story 2.7 (AD-4, AD-14, AD-30, AD-32): OcuTalon.Core.Rule.Outcome, OcuTalon.Core.Rule.Notify, the
/// transform OcuTalon.Core.Rule.Notice and the function set OcuTalon.Core.Rule.Functions. Safe on a slot: a rule is evaluated
/// without a production, the way the router does it, by Ens.Rule.RuleDefinition.EvaluateRulesEx on a shadow instance of
/// EnsLib.MsgRouter.RoutingEngine whose Document, MsgClass and Source are set. The router's session id is the number 0, because
/// the engine of a shadow instance has no process to take it from; the return value is the router's action list, one
/// send:<targets>:<transform> entry per action, and "" for no action. The real router, over the running production, is the job of
/// OcuTalon.Test.Core.RoutingProduction. Every target and every text is written out here, never read from the rules or the catalog.
///   - TestOutcomeRoutes: each outcome, with and without a CatalogKey, for an owner that is a session, instance and eval;
///   - TestNoticeTransform: the three cases of the Notification's key and slots, the first reason line, and each error;
///   - TestNotifyTargets: each kind of Notification with demo mode on and off, with and without a pairing and with Telegram
///     included or not, a reply that came from the web and from Telegram, and a pairing notice with and without a ChatRef;
///     the kind digest on top of that for no digest.channels row and for each value the setting can hold;
///   - TestNotifyPageTargets (Story 24.3a; P1 Option A): kind page is routed by the Data.Page row that its DecisionRef names: nothing for no row, for an address-only person
///     (SessionRef instance) and on the online demo (the flag onlineDemo, not demo mode); otherwise WebChatOut always, and TelegramOut as well when Telegram is included and the row's Channels names telegram, paired or not and
///     never by the pairing; never the simulated phone; a handled Notification for a page takes the generic route and never EmailOut; and the rule PageEmail, which adds EmailOut for a row that names email only while EmailOut has an alive job, so every expected target
///     list here is derived from whether EmailOut has a job on the stack (its cases with a job are also those of OcuTalon.Test.Channel.PageRoute);
///   - TestNotifyDigestEmail (Story 21.7): the rule DigestEmail adds no target to a digest while EmailOut has no alive job (the production here does not run it),
///     whatever digest.channels, email.owner, email.address and the demo flag say; with a job it is the job of OcuTalon.Test.Channel.EmailLive;
///   - TestNotifySlackTargets (Story 27.2): a reply of a Slack turn goes to WebChatOut and SlackOut only while Slack is on (both variables set, not the online demo) and the session
///     has a Data.SlackLink row, and to WebChatOut alone otherwise; a reply of any other channel never goes to SlackOut; and no kind of Notification goes to SlackOut, whatever
///     Slack and the link say;
///   - TestFunctions: the functions of the rules, and that the rules resolve them from OcuTalon.Core.Rule.Functions alone;
///   - TestRuleTargetsAreProductionItems: the two router items use these rules, and every target and transform that a rule
///     names exists in the production.
/// The fixture sessions come from Test.Data.Fixture. The test restores the demo.mode and digest.channels settings (as Test.Demo.Step
/// saves and puts demo.mode back) and the test-only switch ^OcuTalonTest("TelegramIncluded") as it found them. The run's number is n from
/// ^OcuTalonTest("Routing","n") (never reset).
Class OcuTalon.Test.Core.Routing Extends %UnitTest.TestCase
{

/// The rule of the OutcomeRouter item.
Parameter OUTCOMERULE = "OcuTalon.Core.Rule.Outcome";

/// The rule of the Notify item.
Parameter NOTIFYRULE = "OcuTalon.Core.Rule.Notify";

/// The workspace of the Slack fixture links.
Parameter SLACKTEAM = "T0ROUTING";

/// The setting that a digest follows.
Parameter CHANNELSKEY = "digest.channels";

/// The run's number.
Property Number As %Integer;

/// The online demo's flag (onlineDemo) before the run.
Property SavedOnline As %String;

/// The number of Data.Page fixture rows of the run.
Property PageRows As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// 1 when the demo.mode row existed before the run, with its value and UpdatedAt.
Property SavedFound As %Boolean;

Property SavedValue As %String;

Property SavedUpdatedAt As %String;

/// The value of ^OcuTalonTest("TelegramIncluded") before the run, "" when it was absent.
Property SavedIncluded As %String;

/// The digest.channels row before the run: $ListBuild(existed, value, updatedAt).
Property SavedChannels As %List;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("Routing", "n"))
	Set ..Refs = ""
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedFound = found, ..SavedValue = value, ..SavedUpdatedAt = updatedAt
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..SavedIncluded = $Get(^OcuTalonTest("TelegramIncluded"))
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(..#CHANNELSKEY)
	Set ..SavedChannels = $Select($IsObject(row): $ListBuild(1, row.Value, row.UpdatedAt), 1: $ListBuild(0, "", ""))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedFound, ..SavedValue, ..SavedUpdatedAt)
	Do ..PutChannels($Select($List(..SavedChannels, 1): $List(..SavedChannels, 2), 1: ""), $List(..SavedChannels, 1), $List(..SavedChannels, 3))
	If ..SavedIncluded = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedIncluded
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Page WHERE IncidentRef LIKE ?", "zzroute"_..Number_"p%")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId = ?", ..#SLACKTEAM)
	Quit $SYSTEM.Status.OK()
}

/// OutcomeRouter's rule: an ItemDecision of owner eval routes nowhere; digest goes unchanged to DigestStore for a session and
/// instance owner; tellnow and act go to Notify through the transform Notice for a session owner only; ignore, and an instance or
/// unknown owner's tell now or act, route nowhere. A CatalogKey on the ItemDecision changes nothing about the route.
Method TestOutcomeRoutes()
{
	Set session = ..Session("outcome")
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set owners = $ListBuild($ListBuild("a session", session), $ListBuild("instance", "instance"), $ListBuild("eval", "eval"), $ListBuild("an unknown session", unknown))
	Set outcomes = $ListBuild("ignore", "digest", "tellnow", "act", "zzunknown")
	Set position = 0
	While $ListNext(owners, position, owner) {
		Set kind = $List(owner, 1), ref = $List(owner, 2)
		Set at = 0
		While $ListNext(outcomes, at, outcome) {
			For keyed = 0, 1 {
				Set decision = ..Decision(ref, outcome)
				If keyed {
					Set decision.CatalogKey = "watch.productionStopped"
					Set decision.Slots = "{""production"":""Orders"",""time"":""2026-10-16T18:12:00Z""}"
				}
				Set expected = ""
				If (ref '= "eval") && (outcome = "digest") Set expected = "send:DigestStore:"
				If (ref = session) && ((outcome = "tellnow") || (outcome = "act")) Set expected = "send:Notify:OcuTalon.Core.Rule.Notice"
				Do $$$AssertEquals(..Route(..#OUTCOMERULE, decision), expected, outcome_" for "_kind_$Select(keyed: " with a CatalogKey", 1: "")_": ["_expected_"]")
			}
		}
	}
}

/// The transform of the tell-now route. A CatalogKey on the ItemDecision is used with its slots as they are. A fallback uses
/// notice.tellNowFallback with the summary and the fallback reason (unusable when it is empty or unknown), and reads no Decision
/// row, so a fallback whose DecisionRef names no row keeps that DecisionRef. Otherwise it is
/// notice.tellNow with the summary and the first line of the Reasons of the owner's Decision row. Each Notification is of kind
/// tellnow, for the owner, with the DecisionRef, and renders to the catalog's text. The row of another owner, an unknown row, no
/// DecisionRef, an empty first line and an empty summary are errors, with no Notification.
Method TestNoticeTransform()
{
	Set session = ..Session("transform")
	Set other = ..Session("transformother")
	Set mine = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Reasons": ("zz first."_$Char(10)_"zz second.")})
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Decision(other, "decide", , {"Reasons": "zz theirs."})
	Set noReason = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Reasons": ""})
	Set blankFirst = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Reasons": ($Char(10)_"zz second.")})
	Set crlf = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Reasons": ("  zz crlf first.  "_$Char(13, 10)_"zz second.")})
	Set ..Refs = ..Refs_","_mine_","_theirs_","_noReason_","_blankFirst_","_crlf

	Set decision = ..Decision(session, "tellnow")
	Set decision.DecisionRef = mine
	Set decision.Summary = "zz Dana: Invoice"
	Set notification = ..Transform(decision, .sc)
	Do $$$AssertStatusOK(sc, "a decision with a reason is transformed")
	Do $$$AssertEquals(notification.SessionRef_"|"_notification.Kind_"|"_notification.DecisionRef, session_"|tellnow|"_mine, "a Notification of kind tellnow for the owner, with the DecisionRef")
	Do $$$AssertEquals(notification.CatalogKey_"|"_notification.Slots, "notice.tellNow|{""whatHappened"":""zz Dana: Invoice"",""reason"":""zz first.""}", "notice.tellNow, the summary and the first reason line")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(notification.CatalogKey, notification.Slots, "web", .sc), "zz Dana: Invoice"_$Char(10)_"Why now: zz first.", "which renders to the summary and the Why now line")
	Do $$$AssertEquals(notification.ChatRef_"|"_notification.ApprovalRef_"|"_notification.IncidentRef, "||", "and sets nothing else")
	Do $$$AssertEquals(decision.CatalogKey_"|"_decision.Slots, "|", "the ItemDecision itself is left as it was")

	Set decision.Outcome = "act"
	Set notification = ..Transform(decision, .sc)
	Do $$$AssertEquals(notification.Kind_"|"_notification.CatalogKey, "tellnow|notice.tellNow", "an act is also a tellnow Notification")

	Set decision.DecisionRef = crlf
	Set notification = ..Transform(decision, .sc)
	Do $$$AssertEquals(notification.Slots, "{""whatHappened"":""zz Dana: Invoice"",""reason"":""zz crlf first.""}", "the first line has no line break and no white space around it")

	Set decision = ..Decision(session, "tellnow")
	Set decision.CatalogKey = "watch.productionStopped"
	Set decision.Slots = "{""production"":""Orders"",""time"":""2026-10-16T18:12:00Z""}"
	For case = "plain", "fallback", "nosummary", "nodecision" {
		Set label = "a CatalogKey ("_case_")"
		Set decision.Fallback = (case = "fallback")
		Set decision.FallbackReason = $Select(case = "fallback": "refusal", 1: "")
		Set decision.Summary = $Select(case = "nosummary": "", 1: "zz summary")
		Set decision.DecisionRef = $Select(case = "nodecision": "", 1: mine)
		Set notification = ..Transform(decision, .sc)
		Do $$$AssertStatusOK(sc, label_" is transformed")
		Do $$$AssertEquals(notification.SessionRef_"|"_notification.Kind_"|"_notification.DecisionRef, session_"|tellnow|"_decision.DecisionRef, label_": for the owner, kind tellnow, the DecisionRef")
		Do $$$AssertEquals(notification.CatalogKey_"|"_notification.Slots, "watch.productionStopped|{""production"":""Orders"",""time"":""2026-10-16T18:12:00Z""}", label_": that key and those slots, as they are")
	}

	Set decision = ..Decision(session, "tellnow")
	Set decision.Fallback = 1
	Set decision.Summary = "zz Dana: Invoice"
	Set cases = $ListBuild($ListBuild("refusal", "refusal"), $ListBuild("timeout", "timeout"), $ListBuild("", "unusable"), $ListBuild("zz_unknown", "unusable"), $ListBuild("Refusal", "unusable"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set decision.FallbackReason = $List(case, 1)
		Set notification = ..Transform(decision, .sc)
		Set label = "a fallback with the reason '"_$List(case, 1)_"'"
		Do $$$AssertStatusOK(sc, label_" is transformed")
		Do $$$AssertEquals(notification.CatalogKey_"|"_notification.Slots, "notice.tellNowFallback|{""whatHappened"":""zz Dana: Invoice"",""reason"":"""_$List(case, 2)_"""}", label_": notice.tellNowFallback, the summary and the reason "_$List(case, 2))
	}
	Set decision.FallbackReason = "refusal"
	Set notification = ..Transform(decision, .sc)
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(notification.CatalogKey, notification.Slots, "web", .sc), "zz Dana: Invoice"_$Char(10)_"Why now: the model declined to answer", "a fallback renders to the summary and the words of its reason")
	Set decision.DecisionRef = "ZzNoRowForThis"
	Set notification = ..Transform(decision, .sc)
	Do $$$AssertStatusOK(sc, "a fallback needs no Decision row, it has none")
	If $IsObject(notification) Do $$$AssertEquals(notification.CatalogKey_"|"_notification.DecisionRef_"|"_notification.Slots, "notice.tellNowFallback|ZzNoRowForThis|{""whatHappened"":""zz Dana: Invoice"",""reason"":""refusal""}", "and keeps its DecisionRef, with notice.tellNowFallback and its reason")
	Set decision.DecisionRef = ""
	Do ..Transform(decision, .sc)
	Do $$$AssertStatusOK(sc, "and may have no DecisionRef")

	Set errors = $ListBuild($ListBuild("the Decision row of another owner", theirs, 0, "zz summary"), $ListBuild("an unknown Decision row", "ZzNoSuchDecision", 0, "zz summary"), $ListBuild("no DecisionRef", "", 0, "zz summary"))
	Set errors = errors_$ListBuild($ListBuild("an empty reason", noReason, 0, "zz summary"), $ListBuild("an empty first reason line", blankFirst, 0, "zz summary"), $ListBuild("an empty summary (a decision)", mine, 0, ""), $ListBuild("an empty summary (a fallback)", "", 1, ""))
	Set position = 0
	While $ListNext(errors, position, case) {
		Set decision = ..Decision(session, "tellnow")
		Set decision.DecisionRef = $List(case, 2)
		Set decision.Fallback = $List(case, 3)
		Set decision.FallbackReason = $Select($List(case, 3): "refusal", 1: "")
		Set decision.Summary = $List(case, 4)
		Kill target
		Set sc = ##class(OcuTalon.Core.Rule.Notice).Transform(decision, .target)
		Do $$$AssertStatusNotOK(sc, $List(case, 1)_" is an error")
		Do $$$AssertEquals($IsObject($Get(target)), 0, $List(case, 1)_": with no Notification")
	}
}

/// Writes the digest.channels row with the value (exists = 1; the updatedAt of a restore is kept), or deletes it (exists = 0), and drops this
/// process's cache entry, so that the next read sees it.
ClassMethod PutChannels(value As %String, exists As %Boolean = 1, updatedAt As %String = "")
{
	Set key = ..#CHANNELSKEY
	Kill ^||OcuTalon.Setting(key)
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If 'exists {
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Quit
	}
	Do ##class(OcuTalon.Data.Setting).Set(key, value)
	If updatedAt '= "" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Set row.UpdatedAt = updatedAt
		Do row.%Save()
	}
	Kill ^||OcuTalon.Setting(key)
}

/// Notify's rule for every kind of Notification, with demo mode on and off, with and without a pairing, and with Telegram
/// included or not; a reply that came from the web and one from Telegram; a pairing notice with and without a ChatRef.
///   - kind pairing: TelegramOut alone when ChatRef is set and Telegram is included, otherwise none;
///   - kind allowance: WebChatOut, and TelegramOut when Telegram is included and the session is paired;
///   - any other kind: WebChatOut, SimPhoneOut when demo mode is on, TelegramOut when Telegram is included and the session is paired;
///   - page with no Data.Page row (DecisionRef empty): nothing, whatever the session says (TestNotifyPageTargets has the rows);
///   - digest: the same three, each only when digest.channels names it (no row: web, phone and telegram), and nothing when none holds;
///   - a reply: WebChatOut, and TelegramOut when it came from Telegram, Telegram is included and the session is paired.
Method TestNotifyTargets()
{
	Set unpaired = ..Session("notify")
	Set paired = ..Session("notifypaired")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(paired)
	Set kinds = $ListFromString("tellnow,incident,approval,answered,result,reminder,fallback,allowance,pairing,status,handled,page")
	For demo = 0, 1 {
		Do ##class(OcuTalon.Test.Demo.Step).Put(demo, "2026-01-02T03:04:05Z")
		For included = 0, 1 {
			Set ^OcuTalonTest("TelegramIncluded") = included
			For isPaired = 0, 1 {
				Set session = $Select(isPaired: paired, 1: unpaired)
				Set position = 0
				While $ListNext(kinds, position, kind) {
					For chat = 0, 1 {
						If (kind '= "pairing") && chat Continue
						Set notification = ##class(OcuTalon.Msg.Notification).%New()
						Set notification.SessionRef = session
						Set notification.Kind = kind
						If chat Set notification.ChatRef = ##class(OcuTalon.Bridge.Ids).NewRef()
						Set label = kind_$Select(chat: " with a ChatRef", 1: "")_", demo "_$Select(demo: "on", 1: "off")_", Telegram "_$Select(included: "included", 1: "not included")_", "_$Select(isPaired: "paired", 1: "not paired")
						If kind = "pairing" {
							Set expected = $Select(chat && included: "send:TelegramOut:", 1: "")
						} ElseIf kind = "allowance" {
							Set expected = "send:WebChatOut"_$Select(included && isPaired: ",TelegramOut", 1: "")_":"
						} ElseIf kind = "page" {
							Set expected = ""
						} Else {
							Set expected = "send:WebChatOut"_$Select(demo: ",SimPhoneOut", 1: "")_$Select(included && isPaired: ",TelegramOut", 1: "")_":"
						}
						Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), expected, label_": ["_expected_"]")
					}
				}
				For origin = "web", "telegram", "phone" {
					Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
					Set outbound.SessionRef = session
					Set outbound.OriginChannel = origin
					Set expected = "send:WebChatOut"_$Select((origin = "telegram") && included && isPaired: ",TelegramOut", 1: "")_":"
					Do $$$AssertEquals(..Route(..#NOTIFYRULE, outbound), expected, "a reply from "_origin_", demo "_$Select(demo: "on", 1: "off")_", Telegram "_$Select(included: "included", 1: "not included")_", "_$Select(isPaired: "paired", 1: "not paired")_": ["_expected_"]")
				}
			}
		}
	}
	Do ..PutChannels("", 0)
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, "2026-01-02T03:04:05Z")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.Kind = "tellnow"
	Set notification.SessionRef = "eval"
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), "send:WebChatOut,SimPhoneOut:", "a Notification for any owner goes to the channels, whatever its owner (WebChatOut refuses an owner that is not a session)")
	Set outbound = ##class(OcuTalon.Msg.Item).%New()
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, outbound), "", "a message of another class routes nowhere")
}

/// The kind digest goes to the session's own channels that digest.channels also names: web always, phone while demo mode is on, Telegram
/// while it is included and the session is paired. The expected targets are written out per setting value: web, phone, telegram (1 when named).
/// No row names all three. A name that is not one of the three, an empty name, and a value of only such names add no target, and a digest
/// with no target goes nowhere: it never takes the generic route.
Method TestNotifyDigestTargets()
{
	Set unpaired = ..Session("digestunpaired")
	Set paired = ..Session("digestpaired")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(paired)
	Set settings = $ListBuild($ListBuild("no row", "", 1, 1, 1), $ListBuild("web", "web", 1, 0, 0), $ListBuild("phone", "phone", 0, 1, 0), $ListBuild("telegram", "telegram", 0, 0, 1))
	Set settings = settings_$ListBuild($ListBuild("web,phone", "web,phone", 1, 1, 0), $ListBuild("web,phone,telegram", "web,phone,telegram", 1, 1, 1), $ListBuild("phone,telegram", "phone,telegram", 0, 1, 1), $ListBuild("web,telegram", "web,telegram", 1, 0, 1))
	Set settings = settings_$ListBuild($ListBuild("spaces and case", " Telegram , WEB ", 1, 0, 1), $ListBuild("only unknown names", "fax,sms", 0, 0, 0), $ListBuild("an unknown name beside web", "fax,web", 1, 0, 0), $ListBuild("empty names", ",,web,", 1, 0, 0))
	For demo = 0, 1 {
		Do ##class(OcuTalon.Test.Demo.Step).Put(demo, "2026-01-02T03:04:05Z")
		For included = 0, 1 {
			Set ^OcuTalonTest("TelegramIncluded") = included
			For isPaired = 0, 1 {
				Set session = $Select(isPaired: paired, 1: unpaired)
				Set position = 0
				While $ListNext(settings, position, setting) {
					Do ..PutChannels($List(setting, 2), $List(setting, 2) '= "")
					Set notification = ##class(OcuTalon.Msg.Notification).%New()
					Set notification.SessionRef = session
					Set notification.Kind = "digest"
					Set targets = ""
					If $List(setting, 3) Set targets = targets_",WebChatOut"
					If $List(setting, 4) && demo Set targets = targets_",SimPhoneOut"
					If $List(setting, 5) && included && isPaired Set targets = targets_",TelegramOut"
					Set expected = $Select(targets = "": "", 1: "send:"_$Extract(targets, 2, *)_":")
					Set label = "a digest, digest.channels "_$List(setting, 1)_", demo "_$Select(demo: "on", 1: "off")_", Telegram "_$Select(included: "included", 1: "not included")_", "_$Select(isPaired: "paired", 1: "not paired")
					Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), expected, label_": ["_expected_"]")
				}
			}
		}
	}
	Do ..PutChannels("", 0)
}

/// A fixture Data.Page row of the run (an incident of its own, so that the unique (IncidentRef, Role) never meets another row): its Ref. role is oncall or backup.
Method PageRow(role As %String, person As %String, channels As %String) As %String [ Private ]
{
	Set page = ##class(OcuTalon.Data.Page).%New()
	Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..PageRows = ..PageRows + 1
	Set page.IncidentRef = "zzroute"_..Number_"p"_..PageRows
	Set page.Role = role
	Set page.Person = person
	Set page.Channels = channels
	Set page.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(page.%Save(), "a page row for "_role_" with channels '"_channels_"' is made")
	Quit page.Ref
}

/// Story 24.3a, P1 Option A: Notify routes kind page by the Data.Page row that DecisionRef names (the expected targets are written out here). A session gets its web card whatever
/// the channels say, and TelegramOut when Telegram is included and the row's Channels names telegram, paired or not (an unpaired chat is TelegramOut's own report, so the route
/// never reads the pairing), never SimPhoneOut. No row, a Ref that names no row, an address-only person (SessionRef instance) and the online demo route nowhere. A handled
/// Notification for a page takes the generic route and never reaches EmailOut. The rule PageEmail adds EmailOut (a second send, after a ";") for a row that names email exactly
/// when EmailOut has an alive job and the online demo is off, so the expected targets follow the stack's state, whichever it is.
Method TestNotifyPageTargets()
{
	Set unpaired = ..Session("pageunpaired")
	Set paired = ..Session("pagepaired")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(paired)
	Set emailRuns = ##class(OcuTalon.Core.CommandsIn).ItemRunning("EmailOut")
	Set channelsList = $ListBuild("telegram", "email", "telegram,email", " Email , TELEGRAM ", "")
	For online = 0, 1 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", online)
		For demo = 0, 1 {
			Do ##class(OcuTalon.Test.Demo.Step).Put(demo, "2026-01-02T03:04:05Z")
			For included = 0, 1 {
				Set ^OcuTalonTest("TelegramIncluded") = included
				For isPaired = 0, 1 {
					Set session = $Select(isPaired: paired, 1: unpaired)
					Set position = 0
					While $ListNext(channelsList, position, channels) {
						Set page = ..PageRow("oncall", "zzpageperson", channels)
						Set notification = ##class(OcuTalon.Msg.Notification).%New()
						Set notification.SessionRef = session
						Set notification.Kind = "page"
						Set notification.DecisionRef = page
						Set telegram = ($ZConvert($ZStrip(channels, "*W"), "L") [ "telegram")
						Set expected = $Select(online: "", 1: "send:WebChatOut"_$Select(included && telegram: ",TelegramOut", 1: "")_":")
						Set mail = $Select(emailRuns && 'online && ($ZConvert($ZStrip(channels, "*W"), "L") [ "email"): "send:EmailOut:", 1: "")
						Set expected = expected_$Select((expected '= "") && (mail '= ""): ";", 1: "")_mail
						Set label = "a page with channels '"_channels_"', online demo "_$Select(online: "on", 1: "off")_", demo mode "_$Select(demo: "on", 1: "off")_", Telegram "_$Select(included: "included", 1: "not included")_", "_$Select(isPaired: "paired", 1: "not paired")
						Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), expected, label_": ["_expected_"]")
						Set handled = ##class(OcuTalon.Msg.Notification).%New()
						Set handled.SessionRef = session
						Set handled.Kind = "handled"
						Set handled.DecisionRef = page
						Set route = ..Route(..#NOTIFYRULE, handled)
						Do $$$AssertTrue(route '[ "EmailOut", label_": a handled Notification for it never reaches EmailOut ("_route_")")
						Set expected = "send:WebChatOut"_$Select(demo: ",SimPhoneOut", 1: "")_$Select(included && isPaired: ",TelegramOut", 1: "")_":"
						Do $$$AssertEquals(route, expected, label_": a handled Notification for it takes the generic route")
					}
				}
			}
		}
	}
	// no row, an unknown Ref, an address-only person and a Ref that is not the row's exactly
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, "2026-01-02T03:04:05Z")
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Set page = ..PageRow("backup", "zzpageperson@example.test", "email")
	Set cases = $ListBuild($ListBuild("no DecisionRef", paired, "", 0), $ListBuild("a Ref that names no row", paired, ##class(OcuTalon.Bridge.Ids).NewRef(), 0), $ListBuild("an address-only person", "instance", page, 1), $ListBuild("an empty session", "", page, 1), $ListBuild("an unknown session", "zznosession", page, 1), $ListBuild("a Ref that differs in case", paired, $ZConvert(page, "L"), 0))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set notification = ##class(OcuTalon.Msg.Notification).%New()
		Set notification.SessionRef = $List(case, 2)
		Set notification.Kind = "page"
		Set notification.DecisionRef = $List(case, 3)
		Set mail = $Select(emailRuns && $List(case, 4): "send:EmailOut:", 1: "")
		Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), mail, $List(case, 1)_": a page routes nowhere but to EmailOut, when it has a job and the row names email ["_mail_"]")
	}
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = paired
	Set notification.Kind = "page"
	Set notification.DecisionRef = page
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), "send:WebChatOut:"_$Select(emailRuns: ";send:EmailOut:", 1: ""), "control: the same page of a user, whose row names only email, gets the web card, and EmailOut when it has a job")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Core.Rule.Functions", "PageEmail", page), +emailRuns, "PageEmail is 1 for a row that names email exactly when EmailOut has a job ("_+emailRuns_")")
	Set ^OcuTalonTest("TelegramIncluded") = 0
}

/// Story 21.7: the rule DigestEmail adds a target only while EmailOut has an alive job. Here the production does not run EmailOut (the item is disabled until an
/// outgoing server is saved), so a digest of the mailbox owner that names email, with an address saved and demo mode off or on, goes to the same targets as
/// without email, and DigestEmail is 0; the cases with a job are those of OcuTalon.Test.Channel.EmailLive.
Method TestNotifyDigestEmail()
{
	If ##class(OcuTalon.Core.CommandsIn).ItemRunning("EmailOut") {
		Do $$$LogMessage("EmailOut runs on this stack, so the cases with a job are the live test's")
		Quit
	}
	Set owner = ..Session("emailowner")
	Set found = ""
	For key = "email.owner", "email.address" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Set found = found_$ListBuild($ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: "")))
	}
	Try {
		Do ##class(OcuTalon.Data.Setting).Set("email.owner", owner)
		Do ##class(OcuTalon.Data.Setting).Set("email.address", "zzrouting@example.com")
		Do ..PutChannels("web,email")
		For demo = 0, 1 {
			Do ##class(OcuTalon.Test.Demo.Step).Put(demo, "2026-01-02T03:04:05Z")
			Set notification = ##class(OcuTalon.Msg.Notification).%New()
			Set notification.SessionRef = owner
			Set notification.Kind = "digest"
			Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), "send:WebChatOut:", "demo "_demo_": a digest naming web and email goes to the web chat alone while EmailOut has no job")
			Do $$$AssertEquals($ClassMethod("OcuTalon.Core.Rule.Functions", "DigestEmail", owner), 0, "demo "_demo_": DigestEmail is 0 for the owner with a saved address")
		}
		Do ..PutChannels("email")
		Set notification = ##class(OcuTalon.Msg.Notification).%New()
		Set notification.SessionRef = owner
		Set notification.Kind = "digest"
		Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), "", "a digest naming email alone goes nowhere while EmailOut has no job")
	} Catch exception {
		Do $$$AssertTrue(0, "the email routing test failed: "_exception.DisplayString())
	}
	Set position = 0
	Set n = 0
	For key = "email.owner", "email.address" {
		Set n = n + 1
		Set was = $List(found, n)
		If $List(was, 1) {
			Do ##class(OcuTalon.Data.Setting).Set(key, $List(was, 2))
		} Else {
			Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
		}
		Kill ^||OcuTalon.Setting(key)
	}
	Do ..PutChannels("", 0)
}

/// The five functions: IsSession is 1 only for the Ref of a session with a Session row; DemoOn follows the demo.mode setting
/// ("1" is on, anything else and an absent row are off); TelegramOn follows Telegram.In.Included; TelegramPaired needs Telegram
/// included and a Pairing row of the session; DigestNamed is 1 for a channel that digest.channels names, compared trimmed and
/// lowercased, with all three channels named when the setting has no row, and 0 for any other name. The rules find each function in OcuTalon.Core.Rule.Functions, and in no other
/// function set.
Method TestFunctions()
{
	Set functions = "OcuTalon.Core.Rule.Functions"
	Set session = ..Session("functions")
	Set paired = ..Session("functionspaired")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(paired)
	Do $$$AssertEquals($ClassMethod(functions, "IsSession", session), 1, "IsSession: the Ref of a session")
	For ref = "", "instance", "eval", "Instance", "ZzNoSuchSession", ##class(OcuTalon.Bridge.Ids).NewRef() {
		Do $$$AssertEquals($ClassMethod(functions, "IsSession", ref), 0, "IsSession: '"_ref_"' is not a session")
	}
	For value = "0", "1", "2", "yes", "" {
		Do ##class(OcuTalon.Test.Demo.Step).Put(value, "2026-01-02T03:04:05Z")
		Do $$$AssertEquals($ClassMethod(functions, "DemoOn"), (value = "1"), "DemoOn: the setting '"_value_"' is "_$Select(value = "1": "on", 1: "off"))
	}
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Do $$$AssertEquals($ClassMethod(functions, "DemoOn"), 0, "DemoOn: no row is off")
	For included = 0, 1 {
		Set ^OcuTalonTest("TelegramIncluded") = included
		Do $$$AssertEquals($ClassMethod(functions, "TelegramOn"), included, "TelegramOn: "_$Select(included: "included", 1: "not included"))
		Do $$$AssertEquals($ClassMethod(functions, "TelegramPaired", paired), included, "TelegramPaired: a paired session with Telegram "_$Select(included: "included", 1: "not included"))
		Do $$$AssertEquals($ClassMethod(functions, "TelegramPaired", session), 0, "TelegramPaired: a session with no pairing, Telegram "_$Select(included: "included", 1: "not included"))
		Do $$$AssertEquals($ClassMethod(functions, "TelegramPaired", ""), 0, "TelegramPaired: an empty Ref")
		Do $$$AssertEquals($ClassMethod(functions, "TelegramPaired", "instance"), 0, "TelegramPaired: the owner instance")
	}
	Do ..AssertSlackLinked(functions, session)
	Do ..PutChannels("", 0)
	For channel = "web", "phone", "telegram" {
		Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", channel), 1, "DigestNamed: "_channel_" is named when the setting has no row")
	}
	Do ..PutChannels("web, Phone")
	Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", "web")_$ClassMethod(functions, "DigestNamed", "phone")_$ClassMethod(functions, "DigestNamed", "telegram"), "110", "DigestNamed: 'web, Phone' names web and phone, not telegram")
	Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", " PHONE ")_$ClassMethod(functions, "DigestNamed", "Web"), "11", "DigestNamed: the argument is trimmed and lowercased too")
	For channel = "", "fax", "web,phone", "all" {
		Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", channel), 0, "DigestNamed: '"_channel_"' is never a channel")
	}
	Do ..PutChannels("web,phone,telegram")
	Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", "fax"), 0, "DigestNamed: a name that the setting lists but that is not a channel is 0")
	Do ..PutChannels("", 0)
	Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", "email"), 0, "DigestNamed: email is not named when the setting has no row (email is opt-in)")
	Do ..PutChannels("Web, EMAIL")
	Do $$$AssertEquals($ClassMethod(functions, "DigestNamed", "email")_$ClassMethod(functions, "DigestNamed", " Email ")_$ClassMethod(functions, "DigestNamed", "phone"), "110", "DigestNamed: 'Web, EMAIL' names email, trimmed and lowercased, and not phone")
	Do ..PutChannels("", 0)
	Do $$$AssertEquals($ClassMethod(functions, "DigestEmail", "")_$ClassMethod(functions, "DigestEmail", session)_$ClassMethod(functions, "DigestEmail", "instance"), "000", "DigestEmail: an empty Ref, a session that does not own the mailbox and the owner instance are 0 (EmailOut has no job on this stack either; the half with a job is Test.Channel.EmailLive's)")
	Do $$$AssertEquals($ListToString($ClassMethod(functions, "DigestChannels", session)), "web", "DigestChannels: web alone for a session with demo mode off and no pairing, with no value saved")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set both = ..PageRow("oncall", "zzfunctionperson", "telegram,email")
	Set telegramOnly = ..PageRow("backup", "zzfunctionperson", "Telegram")
	Do $$$AssertEquals($ClassMethod(functions, "PageWeb", both, session)_$ClassMethod(functions, "PageWeb", both, "instance")_$ClassMethod(functions, "PageWeb", both, "")_$ClassMethod(functions, "PageWeb", both, "eval")_$ClassMethod(functions, "PageWeb", "", session)_$ClassMethod(functions, "PageWeb", $ZConvert(both, "L"), session)_$ClassMethod(functions, "PageWeb", ##class(OcuTalon.Bridge.Ids).NewRef(), session), "1000000", "PageWeb: the row exists and the session is a session; not an address-only person, an empty or eval owner, an empty, case-changed or unknown Ref")
	Do $$$AssertEquals($ClassMethod(functions, "PageChannel", both, "telegram")_$ClassMethod(functions, "PageChannel", both, "email")_$ClassMethod(functions, "PageChannel", both, " EMAIL ")_$ClassMethod(functions, "PageChannel", both, "web")_$ClassMethod(functions, "PageChannel", both, "")_$ClassMethod(functions, "PageChannel", "", "email"), "111000", "PageChannel: the channels of the row, trimmed and lowercased; not web, an empty channel or Ref")
	Do $$$AssertEquals($ClassMethod(functions, "PageChannel", telegramOnly, "telegram")_$ClassMethod(functions, "PageChannel", telegramOnly, "email")_$ClassMethod(functions, "PageChannel", $ZConvert(telegramOnly, "U"), "telegram"), "100", "PageChannel: a row that names telegram alone does not name email; a Ref that differs in case is no row")
	Set emailRuns = +##class(OcuTalon.Core.CommandsIn).ItemRunning("EmailOut")
	Do $$$AssertEquals($ClassMethod(functions, "PageEmail", both)_$ClassMethod(functions, "PageEmail", ""), emailRuns_"0", "PageEmail: 1 for a row that names email exactly when EmailOut has a job ("_emailRuns_"), 0 for an empty Ref")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals($ClassMethod(functions, "PageWeb", both, session)_$ClassMethod(functions, "PageChannel", both, "telegram")_$ClassMethod(functions, "PageChannel", both, "email")_$ClassMethod(functions, "PageEmail", both), "0000", "PageWeb, PageChannel and PageEmail are 0 on the online demo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	For name = "IsSession", "DemoOn", "TelegramOn", "TelegramPaired", "SlackLinked", "DigestNamed", "DigestEmail", "DigestChannels", "PageWeb", "PageChannel", "PageEmail" {
		Kill class
		Set sc = ##class(Ens.Rule.Utilities).ResolveFunction(name, .class, .method)
		Do $$$AssertStatusOK(sc, name_" resolves as a rule function")
		Do $$$AssertEquals($Get(class)_"|"_$Get(method), functions_"|"_name, name_" is the function of "_functions)
		Set count = 0
		Set subclasses = ##class(%ResultSet).%New("%Dictionary.ClassDefinition:SubclassOf")
		Do $$$AssertStatusOK(subclasses.Execute("Ens.Rule.FunctionSet"), "the function sets are listed")
		While subclasses.Next() {
			If ##class(%Dictionary.CompiledMethod).%ExistsId(subclasses.Data("Name")_"||"_name) Set count = count + 1
		}
		Do $$$AssertEquals(count, 1, "exactly one function set declares "_name)
	}
}

/// Story 27.2: a reply of a Slack turn goes to SlackOut as well as WebChatOut exactly when Slack is on and the session has a link; nothing else ever goes to SlackOut.
Method TestNotifySlackTargets()
{
	Set linked = ..Session("slacklinked")
	Set unlinked = ..Session("slackunlinked")
	Do ##class(OcuTalon.Data.SlackLink).Link(..#SLACKTEAM, "U0ROUTING"_..Number, linked, .sc)
	Do $$$AssertStatusOK(sc, "a member is linked to the first session")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Set kinds = $ListFromString("tellnow,incident,approval,answered,result,reminder,fallback,allowance,pairing,status,handled,page,digest,summary")
	Set saved = ..SaveSlackEnvironment()
	Try {
		For on = 0, 1 {
			For demo = 0, 1 {
				Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", demo)
				Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "zz-routing-secret")
				Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", $Select(on: "zz-routing-token", 1: ""))
				For isLinked = 0, 1 {
					Set session = $Select(isLinked: linked, 1: unlinked)
					Set where = "Slack "_$Select(on: "on", 1: "off")_", online demo "_$Select(demo: "on", 1: "off")_", "_$Select(isLinked: "linked", 1: "not linked")
					For origin = "slack", "web", "telegram", "phone", "email" {
						Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
						Set outbound.SessionRef = session
						Set outbound.OriginChannel = origin
						Set expected = "send:WebChatOut"_$Select((origin = "slack") && on && 'demo && isLinked: ",SlackOut", 1: "")_":"
						Do $$$AssertEquals(..Route(..#NOTIFYRULE, outbound), expected, "a reply from "_origin_", "_where_": ["_expected_"]")
					}
					Set position = 0
					Set routedKinds = 0
					While $ListNext(kinds, position, kind) {
						Set notification = ##class(OcuTalon.Msg.Notification).%New()
						Set notification.SessionRef = session
						Set notification.Kind = kind
						Set routed = ..Route(..#NOTIFYRULE, notification)
						Do $$$AssertTrue(routed '[ "SlackOut", "a Notification of kind "_kind_" never goes to SlackOut, "_where_": ["_routed_"]")
						If routed [ "WebChatOut" Set routedKinds = routedKinds + 1
					}
					Do $$$AssertTrue(routedKinds > 0, "and the Notifications are routed at all (some kind goes to WebChatOut), "_where)
				}
			}
		}
	} Catch exception {
		Do $$$AssertTrue(0, "the Slack routing test failed: "_exception.DisplayString())
	}
	Do ..RestoreSlackEnvironment(saved)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId = ?", ..#SLACKTEAM)
	Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
	Set outbound.SessionRef = linked
	Set outbound.OriginChannel = "slack"
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, outbound), "send:WebChatOut:", "control: with the link removed (and Slack as the environment has it) the reply goes to WebChatOut alone")
}

/// The wiring of the two rules to the production (AD-30): the router items OutcomeRouter and Notify use the rule classes under
/// test, and every target and transform that a rule's send action names exists: each target is an item of OcuTalon.Production and
/// each transform is a compiled data transform. A target that is not an item would fail the send of a notification that demo mode
/// or a pairing sends past the web chat. The targets are scanned from the rules' XML; they are written out here, never read from
/// the rules.
Method TestRuleTargetsAreProductionItems()
{
	Set production = ##class(Ens.Config.Production).%OpenId("OcuTalon.Production")
	Do $$$AssertTrue($IsObject(production), "the compiled production exists")
	If '$IsObject(production) Quit
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		Set items(item.Name) = item
	}
	For router = "OutcomeRouter", "Notify" {
		Set rule = $Select(router = "OutcomeRouter": ..#OUTCOMERULE, 1: ..#NOTIFYRULE)
		Set found = ""
		If $Data(items(router)) {
			For j = 1:1:items(router).Settings.Count() {
				If items(router).Settings.GetAt(j).Name = "BusinessRuleName" Set found = items(router).Settings.GetAt(j).Value
			}
		}
		Do $$$AssertEquals(found, rule, router_" is routed by "_rule)
	}
	Set expected("OcuTalon.Core.Rule.Outcome") = "DigestStore,Notify"
	Set expected("OcuTalon.Core.Rule.Notify") = "EmailOut,SimPhoneOut,SlackOut,TelegramOut,WebChatOut"
	Set rule = ""
	For {
		Set rule = $Order(expected(rule))
		Quit:rule=""
		Set data = ##class(%Dictionary.XDataDefinition).%OpenId(rule_"||RuleDefinition")
		Do $$$AssertTrue($IsObject(data), rule_" holds its rule definition")
		If '$IsObject(data) Continue
		Set xml = ""
		Do data.Data.Rewind()
		While 'data.Data.AtEnd {
			Set xml = xml_data.Data.Read(30000)
		}
		Kill targets, transforms
		Do ..Attribute(xml, "target", .targets)
		Do ..Attribute(xml, "transform", .transforms)
		Set names = "", name = ""
		For {
			Set name = $Order(targets(name))
			Quit:name=""
			Set names = names_$Select(names = "": "", 1: ",")_name
			Do $$$AssertTrue($Data(items(name)), rule_": the target "_name_" is an item of the production")
		}
		Do $$$AssertEquals(names, expected(rule), rule_" sends to exactly these items")
		Set name = ""
		For {
			Set name = $Order(transforms(name))
			Quit:name=""
			Do $$$AssertTrue($ClassMethod(name, "%Extends", "Ens.DataTransform"), rule_": the transform "_name_" is a data transform")
		}
	}
}

/// --- helpers ---
/// SlackLinked, in TestFunctions: 1 only with both variables set, the online demo off and a link row; 0 for an empty Ref, an unlinked session and a link that was removed.
Method AssertSlackLinked(functions As %String, session As %String) [ Private ]
{
	Set linked = ..Session("functionsslack")
	Do ##class(OcuTalon.Data.SlackLink).Link(..#SLACKTEAM, "U0FUNCTION"_..Number, linked, .sc)
	Do $$$AssertStatusOK(sc, "SlackLinked: a member is linked to a session")
	Set saved = ..SaveSlackEnvironment()
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "zz-routing-secret")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-routing-token")
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", linked), 1, "SlackLinked: a linked session with Slack on")
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", session), 0, "SlackLinked: a session with no link")
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", "")_$ClassMethod(functions, "SlackLinked", "instance")_$ClassMethod(functions, "SlackLinked", "ZzNoSuchSession"), "000", "SlackLinked: an empty Ref, the owner instance and an unknown Ref")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "")
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", linked), 0, "SlackLinked: 0 with no token")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-routing-token")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "")
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", linked), 0, "SlackLinked: 0 with no signing secret")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "zz-routing-secret")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", linked), 0, "SlackLinked: 0 on the online demo")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do ##class(OcuTalon.Data.SlackLink).Unlink(linked)
		Do $$$AssertEquals($ClassMethod(functions, "SlackLinked", linked), 0, "SlackLinked: 0 once the link is removed")
	} Catch exception {
		Do $$$AssertTrue(0, "the SlackLinked test failed: "_exception.DisplayString())
	}
	Do ..RestoreSlackEnvironment(saved)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
}

/// The three Slack variables of the process as $ListBuild(name, was set, value) for each.
Method SaveSlackEnvironment() As %List [ Private ]
{
	Set saved = ""
	For name = "SLACK_SIGNING_SECRET", "SLACK_BOT_TOKEN" {
		Set saved = saved_$ListBuild($ListBuild(name, ##class(OcuTalon.Test.Agent.KeyScan).HasEnv(name), $SYSTEM.Util.GetEnviron(name)))
	}
	Quit saved
}

/// Puts the variables back as SaveSlackEnvironment found them.
Method RestoreSlackEnvironment(saved As %List) [ Private ]
{
	Set position = 0
	While $ListNext(saved, position, one) {
		If $List(one, 2) {
			Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv($List(one, 1), $List(one, 3))
		} Else {
			Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv($List(one, 1))
		}
	}
}

/// The values of the attribute in the XML text, comma-separated values split, as the subscripts of values.
ClassMethod Attribute(xml As %String, attribute As %String, Output values) [ Private ]
{
	Kill values
	Set position = 1
	For {
		Set from = $Find(xml, attribute_"=""", position)
		If from = 0 Quit
		Set to = $Find(xml, """", from)
		If to = 0 Quit
		Set list = $ListFromString($Extract(xml, from, to - 2))
		Set at = 0
		While $ListNext(list, at, one) {
			If one '= "" Set values(one) = ""
		}
		Set position = to
	}
}

/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzroute"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// An ItemDecision of the owner with the outcome, a summary and no CatalogKey.
Method Decision(owner As %String, outcome As %String) As OcuTalon.Msg.ItemDecision [ Private ]
{
	Set decision = ##class(OcuTalon.Msg.ItemDecision).%New()
	Set decision.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set decision.OwnerRef = owner
	Set decision.Channel = "mailbox"
	Set decision.Summary = "zz summary"
	Set decision.Outcome = outcome
	Quit decision
}

/// The transform's Notification for the ItemDecision, or "" with the error in sc.
Method Transform(decision As OcuTalon.Msg.ItemDecision, Output sc As %Status) As OcuTalon.Msg.Notification [ Private ]
{
	Kill target
	Set sc = ##class(OcuTalon.Core.Rule.Notice).Transform(decision, .target)
	Quit $Get(target)
}

/// The action list that the rule returns for the message, evaluated on a shadow instance of the routing engine as the router
/// does; an error is returned as "ERROR <text>".
Method Route(rule As %String, document As %RegisteredObject) As %String [ Private ]
{
	Set engine = ##class(Ens.Host).GetShadowInstance("class||EnsLib.MsgRouter.RoutingEngine", .sc)
	If '$IsObject(engine) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Set engine.Document = document
	Set engine.MsgClass = $ClassName(document)
	Set engine.Source = "zzsource"
	Set sc = ##class(Ens.Rule.RuleDefinition).EvaluateRulesEx(rule, 0, engine, "", .return, .reason, 1, "e")
	If $SYSTEM.Status.IsError(sc) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Quit $Get(return)
}

}
