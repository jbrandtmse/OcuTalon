/// A service that takes every provider of OcuTalon. as its provider package (Story 28.3, R-28.3-1), so that Test.Mcp.ServiceReadOnly can prove each test of ToolProblem (safe,
/// read-only, no hook) on the chat tools and on Test.Mcp.ZzHookedTools, whose classes are outside OcuTalon.Mcp. Nothing serves it. It is no test case.
Class OcuTalon.Test.Mcp.ZzLooseService Extends OcuTalon.Mcp.Service
{

Parameter PROVIDERPACKAGE = "OcuTalon.";

}
