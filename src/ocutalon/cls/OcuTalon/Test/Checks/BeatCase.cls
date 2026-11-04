/// The helpers that the tests of the beat in the running production share (Story 39.4): Test.Checks.Heartbeat and Test.Checks.BeatOutcomes extend it. THEY RUN
/// IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), through Test.Watch.Case, with demo mode on. It has no Test methods.
///   - Findings: the Items that Checks sent to Intake for an owner in a trace, with the header's sessions;
///   - Beatable: the preconditions of a beat (the TriageAgent's key is present and the cap is not reached);
///   - Due, SeedBeat, QuietNow and Beat: a time that no real Tick reaches, a person's HeartbeatBeat row made before the settings, its quiet key set to the key of
///     the snapshot that a beat builds now, and the row as stored;
///   - WaitDecision and Marked: the person's decision for a beat Item, and the requests of the CI mock that carry the person's marker;
///   - Check: a BackgroundCheck row as stored now.
/// OnAfterOneTest removes the HeartbeatBeat rows and the settings of the sessions, then the base's clean-up.
Class OcuTalon.Test.Checks.BeatCase Extends OcuTalon.Test.Watch.Case [ Abstract ]
{

/// The finding Items that Checks sent to Intake for the owner, with the owner's TraceRef (trace) as SuperSession, in the headers above the floor (a header id), in
/// order, as a dynamic array of {itemId, catalogKey, slots, channel, provenance, subject, text, and of the header superSession, sessionId and headerId}. Each ItemId joins
/// ItemIds, so that OnAfterOneTest removes the decision and the usage that it made.
Method Findings(trace As %String, owner As %String, floor As %Integer) As %DynamicArray [ Private ]
{
	Set found = []
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, ..#CHECKS, "Intake")
	For i = 0:1:sent.%Size() - 1 {
		Set header = sent.%Get(i)
		If (header.id '> floor) || (header.bodyClass '= "OcuTalon.Msg.Item") Continue
		Set body = ##class(OcuTalon.Msg.Item).%OpenId(header.bodyId)
		If $IsObject(body) && (body.SessionRef = owner) {
			Do found.%Push({"itemId": (body.ItemId), "catalogKey": (body.CatalogKey), "slots": (body.Slots), "channel": (body.Channel), "provenance": (body.Provenance), "subject": (body.Subject), "text": (body.Text), "superSession": (header.superSession), "sessionId": (header.sessionId), "headerId": (header.id)})
			If '$ListFind(..ItemIds, body.ItemId) Set ..ItemIds = ..ItemIds_$ListBuild(body.ItemId)
		}
	}
	Quit found
}

/// The preconditions of a beat: 1 when the entries of the runners point at the CI mock key variable, the TriageAgent's key is present and today's cap is not reached;
/// otherwise a failed assertion that names the precondition, and 0.
Method Beatable() As %Boolean [ Private ]
{
	If '..PointKeys() Quit 0
	Set keyed = ##class(OcuTalon.Bridge.Keys).Status(##class(OcuTalon.Checks.Beat).#AGENT)
	Do $$$AssertEquals(keyed, 1, "precondition: the TriageAgent's key is present (Bridge.Keys.Status)")
	Set capped = ##class(OcuTalon.Bridge.Budget).State().capped
	Do $$$AssertEquals(+capped, 0, "precondition: the daily cost cap is not reached (Bridge.Budget.State)")
	Quit (keyed = 1) && 'capped
}

/// The first minute that is two days ahead of now, as a UTC stamp: no real Tick reaches a row due then.
ClassMethod Due() As %String [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Quit $Extract(##class(OcuTalon.Data.Time).AddSeconds(now, 172800), 1, 17)_"00Z"
}

/// The person's HeartbeatBeat row, due at the time and with the quiet key, made before the settings (on, a 30 minute interval, all day, the checklist), so that a real Tick
/// does not run it first.
Method SeedBeat(session As %String, dueAt As %String, checklist As %String, quietKey As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set row.SessionRef = session
	Set row.NextDueAt = dueAt
	Set row.LastQuietKey = quietKey
	Do $$$AssertStatusOK(row.%Save(), "the person's row is made, due at "_dueAt)
	For name = "on", "interval", "from", "to", "checklist" {
		Set value = $Case(name, "on": 1, "interval": 30, "checklist": checklist, : "")
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(##class(OcuTalon.Checks.Beat).SettingKey(session, name), value), "the setting "_name_" is written")
	}
}

/// The person's HeartbeatBeat row as stored now.
ClassMethod Beat(session As %String) As OcuTalon.Data.HeartbeatBeat [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The person's decision for the beat Item (Kind decide), waiting up to WAITDIAGNOSIS seconds; "" when there is none.
Method WaitDecision(itemId As %String, session As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set decision = ##class(OcuTalon.Data.Ownership).DecisionOfItem(itemId, session, .sc)
		If $IsObject(decision) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit decision
}

/// The number of requests that the CI mock logged after the mark and that carry the person's marker (decide-ignore:<the session's Ref>).
ClassMethod Marked(mark As %Integer, session As %String) As %Integer [ Private ]
{
	Set count = 0
	If $$$ISERR(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Quit -1
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.marker '= "") && $Find(entry.marker, session) Set count = count + 1
	}
	Quit count
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Checks.Beat).Forget($Piece(..Sessions, ",", i))
	}
	Quit ##super(testname)
}

/// Sets the quiet key of the person's HeartbeatBeat row to the key that a beat at the UTC time stores now (the key of the whole, uncut snapshot), as a settled
/// ignore leaves it, and answers it. The snapshot reads the person's saved checklist and rows, so the row and the settings come first (SeedBeat).
Method QuietNow(session As %String, at As %String) As %String [ Private ]
{
	Do ##class(OcuTalon.Checks.Beat).Snapshot(session, at, .whole)
	Set key = ##class(OcuTalon.Checks.Beat).Key(whole)
	Set row = ..Beat(session)
	Set row.LastQuietKey = key
	Do $$$AssertStatusOK(row.%Save(), "the person's quiet key is the key of the snapshot")
	Quit key
}

/// The check row as stored now: other processes change it, and an object that this one opened before is reloaded.
ClassMethod Check(ref As %String) As OcuTalon.Data.BackgroundCheck [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

}
