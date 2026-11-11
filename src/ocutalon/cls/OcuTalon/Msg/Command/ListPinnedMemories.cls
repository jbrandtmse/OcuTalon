/// Lists the session's pinned memories and the tokens they use (AD-1, AD-21, AD-29; Story 41.13). A read: it changes nothing, needs no approval and is no
/// command that an evaluation counts as acting, and the allowance never counts it. Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A), which lists with this
/// command's own SessionRef and answers the items and the used figure in CommandResult Data. Origin: web_user only; the web layer sets the CSP session's
/// SessionRef, never the client's. Not a tool verb. It has no property beyond the base.
Class OcuTalon.Msg.Command.ListPinnedMemories Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
