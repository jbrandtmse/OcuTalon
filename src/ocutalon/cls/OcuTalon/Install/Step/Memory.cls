/// The Memory area's install step (AD-21, AD-23). Run() is idempotent and does three things, in order:
///   - the WorkMgr category OcuTalon.Memory.Embedder (created or set to the declared 2 active workers and 1 default worker; Config.WorkQueues lives
///     in %SYS), which must exist before anything queues an embedding;
///   - the %Embedding.Config row OcuTalonMemory (class OcuTalon.Memory.Embedding, VectorLength 384), inserted or updated;
///   - the model folder (OcuTalon.Memory.Embedder ModelFolder(), or the folder passed in): when it already holds the model nothing is downloaded,
///     which is always so on the image; when it does not, the model is downloaded once, in a worker, with the image build's snapshot_download call.
///     A download that cannot run (no network, or fastembed or huggingface_hub not installed, as on the FR-57 image) is a warning that carries the
///     underlying error's own text, never a failure, so the install completes and a later install tries again.
/// EnsureCategory is the pattern that other areas' worker categories reuse (Story 19.6).
Class OcuTalon.Install.Step.Memory Extends OcuTalon.Install.Step
{

/// The step. folder is the model folder; "" names the rule's folder (OcuTalon.Memory.Embedder ModelFolder()).
ClassMethod Run(folder As %String = "") As %Status
{
	Set sc = ..EnsureCategory(##class(OcuTalon.Memory.Embedder).#CATEGORY, ##class(OcuTalon.Memory.Embedder).#MAXACTIVEWORKERS, ##class(OcuTalon.Memory.Embedder).#DEFAULTWORKERS)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set sc = ..EnsureConfig()
	If $SYSTEM.Status.IsError(sc) Quit sc
	If folder = "" Set folder = ##class(OcuTalon.Memory.Embedder).ModelFolder()
	Do ..EnsureModel(folder)
	Quit $SYSTEM.Status.OK()
}

/// Creates the WorkMgr category, or sets an existing one to the declared values. Config.WorkQueues is in %SYS, so the work is done there and the
/// caller's namespace is back when it returns.
ClassMethod EnsureCategory(name As %String, maxActiveWorkers As %Integer, defaultWorkers As %Integer) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("MaxActiveWorkers") = maxActiveWorkers
	Set properties("DefaultWorkers") = defaultWorkers
	If ##class(Config.WorkQueues).Exists(name) Quit ##class(Config.WorkQueues).Modify(name, .properties)
	Quit ##class(Config.WorkQueues).Create(name, .properties)
}

/// Inserts or updates the %Embedding.Config row OcuTalonMemory in the current namespace.
ClassMethod EnsureConfig() As %Status
{
	Set configuration = {"modelName": (##class(OcuTalon.Memory.Embedder).#MODEL), "dimensions": (##class(OcuTalon.Memory.Embedder).#DIMENSIONS)}.%ToJSON()
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("INSERT OR UPDATE INTO %Embedding.Config (Name, Configuration, EmbeddingClass, VectorLength, Description) VALUES (?, ?, ?, ?, ?)", 1)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set result = statement.%Execute(##class(OcuTalon.Memory.Embedding).#CONFIGNAME, configuration, "OcuTalon.Memory.Embedding", ##class(OcuTalon.Memory.Embedder).#DIMENSIONS, ##class(OcuTalon.Memory.Embedding).#CONFIGDESCRIPTION)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The embedding configuration " _ ##class(OcuTalon.Memory.Embedding).#CONFIGNAME _ " could not be saved: " _ result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// Leaves the model in the folder: nothing when it is there, otherwise one download in a worker. A failure is a warning (Warn) with the error text.
/// Returns 1 when a download was attempted, 0 when the folder already held the model.
ClassMethod EnsureModel(folder As %String) As %Boolean
{
	If ##class(OcuTalon.Memory.Embedder).HasModel(folder) Quit 0
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("Download", ##class(OcuTalon.Memory.Embedder).#DOWNLOADTIMEOUT, .result, folder)
	If $SYSTEM.Status.IsError(sc) {
		Do ..Warn($SYSTEM.Status.GetErrorText(sc))
	} ElseIf '##class(OcuTalon.Memory.Embedder).HasModel(folder) {
		Do ..Warn("The download left no model in " _ folder)
	}
	Quit 1
}

}
