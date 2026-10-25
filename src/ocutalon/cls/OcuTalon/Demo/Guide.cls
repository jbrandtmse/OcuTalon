/// The demo guide's one derivation (AD-12): Compute(sessionRef) answers the guide.state payload from the session's real rows,
/// read through Data.Ownership, the session's markers (Data.GuideState) and the clock. The page never decides progress itself,
/// and Story 4.3's locked check reads Compute(...).BreakFeed. Blank() is the view of a session with no rows; Live.Publish.RefreshGuide
/// compares against it when a stream has no guide.state event yet.
///   - The Orders production is Install.Step.Demo's NAMESPACE (compared without regard to case) and PRODUCTION.
///   - The current run starts at the epoch's latest Break the feed run, or at GuideState.RunStartedAt when the epoch has no run.
///     Steps 3 and 4, the step 4 variant and the finish read the newest visible Orders incident noticed since then. Step 5 is the
///     trace-opened marker, which only Run again resets.
///   - Break the feed is available while the session watches Orders, no visible Orders incident is open, awaiting approval or
///     fixing, and the session's latest run (of any epoch) has either brought a notice or waited NOTICEWAIT seconds. The stage
///     of the run is reported only for a run of the current epoch.
///   - Telegram counts as on only when the release includes it and TelegramState() says "on"; that stays "off", as /state's
///     telegram block does, until Story 10.3 records the real state.
/// Times are UTC strings YYYY-MM-DDThh:mm:ssZ; ages are whole seconds. Compute throws when a read fails.
Class OcuTalon.Demo.Guide
{

/// The approval request states that mean the user answered it.
Parameter ANSWERED = "approved,rejected,executing,done,failed";

/// The approval request states of an approved fix.
Parameter APPROVEDFIX = "approved,executing,done,failed";

/// The incident open variants that step 4 shows in place of the paired or unpaired text.
Parameter VARIANTS = "rejected,fallback,no_fix";

/// The reasons Break the feed is unavailable.
Parameter REASONS = "not_watching,incident_in_progress";

/// The stages of a run's batch.
Parameter STAGES = "sending,waiting,still_waiting,no_notice,notice_arrived";

/// The seconds after which a batch with no notice is still waiting.
Parameter STILLWAITING = 90;

/// The seconds after which a batch with no notice has none coming, and Break the feed is available again.
Parameter NOTICEWAIT = 180;

/// The number of steps.
Parameter STEPS = 5;

/// The guide of the session. It throws when a read fails.
ClassMethod Compute(sessionRef As %String) As OcuTalon.Live.Payload.GuideState
{
	Set namespace = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Set now = ..Now()

	Set state = ##class(OcuTalon.Data.GuideState).ForSession(sessionRef)
	Set epoch = 1, epochStart = "", traceOpened = 0
	If $IsObject(state) {
		Set epoch = $Select(state.RunEpoch > 0: state.RunEpoch, 1: 1)
		Set epochStart = state.RunStartedAt
		Set traceOpened = ''state.TraceOpened
	}

	Set checks = ##class(OcuTalon.Data.Ownership).Checks(sessionRef, .sc)
	Do ..Check(sc)
	Set watching = 0
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		If (check.Kind = "production") && ($ZConvert(check.Namespace, "U") = $ZConvert(namespace, "U")) && (check.Production = production) {
			Set watching = 1
			Quit
		}
	}

	Set reminder = ##class(OcuTalon.Data.Ownership).ReminderSetOrFired(sessionRef, .sc)
	Do ..Check(sc)

	Set run = ##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(sessionRef, .sc)
	Do ..Check(sc)
	Set epochRun = $IsObject(run) && ((epochStart = "") || (epochStart '] run.StartedAt))
	Set window = $Select(epochRun: run.StartedAt, 1: epochStart)

	Set incident = ##class(OcuTalon.Data.Ownership).NewestIncident(sessionRef, namespace, production, window, .sc)
	Do ..Check(sc)
	Set answered = 0, fixApproved = 0
	If $IsObject(incident) {
		Set approvals = ##class(OcuTalon.Data.Ownership).IncidentApprovals(incident.Ref, sessionRef, .sc)
		Do ..Check(sc)
		For i = 1:1:approvals.Count() {
			Set requestState = approvals.GetAt(i).State
			If $ListFind($ListFromString(..#ANSWERED), requestState) Set answered = 1
			If $ListFind($ListFromString(..#APPROVEDFIX), requestState) Set fixApproved = 1
		}
	}

	Set done = $ListBuild(watching, $IsObject(reminder), $IsObject(incident), answered, traceOpened)

	Set variant = ""
	If $IsObject(incident), $ListFind($ListFromString(..#VARIANTS), incident.OpenVariant) Set variant = incident.OpenVariant
	Set telegramOn = ..TelegramOn()
	Set paired = 0
	If telegramOn {
		Set pairing = ##class(OcuTalon.Data.Ownership).Pairing(sessionRef, .sc)
		Do ..Check(sc)
		Set paired = $IsObject(pairing)
	}
	If variant = "" Set variant = $Select(telegramOn && paired: "paired", 1: "unpaired")
	Set telegramRow = telegramOn && 'paired && '$List(done, 1)

	Set finished = 0
	If traceOpened && fixApproved && $IsObject(incident) {
		Set finished = (incident.State = "resolved") || ((incident.State = "closed") && '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#INCIDENTOPENVARIANT), incident.OpenVariant))
	}

	Set step = ..#STEPS
	For i = 1:1:..#STEPS {
		If '$List(done, i) {
			Set step = i
			Quit
		}
	}
	If (step = ..#STEPS) && $ListFind($ListFromString(..#VARIANTS), variant) Set step = ..#STEPS - 1

	Set active = 0, reason = "", stage = "", startedAt = ""
	If 'watching {
		Set reason = "not_watching"
	} Else {
		Set busy = ##class(OcuTalon.Data.Ownership).IncidentInProgress(sessionRef, namespace, production, .sc)
		Do ..Check(sc)
		Set waiting = 0
		If $IsObject(run) {
			Set runIncident = incident
			If 'epochRun {
				Set runIncident = ##class(OcuTalon.Data.Ownership).NewestIncident(sessionRef, namespace, production, run.StartedAt, .sc)
				Do ..Check(sc)
			}
			Set noticed = $IsObject(runIncident)
			Set age = run.Age(now)
			Set waiting = 'noticed && (age < ..#NOTICEWAIT)
			If epochRun {
				Set startedAt = run.StartedAt
				Set stage = $Case(1,
					noticed: "notice_arrived",
					age >= ..#NOTICEWAIT: "no_notice",
					run.State = "sending": "sending",
					age >= ..#STILLWAITING: "still_waiting",
					: "waiting")
			}
		}
		If $IsObject(busy) || waiting {
			Set reason = "incident_in_progress"
		} Else {
			Set active = 1
		}
	}
	Quit ..View(epoch, done, step, finished, active, reason, stage, startedAt, variant, telegramRow)
}

/// The view of a session with no rows: epoch 1, step 1, nothing done, Break the feed unavailable because nothing is watched.
ClassMethod Blank() As OcuTalon.Live.Payload.GuideState
{
	Quit ..View(1, $ListBuild(0, 0, 0, 0, 0), 1, 0, 0, "not_watching", "", "", "unpaired", 0)
}

/// 1 when demo mode is on: the demo.mode setting is "1".
ClassMethod DemoOn() As %Boolean
{
	Try {
		Set on = (##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) = "1")
	} Catch {
		Set on = 0
	}
	Quit on
}

/// The current time in UTC. A seam for the tests.
ClassMethod Now() As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).NowUtc()
}

/// 1 when Telegram counts as on: the release includes it and its recorded state is "on". A seam for the tests.
ClassMethod TelegramOn() As %Boolean [ Private ]
{
	Quit ''##class(OcuTalon.Channel.Telegram.In).Included() && (..TelegramState() = "on")
}

/// The Telegram state as /state reports it: "off" until Story 10.3 records the real state.
ClassMethod TelegramState() As %String [ Private ]
{
	Quit "off"
}

/// The payload of the arguments; done is a list of the five steps' flags.
ClassMethod View(epoch As %Integer, done As %List, step As %Integer, finished As %Boolean, active As %Boolean, reason As %String, stage As %String, startedAt As %String, variant As %String, telegramRow As %Boolean) As OcuTalon.Live.Payload.GuideState [ Private ]
{
	Set view = ##class(OcuTalon.Live.Payload.GuideState).%New()
	Set view.RunEpoch = epoch
	Set view.Step = step
	Set view.Finished = finished
	For i = 1:1:..#STEPS {
		Set row = ##class(OcuTalon.Live.Payload.Part.GuideStep).%New()
		Set row.Step = i
		Set row.Done = $List(done, i)
		Do view.Steps.Insert(row)
	}
	Set view.BreakFeed = ##class(OcuTalon.Live.Payload.Part.GuideBreakFeed).%New()
	Set view.BreakFeed.Active = active
	Set view.BreakFeed.Reason = reason
	Set view.BreakFeed.Stage = stage
	Set view.BreakFeed.StartedAt = startedAt
	Set view.Step4Variant = variant
	Set view.TelegramRow = telegramRow
	Quit view
}

/// Throws the error of a status that is not OK.
ClassMethod Check(sc As %Status) [ Private ]
{
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
}

}
