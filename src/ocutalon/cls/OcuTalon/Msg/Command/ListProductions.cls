/// Lists the productions that Settings > Partner contacts offers for a contact to concern (AD-1, AD-13, AD-29; Story 24.2). A read: it changes nothing, needs no approval,
/// is no tool verb and no command that an evaluation counts as acting, and the allowance never counts it. Owner: SettingsOps (OcuTalon.Core.SettingsOps), which reads
/// OcuTalon.Watch.Reader Productions in the production job and answers Ok 1, Outcome listed and Data {"productions": [{namespace, production, displayName}]}. Production
/// names are not personal data, so the answer is inline. Origin: web_admin only; any other origin, and any origin inside a bridge context, is refused by CommandsIn and
/// nothing is sent. It has no property beyond the base.
Class OcuTalon.Msg.Command.ListProductions Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
