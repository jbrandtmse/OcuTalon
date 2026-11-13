/// The production of the queue-backlog test feed (Story 23.7): a queue that a test can hold and fill. Only a throwaway test stack runs it, in the namespace of its own that
/// OcuTalon.Test.Checks.Queue.Fixture makes and removes; it is compiled into every image with the other test classes and nothing installs or starts it there.
///   - QueueIn (no job) is the source: Fixture Fill sends it one Ens.StringRequest for each message and it passes each on to QueueSink;
///   - QueueSink takes them one at a time and, while the test holds it, keeps each in its queue.
/// The description carries the CI mock's marker, so that the finding Item the display name of this production goes into is answered tell-now.
Class OcuTalon.Test.Checks.Queue.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.Test.Checks.Queue.Production" TestingEnabled="false">
  <Description>Queue test [[mock:check-finding-tell-now]]</Description>
  <Item Name="QueueIn" ClassName="OcuTalon.Test.Checks.Queue.In" PoolSize="0" Enabled="true"/>
  <Item Name="QueueSink" ClassName="OcuTalon.Test.Checks.Queue.Sink" PoolSize="1" Enabled="true"/>
</Production>
}

}
