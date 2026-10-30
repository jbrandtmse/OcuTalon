Include Ensemble

/// Lane A's helpers for the CI mock's Bot API side (Story 12.1; AD-22, DW-370). A class of class methods with no Test methods, so it
/// is no test class and joins no shard run. Its tests run in throwaways and CI only, where ci/compose.ci.yml points
/// OCUTALON_TELEGRAM_API_BASE at the mock. It calls the public helpers of OcuTalon.Test.Contract.Mock and changes none of them.
/// The mock restarts its update ids and message ids at 1 with every reset, and TelegramIn keeps the next offset to confirm: a reset
/// under a kept offset would make the poller confirm the new updates away. So a Lane A test resets the Bot API side only through Reset.
///   - The kept offset is the persistent adapter value $$$EnsStaticAppData("TelegramIn", "offset"), that is
///     ^Ens.AppData("TelegramIn", "offset"), and nowhere else. It holds the last handled update_id plus 1; no node means no offset.
///     Offset() reads it, and SetOffset(offset) sets it (a test calls it to stand in for the poller) or kills it for "".
///   - PollerReason(item): "" when the item has no Alive job, otherwise a reason that names the item and says that a reset would take
///     its updates. The job query follows Ens.Job:Enumerate.
///   - Reset(poller): refuses with PollerReason's text as an error status when it is not empty, sending nothing and clearing nothing.
///     Otherwise, in the one call, it kills the kept offset and resets the mock's Bot API side, and fails when the mock did not answer 200.
///     A scripted getUpdates reply (the telegram-*-update scenarios) is sent as written, with update_id 1, and moves neither the mock's
///     update ids nor its offset filter, so a test queues one update source (a scenario or /updates) per Reset.
///   - BotReply(token, method, body, .statusCode): the Bot API call of Mock.BotCall that returns the parsed body and the status
///     whatever the status is, so that a test can read a 409 or a 429. It throws when the mock cannot be reached, with a text that
///     names the method and never the token, and when the answer is not JSON (the mock answers JSON on every path).
Class OcuTalon.Test.Channel.BotApi Extends %RegisteredObject
{

/// The item that polls the Bot API.
Parameter POLLER = "TelegramIn";

/// The job statuses that mean a job does not run.
Parameter DEADSTATUSES = "error,halted,terminated";

/// The offset that the poller item keeps, or "" when there is none.
ClassMethod Offset() As %String
{
	Quit $Get($$$EnsStaticAppData(..#POLLER, "offset"))
}

/// Sets the offset that the poller item keeps, or removes it for "".
ClassMethod SetOffset(offset As %String)
{
	If offset = "" {
		Kill $$$EnsStaticAppData(..#POLLER, "offset")
	} Else {
		Set $$$EnsStaticAppData(..#POLLER, "offset") = offset
	}
}

/// "" when the item has no Alive job. Otherwise the reason why the mock's Bot API side must not be reset: it names the item.
ClassMethod PollerReason(item As %String = {..#POLLER}) As %String
{
	Set live = 0
	Set result = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	If $$$ISERR(result.Execute()) Quit "the jobs of the production cannot be listed, so a live "_item_" cannot be ruled out"
	While result.Next() {
		If (result.Get("ConfigName") = item) && (result.Get("State") = "Alive") && '$ListFind($ListFromString(..#DEADSTATUSES), result.Get("Status")) Set live = 1
	}
	If 'live Quit ""
	Quit item_" has a live job: a reset of the mock's Bot API side would take its updates and its calls, so this test does not run while it polls"
}

/// Resets the mock's Bot API side and clears the offset that TelegramIn keeps, in one call. Refuses with an error that holds
/// PollerReason(poller) when that is not empty, and then sends nothing and clears nothing.
ClassMethod Reset(poller As %String = {..#POLLER}) As %Status
{
	Set reason = ..PollerReason(poller)
	If reason '= "" Quit $SYSTEM.Status.Error(5001, reason)
	Do ..SetOffset("")
	If '##class(OcuTalon.Test.Contract.Mock).Control("reset") Quit $SYSTEM.Status.Error(5001, "the mock did not answer 200 to the reset of its Bot API side")
	Quit $$$OK
}

/// A Bot API call to the mock: POST /bot<token>/<method> with the JSON body (none when ""). Returns the parsed body, and the status in
/// statusCode, whatever the status. Throws when the mock is not reached, naming the method and never the token, and when the answer
/// is not JSON.
ClassMethod BotReply(token As %String, method As %String, body As %String, Output statusCode As %Integer) As %DynamicObject
{
	Set statusCode = ""
	Set hostPort = $Piece($Piece(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMBASE, "//", 2), "/", 1)
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = $Piece(hostPort, ":", 1)
	Set request.Port = +$Piece(hostPort, ":", 2)
	Set request.Timeout = 10
	If body '= "" {
		Set request.ContentType = "application/json"
		Do request.EntityBody.Write(body)
	}
	Set status = request.Post("/bot"_token_"/"_method)
	If $$$ISERR(status) Throw ##class(%Exception.General).%New("BotReply", 5001, , "the call to "_method_" did not reach the mock")
	Set statusCode = request.HttpResponse.StatusCode
	Quit {}.%FromJSON(request.HttpResponse.Data)
}

}
