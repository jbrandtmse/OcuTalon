import type {
  ApprovalPayload,
  CheckPayload,
  DecisionPayload,
  LiveEventType,
  LivePayloads,
  ReminderPayload,
  StatusPayload,
} from '../live/payloads';

/** A live event without its place in a stream: the type and the payload that goes with it. */
export type LiveItem<T extends LiveEventType = LiveEventType> = T extends LiveEventType ? { type: T; payload: LivePayloads[T] } : never;

/** One event of the poll: the stream is the cursor that it advances, never the session's reference. */
export type LiveEnvelope<T extends LiveEventType = LiveEventType> = LiveItem<T> & {
  seq: number;
  stream: 'session' | 'instance';
  ts: string;
};

/** The Telegram block of the snapshot: whether the release includes Telegram, the bot's state and the session's pairing. */
export interface TelegramState {
  included: boolean;
  state: 'off' | 'on' | 'rejected';
  botUserName: string;
  paired: boolean;
  displayName: string;
  pausedUntil: string;
}

/** GET /ocutalon/api/v1/state: the snapshot that the page loads, then follows with GET /v1/events. */
export interface StateSnapshot {
  version: string;
  instanceZone: string;
  epoch: string;
  streams: { session: number; instance: number };
  chat: LiveItem[];
  rail: {
    approvals: ApprovalPayload[];
    checks: CheckPayload[];
    reminders: ReminderPayload[];
    decisions: DecisionPayload[];
  };
  user: string;
  onlineDemo: boolean;
  demoMode: boolean;
  models: { triage: string; diagnosis: string; chat: string };
  telegram: TelegramState;
  status: StatusPayload[];
}

/** GET /ocutalon/api/v1/events?after=<sessionSeq>&afterInstance=<instanceSeq>: the session's events, then the instance's. */
export interface EventsResponse {
  epoch: string;
  events: LiveEnvelope[];
}

/** POST /ocutalon/api/v1/messages: one message of the chat. The session is the caller's; the body never names one. */
export interface MessagePost {
  clientId: string;
  text: string;
  fromGuide: boolean;
}

/** The 202 answer to a message: its clientId, also for a repeat of one the server already holds. */
export interface MessageAccepted {
  clientId: string;
}

/** POST /ocutalon/api/v1/mailbox/incoming: one simulated email. The session is the caller's; the body never names one. */
export interface MailboxEmail {
  from: string;
  subject: string;
  body: string;
}

/** The 202 answer to a simulated email or a sample: the Ref of the email it recorded. */
export interface MailboxAccepted {
  ref: string;
}

/** POST /ocutalon/api/v1/guide/markers: the guide's two UI markers (Story 4.7). The session is the caller's; the body never names one. */
export type GuideMarker = 'trace_opened' | 'run_again';

/** POST /ocutalon/api/v1/approvals/:ref/answer: the body of the 200 answer, the answered request. The session is the caller's; the body never names one. */
export interface AnswerBody {
  result: 'done';
  approval: ApprovalPayload;
}

/** The body of an error answer to an answer: the error, and the request's payload beside it for a 409 (already answered, expired). */
export interface AnswerError {
  error: { code: string; message: string };
  approval?: ApprovalPayload;
}

/** The body of every error answer. */
export interface ApiError {
  error: { code: string; message: string };
}

/** GET /ocutalon/public/status: no session; every key is present, null where it is not set. */
export interface PublicStatus {
  ready: boolean;
  nextReset: string | null;
  busy: boolean;
  lastReset: string | null;
  lastResetKind: string | null;
}
