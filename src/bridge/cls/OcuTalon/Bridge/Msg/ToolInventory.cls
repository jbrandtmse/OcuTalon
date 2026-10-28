/// The request that asks an agent runner for the tools of its live ToolManager (AD-10, FR-10). It has no properties: the
/// runner answers with an Ens.StringResponse that holds {"tools":[{"name","source","provider","status","reason"}]}. Lane A.
Class OcuTalon.Bridge.Msg.ToolInventory Extends Ens.Request
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
