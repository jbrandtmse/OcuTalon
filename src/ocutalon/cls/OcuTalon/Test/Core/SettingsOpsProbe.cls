/// A subclass of OcuTalon.Core.SettingsOps for the tests, which override its private seams WriteAudit and RunDemo: they
/// write nothing to the audit log (unless the "audit" answer is "record") and run no Demo step. RunStep, with its Try/Catch, its
/// warnings and its kept sentence, is the real one. Each call is recorded under ^OcuTalonTest("SettingsOpsProbe", "calls", n) as
/// "audit" or "step", with the value that Setting.Get reads for demo.mode while it runs ("seen"), and for the audit the data as JSON
/// ("data"). The answers come from ^OcuTalonTest("SettingsOpsProbe", "answer", seam): "" is OK, "error" is an error status, "throw"
/// throws, for "audit" "record" hands the data to Bridge.Audit.Record and answers its status, and for "step" "kept" records the
/// demoKept mark with the note in ^OcuTalonTest("SettingsOpsProbe", "note") and answers OK, and "warn" records one step warning line
/// ("zz warning") and answers OK. The guarded write Apply answers an error status when the "apply" answer is "error", or, for "second",
/// at its second call since ^OcuTalonTest("SettingsOpsProbe", "applies") was last killed, and is the real one otherwise.
/// The answers "auditAt" and "applyAt" (a number n) make the nth audit write, or the nth guarded write, since the counters were killed
/// (^||OcuTalonSettingsOpsProbe("n", seam), a process-private global, which a TROLLBACK does not undo) answer an error status, for the
/// all-or-nothing tests of a section's save (Story 33.2).
/// With ^OcuTalonTest("SettingsOpsProbe", "clash") set to a name (and "clashSession" to a session Ref), the next audit write first stores a webhook row of that
/// name and clears the answer, so that a CreateWebhook's save after its audit entry meets a taken name (Story 35.3 review).
/// The bridge seams BridgeCurrent, BridgeCheck and BridgeSet stand in for Bridge.Settings: each call is recorded under
/// ^OcuTalonTest("SettingsOpsProbe", "bridge", n) as "check" or "set" with the name and value ("what"); the answer "check" is "" for OK, "stub" for
/// "not implemented" (code 5003), "error" for an error status and "error:<name>" for an error status for that name only; the answer "set" is "" for
/// OK and "error" for an error status, "setAt" (a number n) fails the nth Set call only and "throwAt" (a number n) makes it throw. A Set stores the value in
/// ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name) and answers the value it replaced in old. The product never refers to it.
/// The model seams (Story 18.3) BridgeCheckModel, BridgeSetModel, BridgeSetPrice and BridgeTest log each call in order under ^||OcuTalonSettingsOpsProbe("models", n)
/// (a process-private global, which a TROLLBACK does not undo) as "checkModel|agent|provider|model|second", "setModel|agent|provider|model|second",
/// "setPrice|model|prices as JSON" and "test|agent". The answers: "checkModel" is "" for OK, "stub" for "not implemented", "error" for an error status and
/// "error:<Agent>" or "error:<Agent>.second" for that model only; "setModel" is "" for OK and "error" for an error status, "setModelAt" (a number n) fails the nth
/// SetModel call only and "setModelThrowAt" makes it throw; "setPrice" is "" for OK, "error" or "error:<model>", and "setPriceAt" fails the nth SetPrice call only;
/// "test" is "" for an answered test, "timeout", "error" or "refused". A SetModel stores the model in ^OcuTalonTest("SettingsOpsProbe", "bridgeValue",
/// "<Agent>.provider" and ".model", or ".secondProvider" and ".secondModel"), a SetPrice the price in "price.<model>.<key>", and BridgeCurrent reads them.
/// The answer "pass" is a comma-separated list: with "models" the check, set and read of agents' models pass through to Bridge.Settings, and with "prices" the set
/// and read of prices pass through to Bridge.Settings and the real Price rows (the live tests; the test of the rollback of the prices). The answer "audit"
/// "record" writes the real audit entries.
/// The persona seams (Story 40.6): RaiseRequest raises nothing; it records the row's Kind, OwnerRef, TraceRef, DryRun and ResultTarget under
/// ^OcuTalonTest("SettingsOpsProbe", "raised", n, ...) and answers OK with the Ref in ^OcuTalonTest("SettingsOpsProbe", "raiseRef") (a fixed
/// Ref when there is none), or an error status when ^OcuTalonTest("SettingsOpsProbe", "raise") is "error". SendNotice sends nothing; it
/// records the Kind, CatalogKey, Slots, ApprovalRef and SessionRef of each notice in the order sent under
/// ^OcuTalonTest("SettingsOpsProbe", "notices", n, ...) and answers an error status when ^OcuTalonTest("SettingsOpsProbe", "notice") is "error".
/// The roster seam (Story 36.4, DW-1278) SubmitRoster stands in for Commands.Submit of a ListOnCallUsers: it counts its calls in ^OcuTalonTest("SettingsOpsProbe", "roster"),
/// records the uri of each handoff it makes itself under ("roster", "uri", n),
/// and, unless the "roster" answer says otherwise, sends the command to a shadow instance of this class as CommandsIn would (origin web_admin), so that the real
/// handler answers. The "roster" answers: "error" is an error status, "throw" throws, "busy" is an Ok 0 result of outcome busy, "nohandoff" is an Ok 1 result whose
/// handoff names nothing, and "garbled", "notlist", "badrow" and "shortrow" answer Ok 1 with a handoff of their own whose text is not JSON, is not an array, holds a row
/// whose user is not a string, and holds one good row and one row without paired.
Class OcuTalon.Test.Core.SettingsOpsProbe Extends OcuTalon.Core.SettingsOps
{

ClassMethod SubmitRoster(command As OcuTalon.Msg.Command.ListOnCallUsers, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set count = $Increment(^OcuTalonTest("SettingsOpsProbe", "roster"))
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "roster"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz roster submit failed")
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz roster submit threw"))
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	If answer = "busy" {
		Set result.Ok = 0, result.Outcome = "busy"
		Quit $$$OK
	}
	If answer '= "" {
		Set result.Ok = 1, result.Outcome = "listed"
		Set text = $Case(answer, "garbled": "not json", "notlist": "{""user"": ""zzx""}", "badrow": "[{""user"": 5, ""paired"": true}]", "shortrow": "[{""user"": ""zzgood"", ""paired"": false}, {""user"": ""zzbad""}]", : "")
		Set uri = "secret://handoff/00000000000000000000000000000000"
		If text '= "" Do ##class(OcuTalon.Core.SecretHandoff).Put(text, .uri)
		Set ^OcuTalonTest("SettingsOpsProbe", "roster", "uri", count) = $Select(text '= "": uri, 1: "")
		Set result.Data = {"handoff": (uri)}.%ToJSON()
		Quit $$$OK
	}
	Set command.Origin = "web_admin"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.SettingsOpsProbe", .sc)
	If $$$ISERR(sc) Quit sc
	Quit probe.OnMessage(command, .result)
}

Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "calls"))
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit"
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "data") = data.%ToJSON()
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "seen") = ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY)
	If $Get(^OcuTalonTest("SettingsOpsProbe", "clash")) '= "" Do ##class(OcuTalon.Test.Data.Fixture).Webhook($Get(^OcuTalonTest("SettingsOpsProbe", "clashSession")), ^OcuTalonTest("SettingsOpsProbe", "clash"), "zz-ops-clash-0123456789") Kill ^OcuTalonTest("SettingsOpsProbe", "clash")
	If $Increment(^||OcuTalonSettingsOpsProbe("n", "audit")) = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt")) Quit $SYSTEM.Status.Error(5001, "zz audit failed at its turn")
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "audit")) = "record" Quit ##class(OcuTalon.Bridge.Audit).Record("Settings", data)
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "audit")) = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz audit threw"))
	Quit $Select($Get(^OcuTalonTest("SettingsOpsProbe", "answer", "audit")) = "error": $SYSTEM.Status.Error(5001, "zz audit failed"), 1: $$$OK)
}

Method RaiseRequest(row As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String) As %Status [ Private ]
{
	Set ref = ""
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "raised"))
	For name = "Kind", "OwnerRef", "TraceRef", "DryRun", "ResultTarget" {
		Set ^OcuTalonTest("SettingsOpsProbe", "raised", n, name) = $Property(row, name)
	}
	If $Get(^OcuTalonTest("SettingsOpsProbe", "raise")) = "error" Quit $SYSTEM.Status.Error(5001, "zz raise failed")
	Set ref = $Get(^OcuTalonTest("SettingsOpsProbe", "raiseRef"), "zzRaisedRef0000000000A")
	Quit $$$OK
}

Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "notices"))
	For name = "Kind", "CatalogKey", "Slots", "ApprovalRef", "SessionRef" {
		Set ^OcuTalonTest("SettingsOpsProbe", "notices", n, name) = $Property(notification, name)
	}
	If $Get(^OcuTalonTest("SettingsOpsProbe", "notice")) = "error" Quit $SYSTEM.Status.Error(5001, "zz notice failed")
	Quit $$$OK
}

Method RunDemo() As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "calls"))
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "step"
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "seen") = ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY)
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "step"))
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz step threw"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz step failed.")
	If answer = "warn" Do ##class(OcuTalon.Install.Step).Warn("zz warning")
	If answer = "kept" {
		Set sc = ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Install.Step.Demo).#KEPTMARK, $Get(^OcuTalonTest("SettingsOpsProbe", "note")))
		If $$$ISERR(sc) Quit sc
	}
	Quit $$$OK
}

/// The guarded write, failing when the test says so: the value could not be saved.
ClassMethod Apply(key As %String, value As %String) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "apply")) = "error" Quit $SYSTEM.Status.Error(5001, "zz apply failed")
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "apply")) = "second", $Increment(^OcuTalonTest("SettingsOpsProbe", "applies")) = 2 Quit $SYSTEM.Status.Error(5001, "zz apply failed")
	If $Increment(^||OcuTalonSettingsOpsProbe("n", "apply")) = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "applyAt")) Quit $SYSTEM.Status.Error(5001, "zz apply failed at its turn")
	Quit ##super(key, value)
}

Method BridgeCurrent(name As %String) As %String [ Private ]
{
	If (name [ ".") && ..Passes($Select($Extract(name, 1, 6) = "price.": "prices", 1: "models")) Quit ##super(name)
	Quit $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name))
}

/// 1 when the answer "pass" lists the part ("models" or "prices").
Method Passes(part As %String) As %Boolean [ Private ]
{
	Quit ''$ListFind($ListFromString($Get(^OcuTalonTest("SettingsOpsProbe", "answer", "pass"))), part)
}

/// Logs a call of a model seam, in order.
ClassMethod RecordCall(text As %String) [ Private ]
{
	Set n = $Increment(^||OcuTalonSettingsOpsProbe("models"))
	Set ^||OcuTalonSettingsOpsProbe("models", n) = text
}

Method BridgeCheckModel(agent As %String, provider As %String, model As %String, second As %Boolean) As %Status [ Private ]
{
	Do ..RecordCall("checkModel|"_agent_"|"_provider_"|"_model_"|"_+second)
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "checkModel"))
	If answer = "stub" Quit $$$ERROR($$$NotImplemented)
	If (answer = "error") || (answer = ("error:"_agent_$Select(second: ".second", 1: ""))) Quit $SYSTEM.Status.Error(5001, "zz "_agent_" refused")
	If ..Passes("models") Quit ##super(agent, provider, model, second)
	Quit $$$OK
}

Method BridgeSetModel(agent As %String, provider As %String, model As %String, second As %Boolean, Output old As %DynamicObject) As %Status [ Private ]
{
	Set old = {}
	Do ..RecordCall("setModel|"_agent_"|"_provider_"|"_model_"|"_+second)
	Set sets = $Increment(^||OcuTalonSettingsOpsProbe("n", "setModel"))
	If sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setModelThrowAt")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz set model threw"))
	If ($Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setModel")) = "error") || (sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setModelAt"))) Quit $SYSTEM.Status.Error(5001, "zz set model failed")
	If ..Passes("models") Quit ##super(agent, provider, model, second, .old)
	Set prefix = agent_".", names = $Select(second: "secondProvider,secondModel", 1: "provider,model")
	Do old.%Set("provider", $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", prefix_$Piece(names, ",", 1))))
	Do old.%Set("model", $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", prefix_$Piece(names, ",", 2))))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", prefix_$Piece(names, ",", 1)) = provider
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", prefix_$Piece(names, ",", 2)) = model
	Quit $$$OK
}

Method BridgeSetPrice(model As %String, prices As %DynamicObject, Output old As %DynamicObject) As %Status [ Private ]
{
	Set old = {}
	Do ..RecordCall("setPrice|"_model_"|"_prices.%ToJSON())
	Set sets = $Increment(^||OcuTalonSettingsOpsProbe("n", "setPrice"))
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setPrice"))
	If (answer = "error") || (answer = ("error:"_model)) || (sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setPriceAt"))) Quit $SYSTEM.Status.Error(5001, "zz price refused")
	If ..Passes("prices") Quit ##super(model, prices, .old)
	Set iterator = prices.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do old.%Set(key, +$Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "price."_model_"."_key)), "number")
		Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "price."_model_"."_key) = value
	}
	Quit $$$OK
}

Method BridgeTest(agent As %String, Output answer As %DynamicObject, Output refused As %Boolean) As %Status [ Private ]
{
	Set answer = "", refused = 0
	Do ..RecordCall("test|"_agent)
	Set kind = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "test"))
	If kind = "refused" {
		Set refused = 1
		Quit $SYSTEM.Status.Error(5001, "zz agent refused")
	}
	If kind = "error" Quit $SYSTEM.Status.Error(5001, "zz test failed")
	If kind = "timeout" {
		Set answer = {"answered": false, "seconds": 45, "reason": "timeout"}
	} Else {
		Set answer = {"answered": true, "seconds": 0.5, "reason": ""}
	}
	Quit $$$OK
}

Method BridgeCheck(name As %String, value As %String) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "bridge"))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n) = "check"
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n, "what") = name_"="_value
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "check"))
	If answer = "stub" Quit $$$ERROR($$$NotImplemented)
	If (answer = "error") || (answer = ("error:"_name)) Quit $SYSTEM.Status.Error(5001, "zz "_name_" refused")
	Quit $$$OK
}

Method BridgeSet(name As %String, value As %String, Output old As %String) As %Status [ Private ]
{
	Set old = ""
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "bridge"))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n) = "set"
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n, "what") = name_"="_value
	Set sets = $Increment(^||OcuTalonSettingsOpsProbe("n", "set"))
	If sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "throwAt")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz set threw"))
	If ($Get(^OcuTalonTest("SettingsOpsProbe", "answer", "set")) = "error") || (sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setAt"))) Quit $SYSTEM.Status.Error(5001, "zz set failed")
	Set old = $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name) = value
	Quit $$$OK
}

/// The guarded write of SettingsOps, which is private there, for the tests.
ClassMethod Guarded(key As %String, value As %String) As %Status
{
	Quit ..Apply(key, value)
}

}
