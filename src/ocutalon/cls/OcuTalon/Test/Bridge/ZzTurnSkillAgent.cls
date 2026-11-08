/// An agent of the per-request tool tests (Story 19.5) that declares a skill, so that a request cannot take tools of its own: a test fixture, never part of a
/// production.
Class OcuTalon.Test.Bridge.ZzTurnSkillAgent Extends OcuTalon.Test.Bridge.ZzTurnAgent
{

Parameter SKILLS = "%AI.Skills.Planning";

}
