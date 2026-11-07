/// The runner's adapter for the provider-resolution tests of Test.Bridge.Providers (Story 17.3): it resolves on the table of OcuTalon.Test.Bridge.ZzProviders,
/// so that a shadow runner can resolve to a provider whose key variable a test sets in its own process. ForceJob makes the adapter record its key state as
/// a job of the production does (Keys.Record), so that a test can run OnInit on a shadow host. Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzProviderAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// 1 to act as a job of the production (RecordKey records, OnTearDown forgets).
Property ForceJob As %Boolean [ InitialExpression = 0, Transient ];

ClassMethod ProvidersClass() As %String
{
	Quit "OcuTalon.Test.Bridge.ZzProviders"
}

Method IsJob() As %Boolean [ Private ]
{
	Quit ..ForceJob || ##super()
}

}
