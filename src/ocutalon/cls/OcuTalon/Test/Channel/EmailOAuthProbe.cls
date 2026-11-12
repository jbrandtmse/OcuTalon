/// A subclass of OcuTalon.Channel.Email.OAuth for the tests of Story 21.3, which stands in for the three facts that the product reads from its process: whether it is
/// SettingsOps' production job (InJob), whether the online demo is on (OnlineDemo) and the value of the CI-only environment variable (SwitchOn is IsOn of it). The answers
/// are the process-private ^||OcuTalonEmailOAuthProbe("job"), ("demo") and ("env"); with none set the probe is in the job, off the online demo, with the variable unset.
/// The product never refers to it.
Class OcuTalon.Test.Channel.EmailOAuthProbe Extends OcuTalon.Channel.Email.OAuth
{

ClassMethod InJob() As %Boolean
{
	Quit +$Get(^||OcuTalonEmailOAuthProbe("job"), 1)
}

ClassMethod OnlineDemo() As %Boolean
{
	Quit +$Get(^||OcuTalonEmailOAuthProbe("demo"), 0)
}

ClassMethod SwitchOn() As %Boolean
{
	Quit ..IsOn($Get(^||OcuTalonEmailOAuthProbe("env")))
}

}
