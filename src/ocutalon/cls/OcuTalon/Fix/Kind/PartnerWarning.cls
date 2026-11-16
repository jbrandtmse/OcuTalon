/// The fix kind that sends the partner a delay notice about an incident (AD-16; Stories 23.5 and 23.13). The user asks for it in the chat (propose_fix, ASKED 1) with no parameter, and the
/// diagnosis never names it (DIAGNOSED 0). Its text is drafted by the model (DRAFTED 1): IncidentManager has Decide write it from Facts, and only then asks for the dry run with
/// the drafted parameters {"text", "to"}. A request of this kind never moves the incident's state (MOVES 0), and it needs no IRIS privilege (RESOURCES empty): it changes nothing
/// in the production.
///   - The targets are the ids of the production's partner contacts (TARGETTYPE contact), in ascending order; Fix.PartnerContacts holds them (the fixture for the demo's production while
///     demo mode is on, else the contacts of Settings > Partner contacts). The parameter text is the notice, one line of at most NOTICEMAX characters (Normalise leaves it as it is), and to
///     is the comma-separated ids of the recipients, exactly the targets: no name and no address is ever in a parameter, a dry run, a trace or a log (DW-1254).
///   - Facts is the code-built input of the draft: the production, the incident's state (underscores read as spaces), then, only for a resolved incident whose records give it, the Outcome line
///     (built by Outcome, in code, never by the model), the failed items, the count with its item noun, the first and last failure and the stored plain cause. It holds no partner name,
///     message body, sample error, setting value or evidence.
///   - DryRun refuses a production with no contact (NOCONTACTS) and a to that is not the contacts' ids; its answer is {"notice", "recipients": [id, ...], "simulated"}, 1 for the fixture's
///     production and 0 for any other. ForApprover turns the ids into {"id", "name", "address"} for the approval row, which the approver sees (an id that no longer resolves is left out).
///   - Ready: the fixture's production is ready while demo mode is on (its notice goes to the Simulated mailbox); any other production is ready when a mailbox is connected in Settings > Channels
///     > Email and this is not the online demo (MailboxConnected). Otherwise it is 0 with NOTSETUP, and the approved notice is kept as the row's text.
///   - Mail is the mail method (AD-14, MAILS 1) of an executing row of a Settings-contact production: it gives the approved notice, the subject (catalog key partner.emailSubject) and the
///     addresses stored in the row's dry run for the ids of to, for each id whose contact still is one of the production with exactly that address. Any other id is skipped, with the code removed
///     (the contact is gone, no longer lists the production, or the row holds no address for it) or changed (its address is not the approved one) and the reason NOSTART, and nothing ever goes to a
///     new address. It gives 0 for the fixture's production (a fictional contact is never mailed), for a row whose text is not the stored notice and for a to that is not the row's targets.
///   - MayHaveSent says whether the reason of a failed send is an EmailOut sentence that does not say that the mail server never took the email (MAYHAVESENTSENTENCES), which the incident's
///     timeline reads as "may have been sent" (DW-1416).
///   - Recheck and Execute read each target against the source again. For the fixture's production a target passes only if the id still is a contact of the production at its position in to; else
///     it is skipped with a plain reason (RECHECK naming the contact, or NOSTART). Execute sends nothing: its result is {"deliveries": [{"id", "name", "address"}], "skipped": [{"id", "reason"}]},
///     and the executor delivers the approved text from the row, to the Simulated mailbox. A Settings contact is never delivered that way: every target is skipped with NOSTART, and the executor sends
///     such a request only through EmailOut (Mail). Lane A.
Class OcuTalon.Fix.Kind.PartnerWarning Extends OcuTalon.Fix.Kind
{

Parameter NAME = "partner_warning";

Parameter PARAMETERS = "text,to";

Parameter RESOURCES;

Parameter TARGETTYPE = "contact";

Parameter DIAGNOSED = 0;

Parameter ASKED = 1;

Parameter DRAFTED = 1;

Parameter MAILS = 1;

Parameter MOVES = 0;

/// The states in which the chat may ask for the notice: every state but closed (it never moves the incident's state).
Parameter ASKEDSTATES = "open,awaiting_approval,fixing,resolved";

/// The most characters of the notice.
Parameter NOTICEMAX = 1000;

/// The instruction that the draft's turn is given (agent text, never shown to a user). It is constant: no incident data enters it.
Parameter SYSTEMNOTE = "Write a short delay notice to a partner about the failures described below. Use only these facts. Write one plain paragraph of two to four sentences, at most 500 characters, with no greeting line, no signature, no placeholders, no message contents and no setting values, and don't promise when it will be fixed. If the incident is resolved, say how it ended using only the Outcome fact, and don't say that work is still going on or that updates will follow. If there is no Outcome fact, don't say whether the affected items went through.";

Parameter NOTSETUP = "email delivery isn't set up yet";

Parameter NOCONTACTS = "No partner contacts are set up for {production}, so no delay notice was drafted";

Parameter NOITEM = "A delay notice takes no item or address: its recipients are the partner contacts set up for {production}";

Parameter ALLOWANCE = "The online demo allows 20 simulated emails an hour, and this session has used them for now, so no delay notice was drafted";

/// The reason of a recipient that is no longer a contact: {name} and {production} are filled in.
Parameter RECHECK = "{name} is no longer a partner contact of {production}";

Parameter NOSTART = "OcuTalon couldn't deliver the delay notice";

/// The catalog key of the subject of a real email, and the names of the Channel.Email.Out sentences (MESSAGE parameters, read with $Parameter) that its failed send gives as the reason.
Parameter KEYEMAILSUBJECT = "partner.emailSubject";

Parameter OUTSENTENCES = "MESSAGEREFUSED,MESSAGENOTCONNECTED,MESSAGEREJECTED,MESSAGEUNREACHABLE,MESSAGEREFUSEDLOGIN,MESSAGESIGNIN,MESSAGEUNAVAILABLE,MESSAGEFAILED,MESSAGEMAYHAVESENT";

/// The names of the Channel.Email.Out sentences that a failed send of an approved row gives without saying that the mail server never took the email (DW-1416): the claim of an approval is marked
/// failed whatever the failure was, so a timeout or a lost connection during DATA reads MESSAGEUNREACHABLE, an error after the claim reads MESSAGEFAILED, and a repeat of a keyed send reads
/// MESSAGEMAYHAVESENT. Every other OUTSENTENCES word means that nothing was handed to the server (refused before the send, refused login or sign-in, or rejected by the server).
Parameter MAYHAVESENTSENTENCES = "MESSAGEMAYHAVESENT,MESSAGEUNREACHABLE,MESSAGEFAILED";

/// The reason of a run that failed before anything was sent (the executor's NOREAD for this kind): the same words as NOSTART.
Parameter NOREAD = "OcuTalon couldn't deliver the delay notice";

/// The input of the draft, built from the incident's rows only (see the class description): one line each for the production, the incident's state, the failed items,
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
	Set text = "Production: "_..ProductionName(incident)_" ("_incident.Production_")"
	Set text = text_$Char(10)_"Incident state: "_$Translate(incident.State, "_", " ")
	Set outcome = ..Outcome(incident)
	If outcome '= "" Set text = text_$Char(10)_outcome
	Set text = text_$Char(10)_"Failed item: "_items
	Set text = text_$Char(10)_"Failures: "_+incident.Count_" "_$Select(+incident.Count = 1: noun.one, 1: noun.other)
	Set text = text_$Char(10)_"First failure: "_##class(OcuTalon.Tools.CommandCall).TimeLabel(incident.FirstAt, online)
	Set text = text_$Char(10)_"Last failure: "_##class(OcuTalon.Tools.CommandCall).TimeLabel(incident.LastAt, online)
	Set cause = ..Normalise(incident.Cause)
	If cause '= "" Set text = text_$Char(10)_"Cause: "_cause
	Quit text
}

/// The instruction of the draft's turn for the incident: SYSTEMNOTE, the same for every incident. No incident data, the item noun included, enters it.
ClassMethod SystemNote(incident As OcuTalon.Data.Incident) As %String
{
	Quit ..#SYSTEMNOTE
}

/// How the incident ended, as one ruled line for Facts, or "" when its records do not map exactly onto one (the model never computes it). Only a resolved incident has one, and only
/// when exactly one of its requests of a kind that moves the incident (MOVES 1; an unknown kind counts) has a run, that run has ended with Interrupted 0, and the incident's Count (N) is above 0
/// and not below the run's Total or Completed. By the kind of the run:
///   - a fix (a diagnosed kind whose targets are messages): nothing resent gives ""; Resent, Completed and N equal with nothing failed again or skipped gives "all N went through after
///     the fix"; Completed below N gives "A of the N went through after the fix, and R did not" (A is Completed, R is N - A); any other count gives "";
///   - the reroute: Resent equal to N and nothing skipped gives "the N were resent by another route", else "";
///   - a kind that disables an item (ENABLE 0): Completed above 0 and a request parameter item that is the ItemName of one of the incident's failure groups gives "the affected flow was paused,
///     and the N haven't gone through yet", else "";
///   - any other kind gives "".
/// The line holds numbers and the incident's plural item noun only: no item, target, production or partner name, setting value, message content or reason. It reads rows and changes none.
ClassMethod Outcome(incident As OcuTalon.Data.Incident) As %String
{
	If incident.State '= "resolved" Quit ""
	Set count = +incident.Count
	If count < 1 Quit ""
	Set runs = 0
	Set position = 0
	Set refs = $ListFromString(incident.RequestRefs)
	While $ListNext(refs, position, ref) {
		If ref = "" Continue
		Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If '$IsObject(request) || (request.IncidentRef '= incident.Ref) Continue
		Set candidate = ##class(OcuTalon.Data.FixRun).OfRequest(request.Ref)
		If '$IsObject(candidate) Continue
		Set class = ##class(OcuTalon.Fix.Kind).ForName(request.FixKind)
		If (class '= "") && '$Parameter(class, "MOVES") Continue
		Set runs = runs + 1
		Set run = candidate
		Set kind = class
		Set owner = request
	}
	If runs '= 1 Quit ""
	If (run.EndedAt = "") || (+run.Interrupted > 0) || (+run.Total > count) || (+run.Completed > count) Quit ""
	If kind = "" Quit ""
	Set noun = ##class(OcuTalon.Watch.Notice).Noun(incident).other
	If ($Parameter(kind, "TARGETTYPE") = "message") && $Parameter(kind, "DIAGNOSED") {
		If +run.Resent < 1 Quit ""
		If (+run.Resent = count) && (+run.Completed = count) && (+run.FailedAgain = 0) && (+run.Skipped = 0) {
			Quit "Outcome: all "_count_" affected "_noun_" went through after the fix."
		}
		If +run.Completed >= count Quit ""
		Quit "Outcome: "_+run.Completed_" of the "_count_" affected "_noun_" went through after the fix, and "_(count - run.Completed)_" did not."
	}
	If $Parameter(kind, "NAME") = "reroute" {
		If (+run.Resent '= count) || (+run.Skipped '= 0) Quit ""
		Quit "Outcome: the "_count_" affected "_noun_" were resent by another route."
	}
	If ($Parameter(kind, "TARGETTYPE") = "item") && '$Parameter(kind, "ENABLE") {
		If +run.Completed < 1 Quit ""
		Set item = ""
		Try {
			Set parsed = {}.%FromJSON(owner.FixParameters)
			If $IsObject(parsed) && parsed.%IsA("%Library.DynamicObject") Set item = parsed.item
		} Catch {
			Set item = ""
		}
		If (item '= "") && '$IsObject(item) {
			Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
			For i = 1:1:groups.Count() {
				If groups.GetAt(i).ItemName = item Return "Outcome: the affected flow was paused, and the "_count_" affected "_noun_" haven't gone through yet."
			}
		}
		Quit ""
	}
	Quit ""
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

/// The base's schema check, then: text is one line (Normalise leaves it as it is) of at most NOTICEMAX characters, and to is a comma-separated list of positive whole numbers (contact ids).
/// Whether the ids are the production's contacts' is the dry run's and the re-check's.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Set sc = ##super(parameters, fields)
	If $$$ISERR(sc) Quit sc
	Set text = parameters.%Get("text")
	If (text '= ..Normalise(text)) || ($Length(text) > ..#NOTICEMAX) {
		Quit $$$ERROR($$$GeneralError, "The parameter 'text' of "_..#NAME_" is not one line of at most "_..#NOTICEMAX_" characters")
	}
	If '..IdList(parameters.%Get("to")) Quit $$$ERROR($$$GeneralError, "The parameter 'to' of "_..#NAME_" is not a comma-separated list of contact ids")
	Quit $$$OK
}

/// 1 when every piece of the comma-separated list is a positive whole number with no leading zero.
ClassMethod IdList(to As %String) As %Boolean [ Private ]
{
	Quit $Match($Get(to), "^[1-9][0-9]{0,17}(,[1-9][0-9]{0,17})*$")
}

/// The ids of the production's contacts as the targets, and the dry run {"notice", "recipients", "simulated"} (see the class description). An error status that says why when
/// the parameters don't pass CheckParameters, the production has no contact (NOCONTACTS) or to is not exactly the contacts' ids in id order.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set contacts = ##class(OcuTalon.Fix.PartnerContacts).For(incident.Production, incident.Namespace)
	If contacts.%Size() = 0 Quit $$$ERROR($$$GeneralError, ..Reason(..#NOCONTACTS, incident))
	Set ids = ##class(OcuTalon.Fix.PartnerContacts).Ids(contacts)
	If parameters.%Get("to") '= ids {
		Quit $$$ERROR($$$GeneralError, "The recipients of the notice are not the partner contacts set up for "_..ProductionName(incident))
	}
	Set recipients = []
	Set iterator = contacts.%GetIterator()
	While iterator.%GetNext(, .contact) {
		Do recipients.%Push(contact.id)
	}
	Set targets = ids
	Set dryRun = {"notice": (parameters.%Get("text")), "recipients": (recipients), "simulated": (##class(OcuTalon.Fix.PartnerContacts).Simulated(incident.Production))}
	Quit $$$OK
}

/// The dry run as the approver is shown it: each id of recipients becomes {"id", "name", "address"} of the contact it names now; an id that no longer resolves is left out. The result is
/// stored in the approval row and is never part of a traced message.
ClassMethod ForApprover(incident As OcuTalon.Data.Incident, dryRun As %DynamicObject) As %DynamicObject
{
	If '$IsObject(dryRun) || (dryRun.%GetTypeOf("recipients") '= "array") Quit dryRun
	Set shown = []
	Set iterator = dryRun.recipients.%GetIterator()
	While iterator.%GetNext(, .id, .type) {
		If type '= "number" Continue
		Set contact = ##class(OcuTalon.Fix.PartnerContacts).Named(incident.Production, id, incident.Namespace)
		If $IsObject(contact) Do shown.%Push({"id": (contact.id), "name": (contact.name), "address": (contact.address)})
	}
	Do dryRun.%Set("recipients", shown)
	Quit dryRun
}

/// The reason with {production} filled in: the production's display name.
ClassMethod Reason(template As %String, incident As OcuTalon.Data.Incident) As %String
{
	Quit $Replace(template, "{production}", ..ProductionName(incident))
}

/// For the fixture's production: 1 while demo mode is on, else 0 with the reason NOTSETUP (the only contacts there are the demo's simulated ones). For any other production: 1 when a mailbox is
/// connected and this is not the online demo (MailboxConnected), else 0 with NOTSETUP. An approved notice that is not ready is kept as the row's text and nothing is sent.
ClassMethod Ready(incident As OcuTalon.Data.Incident, Output reason As %String) As %Boolean
{
	Set reason = ""
	If ##class(OcuTalon.Fix.PartnerContacts).Simulated(incident.Production) {
		If ##class(OcuTalon.Demo.Guide).DemoOn() Quit 1
	} ElseIf ..MailboxConnected() {
		Quit 1
	}
	Set reason = ..#NOTSETUP
	Quit 0
}

/// 1 when a mailbox is connected in Settings > Channels > Email (the product key email.address, read from its row, holds an address) and this is not the online demo.
ClassMethod MailboxConnected() As %Boolean
{
	Set connected = 0
	Try {
		Set connected = '##class(OcuTalon.Watch.Reader).OnlineDemo() && ##class(OcuTalon.Core.SettingsOps).IsAddress($ZStrip(##class(OcuTalon.Data.Setting).Fresh($Parameter("OcuTalon.Channel.Email.Out", "ADDRESSKEY")), "<>W"))
	} Catch {
		Set connected = 0
	}
	Quit connected
}

/// 1 when the reason is one of the sentences of Channel.Email.Out that a failed send gives (OUTSENTENCES, read from the class), so that a result shows it as EmailOut said it.
ClassMethod OutReason(reason As %String) As %Boolean
{
	If $Get(reason) = "" Quit 0
	Set found = 0
	For i = 1:1:$Length(..#OUTSENTENCES, ",") {
		If $Parameter("OcuTalon.Channel.Email.Out", $Piece(..#OUTSENTENCES, ",", i)) = reason Set found = 1
	}
	Quit found
}

/// 1 when the reason of a failed send is one of the sentences of Channel.Email.Out that do not say that the email was not handed to the mail server (MAYHAVESENTSENTENCES, read from the class), so that the
/// timeline says that the notice may have been sent. Any other reason, a sentence of OUTSENTENCES that says nothing was sent included, gives 0.
ClassMethod MayHaveSent(reason As %String) As %Boolean
{
	If $Get(reason) = "" Quit 0
	Set found = 0
	For i = 1:1:$Length(..#MAYHAVESENTSENTENCES, ",") {
		If $Parameter("OcuTalon.Channel.Email.Out", $Piece(..#MAYHAVESENTSENTENCES, ",", i)) = reason Set found = 1
	}
	Quit found
}

/// The mail method (see the class description). Gives 1 with the recipients, the subject, the approved text and the skipped entries {"id", "code", "reason"} for a row that is as approved, even
/// when every recipient was skipped (recipients is then empty); 0 with empty outputs for anything else.
ClassMethod Mail(row As OcuTalon.Bridge.Data.ApprovalRequest, Output recipients As %DynamicArray, Output subject As %String, Output text As %String, Output skipped As %DynamicArray) As %Boolean
{
	Set recipients = []
	Set subject = ""
	Set text = ""
	Set skipped = []
	Set mailed = 0
	Try {
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(row.IncidentRef)
		If '$IsObject(incident) || ##class(OcuTalon.Fix.PartnerContacts).Simulated(incident.Production) Quit
		Set parameters = {}.%FromJSON(row.FixParameters)
		Set stored = {}.%FromJSON(row.DryRun)
		If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") || '$IsObject(stored) || 'stored.%IsA("%Library.DynamicObject") Quit
		If $$$ISERR(..CheckParameters(parameters, "")) Quit
		If (stored.%GetTypeOf("notice") '= "string") || (stored.notice = "") || (stored.notice '= parameters.text) || (parameters.to '= row.FixTargets) Quit
		If stored.%GetTypeOf("recipients") '= "array" Quit
		Kill approved, current
		Set iterator = stored.recipients.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If $IsObject(entry) && entry.%IsA("%Library.DynamicObject") && (entry.%Get("id") ? 1.N) && (entry.%GetTypeOf("address") = "string") Set approved(+entry.%Get("id")) = $ZStrip(entry.address, "<>W")
		}
		Set iterator = ##class(OcuTalon.Fix.PartnerContacts).For(incident.Production, incident.Namespace).%GetIterator()
		While iterator.%GetNext(, .contact) {
			Set current(contact.id) = $ZStrip(contact.address, "<>W")
		}
		For i = 1:1:$Length(parameters.to, ",") {
			Set id = +$Piece(parameters.to, ",", i)
			If ($Get(approved(id)) '= "") && $Data(current(id)) && (current(id) = approved(id)) {
				Do recipients.%Push(approved(id))
			} Else {
				Do skipped.%Push({"id": (id), "code": ($Select(($Get(approved(id)) = "") || '$Data(current(id)): "removed", 1: "changed")), "reason": (..#NOSTART)})
			}
		}
		Set subject = ##class(OcuTalon.Msg.Catalog).Render(..#KEYEMAILSUBJECT, "", "email", .sc)
		If $$$ISERR(sc) Set subject = ""
		Set text = stored.notice
		Set mailed = 1
	} Catch {
		Set mailed = 0
		Set recipients = []
		Set subject = ""
		Set text = ""
		Set skipped = []
	}
	Quit mailed
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

/// The test of Recheck and Execute: for the fixture's production, deliveries holds {"id", "name", "address"} for each target that is still a contact of the production at its position in to,
/// and skipped {"id", "reason"} for each other target: RECHECK with the contact's name for a contact that is not at its position, NOSTART for an id that the fixture does not name (no
/// name is known for it). A Settings contact is never delivered here: every target is skipped with NOSTART, as is every target of parameters that don't pass CheckParameters. It changes
/// nothing.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output deliveries As %DynamicArray, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Set deliveries = []
	Set skipped = []
	Set valid = $$$ISOK(..CheckParameters(parameters, "")) && ##class(OcuTalon.Fix.PartnerContacts).Simulated(incident.Production)
	For i = 1:1:$Length(targets, ",") {
		Set id = $Piece(targets, ",", i)
		If id = "" Continue
		Set contact = $Select(valid: ##class(OcuTalon.Fix.PartnerContacts).Named(incident.Production, id, incident.Namespace), 1: "")
		If 'valid {
			Do skipped.%Push({"id": (+id), "reason": (..#NOSTART)})
		} ElseIf $IsObject(contact) && (contact.id = +$Piece(parameters.%Get("to"), ",", i)) {
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
