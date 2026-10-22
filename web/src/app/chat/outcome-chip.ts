import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { Icon, type IconName } from '../icon/icon';
import { CHAT_TEXTS } from './chat-view';

/** The four attention outcomes. */
export type Outcome = 'ignore' | 'digest' | 'tell-now' | 'act';

const CHIPS: Readonly<Record<Outcome, { icon: IconName; label: string }>> = {
  ignore: { icon: 'eye-off', label: CHAT_TEXTS.chipIgnore },
  digest: { icon: 'inbox', label: CHAT_TEXTS.chipDigest },
  'tell-now': { icon: 'bell-ring', label: CHAT_TEXTS.chipTellNow },
  act: { icon: 'zap', label: CHAT_TEXTS.chipAct },
};

/**
 * The outcome chip (UX-DR63): a borderless pill with an icon (hidden from assistive technology) and the outcome's label, coloured
 * by the outcome-chip tokens. It is not focusable. Story 2.6 adds its tooltip and its place in the decision strip.
 */
@Component({
  selector: 'app-outcome-chip',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="chip" [class]="outcome()"><app-icon [name]="chip().icon" [size]="12" />{{ chip().label }}</span>`,
  styles: `
    :host {
      display: inline-flex;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      height: 22px;
      padding: 0 var(--space-2) 0 6px;
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1;
      white-space: nowrap;
    }
    .ignore {
      background: var(--outcome-chip-ignore-background);
      color: var(--outcome-chip-ignore-foreground);
      border-radius: var(--outcome-chip-ignore-radius);
    }
    .digest {
      background: var(--outcome-chip-digest-background);
      color: var(--outcome-chip-digest-foreground);
      border-radius: var(--outcome-chip-digest-radius);
    }
    .tell-now {
      background: var(--outcome-chip-tell-now-background);
      color: var(--outcome-chip-tell-now-foreground);
      border-radius: var(--outcome-chip-tell-now-radius);
    }
    .act {
      background: var(--outcome-chip-act-background);
      color: var(--outcome-chip-act-foreground);
      border-radius: var(--outcome-chip-act-radius);
    }
  `,
})
export class OutcomeChip {
  readonly outcome = input.required<Outcome>();
  protected readonly chip = computed(() => CHIPS[this.outcome()]);
}
