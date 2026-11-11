/// EvalIn, the adapterless service that sends the recorded cases of eval/ through the product's own path (AD-22, AD-30). Lane A.
/// The product keeps it disabled; the Production install step enables it only when OCUTALON_EVAL is 1, and Start reaches it only through
/// Ens.Director.CreateBusinessService, so a disabled EvalIn sends nothing. It uses neither EnsLib.Testing.Service nor the production's
/// testing switch. An item case goes to Intake; a turn case goes to Decide and its result to EvalSink; an incident case goes to IncidentManager; a digest
/// case goes to Digest; a case that declares precedents has them seeded and removed through PrecedentOps; and nothing else is ever a target.
///   - Start is the run entry: it creates the service, mints the run's Ref and sends each named case, or each case folder under the
///     folder, once. It returns the run's Ref, how many cases were sent, and the cases that were not, each with its reason.
///   - Start sends the turn cases first (SendOrder), then the others, each group in the order of the case list. ChatAgent has one job,
///     so the Decide timer of a turn case would otherwise be spent behind the act turns of earlier item cases.
///   - A digest case (Story 17.7, SendDigest) holds the watched rows in checks (an array), the vital signs in vitals {rows, figures} and, optionally, saved
///     summaries in saved (an array of strings). EvalIn sends Digest one OcuTalon.Eval.Msg.DigestCase (a fresh ItemId, the case's name as SourceItemId and the
///     three values as JSON text) and, before the send, opens the case's row with that ItemId. Digest sends EvalSink the DigestResult, which completes the
///     row; nothing is delivered to a user. A checks that is not an array refuses the case with REASONNOCHECKS; a send that fails deletes the row. It is not
///     a turn kind: SendOrder leaves it with the others.
///   - A case is a folder with a case.json (the shape of the eval/ cases): name, kind, heldOut, description, expectation and
///     recordedBy, and for a kind of item or injection an item {itemId, channel, provenance, sender, subject, text, catalogKey, slots},
///     and for a kind of all-clear, command or user-turn a turn {text} (and, for an all-clear, checks: the array of the recorded check rows).
///     A case that is not sent is logged as a warning and goes into the skipped list with its reason: a kind that is not sent (one
///     that is not in KINDS), no case.json or one that is not a JSON object, no item.itemId, a recorded provenance other than untrusted, no
///     turn.text, an all-clear case whose checks is not an array, or an incident case whose snapshot is missing or is not a reader
///     snapshot. The other cases still run.
///   - A sent case is an OcuTalon.Msg.Item with a fresh ItemId (OcuTalon.Bridge.Ids.NewRef), SourceItemId set to the recorded
///     item.itemId, owner eval (OcuTalon.Data.Ownership EVAL), provenance untrusted, and the channel, sender, subject, text, catalog key
///     and slots of the record. Before the send EvalIn opens the case's OcuTalon.Eval.Data.CaseResult row, which EvalSink completes;
///     a send that fails deletes the row and skips the case with the error text.
///   - A turn case (SendTurn) is a user turn of owner eval: a fresh ItemId, a request of Kind turn, Provenance user, Channel web,
///     SessionMode fresh (so that no case shares a conversation with another) and no SeedText, with the Input that Agent.Input renders from
///     an unsaved Item of the case's turn.text. Before the send EvalIn saves the case's OcuTalon.Eval.Msg.TurnResult (ItemId,
///     SourceItemId and RecordedChecks, the case's checks as JSON for an all-clear case), which the eval branch of check_status reads by
///     the request's ItemId, and opens the case's row. It sends the request to Decide and waits for the Reply: a Busy reply is asked
///     again BUSYWAIT seconds later, BUSYMAX times at most, and then the case ends as a fallback with the reason rate_limited. The Reply's
///     DecisionRef, ToolsRun, Text, Fallback and FallbackReason go into the TurnResult, and so do the catalog key and rows that
///     Checks.Render gives the Reply's HostData checks. EvalIn then sends the TurnResult to EvalSink, which completes the row. A Decide
///     that gives no Reply (an error, a timeout or an answer that is not a Reply) deletes the row and the TurnResult and skips the case.
///   - A user-turn case (Story 30.5, DW-500) is sent as the decide request of a user's chat turn: Kind decide, Provenance user, and no
///     SessionMode, with the same Input. Decide answers it with a DecisionResponse, not a Reply, so the TurnResult keeps that answer's
///     DecisionRef, Fallback and FallbackReason, and has no reply text, no tool run and no check rows. The report scores the case from the
///     Decision row of that DecisionRef (its outcome and reasons).
///   - An incident case (SendIncident) names a recorded reader snapshot in its snapshot member (a file of the case's folder, loaded with
///     EvidencePack.Load). EvalIn sends IncidentManager one OcuTalon.Eval.Msg.IncidentCase (a fresh IncidentRef from OcuTalon.Bridge.Ids.NewRef, the
///     case's folder name as SourceItemId, and the snapshot's JSON text) and, before the send, opens the case's row with ItemId the IncidentRef, which
///     is the ItemId of the ItemDecision that IncidentManager sends EvalSink. A send that fails deletes the row and skips the case with the error text.
///     The run's incident cases are paced: each one after the first is sent only once the previous one's row is no longer in state sent, after at most
///     INCIDENTWAIT seconds of INCIDENTPOLL-second pauses; at that bound the run sends no more incident cases (REASONPACED), so no case waits out its
///     diagnosis timer in DiagnosisAgent's queue.
///   - A case of kind item or injection may declare a watch {namespace, production}: the production that the case's email talks about, with a
///     watch of it set up for the run. Before the case's row is opened and its Item is sent, EvalIn calls OcuTalon.Watch.Ops.EvalWatch (the
///     watch of owner eval, never polled, never due, no CheckChanged). A watch that is not an object with a non-blank namespace and production
///     skips the case with REASONWATCHSHAPE, and one that cannot be set up skips it with REASONWATCH and the status text; neither leaves a row.
///     A row that cannot be opened and a send that fails remove the watch again. A sent case's record {case, watch}, watch being
///     OcuTalon.Watch.Ops.Fields of the row, goes into the Watches of the service, and Start returns the records in its last output. Finish
///     removes exactly the rows of the records it is given, through OcuTalon.Watch.Ops.RemoveEvalWatch.
///   - A persona (Story 40.7; AD-7): Start may be given a preset and a language for the whole run, and a case may name its own members preset
///     and language in its case.json, which override the run's for that case. The effective pair must pass Agent.Persona.EvalPresetOk (a
///     language exactly for the preset language, and custom never); otherwise the case is not sent, with REASONPERSONA, before anything is saved.
///     Open keeps the effective pair on the case's row, from which Agent.Input renders the persona block of the case's eval item. A run and a
///     case that name none send exactly what they sent before.
///   - A turn case of the kind all-clear or command may carry before {text, preset, language} (Story 40.7, DW-678): the old turn. It is asked first
///     as a fresh turn of its own preset under a temporary row <name>/before, and that row is removed after its Reply. Then the case's turn is
///     asked linked (SessionMode empty), so it opens the session that the old turn saved (AD-6), and only the case's turn is scored. A before
///     that is not valid, or that gets no Reply (none, a Busy one after BUSYMAX asks, or a fallback, which saves no session), ends the case with
///     REASONBEFORE or REASONNOREPLY and leaves no row.
///   - A documents case (Story 19.4; AD-21): a turn case, like a command case, whose case.json also holds documents, an array of {name, file}. Before the case's turn
///     is asked, EvalIn indexes each file (Markdown or plain text, a path relative to the case's folder that stays inside the folder of the cases) as a document of
///     the owner eval, in its own process through OcuTalon.Docs.Ops.AddEval (AD-22): no command, no session or Session row, no web_user origin, no upload, no
///     message to DocumentOps and no live event; no route lists an eval document. It waits at most DOCUMENTSWAIT seconds for all of them; a document that cannot be
///     added or does not become ready skips the case with REASONDOCUMENTS and removes what was added. The TurnResult keeps the Reply's HostData.citations
///     (Citations). A sent case's record {case, documents{refs}} joins the Watches of the service, and Finish removes the documents of the records it is given
///     (DocumentsDown) with their passages.
///   - A case of kind item or injection may declare precedents (Story 41.7; AD-21, AD-33): an array of 1 to PRECEDENTSMAX entries {summary, answer, outcome,
///     daysAgo}: summary a line of 1 to 80 characters, answer one of Data.Precedent ANSWERS, outcome (optional) one of Msg.Enum OUTCOME, and daysAgo
///     (optional) a whole number of 0 to PRECEDENTDAYS, which puts the answer's time that many days before now (without it, now). The shape is checked
///     before anything is saved, and so is the Item's Data.Precedent.KeyFor, which must not be "": a case that fails either is skipped with REASONPRECEDENTS
///     and leaves no row, no watch and nothing seeded. Otherwise EvalIn opens the case's row with Precedents 1, sends PrecedentOps one
///     Core.Msg.SeedPrecedent for each entry (RunRef the run's, Channel the Item's, MatchKey its KeyFor; PrecedentOps writes the rows with owner eval and
///     EvalRunRef), and only then sends the Item. Agent.Input reads those rows only for an item whose row is marked so. A seed that is not answered
///     seeded skips the case with REASONPRECEDENTS and removes its row and its watch. From the first seed on, the case's setup record
///     {case, precedents{runRef}} is in the Watches of the service, and Finish sends PrecedentOps one RemoveSeededPrecedents for each distinct run of the
///     records it is given (Unseed). Start removes, before its first case, the seeded rows of every earlier run that left a marked row, and clears that
///     run's marks; its case rows stay (SweepPrecedents). A failed removal is one warning, and the run goes on.
///   - A command case may declare a session (Story 41.14; AD-1, AD-4, AD-22, AD-33): an object, optionally with forgotten, 1 to SESSIONFORGOTTENMAX non-blank texts of at
///     most SESSIONTEXTMAX characters; a session on any other kind of case (checked for every kind, before anything is saved), a session that is not an object and a forgotten of another shape skip the case with
///     REASONSESSION before anything is saved. SessionUp makes one eval-only Session row for the case through Data.Session.ForEval (which makes it only while OCUTALON_EVAL is 1:
///     no IrisUser, no ResumeHash, so no sign-in can attach to it), and for each forgotten text sends MemoryOps (AskMemory) a SaveMemory of that session with the origin
///     system, which must answer saved, and then a ForgetMemory of the answer's Ref, which must answer forgotten. That is the one command EvalIn sends to an owner outside
///     CommandsIn, as the precedent seed is. A seed that is not answered so skips the case with REASONSESSION and drops the session. The case's Item stays owner eval, so the
///     Input is the same as for every eval turn; only the request's OwnerRef is the case's session (TurnRequest). The TurnResult keeps the Reply's HostData.memories (Memories).
///     A sent case's record {case, session{ref}} joins the Watches of the service from the row's creation on, and Finish drops, for each such record, the session's memories
///     (OcuTalon.Memory.DropSession, the sign-out's own drop), the conversation links of its turns (Bridge.Purge.DropLinks) and then its row (Data.Session.DropEval); BridgeSink
///     publishes and notifies nothing for such a session (Data.Session.IsEval, AD-22); a row whose memories could not be dropped stays, so that the next
///     start's sweep drops both. Start drops, after SweepPrecedents, every Session row with no IrisUser and its memories (SweepSessions); a failure is one warning.
///   - The trace: each case is its own trace session, and every message of the run carries the run's Ref as its SuperSession (AD-26), the old turn
///     of a before included.
/// Wait polls the rows of a run until none is still sent, or the seconds have passed.
Class OcuTalon.Eval.In Extends Ens.BusinessService
{

/// The folder of the recorded cases in a throwaway stack: the repository's eval/ mounted read-only.
Parameter FOLDER = "/opt/ocutalon/eval/";

/// The item that takes every Item.
Parameter TARGET = "Intake";

/// The item that answers a turn case.
Parameter DECIDE = "Decide";

/// The item that completes the rows, and takes the TurnResult of a turn case.
Parameter SINK = "EvalSink";

/// The kinds of case that EvalIn sends, comma-separated.
Parameter KINDS = "item,injection,all-clear,command,user-turn,incident,digest,documents";

/// The kinds of case that hold a recorded Item, and go to Intake.
Parameter ITEMKINDS = "item,injection";

/// The kinds of case that are a user turn, and go to Decide.
Parameter TURNKINDS = "all-clear,command,user-turn,documents";

/// The kind of turn case that is a user's own chat message as Triage decides it (Story 30.5, DW-500): its request is a decide request of
/// provenance user, answered with a DecisionResponse, and it has no reply text.
Parameter USERTURNKIND = "user-turn";

/// The kind of turn case whose documents are added before its turn (Story 19.4): its documents member is an array of {name, file}, each file the path of a
/// Markdown or plain-text file relative to the case's folder (and inside the folder of the cases), indexed as documents of the owner eval (Docs.Ops.AddEval) and
/// removed again by Finish.
Parameter DOCUMENTSKIND = "documents";

/// The seconds to wait for the documents of a case to be ready, all of them together.
Parameter DOCUMENTSWAIT = 120;

/// The item that seeds and removes the precedent rows of a case that declares precedents.
Parameter PRECEDENTTARGET = "PrecedentOps";

/// The most precedents a case seeds: the most rows that Data.Precedent.Similar returns (a test pins them equal).
Parameter PRECEDENTSMAX = 3;

/// The most days ago a precedent of a case may be answered.
Parameter PRECEDENTDAYS = 30;

/// The seconds to wait for PrecedentOps to answer a seed or a removal.
Parameter PRECEDENTWAIT = 30;

/// The item that saves and forgets the seeded memories of a case that declares a session (Story 41.14).
Parameter MEMORYTARGET = "MemoryOps";

/// The seconds to wait for MemoryOps to answer a seeded save or forget.
Parameter MEMORYWAIT = 30;

/// The most texts a session case's forgotten holds, and the most characters of each (the length of Data.Memory.Text).
Parameter SESSIONFORGOTTENMAX = 3;

Parameter SESSIONTEXTMAX = 2000;

/// The kind of case that holds a recorded reader snapshot, and goes to IncidentManager.
Parameter INCIDENTKIND = "incident";

/// The item that diagnoses an incident case.
Parameter INCIDENTTARGET = "IncidentManager";

/// The kind of case that holds recorded check rows for a digest, and goes to Digest.
Parameter DIGESTKIND = "digest";

/// The item that composes the verdict of a digest case.
Parameter DIGEST = "Digest";

/// The kind of turn case that holds recorded check rows.
Parameter ALLCLEARKIND = "all-clear";

/// The channel of a turn case: the user asks in the chat.
Parameter TURNCHANNEL = "web";

/// The seconds to wait for Decide's Reply: above the longest timer of Decide (110) and its 2-second conversation probe.
Parameter TURNWAIT = 150;

/// Seconds to wait before a Busy turn is asked again, and how many times it is asked again before the fallback rate_limited: the numbers
/// of Core.Conversation (a test pins them equal), kept here so that the turn path reads no Lane B class.
Parameter BUSYWAIT = 3;

Parameter BUSYMAX = 5;

/// The seconds an incident case waits for the previous incident case's row to leave state sent: above the longest a diagnose decision takes under
/// Decide's timers (MAXTIMER, 110) and the hops to and from it (a test pins it above MAXTIMER). At that bound the run sends no more incident cases.
Parameter INCIDENTWAIT = 150;

/// The seconds between two checks of the previous incident case's row.
Parameter INCIDENTPOLL = 1;

/// The name of the file that holds a case.
Parameter CASEFILE = "case.json";

Parameter REASONINPUT = "EvalIn takes the folder of a case from Start and nothing else.";

Parameter REASONNOCASEFILE = "the folder has no case.json";

Parameter REASONNOTJSON = "case.json is not a JSON object";

Parameter REASONKIND = "its kind is '{kind}', and only the kinds {kinds} are sent";

Parameter REASONNOITEMID = "it has no item.itemId";

Parameter REASONPROVENANCE = "its recorded provenance is '{provenance}', not untrusted";

Parameter REASONNOTEXT = "it has no turn.text";

Parameter REASONNOCHECKS = "its checks is not an array";

Parameter REASONNOREPLY = "Decide gave no Reply";

/// {why} says what is wrong with the persona the case or the run names.
Parameter REASONPERSONA = "its persona is not valid: {why}";

/// {why} says what is wrong with the case's before.
Parameter REASONBEFORE = "its before is not valid: {why}";

/// {why} says what is wrong with the documents the case declares or what went wrong adding them (Story 19.4).
Parameter REASONDOCUMENTS = "its documents could not be set up: {why}";

/// {why} says what is wrong with the precedents the case declares or what went wrong seeding them (Story 41.7).
Parameter REASONPRECEDENTS = "its precedents could not be seeded: {why}";

/// {why} says what is wrong with the session the case declares or what went wrong setting it up (Story 41.14).
Parameter REASONSESSION = "its session could not be set up: {why}";

Parameter REASONNOSNAPSHOT = "it has no snapshot file name";

/// {why} is the text of the status that EvidencePack.Load returned, or says that the name is not a plain file name.
Parameter REASONSNAPSHOT = "its snapshot could not be used: {why}";

Parameter REASONWATCHSHAPE = "its watch is not an object with a namespace and a production";

/// {why} is the text of the status that WatchOps.EvalWatch returned.
Parameter REASONWATCH = "its watch could not be set up: {why}";

/// {case} is the incident case whose row was still sent at the bound, and {seconds} is INCIDENTWAIT.
Parameter REASONPACED = "the incident case {case} had no result after {seconds} seconds, so this run sends no more incident cases";

/// The start of the warning for a case that is not sent; the case's name and its reason follow it.
Parameter LOGSKIPPED = "EvalIn did not send the case ";

/// The start of the warning for a TurnResult that could not be sent to EvalSink; the case's name and the error follow it.
Parameter LOGNOTDELIVERED = "EvalIn could not send the TurnResult of the case ";

/// The start of the warning for an evaluation document of an earlier run that the start of a run could not remove; the Ref and the error follow it.
Parameter LOGSWEEP = "EvalIn could not remove a document that an earlier run left: ";

/// The start of the warning for the seeded precedents of an earlier run that the start of a run could not remove; the run's Ref and the error follow it.
Parameter LOGUNSEED = "EvalIn could not remove the precedents that an earlier run seeded: ";

/// The start of the warning for an evaluation session of an earlier run that the start of a run could not remove; the Ref and the error follow it.
Parameter LOGSESSIONSWEEP = "EvalIn could not remove an evaluation session that an earlier run left: ";

/// The start of the warning for the session of a case that could not be removed after the case failed to start; the Ref and the error follow it.
Parameter LOGSESSIONDROP = "EvalIn could not remove the session of a case that was not sent: ";

/// The start of the warning for check rows in a Reply that Checks.Render could not take; the error follows it.
Parameter LOGCHECKS = "EvalIn could not render the check rows of the Reply: ";

/// The Ref of the run that this service instance sends; Start sets it.
Property RunRef As %String(MAXLEN = 22);

/// The preset id and the language name that the run names for every case that names none of its own; both "" for none. Start sets them.
Property Preset As %String(MAXLEN = 32);

Property PersonaLanguage As %String(MAXLEN = 40);

/// The setup records of the run's watches, a dynamic array of {"case", "watch"}: one for each sent case that declared a watch. Start sets it.
Property Watches As %DynamicArray;

/// The IncidentRef of the last incident case this service dispatched successfully; "" before the first. The next incident case waits for its row.
Property PaceRef As %String(MAXLEN = 22);

/// The case name of that incident case, which REASONPACED names at the bound; "" before the first.
Property PaceCase As %String(MAXLEN = 128);

/// 1 once the previous incident case's row was still sent at the bound: the run then sends no more incident cases.
Property PaceStalled As %Boolean [ InitialExpression = 0 ];

/// Starts a run: sweeps the evaluation documents that an earlier run left, creates EvalIn, mints the run's Ref, sweeps the seeded precedents that an
/// earlier run left (SweepPrecedents) and sends each case once.
///   - The sweep (DW-900) removes every document of the owner eval, with its passages, through Docs.Ops RemoveEval before anything else, so before the first case is set up: a run that
///     was killed before its Finish leaves such documents, and a case that does not name them would otherwise be answered from them. A removal that fails is one
///     warning, and the run goes on. Evaluation runs do not overlap (one release gate or one test class at a time), which is what lets a run take every eval
///     document for a leftover.
///   - After SweepPrecedents, SweepSessions drops the eval-only sessions that an earlier run left, with their memories.
///   - folder holds the case folders. names is a comma-separated list of case folder names; "" means every subfolder that holds a
///     case.json, in name order.
///   - runRef is the run's Ref, 22 characters, "" when the run did not start. sent is the number of cases sent. skipped is a dynamic
///     array of {"case", "reason"} for each case that was not sent.
///   - watches is always a dynamic array: the setup records {"case", "watch"} of the sent cases that declared a watch (empty when the run
///     did not start). The run's end passes it to Finish.
///   - preset and language are the persona of the whole run ("" for none): a case that names its own preset overrides them. A pair that
///     EvalPresetOk refuses is not checked here: each case is skipped with REASONPERSONA.
///   - The status is the director's error when EvalIn cannot be created, which a disabled EvalIn is (the text says disabled); then
///     nothing was sent and there is no run Ref. Otherwise OK.
ClassMethod Start(folder As %String = {..#FOLDER}, names As %String = "", Output runRef As %String, Output sent As %Integer, Output skipped As %DynamicArray, Output watches As %DynamicArray, preset As %String = "", language As %String = "") As %Status
{
	Set runRef = "", sent = 0, skipped = [], watches = []
	Do ..SweepDocuments()
	Set sc = ##class(Ens.Director).CreateBusinessService("EvalIn", .service)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(service) || 'service.%IsA("OcuTalon.Eval.In") Quit $SYSTEM.Status.Error(5001, "The item EvalIn is not an OcuTalon.Eval.In")
	Set folder = ##class(%File).NormalizeDirectory(folder)
	Set list = ..SendOrder(folder, ..CaseNames(folder, names))
	Set service.RunRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set service.Watches = watches
	Set service.Preset = preset, service.PersonaLanguage = language
	Set runRef = service.RunRef
	Do service.SweepPrecedents()
	Do service.SweepSessions()
	Set position = 0
	While $ListNext(list, position, name) {
		Set input = ##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(folder, name))
		Kill output
		Set sc = service.ProcessInput(input, .output)
		Set reason = $Select($$$ISERR(sc): $SYSTEM.Status.GetOneStatusText(sc), $IsObject($Get(output)): output.StringValue, 1: "")
		If reason = "" {
			Set sent = sent + 1
		} Else {
			Do skipped.%Push({"case": (name), "reason": (reason)})
		}
	}
	Quit $SYSTEM.Status.OK()
}

/// Waits, polling every 0.25 seconds and for at most the seconds, until none of the run's rows is still sent. Returns how many are.
ClassMethod Wait(runRef As %String, seconds As %Integer) As %Integer
{
	Set end = $ZHorolog + seconds
	For {
		Set open = ##class(OcuTalon.Eval.Data.CaseResult).Unanswered(runRef)
		If (open = 0) || ($ZHorolog '< end) Quit
		Hang 0.25
	}
	Quit open
}

/// Removes the watch rows of the records that Start returned in watches, each through OcuTalon.Watch.Ops.RemoveEvalWatch, and the documents of the
/// records of a documents case (DocumentsDown), the precedents of the records of a case that seeded some (Unseed, once for each distinct run) and the sessions of the records of a session case (SessionDown), and nothing else. A row that is already gone is no error. Every record is tried; the status is the first error, and Finish never throws.
ClassMethod Finish(watches As %DynamicArray) As %Status
{
	Set result = $$$OK
	Try {
		If $IsObject($Get(watches)) && watches.%IsA("%Library.DynamicArray") {
			Set iterator = watches.%GetIterator()
			While iterator.%GetNext(, .record) {
				Set sc = ..Unwatch($Select($IsObject(record) && record.%IsA("%Library.DynamicObject"): record.%Get("watch"), 1: ""))
				If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
				If $IsObject(record) && record.%IsA("%Library.DynamicObject") && $IsObject(record.%Get("documents")) {
					Set sc = ..DocumentsDown(record.%Get("documents"))
					If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
				}
				If $IsObject(record) && record.%IsA("%Library.DynamicObject") && $IsObject(record.%Get("session")) {
					Set sc = ..SessionDown(record.%Get("session"))
					If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
				}
				Set run = $Select($IsObject(record) && record.%IsA("%Library.DynamicObject") && $IsObject(record.%Get("precedents")): record.%Get("precedents").%Get("runRef"), 1: "")
				If (run '= "") && '$Data(runs(run)) {
					Set runs(run) = ""
					Set sc = ..Unseed(run)
					If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
				}
			}
		}
	} Catch exception {
		If $$$ISOK(result) Set result = exception.AsStatus()
	}
	Quit result
}

/// The case folder names to send, as a list: the names given, each once, in the order given, or, with no names, every subfolder of the
/// folder that holds a case.json, in name order.
ClassMethod CaseNames(folder As %String, names As %String) As %List
{
	Set list = ""
	If $ZStrip(names, "*W") '= "" {
		For i = 1:1:$Length(names, ",") {
			Set name = $ZStrip($Piece(names, ",", i), "<>W")
			If (name '= "") && '$ListFind(list, name) Set list = list_$ListBuild(name)
		}
		Quit list
	}
	Set rows = ##class(%ResultSet).%New("%File:FileSet")
	If $$$ISERR(rows.Execute(folder, "*", "Name", 1)) Quit ""
	While rows.Next() {
		If rows.Get("Type") '= "D" Continue
		Set name = rows.Get("ItemName")
		If ##class(%File).Exists(##class(%File).NormalizeFilename(..#CASEFILE, ##class(%File).SubDirectoryName(folder, name))) Set list = list_$ListBuild(name)
	}
	Quit list
}

/// The case list in the order Start sends it: the cases of the turn kinds first, then every other, each group in the order of the list. A
/// case whose kind cannot be read goes with the others.
ClassMethod SendOrder(folder As %String, list As %List) As %List
{
	Set turns = "", others = ""
	Set position = 0
	While $ListNext(list, position, name) {
		If $ListFind($ListFromString(..#TURNKINDS), ..KindOf(folder, name)) {
			Set turns = turns_$ListBuild(name)
		} Else {
			Set others = others_$ListBuild(name)
		}
	}
	Quit turns_others
}

/// The kind of the case in the folder's subfolder of that name, or "" when its case.json cannot be read.
ClassMethod KindOf(folder As %String, name As %String) As %String [ Private ]
{
	Set kind = ""
	Try {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename(..#CASEFILE, ##class(%File).SubDirectoryName(folder, name)))
		If $IsObject(case) && case.%IsA("%Library.DynamicObject") Set kind = ..Scalar(case, "kind")
	} Catch exception {
		Set kind = ""
	}
	Quit kind
}

/// Sends the case in the folder; pOutput is an Ens.StringContainer whose StringValue is "" when the case was sent, and otherwise the
/// reason it was not.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ##class(Ens.StringContainer).%New("")
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("Ens.StringContainer") || (..RunRef = "") {
		Set pOutput.StringValue = ..#REASONINPUT
		Quit $$$OK
	}
	Set folder = pInput.StringValue
	Set name = ##class(%File).GetFilename($ZStrip(folder, ">", "/"))
	Set reason = ""
	Try {
		Set reason = ..Send(folder, name)
	} Catch exception {
		Set reason = exception.DisplayString()
	}
	If reason '= "" $$$LOGWARNING(..#LOGSKIPPED_name_": "_reason)
	Set pOutput.StringValue = reason
	Quit $$$OK
}

/// The steps for one case; the reason it was not sent, or "" when it was.
Method Send(folder As %String, name As %String) As %String [ Private ]
{
	Set file = ##class(%File).NormalizeFilename(..#CASEFILE, folder)
	If '##class(%File).Exists(file) Quit ..#REASONNOCASEFILE
	Set case = ""
	Try {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
	} Catch exception {
		Set case = ""
	}
	If '$IsObject(case) || 'case.%IsA("%Library.DynamicObject") Quit ..#REASONNOTJSON
	Set kind = ..Scalar(case, "kind")
	If '$ListFind($ListFromString(..#KINDS), kind) Quit $Replace($Replace(..#REASONKIND, "{kind}", $Extract(kind, 1, 40)), "{kinds}", ..KindsText())
	If case.%IsDefined("session") && (kind '= "command") Quit $Replace(..#REASONSESSION, "{why}", "only a command case has a session")
	If kind = ..#INCIDENTKIND Quit ..SendIncident(case, folder, name)
	If kind = ..#DIGESTKIND Quit ..SendDigest(case, name)
	Set reason = ..Persona(case, .preset, .language)
	If reason '= "" Quit reason
	If $ListFind($ListFromString(..#TURNKINDS), kind) {
		Set session = ""
		If case.%IsDefined("session") {
			Set reason = ..SessionShape(case.%Get("session"), kind, .texts)
			If reason '= "" Quit $Replace(..#REASONSESSION, "{why}", reason)
			Set reason = ..SessionUp(name, texts, .session)
			If reason '= "" Quit $Replace(..#REASONSESSION, "{why}", reason)
		}
		If kind '= ..#DOCUMENTSKIND {
			Set reason = ..SendTurn(case, kind, name, preset, language, $Select($IsObject(session): session.ref, 1: ""))
			If (reason '= "") && $IsObject(session) Do ..SessionDrop(session)
			Quit reason
		}
		Set reason = ..DocumentsUp(case, folder, .documents)
		If reason '= "" Quit reason
		Set reason = ..SendTurn(case, kind, name, preset, language)
		If reason '= "" {
			Do ..DocumentsDown(documents)
		} Else {
			If '$IsObject(..Watches) Set ..Watches = []
			Do ..Watches.%Push({"case": (name), "documents": (documents)})
		}
		Quit reason
	}
	Set record = case.item
	If '$IsObject(record) || 'record.%IsA("%Library.DynamicObject") || (..Scalar(record, "itemId") = "") Quit ..#REASONNOITEMID
	Set provenance = ..Scalar(record, "provenance")
	If (provenance '= "") && (provenance '= "untrusted") Quit $Replace(..#REASONPROVENANCE, "{provenance}", $Extract(provenance, 1, 40))
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SourceItemId = ..Scalar(record, "itemId")
	Set item.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set item.Channel = ..Scalar(record, "channel")
	Set item.Provenance = "untrusted"
	Set item.Sender = ..Scalar(record, "sender")
	Set item.Subject = ..Scalar(record, "subject")
	Set item.Text = ..Scalar(record, "text")
	Set item.CatalogKey = ..Scalar(record, "catalogKey")
	Set item.Slots = $Select($IsObject(record.slots): record.slots.%ToJSON(), 1: ..Scalar(record, "slots"))
	Set entries = ""
	If case.%IsDefined("precedents") {
		Set reason = ..PrecedentsShape(case.%Get("precedents"), item, .entries)
		If reason '= "" Quit $Replace(..#REASONPRECEDENTS, "{why}", reason)
	}
	Set watch = ""
	If case.%IsDefined("watch") {
		Set reason = ..WatchUp(case.%Get("watch"), .watch)
		If reason '= "" Quit reason
	}
	Set opened = 0, why = "", sc = $$$OK
	Try {
		Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, item.SourceItemId, item.ItemId, preset, language, $IsObject(entries))
		If $$$ISOK(sc) {
			Set opened = 1
			Set ..%SuperSession = ..RunRef
			If $IsObject(entries) Set why = ..SeedAll(entries, item, name)
			If why = "" Set sc = ..Dispatch(item)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If (why '= "") || $$$ISERR(sc) {
		If opened Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
		Do ..Unwatch(watch)
		Quit $Select(why '= "": $Replace(..#REASONPRECEDENTS, "{why}", why), 1: $SYSTEM.Status.GetOneStatusText(sc))
	}
	If $IsObject(watch) {
		If '$IsObject(..Watches) Set ..Watches = []
		Do ..Watches.%Push({"case": (name), "watch": (watch)})
	}
	Quit ""
}

/// The steps for one incident case: the reason it was not sent, or "" when it was. The case's snapshot member must be a plain file name (no path
/// separator, no ..) of a recorded reader snapshot in the case's folder that EvidencePack.Load takes; otherwise the case is refused before anything is saved.
/// Otherwise, once Pace allows it (the previous incident case's row is no longer sent), the row is opened with the IncidentRef as ItemId, and the IncidentCase is
/// sent; a send that fails or throws deletes the row. A case that Pace refuses is not sent and leaves no row. Only a case that was sent becomes the previous one.
Method SendIncident(case As %DynamicObject, folder As %String, name As %String) As %String [ Private ]
{
	Set file = ..Scalar(case, "snapshot")
	If file = "" Quit ..#REASONNOSNAPSHOT
	If (file [ "/") || (file [ "\") || (file [ "..") Quit $Replace(..#REASONSNAPSHOT, "{why}", "the name is not a plain file name")
	Set sc = ##class(OcuTalon.Watch.EvidencePack).Load(##class(%File).NormalizeFilename(file, folder), .snapshot)
	If $$$ISERR(sc) Quit $Replace(..#REASONSNAPSHOT, "{why}", $SYSTEM.Status.GetOneStatusText(sc))
	Set incident = ##class(OcuTalon.Eval.Msg.IncidentCase).%New()
	Set incident.IncidentRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set incident.SourceItemId = name
	Set incident.Snapshot = snapshot.%ToJSON()
	Set reason = ..Pace()
	If reason '= "" Quit reason
	Set opened = 0
	Try {
		Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, name, incident.IncidentRef)
		If $$$ISOK(sc) {
			Set opened = 1
			Set ..%SuperSession = ..RunRef
			Set sc = ..DispatchIncident(incident)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		If opened Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
		Quit $SYSTEM.Status.GetOneStatusText(sc)
	}
	Set ..PaceRef = incident.IncidentRef, ..PaceCase = name
	Quit ""
}

/// The wait before an incident case: "" when it may be sent, otherwise REASONPACED. With no previous incident case it is "". Otherwise, until the previous
/// case's row is no longer sent, it pauses INCIDENTPOLL seconds and checks again, at most INCIDENTWAIT \ INCIDENTPOLL times. A row still sent after the last
/// pause sets PaceStalled, and from then on every incident case of the run gets REASONPACED at once, with no check and no pause.
Method Pace() As %String [ Private ]
{
	If ..PaceRef = "" Quit ""
	If '..PaceStalled {
		Set pauses = 0
		While ..StillSent(..PaceRef) {
			If pauses '< (..#INCIDENTWAIT \ ..#INCIDENTPOLL) {
				Set ..PaceStalled = 1
				Quit
			}
			Do ..Pause(..#INCIDENTPOLL)
			Set pauses = pauses + 1
		}
	}
	If '..PaceStalled Quit ""
	Quit $Replace($Replace(..#REASONPACED, "{case}", ..PaceCase), "{seconds}", ..#INCIDENTWAIT)
}

/// 1 while the row of the ItemId is in state sent; a row that is decided or removed is not.
Method StillSent(itemId As %String) As %Boolean [ Private ]
{
	Quit $IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(itemId))
}

/// The steps for one digest case: the reason it was not sent, or "" when it was. A case whose checks is not an array is refused with REASONNOCHECKS before
/// anything is saved. Otherwise the row is opened with the ItemId of the DigestCase, and the DigestCase is sent; a send that fails or throws deletes the row.
Method SendDigest(case As %DynamicObject, name As %String) As %String [ Private ]
{
	Set checks = case.checks
	If '$IsObject(checks) || 'checks.%IsA("%Library.DynamicArray") Quit ..#REASONNOCHECKS
	Set vitals = case.vitals
	Set saved = case.saved
	Set digest = ##class(OcuTalon.Eval.Msg.DigestCase).%New()
	Set digest.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set digest.SourceItemId = name
	Set digest.RecordedChecks = checks.%ToJSON()
	Set digest.RecordedVitals = $Select($IsObject(vitals) && vitals.%IsA("%Library.DynamicObject"): vitals.%ToJSON(), 1: "")
	Set digest.RecordedSaved = $Select($IsObject(saved) && saved.%IsA("%Library.DynamicArray"): saved.%ToJSON(), 1: "")
	Set opened = 0
	Try {
		Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, name, digest.ItemId)
		If $$$ISOK(sc) {
			Set opened = 1
			Set ..%SuperSession = ..RunRef
			Set sc = ..DispatchDigest(digest)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		If opened Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
		Quit $SYSTEM.Status.GetOneStatusText(sc)
	}
	Quit ""
}

/// Checks the precedents member of an item or injection case: the reason it is not usable, or "" with entries set to the array (1 to PRECEDENTSMAX valid
/// entries). The Item's Data.Precedent.KeyFor must not be "" either, for there would be nothing to match. Nothing is saved or sent.
Method PrecedentsShape(declared As %DynamicObject, item As OcuTalon.Msg.Item, Output entries As %DynamicArray) As %String [ Private ]
{
	Set entries = ""
	If '$IsObject(declared) || 'declared.%IsA("%Library.DynamicArray") Quit "precedents is not an array"
	If (declared.%Size() < 1) || (declared.%Size() > ..#PRECEDENTSMAX) Quit "precedents holds "_declared.%Size()_" entries, and it takes 1 to "_..#PRECEDENTSMAX
	Set iterator = declared.%GetIterator()
	Set bad = ""
	While iterator.%GetNext(.index, .entry) && (bad = "") {
		If '..EntryOk(entry) Set bad = index + 1
	}
	If bad '= "" Quit "precedent "_bad_" is not {summary, answer, outcome, daysAgo} with a summary of 1 to 80 characters, an answer of "_##class(OcuTalon.Data.Precedent).#ANSWERS_", an outcome (optional) of "_##class(OcuTalon.Msg.Enum).#OUTCOME_" and a daysAgo (optional) of a whole number 0 to "_..#PRECEDENTDAYS
	If ##class(OcuTalon.Data.Precedent).KeyFor(item) = "" Quit "the item has no match key"
	Set entries = declared
	Quit ""
}

/// 1 when the precedent entry is valid (see PrecedentsShape).
ClassMethod EntryOk(entry As %DynamicObject) As %Boolean [ Private ]
{
	If '$IsObject(entry) || 'entry.%IsA("%Library.DynamicObject") Quit 0
	If (entry.%GetTypeOf("summary") '= "string") || ($ZStrip(entry.summary, "<>WC") = "") || ($Length(entry.summary) > 80) Quit 0
	If (entry.%GetTypeOf("answer") '= "string") || '$ListFind($ListFromString(##class(OcuTalon.Data.Precedent).#ANSWERS), entry.answer) Quit 0
	If entry.%IsDefined("outcome") && ((entry.%GetTypeOf("outcome") '= "string") || '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#OUTCOME), entry.outcome)) Quit 0
	If entry.%IsDefined("daysAgo") {
		If entry.%GetTypeOf("daysAgo") '= "number" Quit 0
		Set days = entry.daysAgo
		If (days '= (days \ 1)) || (days < 0) || (days > ..#PRECEDENTDAYS) Quit 0
	}
	Quit 1
}

/// Seeds the entries of a case, in order. The case's setup record {case, precedents{runRef}} joins the Watches of the service before the first seed, so that
/// Finish removes what was seeded even when a later seed fails. Returns the reason a seed failed, or "" when every one was answered seeded.
Method SeedAll(entries As %DynamicArray, item As OcuTalon.Msg.Item, name As %String) As %String [ Private ]
{
	If '$IsObject(..Watches) Set ..Watches = []
	Do ..Watches.%Push({"case": (name), "precedents": {"runRef": (..RunRef)}})
	Set key = ##class(OcuTalon.Data.Precedent).KeyFor(item)
	Set sc = $$$OK
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(.index, .entry) {
		Set message = ##class(OcuTalon.Core.Msg.SeedPrecedent).%New()
		Set message.RunRef = ..RunRef
		Set message.Channel = item.Channel
		Set message.MatchKey = key
		Set message.Summary = entry.summary
		Set message.Outcome = ..Scalar(entry, "outcome")
		Set message.Answer = entry.answer
		Set message.AnsweredAt = $Select(entry.%IsDefined("daysAgo"): ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -(entry.daysAgo * 86400)), 1: "")
		Kill result
		Set sc = ..Seed(message, .result)
		If $$$ISERR(sc) Quit
		If '$IsObject($Get(result)) || 'result.%IsA("OcuTalon.Msg.CommandResult") {
			Set sc = $SYSTEM.Status.Error(5001, "precedent "_(index + 1)_" was answered with no CommandResult")
			Quit
		}
		If result.Outcome '= "seeded" {
			Set sc = $SYSTEM.Status.Error(5001, "precedent "_(index + 1)_" was answered "_result.Outcome_", not seeded")
			Quit
		}
	}
	Quit $Select($$$ISERR(sc): $SYSTEM.Status.GetOneStatusText(sc), 1: "")
}

/// The one send of a seed: the SeedPrecedent to PrecedentOps, synchronously, for at most PRECEDENTWAIT seconds. Private; a test subclass overrides it.
Method Seed(message As OcuTalon.Core.Msg.SeedPrecedent, Output result As %Library.Persistent) As %Status [ Private ]
{
	Set result = ""
	Quit ..SendRequestSync(..#PRECEDENTTARGET, message, .result, ..#PRECEDENTWAIT)
}

/// Removes every precedent row of the run through PrecedentOps (RemoveRun), from a new EvalIn service. The status is the director's error, the send's, or
/// an error when PrecedentOps does not answer removed. A test subclass overrides it.
ClassMethod Unseed(runRef As %String) As %Status
{
	Set sc = ##class(Ens.Director).CreateBusinessService("EvalIn", .service)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(service) || 'service.%IsA("OcuTalon.Eval.In") Quit $SYSTEM.Status.Error(5001, "The item EvalIn is not an OcuTalon.Eval.In")
	Quit service.RemoveRun(runRef)
}

/// Sends PrecedentOps one RemoveSeededPrecedents for the run: OK when it answers removed, otherwise an error status.
Method RemoveRun(runRef As %String) As %Status
{
	If runRef = "" Quit $SYSTEM.Status.Error(5001, "The precedents of a run need the run")
	Set message = ##class(OcuTalon.Core.Msg.RemoveSeededPrecedents).%New()
	Set message.RunRef = runRef
	Set sc = ..SendRequestSync(..#PRECEDENTTARGET, message, .result, ..#PRECEDENTWAIT)
	If $$$ISERR(sc) Quit sc
	If '$IsObject($Get(result)) || 'result.%IsA("OcuTalon.Msg.CommandResult") || (result.Outcome '= "removed") Quit $SYSTEM.Status.Error(5001, "PrecedentOps did not answer removed for the run "_runRef)
	Quit $$$OK
}

/// The sweep at the start of a run: for each earlier run that left a marked row (CaseResult.PrecedentRuns), removes its seeded precedents (RemoveRun) and,
/// when that worked, clears its marks (CaseResult.Unmark); its case rows stay, so a report or a persona sweep that reads them after this start still finds
/// them. A removal that fails is one warning (LOGUNSEED), its marks stay for the next sweep, and the run goes on. It never throws.
Method SweepPrecedents()
{
	Try {
		Set runs = ##class(OcuTalon.Eval.Data.CaseResult).PrecedentRuns(..RunRef)
		Set position = 0
		While $ListNext(runs, position, run) {
			Set sc = ..RemoveRun(run)
			If $$$ISOK(sc) Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Unmark(run)
			If $$$ISERR(sc) $$$LOGWARNING(..#LOGUNSEED_run_": "_$SYSTEM.Status.GetOneStatusText(sc))
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGUNSEED_exception.DisplayString())
	}
}

/// Checks the session member of a command case (Story 41.14): the reason it is not usable, or "" with texts set to the array of the forgotten texts (empty when the session
/// declares none). Only a command case has a session; the session is an object; forgotten, when present, is an array of 1 to SESSIONFORGOTTENMAX strings that are not blank
/// and have at most SESSIONTEXTMAX characters. Nothing is saved or sent.
Method SessionShape(declared As %DynamicObject, kind As %String, Output texts As %DynamicArray) As %String [ Private ]
{
	Set texts = []
	If kind '= "command" Quit "only a command case has a session"
	If '$IsObject(declared) || 'declared.%IsA("%Library.DynamicObject") Quit "session is not an object"
	If 'declared.%IsDefined("forgotten") Quit ""
	Set list = declared.%Get("forgotten")
	If '$IsObject(list) || 'list.%IsA("%Library.DynamicArray") || (list.%Size() < 1) || (list.%Size() > ..#SESSIONFORGOTTENMAX) Quit "forgotten is not an array of 1 to "_..#SESSIONFORGOTTENMAX_" texts"
	Set usable = 1
	For i = 0:1:list.%Size() - 1 {
		If (list.%GetTypeOf(i) '= "string") || ($ZStrip(list.%Get(i), "<>WC") = "") || ($Length(list.%Get(i)) > ..#SESSIONTEXTMAX) Set usable = 0
	}
	If 'usable Quit "forgotten holds a text that is not a non-blank string of at most "_..#SESSIONTEXTMAX_" characters"
	Set texts = list
	Quit ""
}

/// Makes the session of a session case (Data.Session.ForEval) and seeds its forgotten texts. The case's setup record {case, session{ref}} joins the Watches of the service as
/// soon as the row exists, so that Finish drops it. session is that record's {ref}. Returns the reason the session could not be set up, or "" with the session ready; on a
/// reason the session is already dropped and its record removed.
Method SessionUp(name As %String, texts As %DynamicArray, Output session As %DynamicObject) As %String [ Private ]
{
	Set session = ""
	Set ..%SuperSession = ..RunRef
	Set row = ..SessionRow(.sc)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	If '$IsObject(row) Quit "no session row was made"
	Set session = {"ref": (row.Ref)}
	If '$IsObject(..Watches) Set ..Watches = []
	Do ..Watches.%Push({"case": (name), "session": (session)})
	Set why = ..SessionSeed(row.Ref, texts)
	If why '= "" {
		Do ..SessionDrop(session)
		Set session = ""
	}
	Quit why
}

/// The one making of a session case's Session row: Data.Session.ForEval, which makes it only while OCUTALON_EVAL is 1. Private; a test subclass overrides it.
Method SessionRow(Output sc As %Status) As OcuTalon.Data.Session [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).ForEval(.sc)
}

/// Saves each text as a memory of the session and forgets it again, both through MemoryOps (the real OnSave and OnForget). The save is a SaveMemory of origin system with a fresh
/// idempotency key and must answer saved; the forget is a ForgetMemory of the Ref in that answer and must answer forgotten. Returns the reason one was not, or "".
Method SessionSeed(sessionRef As %String, texts As %DynamicArray) As %String [ Private ]
{
	Set iterator = texts.%GetIterator()
	While iterator.%GetNext(.index, .text) {
		Set save = ##class(OcuTalon.Msg.Command.SaveMemory).%New()
		Set save.SessionRef = sessionRef
		Set save.Origin = "system"
		Set save.IdempotencyKey = ##class(OcuTalon.Bridge.Ids).NewRef()_":1"
		Set save.Text = text
		Set why = ..SessionAsk(save, "saved", "the save of memory "_(index + 1), .saved)
		If why '= "" Quit
		Set forget = ##class(OcuTalon.Msg.Command.ForgetMemory).%New()
		Set forget.SessionRef = sessionRef
		Set forget.Origin = "system"
		Set forget.IdempotencyKey = ##class(OcuTalon.Bridge.Ids).NewRef()_":1"
		Set forget.MemoryRef = saved.Ref
		Set why = ..SessionAsk(forget, "forgotten", "the forget of memory "_(index + 1), .forgotten)
		If why '= "" Quit
	}
	Quit $Get(why)
}

/// Sends MemoryOps the command and checks that it answered a CommandResult with the outcome; the reason it did not, or "". what names the command in the reason.
Method SessionAsk(command As OcuTalon.Msg.Command, outcome As %String, what As %String, Output result As %Library.Persistent) As %String [ Private ]
{
	Set result = ""
	Set sc = ..AskMemory(command, .result)
	If $$$ISERR(sc) Quit what_" failed: "_$SYSTEM.Status.GetOneStatusText(sc)
	If '$IsObject($Get(result)) || 'result.%IsA("OcuTalon.Msg.CommandResult") Quit what_" was answered with no CommandResult"
	If result.Outcome '= outcome Quit what_" was answered "_result.Outcome_", not "_outcome
	Quit ""
}

/// The one send of a seeded memory command: to MemoryOps, synchronously, for at most MEMORYWAIT seconds. Private; a test subclass overrides it.
Method AskMemory(command As OcuTalon.Msg.Command, Output result As %Library.Persistent) As %Status [ Private ]
{
	Set result = ""
	Quit ..SendRequestSync(..#MEMORYTARGET, command, .result, ..#MEMORYWAIT)
}

/// Drops the session of a case that was not sent (SessionDown) and removes its setup record from the Watches again; a failed drop is one warning.
Method SessionDrop(session As %DynamicObject) [ Private ]
{
	Set sc = ..SessionDown(session)
	If $$$ISERR(sc) $$$LOGWARNING(..#LOGSESSIONDROP_session.%Get("ref")_": "_$SYSTEM.Status.GetOneStatusText(sc))
	If $IsObject(..Watches) && ..Watches.%Size() {
		Set last = ..Watches.%Get(..Watches.%Size() - 1)
		If $IsObject(last) && $IsObject(last.%Get("session")) && (last.%Get("session").%Get("ref") = session.%Get("ref")) Do ..Watches.%Pop()
	}
}

/// Drops the memories of the session record {"ref"} (Memory.DropSession, the sign-out's own drop), then the conversation links of its turns (Bridge.Purge.DropLinks, as
/// Data.Purge drops a session's, so that the AI sessions they name are freed) and then its row (Data.Session.DropEval, which drops only a row that has no IrisUser). A row that has an IrisUser (a person's, a visitor's) is refused first (DropEval's error), with its memories untouched. A row that is already gone is no error. When the memories cannot be dropped the row stays, so that SweepSessions finds both again; the status is then that error.
/// It never throws.
ClassMethod SessionDown(session As %DynamicObject) As %Status
{
	Set result = $$$OK
	Try {
		Set ref = $Select($IsObject(session): session.%Get("ref"), 1: "")
		If ref = "" Quit
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		If $IsObject(row) && (row.IrisUser '= "") {
			Set row = ""
			Set result = ##class(OcuTalon.Data.Session).DropEval(ref)
			Quit
		}
		Set row = ""
		Set result = ##class(OcuTalon.Memory).DropSession(ref)
		If $$$ISERR(result) Quit
		Set result = ##class(OcuTalon.Bridge.Purge).DropLinks(ref)
		If $$$ISERR(result) Quit
		If ##class(OcuTalon.Data.Session).RefIndexExists(ref) Set result = ##class(OcuTalon.Data.Session).DropEval(ref)
	} Catch exception {
		Set result = exception.AsStatus()
	}
	Quit result
}

/// Drops every evaluation session that an earlier run left: each Session row with no IrisUser, with its memories (SessionDown). A drop that fails, or a failure to list them,
/// is one warning, and the run goes on. A row with an IrisUser is never touched. It never throws.
ClassMethod SweepSessions()
{
	Try {
		Set refs = []
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session WHERE COALESCE(IrisUser, '') = ''")
		If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, rs.%Message))
		While rs.%Next() {
			Do refs.%Push(rs.%Get("Ref"))
		}
		Set iterator = refs.%GetIterator()
		While iterator.%GetNext(, .ref) {
			Set sc = ..SessionDown({"ref": (ref)})
			If $$$ISERR(sc) $$$LOGWARNING(..#LOGSESSIONSWEEP_ref_": "_$SYSTEM.Status.GetOneStatusText(sc))
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGSESSIONSWEEP_exception.DisplayString())
	}
}

/// Sets up the watch that a case declares: the reason it was not set up, or "" when it was, with the watch's stored fields in fields. A watch
/// that is not an object with a non-blank namespace and production is REASONWATCHSHAPE; one that WatchOps.EvalWatch refuses is REASONWATCH.
Method WatchUp(declared As %DynamicObject, Output fields As %DynamicObject) As %String [ Private ]
{
	Set fields = ""
	If '$IsObject(declared) || 'declared.%IsA("%Library.DynamicObject") Quit ..#REASONWATCHSHAPE
	Set namespace = ..Scalar(declared, "namespace"), production = ..Scalar(declared, "production")
	If ($ZStrip(namespace, "<>WC") = "") || ($ZStrip(production, "<>WC") = "") Quit ..#REASONWATCHSHAPE
	Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch(namespace, production, .fields)
	If $$$ISERR(sc) {
		Set fields = ""
		Quit $Replace(..#REASONWATCH, "{why}", $SYSTEM.Status.GetOneStatusText(sc))
	}
	Quit ""
}

/// Removes the watch row of the stored fields (WatchOps.Fields of the row); "" is no watch. The status of WatchOps.RemoveEvalWatch.
ClassMethod Unwatch(fields As %DynamicObject) As %Status [ Private ]
{
	If '$IsObject(fields) Quit $$$OK
	Quit ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(fields.%Get("Ref"))
}

/// The kinds that EvalIn sends, as the text of a reason: joined with a comma, and with "and" before the last one.
ClassMethod KindsText() As %String [ Private ]
{
	Set count = $Length(..#KINDS, ",")
	If count < 2 Quit ..#KINDS
	Quit $Replace($Piece(..#KINDS, ",", 1, count - 1), ",", ", ")_" and "_$Piece(..#KINDS, ",", count)
}

/// The one send of an item case: the Item to the target item, asynchronously, with no answer. Private; a test subclass overrides it.
Method Dispatch(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#TARGET, item)
}

/// The one send of an incident case: the IncidentCase to IncidentManager, asynchronously, with no answer wanted. Private; a test subclass overrides it.
Method DispatchIncident(incident As OcuTalon.Eval.Msg.IncidentCase) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#INCIDENTTARGET, incident)
}

/// The one send of a digest case: the DigestCase to Digest, asynchronously, with no answer wanted. Private; a test subclass overrides it.
Method DispatchDigest(digest As OcuTalon.Eval.Msg.DigestCase) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#DIGEST, digest)
}

/// The steps for one turn case (see the class description); the reason it was not sent, or "" when it was. A case that has no turn.text,
/// or an all-clear case whose checks is not an array, is refused before anything is saved. Otherwise the case's TurnResult and row are
/// saved, and a case that gets no Reply from Decide (or whose send throws) loses both again. A row that cannot be opened (the run already
/// has a row of that case) is refused with the error text, and only the case's own TurnResult is deleted: the row that is there stays. owner is the Ref of the case's
/// session (Story 41.14), "" for the owner eval.
Method SendTurn(case As %DynamicObject, kind As %String, name As %String, preset As %String = "", language As %String = "", owner As %String = "") As %String [ Private ]
{
	Set turn = case.turn
	Set text = $Select($IsObject(turn) && turn.%IsA("%Library.DynamicObject"): ..Scalar(turn, "text"), 1: "")
	If $ZStrip(text, "*WC") = "" Quit ..#REASONNOTEXT
	Set recorded = ""
	If kind = ..#ALLCLEARKIND {
		Set checks = case.checks
		If '$IsObject(checks) || 'checks.%IsA("%Library.DynamicArray") Quit ..#REASONNOCHECKS
		Set recorded = checks.%ToJSON()
	}
	Set ..%SuperSession = ..RunRef
	Set linked = 0
	If case.%IsDefined("before") {
		Set reason = ..Before(case.before, kind, name)
		If reason '= "" Quit reason
		Set linked = 1
	}
	Set result = ##class(OcuTalon.Eval.Msg.TurnResult).%New()
	Set result.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set result.SourceItemId = name
	Set result.RecordedChecks = recorded
	Set sc = result.%Save()
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, name, result.ItemId, preset, language)
	If $$$ISERR(sc) {
		Do ##class(OcuTalon.Eval.Msg.TurnResult).%DeleteId(result.%Id())
		Quit $SYSTEM.Status.GetOneStatusText(sc)
	}
	Set reason = ""
	Try {
		Set reason = ..Converse(result, text, name, kind, linked, owner)
	} Catch exception {
		Set reason = exception.DisplayString()
	}
	If reason '= "" Do ..Discard(result, name)
	Quit reason
}

/// Asks Decide for the turn, again after a Busy reply, then keeps the Reply in the TurnResult and sends the TurnResult to EvalSink. The
/// reason there was no Reply to keep, or "". The turn is asked at most BUSYMAX + 1 times, BUSYWAIT seconds apart; a Decide that is busy
/// every time ends the case as a fallback with the reason rate_limited, with no DecisionRef.
Method Converse(result As OcuTalon.Eval.Msg.TurnResult, text As %String, name As %String, kind As %String = "", linked As %Boolean = 0, owner As %String = "") As %String [ Private ]
{
	Set userTurn = (kind = ..#USERTURNKIND)
	Set answerClass = $Select(userTurn: "OcuTalon.Bridge.Msg.DecisionResponse", 1: "OcuTalon.Bridge.Msg.Reply")
	Set sc = ..AskTurn(result.ItemId, text, userTurn, linked, .reply, owner)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	If '$IsObject($Get(reply)) || 'reply.%IsA(answerClass) Quit ..#REASONNOREPLY
	If userTurn {
		Set result.DecisionRef = reply.DecisionRef
		Set result.Fallback = +reply.Fallback
		Set result.FallbackReason = reply.FallbackReason
	} ElseIf reply.Busy {
		Set result.Fallback = 1
		Set result.FallbackReason = "rate_limited"
	} Else {
		Set result.DecisionRef = reply.DecisionRef
		Set result.ToolsRun = +reply.ToolsRun
		Set result.ReplyText = reply.Text
		Set result.Fallback = +reply.Fallback
		Set result.FallbackReason = reply.FallbackReason
		Do ..Render(result, reply.HostData)
		Do ..Cite(result, reply.HostData)
	}
	Set sc = result.%Save()
	If $$$ISOK(sc) Set sc = ..Deliver(result)
	If $$$ISERR(sc) $$$LOGWARNING(..#LOGNOTDELIVERED_name_": "_$SYSTEM.Status.GetOneStatusText(sc))
	Quit ""
}

/// Asks Decide for a turn, again after a Busy reply: at most BUSYMAX + 1 times, BUSYWAIT seconds apart. reply is the last answer. A user turn is
/// asked once, because its answer has no Busy.
Method AskTurn(itemId As %String, text As %String, userTurn As %Boolean, linked As %Boolean, Output reply, owner As %String = "") As %Status [ Private ]
{
	Set answerClass = $Select(userTurn: "OcuTalon.Bridge.Msg.DecisionResponse", 1: "OcuTalon.Bridge.Msg.Reply")
	Set reply = "", sc = $$$OK
	For asks = 1:1:..#BUSYMAX + 1 {
		Kill reply
		Set sc = ..Ask(..TurnRequest(itemId, text, userTurn, linked, owner), .reply)
		If $$$ISERR(sc) Quit
		If '$IsObject($Get(reply)) || 'reply.%IsA(answerClass) Quit
		If userTurn || 'reply.Busy Quit
		If asks '> ..#BUSYMAX Do ..Pause(..#BUSYWAIT)
	}
	Quit sc
}

/// The persona of a case: the case's own preset and language, or the run's. A case that names a preset takes its language with it (empty when it
/// names none); a case that names only a language keeps the run's preset. Returns the reason the case is not sent (REASONPERSONA), or "" with
/// preset and language set to the effective pair; both "" when neither the run nor the case names one.
Method Persona(case As %DynamicObject, Output preset As %String, Output language As %String) As %String [ Private ]
{
	Set preset = ..Preset, language = ..PersonaLanguage
	If case.%IsDefined("preset") && (case.%GetTypeOf("preset") '= "string") Quit $Replace(..#REASONPERSONA, "{why}", "preset is not a string")
	If case.%IsDefined("language") && (case.%GetTypeOf("language") '= "string") Quit $Replace(..#REASONPERSONA, "{why}", "language is not a string")
	If case.%IsDefined("preset") {
		Set preset = case.%Get("preset"), language = ""
	}
	If case.%IsDefined("language") Set language = case.%Get("language")
	If (preset = "") && (language = "") Quit ""
	If '##class(OcuTalon.Agent.Persona).EvalPresetOk(preset, language) {
		Quit $Replace(..#REASONPERSONA, "{why}", "preset '"_$Extract($ZStrip(preset, "*C"), 1, 40)_"' with a language of "_$Length(language)_" character(s)")
	}
	Quit ""
}

/// The old turn of a case (DW-678): asked first as a fresh turn of its own preset under the temporary row <name>/before. Returns "" when it got
/// a Reply that is neither Busy nor a fallback (so the agent saved its session), or the reason the case is not sent (a Busy or fallback Reply is
/// REASONNOREPLY); the row is removed in every case. A before is an object with a non-blank text
/// and a preset and language that EvalPresetOk takes; only the kinds all-clear and command carry one.
Method Before(before As %DynamicObject, kind As %String, name As %String) As %String [ Private ]
{
	If (kind '= ..#ALLCLEARKIND) && (kind '= "command") Quit $Replace(..#REASONBEFORE, "{why}", "only an all-clear or command case has one")
	If '$IsObject(before) || 'before.%IsA("%Library.DynamicObject") Quit $Replace(..#REASONBEFORE, "{why}", "it is not an object")
	Set text = ..Scalar(before, "text"), preset = ..Scalar(before, "preset"), language = ..Scalar(before, "language")
	If $ZStrip(text, "*WC") = "" Quit $Replace(..#REASONBEFORE, "{why}", "it has no text")
	If '##class(OcuTalon.Agent.Persona).EvalPresetOk(preset, language) Quit $Replace(..#REASONBEFORE, "{why}", "its preset or language is not valid")
	Set old = name_"/before"
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, old, old, itemId, preset, language)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	Set reason = ""
	Try {
		Set sc = ..AskTurn(itemId, text, 0, 0, .reply)
		If $$$ISERR(sc) {
			Set reason = $SYSTEM.Status.GetOneStatusText(sc)
		} ElseIf '$IsObject($Get(reply)) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") || reply.Busy || reply.Fallback {
			Set reason = ..#REASONNOREPLY
		}
	} Catch exception {
		Set reason = exception.DisplayString()
	}
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, old)
	Quit reason
}

/// The request to Decide for a turn case (AD-6): a user turn of owner eval, in a fresh conversation, with no recap. The Input is what
/// Agent.Input renders from an Item of the same fields as a user's turn in the chat, so the model sees the turn as the product sends it.
/// With userTurn the request is the decide request of a user's chat turn (Kind decide, no SessionMode) instead of the turn request. With linked the
/// turn has no SessionMode, so that it opens the session that the case's before turn saved (AD-6) instead of a fresh one. With an owner (the Ref of a session case's
/// session, Story 41.14) only the request's OwnerRef is that session, so that the tools act as it; the Item, and so the Input, stays owner eval.
Method TurnRequest(itemId As %String, text As %String, userTurn As %Boolean = 0, linked As %Boolean = 0, owner As %String = "") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = itemId
	Set item.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set item.Channel = ..#TURNCHANNEL
	Set item.Provenance = "user"
	Set item.Text = text
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = $Select(userTurn: "decide", 1: "turn")
	Set request.Provenance = "user"
	Set request.Input = ##class(OcuTalon.Agent.Input).Render(item)
	Set request.ItemId = itemId
	Set request.Summary = ..FirstLine(text)
	Set request.OwnerRef = $Select(owner '= "": owner, 1: ##class(OcuTalon.Data.Ownership).#EVAL)
	Set request.TraceRef = ..RunRef
	Set request.Channel = ..#TURNCHANNEL
	Set request.ThreadSessionId = ..%SessionId
	If 'userTurn && 'linked Set request.SessionMode = "fresh"
	Quit request
}

/// The first line of the text that is not blank, without the white space at its ends, cut to the 80 characters of a Summary.
ClassMethod FirstLine(text As %String) As %String [ Private ]
{
	Set text = $Translate(text, $Char(13), $Char(10))
	Set line = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $ZStrip($Piece(text, $Char(10), i), "<>WC")
		If line '= "" Quit
	}
	Quit $Extract(line, 1, 80)
}

/// Puts the catalog key and the rows that Checks.Render gives the check rows of the Reply's HostData in the TurnResult. A HostData that is
/// not a JSON object with an array checks, or that renders neither a key nor a row, adds nothing; one that cannot be read is logged.
Method Render(result As OcuTalon.Eval.Msg.TurnResult, hostData As %String) [ Private ]
{
	If hostData = "" Quit
	Try {
		Set data = ##class(%DynamicAbstractObject).%FromJSON(hostData)
		If ($ClassName(data) '= "%Library.DynamicObject") || (data.%GetTypeOf("checks") '= "array") Quit
		Set key = ##class(OcuTalon.Checks.Render).Render(data.checks, .rows)
		Set size = $Select($IsObject($Get(rows)): rows.%Size(), 1: 0)
		If (key = "") && (size = 0) Quit
		Set result.CatalogKey = key
		Set result.CheckRows = $Select(size > 0: rows.%ToJSON(), 1: "")
	} Catch exception {
		$$$LOGWARNING(..#LOGCHECKS_exception.DisplayString())
	}
}

/// Puts the citations, the memories and the learned saves of the Reply's HostData (each an array) in the TurnResult as JSON (Citations, Memories, Learned). A HostData with none of them adds nothing.
Method Cite(result As OcuTalon.Eval.Msg.TurnResult, hostData As %String) [ Private ]
{
	If hostData = "" Quit
	Try {
		Set data = ##class(%DynamicAbstractObject).%FromJSON(hostData)
		If $ClassName(data) '= "%Library.DynamicObject" Quit
		If (data.%GetTypeOf("citations") = "array") && (data.citations.%Size() > 0) Set result.Citations = data.citations.%ToJSON()
		If (data.%GetTypeOf("memories") = "array") && (data.memories.%Size() > 0) Set result.Memories = data.memories.%ToJSON()
		If (data.%GetTypeOf("learned") = "array") && (data.learned.%Size() > 0) Set result.Learned = data.learned.%ToJSON()
	} Catch exception {
		$$$LOGWARNING(..#LOGCHECKS_exception.DisplayString())
	}
}

/// Adds the documents that a documents case declares (Story 19.4, AD-22; a test subclass overrides it, and Test.Docs.Turns calls it on a shadow instance of EvalIn):
/// each file is indexed as a document of the owner eval by OcuTalon.Docs.Ops.AddEval, in this process, within DOCUMENTSWAIT seconds for all of them. documents is the
/// setup record {"refs"} for DocumentsDown. Returns the reason the case is not sent (REASONDOCUMENTS), or "" with the documents ready; on a reason nothing is left behind.
Method DocumentsUp(case As %DynamicObject, folder As %String, Output documents As %DynamicObject) As %String
{
	Set documents = ""
	Set declared = case.%Get("documents")
	If '$IsObject(declared) || 'declared.%IsA("%Library.DynamicArray") || (declared.%Size() = 0) Quit $Replace(..#REASONDOCUMENTS, "{why}", "documents is not a non-empty array")
	Set root = ##class(%File).ParentDirectoryName(##class(%File).NormalizeDirectory(folder))
	Set files = []
	Set iterator = declared.%GetIterator()
	While iterator.%GetNext(, .one) {
		If '$IsObject(one) || 'one.%IsA("%Library.DynamicObject") Quit
		Set name = ..Scalar(one, "name"), file = ..Scalar(one, "file")
		Set path = ##class(%File).NormalizeFilename(file, folder)
		Set type = $Case($ZConvert($Piece(name, ".", $Length(name, ".")), "L"), "md": "markdown", "markdown": "markdown", "txt": "text", : "")
		If ($ZStrip(name, "<>WC") = "") || (file = "") || (type = "") Quit
		If ($Extract(path, 1, $Length(root)) '= root) || '##class(%File).Exists(path) Quit
		Do files.%Push({"name": (name), "path": (path), "type": (type)})
	}
	If files.%Size() '= declared.%Size() Quit $Replace(..#REASONDOCUMENTS, "{why}", "each document needs a name, and a file of the cases' folder that is Markdown or plain text")
	Set documents = {"refs": []}
	Set reason = ""
	Set end = $ZHorolog + ..#DOCUMENTSWAIT
	Set iterator = files.%GetIterator()
	While iterator.%GetNext(, .file) && (reason = "") {
		Set reason = ..AddOne(documents, file, end)
	}
	If reason '= "" {
		Do ..DocumentsDown(documents)
		Set documents = ""
		Quit $Replace(..#REASONDOCUMENTS, "{why}", reason)
	}
	Quit ""
}

/// Indexes one file as a document of the owner eval and adds its Ref to the record's refs. The reason there is not a ready document, or "". The wait is what is left of
/// the case's DOCUMENTSWAIT at the time end ($ZHorolog).
Method AddOne(documents As %DynamicObject, file As %DynamicObject, end As %Integer) As %String [ Private ]
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Set source = ##class(%Stream.FileBinary).%New()
	Set sc = source.LinkToFile(file.path)
	If $$$ISOK(sc) Set sc = bytes.CopyFrom(source)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	Do bytes.Rewind()
	Set wait = end - $ZHorolog
	If wait < 0 Set wait = 0
	Set reason = ##class(OcuTalon.Docs.Ops).AddEval(bytes, file.name, file.type, wait, .ref)
	If reason '= "" Quit file.name_" was not added ("_reason_")"
	Do documents.refs.%Push(ref)
	Quit ""
}

/// Removes every document of the owner eval with its passages (Docs.Ops RemoveEval), the leftovers of an earlier run (DW-900). A removal that fails, or a
/// failure to list them, is one warning. It never throws.
ClassMethod SweepDocuments() [ Private ]
{
	Try {
		Set refs = []
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Document WHERE OwnerRef = ?", ##class(OcuTalon.Docs.Store).#EVALOWNER)
		If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, rs.%Message))
		While rs.%Next() {
			Do refs.%Push(rs.%Get("Ref"))
		}
		Set iterator = refs.%GetIterator()
		While iterator.%GetNext(, .ref) {
			Set sc = ##class(OcuTalon.Docs.Ops).RemoveEval(ref)
			If $$$ISERR(sc) $$$LOGWARNING(..#LOGSWEEP_ref_": "_$SYSTEM.Status.GetOneStatusText(sc))
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGSWEEP_exception.DisplayString())
	}
}

/// Removes the documents of a setup record {"refs"} with their passages (Docs.Ops.RemoveEval, which removes only documents of the owner eval). Every ref is tried;
/// the status is the first error, and it never throws. A document that is already gone is no error.
ClassMethod DocumentsDown(documents As %DynamicObject) As %Status
{
	Set result = $$$OK
	Try {
		If '$IsObject(documents) || '$IsObject(documents.%Get("refs")) Quit
		Set iterator = documents.refs.%GetIterator()
		While iterator.%GetNext(, .ref) {
			Set sc = ##class(OcuTalon.Docs.Ops).RemoveEval(ref)
			If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
		}
	} Catch exception {
		If $$$ISOK(result) Set result = exception.AsStatus()
	}
	Quit result
}

/// Deletes the case's row and its TurnResult.
Method Discard(result As OcuTalon.Eval.Msg.TurnResult, name As %String) [ Private ]
{
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
	If $IsObject(result) && (result.%Id() '= "") Do ##class(OcuTalon.Eval.Msg.TurnResult).%DeleteId(result.%Id())
}

/// The call of a turn case to Decide: synchronous, for at most TURNWAIT seconds. A call that times out answers OK with no response. Private;
/// a test subclass overrides it.
Method Ask(request As OcuTalon.Bridge.Msg.Request, Output reply As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestSync(..#DECIDE, request, .reply, ..#TURNWAIT)
}

/// The send of a turn case's TurnResult to EvalSink, asynchronously, with no answer. Private; a test subclass overrides it.
Method Deliver(result As OcuTalon.Eval.Msg.TurnResult) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#SINK, result)
}

/// The wait before a Busy turn is asked again. Private; a test subclass overrides it.
Method Pause(seconds As %Integer) [ Private ]
{
	Hang seconds
}

/// The text of a string, number or boolean member of a JSON object; "" for a member that is missing, null, an object or an array. EvalSink
/// reads a Decision payload with it too.
ClassMethod Scalar(object As %DynamicObject, key As %String) As %String
{
	Set type = object.%GetTypeOf(key)
	Quit $Select((type = "string") || (type = "number") || (type = "boolean"): object.%Get(key), 1: "")
}

}
