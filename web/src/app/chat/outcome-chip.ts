import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { Icon, type IconName } from '../icon/icon';
import { Tooltip } from '../shared/tooltip';
import { CHAT_TEXTS } from './chat-view';

/** The four attention outcomes. */
export type Outcome = 'ignore' | 'digest' | 'tell-now' | 'act';

const CHIPS: Readonly<Record<Outcome, { icon: IconName; label: string; meaning: string }>> = {
  ignore: { icon: 'eye-off', label: CHAT_TEXTS.chipIgnore, meaning: CHAT_TEXTS.meaningIgnore },
  digest: { icon: 'inbox', label: CHAT_TEXTS.chipDigest, meaning: CHAT_TEXTS.meaningDigest },
  'tell-now': { icon: 'bell-ring', label: CHAT_TEXTS.chipTellNow, meaning: CHAT_TEXTS.meaningTellNow },
  act: { icon: 'zap', label: CHAT_TEXTS.chipAct, meaning: CHAT_TEXTS.meaningAct },
};

/** What an outcome means in release 1, in the UX's words. */
export function meaningOf(outcome: Outcome): string {
  return CHIPS[outcome].meaning;
}

/**
 * The outcome chip (UX-DR63): a borderless pill with an icon (hidden from assistive technology) and the outcome's label, coloured
 * by the outcome-chip tokens. It is not focusable. A pointer resting on it for 300 ms shows a tooltip with the outcome's meaning,
 * wherever the chip renders; the tooltip never holds the only copy: the decision strip describes itself with the meaning, and the
 * empty chat panel prints it beside each chip.
 */
@Component({
  selector: 'app-outcome-chip',
  imports: [Icon, Tooltip],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="chip" [class]="outcome()" [appTooltip]="chip().meaning"><app-icon [name]="chip().icon" [size]="12" />{{ chip().label }}</span>`,
  styles: `
    :host {
      display: inline-flex;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      min-height: 22px;
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
