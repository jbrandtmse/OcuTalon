/// Tests of the audit writer (Story 3.7; AD-17, FR-9, NFR-11). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it writes entries to the
/// IRIS audit log of the instance and reads them back through Test.Bridge.AuditLog (by time, with a fresh Ref as the marker of its own entries, never
/// by a count of all entries). It changes no setting. Instance-wide auditing and OcuTalon's events must be on, as a clean install leaves them.
///   - TestEveryTypeHasOneShape (row 1): Record of each of the six types writes one entry: source OcuTalon, the type as EventType and Event, data of
///     exactly Shape(type) with the given values, the derived description, a time between the mark and now, and the writing user;
///   - TestRecordRefusesAnyOtherShape (row 2): a missing or extra member, a value of the wrong JSON type or outside its set, an empty required value, a
///     malformed Ref, an unknown type and data that is not an object are each refused, with an error that names the type and the member and not the
///     value, and no entry is written;
///   - TestNoSecretInAnyEntry (row 3): a model key, an access token, a password, a Telegram chat id and display name, a bearer token and URL
///     credentials, in Write's data and description and in the free text of Record's entries, are in no entry read back, also when a key in a long
///     description would straddle the 128-character cut (the description is redacted first, then cut); a sensitive setting's values are blanked, and
///     the caller's object is not changed.
Class OcuTalon.Test.Bridge.Audit Extends %UnitTest.TestCase
{

/// How long a refused entry is waited for, in seconds.
Parameter REFUSEDSECONDS = 2;

/// Row 1: one entry for each type, in its one shape.
Method TestEveryTypeHasOneShape()
{
	Set types = $ListFromString(##class(OcuTalon.Bridge.Audit).#TYPES)
	Set position = 0
	While $ListNext(types, position, type) {
		Set marker = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set data = ..Valid(type, marker)
		Set expected = ..Description(type, data)
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record(type, data), type_": Record writes the entry")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", type, type, marker)
		Do $$$AssertEquals(entries.%Size(), 1, type_": one entry of source OcuTalon, type and event "_type_" carries the marker")
		If entries.%Size() '= 1 Continue
		Set entry = entries.%Get(0)
		Set shape = ##class(OcuTalon.Bridge.Audit).Shape(type)
		Do $$$AssertTrue($IsObject(entry.data), type_": the data is a JSON object")
		If '$IsObject(entry.data) Continue
		Do $$$AssertEquals(entry.data.%Size(), $ListLength(shape), type_": the data has exactly the "_$ListLength(shape)_" members of Shape("_type_")")
		Set member = 0
		While $ListNext(shape, member, name) {
			Set want = data.%Get(name)
			Set got = entry.data.%Get(name)
			If $IsObject(want) {
				Do $$$AssertEquals(got.%ToJSON(), want.%ToJSON(), type_": "_name_" is as given")
			} Else {
				Do $$$AssertEquals(got, want, type_": "_name_" is as given")
			}
			Do $$$AssertEquals(entry.data.%GetTypeOf(name), data.%GetTypeOf(name), type_": "_name_" keeps its JSON type")
		}
		Do $$$AssertEquals(entry.description, expected, type_": the description is derived from the data: "_expected)
		Do $$$AssertTrue((entry.at ] mark) || (entry.at = mark), type_": the time "_entry.at_" is not before the mark "_mark)
		Do $$$AssertTrue('(entry.at ] ##class(OcuTalon.Test.Bridge.AuditLog).Now()), type_": and not after now")
		Do $$$AssertEquals(entry.username, $Username, type_": the entry is written by the calling process's user")
	}
	Do $$$AssertEquals($ListLength(types), 6, "the six types were covered")
}

/// Row 2: every other shape is refused before anything is written.
Method TestRecordRefusesAnyOtherShape()
{
	Set marker = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set cases = $ListBuild(
		$ListBuild("Action", "approvalRef", "remove"),
		$ListBuild("Approval", "ownerRef", "remove"),
		$ListBuild("Tool", "readOnly", "remove"),
		$ListBuild("Action", "chatId", "set", "987654321", "string"),
		$ListBuild("Pairing", "displayName", "set", "Zz Jane Doe", "string"),
		$ListBuild("Action", "counts", "set", "3", "string"),
		$ListBuild("Action", "counts", "counts", "many", "string"),
		$ListBuild("Tool", "readOnly", "set", 2, "number"),
		$ListBuild("Tool", "readOnly", "set", "1", "string"),
		$ListBuild("Tool", "readOnly", "set", 1, "boolean"),
		$ListBuild("Approval", "change", "set", "deleted", "string"),
		$ListBuild("Pairing", "change", "set", "paired", "string"),
		$ListBuild("MCP", "change", "set", "updated", "string"),
		$ListBuild("Pairing", "channel", "set", "sms", "string"),
		$ListBuild("Tool", "classification", "set", "readonly", "string"),
		$ListBuild("Action", "sessionRef", "set", "zzsession", "string"),
		$ListBuild("Action", "approvalRef", "set", "zzapproval", "string"),
		$ListBuild("Action", "sessionRef", "set", "abcdefghijklmnopqrst!#", "string"),
		$ListBuild("Approval", "ref", "set", "abcdefghijklmnopqrstu", "string"),
		$ListBuild("Approval", "ref", "set", "zzref", "string"),
		$ListBuild("Approval", "ownerRef", "set", "zzowner", "string"),
		$ListBuild("Approval", "kind", "set", "chat", "string"),
		$ListBuild("Approval", "from", "set", "waiting", "string"),
		$ListBuild("Approval", "to", "set", "finished", "string"),
		$ListBuild("Action", "irisUser", "set", "", "string"),
		$ListBuild("Action", "action", "set", "", "string"),
		$ListBuild("Settings", "setting", "set", "", "string"),
		$ListBuild("MCP", "server", "set", "", "string"),
		$ListBuild("Tool", "source", "set", "", "string"),
		$ListBuild("Tool", "tool", "set", "", "string"),
		$ListBuild("Action", "result", "set", 5, "number"),
		$ListBuild("Pairing", "reason", "null"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set type = $List(case, 1)
		Set member = $List(case, 2)
		Set how = $List(case, 3)
		Set value = $ListGet(case, 4)
		Set data = ..Valid(type, marker)
		If how = "remove" {
			Do data.%Remove(member)
		} ElseIf how = "null" {
			Do data.%Set(member, "", "null")
		} ElseIf how = "counts" {
			Do data.counts.%Set("resent", value, "string")
		} Else {
			Do data.%Set(member, value, $List(case, 5))
		}
		Set label = type_" with "_member_" ("_how_$Select(how = "set": " "_$Extract(value, 1, 12), 1: "")_")"
		Set sc = ##class(OcuTalon.Bridge.Audit).Record(type, data)
		Do $$$AssertStatusNotOK(sc, label_" is refused")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue((text [ type) && (text [ ("'"_member_"'")), label_": the error names the type and the member: "_text)
		If (how = "set") && ($Length(value) > 2) && ($List(case, 5) = "string") {
			Do $$$AssertTrue(text '[ value, label_": the error does not hold the value")
		}
	}
	Set unknown = ##class(OcuTalon.Bridge.Audit).Record("Zz", ..Valid("Action", marker))
	Do $$$AssertStatusNotOK(unknown, "type Zz is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(unknown) [ "Zz", "the error names the type Zz")
	Set unknown = ##class(OcuTalon.Bridge.Audit).Record("action", ..Valid("Action", marker))
	Do $$$AssertStatusNotOK(unknown, "the type is matched exactly")
	Set others(1) = "not an object"
	Set others(2) = []
	Set others(3) = 5
	Set others(4) = ""
	Set index = ""
	For {
		Set index = $Order(others(index))
		Quit:index=""
		Set sc = ##class(OcuTalon.Bridge.Audit).Record("Action", others(index))
		Do $$$AssertStatusNotOK(sc, "data that is not an object is refused")
		Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) [ "Action") && ($SYSTEM.Status.GetErrorText(sc) [ "dynamic object"), "and the error says so, naming the type")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "", "", marker, "", 1, ..#REFUSEDSECONDS)
	Do $$$AssertEquals(entries.%Size(), 0, "no entry carries the marker: nothing was written")
}

/// Row 3: no secret in any entry.
Method TestNoSecretInAnyEntry()
{
	Set marker = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set apiKey = ..Random()
	Set accessToken = ..Random()
	Set password = ..Random()
	Set chat = ..Random()
	Set display = ..Random()
	Set bearer = ..Random()
	Set modelKey = "sk-ant-api03-" _ ..Random() _ ..Random()
	Set urlPassword = ..Random()
	Set chatId = 100000000 + $Random(899999999)
	Set first = ..Random()
	Set handle = ..Random()
	Set from = ..Random()
	Set to = ..Random()
	Set longKey = "sk-" _ ..Random()
	Set secrets = $ListBuild(apiKey, accessToken, password, chat, display, bearer, modelKey, urlPassword, chatId, first, handle, from, to, longKey)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

	Set raw = {"apiKey": (apiKey), "accessToken": (accessToken), "password": (password), "chatId": (chat), "displayName": (display), "marker": (marker)}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Write("Action", raw, "zz "_marker_" Bearer "_bearer), "Write writes the raw entry")

	Set long = {"marker": (marker)}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Write("Action", long, $Translate($Justify("", 110), " ", "x") _ " " _ longKey), "Write writes a description whose key starts before the 128th character and ends after it")

	Set action = ..Valid("Action", marker)
	Do action.%Set("result", modelKey, "string")
	Do action.%Set("target", "https://zz:" _ urlPassword _ "@example.com/x", "string")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Action", action), "Record writes an Action whose result and target hold secrets")

	Set update = {"update_id": 1, "message": {"chat": {"id": (chatId), "first_name": (first), "username": (handle)}, "text": "hello"}}
	Set pairing = ..Valid("Pairing", marker)
	Do pairing.%Set("reason", update.%ToJSON(), "string")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Pairing", pairing), "Record writes a Pairing whose reason is a Telegram update")

	Set settings = ..Valid("Settings", marker)
	Do settings.%Set("setting", "ZzBotToken", "string")
	Do settings.%Set("from", from, "string")
	Do settings.%Set("to", to, "string")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Settings", settings), "Record writes a Settings entry of a sensitive setting")
	Do $$$AssertEquals(settings.from_"|"_settings.to, from_"|"_to, "the caller's Settings object is unchanged")

	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "", "", marker, "", 5)
	Do $$$AssertEquals(entries.%Size(), 5, "five entries carry the marker")
	Set redacted = ##class(OcuTalon.Bridge.Redact).#REDACTED
	For index = 0:1:entries.%Size() - 1 {
		Set entry = entries.%Get(index)
		Set whole = $Select($IsObject(entry.data): entry.data.%ToJSON(), 1: entry.data) _ "|" _ entry.description
		Set position = 0
		While $ListNext(secrets, position, secret) {
			Do $$$AssertTrue(whole '[ secret, "entry "_(index + 1)_": no secret value is in its data or description")
		}
		Do $$$AssertTrue(whole [ marker, "entry "_(index + 1)_": the marker remains")
	}
	For index = 0:1:entries.%Size() - 1 {
		Set byWord($Piece(entries.%Get(index).description, " ", 1)) = entries.%Get(index)
	}
	Set longEntry = $Get(byWord($Translate($Justify("", 110), " ", "x")))
	Do $$$AssertTrue($IsObject(longEntry), "the long-description entry is found by its description")
	If $IsObject(longEntry) {
		Do $$$AssertTrue($Length(longEntry.description) <= 128, "its description holds at most 128 characters")
		Do $$$AssertTrue(longEntry.description '[ "sk-", "and no part of the key a cut at the 128th character would have left")
		Do $$$AssertTrue(longEntry.description [ redacted, "the key was redacted before the description was cut")
	}
	Set raw = $Get(byWord("zz"))
	Do $$$AssertTrue($IsObject(raw), "the raw entry is found by its description")
	If $IsObject(raw) {
		Do $$$AssertEquals(raw.data.marker, marker, "the raw entry keeps the marker")
		Do $$$AssertEquals(raw.data.apiKey_"|"_raw.data.accessToken_"|"_raw.data.password_"|"_raw.data.chatId_"|"_raw.data.displayName, redacted_"|"_redacted_"|"_redacted_"|"_redacted_"|"_redacted, "and the values of its five sensitive keys are redacted")
		Do $$$AssertTrue(raw.description [ marker, "and the marker of its description")
		Do $$$AssertTrue(raw.description '[ bearer, "and the bearer token is gone from its description")
	}
	Set record = $Get(byWord("resend:"))
	Do $$$AssertTrue($IsObject(record), "the Action entry is found by its description")
	If $IsObject(record) {
		Do $$$AssertEquals(record.data.action_"|"_record.data.counts.resent, "resend|3", "and its non-secret members remain")
		Do $$$AssertEquals(record.data.result, redacted, "while its result, a model key, is "_redacted)
	}
	Set setting = $Get(byWord("Setting"))
	Do $$$AssertTrue($IsObject(setting), "the Settings entry is found by its description")
	If $IsObject(setting) {
		Do $$$AssertEquals(setting.data.from_"|"_setting.data.to, redacted_"|"_redacted, "the sensitive setting's from and to are "_redacted)
		Do $$$AssertEquals(setting.data.setting, "ZzBotToken", "and its name remains")
	}
	Set pairingEntry = $Get(byWord("Pairing"))
	Do $$$AssertTrue($IsObject(pairingEntry), "the Pairing entry is found by its description")
	If $IsObject(pairingEntry) {
		Do $$$AssertEquals(pairingEntry.data.change_"|"_pairingEntry.data.channel, "linked|telegram", "and its non-secret members remain")
	}
}

/// A valid entry of the type: every member of Shape(type), the marker in sessionRef and in one free member.
ClassMethod Valid(type As %String, marker As %String) As %DynamicObject [ Private ]
{
	Set data = {}
	If type = "Action" {
		Set data = {"action": "resend", "target": (marker), "result": "done", "counts": {"resent": 3, "skipped": 0}, "approvalRef": ""}
	} ElseIf type = "Approval" {
		Set data = {"ref": (marker), "kind": "fix", "change": "answered", "from": "pending", "to": "approved", "outcome": "approved", "target": (marker), "ownerRef": "instance"}
	} ElseIf type = "Pairing" {
		Set data = {"change": "linked", "reason": (marker)}
	} ElseIf type = "Settings" {
		Set data = {"setting": "ZzSetting", "from": (marker), "to": "b"}
	} ElseIf type = "MCP" {
		Set data = {"change": "added", "server": (marker)}
	} ElseIf type = "Tool" {
		Set data = {"source": "docs", "tool": (marker), "classification": "safe", "readOnly": 1}
	}
	Do data.%Set("irisUser", "ocutalon", "string")
	Do data.%Set("sessionRef", $Select(type = "Approval": ##class(OcuTalon.Bridge.Ids).NewRef(), 1: marker), "string")
	Do data.%Set("channel", $Select(type = "Pairing": "telegram", 1: "web"), "string")
	Quit data
}

/// The description that Record derives for the data of a valid entry of the type.
ClassMethod Description(type As %String, data As %DynamicObject) As %String [ Private ]
{
	Quit $Case(type,
		"Action": data.action_": "_data.result,
		"Approval": "Approval "_data.ref_" "_data.change_": "_data.to,
		"Pairing": "Pairing "_data.change,
		"Settings": "Setting "_data.setting_" changed",
		"MCP": "MCP server "_data.server_" "_data.change,
		"Tool": "Tool "_data.tool_" of "_data.source_": "_data.classification,
		: "")
}

/// A random value that the redactor does not recognise by its shape: 22 characters of base64url.
ClassMethod Random() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ids).NewRef()
}

}
