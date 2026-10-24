/// The per-call context (AD-6): the runner sets it before a model call, and the gate and the tools read it. It holds
/// the request's fields, including the caller's thread session id and the SuperSession, the taint of the turn and the
/// host data that a tool fills, the characters that the tool results of the current model step have used (ToolResultChars, AD-10) and the
/// number of commands that the tools of the call have submitted (CommandCount, AD-1): a host's tools number the commands that they submit in
/// one call with it, so that the position of a command in the call is the same on every run of the call.
/// It lives in the process-private global ^||OcuTalonBP.Context, not in a local variable,
/// because a callback of AI Hub may New local variables; it ends with the process, and a job that did not call Begin
/// sees no context.
Class OcuTalon.Bridge.Context Extends %RegisteredObject
{

/// The names that Begin copies from the request and that Put may set, comma-separated.
Parameter FIELDS = "Kind,Provenance,ItemId,DecisionRef,OwnerRef,TraceRef,Channel,ThreadSessionId,SuperSession,Tainted,HostData,ToolResultChars,CommandCount";

/// One of Msg.Enum REQUESTKIND.
Property Kind As %String(MAXLEN = 32);

/// One of Msg.Enum PROVENANCE.
Property Provenance As %String(MAXLEN = 32);

/// The item's Ref.
Property ItemId As %String(MAXLEN = 22);

Property DecisionRef As %String(MAXLEN = 22);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

Property TraceRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The caller's own trace session id.
Property ThreadSessionId As %Integer;

/// The SuperSession that the messages of the call carry.
Property SuperSession As %String(MAXLEN = 64);

/// True when untrusted content reached the turn.
Property Tainted As %Boolean [ InitialExpression = 0 ];

/// JSON a tool may fill, such as check rows.
Property HostData As %String(MAXLEN = "");

/// The characters that the results of the tools of the current model step have used (the shared base of the built-in tools keeps the total, AD-10). Begin
/// sets it to 0, and the step renderer sets it to 0 at every model response, so the results of one model step share one room.
Property ToolResultChars As %Integer [ InitialExpression = 0 ];

/// The number of commands that the tools of the call have submitted so far. A host's tools number the commands that they submit in one call
/// with it: the next command is number CommandCount plus 1, which the tool writes back with Put. Begin sets it to 0, so a call that runs again
/// numbers its commands from 1 again.
Property CommandCount As %Integer [ InitialExpression = 0 ];

/// Starts the context of this process from the request, with the SuperSession of the call, and replaces a context
/// that is already set. The taint starts at 0, the host data empty, and the tool result characters and the command count at 0.
ClassMethod Begin(request As OcuTalon.Bridge.Msg.Request, superSession As %String = "") As %Status
{
	If '$IsObject(request) || '$ClassMethod($ClassName(request), "%Extends", "OcuTalon.Bridge.Msg.Request") {
		Quit $SYSTEM.Status.Error(5001, "A context starts from an OcuTalon.Bridge.Msg.Request")
	}
	Kill ^||OcuTalonBP.Context
	Set ^||OcuTalonBP.Context = 1
	For name = "Kind", "Provenance", "ItemId", "DecisionRef", "OwnerRef", "TraceRef", "Channel", "ThreadSessionId" {
		Set ^||OcuTalonBP.Context(name) = $Property(request, name)
	}
	Set ^||OcuTalonBP.Context("SuperSession") = superSession
	Set ^||OcuTalonBP.Context("Tainted") = 0
	Set ^||OcuTalonBP.Context("HostData") = ""
	Set ^||OcuTalonBP.Context("ToolResultChars") = 0
	Set ^||OcuTalonBP.Context("CommandCount") = 0
	Quit $SYSTEM.Status.OK()
}

/// Ends the context of this process. Does nothing when there is none.
ClassMethod End()
{
	Kill ^||OcuTalonBP.Context
}

/// 1 when this process has a context.
ClassMethod Active() As %Boolean
{
	Quit $Data(^||OcuTalonBP.Context) # 2
}

/// A copy of this process's context, or "" when there is none. Changing the copy changes nothing: use Put.
ClassMethod Current() As OcuTalon.Bridge.Context
{
	If '..Active() Quit ""
	Set context = ..%New()
	For i = 1:1:$Length(..#FIELDS, ",") {
		Set name = $Piece(..#FIELDS, ",", i)
		Set $Property(context, name) = $Get(^||OcuTalonBP.Context(name))
	}
	Quit context
}

/// Sets one field of this process's context. An error when there is no context or the name is not one of FIELDS.
ClassMethod Put(name As %String, value As %String) As %Status
{
	If '..Active() Quit $SYSTEM.Status.Error(5001, "There is no context to put "_name_" into")
	If '$ListFind($ListFromString(..#FIELDS), name) Quit $SYSTEM.Status.Error(5001, "'"_name_"' is not a field of the context")
	Set ^||OcuTalonBP.Context(name) = value
	Quit $SYSTEM.Status.OK()
}

}
