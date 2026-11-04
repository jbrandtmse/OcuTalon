/// The shape of one batch that the simulated partner sends (Story 0.10). Not a message: it has no storage and is never saved.
/// Partner.Orders validates it and Partner.OnProcessInput reads it.
Class OcuTalon.Demo.Orders.Batch Extends %RegisteredObject
{

/// How many orders: a whole number from 1 to Partner's MAXCOUNT.
Property Count As %Integer;

/// How the partner writes each order date: YYYY-MM-DD or MM/DD/YYYY.
Property DateFormat As %String;

/// The date of every order, written YYYY-MM-DD. Empty means the partner's own local date today.
Property OrderDate As %String;

/// The trace reference of the batch: empty, or 22 characters of A-Z, a-z, 0-9, - and _. Every message of the batch carries
/// it as SuperSession (AD-4, AD-26).
Property TraceRef As %String;

}
