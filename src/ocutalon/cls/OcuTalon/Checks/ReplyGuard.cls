/// The reply guard (AD-28): the bridge's ReplyFilterClass setting names it, and it runs once on every model-written text
/// before a result leaves Decide. Until Story 5.7 it inherits the do-nothing filter and passes text through.
Class OcuTalon.Checks.ReplyGuard Extends OcuTalon.Bridge.Ext.ReplyFilter
{

}
