/// A WatchOps whose send to Checks is under test control (test only; Story 5.6). Test.Watch.Ops calls the handlers of a shadow instance of it, in its own
/// process. A shadow instance cannot SendRequestAsync (its primary request header is not there), so SendChanged records each CheckChanged in Changes, as a
/// plain object {checkRef, sessionRef, stopped, kind, namespace, production, displayName}, and answers OK, or an error when FailChanged is set. It is not an
/// item of any production.
Class OcuTalon.Test.Watch.OpsProbe Extends OcuTalon.Watch.Ops
{

/// The messages that SendChanged recorded, in order.
Property Changes As %DynamicArray [ Transient ];

/// 1 to make SendChanged answer an error (after it has recorded the message).
Property FailChanged As %Boolean [ InitialExpression = 0, Transient ];

/// Records the message instead of sending it.
Method SendChanged(message As OcuTalon.Checks.Msg.CheckChanged) As %Status [ Private ]
{
	If '$IsObject(..Changes) Set ..Changes = []
	Do ..Changes.%Push({"checkRef": (message.CheckRef), "sessionRef": (message.SessionRef), "stopped": (+message.Stopped), "kind": (message.Kind), "namespace": (message.Namespace), "production": (message.Production), "displayName": (message.DisplayName)})
	If ..FailChanged Quit $SYSTEM.Status.Error(5001, "The send to Checks is refused")
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
