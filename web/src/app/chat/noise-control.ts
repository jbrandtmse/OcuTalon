import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, Injector, computed, effect, inject, input, signal, untracked } from '@angular/core';
import { catchError, type Observable, of, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { NoiseChannel } from '../api/memory-types';
import { messageOf } from '../incidents/incident-dismiss';
import { LiveState } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { InlineNotice } from '../shared/inline-notice';
import { Popovers } from '../shared/popover';
import { isViewer } from '../shared/viewer-view';
import { BUSY_NOTICE, ServerButton } from '../shared/server-button';
import { markedLine, NOISE_TEXTS } from './noise-view';
import { pageTimeBeside } from './page-time';

/** The last id handed to a control, for the id of its notice. */
let lastId = 0;

/**
 * Where focus goes when an update replaces the button that holds it: the button and the status line that replaces it share one container, which is
 * the item of the rule and carries the decision's Ref as its key, so the shared rule finds the container (tabindex -1). The shape of the phone
 * request's PHONE_ANSWER_RULE.
 */
export const NOISE_RULE: FocusRule = {
  item: '[data-noise]',
  keyOf: (item) => item.getAttribute('data-noise') ?? '',
};

/**
 * "This was noise" (Story 41.5; FR-72, NFR-25): the ghost button on the person's own tell-now notice, in the web chat and on the simulated phone. It is a
 * ServerButton, so a press is one call under the busy rule (a repeat press sends nothing; with no answer in 10 s the busy notice shows). The call is the
 * noise route with the channel of the place it sits in.
 * - A 200 replaces the button with the status line "Marked as noise at {time}. Similar items will take this into account.", the time being the first
 *   mark's in the page's time (a repeat shows the first mark's time too). The line is plain text, not a live region. When it replaces the button
 *   that holds focus, the shared focus rule moves focus to the container; this component moves none.
 * - An error reply shows its `error.message` in a warning notice beside the button, announced once, and the button stays; a reply that never came
 *   (status 0) shows the busy notice. A new press clears the notice. This is IncidentDismiss's rule.
 * With no decision Ref the control renders nothing.
 */
@Component({
  selector: 'app-noise-control',
  imports: [InlineNotice, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (decisionRef()) {
      <div class="noise" [attr.data-noise]="decisionRef()" tabindex="-1">
        @if (markedAt()) {
          <p class="marked">{{ line() }}</p>
        } @else if (!viewer()) {
          <app-server-button variant="ghost" [action]="press" [describedBy]="notice() === '' ? [] : [noticeId]">{{ texts.label }}</app-server-button>
        }
        @if (notice(); as text) {
          <app-inline-notice class="notice" variant="warning" [id]="noticeId">{{ text }}</app-inline-notice>
        }
      </div>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .noise {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
    }
    .marked {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
      overflow-wrap: anywhere;
    }
    .notice {
      flex: 1 1 14rem;
      min-width: 0;
    }
  `,
})
export class NoiseControl {
  /** The Ref of the decision to mark; with "" nothing renders. */
  readonly decisionRef = input('');
  /** Where the control sits: the channel its press names. */
  readonly channel = input.required<NoiseChannel>();
  /** The instance's time zone, from the snapshot: the status line's time names the browser's zone when its offset differs. */
  readonly instanceZone = input('');

  protected readonly texts = NOISE_TEXTS;
  protected readonly noticeId = `noise-control-notice-${(lastId += 1)}`;
  /** The notice beside the button: the last error reply's message, else "". */
  protected readonly notice = signal('');
  /** The first mark's UTC time once a press was answered 200, else "". */
  protected readonly markedAt = signal('');
  /** The status line that replaces the button. */
  protected readonly line = computed(() => markedLine(this.markedAt(), this.instanceZone(), pageTimeBeside));

  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  /** True for a viewer (Story 25.4): the button is not shown. */
  protected readonly viewer = computed(() => isViewer(this.live.snapshot()));
  private readonly announcer = inject(Announcer);
  private readonly popovers = inject(Popovers);
  private readonly injector = inject(Injector);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  /** False once the control is gone: a reply that comes later shows and announces nothing. */
  private shown = true;

  constructor() {
    inject(DestroyRef).onDestroy(() => (this.shown = false));
    effect(() => {
      this.markedAt();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, NOISE_RULE));
    });
  }

  /** The press: one POST. A 200 sets the mark's time; an error reply sets the notice, which is announced once, while the control is still shown. */
  protected readonly press = (): Observable<unknown> => {
    this.notice.set('');
    return this.api.markNoise(this.decisionRef(), this.channel()).pipe(
      tap((answer) => {
        if (this.shown) {
          this.markedAt.set(answer.markedAt);
        }
      }),
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
