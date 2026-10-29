/// A subclass of OcuTalon.Core.SessionOps for the tests, which override its two private seams: WriteAudit and SendNotice write and send
/// nothing. Each call is captured on the instance: Audits holds the audit event data of each WriteAudit, in order, as dynamic objects,
/// and Notices the Notification of each SendNotice, in order. The answers are set on the instance: AuditAnswer and NoticeAnswer are ""
/// (OK, the default), "error" (an error status for every call), or for the audit "linked" or "unlinked" (an error status only for an
/// entry of that change). The product never refers to it.
Class OcuTalon.Test.Core.SessionOpsProbe Extends OcuTalon.Core.SessionOps
{

/// The audit event data of each WriteAudit.
Property Audits As %DynamicArray [ InitialExpression = {[]} ];

/// The Notification of each SendNotice.
Property Notices As list Of OcuTalon.Msg.Notification;

/// "", "error", "linked" or "unlinked".
Property AuditAnswer As %String;

/// "" or "error".
Property NoticeAnswer As %String;

Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Do ..Audits.%Push(data)
	If (..AuditAnswer = "error") || ((..AuditAnswer '= "") && (..AuditAnswer = data.change)) Quit $SYSTEM.Status.Error(5001, "zz audit failed")
	Quit $$$OK
}

Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Do ..Notices.Insert(notification)
	If ..NoticeAnswer = "error" Quit $SYSTEM.Status.Error(5001, "zz notice failed")
	Quit $$$OK
}

}
