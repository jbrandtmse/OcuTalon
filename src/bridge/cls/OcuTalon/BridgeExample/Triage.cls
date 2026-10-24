/// ExampleTriage, the business process of the bridge example (FR-5, AD-6, AD-30). It renders each item as text, asks Decide for the
/// decision with one OcuTalon.Bridge.Msg.Request, and sends the decision to its router, ExampleRouter, whose rule routes on the
/// decision. Decide's error status ends the process with that status and nothing is routed. The process names the bridge only (AD-2).
Class OcuTalon.BridgeExample.Triage Extends Ens.BusinessProcess
{

/// The item that every decision is sent to.
Property RouterName As Ens.DataType.ConfigName [ InitialExpression = "ExampleRouter" ];

Parameter SETTINGS = "RouterName:Basic";

/// The longest summary, in characters (OcuTalon.Bridge.Msg.Request Summary).
Parameter MAXSUMMARY = 80;

/// Sends Decide the request of the item, asynchronously, and waits for its answer.
Method OnRequest(request As OcuTalon.BridgeExample.Msg.Item, Output response As Ens.Response) As %Status
{
	Set response = ""
	Quit ..SendRequestAsync("Decide", ..RequestFor(request), 1, "decide")
}

/// Sends the router the decision that Decide answered with, and wants no response.
Method OnResponse(request As OcuTalon.BridgeExample.Msg.Item, ByRef response As Ens.Response, callrequest As Ens.Request, callresponse As Ens.Response, pCompletionKey As %String) As %Status
{
	If '$IsObject(callresponse) || 'callresponse.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Quit $$$ERROR($$$GeneralError, "Decide answered with something other than a DecisionResponse")
	}
	Quit ..SendRequestAsync(..RouterName, ..DecidedFor(request, callresponse), 0)
}

/// The decide request of an item (AD-6): kind decide, owner instance, channel system, the item's provenance (untrusted when it has
/// none), its ItemId, the code-written one-line summary and the rendered text. It never carries the item object.
ClassMethod RequestFor(item As OcuTalon.BridgeExample.Msg.Item) As OcuTalon.Bridge.Msg.Request
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "decide"
	Set request.OwnerRef = "instance"
	Set request.Channel = "system"
	Set request.Provenance = $Select(item.Provenance = "": "untrusted", 1: item.Provenance)
	Set request.ItemId = item.ItemId
	Set request.Summary = ..SummaryOf(item)
	Set request.Input = ..Render(item)
	Quit request
}

/// The text of an item for the model: "Subject: ", the subject, a blank line and the body.
ClassMethod Render(item As OcuTalon.BridgeExample.Msg.Item) As %String
{
	Quit "Subject: "_item.Subject_$Char(10, 10)_item.Body
}

/// The code-written summary of an item: its subject, or the first line of the body that is not blank when the subject is blank. It is
/// one line of at most MAXSUMMARY characters: control characters and line breaks become spaces.
ClassMethod SummaryOf(item As OcuTalon.BridgeExample.Msg.Item) As %String
{
	Set text = item.Subject
	If $ZStrip(text, "*WC") = "" {
		Set text = ""
		Set body = $Translate(item.Body, $Char(13), $Char(10))
		For i = 1:1:$Length(body, $Char(10)) {
			Set line = $Piece(body, $Char(10), i)
			If $ZStrip(line, "*WC") '= "" {
				Set text = line
				Quit
			}
		}
	}
	Set text = $Extract(text, 1, 400)
	Set line = ""
	For i = 1:1:$Length(text) {
		Set char = $Extract(text, i)
		Set line = line_$Select(char?1C: " ", 1: char)
	}
	Quit $ZStrip($Extract($ZStrip(line, "<>W"), 1, ..#MAXSUMMARY), ">W")
}

/// The decision message for the router: the item's ItemId, its summary and the decision's reference, outcome, Fallback and reason.
ClassMethod DecidedFor(item As OcuTalon.BridgeExample.Msg.Item, response As OcuTalon.Bridge.Msg.DecisionResponse) As OcuTalon.BridgeExample.Msg.Decided
{
	Set decided = ##class(OcuTalon.BridgeExample.Msg.Decided).%New()
	Set decided.ItemId = item.ItemId
	Set decided.Summary = ..SummaryOf(item)
	Set decided.DecisionRef = response.DecisionRef
	Set decided.Outcome = response.Outcome
	Set decided.Fallback = response.Fallback
	Set decided.FallbackReason = response.FallbackReason
	Quit decided
}

Storage Default
{
<Data name="TriageDefaultData">
<Subscript>"Triage"</Subscript>
<Value name="1">
<Value>RouterName</Value>
</Value>
</Data>
<DefaultData>TriageDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
