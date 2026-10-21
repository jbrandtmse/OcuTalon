/// The private-data check that ends every start (AD-3, AD-23). It fails, naming the first offender, unless:
///   - a sample global under each private mapping resolves to OCUTALON_PRIVATE;
///   - every ^OcuTalonP. and ^OcuTalonBP. storage global of a compiled OcuTalon class resolves there too;
///   - OCUTALON_DATA holds no global with a private prefix.
Class OcuTalon.Install.Step.PrivateData Extends OcuTalon.Install.Step
{

Parameter PRIVATEDATABASE = "OCUTALON_PRIVATE";

Parameter DATADATABASE = "OCUTALON_DATA";

/// One global name under each private mapping, without the caret.
Parameter SAMPLES = "OcuTalonP.Zz,OcuTalonBP.Zz,AI.Agent.SessionD,IRIS.IF.Zz";

/// The prefixes of private globals, without the caret. OCUTALON_DATA holds none of them.
Parameter PREFIXES = "OcuTalonP.,OcuTalonBP.,AI.Agent.Session,IRIS.IF.";

ClassMethod Run() As %Status
{
	Set sc = ..StorageGlobals(.storage)
	If $$$ISERR(sc) Quit sc
	Quit ..Check($Namespace, .storage)
}

/// storage(global) = the class, for each storage global (no caret, no subscripts) of a compiled OcuTalon class
/// that starts with OcuTalonP. or OcuTalonBP.
ClassMethod StorageGlobals(Output storage) As %Status
{
	Kill storage
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT parent->Name, DataLocation, IndexLocation, IdLocation, StreamLocation FROM %Dictionary.CompiledStorage WHERE parent->Name %STARTSWITH 'OcuTalon.'")
	If $$$ISERR(sc) Quit sc
	Set result = statement.%Execute()
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Reading the storage definitions failed: "_result.%Message)
	While result.%Next() {
		For column = 2:1:5 {
			Set location = result.%GetData(column)
			If $Extract(location) '= "^" Continue
			Set global = $Piece($Piece(location, "(", 1), "^", 2)
			If ($Extract(global, 1, 10) = "OcuTalonP.") || ($Extract(global, 1, 11) = "OcuTalonBP.") {
				Set storage(global) = result.%GetData(1)
			}
		}
	}
	Quit $SYSTEM.Status.OK()
}

/// Reads the database directories from the configuration, in %SYS, and runs the three confirmations in namespace.
ClassMethod Check(namespace As %String, ByRef storage) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = ..Directory(..#PRIVATEDATABASE, .private)
	If $$$ISOK(sc) Set sc = ..Directory(..#DATADATABASE, .data)
	If $$$ISERR(sc) Quit sc

	Set samples = $ListFromString(..#SAMPLES)
	Set position = 0
	While $ListNext(samples, position, global) {
		Set storage(global) = "the mapping sample"
	}
	Set global = ""
	For {
		Set global = $Order(storage(global))
		Quit:global=""
		Set resolved = ##class(%SYS.Namespace).GetGlobalDest(namespace, "^"_global)
		If ($Piece(resolved, "^", 1) '= "") || (##class(%File).NormalizeDirectory($Piece(resolved, "^", 2)) '= private) {
			Quit
		}
	}
	If global '= "" {
		Quit $SYSTEM.Status.Error(5001, "Private global ^"_global_" ("_storage(global)_") resolves to '"_resolved_"', not to "_..#PRIVATEDATABASE_" ("_private_")")
	}

	Set reference = "^^"_data
	Set prefixes = $ListFromString(..#PREFIXES)
	Set found = $Order(^$|reference|GLOBAL(""))
	While found '= "" {
		Set position = 0
		While $ListNext(prefixes, position, prefix) {
			If $Extract(found, 2, $Length(prefix) + 1) = prefix {
				Return $SYSTEM.Status.Error(5001, "Database "_..#DATADATABASE_" holds the private global "_found)
			}
		}
		Set found = $Order(^$|reference|GLOBAL(found))
	}
	Quit $SYSTEM.Status.OK()
}

/// The directory of a database, with a trailing slash, as the configuration holds it.
ClassMethod Directory(database As %String, Output directory As %String) As %Status [ Private ]
{
	Set sc = ##class(Config.Databases).Get(database, .properties)
	If $$$ISERR(sc) Quit sc
	Set directory = ##class(%File).NormalizeDirectory(properties("Directory"))
	Quit $SYSTEM.Status.OK()
}

}
