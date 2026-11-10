/**
 * The bodies of the Memory card's routes (Story 41.6; AD-4, AD-21), kept apart from api-types.ts. Type-only: they hold the shapes of
 * `GET /api/v1/memory/notes`, `GET /api/v1/memory/precedents` and `DELETE /api/v1/memory/precedents/:ref` (Story 41.6), and of the memory items, pinned, pin, unpin and forget routes (Story 41.13), which the server writes
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

/** One memory of the session (Story 41.13): as `GET /api/v1/memory/items` and `/memory/pinned` serve it, with no origin. */
export interface MemoryItem {
  ref: string;
  text: string;
  savedAt: string;
  source: 'told' | 'learned';
  pinned: boolean;
}

/** The 200 answer of the items route: the newest memories, or the best matches of a search, and the count behind them (`total`). */
export interface MemoryItems {
  items: MemoryItem[];
  total: number;
}

/** The 200 answer of the pinned route: the pins, newest pin first, and `used`, the tokens of their core-memory block as the server computes it. */
export interface PinnedMemories {
  items: MemoryItem[];
  used: number;
}

/** The 200 answer of the pin, unpin and forget-memory routes. */
export interface MemoryDone {
  result: 'done';
}

/** The 200 answer of the forget route. */
export interface PrecedentForgotten {
  result: 'done';
}
