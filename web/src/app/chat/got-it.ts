import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, DestroyRef, computed, inject, input, signal } from '@angular/core';
import { catchError, type Observable, of } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { LiveState } from '../live/live-state';
import { PAGE_TEXTS } from '../msg/catalog';
import { Announcer } from '../shared/announcer';
import { InlineNotice } from '../shared/inline-notice';
import { isViewer } from '../shared/viewer-view';
import { BUSY_NOTICE, ServerButton } from '../shared/server-button';

/** The last id handed to a Got it, for the id of its notice. */
let lastId = 0;

/** The channel a Got it press comes from: the web chat's notice card, or the simulated phone's message. */
export type GotItChannel = 'web' | 'phone';

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
 * Got it (Story 18.4; FR-37, AD-14): the control of a tell-now notice, on the web chat's card and on the simulated phone's message. It is a
 * ServerButton labelled with the catalog text of `button.gotIt`, so a press is one call under the busy rule (a spinner, aria-busy,
 * aria-disabled and never `disabled`; a repeat press sends nothing; with no answer in 10 s the button is restored and the busy notice
 * is shown and announced). The call is the got-it route for the notice's Ref, with the channel of the host.
 * - A 200 changes nothing here: the server's handled notification replaces the control with the "Marked as handled at {time}" line on
 *   the card or the message, and the page decides nothing.
 * - An error reply shows its `error.message`, else the busy notice, in a warning notice beside the button, announced once; a new press clears it.
 */
@Component({
  selector: 'app-got-it',
  imports: [InlineNotice, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (!viewer()) {
      <app-server-button variant="secondary" data-part="got-it" [attr.data-ref]="ref()" [action]="press" [describedBy]="notice() === '' ? [] : [noticeId]">
        {{ label }}
      </app-server-button>
    }
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
export class GotIt {
  /** The notice's Ref: the Ref of the Decision behind it. */
  readonly ref = input.required<string>();
  /** Where the control stands: the web chat's card, or the simulated phone's message. */
  readonly channel = input<GotItChannel>('web');

  protected readonly label = PAGE_TEXTS['button.gotIt'];
  protected readonly noticeId = `got-it-notice-${(lastId += 1)}`;
  /** The notice beside the button: the last error reply's message, else "". */
  protected readonly notice = signal('');

  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  /** True for a viewer (Story 25.4): the button is not shown. */
  protected readonly viewer = computed(() => isViewer(this.live.snapshot()));
  private readonly announcer = inject(Announcer);

  /** False once the control is gone (the notice was marked): a reply that comes later shows and announces nothing. */
  private shown = true;

  constructor() {
    inject(DestroyRef).onDestroy(() => (this.shown = false));
  }

  /** The press: one POST. An error reply sets the notice, which is announced once, while the control is still shown. */
  protected readonly press = (): Observable<unknown> => {
    this.notice.set('');
    return this.api.gotIt(this.ref(), this.channel()).pipe(
      catchError((error: unknown) => {
        if (this.shown) {
          const text = messageOf(error) || BUSY_NOTICE;
          this.notice.set(text);
          this.announcer.announce(text);
        }
        return of(undefined);
      }),
    );
  };
}
