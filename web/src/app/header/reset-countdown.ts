import { ChangeDetectionStrategy, Component, computed, effect, inject, signal, untracked } from '@angular/core';

import { countdownSpokenMinutes, countdownText, pageTime } from '../chat/page-time';
import { LiveState } from '../live/live-state';
import { type PillFormat, pillDelayMs, pillView } from '../live/reset-schedule';
import { ResetWatch } from '../live/reset-watch';

/** The pill's texts, from the page's own time module. */
const FORMAT: PillFormat = {
  time: (iso) => pageTime(iso),
  countdown: countdownText,
  spoken: countdownSpokenMinutes,
};

/**
 * The reset countdown (UX-DR10, UX-DR14, UX-DR37, UX-DR124, UX-DR135; Story 16.8): a neutral pill in the header, "Next reset 16:00
 * \u00b7 in 1 h 42 min", on the online demo only and only while the page has a pending reset (ResetWatch). It is urgent
 * (`reset-countdown-urgent`) from 10 minutes before the reset. The visible text is hidden from assistive technology beside a
 * visually hidden twin in words of whole minutes, which changes only at whole-minute boundaries. The pill updates within a second
 * of each whole minute, every second in the last minute, and when it turns urgent. It is not a live region and says nothing by itself.
 */
@Component({
  selector: 'app-reset-countdown',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (pill(); as shown) {
      <span class="reset-countdown tabular" [class.reset-countdown-urgent]="shown.urgent">
        <span aria-hidden="true">{{ shown.text }}</span>
        <span class="visually-hidden">{{ shown.spoken }}</span>
      </span>
    }
  `,
  styles: `
    .reset-countdown {
      display: inline-block;
      padding: 2px var(--space-3);
      border-radius: var(--reset-countdown-radius);
      background: var(--reset-countdown-background);
      color: var(--reset-countdown-foreground);
      font-family: var(--reset-countdown-typography-font-family), var(--font-ui);
      font-size: var(--reset-countdown-typography-font-size);
      font-weight: var(--reset-countdown-typography-font-weight);
      line-height: var(--reset-countdown-typography-line-height);
      white-space: nowrap;
    }
    .reset-countdown-urgent {
      background: var(--reset-countdown-urgent-background);
      color: var(--reset-countdown-urgent-foreground);
    }
  `,
})
export class ResetCountdown {
  private readonly live = inject(LiveState);
  private readonly reset = inject(ResetWatch);

  /** The page's clock for the pill: bumped when the pill next changes. */
  private readonly clock = signal(0);

  protected readonly pill = computed(() => {
    this.clock();
    return pillView(this.live.snapshot()?.onlineDemo === true, this.reset.pending(), Date.now(), FORMAT);
  });

  constructor() {
    effect((onCleanup) => {
      this.clock();
      const pending = this.reset.pending();
      const onlineDemo = this.live.snapshot()?.onlineDemo === true;
      const wait = onlineDemo ? untracked(() => pillDelayMs(pending, Date.now())) : undefined;
      if (wait !== undefined) {
        const id = globalThis.setTimeout(() => this.clock.update((tick) => tick + 1), wait);
        onCleanup(() => globalThis.clearTimeout(id));
      }
    });
  }
}
