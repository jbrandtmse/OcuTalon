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
 * - The status texts are the catalog's answered.* keys. A cancelled request has one only when the payload carries `cancelledAt` and
 *   `server` (a tool call whose MCP server was removed, Story 21.10): answered.canceled, in the rejected tone with the circle-slash icon. The answerer is named only when the install is local (not the online demo)
 *   and `answeredBy` is not the signed-in user, compared without case. Times are page times with the zone name when it differs
 *   from the instance's.
 * - A dry run that is not an object, or has no numeric `affected`, leaves out the fixed-targets line and the dry run block, and
 *   the action reads "Repair and resend.". A count of one uses the singular forms.
 * - The dry run block has one more row, `eitherWay` (Story 7.8; U-249), between After and Will resend: the notice's either-way
 *   sentence, rendered from the page catalog's incident.eitherWayLine, which the generator cuts out of the two catalog entries that
 *   hold it. The server decides whether it applies (the payload's `eitherWay` and `reading`, from the notice's own rule); the page
 *   never looks at a date. The row is "" unless `eitherWay` is true, `reading` is not empty and `resend` is a number of at least 1.
 *   Its slots are the notice's: resendCount is `resend` (which also chooses the one or many form), reading is `reading` and item is
 *   the dry run's singular noun, "message" when it has none. It stays on an answered request.
 * - A suspend or resume (Story 23.2; fixKind suspend_item or resume_item) has a dry run block of two rows, Before "{item}: enabled" and After "{item}: disabled" (swapped for a
 *   resume), with no count line, no fixed-targets line and no resend row; a reroute has the count line, Before "Message {example}: {from}", After "Message {example}: {to}" and the
 *   resend row "{count} copies to {to}; the originals stay unchanged." (one copy: "1 copy to {to}; the original stays unchanged.").
 * - A partner delay notice (Story 23.5; fixKind partner_warning) has no dry run block and no fixed-targets line. Its `partner` holds "To: {recipients}" (the payload's dry run
 *   recipients, each "Name <address>", with the Simulated label beside it when `simulated` is true), the notice as the payload gives it (shown with its line breaks) and, while pending only,
 *   "Nothing is sent unless you approve. It goes to the Simulated mailbox, not to a real inbox.". Its result bands are the texts of APPROVAL_TEXTS: partnerSent, partnerSentSome,
 *   partnerKept and partnerNotSent; each names the Simulated mailbox or the draft, and none says that an email was sent.
 * - A setting request (Story 40.6; kind "setting", a proposed persona) is drawn with the title from the context alone (its notice text,
 *   the catalog's "OcuTalon suggests a new persona..." sentence, is not the card's text), the action is that title with no period, and
 *   `setting` holds the three lines "Now: {old}", "Proposed: {new}" (the payload's dry run before and after) and, while pending only,
 *   "Nothing changes unless you approve.". It has no dry run block and no fixed-targets line; the answered status is the same as for
 *   any request.
 * - answerOutcomeOf reads the reply of POST /approvals/:ref/answer; latePressText is the notice of a press that lost the race.
 * - A request that the signed-in user may not answer (Story 25.5: a pending payload with `answerable` false; an absent `answerable` is answerable) has `cannotAnswer`, the
 *   sentence of its approver kind (refusalText: the catalog's answered.notApprover plus the kind with a capital first letter when the page has that key, else the fallback
 *   "Only an approver can answer this request."), and the card and the phone show it in place of Approve and Reject.
 * - resultView (Story 6.4; AD-16) reads the `result` of one of the incident payload's `requests` into the band under the request's
 *   answered status: the catalog's result.* key by the fields (the page maps the fields, because the payload carries no key), its text
 *   with the count-of-one forms, the tone (success only for all-through, a completed suspend or resume and a completed reroute, else partial), the icon and the
 *   audit line.
 */
import type { ApprovalPayload, DryRun, IncidentPayload, IncidentRequest, IncidentRequestResult, ItemNoun } from '../live/payloads';

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
  itemState: '{item}: {state}',
  rerouteBefore: 'Message {example}: {from}',
  rerouteAfter: 'Message {example}: {to}',
  rerouteCopies: '{count} copies to {to}; the originals stay unchanged.',
  rerouteCopyOne: '1 copy to {to}; the original stays unchanged.',
  settingNow: 'Now: {old}',
  settingProposed: 'Proposed: {new}',
  settingNote: 'Nothing changes unless you approve.',
  partnerTo: 'To: {recipients}',
  partnerNote: 'Nothing is sent unless you approve. It goes to the Simulated mailbox, not to a real inbox.',
  partnerSent: 'Sent to the Simulated mailbox.',
  partnerSentSome: 'Sent to the Simulated mailbox for {completed} of {total} contacts.',
  partnerKept: "Approved and kept as a draft: email delivery isn't set up yet.",
  partnerNotSent: 'Not sent: {reason}.',
  expires: 'Expires {when}',
  notApprover: 'Only an approver can answer this request.',
  gone: 'That request is no longer available.',
  busyNotice: "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
  nounOne: 'message',
  nounOther: 'messages',
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
  /** The notice's either-way sentence, or "" when the row is absent. */
  eitherWay: string;
  resendLine: string;
  /** "Nothing has changed yet." while the request is pending, else "". */
  nothingYet: string;
}

/** The three lines of a setting request's card: what is now, what is proposed, and, while pending, "Nothing changes unless you approve.". */
export interface SettingView {
  now: string;
  proposed: string;
  /** "" unless the request is pending. */
  note: string;
}

/** The card of a partner delay notice: who it goes to, the notice, whether it is simulated and, while pending, the note. */
export interface PartnerView {
  /** "To: Results Partner IT <it@results-partner.example>". */
  to: string;
  /** The notice as approved, with its line breaks. */
  notice: string;
  /** True when the payload says the notice goes to the Simulated mailbox: the card shows the Simulated label beside the To line. */
  simulated: boolean;
  /** "" unless the request is pending. */
  note: string;
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
  render(key: string, slots: Readonly<Record<string, unknown>>): string;
  /** The title of a request: "Repair and resend 50 orders" (rail-view.ts approvalTitle). */
  title(approval: ApprovalPayload): string;
}

/** Everything one approval request card draws. A text that does not apply is "". */
export interface ApprovalView {
  /** `approval:<ref>`, the key of the card. */
  key: string;
  ref: string;
  /** True while the request is pending: the card has the two buttons, or `cannotAnswer` in their place. */
  pending: boolean;
  /** The sentence that replaces the two buttons when the request is pending and the payload says `answerable` is false; "" otherwise (refusalText of its `approverKind`). */
  cannotAnswer: string;
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
  /** The lines of a setting request in place of the dry run; undefined for any other kind. */
  setting: SettingView | undefined;
  /** The lines of a partner delay notice in place of the dry run; undefined for any other kind. */
  partner: PartnerView | undefined;
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

/** The either-way sentence of the dry run, or "" when the payload does not flag it, has no reading, or has no resend count of at least 1. */
function eitherWayOf(dry: DryRun, resend: number | undefined, ctx: ApprovalContext): string {
  const reading = textOf(dry.reading);
  if (dry.eitherWay !== true || reading === '' || resend === undefined || resend < 1) {
    return '';
  }
  return ctx.render('incident.eitherWayLine', {
    resendCount: String(resend),
    reading,
    item: textOf(dry.itemNoun?.one) || APPROVAL_TEXTS.nounOne,
  });
}

/** The dry run block of a suspend or resume (Story 23.2): the item's state before and after, or undefined when the dry run names no item. */
function itemDryRunView(approval: ApprovalPayload, pending: boolean): DryRunView | undefined {
  const dry = approval.dryRun;
  const item = dry === null || typeof dry !== 'object' ? '' : textOf(dry.item);
  if (item === '') {
    return undefined;
  }
  return {
    countLine: '',
    field: '',
    before: fill(APPROVAL_TEXTS.itemState, { item, state: textOf(dry?.before) }),
    after: fill(APPROVAL_TEXTS.itemState, { item, state: textOf(dry?.after) }),
    eitherWay: '',
    resendLine: '',
    nothingYet: pending ? APPROVAL_TEXTS.nothingYet : '',
  };
}

/** The dry run block of a reroute (Story 23.2): the example message where it is now and where it would go, and the copies that will be resent. */
function rerouteDryRunView(dry: DryRun & { affected: number }, pending: boolean): DryRunView {
  const resend = numberOf(dry.resend);
  const example = textOf(dry.example);
  const to = textOf(dry.to);
  return {
    countLine: tidy(fill(APPROVAL_TEXTS.countLine, { count: String(dry.affected), noun: nounFor(dry, dry.affected) })),
    field: '',
    before: example === '' ? '' : fill(APPROVAL_TEXTS.rerouteBefore, { example, from: textOf(dry.from) }),
    after: example === '' ? '' : fill(APPROVAL_TEXTS.rerouteAfter, { example, to }),
    eitherWay: '',
    resendLine:
      resend === undefined ? '' : resend === 1 ? fill(APPROVAL_TEXTS.rerouteCopyOne, { to }) : fill(APPROVAL_TEXTS.rerouteCopies, { count: String(resend), to }),
    nothingYet: pending ? APPROVAL_TEXTS.nothingYet : '',
  };
}

/** The dry run block of a request, or undefined when its dry run has no count. */
function dryRunView(approval: ApprovalPayload, pending: boolean, ctx: ApprovalContext): DryRunView | undefined {
  if (approval.fixKind === 'partner_warning') {
    return undefined;
  }
  if (approval.fixKind === 'suspend_item' || approval.fixKind === 'resume_item') {
    return itemDryRunView(approval, pending);
  }
  const dry = dryRunOf(approval);
  if (dry === undefined) {
    return undefined;
  }
  if (approval.fixKind === 'reroute') {
    return rerouteDryRunView(dry, pending);
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
    eitherWay: eitherWayOf(dry, resend, ctx),
    resendLine:
      resend === undefined ? '' : resend === 1 ? APPROVAL_TEXTS.resendCopyOne : fill(APPROVAL_TEXTS.resendCopies, { count: String(resend) }),
    nothingYet: pending ? APPROVAL_TEXTS.nothingYet : '',
  };
}

/** The lines of a setting request: the payload's dry run before and after, which hold the old and new texts. */
function settingView(approval: ApprovalPayload, pending: boolean): SettingView {
  const dry = approval.dryRun;
  const before = dry === null || typeof dry !== 'object' ? '' : textOf(dry.before);
  const after = dry === null || typeof dry !== 'object' ? '' : textOf(dry.after);
  return {
    now: fill(APPROVAL_TEXTS.settingNow, { old: before }),
    proposed: fill(APPROVAL_TEXTS.settingProposed, { new: after }),
    note: pending ? APPROVAL_TEXTS.settingNote : '',
  };
}

/** The card of a partner delay notice from the payload's dry run, or undefined when the dry run holds neither a notice nor a recipient. */
function partnerView(approval: ApprovalPayload, pending: boolean): PartnerView | undefined {
  const dry = approval.dryRun;
  if (dry === null || typeof dry !== 'object' || Array.isArray(dry)) {
    return undefined;
  }
  const recipients = (Array.isArray(dry.recipients) ? dry.recipients : []).map(textOf).filter((one) => one !== '');
  const notice = typeof dry.notice === 'string' ? dry.notice.trim() : '';
  if (notice === '' && recipients.length === 0) {
    return undefined;
  }
  return {
    to: fill(APPROVAL_TEXTS.partnerTo, { recipients: recipients.join(', ') }),
    notice,
    simulated: dry.simulated === true,
    note: pending ? APPROVAL_TEXTS.partnerNote : '',
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
    case 'cancelled':
      return textOf(approval.cancelledAt) !== '' && textOf(approval.server) !== ''
        ? { text: ctx.render('answered.canceled', { time: ctx.timeBeside(approval.cancelledAt ?? ''), server: textOf(approval.server) }), tone: 'rejected', icon: 'circle-slash' }
        : undefined;
    default:
      return undefined;
  }
}

/**
 * Everything the card draws for one approval payload. A request text (a tool call's, as the notice carried it) is the action as it
 * stands, and its first line, with a lower-case first letter, names the Approve and Reject buttons.
 */
export function approvalView(approval: ApprovalPayload, ctx: ApprovalContext, request = ''): ApprovalView {
  const ref = approval.ref ?? '';
  const pending = approval.state === 'pending';
  const isSetting = approval.kind === 'setting';
  const isPartner = approval.fixKind === 'partner_warning';
  const shownRequest = isSetting ? '' : request;
  const title = shownRequest === '' ? ctx.title(approval) : shownRequest.split('\n', 1)[0] ?? '';
  const dry = isSetting || isPartner ? undefined : dryRunOf(approval);
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
    cannotAnswer: pending && approval.answerable === false ? refusalText(approval.approverKind, ctx.render) : '',
    label: pending ? APPROVAL_TEXTS.labelPending : APPROVAL_TEXTS.labelAnswered,
    bar: barOf(approval.state),
    action: isSetting ? title : shownRequest === '' ? fill(APPROVAL_TEXTS.action, { title }) : shownRequest,
    approveName: fill(APPROVAL_TEXTS.approveName, { action: lowerFirst(title) }),
    rejectName: fill(APPROVAL_TEXTS.rejectName, { action: lowerFirst(title) }),
    fixedTargets,
    dryRun: isSetting ? undefined : dryRunView(approval, pending, ctx),
    setting: isSetting ? settingView(approval, pending) : undefined,
    partner: isPartner ? partnerView(approval, pending) : undefined,
    expiry: expires === '' ? '' : fill(APPROVAL_TEXTS.expires, { when: expires }),
    status: pending ? undefined : statusOf(approval, ctx),
  };
}

/** The catalog key that the refusal sentences start with; the fallback's own key. */
const REFUSAL_KEY = 'answered.notApprover';

/**
 * The sentence that tells a user why they can't answer a request of the approver kind (Story 25.5; the server's Live.Payload.Approval RefusalKey without its admin case): the
 * catalog's answered.notApprover plus the kind with its first letter in upper case when the kind is 1 to 32 lower-case letters or _ and the page's catalog has that key,
 * else the fallback "Only an approver can answer this request." (an empty, absent or unknown kind).
 */
export function refusalText(kind: string | undefined, render: PageRender): string {
  if (typeof kind === 'string' && /^[a-z_]{1,32}$/.test(kind)) {
    try {
      return render(REFUSAL_KEY + kind.charAt(0).toUpperCase() + kind.slice(1), {});
    } catch {
      // The page's catalog has no sentence for this kind: the fallback below.
    }
  }
  return render(REFUSAL_KEY, {});
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
 * - 404 is "no longer available", 403 not allowed (the server's message for the refusal, else the fallback sentence);
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

/** The band of a request's result: the catalog key, its text, the tone and icon of the band, and the audit line beneath it. */
export interface ResultView {
  /** The catalog key, `result.<name>`. */
  key: string;
  text: string;
  tone: 'success' | 'partial';
  icon: 'circle-check' | 'triangle-alert' | 'clock';
  /** "Recorded in the IRIS audit log.", shown beneath the band in caption. */
  audit: string;
}

/** The catalog's renderer (msg/catalog.ts renderPageText), which the page passes in. */
export type PageRender = (key: string, slots: Readonly<Record<string, unknown>>) => string;

/**
 * The result band of one request of the incident payload, or undefined when the request has no `result`. The first row that matches
 * wins (AD-16: a run that could not start is `resent` 0 with a reason):
 * - state `executing`: result.stillResending, partial, `clock`;
 * - `interrupted` above 0: result.interrupted (remaining = total less completed), partial, `triangle-alert`;
 * - `resent`, `completed`, `failedAgain` and `skipped` all 0 and a reason: result.couldNotStart, partial, `triangle-alert`;
 * - `unreached` above 0: result.stoppedPartway (notTried = unreached less 1, at least 0), partial, `triangle-alert`;
 * - `failedAgain` and `skipped` above 0: result.failedAndSkipped; `failedAgain` above 0: result.failedAgain; `skipped` above 0:
 *   result.skipped; all partial, `triangle-alert`;
 * - otherwise result.allThrough, success, `circle-check`.
 * A request of a kind the user asks for in the chat (Story 23.2) has its own bands, the texts of the chat's notice, because "went through" would hide what was done:
 * - a suspend or resume (fixKind suspend_item, resume_item; `item` of the request, `production` of the incident): `completed` above 0 is result.itemSuspended or
 *   result.itemResumed, success, `circle-check`; else `skipped` above 0 is result.itemSkipped (reason), partial, `triangle-alert`; else a reason is result.itemNotChanged,
 *   partial, `triangle-alert`. A run still going or interrupted, and a result that lacks the item, production or reason its text names, has no band (nothing is claimed);
 * - a reroute (fixKind reroute; `item` of the request is the target) whose copies all completed is result.rerouted (count = `total`, to), success, `circle-check`, in
 *   place of result.allThrough; with failures or skips it has the bands above.
 * - a partner delay notice (fixKind partner_warning, Story 23.5): `completed` equal to `total` and above 0 is "Sent to the Simulated mailbox.", success, `circle-check`; `completed`
 *   above 0 but below `total` is "Sent to the Simulated mailbox for {completed} of {total} contacts.", partial; a failed request whose reason is the kind's NOTSETUP reason is
 *   "Approved and kept as a draft: email delivery isn't set up yet.", partial; any other reason is "Not sent: {reason}.", partial; a request still executing, and one with no
 *   reason to give, has no band. The key of each is its catalog key, but the text is the card's own (APPROVAL_TEXTS).
 * A run still going reaches the page as `executing` with no result, so no band shows and the card's fixing line is its still-resending
 * state. The count is the result's `total`; the item noun is the incident's, else "message" and "messages". The catalog picks the count-of-one
 * forms and the noun's form from the strings given.
 */
export function resultView(request: IncidentRequest, itemNoun: ItemNoun | undefined, render: PageRender, production = ''): ResultView | undefined {
  const result = request.result;
  if (result === null || typeof result !== 'object' || Array.isArray(result)) {
    return undefined;
  }
  if (request.fixKind === 'suspend_item' || request.fixKind === 'resume_item') {
    return itemResultView(request, result, render, production);
  }
  if (request.fixKind === 'partner_warning') {
    return partnerResultView(request, result, render);
  }
  const total = numberOf(result.total) ?? 0;
  const resent = numberOf(result.resent) ?? 0;
  const completed = numberOf(result.completed) ?? 0;
  const failedAgain = numberOf(result.failedAgain) ?? 0;
  const skipped = numberOf(result.skipped) ?? 0;
  const interrupted = numberOf(result.interrupted) ?? 0;
  const unreached = numberOf(result.unreached) ?? 0;
  const reason = textOf(result.reason);
  const counts = {
    count: String(total),
    itemNoun: { one: textOf(itemNoun?.one) || APPROVAL_TEXTS.nounOne, other: textOf(itemNoun?.other) || APPROVAL_TEXTS.nounOther },
    completed: String(completed),
  };
  let key: string;
  let slots: Record<string, unknown>;
  let tone: ResultView['tone'] = 'partial';
  let icon: ResultView['icon'] = 'triangle-alert';
  if (request.state === 'executing') {
    key = 'result.stillResending';
    slots = counts;
    icon = 'clock';
  } else if (interrupted > 0) {
    key = 'result.interrupted';
    slots = { ...counts, remaining: String(total - completed) };
  } else if (resent === 0 && completed === 0 && failedAgain === 0 && skipped === 0 && reason !== '') {
    key = 'result.couldNotStart';
    slots = { reason };
  } else if (unreached > 0) {
    key = 'result.stoppedPartway';
    slots = { ...counts, resent: String(resent), notTried: String(Math.max(unreached - 1, 0)) };
  } else if (failedAgain > 0 && skipped > 0) {
    key = 'result.failedAndSkipped';
    slots = { ...counts, failedAgain: String(failedAgain), failReason: reason, skipped: String(skipped) };
  } else if (failedAgain > 0) {
    key = 'result.failedAgain';
    slots = { ...counts, failedAgain: String(failedAgain), failReason: reason };
  } else if (skipped > 0) {
    key = 'result.skipped';
    slots = { ...counts, skipped: String(skipped) };
  } else if (request.fixKind === 'reroute') {
    const to = textOf(request.item);
    if (to === '') {
      return undefined;
    }
    key = 'result.rerouted';
    slots = { count: counts.count, itemNoun: counts.itemNoun, to };
    tone = 'success';
    icon = 'circle-check';
  } else {
    key = 'result.allThrough';
    slots = { count: counts.count, itemNoun: counts.itemNoun };
    tone = 'success';
    icon = 'circle-check';
  }
  return bandOf(key, slots, tone, icon, render);
}

/** The band of a suspend or resume (Story 23.2): see resultView. */
function itemResultView(request: IncidentRequest, result: IncidentRequestResult, render: PageRender, production: string): ResultView | undefined {
  const item = textOf(request.item);
  const reason = textOf(result.reason);
  let key: string;
  let slots: Record<string, unknown>;
  let tone: ResultView['tone'] = 'partial';
  let icon: ResultView['icon'] = 'triangle-alert';
  if (request.state === 'executing' || (numberOf(result.interrupted) ?? 0) > 0) {
    return undefined;
  } else if ((numberOf(result.completed) ?? 0) > 0) {
    if (item === '' || production === '') {
      return undefined;
    }
    key = request.fixKind === 'resume_item' ? 'result.itemResumed' : 'result.itemSuspended';
    slots = { item, production };
    tone = 'success';
    icon = 'circle-check';
  } else if (reason === '') {
    return undefined;
  } else if ((numberOf(result.skipped) ?? 0) > 0) {
    if (item === '') {
      return undefined;
    }
    key = 'result.itemSkipped';
    slots = { item, reason };
  } else {
    key = 'result.itemNotChanged';
    slots = { reason };
  }
  return bandOf(key, slots, tone, icon, render);
}

/** The reason of a partner request that is kept as a draft: the kind's NOTSETUP (Fix.Kind.PartnerWarning). */
export const PARTNER_NOT_SET_UP = "email delivery isn't set up yet";

/** The band of a partner delay notice (Story 23.5): see resultView. */
function partnerResultView(request: IncidentRequest, result: IncidentRequestResult, render: PageRender): ResultView | undefined {
  const total = numberOf(result.total) ?? 0;
  const completed = numberOf(result.completed) ?? 0;
  const reason = textOf(result.reason).replace(/\.$/, '');
  let key: string;
  let text: string;
  let tone: ResultView['tone'] = 'partial';
  let icon: ResultView['icon'] = 'triangle-alert';
  if (request.state === 'executing') {
    return undefined;
  } else if (completed > 0 && completed >= total) {
    key = 'result.partnerSent';
    text = APPROVAL_TEXTS.partnerSent;
    tone = 'success';
    icon = 'circle-check';
  } else if (completed > 0) {
    key = 'result.partnerSentSome';
    text = fill(APPROVAL_TEXTS.partnerSentSome, { completed: String(completed), total: String(total) });
  } else if (request.state === 'failed' && reason === PARTNER_NOT_SET_UP) {
    key = 'result.partnerKept';
    text = APPROVAL_TEXTS.partnerKept;
  } else if (reason === '') {
    return undefined;
  } else {
    key = 'result.partnerNotSent';
    text = fill(APPROVAL_TEXTS.partnerNotSent, { reason });
  }
  return { key, text, tone, icon, audit: render('audit.recorded', {}) };
}

/** A band from its key, slots, tone and icon: the text from the renderer and the audit line beneath it. */
function bandOf(key: string, slots: Record<string, unknown>, tone: ResultView['tone'], icon: ResultView['icon'], render: PageRender): ResultView {
  return { key, text: render(key, slots), tone, icon, audit: render('audit.recorded', {}) };
}
