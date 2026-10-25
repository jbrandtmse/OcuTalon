import { HttpErrorResponse, type HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, throwError } from 'rxjs';

import { SessionGate } from '../session/session-gate';

/** The address of the REST API; the interceptor leaves every other request alone. */
const API = '/ocutalon/api/';

/** The methods that change state, which the server accepts only with the browser envelope (AD-13). */
const CHANGING = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

/**
 * The browser envelope and the 401, for every call to the API.
 * - Once the session is known to be gone, nothing is sent: the call fails at once as a 401.
 * - A state-changing call carries Content-Type: application/json and X-OcuTalon-Request: 1 (the browser adds the Origin).
 * - A 401 tells the session gate, which stops the page and shows the sign-in page, and is passed on to the caller.
 */
export const envelopeInterceptor: HttpInterceptorFn = (request, next) => {
  if (!request.url.startsWith(API)) {
    return next(request);
  }
  const gate = inject(SessionGate);
  if (gate.signedOut()) {
    return throwError(() => new HttpErrorResponse({ status: 401, statusText: 'Signed out', url: request.url }));
  }
  const sent = CHANGING.has(request.method)
    ? request.clone({ setHeaders: { 'Content-Type': 'application/json', 'X-OcuTalon-Request': '1' } })
    : request;
  return next(sent).pipe(
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse && error.status === 401) {
        gate.onSignedOut();
      }
      return throwError(() => error);
    }),
  );
};
