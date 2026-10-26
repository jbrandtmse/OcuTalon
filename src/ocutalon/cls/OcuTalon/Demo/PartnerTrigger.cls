/// PartnerTrigger, the business operation that makes the simulated partner send the session's batch of orders (AD-3, AD-14, AD-17).
/// BreakFeedIn sends it a Demo.Msg.SendOrders; for it the operation:
///   - refuses any other request, and a session with no session row (an error status; nothing is written or sent);
///   - reads the session row, which holds the IRIS user and the TraceRef (no user name travels in a message, AD-4);
///   - writes the Action audit entry (AD-17), through Bridge.Audit.Record, and sends nothing when that fails;
///   - sends the batch: COUNT orders written in DATEFORMAT, with no order date (the partner uses its local date today), every
///     message carrying the session's TraceRef as SuperSession. The orders carry no SessionRef.
/// Send is the one method of the press that switches namespace (New $NAMESPACE, to the Orders namespace); the constants are read before it.
Class OcuTalon.Demo.PartnerTrigger Extends Ens.BusinessOperation
{

/// The number of orders in a batch.
Parameter COUNT = 50;

/// How the partner writes each order date: its second format, the one its transform rejects.
Parameter DATEFORMAT = "MM/DD/YYYY";

/// The action of the audit entry; with the result it reads "Break the feed: 50 orders".
Parameter ACTION = "Break the feed";

Parameter ERRORREQUEST = "PartnerTrigger takes a request to send the session's orders, and nothing else.";

Parameter ERRORSESSION = "The request's session has no session row.";

Parameter ERRORAUDIT = "The audit entry of the press could not be written, so no orders were sent: ";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	If '$IsObject($Get(pRequest)) || ($ClassName(pRequest) '= "OcuTalon.Demo.Msg.SendOrders") Quit $SYSTEM.Status.Error(5001, ..#ERRORREQUEST)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(pRequest.SessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, ..#ERRORSESSION)
	Set sc = ..WriteAudit(..AuditData(session, pRequest.Channel), ..#ACTION_": "_..#COUNT_" orders")
	If $SYSTEM.Status.IsError(sc) Quit $SYSTEM.Status.Error(5001, ..#ERRORAUDIT_$SYSTEM.Status.GetErrorText(sc))
	Quit ..Send(session.TraceRef)
}

/// The audit data of the press, in the shape of the Action type (Bridge.Audit.Record): the action and the result that make the
/// description, the batch's production and date format as the target, the number of orders as the count, no approval, the session's
/// IRIS user, the session and the channel. Every member is typed as Record requires.
ClassMethod AuditData(session As OcuTalon.Data.Session, channel As %String) As %DynamicObject [ Private ]
{
	Set data = {}
	Do data.%Set("action", ..#ACTION, "string")
	Do data.%Set("target", ##class(OcuTalon.Install.Step.Demo).#PRODUCTION_" ("_..#DATEFORMAT_")", "string")
	Do data.%Set("result", ..#COUNT_" orders", "string")
	Do data.%Set("counts", {"orders": (..#COUNT)})
	Do data.%Set("approvalRef", "", "string")
	Do data.%Set("irisUser", session.IrisUser, "string")
	Do data.%Set("sessionRef", session.Ref, "string")
	Do data.%Set("channel", channel, "string")
	Quit data
}

/// The one audit write of the class: an entry of type Action, through the one writer of product code. description is the text the
/// entry will carry (Record builds it from the data). A test subclass overrides it.
Method WriteAudit(data As %DynamicObject, description As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
}

/// The one send of the class, and the one namespace switch: the partner sends the batch in the Orders namespace. The constants are
/// read before the switch.
Method Send(traceRef As %String) As %Status [ Private ]
{
	Set count = ..#COUNT
	Set format = ..#DATEFORMAT
	Set namespace = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Quit ##class(OcuTalon.Demo.Orders.Partner).Send(count, format, traceRef, "")
}

}
