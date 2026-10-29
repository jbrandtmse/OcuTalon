Include Ensemble

/// The runs of approved fixes that no waiter ends (AD-16; Story 7.5, DW-395): the Fix area's two jobs besides FixExecutor's own waiter. Both end a run through FixExecutor's End and
/// Mark, the only code that writes a FixRun's end (AD-33), under the run's lock (Fix.Executor RUNLOCK), so that a run ends exactly once, whichever job ends it. They resend nothing,
/// resume nothing and wait for nothing. Lane A.
///   - Interrupt (the Reconcile step calls it through Install.Step.Fix.Reconcile(), at each start, after the Production step): it goes through every FixRun with no EndedAt (Unended)
///     and takes each run that started before the production's current start (Started) and whose request's row is executing, a run that the restart cut short. Under the run's lock
///     it marks the run (Executor.Mark, unless it is marked already: Total and Interrupted are the number of the request's targets) and closes the request through
///     Approval.FinishExecution with the result interrupted (Close), which leaves the row failed. A run that started after that start is live and is left as it is. A problem with one run (a
///     mark or a close that failed, no start time known) is one line of problems, and the others still go; the status is an error only when the runs cannot be read. It is idempotent.
///   - Sweep (Checks calls it on each heartbeat Tick) goes through every FixRun with no EndedAt (Unended), each under its lock (a run it cannot lock in Executor RUNLOCKSECONDS is skipped
///     this Tick), and returns the final FixResult of each run it ends, in a %ListOfObjects. It sends nothing: Checks sends each result to IncidentManager. Two kinds of run:
///       - A marked run (Interrupt marked it): the request is closed first, if its row still is executing (Interrupt's close may have failed), because a result for an executing row
///         would read as still resending (Notice.ResultKey); when that close fails the run is left for the next Tick, with one Type 3 warning (LOGCLOSE) and no result. Then the copies
///         are read (Statuses) and counted (Executor.Tally): Total is the request's targets (else the stored Total), Resent the run's copies, Completed and FailedAgain those that
///         completed and those that failed again, Skipped 0, and Interrupted Total - Completed - FailedAgain, at least 0: the targets that the restart cut off. A read that is not read, a missing incident and
///         a read that throws (one Type 3 warning, LOGREAD) count no copy as completed or failed again. The Reason is that of the failed copy with the lowest id (Executor.FailReason). The
///         run ends interrupted (Executor.End), one Action entry is written with the result interrupted (WriteAudit) and the FixResult is built (Executor.ResultOf; Interrupted 1 when
///         Interrupted is above 0, else the run's own result). A run whose request's row is gone ends with its counts, and no entry or result is made.
///       - A run that no waiter ended (DW-395), not marked: its FixExecutor waiter stopped (its job was asked to quiesce or terminate, or its item was stopped) and left it. Sweep takes it
///         when it has a ResentAt, its wait is over (now is at least ResentAt + Executor WAITSECONDS), its request's row is executing, the read is read, no copy is still running and the
///         last of its copies was done before the wait was over (Tally lastAt, from the header's time of its last status change; a copy without one never qualifies). Sweep ends it as the
///         waiter would have: Skipped is Total - Resent, Interrupted 0, the request is closed done after End (a close that fails or throws logs one Type 3 warning, LOGCLOSE, and the rest goes on), one Action entry is written with
///         the result done, and the FixResult is returned. A run inside its wait (the waiter's), with a copy still running or whose last copy was done after the wait (Story 30.5's), with no ResentAt
///         (the next start's Interrupt ends it) or whose row is not executing is left alone.
///     A run whose End refuses it (another job ended it) or whose save failed (one Type 3 warning, LOGSAVE) returns no result and is left for the next Tick; a result never goes out twice for
///     a run. Sweep logs one Type 4 line for each run it ends (LOGSWEPT); an exception for one run logs one Type 3 warning (LOGSWEEP) and the next run is still swept.
/// The seams Unended (the runs with no EndedAt), Started (the start of the production), Statuses (the read of the copies, Executor.Read), Close (FinishExecution) and WriteAudit (the audit write)
/// are class methods that a test subclass overrides (Test.Fix.RunProbe). Fix.Run switches no namespace (AD-3): the only read of the production is Watch.Reader, through Executor.Read.
Class OcuTalon.Fix.Run Extends %RegisteredObject
{

/// The state of a request that is carried out.
Parameter EXECUTING = "executing";

/// The result that closes the request of a run that was cut short, and the result of a run that no waiter ended.
Parameter INTERRUPTED = "interrupted";

Parameter DONE = "done";

/// The start of each log line of the class.
Parameter LOGCLOSE = "Fix.Run could not close request ";

Parameter LOGREAD = "Fix.Run could not read the copies of request ";

Parameter LOGSAVE = "Fix.Run could not save the end of the run of request ";

Parameter LOGAUDIT = "Fix.Run could not write the audit entry of request ";

Parameter LOGSWEEP = "Fix.Run could not sweep the run of request ";

Parameter LOGSWEPT = "Fix.Run ended the run of request ";

/// Marks each run that the restart cut short and closes its request (see the class description). problems is a dynamic array of one text for each problem, each naming the request.
/// The status is an error only when the runs cannot be read.
ClassMethod Interrupt(Output problems As %DynamicArray) As %Status
{
	Set problems = []
	Set started = ""
	Try {
		Set started = ..Started()
	} Catch exception {
		Set started = ""
	}
	If started = "" {
		Do problems.%Push("the start time of the production is not known, so no run was marked as interrupted")
		Quit $$$OK
	}
	Try {
		Set ids = ..Unended()
	} Catch exception {
		Return exception.AsStatus()
	}
	Set position = 0
	While $ListNext(ids, position, id) {
		Try {
			Do ..MarkOne(id, started, problems)
		} Catch exception {
			Do problems.%Push("the run "_id_" could not be checked: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		}
	}
	Quit $$$OK
}

/// One run of Interrupt, under its lock: marked and its request closed when it started before started and its request is executing. A problem is pushed on problems.
ClassMethod MarkOne(id As %String, started As %String, problems As %DynamicArray) [ Private ]
{
	If '##class(OcuTalon.Fix.Executor).TakeRun(id) {
		Do problems.%Push("the run "_id_" could not be locked, so it was left as it is")
		Quit
	}
	Set fault = ""
	Try {
		Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
		Set row = $Select($IsObject(run): ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(run.ApprovalRef), 1: "")
		If $IsObject(run) && (run.EndedAt = "") && (run.StartedAt '= "") && (started ] run.StartedAt) && $IsObject(row) && (row.State = ..#EXECUTING) {
			Set marked = 1
			If +run.Interrupted '> 0 {
				Set marked = ##class(OcuTalon.Fix.Executor).Mark(run, ..Targets(row), .sc)
				If 'marked Do problems.%Push("request "_row.Ref_" was not closed, because its run could not be marked as interrupted: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			}
			If marked {
				Set sc = ..Close(row.Ref, ..#INTERRUPTED)
				If $$$ISERR(sc) Do problems.%Push("request "_row.Ref_" was not closed, its run is marked as interrupted and the next heartbeat closes it: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			}
		}
	} Catch exception {
		Set fault = exception
	}
	Do ##class(OcuTalon.Fix.Executor).FreeRun(id)
	If $IsObject(fault) Throw fault
}

/// The final FixResult of each run that ends now (see the class description), as a %ListOfObjects; none for a run that is left alone.
ClassMethod Sweep() As %ListOfObjects
{
	Set results = ##class(%ListOfObjects).%New()
	Set ids = ..Unended()
	Set position = 0
	While $ListNext(ids, position, id) {
		Set result = ""
		Try {
			Set result = ..One(id)
		} Catch exception {
			Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
			$$$LOGWARNING(..#LOGSWEEP_$Select($IsObject(run): run.ApprovalRef, 1: id)_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		}
		If $IsObject(result) Do results.Insert(result)
	}
	Quit results
}

/// One run of Sweep, under its lock: its FixResult, or "" when the run is left alone or locked.
ClassMethod One(id As %String) As OcuTalon.Fix.Msg.FixResult [ Private ]
{
	If '##class(OcuTalon.Fix.Executor).TakeRun(id) Quit ""
	Set result = ""
	Set fault = ""
	Try {
		Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
		If $IsObject(run) && (run.EndedAt = "") {
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(run.ApprovalRef)
			Set result = $Select(+run.Interrupted > 0: ..EndMarked(run, row), 1: ..EndLeft(run, row))
		}
	} Catch exception {
		Set fault = exception
	}
	Do ##class(OcuTalon.Fix.Executor).FreeRun(id)
	If $IsObject(fault) Throw fault
	Quit result
}

/// A marked run: its request closed first, the copies counted, the run ended interrupted, the entry written and the FixResult built (see the class description).
ClassMethod EndMarked(run As OcuTalon.Data.FixRun, row As OcuTalon.Bridge.Data.ApprovalRequest) As OcuTalon.Fix.Msg.FixResult [ Private ]
{
	Set ref = $Select($IsObject(row): row.Ref, 1: run.ApprovalRef)
	If $IsObject(row) && (row.State = ..#EXECUTING) {
		Set sc = ..Close(ref, ..#INTERRUPTED)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGCLOSE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit ""
		}
	}
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(run.IncidentRef)
	Set outcome = ""
	Set statuses = ""
	If $IsObject(incident) {
		Try {
			Set outcome = ..Statuses(incident, run, .statuses)
		} Catch exception {
			Set outcome = ""
			$$$LOGWARNING(..#LOGREAD_ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		}
	}
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, outcome, statuses)
	Set total = $Select($IsObject(row) && (row.FixTargets '= ""): ..Targets(row), 1: +run.Total)
	Set cutOff = total - tally.completed - tally.failedAgain
	Set reason = ""
	If tally.failedAgain > 0 Set reason = ##class(OcuTalon.Fix.Executor).FailReason(incident, row, statuses.%Get(tally.failed))
	Set counts = {"total": (total), "resent": (run.Copies.Count()), "completed": (tally.completed), "failedAgain": (tally.failedAgain), "skipped": 0, "interrupted": ($Select(cutOff > 0: cutOff, 1: 0)), "reason": (..Plain(reason))}
	If '..Ended(run, row, counts, 1) Quit ""
	If '$IsObject(row) Quit ""
	Do ..Entry(row, ..#INTERRUPTED, counts)
	Quit ##class(OcuTalon.Fix.Executor).ResultOf(row, counts)
}

/// A run that no waiter ended: taken only when the waiter would have ended it (see the class description). Its FixResult, or "" when the run is left alone.
ClassMethod EndLeft(run As OcuTalon.Data.FixRun, row As OcuTalon.Bridge.Data.ApprovalRequest) As OcuTalon.Fix.Msg.FixResult [ Private ]
{
	If run.ResentAt = "" Quit ""
	Set start = ##class(OcuTalon.Watch.Settle).Seconds(run.ResentAt)
	If start = "" Quit ""
	Set due = start + ##class(OcuTalon.Fix.Executor).#WAITSECONDS
	If ##class(OcuTalon.Watch.Settle).Seconds(##class(OcuTalon.Data.Time).NowUtc()) < due Quit ""
	If '$IsObject(row) || (row.State '= ..#EXECUTING) Quit ""
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(run.IncidentRef)
	If '$IsObject(incident) Quit ""
	Set outcome = ""
	Try {
		Set outcome = ..Statuses(incident, run, .statuses)
	} Catch exception {
		$$$LOGWARNING(..#LOGREAD_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		Return ""
	}
	If outcome '= "read" Quit ""
	Set tally = ##class(OcuTalon.Fix.Executor).Tally(run, outcome, statuses)
	If (tally.running > 0) || (tally.lastAt = "") || (tally.lastAt '< due) Quit ""
	Set total = ..Targets(row)
	Set resent = run.Copies.Count()
	Set reason = $Select(tally.failed = "": "", 1: ##class(OcuTalon.Fix.Executor).FailReason(incident, row, statuses.%Get(tally.failed)))
	Set counts = {"total": (total), "resent": (resent), "completed": (tally.completed), "failedAgain": (tally.failedAgain), "skipped": ($Select(total > resent: total - resent, 1: 0)), "interrupted": 0, "reason": (..Plain(reason))}
	If '..Ended(run, row, counts, 0) Quit ""
	Set sc = $$$OK
	Try {
		Set sc = ..Close(row.Ref, ..#DONE)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGCLOSE_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
	Do ..Entry(row, ..#DONE, counts)
	Quit ##class(OcuTalon.Fix.Executor).ResultOf(row, counts)
}

/// Ends the run through Executor.End (interrupted 1 for a marked run). 1 when this job wrote the end and saved it, and one Type 4 line (LOGSWEPT) says so. 0 when End refused the run (another job
/// ended it), and also when its save failed (one Type 3 warning, LOGSAVE): nothing else is done for the run then, and the next Tick takes it again.
ClassMethod Ended(run As OcuTalon.Data.FixRun, row As OcuTalon.Bridge.Data.ApprovalRequest, counts As %DynamicObject, interrupted As %Boolean) As %Boolean [ Private ]
{
	Set ref = run.ApprovalRef
	If '##class(OcuTalon.Fix.Executor).End(run, counts, interrupted, .sc) Quit 0
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGSAVE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit 0
	}
	$$$LOGINFO(..#LOGSWEPT_ref_": "_$Select(interrupted: ..#INTERRUPTED, 1: ..#DONE)_", "_counts.total_"/"_counts.resent_"/"_counts.completed_"/"_counts.failedAgain_"/"_counts.skipped_", "_(+counts.interrupted)_" cut off")
	Quit 1
}

/// Writes the Action entry of a run that Sweep ended (WriteAudit; the entry is Executor.ActionEntry's). A write that fails or throws logs one Type 3 warning (LOGAUDIT).
ClassMethod Entry(row As OcuTalon.Bridge.Data.ApprovalRequest, result As %String, counts As %DynamicObject) [ Private ]
{
	Set sc = $$$OK
	Try {
		Set sc = ..WriteAudit(##class(OcuTalon.Fix.Executor).ActionEntry(row, result, counts))
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGAUDIT_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The number of the request's targets (the row's FixTargets).
ClassMethod Targets(row As OcuTalon.Bridge.Data.ApprovalRequest) As %Integer [ Private ]
{
	Quit $Select(row.FixTargets = "": 0, 1: $Length(row.FixTargets, ","))
}

/// The reason as the run, the entry and the FixResult carry it: redacted, at most 1000 characters (as Executor.Finish makes it).
ClassMethod Plain(reason As %String) As %String [ Private ]
{
	Quit $Extract(##class(OcuTalon.Bridge.Redact).Text(reason), 1, 1000)
}

/// The ids of the FixRun rows with no EndedAt, as a list, in the order of the rows (a seam for the tests).
ClassMethod Unended() As %List
{
	Set ids = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.FixRun WHERE EndedAt IS NULL ORDER BY ID")
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The fix runs could not be read: "_rs.%Message))
	While rs.%Next() {
		Set ids = ids _ $ListBuild(rs.%GetData(1))
	}
	Quit ids
}

/// The start of the production as a UTC stamp, to the second (a seam for the tests): that of ^Ens.Runtime("StartTime"), which Ens.Director sets to UTC time "YYYY-MM-DD hh:mm:ss.fff" at
/// each StartProduction (a restart included); when that is unset or not a time, the start of the instance (now less $ZHOROLOG seconds); "" when that is not known either.
ClassMethod Started() As %String
{
	Set value = $Get($$$EnsRuntime("StartTime"))
	Set stamp = $Translate($Piece(value, ".", 1), " ", "T")_"Z"
	If (value '= "") && (##class(OcuTalon.Watch.Settle).Seconds(stamp) '= "") Quit stamp
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -($ZHorolog \ 1))
}

/// The outcome and the statuses of the run's copies (a seam for the tests): Executor.Read's.
ClassMethod Statuses(incident As OcuTalon.Data.Incident, run As OcuTalon.Data.FixRun, Output statuses As %DynamicObject) As %String
{
	Quit ##class(OcuTalon.Fix.Executor).Read(incident, run, .statuses)
}

/// Closes the request through Approval.FinishExecution with the result (a seam for the tests).
ClassMethod Close(ref As %String, result As %String) As %Status
{
	Quit ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, result)
}

/// The one audit write of the class: an entry of type Action, through the one writer of product code (a seam for the tests).
ClassMethod WriteAudit(data As %DynamicObject) As %Status
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
}

}
