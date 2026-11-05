/// One run of one background check (AD-18, AD-28, AD-33): the coverage storage of the daily digest. Lane A. The only writer is OcuTalon.Checks,
/// one INSERT beside the BackgroundCheck update for each run (Story 17.5); OcuTalon.Checks.Coverage.Build reads the rows of a window to say
/// which checks ran throughout it. The rows are purged with the digest area's rows (AD-27). Row ids never leave the server.
Class OcuTalon.Digest.Data.CheckRun Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.CheckRun";

/// The Ref of the background check that ran (AD-14). Refs are case-sensitive.
Property CheckRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the session that owns the check.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// When the run finished, UTC to the second.
Property RanAt As %String(MAXLEN = 20);

/// The result of the run: passed, failed or not_checked.
Property Result As %String(MAXLEN = 32);

/// For a not_checked run, why: error, timeout or unreachable. Empty otherwise.
Property Reason As %String(MAXLEN = 32);

/// The finding of a failed run, or the short phrase of a not-checked one, written in code.
Property Finding As %String(MAXLEN = 1000);

/// The id of the run's header row, when it has one.
Property HeaderId As %Integer;

Index CheckRefRanAtIndex On (CheckRef, RanAt);

Index SessionRefRanAtIndex On (SessionRef, RanAt);

Storage Default
{
<Data name="CheckRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>CheckRef</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>RanAt</Value>
</Value>
<Value name="5">
<Value>Result</Value>
</Value>
<Value name="6">
<Value>Reason</Value>
</Value>
<Value name="7">
<Value>Finding</Value>
</Value>
<Value name="8">
<Value>HeaderId</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.CheckRunD</DataLocation>
<DefaultData>CheckRunDefaultData</DefaultData>
<IdLocation>^OcuTalonP.CheckRunD</IdLocation>
<IndexLocation>^OcuTalonP.CheckRunI</IndexLocation>
<StreamLocation>^OcuTalonP.CheckRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
