/// The transition table of an incident (AD-15; pure). It holds nothing: IncidentManager reads the rows, builds the facts from them (AD-11) and asks Next what
/// a move does. Next gives 1 for an accepted move and 0 for a refused one, and the target state, the open variant and which request gets an Execute.
///
/// Next(state, noticed, event, facts, .to, .variant, .execute): state is "" before the incident exists; noticed matters only for open; facts is a dynamic
/// object with the members variant (a notice's open variant), pending, waiting and demoMode (1 or 0; a member that is absent is 0). execute is OWN (the
/// event's own request), EARLIEST (the earliest waiting request) or "".
///
/// The rows (every other pair of state and event is refused, and so is every event on a closed incident):
///   - (none) + first -> open, no variant;
///   - open, not noticed + notice (variant fallback or no_fix) -> open with that variant;
///   - open, not noticed + raised -> awaiting_approval;
///   - awaiting_approval + approved -> fixing, execute own;
///   - awaiting_approval + rejected or expired -> open with the variant rejected or expired when pending is 0, else awaiting_approval;
///   - fixing + progress -> fixing;
///   - fixing + finished -> fixing with execute earliest when waiting is 1, else awaiting_approval when pending is 1, else resolved;
///   - fixing + approved, rejected or expired -> fixing (an approved request waits);
///   - awaiting_approval or resolved + raised -> awaiting_approval; fixing + raised -> fixing;
///   - resolved + dismiss, closeForReplay or closeQuiet -> closed;
///   - open, noticed + dismiss -> closed; open, noticed + closeQuiet -> closed only when demoMode is 0.
/// The variant is kept only while the target state is open: any other target clears it.
Class OcuTalon.Watch.Transitions
{

/// The states (Msg.Enum INCIDENTSTATE).
Parameter OPEN = "open";

Parameter AWAITING = "awaiting_approval";

Parameter FIXING = "fixing";

Parameter RESOLVED = "resolved";

Parameter CLOSED = "closed";

/// The events: the notice step, the raise of a request, the outcomes of a request, the reports of a run, and the three verbs of an incident command.
Parameter FIRST = "first";

Parameter NOTICE = "notice";

Parameter RAISED = "raised";

Parameter APPROVED = "approved";

Parameter REJECTED = "rejected";

Parameter EXPIRED = "expired";

Parameter PROGRESS = "progress";

Parameter FINISHED = "finished";

Parameter DISMISS = "dismiss";

Parameter CLOSEFORREPLAY = "closeForReplay";

Parameter CLOSEQUIET = "closeQuiet";

/// The open variants that a notice may give (Msg.Enum INCIDENTOPENVARIANT).
Parameter VARIANTFALLBACK = "fallback";

Parameter VARIANTNOFIX = "no_fix";

/// What execute says: the event's own request, or the earliest request that waits.
Parameter OWN = "own";

Parameter EARLIEST = "earliest";

/// Every event, in table order.
Parameter EVENTS = "first,notice,raised,approved,rejected,expired,progress,finished,dismiss,closeForReplay,closeQuiet";

/// The move that the event makes on the state: 1 when accepted, with the target state, the open variant and the execute choice; else 0 and all three empty.
ClassMethod Next(state As %String, noticed As %Boolean, event As %String, facts As %DynamicObject, Output to As %String, Output variant As %String, Output execute As %String) As %Boolean
{
	Set (to, variant, execute) = ""
	Set state = $Get(state)
	Set event = $Get(event)
	Set pending = 0
	Set waiting = 0
	Set demo = 0
	Set given = ""
	If $IsObject($Get(facts)) {
		Set pending = ''+facts.pending
		Set waiting = ''+facts.waiting
		Set demo = ''+facts.demoMode
		Set given = facts.variant
	}
	If state = "" {
		If event = ..#FIRST Set to = ..#OPEN
	} ElseIf state = ..#OPEN {
		If 'noticed {
			If (event = ..#NOTICE) && ((given = ..#VARIANTFALLBACK) || (given = ..#VARIANTNOFIX)) {
				Set to = ..#OPEN
				Set variant = given
			} ElseIf event = ..#RAISED {
				Set to = ..#AWAITING
			}
		} Else {
			If event = ..#DISMISS {
				Set to = ..#CLOSED
			} ElseIf (event = ..#CLOSEQUIET) && 'demo {
				Set to = ..#CLOSED
			}
		}
	} ElseIf state = ..#AWAITING {
		If event = ..#APPROVED {
			Set to = ..#FIXING
			Set execute = ..#OWN
		} ElseIf (event = ..#REJECTED) || (event = ..#EXPIRED) {
			If pending {
				Set to = ..#AWAITING
			} Else {
				Set to = ..#OPEN
				Set variant = event
			}
		} ElseIf event = ..#RAISED {
			Set to = ..#AWAITING
		}
	} ElseIf state = ..#FIXING {
		If (event = ..#PROGRESS) || (event = ..#APPROVED) || (event = ..#REJECTED) || (event = ..#EXPIRED) || (event = ..#RAISED) {
			Set to = ..#FIXING
		} ElseIf event = ..#FINISHED {
			If waiting {
				Set to = ..#FIXING
				Set execute = ..#EARLIEST
			} Else {
				Set to = $Select(pending: ..#AWAITING, 1: ..#RESOLVED)
			}
		}
	} ElseIf state = ..#RESOLVED {
		If event = ..#RAISED {
			Set to = ..#AWAITING
		} ElseIf (event = ..#DISMISS) || (event = ..#CLOSEFORREPLAY) || (event = ..#CLOSEQUIET) {
			Set to = ..#CLOSED
		}
	}
	Quit (to '= "")
}

}
