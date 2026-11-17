/// Lists the Slack settings for Settings > Channels > Slack (AD-1, AD-24; Story 27.3). A read: it changes nothing, is no tool verb and no verb of a Slack sender. It has no
/// property beyond the base. Owner: SettingsOps (OcuTalon.Core.SettingsOps), which answers Ok 1, Outcome listed and Data {"handoff": uri}: the SecretHandoff uri of
/// {state, path, links, users} (Slack's state from OcuTalon.Channel.Slack.In On, the route's path, the links as [{ref, user, member}] and the linkable users' names), so that no
/// user name or member id is in a traced message. Origin: web_admin only; any other origin is refused by CommandsIn and nothing is sent.
Class OcuTalon.Msg.Command.ListSlackLinks Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
