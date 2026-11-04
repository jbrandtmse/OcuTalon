/// The base of the test classes that run over the running production. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21):
/// they need the running OcuTalon.Production, which a slot never has. Where it does not run, every test fails with that reason
/// (Guard), so that a broken start can never give a green shard. Each fixture session comes from Session: its Ref is kept for
/// the clean-up and its TraceRef is a SuperSession of the run. OnAfterAllTests ends the context of the test process, removes
/// the headers of the sessions of the run's messages with their bodies and log rows (Fixture.RemoveMessages) and removes the
/// fixture rows (Fixture.Clean). Send puts a message through WebChatIn, created in the test process as the REST surface creates
/// it, and WaitDone waits for its turn. The run's number is n from ^OcuTalonTest(<the last piece of the class name>, "n") (never
/// reset). It has no Test methods.
Class OcuTalon.Test.Core.InProduction Extends %UnitTest.TestCase [ Abstract ]
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The start of the user name of each fixture session; the run's number and the test's name follow it.
Parameter SESSIONPREFIX = "zzprod";

/// Seconds to wait for a turn to be done.
Parameter WAIT = 20;

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The SuperSessions of the run's messages.
Property Supers As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest($Piece($ClassName($This), ".", *), "n"))
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..Supers = []
	Set ..Missing = ""
	If '##class(Ens.Director).IsProductionRunning(.name) {
		Set ..Missing = "No production runs in "_$Namespace_": this class runs in throwaways and CI only (Rule 21)"
	} ElseIf name '= ..#PRODUCTION {
		Set ..Missing = "The production that runs is "_name_", not "_..#PRODUCTION
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// Sends a message of the page through WebChatIn, created in this process as the REST surface creates it; output is the
/// service's answer.
Method Send(session As %String, clientId As %String, text As %String, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set post = ##class(OcuTalon.Channel.WebChat.Post).%New()
	Set post.SessionRef = session
	Set post.ClientId = clientId
	Set post.Text = text
	Set sc = ##class(Ens.Director).CreateBusinessService("WebChatIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(post, .output)
}

/// The Turn of the clientId once it is done, opened afresh; after WAIT seconds, the Turn as it is, or "" when there is none.
Method WaitDone(session As %String, clientId As %String) As OcuTalon.Data.Turn [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set row = ""
	For {
		Kill row
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		If $IsObject(row) && (row.State = "done") Quit
		If $ZHorolog > end Quit
		Hang 0.25
	}
	Quit row
}

/// A fixture session; its Ref is kept for the clean-up, and its TraceRef is a SuperSession of the run.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..#SESSIONPREFIX_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ..Supers.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

}
