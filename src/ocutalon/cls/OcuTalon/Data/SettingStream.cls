/// The stream of a SettingSnapshot's settings (Story 36.1): a global character stream that is not compressed. %Stream.GlobalCharacter compresses what it stores,
/// and a scan of the globals (Test.Core.SecretHandoff Leaks) could not then find a hash, or any text, in it. It holds no state of its own.
Class OcuTalon.Data.SettingStream Extends %Stream.GlobalCharacter
{

Parameter COMPRESS = 0;

}
