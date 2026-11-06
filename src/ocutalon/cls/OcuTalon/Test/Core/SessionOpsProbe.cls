/// A subclass of OcuTalon.Core.SessionOps for the tests, which override its private seams: WriteAudit and SendNotice write and send
/// nothing, and Forget answers as SettingsAnswer says. Each call is captured on the instance: Audits holds the audit event data of each WriteAudit, in order, as dynamic objects,
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

/// "" (Forget deletes the per-person settings), "error" (an error status) or "throw" (an error is thrown); nothing is deleted
/// for the last two.
Property SettingsAnswer As %String;

Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Do ..Audits.%Push(data)
	If (..AuditAnswer = "error") || ((..AuditAnswer '= "") && (..AuditAnswer = data.change)) Quit $SYSTEM.Status.Error(5001, "zz audit failed")
	Quit $$$OK
}

Method Forget(sessionRef As %String) As %Status [ Private ]
{
	If ..SettingsAnswer = "error" Quit $SYSTEM.Status.Error(5001, "zz forget failed")
	If ..SettingsAnswer = "throw" Throw ##class(%Exception.General).%New("zz forget threw")
	Quit ##super(sessionRef)
}

Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Do ..Notices.Insert(notification)
	If ..NoticeAnswer = "error" Quit $SYSTEM.Status.Error(5001, "zz notice failed")
	Quit $$$OK
}

}
