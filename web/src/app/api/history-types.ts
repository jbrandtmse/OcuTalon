/**
 * The bodies of `GET /api/v1/history/decisions` and `GET /api/v1/history/incidents` (Story 25.2; AD-4, AD-13), kept apart from api-types.ts. Type-only:
 * the server writes them (OcuTalon.Web.History). They hold the caller's own session's past decisions and the incidents it sees, and nothing else: no row
 * id, owner or user name. `ref` is the public Ref, which only keys a row.
 */

/** The values of the Outcome filter, as the route takes them. */
export type HistoryOutcome = 'ignore' | 'digest' | 'tellnow' | 'act';

/** The values of the Fallback filter, as the route takes them. */
export type HistoryFallback = 'yes' | 'no';

/** The filters of the Decisions tab; a filter that is absent is not set. */
export interface HistoryFilters {
  outcome?: HistoryOutcome;
  /** A channel of the Msg.Enum list (web, phone, mailbox, telegram, email, webhook, slack, system, heartbeat). */
  channel?: string;
  /** One instance-zone date, YYYY-MM-DD. */
  day?: string;
  fallback?: HistoryFallback;
}

/** One past decision: the rail's decision payload fields, plus the channel of its usage rows ("" when no model call served it). */
export interface HistoryDecision {
  ref: string;
  outcome: string;
  reasons: string;
  fallback: boolean;
  fallbackReason: string;
  itemSummary: string;
  recordedAt: string;
  channel: string;
  /** Where the decision's trace opens, as the server built it; absent when it could not. */
  traceUrl?: string;
  confidence?: number;
  costUSD?: number;
}

/** One incident of the list. */
export interface HistoryIncident {
  ref: string;
  state: string;
  fallback: boolean;
  count: number;
  itemNoun?: { one?: string; other?: string };
  firstAt: string;
  noticedAt: string;
  /** "" while the incident is open. */
  closedAt: string;
  /** The stored summary as text, one line each; "" when none is stored. */
  summary: string;
  /** Where the incident's diagnosis session opens, as the server built it; absent when it could not. */
  traceUrl?: string;
}

/** One page of past decisions, 25 to a page, newest first. A page past the last has an empty list. */
export interface HistoryDecisionsResponse {
  page: number;
  pages: number;
  decisions: HistoryDecision[];
}

/** One page of incidents, 25 to a page, newest first. */
export interface HistoryIncidentsResponse {
  page: number;
  pages: number;
  incidents: HistoryIncident[];
}
