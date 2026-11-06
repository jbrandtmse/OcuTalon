/**
 * What the Persona card says and sends (Story 40.4; FR-67, FR-68, FR-70, UX-DR117): its fixed strings, the presets, and the pure rules of
 * the card. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - Every string is EXPERIENCE.md's (Later Steps, Personality, the Persona card), word for word, but for the two all-clear sentences of
 *   the Language and "Your own words" help texts, which U-278 fixed in epics.md (Story 40.4). The saved line and every refusal are the
 *   server's own `message`; the page holds no copy of them.
 * - The Language help is the UX help, one space, then `languageAllClear`. The "Your own words" help is `customAllClear` alone. Neither
 *   holds a phrase of the reply guard's BANNED or RESERVED lists (OcuTalon.Checks.ReplyGuard), which web/scripts/persona-card-view.test.mjs
 *   pins against the class itself.
 * - `PRESETS` are the UX table's six presets in its order, with the names and descriptions the card shows. `optionsFor(customOffered)`
 *   leaves "Your own words" out on the online demo.
 * - `saveBody` sends the language only for the Another language preset and the custom text only for Your own words; every other value is "".
 * - `failureOf` says where a failed save shows: `bad_language` beside the Language field, `bad_custom` beside the text area, anything else
 *   under Save. Its message is the error body's `error.message`, or "" when there is none, for which the component shows the busy notice.
 */

/** The card's fixed texts. */
export const PERSONA_TEXTS = {
  intro: 'Choose how OcuTalon words its chat replies and the reasons for its decisions. What OcuTalon may do, and what needs your approval, never changes.',
  change: 'Change',
  save: 'Save',
  language: 'Language',
  languageHelp: 'Name a language, such as Spanish or Portuguese (Brazil). Notices, cards and buttons stay in English.',
  languageAllClear:
    "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. In another language, the model is only told not to say so.",
  customAllClear:
    "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. If this persona writes in another language, the model is only told not to say so.",
  customLabel: 'Your own words',
  counter: '{n} of 1,000 characters',
  pending: 'OcuTalon suggested a change. It waits for your answer in Approval requests.',
  demoNote: 'On the online demo you can choose a preset or a language. Your choice lasts for this visit.',
} as const;

/** One preset of the card: its id (AD-7), the name on the card and its description. */
export interface PersonaPreset {
  id: string;
  name: string;
  description: string;
}

/** The six presets in the UX table's order. */
export const PRESETS: readonly PersonaPreset[] = [
  { id: 'professional', name: 'Professional (default)', description: 'Calm, short and plain.' },
  { id: 'starship', name: 'Starship computer', description: 'Crisp status reports, formal and brief.' },
  { id: 'pirate', name: 'Pirate', description: 'Sailing words and a good-humoured tone; the facts stay exact.' },
  { id: 'kindfriend', name: 'Kind friend', description: 'Warm, patient and encouraging.' },
  { id: 'language', name: 'Another language', description: 'Replies and reasons in the language you name.' },
  { id: 'custom', name: 'Your own words', description: 'Describe the tone, style and preferences you want.' },
];

/** The id of the rail heading the radio group is named by, and of the Approval requests heading that the pending link falls back to. */
export const PERSONA_HEADING_ID = 'rail-heading-persona';
export const APPROVALS_HEADING_ID = 'rail-heading-approvals';

/** The preset with the id, or undefined for an id the card does not know. */
export function presetOf(id: string): PersonaPreset | undefined {
  return PRESETS.find((one) => one.id === id);
}

/** The presets the card offers: all six on a local install, five on the online demo. */
export function optionsFor(customOffered: boolean): readonly PersonaPreset[] {
  return customOffered ? PRESETS : PRESETS.filter((one) => one.id !== 'custom');
}

/** The help text of the Language field: the UX help, one space, then the all-clear sentence. */
export function languageHelpText(): string {
  return `${PERSONA_TEXTS.languageHelp} ${PERSONA_TEXTS.languageAllClear}`;
}

/** The text area's counter for its value: UTF-16 units, which is what IRIS `$Length` counts (an emoji is 2). */
export function counterText(text: string): string {
  return PERSONA_TEXTS.counter.replace('{n}', String(text.length));
}

/** The body of the PUT for the chosen preset and the field values: only the values that the preset uses are sent. */
export function saveBody(preset: string, language: string, custom: string): { preset: string; language: string; custom: string } {
  return { preset, language: preset === 'language' ? language : '', custom: preset === 'custom' ? custom : '' };
}

/** Where a failed save shows, and its message ("" when the answer carried none). */
export interface PersonaFailure {
  where: 'language' | 'custom' | 'save';
  message: string;
}

/** The place and message of a failed save, from the error of the call: an error answer is `{"error":{"code","message"}}` in the error's `error`. */
export function failureOf(error: unknown): PersonaFailure {
  const body = (error as { error?: { error?: { code?: unknown; message?: unknown } | null } | null } | null)?.error?.error;
  const message = typeof body?.message === 'string' ? body.message : '';
  const code = body?.code;
  return { where: code === 'bad_language' ? 'language' : code === 'bad_custom' ? 'custom' : 'save', message };
}
