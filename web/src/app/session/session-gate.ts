import { Injectable, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';

import { ApiClient } from '../api/api-client';
import { LiveState } from '../live/live-state';
import { ResetWatch } from '../live/reset-watch';

/** The sign-in page's address; the application's own page, which shows the sign-in page without a session. */
const HOME = '/ocutalon/';

/**
 * The page's session: whether it has ended, and the two ways it ends.
 * - A 401 from the API at or after the pending reset (Story 16.8): the reset ended the session, so the page enters the resetting
 *   view (ResetWatch) and this path does not run.
 * - A 401 from the API (the CSP session ended elsewhere): the page stops polling, makes no further call and goes to the
 *   sign-in page with the signed-out notice, keeping its hash so that signing in again returns to where the user was.
 * - Sign out: the page stops polling and asks the server to end the session and the sign-in group. If that call fails
 *   (other than with a 401) the page leaves through IRIS's own sign-out, so that a user can always sign out.
 */
@Injectable({ providedIn: 'root' })
export class SessionGate {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly reset = inject(ResetWatch);

  /** True once the session is known to have ended. */
  readonly signedOut = signal(false);

  /** The API answered 401. Acts once; at or after the pending reset the page enters the resetting view instead. */
  onSignedOut(): void {
    if (this.signedOut() || this.reset.enterIfDue()) {
      return;
    }
    this.signedOut.set(true);
    this.live.stop();
    globalThis.location.replace(`${HOME}?signedOut=1${globalThis.location.hash}`);
  }

  /** The user chose Sign out. */
  signOut(): void {
    this.live.stop();
    this.api.endSession().subscribe({
      next: () => undefined,
      complete: () => globalThis.location.replace(HOME),
      error: (error: unknown) => {
        if (error instanceof HttpErrorResponse && error.status === 401) {
          return;
        }
        globalThis.location.replace(`${HOME}?IRISLogout=end`);
      },
    });
  }
}
