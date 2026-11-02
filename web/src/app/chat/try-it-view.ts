/**
 * The texts and the in-flight reader of the "Try it yourself" row (Story 4.10; EXPERIENCE: Demo guide and controls). A framework-free
 * module: it imports only types, so Node runs it as it is and the strings and scenario tests read it. The prompts are the exact text
 * that a press sends, and each has its own prompt scenario of the CI mock under ci/mock/scenarios/B.
 */
import type { LiveItem } from '../api/api-types';
import type { OutboxEntry } from './chat-view';

/** The row's label and its four prompts, in the order the row shows them. */
export const TRY_IT_TEXTS = {
  label: 'Try it yourself',
  prompts: ['Which productions are running?', 'Is anything wrong right now?', 'What was that failure earlier?', 'What can you do?'],
} as const;

/**
 * True while a turn of the session is in flight: an outbox entry of this page that is sending or sent (posted, and the store does not
 * hold its message yet), or a chat message of the session's store that is queued or running, whatever its channel. A failed entry is
 * not in flight.
 */
export function turnInFlight(chat: readonly LiveItem[], outbox: readonly OutboxEntry[]): boolean {
  if (outbox.some((entry) => entry.status === 'sending' || entry.status === 'sent')) {
    return true;
  }
  return chat.some((item) => item.type === 'chat.message' && (item.payload.state === 'queued' || item.payload.state === 'running'));
}
