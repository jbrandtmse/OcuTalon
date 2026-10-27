/**
 * What an incident card shows (Story 6.1; FR-24, UX-DR72 to UX-DR78): the fixed strings, and a view model that turns one
 * `incident` payload (OcuTalon.Live.Payload.Incident, the full view of one incident, keyed by its Ref) into everything the card
 * draws. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is. The
 * times come in through the context, because the page's time formatters are not importable here; the components render what this
 * returns by interpolation only.
 *
 * - The card reads only the payload's fields, the decision of the footer from the context by `decisionRef`, and trace URLs only
 *   as served (`traceUrl`). It never builds a URL, decides a state or merges two payloads. A part whose fields are absent is left
 *   out, so a snapshot payload (row-backed fields only) renders without groups, requests, evidence or trace targets.
 * - The chip shows the payload's `state`; a state the page does not know has no chip and the attention bar. The bar follows the
 *   state: attention (open, awaiting approval, and every open variant), fixing, resolved, closed. A closed card is compact: the
 *   chip row, the headline and the Show details row only.
 * - The headline is "{count} {noun} failed since {time}" with the message time of `firstAt`; "{n} more since the notice" shows
 *   while `count` is above `noticeCount`. The cause and fix are sentences with exactly one final ".". The evidence line joins the
 *   humanized cause category, the element and the grouping, and shows only when a category or an element is set.
 * - While the state is fixing, the card says "Repairing and resending {n} {noun}\u2026" with the count of the executing request's
 *   result when there is one, else `noticeCount`, else `count`.
 * - The Show details panel holds the rows that have data (cause, sample header id, error, failures by item, the held-as-a-task
 *   note while a request is pending, the two trace links); with no row there is no Show details.
 * - announcementOf says what the chat announces for an incident: at first sight "Approval needed" for awaiting approval, "No fix
 *   proposed" for a fallback or a no-fix variant, else the state; afterwards the state, once, when it changes; else nothing.
 * - Story 6.4: a fallback or no-fix card shows its notice sentence (EXPERIENCE: Fallback incident notice, Incident notice without a
 *   fix; the unknown cause has its own sentence in place of the cause and the no-fix sentence) and, under "Failures:", one line per
 *   group; `dismissable` is true for a card in state resolved or open (never while awaiting approval or fixing, nor closed); a
 *   compact card holds the result band of each request of the payload, in order (`results`), and no notice and no groups.
 *   bandTexts says each band's text by the request's ref, for the chat's announcements (a result is announced once, when it first
 *   appears or changes on a card already shown).
 */
import type { ResultView } from '../approvals/approval-view';
import type { DecisionPayload, IncidentPayload, IncidentRequest, ItemNoun } from '../live/payloads';

/** Every fixed string of the incident card, its panel and its announcements. The ellipsis is U+2026, the middle dot U+00B7. */
export const INCIDENT_TEXTS = {
  stateOpen: 'Open',
  stateAwaitingApproval: 'Awaiting approval',
  stateFixing: 'Fixing',
  stateResolved: 'Resolved',
  stateClosed: 'Closed',
  headline: '{count} {noun} failed since {time}',
  headlineNoTime: '{count} {noun} failed',
  more: '{n} more since the notice',
  grouped: '{count} failures grouped into this incident',
  groupedOne: '1 failure grouped into this incident',
  fix: 'I can {fixSummary}.',
  fixing: 'Repairing and resending {count} {noun}\u2026',
  showDetails: 'Show details',
  nounOne: 'message',
  nounOther: 'messages',
  separator: ' \u00B7 ',
  labelCause: 'Cause',
  labelSample: 'Sample failed message',
  labelError: 'Error',
  labelItems: 'Failures by item',
  itemLine: '{item}: {count} failures, first {first}, last {last}',
  itemLineOne: '{item}: 1 failure, at {time}',
  held: 'Held as an IRIS Workflow task until someone answers.',
  linkSample: 'Sample message',
  linkFirstFailure: 'First failure',
  announceApproval: 'Incident: {headline}. Approval needed.',
  announceNoFix: 'Incident: {headline}. No fix proposed.',
  announceState: 'Incident: {headline}. {state}.',
  fallbackNotice: "I couldn't work out the cause ({reason}), so I'm not proposing a fix. Nothing was changed.",
  noFixNotice: "None of my fixes applies to this, so I'm not proposing one. Nothing was changed.",
  noFixUnknown: "I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.",
  failures: 'Failures:',
  groupLine: "{item}: {count}, '{summary}', first at {time}",
  dismiss: 'Dismiss',
} as const;

/** The state names of AD-15's table that the page draws a chip for, in the words of the chip tokens (`--incident-state-*`). */
export type IncidentChip = 'open' | 'awaiting-approval' | 'fixing' | 'resolved' | 'closed';

/** The 4px bar of the card: attention while a person is needed, then by state. */
export type IncidentBar = 'attention' | 'fixing' | 'resolved' | 'closed';

/** The page's readings of the context: decisions of the store, the clock and the three time formats (all take ISO times, "" when unreadable). */
export interface IncidentContext {
  /** The store's decisions; the footer's is the one whose ref is the payload's decisionRef. */
  decisions: readonly DecisionPayload[];
  /** The page's clock in ms, which the time functions read the day against. */
  nowMs: number;
  /** A time in message text: instance time, " ET" on the online demo (page-time.ts messageTime). */
  messageTime(iso: string, nowMs: number): string;
  /** The card's top time: the page's time with the day when it is not today, and the browser zone's name when its offset differs (pageWhenBeside). */
  topTime(iso: string, nowMs: number): string;
  /** A time of a panel row: the page's time with the day when it is not today (pageWhen). */
  itemTime(iso: string, nowMs: number): string;
  /** The band of a request's result with the incident's item noun (approval-view.ts resultView with the catalog's renderer), or undefined for a request with no result. */
  result(request: IncidentRequest, itemNoun: ItemNoun | undefined): ResultView | undefined;
  /** The text of a fallback reason value, as the catalog words it (the generic reason's for a value it does not know). */
  reasonText(reason: string | undefined): string;
}

/** The inputs of the footer's decision strip. */
export interface IncidentStrip {
  decision: DecisionPayload;
  /** The decision's own cost. */
  cost: number | undefined;
  /** The fallback reason value when the incident is a fallback, else undefined. */
  fallbackReason: string | undefined;
}

/** A row of the panel: a label and its value lines, in mono-sm when `mono` is set. */
export interface PanelRow {
  label: string;
  lines: string[];
  mono: boolean;
}

/** A trace link of the panel, as served. */
export interface PanelLink {
  text: string;
  url: string;
}

/** The Show details panel: the rows that have data, the held-as-a-task note while a request is pending, and the served links. */
export interface PanelView {
  rows: PanelRow[];
  held: boolean;
  links: PanelLink[];
}

/** Everything one incident card draws. A text that does not apply is "". */
export interface IncidentView {
  /** `incident:<ref>`, the key of the entry in the live store's chat. */
  key: string;
  ref: string;
  /** The chip's state, or undefined for a state the page does not know (no chip). */
  chip: IncidentChip | undefined;
  /** The chip's text, or undefined for no chip. */
  stateText: string | undefined;
  bar: IncidentBar;
  /** True for a fallback incident: the Fallback flag shows beside the chip. */
  fallback: boolean;
  /** The top time of the card; "" when `lastAt` is absent or unreadable. */
  time: string;
  headline: string;
  more: string;
  causeSentence: string;
  evidenceLine: string;
  fixSentence: string;
  fixingLine: string;
  /** True for a closed card: only the chip row, the headline and the Show details row remain. */
  compact: boolean;
  /** The footer's decision strip, when the decision is found; a compact card has none. */
  strip: IncidentStrip | undefined;
  /** The diagnosis session's served trace URL, when there is one; a compact card has none. */
  diagnosisUrl: string | undefined;
  /** The panel, or undefined when it has no row (then there is no Show details). */
  panel: PanelView | undefined;
  /** The fallback or no-fix sentence; "" for any other card and for a compact one. */
  notice: string;
  /** The failure group lines (the time in the headline's form); empty for a compact card. */
  groups: string[];
  /** True while Dismiss is offered: the state is resolved or open, and the card is not compact. */
  dismissable: boolean;
  /** For a compact card, each request's result band in payload order; empty otherwise. */
  results: ResultView[];
}

/** The text with its `{name}` slots filled. */
const fill = (template: string, values: Readonly<Record<string, string>>): string =>
  template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');

/** A finite number, else undefined. */
const numberOf = (value: unknown): number | undefined => (typeof value === 'number' && Number.isFinite(value) ? value : undefined);

/** A string with something in it, trimmed, else "". */
const textOf = (value: unknown): string => (typeof value === 'string' ? value.trim() : '');

/** The array, or an empty one when the payload's field is absent or is not one. */
const listOf = <T>(value: readonly T[] | undefined): readonly T[] => (Array.isArray(value) ? (value as readonly T[]) : []);

/** The chip, the chip's text and the bar of each state that AD-15 defines. */
const STATES: Readonly<Record<string, { chip: IncidentChip; text: string; bar: IncidentBar }>> = {
  open: { chip: 'open', text: INCIDENT_TEXTS.stateOpen, bar: 'attention' },
  awaiting_approval: { chip: 'awaiting-approval', text: INCIDENT_TEXTS.stateAwaitingApproval, bar: 'attention' },
  fixing: { chip: 'fixing', text: INCIDENT_TEXTS.stateFixing, bar: 'fixing' },
  resolved: { chip: 'resolved', text: INCIDENT_TEXTS.stateResolved, bar: 'resolved' },
  closed: { chip: 'closed', text: INCIDENT_TEXTS.stateClosed, bar: 'closed' },
};

/** The state's entry, or undefined for a state the page does not know. */
function stateOf(state: string | undefined): (typeof STATES)[string] | undefined {
  return state !== undefined && Object.hasOwn(STATES, state) ? STATES[state] : undefined;
}

/** The chip's text of a state, or undefined for a state the page does not know. */
export function stateText(state: string | undefined): string | undefined {
  return stateOf(state)?.text;
}

/**
 * A cause or fix as a sentence: trimmed, with one final "." dropped and one added. Nothing in it gives "".
 */
function sentenceOf(text: string): string {
  const body = text.trim().replace(/\.$/, '').trim();
  return body === '' ? '' : `${body}.`;
}

/** A cause category as words: "data_format_change" is "Data format change". Anything it does not know reads the same way. */
export function categoryText(category: string | undefined): string {
  const words = textOf(category).replace(/_/g, ' ').replace(/\s+/g, ' ').trim();
  return words === '' ? '' : words.charAt(0).toUpperCase() + words.slice(1);
}

/** The item noun for a count: the payload's one or other form, else AD-15's default. */
function nounFor(noun: ItemNoun | undefined, count: number): string {
  const form = count === 1 ? textOf(noun?.one) : textOf(noun?.other);
  if (form !== '') {
    return form;
  }
  return count === 1 ? INCIDENT_TEXTS.nounOne : INCIDENT_TEXTS.nounOther;
}

/** The headline: "50 orders failed since 14:12"; without a readable first time, "50 orders failed". */
function headlineOf(payload: IncidentPayload, ctx: IncidentContext): string {
  const count = numberOf(payload.count) ?? 0;
  const slots = { count: String(count), noun: nounFor(payload.itemNoun, count) };
  const time = ctx.messageTime(payload.firstAt ?? '', ctx.nowMs);
  return time === '' ? fill(INCIDENT_TEXTS.headlineNoTime, slots) : fill(INCIDENT_TEXTS.headline, { ...slots, time });
}

/** "2 more since the notice" while count is above noticeCount; "" when it is not or either is absent. */
function moreOf(payload: IncidentPayload): string {
  const count = numberOf(payload.count);
  const notice = numberOf(payload.noticeCount);
  return count !== undefined && notice !== undefined && count > notice ? fill(INCIDENT_TEXTS.more, { n: String(count - notice) }) : '';
}

/** The evidence line: the category, the element and the grouping, when a category or an element is set; "" otherwise. */
function evidenceLineOf(payload: IncidentPayload): string {
  const category = categoryText(payload.causeCategory);
  const element = textOf(payload.element);
  if (category === '' && element === '') {
    return '';
  }
  const count = numberOf(payload.count);
  const parts = [category, element];
  if (count !== undefined) {
    parts.push(count === 1 ? INCIDENT_TEXTS.groupedOne : fill(INCIDENT_TEXTS.grouped, { count: String(count) }));
  }
  return parts.filter((part) => part !== '').join(INCIDENT_TEXTS.separator);
}

/** The fix sentence "I can repair and resend all 50.", without the message's closing "Approve?"; "" when there is no fix. */
function fixSentenceOf(payload: IncidentPayload): string {
  const summary = sentenceOf(textOf(payload.fixSummary).replace(/\s*Approve\?$/i, ''));
  return summary === '' ? '' : fill(INCIDENT_TEXTS.fix, { fixSummary: summary.slice(0, -1) });
}

/** The count of the fixing line: the first executing request's total, else noticeCount, else count; undefined when there is none. */
function fixingCountOf(payload: IncidentPayload): number | undefined {
  for (const request of listOf(payload.requests)) {
    const total = numberOf(request?.result?.total);
    if (request?.state === 'executing' && total !== undefined) {
      return total;
    }
  }
  return numberOf(payload.noticeCount) ?? numberOf(payload.count);
}

/** "Repairing and resending 50 orders\u2026" while the state is fixing, else "". */
function fixingLineOf(payload: IncidentPayload): string {
  if (payload.state !== 'fixing') {
    return '';
  }
  const count = fixingCountOf(payload) ?? 0;
  return fill(INCIDENT_TEXTS.fixing, { count: String(count), noun: nounFor(payload.itemNoun, count) });
}

/**
 * The failures-by-item lines, one per entry, with times as the panel shows them: one failure has its one time ("1 failure, at
 * 16:12"), more have the first and the last ("3 failures, first 16:12, last 16:14").
 */
function itemLinesOf(payload: IncidentPayload, ctx: IncidentContext): string[] {
  return listOf(payload.evidence?.items)
    .filter((item) => item !== null && typeof item === 'object')
    .map((item) => {
      const count = numberOf(item.count) ?? 0;
      const name = textOf(item.itemName);
      if (count === 1) {
        return fill(INCIDENT_TEXTS.itemLineOne, { item: name, time: ctx.itemTime(item.firstAt ?? item.lastAt ?? '', ctx.nowMs) });
      }
      return fill(INCIDENT_TEXTS.itemLine, {
        item: name,
        count: String(count),
        first: ctx.itemTime(item.firstAt ?? '', ctx.nowMs),
        last: ctx.itemTime(item.lastAt ?? '', ctx.nowMs),
      });
    });
}

/** The panel's view, or undefined when it has no row at all. */
function panelOf(payload: IncidentPayload, ctx: IncidentContext): PanelView | undefined {
  const rows: PanelRow[] = [];
  const cause = [categoryText(payload.causeCategory), textOf(payload.element)].filter((part) => part !== '').join(INCIDENT_TEXTS.separator);
  if (cause !== '') {
    rows.push({ label: INCIDENT_TEXTS.labelCause, lines: [cause], mono: false });
  }
  const sample = numberOf(payload.evidence?.sampleHeaderId);
  if (sample !== undefined && sample > 0) {
    rows.push({ label: INCIDENT_TEXTS.labelSample, lines: [String(sample)], mono: true });
  }
  const error = textOf(payload.evidence?.sampleError);
  if (error !== '') {
    rows.push({ label: INCIDENT_TEXTS.labelError, lines: [error], mono: true });
  }
  const items = itemLinesOf(payload, ctx);
  if (items.length > 0) {
    rows.push({ label: INCIDENT_TEXTS.labelItems, lines: items, mono: true });
  }
  const held = listOf(payload.requests).some((request) => request?.state === 'pending');
  const links: PanelLink[] = [];
  const sampleUrl = textOf(payload.traceTargets?.sample?.traceUrl);
  if (sampleUrl !== '') {
    links.push({ text: INCIDENT_TEXTS.linkSample, url: sampleUrl });
  }
  const firstUrl = textOf(payload.traceTargets?.firstFailure?.traceUrl);
  if (firstUrl !== '') {
    links.push({ text: INCIDENT_TEXTS.linkFirstFailure, url: firstUrl });
  }
  return rows.length === 0 && !held && links.length === 0 ? undefined : { rows, held, links };
}

/** The decision of the footer: the context's decision whose ref is the payload's decisionRef; undefined when there is none. */
function decisionOf(payload: IncidentPayload, ctx: IncidentContext): DecisionPayload | undefined {
  const ref = textOf(payload.decisionRef);
  return ref === '' ? undefined : ctx.decisions.find((decision) => decision.ref === ref);
}

/** True when the incident is a fallback: its `fallback` flag or its open variant says so. */
function isFallback(payload: IncidentPayload): boolean {
  return payload.fallback === true || payload.openVariant === 'fallback';
}

/** True when the incident's cause has no fix in OcuTalon's fixed set. */
function isNoFix(payload: IncidentPayload): boolean {
  return payload.openVariant === 'no_fix';
}

/** True when the cause could not be told from the failed messages (AD-15: no fix includes `unknown`). */
function unknownCause(payload: IncidentPayload): boolean {
  return isNoFix(payload) && payload.causeCategory === 'unknown';
}

/** The cause sentence: the payload's, but none for a no-fix card of an unknown cause, whose notice says it. */
function causeOf(payload: IncidentPayload): string {
  return unknownCause(payload) ? '' : sentenceOf(textOf(payload.cause));
}

/** The notice sentence of a fallback or no-fix card; "" for any other. */
function noticeOf(payload: IncidentPayload, ctx: IncidentContext): string {
  if (isFallback(payload)) {
    return fill(INCIDENT_TEXTS.fallbackNotice, { reason: ctx.reasonText(payload.fallbackReason) });
  }
  if (unknownCause(payload)) {
    return INCIDENT_TEXTS.noFixUnknown;
  }
  return isNoFix(payload) ? INCIDENT_TEXTS.noFixNotice : '';
}

/**
 * The failure group lines "Order transform: 50, 'date could not be read', first at 14:12". The time is the headline's form
 * (message time); where that is dated (not NN:NN, less a trailing " ET"), "first at" becomes "first on", as the catalog's renderer does.
 */
function groupLinesOf(payload: IncidentPayload, ctx: IncidentContext): string[] {
  return listOf(payload.groups)
    .filter((group) => group !== null && typeof group === 'object')
    .map((group) => {
      const time = ctx.messageTime(group.firstAt ?? '', ctx.nowMs);
      const dated = time !== '' && !/^\d\d:\d\d$/.test(time.replace(/ ET$/, ''));
      const template = dated ? INCIDENT_TEXTS.groupLine.replace('first at {time}', 'first on {time}') : INCIDENT_TEXTS.groupLine;
      return fill(template, { item: textOf(group.itemName), count: String(numberOf(group.count) ?? 0), summary: textOf(group.errorSummary), time });
    });
}

/** The result bands of the payload's requests, in order, each with the request's ref; a request with no result has none. */
function bandsOf(payload: IncidentPayload, ctx: IncidentContext): { ref: string; band: ResultView }[] {
  const bands: { ref: string; band: ResultView }[] = [];
  for (const request of listOf(payload.requests)) {
    const band = request !== null && typeof request === 'object' ? ctx.result(request, payload.itemNoun) : undefined;
    if (band !== undefined) {
      bands.push({ ref: request.ref ?? '', band });
    }
  }
  return bands;
}

/** The text of each request's result band by the request's ref (for the chat's announcements). A ref with no band is not there. */
export function bandTexts(payload: IncidentPayload, ctx: IncidentContext): Readonly<Record<string, string>> {
  const texts: Record<string, string> = {};
  for (const { ref, band } of bandsOf(payload, ctx)) {
    texts[ref] = band.text;
  }
  return texts;
}

/** Everything the card draws for one incident payload. */
export function incidentView(payload: IncidentPayload, ctx: IncidentContext): IncidentView {
  const state = stateOf(payload.state);
  const ref = payload.ref ?? '';
  const compact = state?.chip === 'closed';
  const fallback = payload.fallback === true;
  const decision = compact ? undefined : decisionOf(payload, ctx);
  return {
    key: `incident:${ref}`,
    ref,
    chip: state?.chip,
    stateText: state?.text,
    bar: state?.bar ?? 'attention',
    fallback,
    time: ctx.topTime(payload.lastAt ?? '', ctx.nowMs),
    headline: headlineOf(payload, ctx),
    more: compact ? '' : moreOf(payload),
    causeSentence: compact ? '' : causeOf(payload),
    evidenceLine: compact ? '' : evidenceLineOf(payload),
    fixSentence: compact ? '' : fixSentenceOf(payload),
    fixingLine: compact ? '' : fixingLineOf(payload),
    compact,
    strip:
      decision === undefined
        ? undefined
        : { decision, cost: decision.costUSD, fallbackReason: fallback ? (payload.fallbackReason ?? '') : undefined },
    diagnosisUrl: compact ? undefined : textOf(payload.traceTargets?.diagnosis?.traceUrl) || undefined,
    panel: panelOf(payload, ctx),
    notice: compact ? '' : noticeOf(payload, ctx),
    groups: compact ? [] : groupLinesOf(payload, ctx),
    dismissable: !compact && (state?.chip === 'resolved' || state?.chip === 'open'),
    results: compact ? bandsOf(payload, ctx).map((one) => one.band) : [],
  };
}

/** True when the incident is a fallback or has no fix to propose: its `fallback` flag or its open variant says so. */
function proposesNoFix(payload: IncidentPayload): boolean {
  return payload.fallback === true || payload.openVariant === 'fallback' || payload.openVariant === 'no_fix';
}

/**
 * What the chat announces for an incident (the state is the payload's; headline is the card's):
 * - at first sight (`previous` undefined): "Incident: {headline}. Approval needed." for awaiting approval, "\u2026 No fix proposed." for
 *   a fallback or a no-fix variant, else the state's form "Incident: {headline}. Fixing.", so that no announcement claims an
 *   approval that does not exist; a state the page does not know says nothing;
 * - afterwards, when the state differs from `previous` (the state at the last look, "" for none): the state's form;
 * - otherwise nothing: a count-only change, an unchanged update.
 */
export function announcementOf(previous: string | undefined, payload: IncidentPayload, headline: string): string | undefined {
  const state = payload.state ?? '';
  if (previous === undefined) {
    if (state === 'awaiting_approval') {
      return fill(INCIDENT_TEXTS.announceApproval, { headline });
    }
    if (proposesNoFix(payload)) {
      return fill(INCIDENT_TEXTS.announceNoFix, { headline });
    }
  } else if (previous === state) {
    return undefined;
  }
  const text = stateText(state);
  return text === undefined ? undefined : fill(INCIDENT_TEXTS.announceState, { headline, state: text });
}
