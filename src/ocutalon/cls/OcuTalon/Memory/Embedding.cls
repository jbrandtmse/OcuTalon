/// The embedding endpoint of OcuTalon's memory (AD-21): an %Embedding.Interface class, so the SQL function EMBEDDING and an embedding column
/// (a %Library.Embedding property whose MODEL is the configuration row OcuTalonMemory) compute their vectors here. Every call is computed by the Python
/// package fastembed in a worker of OcuTalon.Memory.Embedder (AD-6), so this class holds no Python and no %SYS.Python reference and may be called
/// from inside an AI Hub callback. The vector is AllMiniLM-L6-v2, 384 DOUBLE values, equal within 1e-6 to AI Hub's FastEmbed vector for the same text.
/// The configuration row is {"modelName":"sentence-transformers/all-MiniLM-L6-v2","dimensions":384}; no other model or dimension is accepted.
/// Embedding throws the failure of the work (a missing model or package, a worker error, a timeout) and Embed returns it as a status.
Class OcuTalon.Memory.Embedding Extends %Embedding.Interface
{

/// The configuration row's name and description, which the Memory install step writes.
Parameter CONFIGNAME = "OcuTalonMemory";

Parameter CONFIGDESCRIPTION = "OcuTalon memory embeddings";

/// 1 when the configuration names AllMiniLM-L6-v2 and, if it names a dimension, 384; else 0 and errorMsg says which setting is wrong.
ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean
{
	Set model = ##class(OcuTalon.Memory.Embedder).#MODEL
	Set dimensions = ##class(OcuTalon.Memory.Embedder).#DIMENSIONS
	If config.%Get("modelName") '= model {
		Set errorMsg = "'modelName' must be " _ model
		Quit 0
	}
	If config.%IsDefined("dimensions") && (config.%Get("dimensions") '= dimensions) {
		Set errorMsg = "'dimensions' must be " _ dimensions
		Quit 0
	}
	Quit 1
}

/// The vector of the input (text, or a dynamic object that is embedded as its JSON text) for the configuration (a JSON text). Throws on a failure.
ClassMethod Embedding(input, configuration) As %Vector
{
	Set config = {}.%FromJSON(configuration)
	If '..IsValidConfig(config, .message) {
		$$$ThrowStatus($SYSTEM.Status.Error(5001, "Invalid configuration: " _ message))
	}
	Set text = $Select($IsObject(input): input.%ToJSON(), 1: input)
	Set sc = ..Embed(text, .vector)
	If $SYSTEM.Status.IsError(sc) {
		$$$ThrowStatus(sc)
	}
	Quit vector
}

/// Embeds the text in a worker and returns the vector in vector (a $VECTOR of 384 DOUBLE values) and the worker's $JOB in job, or the error status
/// of the work.
ClassMethod Embed(text As %String, Output vector As %Vector, Output job As %Integer) As %Status
{
	Set vector = "", job = ""
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("Embed", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result, text, ##class(OcuTalon.Memory.Embedder).ModelFolder())
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set job = $Get(result("job"))
	Set values = $ZStrip($Get(result("vector")), "*W", "[]")
	Set vector = $VOP("fromstring", values, "double", ",", 3)
	If '$IsVector(vector) || ($VOP("length", vector) '= ##class(OcuTalon.Memory.Embedder).#DIMENSIONS) {
		Set vector = ""
		Quit $SYSTEM.Status.Error(5001, "The embedding has " _ $Length(values, ",") _ " values, not " _ ##class(OcuTalon.Memory.Embedder).#DIMENSIONS)
	}
	Quit sc
}

}
