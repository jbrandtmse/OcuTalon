/// The second early step of the package's first install run (AD-23, FR-57): it makes IPM available in namespace OCUTALON and,
/// outside OCUTALON, maps IPM's repository definitions into it and stops the run with the next command. The manifest invokes MapAndStop at Initialize, after the CPF
/// resource has created OCUTALON, and IPM compiles this class from its preload tree before that, so it exists before Reload.
Class OcuTalon.Install.Ipm
{

/// The stop sentence, the whole text of the status that a run outside OCUTALON returns.
Parameter STOP = "OcuTalon created namespace OCUTALON. Now run: zn ""OCUTALON"" then the same install command.";

/// Maps the %IPM package and the %IPM.* routines into OCUTALON, from the database where %IPM resolves in the run namespace
/// (IPM's own command "enable -map -ns OCUTALON -q"). Outside OCUTALON it then maps IPM's repository definitions the same way (U-232,
/// see MapRepos), so that the second install command finds the repositories of the first namespace. All of it runs with
/// transactions suspended, so that the rollback of a stopped run cannot undo the mapping. The suspension state before the call is
/// restored on every path.
/// Returns the first mapping error unchanged. Otherwise returns an error status with the stop sentence when the run namespace is
/// not OCUTALON, and OK in OCUTALON, where the install continues. It prints nothing and switches no namespace. IPM's command
/// rewrites the instance's CPF file and reloads OCUTALON's mappings on every call, also when the mapping exists already.
ClassMethod MapAndStop() As %Status
{
	Set suspended = $SYSTEM.Process.TransactionsSuspended(1)
	Try {
		Set sc = ##class(%IPM.Main).Shell("enable -map -ns OCUTALON -q")
		If $$$ISOK(sc), $Namespace '= "OCUTALON" Set sc = ..MapRepos()
	} Catch e {
		Set sc = e.AsStatus()
	}
	Do $SYSTEM.Process.TransactionsSuspended(suspended)
	If $$$ISERR(sc) Quit sc
	If $Namespace '= "OCUTALON" Quit $SYSTEM.Status.Error(5001, ..#STOP)
	Quit $$$OK
}

/// Maps IPM's repository definitions, the globals ^IPM.Repo.DefinitionD, S and I, into OCUTALON from the database where each resolves
/// in the run namespace (%IPM.Utils.Build MapGlobalEquivalently; IPM's own "enable -map -repos" skips OCUTALON). The definitions are
/// mapped as they are: nothing is copied, created, edited or printed. Like IPM's own rule, it maps nothing when OCUTALON already
/// sees repository definitions. Returns the first error unchanged. The caller suspends transactions.
ClassMethod MapRepos() As %Status [ Private ]
{
	If $Data(^|"OCUTALON"|IPM.Repo.DefinitionD)\2 Quit $$$OK
	Set sc = $$$OK
	Set list = $ListBuild("IPM.Repo.DefinitionD", "IPM.Repo.DefinitionS", "IPM.Repo.DefinitionI")
	Set pointer = 0
	While $ListNext(list, pointer, global) && $$$ISOK(sc) {
		Set sc = ##class(%IPM.Utils.Build).MapGlobalEquivalently(global, $Namespace, "OCUTALON")
	}
	Quit sc
}

/// The package's early Reload step (Story 19.8, DW-829): removes the stale copies of the Python distributions that requirements.txt pins,
/// so that IPM's pip step, which installs with --target and so skips every top-level item that exists already, puts the pinned
/// copies in their place. The manifest invokes it at Reload, before IPM's pip step. root is the module root that holds requirements.txt
/// (its name==version lines are the only pins; nothing is listed here), bypass is IPM's -bypass-py-deps flag, and target is the folder
/// to clean, by default <mgr>/python.
/// A distribution is stale when a name-version.dist-info folder of target has the name of a pin and another version. Of a stale
/// distribution it removes the top-level items (folders and files) named by the first segment of its RECORD paths, and then its own
/// dist-info folder, but only an item that no dist-info folder of another distribution lists (the namespace folder google/ stays
/// when another distribution lists a path in it), and only a folder that is itself in target (a symbolic link is never followed, also for
/// the dist-info and __pycache__ folders). It skips absolute and .. paths, bin/, __pycache__/ and every dist-info folder, takes the __pycache__ files of a single-file module with the module, and keeps
/// a stale dist-info folder that has no RECORD. A distribution at its pinned version, a name that is no pin and every other file stay.
/// For each distribution it replaces it writes one line, STEP Python replaced name old-version with pinned-version, after the removal;
/// a second call finds nothing stale and writes nothing. With no requirements.txt in root (the image path), with bypass set, or with a
/// missing target it removes nothing. A stale distribution with an item that could not be removed keeps its dist-info folder and writes
/// no line, so that the next call finds it and tries again. It never throws and always returns OK.
ClassMethod RemoveStaleCopies(root As %String = "", bypass As %String = 0, target As %String = "") As %Status
{
	Try {
		Do ..Replace($Get(root), +$Get(bypass), $Get(target))
	} Catch {
	}
	Quit $$$OK
}

/// The work of RemoveStaleCopies; see there. Throws on an unexpected error.
ClassMethod Replace(root As %String, bypass As %Boolean, target As %String) [ Private ]
{
	If bypass || (root = "") Quit
	If target = "" Set target = $SYSTEM.Util.ManagerDirectory() _ "python/"
	Set target = ##class(%File).NormalizeDirectory(target)
	If '##class(%File).DirectoryExists(target) Quit
	Set real = ##class(%File).ResolvePath(target)
	If real = "" Quit
	Set real = ##class(%File).NormalizeDirectory(real)
	Do ..ReadPins(root, .pins)
	If '$Data(pins) Quit
	Set set = ##class(%ResultSet).%New("%File:FileSet")
	If '$IsObject(set) Quit
	If $$$ISERR(set.Execute(target, "*.dist-info", "Name", 1)) Quit
	While set.Next() {
		Set item = set.Get("ItemName")
		If set.Get("Type") '= "D" || '..EndsWith(item, ".dist-info") Continue
		Set base = $Extract(item, 1, $Length(item) - 10)
		Set count = $Length(base, "-")
		Set norm = ..Normalize($Piece(base, "-", 1, count - 1))
		If norm = "" Continue
		Set dists(item) = $ListBuild($Piece(base, "-", 1, count - 1), norm, $Piece(base, "-", count))
		Do ..RecordTops(target _ item _ "/RECORD", .tops)
		Merge records(item) = tops
		Set top = ""
		For {
			Set top = $Order(tops(top))
			Quit:top=""
			Set claims(top, norm) = ""
		}
	}
	Set item = ""
	For {
		Set item = $Order(dists(item), 1, entry)
		Quit:item=""
		Set norm = $List(entry, 2)
		If '$Data(pins(norm), pin) || (..NormalizeVersion($List(entry, 3)) = ..NormalizeVersion(pin)) Continue
		If '$Data(records(item)) Continue
		Set top = "", kept = 0
		For {
			Set top = $Order(records(item, top))
			Quit:top=""
			If ..EndsWith(top, ".dist-info") || (top = "bin") || (top = "__pycache__") Continue
			Set other = "", owned = 0
			For {
				Set other = $Order(claims(top, other))
				Quit:other=""
				If other '= norm Set owned = 1
				Quit:owned
			}
			If 'owned {
				Do ..RemoveItem(target, real, top)
				If ##class(%File).Exists(target _ top) || ##class(%File).DirectoryExists(target _ top) Set kept = 1
			}
		}
		If 'kept, ..RemoveItem(target, real, item) {
			Write !, "STEP Python replaced ", $List(entry, 1), " ", $List(entry, 3), " with ", pin
		}
	}
}

/// Removes target's top-level item top, a folder with its content or a file with the __pycache__ files of the module of a .py file. A
/// folder (top itself, or __pycache__) is removed or searched only when it resolves to the same folder in real (the resolved target, with
/// a closing slash), so a symbolic link is never followed. Returns 1 when it removed the item.
ClassMethod RemoveItem(target As %String, real As %String, top As %String) As %Boolean [ Private ]
{
	Set path = target _ top
	If ##class(%File).DirectoryExists(path) {
		If '..IsOwnFolder(path, real _ top) Quit 0
		Quit ##class(%File).RemoveDirectoryTree(path)
	}
	If '##class(%File).Exists(path) Quit 0
	If '##class(%File).Delete(path) Quit 0
	If ..EndsWith(top, ".py"), ..IsOwnFolder(target _ "__pycache__", real _ "__pycache__") {
		Set set = ##class(%ResultSet).%New("%File:FileSet")
		If $IsObject(set), $$$ISOK(set.Execute(target _ "__pycache__", $Extract(top, 1, $Length(top) - 3) _ ".*.pyc", "Name", 0)) {
			While set.Next() {
				Do ##class(%File).Delete(set.Get("Name"))
			}
		}
	}
	Quit 1
}

/// 1 when the folder path exists and resolves to the folder expected (a resolved path), that is, when it is no symbolic link to another place.
ClassMethod IsOwnFolder(path As %String, expected As %String) As %Boolean [ Private ]
{
	If '##class(%File).DirectoryExists(path) Quit 0
	Set resolved = ##class(%File).ResolvePath(path)
	If resolved = "" Quit 0
	Quit ##class(%File).NormalizeDirectory(resolved) = ##class(%File).NormalizeDirectory(expected)
}

/// Reads the pins of root's requirements.txt into pins(normalized name) = version. A pin is a name==version line; comments (# at the
/// start of a line), blank lines and every other line are skipped.
ClassMethod ReadPins(root As %String, Output pins) [ Private ]
{
	Kill pins
	Set file = ##class(%File).NormalizeFilename("requirements.txt", ##class(%File).NormalizeDirectory(root))
	If '##class(%File).Exists(file) Quit
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(file)) Quit
	While 'stream.AtEnd {
		Set line = $ZStrip($Translate(stream.ReadLine(), $Char(13)), "<>W")
		If line = "" || ($Extract(line) = "#") || ($Length(line, "==") < 2) Continue
		Set name = $ZStrip($Piece($Piece(line, "==", 1), "["), "<>W")
		Set version = $Piece($Piece($Piece($ZStrip($Piece(line, "==", 2), "<W"), " "), ";"), "#")
		If name '= "", version '= "" Set pins(..Normalize(name)) = version
	}
}

/// 1 when text ends with suffix.
ClassMethod EndsWith(text As %String, suffix As %String) As %Boolean [ CodeMode = expression, Private ]
{
($Length(text) >= $Length(suffix)) && ($Extract(text, $Length(text) - $Length(suffix) + 1, $Length(text)) = suffix)
}

/// A version with the leading zeros of its numeric parts removed (2025.01.31 and 2025.1.31 are one version).
ClassMethod NormalizeVersion(version As %String) As %String [ Private ]
{
	Set out = ""
	For i = 1:1:$Length(version, ".") {
		Set part = $Piece(version, ".", i)
		If part ? 1.N Set part = +part
		Set out = out _ $Select(i = 1: "", 1: ".") _ part
	}
	Quit out
}

/// A distribution name in the form of PEP 503: lower case, and every run of - _ . one -.
ClassMethod Normalize(name As %String) As %String [ Private ]
{
	Set name = $ZConvert(name, "L")
	Set out = ""
	For i = 1:1:$Length(name) {
		Set char = $Extract(name, i)
		If "-_." [ char {
			If $Extract(out, $Length(out)) '= "-" Set out = out _ "-"
		} Else {
			Set out = out _ char
		}
	}
	Quit out
}

/// The top-level items that a RECORD file names, tops(item) = "": the first segment of each path (the first field of a CSV line, with
/// quoted fields allowed), without absolute paths, .. paths and empty segments. Returns 1 when the file was read.
ClassMethod RecordTops(file As %String, Output tops) As %Boolean [ Private ]
{
	Kill tops
	If '##class(%File).Exists(file) Quit 0
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(file)) Quit 0
	While 'stream.AtEnd {
		Set path = ..FirstField($Translate(stream.ReadLine(), $Char(13)))
		If path = "" || ($Extract(path) = "/") || (path [ ":") Continue
		Set top = $Piece(path, "/")
		If top '= "", top '= ".", top '= ".." Set tops(top) = ""
	}
	Quit 1
}

/// The first field of a CSV line; a field in double quotes ends at the quote that is not doubled.
ClassMethod FirstField(line As %String) As %String [ Private ]
{
	If $Extract(line) '= """" Quit $Piece(line, ",")
	Set out = ""
	Set i = 2
	While i <= $Length(line) {
		Set char = $Extract(line, i)
		If char = """" {
			If $Extract(line, i + 1) '= """" Quit
			Set i = i + 1
		}
		Set out = out _ char
		Set i = i + 1
	}
	Quit out
}

/// The package's Unconfigure step: removes the mapping of IPM's repository definitions that MapAndStop made in OCUTALON, with IPM's
/// own "unmap -repos-only -ns OCUTALON -q", which unmaps those three globals and nothing else. Transactions are suspended during the
/// call and restored on every path. It prints nothing and kills and sets no global, so the definitions of the namespace that holds
/// them stay as they are. Returns IPM's status.
ClassMethod UnmapRepos() As %Status
{
	Set suspended = $SYSTEM.Process.TransactionsSuspended(1)
	Try {
		Set sc = ##class(%IPM.Main).Shell("unmap -repos-only -ns OCUTALON -q")
	} Catch e {
		Set sc = e.AsStatus()
	}
	Do $SYSTEM.Process.TransactionsSuspended(suspended)
	Quit sc
}

}
