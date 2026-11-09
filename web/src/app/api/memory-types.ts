/**
 * The bodies of the memory routes (Story 41.5; AD-1, AD-21), kept apart from api-types.ts. Type-only: they hold the shapes of
 * `POST /api/v1/decisions/:ref/noise`, which the server writes (OcuTalon.Web.Api).
 */

/** The channel a "This was noise" press names in its body: the web chat or the simulated phone. */
export type NoiseChannel = 'web' | 'phone';

/** The 200 answer of the noise route: `markedAt` is the UTC time of the first mark, the same for a repeat. */
export interface NoiseMarked {
  result: 'done';
  markedAt: string;
}
