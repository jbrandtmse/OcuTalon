Include Ensemble

/// The classification class of OcuTalon (AD-10, AD-21, AD-31; Lane A): the value of the ClassificationClass setting of the Decide item in OcuTalon.Production. The
/// gate asks it ClassifyMcp(source, name, fingerprint) for every MCP call, and the runner asks it once for each MCP tool at the start of a request.
///   - The server is the <name> of a source that is exactly mcp:remote:@{config:AI.MCP.OcuTalon_<name>} (OcuTalon.Mcp.Attach), where <name> matches the pattern of
///     OcuTalon.Mcp.Server and has a row there. Any other source, and a server with no row, is not registered (registered 0), and the gate denies the call at
///     once. Classify, which answers for a class source, stays the base's: it classifies nothing, so the built-in tools are classified as before.
///   - The classification is the row of OcuTalon.Mcp.ToolClassification for the server and the tool's name. No row, an unclassified row and a call with no
///     fingerprint in the turn's map are unclassified (classification ""). A row that is read-only or risky holds only for the fingerprint it has: a
///     different, non-empty fingerprint is unclassified, and the row is cleared through OcuTalon.Mcp.Ops ClearChanged (one Tool audit entry and one notice for each admin
///     session, once for a change). An error from the clear is one warning and changes nothing in the answer.
///   - read-only answers {safe, readOnly 1, registered 1} and risky {risky, readOnly 0, registered 1}. The class reads rows and writes only through ClearChanged. It
///     runs inside AI Hub's authorization callback and in the runner's job (AD-6): no AI Hub call, no Python, and it reads no MCP annotation.
Class OcuTalon.Mcp.Classification Extends OcuTalon.Bridge.Ext.Classification
{

/// The part of a source before the Config Store entry's prefix (OcuTalon.Mcp.Attach ENTRYPREFIX) and the server's name.
Parameter SOURCEHEAD = "mcp:remote:@{config:AI.MCP.";

/// The part of a source after the server's name.
Parameter SOURCETAIL = "}";

ClassMethod ClassifyMcp(source As %String, name As %String, fingerprint As %String = "") As %DynamicObject
{
	Set server = ..ServerOf(source)
	If (server = "") || '##class(OcuTalon.Mcp.Server).NameIndexExists(server) Quit ..Answer("", 0, 0)
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, name)
	If '$IsObject(row) || ((row.Classification '= "read-only") && (row.Classification '= "risky")) Quit ..Answer("", 0, 1)
	If fingerprint = "" Quit ..Answer("", 0, 1)
	If row.Fingerprint '= fingerprint {
		Try {
			Set sc = ..Clear(server, name, fingerprint)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $$$ISERR(sc) $$$LOGWARNING("OcuTalon.Mcp.Classification: the changed MCP tool "_##class(OcuTalon.Bridge.Redact).Text($Extract(name, 1, 64))_" of "_server_" could not be cleared: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit ..Answer("", 0, 1)
	}
	If row.Classification = "read-only" Quit ..Answer("safe", 1, 1)
	Quit ..Answer("risky", 0, 1)
}

/// The clear of a changed tool: OcuTalon.Mcp.Ops ClearChanged. A seam for the tests, which override it to see the notices that the clear would send.
ClassMethod Clear(server As %String, name As %String, fingerprint As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Mcp.Ops).ClearChanged(server, name, fingerprint)
}

/// The name of the registered server that the source names, or "" when the source is not exactly the toolref that OcuTalon.Mcp.Attach attaches for a server name.
ClassMethod ServerOf(source As %String) As %String [ Private ]
{
	Set head = ..#SOURCEHEAD _ ##class(OcuTalon.Mcp.Attach).#ENTRYPREFIX
	If ($Extract(source, 1, $Length(head)) '= head) || ($Extract(source, *) '= ..#SOURCETAIL) Quit ""
	Set server = $Extract(source, $Length(head) + 1, *-1)
	If '$Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Quit ""
	Quit server
}

/// The answer of ClassifyMcp.
ClassMethod Answer(classification As %String, readOnly As %Boolean, registered As %Boolean) As %DynamicObject [ Private ]
{
	Quit {"classification": (classification), "readOnly": (+readOnly), "registered": (+registered)}
}

}
