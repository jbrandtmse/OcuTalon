import type { ApprovalPayload, CheckPayload, DecisionPayload, LiveEventType, LivePayloads, ReminderPayload } from '../live/payloads';

/** A live event without its place in a stream: the type and the payload that goes with it. */
export type LiveItem<T extends LiveEventType = LiveEventType> = T extends LiveEventType ? { type: T; payload: LivePayloads[T] } : never;

/** One event of the poll: the stream is the cursor that it advances, never the session's reference. */
export type LiveEnvelope<T extends LiveEventType = LiveEventType> = LiveItem<T> & {
  seq: number;
  stream: 'session' | 'instance';
  ts: string;
};

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
}

/** GET /ocutalon/api/v1/events?after=<sessionSeq>&afterInstance=<instanceSeq>: the session's events, then the instance's. */
export interface EventsResponse {
  epoch: string;
  events: LiveEnvelope[];
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
