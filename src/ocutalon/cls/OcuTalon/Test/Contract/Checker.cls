/// Tests of the comparison in Test.Contract itself (QA). Every contract test of Story 0.4 passes when Test.Contract.Compare
/// reports nothing, so a comparison that stopped looking at one kind of difference would leave all of them green.
///   - TestOracleDetectsEachKindOfDifference compiles a fixture class, checks that its own contract passes, and then
///     changes the contract one way at a time (a property left out, one the class lacks, a renamed property, another type,
///     MAXLEN, SCALE, MINVAL, MAXVAL, collection, JSON name, superclasses, abstract, an index missing, extra, renamed, with
///     another uniqueness or other properties, an SQL name): each must be reported;
///   - TestBooleanInitialValue, TestAbstractClass and TestUncompiledClass cover the checks that need another fixture;
///   - TestEveryPinnedPartOfEveryContractIsDetected does the same for the real contracts: for each class of the three
///     oracles, dropping, renaming or retyping each property, dropping, renaming or changing each index, changing the
///     superclasses and flipping the abstract flag must each be reported. The comparison is symmetric, so a class that lost
///     or renamed a property fails in the same way.
/// The fixture classes are named OcuTalon.Test.ZzContract<n><Kind>, with n from ^OcuTalonTest("ContractChecker","n"),
/// which is never reset. Every class with that prefix is deleted in OnBeforeAllTests and again in OnAfterAllTests.
Class OcuTalon.Test.Contract.Checker Extends OcuTalon.Test.Contract
{

/// The start of the name of every fixture class.
Parameter PREFIX = "OcuTalon.Test.ZzContract";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ..RemoveFixtures()
	Set ..Number = $Increment(^OcuTalonTest("ContractChecker", "n"))
	Set fixtures = ..Read("Fixtures")
	Set iterator = fixtures.%GetIterator()
	While iterator.%GetNext(.kind, .lines) {
		Set text = ""
		Set line = lines.%GetIterator()
		While line.%GetNext(, .value) {
			Set text = text _ $Replace(value, "%CLASS%", ..FixtureName(kind)) _ $Char(10)
		}
		Set sc = ##class(%Compiler.UDL.TextServices).SetTextFromString($Namespace, ..FixtureName(kind), text, $Char(10))
		If $$$ISOK(sc) Set sc = $SYSTEM.OBJ.Compile(..FixtureName(kind), "ck-d")
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveFixtures()
	Quit $$$OK
}

/// The fixture passes its own contract, and each change to the contract is reported.
Method TestOracleDetectsEachKindOfDifference()
{
	Set base = ..Read("Contracts").Plain
	Do $$$AssertEquals(..Compare(..FixtureName("Plain"), base), "", "the control: the fixture has exactly its contract")
	Set count = 0
	Set iterator = ..Read("Defects").%GetIterator()
	While iterator.%GetNext(, .defect) {
		Set count = count + 1
		Set contract = ..Copy(base)
		Set ops = defect.ops.%GetIterator()
		While ops.%GetNext(, .op) {
			Do ..Apply(contract, op)
		}
		Do $$$AssertTrue(contract.%ToJSON() '= base.%ToJSON(), defect.what_": the contract is changed")
		Set problems = ..Compare(..FixtureName("Plain"), contract)
		Set expects = defect.expect.%GetIterator()
		While expects.%GetNext(, .expected) {
			Do $$$AssertTrue(..Reports(problems, expected), defect.what_" is reported as '"_expected_"': "_problems)
		}
	}
	Do $$$AssertTrue(count >= 27, "the defects are read: "_count)
}

/// A %Boolean without an initial value 0 is reported although its contract matches.
Method TestBooleanInitialValue()
{
	Set contract = ..Read("Contracts").NoInitial
	Set problems = ..Compare(..FixtureName("NoInitial"), contract)
	Do $$$AssertTrue(..Reports(problems, "Flag has no initial value 0"), "a %Boolean without an initial value 0 is reported: "_problems)
}

/// An abstract class is reported when the contract does not say so, and passes when it does.
Method TestAbstractClass()
{
	Set contract = ..Read("Contracts").Abstract
	Do $$$AssertEquals(..Compare(..FixtureName("Abstract"), contract), "", "an abstract class passes a contract that says abstract")
	Do contract.%Remove("abstract")
	Do $$$AssertTrue(..Reports(..Compare(..FixtureName("Abstract"), contract), "the class is abstract"), "an abstract class is reported when the contract does not say so")
}

/// A class that is not compiled is reported.
Method TestUncompiledClass()
{
	Set problems = ..Compare(..#PREFIX_"NoSuchClass", ..Read("Contracts").Plain)
	Do $$$AssertEquals(problems, "the class is not compiled", "a class that does not exist is reported")
}

/// For every class of the three oracles, each change to a pinned property, index, the superclasses or the abstract flag
/// is reported by the comparison.
Method TestEveryPinnedPartOfEveryContractIsDetected()
{
	Set classes = 0
	Set parts = 0
	Set oracles = $ListFromString(..#ORACLES)
	Set position = 0
	While $ListNext(oracles, position, oracle) {
		Set iterator = ..Read("Contracts", oracle).%GetIterator()
		While iterator.%GetNext(.class, .contract) {
			Set classes = classes + 1
			Set missed = ..Undetected(class, contract, .count)
			Set parts = parts + count
			Do $$$AssertEquals(missed, "", class_": every change to its contract is reported"_$Select(missed = "": "", 1: "; not reported:"_missed))
		}
	}
	Do $$$AssertTrue(classes >= 47, "at least 47 contract classes are checked: "_classes)
	Do $$$AssertTrue(parts >= 700, "at least 700 pinned parts are changed: "_parts)
}

/// The changes to the contract of one class that the comparison does not report, as " <change> <name>" for each; the
/// number of changes made is returned in count.
ClassMethod Undetected(class As %String, contract As %DynamicObject, Output count As %Integer) As %String [ Private ]
{
	Set count = 0
	Set missed = ""
	Set names = ..Keys(contract.props)
	Set position = 0
	While $ListNext(names, position, name) {
		Set spec = contract.props.%Get(name)
		Set count = count + 3
		Set copy = ..Copy(contract)
		Do copy.props.%Remove(name)
		If '..Reports(..Compare(class, copy), "property "_name_" is not in the contract") Set missed = missed_" drop "_name
		Set copy = ..Copy(contract)
		Do copy.props.%Remove(name)
		Do copy.props.%Set("ZzRenamed", spec)
		Set problems = ..Compare(class, copy)
		If '..Reports(problems, "property "_name_" is not in the contract") || '..Reports(problems, "property ZzRenamed is missing") Set missed = missed_" rename "_name
		Set copy = ..Copy(contract)
		Do copy.props.%Set(name, $Select($Extract(spec, 1, 8) = "%Integer": "%String(MAXLEN=22)", 1: "%Integer"))
		If '..Reports(..Compare(class, copy), name_" has ") Set missed = missed_" retype "_name
	}
	If contract.%IsDefined("indexes") {
		Set names = ..Keys(contract.indexes)
		Set position = 0
		While $ListNext(names, position, name) {
			Set spec = contract.indexes.%Get(name)
			Set count = count + 3
			Set copy = ..Copy(contract)
			Do copy.indexes.%Remove(name)
			If '..Reports(..Compare(class, copy), "index "_name_" is not in the contract") Set missed = missed_" drop index "_name
			Set copy = ..Copy(contract)
			Do copy.indexes.%Remove(name)
			Do copy.indexes.%Set("ZzRenamed", spec)
			Set problems = ..Compare(class, copy)
			If '..Reports(problems, "index "_name_" is not in the contract") || '..Reports(problems, "index ZzRenamed is missing") Set missed = missed_" rename index "_name
			Set copy = ..Copy(contract)
			Do copy.indexes.%Set(name, $Select(spec [ " unique": $Piece(spec, " unique", 1), 1: spec_" unique"))
			If '..Reports(..Compare(class, copy), "index "_name_" is on ") Set missed = missed_" change index "_name
		}
	}
	Set count = count + 2
	Set copy = ..Copy(contract)
	Do copy.%Set("super", "%RegisteredObject")
	If '..Reports(..Compare(class, copy), "the superclasses are ") Set missed = missed_" superclasses"
	Set copy = ..Copy(contract)
	Do copy.%Set("abstract", '$Select(contract.%IsDefined("abstract"): contract.abstract, 1: 0))
	If '..Reports(..Compare(class, copy), "the class is ") Set missed = missed_" abstract"
	Quit missed
}

/// Changes a contract: one operation of a defect.
ClassMethod Apply(contract As %DynamicObject, op As %DynamicObject) [ Private ]
{
	Set name = op.name
	If op.op = "dropProp" {
		Do contract.props.%Remove(name)
	} ElseIf (op.op = "addProp") || (op.op = "setProp") {
		Do contract.props.%Set(name, op.spec)
	} ElseIf op.op = "renameProp" {
		Set spec = contract.props.%Get(name)
		Do contract.props.%Remove(name)
		Do contract.props.%Set(op.to, spec)
	} ElseIf op.op = "setSuper" {
		Do contract.%Set("super", op.value)
	} ElseIf op.op = "setAbstract" {
		Do contract.%Set("abstract", op.value)
	} ElseIf op.op = "dropIndex" {
		Do contract.indexes.%Remove(name)
	} ElseIf (op.op = "addIndex") || (op.op = "setIndex") {
		Do contract.indexes.%Set(name, op.spec)
	} ElseIf op.op = "renameIndex" {
		Set spec = contract.indexes.%Get(name)
		Do contract.indexes.%Remove(name)
		Do contract.indexes.%Set(op.to, spec)
	} ElseIf op.op = "setSql" {
		Do contract.sql.%Set(name, op.value)
	} Else {
		$$$ThrowStatus($SYSTEM.Status.Error(5001, "unknown operation "_op.op))
	}
}

/// 1 when the problems line holds the text as one of its reports. A report starts at the start of the line or after "; ",
/// so that "Ref has " is not found in "TraceRef has ".
ClassMethod Reports(problems As %String, text As %String) As %Boolean [ Private ]
{
	Quit ("; "_problems) [ ("; "_text)
}

/// A copy of a contract.
ClassMethod Copy(contract As %DynamicObject) As %DynamicObject [ Private ]
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(contract.%ToJSON())
}

/// The keys of a dynamic object, as a list.
ClassMethod Keys(object As %DynamicObject) As %List [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys _ $ListBuild(key)
	}
	Quit keys
}

/// The name of the fixture class of a kind.
Method FixtureName(kind As %String) As %String [ Private ]
{
	Quit ..#PREFIX_..Number_kind
}

/// Deletes every fixture class, this run's and those of a run that was cut short.
ClassMethod RemoveFixtures() [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT ID FROM %Dictionary.ClassDefinition WHERE ID %STARTSWITH ?")
	If $$$ISERR(sc) Quit
	Set result = statement.%Execute(..#PREFIX)
	Kill names
	While result.%Next() {
		Set names(result.%GetData(1)) = ""
	}
	Set name = ""
	For {
		Set name = $Order(names(name))
		Quit:name=""
		Do $SYSTEM.OBJ.Delete(name, "-d")
	}
}

/// The source of each fixture class, one line per element; %CLASS% is the class name.
XData Fixtures [ MimeType = application/json ]
{
{
 "Plain": [
  "Class %CLASS% Extends (%Persistent, %JSON.Adaptor)",
  "{",
  "Property Name As %String(MAXLEN = 22);",
  "Property Amount As %Numeric(MAXVAL = 1, MINVAL = 0, SCALE = 2);",
  "Property Flag As %Boolean [ InitialExpression = 0 ];",
  "Property Items As list Of %String(MAXLEN = 1000);",
  "Property Input As %String(MAXLEN = \"\") [ SqlFieldName = InputText ];",
  "Property Wire As %String(%JSONFIELDNAME = \"wireName\", MAXLEN = 32);",
  "Index NameIndex On Name [ Unique ];",
  "Index AmountIndex On Amount;",
  "}"
 ],
 "NoInitial": [
  "Class %CLASS% Extends %Persistent",
  "{",
  "Property Flag As %Boolean;",
  "}"
 ],
 "Abstract": [
  "Class %CLASS% Extends %RegisteredObject [ Abstract ]",
  "{",
  "Property Name As %String(MAXLEN = 22);",
  "}"
 ]
}
}

/// The contract of each fixture, in the form of the oracles.
XData Contracts [ MimeType = application/json ]
{
{
 "Plain": {
  "super": "%Persistent,%JSON.Adaptor",
  "props": {
   "Name": "%String(MAXLEN=22)",
   "Amount": "%Numeric(MAXVAL=1,MINVAL=0,SCALE=2)",
   "Flag": "%Boolean",
   "Items": "list Of %String(MAXLEN=1000)",
   "Input": "%String(MAXLEN=)",
   "Wire": "%String(%JSONFIELDNAME=wireName,MAXLEN=32)"
  },
  "indexes": {
   "NameIndex": "Name unique",
   "AmountIndex": "Amount"
  },
  "sql": {
   "Input": "InputText"
  }
 },
 "NoInitial": {
  "super": "%Persistent",
  "props": {
   "Flag": "%Boolean"
  }
 },
 "Abstract": {
  "super": "%RegisteredObject",
  "abstract": 1,
  "props": {
   "Name": "%String(MAXLEN=22)"
  }
 }
}
}

/// The changes to the Plain contract: what changes, the operations, and the reports that each must cause.
XData Defects [ MimeType = application/json ]
{
[
 {"what": "a property that the oracle leaves out", "ops": [{"op": "dropProp", "name": "Flag"}], "expect": ["property Flag is not in the contract"]},
 {"what": "a property that the class lacks", "ops": [{"op": "addProp", "name": "Ghost", "spec": "%Integer"}], "expect": ["property Ghost is missing"]},
 {"what": "a renamed property", "ops": [{"op": "renameProp", "name": "Name", "to": "Title"}], "expect": ["property Title is missing", "property Name is not in the contract"]},
 {"what": "another type", "ops": [{"op": "setProp", "name": "Amount", "spec": "%Integer"}], "expect": ["Amount has type"]},
 {"what": "a longer MAXLEN", "ops": [{"op": "setProp", "name": "Name", "spec": "%String(MAXLEN=23)"}], "expect": ["Name has MAXLEN '22', not '23'"]},
 {"what": "no MAXLEN where the class limits it", "ops": [{"op": "setProp", "name": "Name", "spec": "%String(MAXLEN=)"}], "expect": ["Name has MAXLEN '22', not ''"]},
 {"what": "a limit where the class has none", "ops": [{"op": "setProp", "name": "Input", "spec": "%String(MAXLEN=50)"}], "expect": ["Input has MAXLEN '', not '50'"]},
 {"what": "another SCALE", "ops": [{"op": "setProp", "name": "Amount", "spec": "%Numeric(MAXVAL=1,MINVAL=0,SCALE=3)"}], "expect": ["Amount has SCALE '2', not '3'"]},
 {"what": "another MAXVAL", "ops": [{"op": "setProp", "name": "Amount", "spec": "%Numeric(MAXVAL=2,MINVAL=0,SCALE=2)"}], "expect": ["Amount has MAXVAL '1', not '2'"]},
 {"what": "another MINVAL", "ops": [{"op": "setProp", "name": "Amount", "spec": "%Numeric(MAXVAL=1,MINVAL=1,SCALE=2)"}], "expect": ["Amount has MINVAL '0', not '1'"]},
 {"what": "a list where the class has a single value", "ops": [{"op": "setProp", "name": "Name", "spec": "list Of %String(MAXLEN=22)"}], "expect": ["Name has collection '', not 'list'"]},
 {"what": "a single value where the class has a list", "ops": [{"op": "setProp", "name": "Items", "spec": "%String(MAXLEN=1000)"}], "expect": ["Items has collection 'list', not ''"]},
 {"what": "another JSON name", "ops": [{"op": "setProp", "name": "Wire", "spec": "%String(%JSONFIELDNAME=wire,MAXLEN=32)"}], "expect": ["Wire has %JSONFIELDNAME 'wireName', not 'wire'"]},
 {"what": "no JSON name where the class sets one", "ops": [{"op": "setProp", "name": "Wire", "spec": "%String(MAXLEN=32)"}], "expect": ["Wire has %JSONFIELDNAME 'wireName', not ''"]},
 {"what": "fewer superclasses", "ops": [{"op": "setSuper", "value": "%Persistent"}], "expect": ["the superclasses are"]},
 {"what": "superclasses in another order", "ops": [{"op": "setSuper", "value": "%JSON.Adaptor,%Persistent"}], "expect": ["the superclasses are"]},
 {"what": "an abstract class where the class is not", "ops": [{"op": "setAbstract", "value": 1}], "expect": ["the class is not abstract"]},
 {"what": "an index that the class lacks", "ops": [{"op": "addIndex", "name": "GhostIndex", "spec": "Name"}], "expect": ["index GhostIndex is missing"]},
 {"what": "an index that the oracle leaves out", "ops": [{"op": "dropIndex", "name": "AmountIndex"}], "expect": ["index AmountIndex is not in the contract"]},
 {"what": "a renamed index", "ops": [{"op": "renameIndex", "name": "NameIndex", "to": "NameKey"}], "expect": ["index NameKey is missing", "index NameIndex is not in the contract"]},
 {"what": "a unique index that the oracle calls plain", "ops": [{"op": "setIndex", "name": "NameIndex", "spec": "Name"}], "expect": ["index NameIndex is on 'Name unique', not 'Name'"]},
 {"what": "a plain index that the oracle calls unique", "ops": [{"op": "setIndex", "name": "AmountIndex", "spec": "Amount unique"}], "expect": ["index AmountIndex is on 'Amount', not 'Amount unique'"]},
 {"what": "an index on other properties", "ops": [{"op": "setIndex", "name": "AmountIndex", "spec": "Name"}], "expect": ["index AmountIndex is on 'Amount', not 'Name'"]},
 {"what": "no indexes in the oracle for a class that has them", "ops": [{"op": "dropIndex", "name": "AmountIndex"}, {"op": "dropIndex", "name": "NameIndex"}], "expect": ["index AmountIndex is not in the contract", "index NameIndex is not in the contract"]},
 {"what": "another SQL field name", "ops": [{"op": "setSql", "name": "Input", "value": "Input"}], "expect": ["property Input is not projected as Input"]},
 {"what": "an SQL field name for a property that does not exist", "ops": [{"op": "setSql", "name": "Ghost", "value": "GhostField"}], "expect": ["property Ghost is not projected as GhostField"]},
 {"what": "two changes at once", "ops": [{"op": "dropProp", "name": "Flag"}, {"op": "setProp", "name": "Name", "spec": "%String(MAXLEN=23)"}], "expect": ["property Flag is not in the contract", "Name has MAXLEN '22', not '23'"]}
]
}

}
