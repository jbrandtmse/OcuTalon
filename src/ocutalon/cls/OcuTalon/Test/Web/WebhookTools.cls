/// Helpers of the webhook tests (Story 35.3); it has no Test method. THROWAWAY STACKS AND CI ONLY (Rule 21): they read the production's message headers and
/// event log.
///   - Source gives the implementation of a method, for the tests that pin a property of the code itself;
///   - LastHeader and HeadersSince count the message headers of one source item made after a mark, so a test can show that nothing became an item;
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
