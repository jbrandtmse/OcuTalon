/**
 * What the status rail says (Story 2.8, UX-DR51 to UX-DR57): its fixed strings and the view of the live store that the rail
 * renders. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 * Every value it reuses (the page times, the number formats, the reason lines, the chip of an outcome, the separator) comes in
 * through RailFormat, which the component builds from the real modules; the components render what it returns by interpolation only.
 *
 * - railView(store, format) gives the sections in order: Telegram (only when the release includes it), Approval requests,
 *   Background checks, Reminders and Recent decisions. It shows the store as a reload of the page would (the views filter and
 *   sort the store, and the store keeps everything): approvals and reminders that are pending, by raised and due time and then
 *   in store order; every check in store order; the 20 newest attention decisions, newest first.
 * - Each list section carries its count, its visible heading "Background checks (1)" and its spoken heading "Background checks, 1".
 * - While the heartbeat is stalled (the store's heartbeatStalled condition is active, Story 2.10), a check's "Last run {when}" reads
 *   "Last run {when} (late)"; the rest of its meta line is unchanged.
 * - A request of an incident also carries `jump`, its Ref, and `jumpName`, "Show in the chat: Repair and resend 50 orders", which holds the
 *   visible title verbatim (WCAG 2.5.3): its title is a button that takes focus to the request's card in the chat (Story 6.3). A
 *   tool call's request has no card there, so no jump.
 * - Each row carries its key, its title, an optional detail line and its meta parts; a reminder carries its countdown too, and a
 *   decision its chip, fallback flag and reason lines. A row whose payload has a traceUrl carries it, for the trace link that ends
 *   its meta line; a row whose payload has none carries none.
 */
import type { Outcome } from '../chat/outcome-chip';
import type { Countdown } from '../chat/page-time';
import type { LiveStore } from '../live/live-store';
import type { ApprovalPayload, CheckPayload, DecisionPayload, ReminderPayload } from '../live/payloads';

/** Every fixed string of the rail. The quotes of a hint are straight ASCII quotes. */
export const RAIL_TEXTS = {
  telegram: 'Telegram',
  approvals: 'Approval requests',
  checks: 'Background checks',
  reminders: 'Reminders',
  decisions: 'Recent decisions',
  headingVisible: '{label} ({n})',
  headingSpoken: '{label}, {n}',
  emptyApprovals: 'None waiting.',
  emptyChecks: 'Ask OcuTalon to watch a production.',
  emptyChecksDemo: 'Nothing yet. Step 1 of the guide sets up a watch.',
  emptyReminders: 'None pending.',
  emptyDecisions: 'No decisions yet.',
  hintChecks: 'To stop, ask: "Stop watching Orders."',
  hintReminders: 'To cancel, ask: "Cancel my reminder to stretch."',
  repair: 'Repair and resend',
  repairCount: 'Repair and resend {n} {noun}',
  runTool: 'Run {toolName}',
  showInChat: 'Show in the chat: {action}',
  raised: 'Raised {when}',
  expires: 'expires {when}',
  checkTitle: '{name} production',
  checkSchedule: 'Live, plus a check every minute',
  lastRun: 'Last run {when}',
  lastRunLate: 'Last run {when} (late)',
  titleWithCountdown: '{text}{separator}{countdown}',
  telegramNotSetUp: 'Telegram not set up',
  telegramHowTo: 'How to set it up',
} as const;

/** The anchor of the README's Telegram section. */
export const TELEGRAM_ANCHOR = 'telegram';

/** The most decisions that Recent decisions lists. */
export const DECISIONS_SHOWN = 20;

/** The kind of the production check, which the rail names and schedules. */
const PRODUCTION_KIND = 'production';

/** The values the view reuses from the page's other modules. when and countdown are bound to the clock's now. */
export interface RailFormat {
  when(iso: string): string;
  countdown(dueIso: string): Countdown;
  cost(amount: number | undefined): string;
  confidence(confidence: number | undefined): string;
  reasonLines(reasons: string | undefined, fallbackSentence: string | undefined, max: number): string[];
  outcome(outcome: string | undefined, fallback: boolean | undefined): Outcome | undefined;
  fallbackSentence(reason: string | undefined): string | undefined;
  separator: string;
  /** The template of a reminder's due time, with {time}. */
  due: string;
  words: { passed: string; failed: string; notChecked: string };
}

/** The sections of the rail. */
export type SectionId = 'telegram' | 'approvals' | 'checks' | 'reminders' | 'decisions';

/** The kinds of row. */
export type RowKind = 'approval' | 'check' | 'reminder' | 'decision';

/** What a decision row shows besides its title (the item's summary) and meta. */
export interface DecisionRowView {
  chip: Outcome | undefined;
  fallback: boolean;
  /** True when the first reason line is the fallback's sentence. */
  fallbackLine: boolean;
  /** Line 2 of the collapsed row. */
  firstReason: string;
  /** Every reason line, the fallback's sentence first, which replaces line 2 when the row is expanded. */
  reasons: string[];
}

/** One row of a list section. */
export interface RailRow {
  /** Unique across the rail: the section, a colon and the entity's ref. */
  key: string;
  kind: RowKind;
  /** The whole title as plain text; for a reminder with a countdown it ends with the countdown. */
  title: string;
  /** The title without the countdown. */
  lead: string;
  detail?: string;
  /** The parts of the meta line, which the component joins with the separator; empty for no meta line. */
  meta: string[];
  countdown?: Countdown;
  decision?: DecisionRowView;
  /** Where the row's trace link opens, as the payload served it; absent when the payload has none. */
  traceUrl?: string;
  /** The Ref of the approval request whose card the row's title button jumps to; set only for a request of an incident. */
  jump?: string;
  /** The accessible name of that button: "Show in the chat: Repair and resend 50 orders"; it contains the row's visible title with its case and words. */
  jumpName?: string;
}

/** One section of the rail. A list section has a count and a spoken heading; Telegram has neither. */
export interface RailSection {
  id: SectionId;
  label: string;
  count?: number;
  /** The visible heading: "Background checks (1)", or the label alone for Telegram. */
  heading: string;
  /** The spoken heading: "Background checks, 1", or the label alone for Telegram. */
  spoken: string;
  rows: RailRow[];
  /** The text under an empty list; empty for Telegram. */
  empty: string;
  /** The hint under the list; empty when the section has none. */
  hint: string;
}

/** The rail: its sections in order, and whether the Telegram section is among them. */
export interface RailView {
  sections: RailSection[];
  telegramShown: boolean;
}

/** The template with each {name} replaced in one pass, so that a value that holds a placeholder is not filled in again. */
function fill(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');
}

/** The values of a keyed collection, in the order the store keeps them. */
function inStoreOrder<T>(collection: Readonly<Record<string, T>>): T[] {
  return Object.values(collection);
}

/** The items sorted by a text key, ascending or newest (greatest) first; a tie keeps the order the items came in. */
function sortedBy<T>(items: readonly T[], key: (item: T) => string, newestFirst = false): T[] {
  const sign = newestFirst ? -1 : 1;
  return [...items].sort((a, b) => {
    const left = key(a);
    const right = key(b);
    return left < right ? -sign : left > right ? sign : 0;
  });
}

/** The README address with the section's anchor in place of #readme. */
export function readmeSection(readmeUrl: string, anchor: string): string {
  const at = readmeUrl.indexOf('#');
  return `${at < 0 ? readmeUrl : readmeUrl.slice(0, at)}#${anchor}`;
}

/**
 * The title of an approval request: "Repair and resend 50 orders" for a fix with a dry run (the noun by the count), "Repair and
 * resend" without one, and "Run zz_tool" for a tool call.
 */
export function approvalTitle(approval: ApprovalPayload): string {
  if (approval.kind === 'tool_call') {
    return fill(RAIL_TEXTS.runTool, { toolName: approval.toolName ?? '' }).trim();
  }
  const affected = approval.dryRun?.affected;
  if (typeof affected !== 'number') {
    return RAIL_TEXTS.repair;
  }
  const noun = (affected === 1 ? approval.dryRun?.itemNoun?.one : approval.dryRun?.itemNoun?.other) ?? '';
  return fill(RAIL_TEXTS.repairCount, { n: String(affected), noun }).trim();
}

/** The title of a check: "Orders production" for a production check, the display name alone for any other kind. */
export function checkTitle(check: CheckPayload): string {
  const name = check.displayName ?? '';
  return check.kind === PRODUCTION_KIND ? fill(RAIL_TEXTS.checkTitle, { name }) : name;
}

/** The row with the payload's traceUrl, only when the payload has one. */
function withTrace(row: RailRow, traceUrl: string | undefined): RailRow {
  if (traceUrl) {
    row.traceUrl = traceUrl;
  }
  return row;
}

function approvalRow(approval: ApprovalPayload, format: RailFormat): RailRow {
  const meta: string[] = [];
  const raised = format.when(approval.raisedAt ?? '');
  if (raised !== '') {
    meta.push(fill(RAIL_TEXTS.raised, { when: raised }));
  }
  const expires = format.when(approval.expiresAt ?? '');
  if (expires !== '') {
    meta.push(fill(RAIL_TEXTS.expires, { when: expires }));
  }
  const title = approvalTitle(approval);
  const row: RailRow = { key: `approvals:${approval.ref ?? ''}`, kind: 'approval', title, lead: title, meta };
  if ((approval.incidentRef ?? '') !== '' && (approval.ref ?? '') !== '') {
    row.jump = approval.ref;
    row.jumpName = fill(RAIL_TEXTS.showInChat, { action: title });
  }
  return withTrace(row, approval.traceUrl);
}

function checkRow(check: CheckPayload, format: RailFormat, late: boolean): RailRow {
  const meta: string[] = [];
  const when = format.when(check.lastRunAt ?? '');
  if (when !== '') {
    meta.push(fill(late ? RAIL_TEXTS.lastRunLate : RAIL_TEXTS.lastRun, { when }));
    const finding = check.finding ?? '';
    const word = resultWord(check.result, format);
    if (finding !== '') {
      meta.push(finding);
    } else if (word !== '') {
      meta.push(word);
    }
  }
  const title = checkTitle(check);
  const row: RailRow = { key: `checks:${check.ref ?? ''}`, kind: 'check', title, lead: title, meta };
  if (check.kind === PRODUCTION_KIND) {
    row.detail = RAIL_TEXTS.checkSchedule;
  }
  return withTrace(row, check.traceUrl);
}

/** The word of a check's result: Passed, Failed, Not checked for any other result, and none when it has no result. */
function resultWord(result: string | undefined, format: RailFormat): string {
  if (result === undefined || result === '') {
    return '';
  }
  return result === 'passed' ? format.words.passed : result === 'failed' ? format.words.failed : format.words.notChecked;
}

function reminderRow(reminder: ReminderPayload, format: RailFormat): RailRow {
  const text = reminder.text ?? '';
  const row: RailRow = { key: `reminders:${reminder.ref ?? ''}`, kind: 'reminder', title: text, lead: text, meta: [] };
  const due = reminder.dueAt ?? '';
  const countdown = format.countdown(due);
  const when = format.when(due);
  if (countdown.text !== '' && when !== '') {
    row.countdown = countdown;
    row.title = fill(RAIL_TEXTS.titleWithCountdown, { text, separator: format.separator, countdown: countdown.text });
    row.meta = [fill(format.due, { time: when })];
  }
  return withTrace(row, reminder.traceUrl);
}

function decisionRow(decision: DecisionPayload, format: RailFormat): RailRow {
  const fallback = decision.fallback === true;
  const sentence = fallback ? format.fallbackSentence(decision.fallbackReason ?? '') : undefined;
  const meta: string[] = [];
  const when = format.when(decision.recordedAt ?? '');
  if (when !== '') {
    meta.push(when);
  }
  if (!fallback && decision.confidence !== undefined) {
    meta.push(format.confidence(decision.confidence));
  }
  if (decision.costUSD !== undefined) {
    meta.push(format.cost(decision.costUSD));
  }
  const title = decision.itemSummary ?? '';
  return withTrace(
    {
      key: `decisions:${decision.ref ?? ''}`,
      kind: 'decision',
      title,
      lead: title,
      meta,
      decision: {
        chip: format.outcome(decision.outcome, fallback),
        fallback,
        fallbackLine: (sentence ?? '') !== '',
        firstReason: format.reasonLines(decision.reasons, sentence, 1)[0] ?? '',
        reasons: format.reasonLines(decision.reasons, sentence, Number.MAX_SAFE_INTEGER),
      },
    },
    decision.traceUrl,
  );
}

/** A list section of the rail. */
function listSection(id: SectionId, label: string, rows: RailRow[], empty: string, hint: string): RailSection {
  const values = { label, n: String(rows.length) };
  return {
    id,
    label,
    count: rows.length,
    heading: fill(RAIL_TEXTS.headingVisible, values),
    spoken: fill(RAIL_TEXTS.headingSpoken, values),
    rows,
    empty,
    hint,
  };
}

/** The approval requests that still wait for an answer, oldest raised first: the rail's list and the one count of its heading and of the Status button. */
export function pendingApprovals(store: LiveStore): ApprovalPayload[] {
  return sortedBy(
    inStoreOrder(store.approvals).filter((approval) => approval.state === 'pending'),
    (approval) => approval.raisedAt ?? '',
  );
}

/** The rail for the store: the sections in order and whether Telegram is one of them. In demo mode the empty checks point at the demo guide. */
export function railView(store: LiveStore, format: RailFormat, demo = false): RailView {
  const approvals = pendingApprovals(store);
  const checks = inStoreOrder(store.checks).filter((check) => check.stopped !== true);
  const late = Object.hasOwn(store.status, 'heartbeatStalled') && store.status['heartbeatStalled']?.active === true;
  const reminders = sortedBy(
    inStoreOrder(store.reminders).filter((reminder) => reminder.state === 'pending'),
    (reminder) => reminder.dueAt ?? '',
  );
  const decisions = sortedBy(
    store.decisions.filter((decision) => decision.kind === 'decide'),
    (decision) => decision.recordedAt ?? '',
    true,
  ).slice(0, DECISIONS_SHOWN);
  const sections: RailSection[] = [];
  const telegramShown = store.telegram.included;
  if (telegramShown) {
    sections.push({ id: 'telegram', label: RAIL_TEXTS.telegram, heading: RAIL_TEXTS.telegram, spoken: RAIL_TEXTS.telegram, rows: [], empty: '', hint: '' });
  }
  sections.push(
    listSection('approvals', RAIL_TEXTS.approvals, approvals.map((approval) => approvalRow(approval, format)), RAIL_TEXTS.emptyApprovals, ''),
    listSection('checks', RAIL_TEXTS.checks, checks.map((check) => checkRow(check, format, late)), demo ? RAIL_TEXTS.emptyChecksDemo : RAIL_TEXTS.emptyChecks, RAIL_TEXTS.hintChecks),
    listSection('reminders', RAIL_TEXTS.reminders, reminders.map((reminder) => reminderRow(reminder, format)), RAIL_TEXTS.emptyReminders, RAIL_TEXTS.hintReminders),
    listSection('decisions', RAIL_TEXTS.decisions, decisions.map((decision) => decisionRow(decision, format)), RAIL_TEXTS.emptyDecisions, ''),
  );
  return { sections, telegramShown };
}
