/// A stand-in for %Net.POP3 for the tests of the EmailIn adapter (Story 21.2), so that they open no connection. It keeps its mailbox and its
/// answers in the process-private global ^||OcuTalonEmailInPop3:
///   - ("mail", n) = $ListBuild(uidl, from, subject, text, html, size, parts, ref) is email n (1, 2, ...): text is the plain body, html the HTML body, size the
///     number of octets that LIST reports (0 for the length of the text), parts 1 for a multipart/alternative email with both bodies, and ref the value of
///     its header X-OcuTalon-Ref ("" for none), which FetchMessageHeaders gives under the key x-ocutalon-ref and Fetch in Headers under the same key, in lower
///     case as %Net.POP3 converts every header name;
///   - ("answer", step) = a status code or "": ConnectPort, GetMessageUIDArray, GetSizeOfMessages, FetchMessageHeaders, Fetch and QuitAndCommit answer
///     an error status with that code and the text "SERVER-WORDS zzserver@example.com" (server text, an address) when the step has a code; "code~line"
///     answers that code with the server's line instead, as %Net.POP3 reports a POP3 answer (the line may be empty);
///   - ("calls", name) counts the calls of each method, ("fetched", n) the emails that Fetch read whole and ("headers", n) those that
///     FetchMessageHeaders read; ("connect") = $ListBuild(server, port, user) of the last ConnectPort (the password is never recorded).
/// The product never refers to it.
Class OcuTalon.Test.Channel.EmailInPop3 Extends %Net.POP3
{

ClassMethod Count(name As %String) As %Integer
{
	Quit +$Get(^||OcuTalonEmailInPop3("calls", name))
}

ClassMethod Fails(step As %String) As %Status [ Private ]
{
	Set ^||OcuTalonEmailInPop3("calls", step) = $Get(^||OcuTalonEmailInPop3("calls", step)) + 1
	Set answer = $Get(^||OcuTalonEmailInPop3("answer", step))
	Set code = $Piece(answer, "~", 1)
	Quit $Select(code = "": $$$OK, 1: $SYSTEM.Status.Error(code, $Select(answer [ "~": $Piece(answer, "~", 2, *), 1: "SERVER-WORDS zzserver@example.com")))
}

Method ConnectPort(PopServer As %String, PopPort As %Integer = 110, UserName As %String, Password As %String, AccessToken As %String = "") As %Status
{
	Set sc = ..Fails("ConnectPort")
	Set ^||OcuTalonEmailInPop3("connect") = $ListBuild(PopServer, PopPort, UserName)
	If $$$ISOK(sc) Set ..Connected = 1
	Quit sc
}

Method GetMessageUIDArray(MessageNumber As %String = "", ByRef ListOfUniqueIDs As %ArrayOfDataTypes) As %Status
{
	Set sc = ..Fails("GetMessageUIDArray")
	If $$$ISERR(sc) Quit sc
	Set ListOfUniqueIDs = ##class(%ArrayOfDataTypes).%New()
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonEmailInPop3("mail", n), 1, mail)
		Quit:n=""
		Do ListOfUniqueIDs.SetAt($List(mail, 1), n)
	}
	Quit $$$OK
}

Method GetSizeOfMessages(MessageNumber As %String = "", ByRef ListOfSizes As %ArrayOfDataTypes) As %Status
{
	Set sc = ..Fails("GetSizeOfMessages")
	If $$$ISERR(sc) Quit sc
	Set ListOfSizes = ##class(%ArrayOfDataTypes).%New()
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonEmailInPop3("mail", n), 1, mail)
		Quit:n=""
		Do ListOfSizes.SetAt($Select($List(mail, 6) > 0: $List(mail, 6), 1: $Length($List(mail, 4)) + 200), n)
	}
	Quit $$$OK
}

Method FetchMessageHeaders(MessageNumber As %Integer, ByRef MsgHeadersArray As %String) As %Status
{
	Set sc = ..Fails("FetchMessageHeaders")
	If $$$ISERR(sc) Quit sc
	Set ^||OcuTalonEmailInPop3("headers", MessageNumber) = 1
	Set mail = ^||OcuTalonEmailInPop3("mail", MessageNumber)
	Kill MsgHeadersArray
	Set MsgHeadersArray("from") = $List(mail, 2)
	Set MsgHeadersArray("subject") = $List(mail, 3)
	If $ListGet(mail, 8) '= "" Set MsgHeadersArray("x-ocutalon-ref") = $List(mail, 8)
	Quit $$$OK
}

Method Fetch(MessageNumber As %Integer, ByRef MailMsg As %Net.MailMessage, Delete As %Boolean = 0, messageStream As %BinaryStream) As %Status
{
	Set sc = ..Fails("Fetch")
	If $$$ISERR(sc) Quit sc
	Set ^||OcuTalonEmailInPop3("fetched", MessageNumber) = 1
	Set mail = ^||OcuTalonEmailInPop3("mail", MessageNumber)
	Set MailMsg = ##class(%Net.MailMessage).%New()
	Set MailMsg.From = $List(mail, 2)
	Set MailMsg.Subject = $List(mail, 3)
	If $ListGet(mail, 8) '= "" Do MailMsg.Headers.SetAt($List(mail, 8), "x-ocutalon-ref")
	If $List(mail, 7) {
		Set MailMsg.IsMultiPart = 1
		Set MailMsg.MultiPartType = "alternative"
		Set plain = ##class(%Net.MailMessagePart).%New()
		Do plain.TextData.Write($List(mail, 4))
		Set html = ##class(%Net.MailMessagePart).%New()
		Set html.IsHTML = 1
		Do html.TextData.Write($List(mail, 5))
		Do MailMsg.Parts.SetAt(plain, 1)
		Do MailMsg.Parts.SetAt(html, 2)
	} ElseIf $List(mail, 5) '= "" {
		Set MailMsg.IsHTML = 1
		Do MailMsg.TextData.Write($List(mail, 5))
	} Else {
		Do MailMsg.TextData.Write($List(mail, 4))
	}
	Quit $$$OK
}

Method DeleteMessage(MessageNumber As %Integer) As %Status
{
	Set ^||OcuTalonEmailInPop3("calls", "DeleteMessage") = $Get(^||OcuTalonEmailInPop3("calls", "DeleteMessage")) + 1
	Quit $$$OK
}

Method QuitAndCommit() As %Status
{
	Set sc = ..Fails("QuitAndCommit")
	Set ..Connected = 0
	Quit sc
}

/// Adds an email: the Uidl, From, Subject and plain text, and the optional HTML body, LIST size, multipart flag and X-OcuTalon-Ref header value. Answers its number.
ClassMethod Add(uidl As %String, from As %String = "a@example.com", subject As %String = "zz subject", text As %String = "zz body", html As %String = "", size As %Integer = 0, parts As %Boolean = 0, ref As %String = "") As %Integer
{
	Set n = $Order(^||OcuTalonEmailInPop3("mail", ""), -1) + 1
	Set ^||OcuTalonEmailInPop3("mail", n) = $ListBuild(uidl, from, subject, text, html, size, parts, ref)
	Quit n
}

/// Takes the email with the Uidl out of the mailbox, renumbering the later ones.
ClassMethod Remove(uidl As %String)
{
	Kill keep
	Set n = ""
	Set count = 0
	For {
		Set n = $Order(^||OcuTalonEmailInPop3("mail", n), 1, mail)
		Quit:n=""
		If $List(mail, 1) '= uidl Set keep($Increment(count)) = mail
	}
	Kill ^||OcuTalonEmailInPop3("mail")
	Set n = ""
	For {
		Set n = $Order(keep(n), 1, mail)
		Quit:n=""
		Set ^||OcuTalonEmailInPop3("mail", n) = mail
	}
}

Storage Default
{
<Type>%Storage.Serial</Type>
}

}
