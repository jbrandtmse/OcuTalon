/// The partner contacts of a production, for the delay notices of Fix.Kind.PartnerWarning (Stories 23.5 and 23.13; AD-16, AD-19). It reads two sources and has no write method, no
/// row, no global and no setting of its own; TABLE is the switch that shows Settings > Partner contacts (Core.SettingsOps PartnersShown reads it, exactly 1).
///   - The fixture: the XData block Contacts is a JSON array of {"id", "production", "name", "address"}, with ids that are positive whole numbers, and it names the demo's own
///     fictional partner under an example.com-style address, never a real company or person. It applies only to the production it names and only while demo mode is on
///     (Demo.Guide.DemoOn), and its contacts are simulated (Simulated gives 1 for that production): they are delivered to the Simulated mailbox and never mailed.
///   - The table: every other production reads the contacts that an admin set in Settings (Data.PartnerContact ForProduction, Lane B's reader: namespace and production both match),
///     de-duplicated by address (lower-cased, trimmed; the lowest id is kept, in id order). It is never read on the online demo (Watch.Reader OnlineDemo), where it gives none.
///   - For(production, namespace) gives the production's contacts as a dynamic array of {"id", "name", "address"}, in id order; [] for a production with none, for the fixture's
///     production with demo mode off and on the online demo for any other production.
///   - Named(production, id, namespace) gives the one contact of that source with that id, as a dynamic object, or "" for any other id.
///   - Simulated(production) is 1 when the fixture names the production, whatever the mode: the source follows the production, never the mode.
///   - Ids, Addresses and Names list a contact array's ids, addresses and names, comma-separated, in order.
/// Lane A.
Class OcuTalon.Fix.PartnerContacts [ Abstract ]
{

/// 1 shows Settings > Partner contacts (Story 24.2; Core.SettingsOps PartnersShown). Every other value hides it.
Parameter TABLE = 1;

/// The contacts: one JSON array. A change here is a change of the fixture.
XData Contacts [ MimeType = application/json ]
{
[
 {"id": 1, "production": "OcuTalon.Demo.Orders.Production", "name": "Orders Partner IT", "address": "it@orders-partner.example"}
]
}

/// 1 when the fixture names the production: its contacts are fictional and its notices go to the Simulated mailbox. 0 for any other production.
ClassMethod Simulated(production As %String) As %Boolean
{
	Set iterator = ..All().%GetIterator()
	While iterator.%GetNext(, .contact) {
		If contact.production = $Get(production) Return 1
	}
	Quit 0
}

/// The contacts of the production, in id order, as {"id", "name", "address"}: the fixture's while demo mode is on when the fixture names the production ([] with demo mode off),
/// else the table's for the namespace and the production, de-duplicated by address ([] on the online demo, without reading the table).
ClassMethod For(production As %String, namespace As %String = "") As %DynamicArray
{
	Set found = []
	If ..Simulated($Get(production)) {
		If '##class(OcuTalon.Demo.Guide).DemoOn() Quit found
		Set iterator = ..All().%GetIterator()
		While iterator.%GetNext(, .contact) {
			If contact.production '= $Get(production) Continue
			Do found.%Push({"id": (contact.id), "name": (contact.name), "address": (contact.address)})
		}
		Quit found
	}
	If ##class(OcuTalon.Watch.Reader).OnlineDemo() Quit found
	Kill seen
	Set iterator = ##class(OcuTalon.Data.PartnerContact).ForProduction($Get(namespace), $Get(production)).%GetIterator()
	While iterator.%GetNext(, .contact) {
		Set key = $ZConvert($ZStrip(contact.address, "<>W"), "L")
		If $Data(seen(key)) Continue
		Set seen(key) = ""
		Do found.%Push(contact)
	}
	Quit found
}

/// The contact of the production with the id, as {"id", "name", "address"}; "" when there is none (For decides the source).
ClassMethod Named(production As %String, id As %String, namespace As %String = "") As %DynamicObject
{
	Set contacts = ..For($Get(production), $Get(namespace))
	Set iterator = contacts.%GetIterator()
	While iterator.%GetNext(, .contact) {
		If ($Get(id) ? 1.N) && (contact.id = +id) Return contact
	}
	Quit ""
}

/// The ids of a contact array, comma-separated, in the array's order.
ClassMethod Ids(contacts As %DynamicArray) As %String
{
	Quit ..Joined(contacts, "id", ",")
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
