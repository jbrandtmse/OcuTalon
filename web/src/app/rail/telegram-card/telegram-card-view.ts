/**
 * The state of the Telegram card (Story 12.8; UX-DR56, UX-DR116, FR-22): which of its views the rail shows under the Telegram heading. A
 * framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - The card is paused exactly while the store holds the `telegramPaused` status condition as active: the same reading, of the same store,
 *   as the banner's (banners/banner-view.ts), so the card and the banner appear and leave on the same live update. The card never reads
 *   the snapshot's `telegram.pausedUntil`, which no event updates and which would keep a cleared pause on screen.
 * - Paused comes first, ahead of every other state, whatever the snapshot's Telegram state is (a restart during a pause records `off`).
 *   The paused view holds the retry line only: no link, no QR code, no code.
 * - The retry time is the banner's: the condition's `time` slot as the page shows a time (`format.time`, the browser's zone and hour
 *   format with no suffix). A missing or unreadable time gives an empty time, as the banner's own rule does.
 * - Otherwise the card says "not set up" while the state is `off` or `rejected`, and shows nothing for the other states (Stories 12.3 and
 *   12.4 add theirs below paused).
 */
import type { TelegramState } from '../../api/api-types';
import type { StatusPayload } from '../../live/payloads';

/** The card's fixed texts. The two for the not-set-up view are RAIL_TEXTS' (rail/rail-view.ts). */
export const TELEGRAM_CARD_TEXTS = {
  paused: 'Telegram paused',
  tryingAgainAt: 'Trying again at {time}',
} as const;

/** The condition that pauses the card. */
const PAUSED_CONDITION = 'telegramPaused';

/** The values the view reuses from the page's other modules. */
export interface TelegramCardFormat {
  /** The hour and minute of a UTC time in the browser's zone and hour format, with no zone name; "" when it is unreadable (pageTime). */
  time(iso: string): string;
}

/** The view of the card: paused, not set up, or nothing. `retry` is the paused view's "Trying again at {time}" line, and "" otherwise. */
export interface TelegramCardView {
  kind: 'paused' | 'not-set-up' | 'none';
  retry: string;
}

/** True when the store holds the condition as active (the expression of the banner's `holds`). */
function holds(status: Readonly<Record<string, StatusPayload>>, condition: string): boolean {
  return Object.hasOwn(status, condition) && status[condition]?.active === true;
}

/** The card's view, from the snapshot's Telegram block, the store's status conditions and the page's time format. */
export function telegramCardView(
  telegram: Pick<TelegramState, 'state'>,
  status: Readonly<Record<string, StatusPayload>> | undefined,
  format: TelegramCardFormat,
): TelegramCardView {
  if (status !== undefined && holds(status, PAUSED_CONDITION)) {
    const time = status[PAUSED_CONDITION]?.slots?.time;
    return { kind: 'paused', retry: TELEGRAM_CARD_TEXTS.tryingAgainAt.replace('{time}', typeof time === 'string' ? format.time(time) : '') };
  }
  return { kind: telegram.state === 'off' || telegram.state === 'rejected' ? 'not-set-up' : 'none', retry: '' };
}
