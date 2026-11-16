/// A service whose specification is wider than the shipped one (Story 28.3, R-28.3-1): it adds OcuTalon.Tools.Memory, which holds save_memory and forget_memory. Test.Mcp.ServiceReadOnly
/// proves that ReadOnlyProblem names those tools and that OnAuthenticate refuses every request. Nothing serves it: no web application names it. It is no test case.
Class OcuTalon.Test.Mcp.ZzWideService Extends OcuTalon.Mcp.Service [ DependsOn = (OcuTalon.Mcp.ServiceTools, OcuTalon.Tools.Memory) ]
{

Parameter SPECIFICATION = "OcuTalon.Mcp.ServiceTools,OcuTalon.Tools.Memory";

}
