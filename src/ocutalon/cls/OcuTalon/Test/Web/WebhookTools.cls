/// Helpers of the webhook tests (Story 35.3); it has no Test method. THROWAWAY STACKS AND CI ONLY (Rule 21): they read the production's message headers and
/// event log.
///   - Source gives the implementation of a method, for the tests that pin a property of the code itself;
///   - LastHeader and HeadersSince count the message headers of one source item made after a mark, so a test can show that nothing became an item;
///   - WaitSettled waits until the event of a trace session has been decided and routed, so a test removes its messages only after every late writer is done;
///   - LastLog and LogText give the text of the event log (Ens_Util.Log) written after a mark, for the tests that scan for a secret;
///   - Columns gives all the stored column values of the rows of a table, as one text, for the same scan;
///   - GlobalHolds says whether a global holds the needle in a value or a subscript.
Class OcuTalon.Test.Web.WebhookTools
{

/// The implementation of the class method, one line per line of code.
ClassMethod Source(class As %String, method As %String) As %String
{
	Set definition = ##class(%Dictionary.MethodDefinition).%OpenId(class_"||"_method)
	If '$IsObject(definition) Quit ""
	Set text = ""
	Set stream = definition.Implementation
	Do stream.Rewind()
	While 'stream.AtEnd {
		Set text = text_stream.ReadLine()_$Char(10)
	}
	Quit text
}

/// The id of the newest message header, 0 when there is none: the mark that HeadersSince counts after.
ClassMethod LastHeader() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	If 'result.%Next() Quit 0
	Quit +result.%GetData(1)
}

/// The number of message headers after the mark whose source item is the name.
ClassMethod HeadersSince(mark As %Integer, source As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = ?", mark, source)
	If 'result.%Next() Quit 0
	Quit +result.%GetData(1)
}

/// 1 once the trace session holds an ItemDecision request that OutcomeRouter has completed and none of its requests is still queued or in flight (the Intake,
/// Decide and routing steps of an event are done); 0 when that has not happened within the seconds. The status 9 is Completed, 1 to 3 are Created, Queued and Delivered.
ClassMethod WaitSettled(sessionId As %String, seconds As %Integer = 60) As %Boolean
{
	Set end = $ZHorolog + seconds
	For {
		Set pending = 0, routed = 0
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, MessageBodyClassName FROM Ens.MessageHeader WHERE SessionId = ? AND Type = 1", sessionId)
		While result.%Next() {
			If (result.%Get("Status") >= 1) && (result.%Get("Status") <= 3) Set pending = pending + 1
			If (result.%Get("Status") = 9) && (result.%Get("MessageBodyClassName") = "OcuTalon.Msg.ItemDecision") Set routed = routed + 1
		}
		If (routed > 0) && (pending = 0) Return 1
		If $ZHorolog > end Return 0
		Hang 0.25
	}
}

/// The id of the newest event log row, 0 when there is none.
ClassMethod LastLog() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	If 'result.%Next() Quit 0
	Quit +result.%GetData(1)
}

/// The text of every event log row after the mark, joined with line feeds.
ClassMethod LogText(mark As %Integer) As %String
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ?", mark)
	While result.%Next() {
		Set text = text_result.%GetData(1)_$Char(10)
	}
	Quit text
}

/// The value of every column of every row of the table (an SQL table name), joined with line feeds. The table name is the test's own constant.
ClassMethod Columns(table As %String) As %String
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM "_table)
	Set count = result.%GetMetadata().columns.Count()
	While result.%Next() {
		For i = 1:1:count {
			Set text = text_result.%GetData(i)_"|"
		}
		Set text = text_$Char(10)
	}
	Quit text
}

/// 1 when a node of the global (the name of an unsubscripted global, for example ^OcuTalonP.Webhook) holds the needle in its value or in a subscript,
/// at any depth.
ClassMethod GlobalHolds(root As %String, needle As %String) As %Boolean
{
	Set holds = 0
	If $Get(@root) [ needle Set holds = 1
	Set node = $Query(@root)
	While (node '= "") && ($Piece(node, "(", 1) = root) && 'holds {
		If ($Get(@node) [ needle) || (node [ needle) Set holds = 1
		Set node = $Query(@node)
	}
	Quit holds
}

}
