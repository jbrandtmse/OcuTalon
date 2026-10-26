import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import type { Observable } from 'rxjs';

/** The address of the press. */
const BREAK_FEED = '/ocutalon/api/v1/demo/break-feed';

/** The 200 answer to a press: the run's batch is sent, and when it started. */
export interface BreakFeedSent {
  state: 'sent';
  startedAt: string;
}

/**
 * The page's one call of Break the feed (AD-13): POST /ocutalon/api/v1/demo/break-feed with an empty body, which names no session (AD-4).
 * It goes through the page's HttpClient, so the envelope interceptor adds the browser envelope and handles a 401 like every other call.
 * A 409 fails as an HttpErrorResponse whose body is the error answer `{"error":{"code","message"}}`, code `not_watching` or
 * `incident_in_progress` (break-feed-view.ts's conflictOf reads it); any other failure is passed on as it is.
 *
 * Veto item V1 (Story 4.4): this is a second typed caller of the API, here because `web/src/app/api/**` is Epic 10's while this story
 * builds. When that folder is free the method moves into ApiClient as `breakFeed()`, with its answer type in api-types.ts.
 */
@Injectable({ providedIn: 'root' })
export class BreakFeedApi {
  private readonly http = inject(HttpClient);

  /** Presses Break the feed: the answer is the run's `startedAt`. */
  press(): Observable<BreakFeedSent> {
    return this.http.post<BreakFeedSent>(BREAK_FEED, {});
  }
}
