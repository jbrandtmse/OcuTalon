/// The runner's adapter that notes, at five points of a linked turn, whether another process can take the conversation lock of (SpyOwner, the runner
/// item), for Test.Bridge.Conversation: when the AI session is created (NewSession) or opened (OpenSession), right before Chat (Converse), right before
/// the save (SaveLinked), and each time the agent's Session is cleared (ReleaseSession). Each point is noted as name=1 when another process cannot take
/// the lock (the runner holds it), name=0 when it can and name=? when the other process did not answer. Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzLockSpyAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// The OwnerRef whose conversation lock is observed.
Property SpyOwner As %String;

/// The points reached since the last Forget, in order, as a list of $ListBuild(name, held).
Property Points As %List;

Method NewSession(Output session As %AI.Agent.Session) As %Status
{
	Do ..Note("new")
	Quit ##super(.session)
}

Method OpenSession(id As %String, Output session As %AI.Agent.Session) As %Status
{
	Do ..Note("open")
	Quit ##super(id, .session)
}

Method Converse(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, input As %String, opened As %Boolean, Output reply As OcuTalon.Bridge.Msg.Reply, Output completed As %Boolean) As %Status [ Private ]
{
	Do ..Note("converse")
	Quit ##super(request, session, input, opened, .reply, .completed)
}

Method SaveLinked(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, fresh As %Boolean, reply As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	Do ..Note("save")
	Do ##super(request, session, fresh, reply)
}

Method ReleaseSession() [ Private ]
{
	Do ..Note("release")
	Do ##super()
}

/// The points reached since the last Forget as name=held, joined by commas, in order.
Method Noted() As %String
{
	Set text = ""
	Set position = 0
	While $ListNext(..Points, position, point) {
		Set text = text _ $Select(text = "": "", 1: ",") _ $List(point, 1) _ "=" _ $List(point, 2)
	}
	Quit text
}

/// Forgets the points reached.
Method Forget()
{
	Set ..Points = ""
}

/// Notes the point, with 1 when another process cannot take the conversation lock of (SpyOwner, this runner item), 0 when it can, and ? when the
/// other process did not answer.
Method Note(name As %String) [ Private ]
{
	Set free = ##class(OcuTalon.Test.Bridge.Conversation).LockFree(..SpyOwner, ..BusinessHost.%ConfigName)
	Set ..Points = ..Points _ $ListBuild($ListBuild(name, $Select(free = 1: 0, free = 0: 1, 1: "?")))
}

}
