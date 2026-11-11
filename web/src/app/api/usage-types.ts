/**
 * The body of `GET /api/v1/usage?days=1|7|30` (Story 37.2; AD-4, AD-20), kept apart from api-types.ts. Type-only: the server writes it
 * (OcuTalon.Web.Usage). It holds the caller's own session's usage, summed into buckets, and nothing else: no ref, row id or owner.
 */

/** The ranges the route accepts, in days; a local day each, today included. */
export type UsageDays = 1 | 7 | 30;

/** The sum of the usage rows of one (day, agent, channel, model, estimated). Input tokens already include the cache-read and cache-write tokens. */
export interface UsageBucket {
  /** The local date, YYYY-MM-DD, in the instance zone. */
  day: string;
  /** The stored agent, such as TriageAgent, ChatAgentRetry or compaction. */
  agent: string;
  /** The stored channel, such as web, phone or heartbeat. */
  channel: string;
  /** The model id. */
  model: string;
  /** True for the compaction rows, whose tokens are an estimate. */
  estimated: boolean;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** Dollars; a row with no price counts 0. */
  costUSD: number;
  /** The largest estimated request of the bucket's rows, in tokens. */
  largestRequestTokens: number;
}

/** The answer: the local dates of the range (oldest first, today last), the request-size limit in tokens, and the buckets. */
export interface UsageResponse {
  days: string[];
  limit: number;
  buckets: UsageBucket[];
}
