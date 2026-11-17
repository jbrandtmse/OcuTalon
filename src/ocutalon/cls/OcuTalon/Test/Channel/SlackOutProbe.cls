/// A subclass of OcuTalon.Channel.Slack.Out for the tests (Story 27.2): its read timeout is one second, so that a server that does not answer costs a test a second, not fifteen,
/// and the most seconds it waits for Retry-After is two, so that the bound itself (taken) and one over it (refused) cost a test seconds, not half a minute.
/// Nothing else differs. The product never refers to it.
Class OcuTalon.Test.Channel.SlackOutProbe Extends OcuTalon.Channel.Slack.Out
{

Parameter SENDSECONDS = 1;

Parameter MAXWAIT = 2;

}
