/**
 * What an approval request card shows (Story 6.2; FR-8, FR-25, UX-DR79 to UX-DR83): the fixed strings, and a view model that turns
 * one `approval` payload (OcuTalon.Live.Payload.Approval, the full view of one request, keyed by its Ref) into everything the card
 * draws, plus the reading of the answer endpoint's reply. A framework-free module: it imports only types and uses only erasable
 * TypeScript syntax, so Node runs it as it is. What the page owns comes in through the context: the clock, the signed-in user, the
 * two time formats of page-time.ts, the catalog's renderer (msg/catalog.ts renderPageText) and the rail's title of a request
 * (rail-view.ts approvalTitle). The components render what this returns by interpolation only.
 *
 * - A request is drawn for each `approval` payload of the store whose `incidentRef` is the incident's and whose state is not
 *   cancelled, in `raisedAt` order (requestsOf). A request with no payload is not drawn.
 * - While the state is pending the card has the label "Approval needed", the action in the imperative, the fixed-targets line, the
 *   dry run with "Nothing has changed yet.", Approve and Reject and the expiry. Any other state has the label "Approval request",
 *   the answered status in place of the two buttons, and the dry run as a record: the fixed-targets line, the expiry and "Nothing
 *   has changed yet." go.
 * - The status texts are the catalog's answered.* keys. The answerer is named only when the install is local (not the online demo)
 *   and `answeredBy` is not the signed-in user, compared without case. Times are page times with the zone name when it differs
 *   from the instance's.
 * - A dry run that is not an object, or has no numeric `affected`, leaves out the fixed-targets line and the dry run block, and
 *   the action reads "Repair and resend.". A count of one uses the singular forms.
 * - answerOutcomeOf reads the reply of POST /approvals/:ref/answer; latePressText is the notice of a press that lost the race.
 */
import type { ApprovalPayload, DryRun, IncidentPayload } from '../live/payloads';

/** Every fixed string of the approval request card and its notices. */
export const APPROVAL_TEXTS = {
  labelPending: 'Approval needed',
  labelAnswered: 'Approval request',
  approve: 'Approve',
  reject: 'Reject',
  approveName: 'Approve: {action}',
  rejectName: 'Reject: {action}',
  action: '{title}.',
  fixedTargets:
    'Approving runs exactly this change on these {count} {noun}, without asking the model again. New failures need their own approval.',
  fixedTargetsOne:
    'Approving runs exactly this change on this {noun}, without asking the model again. New failures need their own approval.',
  dryRun: 'Dry run',
  countLine: '{count} {noun} affected',
  before: 'Before',
  after: 'After',
  willResend: 'Will resend',
  resendCopies: '{count} repaired copies; the originals stay unchanged.',
  resendCopyOne: '1 repaired copy; the original stays unchanged.',
  nothingYet: 'Nothing has changed yet.',
  expires: 'Expires {when}',
  notApprover: 'Only an approver for resends can answer this request.',
  gone: 'That request is no longer available.',
  busyNotice: "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
} as const;

/** The 4px bar of the card: pending while it waits, approved from the answer to the fix's end, closed for the rest. */
export type ApprovalBar = 'pending' | 'approved' | 'closed';

/** The answered status line: its text, its tone (the colour of the text and the icon) and its icon. */
export interface AnswerStatus {
  text: string;
  tone: 'approved' | 'rejected' | 'expired';
  icon: 'circle-check' | 'circle-slash' | 'clock';
}

/** The dry run block: every part is already text. `before` and `after` are "" when the request has no example. */
export interface DryRunView {
  countLine: string;
  field: string;
  before: string;
  after: string;
  resendLine: string;
  /** "Nothing has changed yet." while the request is pending, else "". */
  nothingYet: string;
}

/** The page's readings of the context. */
export interface ApprovalContext {
  /** The page's clock in ms, which the expiry's day is read against. */
  nowMs: number;
  /** The instance's time zone (the page-time functions read it through the two functions below). */
  instanceZone: string;
  /** True on the online demo: nobody is named. */
  onlineDemo: boolean;
  /** The signed-in user of the snapshot; an answer by this user does not name them. */
  user: string;
  /** A page time beside message text: the browser's zone name is added when its offset differs from the instance's (page-time.ts pageTimeBeside). */
  timeBeside(iso: string): string;
  /** A page time with its day, beside message text (page-time.ts pageWhenBeside). */
  whenBeside(iso: string, nowMs: number): string;
  /** The page wording of a catalog key with its slots filled (msg/catalog.ts renderPageText). */
  render(key: string, slots: Readonly<Record<string, string>>): string;
  /** The title of a request: "Repair and resend 50 orders" (rail-view.ts approvalTitle). */
  title(approval: ApprovalPayload): string;
}

/** Everything one approval request card draws. A text that does not apply is "". */
export interface ApprovalView {
  /** `approval:<ref>`, the key of the card. */
  key: string;
  ref: string;
  /** True while the request is pending: the card has the two buttons. */
  pending: boolean;
  label: string;
  bar: ApprovalBar;
  /** The action in the imperative with its final period: "Repair and resend 50 orders.". */
  action: string;
  /** The accessible names of the two buttons: "Approve: repair and resend 50 orders". */
  approveName: string;
  rejectName: string;
  /** The fixed-targets line; "" unless the request is pending and its dry run has a count. */
  fixedTargets: string;
  dryRun: DryRunView | undefined;
  /** "Expires tomorrow at 14:13"; "" unless the request is pending and its expiry is readable. */
  expiry: string;
  /** The answered status that replaces the buttons, or undefined while pending (and for a state the page does not know). */
  status: AnswerStatus | undefined;
}

/** The reading of the answer endpoint's reply. */
export type AnswerOutcome =
  | { kind: 'done'; approval: ApprovalPayload | undefined }
  | { kind: 'already'; approval: ApprovalPayload | undefined; message: string }
  | { kind: 'expired'; approval: ApprovalPayload | undefined }
  | { kind: 'gone' }
  | { kind: 'notAllowed'; message: string }
  | { kind: 'failed'; message: string }
  | { kind: 'unreachable' };

/** The text with its `{name}` slots filled. */
const fill = (template: string, values: Readonly<Record<string, string>>): string =>
  template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');

/** A finite number, else undefined. */
const numberOf = (value: unknown): number | undefined => (typeof value === 'number' && Number.isFinite(value) ? value : undefined);

/** A string with something in it, trimmed, else "". */
const textOf = (value: unknown): string => (typeof value === 'string' ? value.trim() : '');

/** The text with its first letter in lower case: "Repair and resend 50 orders" is "repair and resend 50 orders". */
const lowerFirst = (text: string): string => text.charAt(0).toLowerCase() + text.slice(1);

/**
 * The requests of an incident: the store's approvals whose `incidentRef` is the incident's `ref` and whose state is not cancelled,
 * in `raisedAt` order (a tie keeps the order of the store). An incident with no ref has none.
 */
export function requestsOf(incident: IncidentPayload, approvals: Readonly<Record<string, ApprovalPayload>> | undefined): ApprovalPayload[] {
  const ref = textOf(incident.ref);
  if (ref === '' || approvals === undefined) {
    return [];
  }
  const found = Object.values(approvals).filter((approval) => approval.incidentRef === ref && approval.state !== 'cancelled');
  return found
    .map((approval, index) => ({ approval, index }))
    .sort((a, b) => {
      const left = a.approval.raisedAt ?? '';
      const right = b.approval.raisedAt ?? '';
      return left < right ? -1 : left > right ? 1 : a.index - b.index;
    })
    .map((one) => one.approval);
}

/** The dry run when it is an object with a numeric `affected`, else undefined. */
function dryRunOf(approval: ApprovalPayload): (DryRun & { affected: number }) | undefined {
  const dry = approval.dryRun;
  if (dry === null || typeof dry !== 'object' || Array.isArray(dry)) {
    return undefined;
  }
  return numberOf(dry.affected) === undefined ? undefined : (dry as DryRun & { affected: number });
}

/** The noun for a count: the dry run's one or other form, "" when it has none. */
function nounFor(dry: DryRun, count: number): string {
  return textOf(count === 1 ? dry.itemNoun?.one : dry.itemNoun?.other);
}

/** The text with the spaces of an empty slot collapsed: "50  affected" is "50 affected" and "these 50 ," is "these 50,". */
const tidy = (text: string): string => text.replace(/\s{2,}/g, ' ').replace(/\s+,/g, ',').trim();

/** The dry run block of a request, or undefined when its dry run has no count. */
function dryRunView(approval: ApprovalPayload, pending: boolean): DryRunView | undefined {
  const dry = dryRunOf(approval);
  if (dry === undefined) {
    return undefined;
  }
  const noun = nounFor(dry, dry.affected);
  const field = textOf(dry.field);
  const example = (value: string | undefined): string => (textOf(value) === '' ? '' : tidy(`${field} ${textOf(value)}`));
  const resend = numberOf(dry.resend);
  return {
    countLine: tidy(fill(APPROVAL_TEXTS.countLine, { count: String(dry.affected), noun })),
    field,
    before: example(dry.before),
    after: example(dry.after),
    resendLine:
      resend === undefined ? '' : resend === 1 ? APPROVAL_TEXTS.resendCopyOne : fill(APPROVAL_TEXTS.resendCopies, { count: String(resend) }),
    nothingYet: pending ? APPROVAL_TEXTS.nothingYet : '',
  };
}

/** The accent bar of a state: pending; approved, executing and done; closed for the rest (rejected, expired, failed). */
function barOf(state: string | undefined): ApprovalBar {
  if (state === 'pending') {
    return 'pending';
  }
  return state === 'approved' || state === 'executing' || state === 'done' ? 'approved' : 'closed';
}

/** The states of a request that was approved: the fix's own states after the answer. */
const ANSWERED_APPROVED: ReadonlySet<string> = new Set(['approved', 'executing', 'done', 'failed']);

/** True when the answerer is to be named: a local install, a known answerer who is not the signed-in user (compared without case). */
function namesAnswerer(approval: ApprovalPayload, ctx: ApprovalContext): boolean {
  const by = textOf(approval.answeredBy);
  return !ctx.onlineDemo && by !== '' && by.toLowerCase() !== textOf(ctx.user).toLowerCase();
}

/** The slots of an answered text: who, from which channel and when. */
function answeredSlots(approval: ApprovalPayload, ctx: ApprovalContext): Record<string, string> {
  return { user: textOf(approval.answeredBy), channel: textOf(approval.answeredChannel), time: ctx.timeBeside(approval.answeredAt ?? '') };
}

/** The answered status of a request, or undefined for a pending request and for a state the page does not know. */
function statusOf(approval: ApprovalPayload, ctx: ApprovalContext): AnswerStatus | undefined {
  const named = namesAnswerer(approval, ctx) ? 'By' : '';
  if (ANSWERED_APPROVED.has(approval.state ?? '')) {
    return { text: ctx.render(`answered.approved${named}`, answeredSlots(approval, ctx)), tone: 'approved', icon: 'circle-check' };
  }
  switch (approval.state) {
    case 'rejected':
      return { text: ctx.render(`answered.rejected${named}`, answeredSlots(approval, ctx)), tone: 'rejected', icon: 'circle-slash' };
    case 'expired':
      return { text: ctx.render('answered.expired', { time: ctx.timeBeside(approval.expiresAt ?? '') }), tone: 'expired', icon: 'clock' };
    default:
      return undefined;
  }
}

/** Everything the card draws for one approval payload. */
export function approvalView(approval: ApprovalPayload, ctx: ApprovalContext): ApprovalView {
  const ref = approval.ref ?? '';
  const pending = approval.state === 'pending';
  const title = ctx.title(approval);
  const dry = dryRunOf(approval);
  const expires = pending ? ctx.whenBeside(approval.expiresAt ?? '', ctx.nowMs) : '';
  let fixedTargets = '';
  if (pending && dry !== undefined) {
    const noun = nounFor(dry, dry.affected);
    fixedTargets = tidy(
      dry.affected === 1
        ? fill(APPROVAL_TEXTS.fixedTargetsOne, { noun })
        : fill(APPROVAL_TEXTS.fixedTargets, { count: String(dry.affected), noun }),
    );
  }
  return {
    key: `approval:${ref}`,
    ref,
    pending,
    label: pending ? APPROVAL_TEXTS.labelPending : APPROVAL_TEXTS.labelAnswered,
    bar: barOf(approval.state),
    action: fill(APPROVAL_TEXTS.action, { title }),
    approveName: fill(APPROVAL_TEXTS.approveName, { action: lowerFirst(title) }),
    rejectName: fill(APPROVAL_TEXTS.rejectName, { action: lowerFirst(title) }),
    fixedTargets,
    dryRun: dryRunView(approval, pending),
    expiry: expires === '' ? '' : fill(APPROVAL_TEXTS.expires, { when: expires }),
    status: pending ? undefined : statusOf(approval, ctx),
  };
}

/** The body of a reply as an object, else undefined. */
function bodyObject(body: unknown): Record<string, unknown> | undefined {
  return body !== null && typeof body === 'object' && !Array.isArray(body) ? (body as Record<string, unknown>) : undefined;
}

/** The request payload that a reply carries beside its result or its error, else undefined. */
function approvalOf(body: unknown): ApprovalPayload | undefined {
  const approval = bodyObject(bodyObject(body)?.['approval']);
  return approval === undefined ? undefined : (approval as ApprovalPayload);
}

/** The `error.message` of a reply, else "". */
function messageOf(body: unknown): string {
  return textOf(bodyObject(bodyObject(body)?.['error'])?.['message']);
}

/**
 * The reading of the reply to a press, by its HTTP status and body:
 * - 200 is done, with the answered request;
 * - 409 already_answered is the late press, with the request and the server's own message; 409 expired is the expired request;
 * - 404 is "no longer available", 403 not allowed (the server's message for the request's kind);
 * - status 0 (no connection) is unreachable, and any other status is failed with its `error.message`, else unreachable.
 */
export function answerOutcomeOf(status: number, body: unknown): AnswerOutcome {
  const code = textOf(bodyObject(bodyObject(body)?.['error'])?.['code']);
  if (status === 200) {
    return { kind: 'done', approval: approvalOf(body) };
  }
  if (status === 409 && code === 'already_answered') {
    return { kind: 'already', approval: approvalOf(body), message: messageOf(body) };
  }
  if (status === 409 && code === 'expired') {
    return { kind: 'expired', approval: approvalOf(body) };
  }
  if (status === 404) {
    return { kind: 'gone' };
  }
  if (status === 403) {
    return { kind: 'notAllowed', message: messageOf(body) || APPROVAL_TEXTS.notApprover };
  }
  const message = status === 0 ? '' : messageOf(body);
  return message === '' ? { kind: 'unreachable' } : { kind: 'failed', message };
}

/**
 * The notice of a press that lost the race, from the request that won: "Already answered: approved from the simulated phone at
 * 14:15." (rejected, or "by {user}" on a local install for another user's answer, in the same way). A request that is not an
 * approved or rejected one gives "".
 */
export function latePressText(approval: ApprovalPayload, ctx: ApprovalContext): string {
  const verb = approval.state === 'rejected' ? 'Rejected' : ANSWERED_APPROVED.has(approval.state ?? '') ? 'Approved' : '';
  return verb === '' ? '' : ctx.render(`answered.already${verb}${namesAnswerer(approval, ctx) ? 'By' : ''}`, answeredSlots(approval, ctx));
}
