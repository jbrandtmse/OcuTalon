import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { map, type Observable } from 'rxjs';

import type { GuideStatePayload } from '../live/payloads';
import type { EventsResponse, GuideMarker, MailboxAccepted, MailboxEmail, MessageAccepted, MessagePost, StateSnapshot } from './api-types';

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

  /** Simulates an incoming email in the simulated mailbox (demo mode only). Only the answer 202 is a success. */
  postMailboxIncoming(email: MailboxEmail): Observable<MailboxAccepted> {
    return this.accepted<MailboxAccepted>(`${BASE}/mailbox/incoming`, email);
  }

  /** Delivers one of the sample emails (newsletter, partner-notice, suspicious-request) into the simulated mailbox (demo mode only). Only the answer 202 is a success. */
  postMailboxSample(name: string): Observable<MailboxAccepted> {
    return this.accepted<MailboxAccepted>(`${BASE}/mailbox/samples/${encodeURIComponent(name)}`, {});
  }

  /** Writes one of the guide's UI markers (demo mode only); the answer is the guide view that /state carries, with its trace URL. */
  postGuideMarker(marker: GuideMarker): Observable<GuideStatePayload> {
    return this.http.post<GuideStatePayload>(`${BASE}/guide/markers`, { marker });
  }

  /** A POST whose only success is the answer 202 with a body; any other status, a 2xx included, fails as an error. */
  private accepted<T>(url: string, body: object): Observable<T> {
    return this.http.post<T>(url, body, { observe: 'response' }).pipe(
      map((response) => {
        if (response.status !== 202 || response.body === null) {
          throw new HttpErrorResponse({ status: response.status, statusText: response.statusText, url: response.url ?? url });
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
