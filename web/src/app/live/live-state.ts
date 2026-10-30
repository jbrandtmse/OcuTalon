import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, timeout, type Subscription } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { EventsResponse, StateSnapshot } from '../api/api-types';
import { Announcer } from '../shared/announcer';
import { BUSY_STATUS, ContactWatch, pollDelay, type ContactState } from './contact-watch';
import { applyEvents, fromSnapshot, type LiveStore } from './live-store';

/** How the snapshot's load went. */
export type SnapshotStatus = 'loading' | 'loaded' | 'failed';

/** How long the first load may take before the page says it couldn't load. */
export const LOAD_TIMEOUT_MS = 10_000;

/** How long the poll waits after each answer before it asks again (AD-12), so polls come one to two seconds apart. */
export const POLL_DELAY_MS = 1000;

/**
 * How long a poll, or the reload of the snapshot after a skip, may stay unanswered before it counts as failed: it is dropped
 * and the next poll follows (after POLL_DELAY_MS, or at once while the page is unreachable), so a request that never answers
 * cannot stop the live updates. It is no longer than UNREACHABLE_RETRY_MS, so an unreachable page whose polls hang still starts
 * one every 10 seconds, as its banner says.
 */
export const POLL_TIMEOUT_MS = 10_000;

/** What the page says, and the polite announcer reads, when the snapshot did not load. */
export const LOAD_FAILED = "Couldn't load your session.";

/**
 * The page's one live-state service. It loads the snapshot (`/state`) once per page load and every consumer reads it from
 * here; once loaded it polls `/events` with the two cursors, one at a time, waiting POLL_DELAY_MS after each answer, and
 * applies the events to the store idempotently. A skipped Seq or a new epoch loads the snapshot again and keeps the status
 * loaded. A poll or a reload with no answer by POLL_TIMEOUT_MS counts as failed. Nothing here moves keyboard focus.
 *
 * With no answer by LOAD_TIMEOUT_MS, or with an error answer, the status is failed and the polite announcer says so once;
 * a late answer still loads. retry() asks again, and says so again when that fails. A 401 is the session gate's: this
 * service neither fails nor announces for it. stop() ends the polling, drops what is in flight and ends the contact watch;
 * the session gate's 401, Sign out, the idle stop and an epoch change all end the page through it, so none of them shows a
 * lost-contact banner. `halted` turns true at the first stop().
 *
 * On the online demo (the loaded snapshot's onlineDemo, Story 16.4; AD-13) another epoch is another OcuTalon session that began in
 * this browser: the page never applies a poll or a snapshot of an epoch other than its first snapshot's, applies none of that
 * answer's events and does not reload. It stops, and `epochChanged` turns true, which the session gate answers by leaving the page
 * (this service does not know the gate). A local install's page reloads the snapshot instead, as before.
 *
 * `contact` is the page's contact with OcuTalon (Story 2.11), counted by a ContactWatch from the last answer of the live
 * path, which in release 1 is the polling: `ok`, then `reconnecting` after 10 s with no answer and `unreachable` after 30 s.
 * An answer is a poll whose answer was applied, whether it brought events or none; a snapshot that was taken in; or a 503 of
 * either request once the page has loaded (the busy state, which is the server answering). A poll that finds a skipped Seq is
 * answered by the snapshot it reloads, not by itself. A refused connection, a timeout, a 401 and every other status are no
 * answer. The watch is armed by the first snapshot: until then `contact` stays `ok` and the load states are the page's. A poll
 * scheduled while `unreachable` starts 10 seconds after the previous one started; otherwise the next poll follows an answer,
 * or a poll given up, after POLL_DELAY_MS.
 */
@Injectable({ providedIn: 'root' })
export class LiveState {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);

  private requested = false;
  private stopped = false;
  private polling = false;
  /** The number of the latest /state request, and of the latest one whose answer was applied. */
  private issued = 0;
  private applied = 0;
  private loadTimer: ReturnType<typeof setTimeout> | undefined;
  private pollTimer: ReturnType<typeof setTimeout> | undefined;
  /** When the latest poll started, in milliseconds on the page's monotonic clock. */
  private pollStart = 0;
  private readonly inFlight = new Set<Subscription>();
  private readonly haltedState = signal(false);
  private readonly epochState = signal(false);
  /** The contact state, which only the watch sets; `contact` is its read-only view. */
  private readonly contactState = signal<ContactState>('ok');
  private readonly watch = new ContactWatch({
    setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
    clearTimeout: (handle) => globalThis.clearTimeout(handle as ReturnType<typeof setTimeout>),
    onChange: (state) => this.contactState.set(state),
  });

  /**
   * The snapshot as /state last answered, once it has loaded. Its chat, rail, telegram and status are not kept up to date by
   * events: views read those from `store`.
   */
  readonly snapshot = signal<StateSnapshot | undefined>(undefined);

  /** Loading until the snapshot answers, then loaded or failed. */
  readonly status = signal<SnapshotStatus>('loading');

  /** The live store: the snapshot's state with the events applied. */
  readonly store = signal<LiveStore | undefined>(undefined);

  /** Counts the answers of the live path (a snapshot taken in, a poll applied, a busy 503): the reset watch checks its clock at each one. */
  readonly answers = signal(0);

  /** The page's contact with OcuTalon: `ok` until the live path has gone 10 s with no answer, then `reconnecting`, then `unreachable` at 30 s. */
  readonly contact = this.contactState.asReadonly();

  /** True from the first stop(): the page is leaving, or the reset's view has taken over; nothing is polled or loaded any more. */
  readonly halted = this.haltedState.asReadonly();

  /** True once the online demo's page found another epoch in a poll or a snapshot (see the class description). */
  readonly epochChanged = this.epochState.asReadonly();

  /** The last Seq applied on the session's stream, once loaded. */
  readonly sessionSeq = computed(() => this.store()?.cursors.session);

  /** The last Seq applied on the instance stream, once loaded. */
  readonly instanceSeq = computed(() => this.store()?.cursors.instance);

  /** Asks for the snapshot; every call after the first does nothing. */
  load(): void {
    if (this.requested) {
      return;
    }
    this.requested = true;
    this.loadTimer = globalThis.setTimeout(() => {
      this.loadTimer = undefined;
      if (this.status() === 'loading') {
        this.fail();
      }
    }, LOAD_TIMEOUT_MS);
    this.fetchSnapshot(() => this.fail());
  }

  /**
   * Asks for the snapshot again after a failed load: an Observable that emits once and completes when /state has answered,
   * whatever the answer. A failed answer announces the failure again; a good one loads the page.
   */
  retry(): Observable<void> {
    return new Observable<void>((subscriber) => {
      const done = () => {
        subscriber.next();
        subscriber.complete();
      };
      this.fetchSnapshot(
        () => {
          this.fail(true);
          done();
        },
        done,
      );
    });
  }

  /** Ends the polling and the contact watch, and drops every request in flight. Nothing is loaded or polled after it. */
  stop(): void {
    this.stopped = true;
    this.haltedState.set(true);
    this.watch.stop();
    this.clearTimers();
    for (const subscription of this.inFlight) {
      subscription.unsubscribe();
    }
    this.inFlight.clear();
  }

  /**
   * Sends a /state request. onError gets any answer but a 401, and with limitMs the lack of an answer by then; onApplied runs
   * after a good answer was applied.
   */
  private fetchSnapshot(onError: () => void, onApplied?: () => void, limitMs?: number): void {
    if (this.stopped) {
      return;
    }
    const request = ++this.issued;
    const answer = limitMs === undefined ? this.api.state() : this.api.state().pipe(timeout(limitMs));
    const subscription = answer.subscribe({
      next: (snapshot) => {
        if (this.stopped) {
          return;
        }
        if (this.otherEpoch(snapshot.epoch)) {
          this.changeEpoch();
          return;
        }
        if (request > this.applied) {
          this.applied = request;
          this.accept(snapshot);
        }
        onApplied?.();
      },
      error: (error: unknown) => {
        if (this.stopped || (error instanceof HttpErrorResponse && error.status === 401)) {
          return;
        }
        if (this.status() === 'loaded' && isBusy(error)) {
          this.watch.answered();
          this.answers.update((count) => count + 1);
        }
        onError();
      },
    });
    this.track(subscription);
  }

  /** Takes a snapshot in: the page is loaded, the contact watch counts from it, and the poll runs. */
  private accept(snapshot: StateSnapshot): void {
    if (this.loadTimer !== undefined) {
      globalThis.clearTimeout(this.loadTimer);
      this.loadTimer = undefined;
    }
    this.snapshot.set(snapshot);
    this.store.set(fromSnapshot(snapshot));
    this.status.set('loaded');
    this.watch.answered();
    this.answers.update((count) => count + 1);
    if (!this.polling) {
      this.polling = true;
      this.schedulePoll();
    }
  }

  /**
   * The load failed: the status says so and the announcer reads it. The first load announces once, however many ways it
   * fails (the timeout, then an error answer); a failed retry (again) announces again, because the user asked.
   */
  private fail(again = false): void {
    const status = this.status();
    if (status === 'loaded' || (status === 'failed' && !again)) {
      return;
    }
    this.status.set('failed');
    this.announcer.announce(LOAD_FAILED);
  }

  private schedulePoll(): void {
    if (this.stopped) {
      return;
    }
    const delay = pollDelay(this.contact(), performance.now() - this.pollStart, POLL_DELAY_MS);
    this.pollTimer = globalThis.setTimeout(() => {
      this.pollTimer = undefined;
      this.poll();
    }, delay);
  }

  /**
   * One poll with the current cursors; the next one is scheduled when this one has answered, good or not, or has had no answer
   * by POLL_TIMEOUT_MS. A 503 is an answer of the live path.
   */
  private poll(): void {
    const store = this.store();
    if (this.stopped || !store) {
      return;
    }
    this.pollStart = performance.now();
    const subscription = this.api.events(store.cursors.session, store.cursors.instance).pipe(timeout(POLL_TIMEOUT_MS)).subscribe({
      next: (response) => this.applyPoll(response),
      error: (error: unknown) => {
        if (!this.stopped && isBusy(error)) {
          this.watch.answered();
          this.answers.update((count) => count + 1);
        }
        this.schedulePoll();
      },
    });
    this.track(subscription);
  }

  /**
   * Applies a poll's events, and the poll has answered; a reload result loads the snapshot again, with the status kept at loaded,
   * and that snapshot is the answer.
   */
  private applyPoll(response: EventsResponse): void {
    const current = this.store();
    if (this.stopped || !current) {
      return;
    }
    const result = applyEvents(current, response);
    if (result.epochChanged && this.otherEpoch(response.epoch)) {
      this.changeEpoch();
      return;
    }
    if (result.reload) {
      this.fetchSnapshot(
        () => this.schedulePoll(),
        () => this.schedulePoll(),
        POLL_TIMEOUT_MS,
      );
      return;
    }
    if (result.store !== current) {
      this.store.set(result.store);
    }
    this.watch.answered();
    this.answers.update((count) => count + 1);
    this.schedulePoll();
  }

  /** True on the online demo when the epoch is not the one of the snapshot the page loaded first. */
  private otherEpoch(epoch: string): boolean {
    const known = this.store()?.epoch;
    return known !== undefined && epoch !== known && this.snapshot()?.onlineDemo === true;
  }

  /** The online demo's page found another epoch: it stops, applying nothing of that answer, and says so. */
  private changeEpoch(): void {
    this.stop();
    this.epochState.set(true);
  }

  /** Keeps a request's subscription until it ends, so that stop() can drop it. */
  private track(subscription: Subscription): void {
    if (subscription.closed) {
      return;
    }
    this.inFlight.add(subscription);
    subscription.add(() => this.inFlight.delete(subscription));
  }

  private clearTimers(): void {
    if (this.loadTimer !== undefined) {
      globalThis.clearTimeout(this.loadTimer);
      this.loadTimer = undefined;
    }
    if (this.pollTimer !== undefined) {
      globalThis.clearTimeout(this.pollTimer);
      this.pollTimer = undefined;
    }
  }
}

/** True for the server's busy answer (AD-25). */
function isBusy(error: unknown): boolean {
  return error instanceof HttpErrorResponse && error.status === BUSY_STATUS;
}
