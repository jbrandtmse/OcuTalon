/// The photo content class of OcuTalon on the online demo, for the tests of Story 26.3: OcuTalon.Agent.Content with the online-demo flag always set (its OnlineDemo seam), so
/// that a test can name it in the ContentClass setting of Decide and see that no image is sent and no caption is saved. Nothing else differs.
Class OcuTalon.Test.Agent.ZzDemoContent Extends OcuTalon.Agent.Content
{

ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit 1
}

}
