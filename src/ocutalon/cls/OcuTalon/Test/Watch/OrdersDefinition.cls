/// The fixture settings on the failing item of the saved Orders production definition in OCUORDERS (a throwaway; test only), shared by the tests that need a
/// credential setting and a plain one on that item: Test.Watch.Evidence and Test.Eval.Record. It is a helper, not a test class: none of its methods is a test.
///   - Put adds the settings to the definition (on) or takes them out of it (off) and saves it. It first takes out any of them that are there, so that it can be
///     called twice. Each name of CREDENTIALS gets the credential value, and NOTE gets the note value. It calls only Ens classes while it is in OCUORDERS and
///     does not update the running production.
///   - Defined gives the names of the settings of the item in the saved definition, sorted, so that a test can compare the definition before and after.
/// The namespace and the production are those of OcuTalon.Install.Step.Demo.
Class OcuTalon.Test.Watch.OrdersDefinition [ DependsOn = OcuTalon.Install.Step.Demo ]
{

/// The item of the Orders production that the demo failures are at.
Parameter ITEM = "OrdersFromPartner";

/// The names of the four settings that Reader.CredentialName leaves out of a snapshot.
Parameter CREDENTIALS = "Credentials,SMTPPassword,BotToken,ApiKey";

/// The name of the plain setting, which a snapshot keeps.
Parameter NOTE = "ZzFixtureNote";

Parameter NAMESPACE = {##class(OcuTalon.Install.Step.Demo).#NAMESPACE};

Parameter PRODUCTION = {##class(OcuTalon.Install.Step.Demo).#PRODUCTION};

/// Puts the settings into (on) or takes them out of (off) the item of the saved Orders definition, and saves it. The status is an error when the
/// definition or the item is not there.
ClassMethod Put(on As %Boolean, credentialValue As %String = "", noteValue As %String = "") As %Status
{
	Set names = $ListFromString(..#CREDENTIALS_","_..#NOTE)
	Set noteName = ..#NOTE, itemName = ..#ITEM, productionName = ..#PRODUCTION
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set production = ##class(Ens.Config.Production).%OpenId(productionName)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no definition of "_productionName)
	Set found = 0
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.Name '= itemName Continue
		Set found = 1
		For j = item.Settings.Count():-1:1 {
			If $ListFind(names, item.Settings.GetAt(j).Name) Do item.Settings.RemoveAt(j)
		}
		If on {
			Set position = 0
			While $ListNext(names, position, name) {
				Set setting = ##class(Ens.Config.Setting).%New()
				Set setting.Target = "Host"
				Set setting.Name = name
				Set setting.Value = $Select(name = noteName: noteValue, 1: credentialValue)
				Do item.Settings.Insert(setting)
			}
		}
		Quit
	}
	If 'found Quit $SYSTEM.Status.Error(5001, "The definition has no item "_itemName)
	Quit production.%Save()
}

/// The names of the settings of the item in the saved Orders definition, comma-separated and sorted, read from the definition itself; "<no definition>"
/// when there is none.
ClassMethod Defined() As %String
{
	Set itemName = ..#ITEM, productionName = ..#PRODUCTION
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set production = ##class(Ens.Config.Production).%OpenId(productionName)
	If '$IsObject(production) Quit "<no definition>"
	Kill names
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.Name '= itemName Continue
		For j = 1:1:item.Settings.Count() Set names(item.Settings.GetAt(j).Name) = ""
		Quit
	}
	Set list = "", name = ""
	For {
		Set name = $Order(names(name))
		If name = "" Quit
		Set list = list_$Select(list = "": "", 1: ",")_name
	}
	Quit list
}

}
