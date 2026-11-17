/// A subclass of OcuTalon.Core.Access for Test.Core.Access, which overrides the one read that runs inside the %SYS switch so that a test can make it throw, and records the namespace
/// that the read ran in under ^||AccessProbe("namespace"); with ^||AccessProbe("mode") set to "account", AccountUsable answers 0 and counts its calls in ^||AccessProbe("accountCalls") (MayChat asks it, and
/// the read does not run). With ^||AccessProbe("mode") set to "throw" the read throws; otherwise it is the real read. It has no
/// Test methods and the product never refers to it.
Class OcuTalon.Test.Core.AccessProbe Extends OcuTalon.Core.Access
{

ClassMethod AccountUsable(irisUser As %String = "") As %Boolean
{
	If $Get(^||AccessProbe("mode")) '= "account" Quit ##super($Get(irisUser))
	Set ^||AccessProbe("accountCalls") = $Get(^||AccessProbe("accountCalls")) + 1
	Quit 0
}

ClassMethod Enabled(irisUser As %String) As %Boolean [ Private ]
{
	Set ^||AccessProbe("namespace") = $Namespace
	If $Get(^||AccessProbe("mode")) = "throw" Throw ##class(%Exception.General).%New("zz access read threw", 5001, , "zz access read threw")
	Quit ##super($Get(irisUser))
}

}
