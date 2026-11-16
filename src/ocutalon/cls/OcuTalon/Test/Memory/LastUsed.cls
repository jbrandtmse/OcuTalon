/// Tests of the last-used time of a memory (Story 28.2; AD-1, AD-4, AD-21, AD-26, AD-31, FR-43). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), on OcuTalon's Docker image
/// (the stored memories are embedded through a worker), through the CI environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1). A real turn runs through Decide
/// (RunnerFixture.Run) against the CI mock with the real gate, tools, ContentClass (Agent.Content), MemoryIn and MemoryOps (no double).
///   - TestTurnSetsLastUsed (Integration AC; consumer Agent.Content through Decide): a Chat turn of a session with six memories whose search_memories answer (memory-recall-keyword)
///     puts some of them in HostData.memories: within 10 seconds each of those has a LastUsedAt at or after the turn's start, the memory that the reply did not name keeps an
///     empty LastUsedAt, and the reply's HostData is exactly what the runner made (the memories member only);
///   - TestAcceptedUsed: Agent.Content.Accepted, called with a reply HostData of its own, sends the Used for the first MAXUSED named memories only, skips an entry that is no memory,
///     adds no member to hostData, and answers OK and marks nothing for a HostData that cannot be read;
///   - TestOnUsed: MemoryOps' handler, reached through the message map, sets LastUsedAt of the owner's memories that the message names, ignores a Ref of another owner and an unknown
///     Ref, never moves LastUsedAt back or to the same value again, moves it forward, and, for a UsedAt that is not a UTC time, a list that is not a JSON array and an owner that is empty,
///     changes nothing, answers OK and holds no lock;
///   - TestMemoryInTrace (AD-26): MemoryIn, made through Ens.Director as Agent.Content makes it, sends MemoryOps the Used in a trace session whose SuperSession is the TraceRef of the
///     owner's Session row, MemoryOps sets LastUsedAt, and the Used holds no memory text; an input that is not a Used is refused with an error status and sends nothing.
Class OcuTalon.Test.Memory.LastUsed Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-mem-lu";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The owners of the handler test, which need no Session row.
Parameter OWNER = "zz-mem-lu-a";

Parameter OTHER = "zz-mem-lu-b";

Parameter PREFIX = "zz-mem-lu";

/// The ItemIds of the turns that the test made.
Property ItemIds As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state))
		Merge ^||OcuTalonTestMemoryLastUsed = state
		Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If $ClassMethod(..#FIXTURE, "Running") Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If $ClassMethod(..#FIXTURE, "Running") Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Do ..DropRows()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	Do ..DropRows()
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Set sc = $ClassMethod(..#FIXTURE, "RestoreKeys")
	}
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Merge state = ^||OcuTalonTestMemoryLastUsed
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestMemoryLastUsed
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// Deletes the memories of the run's fixture owners, with their index entries.
Method DropRows() [ Private ]
{
	Do ##class(OcuTalon.Test.Memory.Fixture).Purge(..#PREFIX)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Memory.Fixture).Purge($Piece(..Sessions, ",", i))
	}
}

/// 1 when the production is ready, this is OcuTalon's image, and the entries of the runners point at the CI mock key variable. Otherwise the test fails with the
/// reason or records the skip, and quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit 0
	}
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If ..Pointed Quit 1
	Set ..Pointed = 1
	Set sc = $ClassMethod(..#FIXTURE, "PointKeys")
	Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
	Quit $$$ISOK(sc)
}

/// Sends a turn of the owner through Decide (RunnerFixture.Run): answer is the Reply.
Method Turn(text As %String, owner As %String, Output answer As %Persistent) As %Status [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", "user", text, .ref, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit $ClassMethod(..#FIXTURE, "Run", request, .answer, .session)
}

/// Stores six memories of the session (the first holds Lee) with refs <prefix>1 to <prefix>6, never used.
Method Store(session As %String, prefix As %String) [ Private ]
{
	Set texts = $ListBuild("the Results partner's contact is Lee", "the warehouse closes at six on Fridays", "Morgan is the name of my manager", "my neighbour's name is Sam", "the quarterly board meeting agenda covers budgets and hiring", "the printer on the second floor is called Otto")
	For i = 1:1:$ListLength(texts) {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, prefix_i, $List(texts, i), ##class(OcuTalon.Data.Time).NowUtc()), "memory "_i_" is stored")
	}
}

/// The LastUsedAt of the memory with the Ref, "" for none.
ClassMethod LastUsed(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT LastUsedAt FROM OcuTalon_Data.Memory WHERE Ref = ?", ref)
	If rs.%Next() Quit rs.%Get("LastUsedAt")
	Quit ""
}

/// Waits at most seconds until the memory has a LastUsedAt; its value, "" when it has none then.
ClassMethod WaitLastUsed(ref As %String, seconds As %Integer = 10) As %String [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set used = ..LastUsed(ref)
		If (used '= "") || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit used
}

/// The memory Refs of the memories member of the reply's HostData, comma-separated, in order; "" when there is none.
ClassMethod Named(answer As %Persistent) As %String [ Private ]
{
	Set text = ""
	If answer.HostData = "" Quit ""
	Set memories = {}.%FromJSON(answer.HostData).memories
	If '$IsObject(memories) Quit ""
	Set iterator = memories.%GetIterator()
	While iterator.%GetNext(, .memory) {
		Set text = text _ $Select(text '= "": ",", 1: "") _ memory.memoryRef
	}
	Quit text
}

/// A Used for the owner.
ClassMethod Used(owner As %String, refs As %String, usedAt As %String) As OcuTalon.Memory.Msg.Used [ Private ]
{
	Set used = ##class(OcuTalon.Memory.Msg.Used).%New()
	Set used.SessionRef = owner
	Set used.MemoryRefs = refs
	Set used.UsedAt = usedAt
	Quit used
}

/// A turn whose reply names memories sets their LastUsedAt, and only theirs.
Method TestTurnSetsLastUsed()
{
	If '..Ready() Quit
	Set session = ..Session("turn")
	Set prefix = "zzmlu"_..Number_"t"
	Do ..Store(session, prefix)
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ..Turn("Who is the contact? [[mock:memory-recall-keyword]]", session, .answer)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text_"|"_answer.Fallback, "The CI mock found the memory.|0", "the reply is the scenario's text and no fallback")
	Set named = ..Named(answer)
	Do $$$AssertTrue($Length(named, ",") '< 1 && (named '= ""), "the reply names memories: "_named)
	Do $$$AssertEquals($Length(named, ",") < 6, 1, "and not all six, so that one stays unused")
	Do $$$AssertEquals($Piece(named, ",", 1), prefix_1, "the memory with Lee is the first")
	Do $$$AssertEquals($Select(answer.HostData '= "": {}.%FromJSON(answer.HostData).%Size(), 1: 0), 1, "the reply's HostData holds the memories member only: nothing of the use is added to it")
	Set unused = 0
	For i = 1:1:6 {
		Set ref = prefix_i
		If (","_named_",") [ (","_ref_",") {
			Set used = ..WaitLastUsed(ref)
			Do $$$AssertTrue(used '= "", "memory "_i_" is named, and its LastUsedAt is set within 10 seconds: "_used)
			Do $$$AssertTrue('(before ] used), "at or after the start of the turn")
		} Else {
			Set unused = unused + 1
			Do $$$AssertEquals(..LastUsed(ref), "", "memory "_i_" is not named and keeps an empty LastUsedAt")
		}
	}
	Do $$$AssertTrue(unused '< 1, "at least one memory was not named: "_unused)
}

/// Agent.Content.Accepted sends the Used for at most MAXUSED named memories, skips an entry that is no memory, adds no member to hostData, and a reply HostData that cannot be read
/// sends nothing and never fails it.
Method TestAcceptedUsed()
{
	If '..Guard() Quit
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set session = ..Session("accepted")
	Set prefix = "zzmlu"_..Number_"a"
	Do ..Store(session, prefix)
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", "user", "who is the contact", .ref, session)
	Set memories = [1, {"memoryRef": ""}, "text"]
	For i = 1:1:6 {
		Do memories.%Push({"memoryRef": (prefix_i)})
	}
	Set sc = ##class(OcuTalon.Agent.Content).Accepted(request, "the reply", .hostData, {"memories": (memories)}.%ToJSON())
	Do $$$AssertStatusOK(sc, "Accepted answers OK")
	Do $$$AssertEquals($IsObject(hostData) && (hostData.%Size() = 0), 1, "and adds no member to hostData")
	Do $$$AssertTrue(..WaitLastUsed(prefix_5) '= "", "the fifth named memory is marked within 10 seconds")
	Set end = $ZHorolog + 3
	While (##class(Ens.Queue).GetCount("MemoryOps") > 0) && ($ZHorolog < end) {
		Hang 0.2
	}
	Set marked = ""
	For i = 1:1:6 {
		Set marked = marked _ $Select(..LastUsed(prefix_i) '= "": 1, 1: 0)
	}
	Do $$$AssertEquals(marked, "111110", "five are marked (MAXUSED), the sixth is not, and the entries that are no memory are skipped")
	For bad = "not json", "{""memories"": ""x""}", "{""memories"": {""memoryRef"": """_prefix_"6""}}", "[]", "" {
		Set sc = ##class(OcuTalon.Agent.Content).Accepted(request, "the reply", .hostData, bad)
		Do $$$AssertStatusOK(sc, "a reply HostData of '"_bad_"' answers OK")
		Do $$$AssertEquals($IsObject(hostData) && (hostData.%Size() = 0), 1, "with no member")
	}
	Set end = $ZHorolog + 3
	While (##class(Ens.Queue).GetCount("MemoryOps") > 0) && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertEquals(..LastUsed(prefix_6), "", "and none of them marks a memory")
}

/// The handler, reached through the message map: whose memories it marks and when it does not.
Method TestOnUsed()
{
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Memory.Ops", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of MemoryOps is made")
	Set saved = "2026-11-01T10:00:00Z"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#OWNER, "zzmluo1", "the Results partner's contact is Lee", saved), "the owner's first memory is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#OWNER, "zzmluo2", "the warehouse closes at six on Fridays", saved), "the owner's second memory is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#OTHER, "zzmlub1", "the Results partner's contact is Lee", saved), "another owner's memory is stored")
	Set t1 = "2026-11-10T10:00:00Z"
	Do $$$AssertStatusOK(host.MessageHandler(..Used(..#OWNER, "[""zzmluo1"",""zzmlub1"",""zzmluunknown""]", t1), .response), "the message map delivers the Used")
	Do $$$AssertEquals(..LastUsed("zzmluo1"), t1, "the owner's named memory has the time")
	Do $$$AssertEquals(..LastUsed("zzmluo2"), "", "the owner's memory that is not named keeps none")
	Do $$$AssertEquals(..LastUsed("zzmlub1"), "", "the other owner's memory, named, is ignored")
	Set t0 = "2026-11-05T10:00:00Z"
	Do $$$AssertStatusOK(host.OnUsed(..Used(..#OWNER, "[""zzmluo1""]", t0), .response), "an earlier time is handled")
	Do $$$AssertEquals(..LastUsed("zzmluo1"), t1, "LastUsedAt never moves back")
	Do $$$AssertStatusOK(host.OnUsed(..Used(..#OWNER, "[""zzmluo1""]", t1), .response), "the same time is handled")
	Do $$$AssertEquals(..LastUsed("zzmluo1"), t1, "and stays")
	Set t2 = "2026-11-12T08:30:00Z"
	Do $$$AssertStatusOK(host.OnUsed(..Used(..#OWNER, "[""zzmluo2"",""zzmluo1""]", t2), .response), "a later time is handled")
	Do $$$AssertEquals(..LastUsed("zzmluo1")_"|"_..LastUsed("zzmluo2"), t2_"|"_t2, "and moves it forward, and sets the second memory's")
	Set before = ..LastUsed("zzmluo1")_"|"_..LastUsed("zzmluo2")_"|"_..LastUsed("zzmlub1")
	Set t3 = "2026-11-14T08:30:00Z"
	For bad = $ListBuild("not a time", "[""zzmluo1""]"), $ListBuild("2026-11-14", "[""zzmluo1""]"), $ListBuild("", "[""zzmluo1""]"), $ListBuild(t3, "not json"), $ListBuild(t3, "{""a"":""zzmluo1""}"), $ListBuild(t3, "[1, null, {""memoryRef"":""zzmluo1""}, """"]"), $ListBuild(t3, "") {
		Set sc = host.OnUsed(..Used(..#OWNER, $List(bad, 2), $List(bad, 1)), .response)
		Do $$$AssertStatusOK(sc, "UsedAt '"_$List(bad, 1)_"' with '"_$List(bad, 2)_"' answers OK")
		Do $$$AssertEquals(..LastUsed("zzmluo1")_"|"_..LastUsed("zzmluo2")_"|"_..LastUsed("zzmlub1"), before, "and changes nothing")
	}
	Do $$$AssertStatusOK(host.OnUsed(..Used("", "[""zzmluo1""]", t3), .response), "a message with no owner answers OK")
	Do $$$AssertEquals(..LastUsed("zzmluo1")_"|"_..LastUsed("zzmluo2")_"|"_..LastUsed("zzmlub1"), before, "and changes nothing")
	Set owner = ..#OWNER
	Set lockName = "^OcuTalon.Memory("""_owner_""")"
	Lock +^OcuTalon.Memory(owner):5
	Do $$$AssertTrue($Data(^$LOCK(lockName)) > 0, "the check sees a lock of the owner's memories that is held")
	Lock -^OcuTalon.Memory(owner)
	Do $$$AssertEquals($Data(^$LOCK(lockName)), 0, "no lock of the owner's memories is held after the handler")
}

/// MemoryIn sends the Used in the owner's trace session, and refuses anything else.
Method TestMemoryInTrace()
{
	If '..Guard() Quit
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set session = ..Session("trace")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set text = "the Results partner's contact is Lee"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, "zzmlut"_..Number, text, "2026-11-01T10:00:00Z"), "a memory of the session is stored")
	Set mark = $ClassMethod(..#FIXTURE, "HeaderMark")
	Set usedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(##class(Ens.Director).CreateBusinessService("MemoryIn", .service), "MemoryIn is made as Agent.Content makes it")
	Do $$$AssertStatusOK(service.ProcessInput(..Used(session, "[""zzmlut"_..Number_"""]", usedAt)), "it takes the Used")
	Do $$$AssertEquals(..WaitLastUsed("zzmlut"_..Number), usedAt, "MemoryOps sets LastUsedAt to the time of the Used")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SuperSession, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'MemoryIn' AND TargetConfigName = 'MemoryOps' ORDER BY ID", mark)
	Do $$$AssertTrue(rs.%Next(), "Visual Trace holds a message from MemoryIn to MemoryOps")
	Do $$$AssertEquals(rs.%Get("SuperSession")_"|"_rs.%Get("MessageBodyClassName"), trace_"|OcuTalon.Memory.Msg.Used", "a Used, in the trace session of the owner's Session row")
	Set body = ##class(OcuTalon.Memory.Msg.Used).%OpenId(rs.%Get("MessageBodyId"))
	Do $$$AssertTrue($IsObject(body) && (body.MemoryRefs '[ "Lee") && (body.SessionRef '[ "Lee") && (body.UsedAt '[ "Lee"), "and its body holds no memory text")
	Do $$$AssertNotTrue(rs.%Next(), "and it is the only one")
	Set mark = $ClassMethod(..#FIXTURE, "HeaderMark")
	Set sc = service.ProcessInput(##class(OcuTalon.Msg.CommandResult).%New())
	Do $$$AssertTrue($$$ISERR(sc), "an input that is not a Used is refused with an error status")
	Set sc = service.ProcessInput("")
	Do $$$AssertTrue($$$ISERR(sc), "and so is no input")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'MemoryIn'", mark)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "nothing was sent for them")
}

}
