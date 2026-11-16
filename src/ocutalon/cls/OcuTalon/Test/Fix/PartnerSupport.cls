/// Helper of the partner-warning tests (Story 23.13; not a test case): a Settings partner contact row of a test, and its removal, and the mailbox keys that decide whether a warning is sent or kept. A test makes
/// its contacts with names that begin zzpc and removes them in its OnAfterOneTest (Remove), so that no test leaves a contact or depends on another's; it saves the mailbox keys and the online-demo flag
/// before it changes them (SaveMailbox) and puts them back after it (RestoreMailbox).
Class OcuTalon.Test.Fix.PartnerSupport [ Abstract ]
{

/// The namespace and the production that a test contact concerns unless it says otherwise.
Parameter NAMESPACE = "ZZNS";

Parameter PRODUCTION = "ZZPROD";

/// Makes a contact with the name and the address that concerns the productions (the JSON text of its Productions member; the pair NAMESPACE and PRODUCTION when empty); its row ID.
ClassMethod Contact(name As %String, address As %String, productions As %String = "") As %Integer
{
	Set row = ##class(OcuTalon.Data.PartnerContact).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Name = name
	Set row.Email = address
	Set row.Productions = $Select(productions '= "": productions, 1: [{"namespace": (..#NAMESPACE), "production": (..#PRODUCTION)}].%ToJSON())
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.UpdatedAt = row.CreatedAt
	$$$ThrowOnError(row.%Save())
	Quit row.%Id()
}

/// Changes the address of the contact (its row ID).
ClassMethod Readdress(id As %Integer, address As %String)
{
	Set row = ##class(OcuTalon.Data.PartnerContact).%OpenId(id)
	Set row.Email = address
	$$$ThrowOnError(row.%Save())
}

/// Removes the contacts with the row IDs (comma-separated); an ID that has no row is skipped.
ClassMethod Remove(ids As %String)
{
	For i = 1:1:$Length(ids, ",") {
		Set id = $Piece(ids, ",", i)
		If id '= "" Do ##class(OcuTalon.Data.PartnerContact).%DeleteId(id)
	}
}

/// Saves the product keys email.address and email.owner and the public flag onlineDemo, for RestoreMailbox.
ClassMethod SaveMailbox()
{
	Kill ^||OcuTalonPartnerSupport
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^||OcuTalonPartnerSupport("saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Set ^||OcuTalonPartnerSupport("online") = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
}

/// Connects a mailbox (on 1: email.address holds the address) or removes both keys (on 0).
ClassMethod Mailbox(on As %Boolean, address As %String = "zzpartnersupport@example.com")
{
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	}
	If on Do ##class(OcuTalon.Data.Setting).Set("email.address", address)
}

/// Puts the keys and the flag that SaveMailbox saved back.
ClassMethod RestoreMailbox()
{
	Do ..Mailbox(0)
	For key = "email.address", "email.owner" {
		If $Data(^||OcuTalonPartnerSupport("saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	If $Data(^||OcuTalonPartnerSupport("online"), online) Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", online)
	Kill ^||OcuTalonPartnerSupport
}

}
