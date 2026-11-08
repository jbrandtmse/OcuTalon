/// The embedding of the documents' knowledge base (AD-6, AD-21, Story 19.4; Lane A): AI Hub's custom-embedding hook (%AI.RAG.Embedding) over Story 19.2's
/// embedding worker. AI Hub calls EmbedBatch from inside its tool execution when the model searches the documents, to embed the query. EmbedBatch embeds
/// each text through OcuTalon.Memory.Embedding.Embed, which hands the text to the Embedder worker (the only place Python runs, the model read from the
/// image's baked folder, offline), so this class makes no %AI call and runs no Python (it is a callback helper, Test.Bridge.CodeRules). The vectors are
/// the worker's fastembed 0.9.0 AllMiniLM-L6-v2 vectors, within 1.3e-7 of AI Hub's own FastEmbed (Story 19.2's measurement), 384 values each.
/// The passages are embedded with the same call by Docs.Store.Write, so a query and a passage always share one model.
Class OcuTalon.Docs.Embedding Extends %AI.RAG.Embedding
{

/// The number of values of a vector (the model's dimensions; OcuTalon.Memory.Embedder's).
Parameter DIMENSIONS = 384;

/// The model's name, as AI Hub's FastEmbed names it (the name stored in the knowledge base's _Config table).
Parameter MODELNAME = "AllMiniLML6V2";

Method %OnNew() As %Status [ Private ]
{
	Set i%Dimensions = ..#DIMENSIONS
	Set i%ModelName = ..#MODELNAME
	Quit $$$OK
}

/// Embeds each text of texts (a dynamic array of strings) and returns [[384 numbers], ...], one vector for each text, in order. It throws the error
/// status of an embedding that fails, which AI Hub reports as the failed search.
Method EmbedBatch(texts As %DynamicArray) As %DynamicArray
{
	Set result = []
	Set iterator = texts.%GetIterator()
	While iterator.%GetNext(.key, .text) {
		Set sc = ##class(OcuTalon.Memory.Embedding).Embed(text, .vector)
		If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
		Set values = []
		For i = 1:1:$VOP("length", vector) Do values.%Push($VECTOR(vector, i))
		Do result.%Push(values)
	}
	Quit result
}

}
