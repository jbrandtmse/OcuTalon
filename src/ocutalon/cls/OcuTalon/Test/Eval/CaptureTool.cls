/// The capture of the fallback replies of an eval run (DW-1421; AD-8, AD-22). Run reads, on the stack that the run used and before it is torn down, the raw reply of every
/// reply that a fallback decision of kind decide or diagnose got, from the Ens message store, and checks each one again with Decide.Recheck, the reply check that Decide
/// makes, to say which rule of the reply class refused it. It writes one file per reply into a folder, and summary.json (when there is a decision). The files hold the raw text: nothing else does.
///   - The replies of a decision. The request headers whose body is an OcuTalon.Bridge.Msg.Request that carries the decision's Ref (the request that Decide sent to a runner,
///     a re-send to the same runner, and the one it sent to the retry runner), in header order, are the attempts 1, 2, ...; the reply of an attempt is the OcuTalon.Bridge.Msg.Reply
///     body of the response header whose CorrespondingMessageId is that request header. The runner is the TargetConfigName of the request header, and its reply class is Decide.ReplyClassOf.
///     Each reply of a decision whose reason is invalid is checked again, whatever ended its own attempt; its file keeps the attempt's finishReason, which tells a cut-off one apart.
///   - The rule and the field of a reply. The problem of Recheck says the stage (the check, the check after the filter, or no reason left after the filter) and the parts
///     that the check refused, in words that quote nothing of the reply (Decide RefusalText). The rule is the first part: the tag of "ERROR #<code> rule <tag>", else the part as it is.
///     The field is the tag's field in REFUSALRULES of the reply class, else the JSON field name of a compiled property that the part names, else empty. The fixed rule names are
///     "no reply" (a decision with no reply in the store), "no reply text" (a reply with no text, a failure reply), "passes the check" (a reply that passes now, or a fallback whose reason is not invalid)
///     and "no reason left after the filter".
///   - Lines gives the CHK lines for the run's log, and Print writes them: counts, rule names, fields and the names of the files, never a text of a reply.
/// It records nothing and sends nothing: no row, no event, no message and no model call. THIS CLASS RUNS IN THROWAWAY STACKS AND IN EVAL RUNS ONLY, through eval/capture-fallbacks.sh;
/// the product never calls it. Lane A.
Class OcuTalon.Test.Eval.CaptureTool Extends %RegisteredObject
{

/// The rule of a decision with no reply in the store.
Parameter NOREPLY = "no reply";

/// The rule of a reply with no text.
Parameter NOTEXT = "no reply text";

/// The rule of a reply that passes the check now, or of a fallback that is not invalid.
Parameter PASSES = "passes the check";

/// The rule of a reply whose reasons are all blank after the filter.
Parameter NOREASON = "no reason left after the filter";

/// The rule of a reply that Recheck could not judge.
Parameter NOCHECK = "no check";

/// Writes the files of the fallback decisions of kind decide and diagnose (only the Refs in the comma-separated refs, when given) into the folder, and gives the summary: the
/// counts of the decisions, replies and files, the decisions by reason, the replies by rule and field, and by case and rule. The folder is made when it is missing; the files of
/// an earlier capture in it (this class's own file names) are deleted first. An empty folder is an error, never the process's own directory.
ClassMethod Run(folder As %String, refs As %String = "", Output summary As %DynamicObject) As %Status
{
	Set summary = {"decisions": 0, "decide": 0, "diagnose": 0, "replies": 0, "files": 0, "noReply": 0, "reasons": {}, "rules": [], "cases": [], "names": []}
	Try {
		If $ZStrip(folder, "<>W") = "" {
			Set sc = $$$ERROR($$$GeneralError, "The capture folder is empty")
			Quit
		}
		Set folder = ##class(%File).NormalizeDirectory(folder)
		If '##class(%File).DirectoryExists(folder) && '##class(%File).CreateDirectoryChain(folder) {
			Set sc = $$$ERROR($$$GeneralError, "The capture folder cannot be made")
			Quit
		}
		Do ..Clear(folder)
		Set wanted = $ListFromString(refs, ",")
		Kill rules, cases
		Set number = 0
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Kind, FallbackReason FROM OcuTalon_Bridge_Data.Decision WHERE Fallback = 1 AND Kind IN ('decide', 'diagnose') ORDER BY ID")
		While rows.%Next() {
			Set ref = rows.%Get("Ref")
			If (refs '= "") && '$ListFind(wanted, ref) Continue
			Set kind = rows.%Get("Kind")
			Set reason = rows.%Get("FallbackReason")
			Do summary.%Set("decisions", summary.decisions + 1)
			Do summary.%Set(kind, summary.%Get(kind) + 1)
			Set count = +summary.reasons.%Get(reason)
			Do summary.reasons.%Set(reason, count + 1)
			Set case = ..CaseOf(ref, .runRef)
			Set replies = ..Attempts(ref)
			Set answered = 0
			Set position = 0
			While $ListNext(replies, position, one) {
				If $List(one, 2) '= "" Set answered = answered + 1
			}
			If 'answered {
				Do summary.%Set("noReply", summary.noReply + 1)
				Do ..Count(.rules, .cases, ..#NOREPLY, "", case)
				Continue
			}
			Set position = 0
			Set attempt = 0
			While $ListNext(replies, position, one) {
				Set attempt = attempt + 1
				If $List(one, 2) = "" Continue
				Set number = number + 1
				Do summary.%Set("replies", summary.replies + 1)
				Set file = ..Reply(folder, number, ref, kind, reason, case, runRef, attempt, $List(one, 1), $List(one, 2), .rule, .field)
				Do ..Count(.rules, .cases, rule, field, case)
				If file '= "" {
					Do summary.names.%Push(file)
					Do summary.%Set("files", summary.files + 1)
				}
			}
		}
		Do ..Tally(summary, .rules, .cases)
		Set sc = $$$OK
		If summary.decisions {
			Do summary.names.%Push("summary.json")
			Do summary.%Set("files", summary.files + 1)
			Set sc = ..Put(folder_"summary.json", summary)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit $Get(sc, $$$OK)
}

/// The CHK lines of the summary, one per line:
///   CHK|decisions|<n>|<decide>|<diagnose>|<replies>|<files>, CHK|reason|<reason>|<n>, CHK|rule|<rule>|<field or ->|<n>, CHK|case|<case>|<rule>|<n> and CHK|file|<name>.
/// A value holds no bar and no line end. Nothing of a reply's text is in a line.
ClassMethod Lines(summary As %DynamicObject) As %String
{
	Set lines = "CHK|decisions|"_summary.decisions_"|"_summary.decide_"|"_summary.diagnose_"|"_summary.replies_"|"_summary.files
	Set iterator = summary.reasons.%GetIterator()
	While iterator.%GetNext(.reason, .count) {
		Set lines = lines_$Char(10)_"CHK|reason|"_..Plain(reason)_"|"_count
	}
	Set iterator = summary.rules.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set lines = lines_$Char(10)_"CHK|rule|"_..Plain(entry.rule)_"|"_$Select(entry.field = "": "-", 1: ..Plain(entry.field))_"|"_entry.count
	}
	Set iterator = summary.cases.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set lines = lines_$Char(10)_"CHK|case|"_..Plain(entry.case)_"|"_..Plain(entry.rule)_"|"_entry.count
	}
	Set iterator = summary.names.%GetIterator()
	While iterator.%GetNext(, .name) {
		Set lines = lines_$Char(10)_"CHK|file|"_..Plain(name)
	}
	Quit lines
}

/// Writes the lines of the summary, each after a line end.
ClassMethod Print(summary As %DynamicObject)
{
	Set lines = ..Lines(summary)
	For i = 1:1:$Length(lines, $Char(10)) Write !, $Piece(lines, $Char(10), i)
}

/// The value without a bar or a control character, which would break a CHK line.
ClassMethod Plain(value As %String) As %String [ Private ]
{
	Quit $Translate(value, "|"_$Char(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 127), "/")
}

/// Deletes the files of an earlier capture in the folder: this class's own names only.
ClassMethod Clear(folder As %String) [ Private ]
{
	Set files = ##class(%ResultSet).%New("%File:FileSet")
	Do files.Execute(folder, "*.json")
	While files.Next() {
		Set path = files.Get("Name")
		Set name = ##class(%File).GetFilename(path)
		If $Match(name, "[0-9]+-[A-Za-z0-9_-]+-[0-9]+\.json") || (name = "summary.json") Do ##class(%File).Delete(path)
	}
}

/// The case of the decision (CaseResult by DecisionRef), and in runRef the run's Ref; both "" when no case row names the decision.
ClassMethod CaseOf(ref As %String, Output runRef As %String) As %String [ Private ]
{
	Set runRef = ""
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseName, RunRef FROM OcuTalon_Eval_Data.CaseResult WHERE DecisionRef = ? ORDER BY ID", ref)
	If '$IsObject(rows) || 'rows.%Next() Quit ""
	Set runRef = rows.%Get("RunRef")
	Quit rows.%Get("CaseName")
}

/// The attempts of the decision, in header order, as a list of $ListBuild(request id, reply id): the reply id is "" for a request that has no reply in the store.
/// Empty when no request that carries the Ref reached a runner. The request headers are those whose body is a Request with the DecisionRef, and the reply of each is the
/// body of the response header that answers it.
ClassMethod Attempts(ref As %String) As %List [ Private ]
{
	Set list = ""
	Set requests = ##class(%SQL.Statement).%ExecDirect(, "SELECT h.ID AS HeaderId, h.MessageBodyId AS RequestId FROM Ens.MessageHeader h JOIN OcuTalon_Bridge_Msg.Request rq ON rq.ID = h.MessageBodyId WHERE h.MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' AND rq.DecisionRef = ? ORDER BY h.ID", ref)
	While requests.%Next() {
		Set replyId = ""
		Set answers = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE CorrespondingMessageId = ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.Reply' ORDER BY ID", requests.%Get("HeaderId"))
		If answers.%Next() Set replyId = answers.%Get("MessageBodyId")
		Set list = list _ $ListBuild($ListBuild(requests.%Get("RequestId"), replyId))
	}
	Quit list
}

/// Writes the file of one attempt and gives the rule and the field of the reply in rule and field; returns the file's name, or "" when the attempt has no reply to write.
ClassMethod Reply(folder As %String, number As %Integer, ref As %String, kind As %String, reason As %String, case As %String, runRef As %String, attempt As %Integer, requestId As %String, replyId As %String, Output rule As %String, Output field As %String) As %String [ Private ]
{
	Set rule = ..#NOREPLY
	Set field = ""
	Set reply = $Select(replyId = "": "", 1: ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(replyId))
	If '$IsObject(reply) Quit ""
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(requestId)
	Set runner = ..RunnerOf(requestId)
	Set replyClass = $Select(runner = "": "", 1: ##class(OcuTalon.Bridge.Process.Decide).ReplyClassOf(runner))
	Set filterClass = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ReplyFilterClass", "", "Decide", .filterStatus)
	Set text = reply.Text
	Set stage = ""
	Set problem = ""
	Set rules = []
	If $ZStrip(text, "*WC") = "" {
		Set rule = ..#NOTEXT
	} ElseIf reason '= "invalid" {
		Set rule = ..#PASSES
	} ElseIf '$IsObject(request) || (replyClass = "") || (filterClass = "") {
		Set rule = ..#NOCHECK
	} Else {
		Try {
			Set valid = ##class(OcuTalon.Bridge.Process.Decide).Recheck(request, text, replyClass, filterClass, .problem)
			If valid {
				Set rule = ..#PASSES
			} Else {
				Do ..Parse(problem, replyClass, .stage, .rule, .field, rules)
			}
		} Catch exception {
			Set rule = ..#NOCHECK
		}
	}
	Set file = {"decisionRef": (ref), "kind": (kind), "case": (case), "runRef": (runRef), "fallbackReason": (reason), "runner": (runner), "replyClass": (replyClass), "attempt": (attempt), "finishReason": (reply.FinishReason), "stage": (stage), "rule": (rule), "rules": (rules), "field": (field), "problem": (problem), "failureText": (reply.FailureText), "text": (text)}
	Set name = number_"-"_ref_"-"_attempt_".json"
	If $$$ISERR(..Put(folder_name, file)) Quit ""
	Quit name
}

/// The runner that a request was sent to: the TargetConfigName of its header.
ClassMethod RunnerOf(requestId As %String) As %String [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' AND MessageBodyId = ? ORDER BY ID", requestId)
	If rows.%Next() Quit rows.%Get("TargetConfigName")
	Quit ""
}

/// The stage, the rule, the field and the rules (all parts, as a dynamic array) of the problem that Recheck gave for a reply that fails (see the class description).
ClassMethod Parse(problem As %String, replyClass As %String, Output stage As %String, Output rule As %String, Output field As %String, rules As %DynamicArray) [ Private ]
{
	Set stage = "check"
	Set parts = problem
	If problem = "No reason is left once the reply filter has run" {
		Set stage = ..#NOREASON
		Set rule = ..#NOREASON
		Set field = ""
		Do rules.%Push(rule)
		Quit
	}
	If $Extract(problem, 1, 11) = "After the r" {
		Set stage = "after the filter"
		Set parts = $Piece(problem, " refused the filtered payload: ", 2, *)
	} Else {
		Set parts = $Piece(problem, " accepts: ", 2, *)
	}
	Set rule = ..#NOCHECK
	Set field = ""
	For i = 1:1:$Length(parts, "; ") {
		Set part = $Piece(parts, "; ", i)
		If (part = "") || (part ? 1"and "1.N1" more") Continue
		Set name = ..RuleOf(part)
		If name = "" Continue
		Do rules.%Push(name)
		If rules.%Size() = 1 {
			Set rule = name
			Set field = ..FieldOf(part, name, replyClass)
		}
	}
}

/// The rule of one part: the tag of "ERROR #<code> rule <tag>" (a tag is lower-case letters, digits and hyphens), else the part. Reads no store and writes nothing.
ClassMethod RuleOf(part As %String) As %String [ Internal ]
{
	If part ? 1"ERROR #"1.N1" rule "1L.(1L,1N,1"-") Quit $Piece(part, " rule ", 2)
	Quit part
}

/// The field of a part: the field of the tag in REFUSALRULES of the reply class, else the JSON field name of the compiled property that the part names ("<Property>[ element n]: ..."
/// or "... on <Property>[ element n]"), else "". Reads no store and writes nothing.
ClassMethod FieldOf(part As %String, rule As %String, replyClass As %String) As %String [ Internal ]
{
	If rule '= part {
		Set rules = ","_$Parameter(replyClass, "REFUSALRULES")
		Quit $Piece($Piece(rules, ","_rule_":", 2), ",", 1)
	}
	Set name = $Select(part [ " on ": $Piece($Piece(part, " on ", 2), " ", 1), 1: $Piece($Piece(part, ":", 1), " ", 1))
	If (name = "") || ('##class(%Dictionary.CompiledProperty).%ExistsId(replyClass_"||"_name)) Quit ""
	Set property = ##class(%Dictionary.CompiledProperty).%OpenId(replyClass_"||"_name)
	Quit $Select($IsObject(property): property.Parameters.GetAt("%JSONFIELDNAME"), 1: "")
}

/// Counts one reply under its rule and field (an empty field is kept as "-" here), and under its case and rule.
ClassMethod Count(ByRef rules, ByRef cases, rule As %String, field As %String, case As %String) [ Private ]
{
	Set key = $Select(field = "": "-", 1: field)
	Set rules(rule, key) = $Get(rules(rule, key)) + 1
	If case '= "" Set cases(case, rule) = $Get(cases(case, rule)) + 1
}

/// Puts the counts into the summary's arrays, the most frequent first.
ClassMethod Tally(summary As %DynamicObject, ByRef rules, ByRef cases) [ Private ]
{
	Set rule = ""
	For {
		Set rule = $Order(rules(rule))
		If rule = "" Quit
		Set key = ""
		For {
			Set key = $Order(rules(rule, key))
			If key = "" Quit
			Set sorted(-rules(rule, key), rule, key) = ""
		}
	}
	Set count = ""
	For {
		Set count = $Order(sorted(count))
		If count = "" Quit
		Set rule = ""
		For {
			Set rule = $Order(sorted(count, rule))
			If rule = "" Quit
			Set key = ""
			For {
				Set key = $Order(sorted(count, rule, key))
				If key = "" Quit
				Do summary.rules.%Push({"rule": (rule), "field": ($Select(key = "-": "", 1: key)), "count": (-count)})
			}
		}
	}
	Set case = ""
	For {
		Set case = $Order(cases(case))
		If case = "" Quit
		Set rule = ""
		For {
			Set rule = $Order(cases(case, rule))
			If rule = "" Quit
			Do summary.cases.%Push({"case": (case), "rule": (rule), "count": (cases(case, rule))})
		}
	}
}

/// Writes the object as a JSON file in UTF-8.
ClassMethod Put(path As %String, object As %DynamicObject) As %Status [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = path
	Set stream.TranslateTable = "UTF8"
	Do object.%ToJSON(stream)
	Quit stream.%Save()
}

}
