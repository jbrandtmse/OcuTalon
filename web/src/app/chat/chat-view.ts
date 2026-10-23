/**
 * The chat panel's view model (Story 2.5): the fixed strings of the panel, the client ids of the messages the page sends, and
 * the entries to render from the live store's chat and the page's own outbox. A framework-free module: it imports only types
 * and uses only erasable TypeScript syntax, so Node runs it as it is. The components call parseReply, renderPageText and
 * pageTime themselves.
 *
 * - chatView lists the store's chat.message entries in store order, then the page's own messages that the store does not hold
 *   yet, in send order. A local message is gone as soon as the store holds a chat.message with its clientId, whatever its
 *   status was. Incident and notice entries render nothing yet (Stories 6.1 and 2.7).
 * - A turn's reply is none (no indicator: the post is in flight or failed), deciding (the post was accepted, or the turn is
 *   queued), working (the turn is running; with the whole seconds once the page has seen it running for ELAPSED_AFTER_MS, and
 *   with the label of the step the bridge reported for it), the reply text, or a fallback by its catalog key and reason.
 * - A turn has a decision strip when its chat.message carries a decision or its reply is a fallback; the newest such turn of the
 *   chat shows three reason lines and the others one. The strip's fallback state, the turn's cost and its check rows come from
 *   the same chat.message.
 * - indicatorOf says what the turn indicator shows for a reply: the text, the form it is spoken in and whether the dots animate.
 */
import type { LiveItem } from '../api/api-types';
import type { ChatMessagePayload, CheckRow, Cost, DecisionPayload, TurnStepPayload } from '../live/payloads';

/** Every fixed string of the panel. The ellipsis is U+2026, the middle dot U+00B7. */
export const CHAT_TEXTS = {
  composerLabel: 'Message OcuTalon',
  composerPlaceholder: 'Message OcuTalon',
  send: 'Send',
  notSent: 'Not sent',
  retrySending: 'Retry sending',
  deciding: 'Deciding\u2026',
  working: 'Working\u2026',
  workingElapsed: 'Working \u00B7 {n} s',
  workingElapsedSpoken: 'Working \u00B7 {n} seconds',
  stepWorking: '{label}\u2026',
  stepElapsed: '{label} \u00B7 {n} s',
  stepElapsedSpoken: '{label} \u00B7 {n} seconds',
  seconds: '{n} seconds',
  newMessages: 'New messages',
  name: 'OcuTalon',
  viaTelegram: 'via Telegram',
  fromGuide: 'From the demo guide',
  separator: ' \u00B7 ',
  opensInNewTab: '(opens in a new tab)',
  emptyHeadline: 'For everything that arrives, OcuTalon makes one attention decision',
  emptyWatches: 'It watches your productions from inside IRIS, and every decision is a production message you can trace.',
  emptyRisky: 'Anything risky waits for your approval.',
  emptyAsk: 'Ask OcuTalon to watch a production, set a reminder, or say what you need.',
  chipIgnore: 'Ignore',
  chipDigest: 'Digest',
  chipTellNow: 'Tell now',
  chipAct: 'Act',
  meaningIgnore: 'Recorded; nobody notified',
  meaningDigest: 'Saved for later; nobody notified now',
  meaningTellNow: 'Needs you now',
  meaningAct: 'OcuTalon took or requested an action',
} as const;

/** How long the page must have seen a turn running before the indicator adds the elapsed seconds. */
export const ELAPSED_AFTER_MS = 10_000;

/** The status of a message the page sent: the post is in flight, was accepted (202), or failed. */
export type OutboxStatus = 'sending' | 'sent' | 'failed';

/** A message this page sent. sentAt is an ISO time. */
export interface OutboxEntry {
  clientId: string;
  text: string;
  fromGuide: boolean;
  sentAt: string;
  status: OutboxStatus;
}

/** What stands in a turn's reply place. */
export type ReplyView =
  | { kind: 'none' }
  | { kind: 'deciding' }
  | { kind: 'working'; seconds?: number; step?: string }
  | { kind: 'text'; replyText: string }
  | { kind: 'fallback'; catalogKey: string; fallbackReason: string };

/** One message and what answers it. send is stored for a message the server holds. */
export interface TurnView {
  /** The clientId when the message has one, else the turn's ref: the same for a local message and its stored turn. */
  key: string;
  text: string;
  /** An ISO time: the turn's createdAt, or the local sentAt until the stored turn arrives. */
  time: string;
  /** "via Telegram", "From the demo guide" or "". */
  caption: string;
  send: OutboxStatus | 'stored';
  reply: ReplyView;
  /** The decision the turn shows (the triage decision, or the reply decision of a fallback), when its chat.message carries one. */
  decision?: DecisionPayload;
  /** The cost of the whole turn, with the decision. */
  turnCost?: Cost;
  /** The fallback reason of the strip, set when the strip is a fallback strip: the turn's own for a fallback reply, else the decision's. */
  fallbackReason?: string;
  /** True when the turn has a decision strip: it has a decision, or its reply is a fallback. */
  strip: boolean;
  /** True for the last turn of the chat that has a strip. */
  newest: boolean;
  /** The catalog key of the check results of the reply. */
  checkKey?: string;
  /** The check results of the reply, one row each. */
  checks?: readonly CheckRow[];
}

/** What the turn indicator shows: the text, the text it is spoken as, the whole seconds once past 10 s, and whether the dots animate. */
export interface IndicatorView {
  text: string;
  spoken: string;
  seconds?: number;
  dots: boolean;
}

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** A new client id: 16 random bytes as 22 base64url characters (the Identifiers convention). */
export function newClientId(
  random: (bytes: Uint8Array<ArrayBuffer>) => Uint8Array = (bytes) => globalThis.crypto.getRandomValues(bytes),
): string {
  const bytes = random(new Uint8Array(16));
  let id = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const group = ((bytes[i] ?? 0) << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    const chars = Math.min(4, Math.ceil(((bytes.length - i) * 8) / 6));
    for (let j = 0; j < chars; j += 1) {
      id += ALPHABET[(group >> (18 - 6 * j)) & 63];
    }
  }
  return id;
}

/** The chat.message payload of a chat entry, or undefined for any other type. */
function messageOf(item: LiveItem): ChatMessagePayload | undefined {
  return item.type === 'chat.message' ? item.payload : undefined;
}

/** The key of a stored turn. */
function keyOf(message: ChatMessagePayload): string {
  return message.clientId || message.ref || '';
}

/** The label of the step a running turn is at, trimmed; "" when the store holds none for it. */
function stepOf(message: ChatMessagePayload, steps: Readonly<Record<string, TurnStepPayload>>): string {
  const ref = message.ref ?? '';
  if (ref === '' || !Object.hasOwn(steps, ref)) {
    return '';
  }
  const label = steps[ref]?.label;
  return typeof label === 'string' ? label.trim() : '';
}

/** The reply of a stored turn. */
function replyOf(
  message: ChatMessagePayload,
  key: string,
  runningSince: ReadonlyMap<string, number>,
  now: number,
  steps: Readonly<Record<string, TurnStepPayload>>,
): ReplyView {
  switch (message.state) {
    case 'queued':
      return { kind: 'deciding' };
    case 'running': {
      const step = stepOf(message, steps);
      const since = runningSince.get(key);
      const reply: { kind: 'working'; seconds?: number; step?: string } = { kind: 'working' };
      if (since !== undefined && now - since >= ELAPSED_AFTER_MS) {
        reply.seconds = Math.floor((now - since) / 1000);
      }
      if (step !== '') {
        reply.step = step;
      }
      return reply;
    }
    case 'done':
      if (message.catalogKey) {
        return { kind: 'fallback', catalogKey: message.catalogKey, fallbackReason: message.fallbackReason ?? '' };
      }
      return message.replyText ? { kind: 'text', replyText: message.replyText } : { kind: 'none' };
    default:
      return { kind: 'none' };
  }
}

/** The caption of a message: Telegram's, else the guide's, else none. */
function captionOf(channel: string | undefined, fromGuide: boolean | undefined): string {
  if (channel === 'telegram') {
    return CHAT_TEXTS.viaTelegram;
  }
  return fromGuide ? CHAT_TEXTS.fromGuide : '';
}

/**
 * The entries to render. runningSince holds, by key, when (ms, the page's clock) the page first saw each turn running; now is
 * the page's clock in ms; steps are the store's turn steps by the ref of the running turn.
 */
export function chatView(
  chat: readonly LiveItem[],
  outbox: readonly OutboxEntry[],
  runningSince: ReadonlyMap<string, number>,
  now: number,
  steps: Readonly<Record<string, TurnStepPayload>> = {},
): TurnView[] {
  const views: TurnView[] = [];
  const held = new Set<string>();
  for (const item of chat) {
    const message = messageOf(item);
    if (message === undefined) {
      continue;
    }
    const key = keyOf(message);
    if (message.clientId) {
      held.add(message.clientId);
    }
    const reply = replyOf(message, key, runningSince, now, steps);
    const view: TurnView = {
      key,
      text: message.text ?? '',
      time: message.createdAt ?? '',
      caption: captionOf(message.channel, message.fromGuide),
      send: 'stored',
      reply,
      strip: false,
      newest: false,
    };
    const decision = message.decision;
    if (decision !== undefined) {
      view.decision = decision;
      if (message.turnCost !== undefined) {
        view.turnCost = message.turnCost;
      }
    }
    if (reply.kind === 'fallback') {
      view.fallbackReason = reply.fallbackReason;
    } else if (decision?.fallback) {
      view.fallbackReason = decision.fallbackReason ?? '';
    }
    view.strip = decision !== undefined || reply.kind === 'fallback';
    if (message.checkKey) {
      view.checkKey = message.checkKey;
    }
    if (message.checks !== undefined && message.checks.length > 0) {
      view.checks = message.checks;
    }
    views.push(view);
  }
  for (const entry of outbox) {
    if (held.has(entry.clientId)) {
      continue;
    }
    views.push({
      key: entry.clientId,
      text: entry.text,
      time: entry.sentAt,
      caption: captionOf(undefined, entry.fromGuide),
      send: entry.status,
      reply: entry.status === 'sent' ? { kind: 'deciding' } : { kind: 'none' },
      strip: false,
      newest: false,
    });
  }
  for (let i = views.length - 1; i >= 0; i -= 1) {
    const view = views[i];
    if (view?.strip) {
      view.newest = true;
      break;
    }
  }
  return views;
}

/**
 * What the turn indicator shows for a reply, or undefined when the reply is not in progress. Deciding and Working end in the
 * animated ellipsis, and a step label stands in place of the word Working in the same way. From 10 s on the whole seconds replace
 * the ellipsis, after a middle dot, and the spoken form says "seconds" in full.
 */
export function indicatorOf(reply: ReplyView): IndicatorView | undefined {
  if (reply.kind === 'deciding') {
    return { text: CHAT_TEXTS.deciding.slice(0, -1), spoken: CHAT_TEXTS.deciding, dots: true };
  }
  if (reply.kind !== 'working') {
    return undefined;
  }
  const label = reply.step;
  if (reply.seconds === undefined) {
    if (label === undefined) {
      return { text: CHAT_TEXTS.working.slice(0, -1), spoken: CHAT_TEXTS.working, dots: true };
    }
    return { text: label, spoken: CHAT_TEXTS.stepWorking.replace('{label}', () => label), dots: true };
  }
  const n = String(reply.seconds);
  if (label === undefined) {
    return { text: CHAT_TEXTS.workingElapsed.replace('{n}', n), spoken: CHAT_TEXTS.workingElapsedSpoken.replace('{n}', n), seconds: reply.seconds, dots: false };
  }
  return {
    text: CHAT_TEXTS.stepElapsed.replace('{n}', n).replace('{label}', () => label),
    spoken: CHAT_TEXTS.stepElapsedSpoken.replace('{n}', n).replace('{label}', () => label),
    seconds: reply.seconds,
    dots: false,
  };
}

/** True while the panel shows the empty chat panel: the store's chat holds no entry of any type and no message of this page waits. */
export function isFreshChat(chat: readonly LiveItem[], outbox: readonly OutboxEntry[]): boolean {
  return chat.length === 0 && outbox.length === 0;
}
