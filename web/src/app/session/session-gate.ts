import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';

import { ApiClient } from '../api/api-client';
import type { StateSnapshot } from '../api/api-types';
import { ChatOutbox } from '../chat/chat-outbox';
import { LiveState } from '../live/live-state';
import { ResetWatch } from '../live/reset-watch';
import { IdleCap } from './idle-cap';
import { PAGE_LOADED_AT_MS, splashAddress } from './splash-address';

/** The sign-in page's address; the application's own page, which shows the sign-in page without a session. */
const HOME = '/ocutalon/';

/** How long the group sign-out request may stay unanswered before the page leaves anyway. */
export const SIGN_OUT_LIMIT_MS = 3000;

/** How the online demo's page leaves without the user pressing Sign out: the idle cap, a 401, or another epoch. */
type Exit = 'idle' | 'unauthorized' | 'epoch';

/**
 * The page's session: whether it has ended, and the ways it ends.
 * - A 401 from the API at or after the pending reset (Story 16.8): the reset ended the session, so the page enters the resetting
 *   view (ResetWatch) and this path does not run. That test is always the first.
 * - A 401 from the API (the CSP session ended elsewhere) on a local install: the page stops polling, makes no further call and goes to
 *   the sign-in page with the signed-out notice, keeping its hash so that signing in again returns to where the user was.
 * - Sign out on a local install: the page stops polling and asks the server to end the session and the sign-in group. If that call
 *   fails (other than with a 401) the page leaves through IRIS's own sign-out, so that a user can always sign out.
 *
 * On the online demo (the loaded snapshot's onlineDemo; Story 16.4, AD-13) the page frees its place and leaves for the splash:
 * - after the idle cap, `idleSeconds` of the snapshot with no key press, click or sent message (IdleCap; polls, snapshots and timers
 *   never count). The cap runs only while the page polls: it stops with the live state;
 * - on a 401 from the API (the computer slept, the CSP session timed out);
 * - on an epoch change (LiveState.epochChanged: another OcuTalon session began in this browser).
 * Every one of these exits once, in this order: the live state stops, the idle cap stops, then, except after a 401 (the CSP session
 * is already gone, and nothing calls IRIS under a public account without a session), the group sign-out runs, then the page goes to
 * the splash with the time the page loaded (`?since=`; after an epoch change also `&ended=1`, so that the splash does not say the
 * visitor was away). The group sign-out is a same-origin GET of `/ocutalon/?IRISLogout=end`, awaited for at most SIGN_OUT_LIMIT_MS: it
 * ends the CSP session of every application of the sign-in group, and the page is never navigated to that address, because the
 * splash's form would carry IRISLogout into the next sign-in. Nothing here runs on pagehide, beforeunload, unload or visibilitychange
 * (a reload fires pagehide too).
 * Sign out on the online demo asks the server to end the OcuTalon session (POST /session/end); after the 204 the page goes to the plain
 * splash. After any other answer, a 401 apart, it runs the group sign-out and goes to the plain splash, and the session stays resumable.
 */
@Injectable({ providedIn: 'root' })
export class SessionGate {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly reset = inject(ResetWatch);
  private readonly outbox = inject(ChatOutbox);
  private readonly cap = new IdleCap({
    setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
    clearTimeout: (handle) => globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>),
    now: () => Date.now(),
    onIdle: () => this.leave('idle'),
  });
  private idleStarted = false;
  private left = false;

  /** True once the session is known to have ended. */
  readonly signedOut = signal(false);

  constructor() {
    const touch = (): void => this.cap.touch();
    globalThis.document.addEventListener('keydown', touch, true);
    globalThis.document.addEventListener('click', touch, true);
    effect(() => {
      const snapshot = this.live.snapshot();
      untracked(() => this.startIdle(snapshot));
    });
    effect(() => {
      if (this.live.halted()) {
        untracked(() => this.cap.stop());
      }
    });
    effect(() => {
      this.outbox.sendCount();
      untracked(touch);
    });
    effect(() => {
      if (this.live.epochChanged()) {
        untracked(() => this.leave('epoch'));
      }
    });
  }

  /** The API answered 401. Acts once; at or after the pending reset the page enters the resetting view instead. */
  onSignedOut(): void {
    if (this.signedOut() || this.reset.enterIfDue()) {
      return;
    }
    if (this.online()) {
      this.leave('unauthorized');
      return;
    }
    this.signedOut.set(true);
    this.live.stop();
    globalThis.location.replace(`${HOME}?signedOut=1${globalThis.location.hash}`);
  }

  /** The user chose Sign out (on the online demo, in the dialog). */
  signOut(): void {
    const online = this.online();
    this.live.stop();
    if (online) {
      this.cap.stop();
    }
    this.api.endSession().subscribe({
      next: () => undefined,
      complete: () => {
        if (online) {
          this.left = true;
          this.signedOut.set(true);
        }
        globalThis.location.replace(HOME);
      },
      error: (error: unknown) => {
        if (error instanceof HttpErrorResponse && error.status === 401) {
          return;
        }
        if (online) {
          this.left = true;
          this.signedOut.set(true);
          void this.groupSignOut().then(() => globalThis.location.replace(HOME));
          return;
        }
        globalThis.location.replace(`${HOME}?IRISLogout=end`);
      },
    });
  }

  /** True on the online demo, once the snapshot has loaded. */
  private online(): boolean {
    return this.live.snapshot()?.onlineDemo === true;
  }

  /** Starts the idle cap at the first snapshot that carries one; a later snapshot is no activity, so it never starts it again. */
  private startIdle(snapshot: StateSnapshot | undefined): void {
    if (this.idleStarted || this.live.halted() || snapshot?.onlineDemo !== true) {
      return;
    }
    const seconds = snapshot.idleSeconds;
    if (typeof seconds !== 'number' || !(seconds > 0)) {
      return;
    }
    this.idleStarted = true;
    this.cap.start(seconds);
  }

  /** The online demo's page leaves, once, as the class description says. */
  private leave(exit: Exit): void {
    if (this.left) {
      return;
    }
    this.left = true;
    this.live.stop();
    this.cap.stop();
    this.signedOut.set(true);
    const address = splashAddress(PAGE_LOADED_AT_MS, exit === 'epoch');
    if (exit === 'unauthorized') {
      globalThis.location.replace(address);
      return;
    }
    void this.groupSignOut().then(() => globalThis.location.replace(address));
  }

  /**
   * The group sign-out: a same-origin GET of /ocutalon/?IRISLogout=end&t=<unique>, which ends the CSP session of every application of the
   * sign-in group. It resolves when the server answered or SIGN_OUT_LIMIT_MS has passed, whatever came back.
   */
  private async groupSignOut(): Promise<void> {
    const unique = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
    try {
      await globalThis.fetch(`${HOME}?IRISLogout=end&t=${unique}`, {
        credentials: 'same-origin',
        cache: 'no-store',
        signal: AbortSignal.timeout(SIGN_OUT_LIMIT_MS),
      });
    } catch {
      // The page leaves whatever the request came to.
    }
  }
}
