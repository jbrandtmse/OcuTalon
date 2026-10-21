/// The Chat agent (AD-6): answers the user's messages in a conversation. Story 1.1 gives it its instructions and toolsets; until then it carries only its model and its mock key.
Class OcuTalon.Agent.Chat Extends %AI.Agent
{

/// The model of the agent (AD-7): Claude Haiku 5.5 is the default.
Parameter MODEL = "claude-haiku-5-5";

/// The key the CI mock reads to pick this agent's scenario (AD-22).
Parameter MOCKKEY = "chat";

}
