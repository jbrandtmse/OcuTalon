/**
 * The state of the Telegram card (Stories 12.8, 12.3, 12.4 and 12.5; UX-DR55, UX-DR56, UX-DR116, FR-18, FR-22): which of its views the rail shows
 * under the Telegram heading. A framework-free module: it imports only types and the QR library's ESM default, and uses only erasable
 * TypeScript syntax, so Node runs it as it is.
 *
 * - The card is paused exactly while the store holds the `telegramPaused` status condition as active: the same reading, of the same store,
 *   as the banner's (banners/banner-view.ts), so the card and the banner appear and leave on the same live update. The card never reads
 *   the snapshot's `telegram.pausedUntil`, which no event updates and which would keep a cleared pause on screen.
 * - Paused comes first, ahead of every other state, whatever the snapshot's Telegram state is (a restart during a pause records `off`).
 *   The paused view holds the retry line only: no link, no QR code, no code.
 * - The retry time is the banner's: the condition's `time` slot as the page shows a time (`format.time`, the browser's zone and hour
 *   format with no suffix). A missing or unreadable time gives an empty time, as the banner's own rule does.
 * - Then the card says "not set up" while the state is `off` or `rejected`, or while the server refused the page a code (a 409: the
 *   server's state is not `on`, though the snapshot says so).
 * - Then it is paired while the state is `on` and the session is paired, with or without a bot name: the `circle-check` icon, "Telegram
 *   paired {middle dot} {name}" (or "Telegram paired" alone when the name is empty) and a ghost "Unpair" button. A paired card whose state is `off`
 *   or `rejected` says "not set up", because nothing reaches the chat then.
 * - Then, for `JUST_UNPAIRED_MS` after the store's `paired` turned from true to false (the card holds that as `justUnpaired`), it is
 *   just unpaired (UX-DR14, UX-DR56): the `circle-slash` icon and "Telegram unpaired" in one row, with no button, link, QR code or code.
 *   Paused, not set up and paired all come ahead of it, so a pairing during the window shows the paired view.
 * - Then it shows nothing while the state is `on` with no bot name, or while it holds no code yet.
 * - Otherwise it is unpaired: the QR code and the "Open in Telegram" link of `https://t.me/<bot>?start=<code>`, and "New code in {n} min".
 *   `asksForCode` is the condition under which the card asks for a code at all.
 *
 * The code's lifetime on the page: a code that arrives at browser time `receivedAt` is due at the earlier of its `expiresAt` and ten
 * minutes after `receivedAt` (FR-18), so a browser clock behind the server's does not keep a dead code, and a delay never exceeds the
 * ten minutes. `{n}` is the whole minutes left, rounded down and never below 1.
 */
import qrcode from 'qrcode-generator';

import type { TelegramState } from '../../api/api-types';
import type { StatusPayload } from '../../live/payloads';

/** The card's fixed texts. The two for the not-set-up view are RAIL_TEXTS' (rail/rail-view.ts). */
export const TELEGRAM_CARD_TEXTS = {
  paused: 'Telegram paused',
  tryingAgainAt: 'Trying again at {time}',
  scan: "Scan with your phone's camera, then tap Start in Telegram.",
  open: 'Open in Telegram',
  opensTelegram: '(opens Telegram)',
  newCodeIn: 'New code in {n} min',
  qrAlt: 'QR code that opens OcuTalon in Telegram to pair this session',
  paired: 'Telegram paired \u00b7 {name}',
  pairedAlone: 'Telegram paired',
  unpair: 'Unpair',
  unpairLabel: 'Unpair Telegram',
  unpaired: 'Telegram unpaired',
} as const;

/** How long the just-unpaired view shows, in milliseconds: UX-DR14's five seconds. */
export const JUST_UNPAIRED_MS = 5_000;

/** How long a code lives on the page at most, in milliseconds: FR-18's ten minutes. */
export const CODE_LIFETIME_MS = 600_000;

/** The least time between two requests for a code, in milliseconds. */
export const CODE_SPACING_MS = 10_000;

/** How long the card waits after a failed request before it asks again, in milliseconds. */
export const CODE_RETRY_MS = 30_000;

/** The condition that pauses the card. */
const PAUSED_CONDITION = 'telegramPaused';

/** The values the view reuses from the page's other modules. */
export interface TelegramCardFormat {
  /** The hour and minute of a UTC time in the browser's zone and hour format, with no zone name; "" when it is unreadable (pageTime). */
  time(iso: string): string;
}

/** A code the card holds: the code and the browser time (milliseconds since the epoch) at which it is due for replacement. */
export interface HeldCode {
  code: string;
  due: number;
}

/**
 * What the card itself knows: its held code, whether the last answer was a refusal (409), whether the pairing has just ended
 * (`justUnpaired`, for JUST_UNPAIRED_MS), and the browser time now (milliseconds).
 */
export interface CardOwn {
  code: HeldCode | undefined;
  refused: boolean;
  justUnpaired: boolean;
  now: number;
}

/**
 * The view of the card: paused, not set up, paired, just unpaired, unpaired or nothing. `retry` is the paused view's "Trying again at {time}" line, and ""
 * in the other views. `paired` is the paired view's line, "" in the other views. `link` is the unpaired view's pairing link and `minutes`
 * its {n}; they are "" and 0 in the other views.
 */
export interface TelegramCardView {
  kind: 'paused' | 'not-set-up' | 'paired' | 'just-unpaired' | 'unpaired' | 'none';
  retry: string;
  paired: string;
  link: string;
  minutes: number;
}

/** True when the store holds the condition as active (the expression of the banner's `holds`). */
function holds(status: Readonly<Record<string, StatusPayload>>, condition: string): boolean {
  return Object.hasOwn(status, condition) && status[condition]?.active === true;
}

/** True while the store holds the pause, the banner's reading. */
export function telegramPaused(status: Readonly<Record<string, StatusPayload>> | undefined): boolean {
  return status !== undefined && holds(status, PAUSED_CONDITION);
}

/** True when the card asks for a code: the bot is on and has a name, the session is unpaired, and the card is not paused. */
export function asksForCode(telegram: Pick<TelegramState, 'state' | 'botUserName' | 'paired'>, status: Readonly<Record<string, StatusPayload>> | undefined): boolean {
  return telegram.state === 'on' && telegram.botUserName !== '' && !telegram.paired && !telegramPaused(status);
}

/** The link that the QR code and the "Open in Telegram" link share. */
export function pairingLink(botUserName: string, code: string): string {
  return `https://t.me/${botUserName}?start=${code}`;
}

/** When a code is due: the earlier of its expiry and ten minutes after the browser received it. An unreadable expiry is due at once. */
export function dueTime(expiresAt: string, receivedAt: number): number {
  const expires = Date.parse(expiresAt);
  return Math.min(Number.isNaN(expires) ? receivedAt : expires, receivedAt + CODE_LIFETIME_MS);
}

/** The {n} of "New code in {n} min": whole minutes left, rounded down, never below 1. */
export function minutesLeft(due: number, now: number): number {
  return Math.max(1, Math.floor((due - now) / 60_000));
}

/** The symbol of a link: the side of the square in modules, and one path of a unit square per dark module, row by row. */
export interface QrSymbol {
  size: number;
  path: string;
}

/** The QR symbol of a text, with error correction M and the smallest version that fits. The library's own SVG builders draw black and are not used. */
export function qrSymbol(text: string): QrSymbol {
  const code = qrcode(0, 'M');
  code.addData(text);
  code.make();
  const size = code.getModuleCount();
  let path = '';
  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) {
      if (code.isDark(row, col)) path += `M${col} ${row}h1v1h-1z`;
    }
  }
  return { size, path };
}

/** The card's view, from the snapshot's Telegram block, the store's status conditions, what the card itself holds and the page's time format. */
export function telegramCardView(
  telegram: Pick<TelegramState, 'state' | 'botUserName' | 'paired' | 'displayName'>,
  status: Readonly<Record<string, StatusPayload>> | undefined,
  own: CardOwn,
  format: TelegramCardFormat,
): TelegramCardView {
  if (status !== undefined && telegramPaused(status)) {
    const time = status[PAUSED_CONDITION]?.slots?.time;
    return { kind: 'paused', retry: TELEGRAM_CARD_TEXTS.tryingAgainAt.replace('{time}', typeof time === 'string' ? format.time(time) : ''), paired: '', link: '', minutes: 0 };
  }
  if (telegram.state === 'off' || telegram.state === 'rejected' || own.refused) return { kind: 'not-set-up', retry: '', paired: '', link: '', minutes: 0 };
  if (telegram.state === 'on' && telegram.paired) {
    const line = telegram.displayName === '' ? TELEGRAM_CARD_TEXTS.pairedAlone : TELEGRAM_CARD_TEXTS.paired.replace('{name}', () => telegram.displayName);
    return { kind: 'paired', retry: '', paired: line, link: '', minutes: 0 };
  }
  if (own.justUnpaired) return { kind: 'just-unpaired', retry: '', paired: '', link: '', minutes: 0 };
  if (telegram.state !== 'on' || telegram.botUserName === '' || own.code === undefined) {
    return { kind: 'none', retry: '', paired: '', link: '', minutes: 0 };
  }
  return { kind: 'unpaired', retry: '', paired: '', link: pairingLink(telegram.botUserName, own.code.code), minutes: minutesLeft(own.code.due, own.now) };
}
