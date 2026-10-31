/// A double of OcuTalon.Checks.Process that reaches its due rule (test only; Story 9.8). Test.Eval.Watch makes a shadow instance of it with
/// Ens.Host.GetShadowInstance and asks DueAt for the rows that the real Checks item would run at a tick, because Test.Checks.Probe has the Kind
/// zzprobe and so can never see a row of Kind production. It has no tests, is never an item of a production, and changes no behaviour.
Class OcuTalon.Test.Eval.ZzChecks Extends OcuTalon.Checks.Process
{

/// The production checks that Checks.Process.Due gives at the tick time: a dynamic array of {"ref", "sessionRef", "namespace", "production",
/// "displayName", "createdAt", "lastRunAt"}.
Method DueAt(tickAt As %String) As %DynamicArray
{
	Quit ..Due(tickAt)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
