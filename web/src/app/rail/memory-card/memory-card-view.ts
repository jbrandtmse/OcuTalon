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
 * - `nextTab` is the tab one step on (or back) of the four tabs, wrapping at both ends.
 *
 * Story 41.13 adds the tabs Pinned and All memories (FR-73, FR-74, AD-21, AD-28): their strings are EXPERIENCE.md's (the Memory card) or the
 * Contest Planner's rulings (the empty texts, the search, the failures, the demo rule).
 * - `sourceLabel` is the chip of a memory: Told, or Learned for any source that is not told.
 * - `usedText` is the Pinned figure: the number the server gave, grouped as en-US, never computed here.
 * - `memoryName` is the accessible name of a row's button: the word, then the first MEMORY_OPENING characters of the text, with an ellipsis
 *   when the text is longer.
 * - `listMore` is the line under a list that shows only the newest of more, or "" when the list shows them all.
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
  pinned: 'Pinned',
  memories: 'All memories',
  pinnedIntro: 'Pinned facts are read at the start of each conversation.',
  used: '{used} of 1,000 tokens (estimated).',
  pinnedEmpty: 'Nothing pinned yet. Pin a memory from All memories.',
  memoriesEmpty: 'No memories yet. Say "Remember that ..." in the chat.',
  noMatch: 'No memories match.',
  searchLabel: 'Search your memories',
  search: 'Search',
  told: 'Told',
  learned: 'Learned',
  pin: 'Pin',
  unpin: 'Unpin',
  listMore: 'Showing the newest {shown} of {total}. Search to find the others.',
  memoryQuestion: 'Forget this memory? OcuTalon will stop using it.',
  pinFailed: "Couldn't pin it. Nothing was changed.",
  unpinFailed: "Couldn't unpin it. Nothing was changed.",
  overCap: 'That would go over the 1,000-token limit. Unpin something first.',
  searchBusy: 'Search is busy right now. Try again in a moment.',
  demoRule:
    "On the online demo, your memories and pins belong to this visit: they're deleted when you sign out or the demo resets. Each search counts as one of your messages.",
} as const;

/** The words of the stored answers. */
export const ANSWER_WORDS: Readonly<Record<string, string>> = {
  noise: 'This was noise',
  approved: 'Approved',
  rejected: 'Rejected',
};

/** The id of the rail heading that the section takes (status-rail.ts), which names the tab list and takes focus after a confirmed Forget. */
export const MEMORY_HEADING_ID = 'rail-heading-memory';

/** The card's four tabs, in order. */
export type MemoryTab = 'notes' | 'answers' | 'pinned' | 'memories';

/** The tabs, in order. */
export const MEMORY_TABS: readonly MemoryTab[] = ['notes', 'answers', 'pinned', 'memories'];

/** How many characters of a memory's text a button's accessible name quotes (the length of a note's opening). */
export const MEMORY_OPENING = 80;

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

/** The tab one step on (step 1, the default) or one step back (step -1); the first follows the last and the last precedes the first. */
export function nextTab(tab: MemoryTab, step: 1 | -1 = 1): MemoryTab {
  const count = MEMORY_TABS.length;
  const at = MEMORY_TABS.indexOf(tab);
  return MEMORY_TABS[(at + step + count) % count] ?? 'notes';
}

/** The chip of a memory: Told for a told one, Learned for any other. */
export function sourceLabel(source: string): string {
  return source === 'told' ? MEMORY_TEXTS.told : MEMORY_TEXTS.learned;
}

/** The Pinned figure for the tokens the server counted: "{used} of 1,000 tokens (estimated).", the number grouped as en-US. */
export function usedText(used: number): string {
  return MEMORY_TEXTS.used.replace('{used}', () => new Intl.NumberFormat('en-US').format(used));
}

/** The accessible name of a memory row's button: the word, then the text's first MEMORY_OPENING characters, and an ellipsis when the text is longer. */
export function memoryName(word: string, text: string): string {
  const characters = Array.from(text);
  const opening = characters.length > MEMORY_OPENING ? `${characters.slice(0, MEMORY_OPENING).join('')}\u2026` : text;
  return `${word} ${opening}`;
}

/** The line under a list that shows the newest `shown` of `total` memories; "" when the list holds them all. */
export function listMore(shown: number, total: number): string {
  return total > shown ? MEMORY_TEXTS.listMore.replace('{shown}', () => String(shown)).replace('{total}', () => String(total)) : '';
}
