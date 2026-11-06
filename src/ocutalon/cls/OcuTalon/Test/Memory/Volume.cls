/// The recall query at volume (Story 19.3; NFR-16, AD-21): 10,000 memories of one owner and 500 of another, with synthetic unit vectors (50 clusters of 384 values)
/// stored one by one, as MemoryOps stores them, with the statistics step of MemoryOps (OcuTalon.Memory.Tune) after each save.
///   - TestRecallUsesTheIndex: the plan of the recall query (OcuTalon.Memory NEARESTSQL, explained with $SYSTEM.SQL.Explain) reads the HNSW index
///     OcuTalon_Data.Memory.EmbeddingIdx and not the owner's bitmap index; run for each owner it returns the 20 nearest and every one of them is that owner's.
/// Inserting and then deleting the 10,500 rows takes about 100 seconds on an ARM throwaway (Story 19.3, Task 0: 51 s and 50 s), so the class skips unless
/// ^OcuTalonTest("Memory", "volume") is set, which the live unit memory-offline sets before it runs the class (its stack is a fresh install on the image,
/// with the table empty), and clears the flag after it. The rows of both owners are deleted before and after the class, and the table's statistics are first
/// those of a table with no rows, so that only the statistics step of the fill can put the plan on the index.
Class OcuTalon.Test.Memory.Volume Extends %UnitTest.TestCase
{

Parameter BIG = "zz-mem-volume";

Parameter SMALL = "zz-mem-volume2";

Parameter BIGROWS = 10000;

Parameter SMALLROWS = 500;

Parameter CLUSTERS = 50;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#BIG)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#BIG)
	Kill ^||OcuTalonTestVolume
	Quit $$$OK
}

Method TestRecallUsesTheIndex()
{
	If '$Get(^OcuTalonTest("Memory", "volume")) {
		Do $$$AssertSkipped("^OcuTalonTest(""Memory"", ""volume"") is not set: the class stores and deletes 10,500 memories, about 100 seconds, and runs in live:memory-offline")
		Quit
	}
	Try {
		Set start = $ZHorolog
		Do $$$AssertStatusOK($SYSTEM.SQL.Stats.Table.GatherTableStats(##class(OcuTalon.Memory).#TABLE), "the table's statistics are those of a table with no rows")
		Do ..Fill(..#BIG, "zzmv1-", ..#BIGROWS)
		Do ..Fill(..#SMALL, "zzmv2-", ..#SMALLROWS)
		Do $$$LogMessage("stored "_(..#BIGROWS + ..#SMALLROWS)_" memories in "_($ZHorolog - start)_" s")
		Do $$$AssertEquals(..Count(..#BIG), ..#BIGROWS, "the big owner has "_..#BIGROWS_" memories")
		Do $$$AssertEquals(..Count(..#SMALL), ..#SMALLROWS, "and the small owner "_..#SMALLROWS)
		Set sql = ##class(OcuTalon.Memory).#NEARESTSQL
		Set sc = $SYSTEM.SQL.Explain(sql, {"format": "INLINE-TEXT", "silent": 1}, , .plan)
		Do $$$AssertStatusOK(sc, "the recall query is explained")
		Set plan = $Translate(plan, $Char(10, 13), "  ")
		Do $$$AssertTrue(plan [ "Read index map OcuTalon_Data.Memory.EmbeddingIdx", "the plan reads the HNSW index EmbeddingIdx: " _ $Extract(plan, $Find(plan, "Module-FIRST"), $Find(plan, "Module-FIRST") + 400))
		Do $$$AssertTrue(plan '[ "SessionRefSavedAtIndex", "and not the owner's bitmap index")
		Set vector = ..Vector(7)
		For owner = ..#BIG, ..#SMALL {
			Set prefix = $Select(owner = ..#BIG: "zzmv1-", 1: "zzmv2-")
			Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, owner, vector)
			Do $$$AssertTrue(rs.%SQLCODE '< 0, "the query runs for " _ owner _ ": " _ rs.%Message)
			Set rows = 0
			Set foreign = 0
			While rs.%Next() {
				Set rows = rows + 1
				If $Extract(rs.%Get("Ref"), 1, $Length(prefix)) '= prefix Set foreign = foreign + 1
			}
			Do $$$AssertEquals(rows, ##class(OcuTalon.Memory).#CANDIDATES, owner _ ": it returns the 20 nearest")
			Do $$$AssertEquals(foreign, 0, "and every one of them is the owner's")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the volume check ran")
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#BIG)
}

/// Stores the rows of the owner one by one, as MemoryOps does, and calls Tune with each id.
Method Fill(owner As %String, prefix As %String, count As %Integer) [ Private ]
{
	For n = 1:1:count {
		Set row = ##class(OcuTalon.Data.Memory).%New()
		Set row.Ref = prefix _ n
		Set row.SessionRef = owner
		Set row.Text = "volume memory " _ n _ " about " _ (n # 97)
		Set row.SavedAt = "2026-11-05T10:00:00Z"
		Set row.ItemId = "zzmemitem"
		Set row.Origin = "tool"
		Set row.Embedding = $VOP("fromstring", ..Vector(n # ..#CLUSTERS + 1), "double", ",", 3)
		Set sc = row.%Save()
		If $SYSTEM.Status.IsError(sc) {
			Do $$$AssertStatusOK(sc, "memory " _ n _ " of " _ owner _ " is saved")
			Quit
		}
		Do ##class(OcuTalon.Memory).Tune(row.%Id())
		Set row = ""
	}
}

/// A unit vector of 384 values near the centre of the cluster, as comma-separated text (TO_VECTOR reads it).
ClassMethod Vector(cluster As %Integer) As %String [ Private ]
{
	Set norm = 0
	For i = 1:1:384 {
		Set centre = $Get(^||OcuTalonTestVolume(cluster, i))
		If centre = "" Set centre = ($Random(2000001) - 1000000) / 1000000, ^||OcuTalonTestVolume(cluster, i) = centre
		Set value = centre + (($Random(2000001) - 1000000) / 2500000)
		Set values(i) = value
		Set norm = norm + (value * value)
	}
	Set norm = $ZSQR(norm)
	Set text = ""
	For i = 1:1:384 {
		Set text = text _ $Select(i > 1: ",", 1: "") _ $FNumber(values(i) / norm, "", 8)
	}
	Quit text
}

/// The number of memories of the owner.
ClassMethod Count(owner As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Memory WHERE SessionRef = ?", owner)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

}
