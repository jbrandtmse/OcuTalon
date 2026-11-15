/// A partner contact: a named person at a partner, with one email address, and the productions that the contact concerns (AD-13, AD-19, AD-33; Story 24.2). Lane B.
/// The only writer is OcuTalon.Core.SettingsOps (its contacts saver), which also writes the one Settings audit entry of each change before the row; the readers are
/// SettingsOps (List, for the Settings page) and, for the partner warnings, ForProduction. Every read is object access (an index open or $Order over the class's own
/// global), never SQL. A contact's name and address are stored only here, so that deleting the row deletes them: no command, result, log line, trace, notice or audit
/// entry holds them. It is not Lane A's demo fixture OcuTalon.Fix.PartnerContacts, whose For returns the same shape.
///   - Ref is the public reference, 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(); it is unique and case-sensitive.
///   - Productions is a JSON array of {"namespace", "production"}: each production that the contact concerns. A contact concerns a production only when one entry
///     names both its namespace and its production.
///   - CreatedAt and UpdatedAt are UTC to the second.
///   - ForProduction(namespace, production) gives the contacts of the production as a dynamic array of {"id", "name", "address"}, id the row ID, in ID order.
///   - List() gives every contact as {"ref", "name", "email", "productions"} in the order of the upper-cased name, then the Ref. RefOpen(ref) opens one row.
Class OcuTalon.Data.PartnerContact Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.PartnerContact";

/// The public reference, 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The contact's name, 1 to 128 characters, trimmed.
Property Name As %String(MAXLEN = 128);

/// The contact's email address, at most 254 characters.
Property Email As %String(MAXLEN = 254);

/// The productions that the contact concerns: a JSON array of {"namespace", "production"}.
Property Productions As %String(MAXLEN = 4000);

/// When the row was made, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

/// When the row was last changed, UTC to the second.
Property UpdatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

/// The row with the Ref, or "" for a Ref that no row has (an index open, no SQL).
ClassMethod RefOpen(ref As %String) As OcuTalon.Data.PartnerContact
{
	Set ref = $Get(ref)
	If ref = "" Quit ""
	Set row = ..RefIndexOpen(ref)
	Quit $Select($IsObject(row): row, 1: "")
}

/// The Productions of the row as a dynamic array of {"namespace", "production"}, or "" when the stored text is not such an array (a row that SettingsOps wrote
/// always is).
ClassMethod ProductionsOf(text As %String) As %DynamicArray
{
	Set list = ""
	Try {
		Set parsed = ##class(%DynamicAbstractObject).%FromJSON($Get(text))
		If $IsObject(parsed) && parsed.%IsA("%Library.DynamicArray") Set list = parsed
	} Catch {
		Set list = ""
	}
	Quit list
}

/// 1 when one entry of the productions array names the namespace and the production, both exactly.
ClassMethod Concerns(list As %DynamicArray, namespace As %String, production As %String) As %Boolean [ Private ]
{
	If '$IsObject(list) Quit 0
	Set found = 0
	Set iterator = list.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry) && entry.%IsA("%Library.DynamicObject") && (entry.%Get("namespace") = namespace) && (entry.%Get("production") = production) {
			Set found = 1
			Quit
		}
	}
	Quit found
}

/// The contacts of the production in the namespace, as a dynamic array of {"id" (the row ID), "name", "address"}, in ID order. A contact is in it only when one entry
/// of its productions names both the namespace and the production. [] when none does. It reads the rows at the time of the call, so an edited or removed contact is
/// gone at once.
ClassMethod ForProduction(namespace As %String, production As %String) As %DynamicArray
{
	Set found = []
	Set namespace = $Get(namespace), production = $Get(production)
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.PartnerContactD(id))
		Quit:id=""
		Set row = ..%OpenId(id)
		If '$IsObject(row) Continue
		If '..Concerns(..ProductionsOf(row.Productions), namespace, production) Continue
		Do found.%Push({"id": (+id), "name": (row.Name), "address": (row.Email)})
	}
	Quit found
}

/// Every contact as a dynamic array of {"ref", "name", "email", "productions"}, ordered by the upper-cased name, then the Ref. productions is the array of
/// {"namespace", "production"} (an unreadable stored text gives []).
ClassMethod List() As %DynamicArray
{
	Set list = []
	Kill order
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.PartnerContactD(id))
		Quit:id=""
		Set row = ..%OpenId(id)
		If $IsObject(row) Set order($ZConvert(row.Name, "U"), row.Ref) = id
	}
	Set key = ""
	For {
		Set key = $Order(order(key))
		Quit:key=""
		Set ref = ""
		For {
			Set ref = $Order(order(key, ref), 1, id)
			Quit:ref=""
			Set row = ..%OpenId(id)
			Set productions = ..ProductionsOf(row.Productions)
			If '$IsObject(productions) Set productions = []
			Do list.%Push({"ref": (row.Ref), "name": (row.Name), "email": (row.Email), "productions": (productions)})
		}
	}
	Quit list
}

Storage Default
{
<Data name="PartnerContactDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Email</Value>
</Value>
<Value name="5">
<Value>Productions</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
<Value name="7">
<Value>UpdatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.PartnerContactD</DataLocation>
<DefaultData>PartnerContactDefaultData</DefaultData>
<IdLocation>^OcuTalonP.PartnerContactD</IdLocation>
<IndexLocation>^OcuTalonP.PartnerContactI</IndexLocation>
<StreamLocation>^OcuTalonP.PartnerContactS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
