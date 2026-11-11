/// A webhook: a named, secret-protected address through which another system sends OcuTalon JSON events (AD-13, AD-14, AD-19; Story 35.3). Lane B.
/// A row is owned by the admin session that created it (SessionRef), and its events belong to that session. The only writer is
/// OcuTalon.Core.SettingsOps; the readers are OcuTalon.Web.Hook, OcuTalon.Web.HookSettings and OcuTalon.Data.Purge. Every read by the two web classes and this class's helpers is object access (an index
/// open or $Order over the class's own globals), never SQL, because the hook runs as an unauthenticated user; Data.Purge, which runs in the production, checks
/// a session's webhooks with SQL.
///   - SecretHash is the only form of the secret that is kept: HashSecret gives base64url(salt16) "." base64url(SHA-256(salt followed by the UTF-8 secret)),
///     66 characters. Matches recomputes it with the stored salt and compares the whole 43-character hash in constant time. An unknown or malformed Ref
///     is compared against DUMMYHASH, so it takes the same time. The unsalted Data.Pairing.HashCode is not used.
///   - Name is unique without regard to case.
///   - The counters live in COUNTGLOBAL, written by Web.Hook and by the Web area's purge (the only REST-side writes of the webhook; AD-1):
///     ("a", ref, "YYYY-MM-DDTHH") is the number of events accepted in that UTC clock hour (Accept), and ("r", slot) is $ListBuild(the time of the last audit
///     entry, the rejections not yet written) for a Ref, or for "?" (every unknown Ref together) (Reject). A rejection entry (RecordRejection) is an Action
///     entry of the audit log, at most one per AUDITSECONDS per slot, written at once for the first rejection after a quiet period; PurgeCounters writes
///     a count that is still pending and deletes accepted windows older than two hours.
///   - A session that owns a webhook is kept by the session purge (Data.Purge Keeps, AD-27).
Class OcuTalon.Data.Webhook Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Webhook";

/// The global of the hook's counters.
Parameter COUNTGLOBAL = "^OcuTalonP.WebhookC";

/// The SecretHash that an unknown Ref is compared against: a well-formed salt.hash that no secret produces.
Parameter DUMMYHASH = "q8cJw2mZr5nXb7vHd1LsTg.n3VqY8pRk0aUe6Ct4Wj9ZfBxM2hDoS5iGlA7yNwEcKu";

/// The most bytes of an event's body.
Parameter BODYMAX = 65536;

/// The most events of one webhook that are accepted in one UTC clock hour.
Parameter ACCEPTEDMAX = 120;

/// The seconds between two audit entries of one rejection slot.
Parameter AUDITSECONDS = 60;

/// The seconds that an accepted-event window is kept (two hours).
Parameter WINDOWKEEP = 7200;

/// The least and the most characters of a secret.
Parameter SECRETMIN = 16;

Parameter SECRETMAX = 256;

/// The most characters of a name.
Parameter NAMEMAX = 64;

/// The public reference, 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The name, 1 to NAMEMAX characters, trimmed; unique without regard to case (the default collation of a string).
Property Name As %String(MAXLEN = 64);

/// The Ref of the admin session that owns the webhook and its events.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// HashSecret's salt.hash string; never the secret.
Property SecretHash As %String(COLLATION = "EXACT", MAXLEN = 66);

/// When the row was made, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index NameIndex On Name [ Unique ];

Index SessionRefIndex On SessionRef;

/// 1 when the value is a 22-character base64url Ref.
ClassMethod IsRef(ref As %String) As %Boolean
{
	Quit ($Get(ref)?22(1AN,1"-",1"_"))
}

/// base64url of bytes, without padding.
ClassMethod Encode(bytes As %String) As %String [ Private ]
{
	Quit $Translate($SYSTEM.Encryption.Base64Encode(bytes, 1), "+/=", "-_")
}

/// The salt.hash of a secret with a new random salt of 16 bytes: base64url(salt) "." base64url(SHA-256(salt followed by the secret's UTF-8 bytes)).
ClassMethod HashSecret(secret As %String) As %String
{
	Set salt = $SYSTEM.Encryption.GenCryptRand(16)
	Quit ..Encode(salt)_"."_..Encode($SYSTEM.Encryption.SHAHash(256, salt_$ZConvert(secret, "O", "UTF8")))
}

/// 1 when the secret is the one that stored (a salt.hash) was made from. The hash is recomputed with the stored salt, and all 43 characters are
/// compared in constant time: the loop has no exit, so the time does not show where the first difference is. A malformed stored value never matches.
ClassMethod Matches(stored As %String, secret As %String) As %Boolean
{
	Set diff = 1
	Try {
		Set stored = $Get(stored)
		Set storedSalt = $Piece(stored, ".", 1)
		Set storedHash = $Piece(stored, ".", 2)
		Set salt = $SYSTEM.Encryption.Base64Decode($Translate(storedSalt, "-_", "+/")_"==")
		Set computed = ..Encode($SYSTEM.Encryption.SHAHash(256, salt_$ZConvert($Get(secret), "O", "UTF8")))
		Set diff = (($Length(stored, ".") '= 2) || ($Length(storedSalt) '= 22) || ($Length(storedHash) '= 43))
		For i = 1:1:43 {
			Set diff = $ZBoolean(diff, $ZBoolean($Ascii(computed, i), $Ascii(storedHash, i), 6), 7)
		}
	} Catch {
		Set diff = 1
	}
	Quit 'diff
}

/// The row with the Ref, or "" for an unknown or malformed Ref (an index open, no SQL).
ClassMethod Lookup(ref As %String) As OcuTalon.Data.Webhook
{
	If '..IsRef($Get(ref)) Quit ""
	Set row = ..RefIndexOpen(ref)
	Quit $Select($IsObject(row): row, 1: "")
}

/// The Refs of the session's webhooks as a list, in creation order (the order of the ids), read with $Order over SessionRefIndex.
ClassMethod ForSession(sessionRef As %String) As %List
{
	Set refs = ""
	If $Get(sessionRef) = "" Quit refs
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.WebhookI("SessionRefIndex", sessionRef, id))
		Quit:id=""
		Set row = ..%OpenId(id)
		If $IsObject(row) Set refs = refs _ $ListBuild(row.Ref)
	}
	Quit refs
}

/// 1 when a webhook has the name, without regard to case.
ClassMethod NameTaken(name As %String) As %Boolean
{
	Quit ..NameIndexExists($Get(name))
}

/// The catalog key of what is wrong with a name, or "" when it is acceptable: a value holding the two characters that open a setting reference
/// (settings.refusedExpansion); a name that is not 1 to NAMEMAX characters after trimming or that holds a control character (settings.webhookBadName).
ClassMethod NameProblem(name As %String) As %String
{
	Set name = $Get(name)
	If name [ "@{" Quit "settings.refusedExpansion"
	Set trimmed = $ZStrip(name, "<>W")
	If ($Length(trimmed) < 1) || ($Length(trimmed) > ..#NAMEMAX) || ($ZStrip(trimmed, "*C") '= trimmed) Quit "settings.webhookBadName"
	Quit ""
}

/// The catalog key of what is wrong with a secret, or "" when it is acceptable: a value holding the two characters that open a setting reference
/// (settings.refusedExpansion); a secret that is not SECRETMIN to SECRETMAX characters, each printable ASCII from 0x21 to 0x7E (settings.webhookBadSecret).
ClassMethod SecretProblem(secret As %String) As %String
{
	Set secret = $Get(secret)
	If secret [ "@{" Quit "settings.refusedExpansion"
	Set length = $Length(secret)
	If (length < ..#SECRETMIN) || (length > ..#SECRETMAX) Quit "settings.webhookBadSecret"
	Set bad = 0
	For i = 1:1:length {
		Set code = $Ascii(secret, i)
		If (code < 33) || (code > 126) Set bad = 1
	}
	Quit $Select(bad: "settings.webhookBadSecret", 1: "")
}

/// The accepted-event window of a UTC time: its date and hour, YYYY-MM-DDTHH.
ClassMethod Window(now As %String) As %String [ Private ]
{
	Quit $Extract(now, 1, 13)
}

/// Counts one valid event of the webhook in the UTC clock hour of now. Returns 1 when it is accepted. Returns 0 when the hour already holds
/// ACCEPTEDMAX events: the count is then left as it was, and retryAfter is the seconds to the next hour.
ClassMethod Accept(ref As %String, now As %String, Output retryAfter As %Integer) As %Boolean
{
	Set retryAfter = 0
	Set window = ..Window(now)
	Set count = $Increment(@(..#COUNTGLOBAL)@("a", ref, window))
	If count <= ..#ACCEPTEDMAX Quit 1
	Do $Increment(@(..#COUNTGLOBAL)@("a", ref, window), -1)
	Set seconds = ##class(OcuTalon.Data.Time).Seconds(now)
	Set retryAfter = $Select(seconds = "": 3600, 1: 3600 - (seconds # 3600))
	Quit 0
}

/// Gives back the count of one event that Accept counted and that the production did not take (the hook answered 503), in the hour of now. The count never
/// goes below zero.
ClassMethod Unaccept(ref As %String, now As %String)
{
	Set node = $Name(@(..#COUNTGLOBAL)@("a", ref, ..Window(now)))
	If $Get(@node) > 0 Do $Increment(@node, -1)
}

/// Counts one rejection in the slot (a Ref, or "?" for every unknown Ref). Returns 1 when an audit entry is due, with count the rejections since the
/// previous entry (this one included), and the slot is then marked as written at now with none pending. Returns 0 within AUDITSECONDS of the previous entry,
/// with the rejection kept as pending. A previous entry stamped later than now (the clock was set back) counts as due, so that no clock change silences the audit.
ClassMethod Reject(slot As %String, now As %String, Output count As %Integer) As %Boolean
{
	Set count = 0, due = 0
	Set lockName = $Name(@(..#COUNTGLOBAL)@("r", slot))
	Lock +@lockName:2
	If '$Test Quit 0
	Try {
		Set node = $Get(@lockName)
		Set last = $ListGet(node, 1), pending = $ListGet(node, 2) + 1
		Set age = $Select(last = "": ..#AUDITSECONDS, 1: ##class(OcuTalon.Data.Time).Seconds(now) - ##class(OcuTalon.Data.Time).Seconds(last))
		If (age < 0) || (age >= ..#AUDITSECONDS) {
			Set due = 1, count = pending
			Set @lockName = $ListBuild(now, 0)
		} Else {
			Set @lockName = $ListBuild(last, pending)
		}
	} Catch {
		Set due = 0
	}
	Lock -@lockName
	Quit due
}

/// The slots whose pending rejections are older than AUDITSECONDS at now, or stamped later than now, as pending(n) = $ListBuild(slot, count); each is marked as
/// written at now.
ClassMethod Flush(now As %String, Output pending) As %Integer
{
	Kill pending
	Set total = 0
	Set slot = ""
	For {
		Set slot = $Order(@(..#COUNTGLOBAL)@("r", slot))
		Quit:slot=""
		Set lockName = $Name(@(..#COUNTGLOBAL)@("r", slot))
		Lock +@lockName:2
		If '$Test Continue
		Set node = $Get(@lockName)
		Set last = $ListGet(node, 1), count = +$ListGet(node, 2)
		Set age = ##class(OcuTalon.Data.Time).Seconds(now) - ##class(OcuTalon.Data.Time).Seconds(last)
		If (count > 0) && ((age < 0) || (age >= ..#AUDITSECONDS)) {
			Set total = total + 1
			Set pending(total) = $ListBuild(slot, count)
			Set @lockName = $ListBuild(now, 0)
		}
		Lock -@lockName
	}
	Quit total
}

/// Writes the Action entry of a slot's rejections: action webhook_rejected, channel webhook, target the Ref (empty for the unknown slot "?"), result
/// rejected, counts.rejected the number. The irisUser is the process's user. The entry holds no secret, header, body or caller address. The status is the
/// audit writer's.
ClassMethod RecordRejection(slot As %String, count As %Integer) As %Status
{
	Set data = {}
	Do data.%Set("irisUser", $Username, "string")
	Do data.%Set("sessionRef", "", "string")
	Do data.%Set("channel", "webhook", "string")
	Do data.%Set("action", "webhook_rejected", "string")
	Do data.%Set("target", $Select(slot = "?": "", 1: slot), "string")
	Do data.%Set("result", "rejected", "string")
	Do data.%Set("counts", {"rejected": (count)})
	Do data.%Set("approvalRef", "", "string")
	Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
}

/// The Web area's purge of the counters (AD-27): the rejections that are still pending after AUDITSECONDS are written as audit entries, and the
/// accepted-event windows older than WINDOWKEEP seconds are deleted. now is the current UTC time unless a test gives one. The result is the first error;
/// a failed entry is logged without any request data, and the rest still runs.
ClassMethod PurgeCounters(now As %String = "") As %Status
{
	If now = "" Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = $$$OK
	Set total = ..Flush(now, .pending)
	For i = 1:1:total {
		Set one = ..RecordRejection($ListGet(pending(i), 1), $ListGet(pending(i), 2))
		If $$$ISERR(one) && $$$ISOK(sc) Set sc = one
	}
	Set cutoff = ..Window(##class(OcuTalon.Data.Time).AddSeconds(now, -..#WINDOWKEEP))
	Set ref = ""
	For {
		Set ref = $Order(@(..#COUNTGLOBAL)@("a", ref))
		Quit:ref=""
		Set window = ""
		For {
			Set window = $Order(@(..#COUNTGLOBAL)@("a", ref, window))
			Quit:window=""
			If cutoff ] window Kill @(..#COUNTGLOBAL)@("a", ref, window)
		}
	}
	Quit sc
}

Storage Default
{
<Data name="WebhookDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>SessionRef</Value>
</Value>
<Value name="5">
<Value>SecretHash</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.WebhookD</DataLocation>
<DefaultData>WebhookDefaultData</DefaultData>
<IdLocation>^OcuTalonP.WebhookD</IdLocation>
<IndexLocation>^OcuTalonP.WebhookI</IndexLocation>
<StreamLocation>^OcuTalonP.WebhookS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
