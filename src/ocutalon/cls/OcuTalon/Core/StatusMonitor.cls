/// StatusMonitor, the service that watches the status of OcuTalon for the page's banners (AD-12, AD-18, AD-33). It is an
/// Ens.InboundAdapter service that runs every CallInterval seconds (15 in the production), and the one publisher of the
/// status live event. Each run:
///   - reads through two private seams, Readings (OcuTalon.Live.Payload.Status.Readings) and Stream (the instance stream), and
///     takes the conditions of OcuTalon.Live.Payload.Status.Computed, the computation that /state shares;
///   - compares each condition's exported JSON with the one the service remembers from its last run;
///   - publishes a full view of each condition that changed, in the catalog's order, through OcuTalon.Live.Publish. A clear is
///     published as the condition with active false and no slots.
/// The first run after the job starts publishes nothing: it only remembers the state, because the snapshot of /state is computed on
/// read, so a page that loads sees the conditions as they are. What the service remembers is not durable (AD-5): a restart of the
/// job starts again from a silent first run. A publish that fails is logged as a warning and is not remembered, so that the
/// next run publishes it again. OnProcessInput always returns OK.
/// While demo mode is on, each run also refreshes the guide of every session with a Break the feed run started less than
/// GUIDESECONDS ago (Live.Publish.RefreshGuide), which publishes a guide.state event only when the guide changed: the clock
/// stages of a run move without any row changing (AD-12).
Class OcuTalon.Core.StatusMonitor Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Parameter LOGPUBLISH = "StatusMonitor could not publish a status event: ";

Parameter LOGRUN = "StatusMonitor could not read the status: ";

/// The exported JSON of each condition at the last run that remembered it, by condition. Empty until the first run.
Property Remembered [ MultiDimensional, Private ];

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Try {
		Do ..Readings(.keys, .budget)
		Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed(keys, budget)
		Set stream = ..Stream()
		Set first = '$Data(..Remembered)
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
	} Catch exception {
		$$$LOGWARNING(..#LOGRUN_exception.DisplayString())
	}
	Do ..GuideTick()
	Quit $$$OK
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

/// The stream that the events are published on: the instance stream. A seam for the tests.
Method Stream() As %String [ Private ]
{
	Quit ##class(OcuTalon.Live.Publish).#INSTANCE
}

}
