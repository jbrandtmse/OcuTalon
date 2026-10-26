/// The reader of the productions that OcuTalon can watch (AD-3, AD-4, AD-6): the only class that switches namespace to look at a production, and
/// the only place that checks the service user's read access to a namespace. The watch tools and WatchOps both use it, so a tool and the
/// owner of the watch agree on what can be watched.
///   - Productions lists one entry per readable Interoperability namespace: its own current production, the one that
///     Ens.Director.GetProductionStatus gives, else the namespace's last production as Ens.Director.GetActiveProductionName gives it (the last one
///     started there, or the one set to start automatically when none had started), so that a cleanly stopped production can still be watched and a
///     watch on it stopped (DW-222). A namespace that never started a production has no entry, and no
///     other Ens.Config.Production row is ever an entry (DW-38). An entry is
///     {"namespace", "production" (the class name), "displayName"}. The display name is the Description of the production's definition, or the
///     class name when the description is empty. A namespace is readable when the user of the ServiceUser setting of Decide holds Read on the
///     resource of the namespace's default global database ($SYSTEM.Security.CheckUserPermission). An unreadable namespace, and one that
///     cannot be entered, are left out. On the online demo (the public flag onlineDemo) the list holds only the Orders demo production, when
///     it is readable.
///   - Find gives the entries that a name matches: the name is made like a display name (Label: trimmed, white-space runs made one space), a
///     trailing " production" is dropped, and the rest is compared without regard to case with the display name and with the class name. An
///     optional namespace narrows the match. Matches is that rule over any list of entries (the stop resolver uses it on a session's own watches).
///   - Label turns a production's description into its display name: white-space runs become one space and the text is cut to 128 characters
///     (the length of the DisplayName of the command and of the watch's row), so that a long or multi-line description never fails a start.
///   - Admits says whether one namespace and production are an entry, and gives its display name.
///   - OnlineDemo says whether the list is limited to Orders.
///   - Failures reads a watched production's new failures (Story 5.2; AD-15) from the namespace, inside the same one switching method: the
///     production must be the namespace's own (outcome not_current otherwise), and the service user must be able to read the namespace, which is
///     checked before any switch (outcome unreadable, nothing entered). A failure is a message header in Status 8 (Error) from the given time on,
///     whatever its IsError, with the raw text of its error, or an event-log row of Type 2 (Error) or 6 (Alert) with no session; a log row with a
///     session is only the text of its header. Each row of the output array is {"kind" (header, error or alert), "headerId", "sessionId",
///     "superSession", "item", "source", "bodyClass", "at" (IRIS UTC, as stored), "logId", "errorText"}, in time and id order, at most limit.
///   - Evidence reads the evidence of the failures with the given keys (Story 5.4), inside the same switching method and under the same two
///     checks as Failures (readable before any switch, outcome unreadable or not_current). It gives the snapshot as the reader snapshot of
///     Story 0.10 (format ocutalon.readerSnapshot/1): failures (one per header key: the header's fields, its error text chosen as Failures
///     chooses it, and body, the stored datatype properties of its message body, read through the class dictionary), eventLog (the rows of
///     the failures' sessions and of the log keys), items (the named item only, with its settings) and trace (the first failure's session, at
///     most TRACEMAX headers). The settings whose name holds credential, password, passwd, passphrase, secret, token, key or auth
///     (CredentialName) are left out after the switch, before Evidence returns, also when the read fails. The texts are raw, line breaks
///     included: the caller redacts them.
/// The Orders identity is read from OcuTalon.Install.Step.Demo (NAMESPACE and PRODUCTION), never copied. The namespace switch is in one method,
/// Current, which calls no OcuTalon class while it is in the other namespace. A reader runs inside AI Hub's callback, so this class makes no
/// AI Hub call, no Python call and no session call (AD-6).
Class OcuTalon.Watch.Reader
{

/// The longest the reader waits for the production lock of a namespace, in seconds.
Parameter LOCKSECONDS = 1;

/// The most headers in the trace of an evidence snapshot.
Parameter TRACEMAX = 20;

/// The most event-log rows in an evidence snapshot.
Parameter LOGMAX = 100;

/// The longest value of a message body's property in an evidence snapshot, in characters.
Parameter VALUEMAX = 1000;

/// The parts of a setting's name that make its value one that must never leave the reader, in lower case, comma-separated.
Parameter CREDENTIALPARTS = "credential,password,passwd,passphrase,secret,token,key,auth";

/// The trailing word that a name may carry: "the Orders production".
Parameter SUFFIX = " production";

/// The entries of every readable namespace, as a dynamic array of {"namespace", "production", "displayName"}, in namespace order. The
/// ServiceUser setting that cannot be read is an error, never an empty list.
ClassMethod Productions() As %DynamicArray
{
	Set list = []
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Set onlyOrders = ..OnlineDemo()
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set ordersProduction = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	$$$ThrowOnError(##class(%SYS.Namespace).ListAll(.namespaces))
	Set namespace = ""
	For {
		Set namespace = $Order(namespaces(namespace))
		Quit:namespace=""
		If $Extract(namespace) = "^" Continue
		If onlyOrders && (namespace '= orders) Continue
		If '##class(%Library.EnsembleMgr).IsEnsembleNamespace(namespace) Continue
		If '..Readable(user, namespace) Continue
		Set production = ..Current(namespace, .description)
		If production = "" Continue
		If onlyOrders && (production '= ordersProduction) Continue
		Set label = ..Label(description)
		Do list.%Push({"namespace": (namespace), "production": (production), "displayName": ($Select(label '= "": label, 1: production))})
	}
	Quit list
}

/// The entries that name matches (see the class description), in the order of Productions. namespace, when it is not empty, keeps only the
/// entries of that namespace, compared without regard to case. A name that is empty after trimming matches nothing.
ClassMethod Find(name As %String, namespace As %String = "") As %DynamicArray
{
	If ..Normalize(name) = "" Quit []
	Quit ..Matches(..Productions(), name, namespace)
}

/// The entries of the list (a dynamic array of {"namespace", "production", "displayName"}) that the name matches, in the list's order: the rule of
/// Find, over any list. It reads nothing.
ClassMethod Matches(entries As %DynamicArray, name As %String, namespace As %String = "") As %DynamicArray
{
	Set matches = []
	Set wanted = ..Normalize(name)
	If wanted = "" Quit matches
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (namespace '= "") && ($ZConvert(entry.namespace, "L") '= $ZConvert($ZStrip(namespace, "<>W"), "L")) Continue
		If (..Normalize(entry.displayName) = wanted) || ($ZConvert(entry.production, "L") = wanted) {
			Do matches.%Push(entry)
		}
	}
	Quit matches
}

/// 1 when namespace and production are an entry of Productions, with its display name in displayName; otherwise 0 and "".
ClassMethod Admits(namespace As %String, production As %String, Output displayName As %String) As %Boolean
{
	Set displayName = ""
	If (namespace = "") || (production = "") Quit 0
	Set iterator = ..Productions().%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.namespace = namespace) && (entry.production = production) {
			Set displayName = entry.displayName
			Quit
		}
	}
	Quit (displayName '= "")
}

/// 1 when the instance is the online demo, whose list is limited to the Orders demo production.
ClassMethod OnlineDemo() As %Boolean
{
	Quit (+##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 0)
}

/// The display name of a description (pure): white-space runs (line breaks and tabs included) become one space, the ends are trimmed and the
/// text is cut to 128 characters, the length of DisplayName in the StartWatch command and in BackgroundCheck.
ClassMethod Label(description As %String) As %String
{
	Set text = $ZStrip($Translate($Get(description), $Char(9, 10, 13), "   "), "<>W")
	Set text = $Extract($ZStrip(text, "=W"), 1, 128)
	Quit $ZStrip(text, "<>W")
}

/// A name for comparison: made like a display name (Label), in lower case, without a trailing " production".
ClassMethod Normalize(name As %String) As %String [ Private ]
{
	Set text = $ZConvert(..Label($Get(name)), "L")
	Set suffix = ..#SUFFIX
	If ($Length(text) > $Length(suffix)) && ($Extract(text, *-$Length(suffix)+1, *) = suffix) {
		Set text = $ZStrip($Extract(text, 1, *-$Length(suffix)), "<>W")
	}
	Quit text
}

/// 1 when the user holds Read on the resource of the namespace's default global database. Switches no namespace: the resource comes from
/// the namespace table.
ClassMethod Readable(user As %String, namespace As %String) As %Boolean [ Private ]
{
	Kill info
	Do ##class(%SYS.Namespace).GetNSInfo(namespace, .info)
	Set resource = $Get(info("Resource"))
	If resource = "" Set resource = $Get(info("GlobalDB", "Resource"))
	If resource = "" Quit 0
	Quit ''$SYSTEM.Security.CheckUserPermission(user, resource, "R")
}

/// The new failures of the production in the namespace, from the time from (an IRIS UTC stamp) on, at most limit (see the class description), as a
/// dynamic array in rows. The outcome: read (rows holds what was found, possibly nothing), unreadable (the service user cannot read the namespace:
/// nothing was entered and rows is empty) or not_current (the production is not the namespace's own, or a name is empty: nothing was read). A namespace that cannot
/// be read for another reason is an error.
ClassMethod Failures(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray) As %String
{
	Set rows = []
	If (namespace = "") || (production = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Do ..Current(namespace, .description, production, from, limit, .rows, .outcome, .fault)
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The failures of "_production_" in "_namespace_" could not be read: "_fault))
	Quit outcome
}

/// The evidence of the failures with the keys (comma-separated, h<header id> or l<log id>, as OcuTalon.Watch.Mark.KeyOf gives them) of the
/// production's item in the namespace, as the reader snapshot in snapshot (see the class description; always a dynamic object, with empty lists when
/// nothing was read). The outcome: read, unreadable (the service user cannot read the namespace: nothing was entered) or not_current (the production
/// is not the namespace's own, or a name is empty: nothing was read). A namespace that cannot be read for another reason is an error.
ClassMethod Evidence(namespace As %String, production As %String, item As %String, keys As %String, Output snapshot As %DynamicObject) As %String
{
	Set snapshot = {"format": "ocutalon.readerSnapshot/1", "source": {"namespace": ($Get(namespace)), "production": ($Get(production)), "item": ($Get(item))}, "failures": [], "eventLog": [], "items": [], "trace": []}
	If ($Get(namespace) = "") || ($Get(production) = "") || ($Get(item) = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Do ..Current(namespace, .description, production, "", 0, .rows, .outcome, .fault, item, $Get(keys), .snapshot)
	Set items = snapshot.items
	For i = 0:1:items.%Size() - 1 {
		Set settings = items.%Get(i).settings
		Kill left
		Set iterator = settings.%GetIterator()
		While iterator.%GetNext(.name) {
			If ..CredentialName(name) Set left(name) = ""
		}
		Set name = ""
		For {
			Set name = $Order(left(name))
			Quit:name=""
			Do settings.%Remove(name)
		}
	}
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The evidence of "_production_" in "_namespace_" could not be read: "_fault))
	Quit outcome
}

/// 1 when the name of a setting is one whose value must never leave the reader: it holds one of CREDENTIALPARTS, in any case (pure).
ClassMethod CredentialName(name As %String) As %Boolean
{
	Set lower = $ZConvert($Get(name), "L")
	Set parts = $ListFromString(..#CREDENTIALPARTS)
	Set position = 0
	While $ListNext(parts, position, part) {
		If lower [ part Return 1
	}
	Quit 0
}

/// The name of the namespace's own current production, and its definition's Description, as written, in description: the running production as
/// Ens.Director.GetProductionStatus gives it, else the namespace's last production (Ens.Director.GetActiveProductionName). "" when the namespace has
/// none, or when it cannot be entered or read (fault holds why). This is the one method that switches namespace, and it calls no OcuTalon class
/// there, this one's methods included (Productions makes the display name, Failures its answers).
/// When production is not empty it also reads that production's failures (Failures): outcome is not_current when production is not the name that
/// is returned, otherwise read, and rows (a dynamic array) holds the failures from the stamp from on, at most limit, in the order of their time
/// and id, headers before log rows of one time. The text of a header's error is the Type 2 row whose MessageId is the header and whose SessionId
/// matches; else the session's Type 2 row of the header's target; else the header's own ErrorStatus text when IsError; else "".
/// When item is not empty (Evidence) it reads, instead of the failures from a time on, the evidence of the failures with the keys (comma-separated
/// h<header id> and l<log id>) into snapshot, by the same rule for the text of a header's error (see Evidence for the shape). The body of a header
/// is read through the class dictionary: the stored datatype properties of its class, at most VALUEMAX characters each.
ClassMethod Current(namespace As %String, Output description As %String, production As %String = "", from As %String = "", limit As %Integer = 0, Output rows As %DynamicArray, Output outcome As %String, Output fault As %String, item As %String = "", keys As %String = "", Output snapshot As %DynamicObject) As %String [ Private ]
{
	Set description = ""
	Set name = ""
	Set rows = []
	Set outcome = ""
	Set fault = ""
	Set evidence = (item '= "")
	Set lock = ..#LOCKSECONDS
	New $NAMESPACE
	Try {
		Set $NAMESPACE = namespace
		Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state, lock, 1)
		If $$$ISERR(sc) Set name = ""
		If name = "" Set name = ##class(Ens.Director).GetActiveProductionName()
		If name '= "" {
			Set definition = ##class(Ens.Config.Production).%OpenId(name)
			If $IsObject(definition) Set description = definition.Description
		}
		If production '= "" {
			If (name = "") || (name '= production) {
				Set outcome = "not_current"
			} Else {
				Set outcome = "read"
				Set headerIds = ""
				Set logIds = ""
				If evidence {
					For i = 1:1:$Length(keys, ",") {
						Set key = $Piece(keys, ",", i)
						If key ? 1"h".N {
							Set headerIds = headerIds _ $ListBuild(+$Extract(key, 2, *))
						} ElseIf key ? 1"l".N {
							Set logIds = logIds _ $ListBuild(+$Extract(key, 2, *))
						}
					}
				}
				Set passes = $Select(evidence: $ListLength(headerIds), limit > 0: 1, 1: 0)
				If passes {
					Set headers = ##class(%SQL.Statement).%New()
					If evidence {
						$$$ThrowOnError(headers.%Prepare("SELECT ID, SessionId, SuperSession, SourceConfigName, TargetConfigName, MessageBodyClassName, IsError, ErrorStatus, TimeProcessed, MessageBodyId, TimeCreated, Status FROM Ens.MessageHeader WHERE ID = ?", 1))
					} Else {
						$$$ThrowOnError(headers.%Prepare("SELECT TOP ? ID, SessionId, SuperSession, SourceConfigName, TargetConfigName, MessageBodyClassName, IsError, ErrorStatus, TimeProcessed, MessageBodyId, TimeCreated, Status FROM Ens.MessageHeader WHERE Status = 8 AND TimeProcessed >= ? ORDER BY TimeProcessed, ID", 1))
					}
					Set texts = ##class(%SQL.Statement).%New()
					$$$ThrowOnError(texts.%Prepare("SELECT ID, MessageId, ConfigName, Text FROM Ens_Util.Log WHERE SessionId = ? AND Type = 2 ORDER BY ID", 1))
					If limit > 0 {
						Set orphans = ##class(%SQL.Statement).%New()
						$$$ThrowOnError(orphans.%Prepare("SELECT TOP ? ID, Type, ConfigName, Text, TimeLogged FROM Ens_Util.Log WHERE TimeLogged >= ? AND Type IN (2, 6) AND SessionId IS NULL ORDER BY TimeLogged, ID", 1))
					}
					For pass = 1:1:passes {
						If evidence {
							Set result = headers.%Execute($List(headerIds, pass))
						} Else {
							Set result = headers.%Execute(limit, from)
						}
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While result.%Next() {
							Set id = result.%GetData(1)
							Set sessionId = result.%GetData(2)
							Set target = result.%GetData(5)
							Set text = ""
							Set byItem = ""
							Set exact = 0
							Set logId = ""
							If sessionId '= "" {
								Set logs = texts.%Execute(sessionId)
								If logs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, logs.%Message))
								While logs.%Next() {
									If logs.%GetData(2) = id {
										Set text = logs.%GetData(4)
										Set logId = logs.%GetData(1)
										Set exact = 1
										Quit
									}
									If (byItem = "") && (logs.%GetData(3) = target) {
										Set byItem = logs.%GetData(4)
										Set byItemId = logs.%GetData(1)
									}
								}
								If 'exact && (byItem '= "") {
									Set text = byItem
									Set logId = byItemId
								}
							}
							If (text = "") && result.%GetData(7) Set text = $SYSTEM.Status.GetErrorText(result.%GetData(8))
							If evidence {
								Set failure = {"headerId": (id), "sessionId": (sessionId), "superSession": (result.%GetData(3)), "timeCreated": ($Translate($Piece(result.%GetData(11), ".", 1), " ", "T")_"Z"), "timeProcessed": ($Translate($Piece(result.%GetData(9), ".", 1), " ", "T")_"Z"), "sourceConfigName": (result.%GetData(4)), "targetConfigName": (target), "bodyClass": (result.%GetData(6)), "bodyId": (result.%GetData(10)), "status": (##class(Ens.DataType.MessageStatus).LogicalToDisplay(result.%GetData(12)))}
								Do failure.%Set("isError", +result.%GetData(7), "boolean")
								Set failure.error = text
								Set body = {}
								Set bodyClass = result.%GetData(6)
								If (bodyClass '= "") && (result.%GetData(10) '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(bodyClass) && $ClassMethod(bodyClass, "%Extends", "%Library.Persistent") {
									Try {
										Set object = $ClassMethod(bodyClass, "%OpenId", result.%GetData(10))
										If $IsObject(object) {
											Set props = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Type FROM %Dictionary.CompiledProperty WHERE parent = ? AND Private = 0 AND Calculated = 0 AND Transient = 0 AND MultiDimensional = 0 AND Relationship = 0 ORDER BY SequenceNumber", bodyClass)
											If props.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, props.%Message))
											While props.%Next() {
												If ##class(%Dictionary.CompiledProperty).%OpenId(bodyClass_"||"_props.%Get("Name")).Collection '= "" Continue
												Set type = ##class(%Dictionary.CompiledClass).%OpenId(props.%Get("Type"))
												If '$IsObject(type) || (type.ClassType '= "datatype") Continue
												Set value = $Property(object, props.%Get("Name"))
												If $Length(value) > ..#VALUEMAX Set value = $Extract(value, 1, ..#VALUEMAX)
												Do body.%Set(props.%Get("Name"), value)
											}
										}
									} Catch {
										Set body = {}
									}
								}
								Set failure.body = body
								Do snapshot.failures.%Push(failure)
								If sessionId '= "" Set sessions(sessionId) = ""
								If pass = 1 Set traceSession = sessionId
							} Else {
								Set found(result.%GetData(9), 1, id) = {"kind": "header", "headerId": (id), "sessionId": (sessionId), "superSession": (result.%GetData(3)), "item": (target), "source": (result.%GetData(4)), "bodyClass": (result.%GetData(6)), "at": (result.%GetData(9)), "logId": (logId), "errorText": (text)}
							}
						}
					}
					If 'evidence {
						Set result = orphans.%Execute(limit, from)
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While result.%Next() {
							Set id = result.%GetData(1)
							Set found(result.%GetData(5), 2, id) = {"kind": ($Select(result.%GetData(2) = 6: "alert", 1: "error")), "headerId": "", "sessionId": "", "superSession": "", "item": (result.%GetData(3)), "source": "", "bodyClass": "", "at": (result.%GetData(5)), "logId": (id), "errorText": (result.%GetData(4))}
						}
						Set at = ""
						For {
							Set at = $Order(found(at))
							Quit:at=""
							Set order = ""
							For {
								Set order = $Order(found(at, order))
								Quit:order=""
								Set id = ""
								For {
									Set id = $Order(found(at, order, id), 1, row)
									Quit:id=""
									If rows.%Size() '< limit Quit
									Do rows.%Push(row)
								}
							}
						}
					}
				}
				If evidence {
					If $IsObject($Get(definition)) {
						For i = 1:1:definition.Items.Count() {
							Set entry = definition.Items.GetAt(i)
							If entry.Name '= item Continue
							Set settings = {}
							For j = 1:1:entry.Settings.Count() {
								Do settings.%Set(entry.Settings.GetAt(j).Name, entry.Settings.GetAt(j).Value)
							}
							Do snapshot.items.%Push({"name": (entry.Name), "className": (entry.ClassName), "enabled": (+entry.Enabled), "poolSize": (+entry.PoolSize), "settings": (settings)})
							Quit
						}
					}
					Set bySession = ##class(%SQL.Statement).%New()
					$$$ThrowOnError(bySession.%Prepare("SELECT ID, TimeLogged, Type, ConfigName, SourceClass, SourceMethod, SessionId, Text FROM Ens_Util.Log WHERE SessionId = ? ORDER BY ID", 1))
					Set byId = ##class(%SQL.Statement).%New()
					$$$ThrowOnError(byId.%Prepare("SELECT ID, TimeLogged, Type, ConfigName, SourceClass, SourceMethod, SessionId, Text FROM Ens_Util.Log WHERE ID = ?", 1))
					Set count = 0
					Set session = ""
					For {
						Set session = $Order(sessions(session))
						Quit:session=""
						Set count = count + 1
						Set argument(count) = $ListBuild("session", session)
					}
					For i = 1:1:$ListLength(logIds) {
						Set count = count + 1
						Set argument(count) = $ListBuild("id", $List(logIds, i))
					}
					For i = 1:1:count {
						If $List(argument(i), 1) = "session" {
							Set result = bySession.%Execute($List(argument(i), 2))
						} Else {
							Set result = byId.%Execute($List(argument(i), 2))
						}
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While (snapshot.eventLog.%Size() < ..#LOGMAX) && result.%Next() {
							If $Data(logged(result.%Get("ID"))) Continue
							Set logged(result.%Get("ID")) = ""
							Do snapshot.eventLog.%Push({"id": (result.%Get("ID")), "timeLogged": ($Translate($Piece(result.%Get("TimeLogged"), ".", 1), " ", "T")_"Z"), "type": (##class(Ens.DataType.LogType).LogicalToDisplay(result.%Get("Type"))), "configName": (result.%Get("ConfigName")), "sourceClass": (result.%Get("SourceClass")), "sourceMethod": (result.%Get("SourceMethod")), "sessionId": (result.%Get("SessionId")), "text": (result.%Get("Text"))})
						}
					}
					If $Get(traceSession) '= "" {
						Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP ? ID, Type, SourceConfigName, TargetConfigName, MessageBodyClassName, Status, TimeCreated, IsError FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID", ..#TRACEMAX, traceSession)
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While result.%Next() {
							Set entry = {"headerId": (result.%Get("ID")), "type": (##class(Ens.DataType.MessageType).LogicalToDisplay(result.%Get("Type"))), "sourceConfigName": (result.%Get("SourceConfigName")), "targetConfigName": (result.%Get("TargetConfigName")), "bodyClass": (result.%Get("MessageBodyClassName")), "status": (##class(Ens.DataType.MessageStatus).LogicalToDisplay(result.%Get("Status"))), "timeCreated": ($Translate($Piece(result.%Get("TimeCreated"), ".", 1), " ", "T")_"Z")}
							Do entry.%Set("isError", +result.%Get("IsError"), "boolean")
							Do snapshot.trace.%Push(entry)
						}
					}
				}
			}
		}
	} Catch exception {
		Set name = ""
		Set description = ""
		Set rows = []
		Set outcome = ""
		Set fault = exception.DisplayString()
	}
	Quit name
}

}
