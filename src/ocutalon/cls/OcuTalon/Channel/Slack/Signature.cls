/// Slack's request signature, v0 (AD-13, AD-19; Story 27.1): pure class methods, no state and no I/O. A request is signed when its
/// X-Slack-Signature header is "v0=" and the lower-case hex of HMAC-SHA256 over "v0:" the X-Slack-Request-Timestamp header ":" and the body bytes
/// exactly as received, keyed with the signing secret. The body is never decoded or re-encoded before it is hashed. Check answers "" for a signed,
/// fresh request, and otherwise the reason: missing (no secret, timestamp, signature or a timestamp that is not a number), stale (the timestamp is more
/// than STALESECONDS from now, in either direction) or mismatch. The signature is compared at every position of its expected length with no early exit, so the time does
/// not show where the first difference is. The reason never holds the secret, a header or the body.
Class OcuTalon.Channel.Slack.Signature
{

/// The most seconds that a request's timestamp may be from now, in either direction.
Parameter STALESECONDS = 300;

/// The version prefix of the signature and of the signed text.
Parameter VERSION = "v0";

/// "" when the signature is right and the timestamp is fresh, otherwise missing, stale or mismatch. nowEpoch is the current time in seconds since 1970.
ClassMethod Check(secret As %String, timestamp As %String, signature As %String, rawBody As %String, nowEpoch As %Integer) As %String
{
	Set secret = $Get(secret), timestamp = $Get(timestamp), signature = $Get(signature)
	If (secret = "") || (signature = "") || (timestamp '? 1.15N) Quit "missing"
	Set age = $Get(nowEpoch) - timestamp
	If (age > ..#STALESECONDS) || (age < -..#STALESECONDS) Quit "stale"
	Quit $Select(..Matches(secret, timestamp, signature, $Get(rawBody)): "", 1: "mismatch")
}

/// 1 when signature is the v0 signature of the timestamp and body under the secret. Every position of the expected signature (a fixed length) is compared,
/// whatever differs.
ClassMethod Matches(secret As %String, timestamp As %String, signature As %String, rawBody As %String) As %Boolean [ Private ]
{
	Set diff = 1
	Try {
		Set expected = ..#VERSION_"="_..Hex($SYSTEM.Encryption.HMACSHA(256, ..#VERSION_":"_timestamp_":"_rawBody, secret))
		Set length = $Length(expected)
		Set diff = ($Length(signature) '= length)
		For i = 1:1:length {
			Set diff = $ZBoolean(diff, $ZBoolean($Ascii(expected, i), $Ascii(signature, i), 6), 7)
		}
	} Catch {
		Set diff = 1
	}
	Quit 'diff
}

/// The lower-case hexadecimal text of bytes.
ClassMethod Hex(bytes As %String) As %String [ Private ]
{
	Set hex = ""
	For i = 1:1:$Length(bytes) {
		Set hex = hex_$ZConvert($Extract("0"_$ZHex($Ascii(bytes, i)), *-1, *), "L")
	}
	Quit hex
}

}
