/// A business process class that only gives Test.Install.Retention a persistent, completed instance to back-date (Story 30.2). It is in no production, so
/// nothing calls it. THROWAWAY STACKS AND CI ONLY (Rule 21): the test saves instances of it and the 90-day Interoperability purge deletes them.
Class OcuTalon.Test.Install.ZzRetentionProcess Extends Ens.BusinessProcess
{

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
