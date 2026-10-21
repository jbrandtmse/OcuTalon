/// The contract check that the contract tests share (AD-29, AD-33). A subclass holds its contracts in an XData block of JSON,
///   {"<class>": {"super": "<superclass>[,<superclass>...]", "abstract": 1, "props": {"<Name>": "<type spec>"},
///                "indexes": {"<Name>": "<props>[ unique]"}, "sql": {"<Name>": "<SqlFieldName>"}}},
/// where a type spec is [list Of ]<type>[(<PARAMETER>=<value>,...)] and an empty value is written <PARAMETER>=.
/// AssertContract compares each class with the compiled class dictionary: the superclasses in order, whether the class
/// is abstract (it is not unless the contract says so), the set of properties (those inherited from % and Ens classes
/// left out), each property's collection and type, the parameters MAXLEN, SCALE, MINVAL, MAXVAL and %JSONFIELDNAME,
/// an initial value of 0 on every %Boolean, its SQL field name when the contract names one, and the set of indexes.
Class OcuTalon.Test.Contract Extends %UnitTest.TestCase [ Abstract ]
{

/// The type parameters that a contract pins.
Parameter COMPARED = "%JSONFIELDNAME,MAXLEN,MAXVAL,MINVAL,SCALE";

/// The oracles that hold the contracts of Stories 0.4 and 0.5: each has its contracts in an XData block named Contracts.
Parameter ORACLES = "OcuTalon.Test.Msg.Contracts,OcuTalon.Test.Bridge.Contracts,OcuTalon.Test.Data.Tables,OcuTalon.Test.Live.Payloads";

/// Asserts, for each class of the XData block of this class, that it has exactly its contract.
Method AssertContract(xdataName As %String)
{
	Set contracts = ..ReadContracts(xdataName)
	Set iterator = contracts.%GetIterator()
	While iterator.%GetNext(.class, .contract) {
		Set problems = ..Compare(class, contract)
		Do $$$AssertEquals(problems, "", class_" has exactly its contract"_$Select(problems = "": "", 1: ": "_problems))
	}
}

/// Asserts that every message class of the contracts, those that extend Ens.MessageBody, shares the Ens.MessageBody
/// extent and sets no DEFAULTGLOBAL.
Method AssertMessageExtent(xdataName As %String)
{
	Set count = 0
	Set iterator = ..ReadContracts(xdataName).%GetIterator()
	While iterator.%GetNext(.class) {
		If '$ClassMethod(class, "%Extends", "Ens.MessageBody") Continue
		Set count = count + 1
		Set storage = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default")
		Do $$$AssertEquals($Parameter(class, "DEFAULTGLOBAL"), "", class_" sets no DEFAULTGLOBAL")
		Do $$$AssertEquals($Select($IsObject(storage): storage.DataLocation, 1: ""), "^Ens.MessageBodyD", class_" stores in the Ens.MessageBody extent")
	}
	Do $$$AssertTrue(count > 0, "the contracts hold message classes")
}

/// Asserts that class projects no SQL reserved word as its table name or as the name of one of its fields.
Method AssertSqlNames(class As %String)
{
	Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(class)
	If '$IsObject(compiled) {
		Do $$$AssertTrue(0, class_" is compiled")
		Quit
	}
	Set reserved = ""
	If $SYSTEM.SQL.IsReservedWord(compiled.SqlTableName) Set reserved = reserved_" table "_compiled.SqlTableName
	Set key = ""
	For {
		Set property = compiled.Properties.GetNext(.key)
		Quit:key=""
		If ..Inherited(property.Origin) Continue
		If $SYSTEM.SQL.IsReservedWord(property.SqlFieldName) Set reserved = reserved_" field "_property.SqlFieldName
	}
	Do $$$AssertEquals(reserved, "", class_" projects no SQL reserved word")
}

/// The contracts of the XData block, as a dynamic object.
ClassMethod ReadContracts(xdataName As %String) As %DynamicObject [ Private ]
{
	Quit ..Read(xdataName)
}

/// An XData block of JSON as a dynamic object: of this class, or of the class given.
ClassMethod Read(xdataName As %String, class As %String = {$ClassName()}) As %DynamicAbstractObject [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class_"||"_xdataName)
	Quit ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
}

/// The differences between a compiled class and its contract, as one line; "" when there are none.
ClassMethod Compare(class As %String, contract As %DynamicObject) As %String [ Private ]
{
	Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(class)
	If '$IsObject(compiled) Quit "the class is not compiled"
	Set problems = ""
	Set super = ..FullNames(compiled.Super)
	If super '= ..FullNames(contract.super) Set problems = problems_"the superclasses are '"_super_"', not '"_..FullNames(contract.super)_"'; "
	Set abstract = $Select(contract.%IsDefined("abstract"): contract.abstract, 1: 0)
	If compiled.Abstract '= abstract Set problems = problems_"the class is "_$Select(compiled.Abstract: "", 1: "not ")_"abstract; "

	Kill actual
	Set key = ""
	For {
		Set property = compiled.Properties.GetNext(.key)
		Quit:key=""
		If '..Inherited(property.Origin) Set actual(property.Name) = property
	}
	Set iterator = contract.props.%GetIterator()
	While iterator.%GetNext(.name, .spec) {
		If '$Data(actual(name)) {
			Set problems = problems_"property "_name_" is missing; "
			Continue
		}
		Set problems = problems_..CompareProperty(actual(name), spec)
		Kill actual(name)
	}
	Set name = ""
	For {
		Set name = $Order(actual(name))
		Quit:name=""
		Set problems = problems_"property "_name_" is not in the contract; "
	}

	If contract.%IsDefined("sql") {
		Set iterator = contract.sql.%GetIterator()
		While iterator.%GetNext(.name, .field) {
			Set property = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_name)
			If '$IsObject(property) || (property.SqlFieldName '= field) Set problems = problems_"property "_name_" is not projected as "_field_"; "
		}
	}

	Kill actual
	Set key = ""
	For {
		Set index = compiled.Indices.GetNext(.key)
		Quit:key=""
		If index.IdKey || ..Inherited(index.Origin) Continue
		Set actual(index.Name) = $Translate(index.Properties, " ", "")_$Select(index.Unique: " unique", 1: "")
	}
	If contract.%IsDefined("indexes") {
		Set iterator = contract.indexes.%GetIterator()
		While iterator.%GetNext(.name, .spec) {
			If '$Data(actual(name)) {
				Set problems = problems_"index "_name_" is missing; "
			} ElseIf actual(name) '= spec {
				Set problems = problems_"index "_name_" is on '"_actual(name)_"', not '"_spec_"'; "
			}
			Kill actual(name)
		}
	}
	Set name = ""
	For {
		Set name = $Order(actual(name))
		Quit:name=""
		Set problems = problems_"index "_name_" is not in the contract; "
	}
	Quit problems
}

/// The differences between a compiled property and a type spec, as one line.
ClassMethod CompareProperty(property As %Dictionary.CompiledProperty, spec As %String) As %String [ Private ]
{
	Set collection = ""
	If $Extract(spec, 1, 8) = "list Of " {
		Set collection = "list"
		Set spec = $Extract(spec, 9, *)
	}
	Set type = $Piece(spec, "(", 1)
	Set arguments = $Piece($Piece(spec, "(", 2), ")", 1)
	Kill expected
	For i = 1:1:$Length(arguments, ",") {
		Set pair = $Piece(arguments, ",", i)
		If pair '= "" Set expected($Piece(pair, "=", 1)) = $Piece(pair, "=", 2, *)
	}
	Set problems = ""
	Set name = property.Name
	If property.Collection '= collection Set problems = problems_name_" has collection '"_property.Collection_"', not '"_collection_"'; "
	If property.Type '= ..FullName(type) Set problems = problems_name_" has type "_property.Type_", not "_type_"; "
	Set parameters = $ListFromString(..#COMPARED)
	Set position = 0
	While $ListNext(parameters, position, parameter) {
		Set value = property.Parameters.GetAt(parameter)
		If value '= $Get(expected(parameter)) Set problems = problems_name_" has "_parameter_" '"_value_"', not '"_$Get(expected(parameter))_"'; "
	}
	If (property.Type = "%Library.Boolean") && (property.InitialExpression '= 0) Set problems = problems_name_" has no initial value 0; "
	Quit problems
}

/// The full name of a system class written with its short name: %String is %Library.String.
ClassMethod FullName(name As %String) As %String [ Private ]
{
	Quit $Select(($Extract(name) = "%") && (name '[ "."): "%Library."_$Extract(name, 2, *), 1: name)
}

/// A comma list of class names, each in its full name.
ClassMethod FullNames(names As %String) As %String [ Private ]
{
	Set result = ""
	For i = 1:1:$Length(names, ",") {
		Set result = result _ $Select(i > 1: ",", 1: "") _ ..FullName($ZStrip($Piece(names, ",", i), "<>W"))
	}
	Quit result
}

/// 1 for a member that comes from a % class or an Ens class.
ClassMethod Inherited(origin As %String) As %Boolean [ Private ]
{
	Quit ($Extract(origin) = "%") || ($Extract(origin, 1, 4) = "Ens.")
}

}
