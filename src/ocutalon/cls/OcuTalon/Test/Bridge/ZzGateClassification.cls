/// The classification extension of the gate tests (Story 3.2, 22.8; AD-31): a test fixture, never part of a production. Classify gives safe for the MCP
/// tool zz_mcp_safe of the server mcp:zzserver; for zz_mcp_args of that server only when it is given arguments (the gate gives it none); and for
/// zz_gate_risky and zz_gate_held of ZzGateTool and odd_param of ZzGateOdd, so that the tests show what it classifies (a tool that code and the
/// setting leave unclassified) and what it never changes (what code declares). Nothing for any other source and name. ClassifyMcp (Story 22.8) answers
/// for the tools of mcp:zzserver by their name, so that a test shows each shape of answer:
///   - zz_mcp_ro: safe, readOnly 1; zz_mcp_risky: risky, readOnly 0; zz_mcp_risky_ro: risky, readOnly 1 (a flag that a risky tool does not use);
///   - zz_mcp_gone: safe, readOnly 1, registered 0;
///   - zz_mcp_text: an answer that is no object; zz_mcp_other_class: the classification "maybe"; zz_mcp_flag_text: safe with the readOnly "1" as text; zz_mcp_registered_text: safe, readOnly 1 and the registered "0" as text;
///     zz_mcp_none: an object with no classification; zz_mcp_throws: throws;
///   - zz_mcp_fingerprint: safe, readOnly 1, and notes the fingerprint it was given in ^||ZzGateMcp("fingerprint");
///   - the answers with a resource (Story 22.3): zz_mcp_res_lacks (safe, readOnly 1), zz_mcp_res_risky (risky) and zz_mcp_res_none (no classification) name %Admin_Secure, which the service
///     user lacks; zz_mcp_res_held (safe, readOnly 1) names the resource in ^||ZzGateMcp("resource");
///   - any other name and any other source: the base's answer, which delegates to Classify.
/// Test.Bridge.Gate names it in the ClassificationClass setting of Decide for its own run.
Class OcuTalon.Test.Bridge.ZzGateClassification Extends OcuTalon.Bridge.Ext.Classification
{

ClassMethod Classify(source As %String, name As %String, arguments As %DynamicObject = "") As %String
{
	If (source = "mcp:zzserver") && (name = "zz_mcp_safe") Quit "safe"
	If (source = "mcp:zzserver") && (name = "zz_mcp_args") && $IsObject(arguments) Quit "safe"
	If $ListFind($ListBuild("OcuTalon.Test.Bridge.ZzGateTool:zz_gate_risky", "OcuTalon.Test.Bridge.ZzGateTool:zz_gate_held", "OcuTalon.Test.Bridge.ZzGateOdd:odd_param"), source_":"_name) Quit "safe"
	Quit ""
}

ClassMethod ClassifyMcp(source As %String, name As %String, fingerprint As %String = "") As %DynamicObject
{
	If source '= "mcp:zzserver" Quit ##super(source, name, fingerprint)
	If name = "zz_mcp_ro" Quit {"classification": "safe", "readOnly": 1, "registered": 1}
	If name = "zz_mcp_risky" Quit {"classification": "risky", "readOnly": 0, "registered": 1}
	If name = "zz_mcp_risky_ro" Quit {"classification": "risky", "readOnly": 1, "registered": 1}
	If name = "zz_mcp_gone" Quit {"classification": "safe", "readOnly": 1, "registered": 0}
	If name = "zz_mcp_text" Quit "safe"
	If name = "zz_mcp_other_class" Quit {"classification": "maybe", "readOnly": 1, "registered": 1}
	If name = "zz_mcp_flag_text" Quit {"classification": "safe", "readOnly": "1", "registered": 1}
	If name = "zz_mcp_registered_text" Quit {"classification": "safe", "readOnly": 1, "registered": "0"}
	If name = "zz_mcp_none" Quit {"readOnly": 1, "registered": 1}
	If name = "zz_mcp_throws" $$$ThrowStatus($SYSTEM.Status.Error(5001, "ZzGateClassification throws for zz_mcp_throws"))
	If name = "zz_mcp_res_lacks" Quit {"classification": "safe", "readOnly": 1, "registered": 1, "resource": "%Admin_Secure"}
	If name = "zz_mcp_res_risky" Quit {"classification": "risky", "readOnly": 0, "registered": 1, "resource": "%Admin_Secure"}
	If name = "zz_mcp_res_none" Quit {"classification": "", "readOnly": 0, "registered": 1, "resource": "%Admin_Secure"}
	If name = "zz_mcp_res_held" Quit {"classification": "safe", "readOnly": 1, "registered": 1, "resource": ($Get(^||ZzGateMcp("resource")))}
	If name = "zz_mcp_fingerprint" {
		Set ^||ZzGateMcp("fingerprint") = fingerprint
		Quit {"classification": "safe", "readOnly": 1, "registered": 1}
	}
	Quit ##super(source, name, fingerprint)
}

}
