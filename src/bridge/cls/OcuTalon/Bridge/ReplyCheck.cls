/// The request whose reply Decide is checking (AD-7, AD-8, AD-16). The reply class of a decide or diagnose request validates a reply in Decide's job, where no
/// OcuTalon.Bridge.Context exists (the runner's job begins that), and some checks need what the request carried: the item, the owner and the input
/// the model was given. Decide.Interpret begins this check from the request before it checks the reply, and ends it on every exit, an error included;
/// a reply class's %OnValidateObject reads it with Active and Value.
///   - FIELDS are the names that Value answers: Kind, ItemId, OwnerRef and Input, copied from the request;
///   - Begin clears every earlier value first, so nothing of an earlier request survives it, then copies the request. It refuses anything that is not an
///     OcuTalon.Bridge.Msg.Request;
///   - End clears the check, and Active says whether there is one;
///   - Value gives "" for no check and for a name that is not one of FIELDS.
/// The values live in the process-private global ^||OcuTalonBP.ReplyCheck, so a check ends with its process and is never seen by another job. This class is separate
/// from Context, which means "inside a model call" to the gate and the tools.
Class OcuTalon.Bridge.ReplyCheck Extends %RegisteredObject
{

/// The names that Begin copies from the request and that Value answers, comma-separated.
Parameter FIELDS = "Kind,ItemId,OwnerRef,Input";

/// Starts the check of this process from the request, replacing every value of an earlier check.
ClassMethod Begin(request As OcuTalon.Bridge.Msg.Request) As %Status
{
	Kill ^||OcuTalonBP.ReplyCheck
	If '$IsObject(request) || '$ClassMethod($ClassName(request), "%Extends", "OcuTalon.Bridge.Msg.Request") {
		Quit $SYSTEM.Status.Error(5001, "A reply check starts from an OcuTalon.Bridge.Msg.Request")
	}
	Set ^||OcuTalonBP.ReplyCheck = 1
	For i = 1:1:$Length(..#FIELDS, ",") {
		Set name = $Piece(..#FIELDS, ",", i)
		Set ^||OcuTalonBP.ReplyCheck(name) = $Property(request, name)
	}
	Quit $SYSTEM.Status.OK()
}

/// Ends the check of this process. Does nothing when there is none.
ClassMethod End()
{
	Kill ^||OcuTalonBP.ReplyCheck
}

/// 1 when this process has a check.
ClassMethod Active() As %Boolean
{
	Quit $Data(^||OcuTalonBP.ReplyCheck) # 2
}

/// The value of one field of the check, or "" when there is no check or the name is not one of FIELDS.
ClassMethod Value(name As %String) As %String
{
	If '..Active() || '$ListFind($ListFromString(..#FIELDS), $Get(name)) Quit ""
	Quit $Get(^||OcuTalonBP.ReplyCheck($Get(name)))
}

}
