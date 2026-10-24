/// Tests of the bridge example's routing and its refusals (Story 13.1, QA; AD-30, FR-5). Nothing is started, sent or written: the
/// tests evaluate the rule on Decided messages built in memory, read the registered production, and call the service, the process and
/// the operation on paths that refuse before they send or log. The same routes are proved through a running production by
/// release/standalone-bridge.sh, which takes minutes; these pin them in the shard.
///   - TestRuleRoutes: a fallback goes to ExampleFallbackOut whatever its outcome; tellnow and act go to ExampleNotifyOut; digest goes to
///     ExampleDigestOut; ignore, an outcome that is none of the four and a message of another class go nowhere;
///   - TestRuleReadsTwoProperties: the route changes with Fallback and Outcome only, not with the item, the summary, the decision
///     reference or the fallback reason;
///   - TestWiring: each of the six example items has its class, the router names the rule, every target of the rule and every default
///     target of the service and the process is an item of the production;
///   - TestRefusals: the service takes only an Item that Check accepts, the operation answers "not implemented" to any message but a
///     Decided, and the process refuses an answer that is not a DecisionResponse.
Class OcuTalon.Test.Bridge.ExampleRouting Extends %UnitTest.TestCase
{

Parameter PRODUCTION = "OcuTalon.BridgeExample.Production";

Parameter RULE = "OcuTalon.BridgeExample.Rule";

Parameter DECIDED = "OcuTalon.BridgeExample.Msg.Decided";

/// The rows of the matrix: Fallback and Outcome in, the routed items out.
Method TestRuleRoutes()
{
	Do $$$AssertEquals(..Route(0, "tellnow"), "ExampleNotifyOut", "tellnow goes to ExampleNotifyOut only")
	Do $$$AssertEquals(..Route(0, "act"), "ExampleNotifyOut", "act goes to ExampleNotifyOut only")
	Do $$$AssertEquals(..Route(0, "digest"), "ExampleDigestOut", "digest goes to ExampleDigestOut only")
	Do $$$AssertEquals(..Route(0, "ignore"), "", "ignore goes nowhere, and the rule evaluates without an error")
	Do $$$AssertEquals(..Route(0, ""), "", "an empty outcome goes nowhere")
	Do $$$AssertEquals(..Route(0, "shout"), "", "an outcome that is none of the four goes nowhere")
	For outcome = "tellnow", "act", "digest", "ignore", "" {
		Do $$$AssertEquals(..Route(1, outcome), "ExampleFallbackOut", "a fallback with outcome '"_outcome_"' goes to ExampleFallbackOut only")
	}
	Set msg = ##class(Ens.StringRequest).%New()
	Set msg.StringValue = "tellnow"
	Do $$$AssertEquals(..RouteMessage(msg, "Ens.StringRequest"), "", "a message of another class goes nowhere, whatever it holds")
}

/// Only Fallback and Outcome decide the route.
Method TestRuleReadsTwoProperties()
{
	Set decided = ##class(OcuTalon.BridgeExample.Msg.Decided).%New()
	Set decided.ItemId = "digest"
	Set decided.Summary = "ExampleFallbackOut tellnow"
	Set decided.DecisionRef = "fallback"
	Set decided.FallbackReason = "timeout"
	Set decided.Outcome = "digest"
	Set decided.Fallback = 0
	Do $$$AssertEquals(..RouteMessage(decided, ..#DECIDED), "ExampleDigestOut", "a reason on a decision that is not a fallback changes nothing, and the text fields are not read")
	Set decided.Outcome = "ignore"
	Set decided.Summary = "tellnow"
	Do $$$AssertEquals(..RouteMessage(decided, ..#DECIDED), "", "a summary that says tellnow does not route an ignore")
	Set decided.Fallback = 1
	Set decided.FallbackReason = ""
	Do $$$AssertEquals(..RouteMessage(decided, ..#DECIDED), "ExampleFallbackOut", "Fallback decides, with no reason on the message")
}

/// The classes of the example's own items, the router's rule, and that each name the example sends to is an item of its production.
Method TestWiring()
{
	Set definition = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(definition), "the example production is registered")
	If '$IsObject(definition) Quit
	Set classes = "ExampleItemIn=OcuTalon.BridgeExample.ItemIn,ExampleTriage=OcuTalon.BridgeExample.Triage,ExampleRouter=EnsLib.MsgRouter.RoutingEngine,"
		_"ExampleNotifyOut=OcuTalon.BridgeExample.Outcome,ExampleDigestOut=OcuTalon.BridgeExample.Outcome,ExampleFallbackOut=OcuTalon.BridgeExample.Outcome"
	Set names = ","
	Set rule = ""
	Set checked = 0
	For i = 1:1:definition.Items.Count() {
		Set item = definition.Items.GetAt(i)
		Set names = names_item.Name_","
		Set want = ..Lookup(classes, item.Name)
		If want '= "" {
			Set checked = checked + 1
			Do $$$AssertEquals(item.ClassName, want, item.Name_" is of class "_want)
		}
		If item.Name = "ExampleRouter" {
			For j = 1:1:item.Settings.Count() {
				If item.Settings.GetAt(j).Name = "BusinessRuleName" Set rule = item.Settings.GetAt(j).Value
			}
		}
	}
	Do $$$AssertEquals(checked, 6, "the six items of the example's own classes are in the production")
	Do $$$AssertEquals(rule, ..#RULE, "the router's BusinessRuleName is the example's rule")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(rule), "and the rule class is compiled")
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(..#RULE_"||RuleDefinition")
	Do $$$AssertTrue($IsObject(xdata), "the rule has its definition")
	If $IsObject(xdata) {
		Set text = xdata.Data.Read(1000000)
		Set count = $Length(text, "target=""") - 1
		Do $$$AssertEquals(count, 3, "the rule sends to three targets")
		For i = 2:1:count + 1 {
			Set target = $Piece($Piece(text, "target=""", i), """", 1)
			Do $$$AssertTrue(names [ (","_target_","), "the rule's target "_target_" is an item of the production")
		}
	}
	Do $$$AssertTrue(names [ ",Decide,", "Decide, which ExampleTriage sends to, is an item of the production")
	Set service = ..Initial("OcuTalon.BridgeExample.ItemIn", "TargetConfigName")
	Do $$$AssertEquals(service, """ExampleTriage""", "ExampleItemIn sends to ExampleTriage by default")
	Do $$$AssertTrue(names [ (","_$Translate(service, """")_","), "which is an item of the production")
	Set router = ..Initial("OcuTalon.BridgeExample.Triage", "RouterName")
	Do $$$AssertEquals(router, """ExampleRouter""", "ExampleTriage sends its decision to ExampleRouter by default")
	Do $$$AssertTrue(names [ (","_$Translate(router, """")_","), "which is an item of the production")
}

/// The service, the process and the operation refuse what they cannot take, before they send or log anything.
Method TestRefusals()
{
	Set service = ##class(OcuTalon.BridgeExample.ItemIn).%New("ExampleItemIn")
	Set sc = service.OnProcessInput(##class(Ens.StringRequest).%New(), .out)
	Do $$$AssertStatusNotOK(sc, "ExampleItemIn refuses a message that is not an Item")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "takes an OcuTalon.BridgeExample.Msg.Item", "and says it takes an Item")
	Set sc = service.OnProcessInput(##class(OcuTalon.BridgeExample.Msg.Item).%New(), .out)
	Do $$$AssertStatusNotOK(sc, "it refuses an Item with no subject and no body")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "Subject") && (text [ "Body"), "and the error is Check's, which names Subject and Body")
	Set operation = ##class(OcuTalon.BridgeExample.Outcome).%New("ExampleNotifyOut")
	Set sc = operation.OnMessage(##class(Ens.StringRequest).%New(), .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "the operation answers 'not implemented' (error 5003) to a message that is not a Decided")
	Set sc = operation.OnMessage("", .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "and to no message")
	Set process = ##class(OcuTalon.BridgeExample.Triage).%New("ExampleTriage")
	Set item = ##class(OcuTalon.BridgeExample.Msg.Item).%New()
	Set sc = process.OnResponse(item, .reply, "", ##class(Ens.StringResponse).%New(), "")
	Do $$$AssertStatusNotOK(sc, "ExampleTriage refuses an answer that is not a DecisionResponse, and routes nothing")
}

/// --- helpers ---
/// The items that the rule sends a Decided message to, joined by commas; "" when it sends nowhere.
ClassMethod Route(fallback As %Boolean, outcome As %String) As %String [ Private ]
{
	Set decided = ##class(OcuTalon.BridgeExample.Msg.Decided).%New()
	Set decided.Fallback = fallback
	Set decided.Outcome = outcome
	Quit ..RouteMessage(decided, ..#DECIDED)
}

/// Evaluates the example's rule for a message as the router would, with the message as the document and its class as MsgClass. Rule
/// logging is at errors only, so nothing is written for a rule that evaluates. Returns every target of every send action, joined by
/// commas, or the error text. The actions are joined by ";" and the targets of one action by "," (as the router reads them), so a
/// second send, whether a second action or a second target, is in the result.
ClassMethod RouteMessage(message As %RegisteredObject, msgClass As %String) As %String [ Private ]
{
	Set context = ##class(EnsLib.MsgRouter.RoutingEngine).%New("ExampleRouter")
	Set context.Document = message
	Set context.MsgClass = msgClass
	Set sc = ##class(Ens.Rule.Definition).EvaluateRules(..#RULE, "", context, "", .value, .reason, "e")
	If $$$ISERR(sc) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Set value = $Get(value)
	Set targets = ""
	For i = 1:1:$Length(value, ";") {
		Set action = $Piece(value, ";", i)
		If $Piece(action, ":", 1) '= "send" Continue
		Set list = $Piece(action, ":", 2)
		For j = 1:1:$Length(list, ",") {
			Set target = $ZStrip($Piece(list, ",", j), "<>W")
			If target '= "" Set targets = targets_$Select(targets = "": "", 1: ",")_target
		}
	}
	Quit targets
}

/// The value of name in a list of name=value pairs joined by commas, or "".
ClassMethod Lookup(pairs As %String, name As %String) As %String [ Private ]
{
	Set found = ""
	For i = 1:1:$Length(pairs, ",") {
		If $Piece($Piece(pairs, ",", i), "=", 1) = name Set found = $Piece($Piece(pairs, ",", i), "=", 2)
	}
	Quit found
}

/// The InitialExpression of the property of the compiled class, as written (a string keeps its quotes), or "".
ClassMethod Initial(class As %String, property As %String) As %String [ Private ]
{
	Set compiled = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_property)
	If '$IsObject(compiled) Quit ""
	Quit compiled.InitialExpression
}

}
