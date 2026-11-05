/// The Config Store API (AD-19). Merge changes some fields of an AI Hub LLM entry and leaves the others as they are; it is
/// the run-time writer of changes to those entries: Timeouts.Apply and the model-change API (Settings.SetModel) call it, and Restore puts back
/// what Details read when SetModel undoes its own write. Details reads an entry
/// with its placeholders unresolved, for Merge and for OcuTalon.Bridge.Keys, and EntryOf reads the entry name out of a runner's
/// @{config:<name>} reference, for Keys and for Timeouts. The bridge names no other OcuTalon package here (AD-2).
/// What Merge accepts (AD-19, AD-7): exactly two shapes of fields, and nothing else, so that no field a caller passes pairs a key placeholder with
/// an endpoint, a header or a secret reference (the entry's other fields stay as they are).
///   - The timeouts shape: only http_config.request_timeout_secs (a number) and http_config.retry (an object of numbers).
///   - The model-change shape: model_provider, a provider of the table (Providers); api_key, exactly @{env:<that provider's key variable>};
///     and optionally model, a selectable model of that provider. The model is checked and never written, because an entry never holds a
///     model (AD-7): the runner's Model setting carries it.
///   - An empty object merges nothing and is accepted.
/// Any other field, any other value, any @{ form and any mixture of the two shapes is refused, with a reason that names the field and never
/// holds a value, and nothing is written.
Class OcuTalon.Bridge.ConfigStore
{

/// The area of the entries.
Parameter AREA = "AI";

/// The type of the entries.
Parameter TYPE = "LLM";

/// The only form of an api_key value: one environment placeholder (an ICU pattern, anchored at both ends).
Parameter KEYPATTERN = "^@\{env:[A-Za-z0-9_]+\}\z";

/// The only form of a reference to an entry: @{config:<name>}, where the name holds no braces (an ICU pattern, anchored at both ends).
Parameter REFERENCEPATTERN = "^@\{config:[^{}]+\}\z";

/// Merges fields into the entry and leaves the entry's other fields as they are. entry is the fully qualified name of the
/// entry (AI.LLM.OcuTalonTriage), or a name of fewer than three dotted parts, which names the entry AI.LLM.<name>.
/// The merge is deep: an object in fields merges into the object of the entry, and any other value replaces the value of the
/// entry. The entry is read without its secrets resolved and written whole through Modify, which validates it against the descriptor.
/// Nothing is restarted: a Config Store edit takes effect when the runner items that use the entry restart (AD-19).
/// It fails, and writes nothing, when:
///   - fields is not a dynamic object;
///   - fields is not the timeouts shape or the model-change shape (Shape);
///   - the entry does not exist (an empty object merges nothing and is accepted before the entry is read).
/// The text of a refusal names the field and never holds a value. The signature is (entry, fields) and stays so.
ClassMethod Merge(entry As %String, fields As %DynamicObject) As %Status
{
	Try {
		If '$IsObject($Get(fields)) || 'fields.%IsA("%Library.DynamicObject") {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore.Merge: fields is not a dynamic object")
			Quit
		}
		Set refusal = ..Shape(fields)
		If refusal '= "" {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore.Merge refuses the fields: "_refusal)
			Quit
		}
		If fields.%Size() = 0 {
			Set sc = $$$OK
			Quit
		}
		Set fqn = ..FullName($Get(entry))
		Set sc = ..Details(entry, .details)
		If $SYSTEM.Status.IsError(sc) Quit
		Set merged = {}.%FromJSON(fields.%ToJSON())
		If merged.%IsDefined("model") Do merged.%Remove("model")
		Do ..MergeInto(details, merged)
		Set sc = ##class(%ConfigStore.Configuration).Modify(fqn, details)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Puts back the details of an entry that Details read: the entry is written whole through Modify, which validates it against the
/// descriptor. It is for the caller that undoes its own Merge (Settings.SetModel), which passes the dynamic object that Details gave for the
/// entry; the object is written as it is and is not judged against the two shapes of Merge. It fails when details is not a dynamic object or
/// the entry does not exist. Nothing is restarted.
ClassMethod Restore(entry As %String, details As %DynamicObject) As %Status
{
	Try {
		If '$IsObject($Get(details)) || 'details.%IsA("%Library.DynamicObject") {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore.Restore: details is not a dynamic object")
			Quit
		}
		Set fqn = ..FullName($Get(entry))
		If '##class(%ConfigStore.Configuration).Exists(fqn) {
			Set sc = $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore: the Config Store entry "_fqn_" does not exist")
			Quit
		}
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

/// The entry name of a provider configuration that is exactly one @{config:<name>} reference (surrounding white space and control
/// characters are ignored), otherwise "". The name is as written, so it is a name that Details and FullName take.
ClassMethod EntryOf(providerConfig As %String) As %String
{
	Set text = $ZStrip($Get(providerConfig), "<>WC")
	If '$Match(text, ..#REFERENCEPATTERN) Quit ""
	Quit $Piece($Piece(text, "@{config:", 2), "}", 1)
}

/// The fully qualified name of an entry: a name of fewer than three dotted parts is an AI.LLM entry.
ClassMethod FullName(entry As %String) As %String
{
	If $Length(entry, ".") < 3 Quit ..#AREA_"."_..#TYPE_"."_entry
	Quit entry
}

/// "" when the fields are the timeouts shape, the model-change shape or empty; otherwise the reason for the first thing that is refused,
/// naming a field and holding no value. It is pure but for the provider table.
ClassMethod Shape(fields As %DynamicObject) As %String
{
	If fields.%Size() = 0 Quit ""
	Set model = (fields.%IsDefined("model_provider") || fields.%IsDefined("api_key") || fields.%IsDefined("model"))
	Set allowed = $Select(model: $ListBuild("model_provider", "api_key", "model"), 1: $ListBuild("http_config"))
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.key) {
		If '$ListFind(allowed, key) {
			Return "the field "_..FieldName(key)_" is not one that a merge accepts: only "_$Select(model: "model_provider, api_key and model", 1: "http_config.request_timeout_secs and http_config.retry")_" can be merged"
		}
	}
	Quit $Select(model: ..ModelShape(fields), 1: ..TimeoutsShape(fields))
}

/// "" when the object is exactly the timeouts shape (an http_config of request_timeout_secs, a number, and retry, an object of numbers),
/// otherwise the reason, naming the field.
ClassMethod TimeoutsShape(fields As %DynamicObject) As %String [ Private ]
{
	If fields.%GetTypeOf("http_config") '= "object" Quit "http_config is not an object"
	Set block = fields.%Get("http_config")
	Set iterator = block.%GetIterator()
	While iterator.%GetNext(.key) {
		If (key '= "request_timeout_secs") && (key '= "retry") {
			Return "the field http_config."_..FieldName(key)_" is not one that a merge accepts: only http_config.request_timeout_secs and http_config.retry can be merged"
		}
	}
	If block.%IsDefined("request_timeout_secs") && (block.%GetTypeOf("request_timeout_secs") '= "number") Quit "http_config.request_timeout_secs is not a number"
	If block.%IsDefined("retry") {
		If block.%GetTypeOf("retry") '= "object" Quit "http_config.retry is not an object"
		Set retry = block.%Get("retry")
		Set iterator = retry.%GetIterator()
		While iterator.%GetNext(.key) {
			If retry.%GetTypeOf(key) '= "number" Return "http_config.retry."_..FieldName(key)_" is not a number"
		}
	}
	Quit ""
}

/// "" when the object is exactly the model-change shape (model_provider, api_key and optionally model, for a provider of the table),
/// otherwise the reason, naming the field.
ClassMethod ModelShape(fields As %DynamicObject) As %String [ Private ]
{
	If 'fields.%IsDefined("model_provider") Quit "api_key and model need a model_provider"
	If fields.%GetTypeOf("model_provider") '= "string" Quit "model_provider is not a string"
	Set row = ##class(OcuTalon.Bridge.Providers).Row(fields.%Get("model_provider"))
	If '$IsObject(row) Quit "model_provider is not a provider of the provider table"
	If 'fields.%IsDefined("api_key") Quit "model_provider needs an api_key"
	If (fields.%GetTypeOf("api_key") '= "string") || (fields.%Get("api_key") '= ("@{env:"_row.%Get("keyVariable")_"}")) {
		Quit "api_key is not exactly the key placeholder of the provider "_row.%Get("provider")
	}
	If fields.%IsDefined("model") {
		Set models = row.%Get("models")
		Set listed = 0
		If fields.%GetTypeOf("model") = "string" {
			Set iterator = models.%GetIterator()
			While iterator.%GetNext(, .name) {
				If name = fields.%Get("model") Set listed = 1
			}
		}
		If 'listed Quit "model is not a model that the provider "_row.%Get("provider")_" lists"
	}
	Quit ""
}

/// The name of a field for a refusal: the name when it is a plain one (letters, digits, underscores and dots, at most 64 characters), so that
/// a reason never echoes a value that was put in a field name; otherwise a description.
ClassMethod FieldName(name As %String) As %String [ Private ]
{
	If $Match($Get(name), "^[A-Za-z0-9_.]{1,64}\z") Quit $Get(name)
	Quit "whose name is not a plain name"
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
