/// One row per email that EmailIn has seen in a mailbox (AD-14, AD-33; Lane B). A mailbox is named by Mailbox, the SHA-256 hash in
/// upper-case hexadecimal of the server, the port and the user name (IdentityOf), so no address is stored. Uidl is the server's unique id
/// of the email. Baseline is 1 for a row that the first poll of a mailbox recorded without making an Item. A row with the Uidl MARKER
/// (never a real Uidl: a Uidl has no space) says that the mailbox has been baselined, also when it was empty. The only writer is
/// Channel.Email.Adapter, which records a row after it has sent the email on, deletes the rows of an email that is no longer listed and the
/// rows of every other mailbox, and so lets an email that was seen never become an Item again, also after a restart.
Class OcuTalon.Data.MailSeen Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.MailSeen";

/// The Uidl of the row that marks a mailbox as baselined.
Parameter MARKER = "baseline marker";

/// The mailbox's identity: SHA-256 of server, port and user name, 64 upper-case hexadecimal digits. Compared exactly.
Property Mailbox As %String(COLLATION = "EXACT", MAXLEN = 64);

/// The server's unique id of the email. Compared exactly.
Property Uidl As %String(COLLATION = "EXACT", MAXLEN = 70);

/// 1 for a row of the first poll, which made no Item.
Property Baseline As %Boolean [ InitialExpression = 0 ];

/// When the row was recorded, UTC to the second.
Property SeenAt As %String(MAXLEN = 20);

Index MailboxUidlIndex On (Mailbox, Uidl) [ Unique ];

Index MailboxIndex On Mailbox;

/// The identity of a mailbox: the SHA-256 hash, in upper-case hexadecimal, of the server, the port and the user name, each followed by a
/// line feed (a value cannot hold one, so two mailboxes never share a hash input).
ClassMethod IdentityOf(server As %String, port As %Integer, user As %String) As %String
{
	Set hash = $SYSTEM.Encryption.SHAHash(256, $ZConvert($Get(server)_$Char(10)_+$Get(port)_$Char(10)_$Get(user)_$Char(10), "O", "UTF8"))
	Set hex = ""
	For i = 1:1:$Length(hash) {
		Set hex = hex_$Extract("0"_$ZHex($Ascii(hash, i)), *-1, *)
	}
	Quit hex
}

/// 1 when the mailbox has a row for the Uidl.
ClassMethod Seen(mailbox As %String, uidl As %String) As %Boolean
{
	Quit ..MailboxUidlIndexExists(mailbox, uidl)
}

/// 1 when the mailbox has been baselined (its marker row exists).
ClassMethod Baselined(mailbox As %String) As %Boolean
{
	Quit ..MailboxUidlIndexExists(mailbox, ..#MARKER)
}

/// Records the Uidl as seen for the mailbox, with Baseline 1 or 0 and SeenAt now (UTC); a Uidl that is already recorded is left as it is.
ClassMethod Record(mailbox As %String, uidl As %String, baseline As %Boolean = 0) As %Status
{
	If (mailbox = "") || (uidl = "") Quit $SYSTEM.Status.Error(5001, "A seen email needs a mailbox and a uidl")
	If ..MailboxUidlIndexExists(mailbox, uidl) Quit $$$OK
	Set row = ..%New()
	Set row.Mailbox = mailbox
	Set row.Uidl = uidl
	Set row.Baseline = baseline
	Set row.SeenAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row.%Save()
}

/// The Uidls recorded for the mailbox, marker excluded, as a list.
ClassMethod Uidls(mailbox As %String) As %List
{
	Set list = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Uidl FROM OcuTalon_Data.MailSeen WHERE Mailbox = ? AND Uidl <> ?", mailbox, ..#MARKER)
	If result.%SQLCODE < 0 Quit ""
	While result.%Next() {
		Set list = list_$ListBuild(result.%GetData(1))
	}
	Quit list
}

/// Deletes the rows of the mailbox whose Uidl is not listed (listed(uidl) defined for each listed Uidl, so that a mailbox of any size fits;
/// the marker stays) and every row of any other mailbox; returns the first error status or OK.
ClassMethod Trim(mailbox As %String, ByRef listed) As %Status
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Mailbox, Uidl FROM OcuTalon_Data.MailSeen")
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Set count = 0
	While result.%Next() {
		Set uidl = result.%GetData(3)
		If (result.%GetData(2) = mailbox) && ((uidl = ..#MARKER) || ((uidl '= "") && $Data(listed(uidl)))) Continue
		Set ids($Increment(count)) = result.%GetData(1)
	}
	Set sc = $$$OK
	Set n = ""
	For {
		Set n = $Order(ids(n), 1, id)
		Quit:n=""
		Set one = ..%DeleteId(id)
		If $$$ISERR(one) && $$$ISOK(sc) Set sc = one
	}
	Quit sc
}

Storage Default
{
<Data name="MailSeenDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Mailbox</Value>
</Value>
<Value name="3">
<Value>Uidl</Value>
</Value>
<Value name="4">
<Value>Baseline</Value>
</Value>
<Value name="5">
<Value>SeenAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.MailSeenD</DataLocation>
<DefaultData>MailSeenDefaultData</DefaultData>
<IdLocation>^OcuTalonP.MailSeenD</IdLocation>
<IndexLocation>^OcuTalonP.MailSeenI</IndexLocation>
<StreamLocation>^OcuTalonP.MailSeenS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
