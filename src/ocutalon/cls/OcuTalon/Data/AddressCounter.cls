/// A per-address sign-in counter (AD-1). Lane B.
Class OcuTalon.Data.AddressCounter Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.AddrCount";

/// The hash of the client address, never the address.
Property AddressHash As %String(MAXLEN = 128);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index AddressHashIndex On AddressHash;

Storage Default
{
<Data name="AddressCounterDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>AddressHash</Value>
</Value>
<Value name="3">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.AddrCountD</DataLocation>
<DefaultData>AddressCounterDefaultData</DefaultData>
<IdLocation>^OcuTalonP.AddrCountD</IdLocation>
<IndexLocation>^OcuTalonP.AddrCountI</IndexLocation>
<StreamLocation>^OcuTalonP.AddrCountS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
