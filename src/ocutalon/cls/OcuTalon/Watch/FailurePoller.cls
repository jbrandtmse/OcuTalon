/// FailurePoller, the service that picks up the new failures of the watched productions (AD-15). It is an Ens.InboundAdapter service that runs every
/// CallInterval seconds (3 in the production), and it is the only writer of OcuTalon.Data.WatchMark. Each run, for every production that a watch row
/// (BackgroundCheck of Kind production) names, once however many sessions watch it:
///   - starts the reading where OcuTalon.Watch.Mark.Start says (the mark's MarkAt less the overlap, and no earlier than the earliest watch's
///     CreatedAt), reads through the one private seam Read (OcuTalon.Watch.Reader.Failures, the only class that enters the production's
///     namespace), and drops the failures that the mark's Seen set already holds and those beyond MAXFAILURES;
///   - scopes each new failure to the session whose TraceRef is its SuperSession (on any install, whether or not that session watches the
///     production), else to instance (AD-4), and sends IncidentManager one FailureBatch per scope, each its own trace session whose SuperSession
///     is the scope session's TraceRef (empty for instance; AD-26);
///   - then saves the mark. A send cannot share a transaction with the save, so a crash between the two re-sends that poll's failures once and never
///     skips one. A run with nothing new sends nothing and saves nothing.
/// A production that the reader does not read (unreadable, or not its namespace's own production) keeps its mark. Nothing that decides "new" lives in
/// memory (AD-5). The service only reads: it never changes a production and never relies on its alerts. It logs only Type 3 warnings, one per
/// poll of a production whose read or send threw (an unreadable production is not an error and logs nothing), and OnProcessInput always returns OK.
Class OcuTalon.Watch.FailurePoller Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

/// The configuration item that receives the batches.
Parameter TARGET = "IncidentManager";

/// The scope of the failures that no session's TraceRef tags.
Parameter INSTANCE = "instance";

Parameter LOGPOLL = "FailurePoller could not poll the failures of ";

Parameter LOGWATCHES = "FailurePoller could not read the watches: ";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Try {
		Set watched = ..Watched()
		Set iterator = watched.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Try {
				Do ..Poll(entry.namespace, entry.production, entry.created)
			} Catch exception {
				$$$LOGWARNING(..#LOGPOLL_entry.production_" in "_entry.namespace_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGWATCHES_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// The distinct watched productions: a dynamic array of {"namespace", "production", "created"}, created being the earliest CreatedAt of the
/// production's watch rows ("" when none has one), in the order of the namespace and the production.
ClassMethod Watched() As %DynamicArray
{
	Set watched = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, Production, CreatedAt FROM OcuTalon_Data.BackgroundCheck WHERE Kind = 'production' ORDER BY Namespace, Production, ID")
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The watches could not be read: "_rs.%Message))
	Set last = ""
	While rs.%Next() {
		Set key = rs.%GetData(1)_$Char(0)_rs.%GetData(2)
		If key '= last {
			If $IsObject($Get(entry)) Do watched.%Push(entry)
			Set entry = {"namespace": (rs.%GetData(1)), "production": (rs.%GetData(2)), "created": ""}
			Set last = key
		}
		Set created = rs.%GetData(3)
		If (created '= "") && ((entry.created = "") || (entry.created ] created)) Set entry.created = created
	}
	If $IsObject($Get(entry)) Do watched.%Push(entry)
	Quit watched
}

/// One production's poll: the reading, the batches and the mark (see the class description). An error is the caller's warning, and leaves the
/// mark as it was.
Method Poll(namespace As %String, production As %String, created As %String) [ Private ]
{
	Set polledAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set mark = ##class(OcuTalon.Data.WatchMark).NamespaceProductionIndexOpen(namespace, production)
	Set markAt = $Select($IsObject(mark): mark.MarkAt, 1: "")
	Set seen = $Select($IsObject(mark): mark.Seen, 1: "")
	Set from = ##class(OcuTalon.Watch.Mark).Start(markAt, created, polledAt)
	Set limit = ##class(OcuTalon.Watch.Mark).#MAXFAILURES + $Select(seen = "": 0, 1: $Length(seen, ","))
	If ..Read(namespace, production, from, limit, .rows) '= "read" Quit
	Set fresh = ##class(OcuTalon.Watch.Mark).Fresh(rows, seen)
	If fresh.%Size() = 0 Quit
	Set iterator = fresh.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set super = failure.superSession
		Set scope = ..#INSTANCE
		If super '= "" {
			Set session = ##class(OcuTalon.Data.Session).TraceRefIndexOpen(super)
			If $IsObject(session) Set scope = session.Ref
		}
		If '$Data(batch(scope)) {
			Set batch(scope) = ##class(OcuTalon.Watch.Msg.FailureBatch).%New()
			Set batch(scope).Namespace = namespace
			Set batch(scope).Production = production
			Set batch(scope).OwnerRef = scope
			Set batch(scope).PolledAt = polledAt
			Set trace(scope) = $Select(scope = ..#INSTANCE: "", 1: super)
			Set order($Increment(order)) = scope
		}
		Set item = ##class(OcuTalon.Watch.Msg.Failure).%New()
		Set item.Kind = failure.kind
		Set item.HeaderId = failure.headerId
		Set item.SessionId = failure.sessionId
		Set item.ItemName = failure.item
		Set item.SourceName = failure.source
		Set item.BodyClass = failure.bodyClass
		Set item.ErrorText = ##class(OcuTalon.Watch.ErrorText).Sentence(failure.errorText)
		Set item.FailedAt = ##class(OcuTalon.Watch.Mark).FailedAt(failure.at)
		Set item.LogId = failure.logId
		Do batch(scope).Failures.Insert(item)
	}
	For i = 1:1:order {
		Set scope = order(i)
		Set ..%SessionId = ""
		Set ..%SuperSession = trace(scope)
		$$$ThrowOnError(..SendRequestAsync(..#TARGET, batch(scope)))
	}
	Do ##class(OcuTalon.Watch.Mark).Next(markAt, seen, rows, fresh, .nextAt, .nextSeen)
	If '$IsObject(mark) {
		Set mark = ##class(OcuTalon.Data.WatchMark).%New()
		Set mark.Namespace = namespace
		Set mark.Production = production
	}
	Set mark.MarkAt = nextAt
	Set mark.Seen = nextSeen
	$$$ThrowOnError(mark.%Save())
}

/// The failures of the production from the stamp on, at most limit: OcuTalon.Watch.Reader.Failures, its outcome (read, unreadable or not_current)
/// and its rows. A seam for the tests.
Method Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray) As %String [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).Failures(namespace, production, from, limit, .rows)
}

}
