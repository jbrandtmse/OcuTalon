Include Ensemble

/// The knowledge-base tables of the documents (AD-3, AD-5, AD-6, AD-21, AD-33, Stories 19.4 and 19.5; Lane A): AI Hub's vector-store tables, with its columns
/// exactly, and the knowledge base of "documents" that a turn searches. This is the only class that names %AI.RAG.VectorStore.IRIS and the only one that holds
/// the DDL, and it is the only writer of the rows of the tables besides the calls of OcuTalon.Docs.Ops into it (DocumentOps, and the evaluation path AddEval and
/// RemoveEval in the caller's process).
///   - One owner rule (OwnerFor, TableFor), used by every caller: the owner of a document is the session on the online demo, instance on a local install and
///     eval for an evaluation run. The table of instance is OcuTalonKB.Docs (suffix Docs), of eval OcuTalonKB.Eval (suffix Eval) and of a session
///     OcuTalonKB.S<id> (suffix S<id>), <id> being the id of the OcuTalon.Data.Session row whose Ref is the SessionRef exactly. A table name whose suffix is not
///     Docs, Eval or S and digits is refused before any SQL (SuffixOf).
///   - EnsureTable makes a table and its _Config table when one is missing, each with DEFAULTGLOBAL ^OcuTalonP.KB<suffix> and ^OcuTalonP.KB<suffix>Config on the
///     CREATE TABLE line (kb-ddl), so every global resolves to OCUTALON_PRIVATE (AD-3, AD-5). It is called before any AI Hub Build(), and only by DocumentOps
///     (its start on a local install, a session's first AddDocument) and by AddEval: no code builds a vector store over a table that does not exist, so a table that
///     is gone is never opened or made again by a search (AD-21).
///   - Write embeds passages through OcuTalon.Memory.Embedding.Embed (the worker) and inserts them by SQL: one row for each passage, id <Ref>:<chunk_index>,
///     text the passage, source the document's Ref and metadata {source, chunk_index, document, section}. AI Hub's AddDocument is never used: a repeated
///     add replaces every chunk of a source, and its chunker does not bound or section passages. A row is deleted by its id before it is inserted, so a batch
///     that is written twice (a message redelivered after a restart) leaves one row for each passage.
///   - Remove deletes every row of a source. Rows written, updated or deleted by SQL show in the very next search.
///   - Drop drops a table and its _Config table (DROP TABLE IF EXISTS), which leaves no class and no global; the caller holds the owner's lock.
///   - Knowledge builds the knowledge base of a table that exists (Docs.Embedding, the vector store, the knowledge base named Tools.Names DOCUMENTS with TopK 5)
///     in a new instance of this class, the holder of the three AI Hub objects: AI Hub frees a knowledge base when its object closes, so whoever uses it keeps
///     the holder. The holder answers AddToManager, as Bridge.Ext.TurnTools asks of the tools it gives. A table that does not exist gives no holder, and a failure
///     is one redacted warning and no holder.
///   - The owner's lock ^OcuTalon.Docs(<owner>) orders the writers against a drop: LockOwner takes it shared for a table's writers and for Knowledge, exclusive
///     for the drop, and waits at most LOCKWAIT seconds.
/// A model-facing text is the DESCRIPTION of the knowledge base.
Class OcuTalon.Docs.Store Extends %RegisteredObject
{

/// The table of the local install's documents (the owner instance).
Parameter TABLE = "OcuTalonKB.Docs";

/// The private globals' suffix of that table: ^OcuTalonP.KB<SUFFIX> and ^OcuTalonP.KB<SUFFIX>Config.
Parameter SUFFIX = "Docs";

/// The owner of every document of a local install (AD-4).
Parameter OWNER = "instance";

/// The owner, and the adder, of the documents of an evaluation run (AD-22): not an instance, not a session, so that no route lists them and no person's turn
/// searches them.
Parameter EVALOWNER = "eval";

/// The table of the evaluation documents and the suffix of its globals.
Parameter EVALTABLE = "OcuTalonKB.Eval";

Parameter EVALSUFFIX = "Eval";

/// The schema of every knowledge-base table.
Parameter SCHEMA = "OcuTalonKB";

/// How long the owner's lock is waited for, in seconds.
Parameter LOCKWAIT = 5;

/// The results of one search (AI Hub's TopK).
Parameter TOPK = 5;

/// What the model reads about the tool (model-facing text).
Parameter DESCRIPTION = "Searches the documents added to OcuTalon, such as runbooks, and returns the passages that best match the query, each with its document and section.";

Parameter LOGATTACH = "Docs.Store could not build the documents tool: ";

/// The AI Hub embedding, vector store and knowledge base of an attach.
Property Embedding As OcuTalon.Docs.Embedding;

Property VectorStore As %AI.RAG.VectorStore.IRIS;

Property KnowledgeBase As %AI.RAG.KnowledgeBase;

/// 1 when the instance is the online demo (the public setting onlineDemo): the one read of it for the documents.
ClassMethod OnlineDemo() As %Boolean
{
	Quit ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1
}

/// The owner of the documents that the session adds or searches: the session itself on the online demo, instance on a local install (AD-4).
ClassMethod OwnerFor(sessionRef As %String) As %String
{
	Quit $Select(..OnlineDemo(): sessionRef, 1: ..#OWNER)
}

/// The knowledge-base table of the owner, or "" when the owner has none: OcuTalonKB.Docs for instance, OcuTalonKB.Eval for eval, and for a session
/// OcuTalonKB.S<id>, <id> being the id of the Session row whose Ref is the ownerRef exactly (the Ref index finds a Ref in any case), so a Ref that no row has,
/// or that differs in case, has no table. suffix is the table's suffix ("" with no table). It reads and makes nothing.
ClassMethod TableFor(ownerRef As %String, Output suffix As %String) As %String
{
	Set suffix = ""
	If ownerRef = "" Quit ""
	If ownerRef = ..#OWNER {
		Set suffix = ..#SUFFIX
		Quit ..#TABLE
	}
	If ownerRef = ..#EVALOWNER {
		Set suffix = ..#EVALSUFFIX
		Quit ..#EVALTABLE
	}
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ownerRef)
	If '$IsObject(row) || (row.Ref '= ownerRef) Quit ""
	Set suffix = "S" _ row.%Id()
	Quit ..#SCHEMA _ "." _ suffix
}

/// The suffix of the table (Docs, Eval or S and digits), or "" when the name is not that of a knowledge-base table: every method that builds SQL from a table
/// name asks first.
ClassMethod SuffixOf(table As %String) As %String
{
	If ($Length(table, ".") '= 2) || ($Piece(table, ".", 1) '= ..#SCHEMA) Quit ""
	Set suffix = $Piece(table, ".", 2)
	If (suffix = ..#SUFFIX) || (suffix = ..#EVALSUFFIX) Quit suffix
	If ($Extract(suffix) = "S") && ($Extract(suffix, 2, *) ?1.N) Quit suffix
	Quit ""
}

/// The owner whose lock orders the writers of the table: instance for Docs, eval for Eval, and for S<id> the Ref of the Session row (the suffix itself when the
/// row is gone). It is "" for a name that is no table.
ClassMethod OwnerOf(table As %String) As %String
{
	Set suffix = ..SuffixOf(table)
	If suffix = "" Quit ""
	If suffix = ..#SUFFIX Quit ..#OWNER
	If suffix = ..#EVALSUFFIX Quit ..#EVALOWNER
	Set row = ##class(OcuTalon.Data.Session).%OpenId($Extract(suffix, 2, *))
	Quit $Select($IsObject(row): row.Ref, 1: suffix)
}

/// Takes the owner's lock ^OcuTalon.Docs(owner): shared for the writers of its table and for Knowledge, exclusive for the drop of its documents, waiting at most
/// LOCKWAIT seconds. An error status when it could not be taken (nothing is held then); release it with UnlockOwner and the same exclusive.
ClassMethod LockOwner(owner As %String, exclusive As %Boolean = 0) As %Status
{
	If exclusive {
		Lock +^OcuTalon.Docs(owner):..#LOCKWAIT
	} Else {
		Lock +^OcuTalon.Docs(owner)#"S":..#LOCKWAIT
	}
	If '$Test Quit $SYSTEM.Status.Error(5001, "The documents of " _ owner _ " are busy: the lock was not free within " _ ..#LOCKWAIT _ " seconds")
	Quit $SYSTEM.Status.OK()
}

ClassMethod UnlockOwner(owner As %String, exclusive As %Boolean = 0)
{
	If exclusive {
		Lock -^OcuTalon.Docs(owner)
	} Else {
		Lock -^OcuTalon.Docs(owner)#"S"
	}
}

/// Marks the owner's documents as being dropped (on 1) or not (on 0): a writer that holds the owner's shared lock stops between two passages while the mark is
/// set (Write, Draining), so the drop's exclusive lock waits for a passage and not for a batch. The mark lives in ^IRIS.Temp, which a restart empties.
ClassMethod Drain(owner As %String, on As %Boolean)
{
	If on {
		Set ^IRIS.Temp.OcuTalonDocsDrop(owner) = 1
	} Else {
		Kill ^IRIS.Temp.OcuTalonDocsDrop(owner)
	}
}

/// 1 while the owner's documents are being dropped (Drain).
ClassMethod Draining(owner As %String) As %Boolean
{
	Quit $Data(^IRIS.Temp.OcuTalonDocsDrop(owner)) > 0
}

/// Makes the table and its _Config table when one is missing; else nothing. A table made by another process meanwhile is not an error. A name that is no
/// knowledge-base table (SuffixOf) is an error, before any SQL. Each statement is written out whole, with DEFAULTGLOBAL and the private prefix on its own
/// line (the rule kb-ddl of docker/tests/test-class-rules.sh). The session path of DocumentOps calls it under the owner's lock (LockOwner).
ClassMethod EnsureTable(table As %String = {..#TABLE}) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set suffix = ..SuffixOf(table)
		If suffix = "" {
			Set sc = $SYSTEM.Status.Error(5001, "The name " _ table _ " is not that of a knowledge-base table")
			Quit
		}
		If ..Exists(table) && ..Exists(table_"_Config") Quit
		If '..Exists(table) {
			Set sc = ..Create(table, "CREATE TABLE " _ table _ " (id VARCHAR(64) NOT NULL, text VARCHAR(32000) NOT NULL, vector VECTOR(DOUBLE, 384) NOT NULL, metadata VARCHAR(32000), source VARCHAR(512), PRIMARY KEY (id)) WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KB" _ suffix _ "'")
		}
		If $SYSTEM.Status.IsOK(sc) && '..Exists(table_"_Config") {
			Set sc = ..Create(table_"_Config", "CREATE TABLE " _ table _ "_Config (model_name VARCHAR(255) NOT NULL, dimensions INTEGER NOT NULL) WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KB" _ suffix _ "Config'")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// 1 when the SQL table exists.
ClassMethod Exists(table As %String) As %Boolean [ Private ]
{
	Quit ''$SYSTEM.SQL.Schema.TableExists(table)
}

/// Runs the CREATE TABLE statement of the table; an error is not one when the table exists after it (a race with another job).
ClassMethod Create(table As %String, statement As %String) As %Status [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, statement)
	If (result.%SQLCODE < 0) && '..Exists(table) Quit $SYSTEM.Status.Error(5001, "Creating " _ table _ ": " _ result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// Drops the _Config table and then the table (DROP TABLE IF EXISTS, so a table that is not there is no error), which deletes their classes and their globals
/// in OCUTALON_PRIVATE and leaves nothing behind (measured in Story 19.5, Task 0). A name that is no knowledge-base table is an error, before any SQL. The
/// caller holds the owner's exclusive lock (LockOwner).
ClassMethod Drop(table As %String) As %Status
{
	If ..SuffixOf(table) = "" Quit $SYSTEM.Status.Error(5001, "The name " _ table _ " is not that of a knowledge-base table, so nothing was dropped")
	For name = table _ "_Config", table {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE IF EXISTS " _ name)
		If result.%SQLCODE < 0 Quit
	}
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "DROP TABLE " _ name _ ": " _ result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// Embeds the passages from to from + count - 1 (0-based chunk_index, fewer at the end) of passages (a dynamic array of {text, section}) and inserts them
/// as rows of the document ref (name is the document's name without extension; see DocumentName) into the table. Throws the first failure. With an owner, it
/// stops between two passages, with OK, when the owner's documents are being dropped (Draining): the caller finds the document gone.
ClassMethod Write(ref As %String, name As %String, passages As %DynamicArray, from As %Integer, count As %Integer, table As %String = {..#TABLE}, owner As %String = "") As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		If ..SuffixOf(table) = "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The name " _ table _ " is not that of a knowledge-base table"))
		Set last = from + count - 1
		If last > (passages.%Size() - 1) Set last = passages.%Size() - 1
		For n = from:1:last {
			If (owner '= "") && ..Draining(owner) Quit
			Set passage = passages.%Get(n)
			Set section = passage.section
			Set input = $Select(section '= "": section _ $Char(10) _ passage.text, 1: passage.text)
			Set sc = ##class(OcuTalon.Memory.Embedding).Embed(input, .vector)
			If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
			Set metadata = {"source": (ref), "chunk_index": (n), "document": (name), "section": (section)}
			Set cleared = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE id = ?", ref _ ":" _ n)
			If cleared.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "DELETE FROM " _ table _ ": " _ cleared.%Message))
			Set result = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO " _ table _ " (id, text, vector, metadata, source) VALUES (?, ?, TO_VECTOR(?, DOUBLE, 384), ?, ?)", ref _ ":" _ n, passage.text, ..ToText(vector), metadata.%ToJSON(), ref)
			If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "INSERT INTO " _ table _ ": " _ result.%Message))
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Deletes every row of the document ref (its source) from the table. A table that does not exist holds no row of it, so that is not an error, and nothing is
/// made.
ClassMethod Remove(ref As %String, table As %String = {..#TABLE}) As %Status
{
	If ..SuffixOf(table) = "" Quit $SYSTEM.Status.Error(5001, "The name " _ table _ " is not that of a knowledge-base table")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE source = ?", ref)
	If (result.%SQLCODE < 0) && '..Missing(result) Quit $SYSTEM.Status.Error(5001, "DELETE FROM " _ table _ ": " _ result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// 1 when the failed statement failed because the table is not there (SQLCODE -30).
ClassMethod Missing(result As %SQL.StatementResult) As %Boolean [ Private ]
{
	Quit result.%SQLCODE = -30
}

/// The number of rows of the document ref (every row of the table when ref is empty), or -1 when the table cannot be read (so a count of 0 always means no row).
ClassMethod Count(ref As %String = "", table As %String = {..#TABLE}) As %Integer
{
	If ..SuffixOf(table) = "" Quit -1
	If ref = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table _ " WHERE source = ?", ref)
	}
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Builds the documents knowledge base over the table, under the owner's shared lock, and returns its holder (the instance that keeps the AI Hub objects
/// alive), or "" when there is none: the table or its _Config table does not exist (it is never made here), the name is no knowledge-base table, the lock was
/// not free in time, or a build failed, which logs one redacted warning. The status is OK in every case: a turn goes on without the tool.
ClassMethod Knowledge(table As %String, Output holder As OcuTalon.Docs.Store) As %Status
{
	Set holder = ""
	Set locked = 0
	Try {
		If ..SuffixOf(table) = "" Quit
		Set owner = ..OwnerOf(table)
		Set sc = ..LockOwner(owner)
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set locked = 1
		If '..Exists(table) || '..Exists(table_"_Config") Quit
		Set built = ..%New()
		Set built.Embedding = ##class(OcuTalon.Docs.Embedding).%New()
		Set sc = built.Embedding.Register()
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set store = ##class(%AI.RAG.VectorStore.IRIS).%New()
		Set store.Schema = $Piece(table, ".", 1)
		Set store.TableName = table
		Set store.Dimensions = ##class(OcuTalon.Docs.Embedding).#DIMENSIONS
		Set store.ModelName = ##class(OcuTalon.Docs.Embedding).#MODELNAME
		Set built.VectorStore = store
		Set sc = store.Build()
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set base = ##class(%AI.RAG.KnowledgeBase).%New(##class(OcuTalon.Tools.Names).#DOCUMENTS, ..#DESCRIPTION)
		Set base.TopK = ..#TOPK
		Set built.KnowledgeBase = base
		Set sc = base.Build(built.Embedding, store)
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set holder = built
	} Catch exception {
		Set holder = ""
		$$$LOGWARNING(..#LOGATTACH_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
	If locked Do ..UnlockOwner(owner)
	Quit $SYSTEM.Status.OK()
}

/// Adds the knowledge base to the tool manager, as Bridge.Ext.TurnTools asks of the objects it gives. The holder is built (Knowledge).
Method AddToManager(manager As %AI.ToolMgr) As %Status
{
	Quit ..KnowledgeBase.AddToManager(manager)
}

/// The document's name for a citation and a result: the file's name without a final .md, .markdown, .txt, .pdf or .docx, in any case.
ClassMethod DocumentName(name As %String) As %String
{
	Set lower = $ZConvert(name, "L")
	For extension = ".markdown", ".docx", ".txt", ".pdf", ".md" {
		Set length = $Length(extension)
		If ($Length(name) > length) && ($Extract(lower, *-length+1, *) = extension) Quit
		Set extension = ""
	}
	If extension = "" Quit name
	Quit $Extract(name, 1, *-$Length(extension))
}

/// The values of a vector as comma-separated text, which TO_VECTOR(text, DOUBLE, 384) reads (the twin of OcuTalon.Memory.ToText, which is Private).
ClassMethod ToText(vector As %Vector) As %String [ Private ]
{
	Set text = ""
	For i = 1:1:$VOP("length", vector) {
		Set text = text _ $Select(i > 1: ",", 1: "") _ $VECTOR(vector, i)
	}
	Quit text
}

}
