/// A test command that only extends the verb class ListReminders, for OcuTalon.Test.Core.CommandsRouting: OcuTalon.Core.CommandsIn
/// matches a verb by its exact class name, so this class is not a verb of its table. It has no Test methods and is never saved;
/// the product never refers to it.
Class OcuTalon.Test.Core.CommandsSubVerb Extends OcuTalon.Msg.Command.ListReminders
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
