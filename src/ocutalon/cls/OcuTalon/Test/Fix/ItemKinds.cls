/// Tests of the fix kinds that suspend and resume an item of a watched production (Story 23.2; AD-3, AD-16, AD-24). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (FixExecutor is code of the running production), with demo mode on, through Test.Watch.Case: they need the running OcuTalon.Production and the Orders demo production with its item
/// OrdersForReview in OCUORDERS. The items they change are the item OrdersForReview, enabled again after each test (Case keeps the list of the items to enable).
///   - TestLiveSuspendResume (Task 0, AC3, AC8): the dry run is asked of the real FixExecutor and changes nothing; an approved suspend request is carried out by FixExecutor's own job,
///     which calls Ens.Director.EnableConfigItem in OCUORDERS (Fix.Executor.InProduction): OrdersForReview is disabled, the FixResult holds 1/0/1/0/0, the incident is resolved, the
///     session gets result.itemSuspended, and one Action entry names the item, the production and the namespace; then the same for resume. The measured figures are logged and
///     printed as SKIP lines (a status 2 never fails a class);
///   - TestKindParameters, TestCheckParameters and TestGrants (AC9, AC-S1): the parameters of the kinds, their schema check and the grants of the service role on a local and an
///     online-demo install;
///   - TestDryRunsChangeNothing, TestOnlineDemoRefused and TestOwnProduction (AC1, AC8, AC11): the dry runs, their refusals and what they leave unchanged;
///   - TestRecheckSkips (AC3): the item changed since the dry run is skipped, with a reason that names it;
///   - TestNotAllowed (AC9, AC-S1; the matrix row "Missing resource"): on an online-demo install (the public flag on, %Ens_ConfigItemRun not held by the service role), an
///     approved item run that bypasses the ONLINESHARED check could not start;
///   - TestItemThatCannotBeChanged (AC3, AC8): through FixExecutor's handler with the Check and Carry seams of Test.Fix.ExecutorProbe: a change that Ens.Director.EnableConfigItem refuses ends the request
///     failed with the kind's NOSTART and the session reads result.itemNotChanged, and items that can't be read end it failed with the kind's NOREAD;
///   - TestNoApprovedRow (AC8): a pending request is not carried out.
Class OcuTalon.Test.Fix.ItemKinds Extends OcuTalon.Test.Watch.Case
{

/// The item of the Orders production that the live tests change.
Parameter ITEM = "OrdersForReview";

Method TestKindParameters()
{
	Set kinds = $ListBuild("OcuTalon.Fix.Kind.SuspendItem", "OcuTalon.Fix.Kind.ResumeItem", "OcuTalon.Fix.Kind.Reroute")
	Set position = 0
	While $ListNext(kinds, position, class) {
		Do $$$AssertTrue($ListFind(##class(OcuTalon.Fix.Kind).Classes(), class) > 0, class_" is a registered kind")
		Do $$$AssertEquals($Parameter(class, "ASKED"), 1, class_" may be asked for in the chat")
		Do $$$AssertEquals($Parameter(class, "DIAGNOSED"), 0, class_" is never named by the diagnosis")
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Fix.Kind.SuspendItem", "NAME")_"|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "PARAMETERS")_"|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "RESOURCES")_"|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "TARGETTYPE")_"|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "ENABLE"), "suspend_item|item|%Ens_ConfigItemRun:U|item|0", "suspend_item")
	Do $$$AssertEquals($Parameter("OcuTalon.Fix.Kind.ResumeItem", "NAME")_"|"_$Parameter("OcuTalon.Fix.Kind.ResumeItem", "PARAMETERS")_"|"_$Parameter("OcuTalon.Fix.Kind.ResumeItem", "RESOURCES")_"|"_$Parameter("OcuTalon.Fix.Kind.ResumeItem", "TARGETTYPE")_"|"_$Parameter("OcuTalon.Fix.Kind.ResumeItem", "ENABLE"), "resume_item|item|%Ens_ConfigItemRun:U|item|1", "resume_item")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Fix.Kind.ResumeItem", "%Extends", "OcuTalon.Fix.Kind.SuspendItem"), "ResumeItem extends SuspendItem")
	Do $$$AssertEquals($Parameter("OcuTalon.Fix.Kind.Reroute", "NAME")_"|"_$Parameter("OcuTalon.Fix.Kind.Reroute", "PARAMETERS")_"|"_$Parameter("OcuTalon.Fix.Kind.Reroute", "RESOURCES")_"|"_$Parameter("OcuTalon.Fix.Kind.Reroute", "TARGETTYPE"), "reroute|target|%Ens_MessageResend:U|message", "reroute")
	Do $$$AssertEquals($Parameter("OcuTalon.Fix.Kind.RepairResend", "DIAGNOSED")_"|"_$Parameter("OcuTalon.Fix.Kind.RepairResend", "ASKED")_"|"_$Parameter("OcuTalon.Fix.Kind.RepairResend", "TARGETTYPE"), "1|0|message", "repair_resend stays the diagnosis's kind")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Fix.Kind).DiagnosedNames()), "repair_resend", "the diagnosis may name repair_resend only")
	Do $$$AssertTrue('##class(OcuTalon.Fix.Kind).Diagnosed("reroute") && '##class(OcuTalon.Fix.Kind).Diagnosed("suspend_item") && '##class(OcuTalon.Fix.Kind).Diagnosed("resume_item"), "and none of the three new kinds")
}

Method TestCheckParameters()
{
	For class = "OcuTalon.Fix.Kind.SuspendItem", "OcuTalon.Fix.Kind.ResumeItem" {
		Do $$$AssertStatusOK($ClassMethod(class, "CheckParameters", {"item": "OrdersForReview"}, ""), class_": an item name passes")
		Do $$$AssertStatusNotOK($ClassMethod(class, "CheckParameters", {}, ""), class_": no item is refused")
		Do $$$AssertStatusNotOK($ClassMethod(class, "CheckParameters", {"item": "  "}, ""), class_": a blank item is refused")
		Do $$$AssertStatusNotOK($ClassMethod(class, "CheckParameters", {"item": 7}, ""), class_": an item that is not a string is refused")
		Do $$$AssertStatusNotOK($ClassMethod(class, "CheckParameters", {"item": "A", "target": "B"}, ""), class_": another parameter is refused")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind.Reroute).CheckParameters({"target": "OrdersForReview"}, ""), "reroute: a target name passes")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind.Reroute).CheckParameters({"item": "OrdersForReview"}, ""), "reroute: an item is refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("suspend_item", {"item": "OrdersForReview"}, []), "Kind.Check, the diagnosis's check, refuses a kind it may not name, with valid parameters")
}

/// AC-S1: a local install's service role holds %Ens_ConfigItemRun:U, an online-demo install's does not, and the other kinds keep their grants.
Method TestGrants()
{
	Set kinds = ##class(OcuTalon.Fix.Kind).Classes()
	Set local = ..Pairs(##class(OcuTalon.Install.Step.Fix).GrantsOf(kinds, 0))
	Set online = ..Pairs(##class(OcuTalon.Install.Step.Fix).GrantsOf(kinds, 1))
	Do $$$AssertTrue(local [ "|%Ens_ConfigItemRun:U|", "a local install grants %Ens_ConfigItemRun:U: "_local)
	Do $$$AssertTrue(local [ "|%Ens_MessageResend:U|", "and %Ens_MessageResend:U")
	Do $$$AssertTrue(online '[ "%Ens_ConfigItemRun", "an online-demo install grants no %Ens_ConfigItemRun: "_online)
	Do $$$AssertTrue(online [ "|%Ens_MessageResend:U|", "but still %Ens_MessageResend:U")
	Set onlineDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	If onlineDemo '= 1 Do $$$AssertTrue(..RoleResources() [ "%Ens_ConfigItemRun:U", "and the service role of this local install holds it")
	Do ..SetOnlineDemo(1)
	Set held = ..Pairs(##class(OcuTalon.Install.Step.Fix).Grants())
	Do $$$AssertTrue(held '[ "%Ens_ConfigItemRun", "Grants() with the public flag on holds no %Ens_ConfigItemRun: "_held)
	Do $$$AssertTrue(held [ "|%Ens_MessageResend:U|", "but %Ens_MessageResend:U")
	Do ..SetOnlineDemo(0)
	Set held = ..Pairs(##class(OcuTalon.Install.Step.Fix).Grants())
	Do $$$AssertTrue(held [ "|%Ens_ConfigItemRun:U|", "Grants() with the public flag off holds %Ens_ConfigItemRun:U: "_held)
	Do $$$AssertTrue(##class(OcuTalon.Install.Step.Roles).#FORBIDDEN '[ "%Ens_ConfigItemRun", "%Ens_ConfigItemRun is not a forbidden resource")
}

/// The grants as "|resource:permission|..." text.
ClassMethod Pairs(grants As %DynamicArray) As %String [ Private ]
{
	Set text = "|"
	Set iterator = grants.%GetIterator()
	While iterator.%GetNext(, .grant) {
		Set text = text_grant.resource_":"_grant.permission_"|"
	}
	Quit text
}

/// The dry runs of the three kinds read the items and change nothing; a name that is not an item, and an item that already is in the state, are refused with a reason that names them.
Method TestDryRunsChangeNothing()
{
	If '..Ready() Quit
	Set a = ..Session("itemdry")
	Set incident = ..Fixture(a, "1")
	Set before = ..ItemStates()
	Do $$$AssertTrue(before [ (..#ITEM_"=1"), "OrdersForReview is enabled: "_before)

	Set sc = ##class(OcuTalon.Fix.Kind.SuspendItem).DryRun(incident, {"item": (..#ITEM)}, .targets, .dryRun)
	Do $$$AssertStatusOK(sc, "the suspend dry run is worked out")
	Set id = ..ItemId(..#ITEM)
	Do $$$AssertEquals(targets, id, "its target is the item's Ens.Config.Item id")
	Do $$$AssertEquals($Get(dryRun) '= "" && (dryRun.%ToJSON() = {"item": (..#ITEM), "before": "enabled", "after": "disabled"}.%ToJSON()), 1, "and the dry run is the item, enabled before and disabled after: "_$Select($IsObject($Get(dryRun)): dryRun.%ToJSON(), 1: ""))
	Set sc = ##class(OcuTalon.Fix.Kind.ResumeItem).DryRun(incident, {"item": (..#ITEM)}, .targets, .dryRun)
	Do $$$AssertStatusNotOK(sc, "the resume dry run of an enabled item is refused")
	Do $$$AssertEquals(..Text(sc), ..#ITEM_" is already enabled", "with the reason that names it")
	Set sc = ##class(OcuTalon.Fix.Kind.SuspendItem).DryRun(incident, {"item": "NoSuchItem"}, .targets, .dryRun)
	Do $$$AssertEquals(..Text(sc), "NoSuchItem is not an item of Orders", "an unknown item is refused, naming the production by its display name")
	Do $$$AssertEquals(targets_"|"_dryRun, "|", "and gives no target and no dry run")

	// the reroute dry run: the target must be a different, enabled process or operation
	Set sc = ##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": "NoSuchItem"}, .targets, .dryRun)
	Do $$$AssertEquals(..Text(sc), "NoSuchItem is not an item of Orders", "reroute: an unknown target is refused")
	Set sc = ##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": "PartnerOrdersIn"}, .targets, .dryRun)
	Do $$$AssertEquals(..Text(sc), "PartnerOrdersIn is a business service, which can't take rerouted messages", "reroute: a business service is refused")
	Do $$$AssertEquals(..ItemStates(), before, "no item changed")
}

/// On the online demo the two item kinds refuse every item with ONLINESHARED, and the reroute is not refused for that reason.
Method TestOnlineDemoRefused()
{
	If '..Ready() Quit
	Set a = ..Session("itemonline")
	Set incident = ..Fixture(a, "1")
	Do ..SetOnlineDemo(1)
	Set before = ..ItemStates()
	For class = "OcuTalon.Fix.Kind.SuspendItem", "OcuTalon.Fix.Kind.ResumeItem" {
		For item = ..#ITEM, "OrdersToWarehouse", "NoSuchItem" {
			Set sc = $ClassMethod(class, "DryRun", incident, {"item": (item)}, .targets, .dryRun)
			Do $$$AssertEquals(..Text(sc), $Parameter("OcuTalon.Fix.Kind.SuspendItem", "ONLINESHARED"), class_", "_item_": refused with ONLINESHARED")
			Do $$$AssertEquals(targets, "", "and no target")
		}
	}
	Set sc = ##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": (..#ITEM)}, .targets, .dryRun)
	Do $$$AssertStatusOK(sc, "the reroute is offered on the online demo")
	Do $$$AssertEquals(..ItemStates(), before, "nothing changed")
}

/// An item of OcuTalon's own production is refused with OWNPRODUCTION, before anything is read.
Method TestOwnProduction()
{
	Set own = ##class(OcuTalon.Install.Step.Production).#PRODUCTION
	Set incident = ##class(OcuTalon.Data.Incident).%New()
	Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set incident.Namespace = $Namespace
	Set incident.Production = own
	For class = "OcuTalon.Fix.Kind.SuspendItem", "OcuTalon.Fix.Kind.ResumeItem" {
		Set sc = $ClassMethod(class, "DryRun", incident, {"item": "FixExecutor"}, .targets, .dryRun)
		Do $$$AssertEquals(..Text(sc), $Parameter("OcuTalon.Fix.Kind.SuspendItem", "OWNPRODUCTION"), class_": an item of OcuTalon's own production is refused")
		Do $$$AssertEquals(targets, "", "and gives no target")
		Do $$$AssertStatusOK($ClassMethod(class, "Recheck", incident, {"item": "FixExecutor"}, "1", .passed, .skipped), class_": the re-check answers")
		Do $$$AssertEquals(passed_"|"_skipped.%Size(), "|1", "and passes nothing")
	}
}

/// The re-check passes the item that is as the dry run saw it, and skips, with a reason that names the item, one that is gone or is in the other state.
Method TestRecheckSkips()
{
	If '..Ready() Quit
	Set a = ..Session("itemrecheck")
	Set incident = ..Fixture(a, "1")
	Set id = ..ItemId(..#ITEM)
	Set parameters = {"item": (..#ITEM)}
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind.SuspendItem).Recheck(incident, parameters, id, .passed, .skipped), "the suspend re-check answers")
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), id_"|0", "an enabled item passes the suspend re-check")
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind.ResumeItem).Recheck(incident, parameters, id, .passed, .skipped), "the resume re-check answers")
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), "|1", "an enabled item does not pass the resume re-check")
	Do $$$AssertEquals(skipped.%Get(0).reason, ..#ITEM_" changed since the dry run", "it is skipped with the reason that names it")
	Set other = ..ItemId("OrdersToWarehouse")
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind.SuspendItem).Recheck(incident, parameters, other, .passed, .skipped), "the re-check of another item's id answers")
	Do $$$AssertEquals(passed_"|"_skipped.%Get(0).reason, "|"_..#ITEM_" is no longer in the production", "an id that no longer names the item is skipped")
	Do $$$AssertEquals(..ItemStates() [ (..#ITEM_"=1"), 1, "and the re-checks changed nothing")
}

/// The live case, carried out by the real FixExecutor (Task 0): see the class description.
Method TestLiveSuspendResume()
{
	If '..Ready() Quit
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ConfigItemRun", "U"), 1, "the service user "_user_" holds %Ens_ConfigItemRun:U after the Fix step")
	Set a = ..Session("itemlive")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..Watch(a)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now)})
	Set incident = row.Ref
	Kill row
	Set namespaces = $ListBuild(..#ORDERS)
	Set before = ..ItemStates()
	Do $$$AssertTrue(before [ (..#ITEM_"=1"), "OrdersForReview is enabled: "_before)
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

	// the suspend: the dry run goes to the real FixExecutor and changes nothing
	Set answer = ..AskDryRun(incident, "suspend_item", {"item": (..#ITEM)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers the dry run")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Reason, "", "without a reason")
	Do $$$AssertEquals(answer.Targets, ..ItemId(..#ITEM), "its target is the item's id")
	Do $$$AssertEquals(answer.DryRun, {"item": (..#ITEM), "before": "enabled", "after": "disabled"}.%ToJSON(), "and the dry run is the item, enabled before, disabled after")
	Do $$$AssertEquals(..ItemStates(), before, "the dry run changed no item")
	Set suspend = ..Request(a, incident, "suspend_item", {"item": (..#ITEM)}.%ToJSON(), answer.Targets, answer.DryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = suspend
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	// the item is enabled again after the test, whatever happens
	Set ..DisabledItems = ..DisabledItems_$ListBuild(..#ITEM)

	Set start = $ZHorolog
	Do $$$AssertStatusOK(..SendExecute(suspend, .session), "the Execute is handled by FixExecutor's job")
	Set seconds = $ZHorolog - start
	Do $$$AssertEquals(..ItemStates() [ (..#ITEM_"=0"), 1, "OrdersForReview is disabled in OCUORDERS (Watch.Reader sees it)")
	Set results = ..WaitFixResults(suspend, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.interrupted_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped_"|"_result.unreached, "1|0|1|0|1|0|0|0", "it is final and holds Total 1, Resent 0, Completed 1")
	}
	Do $$$AssertEquals(..WaitState(incident, suspend, "done"), "done", "the request is done")
	Set runs = ..Runs(incident)
	Do $$$AssertEquals(runs.%Size(), 1, "one FixRun")
	If runs.%Size() = 1 Do $$$AssertEquals(runs.%Get(0).copies.%Size()_"|"_runs.%Get(0).total_"|"_runs.%Get(0).completed_"|"_(runs.%Get(0).endedAt '= ""), "0|1|1|1", "which holds no copy, Total 1 and Completed 1, and has ended")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "the incident is resolved")
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "result.itemSuspended|"_suspend, "result.itemSuspended with the request's Ref")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), ..#ITEM_" in Orders is suspended: it is disabled now. To undo it, ask me to resume "_..#ITEM_".", "which says what happened")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", suspend, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, "one Action entry names the request")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.action_"|"_data.target_"|"_data.result, "suspend_item|"_..#ITEM_" in "_..#ORDERSPRODUCTION_" in "_..#ORDERS_"|done", "with the item, the production and the namespace")
	}

	// the resume: the undo, with its own dry run
	Set answer = ..AskDryRun(incident, "resume_item", {"item": (..#ITEM)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers the resume dry run")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.DryRun, {"item": (..#ITEM), "before": "disabled", "after": "enabled"}.%ToJSON(), "the item is disabled before and enabled after")
	Set resume = ..Request(a, incident, "resume_item", {"item": (..#ITEM)}.%ToJSON(), answer.Targets, answer.DryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.State = "fixing"
	Set row.RequestRefs = row.RequestRefs_","_resume
	Do $$$AssertStatusOK(row.%Save(), "the incident names the second request")
	Kill row
	Set start = $ZHorolog
	Do $$$AssertStatusOK(..SendExecute(resume, .session), "the Execute of the resume is handled")
	Set resumeSeconds = $ZHorolog - start
	Do $$$AssertEquals(..ItemStates() [ (..#ITEM_"=1"), 1, "OrdersForReview is enabled again")
	Set at = $ListFind(..DisabledItems, ..#ITEM)
	If at Set ..DisabledItems = $List(..DisabledItems, 1, at - 1)_$List(..DisabledItems, at + 1, *)
	Do $$$AssertEquals(..WaitState(incident, resume, "done"), "done", "the resume request is done")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "and the incident is resolved again")
	Do $$$AssertEquals(..ItemStates(), before, "every item is as it was")
	Do ..Timing("Task 0: Ens.Director.EnableConfigItem from FixExecutor's job in OCUORDERS: suspend "_$FNumber(seconds, "", 3)_" s, resume "_$FNumber(resumeSeconds, "", 3)_" s (SendExecute to the end of the handler)")
}

/// With %Ens_ConfigItemRun taken from the service role the run could not start: the item is not changed, the request failed with the kind's reason, and the session reads
/// result.itemNotChanged. The run is that of an online-demo install (AC-S1): the public flag onlineDemo is on and the service role holds no %Ens_ConfigItemRun, as
/// Install.Step.Fix.Grants() leaves it there, and the approved row reaches the executor with no dry run, so the kind's ONLINESHARED check is bypassed.
Method TestNotAllowed()
{
	If '..Ready() Quit
	Set a = ..Session("itemnores")
	Do ..Watch(a)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now)})
	Set incident = row.Ref
	Kill row
	Set before = ..ItemStates()
	Set ref = ..Request(a, incident, "suspend_item", {"item": (..#ITEM)}.%ToJSON(), ..ItemId(..#ITEM), {"item": (..#ITEM), "before": "enabled", "after": "disabled"}.%ToJSON())
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = ref
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	Do ..RevokeRole("%Ens_ConfigItemRun")
	Do ..SetOnlineDemo(1)
	Do $$$AssertTrue(..RoleResources() '[ "%Ens_ConfigItemRun", "the service role holds no %Ens_ConfigItemRun, as on an online-demo install")
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute is handled")
	Do $$$AssertEquals(..WaitState(incident, ref, "failed"), "failed", "the request failed")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.total_"|"_result.resent_"|"_result.completed_"|"_result.skipped_"|"_result.reason, "1|0|0|0|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "NOTALLOWED"), "Total 1, nothing changed, and the kind's reason")
	}
	Do $$$AssertEquals(..ItemStates(), before, "no item changed")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "the incident is resolved")
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey, "result.itemNotChanged", "result.itemNotChanged")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "Nothing was changed: OcuTalon isn't allowed to suspend or resume items in that production.", "which says that nothing was changed")
	}
}

/// An item that is not as the dry run saw it when the approved request runs is skipped: nothing is changed and the session reads result.itemSkipped.
Method TestItemChangedSinceDryRun()
{
	If '..Ready() Quit
	Set a = ..Session("itemchanged")
	Do ..Watch(a)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now)})
	Set incident = row.Ref
	Kill row
	Set id = ..ItemId(..#ITEM)
	Set ref = ..Request(a, incident, "suspend_item", {"item": (..#ITEM)}.%ToJSON(), id, {"item": (..#ITEM), "before": "enabled", "after": "disabled"}.%ToJSON())
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = ref
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	// someone else disables the item after the dry run
	Do $$$AssertStatusOK(..SetItemEnabled(0, ..#ITEM), "the item is disabled by someone else")
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute is handled")
	Do $$$AssertEquals(..WaitState(incident, ref, "done"), "done", "the run ends")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.total_"|"_result.resent_"|"_result.completed_"|"_result.skipped_"|"_result.reason, "1|0|0|1|"_..#ITEM_" changed since the dry run", "Total 1, Skipped 1, with the reason that names the item")
	}
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey, "result.itemSkipped", "result.itemSkipped")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), ..#ITEM_" was not changed: "_..#ITEM_" changed since the dry run. It needs a new approval.", "which says that the item needs a new approval")
	}
	Do $$$AssertStatusOK(..SetItemEnabled(1, ..#ITEM), "the item is enabled again")
}

/// A suspend whose change the production refuses (Ens.Director.EnableConfigItem answers an error, so the item is unreached; the Carry seam gives that answer) ends as could not
/// start: the request is failed, nothing was changed, the reason is the kind's NOSTART and the session reads result.itemNotChanged. Items that can't be read end it with the kind's NOREAD.
Method TestItemThatCannotBeChanged()
{
	Set a = ..Session("itemerr")
	Do ..SetOnlineDemo(0)
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Fix.ExecutorProbe", .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the executor probe is made")
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.StateIs = "running"
	Set parameters = {"item": (..#ITEM)}.%ToJSON()
	Set dryRun = {"item": (..#ITEM), "before": "enabled", "after": "disabled"}.%ToJSON()

	// the change is refused: the item was found and EnableConfigItem answered an error
	Set row = ..Fixture(a, "1", "ZZNS", "Zz.ItemKinds", "h", {"State": "fixing", "OpenVariant": ""})
	Set incident = row.Ref
	Kill row
	Set ref = ..Request(a, incident, "suspend_item", parameters, "7", dryRun)
	Set host.CheckIs = "{""passed"":""7"",""skipped"":[]}"
	Set host.CarryIs = "{""copies"":[],""skipped"":[],""unreached"":[{""id"":7,""code"":""refused""}]}"
	Do $$$AssertStatusOK(..Handle(host, ref), "the Execute is handled")
	Set last = ..Last(host)
	Do $$$AssertTrue($IsObject(last), "a FixResult was sent")
	If $IsObject(last) {
		Do $$$AssertEquals(last.final_"|"_last.total_"|"_last.resent_"|"_last.completed_"|"_last.skipped_"|"_last.reason, "1|1|0|0|0|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "NOSTART"), "it holds Total 1, nothing changed and the kind's NOSTART")
		Do $$$AssertEquals(last.storedState, "failed", "the request is failed")
		Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
		Set result.Final = last.final
		Set result.Total = last.total
		Set result.Reason = last.reason
		Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey(last.storedState, result, "suspend_item"), "result.itemNotChanged", "and the session reads result.itemNotChanged")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State, "failed", "the stored request is failed")

	// the items can't be read (the namespace is not one the service user reads): the kind's own Recheck throws, and the run ends as could not read
	Set row = ..Fixture(a, "1", "ZZNS", "Zz.ItemKinds", "h", {"State": "fixing", "OpenVariant": ""})
	Set incident = row.Ref
	Kill row
	Set ref = ..Request(a, incident, "suspend_item", parameters, "7", dryRun)
	Set host.CheckIs = ""
	Set host.CarryIs = ""
	Do $$$AssertStatusOK(..Handle(host, ref), "the Execute of the unreadable items is handled")
	Set last = ..Last(host)
	Do $$$AssertTrue($IsObject(last), "a FixResult was sent for it")
	If $IsObject(last) Do $$$AssertEquals(last.final_"|"_last.total_"|"_last.completed_"|"_last.reason, "1|1|0|"_$Parameter("OcuTalon.Fix.Kind.SuspendItem", "NOREAD"), "it holds Total 1 and the kind's NOREAD")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State, "failed", "the request is failed")
}

/// Hands the probe an Execute for the Ref; the status.
Method Handle(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String) As %Status [ Private ]
{
	Set request = ##class(OcuTalon.Fix.Msg.Execute).%New()
	Set request.ApprovalRef = ref
	Set response = ""
	Quit host.OnMessage(request, .response)
}

/// The FixResult that the probe recorded last, "" when it recorded none.
ClassMethod Last(host As OcuTalon.Test.Fix.ExecutorProbe) As %DynamicObject [ Private ]
{
	If '$IsObject(host.Results) || (host.Results.%Size() = 0) Quit ""
	Quit host.Results.%Get(host.Results.%Size() - 1)
}

/// A request that is not approved is not carried out.
Method TestNoApprovedRow()
{
	If '..Ready() Quit
	Set a = ..Session("itemnorow")
	Set row = ..Fixture(a, "1")
	Set incident = row.Ref
	Kill row
	Set before = ..ItemStates()
	For state = "pending", "rejected", "expired", "cancelled" {
		Set ref = ..Request(a, incident, "suspend_item", {"item": (..#ITEM)}.%ToJSON(), ..ItemId(..#ITEM), {"item": (..#ITEM), "before": "enabled", "after": "disabled"}.%ToJSON(), state)
		Do $$$AssertStatusOK(..SendExecute(ref, .session), state_": the Execute is handled")
		Do $$$AssertEquals(..ItemStates(), before, state_": no item changed")
		Do $$$AssertEquals(..Runs(incident).%Size(), 0, state_": no FixRun is written")
	}
}

/// --- helpers ---
/// Makes a measured value visible in the output of a run that passes: a log message, and an assert of the status skipped, which ci/iris.sh prints as "SKIP <method>: <text>". It
/// does not set SkipTest, so the rest of the test runs.
Method Timing(text As %String) [ Private ]
{
	Do $$$LogMessage(text)
	Do ..Manager.LogAssert(2, "Timing", text)
}

/// A suspend or resume request of the owner for the incident in the state (approved by default), with the parameters, targets and dry run given; its Ref.
Method Request(owner As %String, incident As %String, kind As %String, parameters As %String, targets As %String, dryRun As %String, state As %String = "approved") As %String [ Private ]
{
	Set fields = {"FixKind": (kind), "FixTargets": (targets), "FixParameters": (parameters), "DryRun": (dryRun), "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , fields)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// The enabled state of each item of the Orders production as "Name=1,Name=0,...", in id order.
Method ItemStates() As %String [ Private ]
{
	Set outcome = ##class(OcuTalon.Watch.Reader).Items(..#ORDERS, ..#ORDERSPRODUCTION, .items)
	If outcome '= "read" Quit "<"_outcome_">"
	Set text = ""
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set text = text_$Select(text = "": "", 1: ",")_item.name_"="_item.enabled
	}
	Quit text
}

/// The Ens.Config.Item id of the item of the Orders production, "" when there is none.
Method ItemId(name As %String) As %String [ Private ]
{
	Set outcome = ##class(OcuTalon.Watch.Reader).Items(..#ORDERS, ..#ORDERSPRODUCTION, .items)
	Set item = ##class(OcuTalon.Fix.Kind).ItemNamed(items, name)
	Quit $Select($IsObject(item): item.id, 1: "")
}

/// The first error text of a status, without its "ERROR #n:" start.
ClassMethod Text(sc As %Status) As %String [ Private ]
{
	Set text = $SYSTEM.Status.GetOneErrorText(sc)
	If $Extract(text, 1, 7) = "ERROR #" Set text = $ZStrip($Piece(text, ":", 2, *), "<W")
	Quit text
}

}
