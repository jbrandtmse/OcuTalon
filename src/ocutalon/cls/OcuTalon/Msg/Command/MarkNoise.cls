/// Marks one of the session's own tell-now or act notices as noise (AD-1, AD-21, AD-29; Story 41.2). Owner: PrecedentOps (OcuTalon.Core.PrecedentOps, Lane B).
/// Origin: web_user only. The first press wins; a repeat is ignored.
Class OcuTalon.Msg.Command.MarkNoise Extends OcuTalon.Msg.Command
{

/// The Ref of the Decision behind the notice: the session's own decide Decision.
Property DecisionRef As %String(MAXLEN = 22);

/// Where the press came from: web or phone.
Property Channel As %String(MAXLEN = 32);

Storage Default
{
<Data name="MarkNoiseDefaultData">
<Subscript>"MarkNoise"</Subscript>
<Value name="1">
<Value>DecisionRef</Value>
</Value>
<Value name="2">
<Value>Channel</Value>
</Value>
</Data>
<DefaultData>MarkNoiseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
