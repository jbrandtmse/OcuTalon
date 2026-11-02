/// Test.Fix.ExecutorProbe with a wait of 30 seconds (test only; Story 7.4), for the tests that must not depend on the speed of the host: a run waits for its copies
/// from its ResentAt, and a test that hands the wait to another job or stops the waiter ends as soon as its runs are done, so the longer window costs it nothing, while the
/// probe's own three seconds are for the tests that sit the whole wait out. Everything else is the probe's, the lock WAITLOCK included. It is no item of any production.
Class OcuTalon.Test.Fix.ExecutorProbeLong Extends OcuTalon.Test.Fix.ExecutorProbe
{

Parameter WAITSECONDS = 30;

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
