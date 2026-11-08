/// Tests of the documents' embedding (Story 19.4 QA; AD-6, AD-21; the Contest Planner's ruling Q2). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), on
/// OcuTalon's Docker image: EmbedBatch embeds in the Embedder worker. They skip elsewhere. The class writes nothing but the worker category and the embedding
/// configuration that Fixture.Prepare sets, and puts both back.
///   - TestShape: Dimensions is 384 and ModelName is AllMiniLML6V2 (what AI Hub stores in the knowledge base's _Config table); EmbedBatch of an empty array
///     returns an empty array, and one of three texts returns three vectors of 384 numbers, in the order of the texts;
///   - TestSameVectors: the vector that EmbedBatch returns for a text is the vector that Memory.Embedding.Embed gives the same text, which is the one
///     Docs.Store.Write puts into the table for a passage, so a query and a passage share one model (Q2); two different texts give different vectors.
Class OcuTalon.Test.Docs.Embedding Extends %UnitTest.TestCase
{

Parameter QUESTION = "how do I rotate the Results certificate?";

Parameter OTHER = "what is the capital of France?";

Parameter THIRD = "Stop the item named Results.Sender.";

/// What Fixture.Prepare changed (the worker category and the embedding config), put back in OnAfterAllTests.
Property State As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
	Merge ..State = state
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Merge state = ..State
	If $Data(state) Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// The largest difference between the values of the dynamic array and of the vector, or 1000 when their lengths differ.
ClassMethod Distance(values As %DynamicArray, vector As %Vector) As %Numeric [ Private ]
{
	If '$IsObject(values) || '$IsVector(vector) || (values.%Size() '= $VOP("length", vector)) Quit 1000
	Set largest = 0
	For i = 1:1:values.%Size() {
		Set difference = $ZAbs(values.%Get(i - 1) - $VECTOR(vector, i))
		If difference > largest Set largest = difference
	}
	Quit largest
}

Method TestShape()
{
	If '..OnImage() Quit
	Set embedding = ##class(OcuTalon.Docs.Embedding).%New()
	Do $$$AssertEquals(embedding.Dimensions _ "|" _ embedding.ModelName, "384|AllMiniLML6V2", "the embedding has 384 dimensions and the model name AllMiniLML6V2")
	Set none = embedding.EmbedBatch([])
	Do $$$AssertEquals($Select($IsObject(none): none.%Size(), 1: "no array"), 0, "EmbedBatch of no text returns no vector")
	Set batch = embedding.EmbedBatch([(..#QUESTION), (..#OTHER), (..#THIRD)])
	Do $$$AssertEquals($Select($IsObject(batch): batch.%Size(), 1: "no array"), 3, "EmbedBatch of three texts returns three vectors")
	If '$IsObject(batch) || (batch.%Size() '= 3) Quit
	Set texts = $ListBuild(..#QUESTION, ..#OTHER, ..#THIRD)
	For i = 1:1:3 {
		Set values = batch.%Get(i - 1)
		Do $$$AssertEquals($Select($IsObject(values): values.%Size(), 1: "no array"), 384, "vector " _ i _ " has 384 values")
		Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed($List(texts, i), .expected), "text " _ i _ " is embedded by Memory.Embedding.Embed")
		Do $$$AssertTrue(..Distance(values, expected) < 0.000001, "and vector " _ i _ " of the batch is the vector of text " _ i _ ", in the order of the texts: " _ ..Distance(values, expected))
	}
}

Method TestSameVectors()
{
	If '..OnImage() Quit
	Set embedding = ##class(OcuTalon.Docs.Embedding).%New()
	Set batch = embedding.EmbedBatch([(..#QUESTION), (..#OTHER)])
	If '$IsObject(batch) || (batch.%Size() '= 2) {
		Do $$$AssertTrue(0, "EmbedBatch returns two vectors")
		Quit
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(..#OTHER, .other), "the second text is embedded alone")
	Do $$$AssertTrue(..Distance(batch.%Get(0), other) > 0.01, "two different texts give different vectors: " _ ..Distance(batch.%Get(0), other))
	Do $$$AssertTrue(..Distance(batch.%Get(1), other) < 0.000001, "and the second vector of the batch is the second text's own")
	Set single = embedding.EmbedBatch([(..#QUESTION)])
	Do $$$AssertEquals($Select($IsObject(single): single.%Size(), 1: "no array"), 1, "a batch of one text returns one vector")
	If $IsObject(single) && (single.%Size() = 1) {
		Do $$$AssertTrue(..Distance(single.%Get(0), $VOP("fromstring", $ZStrip(batch.%Get(0).%ToJSON(), "*W", "[]"), "double", ",", 3)) < 0.000001, "which equals the first vector of the two-text batch: a text's vector does not depend on the others")
	}
}

}
