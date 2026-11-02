Include Ensemble

/// The replay of an approved tool call (AD-6, AD-10, AD-11): the runner's answer to a request of kind tool, whose ItemId is the Ref of an
/// approval request. It runs the stored call exactly once and never calls a model.
/// Run does, in this order:
///   1. StartExecution of the Ref: the atomic change from approved to executing under the row's lock is the single gate of a run (NFR-13). A row
///      that is not a tool_call is not touched. When the start is refused, nothing runs: the row stays as it is, except an approved row that is
///      past its ExpiresAt, which is closed failed through FinishExecution (it could not start). The reply holds the refusal as FailureText and
///      ToolsRun 0, and no Action entry is written.
///   2. Once started, in a try: the agent is built, a throwaway AI session is created (AD-6 is read literally: it is never linked, never saved and
///      never used for a model request, and ReleaseThrowaway drops it on every path), the context is begun (kind tool, provenance user, the Ref, the
///      runner item) with the grant that Context.Grant builds from the executing row, the step buffer starts, and the tool manager of the agent
///      runs ExecuteTool with exactly the row's ToolName and ToolArguments. The call goes through the whole policy chain: the gate's
///      classification, permissions and provenance rules, then the grant in place of the hold, then the step audit. The result is done when
///      ExecuteTool returns a result with a value (or a void result), and failed otherwise or when it raises. A call that failed is never retried.
///      The returned value is discarded: it reaches no column, no reply and no event, and appears only in the step record of the trace.
///   3. One Action entry through Audit.Record (action the ToolName, target the ToolSource, the result, no counts, the approvalRef, the approver of
///      the row, the session of the owner when it is a Ref, the channel of the answer), and then FinishExecution of the Ref with the result, which
///      fires approval.result. A write or a finish that fails is a warning that names the Ref.
///   4. The reply holds no text and no host data, Tainted 0, ToolsRun 1 (0 when the failure came before ExecuteTool was called), the step records and, for a call that failed, its redacted and cut error
///      text as FailureText.
///   5. The context and the step buffer end, and the throwaway session is released, on every path.
/// A replay holds LOCK ^OcuTalon.Bridge.Replay(<Ref>) from before StartExecution until after Record, and releases it on every path, so the lock
/// says whether a replay of the Ref is alive. CloseInterrupted, which Approval.Reconcile runs after an instance start, closes an executing tool_call
/// row only when it can take that lock at once (no live replay): it writes the Action entry with the result interrupted and finishes the row as
/// interrupted, and never runs the call again (NFR-13).
/// No Chat, no conversation link and no Usage row. This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Replay
{

/// Replays the approved call of the request (kind tool, ItemId the Ref of the approval request) in the job of adapter, which is the runner
/// that holds the call. reply is the Reply described above; the status is an error only when the ItemId of the request is not the Ref of an
/// approval request, and OK otherwise: a refused start, an agent that cannot be built and a call that failed are told by the reply.
ClassMethod Run(adapter As OcuTalon.Bridge.Adapter.Agent, request As OcuTalon.Bridge.Msg.Request, superSession As %String = "", Output reply As OcuTalon.Bridge.Msg.Reply) As %Status
{
	Set reply = ""
	Set ref = request.ItemId
	If '##class(OcuTalon.Bridge.Approval).IsRef(ref) {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Replay.Run needs the Ref of an approval request as the ItemId of the request")
	}
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) || (row.Kind '= "tool_call") {
		Set reply = ..Failure("there is no tool_call approval request with this Ref, so nothing was run")
		Quit $$$OK
	}
	Lock +^OcuTalon.Bridge.Replay(ref):0
	If '$Test {
		Set reply = ..Failure("another replay of this call is running, so nothing was run")
		Quit $$$OK
	}
	Try {
		Set sc = ..Execute(adapter, request, superSession, row, ref, .reply)
	} Catch exception {
		Lock -^OcuTalon.Bridge.Replay(ref)
		Throw exception
	}
	Lock -^OcuTalon.Bridge.Replay(ref)
	Quit sc
}

/// The part of Run that holds the replay lock: the start, the call and Record.
ClassMethod Execute(adapter As OcuTalon.Bridge.Adapter.Agent, request As OcuTalon.Bridge.Msg.Request, superSession As %String, row As OcuTalon.Bridge.Data.ApprovalRequest, ref As %String, Output reply As OcuTalon.Bridge.Msg.Reply) As %Status [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Approval).StartExecution(ref)
	If $$$ISERR(sc) {
		Do ..CloseUnstarted(ref)
		Set reply = ..Failure($SYSTEM.Status.GetErrorText(sc))
		Quit $$$OK
	}
	Set started = $ZHorolog
	Set result = "failed"
	Set failure = ""
	Set steps = ""
	Set count = 0
	Set session = ""
	Set executed = 0
	Try {
		Set sc = adapter.BuildAgent()
		If $$$ISOK(sc) Set sc = adapter.NewSession(.session)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Bridge.Context).Begin(request, superSession, adapter.BusinessHost.%ConfigName)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Bridge.Context).Grant(ref)
		If $$$ISERR(sc) {
			Set failure = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part($SYSTEM.Status.GetErrorText(sc), ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
		} Else {
			Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(0)
			Set executed = 1
			Set answer = adapter.Agent.ToolManager.ExecuteTool(row.ToolName, {}.%FromJSON(row.ToolArguments))
			If $IsObject(answer) && (answer.%IsDefined("value") || (answer.%Get("is_void") = 1)) {
				Set result = "done"
			} Else {
				Set failure = "the tool returned no result"
			}
			Set answer = ""
		}
	} Catch exception {
		Set result = "failed"
		Set failure = ..ErrorText(exception)
	}
	Set records = ""
	Try {
		Set records = adapter.StepRecords()
		Set steps = adapter.StepsJson(records)
		If $IsObject(records) Set count = records.%Size()
	} Catch {
	}
	Set session = ""
	Do adapter.ReleaseThrowaway()
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	Do ..Record(row, ref, result)
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.ToolsRun = executed
	Set reply.Tainted = 0
	Set reply.Steps = steps
	Set reply.AgentStepCount = count
	Set reply.DurationMs = $Number(($ZHorolog - started) * 1000, 0)
	Set reply.FailureText = failure
	Quit $$$OK
}

/// A failure Reply for a run that did not start: the redacted, cut text as FailureText, ToolsRun 0.
ClassMethod Failure(text As %String) As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.FailureText = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(text, ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
	Set reply.ToolsRun = 0
	Quit reply
}

/// The redacted, cut text of an exception: AI Hub's error text when it can be read, else the exception's own.
ClassMethod ErrorText(exception As %Exception.AbstractException) As %String [ Private ]
{
	Set text = ""
	Try {
		Set text = $SYSTEM.Status.GetErrorText(##class(%AI.System).HandleError(exception, 1))
	} Catch {
		Set text = ""
	}
	If text = "" {
		Try {
			Set text = exception.DisplayString()
		} Catch {
			Set text = "the call failed"
		}
	}
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(text, ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
}

/// Closes a run that could not start: an approved row past its ExpiresAt becomes failed through FinishExecution (its caller learns the end from
/// approval.result). A row in any other state, and a refusal for any other reason (a lock that was not taken), is left alone.
ClassMethod CloseUnstarted(ref As %String) [ Private ]
{
	Try {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If $IsObject(row) && ($$$ISOK(row.%Reload())) && (row.State = "approved") {
			Set seconds = ##class(OcuTalon.Bridge.Time).SecondsUntil(row.ExpiresAt)
			If (seconds '= "") && '(seconds > 0) {
				Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, "failed")
				If $$$ISERR(sc) {
					$$$LOGWARNING("OcuTalon.Bridge.Replay: "_ref_" could not start and was not closed as failed: "_$SYSTEM.Status.GetErrorText(sc))
				}
			}
		}
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Bridge.Replay: "_ref_" could not start and was not closed as failed: "_exception.DisplayString())
	}
}

/// Writes the Action entry of a run that started and then finishes it with the result. A failed write or finish is a warning that names the Ref,
/// and the errors are returned combined.
ClassMethod Record(row As OcuTalon.Bridge.Data.ApprovalRequest, ref As %String, result As %String) As %Status [ Private ]
{
	Set status = $$$OK
	Try {
		Set sc = $$$OK
		If $$$ISOK(row.%Reload()) {
			Set sc = ##class(OcuTalon.Bridge.Audit).Record("Action", ..ActionEntry(row, result))
		}
		If $$$ISERR(sc) {
			$$$LOGWARNING("OcuTalon.Bridge.Replay: the Action entry of "_ref_" was not written: "_$SYSTEM.Status.GetErrorText(sc))
			Set status = $SYSTEM.Status.AppendStatus(status, sc)
		}
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Bridge.Replay: the Action entry of "_ref_" was not written: "_exception.DisplayString())
		Set status = $SYSTEM.Status.AppendStatus(status, exception.AsStatus())
	}
	Try {
		Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, result)
		If $$$ISERR(sc) {
			$$$LOGWARNING("OcuTalon.Bridge.Replay: "_ref_" was not finished as "_result_": "_$SYSTEM.Status.GetErrorText(sc))
			Set status = $SYSTEM.Status.AppendStatus(status, sc)
		}
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Bridge.Replay: "_ref_" was not finished as "_result_": "_exception.DisplayString())
		Set status = $SYSTEM.Status.AppendStatus(status, exception.AsStatus())
	}
	Quit status
}

/// Closes the replays that an instance stop interrupted (DW-444): every tool_call row that is executing and whose replay lock can be taken at once,
/// which means that no replay of it is alive. For each, the Action entry with the result interrupted is written and the row is finished as
/// interrupted (failed, Result interrupted, FinishedAt set, approval.result fired), exactly as Record does; the call is never run again (NFR-13). A
/// row whose lock is held (a live replay), and a row in any other state or kind, is left alone. Every row is tried; the errors are combined, each
/// naming its Ref.
ClassMethod CloseInterrupted() As %Status
{
	Set sc = $$$OK
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Kind = 'tool_call' AND State = 'executing'")
	If rows.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The executing tool calls cannot be read: SQLCODE " _ rows.%SQLCODE _ " " _ rows.%Message)
	Set refs = ""
	While rows.%Next() {
		Set refs = refs _ $ListBuild(rows.%Get("Ref"))
	}
	If rows.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The executing tool calls cannot be read: SQLCODE " _ rows.%SQLCODE _ " " _ rows.%Message)
	Set position = 0
	While $ListNext(refs, position, ref) {
		Lock +^OcuTalon.Bridge.Replay(ref):0
		If '$Test Continue
		Try {
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
			If $IsObject(row) && $$$ISOK(row.%Reload()) && (row.Kind = "tool_call") && (row.State = "executing") {
				Set one = ..Record(row, ref, "interrupted")
				If $$$ISERR(one) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The interrupted replay of " _ ref _ " was not closed: " _ $SYSTEM.Status.GetErrorText(one)))
			}
		} Catch exception {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The interrupted replay of " _ ref _ " was not closed: " _ exception.DisplayString()))
		}
		Lock -^OcuTalon.Bridge.Replay(ref)
	}
	Quit sc
}

/// The data of the Action entry of the run (the shape of the field's own entry, which the bridge cannot call, AD-2): the action is the tool's
/// name, the target its source, the counts empty, the approvalRef the Ref, the approver the row's AnsweredBy (else the job's user), the session the
/// row's OwnerRef when that is a Ref, and the channel the row's AnsweredChannel (else system). It holds no argument and no result.
ClassMethod ActionEntry(row As OcuTalon.Bridge.Data.ApprovalRequest, result As %String) As %DynamicObject
{
	Set data = {}
	Do data.%Set("action", row.ToolName, "string")
	Do data.%Set("target", row.ToolSource, "string")
	Do data.%Set("result", result, "string")
	Do data.%Set("counts", {})
	Do data.%Set("approvalRef", row.Ref, "string")
	Do data.%Set("irisUser", $Select(row.AnsweredBy '= "": row.AnsweredBy, 1: $Username), "string")
	Do data.%Set("sessionRef", $Select(##class(OcuTalon.Bridge.Approval).IsRef(row.OwnerRef): row.OwnerRef, 1: ""), "string")
	Do data.%Set("channel", $Select(row.AnsweredChannel '= "": row.AnsweredChannel, 1: "system"), "string")
	Quit data
}

}
