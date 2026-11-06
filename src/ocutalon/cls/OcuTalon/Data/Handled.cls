/// One row per tell-now notice that its session has marked as handled (AD-14, Got it; Lane B). The notice's Ref is its Decision's Ref
/// (a notice has none of its own, and each channel's Delivery row records it as DecisionRef). A row says that the session handled the
/// notice, when, and from which channel. The class is created by Story 33.2; its writer is Story 18.4's GotIt branch of SessionOps, and
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

/// When the notice was marked handled, UTC to the second, or "" when it is not marked (or the Ref is empty).
ClassMethod Marked(ref As %String) As %String
{
	If $Get(ref) = "" Quit ""
	Set row = ..RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.HandledAt, 1: "")
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
