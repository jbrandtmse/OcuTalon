/**
 * The History page's view model (Story 25.2; FR-53, FR-30; EXPERIENCE: Step 6): the fixed strings of the page, the filters' values, and the pure rules that
 * read and write the address, label the empty and pager texts, and shape an incident row's times and summary. A framework-free module: it imports only
 * types and uses only erasable TypeScript syntax, so Node runs it as it is. The page decides nothing (AD-12): the lists, their pages and their page
 * count are the server's (`GET /v1/history/decisions` and `/incidents`).
 *
 * - HISTORY_TEXTS is the page's own fixed strings. The labels it shares are not copied here: the page reads the outcome labels from CHAT_TEXTS and the
 *   channel labels from USAGE_TEXTS.channels, and `outcomeOptions` and `channelOptions` take them as arguments, as the Usage page passes the agent names.
 * - paramsOf reads the address (a queryParamMap-like) into the state {tab, outcome, channel, day, fallback, page}, dropping every value that the server would not
 *   take; queryOf writes only the values that are set (`tab` only for the Incidents tab, `page` only above 1); isCanonical says whether an address is
 *   already what queryOf would write for it.
 * - emptyText, pageText, incidentTimes, summaryLines and noSummaryText are the texts of the lists.
 */

/** The page's tabs, in order. */
export type HistoryTab = 'decisions' | 'incidents';

/** The tabs, in order. */
export const HISTORY_TABS: readonly HistoryTab[] = ['decisions', 'incidents'];

/** The other tab: with two tabs, either arrow key moves to it. */
export function otherTab(tab: HistoryTab): HistoryTab {
  return tab === 'decisions' ? 'incidents' : 'decisions';
}

/** The values of the Outcome filter, in the order of Msg.Enum OUTCOME. */
export const OUTCOMES: readonly string[] = ['ignore', 'digest', 'tellnow', 'act'];

/** The values of the Channel filter, in the order of Msg.Enum CHANNEL. */
export const CHANNELS: readonly string[] = ['web', 'phone', 'mailbox', 'telegram', 'email', 'webhook', 'slack', 'system', 'heartbeat'];

/** The values of the Fallback filter. */
export const FALLBACKS: readonly string[] = ['yes', 'no'];

/** The highest page the route takes. */
export const MAX_PAGE = 9999;

/** The names of the address's parameters, in the order queryOf writes them. */
export const PARAMS = ['tab', 'outcome', 'channel', 'day', 'fallback', 'page'] as const;

/** The page's own fixed strings. The separator in the title is U+00B7. */
export const HISTORY_TEXTS = {
  title: 'History \u00B7 OcuTalon',
  heading: 'History',
  tabDecisions: 'Decisions',
  tabIncidents: 'Incidents',
  outcome: 'Outcome',
  channel: 'Channel',
  date: 'Date',
  fallback: 'Fallback',
  anyOutcome: 'Any outcome',
  anyChannel: 'Any channel',
  fallbackAll: 'All decisions',
  fallbackOnly: 'Fallback only',
  fallbackNone: 'Without fallback',
  clear: 'Clear filters',
  noticed: 'Noticed {time}',
  closed: 'Closed {time}',
  noSummaryOpen: 'No summary yet. OcuTalon writes one when the incident closes.',
  noSummaryClosed: 'No summary was written for this incident.',
  previous: 'Previous page',
  next: 'Next page',
  pageOf: 'Page {page} of {pages}',
  decisionPages: 'Decision pages',
  incidentPages: 'Incident pages',
  emptyFiltered: 'No decisions match these filters.',
  emptyDecisions: 'No decisions yet.',
  emptyIncidents: 'No incidents yet.',
  error: "Couldn't load your history.",
  retry: 'Retry',
} as const;

/** What the page reads of the address: the router's ParamMap has this shape. */
export interface ParamSource {
  get(name: string): string | null;
}

/** The page's state: the tab, the four filters ("" for one that is not set) and the page. */
export interface HistoryState {
  tab: HistoryTab;
  outcome: string;
  channel: string;
  day: string;
  fallback: string;
  page: number;
}

/** The earliest year of a day the server reads in every zone: IRIS dates start at 1840-12-31 (Data.Time.FromLocal). */
const FIRST_YEAR = 1841;

/** True for a YYYY-MM-DD that names a real calendar date from FIRST_YEAR on. */
export function isDay(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (match === null) {
    return false;
  }
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  return year >= FIRST_YEAR && date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/** A page number: digits with no leading zero, 1 to MAX_PAGE; anything else is 1. */
export function pageOf(value: string | null): number {
  if (value === null || !/^[1-9]\d{0,3}$/.test(value)) {
    return 1;
  }
  return Number(value);
}

/** The state an address holds, every value the server would not take dropped. */
export function paramsOf(source: ParamSource): HistoryState {
  const outcome = source.get('outcome') ?? '';
  const channel = source.get('channel') ?? '';
  const day = source.get('day') ?? '';
  const fallback = source.get('fallback') ?? '';
  return {
    tab: source.get('tab') === 'incidents' ? 'incidents' : 'decisions',
    outcome: OUTCOMES.includes(outcome) ? outcome : '',
    channel: CHANNELS.includes(channel) ? channel : '',
    day: isDay(day) ? day : '',
    fallback: FALLBACKS.includes(fallback) ? fallback : '',
    page: pageOf(source.get('page')),
  };
}

/** The address's parameters for a state: only the values that are set, `tab` only for the Incidents tab and `page` only above 1. */
export function queryOf(state: HistoryState): Record<string, string> {
  const query: Record<string, string> = {};
  if (state.tab === 'incidents') {
    query['tab'] = 'incidents';
  }
  for (const name of ['outcome', 'channel', 'day', 'fallback'] as const) {
    if (state[name] !== '') {
      query[name] = state[name];
    }
  }
  if (state.page > 1) {
    query['page'] = String(state.page);
  }
  return query;
}

/** A query that sets the page's parameters for navigation with merge: a parameter that is not in the state is null, which removes it. */
export function mergeQueryOf(state: HistoryState): Record<string, string | null> {
  const query = queryOf(state);
  const merged: Record<string, string | null> = {};
  for (const name of PARAMS) {
    merged[name] = query[name] ?? null;
  }
  return merged;
}

/** True when the address already holds exactly what queryOf writes for its state: no value that was dropped and none that was spelt another way. */
export function isCanonical(source: ParamSource): boolean {
  const query = queryOf(paramsOf(source));
  return PARAMS.every((name) => (source.get(name) ?? null) === (query[name] ?? null));
}

/** True when any of the four filters is set. */
export function filtered(state: HistoryState): boolean {
  return state.outcome !== '' || state.channel !== '' || state.day !== '' || state.fallback !== '';
}

/** A state with every filter cleared and the page back at 1, on the same tab. */
export function cleared(state: HistoryState): HistoryState {
  return { ...state, outcome: '', channel: '', day: '', fallback: '', page: 1 };
}

/** The options of a select: the value the route takes and the text shown. */
export interface Option {
  value: string;
  label: string;
}

/** The Outcome options: Any outcome, then the four outcomes with the labels given by value (the chip's words). */
export function outcomeOptions(labels: Readonly<Record<string, string>>): Option[] {
  return [{ value: '', label: HISTORY_TEXTS.anyOutcome }, ...OUTCOMES.map((value) => ({ value, label: labels[value] ?? value }))];
}

/** The Channel options: Any channel, then every channel in the enum's order with the labels given by value. */
export function channelOptions(labels: Readonly<Record<string, string>>): Option[] {
  return [{ value: '', label: HISTORY_TEXTS.anyChannel }, ...CHANNELS.map((value) => ({ value, label: labels[value] ?? value }))];
}

/** The Fallback options: all decisions, those with a fallback, those without. */
export function fallbackOptions(): Option[] {
  return [
    { value: '', label: HISTORY_TEXTS.fallbackAll },
    { value: 'yes', label: HISTORY_TEXTS.fallbackOnly },
    { value: 'no', label: HISTORY_TEXTS.fallbackNone },
  ];
}

/** The text with each {name} replaced by its value. */
function fill(template: string, values: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');
}

/** What an empty list says: for the Incidents tab "No incidents yet."; for the Decisions tab "No decisions match these filters." when any filter is set, else "No decisions yet.". */
export function emptyText(state: HistoryState): string {
  if (state.tab === 'incidents') {
    return HISTORY_TEXTS.emptyIncidents;
  }
  return filtered(state) ? HISTORY_TEXTS.emptyFiltered : HISTORY_TEXTS.emptyDecisions;
}

/** "Page 2 of 3". */
export function pageText(page: number, pages: number): string {
  return fill(HISTORY_TEXTS.pageOf, { page: String(page), pages: String(pages) });
}

/** The parts of an incident row's times line: "Noticed {time}" and, once closed, "Closed {time}"; a part whose time cannot be read is left out. `when` formats an ISO time. */
export function incidentTimes(row: { noticedAt: string; closedAt: string }, when: (iso: string) => string): string[] {
  const parts: string[] = [];
  const noticed = row.noticedAt === '' ? '' : when(row.noticedAt);
  if (noticed !== '') {
    parts.push(fill(HISTORY_TEXTS.noticed, { time: noticed }));
  }
  const closed = row.closedAt === '' ? '' : when(row.closedAt);
  if (closed !== '') {
    parts.push(fill(HISTORY_TEXTS.closed, { time: closed }));
  }
  return parts;
}

/** The lines of a stored summary: the text split at its line feeds, with no empty line. */
export function summaryLines(text: string): string[] {
  return text.split('\n').filter((line) => line.trim() !== '');
}

/** What an incident row with no summary says: the closed text for a closed incident, else the text that promises one at the close. */
export function noSummaryText(state: string): string {
  return state === 'closed' ? HISTORY_TEXTS.noSummaryClosed : HISTORY_TEXTS.noSummaryOpen;
}
