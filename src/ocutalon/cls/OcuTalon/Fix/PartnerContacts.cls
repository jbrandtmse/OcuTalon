/// The partner contacts of a production, for the delay notices of Fix.Kind.PartnerWarning (Story 23.5; AD-16). A read-only fixture in code: the XData block Contacts is a
/// JSON array of {"id", "production", "name", "address"}, with ids that are positive whole numbers, and it names the demo's own fictional partner under an
/// example.com-style address, never a real company or person. It is demo-only: For gives a production's contacts only while demo mode is on (Demo.Guide.DemoOn), else none, so
/// that an own install with no contact table drafts no notice. The class has no write method, no row, no global and no setting.
///   - For(production) gives the production's contacts as a dynamic array of {"id", "name", "address"}, in id order; [] with demo mode off or for a production with none.
///   - Named(production, id) gives the one contact of that production with that id, as a dynamic object, or "" for any other id, a production with none, or demo mode off.
///   - Addresses and Names list a contact array's addresses and names, comma-separated, in order.
/// Lane A.
Class OcuTalon.Fix.PartnerContacts [ Abstract ]
{

/// The contacts: one JSON array. A change here is a change of the fixture.
XData Contacts [ MimeType = application/json ]
{
[
 {"id": 1, "production": "OcuTalon.Demo.Orders.Production", "name": "Orders Partner IT", "address": "it@orders-partner.example"}
]
}

/// The contacts of the production, in id order, as {"id", "name", "address"}; [] when demo mode is off or the production has none.
ClassMethod For(production As %String) As %DynamicArray
{
	Set found = []
	If '##class(OcuTalon.Demo.Guide).DemoOn() Quit found
	Set all = ..All()
	Set iterator = all.%GetIterator()
	While iterator.%GetNext(, .contact) {
		If contact.production '= $Get(production) Continue
		Do found.%Push({"id": (contact.id), "name": (contact.name), "address": (contact.address)})
	}
	Quit found
}

/// The contact of the production with the id (demo mode on), as {"id", "name", "address"}; "" when there is none.
ClassMethod Named(production As %String, id As %String) As %DynamicObject
{
	Set contacts = ..For($Get(production))
	Set iterator = contacts.%GetIterator()
	While iterator.%GetNext(, .contact) {
		If ($Get(id) ? 1.N) && (contact.id = +id) Return contact
	}
	Quit ""
}

/// The addresses of a contact array, comma-separated, in the array's order.
ClassMethod Addresses(contacts As %DynamicArray) As %String
{
	Quit ..Joined(contacts, "address", ",")
}

/// The names of a contact array, comma-separated, in the array's order.
ClassMethod Names(contacts As %DynamicArray) As %String
{
	Quit ..Joined(contacts, "name", ",")
}

/// The field of each contact of the array, joined with the separator.
ClassMethod Joined(contacts As %DynamicArray, field As %String, separator As %String) As %String [ Private ]
{
	Set text = ""
	Set iterator = contacts.%GetIterator()
	While iterator.%GetNext(, .contact) {
		Set text = text_$Select(text = "": "", 1: separator)_contact.%Get(field)
	}
	Quit text
}

/// The whole fixture in id order, whatever the production and demo mode.
ClassMethod All() As %DynamicArray [ Private ]
{
	Set stream = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Contacts").Data
	Set contacts = ##class(%DynamicAbstractObject).%FromJSON(stream)
	Set ordered = []
	Kill byId
	Set iterator = contacts.%GetIterator()
	While iterator.%GetNext(, .contact) {
		Set byId(contact.id) = contact
	}
	Set id = ""
	For {
		Set id = $Order(byId(id))
		Quit:id=""
		Do ordered.%Push(byId(id))
	}
	Quit ordered
}

}
