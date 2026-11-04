/// A session's guide state (AD-1): the markers the server cannot derive from the session's rows, the run epoch and the
/// trace-opened flag. Lane B and Epic 4 own it (AD-33). The REST marker endpoint is the only caller of TraceOpened and
/// RunAgain; Demo.Guide derives everything else.
Class OcuTalon.Data.GuideState Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Guide";

/// Unique.
Property SessionRef As %String(MAXLEN = 22);

/// The session's run epoch.
Property RunEpoch As %Integer;

/// True once the session opened a trace link.
Property TraceOpened As %Boolean [ InitialExpression = 0 ];

/// When the current run epoch started, UTC to the second; empty for the first epoch.
Property RunStartedAt As %String(MAXLEN = 20);

Index SessionRefIndex On SessionRef [ Unique ];

/// The session's row, or "".
ClassMethod ForSession(sessionRef As %String) As OcuTalon.Data.GuideState
{
	If $Get(sessionRef) = "" Quit ""
	Quit ..SessionRefIndexOpen(sessionRef)
}

/// Takes the session's guide lock, ^OcuTalon.Demo.Guide(sessionRef), for up to wait seconds; 1 when it is held. The lock is
/// incremental: a process that holds it takes it again, and every Lock is paired with an Unlock.
ClassMethod Lock(sessionRef As %String, wait As %Integer = 5) As %Boolean
{
	Lock +^OcuTalon.Demo.Guide(sessionRef):wait
	Quit $Test
}

/// Releases one Lock of the session's guide lock.
ClassMethod Unlock(sessionRef As %String)
{
	Lock -^OcuTalon.Demo.Guide(sessionRef)
}

/// The "trace opened" marker: sets TraceOpened, creating the row (epoch 1) when the session has none. The REST marker
/// endpoint is the only caller (AD-1).
ClassMethod TraceOpened(sessionRef As %String) As %Status
{
	If '..Lock(sessionRef) Quit $SYSTEM.Status.Error(5001, "The guide state is busy")
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set row = ..ForSession(sessionRef)
		If '$IsObject(row) {
			Set row = ..%New()
			Set row.SessionRef = sessionRef
			Set row.RunEpoch = 1
		}
		Set row.TraceOpened = 1
		Set sc = row.%Save()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ..Unlock(sessionRef)
	Quit sc
}

/// The "run again" marker: adds 1 to RunEpoch (2 when the session has no row), sets RunStartedAt to now and clears
/// TraceOpened. The REST marker endpoint is the only caller (AD-1).
ClassMethod RunAgain(sessionRef As %String) As %Status
{
	If '..Lock(sessionRef) Quit $SYSTEM.Status.Error(5001, "The guide state is busy")
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set row = ..ForSession(sessionRef)
		If '$IsObject(row) {
			Set row = ..%New()
			Set row.SessionRef = sessionRef
			Set row.RunEpoch = 1
		}
		Set row.RunEpoch = row.RunEpoch + 1
		Set row.RunStartedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set row.TraceOpened = 0
		Set sc = row.%Save()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ..Unlock(sessionRef)
	Quit sc
}

Storage Default
{
<Data name="GuideStateDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>RunEpoch</Value>
</Value>
<Value name="4">
<Value>TraceOpened</Value>
</Value>
<Value name="5">
<Value>RunStartedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.GuideD</DataLocation>
<DefaultData>GuideStateDefaultData</DefaultData>
<IdLocation>^OcuTalonP.GuideD</IdLocation>
<IndexLocation>^OcuTalonP.GuideI</IndexLocation>
<StreamLocation>^OcuTalonP.GuideS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
