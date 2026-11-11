Include %cspBuild

/// The host's part of the purge (AD-27; Lane B's Data area): the Turn, Delivery and Session rows that are old enough, and the rows that go with a session.
/// The Retention area calls Run(daysToKeep, now) just before the bridge's purge with the same now, so both parts use the same cutoff
/// (Bridge.Time.DaysCutoff) and a turn that is kept never names a decision that the bridge's purge removed.
///   - Turns: the rows created before the cutoff go, whatever their state. A turn created at the cutoff stays;
///   - Deliveries: the rows recorded before the cutoff go, Telegram rows with their kept text included;
///   - Sessions: a Session row goes only when it was created before the cutoff, has no Turn, Delivery or Decision at or after the cutoff, holds no
///     memory and no document, and is not current: never by age alone. Current means any one of: a live CSP session holding its Ref (signed in,
///     OcuTalon.Data.Ownership SESSIONKEY), a Telegram pairing, an approval request that is pending, approved or executing, a background check (a watch),
///     a webhook that it owns (Data.Webhook; a webhook has no removal, so its session is kept for good), or a pending reminder. The checks run again for each session right before it is deleted;
///   - With a session go its GuideState, SimMessage, BreakFeedRun and finished (fired or cancelled) Reminder rows, and its conversation links
///     (OcuTalon.Bridge.Purge.DropLinks), so that the bridge's purge frees the AI sessions they named. When one of these deletes fails, the Session row
///     stays and a later run retries it. Memories and documents are never deleted by this class: a session that holds one is kept.
/// The purge deletes only from the tables OcuTalon_Data.Turn, Delivery, GuideState, SimMessage, Reminder, BreakFeedRun and Session, and reaches the
/// bridge's conversation links only through DropLinks. It reads the bridge's decision and approval tables, and it touches no IRIS system record, no AI
/// session and no message (AD-17). Each part runs whatever an earlier part returned, and the errors are combined into one status.
Class OcuTalon.Data.Purge
{

/// Deletes the turns created, and the deliveries recorded, more than daysToKeep days before now, and the sessions that qualify as the class doc says,
/// with their rows.
/// daysToKeep must be a whole number of at least 1, and now (default the current time) a UTC time, YYYY-MM-DDThh:mm:ssZ: anything else is an error
/// status, and nothing is deleted. A day count so large that the cutoff falls before the calendar deletes nothing. store is the CSP session store (by
/// default ^%cspSession; a test passes a private global).
ClassMethod Run(daysToKeep As %Integer, now As %String = "", store As %String = "^%cspSession") As %Status
{
	If now = "" Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set sc = ##class(OcuTalon.Bridge.Time).DaysCutoff(daysToKeep, "OcuTalon.Data.Purge.Run", .cutoff, now)
	If $$$ISERR(sc) || (cutoff = "") Quit sc
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteTurns(cutoff))
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteDeliveries(cutoff))
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteSessions(cutoff, store))
	Quit sc
}

/// Deletes the turns created before the cutoff.
ClassMethod DeleteTurns(cutoff As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Turn WHERE CreatedAt < ?", cutoff)
		If result.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "Deleting the old turns failed: "_result.%Message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Deletes the deliveries recorded before the cutoff.
ClassMethod DeleteDeliveries(cutoff As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE RecordedAt < ?", cutoff)
		If result.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "Deleting the old deliveries failed: "_result.%Message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Selects the sessions created before the cutoff, then checks each one again and deletes it when it is neither active nor current.
ClassMethod DeleteSessions(cutoff As %String, store As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, %EXACT(Ref) AS Ref FROM OcuTalon_Data.Session WHERE CreatedAt < ?", cutoff)
		If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the old sessions failed: "_result.%Message))
		While result.%Next() {
			Set candidates(result.%Get("ID")) = result.%Get("Ref")
		}
		If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the old sessions failed: "_result.%Message))
		Set id = ""
		For {
			Set id = $Order(candidates(id), 1, ref)
			Quit:id=""
			If ..Keeps(ref, cutoff, store, .check) {
				Set sc = $SYSTEM.Status.AppendStatus(sc, check)
				Continue
			}
			Set dropped = ..DeleteOwnedRows(ref)
			If $$$ISERR(dropped) {
				Set sc = $SYSTEM.Status.AppendStatus(sc, dropped)
				Continue
			}
			Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Data.Session).%DeleteId(id))
		}
	} Catch exception {
		Set sc = $SYSTEM.Status.AppendStatus(sc, exception.AsStatus())
	}
	Quit sc
}

/// Deletes the rows that only the session owns: its GuideState, SimMessage and BreakFeedRun rows, its finished Reminder rows, and its conversation
/// links. The first failure stops the rest and is returned, so the caller keeps the Session row.
ClassMethod DeleteOwnedRows(ref As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set sql(1) = "DELETE FROM OcuTalon_Data.GuideState WHERE SessionRef = ?"
		Set sql(2) = "DELETE FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?"
		Set sql(3) = "DELETE FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ?"
		Set sql(4) = "DELETE FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND State IN ('fired', 'cancelled')"
		Set n = ""
		For {
			Set n = $Order(sql(n))
			Quit:n=""
			Set result = ##class(%SQL.Statement).%ExecDirect(, sql(n), ref)
			If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Deleting the rows of session "_ref_" failed: "_result.%Message))
		}
		$$$ThrowOnError(##class(OcuTalon.Bridge.Purge).DropLinks(ref))
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// 1 when the session must be kept: it has a Turn, Delivery or Decision at or after the cutoff, holds a memory or a document, or it is current. A read that fails keeps the session
/// and returns its error in check (OK otherwise).
ClassMethod Keeps(ref As %String, cutoff As %String, store As %String, Output check As %Status) As %Boolean [ Private ]
{
	Set check = $$$OK
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND CreatedAt >= ?", .check, ref, cutoff) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND RecordedAt >= ?", .check, ref, cutoff) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND RecordedAt >= ?", .check, ref, cutoff) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Memory WHERE SessionRef = ?", .check, ref) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Document WHERE OwnerRef = ?", .check, ref) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Pairing WHERE SessionRef = ?", .check, ref) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Webhook WHERE SessionRef = ?", .check, ref) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ? AND State IN ('pending', 'approved', 'executing')", .check, ref) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", .check, ref) Quit 1
	If ..Found("SELECT TOP 1 1 FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND State = 'pending'", .check, ref) Quit 1
	If ..Signed(ref, store) Quit 1
	Quit 0
}

/// 1 when a live CSP session in the store holds the ref: an entry from subscript 0 onward (the nodes -2, -1 and 0 are the store's own) whose stored
/// timeout (the list position sesOldTimeout, an absolute time in seconds) is ahead of now and whose data holds the ref under Ownership's SESSIONKEY.
/// The reader takes no session and writes nothing.
ClassMethod Signed(ref As %String, store As %String) As %Boolean [ Private ]
{
	Set stamp = $ZTimeStamp
	Set now = ($Piece(stamp, ",") * 86400 + $Piece(stamp, ",", 2)) \ 1
	Set key = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	Set id = 0
	For {
		Set id = $Order(@store@(id))
		If id = "" Quit
		If $ListGet($Get(@store@(id)), $$$sesOldTimeout) > now, $Get(@store@(id, 0, key)) = ref Quit
	}
	Quit id '= ""
}

/// 1 when the query returns a row. An error is returned in check and counts as found, so that a failed read never deletes a session.
ClassMethod Found(sql As %String, ByRef check As %Status, args... As %String) As %Boolean [ Private ]
{
	Set found = 1
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, sql, args...)
		If result.%SQLCODE < 0 {
			Set check = $SYSTEM.Status.AppendStatus(check, $SYSTEM.Status.Error(5001, "Checking a session before its purge failed: "_result.%Message))
		} Else {
			Set found = +result.%Next()
			If result.%SQLCODE < 0 {
				Set found = 1
				Set check = $SYSTEM.Status.AppendStatus(check, $SYSTEM.Status.Error(5001, "Checking a session before its purge failed: "_result.%Message))
			}
		}
	} Catch exception {
		Set check = $SYSTEM.Status.AppendStatus(check, exception.AsStatus())
	}
	Quit found
}

}
