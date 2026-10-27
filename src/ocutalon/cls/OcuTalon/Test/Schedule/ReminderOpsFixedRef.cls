/// A subclass of OcuTalon.Schedule.ReminderOps for the tests, which overrides its private seam NewRef: the next reminder it sets gets the
/// Ref that Next stored, once; every other reminder gets a new Ref as the product gives it. Everything else, the three verbs, the row, the
/// waiter and the events, is the real one. The product never refers to it.
///   - Next(ref) stores the Ref for the next set;
///   - Use() puts this class behind the ReminderOps item and stores the class the item had;
///   - Restore() puts the stored class back and removes both stored values, whatever happened.
/// The values are the nodes of ^OcuTalonTest("ReminderOpsFixedRef"): "next" and "className".
Class OcuTalon.Test.Schedule.ReminderOpsFixedRef Extends OcuTalon.Schedule.ReminderOps
{

/// The Ref that Next stored, once; otherwise a new Ref.
Method NewRef() As %String [ Private ]
{
	Set ref = $Get(^OcuTalonTest("ReminderOpsFixedRef", "next"))
	If ref = "" Quit ##super()
	Kill ^OcuTalonTest("ReminderOpsFixedRef", "next")
	Quit ref
}

/// Stores the Ref that the next reminder gets.
ClassMethod Next(ref As %String)
{
	Set ^OcuTalonTest("ReminderOpsFixedRef", "next") = ref
}

/// Puts this class behind the ReminderOps item (RunnerFixture.UseItemClass) and stores the class the item had, for Restore. The status
/// of UseItemClass. THIS CHANGES THE RUNNING PRODUCTION: throwaways and CI only (Rule 21).
ClassMethod Use() As %Status
{
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemClass("ReminderOps", $ClassName(), .saved)
	If $IsObject(saved) && saved.%IsDefined("className") && (saved.className '= $ClassName()) && ($Get(^OcuTalonTest("ReminderOpsFixedRef", "className")) = "") {
		Set ^OcuTalonTest("ReminderOpsFixedRef", "className") = saved.className
	}
	Quit sc
}

/// Puts the class that Use stored back behind the ReminderOps item (RunnerFixture.RestoreItemClass) and removes both stored values.
/// With no class stored it changes nothing and answers OK.
ClassMethod Restore() As %Status
{
	Set sc = $$$OK
	Set className = $Get(^OcuTalonTest("ReminderOpsFixedRef", "className"))
	If className '= "" Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass("ReminderOps", {"className": (className)})
	Kill ^OcuTalonTest("ReminderOpsFixedRef")
	Quit sc
}

}
