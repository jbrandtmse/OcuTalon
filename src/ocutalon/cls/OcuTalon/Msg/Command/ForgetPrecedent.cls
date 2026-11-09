/// Forgets one of the session's own precedents (AD-1, AD-21, AD-29; Story 41.2). Owner: PrecedentOps (OcuTalon.Core.PrecedentOps, Lane B).
/// Origin: web_user only.
Class OcuTalon.Msg.Command.ForgetPrecedent Extends OcuTalon.Msg.Command
{

/// The precedent's Ref (OcuTalon.Data.Precedent).
Property PrecedentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="ForgetPrecedentDefaultData">
<Subscript>"ForgetPrecedent"</Subscript>
<Value name="1">
<Value>PrecedentRef</Value>
</Value>
</Data>
<DefaultData>ForgetPrecedentDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
