Include Ensemble

/// The governance gate (AD-6, AD-9, AD-10, AD-31): the authorization policy that the adapter adds to every agent it builds
/// (OcuTalon.Bridge.Adapter.Agent). AI Hub calls %CanExecute for every tool call before the tool runs, whether or not the tool requires
/// authorization, and a denial is a ToolAccessDenied status that AI Hub records through the audit policy's %LogDenial (a denied step) and
/// puts, after its own "Tool access denied: " prefix, in the tool result that the model reads.
/// The decision, in this order (Check):
///   1. The call: a missing context, a call that is not an object or has no name, an error status from any step and any exception deny the
///      call with FAILED, and Check logs one redacted warning that names the tool and its source. Nothing leaves %CanExecute.
///   2. The classification by (source, name) (ClassificationOf), which only the exact values safe and risky give, with the flags READONLY and
///      TRUSTEDOUTPUT carried for Story 3.3:
///        - a toolref that starts mcp: is an MCP call. Its source is the toolref, and only the ClassificationClass extension classifies it:
///          no class parameter and no ToolClassification entry is read for it, so an MCP tool never takes a built-in's classification;
///        - any other call has the source metadata.origin_class. The code of that class decides first: its [ Internal ] class method
///          Classify<NAME>(arguments), else Classify(arguments), else its parameter CLASSIFICATION<NAME>, else CLASSIFICATION, where NAME is
///          the tool's name in upper case with _ and - removed (StepBuffer.ToolParameter). What code declares is final, so a setting or an
///          extension never changes it, and a declared value other than safe or risky leaves the tool unclassified. Then the entry of Decide's
///          ToolClassification setting for exactly that class and tool; then the ClassificationClass extension;
///        - anything else is unclassified, which counts as risky.
///      Nothing in the call, its metadata, its arguments (except as the input of a code Classify method) or the context classifies it.
///   3. The permissions: for each resource:permission pair of the tool's RESOURCES parameter (Resources, the one bridge parser), one
///      $SYSTEM.Security.CheckUserPermission call per permission letter for the ServiceUser setting of Decide. The first missing pair denies
///      the call with NOPRIVILEGE. A tool that declares no resources needs no check.
///   4. The result: a safe call is allowed, and every other call is denied with NEEDSAPPROVAL (Story 3.6 raises an approval request here).
/// An allowed call fires turn.step through Decide.FireEvent to the HostSinkClass setting of Decide, owned by the session of the context, with
/// the payload HostSink.TurnStepPayload(DecisionRef, label) and the tool's step label. A denied call fires nothing. A sink that fails is logged
/// and never changes the decision. The gate never modifies the call and takes no lock.
/// The class has no instance property (AI Hub infers a policy's statefulness from its properties), makes no call into AI Hub beyond its base
/// class and runs no Python: it runs inside a callback (AD-6). Only the Class line names the AI Hub package.
Class OcuTalon.Bridge.Policy.Gate Extends %AI.Policy.Authorization
{

/// The status code of a denial: the code of AI Hub's ToolAccessDenied, so that AI Hub reports the denial as a denial.
Parameter DENIEDCODE = "<%AICore>ToolAccessDenied";

/// The sentences of the denials, which the model reads after AI Hub's "Tool access denied: ". They hold no argument and no model text, and
/// only NOPRIVILEGE names anything of the system: the resource and the permission letter that the service user lacks.
Parameter NEEDSAPPROVAL = "this tool is risky or not classified, so it needs an approval, and nothing was run.";

/// {privilege} is the resource and the permission letter that the service user lacks, such as %DB_IRISLIB:W.
Parameter NOPRIVILEGE = "the service user lacks the privilege {privilege} that this tool needs, so nothing was run.";

Parameter FAILED = "the check of this tool call failed, so nothing was run.";

/// The classifications that classify a tool.
Parameter SAFE = "safe";

Parameter RISKY = "risky";

/// The prefix of the toolref of an MCP call.
Parameter MCPPREFIX = "mcp:";

/// The longest name, source or error text in a warning, in characters.
Parameter MAXWARNING = 300;

/// The keys of an entry of the ToolClassification setting.
Parameter ENTRYKEYS = "class,tool,classification,readOnly,trustedOutput";

/// Decides one tool call. Any exception is caught in Check, and the denial is FAILED.
Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
	Set sc = ""
	Try {
		Set sc = ..Check(toolref, call, metadata)
	} Catch {
		Set sc = $SYSTEM.Status.Error(..#DENIEDCODE, ..#FAILED)
	}
	Quit sc
}

/// The decision for one call: OK to allow it, or a ToolAccessDenied status (Denial) to deny it. It catches every exception. An empty
/// sinkClass means the HostSinkClass setting of Decide.
ClassMethod Check(toolref As %String, call As %DynamicObject, metadata As %DynamicObject, sinkClass As %String = "") As %Status
{
	Set name = ""
	Set source = ""
	Set sc = ""
	Try {
		Set name = ..NameOf(call)
		Set source = ..Source(toolref, metadata)
		Set sc = ..Decision(name, source, call, sinkClass)
	} Catch exception {
		Set sc = ..Denial(..#FAILED)
		Do ..Warn(name, source, exception.DisplayString())
	}
	Quit sc
}

/// The decision of Check, which throws for any failure.
ClassMethod Decision(name As %String, source As %String, call As %DynamicObject, sinkClass As %String) As %Status [ Private ]
{
	If '##class(OcuTalon.Bridge.Context).Active() $$$ThrowStatus($SYSTEM.Status.Error(5001, "There is no context for the call"))
	If name = "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The call is not an object with a name"))
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	Set classification = ..ClassificationOf(source, name, ..ArgumentsOf(call))
	Set missing = ..MissingPrivilege(source, name)
	If missing '= "" Quit ..Denial($Replace(..#NOPRIVILEGE, "{privilege}", missing))
	If classification.classification '= ..#SAFE Quit ..Denial(..#NEEDSAPPROVAL)
	Do ..ReportStep(context, source, name, sinkClass)
	Quit $$$OK
}

/// The source of the call: its toolref when that starts mcp:, else metadata.origin_class, else "".
ClassMethod Source(toolref As %String, metadata As %DynamicObject) As %String
{
	If ..IsMcp(toolref) Quit toolref
	If ..IsObject(metadata) && (metadata.%GetTypeOf("origin_class") = "string") Quit metadata."origin_class"
	Quit ""
}

/// The classification of the tool name of the source: {"classification","readOnly","trustedOutput","by"}, where classification is safe, risky or
/// "" (unclassified), the flags are 1 or 0, and by is code, setting, extension or "". arguments is the call's arguments, an object or a JSON
/// string, and is read only as the input of a code Classify method; "" means none. It throws for a malformed ToolClassification setting, a
/// ClassificationClass that is not usable, arguments that are not JSON and an exception of a code Classify method.
ClassMethod ClassificationOf(source As %String, name As %String, arguments As %RegisteredObject = "") As %DynamicObject
{
	If (source = "") || (name = "") Quit ..Unclassified()
	If ..IsMcp(source) Quit ..FromExtension(source, name)

	Set hook = ..HookFor(source, name)
	If hook '= "" {
		Set declared = $ClassMethod(source, hook, ..ArgumentsObject(arguments))
	} Else {
		Set declared = ##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(source, name, "CLASSIFICATION")
	}
	If (hook '= "") || (declared '= "") {
		If '..Valid(declared) Quit ..Unclassified()
		Quit ..Classified(declared, ..Flag(source, name, "READONLY"), ..Flag(source, name, "TRUSTEDOUTPUT"), "code")
	}

	Set entry = ..EntryFor(source, name)
	If $IsObject(entry) Quit ..Classified(entry.classification, entry.%Get("readOnly") = 1, entry.%Get("trustedOutput") = 1, "setting")
	Quit ..FromExtension(source, name)
}

/// The pairs of a RESOURCES value as a dynamic array of {"resource","permission"}: resource:permission[,resource:permission...], where the
/// permission is one or more of R, W and U. An empty value gives []. A pair without a colon, with an empty or spaced resource, or with a
/// permission that is empty or holds another character throws a status that names where (the class and the tool, or the caller's own words).
ClassMethod Resources(value As %String, where As %String) As %DynamicArray
{
	Set pairs = []
	If value = "" Quit pairs
	For i = 1:1:$Length(value, ",") {
		Set pair = $Piece(value, ",", i)
		Set resource = $Piece(pair, ":", 1)
		Set permission = $Piece(pair, ":", 2)
		If ($Length(pair, ":") '= 2) || (resource = "") || ($ZStrip(resource, "*W") '= resource) {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, where_" RESOURCES: '"_pair_"' in '"_value_"' is not resource:permission with a resource name"))
		}
		If (permission = "") || ($Translate(permission, "RWU") '= "") {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, where_" RESOURCES: the permission of '"_pair_"' in '"_value_"' is not made of R, W and U"))
		}
		Do pairs.%Push({"resource": (resource), "permission": (permission)})
	}
	Quit pairs
}

/// The denial with the sentence: a ToolAccessDenied status that AI Hub shows the model after "Tool access denied: ", and that the audit policy
/// records as a denied step.
ClassMethod Denial(sentence As %String) As %Status
{
	Quit $SYSTEM.Status.Error(..#DENIEDCODE, sentence)
}

/// The first resource:letter pair of the tool's RESOURCES that the ServiceUser setting of Decide does not hold, one permission letter per
/// CheckUserPermission call, or "" when it holds them all or the tool declares none. An MCP source declares none here.
ClassMethod MissingPrivilege(source As %String, name As %String) As %String [ Private ]
{
	If ..IsMcp(source) Quit ""
	Set value = ##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(source, name, "RESOURCES")
	If value = "" Quit ""
	Set pairs = ..Resources(value, source_" "_name)
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Set missing = ""
	Set iterator = pairs.%GetIterator()
	While iterator.%GetNext(, .pair) && (missing = "") {
		For i = 1:1:$Length(pair.permission) {
			Set letter = $Extract(pair.permission, i)
			If '$SYSTEM.Security.CheckUserPermission(user, pair.resource, letter) {
				Set missing = pair.resource_":"_letter
				Quit
			}
		}
	}
	Quit missing
}

/// Reports turn.step for an allowed call to the sink, owned by the session of the context. The sink class is the argument, or the
/// HostSinkClass setting of Decide. A sink that fails is logged by FireEvent and changes nothing.
ClassMethod ReportStep(context As OcuTalon.Bridge.Context, source As %String, name As %String, sinkClass As %String) [ Private ]
{
	Set label = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(source, name), ##class(OcuTalon.Bridge.Adapter.StepBuffer).#MAXLABEL)
	If sinkClass = "" {
		Set sinkClass = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("HostSinkClass", , , .sc)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
	}
	Do ##class(OcuTalon.Bridge.Process.Decide).FireEvent(sinkClass, context.OwnerRef, context.DecisionRef, ##class(OcuTalon.Bridge.Ext.HostSink).#TURNSTEP, ##class(OcuTalon.Bridge.Ext.HostSink).TurnStepPayload(context.DecisionRef, label))
}

/// The classification that the ClassificationClass extension gives for the source and name (the gate gives it no arguments), or the
/// unclassified result. It throws when the setting names a class that is not usable.
ClassMethod FromExtension(source As %String, name As %String) As %DynamicObject [ Private ]
{
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ClassificationClass", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Set value = $ClassMethod(class, "Classify", source, name)
	If '..Valid(value) Quit ..Unclassified()
	Quit ..Classified(value, 0, 0, "extension")
}

/// The entry of the ToolClassification setting of Decide for exactly the class and the tool, or "". It throws unless the whole setting is
/// well formed: empty (none), or a JSON array of objects with the keys class and tool (not empty), classification (exactly safe or risky) and
/// optionally readOnly and trustedOutput (1 or 0, or a boolean), no other key, and no two entries for one class and tool.
ClassMethod EntryFor(source As %String, name As %String) As %DynamicObject [ Private ]
{
	Set value = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ToolClassification", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If $ZStrip(value, "*WC") = "" Quit ""
	Set found = ""
	Try {
		Set entries = {}.%FromJSON(value)
	} Catch {
		$$$ThrowStatus($SYSTEM.Status.Error(5001, "The setting ToolClassification is not JSON"))
	}
	If '$IsObject(entries) || ($ClassName(entries) '= "%Library.DynamicArray") $$$ThrowStatus($SYSTEM.Status.Error(5001, "The setting ToolClassification is not a JSON array"))
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(.position, .entry) {
		Set at = "The setting ToolClassification, entry "_(position + 1)_", "
		If '..IsObject(entry) $$$ThrowStatus($SYSTEM.Status.Error(5001, at_"is not an object"))
		Set keys = entry.%GetIterator()
		While keys.%GetNext(.key) {
			If '$ListFind($ListFromString(..#ENTRYKEYS), key) $$$ThrowStatus($SYSTEM.Status.Error(5001, at_"has the unknown key "_..Part(key, 40)))
		}
		For key = "class", "tool" {
			If (entry.%GetTypeOf(key) '= "string") || (entry.%Get(key) = "") $$$ThrowStatus($SYSTEM.Status.Error(5001, at_"has no "_key))
		}
		If '..Valid(entry.%Get("classification")) || (entry.%GetTypeOf("classification") '= "string") $$$ThrowStatus($SYSTEM.Status.Error(5001, at_"does not say safe or risky"))
		For key = "readOnly", "trustedOutput" {
			If entry.%IsDefined(key) {
				Set type = entry.%GetTypeOf(key)
				If '(((type = "number") && ((entry.%Get(key) = 0) || (entry.%Get(key) = 1))) || (type = "boolean")) $$$ThrowStatus($SYSTEM.Status.Error(5001, at_"has a "_key_" that is not 1 or 0"))
			}
		}
		Set pair = entry.%Get("class")_$Char(1)_entry.%Get("tool")
		If $Data(seen(pair)) $$$ThrowStatus($SYSTEM.Status.Error(5001, at_"repeats a class and tool"))
		Set seen(pair) = ""
		If (entry.%Get("class") = source) && (entry.%Get("tool") = name) Set found = entry
	}
	Quit found
}

/// The name of the class method that classifies the tool in code: Classify<NAME>, else Classify, where NAME is the tool's name in upper case
/// with _ and - removed; "" when the class has neither as a class method. The governance test asks it which tools classify by their arguments.
ClassMethod HookFor(source As %String, name As %String) As %String
{
	Set hook = ""
	Try {
		Set own = "Classify"_$ZConvert($Translate(name, "_-"), "U")
		If $$$comMemberKeyGet(source, $$$cCLASSmethod, own, $$$cMETHclassmethod) = 1 {
			Set hook = own
		} ElseIf $$$comMemberKeyGet(source, $$$cCLASSmethod, "Classify", $$$cMETHclassmethod) = 1 {
			Set hook = "Classify"
		}
	} Catch {
		Set hook = ""
	}
	Quit hook
}

/// 1 when the class parameter READONLY or TRUSTEDOUTPUT of the tool (base) is exactly 1, else 0.
ClassMethod Flag(source As %String, name As %String, base As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(source, name, base) = 1
}

/// The arguments of the call as the gate keeps them for a code Classify method: the call's arguments member (an object or a JSON string), or ""
/// when the call has none.
ClassMethod ArgumentsOf(call As %DynamicObject) As %RegisteredObject [ Private ]
{
	Set arguments = ""
	If ..IsObject(call) {
		Set type = call.%GetTypeOf("arguments")
		If type = "object" {
			Set arguments = call.arguments
		} ElseIf type = "string" {
			Set arguments = call.arguments
		}
	}
	Quit arguments
}

/// The arguments as an object for a code Classify method: an object as it is, a JSON string parsed, and an empty object for none (""). It
/// throws for text that is not a JSON object.
ClassMethod ArgumentsObject(arguments As %RegisteredObject) As %DynamicObject [ Private ]
{
	If $IsObject(arguments) Quit arguments
	If $ZStrip(arguments, "*WC") = "" Quit {}
	Try {
		Set object = {}.%FromJSON(arguments)
	} Catch {
		$$$ThrowStatus($SYSTEM.Status.Error(5001, "The arguments of the call are not JSON"))
	}
	If '..IsObject(object) $$$ThrowStatus($SYSTEM.Status.Error(5001, "The arguments of the call are not a JSON object"))
	Quit object
}

/// The name of the call, or "" when the call is not an object or has no name that is a string.
ClassMethod NameOf(call As %DynamicObject) As %String [ Private ]
{
	If ..IsObject(call) && (call.%GetTypeOf("name") = "string") Quit call.name
	Quit ""
}

/// 1 when the value is a dynamic object.
ClassMethod IsObject(value As %RegisteredObject) As %Boolean [ Private ]
{
	Quit $IsObject(value) && ($ClassName(value) = "%Library.DynamicObject")
}

/// 1 when the toolref or the source starts mcp: (in any case).
ClassMethod IsMcp(toolref As %String) As %Boolean [ Private ]
{
	Quit $ZConvert($Extract(toolref, 1, $Length(..#MCPPREFIX)), "L") = ..#MCPPREFIX
}

/// 1 when the value is exactly safe or exactly risky.
ClassMethod Valid(value As %String) As %Boolean [ Private ]
{
	Quit '$IsObject(value) && ((value = ..#SAFE) || (value = ..#RISKY))
}

ClassMethod Classified(classification As %String, readOnly As %Boolean, trustedOutput As %Boolean, by As %String) As %DynamicObject [ Private ]
{
	Quit {"classification": (classification), "readOnly": (+readOnly), "trustedOutput": (+trustedOutput), "by": (by)}
}

ClassMethod Unclassified() As %DynamicObject [ Private ]
{
	Quit ..Classified("", 0, 0, "")
}

/// Logs one warning that names the tool and its source, with the text of the failure, all redacted and cut. It never throws.
ClassMethod Warn(name As %String, source As %String, text As %String) [ Private ]
{
	Try {
		$$$LOGWARNING("The gate denied the call of the tool "_..Part(name, 64)_" from "_..Part(source, 128)_" because its check failed, and nothing was run: "_..Part(text, ..#MAXWARNING))
	} Catch {
	}
}

/// The text redacted and cut (StepBuffer.Part).
ClassMethod Part(text As %String, max As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(text, max)
}

}
