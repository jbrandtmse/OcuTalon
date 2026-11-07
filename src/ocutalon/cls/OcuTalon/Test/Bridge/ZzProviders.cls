/// A provider table of its own, for Test.Bridge.Providers (Story 17.3): the table of OcuTalon.Bridge.Providers with key variables that no process sets
/// and with the flags that the resolution tests need. Providers.Rows reads the Table of the class it is called on, so this class replaces the table.
Class OcuTalon.Test.Bridge.ZzProviders Extends OcuTalon.Bridge.Providers
{

XData Table [ MimeType = application/json ]
{
[
 {"provider": "anthropic", "defaultModel": "claude-haiku-5-5", "models": ["claude-haiku-5-5", "claude-sonnet-5-5"], "keyVariable": "OCUTALON_ZZ17_ANTHROPIC", "supported": true},
 {"provider": "openai", "defaultModel": "gpt-5.4-mini", "models": ["gpt-5.4-mini", "gpt-5.4"], "keyVariable": "OCUTALON_ZZ17_OPENAI", "supported": true},
 {"provider": "gemini", "defaultModel": "gemini-3.1-flash-lite", "models": ["gemini-3.1-flash-lite", "gemini-3.1-pro-preview"], "keyVariable": "OCUTALON_ZZ17_GEMINI", "supported": false},
 {"provider": "bedrock", "defaultModel": "us.anthropic.claude-haiku-5-5", "models": ["us.anthropic.claude-haiku-5-5", "us.anthropic.claude-sonnet-5-5"], "keyVariable": "OCUTALON_ZZ17_BEDROCK", "supported": true}
]
}

}
