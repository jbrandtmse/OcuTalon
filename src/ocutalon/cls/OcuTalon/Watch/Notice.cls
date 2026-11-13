/// What the notice of an incident says, as catalog keys and slots written by code (pure; Story 5.8; AD-8, AD-15, AD-31, AD-32). The producer never
/// renders (OcuTalon.Msg.Catalog does that in the *Out operations): this class decides which key a settled incident gets and builds the slots of that key
/// from the incident row and its failure groups. It renders nothing, writes nothing and sends nothing; IncidentManager sends the notice.
///   - Key and Variant of a diagnosed incident (OcuTalon.Msg.Catalog.Watch):
///       Fallback 1 (any reason)                     incident.fallback       open variant fallback
///       usable, category unknown                    incident.noFixUnknown   open variant no_fix
///       usable, data_format_change (with a fix)     "" : no notice here; the with-fix notice goes out with the dry run and the approval request
///       usable, data_format_change with no fix      incident.noFix          open variant no_fix (a diagnosis that cannot tell which way a date reads, DW-644)
///       usable, any other category                  incident.noFix          open variant no_fix
///   - Slots, by key: count is the incident's NoticeCount (its Count while that is empty), time its FirstAt and itemNoun its ItemNoun, else the code noun
///     of an empty body class. incident.noFix adds cause and groups, incident.noFixUnknown groups, incident.fallback fallbackReason (the row's reason, unusable
///     when it is empty or not a Msg.Enum FALLBACKREASON) and groups. WithFixSlots is the builder of the with-fix notice: count, time, itemNoun, cause and
///     fixSummary, and, given the dry run, its field, before, after and resendCount (the dry run's resend as an integer). A key given to Slots replaces Key(incident):
///     the incident.noFix notice of a data-format incident whose fix cannot be proposed (the dry run is refused, finds nothing to resend, or its request is not raised).
///   - Dates that read two ways (DW-644): WithFixKey gives the key of the with-fix notice. It is incident.withFixEitherWay (a later request:
///     incident.laterRequestEitherWay) exactly when the request's sourceFormat is MM/DD/YYYY or DD/MM/YYYY and the dry run's before reads in both orders as two
///     different dates (the dry run refuses a request whose dates read both ways with nothing to single out the reading, so every raised request of that kind
///     has arrival evidence: Fix.Kind.RepairResend Evidence). WithFixSlots, given the parameters, then adds reading (month first or day first, the source
///     format's, READINGS) and item (the one form of the itemNoun slot). Reading is public because it is the one rule: the approval payload
///     (Live.Payload.Approval FromRow) asks it over the row's stored dry run and FixParameters, so the web card shows the line exactly when the notice does.
///   - The later request (Story 7.6, KEYLATER incident.laterRequest) takes the with-fix slots with its own round's count and time: WithFixSlots given a count and a
///     time replaces the slots count and time (the failures of the round, and the first of them), and renders "{count} more {itemNoun} failed since {time}, with
///     the same cause ...". It carries the cause slot too, which the catalog ignores.
///   - Good messages checked (Story 7.9, FR-25): the dry run of repair_resend also carries goodCheck {"checked", "changed"} (the answer only; the stored dry run does not
///     hold it). When checked is at least 1, WithFixKey gives the ...Checked variant of the key it gives otherwise: incident.withFixChecked, incident.laterRequestChecked,
///     incident.withFixEitherWayChecked and incident.laterRequestEitherWayChecked, and WithFixSlots adds goodChecked and goodChanged (counts) and goodNoun (the itemNoun's
///     one form when goodChecked is 1, else its other form). With checked 0, or no goodCheck, the key and the slots are today's. A goodCheck that is not an object with
///     whole-number checked and changed is refused like a bad dry run ("" with sc).
///   - groups holds one {itemName, count, errorSummary, firstAt} per failure group that has a NoticeCount, in Seq order. A group's count is its
///     NoticeCount, so the lines add up to the count slot even when failures joined during the diagnosis. An empty error summary is written as NOERRORTEXT.
///   - The result of a fix run (Story 7.3, Consistency Conventions: Result texts): ResultKey gives the catalog key of the notice for an accepted FixResult (final,
///     interrupted or in progress), the first row that matches:
///       the request's row is executing, or the result is neither final nor interrupted (a progress report)   result.stillResending
///       the run was interrupted                             result.interrupted
///       Resent, Completed, FailedAgain and Skipped are 0    result.couldNotStart (when Reason is set; Total is the number of targets that were not resent)
///       Unreached is above 0                                result.stoppedPartway (the resend stopped at the first copy that erred; Unreached is part of Skipped)
///       FailedAgain and Skipped                             result.failedAndSkipped
///       FailedAgain                                         result.failedAgain
///       Skipped                                             result.skipped
///       otherwise                                           result.allThrough
///     ResultSlots gives the slots that the key declares, as a dynamic object, from the FixResult and the item noun: count (Total), itemNoun, completed, failedAgain,
///     skipped, resent, notTried (Unreached less the copy that erred, at least 0), remaining (Total less Completed, at least 0), failReason and reason (both the Reason). An empty count is 0. The result texts (OcuTalon.Msg.Catalog.Watch)
///     are the experience document's; this class renders nothing.
///   - A fix the user asked for in the chat (Story 23.2): AskedKey gives the catalog key of its approval notice from the kind's name (incident.suspendRequest,
///     incident.resumeRequest or incident.rerouteRequest) and AskedSlots builds the slots from the dry run: item and production for the two item kinds; count (the dry run's
///     affected), itemNoun, from, to, example and resendCount (its resend) for a reroute. ResultKey, given the kind's name, gives result.itemSuspended or result.itemResumed
///     for an item kind that changed its item, result.itemSkipped when the re-check skipped it and result.itemNotChanged when the run could not start; for a reroute whose copies
///     all completed (the key that is result.allThrough) it gives result.rerouted. ResultSlots, given the item, production and target in extra, adds them.
///   - A partner delay notice (Story 23.5): AskedKey gives incident.partnerRequest for partner_warning and AskedSlots {recipients ("Name <address>" of each recipient of the dry
///     run, joined with ", "), notice (the dry run's text)}. ResultKey, given the kind's name, gives for a kind whose targets are contacts result.partnerKept (the run failed with the
///     kind's NOTSETUP reason), result.partnerSent (every recipient was sent), result.partnerSentSome (some were) or result.partnerNotSent (none was); ResultSlots gives count
///     (Completed), or completed, total and reason (the Reason), or reason, by the key. result.partnerNotDrafted, the result of a draft that failed, is IncidentManager's and has no slots.
///   - The good-message refusal (DW-823): NoFixKey gives incident.goodChanged, in place of incident.noFix, for the reason of a repair dry run that the good-message check refused
///     (Fix.Kind.RepairResend GOODCHANGED); its slots are those of incident.noFix and noun, the plural item noun.
/// Slots, WithFixSlots and ResultSlots give "" with an error status in sc where the slots cannot be built (no group, an empty cause, an empty time, a dry run without its
/// field, before or after or with a resend below 1, a given count below 1 or not a whole number, a given time that is empty; a noun without both forms, an empty
/// reason where the key needs one, a key that is no result key).
Class OcuTalon.Watch.Notice
{

/// The catalog keys of the notices.
Parameter KEYFALLBACK = "incident.fallback";

Parameter KEYUNKNOWN = "incident.noFixUnknown";

Parameter KEYNOFIX = "incident.noFix";

Parameter KEYWITHFIX = "incident.withFix";

/// The catalog key of the notice of a later request in the same incident (Story 7.6).
Parameter KEYLATER = "incident.laterRequest";

/// The variants of KEYWITHFIX and KEYLATER whose dry-run paragraph says that the dates read both ways and match the day each item arrived.
Parameter KEYWITHFIXEITHER = "incident.withFixEitherWay";

Parameter KEYLATEREITHER = "incident.laterRequestEitherWay";

/// The variants of the four keys above whose dry-run paragraph also says how many good messages from the same source the repair was tried on and how many it would
/// change (Story 7.9): given when the dry run's goodCheck counts at least one message.
Parameter KEYWITHFIXCHECKED = "incident.withFixChecked";

Parameter KEYLATERCHECKED = "incident.laterRequestChecked";

Parameter KEYWITHFIXEITHERCHECKED = "incident.withFixEitherWayChecked";

Parameter KEYLATEREITHERCHECKED = "incident.laterRequestEitherWayChecked";

/// The key of the dry run's answer that holds the counts of the good-message check (Fix.Kind.RepairResend GOODCHECK; it is not stored).
Parameter GOODCHECK = "goodCheck";

/// The source formats that read both ways, each with the words of its reading in the catalog line, separated by commas.
Parameter READINGS = "MM/DD/YYYY:month first,DD/MM/YYYY:day first";

/// The open variants (Msg.Enum INCIDENTOPENVARIANT).
Parameter VARIANTFALLBACK = "fallback";

Parameter VARIANTNOFIX = "no_fix";

/// The cause category that has a fix to propose, and the one that has no cause.
Parameter WITHFIXCATEGORY = "data_format_change";

Parameter UNKNOWNCATEGORY = "unknown";

/// The catalog keys of the notice of a fix run's result (Story 7.3).
Parameter KEYALLTHROUGH = "result.allThrough";

Parameter KEYFAILEDAGAIN = "result.failedAgain";

Parameter KEYSKIPPED = "result.skipped";

Parameter KEYFAILEDANDSKIPPED = "result.failedAndSkipped";

Parameter KEYSTILL = "result.stillResending";

Parameter KEYINTERRUPTED = "result.interrupted";

Parameter KEYPARTWAY = "result.stoppedPartway";

Parameter KEYCOULDNOTSTART = "result.couldNotStart";

/// The catalog keys of the notice of a fix the user asked for in the chat and of its result (Story 23.2), and of the good-message refusal (DW-823).
Parameter KEYSUSPENDREQUEST = "incident.suspendRequest";

Parameter KEYRESUMEREQUEST = "incident.resumeRequest";

Parameter KEYREROUTEREQUEST = "incident.rerouteRequest";

Parameter KEYGOODCHANGED = "incident.goodChanged";

Parameter KEYITEMSUSPENDED = "result.itemSuspended";

Parameter KEYITEMRESUMED = "result.itemResumed";

Parameter KEYITEMSKIPPED = "result.itemSkipped";

Parameter KEYITEMNOTCHANGED = "result.itemNotChanged";

Parameter KEYREROUTED = "result.rerouted";

/// The catalog keys of a partner delay notice (Story 23.5): the approval notice, and the results of a run and of a draft that failed.
Parameter KEYPARTNERREQUEST = "incident.partnerRequest";

Parameter KEYPARTNERSENT = "result.partnerSent";

Parameter KEYPARTNERSENTSOME = "result.partnerSentSome";

Parameter KEYPARTNERNOTSENT = "result.partnerNotSent";

Parameter KEYPARTNERKEPT = "result.partnerKept";

Parameter KEYPARTNERNOTDRAFTED = "result.partnerNotDrafted";

/// The state of an approval request that is still carrying out its fix.
Parameter EXECUTING = "executing";

/// The fallback reason of a reason that is empty or not one of Msg.Enum FALLBACKREASON.
Parameter UNUSABLE = "unusable";

/// The summary of a group whose error text is empty: the catalog needs a text, and the line stays (public text, veto U-94).
Parameter NOERRORTEXT = "no error text";

/// The catalog key of the notice for the diagnosed incident, "" when it gets none from this class (a usable data-format diagnosis with a fix summary: its
/// notice is the with-fix notice, KEYWITHFIX; a data-format diagnosis with no fix summary gets KEYNOFIX).
ClassMethod Key(incident As OcuTalon.Data.Incident) As %String
{
	If incident.Fallback Quit ..#KEYFALLBACK
	If incident.CauseCategory = ..#UNKNOWNCATEGORY Quit ..#KEYUNKNOWN
	If incident.CauseCategory = ..#WITHFIXCATEGORY Quit $Select(..Text(incident.FixSummary) = "": ..#KEYNOFIX, 1: "")
	Quit ..#KEYNOFIX
}

/// The open variant that goes with Key(incident): fallback or no_fix; "" when Key gives "".
ClassMethod Variant(incident As OcuTalon.Data.Incident) As %String
{
	Set key = ..Key(incident)
	If key = "" Quit ""
	Quit $Select(key = ..#KEYFALLBACK: ..#VARIANTFALLBACK, 1: ..#VARIANTNOFIX)
}

/// The slots of the notice of Key(incident) as a dynamic object, or "" with the reason in sc. groups is the list of the incident's FailureGroup objects in
/// Seq order, or "" for the incident's own (FailureGroup.OfIncident). A key given replaces Key(incident).
ClassMethod Slots(incident As OcuTalon.Data.Incident, groups As %ListOfObjects = "", Output sc As %Status, key As %String = "") As %DynamicObject
{
	Set sc = $$$OK
	If key = "" Set key = ..Key(incident)
	If key = "" {
		Set sc = $SYSTEM.Status.Error(5001, "The incident has no notice of its own: it has a fix")
		Quit ""
	}
	Set slots = ..Common(incident, .sc)
	If $$$ISERR(sc) Quit ""
	If key = ..#KEYFALLBACK Do slots.%Set("fallbackReason", ..Reason(incident))
	If (key = ..#KEYNOFIX) || (key = ..#KEYGOODCHANGED) {
		Set cause = ..Text(incident.Cause)
		If cause = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" has no cause")
			Quit ""
		}
		Do slots.%Set("cause", cause)
		If key = ..#KEYGOODCHANGED Do slots.%Set("noun", slots.itemNoun.other)
	}
	Set lines = ..Groups(incident, groups, .sc)
	If $$$ISERR(sc) Quit ""
	Do slots.%Set("groups", lines)
	Quit slots
}

/// The catalog key of the notice of a no-fix incident whose repair dry run was refused with the reason: KEYGOODCHANGED when the reason is that of the good-message check
/// (it starts with the text of Fix.Kind.RepairResend GOODCHANGED before its first placeholder), else KEYNOFIX. Pure.
ClassMethod NoFixKey(reason As %String) As %String
{
	Set lead = $Piece($Parameter("OcuTalon.Fix.Kind.RepairResend", "GOODCHANGED"), "{", 1)
	If (lead '= "") && ($Extract($Get(reason), 1, $Length(lead)) = lead) Quit ..#KEYGOODCHANGED
	Quit ..#KEYNOFIX
}

/// The catalog key of the approval notice of a fix the user asked for in the chat, from the kind's name (suspend_item, resume_item, reroute or partner_warning); "" for any
/// other kind. Pure.
ClassMethod AskedKey(kind As %String) As %String
{
	Quit $Case($Get(kind), "suspend_item": ..#KEYSUSPENDREQUEST, "resume_item": ..#KEYRESUMEREQUEST, "reroute": ..#KEYREROUTEREQUEST, "partner_warning": ..#KEYPARTNERREQUEST, : "")
}

/// The slots of the approval notice of a fix the user asked for in the chat (see the class description), from the kind's name, the dry run (a dynamic object) and the incident;
/// "" with the reason in sc when the kind has no such notice or the dry run lacks what the notice says.
ClassMethod AskedSlots(kind As %String, dryRun As %DynamicObject, incident As OcuTalon.Data.Incident, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Set key = ..AskedKey(kind)
	If key = "" {
		Set sc = $SYSTEM.Status.Error(5001, "'"_$Get(kind)_"' is not a fix that the chat asks for")
		Quit ""
	}
	If '$IsObject($Get(dryRun)) {
		Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" is not an object")
		Quit ""
	}
	If key = ..#KEYPARTNERREQUEST {
		Set notice = ..Text(dryRun.notice)
		Set recipients = ""
		If $IsObject(dryRun.recipients) {
			Set iterator = dryRun.recipients.%GetIterator()
			While iterator.%GetNext(, .recipient) {
				If (..Text(recipient.name) = "") || (..Text(recipient.address) = "") Continue
				Set recipients = recipients_$Select(recipients = "": "", 1: ", ")_..Text(recipient.name)_" <"_..Text(recipient.address)_">"
			}
		}
		If (notice = "") || (recipients = "") {
			Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no notice or no recipient")
			Quit ""
		}
		Quit {"recipients": (recipients), "notice": (notice)}
	}
	If (key = ..#KEYSUSPENDREQUEST) || (key = ..#KEYRESUMEREQUEST) {
		Set item = ..Text(dryRun.item)
		If item = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no item")
			Quit ""
		}
		Quit {"item": (item), "production": (##class(OcuTalon.Fix.Kind).ProductionName(incident))}
	}
	Set from = ..Text(dryRun.from)
	Set to = ..Text(dryRun.to)
	Set example = ..Text(dryRun.example)
	Set noun = dryRun.itemNoun
	Set affected = dryRun.affected
	Set resend = dryRun.resend
	If (from = "") || (to = "") || (example = "") || (affected '? 1.N) || (+affected < 1) || (resend '? 1.N) || (+resend < 1) {
		Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no from, to, example, affected or resend")
		Quit ""
	}
	If '$IsObject(noun) || (..Text(noun.one) = "") || (..Text(noun.other) = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no item noun with both forms")
		Quit ""
	}
	Quit {"count": (+affected), "itemNoun": (noun), "from": (from), "to": (to), "example": (example), "resendCount": (+resend)}
}

/// The catalog key of the with-fix notice for the dry run and the request's parameters (JSON text or a dynamic object): KEYWITHFIX, or KEYWITHFIXEITHER when the
/// request's source format is an order format and the dry run's before reads in both orders as two different dates; with later 1, KEYLATER or KEYLATEREITHER. When the
/// dry run's goodCheck counts at least one checked message (Checked), the ...CHECKED variant of that key. Pure.
ClassMethod WithFixKey(dryRun As %DynamicObject, parameters As %String = "", later As %Boolean = 0) As %String
{
	Set eitherWay = ..Reading($Get(dryRun), $Get(parameters)) '= ""
	Set checked = (..Checked($Get(dryRun)) > 0)
	If later Quit $Select(eitherWay: $Select(checked: ..#KEYLATEREITHERCHECKED, 1: ..#KEYLATEREITHER), 1: $Select(checked: ..#KEYLATERCHECKED, 1: ..#KEYLATER))
	Quit $Select(eitherWay: $Select(checked: ..#KEYWITHFIXEITHERCHECKED, 1: ..#KEYWITHFIXEITHER), 1: $Select(checked: ..#KEYWITHFIXCHECKED, 1: ..#KEYWITHFIX))
}

/// The number of good messages that the dry run's goodCheck says were checked: 0 when the dry run has no goodCheck, or when it is not an object with whole-number
/// checked and changed (a bad goodCheck gives no ...Checked key; WithFixSlots refuses it). Pure.
ClassMethod Checked(dryRun As %DynamicObject) As %Integer
{
	If '$IsObject($Get(dryRun)) || 'dryRun.%IsDefined(..#GOODCHECK) Quit 0
	Set check = dryRun.%Get(..#GOODCHECK)
	If '$IsObject(check) || 'check.%IsA("%Library.DynamicObject") Quit 0
	Set checked = check.%Get("checked")
	Set changed = check.%Get("changed")
	If (checked '? 1.N) || (changed '? 1.N) Quit 0
	Quit +checked
}

/// The words of the source reading ("month first" or "day first") when WithFixKey gives an either-way key for the dry run and the parameters, else "". The
/// notice and the approval payload (Live.Payload.Approval FromRow) both ask this method, so they agree. Pure.
ClassMethod Reading(dryRun As %DynamicObject, parameters As %String = "") As %String
{
	If '$IsObject($Get(dryRun)) Quit ""
	If '$IsObject(parameters) {
		Try {
			Set parameters = {}.%FromJSON(parameters)
		} Catch {
			Set parameters = ""
		}
	}
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") Quit ""
	Set source = parameters.%Get("sourceFormat")
	If '##class(OcuTalon.Fix.Reformat).Readings(dryRun.before, source, .first, .second) || (first = second) Quit ""
	Set words = ""
	For i = 1:1:$Length(..#READINGS, ",") {
		Set entry = $Piece(..#READINGS, ",", i)
		If $Piece(entry, ":", 1) = source Set words = $Piece(entry, ":", 2)
	}
	Quit words
}

/// The slots of the with-fix notice that the incident's diagnosis gives: count, time, itemNoun, cause and fixSummary. Given the dry run (a dynamic object with the
/// keys of ApprovalRequest DRYRUNKEYS), it adds field, before, after and resendCount (the dry run's resend as an integer). "" with the reason in sc when the cause
/// or the fix summary is empty, or when the dry run has no field, before or after, or a resend below 1. A count given (a whole number of at least 1) replaces the
/// count slot and a time given (not empty) replaces the time slot: the failures of a later round and the first of them (an argument that is passed counts as
/// given, also when it is empty; an argument that is left out does not). Given the request's parameters (JSON text or a dynamic object) and a dry run for which
/// WithFixKey gives an either-way key, it adds reading and item.
ClassMethod WithFixSlots(incident As OcuTalon.Data.Incident, Output sc As %Status, dryRun As %DynamicObject = "", count As %Integer, time As %String, parameters As %String = "") As %DynamicObject
{
	Set slots = ..Common(incident, .sc)
	If $$$ISERR(sc) Quit ""
	If $Data(count) {
		If (count '? 1.N) || (+count < 1) {
			Set sc = $SYSTEM.Status.Error(5001, "The count of the later request of incident "_incident.Ref_" is not a whole number of at least one")
			Quit ""
		}
		Do slots.%Set("count", +count)
	}
	If $Data(time) {
		If time = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The later request of incident "_incident.Ref_" has no first failure time")
			Quit ""
		}
		Do slots.%Set("time", time)
	}
	Set cause = ..Text(incident.Cause)
	Set fix = ..Text(incident.FixSummary)
	If (cause = "") || (fix = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" has no cause or no fix summary")
		Quit ""
	}
	Do slots.%Set("cause", cause)
	Do slots.%Set("fixSummary", fix)
	If $IsObject(dryRun) {
		Set field = ..Text(dryRun.field)
		Set before = ..Text(dryRun.before)
		Set after = ..Text(dryRun.after)
		Set resend = dryRun.resend
		If (field = "") || (before = "") || (after = "") || (resend '? 1.N) || (+resend < 1) {
			Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no field, before or after, or resends fewer than one")
			Quit ""
		}
		Do slots.%Set("field", field)
		Do slots.%Set("before", before)
		Do slots.%Set("after", after)
		Do slots.%Set("resendCount", +resend)
		Set reading = ..Reading(dryRun, parameters)
		If reading '= "" {
			Do slots.%Set("reading", reading)
			Do slots.%Set("item", slots.itemNoun.one)
		}
		If dryRun.%IsDefined(..#GOODCHECK) {
			Set check = dryRun.%Get(..#GOODCHECK)
			If '$IsObject(check) || 'check.%IsA("%Library.DynamicObject") || (check.%Get("checked") '? 1.N) || (check.%Get("changed") '? 1.N) {
				Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has a goodCheck that is not an object with whole-number checked and changed")
				Quit ""
			}
			If +check.checked > 0 {
				Do slots.%Set("goodChecked", +check.checked, "number")
				Do slots.%Set("goodChanged", +check.changed, "number")
				Do slots.%Set("goodNoun", $Select(+check.checked = 1: slots.itemNoun.one, 1: slots.itemNoun.other))
			}
		}
	}
	Quit slots
}

/// The catalog key of the notice of a FixResult, for the state of the request's row (see the class description). Pure.
ClassMethod ResultKey(state As %String, result As OcuTalon.Fix.Msg.FixResult, kind As %String = "") As %String
{
	If ($Get(state) = ..#EXECUTING) || ('result.Final && 'result.Interrupted) Quit ..#KEYSTILL
	If result.Interrupted Quit ..#KEYINTERRUPTED
	Set class = ##class(OcuTalon.Fix.Kind).ForName(kind)
	If (class '= "") && ($Parameter(class, "TARGETTYPE") = "contact") {
		If ($Get(state) = "failed") && ($Parameter(class, "NOTSETUP") '= "") && (result.Reason = $Parameter(class, "NOTSETUP")) Quit ..#KEYPARTNERKEPT
		If (+result.Completed > 0) && (+result.Completed = +result.Total) Quit ..#KEYPARTNERSENT
		If +result.Completed > 0 Quit ..#KEYPARTNERSENTSOME
		Quit ..#KEYPARTNERNOTSENT
	}
	If (class '= "") && ($Parameter(class, "TARGETTYPE") = "item") {
		If +result.Completed > 0 Quit $Select($Parameter(class, "ENABLE"): ..#KEYITEMRESUMED, 1: ..#KEYITEMSUSPENDED)
		If +result.Skipped > 0 Quit ..#KEYITEMSKIPPED
		Quit ..#KEYITEMNOTCHANGED
	}
	Set key = ..MessageKey(result)
	If (key = ..#KEYALLTHROUGH) && ($Get(kind) = "reroute") Quit ..#KEYREROUTED
	Quit key
}

/// The catalog key of the result of a fix whose targets are messages, from the counts (the rows of the class description after the first two). Pure.
ClassMethod MessageKey(result As OcuTalon.Fix.Msg.FixResult) As %String [ Private ]
{
	Set failedAgain = +result.FailedAgain
	Set skipped = +result.Skipped
	If (+result.Resent = 0) && (+result.Completed = 0) && (failedAgain = 0) && (skipped = 0) && (result.Reason '= "") Quit ..#KEYCOULDNOTSTART
	If +result.Unreached > 0 Quit ..#KEYPARTWAY
	If failedAgain && skipped Quit ..#KEYFAILEDANDSKIPPED
	If failedAgain Quit ..#KEYFAILEDAGAIN
	If skipped Quit ..#KEYSKIPPED
	Quit ..#KEYALLTHROUGH
}

/// The slots of the result key for the FixResult (see the class description) as a dynamic object, or "" with the reason in sc. noun is the item noun, a dynamic
/// object with both forms {"one", "other"}.
ClassMethod ResultSlots(key As %String, result As OcuTalon.Fix.Msg.FixResult, noun As %DynamicObject, Output sc As %Status, extra As %DynamicObject = "") As %DynamicObject
{
	Set sc = $$$OK
	Set reason = ..Text(result.Reason)
	If '$IsObject(extra) Set extra = {}
	If $ListFind($ListBuild(..#KEYPARTNERSENT, ..#KEYPARTNERSENTSOME, ..#KEYPARTNERNOTSENT, ..#KEYPARTNERKEPT), key) {
		If key = ..#KEYPARTNERKEPT Quit {}
		If key = ..#KEYPARTNERSENT Quit {"count": (+result.Completed)}
		If reason = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no reason")
			Quit ""
		}
		If key = ..#KEYPARTNERNOTSENT Quit {"reason": (reason)}
		Quit {"completed": (+result.Completed), "total": (+result.Total), "reason": (reason)}
	}
	If (key = ..#KEYITEMSUSPENDED) || (key = ..#KEYITEMRESUMED) || (key = ..#KEYITEMSKIPPED) || (key = ..#KEYITEMNOTCHANGED) {
		If (key '= ..#KEYITEMNOTCHANGED) && (..Text(extra.item) = "") {
			Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no item")
			Quit ""
		}
		If ((key = ..#KEYITEMSUSPENDED) || (key = ..#KEYITEMRESUMED)) && (..Text(extra.production) = "") {
			Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no production")
			Quit ""
		}
		If ((key = ..#KEYITEMSKIPPED) || (key = ..#KEYITEMNOTCHANGED)) && (reason = "") {
			Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no reason")
			Quit ""
		}
		If key = ..#KEYITEMNOTCHANGED Quit {"reason": (reason)}
		If key = ..#KEYITEMSKIPPED Quit {"item": (..Text(extra.item)), "reason": (reason)}
		Quit {"item": (..Text(extra.item)), "production": (..Text(extra.production))}
	}
	If key = ..#KEYCOULDNOTSTART {
		If reason = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no reason")
			Quit ""
		}
		Quit {"reason": (reason)}
	}
	If '$ListFind($ListBuild(..#KEYALLTHROUGH, ..#KEYREROUTED, ..#KEYFAILEDAGAIN, ..#KEYSKIPPED, ..#KEYFAILEDANDSKIPPED, ..#KEYSTILL, ..#KEYINTERRUPTED, ..#KEYPARTWAY), key) {
		Set sc = $SYSTEM.Status.Error(5001, "'"_$Get(key)_"' is not the key of a result")
		Quit ""
	}
	If '$IsObject($Get(noun)) || (..Text(noun.one) = "") || (..Text(noun.other) = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no item noun with both forms")
		Quit ""
	}
	If ((key = ..#KEYFAILEDAGAIN) || (key = ..#KEYFAILEDANDSKIPPED)) && (reason = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has failures and no reason")
		Quit ""
	}
	Set count = +result.Total
	Set completed = +result.Completed
	Set slots = {}
	Do slots.%Set("count", count, "number")
	Do slots.%Set("itemNoun", noun)
	If key = ..#KEYREROUTED {
		If ..Text(extra.to) = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The result of "_result.ApprovalRef_" has no target item")
			Quit ""
		}
		Do slots.%Set("to", ..Text(extra.to))
	}
	If (key '= ..#KEYALLTHROUGH) && (key '= ..#KEYREROUTED) Do slots.%Set("completed", completed, "number")
	If (key = ..#KEYFAILEDAGAIN) || (key = ..#KEYFAILEDANDSKIPPED) {
		Do slots.%Set("failedAgain", +result.FailedAgain, "number")
		Do slots.%Set("failReason", reason)
	}
	If (key = ..#KEYSKIPPED) || (key = ..#KEYFAILEDANDSKIPPED) Do slots.%Set("skipped", +result.Skipped, "number")
	If key = ..#KEYINTERRUPTED Do slots.%Set("remaining", $Select(count > completed: count - completed, 1: 0), "number")
	If key = ..#KEYPARTWAY {
		Do slots.%Set("resent", +result.Resent, "number")
		Set tried = +result.Unreached - 1
		Do slots.%Set("notTried", $Select(tried > 0: tried, 1: 0), "number")
	}
	If key = ..#KEYFAILEDANDSKIPPED Do slots.%Set("resent", +result.Resent, "number")
	Quit slots
}

/// The slots every notice has: count, time and itemNoun. The summary of a closed incident (Watch.Summary) reads its itemNoun.
ClassMethod Common(incident As OcuTalon.Data.Incident, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	If incident.FirstAt = "" {
		Set sc = $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" has no first failure time")
		Quit ""
	}
	Set noun = ""
	If incident.ItemNoun '= "" {
		Try {
			Set noun = {}.%FromJSON(incident.ItemNoun)
		} Catch {
			Set noun = ""
		}
	}
	If '$IsObject(noun) Set noun = {}.%FromJSON(##class(OcuTalon.Watch.ItemNoun).For(""))
	Quit {"count": (+$Select(incident.NoticeCount '= "": incident.NoticeCount, 1: incident.Count)), "time": (incident.FirstAt), "itemNoun": (noun)}
}

/// The item noun {"one", "other"} of a request: the itemNoun of the request's stored dry run (JSON text), else the incident's ItemNoun, else the code noun of an
/// empty body class (the first that is an object with both forms).
ClassMethod Noun(incident As OcuTalon.Data.Incident, dryRun As %String = "") As %DynamicObject
{
	For source = 1, 2 {
		Set noun = ""
		Try {
			If source = 1 {
				If dryRun '= "" Set noun = {}.%FromJSON(dryRun).itemNoun
			} ElseIf incident.ItemNoun '= "" {
				Set noun = {}.%FromJSON(incident.ItemNoun)
			}
		} Catch {
			Set noun = ""
		}
		If $IsObject(noun) && noun.%IsA("%Library.DynamicObject") && (noun.one '= "") && (noun.other '= "") Quit
		Set noun = ""
	}
	If '$IsObject(noun) Set noun = {}.%FromJSON(##class(OcuTalon.Watch.ItemNoun).For(""))
	Quit noun
}

/// The fallback reason of the incident as the catalog takes it: its own when it is one of Msg.Enum FALLBACKREASON, else unusable.
ClassMethod Reason(incident As OcuTalon.Data.Incident) As %String
{
	Set reason = incident.FallbackReason
	If (reason '= "") && $ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#FALLBACKREASON), reason) Quit reason
	Quit ..#UNUSABLE
}

/// The groups slot: one {itemName, count, errorSummary, firstAt} per group that has a NoticeCount, in the order of the list. "" with an error in sc when
/// no group is left. With every 1 (the summary of a closed incident, Story 23.6), every group is listed with its Count, its count at the close, whether or not
/// it has a NoticeCount.
ClassMethod Groups(incident As OcuTalon.Data.Incident, groups As %ListOfObjects = "", Output sc As %Status, every As %Boolean = 0) As %DynamicArray
{
	Set sc = $$$OK
	If '$IsObject(groups) Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	Set lines = []
	For i = 1:1:groups.Count() {
		Set group = groups.GetAt(i)
		If (group.NoticeCount = "") && 'every Continue
		Do lines.%Push({"itemName": (group.ItemName), "count": (+$Select(every || (group.NoticeCount = ""): group.Count, 1: group.NoticeCount)), "errorSummary": ($Select(group.ErrorSummary '= "": group.ErrorSummary, 1: ..#NOERRORTEXT)), "firstAt": ($Select(group.FirstAt '= "": group.FirstAt, 1: incident.FirstAt))})
	}
	If lines.%Size() = 0 {
		Set sc = $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" has no failure group that settled")
		Quit ""
	}
	Quit lines
}

/// A model-written sentence as the slot takes it: trimmed; "" when there is none.
ClassMethod Text(value As %String) As %String [ Private ]
{
	Quit $ZStrip($Get(value), "<>W")
}

}
