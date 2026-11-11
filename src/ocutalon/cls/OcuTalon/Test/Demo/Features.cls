/// Tests of Demo.Features (Story 4.11; AD-12, AD-29): the feature catalog of the demo guide's "Other things to try" panel.
///   - TestIds: the pure mapping from probe flags to ids: with no flag the seven constants (incidentSummary, Story 23.6, first; reroute, Story 23.2, after rejectFix; partnerWarning, Story 23.5, after reroute; queueWatch, Story 23.7, after partnerWarning) and usage and history, each flag alone adds exactly its id in its
///     place (memory adds memory and memoryCard, in that order), all flags give the fifteen in order, sources only with memory or documents and usage then history always last, and a false or missing flag adds nothing;
///   - TestPresentFollowsTheProbes: Present() equals Ids of the probes this test computes itself (the persona and heartbeat command
///     classes compiled; the memory and document operations compiled and not marked STUB = 1);
///   - TestStubsAreNotFeatures: while the memory and document operations carry STUB = 1 their ids are absent from Present(); once a
///     story builds one, its id is listed exactly when the class is built;
///   - TestGuideCarriesTheCatalog: Guide.Compute of a fixture session and Guide.Blank() carry Features equal to Present(), in order,
///     and their JSON holds it as "features";
///   - TestReadOnly: the class holds no SQL, no save, no global write, no lock and no setting write (a read of its source).
Class OcuTalon.Test.Demo.Features Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("DemoFeatures", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// The ids as one comma-separated string.
ClassMethod Text(ids As %List) As %String [ Private ]
{
	Quit $ListToString(ids, ",")
}

/// The ids for the flags that are set.
ClassMethod IdsOf(flags As %DynamicObject) As %String [ Private ]
{
	Quit ..Text(##class(OcuTalon.Demo.Features).Ids(flags))
}

/// The catalog is a pure mapping: the seven constants are always there, and each flag adds its own id in its place.
Method TestIds()
{
	Set base = "incidentSummary,suspiciousEmail,rejectFix,reroute,partnerWarning,queueWatch,demoView"
	Do $$$AssertEquals(..IdsOf({}), base_",usage,history", "no flag: the seven constants, incidentSummary first, reroute (Story 23.2) after rejectFix, partnerWarning (Story 23.5) after reroute and queueWatch (Story 23.7) after partnerWarning, then usage and history")
	Do $$$AssertEquals(..IdsOf({"persona": 0, "memory": 0, "documents": 0, "heartbeat": 0}), base_",usage,history", "every flag false: the seven constants, then usage and history")
	Do $$$AssertEquals(..IdsOf({"persona": 1}), "incidentSummary,persona,suspiciousEmail,rejectFix,reroute,partnerWarning,queueWatch,demoView,usage,history", "persona alone follows incidentSummary and leads the rest")
	Do $$$AssertEquals(..IdsOf({"memory": 1}), base_",memory,memoryCard,sources,usage,history", "memory alone follows the constants, with memoryCard right after it, then sources, then usage and history")
	Do $$$AssertEquals(..IdsOf({"documents": 1}), base_",documents,sources,usage,history", "documents alone follows the constants, then sources, then usage and history")
	Do $$$AssertEquals(..IdsOf({"heartbeat": 1}), base_",heartbeat,usage,history", "heartbeat alone follows the constants and brings no sources")
	Do $$$AssertEquals(..IdsOf({"memory": 1, "heartbeat": 1}), base_",memory,memoryCard,heartbeat,sources,usage,history", "two flags keep the order, sources, usage and history last")
	Do $$$AssertEquals(..IdsOf({"heartbeat": true, "documents": true, "memory": true, "persona": true}), "incidentSummary,persona,suspiciousEmail,rejectFix,reroute,partnerWarning,queueWatch,demoView,memory,memoryCard,documents,heartbeat,sources,usage,history", "all flags: the fifteen in order, whatever the order the flags were written in")
	Do $$$AssertEquals(..IdsOf({"unknown": 1}), base_",usage,history", "a flag the catalog does not know adds nothing")
}

/// 1 when the class is compiled and its STUB parameter is not 1.
ClassMethod Built(class As %String) As %Boolean [ Private ]
{
	If '##class(%Dictionary.CompiledClass).%ExistsId(class) Quit 0
	Quit '+$Parameter(class, "STUB")
}

/// Present() is Ids of the instance's probes, which this test computes with its own reads.
Method TestPresentFollowsTheProbes()
{
	Set flags = {}
	Set flags.persona = ''##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Msg.Command.SetPersona")
	Set flags.memory = ..Built("OcuTalon.Memory.Ops")
	Set flags.documents = ..Built("OcuTalon.Docs.Ops")
	Set flags.heartbeat = ''##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Msg.Command.RunHeartbeat")
	Do $$$AssertEquals(..Text(##class(OcuTalon.Demo.Features).Present()), ..IdsOf(flags), "Present() is the mapping of the instance's own probes")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Demo.Features).Present()) >= 3, 1, "the constants are always listed")
}

/// A stub is not a feature: while a story is open its operation carries STUB = 1, and Present() then leaves its id out.
Method TestStubsAreNotFeatures()
{
	Set present = ##class(OcuTalon.Demo.Features).Present()
	For pair = $ListBuild("OcuTalon.Memory.Ops", "memory"), $ListBuild("OcuTalon.Docs.Ops", "documents") {
		Set class = $ListGet(pair, 1), id = $ListGet(pair, 2)
		If ##class(%Dictionary.CompiledClass).%ExistsId(class), +$Parameter(class, "STUB") {
			Do $$$AssertEquals($ListFind(present, id), 0, class_" is a stub, so "_id_" is not listed")
		}
		Else {
			Do $$$AssertEquals($ListFind(present, id) > 0, ..Built(class), id_" is listed exactly when "_class_" is built")
		}
	}
}

/// The guide view carries the catalog, so it rides /v1/state and the guide.state event: Compute, Blank() and their JSON.
Method TestGuideCarriesTheCatalog()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzfeat"_..Number)
	Set present = ##class(OcuTalon.Demo.Features).Present()
	For view = ##class(OcuTalon.Demo.Guide).Compute(ref), ##class(OcuTalon.Demo.Guide).Blank() {
		Set got = ""
		For i = 1:1:view.Features.Count() {
			Set got = got _ $ListBuild(view.Features.GetAt(i))
		}
		Do $$$AssertEquals(..Text(got), ..Text(present), "the view's Features are Present(), in order")
		Do view.%JSONExportToString(.json)
		Set features = {}.%FromJSON(json).features
		Do $$$AssertEquals(features.%Size(), $ListLength(present), "the exported JSON holds features, one entry for each id")
		Do $$$AssertEquals(features.%Get(0), $ListGet(present, 1), "and the first id is Present()'s first")
	}
}

/// The source of the class: no SQL, no save, no global write, no lock, no setting write.
Method TestReadOnly()
{
	Set class = ##class(%Dictionary.ClassDefinition).%OpenId("OcuTalon.Demo.Features")
	Do $$$AssertTrue($IsObject(class), "the class definition is readable")
	If '$IsObject(class) Quit
	Set source = ""
	For i = 1:1:class.Methods.Count() {
		Set stream = class.Methods.GetAt(i).Implementation
		Do stream.Rewind()
		While 'stream.AtEnd {
			Set source = source _ $ZConvert(stream.ReadLine(), "L") _ $Char(10)
		}
	}
	Do $$$AssertTrue($Length(source) > 0, "the methods' source is read")
	For forbidden = "&sql(", "%sql.", "%resultset", "%save(", "%delete", "set ^", "kill ^", "merge ^", "lock ", "$increment", "setting).set", "%newid" {
		Do $$$AssertEquals(source [ forbidden, 0, "the class holds no "_forbidden)
	}
}

}
