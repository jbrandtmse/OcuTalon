/// The one source of public references (the identifiers convention). A reference is 22 characters from
/// A-Z, a-z, 0-9, - and _, with no padding, and carries 128 random bits.
Class OcuTalon.Bridge.Ids
{

/// A new reference: 16 bytes from $SYSTEM.Encryption.GenCryptRand, base64url-encoded without padding.
ClassMethod NewRef() As %String
{
	Quit $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(16), 1), "+/=", "-_")
}

}
