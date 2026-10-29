/// A Telegram chat paired with a session (AD-4, AD-14), and a session's pairing code. Lane B. A row is one of two kinds, and the
/// kind decides which columns are set:
///   - A chat row has a ChatId. Its Ref is the ChatRef that messages carry. Its SessionRef is set only while the chat is paired,
///     because Ownership.Pairing counts every row with a SessionRef as a live pairing.
///   - A code row holds one session's pairing code in CodeSessionRef, as the hash of the code (HashCode) with its expiry and the
///     time it was used. It has no ChatId and no SessionRef. A session has at most one code row, and a hash is in at most one: both
///     indexes are unique (an empty value is not checked, so the chat rows share it), and StoreCode replaces the session's hash.
/// The columns with a COLLATION of EXACT, and every lookup below, compare case-sensitively; the default collation of the older
/// columns ignores case, so Chat re-checks the Ref after the index open. The only writers of a chat row's SessionRef and of
/// CodeUsedAt are in OcuTalon.Core.SessionOps.
Class OcuTalon.Data.Pairing Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Pairing";

/// The seconds between two replies to an unpaired chat (TakeReplySlot).
Parameter REPLYSECONDS = 60;

/// The error code that an index open answers for a key that has no row (KeyValueNotFoundOpen).
Parameter NOTFOUND = 5770;

/// The ChatRef: the chat reference that messages carry instead of a chat id.
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// The Telegram chat id; never passed to the audit writer or logs (AD-14).
Property ChatId As %String(MAXLEN = 32);

/// The name of the chat; never passed to the audit writer or logs (AD-14).
Property DisplayName As %String(MAXLEN = 128);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

/// A code row: the Ref of the session that the code belongs to.
Property CodeSessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// A code row: HashCode of the pairing code. The code itself is stored nowhere (AD-4).
Property CodeHash As %String(COLLATION = "EXACT", MAXLEN = 64);

/// A code row: when the code expires, UTC to the second.
Property CodeExpiresAt As %String(COLLATION = "EXACT", MAXLEN = 20);

/// A code row: when the code was used, UTC to the second, or empty while it is unused.
Property CodeUsedAt As %String(COLLATION = "EXACT", MAXLEN = 20);

/// A chat row: when the chat was last given a reply without a pairing (TakeReplySlot), UTC to the second.
Property ReplySlotAt As %String(COLLATION = "EXACT", MAXLEN = 20);

/// When a writer last touched the row, UTC to the second. Purge counts a row without a session as old by this time.
Property SeenAt As %String(COLLATION = "EXACT", MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Index ChatIdIndex On ChatId;

Index CodeSessionRefIndex On CodeSessionRef [ Unique ];

Index CodeHashIndex On CodeHash [ Unique ];

/// The hash of a pairing code: SHA-256 of the code's UTF-8 bytes, base64url, 43 characters, no padding. Empty for an empty code.
/// Both lanes hash through this method, and only the hash is ever stored or sent (AD-4).
ClassMethod HashCode(code As %String) As %String
{
	If $Get(code) = "" Quit ""
	Quit $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, $ZConvert(code, "O", "UTF8")), 1), "+/=", "-_")
}

/// Records that a chat was seen: the Ref of the chat row of this chat id, made when there is none. The chat id is a whole number of
/// at most 20 digits with an optional minus sign. The name is stripped of control characters, trimmed and cut to 128 characters.
/// A known chat keeps its Ref and SessionRef; its name and SeenAt are updated. The Ref is "" with an error status (sc) that names
/// the rule and never the value when the id is not valid, and when the row could not be looked up, written or locked. It reads with SQL, so it runs
/// in a production job (the Telegram service), never in a web request.
ClassMethod RecordChat(chatId As %String, displayName As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	Set chatId = $Get(chatId)
	If chatId '? .1"-"1.20N {
		Set sc = $SYSTEM.Status.Error(5001, "A Telegram chat id is a whole number of at most 20 digits with an optional minus sign")
		Quit ""
	}
	Set name = $Extract($ZStrip($ZStrip($Get(displayName), "*C"), "<>W"), 1, 128)
	Set ref = ""
	Set locked = 0
	Try {
		Lock +^OcuTalon.Data.Pairing("chat", chatId):5
		If '$Test {
			Set sc = $SYSTEM.Status.Error(5001, "The chat's row is busy, so the chat was not recorded")
		} Else {
			Set locked = 1
			Set now = ##class(OcuTalon.Data.Time).NowUtc()
			Set id = ""
			Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Pairing WHERE ChatId = ? ORDER BY ID", chatId)
			If (found.%SQLCODE >= 0) && found.%Next() Set id = found.%Get("ID")
			If found.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "The chat's row could not be looked up, so the chat was not recorded")
			Set row = ""
			If id '= "" Set row = ..%OpenId(id, 4, .sc)
			If $IsObject(row) && (row.ChatId '= chatId) Set row = ""
			If $SYSTEM.Status.IsOK(sc) {
				If '$IsObject(row) {
					Set row = ..%New()
					Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
					Set row.ChatId = chatId
					Set row.CreatedAt = now
				}
				Set row.DisplayName = name
				Set row.SeenAt = now
				Set sc = row.%Save()
				If $SYSTEM.Status.IsOK(sc) Set ref = row.Ref
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
		Set ref = ""
	}
	If locked Lock -^OcuTalon.Data.Pairing("chat", chatId)
	Quit ref
}

/// Takes the chat's reply slot: 1 and ReplySlotAt = now when no reply slot was taken in the last REPLYSECONDS seconds, otherwise 0.
/// It is 0 for a Ref that is not a chat row, and when the row's lock is not taken. The check and the write run under the row's
/// exclusive lock, so two callers never both get the slot.
ClassMethod TakeReplySlot(chatRef As %String) As %Boolean
{
	Set taken = 0
	Try {
		Set chat = ##class(OcuTalon.Data.Pairing).Chat($Get(chatRef))
		If $IsObject(chat) {
			Set id = chat.%Id()
			Set chat = ""
			Set row = ..%OpenId(id, 4, .sc)
			If $IsObject(row) && (row.Ref = chatRef) {
				Set now = ##class(OcuTalon.Data.Time).NowUtc()
				Set free = ##class(OcuTalon.Data.Time).AddSeconds(row.ReplySlotAt, ..#REPLYSECONDS)
				If (free = "") || (##class(OcuTalon.Data.Time).Seconds(now) >= ##class(OcuTalon.Data.Time).Seconds(free)) {
					Set row.ReplySlotAt = now
					Set taken = $SYSTEM.Status.IsOK(row.%Save())
				}
			}
		}
	} Catch {
		Set taken = 0
	}
	Quit taken
}

/// Stores the session's pairing code as its hash with its expiry: the session's one code row is made, or its hash and expiry are
/// replaced and its used mark cleared. An empty session or hash, or an expiry that is not a UTC time, is an error status and no
/// row is written. The code itself never reaches this method (AD-4).
ClassMethod StoreCode(sessionRef As %String, codeHash As %String, expiresAt As %String) As %Status
{
	Set sessionRef = $Get(sessionRef), codeHash = $Get(codeHash), expiresAt = $Get(expiresAt)
	If sessionRef = "" Quit $SYSTEM.Status.Error(5001, "A pairing code belongs to a session: the session is empty")
	If codeHash = "" Quit $SYSTEM.Status.Error(5001, "A pairing code is stored as its hash: the hash is empty")
	If ##class(OcuTalon.Data.Time).Seconds(expiresAt) = "" Quit $SYSTEM.Status.Error(5001, "A pairing code expires at a UTC time: the expiry is not one")
	Set sc = $SYSTEM.Status.OK()
	Set locked = 0
	Try {
		Lock +^OcuTalon.Data.Pairing("code", sessionRef):5
		If '$Test {
			Set sc = $SYSTEM.Status.Error(5001, "The session's code row is busy, so the code was not stored")
		} Else {
			Set locked = 1
			Set now = ##class(OcuTalon.Data.Time).NowUtc()
			Set row = ..CodeSessionRefIndexOpen(sessionRef, 4, .sc)
			If '$IsObject(row) && $SYSTEM.Status.Equals(sc, ..#NOTFOUND) Set sc = $SYSTEM.Status.OK()
			If $SYSTEM.Status.IsOK(sc) {
				If '$IsObject(row) {
					Set row = ..%New()
					Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
					Set row.CodeSessionRef = sessionRef
					Set row.CreatedAt = now
				}
				Set row.CodeHash = codeHash
				Set row.CodeExpiresAt = expiresAt
				Set row.CodeUsedAt = ""
				Set row.SeenAt = now
				Set sc = row.%Save()
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If locked Lock -^OcuTalon.Data.Pairing("code", sessionRef)
	Quit sc
}

/// The chat row with exactly this Ref, or "" when there is none, when the row is a code row, or when the Ref differs only in case
/// (the default index collation of Ref ignores case).
ClassMethod Chat(chatRef As %String) As OcuTalon.Data.Pairing
{
	If $Get(chatRef) = "" Quit ""
	Set row = ..RefIndexOpen(chatRef)
	If '$IsObject(row) Quit ""
	If (row.Ref '= chatRef) || (row.ChatId = "") Quit ""
	Quit row
}

/// The code row whose CodeHash is exactly this hash, or "".
ClassMethod ForCode(codeHash As %String) As OcuTalon.Data.Pairing
{
	If $Get(codeHash) = "" Quit ""
	Set row = ..CodeHashIndexOpen(codeHash)
	If '$IsObject(row) || (row.CodeHash '= codeHash) Quit ""
	Quit row
}

/// Deletes the rows without a session (the chats that are not paired and the pairing codes) that no writer touched for daysToKeep
/// days: those whose SeenAt, or CreatedAt when SeenAt is empty, is before now (Data.Time.NowUtc) moved back daysToKeep whole days,
/// by date arithmetic on the UTC date. A row with a SessionRef stays whatever its age. daysToKeep must be a whole number of at least 1;
/// anything else is an error status and nothing is deleted.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set bad = $SYSTEM.Status.Error(5001, "OcuTalon.Data.Pairing.Purge needs a whole number of days, at least 1, not '"_$Extract($Get(daysToKeep), 1, 40)_"'")
	If $Get(daysToKeep) '? 1.N Quit bad
	Set sc = $SYSTEM.Status.OK()
	Try {
		If +daysToKeep < 1 {
			Set sc = bad
		} Else {
			Set now = ##class(OcuTalon.Data.Time).NowUtc()
			Set day = $ZDateH($Piece(now, "T", 1), 3) - daysToKeep
			If day >= 0 {
				Set cutoff = $ZDate(day, 3)_"T"_$Piece(now, "T", 2)
				Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Pairing WHERE (SessionRef IS NULL OR SessionRef = '') AND (CASE WHEN SeenAt IS NULL OR SeenAt = '' THEN CreatedAt ELSE SeenAt END) < ?", cutoff)
				If result.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "Deleting the old pairing rows failed: "_result.%Message)
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

Storage Default
{
<Data name="PairingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>ChatId</Value>
</Value>
<Value name="5">
<Value>DisplayName</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
<Value name="7">
<Value>CodeSessionRef</Value>
</Value>
<Value name="8">
<Value>CodeHash</Value>
</Value>
<Value name="9">
<Value>CodeExpiresAt</Value>
</Value>
<Value name="10">
<Value>CodeUsedAt</Value>
</Value>
<Value name="11">
<Value>ReplySlotAt</Value>
</Value>
<Value name="12">
<Value>SeenAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.PairingD</DataLocation>
<DefaultData>PairingDefaultData</DefaultData>
<IdLocation>^OcuTalonP.PairingD</IdLocation>
<IndexLocation>^OcuTalonP.PairingI</IndexLocation>
<StreamLocation>^OcuTalonP.PairingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
