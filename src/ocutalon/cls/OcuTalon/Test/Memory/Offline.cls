/// The offline proof of the memory vectors (Story 19.2; AD-21): the model is the one the image baked, so nothing needs the network. The live unit
/// live:memory-offline runs this class in a fresh stack whose networks are all disconnected. It needs the Python package and the baked folder, so it runs
/// only on OcuTalon's Docker image and records one named skip elsewhere.
///   - TestStoreAndRecall: a memory row (OcuTalon.Data.Memory) is stored with its embedding from this story's endpoint and is the top hit of a
///     VECTOR_COSINE query for a paraphrase, ahead of two rows about other things; the rows are deleted afterwards (Story 19.3 adds the tool path);
///   - TestHubFromTheBakedFolder: AI Hub's FastEmbed embeds a document chunk into a test vector-store table from the baked folder, and the stored
///     vector equals the endpoint's vector for the chunk's text within 1e-6;
///   - TestHubFromACopyInAWorker: the same from a copy of the baked folder under the manager directory, in a worker whose FASTEMBED_CACHE_DIR is set
///     to the copy (the way a package that cannot set the process's environment passes the folder, AD-21).
Class OcuTalon.Test.Memory.Offline Extends %UnitTest.TestCase
{

Parameter SESSION = "zz-mem-offline";

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTestMemoryOffline
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
	Merge ^||OcuTalonTestMemoryOffline = state
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Merge state = ^||OcuTalonTestMemoryOffline
	Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	Kill ^||OcuTalonTestMemoryOffline
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

Method TestStoreAndRecall()
{
	If '..OnImage() Quit
	Set texts(1) = "the Results partner's contact is Lee"
	Set texts(2) = "the warehouse closes at six on Fridays"
	Set texts(3) = "invoices are paid by bank transfer within thirty days"
	Set query = "who do I contact at the Results partner?"
	Try {
		Do ..DeleteRows()
		For n = 1:1:3 {
			Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(texts(n), .vector), "memory " _ n _ " is embedded")
			Set row = ##class(OcuTalon.Data.Memory).%New()
			Set row.Ref = "zzmo" _ n
			Set row.SessionRef = ..#SESSION
			Set row.Text = texts(n)
			Set row.SavedAt = "2026-11-06T00:00:0" _ n _ "Z"
			Set row.Origin = "tool"
			Set row.Embedding = vector
			Do $$$AssertStatusOK(row.%Save(), "and stored")
			Set row = ""
		}
		Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(query, .queryVector), "the paraphrase is embedded")
		Set statement = ##class(%SQL.Statement).%New()
		Do $$$AssertStatusOK(statement.%Prepare("SELECT TOP 3 Ref, Text FROM OcuTalon_Data.Memory WHERE SessionRef = ? ORDER BY VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE, 384)) DESC", 1), "the cosine query prepares")
		Set result = statement.%Execute(..#SESSION, ##class(OcuTalon.Test.Memory.Fixture).ToString(queryVector))
		Do $$$AssertTrue(result.%SQLCODE >= 0, "and runs: " _ result.%Message)
		Do $$$AssertTrue(result.%Next(), "and returns rows")
		Do $$$AssertEquals(result.%Get("Ref"), "zzmo1", "the memory about the Results partner is the top hit")
		Do $$$AssertEquals(result.%Get("Text"), texts(1), "with its text")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the store and recall check ran")
	}
	Do ..DeleteRows()
}

Method TestHubFromTheBakedFolder()
{
	If '..OnImage() Quit
	Set table = "OcuTalonKB.ZzMoff", suffix = "ZzMoff"
	Try {
		Do $$$AssertEquals($SYSTEM.Util.GetEnviron("FASTEMBED_CACHE_DIR"), "/opt/fastembed", "FASTEMBED_CACHE_DIR names the baked folder")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).CreateTable(table, suffix), "the test table is made")
		Set texts(1) = ##class(OcuTalon.Test.Memory.Fixture).Matrix(1)
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).HubFill(table, .texts), "AI Hub's FastEmbed embeds a document chunk")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).HubRows(table, .rows), "and the row is read")
		Do $$$AssertEquals($Order(rows(""), -1), 1, "one chunk")
		Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(rows(1), .vector), "the endpoint embeds the chunk's text")
		Set distance = ##class(OcuTalon.Test.Memory.Fixture).Distance(vector, rows(1, "vector"))
		Do $$$AssertTrue(distance <= 0.000001, "and equals AI Hub's vector within 1e-6, to " _ distance)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the AI Hub check ran")
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).DropTable(table, suffix)
}

Method TestHubFromACopyInAWorker()
{
	If '..OnImage() Quit
	Set table = "OcuTalonKB.ZzMcopy", suffix = "ZzMcopy"
	Set copy = $SYSTEM.Util.ManagerDirectory() _ "zz-memory-copy/"
	Try {
		Do $$$AssertEquals(##class(OcuTalon.Test.Memory.Fixture).CopyBaked(copy), 0, "the baked folder is copied under the manager directory")
		Do $$$AssertTrue(##class(OcuTalon.Memory.Embedder).HasModel(copy), "and the copy holds the model")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).CreateTable(table, suffix), "the test table is made")
		Set queue = $SYSTEM.WorkMgr.%New("", 1)
		Do $$$AssertTrue(queue '= "", "a worker group is made")
		Set sc = queue.Queue("##class(OcuTalon.Test.Memory.Offline).HubWorker", table, copy)
		Do $$$AssertStatusOK(sc, "the work item is queued")
		Set finished = queue.WaitOne(300, .workStatus, .workArgs, .workResult)
		Do $$$AssertTrue(finished, "and finishes")
		Do $$$AssertStatusOK(workStatus, "with no error")
		Do $$$AssertTrue($Get(workResult("job")) '= $Job, "in a worker, not in the calling process")
		Do $$$AssertEquals($Get(workResult("folder")), copy, "which had the copy as FASTEMBED_CACHE_DIR")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).HubRows(table, .rows), "the row is read")
		Do $$$AssertEquals($Order(rows(""), -1), 1, "one chunk")
		Do $$$AssertEquals($VOP("length", rows(1, "vector")), 384, "of 384 values")
		Set queue = ""
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the copy check ran")
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).DropTable(table, suffix)
	Do ##class(OcuTalon.Test.Memory.Fixture).RemoveCopy(copy)
}

/// The work item of TestHubFromACopyInAWorker: sets FASTEMBED_CACHE_DIR to the folder before AI Hub's FastEmbed is created, then embeds one chunk
/// into the table, and puts the variable back as the worker had it (workers are reused). %result("job") is the worker's $JOB and
/// %result("folder") the variable as the worker sees it while it embeds.
ClassMethod HubWorker(table As %String, folder As %String) As %Status
{
	Kill %result
	Set variable = ##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE
	Set previous = $SYSTEM.Util.GetEnviron(variable)
	Set environ = ##class(%SYS.Python).Import("os").environ
	Do environ."__setitem__"(variable, folder)
	Set %result("job") = $Job
	Set %result("folder") = $SYSTEM.Util.GetEnviron(variable)
	Set texts(1) = ##class(OcuTalon.Test.Memory.Fixture).Matrix(1)
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).HubFill(table, .texts)
	If previous '= "" {
		Do environ."__setitem__"(variable, previous)
	} Else {
		Do environ.pop(variable)
	}
	Quit sc
}

/// Deletes the fixture rows of the session.
ClassMethod DeleteRows()
{
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("DELETE FROM OcuTalon_Data.Memory WHERE SessionRef = ?", 1)
	Do statement.%Execute(..#SESSION)
}

}
