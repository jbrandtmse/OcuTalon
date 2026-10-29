Include (Ensemble, %sySecurity)

/// The fixture of the evaluation set's test feed (Story 9.9; AD-22, CON-3): it installs OcuTalon.Test.Eval.Feed in a namespace of its own, sends the
/// feed's nine cases, reads their keys, records them, and removes everything it made. It is not a test case (it has no test method).
///   - THROWAWAYS ONLY. Install refuses, writes nothing and names the reason unless the folder of the evaluation set (Eval.In FOLDER, which only
///     docker/tests/compose.throwaway.yml mounts) exists. Its only callers are Test.Eval.Record and docker/tests/record-eval.sh feed, each in a
///     throwaway of its own. Nothing in the product's install, the judges' compose file or the demo host names it.
///   - What Install makes, in this order: the resource RESOURCE (no public permission); the folder below the manager directory and the database
///     DATABASE in it, with its Config.Databases entry; the namespace NAMESPACE (globals and routines in DATABASE); the package mapping of CODEPACKAGE
///     from CODEDATABASE, which makes this class, the feed's production and the classes below them visible there; Interoperability in the namespace
///     (EnableNamespace with the install flag); the one grant, Read on RESOURCE added to the Resources of the service role (Install.Step.Users
///     SERVICEROLE), nothing else and never %All; then the production, started, with every enabled item that has a pool alive. A leftover of an earlier
///     run is removed first.
///   - What Remove removes, each step skipped when there is nothing to remove: the production (stopped), the web applications of the namespace, the
///     namespace, the Interoperability marker and role, every database entry at or below the folder with its files and the folder, and the resource.
///     Deleting the resource also takes the grant out of the role (Security.Resources.Delete). It is idempotent and its status says what it could not
///     remove; Leftovers names what still exists.
///   - Cases (XData) holds the nine cases: each has a name, a held-out flag, a description, the expectation of the diagnosis, the item the failures are
///     at, the message class and three messages of fixed synthetic values, and the markers (errorHas) that every recorded error must hold. Start sends
///     them, one batch for each, with a reference of its own as the SuperSession of the batch's messages. Keys waits for a case's failures and gives
///     their reader keys. Record is the driver's entry: install, send, capture every case with Eval.Record into a folder, check that Build gives the
///     capture's own pack from each written file, and always remove the feed.
///   - The code that runs in %SYS or NAMESPACE calls no OcuTalon class outside the feed.
Class OcuTalon.Test.Eval.Feed.Fixture
{

/// The namespace of the feed.
Parameter NAMESPACE = "EVALFEED";

/// The database of the feed: globals and routines.
Parameter DATABASE = "EVALFEED_DATA";

/// The resource of the database.
Parameter RESOURCE = "%DB_EVALFEED_DATA";

/// The production of the feed.
Parameter PRODUCTION = "OcuTalon.Test.Eval.Feed";

/// The package that the namespace maps from CODEDATABASE.
Parameter CODEPACKAGE = "OcuTalon.Test.Eval";

Parameter CODEDATABASE = "OCUTALON_CODE";

/// The item that takes the batches.
Parameter SOURCEITEM = "FeedIn";

/// The seconds Install waits for the production to run and Keys waits for a case's failures.
Parameter WAITSECONDS = 60;

/// The seconds the production gets to stop.
Parameter STOPSECONDS = 10;

/// The start of the refusal of Install.
Parameter REFUSAL = "Only a throwaway test stack installs the test feed: ";

/// The nine cases, in name order: each has the expectation of the diagnosis, the item its failures are at, the class and the three messages sent to it,
/// and the markers (errorHas) that every recorded error must hold.
XData Cases [ MimeType = application/json ]
{
[
  {
    "name": "carrier-host-not-found",
    "heldOut": true,
    "description": "Three shipments from the test feed sent to the carrier booking service at carrier.example, a host that does not exist; the booking operation cannot connect.",
    "expectation": {"causeCategory": "connection_failure", "elementAtFault": "CarrierBookingOut", "fixKind": ""},
    "item": "CarrierBookingOut",
    "messageClass": "OcuTalon.Test.Eval.Feed.Shipment",
    "messages": [
      {"ShipmentId": "SH-3001", "OrderNumber": "ON-3001", "ShippedAt": "2026-10-16 09:30:00", "Weight": "12.5", "Carrier": "CARRIER-A"},
      {"ShipmentId": "SH-3002", "OrderNumber": "ON-3002", "ShippedAt": "2026-10-16 09:45:00", "Weight": "8.0", "Carrier": "CARRIER-A"},
      {"ShipmentId": "SH-3003", "OrderNumber": "ON-3003", "ShippedAt": "2026-10-16 10:00:00", "Weight": "20.5", "Carrier": "CARRIER-B"}
    ],
    "errorHas": ["#6059", "carrier.example"]
  },
  {
    "name": "claims-archive-internal-error",
    "heldOut": false,
    "description": "Three claims from the test feed sent to the archive operation, which fails with an internal ObjectScript error on every claim, whatever the claim holds.",
    "expectation": {"causeCategory": "unknown", "elementAtFault": "ClaimsToArchive", "fixKind": ""},
    "item": "ClaimsToArchive",
    "messageClass": "OcuTalon.Test.Eval.Feed.Claim",
    "messages": [
      {"ClaimId": "CL-6001", "MemberId": "M-60001", "ServiceDate": "2026-10-15", "Amount": "125.40", "PayerCode": "PAYER-A"},
      {"ClaimId": "CL-6002", "MemberId": "M-60002", "ServiceDate": "2026-10-15", "Amount": "80.00", "PayerCode": "PAYER-A"},
      {"ClaimId": "CL-6003", "MemberId": "M-60003", "ServiceDate": "2026-10-16", "Amount": "310.25", "PayerCode": "PAYER-B"}
    ],
    "errorHas": ["<UNDEFINED>"]
  },
  {
    "name": "claims-member-missing",
    "heldOut": false,
    "description": "Three claims from the test feed with the member identifier left empty; the billing operation requires it.",
    "expectation": {"causeCategory": "validation_error", "elementAtFault": "MemberId", "fixKind": ""},
    "item": "ClaimsToBilling",
    "messageClass": "OcuTalon.Test.Eval.Feed.Claim",
    "messages": [
      {"ClaimId": "CL-4001", "MemberId": "", "ServiceDate": "2026-10-15", "Amount": "125.40", "PayerCode": "PAYER-A"},
      {"ClaimId": "CL-4002", "MemberId": "", "ServiceDate": "2026-10-15", "Amount": "80.00", "PayerCode": "PAYER-A"},
      {"ClaimId": "CL-4003", "MemberId": "", "ServiceDate": "2026-10-16", "Amount": "310.25", "PayerCode": "PAYER-B"}
    ],
    "errorHas": ["#5659", "MemberId(128@"]
  },
  {
    "name": "lab-results-refused",
    "heldOut": false,
    "description": "Three lab results from the test feed sent to the lab results service on 127.0.0.1 port 9382, where nothing listens; the connection is refused.",
    "expectation": {"causeCategory": "connection_failure", "elementAtFault": "LabResultsOut", "fixKind": ""},
    "item": "LabResultsOut",
    "messageClass": "OcuTalon.Test.Eval.Feed.LabResult",
    "messages": [
      {"ResultId": "LR-2001", "PatientRef": "PT-2001", "TestCode": "GLU", "ResultValue": "7.5", "Units": "mmol/L"},
      {"ResultId": "LR-2002", "PatientRef": "PT-2002", "TestCode": "GLU", "ResultValue": "5.1", "Units": "mmol/L"},
      {"ResultId": "LR-2003", "PatientRef": "PT-2003", "TestCode": "HBA", "ResultValue": "6.2", "Units": "percent"}
    ],
    "errorHas": ["#6059", "127.0.0.1:9382"]
  },
  {
    "name": "payer-unavailable",
    "heldOut": false,
    "description": "Three claims from the test feed sent to the payer's claims service, which answers HTTP 503 Service Unavailable.",
    "expectation": {"causeCategory": "partner_outage", "elementAtFault": "PayerClaimsOut", "fixKind": ""},
    "item": "PayerClaimsOut",
    "messageClass": "OcuTalon.Test.Eval.Feed.Claim",
    "messages": [
      {"ClaimId": "CL-5001", "MemberId": "M-50001", "ServiceDate": "2026-10-15", "Amount": "125.40", "PayerCode": "PAYER-A"},
      {"ClaimId": "CL-5002", "MemberId": "M-50002", "ServiceDate": "2026-10-15", "Amount": "80.00", "PayerCode": "PAYER-A"},
      {"ClaimId": "CL-5003", "MemberId": "M-50003", "ServiceDate": "2026-10-16", "Amount": "310.25", "PayerCode": "PAYER-B"}
    ],
    "errorHas": ["ErrHTTPStatus", "503"]
  },
  {
    "name": "reference-lab-server-error",
    "heldOut": false,
    "description": "Three lab results from the test feed sent to the reference lab's service, which answers HTTP 500 Internal Server Error.",
    "expectation": {"causeCategory": "partner_outage", "elementAtFault": "ReferenceLabOut", "fixKind": ""},
    "item": "ReferenceLabOut",
    "messageClass": "OcuTalon.Test.Eval.Feed.LabResult",
    "messages": [
      {"ResultId": "LR-3001", "PatientRef": "PT-3001", "TestCode": "NA", "ResultValue": "139", "Units": "mmol/L"},
      {"ResultId": "LR-3002", "PatientRef": "PT-3002", "TestCode": "K", "ResultValue": "4.2", "Units": "mmol/L"},
      {"ResultId": "LR-3003", "PatientRef": "PT-3003", "TestCode": "CL", "ResultValue": "101", "Units": "mmol/L"}
    ],
    "errorHas": ["ErrHTTPStatus", "500"]
  },
  {
    "name": "results-decimal-comma",
    "heldOut": false,
    "description": "Three lab results from the test feed with the result value written with a decimal comma (7,5); the chart operation expects a decimal point.",
    "expectation": {"causeCategory": "data_format_change", "elementAtFault": "ResultValue", "fixKind": "repair_resend"},
    "item": "ResultsToChart",
    "messageClass": "OcuTalon.Test.Eval.Feed.LabResult",
    "messages": [
      {"ResultId": "LR-1001", "PatientRef": "PT-1001", "TestCode": "GLU", "ResultValue": "7,5", "Units": "mmol/L"},
      {"ResultId": "LR-1002", "PatientRef": "PT-1002", "TestCode": "GLU", "ResultValue": "12,1", "Units": "mmol/L"},
      {"ResultId": "LR-1003", "PatientRef": "PT-1003", "TestCode": "HBA", "ResultValue": "4,0", "Units": "percent"}
    ],
    "errorHas": ["#7207", "ResultValue"]
  },
  {
    "name": "returns-negative-weight",
    "heldOut": true,
    "description": "Three returned shipments from the test feed with a negative weight (-2.5); the ledger operation accepts a weight of 0 or more.",
    "expectation": {"causeCategory": "validation_error", "elementAtFault": "Weight", "fixKind": ""},
    "item": "ReturnsToLedger",
    "messageClass": "OcuTalon.Test.Eval.Feed.Shipment",
    "messages": [
      {"ShipmentId": "SH-2001", "OrderNumber": "ON-2001", "ShippedAt": "2026-10-16 09:30:00", "Weight": "-2.5", "Carrier": "CARRIER-A"},
      {"ShipmentId": "SH-2002", "OrderNumber": "ON-2002", "ShippedAt": "2026-10-16 09:45:00", "Weight": "-1.0", "Carrier": "CARRIER-A"},
      {"ShipmentId": "SH-2003", "OrderNumber": "ON-2003", "ShippedAt": "2026-10-16 10:00:00", "Weight": "-0.5", "Carrier": "CARRIER-B"}
    ],
    "errorHas": ["#7204", "Weight"]
  },
  {
    "name": "shipments-epoch-time",
    "heldOut": false,
    "description": "Three shipments from the test feed with the shipping time written as seconds since 1970 (1792138500); the ledger operation expects a date and time.",
    "expectation": {"causeCategory": "data_format_change", "elementAtFault": "ShippedAt", "fixKind": "repair_resend"},
    "item": "ShipmentsToLedger",
    "messageClass": "OcuTalon.Test.Eval.Feed.Shipment",
    "messages": [
      {"ShipmentId": "SH-1001", "OrderNumber": "ON-1001", "ShippedAt": "1792138500", "Weight": "12.5", "Carrier": "CARRIER-A"},
      {"ShipmentId": "SH-1002", "OrderNumber": "ON-1002", "ShippedAt": "1792142100", "Weight": "8.0", "Carrier": "CARRIER-A"},
      {"ShipmentId": "SH-1003", "OrderNumber": "ON-1003", "ShippedAt": "1792145700", "Weight": "20.5", "Carrier": "CARRIER-B"}
    ],
    "errorHas": ["#7208", "ShippedAt"]
  }
]
}

/// The cases as a dynamic array, in the order of the XData (by name).
ClassMethod Definitions() As %DynamicArray
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Cases").Data)
}

/// The names of the cases, comma-separated, in name order.
ClassMethod Names() As %String
{
	Kill sorted
	Set iterator = ..Definitions().%GetIterator()
	While iterator.%GetNext(, .definition) {
		Set sorted(definition.name) = ""
	}
	Set names = "", name = ""
	For {
		Set name = $Order(sorted(name))
		If name = "" Quit
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Quit names
}

/// The definition of the case, or "" when no case has the name.
ClassMethod Definition(name As %String) As %DynamicObject
{
	Set found = ""
	Set iterator = ..Definitions().%GetIterator()
	While iterator.%GetNext(, .definition) {
		If definition.name = name {
			Set found = definition
			Quit
		}
	}
	Quit found
}

/// Installs the feed (see the class description) and starts its production. It refuses, and does nothing, when the folder does not exist: the
/// folder is the throwaway's mount of the evaluation set. Any leftover of an earlier run is removed first. The status is the first step that failed.
ClassMethod Install(folder As %String = {##class(OcuTalon.Eval.In).#FOLDER}) As %Status
{
	If '##class(%File).DirectoryExists(folder) Quit $$$ERROR($$$GeneralError, ..#REFUSAL_"the evaluation folder "_folder_" is not mounted here")
	Set sc = ..Remove()
	If $$$ISERR(sc) Quit sc
	Set sc = ..CreateSystem()
	If $$$ISERR(sc) Quit sc
	Quit ..StartProduction()
}

/// Removes everything Install made (see the class description). Idempotent. The status holds each step that failed, and an error naming what Leftovers
/// still finds.
ClassMethod Remove() As %Status
{
	Set sc = ..StopProduction()
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..RemoveSystem())
	Set left = ..Leftovers()
	If left '= "" Set sc = $SYSTEM.Status.AppendStatus(sc, $$$ERROR($$$GeneralError, "The test feed was not removed completely: "_left))
	Quit sc
}

/// What still exists of what Install made, comma-separated: namespace, database, directory, resource, marker, role, application and grant. "" when
/// nothing does.
ClassMethod Leftovers() As %String
{
	Set ns = ..#NAMESPACE, db = ..#DATABASE, resource = ..#RESOURCE
	Set directory = ..Directory()
	Set interopRole = $$$InteropNSRole(ns)
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set left = ""
	If ##class(Config.Namespaces).Exists(ns) Set left = left_",namespace"
	If ##class(Config.Databases).Exists(db) Set left = left_",database"
	If ##class(%File).DirectoryExists(directory) Set left = left_",directory"
	If ##class(Security.Resources).Exists(resource) Set left = left_",resource"
	If $Data(^%SYS("Ensemble", "InstalledNamespace", ns)) Set left = left_",marker"
	If ##class(Security.Roles).Exists(interopRole) Set left = left_",role"
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Security.Applications WHERE NameSpace = ?", ns)
	If rs.%Next() && rs.%GetData(1) Set left = left_",application"
	If ##class(Security.Roles).Exists(role) {
		Kill props
		If $$$ISOK(##class(Security.Roles).Get(role, .props)) && (("," _ $Get(props("Resources")) _ ",") [ ("," _ resource _ ":")) Set left = left_",grant"
	}
	Quit $Extract(left, 2, *)
}

/// The Resources of the service role, as the security database holds them ("" when the role does not exist).
ClassMethod RoleResources() As %String
{
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill props
	If '##class(Security.Roles).Exists(role) Quit ""
	If $$$ISERR(##class(Security.Roles).Get(role, .props)) Quit ""
	Quit $Get(props("Resources"))
}

/// 1 when the production of the feed runs in the namespace of the feed.
ClassMethod Running() As %Boolean
{
	Set ns = ..#NAMESPACE, production = ..#PRODUCTION
	If '##class(%SYS.Namespace).Exists(ns) Quit 0
	If '##class(%Library.EnsembleMgr).IsEnsembleNamespace(ns) Quit 0
	New $NAMESPACE
	Set $NAMESPACE = ns
	Quit ''##class(Ens.Director).IsProductionRunning(.name) && (name = production)
}

/// Sends the messages of every case, one batch to FeedIn for each, and gives in refs, by the name of each case, the reference that is the SuperSession
/// of the case's messages. The feed must run. The batches are sent and the failures happen in the item's own jobs.
ClassMethod Start(Output refs As %DynamicObject) As %Status
{
	Set refs = {}
	Set ns = ..#NAMESPACE, source = ..#SOURCEITEM
	Set definitions = ..Definitions()
	Set iterator = definitions.%GetIterator()
	While iterator.%GetNext(, .definition) {
		Do refs.%Set(definition.name, ##class(OcuTalon.Bridge.Ids).NewRef())
	}
	Set sc = $$$OK
	Try {
		New $NAMESPACE
		Set $NAMESPACE = ns
		$$$ThrowOnError(##class(Ens.Director).CreateBusinessService(source, .service))
		Set iterator = definitions.%GetIterator()
		While iterator.%GetNext(, .definition) {
			Set batch = ##class(OcuTalon.Test.Eval.Feed.Batch).%New()
			Set batch.Target = definition.item
			Set batch.TraceRef = refs.%Get(definition.name)
			Set messages = definition.messages.%GetIterator()
			While messages.%GetNext(, .fields) {
				Set message = $ClassMethod(definition.messageClass, "%New")
				$$$ThrowOnError(message.%JSONImport(fields))
				Do batch.Messages.Insert(message)
			}
			$$$ThrowOnError(service.ProcessInput(batch))
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Waits up to WAITSECONDS for the case's failures: as many headers of the reference in the status Error at the case's item as the case has messages.
/// Gives where and which they are: the namespace, production and item they are at and the keys of their failed headers (h<id>, ascending), as
/// Eval.Record.Capture takes them. Short of the count, the status is an error that names the count seen.
ClassMethod Keys(name As %String, ref As %String, Output namespace As %String, Output production As %String, Output item As %String, Output keys As %String) As %Status
{
	Set keys = ""
	Set definition = ..Definition(name)
	If '$IsObject(definition) Quit $$$ERROR($$$GeneralError, "The test feed has no case "_name)
	Set namespace = ..#NAMESPACE, production = ..#PRODUCTION, item = definition.item
	Set wanted = definition.messages.%Size()
	Set deadline = $ZHorolog + ..#WAITSECONDS
	For {
		Set seen = ..Count(ref, item)
		If (seen >= wanted) || ($ZHorolog >= deadline) Quit
		Hang 0.5
	}
	If seen '= wanted Quit $$$ERROR($$$GeneralError, "The case "_name_" has "_seen_" failed headers at "_item_" after "_..#WAITSECONDS_" s, not "_wanted)
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE SuperSession = ? AND TargetConfigName = ? AND Status = ? ORDER BY ID", ref, item, $$$eMessageStatusError)
	If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "The headers of "_name_" could not be listed: "_rs.%Message)
	While rs.%Next() {
		Set keys = keys_$Select(keys = "": "", 1: ",")_"h"_rs.%Get("ID")
	}
	Quit $$$OK
}

/// The driver's entry (docker/tests/record-eval.sh feed): installs the feed, sends the cases, and for each case in name order reads its keys,
/// captures it with Eval.Record into the folder (<folder>/<name>/case.json and snapshot.json), and checks that EvidencePack.Build gives, from the
/// snapshot just written, exactly the pack that Capture returned. names holds the names of the cases that were recorded, comma-separated. The feed is
/// always removed; the status is the first failure, with the removal's status appended. The folder is emptied once Install has not refused.
ClassMethod Record(folder As %String, Output names As %String) As %Status
{
	Set names = ""
	Set sc = $$$OK
	Try {
		$$$ThrowOnError(..Install())
		Do ##class(%File).RemoveDirectoryTree(folder)
		$$$ThrowOnError(..Start(.refs))
		Set iterator = ..Definitions().%GetIterator()
		While iterator.%GetNext(, .definition) {
			$$$ThrowOnError(..Keys(definition.name, refs.%Get(definition.name), .namespace, .production, .item, .keys))
			Set case = {"name": (definition.name), "description": (definition.description), "expectation": (definition.expectation)}
			Do case.%Set("heldOut", +definition.heldOut, "boolean")
			$$$ThrowOnError(##class(OcuTalon.Eval.Record).Capture(case, namespace, production, item, keys, folder, .pack))
			Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(folder, definition.name))
			$$$ThrowOnError(##class(OcuTalon.Watch.EvidencePack).Load(file, .snapshot))
			$$$ThrowOnError(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .replay))
			If replay.%ToJSON() '= pack.%ToJSON() $$$ThrowStatus($$$ERROR($$$GeneralError, "The pack that Build gives the written snapshot of "_definition.name_" is not the pack that Capture returned"))
			Set names = names_$Select(names = "": "", 1: ",")_definition.name
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit $SYSTEM.Status.AppendStatus(sc, ..Remove())
}

/// The number of headers of the reference at the item in the status Error.
ClassMethod Count(ref As %String, item As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SuperSession = ? AND TargetConfigName = ? AND Status = ?", ref, item, $$$eMessageStatusError)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The folder of the feed's database: below the manager directory, in lower case, with its closing slash.
ClassMethod Directory() As %String [ Private ]
{
	Quit ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory()_$ZConvert(..#DATABASE, "L"))
}

/// Makes what lives in %SYS and in the CPF (see the class description), in this order, and the grant. Runs in %SYS, where only the system classes
/// resolve, so everything it needs is read before the switch and it calls no other method of this class there.
ClassMethod CreateSystem() As %Status [ Private ]
{
	Set ns = ..#NAMESPACE, db = ..#DATABASE, resource = ..#RESOURCE
	Set package = ..#CODEPACKAGE, codeDatabase = ..#CODEDATABASE
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Set directory = ..Directory()
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	#; The resource has no public permission.
	Set sc = ##class(Security.Resources).Create(resource, "Evaluation test feed database")
	If $$$ISERR(sc) Quit sc
	If '##class(%File).CreateDirectoryChain(directory) Quit $$$ERROR($$$GeneralError, "The folder "_directory_" could not be made")
	Set sc = ##class(SYS.Database).CreateDatabase(directory, , , , resource)
	If $$$ISERR(sc) Quit sc
	Kill props
	Set props("Directory") = directory
	Set sc = ##class(Config.Databases).Create(db, .props)
	If $$$ISERR(sc) Quit sc
	Kill props
	Set props("Globals") = db
	Set props("Routines") = db
	Set sc = ##class(Config.Namespaces).Create(ns, .props)
	If $$$ISERR(sc) Quit sc
	Kill props
	Set props("Database") = codeDatabase
	Set sc = ##class(Config.MapPackages).Create(ns, package, .props)
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(%Library.EnsembleMgr).EnableNamespace(ns, 0, , 1)
	If $$$ISERR(sc) Quit sc
	#; The one grant: Read on the feed's database, added to the service role's Resources.
	If '##class(Security.Roles).Exists(role) Quit $$$ERROR($$$GeneralError, "The role "_role_" does not exist, so the test feed cannot be granted to it")
	Kill props
	Set sc = ##class(Security.Roles).Get(role, .props)
	If $$$ISERR(sc) Quit sc
	Set resources = $Get(props("Resources"))
	If ("," _ resources _ ",") '[ ("," _ resource _ ":R,") Set resources = resources _ $Select(resources = "": "", 1: ",") _ resource _ ":R"
	Kill props
	Set props("Resources") = resources
	Quit ##class(Security.Roles).Modify(role, .props)
}

/// Loads the production from its class in the namespace of the feed, starts it, and waits up to WAITSECONDS until it runs and every enabled item that
/// has a pool has an alive job that is not in error, halted or terminated.
ClassMethod StartProduction() As %Status [ Private ]
{
	Set ns = ..#NAMESPACE, production = ..#PRODUCTION, wait = ..#WAITSECONDS
	New $NAMESPACE
	Set $NAMESPACE = ns
	Set sc = ##class(Ens.Config.Production).LoadFromClass(production)
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(Ens.Director).StartProduction(production)
	If $$$ISERR(sc) Quit sc
	Set deadline = $ZHorolog + wait
	For {
		Kill alive
		Set missing = ""
		If '##class(Ens.Director).IsProductionRunning(.running) || (running '= production) {
			Set missing = production_" is not running"
		} Else {
			Set rs = ##class(%ResultSet).%New("Ens.Job:Enumerate")
			If $$$ISOK(rs.Execute()) {
				While rs.Next() {
					If rs.Get("State") '= "Alive" Continue
					If $ListFind($ListBuild("error", "halted", "terminated"), rs.Get("Status")) Continue
					Set alive(rs.Get("ConfigName")) = ""
				}
			}
			Set item = ""
			For {
				Set item = $Order($$$ConfigRoot(item))
				Quit:item=""
				If item = "%Production" Continue
				If '$Get($$$ConfigIsEnabled(item)) Continue
				If '$Get($$$ConfigPoolSize(item)) Continue
				If '$Data(alive(item)) Set missing = missing_$Select(missing = "": "", 1: ",")_item
			}
			If missing '= "" Set missing = "these items do not run: "_missing
		}
		If missing = "" Quit
		If $ZHorolog >= deadline Quit
		Hang 1
	}
	If missing '= "" Quit $$$ERROR($$$GeneralError, production_" did not finish starting in "_wait_" s: "_missing)
	Quit $$$OK
}

/// Stops the production while it runs, is troubled or is suspended (forced after STOPSECONDS). Nothing to do when the namespace does not exist.
ClassMethod StopProduction() As %Status [ Private ]
{
	Set ns = ..#NAMESPACE, production = ..#PRODUCTION, seconds = ..#STOPSECONDS
	Set sc = $$$OK
	Try {
		If '##class(%SYS.Namespace).Exists(ns) Quit
		If '##class(%Library.EnsembleMgr).IsEnsembleNamespace(ns) Quit
		New $NAMESPACE
		Set $NAMESPACE = ns
		$$$ThrowOnError(##class(Ens.Director).GetProductionStatus(.name, .state))
		If (name = production) && ((state = $$$eProductionStateRunning) || (state = $$$eProductionStateTroubled) || (state = $$$eProductionStateSuspended)) {
			$$$ThrowOnError(##class(Ens.Director).StopProduction(seconds, 1))
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Removes what lives in %SYS and in the CPF (see the class description): the web applications of the namespace, the namespace, its Interoperability
/// marker and role, every database entry at or below the folder (innermost first) with its files and the folder, and the resource. Each step is
/// skipped when there is nothing to remove. Runs in %SYS, as CreateSystem does.
ClassMethod RemoveSystem() As %Status [ Private ]
{
	Set ns = ..#NAMESPACE, resource = ..#RESOURCE
	Set directory = ..Directory()
	Set interopRole = $$$InteropNSRole(ns)
	Set portalDir = ##class(%File).NormalizeDirectory($SYSTEM.Util.DataDirectory()_"csp/"_$ZConvert(ns, "L"))
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Path FROM Security.Applications WHERE NameSpace = ?", ns)
	If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "The web applications of "_ns_" could not be listed: "_rs.%Message)
	While rs.%Next() {
		Set apps(rs.%Get("Name")) = rs.%Get("Path")
	}
	Set sc = $$$OK
	Set app = ""
	For {
		Set app = $Order(apps(app), 1, path)
		Quit:app=""
		Set sc = ##class(Security.Applications).Delete(app)
		If $$$ISERR(sc) Quit
		If (path '= "") && (##class(%File).NormalizeDirectory(path) = portalDir) && ##class(%File).DirectoryExists(portalDir) {
			If '##class(%File).RemoveDirectoryTree(portalDir) Set sc = $$$ERROR($$$GeneralError, "The folder "_portalDir_" could not be removed")
		}
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	If ##class(Config.Namespaces).Exists(ns) {
		Set sc = ##class(Config.Namespaces).Delete(ns)
		If $$$ISERR(sc) Quit sc
	}
	If $Data(^%SYS("Ensemble", "InstalledNamespace", ns)) {
		Set sc = ##class(%Library.EnsembleMgr).DisableNamespace(ns)
		If $$$ISERR(sc) Quit sc
	}
	If ##class(Security.Roles).Exists(interopRole) {
		Set sc = ##class(Security.Roles).Delete(interopRole)
		If $$$ISERR(sc) Quit sc
	}
	#; The databases whose folder is the feed's folder or below it, innermost first.
	Set dbs = ##class(%ResultSet).%New("Config.Databases:List")
	Set sc = dbs.Execute()
	If $$$ISERR(sc) Quit sc
	While dbs.Next() {
		Set dir = ##class(%File).NormalizeDirectory(dbs.Get("Directory"))
		If $Extract(dir, 1, $Length(directory)) = directory {
			Set owned($Length(dir), dbs.Get("Name")) = dir
			If dbs.Get("Name") '= ..#DATABASE Set gone("%DB_"_dbs.Get("Name")) = ""
		}
	}
	Set length = ""
	For {
		Set length = $Order(owned(length), -1)
		Quit:length=""
		Set db = ""
		For {
			Set db = $Order(owned(length, db), 1, dir)
			Quit:db=""
			Set sc = ##class(Config.Databases).Delete(db)
			If $$$ISERR(sc) Quit
			If ##class(%File).Exists(dir_"IRIS.DAT") {
				Set sc = ##class(SYS.Database).DeleteDatabase(dir)
				If $$$ISERR(sc) Quit
			}
			If ##class(%File).DirectoryExists(dir) && '##class(%File).RemoveDirectoryTree(dir) {
				Set sc = $$$ERROR($$$GeneralError, "The folder "_dir_" could not be removed")
				Quit
			}
		}
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	#; A database that was never entered in the CPF leaves its folder.
	If ##class(%File).Exists(directory_"IRIS.DAT") {
		Set sc = ##class(SYS.Database).DeleteDatabase(directory)
		If $$$ISERR(sc) Quit sc
	}
	If ##class(%File).DirectoryExists(directory) && '##class(%File).RemoveDirectoryTree(directory) Quit $$$ERROR($$$GeneralError, "The folder "_directory_" could not be removed")
	#; The resource, which takes its grant out of every role, and the resources and roles of the other databases that Interoperability made.
	Set gone(resource) = ""
	Set name = ""
	For {
		Set name = $Order(gone(name))
		Quit:name=""
		If ##class(Security.Roles).Exists(name) {
			Set sc = ##class(Security.Roles).Delete(name)
			If $$$ISERR(sc) Quit
		}
		If ##class(Security.Resources).Exists(name) {
			Set sc = ##class(Security.Resources).Delete(name)
			If $$$ISERR(sc) Quit
		}
	}
	Quit sc
}

}
