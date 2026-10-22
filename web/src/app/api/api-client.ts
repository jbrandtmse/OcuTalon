import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import type { Observable } from 'rxjs';

import type { EventsResponse, StateSnapshot } from './api-types';

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

  /** The events after the two cursors, one for the session's stream and one for the instance's. */
  events(after: number, afterInstance: number): Observable<EventsResponse> {
    return this.http.get<EventsResponse>(`${BASE}/events`, { params: { after, afterInstance } });
  }
}
