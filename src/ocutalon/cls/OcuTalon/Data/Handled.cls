/// One row per tell-now notice that its session has marked as handled (AD-14, Got it; Lane B). The notice's Ref is its Decision's Ref
/// (a notice has none of its own, and each channel's Delivery row records it as DecisionRef). A row says that the session handled the
/// notice, when, and from which channel. The class is created by Story 33.2; its writer is the GotIt branch of SessionOps (Story 12.12;
/// Story 18.4 adds the web chat's and the Simulated phone's controls), SessionOps.End deletes a session's rows through DropSession, and
/// Digest reads it through Marked.
Class OcuTalon.Data.Handled Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Handled";

/// The notice's Ref; unique. Compared exactly.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The session that marked the notice. Compared exactly.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// When the notice was marked, UTC to the second.
Property HandledAt As %String(MAXLEN = 20);

/// The channel the press came from: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

Index RefIndex On Ref [ Unique ];

/// The status code of a %DeleteId whose row is already gone ($$$DeleteObjectNotFound).
Parameter NOTFOUND [ Final ] = 5810;

/// When the notice was marked handled, UTC to the second, or "" when it is not marked (or the Ref is empty).
ClassMethod Marked(ref As %String) As %String
{
	If $Get(ref) = "" Quit ""
	Set row = ..RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.HandledAt, 1: "")
}

/// Deletes every row of the session (its sign-out; AD-4) and no other session's. An empty sessionRef is OK, and a row that is already gone is
/// not an error. Returns OK when none is left, else the first error.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	If $Get(sessionRef) = "" Quit $$$OK
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Handled WHERE SessionRef = ?", sessionRef)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Set count = 0
	While result.%Next() {
		Set ids($Increment(count)) = result.%GetData(1)
	}
	Set sc = $$$OK
	Set n = ""
	For {
		Set n = $Order(ids(n), 1, id)
		Quit:n=""
		Set one = ..%DeleteId(id)
		If $$$ISERR(one) && '$SYSTEM.Status.Equals(one, ..#NOTFOUND) && $$$ISOK(sc) Set sc = one
	}
	Quit sc
}

Storage Default
{
<Data name="HandledDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>HandledAt</Value>
</Value>
<Value name="5">
<Value>Channel</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.HandledD</DataLocation>
<DefaultData>HandledDefaultData</DefaultData>
<IdLocation>^OcuTalonP.HandledD</IdLocation>
<IndexLocation>^OcuTalonP.HandledI</IndexLocation>
<StreamLocation>^OcuTalonP.HandledS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
