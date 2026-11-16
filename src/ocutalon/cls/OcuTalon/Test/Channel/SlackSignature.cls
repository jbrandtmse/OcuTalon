/// Tests of Slack's request signature (Story 27.1; AD-13, AD-19): Channel.Slack.Signature Check is pure, so these need no production and no fixture. The signatures
/// of the first two vectors were made with openssl, not with the product's code, over the bytes shown.
///   - TestVectors: the signature of an ASCII body and of a body with a UTF-8 byte pair is accepted, and the same text decoded to characters is not the signed body;
///   - TestMismatch: a changed body, timestamp, secret or signature, a signature with a digit changed at each end, a shorter and a longer one, one with no v0= prefix,
///     an upper-case one and one that is not hexadecimal are each mismatch;
///   - TestMissing: no secret, no timestamp, no signature and a timestamp that is not a number are missing;
///   - TestStale: a timestamp exactly 300 s from now is fresh in either direction, and 301 s is stale in either direction, and the staleness is judged before the signature;
///   - TestWholeLengthIsCompared: a signature that differs only in its last character is a mismatch, at each of the 67 positions.
Class OcuTalon.Test.Channel.SlackSignature Extends %UnitTest.TestCase
{

Parameter SECRET = "zz-signing-secret-0123456789";

Parameter TIMESTAMP = 1700000000;

Parameter ASCII = "v0=264d527f767a47bc89795c6a6867131105112bee0ad503778c73b4699a916fd9";

Parameter UTF8 = "v0=c515efea52d9c05c92f1d49d9f3cd6bb0cb48c9fc48e1c6dc0dd047470befa85";

Method TestVectors()
{
	Set now = ..#TIMESTAMP
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII, "{""a"":1}", now), "", "the signature of an ASCII body is accepted")
	Set bytes = "{""t"":""caf"_$Char(195, 169)_"""}"
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#UTF8, bytes, now), "", "so is the signature of a body with the UTF-8 bytes of an e with an acute accent, hashed as the bytes")
	Set decoded = "{""t"":""caf"_$Char(233)_"""}"
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#UTF8, decoded, now), "mismatch", "and the same text decoded to characters is not the signed body")
}

Method TestMismatch()
{
	Set now = ..#TIMESTAMP
	Set body = "{""a"":1}"
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII, "{""a"":2}", now), "mismatch", "a changed body")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP + 1, ..#ASCII, body, now), "mismatch", "a changed timestamp")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET_"x", ..#TIMESTAMP, ..#ASCII, body, now), "mismatch", "a changed secret")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, $Extract(..#ASCII, 1, 66)_"0", body, now), "mismatch", "a changed last digit")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, "v0=0"_$Extract(..#ASCII, 5, *), body, now), "mismatch", "a changed first digit")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, $Extract(..#ASCII, 1, *-1), body, now), "mismatch", "a shorter signature")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII_"0", body, now), "mismatch", "a longer signature")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, $Extract(..#ASCII, 4, *), body, now), "mismatch", "a signature with no v0= prefix")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, $ZConvert(..#ASCII, "U"), body, now), "mismatch", "an upper-case signature")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, "v0="_$Translate($Justify("", 64), " ", "z"), body, now), "mismatch", "a signature of the right length that is not hexadecimal")
}

Method TestMissing()
{
	Set now = ..#TIMESTAMP
	Set body = "{""a"":1}"
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check("", ..#TIMESTAMP, ..#ASCII, body, now), "missing", "no secret")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, "", ..#ASCII, body, now), "missing", "no timestamp")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, "", body, now), "missing", "no signature")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, "abc", ..#ASCII, body, now), "missing", "a timestamp that is not a number")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, "17e8", ..#ASCII, body, now), "missing", "or one in exponent form")
}

Method TestStale()
{
	Set body = "{""a"":1}"
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII, body, ..#TIMESTAMP + 300), "", "300 s old is fresh")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII, body, ..#TIMESTAMP - 300), "", "300 s in the future is fresh")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII, body, ..#TIMESTAMP + 301), "stale", "301 s old is stale")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, ..#ASCII, body, ..#TIMESTAMP - 301), "stale", "301 s in the future is stale")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, "v0=wrong", body, ..#TIMESTAMP + 301), "stale", "staleness is judged before the signature")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.Signature).#STALESECONDS, 300, "the limit is 300 s")
}

Method TestWholeLengthIsCompared()
{
	Set body = "{""a"":1}"
	For i = 1:1:$Length(..#ASCII) {
		Set wrong = $Extract(..#ASCII, 1, i - 1)_$Select($Extract(..#ASCII, i) = "0": "1", 1: "0")_$Extract(..#ASCII, i + 1, *)
		If ##class(OcuTalon.Channel.Slack.Signature).Check(..#SECRET, ..#TIMESTAMP, wrong, body, ..#TIMESTAMP) '= "mismatch" {
			Do $$$AssertTrue(0, "a signature that differs at character "_i_" is a mismatch")
			Quit
		}
	}
	Do $$$AssertTrue(1, "a signature that differs at any one of its "_$Length(..#ASCII)_" characters is a mismatch")
}

}
