/// The parts of the first model request of a runner that Decide can read without a live agent (AD-6, AD-20), in characters. Decide
/// estimates a request before it sends it, in its own job, where no agent exists: building one would call AI Hub's native library
/// outside a runner and would need the model key. These methods only read. They build no AI Hub agent, open or attach no AI session,
/// make no $ZF call and name no other OcuTalon package (AD-2).
///   - AgentChars: the system prompt of an agent class and the tool schemas of its toolsets, as the agent loads them. The tools that an
///     MCP server adds later (AD-21) are known only to a live tool manager and are not counted.
///   - HistoryChars: the stored history of a saved AI session, read from the stored value of the session.
///   - StoredMessages: the messages of that stored history as a JSON array, read from the same value.
/// A part that cannot be read counts 0, so that the estimate stays a number.
Class OcuTalon.Bridge.RequestSize
{

/// The characters of the system prompt and of the tool schemas of the agent class, and an error status in sc when a part cannot be read
/// (the part then counts 0).
///   - The system prompt is the compiled INSTRUCTIONS block of the class (inherited ones included), read the way AI Hub loads it: the
///     lines of the block, each followed by a line feed, and the last line feed dropped. A class without the block has an empty prompt.
///   - The tool schemas are, for each class that the TOOLSETS parameter names (comma-separated, white space around a name removed),
///     the JSON of the "tools" of the class's own Discover list, which a new instance of the class gives with no native call. A name that
///     holds a colon is a URI and counts 0.
/// A class that is not compiled counts 0 and sets sc.
ClassMethod AgentChars(agentClass As %String, Output sc As %Status) As %Integer
{
	Set sc = $$$OK
	If (agentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) {
		Set sc = $$$ERROR($$$GeneralError, "The agent class '"_agentClass_"' is not a compiled class, so its system prompt and tool schemas are not counted")
		Quit 0
	}
	Set chars = ..InstructionsChars(agentClass, .sc)
	Set toolsets = $Parameter(agentClass, "TOOLSETS")
	For i = 1:1:$Length(toolsets, ",") {
		Set name = $ZStrip($Piece(toolsets, ",", i), "<>W")
		If (name = "") || (name [ ":") Continue
		Try {
			Set chars = chars + $Length($ClassMethod(name, "%New").%Discover().%Get("tools").%ToJSON())
		} Catch exception {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $$$ERROR($$$GeneralError, "The tool schemas of the toolset '"_name_"' of "_agentClass_" cannot be read: "_exception.DisplayString()))
		}
	}
	Quit chars
}

/// The characters of the system prompt of the agent class (AgentChars): 0 for a class with no INSTRUCTIONS block, as AI Hub loads it, and 0 with an
/// error in sc when the block cannot be read.
ClassMethod InstructionsChars(agentClass As %String, ByRef sc As %Status) As %Integer [ Private ]
{
	Set chars = 0
	Try {
		Set xdata = ##class(%Dictionary.CompiledXData).IDKEYOpen(agentClass, "INSTRUCTIONS")
		If $IsObject(xdata) {
			Set text = ""
			Do xdata.Data.Rewind()
			While 'xdata.Data.AtEnd {
				Set text = text _ xdata.Data.ReadLine() _ $Char(10)
			}
			If $Extract(text, $Length(text)) = $Char(10) Set text = $Extract(text, 1, $Length(text) - 1)
			Set chars = $Length(text)
		}
	} Catch exception {
		Set chars = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, $$$ERROR($$$GeneralError, "The INSTRUCTIONS of "_agentClass_" cannot be read: "_exception.DisplayString()))
	}
	Quit chars
}

/// The characters of the history that the saved AI session stores: the size of its stored ContextData stream, which holds the session's
/// exported messages. It is read from the stored value, never by opening or attaching the session, so it needs no live agent and no
/// native call. 0 for an empty id, for an id that no saved session has, for a session that stores no history and when the value cannot
/// be read.
ClassMethod HistoryChars(sessionId As %String) As %Integer
{
	Set chars = 0
	If sessionId = "" Quit 0
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ContextData FROM %AI_Agent.Session WHERE ID = ?", sessionId)
		If result.%Next() {
			Set oid = result.%GetData(1)
			If $ListValid(oid) {
				Set stream = ##class(%Stream.GlobalCharacter).%Open(oid)
				If $IsObject(stream) Set chars = +stream.Size
			}
		}
	} Catch {
		Set chars = 0
	}
	Quit chars
}

/// The messages of the history that the saved AI session stores, as a dynamic array in the order GetContext() gives them, or [] for an empty
/// id, an id that no saved session has, a session that stores no history and a value that cannot be read. Measured (Story 17.2, Task 0): the
/// stored ContextData stream is one full export of the session, a JSON object with its messages, followed by zero or more delta records, each
/// a JSON array of new messages, all separated by the record separator $Char(30); the messages of the full export are the same JSON as
/// GetContext() of the opened session. The session is not opened or attached, so the read takes no native call, no live agent and no lock.
ClassMethod StoredMessages(sessionId As %String) As %DynamicArray
{
	Set messages = []
	If sessionId = "" Quit messages
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ContextData FROM %AI_Agent.Session WHERE ID = ?", sessionId)
		If result.%Next() {
			Set oid = result.%GetData(1)
			If $ListValid(oid) {
				Set stream = ##class(%Stream.GlobalCharacter).%Open(oid)
				If $IsObject(stream) {
					Set text = ""
					Do stream.Rewind()
					While 'stream.AtEnd {
						Set text = text _ stream.Read(32000)
					}
					Set found = []
					For i = 1:1:$Length(text, $Char(30)) {
						Set record = ""
						Try {
							Set record = {}.%FromJSON($Piece(text, $Char(30), i))
						} Catch {
							Set record = ""
						}
						If '$IsObject(record) Continue
						If record.%IsA("%Library.DynamicArray") {
							Set iterator = record.%GetIterator()
							While iterator.%GetNext(, .message) {
								Do found.%Push(message)
							}
						} ElseIf record.%IsA("%Library.DynamicObject") && (record.%GetTypeOf("messages") = "array") {
							Set found = record.messages
						}
					}
					Set messages = found
				}
			}
		}
	} Catch {
		Set messages = []
	}
	Quit messages
}

}
