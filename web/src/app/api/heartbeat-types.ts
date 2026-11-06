/**
 * The bodies of the heartbeat routes (Story 39.5; AD-1, AD-12, AD-19), kept apart from api-types.ts. Type-only: they hold the shapes of
 * `GET /api/v1/heartbeat`, `PUT /api/v1/heartbeat` and `POST /api/v1/heartbeat/run`, which the server writes (OcuTalon.Web.Api).
 */
import type { HeartbeatPayload } from '../live/payloads';

/** The heartbeat's check-ins and cost in the daily cap's day. */
export interface HeartbeatToday {
  checkIns: number;
  costUSD: number;
}

/**
 * The answer of `GET /api/v1/heartbeat`: the public view of the person's settings and HeartbeatBeat row (the members of the `heartbeat`
 * event), then the checklist, whether it is the online demo's unsaved sample, whether this is the online demo, today's check-ins and
 * cost, and the plain-reason value of the last fallback when the last beat was one.
 */
export interface HeartbeatState extends HeartbeatPayload {
  checklist: string;
  sample: boolean;
  onlineDemo: boolean;
  today: HeartbeatToday;
  lastFallbackReason?: string;
}

/** The body of `PUT /api/v1/heartbeat`: all day is both hours empty. */
export interface HeartbeatPut {
  on: boolean;
  interval: number;
  from: string;
  to: string;
  checklist: string;
}

/** The 200 answer of `PUT /api/v1/heartbeat`: the server's saved line and the values as it saved them. */
export interface HeartbeatSaved {
  result: 'done';
  message: string;
  on: boolean;
  interval: number;
  from: string;
  to: string;
  checklist: string;
}

/** The body of a 409 answer of `POST /api/v1/heartbeat/run`: the refusal, and when it can be tried again (cooldown, backoff). */
export interface HeartbeatRunRefused {
  error: { code: string; message: string };
  availableAt?: string;
}
