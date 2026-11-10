/// The mock MCP server listens on the loopback only (Story 35.1; the Contest Planner's ruling planner-2026-11-09-35.1, SECURITY; AD-22). The test starts
/// OcuTalon.Test.Mcp.Mock, connects to its port on 127.0.0.1, which is accepted, and then to the same port on each non-loopback IPv4 address of the
/// container, none of which may accept within 2 seconds. It needs no model mock and no running production, so it runs on a warm throwaway and in CI.
///   - TestBindsLoopbackOnly: the loopback connection is accepted and every other address is not; the test FAILS, and never skips, when the container has
///     no non-loopback IPv4 address (a throwaway and a CI runner always have one), so it cannot pass without the proof;
///   - TestProbeSeesAnOpenListener: the probe itself accepts a listener that is bound to every interface (a listener of this test, opened without a
///     bind), so that a refusal above means the bind and not a broken probe.
Class OcuTalon.Test.Mcp.Loopback Extends %UnitTest.TestCase
{

/// How long a connection attempt may take before it counts as not accepted, in seconds.
Parameter PROBESECONDS = 2;

/// The port of the mock the test started, to stop in the teardown.
Property Port As %Integer [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Port Do ##class(OcuTalon.Test.Mcp.Mock).Stop(..Port), ##class(OcuTalon.Test.Mcp.Mock).Forget(..Port)
	Set ..Port = 0
	Kill ^||ZzLoopback
	Quit $$$OK
}

Method TestBindsLoopbackOnly()
{
	Set sc = ##class(OcuTalon.Test.Mcp.Mock).Start(.port)
	Do $$$AssertStatusOK(sc, "the mock starts")
	If $$$ISERR(sc) Quit
	Set ..Port = port
	Set others = ..OtherAddresses()
	Do $$$AssertTrue($ListLength(others) > 0, "the container has a non-loopback IPv4 address to try (this test fails, never skips, without one)")
	Do $$$AssertEquals(..Accepts("127.0.0.1", port), 1, "a connection to 127.0.0.1 on the mock's port is accepted")
	Set position = 0
	While $ListNext(others, position, address) {
		Do $$$AssertEquals(..Accepts(address, port), 0, "a connection to the same port on the address "_address_" is not accepted")
	}
}

Method TestProbeSeesAnOpenListener()
{
	Set others = ..OtherAddresses()
	Do $$$AssertTrue($ListLength(others) > 0, "the container has a non-loopback IPv4 address to try")
	If $ListLength(others) = 0 Quit
	Set port = 53200 + $Random(800)
	Set timeout = 5
	Set socket = ##class(%IO.ServerSocket).%New()
	Set socket.ConnectionQueueSize = 0
	Set socket.KeepAliveInterval = -1
	If 'socket.Open(port, .timeout, .sc) {
		Do $$$AssertTrue(0, "a listener for the probe opens on port "_port)
		Quit
	}
	Do $$$AssertEquals(..Accepts("127.0.0.1", port), 1, "an unbound listener accepts a connection to 127.0.0.1")
	Do $$$AssertEquals(..Accepts($List(others, 1), port), 1, "and one to "_$List(others, 1))
	Do socket.Close()
}

/// The non-loopback IPv4 addresses of the container, as a list: the addresses of $SYSTEM.INetInfo.GetListOfConfiguredInterfaces() (which leaves the loopback
/// interface out) that have four dotted parts, without their /prefix.
ClassMethod OtherAddresses() As %List [ Private ]
{
	Set addresses = ""
	Set interfaces = $SYSTEM.INetInfo.GetListOfConfiguredInterfaces()
	Set position = 0
	While $ListNext(interfaces, position, interface) {
		For i = 2:1:$ListLength(interface) {
			Set address = $Piece($List(interface, i), "/", 1)
			If ($Length(address, ".") = 4) && (address '[ ":") && ($Piece(address, ".", 1) '= 127) Set addresses = addresses _ $ListBuild(address)
		}
	}
	Quit addresses
}

/// 1 when a connection to the address and port is accepted within PROBESECONDS, otherwise 0.
ClassMethod Accepts(address As %String, port As %Integer) As %Boolean [ Private ]
{
	Set client = ##class(%IO.Socket).%New()
	Set timeout = ..#PROBESECONDS
	Set accepted = client.Open(address, port, .timeout, .sc)
	If accepted Do client.Close()
	Quit +accepted
}

}
