/**
 * What the "This was noise" control shows (Story 41.5; FR-72): its texts and where it shows. A framework-free module: it imports only
 * types and uses only erasable TypeScript syntax, so Node runs it as it is.
 * - The control shows on a notice of kind `tellnow` whose served decision has a Ref (act decisions arrive as kind `tellnow` too), and on a
 *   phone message that has a `decisionRef` and no `approvalRef`. It shows on no other notice, request card, reply or turn.
 */
import type { PhonePayload } from '../live/payloads';
import type { NoticeView } from './chat-view';

/** The fixed strings of the control (EXPERIENCE: "This was noise"); `{time}` is the first mark's time. */
export const NOISE_TEXTS = {
  label: 'This was noise',
  marked: 'Marked as noise at {time}. Similar items will take this into account.',
} as const;

/** The decision Ref the control acts on for a notice of the chat: "" unless the notice is a tell now with a decision that has a Ref. */
export function noticeNoiseRef(notice: NoticeView): string {
  return notice.kind === 'tellnow' ? (notice.decision?.ref ?? '') : '';
}

/** The decision Ref the control acts on for a phone message: its `decisionRef`, "" when it names an approval request or has none. */
export function phoneNoiseRef(message: PhonePayload): string {
  return message.approvalRef ? '' : (message.decisionRef ?? '');
}

/** The status line that replaces the button: the first mark's time, as `timeBeside` writes it for the zone, in the text. */
export function markedLine(markedAt: string, zone: string, timeBeside: (iso: string, zone: string) => string): string {
  const time = timeBeside(markedAt, zone);
  return NOISE_TEXTS.marked.replace('{time}', () => time);
}
