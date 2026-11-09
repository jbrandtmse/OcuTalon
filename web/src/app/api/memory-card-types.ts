/**
 * The bodies of the Memory card's routes (Story 41.6; AD-4, AD-21), kept apart from api-types.ts. Type-only: they hold the shapes of
 * `GET /api/v1/memory/notes`, `GET /api/v1/memory/precedents` and `DELETE /api/v1/memory/precedents/:ref`, which the server writes
 * (OcuTalon.Web.Api, Data.Precedent.View).
 */

/** The day that the notes route is asked for. */
export type MemoryDay = 'today' | 'yesterday';

/** The 200 answer of the notes route: the day, its local date (YYYY-MM-DD) and the day's note lines as the server built them. */
export interface MemoryNotes {
  day: string;
  date: string;
  lines: string[];
}

/** One precedent of the session, every field a string, in the order that the server writes them. `channel` is "" for a tool call's row. */
export interface PrecedentRow {
  ref: string;
  answeredAt: string;
  channel: string;
  answeredChannel: string;
  summary: string;
  outcome: string;
  answer: string;
}

/** The 200 answer of the list route: the session's own rows, newest first. */
export interface PrecedentList {
  precedents: PrecedentRow[];
}

/** The 200 answer of the forget route. */
export interface PrecedentForgotten {
  result: 'done';
}
