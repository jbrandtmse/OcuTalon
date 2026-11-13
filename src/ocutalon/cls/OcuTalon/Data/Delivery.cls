/// One row per session's copy of an outbound message: what an *Out operation sent, and where, so that an edit in place finds it (AD-14). Lane B.
/// WebChatOut is the first writer (Story 2.7) and the web chat's copy of a notice card: its row keeps the card as it was shown
/// (Kind, the rendered Text, DecisionRef, DueAt and FallbackReason), so that a reload shows the card as it was sent (DW-62).
/// A web digest card's row also keeps the card's check rows (CheckRows, JSON), so that a reload shows them (Story 18.4); a row written before
/// CheckRows existed reads it as empty and draws the card without the rows.
/// A row is read only through Ownership (RecentNotices for the chat, DeliveryFor for an edit in place), except the rows of channel email, which EmailOut and
/// EmailIn read through the methods SentByEmail, TakeEcho, DigestEmailsSince and DigestEmailSent below.
/// A row of channel email is EmailOut's: its ChannelMessageId is the random Ref that the email carries in its X-OcuTalon-Ref header, so that EmailIn
/// can tell the mail that comes back to the polled mailbox from other mail (SentByEmail, TakeEcho). A digest's row (Kind digest) also keeps DigestKey,
/// which makes one digest go by email once; so does the row of a tool send with an IdempotencyKey, whose DigestKey is the hash of the key (EmailOut.ToolKeyOf)
/// and which makes the send go once for the key of its session. These rows keep no text and no address.
Class OcuTalon.Data.Delivery Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Delivery";

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The channel's message id; for Telegram <ChatRef>:<message_id> (AD-14). For a web card, the card's Ref.
Property ChannelMessageId As %String(MAXLEN = 128);

/// The Ref of the approval request (AD-11).
Property ApprovalRef As %String(MAXLEN = 22);

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

/// The kind of the notification the row delivers: one of Msg.Enum NOTIFICATIONKIND; empty for a reply.
Property Kind As %String(MAXLEN = 32);

/// The rendered text of a web notice card, exactly as it was sent; empty for any other row.
Property Text As %String(MAXLEN = "");

/// The Ref of the Decision row behind the notification, when a decision raised it (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// When the thing a reminder card is about is due, UTC to the second.
Property DueAt As %String(MAXLEN = 20);

/// The fallback reason the card shows: one of Msg.Enum FALLBACKREASON; empty when the card is not a fallback. On EmailOut's claim of an approval (a row
/// of channel email with an ApprovalRef) or of a keyed tool send (a row of channel email with a DigestKey and no Kind) it is instead pending while the send
/// has not finished, failed when it did not go through, and empty once sent. A failed approval send keeps its row, marked failed; a failed keyed tool
/// send deletes its row, except when the email may still have reached the server, which marks it maysent, or an error followed the claim, which marks it failed.
Property FallbackReason As %String(MAXLEN = 32);

/// The check rows of a web digest card, as the JSON array of the digest's Slots rows ({result, entry, finding, checkedAt}); empty for any other row.
Property CheckRows As %String(MAXLEN = "");

/// The key of a digest that went by email (EmailOut.DigestKeyOf), or of a tool send with an IdempotencyKey (EmailOut.ToolKeyOf), 22 characters; empty for
/// any other row. One digest sends once: a row with the key means the digest was sent. A keyed tool send's row with the key is sent when its
/// FallbackReason is empty.
Property DigestKey As %String(MAXLEN = 22);

/// When EmailIn took the email that came back with this row's Ref and made no Item of it, UTC to the second; empty until then. A Ref is used once.
Property EchoedAt As %String(MAXLEN = 20);

Index ApprovalRefChannelOwnerRefIndex On (ApprovalRef, Channel, OwnerRef);

Index OwnerRefChannelIndex On (OwnerRef, Channel);

/// Records one session's copy of an outbound message: the channel's message id, the approval request it carries, if any, and
/// for a web card its kind, text, decision, due time, fallback reason and, for a digest card, its check rows; digestKey is the key of a digest that went by email. RecordedAt is the time now. An empty owner or a
/// channel outside Msg.Enum CHANNEL is an error status and records nothing. row is the saved row, "" when nothing was saved.
ClassMethod Record(ownerRef As %String, channel As %String, channelMessageId As %String, approvalRef As %String, kind As %String = "", text As %String = "", decisionRef As %String = "", dueAt As %String = "", fallbackReason As %String = "", Output row As OcuTalon.Data.Delivery, checkRows As %String = "", digestKey As %String = "") As %Status
{
	Set row = ""
	If $Get(ownerRef) = "" Quit $SYSTEM.Status.Error(5001, "A delivery needs the Ref of its owner")
	If '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#CHANNEL), $Get(channel)) Quit $SYSTEM.Status.Error(5001, "'"_$Get(channel)_"' is not a channel")
	Set row = ..%New()
	Set row.OwnerRef = ownerRef
	Set row.Channel = channel
	Set row.ChannelMessageId = $Get(channelMessageId)
	Set row.ApprovalRef = $Get(approvalRef)
	Set row.Kind = kind
	Set row.Text = text
	Set row.DecisionRef = decisionRef
	Set row.DueAt = dueAt
	Set row.FallbackReason = fallbackReason
	Set row.CheckRows = checkRows
	Set row.DigestKey = digestKey
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	If $SYSTEM.Status.IsError(sc) Set row = ""
	Quit sc
}

/// The ids of the sent rows of channel email whose ChannelMessageId is exactly ref (the column compares without regard to case and trailing spaces, so
/// the value read is compared again here, as a Ref is case-sensitive): "sent" means the row is not the claim of a send that failed or never
/// finished (its FallbackReason is empty). Read by SQL on Channel and ChannelMessageId; the table has no index on either, so the cost grows with the
/// table, and EmailIn asks only for an email that carries the header.
ClassMethod SentEmailIds(ref As %String) As %List [ Private ]
{
	Set ids = ""
	If $Get(ref) = "" Quit ids
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ChannelMessageId, FallbackReason FROM OcuTalon_Data.Delivery WHERE Channel = ? AND ChannelMessageId = ?", "email", ref)
	If rows.%SQLCODE < 0 Quit ids
	While rows.%Next() {
		If (rows.%Get("ChannelMessageId") = ref) && (rows.%Get("FallbackReason") = "") Set ids = ids_$ListBuild(rows.%Get("ID"))
	}
	Quit ids
}

/// 1 when a sent row of channel email has the ChannelMessageId ref (the Ref of an email that EmailOut sent). 0 for an empty, unknown or unsent Ref.
ClassMethod SentByEmail(ref As %String) As %Boolean
{
	Quit $ListLength(..SentEmailIds($Get(ref))) > 0
}

/// Takes the one use of the Ref of a sent email: 1 and the row's EchoedAt is set to now when a sent row of channel email has the Ref and was not
/// taken before; 0 when there is none or it was taken (the second use of a Ref is not the first). Under a lock on the Ref, so two polls cannot both take it.
ClassMethod TakeEcho(ref As %String) As %Boolean
{
	Set taken = 0
	Set ref = $Get(ref)
	If ref = "" Quit 0
	Lock +^OcuTalon.Delivery.Echo(ref):10
	If '$Test Quit 0
	Try {
		Set ids = ..SentEmailIds(ref)
		If $ListLength(ids) = 1 {
			Set row = ..%OpenId($List(ids, 1))
			If $IsObject(row) && (row.EchoedAt = "") {
				Set row.EchoedAt = ##class(OcuTalon.Data.Time).NowUtc()
				Set taken = $$$ISOK(row.%Save())
			}
		}
	} Catch exception {
		Set taken = 0
	}
	Lock -^OcuTalon.Delivery.Echo(ref)
	Quit taken
}

/// How many digests went by email to the mailbox since the UTC instant: the rows of channel email and Kind digest of every owner, as the instance has one
/// mailbox (email.address) and its owner session can change. Read by SQL with no index on Kind, so the cost grows with the table. -1 when the count cannot
/// be read.
ClassMethod DigestEmailsSince(sinceUtc As %String) As %Integer
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE Channel = ? AND Kind = ? AND RecordedAt >= ?", "email", "digest", sinceUtc)
	If rows.%SQLCODE < 0 || 'rows.%Next() Quit -1
	Quit +rows.%GetData(1)
}

/// 1 when a row of channel email of the owner has exactly the DigestKey: the digest was sent by email already (the key is case-sensitive).
ClassMethod DigestEmailSent(ownerRef As %String, digestKey As %String) As %Boolean
{
	If $Get(digestKey) = "" Quit 0
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT DigestKey FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = ? AND DigestKey = ?", ownerRef, "email", digestKey)
	If rows.%SQLCODE < 0 Quit 0
	Set found = 0
	While 'found && rows.%Next() {
		Set found = (rows.%Get("DigestKey") = digestKey)
	}
	Quit found
}

/// Finds the channel message id of the approval message to edit in place: the newest row of the owner whose approval Ref and
/// channel are exactly these (case-sensitive), read through Ownership.DeliveryFor. "" when there is none, for an empty value
/// and for the owners instance and eval, which have no rows to read (AD-14).
ClassMethod FindByApproval(approvalRef As %String, channel As %String, ownerRef As %String) As %String
{
	If ($Get(approvalRef) = "") || ($Get(channel) = "") || ($Get(ownerRef) = "") Quit ""
	Set row = ##class(OcuTalon.Data.Ownership).DeliveryFor(approvalRef, channel, ownerRef, .sc)
	If $SYSTEM.Status.IsError(sc) || '$IsObject(row) Quit ""
	Quit row.ChannelMessageId
}

/// Finds the channel message id of a notice's copy to edit in place: the newest row of the owner and channel whose DecisionRef is
/// exactly ref (case-sensitive), the notice's Ref being its Decision's Ref, read through Ownership.DeliveryByRef. "" when there is
/// none, for an empty value and for the owners instance and eval, which have no rows to read (AD-14).
ClassMethod FindByRef(ref As %String, channel As %String, ownerRef As %String) As %String
{
	If ($Get(ref) = "") || ($Get(channel) = "") || ($Get(ownerRef) = "") Quit ""
	Set row = ##class(OcuTalon.Data.Ownership).DeliveryByRef(ref, channel, ownerRef, .sc)
	If $SYSTEM.Status.IsError(sc) || '$IsObject(row) Quit ""
	Quit row.ChannelMessageId
}

Storage Default
{
<Data name="DeliveryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>OwnerRef</Value>
</Value>
<Value name="3">
<Value>Channel</Value>
</Value>
<Value name="4">
<Value>ChannelMessageId</Value>
</Value>
<Value name="5">
<Value>ApprovalRef</Value>
</Value>
<Value name="6">
<Value>RecordedAt</Value>
</Value>
<Value name="7">
<Value>Kind</Value>
</Value>
<Value name="8">
<Value>Text</Value>
</Value>
<Value name="9">
<Value>DecisionRef</Value>
</Value>
<Value name="10">
<Value>DueAt</Value>
</Value>
<Value name="11">
<Value>FallbackReason</Value>
</Value>
<Value name="12">
<Value>CheckRows</Value>
</Value>
<Value name="13">
<Value>DigestKey</Value>
</Value>
<Value name="14">
<Value>EchoedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.DeliveryD</DataLocation>
<DefaultData>DeliveryDefaultData</DefaultData>
<IdLocation>^OcuTalonP.DeliveryD</IdLocation>
<IndexLocation>^OcuTalonP.DeliveryI</IndexLocation>
<StreamLocation>^OcuTalonP.DeliveryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
