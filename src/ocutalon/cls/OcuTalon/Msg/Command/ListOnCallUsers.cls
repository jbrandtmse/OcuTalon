/// Lists the OcuTalon users that Settings > On call offers to page (AD-1, AD-13, AD-24, AD-29; Story 36.4, DW-1278). A read: it changes nothing, needs no approval, is
/// no tool verb and no command that an evaluation counts as acting, and the allowance never counts it. Owner: SettingsOps (OcuTalon.Core.SettingsOps), which reads the
/// roster in the production job and answers Ok 1 with Data {"handoff": uri}: the list itself, [{user, paired}], goes to OcuTalon.Core.SecretHandoff and is in no
/// message, so that no IRIS user name is in a trace. Origin: web_admin only; the web layer sends it for GET /v1/settings, an admin's request. It has no property beyond
/// the base.
Class OcuTalon.Msg.Command.ListOnCallUsers Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
