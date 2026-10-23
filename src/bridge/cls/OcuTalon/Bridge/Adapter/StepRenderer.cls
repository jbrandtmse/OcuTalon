/// The step renderer (AD-6, AD-9): the runner passes it to Chat, and AI Hub calls it once for every model response. It records one
/// model step in the step buffer (OcuTalon.Bridge.Adapter.StepBuffer) with the length of the response's text, and nothing else.
///   - OnBegin returns an empty string, so that it writes nothing to the job's device and gets no progress calls; it moves the
///     clock mark of the buffer.
///   - OnMessage(content) appends a model step with the length of content.value, or 0 when the value cannot be read (a text over
///     the limit of a string), and sets ToolResultChars of the context to 0 (OcuTalon.Bridge.Context), so that the tool results of
///     one model step share one room (AD-10). AI Hub calls it once for each model response, before the tools of that response run.
///   - OnEnd, OnFeedback and OnChunk do nothing.
/// It catches every exception. It makes no call into AI Hub beyond its base class and runs no Python: a session call from inside a
/// callback deadlocks the job (AD-6); the step buffer and Context.Put, which it calls, only set process-private globals. Only the Class line
/// may name the AI Hub package.
Class OcuTalon.Bridge.Adapter.StepRenderer Extends %AI.Shell.StreamRenderer
{

/// Returns "" and moves the mark of the step buffer.
Method OnBegin() As %String
{
	Try {
		Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Mark()
	} Catch {
	}
	Quit ""
}

/// Records one model step whose text is as long as content.value.
Method OnMessage(content As %DynamicObject)
{
	Try {
		Set length = 0
		Try {
			Set length = $Length(content.%Get("value"))
		} Catch {
			Set length = 0
		}
		Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Model(length)
		Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", 0)
	} Catch {
	}
}

Method OnEnd()
{
}

Method OnFeedback()
{
}

Method OnChunk(chunk As %String)
{
}

}
