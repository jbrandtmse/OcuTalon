/**
 * The bodies of the persona routes (Story 40.8; AD-1, AD-19), kept apart from api-types.ts. Type-only: they hold the shapes of
 * `GET /api/v1/persona` and `PUT /api/v1/persona`, which the server writes (OcuTalon.Web.Api).
 */

/** The answer of `GET /api/v1/persona`: the session's persona and whether it may hold the person's own words. */
export interface PersonaState {
  /** The preset id: professional, starship, pirate, kindfriend, language or custom. */
  preset: string;
  /** The language name; empty unless the preset is `language`. */
  language: string;
  /** The person's own words; empty unless the preset is `custom`. */
  custom: string;
  /** False on the online demo, where a persona is a preset or a language only. */
  customOffered: boolean;
  /** The Ref of the pending `setting` approval request that proposes a persona, or empty for none. */
  pendingRef: string;
}

/** The body of `PUT /api/v1/persona`: the three values, each a string, the unused ones empty. */
export interface PersonaPut {
  preset: string;
  language: string;
  custom: string;
}

/** The 200 answer of `PUT /api/v1/persona`: the server's saved line and the values as it saved them. */
export interface PersonaSaved {
  result: 'done';
  message: string;
  preset: string;
  language: string;
  custom: string;
}
