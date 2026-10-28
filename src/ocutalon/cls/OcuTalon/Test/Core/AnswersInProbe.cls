/// A subclass of OcuTalon.Core.AnswersIn for the tests, which overrides its private Send: the answer goes to a shadow instance of
/// OcuTalon.Test.Core.AnswerOpsProbe whose request header names the source item Source (default AnswersIn), called with OnMessage, so
/// that no production is needed. It records what the send saw: Sends (the count), LastRequest, SeenSessionId and SeenSuperSession (the
/// trace session that the service had set when it sent). The product never refers to it.
Class OcuTalon.Test.Core.AnswersInProbe Extends OcuTalon.Core.AnswersIn
{

/// The source item that the header of the send names.
Property Source As %String [ InitialExpression = "AnswersIn" ];

/// The number of sends.
Property Sends As %Integer [ InitialExpression = 0 ];

/// The request of the last send.
Property LastRequest As %Library.Persistent;

/// The service's %SessionId when it sent.
Property SeenSessionId As %String;

/// The service's %SuperSession when it sent.
Property SeenSuperSession As %String;

Method Send(request As OcuTalon.Core.Msg.Answer, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set response = ""
	Set ..Sends = ..Sends + 1
	Set ..LastRequest = request
	Set ..SeenSessionId = ..%SessionId
	Set ..SeenSuperSession = ..%SuperSession
	Set operation = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswerOpsProbe", .sc)
	If '$IsObject(operation) Quit sc
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = ..Source
	Set operation.%RequestHeader = header
	Quit operation.OnMessage(request, .response)
}

}
