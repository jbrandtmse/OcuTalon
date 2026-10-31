/**
 * The page's live store (AD-12): the snapshot's state and the events that follow it. A framework-free module: it imports
 * only types and uses only erasable TypeScript syntax, so Node runs it as it is, and every function returns a new store
 * and changes nothing it was given.
 *
 * - fromSnapshot(snapshot) builds the store: the entities of the snapshot, and one cursor for each stream.
 * - applyEvents(store, response) applies the events of a poll. Each event carries the full current view of one entity: it
 *   replaces the entity with the same key, or is added. Per stream, an event at or below the cursor is ignored (a repeat),
 *   the event right after the cursor is applied and advances it, and an event further on, or an epoch that is not the
 *   store's, means the page missed something: the store comes back unchanged with reload set, and the caller fetches the
 *   snapshot again. A result with epochChanged set says which of the two it was (Story 16.4): on the online demo another epoch means
 *   that another OcuTalon session began in this browser, and the page leaves instead of loading it.
 * - COLLECTIONS says where each event type lives and by which key.
 */
import type { EventsResponse, LiveEnvelope, LiveItem, StateSnapshot, TelegramState } from '../api/api-types';
import type {
  ApprovalPayload,
  BreakFeedProgressPayload,
  CheckPayload,
  DecisionPayload,
  GuideStatePayload,
  LiveEventType,
  LivePayloads,
  MailboxPayload,
  PhonePayload,
  ReminderPayload,
  ResetPayload,
  StatusPayload,
  TurnStepPayload,
  WatchProgressPayload,
} from './payloads';

/** How an event type is stored: the collection and the payload field that keys it, or null for a single value. */
export interface CollectionRule {
  collection: string;
  key: string | null;
}

/** The type to collection and key table (AD-12). The key of an entry of the chat is `type:ref`. */
export const COLLECTIONS: Readonly<Record<LiveEventType, CollectionRule>> = {
  'chat.message': { collection: 'chat', key: 'ref' },
  notification: { collection: 'chat', key: 'ref' },
  incident: { collection: 'chat', key: 'ref' },
  decision: { collection: 'decisions', key: 'ref' },
  approval: { collection: 'approvals', key: 'ref' },
  check: { collection: 'checks', key: 'ref' },
  reminder: { collection: 'reminders', key: 'ref' },
  phone: { collection: 'phones', key: 'ref' },
  mailbox: { collection: 'mailboxes', key: 'ref' },
  'watch.progress': { collection: 'watchProgress', key: 'ref' },
  status: { collection: 'status', key: 'condition' },
  'turn.step': { collection: 'turnSteps', key: 'turnRef' },
  pairing: { collection: 'telegram', key: null },
  'guide.state': { collection: 'guideState', key: null },
  reset: { collection: 'reset', key: null },
  'breakfeed.progress': { collection: 'breakfeedProgress', key: null },
};

/** One cursor for each stream: the Seq of the last event applied. */
export interface Cursors {
  session: number;
  instance: number;
}

/** The latest full view of every entity, by collection. The views (Stories 2.5 to 2.10) filter by state. */
export interface LiveStore {
  epoch: string;
  cursors: Cursors;
  /** The chat's entries in order: turns, incidents and notices; replaced in place by `type:ref`, new ones appended. */
  chat: LiveItem[];
  /** Decisions, newest first: a new one is put first. */
  decisions: DecisionPayload[];
  approvals: Readonly<Record<string, ApprovalPayload>>;
  checks: Readonly<Record<string, CheckPayload>>;
  reminders: Readonly<Record<string, ReminderPayload>>;
  phones: Readonly<Record<string, PhonePayload>>;
  mailboxes: Readonly<Record<string, MailboxPayload>>;
  watchProgress: Readonly<Record<string, WatchProgressPayload>>;
  /** By condition. */
  status: Readonly<Record<string, StatusPayload>>;
  /** By the ref of the running turn that the step belongs to: the latest step of each turn. */
  turnSteps: Readonly<Record<string, TurnStepPayload>>;
  telegram: TelegramState;
  guideState: GuideStatePayload | undefined;
  reset: ResetPayload | undefined;
  breakfeedProgress: BreakFeedProgressPayload | undefined;
}

/**
 * The result of applying a poll: the store, whether the snapshot has to be loaded again, and whether that is because the poll carried
 * another epoch (epochChanged, always with reload) and not a skipped Seq.
 */
export interface ApplyResult {
  store: LiveStore;
  reload: boolean;
  epochChanged: boolean;
}

/** The key of an entry of the chat. */
export function chatKey(item: LiveItem): string {
  return `${item.type}:${(item.payload as { ref?: string }).ref ?? ''}`;
}

/** A map of payloads by the value of one of their fields. */
function keyed<T>(payloads: readonly T[], field: string): Record<string, T> {
  const map: Record<string, T> = Object.create(null) as Record<string, T>;
  for (const payload of payloads) {
    map[String((payload as Record<string, unknown>)[field] ?? '')] = payload;
  }
  return map;
}

/** The rail's decisions, then the decision of each incident entry of the chat whose ref the rail does not hold. */
function snapshotDecisions(snapshot: StateSnapshot): DecisionPayload[] {
  const decisions = [...snapshot.rail.decisions];
  for (const item of snapshot.chat) {
    const decision = item.type === 'incident' ? item.decision : undefined;
    if (decision && !decisions.some((entry) => entry.ref === decision.ref)) {
      decisions.push(decision);
    }
  }
  return decisions;
}

/** The store of a snapshot. */
export function fromSnapshot(snapshot: StateSnapshot): LiveStore {
  return {
    epoch: snapshot.epoch,
    cursors: { session: snapshot.streams.session, instance: snapshot.streams.instance },
    chat: [...snapshot.chat],
    decisions: snapshotDecisions(snapshot),
    approvals: keyed(snapshot.rail.approvals, 'ref'),
    checks: keyed(snapshot.rail.checks, 'ref'),
    reminders: keyed(snapshot.rail.reminders, 'ref'),
    phones: keyed([], 'ref'),
    mailboxes: keyed([], 'ref'),
    watchProgress: keyed([], 'ref'),
    status: keyed(snapshot.status, 'condition'),
    turnSteps: keyed([], 'turnRef'),
    telegram: { ...snapshot.telegram },
    guideState: undefined,
    reset: undefined,
    breakfeedProgress: undefined,
  };
}

/** The store with one entity put in a keyed collection, replacing the one with the same key. */
function put<T>(map: Readonly<Record<string, T>>, key: string, payload: T): Record<string, T> {
  const next: Record<string, T> = Object.create(null) as Record<string, T>;
  Object.assign(next, map);
  next[key] = payload;
  return next;
}

/** The store after one event; an event of a type the page does not know changes nothing. */
function applyEvent(store: LiveStore, event: LiveEnvelope): LiveStore {
  const rule = COLLECTIONS[event.type] as CollectionRule | undefined;
  if (!rule) {
    return store;
  }
  const payload = event.payload as Record<string, unknown>;
  const key = rule.key === null ? '' : String(payload[rule.key] ?? '');
  switch (rule.collection) {
    case 'chat': {
      const item = { type: event.type, payload: event.payload } as LiveItem;
      const wanted = chatKey(item);
      const at = store.chat.findIndex((entry) => chatKey(entry) === wanted);
      const chat = at < 0 ? [...store.chat, item] : store.chat.map((entry, i) => (i === at ? item : entry));
      return { ...store, chat };
    }
    case 'decisions': {
      const decision = event.payload as DecisionPayload;
      const at = store.decisions.findIndex((entry) => entry.ref === decision.ref);
      const decisions = at < 0 ? [decision, ...store.decisions] : store.decisions.map((entry, i) => (i === at ? decision : entry));
      return { ...store, decisions };
    }
    case 'approvals':
      return { ...store, approvals: put(store.approvals, key, event.payload as ApprovalPayload) };
    case 'checks':
      return { ...store, checks: put(store.checks, key, event.payload as CheckPayload) };
    case 'reminders':
      return { ...store, reminders: put(store.reminders, key, event.payload as ReminderPayload) };
    case 'phones':
      return { ...store, phones: put(store.phones, key, event.payload as PhonePayload) };
    case 'mailboxes':
      return { ...store, mailboxes: put(store.mailboxes, key, event.payload as MailboxPayload) };
    case 'watchProgress':
      return { ...store, watchProgress: put(store.watchProgress, key, event.payload as WatchProgressPayload) };
    case 'status':
      return { ...store, status: put(store.status, key, event.payload as StatusPayload) };
    case 'turnSteps':
      return { ...store, turnSteps: put(store.turnSteps, key, event.payload as TurnStepPayload) };
    case 'telegram': {
      const pairing = event.payload as LivePayloads['pairing'];
      return { ...store, telegram: { ...store.telegram, paired: pairing.paired ?? false, displayName: pairing.displayName ?? '' } };
    }
    case 'guideState':
      return { ...store, guideState: event.payload as GuideStatePayload };
    case 'reset':
      return { ...store, reset: event.payload as ResetPayload };
    case 'breakfeedProgress':
      return { ...store, breakfeedProgress: event.payload as BreakFeedProgressPayload };
    default:
      return store;
  }
}

/**
 * Applies the events of a poll, in the order served (the session's stream, then the instance's). A poll answered with another
 * epoch, or with an event that skips a Seq of its stream, applies nothing and asks for a reload; epochChanged tells the first from
 * the second.
 */
export function applyEvents(store: LiveStore, response: EventsResponse): ApplyResult {
  if (response.epoch !== store.epoch) {
    return { store, reload: true, epochChanged: true };
  }
  let next = store;
  const cursors: Cursors = { ...store.cursors };
  for (const event of response.events) {
    const cursor = cursors[event.stream];
    if (event.seq <= cursor) {
      continue;
    }
    if (event.seq !== cursor + 1) {
      return { store, reload: true, epochChanged: false };
    }
    next = applyEvent(next, event);
    cursors[event.stream] = event.seq;
  }
  const advanced = cursors.session !== store.cursors.session || cursors.instance !== store.cursors.instance;
  return { store: advanced ? { ...next, cursors } : store, reload: false, epochChanged: false };
}
