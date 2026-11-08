/// Minimal reproduction for the S11 crash: an AI Hub tool whose one method calls the embedded Python method.
Class Repro.Tools Extends %AI.Tool
{

/// Calls Repro.Py's Python method from inside the tool callback.
ClassMethod PyPing() As %String
{
	quit ##class(Repro.Py).PyPing()
}

}
