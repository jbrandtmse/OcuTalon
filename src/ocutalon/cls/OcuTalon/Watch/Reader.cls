/// The reader of the productions that OcuTalon can watch (AD-3, AD-4, AD-6): the only class that switches namespace to look at a production, and
/// the only place that checks the service user's read access to a namespace. The watch tools and WatchOps both use it, so a tool and the
/// owner of the watch agree on what can be watched.
///   - Productions lists one entry per readable Interoperability namespace: its own current production, the one that
///     Ens.Director.GetProductionStatus gives (a namespace with no current production has no entry). An entry is
///     {"namespace", "production" (the class name), "displayName"}. The display name is the Description of the production's definition, or the
///     class name when the description is empty. A namespace is readable when the user of the ServiceUser setting of Decide holds Read on the
///     resource of the namespace's default global database ($SYSTEM.Security.CheckUserPermission). An unreadable namespace, and one that
///     cannot be entered, are left out. On the online demo (the public flag onlineDemo) the list holds only the Orders demo production, when
///     it is readable.
///   - Find gives the entries that a name matches: the name is trimmed, a trailing " production" is dropped, and the rest is compared without
///     regard to case with the display name and with the class name. An optional namespace narrows the match.
///   - Label turns a production's description into its display name: white-space runs become one space and the text is cut to 128 characters
///     (the length of the DisplayName of the command and of the watch's row), so that a long or multi-line description never fails a start.
///   - Admits says whether one namespace and production are an entry, and gives its display name.
///   - OnlineDemo says whether the list is limited to Orders.
/// The Orders identity is read from OcuTalon.Install.Step.Demo (NAMESPACE and PRODUCTION), never copied. The namespace switch is in one method,
/// Current, which calls no OcuTalon class while it is in the other namespace. A reader runs inside AI Hub's callback, so this class makes no
/// AI Hub call, no Python call and no session call (AD-6).
Class OcuTalon.Watch.Reader
{

/// The longest the reader waits for the production lock of a namespace, in seconds.
Parameter LOCKSECONDS = 1;

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
		Do list.%Push({"namespace": (namespace), "production": (production), "displayName": ($Select(description '= "": description, 1: production))})
	}
	Quit list
}

/// The entries that name matches (see the class description), in the order of Productions. namespace, when it is not empty, keeps only the
/// entries of that namespace, compared without regard to case. A name that is empty after trimming matches nothing.
ClassMethod Find(name As %String, namespace As %String = "") As %DynamicArray
{
	Set matches = []
	Set wanted = ..Normalize(name)
	If wanted = "" Quit matches
	Set iterator = ..Productions().%GetIterator()
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

/// A name for comparison: trimmed, in lower case, without a trailing " production".
ClassMethod Normalize(name As %String) As %String [ Private ]
{
	Set text = $ZConvert($ZStrip($Get(name), "<>W"), "L")
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

/// The name of the namespace's own current production, as Ens.Director.GetProductionStatus gives it, and its description in description.
/// "" when the namespace has no current production, or when it cannot be entered or read. This is the one method that switches namespace,
/// and it calls no OcuTalon class there.
ClassMethod Current(namespace As %String, Output description As %String) As %String [ Private ]
{
	Set description = ""
	Set name = ""
	Set lock = ..#LOCKSECONDS
	New $NAMESPACE
	Try {
		Set $NAMESPACE = namespace
		Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state, lock, 1)
		If $$$ISERR(sc) Set name = ""
		If name '= "" {
			Set definition = ##class(Ens.Config.Production).%OpenId(name)
			If $IsObject(definition) Set description = ..Label(definition.Description)
		}
	} Catch {
		Set name = ""
		Set description = ""
	}
	Quit name
}

}
