import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { map, type Observable } from 'rxjs';

import type { EventsResponse, MessageAccepted, MessagePost, StateSnapshot } from './api-types';

const BASE = '/ocutalon/api/v1';

/** The typed client of the REST API: one method per call that the page makes. */
@Injectable({ providedIn: 'root' })
export class ApiClient {
  private readonly http = inject(HttpClient);

  /** The snapshot of the signed-in user's session. */
  state(): Observable<StateSnapshot> {
    return this.http.get<StateSnapshot>(`${BASE}/state`);
  }

  /** Signs the user out: the server ends the CSP session and the whole sign-in group (204, no body). */
  endSession(): Observable<void> {
    return this.http.post<void>(`${BASE}/session/end`, {});
  }

  /**
   * Posts one message of the chat. Only the answer 202 is a success; any other status, a 2xx included, fails as an error.
   * A repeat of a clientId is answered 202 too, so a retry never queues a second turn.
   */
  postMessage(body: MessagePost): Observable<MessageAccepted> {
    return this.http.post<MessageAccepted>(`${BASE}/messages`, body, { observe: 'response' }).pipe(
      map((response) => {
        if (response.status !== 202 || response.body === null) {
          throw new HttpErrorResponse({ status: response.status, statusText: response.statusText, url: response.url ?? `${BASE}/messages` });
        }
        return response.body;
      }),
    );
  }

  /** The events after the two cursors, one for the session's stream and one for the instance's. */
  events(after: number, afterInstance: number): Observable<EventsResponse> {
    return this.http.get<EventsResponse>(`${BASE}/events`, { params: { after, afterInstance } });
  }
}
