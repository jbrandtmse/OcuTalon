/// The governed proxy of the proxy tests (Story 22.3): a test fixture, never part of a production. It is OcuTalon.Mcp.Proxy with two seams changed, so that a test chooses what a
/// call finds without changing the instance: OnlineDemo answers ^||ZzProxy("demo") (1 or 0) when the node is set and the real flag otherwise, and WriteAudit answers an error
/// whose text holds a marker when ^||ZzProxy("auditError") is 1 and otherwise writes the entry through the real writer. The nodes are process-private.
Class OcuTalon.Test.Mcp.ZzProxy Extends OcuTalon.Mcp.Proxy
{

ClassMethod OnlineDemo() As %Boolean
{
	If $Get(^||ZzProxy("demo")) = "" Quit ##super()
	Quit (^||ZzProxy("demo") = 1)
}

ClassMethod WriteAudit(data As %DynamicObject) As %Status
{
	If $Get(^||ZzProxy("auditError")) = 1 Quit $SYSTEM.Status.Error(5001, "ZzProxy refuses the audit entry on purpose")
	Quit ##super(data)
}

}
