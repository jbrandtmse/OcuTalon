/// OcuTalon.Mcp.Ops, the item that adds, removes and classifies MCP servers, and OcuTalon.Install.Step.Mcp, the one entry point to the resource of each
/// server (Story 22.2; AD-1, AD-3, AD-10, AD-17, AD-19, AD-21, AD-25). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they create and delete an IRIS
/// resource and change the role OcuTalonServiceRole in %SYS, and they write audit entries. They use the probe OcuTalon.Test.Mcp.OpsProbe, which restarts no
/// runner and records the notices it would send; they need no production and no mock server. Each test makes its own fixtures (the servers zzmcpops<n>, their
/// tool rows, the resources, the grants and a fixture admin session) and OnAfterOneTest removes them whether the test passed or failed and asserts that none is left.
///   - TestAdd: a valid add from CommandsIn with origin web_admin answers added, writes the row, makes the resource with no public permission, gives the role that one
///     pair, audits it (an MCP entry naming the acting user) and restarts once;
///   - TestEntryPointRefusesOtherNames (the Contest Planner's condition): Grant and Revoke refuse a name that fails NAMEPATTERN, change no resource and leave the role's
///     resources byte-identical; a valid add changes the role by exactly OcuTalon_MCP_<server>:U and no OcuTalon role gains an %Admin_ or %All resource;
///   - TestBadAddress, TestBadNameAndTaken: the refusals change nothing and restart nothing; a port is 1 to 65535;
///   - TestWrongSender, TestOnlineDemo, TestOnlineDemoRealFlag: a sender other than CommandsIn, an origin other than web_admin, a bridge context, an empty acting user and
///     the online demo (through the probe's switch, and through the real onlineDemo setting) are refused for all three verbs with the sentences of CommandsIn, before any write;
///   - TestRemove, TestClassify: the rows, resource, grant and audit entries; an unknown server or tool, and a word that is not a classification, change nothing;
///   - TestAuditFails, TestRestartFails: an audit that fails undoes an add and a classification (not_audited); a restart that fails keeps the change (failed);
///   - TestRolesCompose: the Roles step composes the grant of each row whose resource exists, skips a row whose resource is missing, and composes none on the
///     online demo;
///   - TestRecordAttachRows, TestToolNamesAreCaseSensitive, TestChangedTool, TestClearChanged, TestNotices: the tool rows of an attach report (names are case-sensitive;
///     a classified tool that is reported refused keeps its classification, and one that is listed with a different or missing fingerprint is cleared), the clear of a
///     changed tool, and one notice per transition;
///   - TestNoAddressOrSecretInAnyText (AC 7): the address a command gives, and a failure's text that holds a credential, show in no result, audit entry, notice,
///     or event-log row of the add, classify, remove and attach paths (a refusal, a failed audit and a failed restart included);
///   - TestToolFingerprint: the fingerprint (Story 22.8) is 64 hexadecimal characters that change with the server, the name, the description or the input schema, not with the
///     order of the schema's keys.
Class OcuTalon.Test.Mcp.Ops Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Mcp.OpsProbe";

Parameter SENDER = "CommandsIn";

Parameter ROLE = "OcuTalonServiceRole";

Parameter URL = "https://example.invalid/mcp";

Parameter USER = "zzmcpopsadmin";

/// The server names the test made, comma-separated, for the clean-up.
Property Names As %String(MAXLEN = "");

/// The number of the test, in the names of its servers.
Property Number As %Integer;

/// The mark of the audit log when the test began.
Property AuditMark As %String;

/// The fixture admin session, and what the public online-demo flag held before the test.
Property Admin As %String;

Property SavedDemo As %String;

Property DemoSaved As %Boolean [ InitialExpression = 0 ];

/// A test that offers the entry point names that must be refused snapshots the OcuTalon roles and the OcuTalon_MCP_ resources (Guard), and the clean-up puts them
/// back, so that a wrong refusal cannot leave a resource or a grant for the next test.
Property Guarded As %Boolean [ InitialExpression = 0 ];

Property RoleSnapshot As %String(MAXLEN = "");

Property ResourceSnapshot As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzOps
	Set ..Names = ""
	Set ..Admin = ""
	Set ..DemoSaved = 0
	Set ..Guarded = 0
	Set ..Number = $Increment(^OcuTalonTest("McpOps", "n"))
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..DemoSaved Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Do ..DeleteRequests($Get(^||ZzOps("requests")))
	Do ..Clean()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no row, resource, grant or session behind")
	Kill ^||ZzOps
	Quit $$$OK
}

Method TestAdd()
{
	Set server = ..Server("a")
	Set before = ..RoleResources(..#ROLE)
	Set result = ..Run(..#SENDER, ..Add(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|added|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGEADDED, "the add is answered added")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	Do $$$AssertTrue($IsObject(row), "the row is written")
	If $IsObject(row) Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "with the time it was made")
	Set resource = "OcuTalon_MCP_" _ server
	Do $$$AssertEquals(..ResourceExists(resource), 1, "the resource exists")
	Do $$$AssertEquals(..PublicPermission(resource), "", "with no public permission")
	Do $$$AssertEquals(..SortedPairs(..RoleResources(..#ROLE)), ..SortedPairs($Select(before = "": "", 1: before _ ",") _ resource _ ":U"), "and the service role gained that one pair")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 1, "the runners are restarted once")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP entry names the server")
	If entries.%Size() {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.change _ "|" _ data.server _ "|" _ data.irisUser _ "|" _ data.channel, "added|" _ server _ "|" _ ..#USER _ "|web", "it says added, and names the acting user and the channel")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "no notice is sent")
}

/// The Contest Planner's condition on the resource and its grant (Story 22.2, AC 6).
Method TestEntryPointRefusesOtherNames()
{
	Do ..Guard()
	Set roles = ..OcuTalonRoles()
	Set resources = ..ResourceCount()
	Set long = $Translate($Justify("", 41), " ", "a")
	Set bad = $ListBuild("", "%All", "x;y", "x y", "../x", "1abc", "%Admin_Secure", long, "x" _ $Char(10), "a-b", "a.b", "%Admin_Manage")
	// all the Grants first and then all the Revokes, so that a Revoke cannot hide what a Grant made
	For verb = "Grant", "Revoke" {
		Set position = 0
		While $ListNext(bad, position, name) {
			Set shown = $Extract($Translate(name, $Char(10), "?"), 1, 12)
			Do $$$AssertStatusNotOK($ClassMethod("OcuTalon.Install.Step.Mcp", verb, name), verb _ " refuses '" _ shown _ "'")
		}
		Do $$$AssertEquals(..ResourceCount(), resources, "after the " _ verb _ "s no resource is created or deleted")
		Do $$$AssertEquals(..OcuTalonRoles(), roles, "and the resources of every OcuTalon role, the service role included, are byte-identical")
	}
	Do $$$AssertEquals(..ResourceExists("%Admin_Secure"), 1, "%Admin_Secure is still there")
	// a valid add changes the service role by exactly one pair and no other OcuTalon role at all
	Set server = ..Server("e")
	Set result = ..Run(..#SENDER, ..Add(server))
	Do $$$AssertEquals(result.Outcome, "added", "a valid add is carried out")
	Set after = ..OcuTalonRoles()
	Do $$$AssertEquals(..Without(after, ..#ROLE), ..Without(roles, ..#ROLE), "no other OcuTalon role changed")
	Do $$$AssertEquals(..SortedPairs(..Pairs(after, ..#ROLE)), ..SortedPairs(..Pairs(roles, ..#ROLE) _ ",OcuTalon_MCP_" _ server _ ":U"), "the service role gained exactly OcuTalon_MCP_" _ server _ ":U")
	Do $$$AssertEquals(..AdminResources(after), ..AdminResources(roles), "and no OcuTalon role gained an %All or %Admin_ resource")
}

Method TestBadAddress()
{
	Set server = ..Server("b")
	Set urls = $ListBuild("http://example.com/mcp", "ftp://example.com/mcp", "", "https://x/@{env:K}", "https://", "http://localhost@example.com/mcp", "https://user@example.com/mcp", "http://127.0.0.1.example.com/mcp", "https://example.com:port/mcp", "https://exa mple.com/mcp", "example.com/mcp", "http://example.com@127.0.0.1/", "https://example.com:0/mcp", "https://example.com:65536/mcp", "https://example.com:99999/mcp", "http://127.0.0.1:0/mcp", "http://[::1]:00000/mcp")
	Set position = 0
	While $ListNext(urls, position, url) {
		Set result = ..Run(..#SENDER, ..Add(server, url))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|bad_address|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGEADDRESS, "'" _ $Extract(url, 1, 24) _ "' is a bad address")
	}
	Do $$$AssertEquals(..Written(server), "", "nothing is written")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 0, "and no runner is restarted")
	For url = "https://example.com/mcp", "http://127.0.0.1:8080/mcp", "http://localhost/mcp", "http://[::1]:9/mcp", "https://example.com:65535/mcp", "http://127.0.0.1:1/mcp" {
		Do $$$AssertEquals(##class(OcuTalon.Mcp.Ops).AddressAllowed(url), 1, "'" _ url _ "' is allowed")
	}
	// a query string or a fragment is refused by the add with T12 (ruling B2); AddressAllowed, which Mcp.Proxy asks at call time, is unchanged
	For url = "https://example.com:8443/a?b=c", "https://example.com/mcp#frag" {
		Set result = ..Run(..#SENDER, ..Add(server, url))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|bad_address|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGEQUERY, "'" _ url _ "' is refused with the query-string text")
		Do $$$AssertEquals(##class(OcuTalon.Mcp.Ops).AddressAllowed(url), 1, "while AddressAllowed still allows it at call time")
	}
	Do $$$AssertEquals(..Written(server), "", "and nothing is written for them")
}

Method TestBadNameAndTaken()
{
	Set long = $Translate($Justify("", 41), " ", "a")
	For name = "", "9abc", "a-b", "a b", "a.b", "a}", long {
		Set result = ..Run(..#SENDER, ..Add(name))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|bad_name|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENAME, "'" _ $Extract(name, 1, 12) _ "' is a bad name")
	}
	Set server = ..Server("t")
	Set first = ..Run(..#SENDER, ..Add(server))
	Do $$$AssertEquals(first.Outcome, "added", "the first add is carried out")
	Set role = ..RoleResources(..#ROLE)
	Set second = ..Run(..#SENDER, ..Add(server))
	Do $$$AssertEquals(second.Ok _ "|" _ second.Outcome _ "|" _ second.Message, "0|exists|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGEEXISTS, "a second add of the name is refused")
	Do $$$AssertEquals(..RoleResources(..#ROLE), role, "and changes nothing")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 1, "and restarts nothing")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server)
	Do $$$AssertEquals(entries.%Size(), 1, "and audits nothing")
}

Method TestWrongSender()
{
	Set server = ..Server("w")
	Do ..MakeRows(server, "zz_one")
	Set notFromTool = ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTFROMTOOL
	Set adminOnly = ##class(OcuTalon.Core.CommandsIn).#MESSAGEADMINONLY
	// origin, sender and acting user of a command, and the sentence of the refusal
	Set cases = $ListBuild($ListBuild("tool", ..#SENDER, ..#USER, notFromTool), $ListBuild("web_user", ..#SENDER, ..#USER, adminOnly), $ListBuild("system", ..#SENDER, ..#USER, adminOnly), $ListBuild("", ..#SENDER, ..#USER, adminOnly), $ListBuild("web_admin", "WebChatIn", ..#USER, adminOnly), $ListBuild("web_admin", "", ..#USER, adminOnly), $ListBuild("web_admin", ..#SENDER, "", adminOnly))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set why = $List(case, 1) _ "/" _ $List(case, 2) _ "/" _ $List(case, 3)
		For verb = "add", "remove", "classify" {
			Set command = $Case(verb, "add": ..Add(..Server("w2"), , $List(case, 1), $List(case, 3)), "remove": ..Remove(server, $List(case, 1), $List(case, 3)), : ..Classify(server, "zz_one", "risky", $List(case, 1), $List(case, 3)))
			Set result = ..Run($List(case, 2), command)
			Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_allowed|" _ $List(case, 4), verb _ " from " _ why _ " is refused")
		}
	}
	// a bridge context counts as origin tool, whatever the command says
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "trusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request), "a bridge context begins")
	Set result = ..Run(..#SENDER, ..Add(..Server("w3")))
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_allowed|" _ notFromTool, "an add inside a bridge context is refused as from a tool")
	Do $$$AssertEquals(..Written(..Server("w2")) _ ..Written(..Server("w3")), "", "nothing is written")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one").Classification, "unclassified", "the tool is still unclassified")
	Do $$$AssertTrue(##class(OcuTalon.Mcp.Server).NameIndexExists(server), "and the server is still registered")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 0, "no runner is restarted")
}

Method TestOnlineDemo()
{
	Set server = ..Server("d")
	Do ..MakeRows(server, "zz_one")
	Set ^||ZzOps("demo") = 1
	Set refused = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED
	Set result = ..Run(..#SENDER, ..Add(..Server("d2")))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "an add on the online demo is refused")
	Set result = ..Run(..#SENDER, ..Remove(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a remove is refused")
	Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", "risky"))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a classification is refused")
	Set session = ..MakeAdmin()
	Set result = ..Run(..#SENDER, ..SetSource(server, "zz_one", session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a SetSourcePoll is refused")
	Set result = ..Run(..#SENDER, ..RemoveSource("zzNoSuchSource", session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a RemoveSourcePoll is refused")
	Do $$$AssertEquals(..SourceRows(session), 0, "and no source row is written")
	Do $$$AssertEquals(..Written(..Server("d2")), "", "nothing was added")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one").Classification, "unclassified", "nothing was classified")
	Do $$$AssertTrue(##class(OcuTalon.Mcp.Server).NameIndexExists(server), "nothing was removed")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 0, "and no runner is restarted")
	Set ^||ZzOps("demo") = 0
	Do $$$AssertEquals(..Run(..#SENDER, ..Add(..Server("d2"))).Outcome, "added", "off the online demo the same add is carried out")
}

/// The online demo as the real Ops.OnlineDemo reads it: the onlineDemo setting at 1 and no switch of the probe.
Method TestOnlineDemoRealFlag()
{
	Set server = ..Server("z")
	Do ..MakeRows(server, "zz_one")
	Do $$$AssertEquals($Data(^||ZzOps("demo")), 0, "the probe's switch is not set, so the real reading of the setting decides")
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..DemoSaved = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set refused = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED
	Set roles = ..OcuTalonRoles()
	Set resources = ..ResourceCount()
	Set result = ..Run(..#SENDER, ..Add(..Server("z2")))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "an add is refused while the onlineDemo setting is 1")
	Set result = ..Run(..#SENDER, ..Remove(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a remove is refused")
	Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", "risky"))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a classification is refused")
	Set session = ..MakeAdmin()
	Set result = ..Run(..#SENDER, ..SetSource(server, "zz_one", session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a SetSourcePoll is refused")
	Set result = ..Run(..#SENDER, ..RemoveSource("zzNoSuchSource", session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a RemoveSourcePoll is refused")
	Do $$$AssertEquals(..SourceRows(session), 0, "and no source row is written")
	Do $$$AssertEquals(..Written(..Server("z2")), "", "nothing was added")
	Do $$$AssertEquals(..ResourceCount() _ "|" _ ..OcuTalonRoles(), resources _ "|" _ roles, "and no resource or grant was made")
	Do $$$AssertTrue(##class(OcuTalon.Mcp.Server).NameIndexExists(server), "nothing was removed")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one").Classification, "unclassified", "nothing was classified")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 0, "and no runner is restarted")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", "risky"))
	Do $$$AssertEquals(result.Outcome, "saved", "with the setting back as it was the same classification is carried out")
}

Method TestRemove()
{
	Set server = ..Server("r")
	Set other = ..Server("s")
	Do ..Run(..#SENDER, ..Add(server))
	Do ..Run(..#SENDER, ..Add(other))
	Do ..MakeTool(server, "zz_one", "read-only", "fpone")
	Do ..MakeTool(server, "zz_two", "unclassified", "fptwo")
	Do ..MakeTool(other, "zz_one", "risky", "fpother")
	Set resource = "OcuTalon_MCP_" _ server
	Do $$$AssertEquals(..ResourceExists(resource), 1, "the resource exists before the remove")
	// Story 22.4: a pending approval request for a tool of the server, and one for the other server's tool, held before the remove
	Set pendingRef = ..PendingRequest(server)
	Set otherRef = ..PendingRequest(other)
	Set restarts = +$Get(^||ZzOps("restarts"))
	Set result = ..Run(..#SENDER, ..Remove(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|removed|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGEREMOVED, "the remove is answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(pendingRef, "State") _ "|" _ ##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(otherRef, "State"), "cancelled|pending", "the pending request for the removed server's tool is cancelled, and the other server's is not")
	Set cancelled = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "Approval", "Approval", pendingRef)
	Do $$$AssertEquals(cancelled.%Size(), 1, "one Approval entry exists for the cancelled request")
	If cancelled.%Size() = 1 {
		Set data = cancelled.%Get(0).data
		Do $$$AssertEquals(data.change _ "|" _ data.from _ "|" _ data.to _ "|" _ data.irisUser _ "|" _ data.channel _ "|" _ data.sessionRef, "cancelled|pending|cancelled|" _ ..#USER _ "|web|" _ ##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(pendingRef, "OwnerRef"), "it names the admin and the web channel, and the request's owner as the session, since the command carries none")
	}
	Do $$$AssertEquals(..Written(server), "", "the server's row and its tool rows are gone")
	Do $$$AssertEquals(..ResourceExists(resource), 0, "the resource is gone")
	Do $$$AssertEquals(..RoleResources(..#ROLE) [ (resource _ ":"), 0, "and so is the grant")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), restarts + 1, "the runners are restarted")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Mcp.Ops).Tools(server, .tools), "Tools of the server is an error")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 2)
	Set changes = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changes = changes _ $ListBuild(entry.data.change)
	}
	Do $$$AssertEquals($ListToString(changes), "added,removed", "the audit log holds the addition and the removal")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexExists(other, "zz_one"), 1, "another server's tool row is still there")
	Do $$$AssertEquals(..ResourceExists("OcuTalon_MCP_" _ other), 1, "and so is its resource")
	// an unknown server changes nothing
	Set roles = ..OcuTalonRoles()
	Set restarts = +$Get(^||ZzOps("restarts"))
	For name = ..Server("u"), "", "%All", "x;y" {
		Set result = ..Run(..#SENDER, ..Remove(name))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER, "removing '" _ name _ "' is not_found")
	}
	Do $$$AssertEquals(..OcuTalonRoles(), roles, "nothing changed")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), restarts, "and no runner was restarted")
}

Method TestClassify()
{
	Set server = ..Server("c")
	Do ..MakeRows(server, "zz_one")
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one")
	Set row.Fingerprint = "fingerprintkept"
	Do row.%Save()
	// the word, the classification the audit log holds and its readOnly flag
	For case = $ListBuild("read-only", "safe", 1), $ListBuild("risky", "risky", 0), $ListBuild("unclassified", "unclassified", 0) {
		Set word = $List(case, 1)
		Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", word))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|saved|Saved", word _ " is saved")
		Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one")
		Do $$$AssertEquals(row.Classification _ "|" _ row.Fingerprint, word _ "|fingerprintkept", "the row holds " _ word _ " and keeps its fingerprint")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "Tool", "Tool", server, , $ListFind($ListBuild("read-only", "risky", "unclassified"), word))
		Set last = entries.%Get(entries.%Size() - 1)
		Do $$$AssertEquals(last.data.source _ "|" _ last.data.tool _ "|" _ last.data.classification _ "|" _ last.data.readOnly _ "|" _ last.data.irisUser _ "|" _ last.data.channel, server _ "|zz_one|" _ $List(case, 2) _ "|" _ $List(case, 3) _ "|" _ ..#USER _ "|web", "the Tool entry says " _ $List(case, 2) _ " with readOnly " _ $List(case, 3))
	}
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 0, "a classification restarts nothing")
	// nothing is changed by a refusal
	Do ..Run(..#SENDER, ..Classify(server, "zz_one", "read-only"))
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", "Tool", "Tool", server)
	Set count = entries.%Size()
	Set bad = $ListBuild($ListBuild(server, "zz_one", "Read-only", "bad_classification", ##class(OcuTalon.Mcp.Ops).#MESSAGECLASSIFICATION), $ListBuild(server, "zz_one", "", "bad_classification", ##class(OcuTalon.Mcp.Ops).#MESSAGECLASSIFICATION), $ListBuild(server, "zz_none", "risky", "not_found", ##class(OcuTalon.Mcp.Ops).#MESSAGENOTOOL), $ListBuild(..Server("x"), "zz_one", "risky", "not_found", ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER), $ListBuild("", "zz_one", "risky", "not_found", ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER))
	Set position = 0
	While $ListNext(bad, position, case) {
		Set result = ..Run(..#SENDER, ..Classify($List(case, 1), $List(case, 2), $List(case, 3)))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|" _ $List(case, 4) _ "|" _ $List(case, 5), "'" _ $List(case, 3) _ "' for '" _ $List(case, 2) _ "' is " _ $List(case, 4))
	}
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one").Classification, "read-only", "the classification is as it was")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", "Tool", "Tool", server).%Size(), count, "and no entry was added")
}

Method TestAuditFails()
{
	Set ^||ZzOps("auditError") = 1
	Set server = ..Server("f")
	Set roles = ..OcuTalonRoles()
	Set result = ..Run(..#SENDER, ..Add(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_audited|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "an add whose audit fails is answered not_audited")
	Do $$$AssertEquals(..Written(server), "", "the row is gone again")
	Do $$$AssertEquals(..ResourceExists("OcuTalon_MCP_" _ server), 0, "and so is the resource")
	Do $$$AssertEquals(..OcuTalonRoles(), roles, "the roles are as they were")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 0, "and no runner was restarted")
	// a classification
	Kill ^||ZzOps("auditError")
	Do ..MakeRows(server, "zz_one")
	Set ^||ZzOps("auditError") = 1
	Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", "read-only"))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_audited|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "a classification whose audit fails is answered not_audited")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_one").Classification, "unclassified", "and the tool is still unclassified")
	// a remove keeps the server, its rows and its resource
	Kill ^||ZzOps("auditError")
	Set again = ..Server("f2")
	Do ..Run(..#SENDER, ..Add(again))
	Do ..MakeTool(again, "zz_one", "risky", "fp")
	Set roles = ..OcuTalonRoles()
	Set ^||ZzOps("auditError") = 1
	Set result = ..Run(..#SENDER, ..Remove(again))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "0|not_audited", "a remove whose audit fails is answered not_audited")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(again, "zz_one").Classification, "risky", "the tool row is back")
	Do $$$AssertTrue(##class(OcuTalon.Mcp.Server).NameIndexExists(again), "and so is the server's row")
	Do $$$AssertEquals(..ResourceExists("OcuTalon_MCP_" _ again), 1, "and its resource")
	Do $$$AssertEquals(..RoleResources(..#ROLE) [ ("OcuTalon_MCP_" _ again _ ":U"), 1, "and its grant")
}

Method TestRestartFails()
{
	Set ^||ZzOps("restartError") = 1
	Set server = ..Server("g")
	Set result = ..Run(..#SENDER, ..Add(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|failed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "an add whose restart fails is answered failed")
	Do $$$AssertTrue(##class(OcuTalon.Mcp.Server).NameIndexExists(server), "the row is kept")
	Do $$$AssertEquals(..ResourceExists("OcuTalon_MCP_" _ server), 1, "and so is the resource")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 1, "the restart was tried once")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server)
	Do $$$AssertEquals(entries.%Size(), 1, "and the addition is audited")
	Set result = ..Run(..#SENDER, ..Remove(server))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "0|failed", "a remove whose restart fails is answered failed")
	Do $$$AssertEquals(..Written(server), "", "and the server is gone")
}

Method TestRolesCompose()
{
	Set server = ..Server("o")
	Set resource = "OcuTalon_MCP_" _ server
	Do ..Run(..#SENDER, ..Add(server))
	Set sc = ##class(OcuTalon.Install.Step.Roles).Compose(.roles)
	Do $$$AssertStatusOK(sc, "the Roles step composes the roles")
	Do $$$AssertEquals($Get(roles(..#ROLE, resource)), "U", "the service role holds the resource with U while the row exists")
	// the area declares the pair from the row, and none on the online demo
	Set grants = ##class(OcuTalon.Install.Step.Mcp).Grants()
	Set found = 0
	Set iterator = grants.%GetIterator()
	While iterator.%GetNext(, .grant) {
		If (grant.resource = resource) && (grant.role = ..#ROLE) && (grant.permission = "U") Set found = found + 1
	}
	Do $$$AssertEquals(found, 1, "Grants declares the pair once")
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..DemoSaved = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Mcp).Grants().%Size(), 0, "on an online-demo install Grants declares nothing")
	Kill roles
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Compose(.roles), "the Roles step composes the roles on the online demo")
	Do $$$AssertEquals($Data(roles(..#ROLE, resource)), 0, "and the service role holds no MCP server resource")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	// a row whose resource is gone is skipped with a warning, and the start does not fail
	Do ##class(OcuTalon.Install.Step.Mcp).Revoke(server)
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Set grants = ##class(OcuTalon.Install.Step.Mcp).Grants()
	Set found = 0
	Set iterator = grants.%GetIterator()
	While iterator.%GetNext(, .grant) {
		If grant.resource = resource Set found = found + 1
	}
	Do $$$AssertEquals(found, 0, "a row whose resource is missing declares no pair")
	Do $$$AssertTrue($ListLength(##class(OcuTalon.Install.Step).TakeWarnings()) >= 1, "and is a warning, not a failure")
}

Method TestRecordAttachRows()
{
	Set server = ..Server("t")
	Do ..MakeServer(server)
	Set report = {"status": "attached", "reason": "", "tools": ["zz_a", "zz_b"], "refused": ["zz_c"], "fingerprints": {"zz_a": "fpa", "zz_b": "fpb"}}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, report), "an attached report is recorded")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|unclassified|fpa;zz_b|unclassified|fpb;zz_c|unclassified|", "a row for each listed and refused tool, new ones unclassified, the refused one with no fingerprint")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_a").ChangedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", 1, "with the time they were made")
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_a")
	Set row.Classification = "read-only"
	Do row.%Save()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, report), "the same report again is recorded")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|read-only|fpa;zz_b|unclassified|fpb;zz_c|unclassified|", "and changes no row")
	Set again = {"status": "attached", "reason": "", "tools": ["zz_a"], "refused": [], "fingerprints": {"zz_a": "fpa"}}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, again), "a report with fewer tools is recorded")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|read-only|fpa", "the rows of the tools it no longer lists are deleted")
	Set down = {"status": "unavailable", "reason": "unreachable", "tools": [], "refused": []}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, down), "an unavailable report is recorded")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|read-only|fpa", "and keeps the rows")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(..Server("none"), report), "a report for an unknown server is an error")
	Do $$$AssertEquals(..ToolRows(..Server("none")), "", "and writes no row")
	// a report with no fingerprints gives rows with none
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_n"], "refused": []})
	Do $$$AssertEquals(..ToolRows(server), "zz_n|unclassified|", "a report with no fingerprints gives rows with none, and drops the old ones")
	// a classified tool that is reported refused keeps its classification and has no fingerprint; listed again, or listed with no fingerprints, it is cleared
	Set admin = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Kill ^||ZzOps("notice")
	Do ..MakeTool(server, "zz_k", "risky", "fpk")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": [], "refused": ["zz_k"], "fingerprints": {}})
	Do $$$AssertEquals(..ToolRows(server), "zz_k|risky|", "a classified tool that is reported refused keeps its classification and has an empty fingerprint")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Tool", "Tool", server).%Size(), 0, "with no audit entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 0, "and no mcp.toolChanged notice")
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_k"], "refused": [], "fingerprints": {"zz_k": "fpk"}})
	Do $$$AssertEquals(..ToolRows(server), "zz_k|unclassified|fpk", "reported listed again, the tool is cleared")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 1, "and the admin is told once")
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_k")
	Set row.Classification = "read-only"
	Do row.%Save()
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_k"], "refused": []})
	Do $$$AssertEquals(..ToolRows(server), "zz_k|unclassified|", "a classified tool in an attached report with no fingerprints member is cleared")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 2, "and the admin is told")
}

/// MCP tool names are case-sensitive: Foo and foo are two tools with two rows, and ClassifyTool finds a tool by its exact name.
Method TestToolNamesAreCaseSensitive()
{
	Set server = ..Server("i")
	Do ..MakeServer(server)
	Set admin = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Set report = {"status": "attached", "reason": "", "tools": ["Foo", "foo"], "refused": [], "fingerprints": {"Foo": "fpupper", "foo": "fplower"}}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, report), "a report with the tools Foo and foo is recorded")
	Do $$$AssertEquals(..ToolRows(server), "Foo|unclassified|fpupper;foo|unclassified|fplower", "there is a row for each, with its own fingerprint")
	Set result = ..Run(..#SENDER, ..Classify(server, "Foo", "read-only"))
	Do $$$AssertEquals(result.Outcome, "saved", "Foo is classified")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, report), "the same report again is recorded")
	Do $$$AssertEquals(..ToolRows(server), "Foo|read-only|fpupper;foo|unclassified|fplower", "and clears nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "and sends no notice")
	Set result = ..Run(..#SENDER, ..Classify(server, "FOO", "risky"))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTOOL, "FOO is not a tool of the server")
	Do $$$AssertEquals(..ToolRows(server), "Foo|read-only|fpupper;foo|unclassified|fplower", "and nothing changed")
}

/// AC 7: the address that a command gives, and the text of a failure that holds a credential (AI Hub's error text can), show in no result, no audit entry, no
/// notice, no event-log row and no stored row, on any path: add (valid, bad, taken, refused, not audited, restart failed), classify, remove and the attach report.
Method TestNoAddressOrSecretInAnyText()
{
	Set tag = ..Number _ "x" _ $Random(1000000000)
	Set address = "zzleakurl" _ tag
	Set secret = "zzleaksecret" _ tag
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set logMark = ..EventMark()
	Set admin = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Set server = ..Server("l")
	Set url = "https://" _ address _ ".example.invalid/mcp/" _ secret
	Set texts = ""
	// the add, its refusals and its failures
	Set result = ..Run(..#SENDER, ..Add(server, url))
	Do $$$AssertEquals(result.Outcome, "added", "the add of a server with the marked address is carried out")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Add(server, url))
	Do $$$AssertEquals(result.Outcome, "exists", "a second add is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Add(..Server("m"), "http://" _ address _ ".example.invalid/mcp?token=" _ secret))
	Do $$$AssertEquals(result.Outcome, "bad_address", "an address that is not allowed is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Add(..Server("r"), "https://" _ address _ ".example.invalid/mcp?token=" _ secret))
	Do $$$AssertEquals(result.Outcome, "bad_address", "an address with a query string is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Add("1" _ address, url))
	Do $$$AssertEquals(result.Outcome, "bad_name", "a bad name is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run("WebChatIn", ..Add(..Server("n"), url))
	Do $$$AssertEquals(result.Outcome, "not_allowed", "a wrong sender is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set ^||ZzOps("auditError") = 1
	Set result = ..Run(..#SENDER, ..Add(..Server("o"), url))
	Kill ^||ZzOps("auditError")
	Do $$$AssertEquals(result.Outcome, "not_audited", "an add whose audit fails is answered not_audited")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set ^||ZzOps("restartError") = 1
	Set result = ..Run(..#SENDER, ..Add(..Server("p"), url))
	Kill ^||ZzOps("restartError")
	Do $$$AssertEquals(result.Outcome, "failed", "an add whose restart fails is answered failed")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	// the attach report: a failure whose text holds the address and the credential, then a refused tool, then a changed one
	Set text = "Failed to add tool spec 'mcp:remote:" _ url _ "' with the header value " _ secret
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "unavailable", "reason": (text), "tools": [], "refused": []}), "a report whose reason is the failure text is recorded")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_a"], "refused": ["zz_shadow"], "fingerprints": {"zz_a": "fp1"}}), "an attached report with a refused tool is recorded")
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_a")
	Set row.Classification = "read-only"
	Do row.%Save()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_a"], "refused": ["zz_shadow"], "fingerprints": {"zz_a": "fp2"}}), "a report with a changed tool is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.serverUnavailable") _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolShadowsBuiltIn") _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), "1|1|1", "the three notices were sent, so the scan of the notices has something to scan")
	// classify, then remove
	Do ..MakeTool(server, "zz_one", "unclassified", "fp")
	Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", "risky"))
	Do $$$AssertEquals(result.Outcome, "saved", "a classification is carried out")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Classify(server, "zz_one", "maybe"))
	Do $$$AssertEquals(result.Outcome, "bad_classification", "a bad classification is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Remove(server))
	Do $$$AssertEquals(result.Outcome, "removed", "the remove is carried out")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Remove(..Server("q")))
	Do $$$AssertEquals(result.Outcome, "not_found", "the remove of an unknown server is refused")
	Set texts = texts _ result.Outcome _ "|" _ result.Message _ "|"
	Set result = ..Run(..#SENDER, ..Remove(..Server("p")))
	Do $$$AssertEquals(result.Outcome, "removed", "the server whose restart failed is removed")
	// the scans (the values are never part of a message)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", server, , 2)
	Do $$$AssertEquals(entries.%Size(), 2, "the audit log holds the addition and the removal, so the scan of the audit log has something to scan")
	Set notices = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%ToJSON()
	Do $$$AssertTrue(notices [ server, "the notices name the server, so a scan of them can find a value")
	Do $$$AssertEquals((texts [ address) + (texts [ secret), 0, "no result holds the address or the credential")
	Do $$$AssertEquals((notices [ address) + (notices [ secret), 0, "no notice holds the address or the credential")
	// IRIS's own audit entry of the Config Store entry that McpOps now writes (Story 21.4) holds the entry's address, so the scan names OcuTalon's own entries
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", , , address).%Size() + ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", , , secret).%Size(), 0, "no OcuTalon audit entry holds the address or the credential")
	Do $$$AssertEquals(..LogRowsHolding(logMark, address) + ..LogRowsHolding(logMark, secret), 0, "no event-log row holds the address or the credential")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(secret), "", "no trace global (message body, header or log row) holds the credential")
	Do $$$AssertTrue(..LogRowsHolding(logMark, "refused AddMcpServer") > 0, "the event log holds the warning of the refused add, so a scan of the log can find a value")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(..Server("p"))
	Do $$$AssertEquals($IsObject(row), 0, "no row of a removed server is left")
}

/// The fingerprint of a tool (Story 22.8): 64 lower-case hexadecimal characters that follow the server, the name, the description and the input schema and nothing
/// else; the order of the schema's keys does not matter.
Method TestToolFingerprint()
{
	Set context = "OcuTalon.Bridge.Context"
	Set server = "mcp:remote:@{config:AI.MCP.OcuTalon_zz}"
	Set schema = {"type": "object", "properties": {"id": {"type": "string", "description": "the id"}, "limit": {"type": "integer"}}, "required": ["id"]}
	Set base = $ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", schema)
	Do $$$AssertEquals($Length(base), 64, "a fingerprint is 64 characters")
	Do $$$AssertEquals($Translate(base, "0123456789abcdef"), "", "of lower-case hexadecimal digits")
	Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", schema), base, "the same tool has the same fingerprint")
	Set changedSchema = {"type": "object", "properties": {"id": {"type": "string", "description": "the id"}, "limit": {"type": "string"}}, "required": ["id"]}
	Do $$$AssertNotEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", changedSchema), base, "a change of the schema alone changes the fingerprint")
	Do $$$AssertNotEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket by id.", schema), base, "a change of the description alone changes the fingerprint")
	Do $$$AssertNotEquals($ClassMethod(context, "ToolFingerprint", server, "zz_find", "Looks up a ticket.", schema), base, "a change of the tool's name alone changes the fingerprint")
	Do $$$AssertNotEquals($ClassMethod(context, "ToolFingerprint", "mcp:remote:@{config:AI.MCP.OcuTalon_zy}", "zz_lookup", "Looks up a ticket.", schema), base, "a change of the server alone changes the fingerprint")
	Do $$$AssertNotEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket. ", schema), base, "a space more in the description changes it")
	Set reordered = {"required": ["id"], "properties": {"limit": {"type": "integer"}, "id": {"description": "the id", "type": "string"}}, "type": "object"}
	Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", reordered), base, "the order of the schema's keys, nested ones included, does not change it")
	Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", schema.%ToJSON()), base, "a schema given as JSON text is the same as the object")
	Set empty = $ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", {})
	Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", ""), empty, "blank parameters are the same as {}")
	Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", server, "zz_lookup", "Looks up a ticket.", "  "), empty, "and so is parameters of spaces")
	Do $$$AssertNotEquals(empty, base, "and {} differs from a real schema")
	// the canonical form is the hash of {description, name, parameters, server} with the keys sorted, so the value is not the hash of any other form
	Set canonical = "{""description"":""Looks up a ticket."",""name"":""zz_lookup"",""parameters"":{},""server"":""" _ server _ """}"
	Set digest = $SYSTEM.Encryption.SHAHash(256, $ZConvert(canonical, "O", "UTF8"))
	Set hex = ""
	For i = 1:1:$Length(digest) Set hex = hex _ $ZConvert($Extract($ZHex(256 + $Ascii(digest, i)), 2, 3), "L")
	Do $$$AssertEquals(empty, hex, "it is the SHA-256 in hexadecimal of the canonical text with the keys in order, computed here by hand")
}

Method TestChangedTool()
{
	Set server = ..Server("h")
	Do ..MakeServer(server)
	Set admin = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_a", "zz_b"], "refused": [], "fingerprints": {"zz_a": "fpa", "zz_b": "fpb"}})
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_a")
	Set row.Classification = "read-only"
	Do row.%Save()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set changed = {"status": "attached", "reason": "", "tools": ["zz_a", "zz_b"], "refused": [], "fingerprints": {"zz_a": "fpa2", "zz_b": "fpb2"}}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, changed), "the report of the changed tools is recorded")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|unclassified|fpa2;zz_b|unclassified|fpb2", "the classified tool is unclassified again, with the new fingerprint, and the unclassified one has the new fingerprint")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Tool", "Tool", server)
	Do $$$AssertEquals(entries.%Size(), 1, "one Tool entry is audited, for the classified tool only")
	If entries.%Size() {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.source _ "|" _ data.tool _ "|" _ data.classification _ "|" _ data.readOnly _ "|" _ data.irisUser _ "|" _ data.channel, server _ "|zz_a|unclassified|0|" _ $Username _ "|system", "it says unclassified, by the running user, on the system channel")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 1, "the admin session gets one mcp.toolChanged notice")
	Set notices = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices()
	Do $$$AssertEquals(notices.%Size(), 1, "and no other notice")
	Set expected = {"tool": "zz_a", "server": (server)}.%ToJSON()
	If notices.%Size() Do $$$AssertEquals(notices.%Get(0).kind _ "|" _ notices.%Get(0).slots, "status|" _ expected, "which is of kind status, with the tool and the server")
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, changed)
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 1, "the same report again sends no notice")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Tool", "Tool", server).%Size(), 1, "and audits nothing")
}

Method TestClearChanged()
{
	Set server = ..Server("k")
	Do ..MakeServer(server)
	Set admin = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Do ..MakeTool(server, "zz_a", "risky", "fpa")
	Do ..MakeTool(server, "zz_u", "unclassified", "fpu")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, "zz_a", "fpa"), "a fingerprint that is the row's clears nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, "zz_none", "x"), "a tool with no row clears nothing")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|risky|fpa;zz_u|unclassified|fpu", "the rows are as they were")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "and no notice was sent")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, "zz_a", "fpa2"), "a changed fingerprint is cleared")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|unclassified|fpa2;zz_u|unclassified|fpu", "the tool is unclassified with the new fingerprint")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 1, "the admin gets one notice")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Tool", "Tool", server).%Size(), 1, "and the change is audited")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, "zz_u", "fpu2"), "an unclassified tool takes the new fingerprint")
	Do $$$AssertEquals(..ToolRows(server), "zz_a|unclassified|fpa2;zz_u|unclassified|fpu2", "with no other change")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 1, "and no notice")
	// an audit that fails leaves the tool cleared and still tells the admin
	Do ..MakeTool(server, "zz_f", "read-only", "fpf")
	Set ^||ZzOps("auditError") = 1
	Do $$$AssertStatusNotOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, "zz_f", "fpf2"), "a change that cannot be audited is an error")
	Kill ^||ZzOps("auditError")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_f").Classification, "unclassified", "but the tool is unclassified")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 2, "and the admin is still told")
}

Method TestNotices()
{
	Set server = ..Server("n")
	Do ..MakeServer(server)
	Set admin = ..MakeAdmin()
	Set other = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin, other)
	Set down = {"status": "unavailable", "reason": "unreachable", "tools": [], "refused": []}
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, down)
	For ref = admin, other {
		Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(ref, "mcp.serverUnavailable"), 1, "an admin session gets one mcp.serverUnavailable when the server turns unavailable")
	}
	Set notices = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices()
	Set slots = {}.%FromJSON(notices.%Get(0).slots)
	Do $$$AssertEquals(notices.%Get(0).kind _ "|" _ slots.server, "status|" _ server, "of kind status, with the server")
	Do $$$AssertTrue(slots.time ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the time, UTC")
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, down)
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 2, "the same report again sends nothing")
	// attached, with a refused tool: one shadow notice per admin session, once
	Set up = {"status": "attached", "reason": "", "tools": ["zz_a"], "refused": ["zz_shadow"], "fingerprints": {"zz_a": "fpa"}}
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, up)
	For ref = admin, other {
		Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(ref, "mcp.toolShadowsBuiltIn"), 1, "an admin session gets one mcp.toolShadowsBuiltIn for a tool newly refused")
	}
	Set notices = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices()
	Set expected = {"server": (server), "tool": "zz_shadow"}.%ToJSON()
	Do $$$AssertEquals({}.%FromJSON(notices.%Get(notices.%Size() - 1).slots).%ToJSON(), expected, "which names the server and the tool")
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, up)
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 4, "the same report again sends nothing")
	// unavailable again after being attached: a new transition
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, down)
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.serverUnavailable"), 2, "a server that turns unavailable again sends another notice")
	// a failing read of the admins' sessions sends nothing and the rows are still written
	Kill ^||ZzOps("notice")
	Set ^||ZzOps("adminsError") = 1
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, up)
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, down)
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "when the admins' sessions cannot be read no notice is sent")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Server).NameIndexOpen(server).AttachStatus, "unavailable", "and the row is still written")
	// a notice that cannot be sent does not fail the report
	Kill ^||ZzOps("adminsError")
	Set ^||ZzOps("noticeError") = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, up), "a report whose notice cannot be sent is still recorded")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Server).NameIndexOpen(server).AttachStatus, "attached", "and the row says attached")
}

/// The real read of the admins' sessions: a session row with AdminAtSignIn 1 is listed, and one without is not.
Method TestAdminSessionsRead()
{
	Set admin = ..MakeAdmin()
	Set plain = ..MakeAdmin(0)
	Set found = ##class(OcuTalon.Data.Ownership).AdminSessions(.sc)
	Do $$$AssertStatusOK(sc, "the read of the admins' sessions works")
	Do $$$AssertEquals($ListFind(found, admin) > 0, 1, "the admin's session is listed")
	Do $$$AssertEquals($ListFind(found, plain), 0, "and a session that is not an admin's is not")
}

/// --- helpers ---
/// The highest id of the event log.
Method EventMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of event-log rows after the mark whose text holds the value.
Method LogRowsHolding(mark As %Integer, value As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Text [ ?", mark, value)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The name of the test's server with the suffix, which the clean-up removes.
Method Server(suffix As %String) As %String [ Private ]
{
	Set name = "zzmcpops" _ ..Number _ suffix
	If '$ListFind($ListFromString(..Names), name) Set ..Names = ..Names _ $Select(..Names = "": "", 1: ",") _ name
	Quit name
}

/// Saves a pending tool_call request (a fixture row, with no hold) for the tool zz_one of the server, with the server's toolref and a fingerprint, and returns its Ref
/// (Story 22.4): the request that a removal of the server cancels.
Method PendingRequest(server As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", "zz_one", "{""id"":""1""}", ##class(OcuTalon.Mcp.Attach).Toolref(server), "ChatAgent")
	Set row.ToolFingerprint = "fingerprintofzzone"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "pending", 3600, , .ref), "a pending request for " _ server _ " is saved")
	Set ^||ZzOps("requests") = $Get(^||ZzOps("requests")) _ $Select($Get(^||ZzOps("requests")) = "": "", 1: ",") _ ref
	Quit ref
}

/// Deletes the approval rows of the Refs (a comma list).
Method DeleteRequests(refs As %String) [ Private ]
{
	For i = 1:1:$Length(refs, ",") {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen($Piece(refs, ",", i))
		If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
	}
}

/// Runs the command through a probe whose request header names the sender.
Method Run(sender As %String, command As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow(sender, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.MessageHandler(command, .result)
	Do $$$AssertStatusOK(sc, "the command is delivered by the message map and answered with an OK status")
	Quit result
}

Method Add(server As %String, url As %String = {..#URL}, origin As %String = "web_admin", user As %String = {..#USER}) As OcuTalon.Msg.Command.AddMcpServer [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.AddMcpServer).%New()
	Set command.Server = server
	Set command.Url = url
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

Method Remove(server As %String, origin As %String = "web_admin", user As %String = {..#USER}) As OcuTalon.Msg.Command.RemoveMcpServer [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveMcpServer).%New()
	Set command.Server = server
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

Method Classify(server As %String, tool As %String, word As %String, origin As %String = "web_admin", user As %String = {..#USER}) As OcuTalon.Msg.Command.ClassifyTool [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ClassifyTool).%New()
	Set command.Server = server
	Set command.Tool = tool
	Set command.Classification = word
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

/// A SetSourcePoll for the tool, from the admin session, with fixed values.
Method SetSource(server As %String, tool As %String, session As %String, origin As %String = "web_admin", user As %String = {..#USER}) As OcuTalon.Msg.Command.SetSourcePoll [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetSourcePoll).%New()
	Set command.Server = server
	Set command.Tool = tool
	Set command.Name = "Jira"
	Set command.Arguments = "{}"
	Set command.IntervalMinutes = 15
	Set command.SessionRef = session
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

Method RemoveSource(ref As %String, session As %String, origin As %String = "web_admin", user As %String = {..#USER}) As OcuTalon.Msg.Command.RemoveSourcePoll [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveSourcePoll).%New()
	Set command.SourceRef = ref
	Set command.SessionRef = session
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

/// The check rows of the session.
Method SourceRows(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// A server row with no resource, and a tool row of each name (unclassified, with the fingerprint "fp").
Method MakeRows(server As %String, tools As %String) [ Private ]
{
	Do ..MakeServer(server)
	For i = 1:1:$Length(tools, ",") Do ..MakeTool(server, $Piece(tools, ",", i), "unclassified", "fp")
}

Method MakeServer(server As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = server
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture row " _ server _ " is saved")
}

Method MakeTool(server As %String, tool As %String, classification As %String, fingerprint As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set row.Server = server
	Set row.Tool = tool
	Set row.Classification = classification
	Set row.Fingerprint = fingerprint
	Set row.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture tool " _ tool _ " of " _ server _ " is saved")
}

/// A fixture session, an admin's unless admin is 0. Returns its Ref.
Method MakeAdmin(admin As %Boolean = 1) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.IrisUser = "zzmcpops" _ ..Number
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.AdminAtSignIn = admin
	Do $$$AssertStatusOK(row.%Save(), "the fixture session is saved")
	Set ..Admin = ..Admin _ $Select(..Admin = "": "", 1: ",") _ row.Ref
	Quit row.Ref
}

/// The tool rows of the server as "tool|classification|fingerprint" joined by ";", in the order of the names.
Method ToolRows(server As %String) As %String [ Private ]
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, Classification, Fingerprint FROM OcuTalon_Mcp.ToolClassification WHERE Server = ? ORDER BY %EXACT(Tool)", server)
	While result.%Next() {
		Set text = text _ $Select(text = "": "", 1: ";") _ result.%Get("Tool") _ "|" _ result.%Get("Classification") _ "|" _ result.%Get("Fingerprint")
	}
	Quit text
}

/// What is written for the server: its row and its tool rows, as a text of places ("" when nothing).
Method Written(server As %String) As %String [ Private ]
{
	Set places = ""
	If server '= "", ##class(OcuTalon.Mcp.Server).NameIndexExists(server) Set places = places _ $ListBuild("the row")
	If ..ToolRows(server) '= "" Set places = places _ $ListBuild("the tool rows")
	Quit $ListToString(places, ", ")
}

/// The Resources of the role in %SYS (resource:permission pairs, comma-separated), or "" when the role does not exist.
Method RoleResources(role As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	If '##class(Security.Roles).Exists(role) Quit ""
	Do ##class(Security.Roles).Get(role, .properties)
	Quit $Get(properties("Resources"))
}

/// The Resources of every role whose name starts with OcuTalon, as "role=resources" joined by ";", in the order of the names.
Method OcuTalonRoles() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Roles WHERE Name LIKE 'OcuTalon%' ORDER BY Name")
	While result.%Next() {
		Kill properties
		Do ##class(Security.Roles).Get(result.%Get("Name"), .properties)
		Set text = text _ $Select(text = "": "", 1: ";") _ result.%Get("Name") _ "=" _ $Get(properties("Resources"))
	}
	Quit text
}

/// The text of OcuTalonRoles without the role.
Method Without(text As %String, role As %String) As %String [ Private ]
{
	Set kept = ""
	For i = 1:1:$Length(text, ";") {
		Set part = $Piece(text, ";", i)
		If ($Piece(part, "=", 1) '= role) && (part '= "") Set kept = kept _ $Select(kept = "": "", 1: ";") _ part
	}
	Quit kept
}

/// The pairs of the role's Resources in the text of OcuTalonRoles, comma-separated.
Method Pairs(text As %String, role As %String) As %String [ Private ]
{
	Set pairs = ""
	For i = 1:1:$Length(text, ";") {
		Set part = $Piece(text, ";", i)
		If $Piece(part, "=", 1) '= role Continue
		Set pairs = $Piece(part, "=", 2, *)
	}
	Quit pairs
}

/// The pairs of a comma-separated Resources text, sorted, so that the order IRIS keeps them in plays no part.
Method SortedPairs(resources As %String) As %String [ Private ]
{
	Kill pairs
	For i = 1:1:$Length(resources, ",") {
		If $Piece(resources, ",", i) '= "" Set pairs($Piece(resources, ",", i)) = ""
	}
	Set text = ""
	Set pair = ""
	For {
		Set pair = $Order(pairs(pair))
		Quit:pair=""
		Set text = text _ $Select(text = "": "", 1: ",") _ pair
	}
	Quit text
}

/// The %All and %Admin_ resources that the OcuTalon roles in the text hold, as "role:resource" joined by ",".
Method AdminResources(text As %String) As %String [ Private ]
{
	Set found = ""
	For i = 1:1:$Length(text, ";") {
		Set part = $Piece(text, ";", i)
		Set resources = $Piece(part, "=", 2, *)
		For j = 1:1:$Length(resources, ",") {
			Set name = $Piece($Piece(resources, ",", j), ":", 1)
			If (name = "%All") || ($Extract(name, 1, 7) = "%Admin_") Set found = found _ $Select(found = "": "", 1: ",") _ $Piece(part, "=", 1) _ ":" _ name
		}
	}
	Quit found
}

Method ResourceExists(name As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Resources).Exists(name)
}

Method PublicPermission(name As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	Do ##class(Security.Resources).Get(name, .properties)
	Quit $Get(properties("PublicPermission"))
}

Method ResourceCount() As %Integer [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Security.Resources")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Removes every fixture this test may have made: the servers' rows and tool rows, their resources and grants, the entry, wallet key and collection that McpOps writes for an add, and the fixture sessions. Each removal is attempted
/// whatever happened before.
Method Clean() [ Private ]
{
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(name)
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_" _ name) Do ##class(%ConfigStore.Configuration).Delete("AI.MCP.OcuTalon_" _ name)
		If ##class(%Wallet.Secret).Exists("OcuTalon_MCP_" _ name _ ".Key") Do ##class(%Wallet.KeyValue).Delete("OcuTalon_MCP_" _ name _ ".Key")
		If ##class(%Wallet.Collection).Exists("OcuTalon_MCP_" _ name) Do ##class(%Wallet.Collection).Delete("OcuTalon_MCP_" _ name)
	}
	For i = 1:1:$Length(..Admin, ",") {
		Set ref = $Piece(..Admin, ",", i)
		If ref '= "", ##class(OcuTalon.Data.Session).RefIndexExists(ref, .id) Do ##class(OcuTalon.Data.Session).%DeleteId(id)
	}
	If ..Guarded Do ..Restore()
}

/// Snapshots the OcuTalon roles and the OcuTalon_MCP_ resources for Restore.
Method Guard() [ Private ]
{
	Set ..RoleSnapshot = ..OcuTalonRoles()
	Set ..ResourceSnapshot = ..McpResources()
	Set ..Guarded = 1
}

/// The names of the OcuTalon_MCP_ resources, comma-separated and sorted.
Method McpResources() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set names = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Resources ORDER BY Name")
	While result.%Next() {
		If $Extract(result.%Get("Name"), 1, 13) = "OcuTalon_MCP_" Set names = names _ $Select(names = "": "", 1: ",") _ result.%Get("Name")
	}
	Quit names
}

/// Puts the Resources of each OcuTalon role back as Guard saw them, then deletes the OcuTalon_MCP_ resources that Guard did not see.
Method Restore() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	For i = 1:1:$Length(..RoleSnapshot, ";") {
		Set part = $Piece(..RoleSnapshot, ";", i)
		Set role = $Piece(part, "=", 1)
		If role = "" Continue
		Kill properties
		If '##class(Security.Roles).Exists(role) || '$$$ISOK(##class(Security.Roles).Get(role, .properties)) Continue
		If $Get(properties("Resources")) = $Piece(part, "=", 2, *) Continue
		Kill properties
		Set properties("Resources") = $Piece(part, "=", 2, *)
		Do ##class(Security.Roles).Modify(role, .properties)
	}
	Set names = ..McpResources()
	For i = 1:1:$Length(names, ",") {
		Set name = $Piece(names, ",", i)
		If (name '= "") && '$ListFind($ListFromString(..ResourceSnapshot), name) Do ##class(Security.Resources).Delete(name)
	}
}

/// What is left of the fixtures, as a text of places ("" when nothing): a row, a tool row, a resource, a grant or a session.
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	Set roles = ..RoleResources(..#ROLE)
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		If ..Written(name) '= "" Set places = places _ $ListBuild(name _ " rows")
		If ..ResourceExists("OcuTalon_MCP_" _ name) Set places = places _ $ListBuild(name _ " resource")
		If roles [ ("OcuTalon_MCP_" _ name) Set places = places _ $ListBuild(name _ " grant")
	}
	For i = 1:1:$Length(..Admin, ",") {
		Set ref = $Piece(..Admin, ",", i)
		If ref '= "", ##class(OcuTalon.Data.Session).RefIndexExists(ref) Set places = places _ $ListBuild("a session")
	}
	Quit $ListToString(places, ", ")
}

}
