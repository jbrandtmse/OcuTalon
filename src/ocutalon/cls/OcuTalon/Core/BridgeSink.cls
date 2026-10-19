/// The host sink of OcuTalon (AD-31): the bridge's HostSinkClass setting names it, and Story 2.6 makes it the one place
/// that turns the bridge's events into Live.Publish calls and notices. Until then it inherits the do-nothing sink.
Class OcuTalon.Core.BridgeSink Extends OcuTalon.Bridge.Ext.HostSink
{

}
