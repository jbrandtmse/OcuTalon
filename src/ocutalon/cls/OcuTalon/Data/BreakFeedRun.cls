/// A Break the feed run, owned by Lane B (AD-33).
Class OcuTalon.Data.BreakFeedRun Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.BreakFeed";

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// sending or sent.
Property State As %String(MAXLEN = 32);

/// When the run started, UTC to the second.
Property StartedAt As %String(MAXLEN = 20);

Index SessionRefIndex On SessionRef;

/// Whole seconds from StartedAt to now (UTC times); a large value when either time is unreadable.
Method Age(now As %String) As %Integer
{
	Set start = ..ToSeconds(..StartedAt)
	Set end = ..ToSeconds(now)
	If (start = "") || (end = "") Quit 999999999
	Quit end - start
}

/// The distinct SessionRefs, as stored (case-sensitive), with a run started less than seconds before now, in the order of
/// their first run, as a list. The statement is prepared with
/// the privilege check, so it runs in the StatusMonitor job (the production holds %All, AD-24) and in tests; sc is an
/// error status, with an empty list, when the read failed.
ClassMethod RecentSessions(seconds As %Integer, now As %String = {##class(OcuTalon.Data.Time).NowUtc()}, Output sc As %Status) As %List
{
	Set sc = $SYSTEM.Status.OK()
	Set refs = ""
	Kill seen
	Set end = ..ToSeconds(now)
	If end = "" Quit ""
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT SessionRef FROM OcuTalon_Data.BreakFeedRun WHERE StartedAt > ? ORDER BY ID")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute(..FromSeconds(end - seconds))
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the recent runs failed: "_result.%Message)
			} Else {
				While result.%Next() {
					Set ref = result.%Get("SessionRef")
					If (ref '= "") && '$Data(seen(ref)) {
						Set seen(ref) = ""
						Set refs = refs_$ListBuild(ref)
					}
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit refs
}

/// Seconds since the horolog epoch for a UTC time YYYY-MM-DDThh:mm:ssZ, "" when it is not one.
ClassMethod ToSeconds(time As %String) As %Integer [ Private ]
{
	If $Get(time) '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Try {
		Set horolog = $ZDateTimeH($Translate($Extract(time, 1, 19), "T", " "), 3, 1)
		Set seconds = $Piece(horolog, ",", 1) * 86400 + $Piece(horolog, ",", 2)
	} Catch {
		Set seconds = ""
	}
	Quit seconds
}

/// The UTC time YYYY-MM-DDThh:mm:ssZ of seconds since the horolog epoch.
ClassMethod FromSeconds(seconds As %Integer) As %String [ Private ]
{
	Quit $Translate($ZDateTime((seconds \ 86400)_","_(seconds # 86400), 3, 1), " ", "T")_"Z"
}

Storage Default
{
<Data name="BreakFeedRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>State</Value>
</Value>
<Value name="4">
<Value>StartedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.BreakFeedD</DataLocation>
<DefaultData>BreakFeedRunDefaultData</DefaultData>
<IdLocation>^OcuTalonP.BreakFeedD</IdLocation>
<IndexLocation>^OcuTalonP.BreakFeedI</IndexLocation>
<StreamLocation>^OcuTalonP.BreakFeedS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
