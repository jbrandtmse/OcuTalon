/// What the notice of an incident says, as catalog keys and slots written by code (pure; Story 5.8; AD-8, AD-15, AD-31, AD-32). The producer never
/// renders (OcuTalon.Msg.Catalog does that in the *Out operations): this class decides which key a settled incident gets and builds the slots of that key
/// from the incident row and its failure groups. It renders nothing, writes nothing and sends nothing; IncidentManager sends the notice.
///   - Key and Variant of a diagnosed incident (OcuTalon.Msg.Catalog.Watch):
///       Fallback 1 (any reason)                     incident.fallback       open variant fallback
///       usable, category unknown                    incident.noFixUnknown   open variant no_fix
///       usable, data_format_change (with a fix)     "" : no notice here; the with-fix notice goes out with the dry run and the approval request
///       usable, any other category                  incident.noFix          open variant no_fix
///   - Slots, by key: count is the incident's NoticeCount (its Count while that is empty), time its FirstAt and itemNoun its ItemNoun, else the code noun
///     of an empty body class. incident.noFix adds cause and groups, incident.noFixUnknown groups, incident.fallback fallbackReason (the row's reason, unusable
///     when it is empty or not a Msg.Enum FALLBACKREASON) and groups. WithFixSlots is the builder of the with-fix notice: count, time, itemNoun, cause and
///     fixSummary, and, given the dry run, its field, before, after and resendCount (the dry run's resend as an integer). A key given to Slots replaces Key(incident):
///     the incident.noFix notice of a data-format incident whose fix cannot be proposed (the dry run is refused, finds nothing to resend, or its request is not raised).
///   - The later request (Story 7.6, KEYLATER incident.laterRequest) takes the with-fix slots with its own round's count and time: WithFixSlots given a count and a
///     time replaces the slots count and time (the failures of the round, and the first of them), and renders "{count} more {itemNoun} failed since {time}, with
///     the same cause ...". It carries the cause slot too, which the catalog ignores.
///   - groups holds one {itemName, count, errorSummary, firstAt} per failure group that has a NoticeCount, in Seq order. A group's count is its
///     NoticeCount, so the lines add up to the count slot even when failures joined during the diagnosis. An empty error summary is written as NOERRORTEXT.
/// Slots and WithFixSlots give "" with an error status in sc where the slots cannot be built (no group, an empty cause, an empty time, a dry run without its
/// field, before or after or with a resend below 1, a given count below 1 or not a whole number, a given time that is empty).
Class OcuTalon.Watch.Notice
{

/// The catalog keys of the notices.
Parameter KEYFALLBACK = "incident.fallback";

Parameter KEYUNKNOWN = "incident.noFixUnknown";

Parameter KEYNOFIX = "incident.noFix";

Parameter KEYWITHFIX = "incident.withFix";

/// The catalog key of the notice of a later request in the same incident (Story 7.6).
Parameter KEYLATER = "incident.laterRequest";

/// The open variants (Msg.Enum INCIDENTOPENVARIANT).
Parameter VARIANTFALLBACK = "fallback";

Parameter VARIANTNOFIX = "no_fix";

/// The cause category that has a fix to propose, and the one that has no cause.
Parameter WITHFIXCATEGORY = "data_format_change";

Parameter UNKNOWNCATEGORY = "unknown";

/// The fallback reason of a reason that is empty or not one of Msg.Enum FALLBACKREASON.
Parameter UNUSABLE = "unusable";

/// The summary of a group whose error text is empty: the catalog needs a text, and the line stays (public text, veto U-94).
Parameter NOERRORTEXT = "no error text";

/// The catalog key of the notice for the diagnosed incident, "" when it gets none from this class (a usable data-format diagnosis: its notice is the
/// with-fix notice, KEYWITHFIX).
ClassMethod Key(incident As OcuTalon.Data.Incident) As %String
{
	If incident.Fallback Quit ..#KEYFALLBACK
	If incident.CauseCategory = ..#UNKNOWNCATEGORY Quit ..#KEYUNKNOWN
	If incident.CauseCategory = ..#WITHFIXCATEGORY Quit ""
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
	If key = ..#KEYNOFIX {
		Set cause = ..Text(incident.Cause)
		If cause = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" has no cause")
			Quit ""
		}
		Do slots.%Set("cause", cause)
	}
	Set lines = ..Groups(incident, groups, .sc)
	If $$$ISERR(sc) Quit ""
	Do slots.%Set("groups", lines)
	Quit slots
}

/// The slots of the with-fix notice that the incident's diagnosis gives: count, time, itemNoun, cause and fixSummary. Given the dry run (a dynamic object with the
/// keys of ApprovalRequest DRYRUNKEYS), it adds field, before, after and resendCount (the dry run's resend as an integer). "" with the reason in sc when the cause
/// or the fix summary is empty, or when the dry run has no field, before or after, or a resend below 1. A count given (a whole number of at least 1) replaces the
/// count slot and a time given (not empty) replaces the time slot: the failures of a later round and the first of them (an argument that is passed counts as
/// given, also when it is empty; an argument that is left out does not).
ClassMethod WithFixSlots(incident As OcuTalon.Data.Incident, Output sc As %Status, dryRun As %DynamicObject = "", count As %Integer, time As %String) As %DynamicObject
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
	}
	Quit slots
}

/// The slots every notice has: count, time and itemNoun.
ClassMethod Common(incident As OcuTalon.Data.Incident, Output sc As %Status) As %DynamicObject [ Private ]
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

/// The fallback reason of the incident as the catalog takes it: its own when it is one of Msg.Enum FALLBACKREASON, else unusable.
ClassMethod Reason(incident As OcuTalon.Data.Incident) As %String
{
	Set reason = incident.FallbackReason
	If (reason '= "") && $ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#FALLBACKREASON), reason) Quit reason
	Quit ..#UNUSABLE
}

/// The groups slot: one {itemName, count, errorSummary, firstAt} per group that has a NoticeCount, in the order of the list. "" with an error in sc when
/// no group is left.
ClassMethod Groups(incident As OcuTalon.Data.Incident, groups As %ListOfObjects = "", Output sc As %Status) As %DynamicArray
{
	Set sc = $$$OK
	If '$IsObject(groups) Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	Set lines = []
	For i = 1:1:groups.Count() {
		Set group = groups.GetAt(i)
		If group.NoticeCount = "" Continue
		Do lines.%Push({"itemName": (group.ItemName), "count": (+group.NoticeCount), "errorSummary": ($Select(group.ErrorSummary '= "": group.ErrorSummary, 1: ..#NOERRORTEXT)), "firstAt": ($Select(group.FirstAt '= "": group.FirstAt, 1: incident.FirstAt))})
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
