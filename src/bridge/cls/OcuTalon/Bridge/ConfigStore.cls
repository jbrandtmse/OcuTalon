/// The Config Store API (AD-19). Merge changes some fields of an AI Hub LLM entry and leaves the others as they are; it is
/// the one run-time writer of those entries, and the first caller is the model-change API of Story 17.3. Details reads an entry
/// with its placeholders unresolved, for Merge and for OcuTalon.Bridge.Keys. The bridge names no other OcuTalon package here (AD-2).
/// What Merge guards (AD-19): an api_key field, at any depth, takes only one environment placeholder, @{env:NAME}, which
/// AI Hub resolves inside its provider, and an @{ in any other string or field name is refused, so that no merged value can
/// expand an environment variable that is not a key placeholder. Merge judges nothing else: not the variable a placeholder
/// names, not base_url or a header, not a secret:// reference, not a literal credential in a field other than api_key. A
/// caller that takes the fields from a user validates them first.
Class OcuTalon.Bridge.ConfigStore
{

/// The area of the entries.
Parameter AREA = "AI";

/// The type of the entries.
Parameter TYPE = "LLM";

/// The only form of an api_key value: one environment placeholder (an ICU pattern, anchored at both ends).
Parameter KEYPATTERN = "^@\{env:[A-Za-z0-9_]+\}\z";

/// Merges fields into the entry and leaves the entry's other fields as they are. entry is the fully qualified name of the
/// entry (AI.LLM.OcuTalonTriage), or a name of fewer than three dotted parts, which names the entry AI.LLM.<name>.
/// The merge is deep: an object in fields merges into the object of the entry, any other value replaces the value of the
/// entry, and a JSON null removes the field. The entry is read without its secrets resolved and written whole through
/// Modify, which validates it against the descriptor. Nothing is restarted: a Config Store edit takes effect when the
/// runner items that use the entry restart (AD-19).
/// It fails, and writes nothing, when:
///   - fields is not a dynamic object;
///   - an api_key field, at any depth, is not exactly one @{env:NAME} placeholder (NAME is letters, digits and underscores);
///   - an @{ appears in any other string of fields, a field name included;
///   - the entry does not exist.
/// The text of a refusal names the field and never holds a value.
ClassMethod Merge(entry As %String, fields As %DynamicObject) As %Status
{
	Try {
		If '$IsObject($Get(fields)) || 'fields.%IsA("%Library.DynamicObject") {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore.Merge: fields is not a dynamic object")
			Quit
		}
		Set refusal = ..Refusal(fields, "")
		If refusal '= "" {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore.Merge refuses the fields: "_refusal)
			Quit
		}
		Set fqn = ..FullName($Get(entry))
		Set sc = ..Details(entry, .details)
		If $SYSTEM.Status.IsError(sc) Quit
		Do ..MergeInto(details, fields)
		Set sc = ##class(%ConfigStore.Configuration).Modify(fqn, details)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Reads the entry (a name as in Merge) without its placeholders and secret references resolved: details is a dynamic object as it is
/// stored, so that an api_key written as @{env:NAME} is that text and never the value of the variable. An entry that someone else wrote
/// with a literal value returns that value as written, so a caller never logs, stores or returns details. It fails, with details
/// empty, when the entry does not exist (the error names the entry) or cannot be read. It never throws.
ClassMethod Details(entry As %String, Output details As %DynamicObject) As %Status
{
	Set details = ""
	Try {
		Set fqn = ..FullName($Get(entry))
		If '##class(%ConfigStore.Configuration).Exists(fqn) {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore: the Config Store entry "_fqn_" does not exist")
			Quit
		}
		Set sc = ##class(%ConfigStore.Configuration).GetDetails(fqn, .read, 0, 0)
		If $SYSTEM.Status.IsOK(sc) Set details = read
	} Catch exception {
		Set details = ""
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The fully qualified name of an entry: a name of fewer than three dotted parts is an AI.LLM entry.
ClassMethod FullName(entry As %String) As %String
{
	If $Length(entry, ".") < 3 Quit ..#AREA_"."_..#TYPE_"."_entry
	Quit entry
}

/// "" when every field of the object or array passes; otherwise the reason for the first one that is refused, naming its
/// path and holding no value. path is the path of node, "" for the top level.
ClassMethod Refusal(node As %DynamicAbstractObject, path As %String) As %String [ Private ]
{
	Set reason = ""
	Set isObject = node.%IsA("%Library.DynamicObject")
	Set iterator = node.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set here = $Select(path = "": key, 1: path_"."_key)
		Set type = node.%GetTypeOf(key)
		If isObject && (key [ "@{") {
			Set reason = "a field name under "_$Select(path = "": "the top level", 1: path)_" holds @{"
		} ElseIf isObject && (key = "api_key") {
			If (type '= "string") || '$Match(value, ..#KEYPATTERN) {
				Set reason = "api_key at "_here_" is not exactly one @{env:NAME} placeholder"
			}
		} ElseIf type = "string" {
			If value [ "@{" Set reason = "the string at "_here_" holds @{"
		} ElseIf (type = "object") || (type = "array") {
			Set reason = ..Refusal(value, here)
		}
		If reason '= "" Quit
	}
	Quit reason
}

/// Merges fields into target, in place: null removes a field, an object merges into the object that target holds at the
/// key (a new one when it holds none), and any other value replaces.
ClassMethod MergeInto(target As %DynamicObject, fields As %DynamicObject) [ Private ]
{
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set type = fields.%GetTypeOf(key)
		If type = "null" {
			Do target.%Remove(key)
		} ElseIf type = "object" {
			If target.%GetTypeOf(key) '= "object" Do target.%Set(key, {})
			Do ..MergeInto(target.%Get(key), value)
		} ElseIf type = "array" {
			Do target.%Set(key, value)
		} Else {
			Do target.%Set(key, value, type)
		}
	}
}

}
