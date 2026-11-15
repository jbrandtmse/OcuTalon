/// The setting change that an incident names as its cause, in the incident payload (Story 23.3; Lane B): the item, the target (Host or Adapter), the setting, the two values (blank for
/// a secret, with credential 1) and when the change was detected. It names no one who made the change.
Class OcuTalon.Live.Payload.Part.SettingChange Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The item whose setting changed.
Property Item As %String(%JSONFIELDNAME = "item", MAXLEN = 256);

/// Host or Adapter.
Property Target As %String(%JSONFIELDNAME = "target", MAXLEN = 32);

/// The setting's name.
Property Setting As %String(%JSONFIELDNAME = "setting", MAXLEN = 256);

/// The value before the change.
Property OldValue As %String(%JSONFIELDNAME = "oldValue", MAXLEN = 2000);

/// The value after the change.
Property NewValue As %String(%JSONFIELDNAME = "newValue", MAXLEN = 2000);

/// 1 when the value is a secret, whose two values are blank.
Property Credential As %Boolean(%JSONFIELDNAME = "credential") [ InitialExpression = 0 ];

/// When the check that saw the change ran, UTC to the second.
Property DetectedAt As %String(%JSONFIELDNAME = "detectedAt", MAXLEN = 20);

}
