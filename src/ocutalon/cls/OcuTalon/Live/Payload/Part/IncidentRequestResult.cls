/// The outcome of a resend. Lane A.
Class OcuTalon.Live.Payload.Part.IncidentRequestResult Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The messages the request covered.
Property Total As %Integer(%JSONFIELDNAME = "total");

/// The messages that were resent.
Property Resent As %Integer(%JSONFIELDNAME = "resent");

/// The resent messages that completed.
Property Completed As %Integer(%JSONFIELDNAME = "completed");

/// The resent messages that failed again.
Property FailedAgain As %Integer(%JSONFIELDNAME = "failedAgain");

/// The messages that were left out.
Property Skipped As %Integer(%JSONFIELDNAME = "skipped");

/// The messages the run did not reach.
Property Interrupted As %Integer(%JSONFIELDNAME = "interrupted");

/// Why the run ended early, when it did.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 1000);

}
