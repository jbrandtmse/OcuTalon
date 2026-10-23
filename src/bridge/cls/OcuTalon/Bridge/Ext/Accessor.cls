/// The one reader and writer of the bridge's host settings (AD-19, AD-31). The Decide item names three extension classes in its
/// host settings, and any job can read them through ClassFor, the AnswersIn job that calls Approval.Answer included.
/// A named class that is missing, or that does not extend its base, is an error and never silently the do-nothing
/// base, so a misconfigured reply filter cannot disable the all-clear guard without a trace. ValueFor is the general read
/// of a setting, which ClassFor builds on and which the budget reads its three settings through (AD-20). WriteDefault is the
/// one writer of a System Default Settings row, for the bridge and for the install steps that call it.
Class OcuTalon.Bridge.Ext.Accessor
{

/// The settings of the Decide item, each with the base class that its class must extend.
Parameter BASES = "HostSinkClass=OcuTalon.Bridge.Ext.HostSink,ReplyFilterClass=OcuTalon.Bridge.Ext.ReplyFilter,ClassificationClass=OcuTalon.Bridge.Ext.Classification";

/// The value of the host setting on the item of the production, or "" with an error in sc.
/// The setting is read from the production definition, the System Default Settings and the initial value of the host's property,
/// in that order, so no production needs to be running when the production is named. An empty production is Ens.Director's
/// active production: the running production, else the suspended one, else the last one used in the namespace.
ClassMethod ValueFor(setting As %String, production As %String = "", item As %String = "Decide", Output sc As %Status) As %String
{
	Set sc = $$$OK
	If production = "" Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" {
		Set sc = $$$ERROR($$$GeneralError, "No production is named and none is active, so the setting '"_setting_"' cannot be read")
		Quit ""
	}
	Set value = ##class(Ens.Director).GetHostSettingValue(production_"||"_item, setting, .sc)
	If $$$ISERR(sc) Quit ""
	Quit value
}

/// Writes the System Default Settings row (production, item, any class, setting) with the value and the description: it
/// changes the row when it exists and creates it otherwise. A row that matches every class applies to the director's
/// lookup of the item and to the job of the item alike.
ClassMethod WriteDefault(production As %String, item As %String, setting As %String, value As %String, description As %String) As %Status
{
	Set id = production_"||"_item_"||*||"_setting
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id, , .sc)
		If $$$ISERR(sc) Quit sc
	} Else {
		Set row = ##class(Ens.Config.DefaultSettings).%New()
		Set row.ProductionName = production
		Set row.ItemName = item
		Set row.HostClassName = "*"
		Set row.SettingName = setting
	}
	Set row.SettingValue = value
	Set row.Description = description
	Quit row.%Save()
}

/// The class that the setting names on the item of the production, or "" with an error in sc (ValueFor reads the setting).
/// The class is returned only when Check(setting, class) passes.
ClassMethod ClassFor(setting As %String, production As %String = "", item As %String = "Decide", Output sc As %Status) As %String
{
	Set sc = $$$OK
	If ..BaseOf(setting) = "" {
		Set sc = $$$ERROR($$$GeneralError, "'"_setting_"' is not an extension setting; the settings are named by the BASES parameter")
		Quit ""
	}
	Set class = ..ValueFor(setting, production, item, .sc)
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
