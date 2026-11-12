Include Ensemble

/// SessionOps, the business operation that carries out the session commands Pair, Unpair, EndSession and GotIt (AD-1, AD-4, AD-12, AD-14, AD-17, AD-32).
/// It is the only writer of a chat row's SessionRef (Data.Pairing), the only code that marks a pairing code used, and the only publisher of
/// the pairing live event. It compares hashes only: a pairing code never reaches it (AD-4). Its answer is always a CommandResult; the
/// Telegram service that sent the command writes the reply from the outcome.
///   - Pair {CodeHash, ChatRef}, origin telegram only. In order it finds the chat row, then the code row of the hash, then the session
///     row of the code. The outcomes are paired, unknown_chat, unknown_code (also a code whose session is gone), used_code, expired_code
///     and failed. A used code repeated by the chat that is already on its session is paired and changes nothing. A chat that pairs
///     with another session leaves its old session (reason moved, no notice), and a session that already has another chat drops that
///     chat (reason other_chat, with the notice pairing.otherChatPaired). Then the linked audit entry is written, and only after it the
///     chat row gets its SessionRef and the code row its used mark. The pairing event follows the save.
///   - Unpair {ChatRef}. From telegram (the /stop command) it unlinks the chat's own session. From any other origin it unlinks the
///     command's session, whose paired chat must be the ChatRef when one is given, with the notice pairing.unpairedFromPage. The outcomes
///     are unpaired and not_paired (Ok 0, nothing changed, nothing audited).
///   - EndSession {SessionRef} ends an online-demo session (Story 16.4; AD-4): the page's Sign out, through POST /v1/session/end. In order,
///     and each of the first seven steps is tried even when an earlier one failed: Unlink of the session's chat (reason session_end, no
///     notice); one CancelReminder for each pending reminder, sent to ReminderOps; one StopWatch for each production watch, sent to WatchOps;
///     Approval.Cancel for each pending approval request the session owns; SettingsOps.ForgetPerson for the session's per-person
///     values (AD-19): the persona keys and the five heartbeat keys; Data.Handled.DropSession for the session's Handled rows; one EndSession
///     to PrecedentOps for the session's precedents, always sent, so that the drop queues behind every write already queued (AD-21). Only when all
///     of them succeeded is the row's ResumeHash cleared, so that a resume cookie that outlives the sign-out resumes nothing; after a failed
///     End the session stays resumable and the visitor can end
///     it again. The outcomes are ended (Ok 1; a repeat changes nothing and also answers ended), failed (Ok 0, after the first seven steps were
///     tried) and no_session (Ok 0, the session has no row). The session's conversation, orders and decisions stay with the row.
///   - GotIt {Ref, Channel} marks one of the session's own tell-now notices as handled (AD-14; Story 12.12). In order it checks that the
///     Channel is a Msg.Enum CHANNEL value, that the Ref is a reference, that the session's own Decision (Data.Ownership.Decision, compared by
///     its exact Ref) has that Ref and its Outcome is tellnow. Any of them failing is not_found (Ok 0, nothing written, nothing sent), so
///     another session's notice answers like a missing one. A notice that Data.Handled already marks is already_handled (Ok 1, nothing
///     changed; the first press wins through the table's unique Ref). Otherwise one Handled row {Ref, SessionRef, now, Channel} is saved and
///     one Notification of kind handled, with the Decision's Ref and no text, goes to Notify, so that each channel updates its copy of
///     the notice; a failed send is a warning and the marker stands. A save that fails while the Ref is still not marked is failed (Ok 0).
/// Every pair outcome is audited as a Pairing entry (linked or rejected) through Bridge.Audit.Record, and every unlink as an unlinked
/// entry, with the session's IRIS user (else the job's user), the session, the channel of the command's origin and no chat id or display
/// name. A link needs its audit entry: when the entry can't be written nothing links and the outcome is failed, and a chat that the pair had already dropped stays dropped. An unlink stands when its
/// audit entry, its notice or its event fails; the failure is a warning. A notice is a Notification of kind pairing with the dropped
/// chat's ChatRef, a catalog key and no text; Notify decides where it goes. An error thrown while carrying out a command is logged and
/// answers failed. The pool of the item is 1, so its commands are handled one at a time.
/// Unlink is the one way a chat is unlinked, and End calls it.
/// From step 3, End first drops the session's documents, memories and uploads (OcuTalon.Docs.DropSession, OcuTalon.Memory.DropSession and OcuTalon.Data.Upload.DropSession, AD-4, AD-21).
Class OcuTalon.Core.SessionOps Extends Ens.BusinessOperation
{

/// The item that routes a notification.
Parameter NOTIFYITEM = "Notify";

/// The audit channel of each command origin.
Parameter CHANNELS = "telegram:telegram,web_user:web,web_admin:web,timer:system,system:system";

/// The Message of each outcome. The messages are for the model and the logs and are never shown as written.
Parameter MESSAGEPAIRED = "The chat is paired with the session.";

Parameter MESSAGEUNKNOWNCODE = "That pairing code is not known, so nothing was linked.";

Parameter MESSAGEEXPIREDCODE = "That pairing code has expired, so nothing was linked.";

Parameter MESSAGEUSEDCODE = "That pairing code was already used, so nothing was linked.";

Parameter MESSAGEUNKNOWNCHAT = "That chat is not known, so nothing was linked.";

Parameter MESSAGEUNPAIRED = "The chat is no longer paired with the session.";

Parameter MESSAGENOTPAIRED = "No chat is paired, so nothing was changed.";

Parameter MESSAGEENDED = "The session was ended.";

Parameter MESSAGENOSESSION = "That session is not known, so nothing was ended.";

Parameter MESSAGEHANDLED = "The notice is marked as handled.";

Parameter MESSAGEALREADYHANDLED = "The notice was already marked as handled, so nothing was changed.";

Parameter MESSAGENOTICENOTFOUND = "That notice is not known, so nothing was marked.";

/// The item that carries out the reminder commands End sends.
Parameter REMINDERITEM = "ReminderOps";

/// The item that carries out the watch commands End sends.
Parameter WATCHITEM = "WatchOps";

/// The item that deletes the session's precedents at End.
Parameter PRECEDENTITEM = "PrecedentOps";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Set command = $Get(pRequest)
	Set class = $Select($IsObject(command): $ClassName(command), 1: "")
	If '$ListFind($ListBuild("OcuTalon.Msg.Command.Pair", "OcuTalon.Msg.Command.Unpair", "OcuTalon.Msg.Command.EndSession", "OcuTalon.Msg.Command.GotIt"), class) {
		$$$LOGERROR("OcuTalon.Core.SessionOps: it carries out no " _ $Select(class = "": "message that is not an object", 1: class))
		Quit $SYSTEM.Status.Error(5001, "SessionOps carries out only Pair, Unpair, EndSession and GotIt")
	}
	Try {
		Set pResponse = $Case(class, "OcuTalon.Msg.Command.Pair": ..Pair(command), "OcuTalon.Msg.Command.Unpair": ..Unpair(command), "OcuTalon.Msg.Command.GotIt": ..GotIt(command), : ..End(command))
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set pResponse = ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// Unlinks the session's paired chat, the one way a chat is unlinked (a /stop, a page Unpair, a move, a second chat, and Story 16.4's
/// session end):
///   - sessionRef is required. chatRef is "" for the session's live pairing (Data.Ownership), or the Ref of that chat: any other
///     ChatRef unlinks nothing.
///   - reason is the audit entry's reason. channel is a Msg.Enum CHANNEL value and is checked before anything changes.
///   - noticeKey is "" for no notice, or a catalog key: one Notification of kind pairing, with the dropped chat's ChatRef, goes to Notify.
/// When a chat is unlinked, in order: the chat row's SessionRef is cleared (the row stays, so that the Telegram sender can still resolve
/// the ChatRef), one unlinked audit entry is written with the session's IRIS user (else the job's user), the notice is sent, one pairing
/// event (not paired) is published to the session, and changed is 1. A failed audit entry, notice or event is a warning and the unlink
/// stands. Nothing to unlink is OK with changed 0. An error status means that nothing changed.
Method Unlink(sessionRef As %String, chatRef As %String, reason As %String, channel As %String, noticeKey As %String = "", Output changed As %Boolean) As %Status
{
	Set changed = 0
	Set sessionRef = $Get(sessionRef), chatRef = $Get(chatRef), reason = $Get(reason), channel = $Get(channel), noticeKey = $Get(noticeKey)
	If sessionRef = "" Quit $SYSTEM.Status.Error(5001, "An unlink needs the session: the session is empty")
	If reason = "" Quit $SYSTEM.Status.Error(5001, "An unlink needs a reason: the reason is empty")
	Set channels = ##class(OcuTalon.Msg.Enum).#CHANNEL
	If '$ListFind($ListFromString(channels), channel) Quit $SYSTEM.Status.Error(5001, "The channel of an unlink is one of " _ channels)
	Set paired = ##class(OcuTalon.Data.Ownership).Pairing(sessionRef, .sc)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(paired) Quit $$$OK
	If (chatRef '= "") && (paired.Ref '= chatRef) Quit $$$OK
	Set id = paired.%Id(), dropped = paired.Ref
	Set paired = ""
	Set row = ##class(OcuTalon.Data.Pairing).%OpenId(id, 4, .sc)
	If '$IsObject(row) Quit $Select($$$ISERR(sc): sc, 1: $SYSTEM.Status.Error(5001, "The paired chat's row could not be opened"))
	If row.SessionRef '= sessionRef Quit $$$OK
	Set row.SessionRef = ""
	Set row.SeenAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	Set row = ""
	If $$$ISERR(sc) Quit sc
	Set changed = 1
	Set written = ..WriteAudit(..AuditData("unlinked", reason, ..IrisUser(sessionRef), sessionRef, channel))
	If $$$ISERR(written) {
		$$$LOGWARNING("OcuTalon.Core.SessionOps: the unlinked audit entry of session " _ sessionRef _ " was not written: " _ $SYSTEM.Status.GetErrorText(written))
	}
	If noticeKey '= "" {
		Set notification = ##class(OcuTalon.Msg.Notification).%New()
		Set notification.SessionRef = sessionRef
		Set notification.ChatRef = dropped
		Set notification.Kind = "pairing"
		Set notification.CatalogKey = noticeKey
		Set notification.Slots = "{}"
		Set sent = ..SendNotice(notification)
		If $$$ISERR(sent) {
			$$$LOGWARNING("OcuTalon.Core.SessionOps: the notice " _ noticeKey _ " of session " _ sessionRef _ " was not sent: " _ $SYSTEM.Status.GetErrorText(sent))
		}
	}
	Do ..Announce(sessionRef, 0, "")
	Quit $$$OK
}

/// Carries out a Pair command and returns the CommandResult to answer.
Method Pair(command As OcuTalon.Msg.Command.Pair) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set channel = ..ChannelOf(command.Origin)
	Set chat = ##class(OcuTalon.Data.Pairing).Chat(command.ChatRef)
	If '$IsObject(chat) Quit ..Reject("unknown_chat", "unknown_chat", "", channel)
	Set code = ##class(OcuTalon.Data.Pairing).ForCode(command.CodeHash)
	If '$IsObject(code) Quit ..Reject("unknown_code", "unknown", "", channel)
	Set session = code.CodeSessionRef
	If code.CodeUsedAt '= "" {
		If chat.SessionRef = session Quit ..Result(1, "paired", ..#MESSAGEPAIRED)
		Quit ..Reject("used_code", "used", session, channel)
	}
	Set expires = ##class(OcuTalon.Data.Time).Seconds(code.CodeExpiresAt)
	If (expires = "") || (expires <= ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())) Quit ..Reject("expired_code", "expired", session, channel)
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(session)) Quit ..Reject("unknown_code", "unknown", "", channel)
	Set chatId = chat.%Id(), chatRef = chat.Ref, codeId = code.%Id(), oldSession = chat.SessionRef
	Set (chat, code) = ""
	If (oldSession '= "") && (oldSession '= session) {
		Set sc = ..Unlink(oldSession, chatRef, "moved", channel, "", .changed)
		If $$$ISERR(sc) Quit ..Failed("the chat could not leave its session", sc)
	}
	Set other = ##class(OcuTalon.Data.Ownership).Pairing(session, .sc)
	If $$$ISERR(sc) Quit ..Failed("the session's paired chat could not be read", sc)
	If $IsObject(other) {
		Set otherId = other.%Id(), otherRef = other.Ref
		Set other = ""
		If otherId '= chatId {
			Set sc = ..Unlink(session, otherRef, "other_chat", channel, "pairing.otherChatPaired", .changed)
			If $$$ISERR(sc) Quit ..Failed("the session's other chat could not be dropped", sc)
		}
	}
	Set sc = ..WriteAudit(..AuditData("linked", "code", ..IrisUser(session), session, channel))
	If $$$ISERR(sc) Quit ..Failed("the linked audit entry was not written, so nothing was linked", sc)
	Set sc = ..Link(chatId, codeId, session, .name)
	If $$$ISERR(sc) Quit ..Failed("the chat could not be linked", sc)
	Do ..Announce(session, 1, name)
	Quit ..Result(1, "paired", ..#MESSAGEPAIRED)
}

/// Links the chat row to the session and marks the code row used, in one transaction, and returns the chat's display name. Nothing is
/// published here.
Method Link(chatId As %String, codeId As %String, session As %String, Output name As %String) As %Status [ Private ]
{
	Set name = ""
	Set sc = $$$OK
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set level = $TLevel
	TSTART
	Try {
		Set chat = ##class(OcuTalon.Data.Pairing).%OpenId(chatId, 4, .sc)
		If '$IsObject(chat) {
			If $$$ISOK(sc) Set sc = $SYSTEM.Status.Error(5001, "The chat's row could not be opened")
			Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		}
		Set code = ##class(OcuTalon.Data.Pairing).%OpenId(codeId, 4, .sc)
		If '$IsObject(code) {
			If $$$ISOK(sc) Set sc = $SYSTEM.Status.Error(5001, "The code's row could not be opened")
			Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		}
		Set chat.SessionRef = session
		Set chat.SeenAt = now
		Set sc = chat.%Save()
		If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Set code.CodeUsedAt = now
		Set sc = code.%Save()
		If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Set name = chat.DisplayName
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
		Set name = ""
	}
	If $TLevel > level TROLLBACK 1
	Quit sc
}

/// Carries out an Unpair command and returns the CommandResult to answer: from Telegram the chat's own session is unlinked, from any other
/// origin the command's session is.
Method Unpair(command As OcuTalon.Msg.Command.Unpair) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set channel = ..ChannelOf(command.Origin)
	Set changed = 0
	If command.Origin = "telegram" {
		Set chat = ##class(OcuTalon.Data.Pairing).Chat(command.ChatRef)
		If '$IsObject(chat) || (chat.SessionRef = "") Quit ..Result(0, "not_paired", ..#MESSAGENOTPAIRED)
		Set session = chat.SessionRef, ref = chat.Ref
		Set chat = ""
		Set sc = ..Unlink(session, ref, "stop", channel, "", .changed)
	} Else {
		Set sc = ..Unlink(command.SessionRef, command.ChatRef, "page", channel, "pairing.unpairedFromPage", .changed)
	}
	If $$$ISERR(sc) Quit ..Failed("the chat could not be unlinked", sc)
	If changed Quit ..Result(1, "unpaired", ..#MESSAGEUNPAIRED)
	Quit ..Result(0, "not_paired", ..#MESSAGENOTPAIRED)
}

/// Carries out a GotIt command and returns the CommandResult to answer (see the class description). The answers are handled and
/// already_handled (Ok 1), not_found (Ok 0: a Channel that is not a CHANNEL value, a Ref that is not a reference or names no tell-now
/// Decision of the session) and failed (Ok 0: a read or save error that left the notice unmarked).
Method GotIt(command As OcuTalon.Msg.Command.GotIt) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set ref = command.Ref
	If '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#CHANNEL), command.Channel) Quit ..Result(0, "not_found", ..#MESSAGENOTICENOTFOUND)
	If '##class(OcuTalon.Bridge.Approval).IsRef(ref) Quit ..Result(0, "not_found", ..#MESSAGENOTICENOTFOUND)
	Set decision = ##class(OcuTalon.Data.Ownership).Decision(ref, command.SessionRef, .sc)
	If $$$ISERR(sc) Quit ..Failed("the notice could not be read", sc)
	If '$IsObject(decision) Quit ..Result(0, "not_found", ..#MESSAGENOTICENOTFOUND)
	If (decision.Ref '= ref) || (decision.Outcome '= "tellnow") Quit ..Result(0, "not_found", ..#MESSAGENOTICENOTFOUND)
	Set ref = decision.Ref
	Set decision = ""
	If ##class(OcuTalon.Data.Handled).RefIndexExists(ref) Quit ..Result(1, "already_handled", ..#MESSAGEALREADYHANDLED)
	Set sc = ..SaveHandled(ref, command.SessionRef, command.Channel)
	If $$$ISERR(sc) {
		If ##class(OcuTalon.Data.Handled).RefIndexExists(ref) Quit ..Result(1, "already_handled", ..#MESSAGEALREADYHANDLED)
		Quit ..Failed("the notice could not be marked as handled", sc)
	}
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = command.SessionRef
	Set notification.Kind = "handled"
	Set notification.DecisionRef = ref
	Set notification.CatalogKey = ""
	Set notification.Slots = "{}"
	Set sent = ..SendNotice(notification)
	If $$$ISERR(sent) Do ..Warn("the handled notice of session " _ command.SessionRef _ " was not sent", sent)
	Quit ..Result(1, "handled", ..#MESSAGEHANDLED)
}

/// Carries out an EndSession command and returns the CommandResult to answer (see the class description). The document, memory and upload drops,
/// Unlink, the reminders, the watches, the approval requests, the per-person settings, the Handled rows and the precedents each run even when an earlier one failed or threw, and a failure is a
/// warning with the step's reason; the resume hash is cleared last, and only when none of them failed, so a failed End leaves the session
/// resumable.
Method End(command As OcuTalon.Msg.Command.EndSession) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sessionRef = command.SessionRef
	Set row = $Select(sessionRef = "": "", 1: ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef))
	If '$IsObject(row) Quit ..Result(0, "no_session", ..#MESSAGENOSESSION)
	Set row = ""
	Set channel = ..ChannelOf(command.Origin)
	Set failed = ..EndDocumentsAndMemories(sessionRef)
	Try {
		Set sc = ..Unlink(sessionRef, "", "session_end", channel, "", .changed)
		If $$$ISERR(sc) Set failed = 1 Do ..Warn("the chat could not be unlinked at the end of session " _ sessionRef, sc)
	} Catch exception {
		Set failed = 1
		Do ..Warn("the chat could not be unlinked at the end of session " _ sessionRef, exception.AsStatus())
	}
	Set failed = ..EndReminders(command) + ..EndWatches(command) + ..EndApprovals(sessionRef, channel) + ..EndSettings(sessionRef) + ..EndHandled(sessionRef) + ..EndPrecedents(command) + failed
	If 'failed Set failed = ..EndResume(sessionRef)
	Quit $Select(failed: ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED), 1: ..Result(1, "ended", ..#MESSAGEENDED))
}

/// End's reminders: one CancelReminder for each pending reminder of the session, sent to the ReminderOps item. The result is the
/// number of reminders that could not be cancelled (a failed answer, an error status or an error thrown); a reminder that is no longer
/// pending when its command arrives is not a failure.
Method EndReminders(command As OcuTalon.Msg.Command.EndSession) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set rows = ##class(OcuTalon.Data.Ownership).Reminders(command.SessionRef, .sc)
		If $$$ISERR($Get(sc, 1)) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		For i = 1:1:rows.Count() {
			Set cancel = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
			Set cancel.SessionRef = command.SessionRef
			Set cancel.Origin = command.Origin
			Set cancel.ReminderRef = rows.GetAt(i).Ref
			Set failed = failed + ..Carry(..#REMINDERITEM, cancel, "a reminder of session " _ command.SessionRef _ " was not cancelled")
		}
	} Catch exception {
		Set failed = failed + 1
		Do ..Warn("the reminders of session " _ command.SessionRef _ " could not be read", exception.AsStatus())
	}
	Quit failed
}

/// End's watches: one StopWatch for each production watch and for the queue-backlog check of the session (with the row's Kind), sent to the
/// WatchOps item. The result is the number of watches that could not be stopped; a watch that is already gone is not a failure.
Method EndWatches(command As OcuTalon.Msg.Command.EndSession) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set rows = ##class(OcuTalon.Data.Ownership).Checks(command.SessionRef, .sc)
		If $$$ISERR($Get(sc, 1)) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		For i = 1:1:rows.Count() {
			Set check = rows.GetAt(i)
			If (check.Kind '= ##class(OcuTalon.Watch.Ops).#KIND) && (check.Kind '= ##class(OcuTalon.Watch.Ops).#QUEUEKIND) Continue
			Set stop = ##class(OcuTalon.Msg.Command.StopWatch).%New()
			Set stop.SessionRef = command.SessionRef
			Set stop.Origin = command.Origin
			Set stop.Kind = check.Kind
			Set stop.Namespace = check.Namespace
			Set stop.Production = check.Production
			Set failed = failed + ..Carry(..#WATCHITEM, stop, "a watch of session " _ command.SessionRef _ " was not stopped")
		}
	} Catch exception {
		Set failed = failed + 1
		Do ..Warn("the watches of session " _ command.SessionRef _ " could not be read", exception.AsStatus())
	}
	Quit failed
}

/// End's approval requests: Approval.Cancel (the one way a request is cancelled, AD-11) for each pending request that the session owns,
/// naming the session's IRIS user, the channel and the session in the Approval entry. The result is the number of requests that could
/// not be cancelled; a request that was answered meanwhile is not a failure.
Method EndApprovals(sessionRef As %String, channel As %String) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set rows = ##class(OcuTalon.Data.Ownership).Approvals(sessionRef, .sc)
		If $$$ISERR($Get(sc, 1)) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Set irisUser = ..IrisUser(sessionRef)
		For i = 1:1:rows.Count() {
			Set request = rows.GetAt(i)
			If request.OwnerRef '= sessionRef Continue
			Set ref = request.Ref
			Set sc = ##class(OcuTalon.Bridge.Approval).Cancel(ref, "", channel, irisUser, sessionRef)
			If $$$ISERR(sc) {
				Set current = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
				If '$IsObject(current) || (current.State = "pending") {
					Set failed = failed + 1
					Do ..Warn("a request of session " _ sessionRef _ " was not cancelled", sc)
				}
			}
		}
	} Catch exception {
		Set failed = failed + 1
		Do ..Warn("the requests of session " _ sessionRef _ " could not be read", exception.AsStatus())
	}
	Quit failed
}

/// End's per-person settings: Forget deletes every per-person value of the session (AD-19), the persona's keys included. The
/// result is 1 when they could not be deleted (an error status or an error thrown), 0 otherwise.
Method EndSettings(sessionRef As %String) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set sc = ..Forget(sessionRef)
		If $$$ISERR(sc) {
			Set failed = 1
			Do ..Warn("the per-person settings of session " _ sessionRef _ " were not deleted", sc)
		}
	} Catch exception {
		Set failed = 1
		Do ..Warn("the per-person settings of session " _ sessionRef _ " were not deleted", exception.AsStatus())
	}
	Quit failed
}

/// The one call of End's per-person settings step, SettingsOps.ForgetPerson. Private, so that a test subclass can override it.
Method Forget(sessionRef As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.SettingsOps).ForgetPerson(sessionRef)
}

/// End's Handled step: the session's Handled rows are deleted. The result is 1 when the delete failed (an error status or an error thrown), a
/// warning with the reason, else 0.
Method EndHandled(sessionRef As %String) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set sc = ..DropHandled(sessionRef)
		If $$$ISERR(sc) {
			Set failed = 1
			Do ..Warn("the handled marks of session " _ sessionRef _ " were not deleted", sc)
		}
	} Catch exception {
		Set failed = 1
		Do ..Warn("the handled marks of session " _ sessionRef _ " were not deleted", exception.AsStatus())
	}
	Quit failed
}

/// End's precedents step: one EndSession always goes to PrecedentOps, which deletes the session's rows; sent even for a session with no rows, so that the
/// drop queues behind every write already queued. The result is 1 when the drop failed (an error status, a failed answer or an error thrown), a warning with the reason, else 0.
Method EndPrecedents(command As OcuTalon.Msg.Command.EndSession) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set drop = ##class(OcuTalon.Msg.Command.EndSession).%New()
		Set drop.SessionRef = command.SessionRef
		Set drop.Origin = command.Origin
		Set failed = ..DropPrecedents(drop)
	} Catch exception {
		Set failed = 1
		Do ..Warn("the precedents of session " _ command.SessionRef _ " were not deleted", exception.AsStatus())
	}
	Quit failed
}

/// The one call that sends the EndSession to PrecedentOps (Lane B; a seam for the tests). The result is 0 when the precedents were deleted, else 1.
Method DropPrecedents(request As OcuTalon.Msg.Command.EndSession) As %Integer [ Private ]
{
	Quit ..Carry(..#PRECEDENTITEM, request, "the precedents of session " _ request.SessionRef _ " were not deleted")
}

/// The one call that saves a Handled row {ref, sessionRef, now, channel} (a seam for the tests). The unique Ref makes the first save win.
Method SaveHandled(ref As %String, sessionRef As %String, channel As %String) As %Status [ Private ]
{
	Set row = ##class(OcuTalon.Data.Handled).%New()
	Set row.Ref = ref
	Set row.SessionRef = sessionRef
	Set row.HandledAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.Channel = channel
	Quit row.%Save()
}

/// The one call that deletes a session's Handled rows (Lane B; a seam for the tests).
Method DropHandled(sessionRef As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Data.Handled).DropSession(sessionRef)
}

/// End's last step, run only when every earlier step succeeded: the row's ResumeHash is cleared (saved only when it holds one). The result
/// is 1 when the row could not be saved.
Method EndResume(sessionRef As %String) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef, 4, .sc)
		If '$IsObject(row) {
			Set failed = 1
			Do ..Warn("the session " _ sessionRef _ " could not be opened to clear its resume hash", $Get(sc, $$$OK))
		} ElseIf row.ResumeHash '= "" {
			Set row.ResumeHash = ""
			Set sc = row.%Save()
			If $$$ISERR(sc) Set failed = 1 Do ..Warn("the resume hash of session " _ sessionRef _ " was not cleared", sc)
		}
	} Catch exception {
		Set failed = 1
		Do ..Warn("the resume hash of session " _ sessionRef _ " was not cleared", exception.AsStatus())
	}
	Quit failed
}

/// Sends a command to an owner item of the production, synchronously, and returns 0 when the owner carried it out or had nothing to do,
/// else 1 (a status error, an answer that is not a CommandResult, or the outcome failed), with the reason logged as a warning.
Method Carry(target As %String, request As OcuTalon.Msg.Command, reason As %String) As %Integer [ Private ]
{
	Try {
		Set sc = ..SendRequestSync(target, request, .response, ##class(OcuTalon.Core.CommandsIn).#TIMEOUT)
		If $$$ISOK(sc) {
			If '$IsObject($Get(response)) || 'response.%IsA("OcuTalon.Msg.CommandResult") {
				Set sc = $SYSTEM.Status.Error(5001, "The owner answered no CommandResult")
			} ElseIf response.Outcome = "failed" {
				Set sc = $SYSTEM.Status.Error(5001, "The owner answered failed")
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISOK(sc) Quit 0
	Do ..Warn(reason, sc)
	Quit 1
}

/// A warning with the reason and the status text (which holds no chat id and no name).
Method Warn(reason As %String, sc As %Status) [ Private ]
{
	$$$LOGWARNING("OcuTalon.Core.SessionOps: " _ reason _ ": " _ $SYSTEM.Status.GetErrorText(sc))
}

/// A rejected pair: one rejected audit entry with the reason, and the CommandResult of the outcome (Ok 0). Nothing is linked. A failed
/// audit entry is a warning.
Method Reject(outcome As %String, reason As %String, sessionRef As %String, channel As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sc = ..WriteAudit(..AuditData("rejected", reason, ..IrisUser(sessionRef), sessionRef, channel))
	If $$$ISERR(sc) {
		$$$LOGWARNING("OcuTalon.Core.SessionOps: the rejected audit entry (" _ reason _ ") was not written: " _ $SYSTEM.Status.GetErrorText(sc))
	}
	Quit ..Result(0, outcome, $Parameter("OcuTalon.Core.SessionOps", "MESSAGE" _ $ZConvert($Translate(outcome, "_"), "U")))
}

/// The failed answer: the reason is logged as a warning, with the status text (which holds no chat id and no name), and the CommandResult
/// is failed.
Method Failed(reason As %String, sc As %Status) As OcuTalon.Msg.CommandResult [ Private ]
{
	$$$LOGWARNING("OcuTalon.Core.SessionOps: " _ reason _ ": " _ $SYSTEM.Status.GetErrorText(sc))
	Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
}

/// Publishes the pairing event to the session's stream: the full current view, outside any transaction and after the row is saved. A
/// failed publish is a warning.
Method Announce(sessionRef As %String, paired As %Boolean, displayName As %String) [ Private ]
{
	Set payload = ##class(OcuTalon.Live.Payload.Pairing).%New()
	Set payload.Paired = paired
	Set payload.DisplayName = displayName
	Set sc = ##class(OcuTalon.Live.Publish).Publish(sessionRef, "pairing", payload, .seq)
	If $$$ISERR(sc) {
		$$$LOGWARNING("OcuTalon.Core.SessionOps: the pairing event of session " _ sessionRef _ " was not published: " _ $SYSTEM.Status.GetErrorText(sc))
	}
}

/// The audit channel of the origin, or "" for an origin that is not in CHANNELS.
ClassMethod ChannelOf(origin As %String) As %String [ Private ]
{
	Quit $Piece($Piece("," _ ..#CHANNELS, "," _ origin _ ":", 2), ",", 1)
}

/// The IRIS user for the session's audit entries: the session's IrisUser, else the user of this job.
ClassMethod IrisUser(sessionRef As %String) As %String [ Private ]
{
	Set session = $Select(sessionRef = "": "", 1: ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef))
	Quit $Select($IsObject(session) && (session.IrisUser '= ""): session.IrisUser, 1: $Username)
}

/// The audit event data of a Pairing entry, in the shape of Bridge.Audit.Record: change, reason, irisUser, sessionRef and channel, each typed
/// as a JSON string, and no chat id and no display name.
ClassMethod AuditData(change As %String, reason As %String, irisUser As %String, sessionRef As %String, channel As %String) As %DynamicObject [ Private ]
{
	Set data = {}
	Do data.%Set("change", change, "string")
	Do data.%Set("reason", reason, "string")
	Do data.%Set("irisUser", irisUser, "string")
	Do data.%Set("sessionRef", sessionRef, "string")
	Do data.%Set("channel", channel, "string")
	Quit data
}

/// The one audit write of the class: an entry of type Pairing, through the one writer of product code. A test subclass overrides it.
Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("Pairing", data)
}

/// Sends the notification to the Notify item, asynchronously, with no answer wanted (a seam for the tests).
Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#NOTIFYITEM, notification, 0)
}

/// A CommandResult with the outcome and the message.
ClassMethod Result(ok As %Boolean, outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = ok
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

/// End's step 3 drops: the session's documents, then its memories, then its uploads (the bytes of files not yet taken by DocumentOps), each in its own Try. The result is the number of drops that failed
/// (an error status or an error thrown), each a warning.
Method EndDocumentsAndMemories(sessionRef As %String) As %Integer [ Private ]
{
	Set failed = 0
	Try {
		Set sc = ..DropDocuments(sessionRef)
		If $$$ISERR(sc) Set failed = failed + 1 Do ..Warn("the documents of session " _ sessionRef _ " could not be dropped", sc)
	} Catch exception {
		Set failed = failed + 1
		Do ..Warn("the documents of session " _ sessionRef _ " could not be dropped", exception.AsStatus())
	}
	Try {
		Set sc = ..DropMemories(sessionRef)
		If $$$ISERR(sc) Set failed = failed + 1 Do ..Warn("the memories of session " _ sessionRef _ " could not be dropped", sc)
	} Catch exception {
		Set failed = failed + 1
		Do ..Warn("the memories of session " _ sessionRef _ " could not be dropped", exception.AsStatus())
	}
	Try {
		Set sc = ..DropUploads(sessionRef)
		If $$$ISERR(sc) Set failed = failed + 1 Do ..Warn("the uploads of session " _ sessionRef _ " could not be dropped", sc)
	} Catch exception {
		Set failed = failed + 1
		Do ..Warn("the uploads of session " _ sessionRef _ " could not be dropped", exception.AsStatus())
	}
	Quit failed
}

/// The one call that drops a session's documents (AD-21; a seam for the tests).
Method DropDocuments(sessionRef As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Docs).DropSession(sessionRef)
}

/// The one call that drops a session's memories (AD-21; a seam for the tests).
Method DropMemories(sessionRef As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Memory).DropSession(sessionRef)
}

/// The one call that drops a session's uploads (Lane B; a seam for the tests).
Method DropUploads(sessionRef As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Data.Upload).DropSession(sessionRef)
}

}
