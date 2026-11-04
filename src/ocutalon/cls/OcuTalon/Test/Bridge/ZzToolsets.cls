/// A class with no INSTRUCTIONS block and a TOOLSETS parameter in the forms that OcuTalon.Bridge.RequestSize.AgentChars has to read: white space
/// around a name, an empty name and a toolset named by a URI (Story 1.9; AD-20). It is no agent and no part of a production; Test.Bridge.Decide
/// reads it.
Class OcuTalon.Test.Bridge.ZzToolsets
{

Parameter TOOLSETS = "  OcuTalon.Tools.Watch , ,mcp:docs,";

}
