/// The step audit policy (AD-6, AD-9): the adapter adds it to every agent it builds, and AI Hub calls it for every tool call, whatever
/// the tool. It records one tool step in the step buffer (OcuTalon.Bridge.Adapter.StepBuffer) with the raw strings, which the
/// adapter redacts and cuts after Chat.
///   - %LogExecution records the tool's name (call.name), its class (metadata.origin_class), its arguments (call.arguments: the JSON
///     string, or an object turned into JSON), its result (result.result_json, or "" when result is null), the duration in
///     milliseconds, and the status ok or error with the error's own text, without its code, as the detail.
///   - %LogDenial records the status denied with the text of the denial.
/// Both return OK always and catch every exception, and record the step with "" for what they cannot read. They make no call into
/// AI Hub beyond the base class and run no Python: a session call from inside a callback deadlocks the job (AD-6). Only the Class
/// line may name the AI Hub package.
Class OcuTalon.Bridge.Policy.StepAudit Extends %AI.Policy.Audit
{

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
	Try {
		Set outcome = "ok"
		Set detail = ""
		If (status '= "") && $$$ISERR(status) {
			Set outcome = "error"
			Set detail = ..StatusText(status)
		}
		Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tool(..Field(call, "name"), ..Field(metadata, "origin_class"), ..Field(call, "arguments"), ..Field(result, "result_json"), +duration, outcome, detail)
	} Catch {
	}
	Quit $$$OK
}

Method %LogDenial(call As %DynamicObject, metadata As %DynamicObject, status As %Status) As %Status
{
	Try {
		Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tool(..Field(call, "name"), ..Field(metadata, "origin_class"), ..Field(call, "arguments"), "", 0, "denied", ..StatusText(status))
	} Catch {
	}
	Quit $$$OK
}

/// The text of the status, without its code, or "" when it cannot be read: the error text of every error of the status, each without its
/// leading "ERROR <code>:", the control characters that AI Hub puts around the text of an embedded error as spaces (and runs of spaces
/// as one), and the long dash that it puts before it as a hyphen. The text of a tool that failed is inside it, because AI Hub reports
/// the failure as one error whose cause is embedded. At most 2,000 characters.
ClassMethod StatusText(status As %Status) As %String [ Private ]
{
	Set text = ""
	Try {
		Set lines = $ListFromString($SYSTEM.Status.GetErrorText(status), $Char(13, 10))
		Set position = 0
		While $ListNext(lines, position, line) {
			If $Locate(line, "^ERROR (#[0-9]+|<[^>]*>[^:]*): ", 1, end) Set line = $Extract(line, end, *)
			Set text = text _ $Select(text = "": "", 1: " ") _ line
		}
		Set text = $Translate(text, $Char(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31) _ $Char(8212), $Justify("", 31) _ "-")
		Set text = $Extract($ZStrip(text, "=<>", " "), 1, 2000)
	} Catch {
		Set text = ""
	}
	Quit text
}

/// The member of the object as a string: a string or a number as it is, an object or an array as JSON, and "" for anything else, for
/// a member that is not there and for a value that is not an object.
ClassMethod Field(object As %DynamicObject, name As %String) As %String [ Private ]
{
	Set value = ""
	Try {
		If $IsObject(object) {
			Set type = object.%GetTypeOf(name)
			If (type = "string") || (type = "number") {
				Set value = object.%Get(name)
			} ElseIf (type = "object") || (type = "array") {
				Set value = object.%Get(name).%ToJSON()
			}
		}
	} Catch {
		Set value = ""
	}
	Quit value
}

}
