/// The one reader of the bridge's extension settings (AD-31). The Decide item names three extension classes in its
/// host settings, and any job can read them through ClassFor, the AnswersIn job that calls Approval.Answer included.
/// A named class that is missing, or that does not extend its base, is an error and never silently the do-nothing
/// base, so a misconfigured reply filter cannot disable the all-clear guard without a trace.
Class OcuTalon.Bridge.Ext.Accessor
{

/// The settings of the Decide item, each with the base class that its class must extend.
Parameter BASES = "HostSinkClass=OcuTalon.Bridge.Ext.HostSink,ReplyFilterClass=OcuTalon.Bridge.Ext.ReplyFilter,ClassificationClass=OcuTalon.Bridge.Ext.Classification";

/// The class that the setting names on the item of the production, or "" with an error in sc.
/// The setting is read from the production definition and the System Default Settings, so no production needs to
/// be running when the production is named. An empty production is Ens.Director's active production: the running
/// production, else the suspended one, else the last one used in the namespace.
/// The class is returned only when Check(setting, class) passes.
ClassMethod ClassFor(setting As %String, production As %String = "", item As %String = "Decide", Output sc As %Status) As %String
{
	Set sc = $$$OK
	If ..BaseOf(setting) = "" {
		Set sc = $$$ERROR($$$GeneralError, "'"_setting_"' is not an extension setting; the settings are named by the BASES parameter")
		Quit ""
	}
	If production = "" Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" {
		Set sc = $$$ERROR($$$GeneralError, "No production is named and none is active, so the setting '"_setting_"' cannot be read")
		Quit ""
	}
	Set class = ##class(Ens.Director).GetHostSettingValue(production_"||"_item, setting, .sc)
	If $$$ISERR(sc) Quit ""
	Set sc = ..Check(setting, class)
	If $$$ISERR(sc) Quit ""
	Quit class
}

/// OK when class is compiled and extends the base of the setting; otherwise an error that names the setting, the
/// class and the problem.
ClassMethod Check(setting As %String, class As %String) As %Status
{
	Set base = ..BaseOf(setting)
	If base = "" Quit $$$ERROR($$$GeneralError, "'"_setting_"' is not an extension setting")
	If class = "" Quit $$$ERROR($$$GeneralError, "The setting "_setting_" names no class; it needs a class that extends "_base)
	If '##class(%Dictionary.CompiledClass).%ExistsId(class) Quit $$$ERROR($$$GeneralError, "The class "_class_" of the setting "_setting_" is not compiled")
	If '$ClassMethod(class, "%Extends", base) Quit $$$ERROR($$$GeneralError, "The class "_class_" of the setting "_setting_" does not extend "_base)
	Quit $$$OK
}

/// The base class of the setting, or "" when it is not an extension setting.
ClassMethod BaseOf(setting As %String) As %String [ Private ]
{
	Set base = ""
	For i = 1:1:$Length(..#BASES, ",") {
		Set pair = $Piece(..#BASES, ",", i)
		If $Piece(pair, "=", 1) = setting Set base = $Piece(pair, "=", 2)
	}
	Quit base
}

}
