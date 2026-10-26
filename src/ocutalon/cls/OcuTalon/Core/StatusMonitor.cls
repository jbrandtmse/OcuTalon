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
Class OcuTalon.Core.StatusMonitor Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Parameter LOGPUBLISH = "StatusMonitor could not publish a status event: ";

Parameter LOGRUN = "StatusMonitor could not read the status: ";

/// The exported JSON of each condition at the last run that remembered it, by condition. Empty until the first run.
Property Remembered [ MultiDimensional, Private ];

/// The next reset at the last run, whether or not it was published; "" until a run has remembered it.
Property RememberedReset As %String [ Private ];

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Try {
		Do ..Readings(.keys, .budget)
		Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed(keys, budget)
		Do conditions.Insert(..ResetSoon())
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
		Do ..PublishReset(stream, first)
	} Catch exception {
		$$$LOGWARNING(..#LOGRUN_exception.DisplayString())
	}
	Quit $$$OK
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
