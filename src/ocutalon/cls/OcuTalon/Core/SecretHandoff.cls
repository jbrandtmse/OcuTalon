/// The one way a secret that the REST process received reaches SettingsOps (AD-1, AD-19; the shared handoff of Stories 35.3 and 21.2). The secret travels in
/// an IRIS event resource, which lives in shared memory only: no global, command, production message, log line, trace or audit entry holds it. Put creates a
/// uniquely named resource and signals the secret into it; the caller puts only the returned uri in its command. Take, in the production job, reads the one
/// message, deletes the resource and returns the secret. A second Take of the same uri, an unknown uri, a malformed uri and an expired wait all fail with the
/// same status and no detail. Discard deletes a resource that nobody took, so the REST process calls it on every path after Put (an error included);
/// nothing persists. No method logs or returns the secret except Take's output.
Class OcuTalon.Core.SecretHandoff
{

/// What every uri starts with, followed by the 22-character Ref that names the resource.
Parameter SCHEME = "secret://handoff/";

/// The seconds that Take waits for the message by default.
Parameter WAITSECONDS = 5;

/// The status of every failure: it never says why.
Parameter MESSAGEFAILED = "The secret could not be handed over.";

/// Creates the resource, signals the secret into it and returns its uri (secret://handoff/<Ref>) in uri. On an error uri is "" and no resource is left.
ClassMethod Put(secret As %String, Output uri As %String) As %Status
{
	Set uri = ""
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set name = ..ResourceName(ref)
	Set created = 0, signaled = 0
	Try {
		Set created = ''$SYSTEM.Event.Create(name)
		If created Set signaled = ''$SYSTEM.Event.Signal(name, $Get(secret))
	} Catch {
		Set signaled = 0
	}
	If 'signaled {
		If created Do $SYSTEM.Event.Delete(name)
		Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFAILED)
	}
	Set uri = ..#SCHEME_ref
	Quit $SYSTEM.Status.OK()
}

/// Reads the one message of the uri's resource, waiting at most timeoutSec seconds, and deletes the resource whatever came back. The secret is in secret
/// on success. Any failure leaves secret empty and gives the same error status.
ClassMethod Take(uri As %String, Output secret As %String, timeoutSec As %Integer = {..#WAITSECONDS}) As %Status
{
	Set secret = ""
	Set name = ..NameOf($Get(uri))
	If name = "" Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFAILED)
	Set got = 0
	Try {
		Set result = $SYSTEM.Event.WaitMsg(name, timeoutSec)
		If $ListGet(result, 1) = 1 {
			Set secret = $ListGet(result, 2)
			Set got = 1
		}
	} Catch {
		Set got = 0
		Set secret = ""
	}
	Do $SYSTEM.Event.Delete(name)
	If 'got Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFAILED)
	Quit $SYSTEM.Status.OK()
}

/// Deletes the uri's resource and the message in it, if any. A malformed or unknown uri is not an error.
ClassMethod Discard(uri As %String) As %Status
{
	Set name = ..NameOf($Get(uri))
	If name '= "" Do $SYSTEM.Event.Delete(name)
	Quit $SYSTEM.Status.OK()
}

/// The resource name of a uri, or "" when the uri is not SCHEME followed by a 22-character Ref.
ClassMethod NameOf(uri As %String) As %String [ Private ]
{
	If $Extract(uri, 1, $Length(..#SCHEME)) '= ..#SCHEME Quit ""
	Set ref = $Extract(uri, $Length(..#SCHEME) + 1, *)
	If ref '?22(1AN,1"-",1"_") Quit ""
	Quit ..ResourceName(ref)
}

/// The name of the event resource for a Ref. It is a name only: no node of the global exists.
ClassMethod ResourceName(ref As %String) As %String [ Private ]
{
	Quit $Name(^OcuTalonP.SecretHandoff(ref))
}

}
