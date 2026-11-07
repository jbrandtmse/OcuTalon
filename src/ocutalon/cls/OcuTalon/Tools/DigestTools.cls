/// The method behind the Chat agent's digest tool, send_digest (AD-1, AD-4, AD-7, AD-9, AD-10, AD-18; Story 17.6): it submits Epic 0's SendDigest command
/// through OcuTalon.Tools.CommandCall (origin tool, IdempotencyKey the turn's ItemId, a colon and the command's position) and returns the owner's
/// answer. The tool takes no input and names no recipient: the digest goes to the digest channels of the session of the call, which come from the
/// bridge context and never from an argument. The tool never reads or writes a digest itself: Digest owns them.
/// The tool is safe and has trusted output: its answer is built in code from the owner's CommandResult (CommandCall.Answer), the fixed text of
/// Digest.Process MESSAGESENDING, which says that the digest is on its way and never that it was delivered, and holds no digest content and no names.
/// The tool changes state, so it is not read-only and the gate denies it in an untrusted or tainted turn.
/// It declares, by the naming rule of OcuTalon.Tools.ReminderTools, its step label (STEPLABELSENDDIGEST, AD-9) and its classification for the gate
/// (CLASSIFICATIONSENDDIGEST, READONLYSENDDIGEST and TRUSTEDOUTPUTSENDDIGEST, AD-10). It extends OcuTalon.Tools.Result and returns only through
/// Return. A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6). The description of the tool is
/// its method's doc comment: text for the model, never shown to the user as written.
Class OcuTalon.Tools.DigestTools Extends OcuTalon.Tools.Result
{

Parameter STEPLABELSENDDIGEST = "Sending your digest";

Parameter CLASSIFICATIONSENDDIGEST = "safe";

Parameter READONLYSENDDIGEST = 0;

Parameter TRUSTEDOUTPUTSENDDIGEST = 1;

/// Sends the user's digest now, to the user's digest channels. Use it when the user asks for their digest, for example "send my digest now". It takes no
/// input and cannot send the digest anywhere else. The answer says only that the digest is on its way. Delivery is not confirmed, so tell the user that
/// the digest is on its way, never that it has arrived.
ClassMethod SendDigest() As %DynamicObject
{
	Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.CommandCall).Answer(result))
}

}
