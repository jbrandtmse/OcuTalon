/// The fix kind that sends the partner a delay notice about an incident (AD-16; Story 23.5). The user asks for it in the chat (propose_fix, ASKED 1) with no parameter, and the
/// diagnosis never names it (DIAGNOSED 0). Its text is drafted by the model (DRAFTED 1): IncidentManager has Decide write it from Facts, and only then asks for the dry run with
/// the drafted parameters {"text", "to"}. A request of this kind never moves the incident's state (MOVES 0), and it needs no IRIS privilege (RESOURCES empty): it changes nothing
/// in the production, and the send stays inside OcuTalon's own production, to the Simulated mailbox, never to a real inbox (Fix.Executor.Deliver).
///   - The targets are the ids of the production's partner contacts (TARGETTYPE contact), in ascending order; Fix.PartnerContacts holds them, demo mode only. The parameter
///     text is the notice, one line of at most NOTICEMAX characters (Normalise leaves it as it is), and to is the comma-separated addresses of the recipients, exactly the
///     production's contacts' in id order.
///   - Facts is the code-built input of the draft: the partner names, the production, the failed items, the count with its item noun, the first and last failure and the stored
///     plain cause. It holds no message body, sample error, setting value or evidence.
///   - DryRun refuses a production with no contact (NOCONTACTS) and a to that is not the contacts' addresses; its answer is {"notice", "recipients": [{"name", "address"}],
///     "simulated": 1}. Ready is 0 with NOTSETUP when demo mode is off, so that an approved notice is kept as a draft and says so.
///   - Recheck and Execute read each target against the fixture again: it passes only if the id still is a contact of the production and has the address at its position in to;
///     else it is skipped with a plain reason (RECHECK naming the contact, or NOSTART for an id the fixture does not name). Execute sends nothing: its result is {"deliveries": [{"id", "name", "address"}], "skipped": [{"id", "reason"}]},
///     and the executor delivers the approved text from the row. Lane A.
Class OcuTalon.Fix.Kind.PartnerWarning Extends OcuTalon.Fix.Kind
{

Parameter NAME = "partner_warning";

Parameter PARAMETERS = "text,to";

Parameter RESOURCES;

Parameter TARGETTYPE = "contact";

Parameter DIAGNOSED = 0;

Parameter ASKED = 1;

Parameter DRAFTED = 1;

Parameter MOVES = 0;

/// The most characters of the notice.
Parameter NOTICEMAX = 1000;

/// The instruction that the draft's turn is given (agent text, never shown to a user).
Parameter SYSTEMNOTE = "Write a short delay notice to the partner named below about the failures described below. Use only these facts. Write one plain paragraph of two to four sentences, at most 500 characters, with no greeting line, no signature, no placeholders, no message contents and no setting values, and don't promise when it will be fixed.";

Parameter NOTSETUP = "email delivery isn't set up yet";

Parameter NOCONTACTS = "No partner contacts are set up for {production}, so no delay notice was drafted";

Parameter NOITEM = "A delay notice takes no item or address: its recipients are the partner contacts set up for {production}";

Parameter ALLOWANCE = "The online demo allows 20 simulated emails an hour, and this session has used them for now, so no delay notice was drafted";

/// The reason of a recipient that is no longer a contact: {name} and {production} are filled in.
Parameter RECHECK = "{name} is no longer a partner contact of {production}";

Parameter NOSTART = "OcuTalon couldn't deliver the delay notice";

/// The reason of a run that failed before anything was sent (the executor's NOREAD for this kind): the same words as NOSTART.
Parameter NOREAD = "OcuTalon couldn't deliver the delay notice";

/// The input of the draft, built from the incident's rows and the fixture only (see the class description): one line each for the partner, the production, the failed items,
/// the failures, the first and the last failure and, when the incident has one, the cause.
ClassMethod Facts(incident As OcuTalon.Data.Incident) As %String
{
	Set online = ##class(OcuTalon.Watch.Reader).OnlineDemo()
	Set noun = ##class(OcuTalon.Watch.Notice).Noun(incident)
	Set items = ""
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	For i = 1:1:groups.Count() {
		Set name = groups.GetAt(i).ItemName
		If '$ListFind($ListFromString(items, ", "), name) Set items = items_$Select(items = "": "", 1: ", ")_name
	}
	Set text = "Partner: "_##class(OcuTalon.Fix.PartnerContacts).Names(##class(OcuTalon.Fix.PartnerContacts).For(incident.Production))
	Set text = text_$Char(10)_"Production: "_..ProductionName(incident)_" ("_incident.Production_")"
	Set text = text_$Char(10)_"Failed item: "_items
	Set text = text_$Char(10)_"Failures: "_+incident.Count_" "_$Select(+incident.Count = 1: noun.one, 1: noun.other)
	Set text = text_$Char(10)_"First failure: "_##class(OcuTalon.Tools.CommandCall).TimeLabel(incident.FirstAt, online)
	Set text = text_$Char(10)_"Last failure: "_##class(OcuTalon.Tools.CommandCall).TimeLabel(incident.LastAt, online)
	Set cause = ..Normalise(incident.Cause)
	If cause '= "" Set text = text_$Char(10)_"Cause: "_cause
	Quit text
}

/// The text as one line: each run of white space (line breaks included) is one space, the control characters, the invisible format characters and the bidirectional controls go
/// (the set that Msg.Catalog drops from a slot), and the ends are trimmed.
ClassMethod Normalise(text As %String) As %String
{
	Set text = $Translate($Get(text), $Char(9, 10, 11, 12, 13, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288), $Justify("", 24))
	Set text = $Translate(text, $Char(1564, 6158, 8203, 8206, 8207, 8234, 8235, 8236, 8237, 8238, 8288, 8289, 8290, 8291, 8292, 8294, 8295, 8296, 8297, 65279, 65529, 65530, 65531))
	Set text = $ZStrip(text, "*C")
	Quit $ZStrip($ZStrip(text, "<>W"), "=W")
}

/// The base's schema check, then: text is one line (Normalise leaves it as it is) of at most NOTICEMAX characters, and to is a comma-separated list of addresses. Whether the
/// addresses are the production's contacts' is the dry run's and the re-check's.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Set sc = ##super(parameters, fields)
	If $$$ISERR(sc) Quit sc
	Set text = parameters.%Get("text")
	If (text '= ..Normalise(text)) || ($Length(text) > ..#NOTICEMAX) {
		Quit $$$ERROR($$$GeneralError, "The parameter 'text' of "_..#NAME_" is not one line of at most "_..#NOTICEMAX_" characters")
	}
	If '..AddressList(parameters.%Get("to")) Quit $$$ERROR($$$GeneralError, "The parameter 'to' of "_..#NAME_" is not a comma-separated list of addresses")
	Quit $$$OK
}

/// 1 when every piece of the comma-separated list is an address: no white space, angle bracket or comma, one @ and a dot in the domain.
ClassMethod AddressList(to As %String) As %Boolean [ Private ]
{
	For i = 1:1:$Length(to, ",") {
		If '$Match($Piece(to, ",", i), "^[^\s@,<>]+@[^\s@,<>]+\.[^\s@,<>]+$") Return 0
	}
	Quit 1
}

/// The ids of the production's contacts as the targets, and the dry run {"notice", "recipients", "simulated"} (see the class description). An error status that says why when
/// the parameters don't pass CheckParameters, the production has no contact (NOCONTACTS) or to is not exactly the contacts' addresses in id order.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set contacts = ##class(OcuTalon.Fix.PartnerContacts).For(incident.Production)
	If contacts.%Size() = 0 Quit $$$ERROR($$$GeneralError, ..Reason(..#NOCONTACTS, incident))
	If parameters.%Get("to") '= ##class(OcuTalon.Fix.PartnerContacts).Addresses(contacts) {
		Quit $$$ERROR($$$GeneralError, "The recipients of the notice are not the partner contacts set up for "_..ProductionName(incident))
	}
	Set recipients = []
	Set iterator = contacts.%GetIterator()
	While iterator.%GetNext(, .contact) {
		Set targets = targets_$Select(targets = "": "", 1: ",")_contact.id
		Do recipients.%Push({"name": (contact.name), "address": (contact.address)})
	}
	Set dryRun = {"notice": (parameters.%Get("text")), "recipients": (recipients), "simulated": 1}
	Quit $$$OK
}

/// The reason with {production} filled in: the production's display name.
ClassMethod Reason(template As %String, incident As OcuTalon.Data.Incident) As %String
{
	Quit $Replace(template, "{production}", ..ProductionName(incident))
}

/// 0 with the reason NOTSETUP when demo mode is off: the only contacts there are are the demo's simulated ones, and nothing is delivered without them.
ClassMethod Ready(incident As OcuTalon.Data.Incident, Output reason As %String) As %Boolean
{
	Set reason = ""
	If ##class(OcuTalon.Demo.Guide).DemoOn() Quit 1
	Set reason = ..#NOTSETUP
	Quit 0
}

/// Re-checks the contacts of an approved request before anything is sent (see the class description): passed holds the ids that pass, comma-separated and ascending, skipped
/// holds {"id", "reason"} for the others. It changes nothing.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Set sc = ..Plan(incident, parameters, targets, .deliveries, .skipped)
	If $$$ISERR(sc) Quit sc
	Set iterator = deliveries.%GetIterator()
	While iterator.%GetNext(, .delivery) {
		Set passed = passed_$Select(passed = "": "", 1: ",")_delivery.id
	}
	Quit $$$OK
}

/// Gives the deliveries of the targets that still pass the re-check, and sends nothing (see the class description). result is {"deliveries", "skipped"}.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = {"deliveries": [], "skipped": []}
	Set sc = ..Plan(incident, parameters, targets, .deliveries, .skipped)
	If $$$ISERR(sc) Quit sc
	Set result.deliveries = deliveries
	Set result.skipped = skipped
	Quit $$$OK
}

/// The test of Recheck and Execute: deliveries holds {"id", "name", "address"} for each target that is still a contact of the production with the address at its position in
/// to, skipped holds {"id", "reason"} for each other target: RECHECK with the contact's name for a contact whose address is not the one at its position, NOSTART for an id that the
/// fixture does not name (no name is known for it). Parameters that don't pass CheckParameters skip every target with NOSTART. It changes nothing.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output deliveries As %DynamicArray, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Set deliveries = []
	Set skipped = []
	Set valid = $$$ISOK(..CheckParameters(parameters, ""))
	For i = 1:1:$Length(targets, ",") {
		Set id = $Piece(targets, ",", i)
		If id = "" Continue
		Set contact = ##class(OcuTalon.Fix.PartnerContacts).Named(incident.Production, id)
		If 'valid {
			Do skipped.%Push({"id": (+id), "reason": (..#NOSTART)})
		} ElseIf $IsObject(contact) && (contact.address = $Piece(parameters.%Get("to"), ",", i)) {
			Do deliveries.%Push(contact)
		} ElseIf $IsObject(contact) {
			Do skipped.%Push({"id": (+id), "reason": ($Replace(..Reason(..#RECHECK, incident), "{name}", contact.name))})
		} Else {
			Do skipped.%Push({"id": (+id), "reason": (..#NOSTART)})
		}
	}
	Quit $$$OK
}

}
