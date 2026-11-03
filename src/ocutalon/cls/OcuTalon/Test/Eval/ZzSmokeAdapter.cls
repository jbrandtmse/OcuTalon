/// The runner's adapter of the thinking-history smoke test (Test.Eval.ThinkingSmoke; Story 30.1, AD-20): the session config of the adapter with the
/// thinking rule forced, extra_params.thinking {"type": "adaptive", "block_binding": {"prefix_mismatch_behavior": "error"}}, so that a provider that
/// binds the thinking blocks to the prefix of the conversation refuses a history whose prefix changed. It applies to every session the adapter makes or
/// opens (a new one, a resumed one and a compaction fork). Nothing else differs from the adapter, and no runner of the product uses it.
Class OcuTalon.Test.Eval.ZzSmokeAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// The composed config (Compose) with extra_params.thinking added.
Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Set sc = ##super(.config)
	If $$$ISERR(sc) Quit sc
	Set extra = config."extra_params"
	If '$IsObject(extra) {
		Set extra = {}
		Do config.%Set("extra_params", extra)
	}
	Do extra.%Set("thinking", {"type": "adaptive", "block_binding": {"prefix_mismatch_behavior": "error"}})
	Quit $$$OK
}

}
