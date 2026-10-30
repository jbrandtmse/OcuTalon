/// The bridge's purge (AD-27): the part of the daily OcuTalon purge task that deletes the bridge's own old records. Run(daysToKeep) is called through
/// OcuTalon.Install.Step.Retention with the day count of the task (a task property, AD-19).
///   - Decisions and usage: the Decision and Usage rows recorded before the cutoff, which is now moved back daysToKeep whole days
///     (Time.DaysCutoff). A row recorded at the cutoff stays;
///   - AI sessions: a session is deleted, with its context stream, when no conversation link has named it for a day. The links only move forward,
///     to a new session, so a session that is named by no link stays unnamed. The mark ^OcuTalonBP.Unlinked(sessionId) holds the UTC time of the
///     first run that found the session with no link, in the private database like ^OcuTalonBP.UsageCapped (Budget). A run deletes a session whose
///     mark is at least 86,400 s old and that is still unnamed, clears the mark of a session that a link names and of one that is gone, and marks
///     the others. The session rule does not depend on daysToKeep. It covers every AI session of the namespace; only the bridge's runner saves
///     sessions in OCUTALON (Adapter.Agent), and it points a link at a session right after it saves it, so a session that is saved and not yet named
///     is marked and then kept for a day.
/// The purge reads the links' SessionId values with one SELECT and compares them in ObjectScript; it takes no conversation lock and writes no link
/// (AD-6). It works in the current namespace only (AD-3), touches no audit entry (AD-17) and names no other OcuTalon package (AD-2). Each part runs
/// whatever an earlier part returned, and their errors are combined into one status.
Class OcuTalon.Bridge.Purge
{

/// A session whose mark is this many seconds old and that no link names is deleted: one day.
Parameter UNLINKEDSECONDS = 86400;

/// Deletes the decisions and usage rows recorded more than daysToKeep days before now, and the AI sessions that no link has named for a day.
/// daysToKeep must be a whole number of at least 1, and now (default the current time) a UTC time, YYYY-MM-DDThh:mm:ssZ: anything else is an
/// error status, and nothing is deleted or marked. A day count so large that the cutoff falls before the calendar deletes no row of the other
/// kinds, and the session rule still applies.
ClassMethod Run(daysToKeep As %Integer, now As %String = "") As %Status
{
	If now = "" Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set sc = ##class(OcuTalon.Bridge.Time).DaysCutoff(daysToKeep, "OcuTalon.Bridge.Purge.Run", .cutoff, now)
	If $$$ISERR(sc) Quit sc
	If cutoff '= "" {
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteBefore("OcuTalon_Bridge_Data.Decision", cutoff))
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteBefore("OcuTalon_Bridge_Data.Usage", cutoff))
	}
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..Sessions(now))
	Quit sc
}

/// Deletes the rows of the table (an SQL table name of this class's own data) whose RecordedAt is before the cutoff.
ClassMethod DeleteBefore(table As %String, cutoff As %String) As %Status
{
	Set sc = $$$OK
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_table_" WHERE RecordedAt < ?", cutoff)
		If result.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "Deleting the old rows of "_table_" failed: "_result.%Message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The session rule: marks, clears and deletes AI sessions as the class doc says, at the UTC time now.
ClassMethod Sessions(now As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set linkSql = "SELECT SessionId FROM OcuTalon_Bridge_Data.ConversationLink"
		Set links = ##class(%SQL.Statement).%ExecDirect(, linkSql)
		If links.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the conversation links failed: "_links.%Message))
		While links.%Next() {
			Set linkedId = links.%GetData(1)
			If linkedId '= "" Set linked(linkedId) = ""
		}
		If links.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the conversation links failed: "_links.%Message))
		Set sessions = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID FROM %AI_Agent.Session")
		If sessions.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the AI sessions failed: "_sessions.%Message))
		While sessions.%Next() {
			Set id = sessions.%GetData(1)
			Set exists(id) = ""
			If $Data(linked(id)) {
				Kill ^OcuTalonBP.Unlinked(id)
				Continue
			}
			Set due = ""
			If $Data(^OcuTalonBP.Unlinked(id)) Set due = ##class(OcuTalon.Bridge.Time).PlusSeconds(^OcuTalonBP.Unlinked(id), ..#UNLINKEDSECONDS)
			If due = "" {
				Set ^OcuTalonBP.Unlinked(id) = now
			} ElseIf due '] now {
				Set expired(id) = ""
			}
		}
		If sessions.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the AI sessions failed: "_sessions.%Message))
		Set id = ""
		For {
			Set id = $Order(expired(id))
			Quit:id=""
			Set deleted = ##class(%AI.Agent.Session).%DeleteId(id)
			If $$$ISOK(deleted) {
				Kill ^OcuTalonBP.Unlinked(id)
			} Else {
				Set sc = $SYSTEM.Status.AppendStatus(sc, deleted)
			}
		}
		Set id = ""
		For {
			Set id = $Order(^OcuTalonBP.Unlinked(id))
			Quit:id=""
			If '$Data(exists(id)) Kill ^OcuTalonBP.Unlinked(id)
		}
	} Catch exception {
		Set sc = $SYSTEM.Status.AppendStatus(sc, exception.AsStatus())
	}
	Quit sc
}

}
