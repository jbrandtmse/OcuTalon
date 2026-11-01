import { ChangeDetectionStrategy, Component, computed, inject, input } from '@angular/core';

import { AllowanceState } from '../live/allowance-state';
import { LiveState } from '../live/live-state';
import { DemoView } from '../shared/demo-view';
import { ChatOutbox } from './chat-outbox';
import { COMPOSER_REASON_ID } from './composer';
import { TRY_IT_TEXTS, turnInFlight } from './try-it-view';

/** The count that gives each row its own label id, because the empty chat and the finish state can both show a row. */
let rows = 0;

/**
 * The "Try it yourself" row (Story 4.10; EXPERIENCE: Demo guide and controls): a labelled group of four example prompts, one native
 * button each, named by its text alone. It renders only in the demo view (DemoView.on()), after the finish state's "More to try"
 * line and after the empty chat's last line. The label is a paragraph, never a heading: the page's heading lists are pinned.
 *
 * A press sends the chip's text through ChatOutbox.send, the composer's own path: a new message of the user's, not from the guide, that
 * counts against the session's message allowance. While a turn is in flight (turn-in-flight reader in try-it-view.ts) or the allowance
 * is used up, every chip is aria-disabled, never disabled, so it stays focusable and keeps the focus a press gave it, and a press
 * sends nothing; while the allowance is used up the chips are also described by the composer's reason. The row announces nothing and
 * moves no focus.
 */
@Component({
  selector: 'app-try-it-row',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (demoView.on()) {
      <div class="row" role="group" [attr.aria-labelledby]="labelId" [class.centered]="centered()">
        <p class="try-label" [id]="labelId">{{ texts.label }}</p>
        <div class="try-chips">
          @for (prompt of texts.prompts; track prompt) {
            <button
              type="button"
              class="button try-chip"
              [attr.aria-disabled]="blocked() ? 'true' : null"
              [attr.aria-describedby]="describedBy()"
              (click)="press(prompt)"
            >{{ prompt }}</button>
          }
        </div>
      </div>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .row {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-2);
      margin-top: var(--space-3);
    }
    .row.centered {
      align-items: center;
    }
    .try-label {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .try-chips {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-2);
    }
    .centered .try-chips {
      justify-content: center;
    }
    /* The actionable chip of DESIGN (sample-email-chip): a bordered pill, with no icon. */
    .try-chip {
      min-height: var(--space-target-min);
      padding: 0 var(--space-3);
      background: var(--sample-email-chip-background);
      color: var(--sample-email-chip-foreground);
      border: var(--sample-email-chip-border);
      border-radius: var(--sample-email-chip-radius);
    }
    .try-chip:hover:not([aria-disabled='true']) {
      background: var(--sample-email-chip-background-hover);
    }
  `,
})
export class TryItRow {
  protected readonly demoView = inject(DemoView);
  private readonly live = inject(LiveState);
  private readonly outbox = inject(ChatOutbox);
  private readonly allowance = inject(AllowanceState);

  /** True when the row sits in the empty chat, where its chips are centred; else they start at the row's edge. */
  readonly centered = input(false);

  protected readonly texts = TRY_IT_TEXTS;
  protected readonly labelId = `try-it-label-${++rows}`;

  /** True while a turn of this page is in flight. */
  private readonly inFlight = computed(() => turnInFlight(this.live.store()?.chat ?? [], this.outbox.entries()));

  /** True while the session's message allowance is used up. */
  private readonly used = computed(() => this.allowance.active() !== undefined);

  /** True while a press sends nothing. */
  protected readonly blocked = computed(() => this.inFlight() || this.used());

  /** The composer's reason, while the allowance is used up; else none. */
  protected readonly describedBy = computed(() => (this.used() ? COMPOSER_REASON_ID : null));

  /** Sends the chip's text as the user's own message; nothing is sent while a turn is in flight or the allowance is used up. */
  protected press(text: string): void {
    if (this.blocked()) {
      return;
    }
    this.outbox.send(text);
  }
}
