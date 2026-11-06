/// A subclass of OcuTalon.Web.Documents for Test.Web.DocumentsApi.TestOwnerRunningReadsTheItem (Story 34.2): it keeps the real OwnerRunning and
/// names an owner item that only the test creates (OWNER), and Running makes the private check callable. It has no Test methods and the product
/// never refers to it.
Class OcuTalon.Test.Web.DocumentsOwnerProbe Extends OcuTalon.Web.Documents
{

Parameter OWNER = "zzDocumentsOwnerProbe";

/// The real OwnerRunning for the item named by OWNER.
ClassMethod Running() As %Boolean
{
	Quit ..OwnerRunning()
}

}
