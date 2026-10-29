/// StatusMonitor, the service that watches the status of OcuTalon for the page's banners (AD-12, AD-18, AD-33). It is an
/// Ens.InboundAdapter service that runs every CallInterval seconds (15 in the production), and the one publisher of the
/// status live event. Each run:
///   - reads through two private seams, Readings (OcuTalon.Live.Payload.Status.Readings) and Stream (the instance stream), and
///     takes the conditions of OcuTalon.Live.Payload.Status.Computed, the computation that /state shares, and then resetSoon,
///     which ResetSoon builds and /state also calls (Story 16.8);
///   - compares each condition's exported JSON with the one the service remembers from its last run;
///   - publishes a full view of each condition that changed, in the catalog's order, through OcuTalon.Live.Publish. A clear is
///     published as the condition with active false and no slots.
/// The first run after the job starts publishes nothing: it only remembers the state, because the snapshot of /state is computed on
/// read, so a page that loads sees the conditions as they are. The service also publishes the reset event (the one publisher,
/// AD-12) with OcuTalon.Data.Public.Settings.NextReset when that changes, on the online demo only, never an empty value, and
/// with a silent first run. What the service remembers is not durable (AD-5): a restart of the
/// job starts again from a silent first run. A publish that fails is logged as a warning and is not remembered, so that the
/// next run publishes it again. OnProcessInput always returns OK.
/// On the online demo each run also publishes the allowance condition of the sessions whose view changed (Story 16.9, AD-12):
/// AllowanceTick reads the sessions with an open allowance window (the private seam AllowanceSessions, Ownership.AllowanceHeld) and
/// the ones it published as active before, builds each one's OcuTalon.Live.Payload.Status.Allowance and publishes it on that
/// session's own stream (the private seam SessionStream) when its exported
/// JSON differs from the remembered one: the active view when a refusal opened the window, and a clear (active false, no slots)
/// once the window has ended. It remembers the active views only, and forgets a session once its clear is published. The first run
/// only remembers, and a failed read is a warning that remembers nothing. The instance events are unchanged.
/// While demo mode is on, each run also refreshes the guide of every session with a Break the feed run started less than
/// GUIDESECONDS ago (Live.Publish.RefreshGuide), which publishes a guide.state event only when the guide changed: the clock
/// stages of a run move without any row changing (AD-12).
Class OcuTalon.Core.StatusMonitor Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Parameter LOGPUBLISH = "StatusMonitor could not publish a status event: ";

Parameter LOGRUN = "StatusMonitor could not read the status: ";

Parameter LOGALLOWANCE = "StatusMonitor could not publish the allowance status: ";

/// The exported JSON of each condition at the last run that remembered it, by condition. Empty until the first run.
Property Remembered [ MultiDimensional, Private ];

/// The next reset at the last run, whether or not it was published; "" until a run has remembered it.
Property RememberedReset As %String [ Private ];

/// The exported JSON of the allowance condition that was last published or remembered as active, by session Ref. A session that has
/// no entry was last seen with no open window.
Property RememberedAllowance [ MultiDimensional, Private ];

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Set first = '$Data(..Remembered)
	Try {
		Do ..Readings(.keys, .budget)
		Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed(keys, budget)
		Do conditions.Insert(..ResetSoon())
		Set stream = ..Stream()
		For i = 1:1:conditions.Count() {
			Set condition = conditions.GetAt(i)
			Set sc = condition.%JSONExportToString(.json)
			If $SYSTEM.Status.IsError(sc) {
				$$$LOGWARNING(..#LOGPUBLISH_$SYSTEM.Status.GetOneStatusText(sc))
				Continue
			}
			If first {
				Set ..Remembered(condition.Condition) = json
				Continue
			}
			If json = $Get(..Remembered(condition.Condition)) Continue
			Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "status", condition)
			If $SYSTEM.Status.IsError(sc) {
				$$$LOGWARNING(..#LOGPUBLISH_$SYSTEM.Status.GetOneStatusText(sc))
				Continue
			}
			Set ..Remembered(condition.Condition) = json
		}
		Do ..PublishReset(stream, first)
	} Catch exception {
		$$$LOGWARNING(..#LOGRUN_exception.DisplayString())
	}
	Do ..AllowanceTick(first)
	Do ..GuideTick()
	Quit $$$OK
}

/// The allowance statuses of one run, on the online demo only: for each session that has an open window or was remembered as active,
/// Status.Allowance is published on the session's own stream when its exported JSON changed, as the class comment says. first is
/// the run's first-run flag: the first run only remembers the active views. Every error is a warning; nothing throws.
Method AllowanceTick(first As %Boolean) [ Private ]
{
	Try {
		If ##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1 Quit
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set held = ..AllowanceSessions(now, .sc)
		If $SYSTEM.Status.IsError(sc) {
			$$$LOGWARNING(..#LOGALLOWANCE_$SYSTEM.Status.GetOneStatusText(sc))
			Quit
		}
		Kill sessions
		Set position = 0
		While $ListNext(held, position, ref) {
			Set sessions(ref) = ""
		}
		Set ref = ""
		For {
			Set ref = $Order(..RememberedAllowance(ref))
			Quit:ref=""
			Set sessions(ref) = ""
		}
		Set ref = ""
		For {
			Set ref = $Order(sessions(ref))
			Quit:ref=""
			Do ..AllowanceOf(ref, now, first)
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGALLOWANCE_exception.DisplayString())
	}
}

/// The allowance status of one session at now: remembered on the first run, otherwise published when it changed. An error is a
/// warning that remembers nothing.
Method AllowanceOf(sessionRef As %String, now As %String, first As %Boolean) [ Private ]
{
	Try {
		Set condition = ##class(OcuTalon.Live.Payload.Status).Allowance(sessionRef, now)
		Set sc = condition.%JSONExportToString(.json)
		If $SYSTEM.Status.IsError(sc) {
			$$$LOGWARNING(..#LOGALLOWANCE_$SYSTEM.Status.GetOneStatusText(sc))
			Quit
		}
		Set before = $Get(..RememberedAllowance(sessionRef))
		If first {
			If condition.Active Set ..RememberedAllowance(sessionRef) = json
			Quit
		}
		If $Select(condition.Active: json = before, 1: before = "") Quit
		Set sc = ##class(OcuTalon.Live.Publish).Publish(..SessionStream(sessionRef), "status", condition)
		If $SYSTEM.Status.IsError(sc) {
			$$$LOGWARNING(..#LOGALLOWANCE_$SYSTEM.Status.GetOneStatusText(sc))
			Quit
		}
		If condition.Active {
			Set ..RememberedAllowance(sessionRef) = json
		} Else {
			Kill ..RememberedAllowance(sessionRef)
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGALLOWANCE_exception.DisplayString())
	}
}

/// The stream that a session's allowance status is published on: the session's own. Private; a test subclass overrides it.
Method SessionStream(sessionRef As %String) As %String [ Private ]
{
	Quit sessionRef
}

/// The resetSoon condition (AD-12): active on the online demo while the next reset is at most
/// OcuTalon.Data.Public.Settings.#RESETSOONSECONDS ahead (Settings.ResetSoon). It has no slots. now defaults to the current UTC time.
/// /state calls it too, so the banner and the snapshot share this one computation.
ClassMethod ResetSoon(now As %String = "") As OcuTalon.Live.Payload.Status
{
	Set condition = ##class(OcuTalon.Live.Payload.Status).%New()
	Set condition.Condition = "resetSoon"
	Set condition.Active = (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1) && ##class(OcuTalon.Data.Public.Settings).ResetSoon(now)
	Quit condition
}

/// Publishes the reset event (OcuTalon.Live.Payload.Reset) when the next reset differs from the one the last run saw. The run
/// that starts the job only remembers (first). Nothing is published off the online demo or for an empty value. A publish that
/// fails is logged as a warning and not remembered, so the next run publishes it again.
Method PublishReset(stream As %String, first As %Boolean) [ Private ]
{
	Set next = ##class(OcuTalon.Data.Public.Settings).NextReset()
	If first {
		Set ..RememberedReset = next
		Quit
	}
	If next = ..RememberedReset Quit
	If (next = "") || (##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1) {
		Set ..RememberedReset = next
		Quit
	}
	Set payload = ##class(OcuTalon.Live.Payload.Reset).%New()
	Set payload.NextReset = next
	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reset", payload)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGPUBLISH_$SYSTEM.Status.GetOneStatusText(sc))
		Quit
	}
	Set ..RememberedReset = next
}

Parameter LOGGUIDE = "StatusMonitor could not refresh the guide: ";

/// How long after a Break the feed run starts the tick keeps refreshing its session's guide: the 180 s of the longest stage
/// and four 15 s runs of slack.
Parameter GUIDESECONDS = 240;

/// The guide refresh of one run: while demo mode is on, Live.Publish.RefreshGuide for each session with a recent Break the
/// feed run. Every error is a warning; nothing throws.
Method GuideTick() [ Private ]
{
	Try {
		If '##class(OcuTalon.Core.Rule.Functions).DemoOn() Quit
		Set sessions = ##class(OcuTalon.Data.BreakFeedRun).RecentSessions(..#GUIDESECONDS, , .sc)
		If $SYSTEM.Status.IsError(sc) {
			$$$LOGWARNING(..#LOGGUIDE_$SYSTEM.Status.GetOneStatusText(sc))
			Quit
		}
		Set position = 0
		While $ListNext(sessions, position, sessionRef) {
			Set sc = ##class(OcuTalon.Live.Publish).RefreshGuide(sessionRef)
			If $SYSTEM.Status.IsError(sc) {
				$$$LOGWARNING(..#LOGGUIDE_$SYSTEM.Status.GetOneStatusText(sc))
			}
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGGUIDE_exception.DisplayString())
	}
}

/// The readings of this run: OcuTalon.Live.Payload.Status.Readings. A seam for the tests.
Method Readings(Output keys As %DynamicObject, Output budget As %DynamicObject) [ Private ]
{
	Do ##class(OcuTalon.Live.Payload.Status).Readings(.keys, .budget)
}

/// The sessions with an open allowance window at now: Ownership.AllowanceHeld. A seam for the tests.
Method AllowanceSessions(now As %String, Output sc As %Status) As %List [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).AllowanceHeld(now, .sc)
}

/// The stream that the events are published on: the instance stream. A seam for the tests.
Method Stream() As %String [ Private ]
{
	Quit ##class(OcuTalon.Live.Publish).#INSTANCE
}

}
