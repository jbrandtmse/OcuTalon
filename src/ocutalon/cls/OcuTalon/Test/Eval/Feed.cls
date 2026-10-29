/// The evaluation set's test feed (Story 9.9; AD-22, CON-3): a production of nine items that fail on purpose, each through IRIS's own machinery, so that
/// the incidents of eval/ are recorded from real failures. Only a throwaway test stack runs it, in the namespace of its own that
/// OcuTalon.Test.Eval.Feed.Fixture makes and removes; it is compiled into every image with the other test classes and nothing installs or starts it
/// there. Nothing watches it. Its testing switch is off, and it has no EnsLib.Testing.Service.
///   - Sender (FeedIn, no job) sends the messages of a batch to one of the items below, each in a session of its own;
///   - Intake items validate the message as a typed record: ResultsToChart and ShipmentsToLedger (a datatype), ReturnsToLedger (a minimum value) and
///     ClaimsToBilling (a required property);
///   - PartnerOut items POST the message to an HTTP partner: LabResultsOut (a port where nothing listens), CarrierBookingOut (a host that does not
///     exist), PayerClaimsOut (503 from PartnerSite) and ReferenceLabOut (500 from PartnerSite). The retried ones give up after 2 seconds;
///   - PartnerSite (port 9381) is the feed's partner: 503 for /payer/, 500 for /reference-lab/;
///   - ClaimsToArchive fails with an <UNDEFINED> error.
Class OcuTalon.Test.Eval.Feed Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.Test.Eval.Feed" TestingEnabled="false">
  <Description>The evaluation set's test feed (throwaway test stacks only)</Description>
  <Item Name="FeedIn" ClassName="OcuTalon.Test.Eval.Feed.Sender" PoolSize="0" Enabled="true"/>
  <Item Name="PartnerSite" ClassName="OcuTalon.Test.Eval.Feed.Partner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">9381</Setting>
  </Item>
  <Item Name="ResultsToChart" ClassName="OcuTalon.Test.Eval.Feed.Intake" PoolSize="1" Enabled="true"/>
  <Item Name="ShipmentsToLedger" ClassName="OcuTalon.Test.Eval.Feed.Intake" PoolSize="1" Enabled="true"/>
  <Item Name="ReturnsToLedger" ClassName="OcuTalon.Test.Eval.Feed.Intake" PoolSize="1" Enabled="true"/>
  <Item Name="ClaimsToBilling" ClassName="OcuTalon.Test.Eval.Feed.Intake" PoolSize="1" Enabled="true"/>
  <Item Name="LabResultsOut" ClassName="OcuTalon.Test.Eval.Feed.PartnerOut" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">9382</Setting>
    <Setting Target="Adapter" Name="URL">/lab/results</Setting>
    <Setting Target="Host" Name="FailureTimeout">2</Setting>
    <Setting Target="Host" Name="RetryInterval">1</Setting>
  </Item>
  <Item Name="CarrierBookingOut" ClassName="OcuTalon.Test.Eval.Feed.PartnerOut" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="HTTPServer">carrier.example</Setting>
    <Setting Target="Adapter" Name="HTTPPort">80</Setting>
    <Setting Target="Adapter" Name="URL">/bookings</Setting>
    <Setting Target="Host" Name="FailureTimeout">2</Setting>
    <Setting Target="Host" Name="RetryInterval">1</Setting>
  </Item>
  <Item Name="PayerClaimsOut" ClassName="OcuTalon.Test.Eval.Feed.PartnerOut" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">9381</Setting>
    <Setting Target="Adapter" Name="URL">/payer/claims</Setting>
    <Setting Target="Host" Name="FailureTimeout">2</Setting>
    <Setting Target="Host" Name="RetryInterval">1</Setting>
  </Item>
  <Item Name="ReferenceLabOut" ClassName="OcuTalon.Test.Eval.Feed.PartnerOut" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">9381</Setting>
    <Setting Target="Adapter" Name="URL">/reference-lab/results</Setting>
  </Item>
  <Item Name="ClaimsToArchive" ClassName="OcuTalon.Test.Eval.Feed.Archive" PoolSize="1" Enabled="true"/>
</Production>
}

}
