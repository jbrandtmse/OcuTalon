/// DigestStore, the business operation that keeps the items saved for the digest (AD-1, AD-30, AD-33). Lane A. OutcomeRouter forwards the
/// OcuTalon.Msg.ItemDecision of an untrusted item whose outcome is digest, and the operation keeps it as one OcuTalon.Digest.Data.Item row
/// for the digest of step 2 to summarise. It answers OK with no response, sends no message and publishes no live event, calls no model and writes
/// no other table (AD-6).
///   - An ItemDecision whose Outcome is digest, whose ItemId is not empty and whose OwnerRef is neither empty nor eval is kept (OutcomeRouter
///     forwards a session's Ref or instance, and the format of the OwnerRef is not checked here): RecordedAt is the time of the save
///     (Data.Time.NowUtc), because the message has no time of its own.
///   - An ItemDecision whose ItemId is already kept is a repeat (the owner ignores a repeat, AD-1): the answer is OK and the first row stays.
///   - Any other Outcome, an empty ItemId, and an empty OwnerRef or eval (evaluation decisions go to EvalSink only, AD-30) are refused with an
///     error status that names the reason and the ItemId; no row is written. Ens logs the error, so the operation logs nothing of its own.
///   - A save that fails and leaves no row for the ItemId (a row of the ItemId that appeared meanwhile is a repeat) is an error status that names the
///     ItemId and the reason of the failure.
///   - Any other message class gets "not implemented" (code 5003).
Class OcuTalon.Digest.Store Extends Ens.BusinessOperation
{

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	If $IsObject(pRequest) && pRequest.%IsA("OcuTalon.Msg.ItemDecision") Quit ..Keep(pRequest)
	Quit $$$ERROR($$$NotImplemented)
}

/// Keeps the decision as a row, ignores a repeat of its ItemId, or refuses it (see the class description).
Method Keep(decision As OcuTalon.Msg.ItemDecision) As %Status [ Private ]
{
	Set itemId = decision.ItemId
	Set label = "DigestStore refuses the item"_$Select(itemId '= "": " "_itemId, 1: "")_": "
	If decision.Outcome '= "digest" Quit $SYSTEM.Status.Error(5001, label_"its outcome is '"_$Extract(decision.Outcome, 1, 32)_"', not digest")
	If itemId = "" Quit $SYSTEM.Status.Error(5001, label_"it has no ItemId")
	If (decision.OwnerRef = "") || (decision.OwnerRef = "eval") Quit $SYSTEM.Status.Error(5001, label_"its owner is "_$Select(decision.OwnerRef = "": "empty", 1: "eval")_", not a session or instance")
	If ##class(OcuTalon.Digest.Data.Item).ItemIdIndexExists(itemId) Quit $SYSTEM.Status.OK()
	Set item = ##class(OcuTalon.Digest.Data.Item).%New()
	Set item.SessionRef = decision.OwnerRef
	Set item.ItemId = itemId
	Set item.DecisionRef = decision.DecisionRef
	Set item.Channel = decision.Channel
	Set item.Summary = decision.Summary
	Set item.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = item.%Save()
	If $$$ISOK(sc) Quit sc
	If ##class(OcuTalon.Digest.Data.Item).ItemIdIndexExists(itemId) Quit $SYSTEM.Status.OK()
	Quit $SYSTEM.Status.Error(5001, "DigestStore could not keep the item "_itemId_": "_$SYSTEM.Status.GetErrorText(sc))
}

}
