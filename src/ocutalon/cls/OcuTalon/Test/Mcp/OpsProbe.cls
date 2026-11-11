/// A subclass of OcuTalon.Mcp.Ops for the Mcp tests (Story 22.2): a test fixture, never part of a production, with no Test method. It overrides the
/// private seams of its parent and keeps what they are asked in process-private nodes, so a test sees what a handler or RecordAttach would have sent:
///   - OnlineDemo answers ^||ZzOps("demo") (1 or 0), and the real flag when the node is not set;
///   - AdminSessions answers the list in ^||ZzOps("admins") when the node is set (and an error when ^||ZzOps("adminsError") is 1), else the real read;
///   - Notice records each notification in ^||ZzOps("notice", n) as a list of the session, the kind, the catalog key and the slots (and answers an error
///     when ^||ZzOps("noticeError") is 1), and sends nothing;
///   - Restart counts its calls in ^||ZzOps("restarts") and answers an error when ^||ZzOps("restartError") is 1; it restarts nothing;
///   - WriteAudit answers an error when ^||ZzOps("auditError") is 1, else it writes the entry through the real writer.
/// Shadow gives a probe whose request header names the sender, as the production does, and a test calls its MessageHandler with a command.
Class OcuTalon.Test.Mcp.OpsProbe Extends OcuTalon.Mcp.Ops
{

/// A shadow instance of the probe whose request header names the sender.
ClassMethod Shadow(sender As %String, Output sc As %Status) As OcuTalon.Test.Mcp.OpsProbe
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Mcp.OpsProbe", .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = sender
	Set probe.%RequestHeader = header
	Quit probe
}

/// The notices recorded so far, as a %DynamicArray of {"session", "kind", "key", "slots"}.
ClassMethod Notices() As %DynamicArray
{
	Set notices = []
	Set n = ""
	For {
		Set n = $Order(^||ZzOps("notice", n), 1, entry)
		Quit:n=""
		Do notices.%Push({"session": ($List(entry, 1)), "kind": ($List(entry, 2)), "key": ($List(entry, 3)), "slots": ($List(entry, 4))})
	}
	Quit notices
}

/// How many notices with the key went to the session.
ClassMethod NoticeCount(session As %String, key As %String) As %Integer
{
	Set count = 0
	Set iterator = ..Notices().%GetIterator()
	While iterator.%GetNext(, .notice) {
		If (notice.session = session) && (notice.key = key) Set count = count + 1
	}
	Quit count
}

ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	If $Get(^||ZzOps("demo")) = "" Quit ##super()
	Quit (^||ZzOps("demo") = 1)
}

ClassMethod AdminSessions(Output sc As %Status) As %List [ Private ]
{
	If $Get(^||ZzOps("adminsError")) = 1 {
		Set sc = $SYSTEM.Status.Error(5001, "zz the admins' sessions failed on purpose")
		Quit ""
	}
	If $Data(^||ZzOps("admins")) {
		Set sc = $SYSTEM.Status.OK()
		Quit ^||ZzOps("admins")
	}
	Quit ##super(.sc)
}

ClassMethod Notice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	If $Get(^||ZzOps("noticeError")) = 1 Quit $SYSTEM.Status.Error(5001, "zz the notice failed on purpose")
	Set ^||ZzOps("notice", $Increment(^||ZzOps("notice"))) = $ListBuild(notification.SessionRef, notification.Kind, notification.CatalogKey, notification.Slots)
	Quit $SYSTEM.Status.OK()
}

ClassMethod Restart() As %Status [ Private ]
{
	Set ^||ZzOps("restarts") = $Get(^||ZzOps("restarts")) + 1
	If $Get(^||ZzOps("restartError")) = 1 Quit $SYSTEM.Status.Error(5001, "zz the restart failed on purpose")
	Quit $SYSTEM.Status.OK()
}

ClassMethod WriteAudit(type As %String, data As %DynamicObject) As %Status [ Private ]
{
	If $Get(^||ZzOps("auditError")) = 1 Quit $SYSTEM.Status.Error(5001, "zz the audit failed on purpose")
	Quit ##super(type, data)
}

}
