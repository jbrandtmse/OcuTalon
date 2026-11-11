/// The queue test feed's source (Story 23.7): an adapterless service that sends each request it is given to QueueSink, asynchronously, in a session of its own.
Class OcuTalon.Test.Checks.Queue.In Extends Ens.BusinessService
{

/// The item that takes each request.
Parameter TARGET = "QueueSink";

Method OnProcessInput(pInput As Ens.StringRequest, Output pOutput As %RegisteredObject) As %Status
{
	Quit ..SendRequestAsync(..#TARGET, pInput)
}

}
