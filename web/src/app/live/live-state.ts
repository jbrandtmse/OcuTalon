import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, type Subscription } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { EventsResponse, StateSnapshot } from '../api/api-types';
import { Announcer } from '../shared/announcer';
import { applyEvents, fromSnapshot, type LiveStore } from './live-store';

/** How the snapshot's load went. */
export type SnapshotStatus = 'loading' | 'loaded' | 'failed';

/** How long the first load may take before the page says it couldn't load. */
export const LOAD_TIMEOUT_MS = 10_000;

/** How long the poll waits after each answer before it asks again (AD-12), so polls come one to two seconds apart. */
export const POLL_DELAY_MS = 1000;

/** What the page says, and the polite announcer reads, when the snapshot did not load. */
export const LOAD_FAILED = "Couldn't load your session.";

/**
 * The page's one live-state service. It loads the snapshot (`/state`) once per page load and every consumer reads it from
 * here; once loaded it polls `/events` with the two cursors, one at a time, waiting POLL_DELAY_MS after each answer, and
 * applies the events to the store idempotently. A skipped Seq or a new epoch loads the snapshot again and keeps the status
 * loaded. Nothing here moves keyboard focus.
 *
 * With no answer by LOAD_TIMEOUT_MS, or with an error answer, the status is failed and the polite announcer says so once;
 * a late answer still loads. retry() asks again, and says so again when that fails. A 401 is the session gate's: this
 * service neither fails nor announces for it. stop() ends the polling and drops what is in flight.
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
  private readonly inFlight = new Set<Subscription>();

  /**
   * The snapshot as /state last answered, once it has loaded. Its chat, rail, telegram and status are not kept up to date by
   * events: views read those from `store`.
   */
  readonly snapshot = signal<StateSnapshot | undefined>(undefined);

  /** Loading until the snapshot answers, then loaded or failed. */
  readonly status = signal<SnapshotStatus>('loading');

  /** The live store: the snapshot's state with the events applied. */
  readonly store = signal<LiveStore | undefined>(undefined);

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

  /** Ends the polling and drops every request in flight. Nothing is loaded or polled after it. */
  stop(): void {
    this.stopped = true;
    this.clearTimers();
    for (const subscription of this.inFlight) {
      subscription.unsubscribe();
    }
    this.inFlight.clear();
  }

  /** Sends a /state request. onError gets any answer but a 401; onApplied runs after a good answer was applied. */
  private fetchSnapshot(onError: () => void, onApplied?: () => void): void {
    if (this.stopped) {
      return;
    }
    const request = ++this.issued;
    const subscription = this.api.state().subscribe({
      next: (snapshot) => {
        if (this.stopped) {
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
        onError();
      },
    });
    this.track(subscription);
  }

  /** Takes a snapshot in: the page is loaded, and the poll runs. */
  private accept(snapshot: StateSnapshot): void {
    if (this.loadTimer !== undefined) {
      globalThis.clearTimeout(this.loadTimer);
      this.loadTimer = undefined;
    }
    this.snapshot.set(snapshot);
    this.store.set(fromSnapshot(snapshot));
    this.status.set('loaded');
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
    this.pollTimer = globalThis.setTimeout(() => {
      this.pollTimer = undefined;
      this.poll();
    }, POLL_DELAY_MS);
  }

  /** One poll with the current cursors; the next one is scheduled when this one has answered, good or not. */
  private poll(): void {
    const store = this.store();
    if (this.stopped || !store) {
      return;
    }
    const subscription = this.api.events(store.cursors.session, store.cursors.instance).subscribe({
      next: (response) => this.applyPoll(response),
      error: () => this.schedulePoll(),
    });
    this.track(subscription);
  }

  /** Applies a poll's events; a reload result loads the snapshot again, with the status kept at loaded. */
  private applyPoll(response: EventsResponse): void {
    const current = this.store();
    if (this.stopped || !current) {
      return;
    }
    const result = applyEvents(current, response);
    if (result.reload) {
      this.fetchSnapshot(
        () => this.schedulePoll(),
        () => this.schedulePoll(),
      );
      return;
    }
    if (result.store !== current) {
      this.store.set(result.store);
    }
    this.schedulePoll();
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
