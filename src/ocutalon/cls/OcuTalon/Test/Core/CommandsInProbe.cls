/// A subclass of OcuTalon.Core.CommandsIn for the tests, which may override its private Send: it passes each send to a
/// shadow instance of OcuTalon.Test.Core.CommandsOwner instead of the production, and records what the send saw. It adds
/// nothing to the product's surface; the product never refers to it. RunNumber and AnswerMode are handed to the owner;
/// LastRequest and LastResponse are the objects of the last send, and SeenSessionId and SeenSuperSession are the trace session
/// that the service had set when it sent.
Class OcuTalon.Test.Core.CommandsInProbe Extends OcuTalon.Core.CommandsIn
{

/// The subscript of the run under ^OcuTalonTest("CommandsRouting").
Property RunNumber As %String;

/// How the test owner answers (CommandsOwner).
Property AnswerMode As %String [ InitialExpression = "ok" ];

/// The request of the last send.
Property LastRequest As %Library.Persistent;

/// The owner's response to the last send.
Property LastResponse As %Library.Persistent;

/// The service's %SessionId when it sent.
Property SeenSessionId As %String;

/// The service's %SuperSession when it sent.
Property SeenSuperSession As %String;

Method Send(target As %String, request As OcuTalon.Msg.Command, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set response = ""
	Set ..SeenSessionId = ..%SessionId
	Set ..SeenSuperSession = ..%SuperSession
	Set ..LastRequest = request
	Set owner = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsOwner", .sc)
	If '$IsObject(owner) Quit sc
	Set owner.RunNumber = ..RunNumber
	Set owner.AnswerMode = ..AnswerMode
	Set owner.SentTo = target
	Set sc = owner.OnMessage(request, .response)
	Set ..LastResponse = response
	Quit sc
}

}
