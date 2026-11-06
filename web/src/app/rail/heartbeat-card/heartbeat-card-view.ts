/**
 * What the Heartbeat checklist card says and sends (Story 39.5; FR-63 to FR-66, DW-634, DW-781): its fixed strings and the pure rules of the
 * card. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - Every constant of HEARTBEAT_TEXTS is a verbatim run of EXPERIENCE.md's Heartbeat checklist card or a ruled string (web/scripts/ux-strings.test.mjs
 *   gives each its source). A line is composed of runs: the state line joins "Every {interval}, {from} to {to}" (or "Every {interval}" for all
 *   day) and "Next check-in {time}" with the separator. The saved line, the refusals and the checklist's sample are the server's own text; the
 *   page holds a copy only of the two unavailable reasons (DW-634), which web/scripts/heartbeat-card-view.test.mjs pins against OcuTalon.Web.Api.
 * - Times come in through a function, as the page's times do (pageWhen, the browser's zone), and a cost through formatCost; `from` and `to`
 *   are shown as stored, in the instance zone.
 * - lastLine shows the newer of the last check-in and the last skip. A check-in reads "Last check-in {time}" and, for an outcome the card
 *   knows, the outcome, the cost when there is one and the trace; a fallback reads "Couldn't decide: {plain reason}". An outcome that the
 *   card does not know, or none yet, gives the time alone. A skip reads "Skipped at {time}: {reason}"; a reason that the card does not know,
 *   or a backoff with no readable end, gives no line. No text says that all is well (AD-28): an ignore is "Stayed quiet".
 * - todayLine is empty at 0 check-ins and has a singular form for 1.
 * - cooldownUntil is the later of LastRunNowAt plus RUN_NOW_SECONDS and the server's availableAt; unavailable(store) is the cap, then the
 *   missing key, from the store's status conditions, as the banners read them.
 * - saveBody sends all day as both hours empty. failureOf says where a failed call shows: bad_checklist, bad_hours, bad_interval and bad_on
 *   beside their field, anything else under the button, with the error body's message ("" when there is none) and availableAt.
 */
import type { HeartbeatPut, HeartbeatState, HeartbeatToday } from '../../api/heartbeat-types';
import type { LiveStore } from '../../live/live-store';

/** The card's fixed texts. */
export const HEARTBEAT_TEXTS = {
  off: 'Off. Turn it on to have OcuTalon look at your list every 30 minutes.',
  every: 'Every {interval}',
  everyHours: 'Every {interval}, {from} to {to}',
  next: 'Next check-in {time}',
  last: 'Last check-in {time}',
  stayedQuiet: 'Stayed quiet',
  toldNow: 'Told you now',
  digest: 'Saved for the digest',
  offered: 'Offered an action',
  couldntDecide: "Couldn't decide: {reason}",
  skipped: 'Skipped at {time}:',
  skip: {
    empty: 'your checklist is empty.',
    hours: 'outside your active hours.',
    unchanged: 'nothing has changed since the last quiet check-in.',
    cap: "today's cost limit has been reached.",
    nokey: 'no model key is set.',
    backoff: 'waiting after a failed check-in, until {time}.',
  },
  today: 'Today: {n} check-ins, {cost}',
  todayOne: 'Today: 1 check-in, {cost}',
  help: 'Write what OcuTalon should look for, one item per line. With an empty list, OcuTalon makes no model call. It looks at most once per interval, and only when something has changed.',
  run: 'Run the heartbeat now',
  cooldown: 'You can run it again at {time}.',
  unavailableCap: "Today's cost limit has been reached.",
  unavailableNoKey: 'No model key is set.',
  demoNote: "On the online demo the heartbeat is off until you turn it on, and each check-in counts toward the demo's daily cost cap.",
  edit: 'Edit',
  save: 'Save',
  on: 'On',
  interval: 'Interval',
  activeHours: 'Active hours',
  from: 'From',
  to: 'To',
  allDay: 'All day',
  checklist: 'Checklist',
  intervals: { '30': '30 minutes', '60': '1 hour', '120': '2 hours', '240': '4 hours', '480': '8 hours', '1440': '24 hours' },
} as const;

/** The id of the rail heading that the card is named by. */
export const HEARTBEAT_HEADING_ID = 'rail-heading-heartbeat';

/** The seconds between two run-nows (OcuTalon.Checks.Beat RUNNOWSECONDS): the cooldown of the button. */
export const RUN_NOW_SECONDS = 120;

/** The skip reasons that Checks records (OcuTalon.Checks.Beat SKIPEMPTY, SKIPHOURS, SKIPUNCHANGED, SKIPCAP, SKIPNOKEY, SKIPBACKOFF). */
export const SKIP_REASONS = ['empty', 'hours', 'unchanged', 'cap', 'nokey', 'backoff'] as const;

/** One interval of the Interval select: its minutes and its name. */
export interface IntervalOption {
  minutes: number;
  name: string;
}

/** The intervals the card offers (OcuTalon.Checks.Beat INTERVALS), shortest first. */
export const INTERVALS: readonly IntervalOption[] = [30, 60, 120, 240, 480, 1440].map((minutes) => ({
  minutes,
  name: HEARTBEAT_TEXTS.intervals[String(minutes) as keyof typeof HEARTBEAT_TEXTS.intervals],
}));

/** The times of the From and To selects: every quarter hour of the day, 00:00 to 23:45. */
export const QUARTER_HOURS: readonly string[] = Array.from({ length: 96 }, (_unused, i) => {
  const hours = String(Math.floor(i / 4)).padStart(2, '0');
  const minutes = String((i % 4) * 15).padStart(2, '0');
  return `${hours}:${minutes}`;
});

/** The separator of the card's lines: the chat's own (CHAT_TEXTS.separator), which web/scripts/heartbeat-card-view.test.mjs pins. */
export const SEPARATOR = ' \u00b7 ';

/** The values the view reuses from the page's other modules, bound to the clock's now: the page's time, the cost and the plain fallback reason. */
export interface HeartbeatFormat {
  when(iso: string): string;
  cost(amount: number | undefined): string;
  reason(reason: string | undefined): string;
}

/** The last line of the card: the parts of a check-in, which the card joins with the separator, with the trace address last; or one skip line. */
export interface LastLine {
  kind: 'checkin' | 'skip' | 'none';
  parts: string[];
  traceUrl: string;
}

/** The form of the Edit disclosure. */
export interface HeartbeatForm {
  on: boolean;
  interval: number;
  allDay: boolean;
  from: string;
  to: string;
  checklist: string;
}

/** Where a failed call shows, its error code, its message ("" when the answer carried none) and, for a 409, when it can be tried again. */
export interface HeartbeatFailure {
  where: 'checklist' | 'hours' | 'interval' | 'on' | 'save';
  code: string;
  message: string;
  availableAt: string;
}

/** The template with each {name} replaced in one pass, so that a value that holds a placeholder is not filled in again. */
function fill(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');
}

/** The name of an interval in minutes, or "" for one that the card does not offer. */
export function intervalName(minutes: number | undefined): string {
  return INTERVALS.find((one) => one.minutes === minutes)?.name ?? '';
}

/** The state line: the off line, or "Every {interval}, {from} to {to}, then the separator and Next check-in {time}" without the hours part for all day and without the last part when no check-in is due. */
export function stateLine(state: HeartbeatState, when: (iso: string) => string): string {
  if (state.on !== true) {
    return HEARTBEAT_TEXTS.off;
  }
  const interval = intervalName(state.interval);
  if (interval === '') {
    return '';
  }
  const from = state.from ?? '';
  const to = state.to ?? '';
  const every = from !== '' && to !== '' ? fill(HEARTBEAT_TEXTS.everyHours, { interval, from, to }) : fill(HEARTBEAT_TEXTS.every, { interval });
  const next = when(state.nextDueAt ?? '');
  return next === '' ? every : `${every}${SEPARATOR}${fill(HEARTBEAT_TEXTS.next, { time: next })}`;
}

/** The text of an outcome of the last check-in, or "" for one that the card does not know. */
function outcomeText(state: HeartbeatState, format: HeartbeatFormat): string {
  if (state.lastFallback === true) {
    return fill(HEARTBEAT_TEXTS.couldntDecide, { reason: format.reason(state.lastFallbackReason) });
  }
  switch (state.lastOutcome) {
    case 'ignore':
      return HEARTBEAT_TEXTS.stayedQuiet;
    case 'tellnow':
      return HEARTBEAT_TEXTS.toldNow;
    case 'digest':
      return HEARTBEAT_TEXTS.digest;
    case 'act':
      return HEARTBEAT_TEXTS.offered;
    default:
      return '';
  }
}

/** The skip line for the state's last skip, or "" for a reason the card does not know (or a backoff with no readable end). */
function skipText(state: HeartbeatState, format: HeartbeatFormat): string {
  const reason = state.lastSkipReason ?? '';
  if (!Object.hasOwn(HEARTBEAT_TEXTS.skip, reason)) {
    return '';
  }
  const text = HEARTBEAT_TEXTS.skip[reason as keyof typeof HEARTBEAT_TEXTS.skip];
  const until = reason === 'backoff' ? format.when(state.backoffUntil ?? '') : '';
  if (reason === 'backoff' && until === '') {
    return '';
  }
  return `${fill(HEARTBEAT_TEXTS.skipped, { time: format.when(state.lastSkipAt ?? '') })} ${fill(text, { time: until })}`;
}

/** The last line: the newer of the last check-in and the last skip (a check-in when they are the same instant); none when neither has a readable time. */
export function lastLine(state: HeartbeatState, format: HeartbeatFormat): LastLine {
  const beat = format.when(state.lastBeatAt ?? '') === '' ? '' : (state.lastBeatAt ?? '');
  const skip = format.when(state.lastSkipAt ?? '') === '' ? '' : (state.lastSkipAt ?? '');
  const none: LastLine = { kind: 'none', parts: [], traceUrl: '' };
  if (beat !== '' && (skip === '' || Date.parse(beat) >= Date.parse(skip))) {
    const time = fill(HEARTBEAT_TEXTS.last, { time: format.when(beat) });
    const outcome = outcomeText(state, format);
    if (outcome === '') {
      return { kind: 'checkin', parts: [time], traceUrl: '' };
    }
    const parts = [time, outcome];
    if (typeof state.lastCostUSD === 'number') {
      parts.push(format.cost(state.lastCostUSD));
    }
    return { kind: 'checkin', parts, traceUrl: state.traceUrl ?? '' };
  }
  if (skip !== '') {
    const text = skipText(state, format);
    return text === '' ? none : { kind: 'skip', parts: [text], traceUrl: '' };
  }
  return none;
}

/** The Today line: "" at 0 check-ins, "Today: 1 check-in, {cost}", else "Today: {n} check-ins, {cost}". */
export function todayLine(today: HeartbeatToday | undefined, cost: (amount: number) => string): string {
  const checkIns = today?.checkIns ?? 0;
  if (!(checkIns >= 1)) {
    return '';
  }
  const values = { n: String(checkIns), cost: cost(today?.costUSD ?? 0) };
  return fill(checkIns === 1 ? HEARTBEAT_TEXTS.todayOne : HEARTBEAT_TEXTS.today, values);
}

/** An instant as the UTC form that the server stores: YYYY-MM-DDThh:mm:ssZ. */
function isoOf(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** When the button may be pressed again: the later of LastRunNowAt plus RUN_NOW_SECONDS and availableAt; "" when neither is a readable time. */
export function cooldownUntil(state: HeartbeatState | undefined, availableAt: string): string {
  const ends: number[] = [];
  const ran = Date.parse(state?.lastRunNowAt ?? '');
  if (!Number.isNaN(ran)) {
    ends.push(ran + RUN_NOW_SECONDS * 1000);
  }
  const given = Date.parse(availableAt);
  if (!Number.isNaN(given)) {
    ends.push(given);
  }
  return ends.length === 0 ? '' : isoOf(Math.max(...ends));
}

/** Why the button cannot be pressed: the daily cap (dailyCap active), else the missing model key (noModelKey active), else "". */
export function unavailable(store: Pick<LiveStore, 'status'> | undefined): 'cap' | 'nokey' | '' {
  const status = store?.status;
  if (status?.['dailyCap']?.active === true) {
    return 'cap';
  }
  return status?.['noModelKey']?.active === true ? 'nokey' : '';
}

/** The body of the PUT for the form: all day is both hours empty. */
export function saveBody(form: HeartbeatForm): HeartbeatPut {
  return { on: form.on, interval: form.interval, from: form.allDay ? '' : form.from, to: form.allDay ? '' : form.to, checklist: form.checklist };
}

const FIELD_OF_CODE: Readonly<Record<string, HeartbeatFailure['where']>> = {
  bad_checklist: 'checklist',
  bad_hours: 'hours',
  bad_interval: 'interval',
  bad_on: 'on',
};

/** The place, code, message and availableAt of a failed call, from the error of the call: an error answer is `{"error":{"code","message"},"availableAt"?}` in the error's `error`. */
export function failureOf(error: unknown): HeartbeatFailure {
  const answer = (error as { error?: { error?: { code?: unknown; message?: unknown } | null; availableAt?: unknown } | null } | null)?.error;
  const body = answer?.error;
  const code = typeof body?.code === 'string' ? body.code : '';
  return {
    where: Object.hasOwn(FIELD_OF_CODE, code) ? (FIELD_OF_CODE[code] ?? 'save') : 'save',
    code,
    message: typeof body?.message === 'string' ? body.message : '',
    availableAt: typeof answer?.availableAt === 'string' ? answer.availableAt : '',
  };
}
