/// The checks that live:documents (docker/tests/test-documents.sh) runs inside the stack after it has added and removed documents through the real
/// /v1/documents routes over HTTP (Story 19.4; AC 5, AD-5, DW-739). The class has no state of its own: it skips unless the script has left the Ref of the
/// document to check in ^OcuTalonTest("Docs","live") (a document that must be there and found) or ^OcuTalonTest("Docs","gone") (one that must be gone), and the
/// script deletes both nodes. It runs in the CI shard too, where it skips, so the class always compiles and loads.
///   - TestFound: the document with the Ref is listed as ready for the instance, its rows are in OcuTalonKB.Docs with their chunk_index, document and section, and
///     a search of the table through a bare %AI.ToolMgr and AI Hub's knowledge base, built by Docs.Store.Attach, returns the passage "Rotating the certificate"
///     of the document first with a score over the floor, for a question about the certificate - after the script has restarted the iris container as well;
///   - TestGone: the Ref has no row and no KB row, and the table holds no row of any document.
Class OcuTalon.Test.Docs.Live Extends %UnitTest.TestCase
{

Parameter STORE = "OcuTalon.Docs.Store";

Method TestFound()
{
	Set ref = $Get(^OcuTalonTest("Docs", "live"))
	If ref = "" {
		Do $$$AssertSkipped("live:documents has not named a document to find (^OcuTalonTest(""Docs"",""live""))")
		Quit
	}
	Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the document has a row")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State _ "|" _ row.OwnerRef _ "|" _ row.KnowledgeBase, "ready|instance|OcuTalonKB.Docs", "it is ready, the install's, in OcuTalonKB.Docs")
	Do $$$AssertEquals(row.Reason, "", "with no reason")
	Set passages = $ClassMethod(..#STORE, "Count", ref)
	Do $$$AssertTrue(passages > 0, "its passages are in the table: " _ passages)
	Set sections = {}.%FromJSON(row.Sections)
	Do $$$AssertEquals(sections.%Size(), passages, "and Sections has an element for each")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT metadata FROM OcuTalonKB.Docs WHERE source = ?", ref)
	Set rotating = 0
	While rs.%Next() {
		Set meta = {}.%FromJSON(rs.%Get("metadata"))
		If meta.section = "Rotating the certificate" Set rotating = rotating + 1
		Do $$$AssertEquals(sections.%Get(meta."chunk_index"), meta.section, "the section of chunk_index " _ meta."chunk_index" _ " is the row's")
	}
	Do $$$AssertEquals(rotating, 1, "one passage is under Rotating the certificate")
	Set agent = ##class(%AI.Agent).%New()
	Do $ClassMethod(..#STORE, "Attach", agent, .holder)
	Do $$$AssertTrue($IsObject(holder), "the documents tool attaches")
	If '$IsObject(holder) Quit
	Set result = agent.ToolManager.ExecuteTool("documents", {"query": "how do I rotate the Results certificate?"})
	Set first = result.value.%Get(0)
	Do $$$AssertEquals(first.metadata.source _ "|" _ first.metadata.section _ "|" _ first.metadata.document, ref _ "|Rotating the certificate|Results runbook", "the search finds the passage of the certificate first, with its document and section")
	Do $$$AssertTrue(first.score '< $Parameter("OcuTalon.Bridge.Citations", "CITEFLOOR"), "with a score over the floor: " _ first.score)
}

Method TestGone()
{
	Set ref = $Get(^OcuTalonTest("Docs", "gone"))
	If ref = "" {
		Do $$$AssertSkipped("live:documents has not named a removed document (^OcuTalonTest(""Docs"",""gone""))")
		Quit
	}
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(ref)), 0, "the document has no row")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "and no row in the table")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count"), 0, "which holds no row of any document")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE OwnerRef = 'instance'")
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "and the install owns no document")
}

}
