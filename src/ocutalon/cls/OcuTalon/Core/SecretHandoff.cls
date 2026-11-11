/// SecretHandoff, the in-memory hand-off of one secret from the REST process to the operation that stores it (AD-1, AD-19): a secret the page
/// sent (a mail password, a hook secret) never enters a command, a message, a log, a trace or a global; the command carries only a
/// reference, secret://handoff/<name>, and the operation that carries the command out takes the secret by that reference.
///   - Put creates a uniquely named $SYSTEM.Event resource, signals the secret into it as the one queued message, and answers the
///     reference. The resource lives in memory only and is deleted by the Take that ends it.
///   - Take waits at most timeoutSec seconds for the queued message, answers it in secret and always deletes the resource: a second Take
///     of the same reference, a reference that names no resource, one that was never offered and one of any other form all fail with
///     the same plain status, which names neither the reference nor the secret. A Take with timeoutSec 0 is the discard of the caller
///     that offered the secret: it takes what is queued (nothing, when the operation took it) and deletes the resource.
/// Nothing here logs, stores or echoes a secret. The class has no other public method.
Class OcuTalon.Core.SecretHandoff
{

/// The start of every reference.
Parameter PREFIX = "secret://handoff/";

/// The start of every event resource name; the reference's name follows it.
Parameter RESOURCE = "OcuTalonHandoff";

/// The plain text of every failure: it says nothing about why.
Parameter MESSAGEFAILED = "The secret hand-off failed.";

/// Offers the secret (a non-empty string): uri is the reference that Take needs. A secret that is empty or not a string is an error and
/// nothing is created. The secret is not logged.
ClassMethod Put(secret As %String, Output uri As %String) As %Status
{
	Set uri = ""
	If ($Get(secret) = "") Quit ..Failed()
	Set name = "", resource = ""
	Try {
		Set random = $SYSTEM.Encryption.GenCryptRand(16)
		For i = 1:1:16 {
			Set name = name_$Extract("0"_$ZHex($Ascii(random, i)), *-1, *)
		}
		Set resource = ..#RESOURCE_name
		If '$SYSTEM.Event.Create(resource) Quit
		If '$SYSTEM.Event.Signal(resource, secret) {
			Do $SYSTEM.Event.Delete(resource)
			Quit
		}
		Set uri = ..#PREFIX_name
	} Catch {
		If resource '= "" Do $SYSTEM.Event.Delete(resource)
		Set uri = ""
	}
	Quit $Select(uri = "": ..Failed(), 1: $$$OK)
}

/// Takes the secret that uri names, waiting at most timeoutSec seconds for it, and deletes the resource whatever the outcome: a second
/// Take of the same uri fails. A uri that is not a reference of Put, names no resource or holds no secret is an error and secret is empty.
ClassMethod Take(uri As %String, Output secret As %String, timeoutSec As %Integer = 5) As %Status
{
	Set secret = ""
	Set resource = ..Resource($Get(uri))
	If resource = "" Quit ..Failed()
	Set found = 0
	Try {
		If $SYSTEM.Event.Defined(resource) {
			Set message = $SYSTEM.Event.WaitMsg(resource, +$Get(timeoutSec))
			Do $SYSTEM.Event.Delete(resource)
			If $ListGet(message, 1) = 1 {
				Set secret = $List(message, 2)
				Set found = 1
			}
		}
	} Catch {
		Set secret = ""
		Set found = 0
	}
	If 'found Set secret = ""
	Quit $Select(found: $$$OK, 1: ..Failed())
}

/// The event resource of a reference, or "" when the text is not a reference of Put: the prefix and 32 upper-case hexadecimal digits.
ClassMethod Resource(uri As %String) As %String [ Private ]
{
	If $Extract(uri, 1, $Length(..#PREFIX)) '= ..#PREFIX Quit ""
	Set name = $Extract(uri, $Length(..#PREFIX) + 1, *)
	If '$Match(name, "^[0-9A-F]{32}$") Quit ""
	Quit ..#RESOURCE_name
}

/// The failure status of every method.
ClassMethod Failed() As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFAILED)
}

}
