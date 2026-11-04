import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, DestroyRef, inject, input, signal } from '@angular/core';
import { catchError, finalize, type Observable, of, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { Announcer } from '../shared/announcer';
import { InlineNotice } from '../shared/inline-notice';
import { BUSY_NOTICE, ServerButton } from '../shared/server-button';
import { Dismissals } from './dismissals';
import { INCIDENT_TEXTS } from './incident-view';

/** The last id handed to a Dismiss, for the id of its notice. */
let lastId = 0;

/** What a Dismiss acts on: the incident's Ref, and the card's view key (`incident:<ref>`, incidentView's key), which the chat's focus rule finds the card by. */
export interface DismissTarget {
  ref: string;
  key: string;
}

/** The message of an error reply (`error.message` of the body), else "". */
function messageOf(error: unknown): string {
  if (!(error instanceof HttpErrorResponse) || error.status === 0) {
    return '';
  }
  const body: unknown = error.error;
  const inner = body !== null && typeof body === 'object' ? (body as { error?: unknown }).error : undefined;
  const message = inner !== null && typeof inner === 'object' ? (inner as { message?: unknown }).message : undefined;
  return typeof message === 'string' ? message.trim() : '';
}

/**
 * Dismiss (Story 6.4; FR-24, UX-DR72): the ghost button that closes an incident that is resolved or open. It is a ServerButton, so a
 * press is one call under the busy rule (a spinner, aria-busy, aria-disabled and never `disabled`; a repeat press sends nothing; with
 * no answer in 10 s the button is restored and the busy notice is shown and announced, and a later answer still counts). The call is
 * the dismiss route with an empty body: the incident is in the path and the session is the caller's.
 * - The press is recorded in Dismissals until its reply comes, so that the owner's closed event, which can reach the page before the
 *   200, is not announced either.
 * - A 200 records the incident as closed by this page (Dismissals); the chat then compacts the card in place and moves focus to its
 *   headline (the chat panel's focus rule keeps the focus: this component moves none), and nothing is announced.
 * - An error reply shows its `error.message` in a warning notice beside the button, announced once, and the card stays as it is; a
 *   reply that never came (status 0) shows the busy notice at once. A new press clears the notice. A reply that comes after the
 *   Dismiss is gone shows and announces nothing.
 * The host carries `data-part="dismiss"` and the card's view key, so that the chat's focus rule finds the button's item.
 */
@Component({
  selector: 'app-incident-dismiss',
  imports: [InlineNotice, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-server-button
      variant="ghost"
      data-part="dismiss"
      [attr.data-key]="target().key"
      [action]="press"
      [describedBy]="notice() === '' ? [] : [noticeId]"
    >
      {{ texts.dismiss }}
    </app-server-button>
    @if (notice(); as text) {
      <app-inline-notice class="notice" variant="warning" [id]="noticeId">{{ text }}</app-inline-notice>
    }
  `,
  styles: `
    :host {
      display: inline-flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
    }
    .notice {
      flex: 1 1 14rem;
      min-width: 0;
    }
  `,
})
export class IncidentDismiss {
  /** The incident to dismiss and the card's view key. */
  readonly target = input.required<DismissTarget>();

  protected readonly texts = INCIDENT_TEXTS;
  protected readonly noticeId = `incident-dismiss-notice-${(lastId += 1)}`;
  /** The notice beside the button: the last error reply's message, else "". */
  protected readonly notice = signal('');

  private readonly api = inject(ApiClient);
  private readonly dismissals = inject(Dismissals);
  private readonly announcer = inject(Announcer);

  /** False once the Dismiss is gone (its card compacted or left the chat): a reply that comes later shows and announces nothing. */
  private shown = true;

  constructor() {
    inject(DestroyRef).onDestroy(() => (this.shown = false));
  }

  /**
   * The press: one POST, recorded in Dismissals from the press until its reply. A 200 closes the card; an error reply sets the
   * notice, which is announced once, while the Dismiss is still shown.
   */
  protected readonly press = (): Observable<unknown> => {
    this.notice.set('');
    const ref = this.target().ref;
    this.dismissals.pressed(ref);
    return this.api.dismissIncident(ref).pipe(
      tap(() => this.dismissals.add(ref)),
      catchError((error: unknown) => {
        if (this.shown) {
          const text = messageOf(error) || BUSY_NOTICE;
          this.notice.set(text);
          this.announcer.announce(text);
        }
        return of(undefined);
      }),
      finalize(() => this.dismissals.settled(ref)),
    );
  };
}
