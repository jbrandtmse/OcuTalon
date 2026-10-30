/// The per-call context (AD-6): the runner sets it before a model call, and the gate and the tools read it. It holds
/// the request's fields, including the caller's thread session id and the SuperSession, the taint of the turn and the
/// host data that a tool fills, the characters that the tool results of the current model step have used (ToolResultChars, AD-10) and the
/// number of commands that the tools of the call have submitted (CommandCount, AD-1): a host's tools number the commands that they submit in
/// one call with it, and Begin starts it at 0, so a call that runs again numbers its commands from 1 again.
/// It lives in the process-private global ^||OcuTalonBP.Context, not in a local variable,
/// because a callback of AI Hub may New local variables; it ends with the process, and a job that did not call Begin
/// sees no context.
/// The context of a replay (kind tool, Replay.Run) also holds the grant of the approved call (Grant): one entry of the same global that the gate
/// consumes at the first call that matches it (TakeGrant). The grant is not a field: Current and Put never expose or set it, and Begin and End kill it.
Class OcuTalon.Bridge.Context Extends %RegisteredObject
{

/// The names that Begin copies from the request and that Put may set, comma-separated.
Parameter FIELDS = "Kind,Provenance,ItemId,DecisionRef,OwnerRef,TraceRef,Channel,ThreadSessionId,SuperSession,Runner,Tainted,HostData,ToolResultChars,CommandCount";

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

/// The runner item (its config name) whose job holds the context: the gate copies it into the approval request of a held call, so that the
/// request is replayed in the same runner (DW-194). Empty for a context that no runner began.
Property Runner As %String(MAXLEN = 128);

/// True when a tool result that is not trusted output has reached the turn (AD-10). The gate sets it when it allows a call whose tool is
/// not trusted output, and a tool may set it itself. Begin starts every turn at 0, an untrusted turn included: the provenance says whether
/// the item came from the user, and this says whether such a result reached the model.
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

/// Starts the context of this process from the request, with the SuperSession of the call and the runner item (empty for none), and replaces a
/// context that is already set (and kills its grant). The taint starts at 0, the host data empty, and the tool result characters and the command count at 0.
ClassMethod Begin(request As OcuTalon.Bridge.Msg.Request, superSession As %String = "", runner As %String = "") As %Status
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
	Set ^||OcuTalonBP.Context("Runner") = runner
	Set ^||OcuTalonBP.Context("Tainted") = 0
	Set ^||OcuTalonBP.Context("HostData") = ""
	Set ^||OcuTalonBP.Context("ToolResultChars") = 0
	Set ^||OcuTalonBP.Context("CommandCount") = 0
	Quit $SYSTEM.Status.OK()
}

/// Ends the context of this process, and its grant. Does nothing when there is none.
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

/// The node of the grant of the replay, in the same process-private global as the context and outside FIELDS.
Parameter GRANT = "grant";

/// Builds the grant of the replay from the approval request with the Ref, in the context of this process: $ListBuild(Ref, ToolName, the hash of the
/// canonical ToolArguments, ToolSource). Only a tool_call row in the state executing gives a grant (the replay starts the run first, StartExecution);
/// any other row, a missing row and a process with no context are an error and leave no grant. A grant already there is replaced.
ClassMethod Grant(ref As %String) As %Status
{
	Kill ^||OcuTalonBP.Context(..#GRANT)
	If '..Active() Quit $SYSTEM.Status.Error(5001, "There is no context to grant the call of "_$Extract(ref, 1, 64)_" in")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) || $$$ISERR(row.%Reload()) Quit $SYSTEM.Status.Error(5001, "There is no approval request "_$Extract(ref, 1, 64)_" to grant")
	If (row.Kind '= "tool_call") || (row.State '= "executing") {
		Quit $SYSTEM.Status.Error(5001, "The approval request "_ref_" is a "_row.Kind_" in the state "_row.State_", and only an executing tool_call is granted")
	}
	Set hash = ""
	Set failure = $SYSTEM.Status.Error(5001, "The arguments of the approval request "_ref_" cannot be hashed")
	Try {
		Set hash = ..ArgumentsHash(row.ToolArguments)
	} Catch exception {
		Set hash = ""
		Set failure = exception.AsStatus()
	}
	If hash = "" Quit failure
	Set ^||OcuTalonBP.Context(..#GRANT) = $ListBuild(ref, row.ToolName, hash, row.ToolSource)
	Quit $SYSTEM.Status.OK()
}

/// 1 and the grant is gone when the call matches it: the name, the hash of the canonical arguments (key order and number spelling do not matter)
/// and the source are all equal. Any other call, a hash that cannot be made and a process with no grant give 0 and leave the grant as it was.
ClassMethod TakeGrant(name As %String, arguments As %RegisteredObject, source As %String) As %Boolean
{
	If '..Active() || '$Data(^||OcuTalonBP.Context(..#GRANT)) Quit 0
	Set grant = ^||OcuTalonBP.Context(..#GRANT)
	Set hash = ""
	Try {
		Set hash = ..ArgumentsHash(arguments)
	} Catch {
		Set hash = ""
	}
	If (hash = "") || (name '= $ListGet(grant, 2)) || (hash '= $ListGet(grant, 3)) || (source '= $ListGet(grant, 4)) Quit 0
	Kill ^||OcuTalonBP.Context(..#GRANT)
	Quit 1
}

/// The source of the grant (the ToolSource of the approved row), or "" when there is none.
ClassMethod GrantSource() As %String
{
	If '..Active() || '$Data(^||OcuTalonBP.Context(..#GRANT)) Quit ""
	Quit $ListGet(^||OcuTalonBP.Context(..#GRANT), 4)
}

/// The hash of the canonical form of the arguments, an object or JSON text (blank text is {}): SHA-256 of the UTF-8 text, base64. The canonical form
/// sorts the keys of every object, keeps the order of every array, writes a number as +value (so 1.0, 1 and 1e0 are one) and writes a string and a
/// literal by its type. It throws for text that is not JSON.
ClassMethod ArgumentsHash(arguments As %RegisteredObject) As %String
{
	If $IsObject(arguments) {
		Set value = arguments
	} ElseIf $ZStrip(arguments, "*WC") = "" {
		Set value = {}
	} Else {
		Set value = ##class(%Library.DynamicAbstractObject).%FromJSON(arguments)
	}
	If '$IsObject(value) || 'value.%IsA("%Library.DynamicAbstractObject") $$$ThrowStatus($SYSTEM.Status.Error(5001, "The arguments are not a JSON object or array"))
	Quit $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, $ZConvert(..Canonical(value, $Select(value.%IsA("%Library.DynamicArray"): "array", 1: "object")), "O", "UTF8")), 1)
}

/// The canonical text of a JSON value of the type (%GetTypeOf): see ArgumentsHash.
ClassMethod Canonical(value, type As %String) As %String [ Private ]
{
	If type = "object" {
		Kill keys
		Set iterator = value.%GetIterator()
		While iterator.%GetNext(.key) {
			Set keys("k" _ key) = ""
		}
		Set text = ""
		Set sorted = ""
		For {
			Set sorted = $Order(keys(sorted))
			If sorted = "" Quit
			Set key = $Extract(sorted, 2, *)
			Set text = text _ $Select(text = "": "", 1: ",") _ ..Quoted(key) _ ":" _ ..Canonical(value.%Get(key), value.%GetTypeOf(key))
		}
		Quit "{" _ text _ "}"
	}
	If type = "array" {
		Set text = ""
		Set iterator = value.%GetIterator()
		While iterator.%GetNext(.index, .item, .itemType) {
			Set text = text _ $Select(index = 0: "", 1: ",") _ ..Canonical(item, itemType)
		}
		Quit "[" _ text _ "]"
	}
	If type = "number" Quit +value
	If type = "boolean" Quit $Select(value: "true", 1: "false")
	If type = "string" Quit ..Quoted(value)
	Quit "null"
}

/// The JSON text of one string.
ClassMethod Quoted(text As %String) As %String [ Private ]
{
	Set holder = []
	Do holder.%Push(text, "string")
	Set json = holder.%ToJSON()
	Quit $Extract(json, 2, *-1)
}

}
