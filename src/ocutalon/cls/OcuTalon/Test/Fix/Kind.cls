/// Tests of the fix-kind contract and the kind repair_resend (Story 7.1; AD-16): OcuTalon.Fix.Kind, OcuTalon.Fix.Kind.RepairResend, Install.Step.Fix and the
/// kind's check of a diagnosis (through Decide.CheckReply and Decide.Conclude, with a ReplyCheck begun). They need no production, so they run anywhere, a slot
/// included; Conclude records Decision rows in the namespace, and the tests remove the ones they made. That the grant reaches the service user is proved on a fresh start by
/// OcuTalon.Test.Fix.DryRun.TestServiceUserMayResend.
///   - TestContract: the base declares NAME, PARAMETERS, RESOURCES, NOTALLOWED (Story 7.3: the plain reason of a run that cannot start without the resources) and
///     KINDS, and the methods Classes, Names, ForName, Check, CheckParameters, DryRun, Recheck and
///     Execute (the last three with the same first three arguments, and Execute with the run as its last); the base's DryRun, Recheck and Execute are not implemented; the registered kinds are exactly
///     RepairResend, SuspendItem, ResumeItem, Reroute and PartnerWarning (Story 23.5: the base's DRAFTED, MOVES, NOTSETUP and Ready), whose NAME, PARAMETERS, RESOURCES and NOTALLOWED are fixed; every registered kind that declares RESOURCES sets NOTALLOWED; a class that is not
///     in KINDS (ZzKind) is unknown;
///   - TestSchemaCheck: the base's CheckParameters (through ZzKind) accepts exactly the PARAMETERS keys, each a string that is not blank;
///   - TestCheckParameters: RepairResend's matrix: the field must be a member of the fields (exactly), both formats registered, one family, two different formats;
///   - TestFieldWords: the words of a property name;
///   - TestItemsNotRead (Story 23.2): a suspend, resume or reroute dry run for a production whose items can't be read refuses with the item kinds' plain reason
///     (SuspendItem NOREAD), the text the chat model is given, and nothing else;
///   - TestGoodChanges (Story 7.9): RepairResend GoodChanges says whether the repair would change a good message's body: 11/11/2026 from MM/DD/YYYY to DD/MM/YYYY converts to
///     itself and is unchanged, to YYYY-MM-DD it is changed, 1234 from 1234.56 to 1234,56 is unchanged, and an empty value, a missing field, an empty body, a body that is no
///     object and a value in another format (YYYY-MM-DD under MM/DD/YYYY) are unchanged;
///   - TestGrants: Install.Step.Fix.Grants is generated from the RESOURCES of the registered kinds, GrantsOf of ZzKind gives its pairs once each, and no registered kind
///     declares a forbidden resource of the Roles step;
///   - TestInstructionsNameTheFormats: each registered format appears quoted in the instructions of the Diagnosis agent, which hold no template token;
///   - TestFromInput: EvidencePack.FromInput gives back the pack that Input made (braces and quotes inside a string included), ignores text after the pack, and
///     gives "" for no pack: an empty text, another first line, no JSON object, another format or an object that is not closed;
///   - TestReplyCheckRows: the validation rows through Decide.CheckReply: a valid repair is accepted; an unknown field, a bad format, formats of two families, one format
///     twice and an extra parameter are refused with the reply-check error; with no ReplyCheck begun, or an input that is no pack or a pack with no sample body, every repair
///     is refused, and a diagnosis with no fix is still accepted;
///   - TestConcludeRows: Decide.Conclude gives the fallback invalid and no payload for those refusals, and a usable diagnosis for the valid repair.
Class OcuTalon.Test.Fix.Kind Extends %UnitTest.TestCase
{

Parameter KIND = "OcuTalon.Fix.Kind";

Parameter REPAIR = "OcuTalon.Fix.Kind.RepairResend";

Parameter ZZ = "OcuTalon.Test.Fix.ZzKind";

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

Parameter PAYLOAD = "OcuTalon.Watch.Msg.DiagnosisPayload";

/// The ItemIds of the requests that the test made, for the clean-up of their Decision rows.
Property ItemIds As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

Method TestContract()
{
	Do $$$AssertTrue($Parameter(..#KIND, "NAME") = "" && ($Parameter(..#KIND, "PARAMETERS") = "") && ($Parameter(..#KIND, "RESOURCES") = "") && ($Parameter(..#KIND, "NOTALLOWED") = ""), "the base declares NAME, PARAMETERS, RESOURCES and NOTALLOWED, and sets none")
	Do $$$AssertEquals($Parameter(..#KIND, "KINDS"), "OcuTalon.Fix.Kind.RepairResend,OcuTalon.Fix.Kind.SuspendItem,OcuTalon.Fix.Kind.ResumeItem,OcuTalon.Fix.Kind.Reroute,OcuTalon.Fix.Kind.PartnerWarning,OcuTalon.Fix.Kind.Email", "the kinds that exist are listed once, in KINDS")
	Do $$$AssertEquals($Parameter(..#KIND, "TARGETTYPE")_"|"_$Parameter(..#KIND, "DIAGNOSED")_"|"_$Parameter(..#KIND, "ASKED")_"|"_$Parameter(..#KIND, "NOSTART")_"|"_$Parameter(..#KIND, "NOREAD")_"|"_$Parameter(..#KIND, "ONLINEGRANT"), "message|1|0|||1", "the base's kind has message targets, is a diagnosis kind, is not asked for and has no reasons of its own (Story 23.2)")
	Do $$$AssertEquals($Parameter(..#KIND, "DRAFTED")_"|"_$Parameter(..#KIND, "MOVES")_"|"_$Parameter(..#KIND, "NOTSETUP"), "0|1|", "the base's kind is not drafted, moves the incident and has no not-set-up reason (Story 23.5)")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).Ready("", .why)_"|"_why, "1|", "the base's kind is always ready (Story 23.5)")
	For parameter = "NAME", "PARAMETERS", "RESOURCES", "NOTALLOWED", "KINDS", "TARGETTYPE", "DIAGNOSED", "ASKED", "NOSTART", "NOREAD", "ONLINEGRANT", "ERRORSTATUS", "DRAFTED", "MOVES", "NOTSETUP" {
		Do $$$AssertTrue(##class(%Dictionary.CompiledParameter).%ExistsId(..#KIND_"||"_parameter), "the base declares "_parameter)
	}
	For method = "Classes", "Names", "ForName", "Check", "CheckParameters", "DryRun", "Recheck", "Execute", "DiagnosedNames", "Diagnosed", "Standing", "Failed", "ItemsOf", "ItemNamed", "Targeted", "MessageReason", "ItemNounOf", "ProductionName", "Ready" {
		Do $$$AssertTrue(##class(%Dictionary.CompiledMethod).%ExistsId(..#KIND_"||"_method), "the base declares "_method)
	}
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%OpenId(..#KIND).Abstract, "the base is abstract")
	For method = "DryRun", "Recheck", "Execute" {
		Set spec = ##class(%Dictionary.CompiledMethod).%OpenId(..#KIND_"||"_method).FormalSpec
		Set names = ""
		For i = 1:1:3 Set names = names _ $ListBuild($Translate($Piece($Piece(spec, ",", i), ":", 1), "*&", ""))
		Do $$$AssertEquals(names, $ListBuild("incident", "parameters", "targets"), method_" takes the incident, the parameters and the targets (DryRun works them out) first")
	}
	Do $$$AssertEquals($$$ISOK(##class(OcuTalon.Fix.Kind).Recheck("", "", "", .passed, .skipped)), 0, "the base's Recheck is not implemented")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(##class(OcuTalon.Fix.Kind).Execute("", "", "", .result)), 5003, "and so is its Execute (error 5003)")
	Do $$$AssertEquals($Translate($Piece($Piece(##class(%Dictionary.CompiledMethod).%OpenId(..#KIND_"||Execute").FormalSpec, ",", 5), ":", 1), "*&", ""), "run", "Execute takes the run (the FixRun row) as its fifth argument")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(##class(OcuTalon.Fix.Kind).DryRun("", "", .targets, .dryRun)), 5003, "and its DryRun")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).Classes(), $ListBuild(..#REPAIR, "OcuTalon.Fix.Kind.SuspendItem", "OcuTalon.Fix.Kind.ResumeItem", "OcuTalon.Fix.Kind.Reroute", "OcuTalon.Fix.Kind.PartnerWarning", "OcuTalon.Fix.Kind.Email"), "the registered kinds are RepairResend, SuspendItem, ResumeItem, Reroute, PartnerWarning and Email (Story 22.7)")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).Names(), $ListBuild("repair_resend", "suspend_item", "resume_item", "reroute", "partner_warning", "email"), "named repair_resend, suspend_item, resume_item, reroute, partner_warning and email")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).DiagnosedNames(), $ListBuild("repair_resend"), "the diagnosis may name repair_resend only")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).ForName("repair_resend"), ..#REPAIR, "ForName gives its class")
	For name = "", "Repair_Resend", "repair_resend ", "zz_kind", "rollback", "OcuTalon.Fix.Kind.RepairResend" {
		Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).ForName(name), "", "ForName gives no class for '"_name_"'")
	}
	Do $$$AssertEquals($Parameter(..#REPAIR, "NAME")_"|"_$Parameter(..#REPAIR, "PARAMETERS")_"|"_$Parameter(..#REPAIR, "RESOURCES"), "repair_resend|field,sourceFormat,targetFormat|%Ens_MessageResend:U", "RepairResend's name, parameters and resources")
	Do $$$AssertEquals($Parameter(..#REPAIR, "NOTALLOWED"), "OcuTalon isn't allowed to resend messages in that production", "and the plain reason of a run that cannot start without its resources")
	Set classes = ##class(OcuTalon.Fix.Kind).Classes()
	Set position = 0
	While $ListNext(classes, position, class) {
		If $Parameter(class, "RESOURCES") '= "" Do $$$AssertTrue($Parameter(class, "NOTALLOWED") '= "", class_" declares RESOURCES, so it sets NOTALLOWED, the plain reason of a run that cannot start without them")
	}
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(..#ZZ) && ($Parameter(..#ZZ, "NAME") = "zz_kind"), "the fixture kind exists")
	Do $$$AssertNotTrue($ListFind(##class(OcuTalon.Fix.Kind).Classes(), ..#ZZ), "and is not a registered kind")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("zz_kind", {"alpha": "a", "beta": "b"}, []), "Check refuses a kind that is not registered")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(##class(OcuTalon.Fix.Kind).Check("rollback", {}, [])) [ "repair_resend", "and the error names the kinds the diagnosis may name")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("reroute", {"target": "OrdersForReview"}, []), "Check refuses a registered kind that the diagnosis may not name (DIAGNOSED 0), with valid parameters")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("suspend_item", {"item": "OrdersToWarehouse"}, []), "and suspend_item")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("partner_warning", {"text": "A notice.", "to": "it@results-partner.example"}, []), "and partner_warning (Story 23.5)")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("email", {"recipients": ["it@example.test"], "subject": "A subject", "text": "A text."}, []), "and email (Story 22.7), which only the chat raises")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(##class(OcuTalon.Fix.Kind).Check("reroute", {"target": "A"}, [])) '[ "reroute,", "without naming it among the kinds it may name")
}

Method TestSchemaCheck()
{
	Do $$$AssertStatusOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": "b"}, []), "exactly the PARAMETERS keys, as strings, pass")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": "b", "gamma": "c"}, []), "an extra key is refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a"}, []), "a missing key is refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": 5}, []), "a number is refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": ["b"]}, []), "an array is refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": {"b": 1}}, []), "an object is refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": ""}, []), "a blank value is refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", {"alpha": "a", "beta": "  "}, []), "so is one of white space")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", ["a", "b"], []), "parameters that are an array are refused")
	Do $$$AssertStatusNotOK($ClassMethod(..#ZZ, "CheckParameters", "", []), "and parameters that are no object")
}

Method TestCheckParameters()
{
	Set fields = ["OrderNumber", "OrderDate", "Sku", "Quantity"]
	Set valid = {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}
	Do $$$AssertStatusOK($ClassMethod(..#REPAIR, "CheckParameters", valid, fields), "a field of the sample and two different formats of one family pass")
	Do $$$AssertStatusOK($ClassMethod(..#REPAIR, "CheckParameters", {"field": "Quantity", "sourceFormat": "1.234,56", "targetFormat": "1234.56"}, fields), "so do two number formats")
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind).Check("repair_resend", valid, fields), "Check by the kind's name passes")
	Do ..AssertRefused({"field": "ShipDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, fields, "a field that the sample does not have")
	Do ..AssertRefused({"field": "orderdate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, fields, "a field in another case")
	Do ..AssertRefused({"field": "OrderDate ", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, fields, "a field with a space")
	Do ..AssertRefused(valid, [], "no fields")
	Do ..AssertRefused(valid, "", "fields that are no array")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "MM-DD-YY", "targetFormat": "YYYY-MM-DD"}, fields, "an unregistered source format")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "iso"}, fields, "an unregistered target format")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "mm/dd/yyyy", "targetFormat": "YYYY-MM-DD"}, fields, "a format in lower case")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "1234.56"}, fields, "formats of two families")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "1234.56", "targetFormat": "YYYY-MM-DD"}, fields, "formats of two families, a number first")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "MM/DD/YYYY"}, fields, "one format twice")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD", "rounding": "2"}, fields, "an extra parameter")
	Do ..AssertRefused({"field": "OrderDate", "sourceFormat": "MM/DD/YYYY"}, fields, "a missing parameter")
	Do ..AssertRefused({"field": "", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, fields, "a blank field")
	Do ..AssertRefused({"field": 5, "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, fields, "a field that is a number")
	Do ..AssertRefused("", fields, "parameters that are no object")
}

Method TestGoodChanges()
{
	Set dates = {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}
	Set sameDay = {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "DD/MM/YYYY"}
	Set numbers = {"field": "Quantity", "sourceFormat": "1234.56", "targetFormat": "1234,56"}
	Do $$$AssertEquals(..GoodChanges({"OrderDate": "11/11/2026"}, sameDay), 0, "11/11/2026 from MM/DD/YYYY to DD/MM/YYYY converts to itself: unchanged")
	Do $$$AssertEquals(..GoodChanges({"OrderDate": "11/11/2026"}, dates), 1, "11/11/2026 from MM/DD/YYYY to YYYY-MM-DD is changed")
	Do $$$AssertEquals(..GoodChanges({"OrderDate": "11/05/2026"}, sameDay), 1, "11/05/2026 from MM/DD/YYYY to DD/MM/YYYY is changed")
	Do $$$AssertEquals(..GoodChanges({"Quantity": "1234"}, numbers), 0, "1234 from 1234.56 to 1234,56 converts to itself: unchanged")
	Do $$$AssertEquals(..GoodChanges({"Quantity": "1234.5"}, numbers), 1, "1234.5 from 1234.56 to 1234,56 is changed")
	Do $$$AssertEquals(..GoodChanges({"OrderDate": ""}, dates), 0, "an empty value is unchanged")
	Do $$$AssertEquals(..GoodChanges({"Sku": "A"}, dates), 0, "a missing field is unchanged")
	Do $$$AssertEquals(..GoodChanges({}, dates), 0, "an empty body is unchanged")
	Do $$$AssertEquals(..GoodChanges("", dates), 0, "a body that is no object is unchanged")
	Do $$$AssertEquals(..GoodChanges({"OrderDate": "2026-11-05"}, dates), 0, "a value in the target format is unchanged: the reformatter refuses it")
}

/// 1 when RepairResend GoodChanges says that the repair changes the body.
ClassMethod GoodChanges(body As %DynamicObject, parameters As %DynamicObject) As %Boolean [ Private ]
{
	Quit ''$ClassMethod(..#REPAIR, "GoodChanges", body, parameters)
}

/// Asserts that RepairResend refuses the parameters.
Method AssertRefused(parameters As %DynamicObject, fields As %DynamicArray, label As %String) [ Private ]
{
	Do $$$AssertStatusNotOK($ClassMethod(..#REPAIR, "CheckParameters", parameters, fields), label_" is refused")
}

Method TestFieldWords()
{
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind.RepairResend).FieldWords(""), "", "an empty name has no words")
	For pair = "OrderDate=order date", "PONumber=po number", "Sku=sku", "order_date=order date", "order-date=order date", "order.date=order date", "OrderID=order id", "XMLHttpRequest=xml http request", "Line2Total=line2 total", "a__b=a b", "_Lead=lead", "ALLCAPS=allcaps" {
		Do $$$AssertEquals(##class(OcuTalon.Fix.Kind.RepairResend).FieldWords($Piece(pair, "=", 1)), $Piece(pair, "=", 2), "the words of '"_$Piece(pair, "=", 1)_"'")
	}
}

Method TestItemsNotRead()
{
	Set incident = ##class(OcuTalon.Data.Incident).%New()
	Set incident.Namespace = ""
	Set incident.Production = "Zz.NoSuchProduction"
	Set noread = $Parameter("OcuTalon.Fix.Kind.SuspendItem", "NOREAD")
	For pair = "OcuTalon.Fix.Kind.SuspendItem|item", "OcuTalon.Fix.Kind.ResumeItem|item", "OcuTalon.Fix.Kind.Reroute|target" {
		Set class = $Piece(pair, "|", 1)
		Set parameters = {}
		Do parameters.%Set($Piece(pair, "|", 2), "OrdersForReview")
		Set sc = $ClassMethod(class, "DryRun", incident, parameters, .targets, .dryRun)
		Do $$$AssertStatusNotOK(sc, class_": the dry run refuses when the items can't be read")
		Do $$$AssertEquals($SYSTEM.Status.GetOneStatusText(sc), noread, class_": with the plain reason NOREAD only")
		Do $$$AssertEquals($Get(targets)_"|"_$IsObject($Get(dryRun)), "|0", class_": and gives no target and no dry run")
	}
}

Method TestGrants()
{
	Set grants = ##class(OcuTalon.Install.Step.Fix).Grants()
	Do $$$AssertEquals(grants.%Size(), 2, "the Fix area declares two grants: the resend and the item run (Story 23.2)")
	Do $$$AssertEquals(grants.%ToJSON(), "[{""role"":"""_##class(OcuTalon.Install.Step.Users).#SERVICEROLE_""",""resource"":""%Ens_MessageResend"",""permission"":""U""},{""role"":"""_##class(OcuTalon.Install.Step.Users).#SERVICEROLE_""",""resource"":""%Ens_ConfigItemRun"",""permission"":""U""}]", "the service role may use %Ens_MessageResend and %Ens_ConfigItemRun, as the RESOURCES of the kinds say")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Fix).GrantsOf(##class(OcuTalon.Fix.Kind).Classes()).%ToJSON(), grants.%ToJSON(), "and Grants is GrantsOf the registered kinds")
	Set zz = ##class(OcuTalon.Install.Step.Fix).GrantsOf($ListBuild(..#ZZ))
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Do $$$AssertEquals(zz.%ToJSON(), "[{""role"":"""_role_""",""resource"":""ZzResource"",""permission"":""R""},{""role"":"""_role_""",""resource"":""ZzResource"",""permission"":""W""},{""role"":"""_role_""",""resource"":""ZzOther"",""permission"":""U""}]", "GrantsOf a kind gives each of its pairs once")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Fix).GrantsOf("").%Size(), 0, "and no kind gives no grant")
	Set forbidden = $ListFromString($ZConvert($Parameter("OcuTalon.Install.Step.Roles", "FORBIDDEN"), "U"))
	Set classes = ##class(OcuTalon.Fix.Kind).Classes()
	Set position = 0
	While $ListNext(classes, position, class) {
		Set pairs = ##class(OcuTalon.Install.Step.Tools).Parse($Parameter(class, "RESOURCES"), class)
		Set iterator = pairs.%GetIterator()
		While iterator.%GetNext(, .pair) {
			Do $$$AssertNotTrue($ListFind(forbidden, $ZConvert(pair.resource, "U")), class_" declares "_pair.resource_", which the Roles step does not forbid")
			Do $$$AssertTrue($ZConvert(pair.resource, "U") '= "%ENS_MESSAGEEDITRESEND", class_" declares no %Ens_MessageEditResend")
		}
	}
	Do $$$AssertTrue($ListFind(forbidden, "%ENS_MESSAGEEDITRESEND"), "the Roles step forbids %Ens_MessageEditResend")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Registry).Declared("Grants", .entries), "the installer areas declare their grants")
	Set found = 0
	Set n = ""
	For {
		Set n = $Order(entries(n))
		Quit:n=""
		If (entries(n, "area") = "OcuTalon.Install.Step.Fix") && (entries(n).resource = "%Ens_MessageResend") && (entries(n).permission = "U") Set found = 1
	}
	Do $$$AssertTrue(found, "and the grant of the Fix area is among them, so the Roles step composes it")
}

Method TestInstructionsNameTheFormats()
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Agent.Diagnosis||INSTRUCTIONS")
	Set text = $Replace(xdata.Data.Read(1000000), $Char(13), "")
	Do $$$AssertTrue(text '= "", "the Diagnosis agent has instructions")
	Set names = ##class(OcuTalon.Fix.Reformat).Names()
	Set position = 0
	While $ListNext(names, position, name) {
		Do $$$AssertTrue(text [ ("""" _ name _ """"), "the instructions name "_name_" quoted")
	}
	Do $$$AssertNotTrue(text [ "{{", "and hold no template token")
	Do $$$AssertTrue(text [ "written exactly", "and say that the names are written exactly")
}

Method TestFromInput()
{
	Set class = "OcuTalon.Watch.EvidencePack"
	Set line = $Parameter(class, "INPUTLINE")
	Set object = {"format": "ocutalon.evidencePack/1", "item": "A } { \"quoted\" \\ item", "sample": {"body": {"OrderDate": "10/16/2026"}}}
	Set input = $ClassMethod(class, "Input", object)
	Do $$$AssertEquals(..JsonOf($ClassMethod(class, "FromInput", input)), object.%ToJSON(), "FromInput gives back the pack that Input made, braces and quotes in a string included")
	Do $$$AssertEquals(..JsonOf($ClassMethod(class, "FromInput", input_" (test zz) {x}")), object.%ToJSON(), "text after the pack is ignored")
	Do $$$AssertEquals(..JsonOf($ClassMethod(class, "FromInput", input_$Char(10))), object.%ToJSON(), "so is a line break")
	For text = "", "Triage this item.", line, line_$Char(10), line_$Char(10)_"[]", line_$Char(10)_"{""format"":""x""}", line_$Char(10)_" {""format"":""ocutalon.evidencePack/1""}", line_$Char(10)_"{""format"":""ocutalon.evidencePack/1""", "x"_$Char(10)_$Piece(input, $Char(10), 2) {
		Do $$$AssertEquals($ClassMethod(class, "FromInput", text), "", "'"_$Extract(text, 1, 30)_"' holds no pack")
	}
}

/// The JSON text of a dynamic object, or "none" when the value is no object (so that an assertion on a missing pack fails instead of throwing).
ClassMethod JsonOf(value As %DynamicObject) As %String [ Private ]
{
	Quit $Select($IsObject(value): value.%ToJSON(), 1: "none")
}

/// A usable repair as a dynamic object: the field, the source format and the target format may be changed by the caller. Test.Fix.Validation uses it too.
ClassMethod Repair() As %DynamicObject
{
	Quit {"outcome": "act", "causeCategory": "data_format_change", "elementAtFault": "OrderDate", "evidence": ["h2"], "fixKind": "repair_resend", "fixParameters": {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, "cause": "The order date is in another format.", "fixSummary": "rewrite the order date and send the orders again", "itemNoun": {"one": "order", "other": "orders"}, "reasons": ["The sample holds 10/16/2026."], "confidence": 0.9}
}

/// A request for a diagnosis whose input is the text.
Method NewRequest(input As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = input
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// The input of a diagnose request over an evidence pack whose sample holds the body (a dynamic object), or no sample body when body is "".
ClassMethod PackInput(body As %DynamicObject = "") As %String
{
	Set pack = {"format": "ocutalon.evidencePack/1", "namespace": "OCUORDERS", "item": "OrdersFromPartner", "count": 50, "sample": {"headerId": 2, "bodyClass": "OcuTalon.Demo.Orders.PartnerOrder"}}
	If $IsObject(body) Set pack.sample.body = body
	Quit ##class(OcuTalon.Watch.EvidencePack).Input(pack)
}

/// The body of an order as the evidence pack holds it.
ClassMethod OrderBody() As %DynamicObject
{
	Quit {"OrderNumber": "A-1001", "OrderDate": "10/16/2026", "Sku": "SKU-1", "Quantity": "3"}
}

/// The status of Decide.CheckReply for the reply, with the ReplyCheck begun from a request with the input (none when begun is 0).
Method CheckWith(reply As %DynamicObject, input As %String, begun As %Boolean = 1) As %Status [ Private ]
{
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	If begun Do ##class(OcuTalon.Bridge.ReplyCheck).Begin(..NewRequest(input))
	Set sc = $ClassMethod(..#DECIDE, "CheckReply", reply.%ToJSON(), ..#PAYLOAD, .payload)
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Quit sc
}

Method TestReplyCheckRows()
{
	Set input = ..PackInput(..OrderBody())
	Do $$$AssertStatusOK(..CheckWith(..Repair(), input), "a valid repair is accepted")
	Do $$$AssertStatusOK(..CheckWith(..Repair(), input_" (test zz)"), "also when text follows the pack")
	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Do ..AssertInvalid(..CheckWith(reply, input), "a field that is not a key of the sample body")
	Set reply = ..Repair()
	Set reply.fixParameters.field = "orderdate"
	Do ..AssertInvalid(..CheckWith(reply, input), "a field in another case")
	Set reply = ..Repair()
	Set reply.fixParameters.sourceFormat = "MM-DD-YY"
	Do ..AssertInvalid(..CheckWith(reply, input), "an unregistered source format")
	Set reply = ..Repair()
	Set reply.fixParameters.targetFormat = "1234.56"
	Do ..AssertInvalid(..CheckWith(reply, input), "formats of two families")
	Set reply = ..Repair()
	Set reply.fixParameters.targetFormat = "MM/DD/YYYY"
	Do ..AssertInvalid(..CheckWith(reply, input), "a source format equal to the target format")
	Set reply = ..Repair()
	Set reply.fixParameters.rounding = "2"
	Do ..AssertInvalid(..CheckWith(reply, input), "an extra parameter")
	Set reply = ..Repair()
	Set reply.fixKind = "rollback"
	Do ..AssertInvalid(..CheckWith(reply, input), "a fix kind that is not registered")
	Do ..AssertInvalid(..CheckWith(..Repair(), input, 0), "a repair with no ReplyCheck begun")
	Do ..AssertInvalid(..CheckWith(..Repair(), "Triage this item."), "a request whose input is no pack")
	Do ..AssertInvalid(..CheckWith(..Repair(), ##class(OcuTalon.Watch.EvidencePack).#INPUTLINE_$Char(10)_"{not json"), "an input whose pack is not JSON")
	Do ..AssertInvalid(..CheckWith(..Repair(), ##class(OcuTalon.Watch.EvidencePack).#INPUTLINE_$Char(10)_"{""format"":""other/1"",""sample"":{""body"":{""OrderDate"":""x""}}}"), "a pack of another format")
	Do ..AssertInvalid(..CheckWith(..Repair(), "Another line"_$Char(10)_$Piece(input, $Char(10), 2, *)), "a pack under another first line")
	Do ..AssertInvalid(..CheckWith(..Repair(), ..PackInput()), "a pack whose sample has no body")
	Do ..AssertInvalid(..CheckWith(..Repair(), ..PackInput({})), "a pack whose sample body is empty")
	Set outage = {"outcome": "act", "causeCategory": "partner_outage", "cause": "The partner did not answer.", "reasons": ["The failures show no data problem."], "confidence": 0.7}
	Do $$$AssertStatusOK(..CheckWith(outage, "Triage this item.", 0), "a diagnosis with no fix is accepted with no ReplyCheck")
	Do $$$AssertStatusOK(..CheckWith(outage, "Triage this item."), "and with an input that is no pack")
}

/// Asserts that the status is the error of the reply check.
Method AssertInvalid(sc As %Status, label As %String) [ Private ]
{
	Do $$$AssertStatusNotOK(sc, label_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "The reply check failed", label_" gives the reply-check error: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 200))
}

Method TestConcludeRows()
{
	Set input = ..PackInput(..OrderBody())
	Set request = ..NewRequest(input)
	Do $$$AssertStatusOK(..Conclude(request, ..Repair(), .response), "a valid repair is concluded")
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
	Do $$$AssertEquals($IsObject(row) && 'row.Fallback, 1, "as a usable diagnosis")
	Do $$$AssertEquals($Select($IsObject(row): {}.%FromJSON(row.Payload).fixKind, 1: ""), "repair_resend", "whose payload holds the fix kind")
	Set reply = ..Repair()
	Set reply.fixParameters.field = "ShipDate"
	Do ..AssertFallback(input, reply, "an unknown field")
	Set reply = ..Repair()
	Set reply.fixParameters.sourceFormat = "MM-DD-YY"
	Do ..AssertFallback(input, reply, "a bad format")
	Set reply = ..Repair()
	Set reply.fixParameters.targetFormat = "1234.56"
	Do ..AssertFallback(input, reply, "formats of two families")
	Set reply = ..Repair()
	Set reply.fixParameters.rounding = "2"
	Do ..AssertFallback(input, reply, "an extra parameter")
	Do ..AssertFallback("Triage this item.", ..Repair(), "a request whose input is no pack")
	Do ..AssertFallback(..PackInput(), ..Repair(), "a pack with no sample body")
}

/// Concludes the diagnosis reply for a request with the input, and asserts the fallback invalid with no payload.
Method AssertFallback(input As %String, reply As %DynamicObject, label As %String) [ Private ]
{
	Set request = ..NewRequest(input)
	Do $$$AssertStatusOK(..Conclude(request, reply, .response), label_" is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Payload, 1: "none"), "1|invalid|", label_" gives the fallback invalid and no payload")
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
	Do $$$AssertEquals($IsObject(row) && row.Fallback, 1, "and the row is the fallback")
}

/// Decide.Conclude with the DiagnosisPayload class, the do-nothing filter and sink, for the reply.
Method Conclude(request As OcuTalon.Bridge.Msg.Request, reply As %DynamicObject, Output response) As %Status [ Private ]
{
	Set text = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set text.Text = reply.%ToJSON()
	Quit $ClassMethod(..#DECIDE, "Conclude", request, ##class(OcuTalon.Bridge.Ids).NewRef(), text, ..#PAYLOAD, "OcuTalon.Bridge.Ext.ReplyFilter", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
}

}
