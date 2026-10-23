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
///   - TestFunctions: the four functions of the rules, and that the rules resolve them from OcuTalon.Core.Rule.Functions alone.
/// The fixture sessions come from Test.Data.Fixture. The test restores the demo.mode setting (as Test.Demo.Step saves and puts it
/// back) and the test-only switch ^OcuTalonTest("TelegramIncluded") as it found them. The run's number is n from
/// ^OcuTalonTest("Routing","n") (never reset).
Class OcuTalon.Test.Core.Routing Extends %UnitTest.TestCase
{

/// The rule of the OutcomeRouter item.
Parameter OUTCOMERULE = "OcuTalon.Core.Rule.Outcome";

/// The rule of the Notify item.
Parameter NOTIFYRULE = "OcuTalon.Core.Rule.Notify";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// 1 when the demo.mode row existed before the run, with its value and UpdatedAt.
Property SavedFound As %Boolean;

Property SavedValue As %String;

Property SavedUpdatedAt As %String;

/// The value of ^OcuTalonTest("TelegramIncluded") before the run, "" when it was absent.
Property SavedIncluded As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("Routing", "n"))
	Set ..Refs = ""
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedFound = found, ..SavedValue = value, ..SavedUpdatedAt = updatedAt
	Set ..SavedIncluded = $Get(^OcuTalonTest("TelegramIncluded"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedFound, ..SavedValue, ..SavedUpdatedAt)
	If ..SavedIncluded = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedIncluded
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
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
/// notice.tellNowFallback with the summary and the fallback reason (unusable when it is empty or unknown). Otherwise it is
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
	Do $$$AssertStatusOK(sc, "a fallback needs no Decision row, it has none")
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

/// Notify's rule for every kind of Notification, with demo mode on and off, with and without a pairing, and with Telegram
/// included or not; a reply that came from the web and one from Telegram; a pairing notice with and without a ChatRef.
///   - kind pairing: TelegramOut alone when ChatRef is set and Telegram is included, otherwise none;
///   - kind allowance: WebChatOut, and TelegramOut when Telegram is included and the session is paired;
///   - any other kind: WebChatOut, SimPhoneOut when demo mode is on, TelegramOut when Telegram is included and the session is paired;
///   - a reply: WebChatOut, and TelegramOut when it came from Telegram, Telegram is included and the session is paired.
Method TestNotifyTargets()
{
	Set unpaired = ..Session("notify")
	Set paired = ..Session("notifypaired")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(paired)
	Set kinds = $ListFromString("tellnow,incident,approval,answered,result,reminder,fallback,allowance,pairing,status,digest")
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
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, "2026-01-02T03:04:05Z")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.Kind = "tellnow"
	Set notification.SessionRef = "eval"
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notification), "send:WebChatOut,SimPhoneOut:", "a Notification for any owner goes to the channels, whatever its owner (WebChatOut refuses an owner that is not a session)")
	Set outbound = ##class(OcuTalon.Msg.Item).%New()
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, outbound), "", "a message of another class routes nowhere")
}

/// The four functions: IsSession is 1 only for the Ref of a session with a Session row; DemoOn follows the demo.mode setting
/// ("1" is on, anything else and an absent row are off); TelegramOn follows Telegram.In.Included; TelegramPaired needs Telegram
/// included and a Pairing row of the session. The rules find each function in OcuTalon.Core.Rule.Functions, and in no other
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
	For name = "IsSession", "DemoOn", "TelegramOn", "TelegramPaired" {
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

/// --- helpers ---
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
