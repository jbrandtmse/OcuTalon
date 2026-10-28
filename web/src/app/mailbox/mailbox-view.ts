/**
 * The simulated mailbox's view model (Story 4.6): the fixed strings of the mailbox, the list it shows and the small rules of its rows
 * and its form. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides nothing (AD-12): an email's text, sender and subject are the server's and untrusted (AD-13), and its decision is the
 * server's `decision` event or the snapshot entry's own `decision` member.
 *
 * - mailOf(snapshot, store) is the mailbox's list, newest first, or undefined unless the snapshot says demo mode is on: the snapshot's
 *   `mailbox` (oldest first), then the store's mailbox events that the snapshot does not hold, in arrival order. A ref in both takes
 *   the store's payload, in the snapshot's place, and keeps the snapshot entry's `decision`.
 * - decisionOf(mail, decisions) is the email's decision: the first decide decision of the store with the email's itemId, else the
 *   entry's own; none for a sent email.
 * - The opened emails are kept per browser as a short list of refs (openedRefs, withOpened); the server records no reading.
 */
import type { StateSnapshot } from '../api/api-types';
import type { DecisionPayload, MailboxPayload } from '../live/payloads';

/** A mailbox entry of the snapshot: the `mailbox` payload, and its decide decision when the session has one. */
export type MailboxEntry = MailboxPayload & { decision?: DecisionPayload };

/** The snapshot as the mailbox reads it: `/state` carries `mailbox` only in demo mode. */
export type MailboxSnapshot = StateSnapshot & { mailbox?: MailboxEntry[] };

/** Every fixed string of the mailbox. The ellipsis is U+2026. */
export const MAILBOX_TEXTS = {
  caption: 'Send one and see what OcuTalon decides.',
  simulate: 'Simulate an incoming email',
  empty: 'No emails yet. Simulate an incoming email, or send a sample.',
  unread: 'Unread',
  deciding: 'Deciding\u2026',
  decided: "Email '{subject}': {outcome}",
  chipSuffix: ', send sample email',
  labelFrom: 'From',
  labelSubject: 'Subject',
  labelBody: 'Body',
  send: 'Send',
  back: 'Back',
  fromPrefill: 'Results Partner IT <it@results-partner.example>',
  errSubject: 'Enter a subject.',
  errBody: 'Enter a body.',
} as const;

/** The sample chips in order: the sample's name, which the server knows, and the chip's visible label. */
export const SAMPLES: readonly { name: string; label: string }[] = [
  { name: 'newsletter', label: 'Sample: newsletter' },
  { name: 'partner-notice', label: 'Sample: partner notice' },
  { name: 'suspicious-request', label: 'Sample: suspicious request' },
];

/** The browser-storage key of the opened emails. */
export const OPENED_KEY = 'ocutalon.mailbox.opened';

/** The most opened emails the list keeps. */
export const OPENED_MAX = 100;

/** The mailbox's list, newest first, or undefined when the snapshot is not loaded or demo mode is off. */
export function mailOf(snapshot: MailboxSnapshot | undefined, store: { mailboxes?: Readonly<Record<string, MailboxPayload>> } | undefined): MailboxEntry[] | undefined {
  if (snapshot === undefined || snapshot.demoMode !== true) {
    return undefined;
  }
  const live = store?.mailboxes ?? {};
  const inSnapshot = snapshot.mailbox ?? [];
  const known = new Set(inSnapshot.map((one) => one.ref ?? ''));
  const list: MailboxEntry[] = inSnapshot.map((one) => {
    const fresh = live[one.ref ?? ''];
    if (fresh === undefined) {
      return one;
    }
    return one.decision === undefined ? { ...fresh } : { ...fresh, decision: one.decision };
  });
  for (const [ref, payload] of Object.entries(live)) {
    if (!known.has(ref)) {
      list.push({ ...payload });
    }
  }
  return list.reverse();
}

/** The decision of an incoming email: the store's first decide decision with its itemId, else the entry's own; none for a sent email. */
export function decisionOf(mail: MailboxEntry, decisions: readonly DecisionPayload[] | undefined): DecisionPayload | undefined {
  const itemId = mail.itemId ?? '';
  if (mail.direction === 'out' || itemId === '') {
    return undefined;
  }
  return (decisions ?? []).find((one) => one.kind === 'decide' && one.itemId === itemId) ?? mail.decision;
}

/** The display name of "Name <address>", else the whole value. */
export function senderName(from: string | undefined): string {
  const value = (from ?? '').trim();
  const match = /^"?([^<>"]*?)"?\s*<[^<>]*>$/.exec(value);
  const name = match?.[1]?.trim() ?? '';
  return name === '' ? value : name;
}

/** True when the text is empty after the whitespace and control characters (C0, DEL and C1, as the server's check) are stripped. */
export function isBlank(text: string): boolean {
  // eslint-disable-next-line no-control-regex
  return text.replace(/[\s\u0000-\u001f\u007f-\u009f]/g, '') === '';
}

/** The field errors of the form: the subject's and the body's, each undefined when the field has text. */
export function fieldErrors(subject: string, body: string): { subject?: string; body?: string } {
  return {
    ...(isBlank(subject) ? { subject: MAILBOX_TEXTS.errSubject } : {}),
    ...(isBlank(body) ? { body: MAILBOX_TEXTS.errBody } : {}),
  };
}

/** The sample chip's accessible name: its label, which it starts with, then ", send sample email". */
export function chipName(label: string): string {
  return `${label}${MAILBOX_TEXTS.chipSuffix}`;
}

/** What is announced when an email arrives, still undecided: the decided pattern with "Deciding\u2026" as the outcome. */
export function arrivedText(subject: string): string {
  return decidedText(subject, MAILBOX_TEXTS.deciding);
}

/** What is announced when an email is decided: the outcome's label as the chip shows it. */
export function decidedText(subject: string, label: string): string {
  return MAILBOX_TEXTS.decided.replace(/\{(subject|outcome)\}/g, (_slot, name: string) => (name === 'subject' ? subject : label));
}

/** The refs of the opened emails in the stored text: space-separated, in the order they were opened; anything that is no ref is dropped. */
export function openedRefs(text: string): string[] {
  return text
    .split(' ')
    .filter((one) => /^[A-Za-z0-9_-]{1,64}$/.test(one))
    .slice(-OPENED_MAX);
}

/** The stored text with the ref added as the newest (a ref that is there moves to the end), at most OPENED_MAX refs. */
export function withOpened(text: string, ref: string): string {
  const refs = openedRefs(text).filter((one) => one !== ref);
  refs.push(ref);
  return refs.slice(-OPENED_MAX).join(' ');
}
