/**
 * The simulated phone's view model (Story 4.5): the fixed strings of the phone, the list it shows and whether an approval request is
 * pending on screen. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides nothing (AD-12): the text of a message is the server's, rendered once (AD-32), and the page never edits it.
 *
 * - phoneOf(snapshot, store) is the phone's list, or undefined unless the snapshot says demo mode is on, whatever else it carries: the
 *   snapshot's `phone` in its order, then the store's phone messages that the snapshot does not hold, in arrival order. A ref in both
 *   takes the store's payload, in the snapshot's place.
 * - pendingApproval(list, approvals) is true when a message names an approval request that is pending.
 */
import type { StateSnapshot } from '../api/api-types';
import type { PhonePayload } from '../live/payloads';

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

/** True when a message of the list names an approval request that the store holds as pending. */
export function pendingApproval(list: readonly PhonePayload[], approvals: Readonly<Record<string, { state?: string }>> | undefined): boolean {
  return list.some((one) => {
    const ref = one.approvalRef ?? '';
    return ref !== '' && approvals?.[ref]?.state === 'pending';
  });
}
