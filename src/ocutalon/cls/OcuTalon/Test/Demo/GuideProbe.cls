/// A subclass of OcuTalon.Demo.Guide for the tests, which overrides its two private seams (Story 4.2; AD-22): Now answers
/// ^OcuTalonTest("GuideProbe","now") when a test sets it, otherwise the real clock; TelegramOn answers
/// ^OcuTalonTest("GuideProbe","telegram"), 0 when unset. The test kills ^OcuTalonTest("GuideProbe") before and after. It has no
/// Test methods and the product never refers to it.
Class OcuTalon.Test.Demo.GuideProbe Extends OcuTalon.Demo.Guide
{

ClassMethod Now() As %String [ Private ]
{
	Set now = $Get(^OcuTalonTest("GuideProbe", "now"))
	Quit $Select(now '= "": now, 1: ##super())
}

ClassMethod TelegramOn() As %Boolean [ Private ]
{
	Quit +$Get(^OcuTalonTest("GuideProbe", "telegram"))
}

}
