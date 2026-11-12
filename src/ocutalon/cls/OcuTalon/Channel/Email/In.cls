/// EmailIn, the inbound service of the connected mailbox (Story 21.2; AD-1, AD-14, AD-26, AD-30). Its adapter, Channel.Email.Adapter, polls
/// the mailbox every CallInterval seconds and hands each new email, a Channel.Email.Mail, to ProcessInput. The service is disabled in the
/// production until SettingsOps saves a mailbox (the System Default Settings rows of the item), and stays disabled on the online demo.
/// For each email, in order, the service:
///   - refuses what is not a Mail, a Mail with no Uidl, no owner (the product key email.owner, read from its row and never from the cache,
///     because the mailbox moves to the admin who saved last) or an owner with no Session row: an error status, and nothing is sent;
///   - sets its SuperSession to the owner session's TraceRef, so that the email has a trace session of its own under the owner's (AD-26);
///   - sends Intake an OcuTalon.Msg.Item, asynchronously, with a new ItemId, the owner's SessionRef, channel email, provenance untrusted
///     and the Sender, Subject and Text of the Mail, the Text cut to SimMailbox.In BODYMAX characters (the size the simulated mailbox
///     takes); every other field is empty or 0.
/// The service never decides, writes no table of its own and publishes no event. Nothing in an email is read as an instruction: the Item is
/// untrusted content that Intake and Decide judge.
Class OcuTalon.Channel.Email.In Extends Ens.BusinessService
{

Parameter ADAPTER = "OcuTalon.Channel.Email.Adapter";

/// The item that takes every Item.
Parameter TARGET = "Intake";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "email";

/// The product key of the session that owns the mailbox.
Parameter OWNERKEY = "email.owner";

Parameter ERRORINPUT = "EmailIn takes an email from its adapter and nothing else.";

Parameter ERROROWNER = "The mailbox has no owner session.";

/// Takes an email.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Channel.Email.Mail") || (pInput.Uidl = "") Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
	Set owner = ..Owner()
	Set session = $Select(owner = "": "", 1: ##class(OcuTalon.Data.Session).RefIndexOpen(owner))
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, ..#ERROROWNER)
	Set ..%SuperSession = session.TraceRef
	Set sc = $$$OK
	Try {
		Set item = ##class(OcuTalon.Msg.Item).%New()
		Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set item.SessionRef = owner
		Set item.Channel = ..#CHANNEL
		Set item.Provenance = "untrusted"
		Set item.Sender = $Extract(pInput.Sender, 1, 1000)
		Set item.Subject = $Extract(pInput.Subject, 1, 1000)
		Set item.Text = $Extract(pInput.Text, 1, ##class(OcuTalon.Channel.SimMailbox.In).#BODYMAX)
		Set sc = ..Send(..#TARGET, item)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The Ref of the session that owns the mailbox, read from the product key's row and never from the per-process cache; "" when there is none.
ClassMethod Owner() As %String
{
	Quit ##class(OcuTalon.Data.Setting).Fresh(..#OWNERKEY)
}

/// The one send of the class: the request to the item, asynchronously. Private; a test subclass overrides it.
Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, request)
}

}
