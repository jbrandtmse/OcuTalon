/// An insurance claim as the test feed's partner sends it (Story 9.9; AD-22). Every property is text, so that any body saves and reaches its item: the typed
/// record that RECORDCLASS names decides whether the values are valid. It shares the Ens.MessageBody extent and sets no DEFAULTGLOBAL (a message, not a
/// table). The values are synthetic.
Class OcuTalon.Test.Eval.Feed.Claim Extends (Ens.Request, %JSON.Adaptor)
{

/// The typed record that Intake validates this message as.
Parameter RECORDCLASS = "OcuTalon.Test.Eval.Feed.BillingClaim";

Property ClaimId As %String(MAXLEN = 40);

Property MemberId As %String(MAXLEN = 40);

Property ServiceDate As %String(MAXLEN = 40);

Property Amount As %String(MAXLEN = 40);

Property PayerCode As %String(MAXLEN = 40);

Storage Default
{
<Data name="ClaimDefaultData">
<Subscript>"Claim"</Subscript>
<Value name="1">
<Value>ClaimId</Value>
</Value>
<Value name="2">
<Value>MemberId</Value>
</Value>
<Value name="3">
<Value>ServiceDate</Value>
</Value>
<Value name="4">
<Value>Amount</Value>
</Value>
<Value name="5">
<Value>PayerCode</Value>
</Value>
</Data>
<DefaultData>ClaimDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
