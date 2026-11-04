/// A stand-in for the IncidentManager item (Story 4.3; AD-22), put behind the item by Test.Demo.BreakFeedProduction
/// (Test.Agent.RunnerFixture.UseItemClass) in a throwaway. For an IncidentCommand it records, under
/// ^OcuTalonTest("IncidentManagerDouble", "commands", n), the verb, the incident ("ref"), the session, the origin and the number of
/// Break the feed runs that the session has at that moment ("runs"), and answers by ^OcuTalonTest("IncidentManagerDouble", "answer"):
/// "" closes the fixture incident (State closed, ClosedAt now) and answers Ok 1, "refuse" answers Ok 0, and "error" answers an error
/// status. ^OcuTalonTest("IncidentManagerDouble", "delay"), seconds, holds each command before it answers (a press that is slow to close
/// shows whether a second press can get in). Any other request, such as a batch of failures, is answered OK with no response.
/// For the verb dismiss (Story 6.4; AD-15's dismiss rows), after the "error" and "refuse" settings: a resolved incident, or an open one
/// with NoticedAt set, is closed (State closed, ClosedAt now) and saved; any other incident is refused (Ok 0, Outcome refused, Message
/// "zz the double refuses to dismiss an incident that is {state}") and left as it is. After the save, outside any transaction, the double
/// publishes the incident's full view, the newest published incident payload of that ref in its owner's stream with state closed (else
/// Live.Payload.Incident.FromRow), to the owner's stream, or for an instance incident to each session of Session.Recipients.
/// Use and Restore put the double behind the IncidentManager item and take it away again, for the e2e helpers and Test.Web.DismissApi; Recorded
/// says what it recorded about one incident, for the e2e helpers (the browser specs never read the test global themselves).
/// THROWAWAYS AND CI ONLY (Rule 21).
Class OcuTalon.Test.Demo.IncidentManagerDouble Extends Ens.BusinessProcess
{

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If '$IsObject($Get(request)) || 'request.%IsA("OcuTalon.Msg.IncidentCommand") Quit $SYSTEM.Status.OK()
	Set n = $Increment(^OcuTalonTest("IncidentManagerDouble", "commands"))
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n) = request.Verb
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "ref") = request.IncidentRef
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "session") = request.SessionRef
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "origin") = request.Origin
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "runs") = ##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(request.SessionRef)
	Hang +$Get(^OcuTalonTest("IncidentManagerDouble", "delay"))
	Set answer = $Get(^OcuTalonTest("IncidentManagerDouble", "answer"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz the double answers an error")
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	If answer = "refuse" {
		Set response.Ok = 0
		Set response.Outcome = "refused"
		Quit $SYSTEM.Status.OK()
	}
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef)
	If request.Verb = "dismiss" Quit ..Dismiss(incident, response)
	If $IsObject(incident) {
		Set incident.State = "closed"
		Set incident.ClosedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = incident.%Save()
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	Set response.Ok = 1
	Set response.Outcome = "closed"
	Set response.Ref = request.IncidentRef
	Quit $SYSTEM.Status.OK()
}

/// The dismiss rows of AD-15 and the publish of the closed view; the answer is in response.
Method Dismiss(incident As OcuTalon.Data.Incident, response As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	If '$IsObject(incident) {
		Set response.Ok = 0
		Set response.Outcome = "not_found"
		Quit $SYSTEM.Status.OK()
	}
	Set state = incident.State
	If '((state = "resolved") || ((state = "open") && (incident.NoticedAt '= ""))) {
		Set response.Ok = 0
		Set response.Outcome = "refused"
		Set response.Message = "zz the double refuses to dismiss an incident that is "_state
		Quit $SYSTEM.Status.OK()
	}
	Set incident.State = "closed"
	Set incident.ClosedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = incident.%Save()
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set streams = $Select(incident.OwnerRef = ##class(OcuTalon.Data.Ownership).#INSTANCE: ##class(OcuTalon.Data.Session).Recipients(incident.OwnerRef, incident.Ref, .sc), 1: $ListBuild(incident.OwnerRef))
	If $SYSTEM.Status.IsError(sc) Quit sc
	For i = 1:1:$ListLength(streams) {
		Set stream = $List(streams, i)
		Set payload = ..ClosedView(stream, incident)
		Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "incident", payload)
		If $SYSTEM.Status.IsError(sc) Quit
	}
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set response.Ok = 1
	Set response.Outcome = "closed"
	Set response.Ref = incident.Ref
	Quit $SYSTEM.Status.OK()
}

/// The newest incident payload of the incident's ref in the stream with state closed; the payload of the row when the stream holds none.
ClassMethod ClosedView(stream As %String, incident As OcuTalon.Data.Incident) As OcuTalon.Live.Payload.Incident [ Private ]
{
	Set newest = ""
	Set after = 0
	Set more = 1
	While more {
		Set events = ##class(OcuTalon.Live.Event).Since(stream, after)
		Set more = (events.%Size() >= ##class(OcuTalon.Live.Event).#MAXEVENTS)
		For i = 0:1:events.%Size() - 1 {
			Set event = events.%Get(i)
			Set after = event.seq
			If (event.type = "incident") && (event.payload.ref = incident.Ref) Set newest = event.payload
		}
	}
	Set payload = ##class(OcuTalon.Live.Payload.Incident).%New()
	If $IsObject(newest) {
		Set sc = payload.%JSONImport(newest)
		If $SYSTEM.Status.IsError(sc) Set payload = ""
	} Else {
		Set payload = ""
	}
	If '$IsObject(payload) Set payload = ##class(OcuTalon.Live.Payload.Incident).FromRow(incident)
	Set payload.State = "closed"
	Quit payload
}

/// What the double recorded about the incident (the browser specs read it through this, not the global): the commands for the ref, oldest
/// first, each as verb|session|origin, joined by ";". "" when there is none.
ClassMethod Recorded(ref As %String) As %String
{
	Set out = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("IncidentManagerDouble", "commands", n))
		Quit:n=""
		If $Get(^OcuTalonTest("IncidentManagerDouble", "commands", n, "ref")) '= ref Continue
		Set out = out_$Select(out = "": "", 1: ";")_^OcuTalonTest("IncidentManagerDouble", "commands", n)_"|"_$Get(^OcuTalonTest("IncidentManagerDouble", "commands", n, "session"))_"|"_$Get(^OcuTalonTest("IncidentManagerDouble", "commands", n, "origin"))
	}
	Quit out
}

/// Puts the double behind the IncidentManager item of OcuTalon.Production (RunnerFixture.UseItemClass) and keeps what the item had under
/// ^OcuTalonTest("IncidentManagerDoubleUse") (a value left there by an earlier Use that was never restored stays, so Restore puts back the original class). Refuses unless OcuTalon.Production runs. THIS CHANGES THE RUNNING PRODUCTION: throwaways and CI only.
ClassMethod Use() As %Status
{
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Production does not run in "_$Namespace_": the double can't be put behind IncidentManager")
	}
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemClass("IncidentManager", $ClassName(), .saved)
	If $IsObject(saved) && ($Get(^OcuTalonTest("IncidentManagerDoubleUse")) = "") Set ^OcuTalonTest("IncidentManagerDoubleUse") = saved.%ToJSON()
	Kill ^OcuTalonTest("IncidentManagerDouble")
	Quit sc
}

/// Puts the item's class back as Use saved it and kills both nodes. With nothing saved it does nothing and is OK. When the restore
/// fails, the saved class stays under ^OcuTalonTest("IncidentManagerDoubleUse"), so that a later Restore can still put it back.
ClassMethod Restore() As %Status
{
	Set json = $Get(^OcuTalonTest("IncidentManagerDoubleUse"))
	If json = "" {
		Kill ^OcuTalonTest("IncidentManagerDouble")
		Quit $SYSTEM.Status.OK()
	}
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass("IncidentManager", ##class(%DynamicObject).%FromJSON(json))
	If $SYSTEM.Status.IsOK(sc) Kill ^OcuTalonTest("IncidentManagerDoubleUse")
	Kill ^OcuTalonTest("IncidentManagerDouble")
	Quit sc
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
