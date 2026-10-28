/// The transform of OutcomeRouter's tell-now and act route (AD-14, AD-30, AD-32): an OcuTalon.Msg.ItemDecision becomes the
/// OcuTalon.Msg.Notification of kind tellnow for the owner's session, with the decision's DecisionRef. It renders no text; it
/// chooses the catalog key and its slots, in this order:
///   1. the ItemDecision has a CatalogKey: that key and its Slots, as they are (the key's text carries its "Why now:" line);
///   2. the ItemDecision is a fallback: notice.tellNowFallback with the slots whatHappened (the Summary) and reason (the
///      FallbackReason, unusable when it is empty or not in Msg.Enum FALLBACKREASON);
///   3. otherwise notice.tellNow with whatHappened (the Summary) and reason (the first line of the Reasons of the Decision row,
///      read through Ownership.Decision as the owner's own).
/// It returns an error status, and so no Notification, when the Summary is empty for case 2 or 3, when the Decision row is not
/// visible to the owner, or when its first reason line is empty. The router logs the error and sends nothing.
Class OcuTalon.Core.Rule.Notice Extends Ens.DataTransform
{

/// The catalog key of a tell-now notice with a model-written reason.
Parameter TELLNOWKEY = "notice.tellNow";

/// The catalog key of a tell-now notice whose decision is a fallback.
Parameter FALLBACKKEY = "notice.tellNowFallback";

Parameter ERRORSUMMARY = "The notice has no summary to say what happened.";

Parameter ERRORNODECISION = "The decision of the notice isn't one the owner can see.";

Parameter ERRORNOREASON = "The decision of the notice has no first reason line.";

ClassMethod Transform(source As %RegisteredObject, ByRef target As %RegisteredObject, ByRef aux) As %Status
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = source.OwnerRef
	Set notification.Kind = "tellnow"
	Set notification.DecisionRef = source.DecisionRef
	If source.CatalogKey '= "" {
		Set notification.CatalogKey = source.CatalogKey
		Set notification.Slots = source.Slots
		Set target = notification
		Quit $$$OK
	}
	If $ZStrip(source.Summary, "<>WC") = "" Quit $SYSTEM.Status.Error(5001, ..#ERRORSUMMARY)
	If source.Fallback {
		Set reason = source.FallbackReason
		If '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#FALLBACKREASON), reason) Set reason = "unusable"
		Set notification.CatalogKey = ..#FALLBACKKEY
	} Else {
		Set decision = ##class(OcuTalon.Data.Ownership).Decision(source.DecisionRef, source.OwnerRef, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
		If '$IsObject(decision) Quit $SYSTEM.Status.Error(5001, ..#ERRORNODECISION)
		Set reason = $ZStrip($Piece($Translate(decision.Reasons, $Char(13)), $Char(10), 1), "<>WC")
		If reason = "" Quit $SYSTEM.Status.Error(5001, ..#ERRORNOREASON)
		Set notification.CatalogKey = ..#TELLNOWKEY
	}
	Set notification.Slots = {"whatHappened": (source.Summary), "reason": (reason)}.%ToJSON()
	Set target = notification
	Quit $$$OK
}

}
