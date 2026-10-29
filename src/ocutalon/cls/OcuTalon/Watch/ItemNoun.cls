/// The noun of the items that fail, from the class of the message body (AD-15), as the JSON text that OcuTalon.Data.Incident ItemNoun holds:
/// {"one":"order","other":"orders"} for the body class of the Orders demo, else {"one":"message","other":"messages"}. Pure.
Class OcuTalon.Watch.ItemNoun
{

/// The nouns by body class, as class=one/other pairs separated by semicolons.
Parameter NOUNS = "OcuTalon.Demo.Orders.PartnerOrder=order/orders";

/// The noun of a body class that the map does not name.
Parameter DEFAULT = "message/messages";

/// The JSON text of the noun for the body class.
ClassMethod For(bodyClass As %String) As %String
{
	Set pair = ..#DEFAULT
	For i = 1:1:$Length(..#NOUNS, ";") {
		Set entry = $Piece(..#NOUNS, ";", i)
		If ($Get(bodyClass) '= "") && ($Piece(entry, "=", 1) = bodyClass) Set pair = $Piece(entry, "=", 2)
	}
	Quit {"one": ($Piece(pair, "/", 1)), "other": ($Piece(pair, "/", 2))}.%ToJSON()
}

}
