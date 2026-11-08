Include Ensemble

/// The local documents' knowledge base (AD-5, AD-6, AD-21, Story 19.4; Lane A): the table OcuTalonKB.Docs (AI Hub's vector-store table, with its columns
/// exactly) and the attach of AI Hub's knowledge-base tool "documents" to the Chat agent. This is the only class that names %AI.RAG.VectorStore.IRIS and the
/// only one that holds the DDL, and it is the only writer of the rows of OcuTalonKB.Docs besides the calls of OcuTalon.Docs.Ops into it (DocumentOps, and the
/// evaluation path AddEval and RemoveEval in the caller's process).
///   - EnsureTable makes OcuTalonKB.Docs and OcuTalonKB.Docs_Config when one is missing, each with DEFAULTGLOBAL ^OcuTalonP.KBDocs and ^OcuTalonP.KBDocsConfig
///     on the CREATE TABLE line (kb-ddl), so every global resolves to OCUTALON_PRIVATE (AD-3, AD-5). It is called before any AI Hub Build().
///   - Write embeds passages through OcuTalon.Memory.Embedding.Embed (the worker) and inserts them by SQL: one row for each passage, id <Ref>:<chunk_index>,
///     text the passage, source the document's Ref and metadata {source, chunk_index, document, section}. AI Hub's AddDocument is never used: a repeated
///     add replaces every chunk of a source, and its chunker does not bound or section passages. A row is deleted by its id before it is inserted, so a batch
///     that is written twice (a message redelivered after a restart) leaves one row for each passage.
///   - Remove deletes every row of a source. Rows written, updated or deleted by SQL show in the very next search.
///   - Attach builds the knowledge base for a Chat agent (Docs.Embedding, the vector store, the knowledge base named Tools.Names DOCUMENTS with TopK 5) and
///     adds it to the agent's tool manager. An instance of this class is the holder of the three AI Hub objects: AI Hub frees a knowledge base when its object
///     closes, so the Chat agent keeps the holder. On the online demo nothing is attached (Story 19.5), and a failure is one redacted warning, no holder, and the
///     agent still builds.
/// A model-facing text is the DESCRIPTION of the knowledge base.
Class OcuTalon.Docs.Store Extends %RegisteredObject
{

/// The table of the local install's documents.
Parameter TABLE = "OcuTalonKB.Docs";

/// The private globals' suffix: ^OcuTalonP.KB<SUFFIX> and ^OcuTalonP.KB<SUFFIX>Config.
Parameter SUFFIX = "Docs";

/// The results of one search (AI Hub's TopK).
Parameter TOPK = 5;

/// What the model reads about the tool (model-facing text).
Parameter DESCRIPTION = "Searches the documents added to OcuTalon, such as runbooks, and returns the passages that best match the query, each with its document and section.";

Parameter LOGATTACH = "Docs.Store could not attach the documents tool: ";

/// The AI Hub embedding, vector store and knowledge base of an attach.
Property Embedding As OcuTalon.Docs.Embedding;

Property VectorStore As %AI.RAG.VectorStore.IRIS;

Property KnowledgeBase As %AI.RAG.KnowledgeBase;

/// Makes the table and its _Config table when one is missing; else nothing. A table made by another process meanwhile is not an error. Each statement is
/// written out whole, with DEFAULTGLOBAL and the private prefix on its own line (the rule kb-ddl of docker/tests/test-class-rules.sh).
ClassMethod EnsureTable() As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		If ..Exists(..#TABLE) && ..Exists(..#TABLE_"_Config") Quit
		If '..Exists(..#TABLE) {
			Set sc = ..Create(..#TABLE, "CREATE TABLE OcuTalonKB.Docs (id VARCHAR(64) NOT NULL, text VARCHAR(32000) NOT NULL, vector VECTOR(DOUBLE, 384) NOT NULL, metadata VARCHAR(32000), source VARCHAR(512), PRIMARY KEY (id)) WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KBDocs'")
		}
		If $SYSTEM.Status.IsOK(sc) && '..Exists(..#TABLE_"_Config") {
			Set sc = ..Create(..#TABLE_"_Config", "CREATE TABLE OcuTalonKB.Docs_Config (model_name VARCHAR(255) NOT NULL, dimensions INTEGER NOT NULL) WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KBDocsConfig'")
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

/// Embeds the passages from to from + count - 1 (0-based chunk_index, fewer at the end) of passages (a dynamic array of {text, section}) and inserts them
/// as rows of the document ref (name is the document's name without extension; see DocumentName). Throws the first failure.
ClassMethod Write(ref As %String, name As %String, passages As %DynamicArray, from As %Integer, count As %Integer) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set last = from + count - 1
		If last > (passages.%Size() - 1) Set last = passages.%Size() - 1
		For n = from:1:last {
			Set passage = passages.%Get(n)
			Set section = passage.section
			Set input = $Select(section '= "": section _ $Char(10) _ passage.text, 1: passage.text)
			Set sc = ##class(OcuTalon.Memory.Embedding).Embed(input, .vector)
			If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
			Set metadata = {"source": (ref), "chunk_index": (n), "document": (name), "section": (section)}
			Set cleared = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ ..#TABLE _ " WHERE id = ?", ref _ ":" _ n)
			If cleared.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "DELETE FROM " _ ..#TABLE _ ": " _ cleared.%Message))
			Set result = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO " _ ..#TABLE _ " (id, text, vector, metadata, source) VALUES (?, ?, TO_VECTOR(?, DOUBLE, 384), ?, ?)", ref _ ":" _ n, passage.text, ..ToText(vector), metadata.%ToJSON(), ref)
			If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "INSERT INTO " _ ..#TABLE _ ": " _ result.%Message))
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Deletes every row of the document ref (its source).
ClassMethod Remove(ref As %String) As %Status
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ ..#TABLE _ " WHERE source = ?", ref)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "DELETE FROM " _ ..#TABLE _ ": " _ result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// The number of rows of the document ref (every row of the table when ref is empty), or -1 when the table cannot be read (so a count of 0 always means no row).
ClassMethod Count(ref As %String = "") As %Integer
{
	If ref = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ ..#TABLE)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ ..#TABLE _ " WHERE source = ?", ref)
	}
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Builds the documents knowledge base and adds it to the agent's tool manager; holder is the instance that keeps the AI Hub objects alive, or "" when
/// nothing was attached (the online demo, or a failure, which logs one redacted warning). The agent builds either way.
ClassMethod Attach(agent As %AI.Agent, Output holder As OcuTalon.Docs.Store) As %Status
{
	Set holder = ""
	Set sc = $SYSTEM.Status.OK()
	Try {
		If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 Quit
		Set sc = ..EnsureTable()
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set built = ..%New()
		Set built.Embedding = ##class(OcuTalon.Docs.Embedding).%New()
		Set sc = built.Embedding.Register()
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set store = ##class(%AI.RAG.VectorStore.IRIS).%New()
		Set store.Schema = $Piece(..#TABLE, ".", 1)
		Set store.TableName = ..#TABLE
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
		Set sc = base.AddToAgent(agent)
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set holder = built
	} Catch exception {
		Set holder = ""
		$$$LOGWARNING(..#LOGATTACH_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
	Quit $SYSTEM.Status.OK()
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
