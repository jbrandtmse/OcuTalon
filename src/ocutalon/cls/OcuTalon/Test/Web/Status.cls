/// Tests of the public status class (matrix row 19, the slot A part): the body for the public settings that are set
/// and for none, the busy formula, the route and the authorisation, an error's answer, and the classes of both public packages
/// (OcuTalon.Web.Public and OcuTalon.Data.Public, read from the class dictionary), which may reference only what AD-3 allows. The tests set the public settings that the body reads. OnBeforeAllTests saves them and
/// OnAfterAllTests restores each one, so the slot's settings are as they were. The HTTP half is test-sign-in.sh's.
Class OcuTalon.Test.Web.Status Extends %UnitTest.TestCase
{

/// The settings that the tests change: the readiness key and the fixed keys that the body reads.
Parameter KEYS = "ready,resetAnchor,resetIntervalHours,lastReset,lastResetKind,connectionCap,connectionReserve";

/// saved(key) = the stored value of each setting before the tests, "" when it was unset.
Property Saved As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
	Set position = 0
	Set keys = $ListFromString(..#KEYS)
	While $ListNext(keys, position, key) {
		Set ..Saved(key) = ##class(OcuTalon.Data.Public.Settings).Get(key)
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Restore()
	Quit $SYSTEM.Status.OK()
}

/// With every setting set, the body has exactly five keys with the stored values; ready is a JSON boolean.
Method TestBodyWithSettings()
{
	Do ##class(OcuTalon.Data.Public.Settings).SetReady()
	Do ..SetAll("2026-01-01T00:00:00Z", 24, "2026-10-18T03:00:00Z", "scheduled", 100000, 2)
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(..Keys(body), "ready,nextReset,busy,lastReset,lastResetKind", "exactly the five keys")
	Do $$$AssertEquals(body.%GetTypeOf("ready"), "boolean", "ready is a boolean")
	Do $$$AssertEquals(body.ready, 1, "ready is true")
	Do $$$AssertEquals(body.nextReset, ##class(OcuTalon.Data.Public.Settings).NextReset(), "nextReset is the next scheduled reset")
	Do $$$AssertTrue(body.nextReset ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and a Utc time: "_body.nextReset)
	Do $$$AssertEquals(body.%GetTypeOf("busy"), "boolean", "busy is a boolean")
	Do $$$AssertEquals(body.busy, 0, "busy is false while the connections are far below the cap less the reserve")
	Do $$$AssertEquals(body.lastReset, "2026-10-18T03:00:00Z", "lastReset")
	Do $$$AssertEquals(body.lastResetKind, "scheduled", "lastResetKind")

	Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(body.%GetTypeOf("ready"), "boolean", "ready is a boolean when it is not set")
	Do $$$AssertEquals(body.ready, 0, "ready is false when readiness is cleared")

	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionCap", 8)
	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionReserve", 8)
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(body.busy, 1, "busy is true when the connections reach the cap less the reserve")
}

/// With no setting, every key is still there: ready false, busy false, and null for the times and the kind.
Method TestBodyWithoutSettings()
{
	Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
	Do ..SetAll("", "", "", "", "", "")
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(..Keys(body), "ready,nextReset,busy,lastReset,lastResetKind", "exactly the five keys")
	Do $$$AssertEquals(body.ready, 0, "ready is false")
	Do $$$AssertEquals(body.busy, 0, "busy is false without a cap")
	For key = "nextReset", "lastReset", "lastResetKind" {
		Do $$$AssertEquals(body.%GetTypeOf(key), "null", key_" is null")
	}
	Do $$$AssertEquals(body.%ToJSON(), "{""ready"":false,""nextReset"":null,""busy"":false,""lastReset"":null,""lastResetKind"":null}", "the JSON")
}

/// Busy is true when the connections reach the cap less the reserve, and false without a valid cap.
Method TestIsBusy()
{
	Set status = "OcuTalon.Web.Public.Status"
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 6, 8, 2), 1, "6 of 8 less 2 is busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 5, 8, 2), 0, "5 of 8 less 2 is not")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 7, 8, 2), 1, "7 is busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, "", 2), 0, "no cap is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, "x", 2), 0, "a cap that isn't a number is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, 0, 2), 0, "a cap of 0 is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, -3, 0), 0, "a negative cap is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 1, 1, ""), 1, "no reserve counts as 0")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 0, 1, "x"), 0, "a reserve that isn't a number counts as 0")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 8, 8, 8), 1, "a reserve as large as the cap is always busy")
}

/// One route, GET /status; no session; JSON; everyone is authorised; Show writes the body with no-store.
Method TestRouteAndAccess()
{
	Set found = ##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.Public.Status")
	Do $$$AssertEquals($ListToString(found, "|"), "GET /status Show", "exactly one route")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Status", "UseSession"), 0, "no session")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Status", "CONTENTTYPE"), "application/json", "JSON")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Status", "HandleCorsRequest"), 0, "no CORS handling")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Web.Public.Status", "%Extends", "%CSP.REST"), "it is a %CSP.REST class")
	Do $ClassMethod("OcuTalon.Web.Public.Status", "AccessCheck", .authorized)
	Do $$$AssertEquals(authorized, 1, "AccessCheck authorises")

	Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
	Do ..SetAll("", "", "", "", "", "")
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/public/")
	Set %response = ##class(%CSP.Response).%New()
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Public.Status", "Show")
	Do $$$AssertStatusOK(sc, "Show returns OK")
	Do $$$AssertEquals(%response.GetHeader("Cache-Control"), "no-store", "Cache-Control: no-store")
	Do $$$AssertEquals(written, ##class(OcuTalon.Web.Public.Status).Body().%ToJSON(), "Show writes the body")
}

/// An error is answered with its status line only: its cause is never written to the anonymous caller.
Method TestErrorSendsNoCause()
{
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/public/")
	Set %response = ##class(%CSP.Response).%New()
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Public.Status", "ReportHttpStatusCode", "500 Internal Server Error", $SYSTEM.Status.Error(5001, "zz-the-cause"))
	Do $$$AssertStatusOK(sc, "ReportHttpStatusCode returns OK")
	Do $$$AssertEquals(%response.Status, "500 Internal Server Error", "the status line")
	Do $$$AssertEquals(written, "", "and no body, so the cause is not sent")
}

/// Every class of the two public packages, read from the class dictionary so that a new class is covered, references only what
/// AD-3 allows: %CSP (including %CSP.REST), dynamic objects, $SYSTEM.License, $SYSTEM.Status, $SYSTEM.Encryption in a generator
/// method only, and the two packages. The scan covers the source's ##class calls, $SYSTEM members and dynamic dispatch, the
/// superclasses, and the types of the properties, the arguments and the return values. The samples show that the scans find a
/// class, a $SYSTEM member, a dynamic call, a superclass and a type outside the list, and $SYSTEM.Encryption in a plain method.
Method TestReferencesOnlyThePublicAllowList()
{
	Set classes = ..PublicClasses()
	Do $$$AssertTrue($ListLength(classes) >= 6, "the dictionary lists the classes of both public packages")
	Set position = 0
	While $ListNext(classes, position, class) {
		Set sc = ##class(%Compiler.UDL.TextServices).GetTextAsString($Namespace, class, .text)
		Do $$$AssertStatusOK(sc, "the source of "_class)
		Do $$$AssertTrue($Length(text) > 200, class_" has a source")
		Do $$$AssertEquals(..Outside(text, ..GeneratorText(class)), "", class_" references nothing outside the allow-list")
		Do $$$AssertEquals(..MembersOutside(class), "", class_" extends and types its members with nothing outside the allow-list")
	}
	Do $$$AssertTrue($ListFind(classes, "OcuTalon.Web.Public.Login"), "the list holds the sign-in page, whose generators use $SYSTEM.Encryption")

	Set found = ..Outside("Quit ##Class(OcuTalon.Fix.Executor).Run()_$system.Util.DataDirectory()_$classmethod(a, b)_##class(%CSP.REST).X()_$SYSTEM.License.X()")
	Do $$$AssertEquals(found, " OCUTALON.FIX.EXECUTOR $SYSTEM.UTIL $CLASSMETHOD", "the scan finds a class, a $SYSTEM member and a dynamic call outside the allow-list, whatever their case")
	Set found = ..Outside("Quit ##class(OcuTalon.Data.Public.Settings).Get(k)_##class(OcuTalon.Web.Public.Login).X()_##class(%CSP.Page).X()_$SYSTEM.Status.OK()_##class(%DynamicObject).%New()")
	Do $$$AssertEquals(found, "", "the scan passes the two packages, %CSP, dynamic objects, $SYSTEM.License and $SYSTEM.Status")
	Set found = ..Outside("Quit $zobjclassmethod(a, b)_$ZObjMethod(c, d)")
	Do $$$AssertEquals(found, " $ZOBJCLASSMETHOD $ZOBJMETHOD", "the scan finds the other dynamic calls")

	Set plain = "ClassMethod A() { Quit $SYSTEM.Encryption.Base64Encode(x) }"
	Set generator = "Do %code.WriteLine($SYSTEM.Encryption.Base64Encode(css))"
	Do $$$AssertEquals(..Outside(plain), " $SYSTEM.ENCRYPTION", "$SYSTEM.Encryption in a plain method is outside the allow-list")
	Do $$$AssertEquals(..Outside(generator, generator), "", "$SYSTEM.Encryption in a generator method is inside it")
	Do $$$AssertEquals(..Outside(generator_" "_plain, generator), " $SYSTEM.ENCRYPTION", "and one more use, outside the generator methods, is not")

	Do $$$AssertEquals(..SupersOutside("%CSP.REST"), "", "%CSP.REST is allowed")
	Do $$$AssertEquals(..SupersOutside("%CSP.Login, OcuTalon.Web.Public.SignInAssets,%DynamicObject"), "", "%CSP, the two packages and dynamic objects are allowed")
	Do $$$AssertEquals(..SupersOutside("%CSP.REST,OcuTalon.Data.Setting,%Persistent"), " OCUTALON.DATA.SETTING %PERSISTENT", "a superclass outside the list is found")
	Do $$$AssertEquals(..TypeOutside("%String")_..TypeOutside("%Library.Boolean")_..TypeOutside("%Status")_..TypeOutside("%Integer"), "0000", "the system datatype classes are allowed")
	Do $$$AssertEquals(..TypeOutside("%DynamicObject")_..TypeOutside("%Library.DynamicArray")_..TypeOutside("%CSP.REST")_..TypeOutside("OcuTalon.Web.Public.Login")_..TypeOutside("OcuTalon.Data.Public.Settings"), "00000", "dynamic objects, %CSP and the two packages are allowed as types")
	Do $$$AssertEquals(..TypeOutside("OcuTalon.Data.Setting")_..TypeOutside("%Persistent")_..TypeOutside("%Library.RegisteredObject")_..TypeOutside("Ens.DataType.ConfigName"), "1111", "a persistent class, a system class that is not a datatype and a datatype class of another package are outside")
	Set types = ..ArgTypes("a,b:%Status=1,&c:OcuTalon.Msg.Item,*d:%Integer,e:%String(MAXLEN=5)={$$$OK},f:%String=""x,y""")
	Do $$$AssertEquals($ListToString(types, "|"), "%Status|OcuTalon.Msg.Item|%Integer|%String|%String", "the argument types of a formal spec, whatever their defaults hold")
}

/// The scans of a class definition find what the allow-list does not name, in the superclasses, the property, return and argument
/// types, and $SYSTEM.Encryption outside the generator methods. The samples are definitions in memory, never saved, so that a
/// scan that can no longer find anything fails here and not only on the classes of the packages.
Method TestDefinitionScansFindWhatIsOutside()
{
	Set outside = ##class(%Dictionary.ClassDefinition).%New("Zz.Outside")
	Set outside.Super = "%CSP.REST,Zz.Super"
	Set property = ##class(%Dictionary.PropertyDefinition).%New()
	Set property.Name = "Prop"
	Set property.Type = "Zz.PropType"
	Set property.parent = outside
	Set method = ##class(%Dictionary.MethodDefinition).%New()
	Set method.Name = "Run"
	Set method.ReturnType = "Zz.RetType"
	Set method.FormalSpec = "a:Zz.ArgType,b:%String"
	Set method.parent = outside
	Do $$$AssertEquals(..DefinitionOutside(outside), " ZZ.SUPER ZZ.PROPTYPE ZZ.RETTYPE ZZ.ARGTYPE", "a superclass, a property type, a return type and an argument type outside the list are found")

	Set inside = ##class(%Dictionary.ClassDefinition).%New("Zz.Inside")
	Set inside.Super = "%CSP.REST,OcuTalon.Web.Public.ApiBase"
	Set property = ##class(%Dictionary.PropertyDefinition).%New()
	Set property.Name = "Prop"
	Set property.Type = "%String"
	Set property.parent = inside
	Set method = ##class(%Dictionary.MethodDefinition).%New()
	Set method.Name = "Run"
	Set method.ReturnType = "%Status"
	Set method.FormalSpec = "a:%Integer,b:OcuTalon.Data.Public.Settings"
	Set method.parent = inside
	Do $$$AssertEquals(..DefinitionOutside(inside), "", "the system datatypes, %CSP and the two packages are inside the list")

	Set sample = ##class(%Dictionary.ClassDefinition).%New("Zz.Generators")
	Set method = ##class(%Dictionary.MethodDefinition).%New()
	Set method.Name = "Plain"
	Do method.Implementation.Write("Quit PLAINBODY")
	Set method.parent = sample
	Set method = ##class(%Dictionary.MethodDefinition).%New()
	Set method.Name = "Gen"
	Set method.CodeMode = "generator"
	Do method.Implementation.Write("Do %code.WriteLine(ALPHAGEN)")
	Set method.parent = sample
	Set method = ##class(%Dictionary.MethodDefinition).%New()
	Set method.Name = "ObjectGen"
	Set method.CodeMode = "objectgenerator"
	Do method.Implementation.Write("Do %code.WriteLine(BETAOBJ)")
	Set method.parent = sample
	Set text = ..GeneratorTextOf(sample)
	Do $$$AssertTrue((text [ "ALPHAGEN") && (text [ "BETAOBJ"), "the text of a generator and of an object generator is taken")
	Do $$$AssertTrue(text '[ "PLAINBODY", "and the text of a plain method is not")
}

/// --- helpers ---
/// The classes of the two public packages, from the class dictionary, as a list.
ClassMethod PublicClasses() As %List [ Private ]
{
	Set classes = ""
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Web.Public.' OR Name %STARTSWITH 'OcuTalon.Data.Public.' ORDER BY Name")
	If $SYSTEM.Status.IsError(sc) Quit classes
	Set result = statement.%Execute()
	While result.%Next() {
		Set classes = classes_$ListBuild(result.%GetData(1))
	}
	Quit classes
}

/// The implementations of the generator methods of a class (CodeMode generator or objectgenerator), as one text.
ClassMethod GeneratorText(class As %String) As %String [ Private ]
{
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(class)
	If '$IsObject(definition) Quit ""
	Quit ..GeneratorTextOf(definition)
}

/// The same for a class definition in memory.
ClassMethod GeneratorTextOf(definition As %Dictionary.ClassDefinition) As %String [ Private ]
{
	Set text = ""
	Set key = ""
	For {
		Set method = definition.Methods.GetNext(.key)
		Quit:key=""
		If ($ZConvert(method.CodeMode, "L") '= "generator") && ($ZConvert(method.CodeMode, "L") '= "objectgenerator") Continue
		Do method.Implementation.Rewind()
		While 'method.Implementation.AtEnd {
			Set text = text_method.Implementation.Read(30000)
		}
	}
	Quit text
}

/// The superclasses, and the property, argument and return types of a class, that the allow-list does not name, as a list of
/// names in upper case.
ClassMethod MembersOutside(class As %String) As %String [ Private ]
{
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(class)
	If '$IsObject(definition) Quit " "_$ZConvert(class, "U")_" (no definition)"
	Quit ..DefinitionOutside(definition)
}

/// The same for a class definition in memory.
ClassMethod DefinitionOutside(definition As %Dictionary.ClassDefinition) As %String [ Private ]
{
	Set outside = ..SupersOutside(definition.Super)
	Set key = ""
	For {
		Set property = definition.Properties.GetNext(.key)
		Quit:key=""
		If ..TypeOutside(property.Type) Set outside = outside_" "_$ZConvert(property.Type, "U")
	}
	Set key = ""
	For {
		Set method = definition.Methods.GetNext(.key)
		Quit:key=""
		Set types = $ListBuild(method.ReturnType)_..ArgTypes(method.FormalSpec)
		Set position = 0
		While $ListNext(types, position, type) {
			If ..TypeOutside(type) Set outside = outside_" "_$ZConvert($Piece(type, "(", 1), "U")
		}
	}
	Quit outside
}

/// The superclasses in a comma list that the allow-list does not name: %CSP, dynamic objects and the two packages.
ClassMethod SupersOutside(supers As %String) As %String [ Private ]
{
	Set outside = ""
	For i = 1:1:$Length(supers, ",") {
		Set super = $ZStrip($Piece(supers, ",", i), "<>W")
		If super '= "", ..Outside("##class("_super_")") '= "" Set outside = outside_" "_$ZConvert(super, "U")
	}
	Quit outside
}

/// 1 when a type is outside the allow-list: a class that is not %CSP, a dynamic object, in the two packages or a system datatype
/// class (%String, %Integer, %Boolean, %Status and the like); a datatype class of another package is outside.
ClassMethod TypeOutside(type As %String) As %Boolean [ Private ]
{
	Set type = $ZStrip($Piece(type, "(", 1), "<>W")
	If type = "" Quit 0
	If ..Outside("##class("_type_")") = "" Quit 0
	If $Extract(type) '= "%" Quit 1
	Set full = $Select(type [ ".": type, 1: "%Library."_$Extract(type, 2, *))
	Quit '(##class(%Dictionary.CompiledClass).%ExistsId(full) && (##class(%Dictionary.CompiledClass).%OpenId(full).ClassType = "datatype"))
}

/// The types in a formal spec (name:type=default, with & and * before the name), as a list; an argument without a type has none.
ClassMethod ArgTypes(spec As %String) As %List [ Private ]
{
	Set types = ""
	Set argument = ""
	Set depth = 0
	Set quoted = 0
	For i = 1:1:$Length(spec) + 1 {
		Set char = $Extract(spec, i)
		If (i > $Length(spec)) || ((char = ",") && (depth = 0) && ('quoted)) {
			Set head = $Piece($Piece(argument, "=", 1), ":", 2)
			Set head = $ZStrip($Piece(head, "(", 1), "<>W")
			If head '= "" Set types = types_$ListBuild(head)
			Set argument = ""
			Continue
		}
		If char = """" Set quoted = 'quoted
		If 'quoted {
			If (char = "(") || (char = "{") Set depth = depth + 1
			If (char = ")") || (char = "}") Set depth = depth - 1
		}
		Set argument = argument_char
	}
	Quit types
}

/// The classes and $SYSTEM members that a source references and AD-3 does not allow, and any dynamic dispatch, as a
/// list of names in upper case. ObjectScript is case-insensitive, so the scan is too. generated is the text of the generator
/// methods: $SYSTEM.Encryption is allowed only when every use of it in the source lies in that text.
ClassMethod Outside(text As %String, generated As %String = "") As %String [ Private ]
{
	Set outside = ""
	Set upper = $ZConvert(text, "U")
	Set from = 1
	While $Find(upper, "##CLASS(", from) {
		Set start = $Find(upper, "##CLASS(", from)
		Set name = $Piece($Extract(upper, start, start + 100), ")", 1)
		Set from = start
		If ($Extract(name, 1, 5) = "%CSP.") || ($Extract(name, 1, 20) = "OCUTALON.WEB.PUBLIC.") || ($Extract(name, 1, 21) = "OCUTALON.DATA.PUBLIC.") || (name = "%DYNAMICOBJECT") || (name = "%DYNAMICARRAY") || (name = "%LIBRARY.DYNAMICOBJECT") || (name = "%LIBRARY.DYNAMICARRAY") Continue
		Set outside = outside_" "_name
	}
	Set from = 1
	Set encryption = 0
	While $Find(upper, "$SYSTEM.", from) {
		Set start = $Find(upper, "$SYSTEM.", from)
		Set name = ..Word(upper, start)
		Set from = start
		If (name = "LICENSE") || (name = "STATUS") Continue
		If name = "ENCRYPTION" Set encryption = encryption + 1 Continue
		Set outside = outside_" $SYSTEM."_name
	}
	Set inGenerators = $Select(generated = "": 0, 1: $Length($ZConvert(generated, "U"), "$SYSTEM.ENCRYPTION") - 1)
	If encryption > inGenerators Set outside = outside_" $SYSTEM.ENCRYPTION"
	For dispatch = "$CLASSMETHOD(", "$METHOD(", "$ZOBJCLASSMETHOD(", "$ZOBJMETHOD(" {
		If $Find(upper, dispatch) Set outside = outside_" "_$Extract(dispatch, 1, *-1)
	}
	Quit outside
}

/// Sets the fixed keys that the body reads.
Method SetAll(anchor As %String, interval As %String, lastReset As %String, kind As %String, cap As %String, reserve As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", anchor), "resetAnchor is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("resetIntervalHours", interval), "resetIntervalHours is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("lastReset", lastReset), "lastReset is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("lastResetKind", kind), "lastResetKind is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("connectionCap", cap), "connectionCap is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("connectionReserve", reserve), "connectionReserve is set")
}

/// Puts every setting back as OnBeforeAllTests found it.
Method Restore() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If key = "ready" {
			If ..Saved(key) '= "" {
				Do ##class(OcuTalon.Data.Public.Settings).SetReady()
			} Else {
				Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
			}
		} Else {
			Do ##class(OcuTalon.Data.Public.Settings).Set(key, ..Saved(key))
		}
	}
}

/// The run of letters of text that starts at position start.
ClassMethod Word(text As %String, start As %Integer) As %String [ Private ]
{
	Set word = ""
	For i = start:1:start + 40 {
		Set char = $Extract(text, i)
		If char '? 1A Quit
		Set word = word_char
	}
	Quit word
}

/// The keys of a dynamic object, as a comma list in order.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

}
