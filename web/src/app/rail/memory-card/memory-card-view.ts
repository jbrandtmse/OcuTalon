/**
 * What the Memory card says (Story 41.6; FR-71, FR-72, AD-4, AD-28): its fixed strings and the pure rules of its rows. A framework-free
 * module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is. Nothing in it builds a request.
 *
 * - Every string is EXPERIENCE.md's (Later Steps, Personality, the Memory card), the epics' (the day labels) or a string that the Contest
 *   Planner ruled (the empty texts of yesterday and of the answers, the Forget name, the dialog's buttons and failure, the answer words,
 *   the tool note). The note lines are the server's own and the page holds no copy of them.
 * - `answerWord` is the ruled word of a stored answer, or the value as served for any other.
 * - `isToolRow` is true for a row with no channel: only a tool call's answer has none (Data.Precedent).
 * - `metaParts` gives a row's meta parts (when, the channel as the server sends it, the answer word), which the component joins with the
 *   rail's separator; an empty part is left out.
 * - `forgetName` is the accessible name of a row's Forget: "Forget" followed by the row's summary.
 * - `nextTab` is the other of the two tabs.
 */

/** The card's fixed texts. */
export const MEMORY_TEXTS = {
  notes: 'Notes',
  answers: 'Your answers',
  notesIntro: "Built by OcuTalon from today's decisions, incidents, approvals and reminders. No model writes these notes.",
  notesEmpty: 'Nothing recorded yet today.',
  yesterdayEmpty: 'Nothing recorded yesterday.',
  today: 'Today',
  yesterday: 'Yesterday',
  answersIntro: 'OcuTalon looks at these when it decides on similar items. Only your own answers are kept here.',
  answersEmpty: 'No answers yet.',
  forget: 'Forget',
  forgetName: 'Forget {summary}',
  question: 'Forget this answer? OcuTalon will stop using it.',
  cancel: 'Cancel',
  confirm: 'Forget',
  forgetFailed: "Couldn't forget it. Nothing was changed.",
  toolNote: 'OcuTalon keeps this answer but does not use it when it decides.',
} as const;

/** The words of the stored answers. */
export const ANSWER_WORDS: Readonly<Record<string, string>> = {
  noise: 'This was noise',
  approved: 'Approved',
  rejected: 'Rejected',
};

/** The id of the rail heading that the section takes (status-rail.ts), which names the tab list and takes focus after a confirmed Forget. */
export const MEMORY_HEADING_ID = 'rail-heading-memory';

/** The card's two tabs, in order. */
export type MemoryTab = 'notes' | 'answers';

/** The fields of a precedent row that the rules read. */
export interface MemoryRowFields {
  channel: string;
  answer: string;
}

/** The word of an answer: the ruled word for noise, approved and rejected, and the value as served for any other. */
export function answerWord(answer: string): string {
  return Object.hasOwn(ANSWER_WORDS, answer) ? (ANSWER_WORDS[answer] ?? answer) : answer;
}

/** True for a tool call's row: it has no channel. */
export function isToolRow(row: Pick<MemoryRowFields, 'channel'>): boolean {
  return row.channel === '';
}

/** The meta parts of a row, in order: when (already formatted), the channel as served, the answer word. An empty part is left out. */
export function metaParts(row: MemoryRowFields, when: string): string[] {
  return [when, row.channel, answerWord(row.answer)].filter((part) => part !== '');
}

/** The accessible name of a row's Forget button: the visible word, then the row's summary. */
export function forgetName(summary: string): string {
  return MEMORY_TEXTS.forgetName.replace('{summary}', () => summary);
}

/** The other tab. */
export function nextTab(tab: MemoryTab): MemoryTab {
  return tab === 'notes' ? 'answers' : 'notes';
}
