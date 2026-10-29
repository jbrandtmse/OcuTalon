/**
 * The simulated phone's view model (Story 4.5): the fixed strings of the phone, the list it shows and whether an approval request is
 * pending on screen. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides nothing (AD-12): the text of a message is the server's, rendered once (AD-32), and the page never edits it.
 *
 * - phoneOf(snapshot, store) is the phone's list, or undefined unless the snapshot says demo mode is on, whatever else it carries: the
 *   snapshot's `phone` in its order, then the store's phone messages that the snapshot does not hold, in arrival order. A ref in both
 *   takes the store's payload, in the snapshot's place.
 * - pendingApproval(list, approvals) is true when a message names an approval request that is pending and has no answer line;
 *   pendingRef(list, approvals) is the ref of the newest such message (Story 4.7: where the guide's Show me puts focus).
 * - requestView(message, approval, local, ctx) is what a request message draws (Story 6.3; AD-32): its text split into blocks (the
 *   one that holds the dry run's example marked as an inset, with the example's before and after values as parts of their own),
 *   whether Approve and Reject show, the answer line that replaces them, and the buttons' names. A message has buttons only when
 *   it names a request (`approvalRef`, which the server stores for the kinds incident and approval only) and has no answer, from
 *   the server or from the phone's own press: the buttons never come from the approvals store, and the phone never follows the
 *   store's `approval` event, only the server's edit of its message and its own press.
 */
import type { StateSnapshot } from '../api/api-types';
import type { ApprovalView } from '../approvals/approval-view';
import type { ApprovalPayload, PhonePayload } from '../live/payloads';

/** The snapshot as the phone reads it: `/state` carries `phone` only in demo mode. */
export type PhoneSnapshot = StateSnapshot & { phone?: PhonePayload[] };

/** Every fixed string of the phone. */
export const PHONE_TEXTS = {
  name: 'OcuTalon',
  empty: "Notifications, reminders and approval requests appear here. The simulated phone is a real channel in the production; you'll see it in the trace.",
} as const;

/** The phone's list, or undefined when the snapshot is not loaded or demo mode is off. */
export function phoneOf(snapshot: PhoneSnapshot | undefined, store: { phones?: Readonly<Record<string, PhonePayload>> } | undefined): PhonePayload[] | undefined {
  if (snapshot === undefined || snapshot.demoMode !== true) {
    return undefined;
  }
  const live = store?.phones ?? {};
  const inSnapshot = snapshot.phone ?? [];
  const known = new Set(inSnapshot.map((one) => one.ref ?? ''));
  const list = inSnapshot.map((one) => live[one.ref ?? ''] ?? one);
  for (const [ref, payload] of Object.entries(live)) {
    if (!known.has(ref)) {
      list.push(payload);
    }
  }
  return list;
}

/** True when the message has an answer line of the server's: the buttons are gone. */
const answered = (one: PhonePayload): boolean => (one.answer ?? '') !== '';

/** The ref of the newest message of the list that names an approval request the store holds as pending and that has no answer line; undefined with none. */
export function pendingRef(list: readonly PhonePayload[], approvals: Readonly<Record<string, { state?: string }>> | undefined): string | undefined {
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const one = list[i];
    const approval = one?.approvalRef ?? '';
    if (one !== undefined && approval !== '' && !answered(one) && approvals?.[approval]?.state === 'pending') {
      return one.ref ?? '';
    }
  }
  return undefined;
}

/** True when a message of the list names an approval request that the store holds as pending and that has no answer line. */
export function pendingApproval(list: readonly PhonePayload[], approvals: Readonly<Record<string, { state?: string }>> | undefined): boolean {
  return pendingRef(list, approvals) !== undefined;
}

/** One run of a block's text: plain, or the dry run's example value before the fix (before) or after it (after). */
export interface BlockPart {
  text: string;
  kind: 'plain' | 'before' | 'after';
}

/** One paragraph of a message's text. The inset holds the dry run's example: the page sets it on `surface`, with its values in mono. */
export interface RequestBlock {
  inset: boolean;
  /** The block's text, whole. */
  text: string;
  /** The same text in runs, in order: a plain block is one plain run. */
  parts: BlockPart[];
}

/** The answer line that replaces the buttons: its text, its tone (ink) and its icon (none for an answer of unknown state). */
export interface RequestAnswer {
  text: string;
  tone: 'approved' | 'rejected' | 'expired' | 'neutral';
  icon: 'circle-check' | 'circle-slash' | 'clock' | undefined;
}

/** What the page reads of a request: the approval view of a payload (approval-view.ts approvalView, with the phone's message context). */
export interface RequestContext {
  viewOf(approval: ApprovalPayload): ApprovalView;
}

/** Everything one request message draws, apart from its caption time. */
export interface RequestView {
  blocks: RequestBlock[];
  /** True when Approve and Reject show: the message names a request and has no answer, the server's or the phone's own. */
  buttons: boolean;
  /** The answer line, or undefined while the message has buttons. */
  answer: RequestAnswer | undefined;
  approveName: string;
  rejectName: string;
}

/** The names of the buttons for a request the page has no payload for. */
export const REQUEST_NAMES = { approve: 'Approve', reject: 'Reject' } as const;

/** A string with something in it, else "". */
const textOf = (value: unknown): string => (typeof value === 'string' ? value.trim() : '');

/** The text's blocks: split at blank lines; the block that holds "{field} {before} becomes {after}" of the dry run is the inset. */
function blocksOf(text: string, approval: ApprovalPayload | undefined): RequestBlock[] {
  const dry = approval?.dryRun;
  const field = textOf(dry?.field);
  const before = textOf(dry?.before);
  const after = textOf(dry?.after);
  const needle = field === '' || before === '' || after === '' ? '' : `${field} ${before} becomes ${after}`;
  return text.split(/\n{2,}/).map((block) => {
    const at = needle === '' ? -1 : block.indexOf(needle);
    if (at < 0) {
      return { inset: false, text: block, parts: [{ text: block, kind: 'plain' }] };
    }
    const beforeAt = at + field.length + 1;
    const afterAt = beforeAt + before.length + ' becomes '.length;
    const runs: BlockPart[] = [
      { text: block.slice(0, beforeAt), kind: 'plain' },
      { text: before, kind: 'before' },
      { text: ' becomes ', kind: 'plain' },
      { text: after, kind: 'after' },
      { text: block.slice(afterAt + after.length), kind: 'plain' },
    ];
    return { inset: true, text: block, parts: runs.filter((run) => run.text !== '') };
  });
}

/**
 * What a request message draws. `approval` is the store's payload for the message's request (undefined when the store has none:
 * the snapshot holds pending requests only), `local` the request as the phone's own press showed it, `ctx` the page's reading of
 * a payload in message form. The answer line is the server's `answer` first, else the local view's status; its tone and icon
 * come from the local view, else from the store's state, else it is neutral with no icon.
 */
export function requestView(message: PhonePayload, approval: ApprovalPayload | undefined, local: ApprovalPayload | undefined, ctx: RequestContext): RequestView {
  const named = approval === undefined ? undefined : ctx.viewOf(approval);
  const asked = (message.approvalRef ?? '') !== '';
  const server = textOf(message.answer);
  const localStatus = local === undefined ? undefined : ctx.viewOf(local).status;
  let answer: RequestAnswer | undefined;
  if (server !== '') {
    const status = localStatus ?? named?.status;
    answer = { text: server, tone: status?.tone ?? 'neutral', icon: status?.icon };
  } else if (localStatus !== undefined) {
    answer = { text: localStatus.text, tone: localStatus.tone, icon: localStatus.icon };
  }
  return {
    blocks: blocksOf(message.text ?? '', approval),
    buttons: asked && answer === undefined && local === undefined,
    answer,
    approveName: named?.approveName ?? REQUEST_NAMES.approve,
    rejectName: named?.rejectName ?? REQUEST_NAMES.reject,
  };
}
