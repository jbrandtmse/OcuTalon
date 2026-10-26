/// The request that BreakFeedIn sends PartnerTrigger: the session whose batch of orders the simulated partner sends (Story 4.3). It
/// carries no user name and no date; PartnerTrigger reads the session row for both the user and the TraceRef. Its readable class name
/// shows in Visual Trace (AD-26).
Class OcuTalon.Demo.Msg.SendOrders Extends Ens.Request
{

/// The pressing session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// The channel of the press: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

Storage Default
{
<Data name="SendOrdersDefaultData">
<Subscript>"SendOrders"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>Channel</Value>
</Value>
</Data>
<DefaultData>SendOrdersDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
