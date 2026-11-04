/// The messages that the test feed sends to one item (Story 9.9): Sender sends each message of Messages to Target, each in a session of its own, with
/// TraceRef as the SuperSession of every message. It has no storage and is never saved.
Class OcuTalon.Test.Eval.Feed.Batch Extends %RegisteredObject
{

/// The item that takes each message.
Property Target As %String;

/// The trace reference of the batch: 22 characters of A-Z, a-z, 0-9, - and _.
Property TraceRef As %String;

/// The messages, in the order they are sent.
Property Messages As list Of Ens.Request;

}
