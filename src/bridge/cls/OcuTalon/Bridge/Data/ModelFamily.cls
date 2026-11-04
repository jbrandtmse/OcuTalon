/// A model family's session-config keys (AD-7). Lane A.
Class OcuTalon.Bridge.Data.ModelFamily Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.ModelFamily";

/// The family; unique.
Property Family As %String(MAXLEN = 32);

/// The model id prefix that selects the family.
Property ModelPrefix As %String(MAXLEN = 128);

/// The session-config key that caps output.
Property CapKey As %String(MAXLEN = 128);

/// The session-config key that sets effort.
Property EffortKey As %String(MAXLEN = 128);

Index FamilyIndex On Family [ Unique ];

Storage Default
{
<Data name="ModelFamilyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Family</Value>
</Value>
<Value name="3">
<Value>ModelPrefix</Value>
</Value>
<Value name="4">
<Value>CapKey</Value>
</Value>
<Value name="5">
<Value>EffortKey</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.ModelFamilyD</DataLocation>
<DefaultData>ModelFamilyDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.ModelFamilyD</IdLocation>
<IndexLocation>^OcuTalonBP.ModelFamilyI</IndexLocation>
<StreamLocation>^OcuTalonBP.ModelFamilyS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
