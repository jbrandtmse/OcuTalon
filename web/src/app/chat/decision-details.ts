import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import type { Cost, DecisionPayload } from '../live/payloads';
import { costRow, DECISION_TEXTS, formatDuration, formatTokens, tokensLine } from './decision-view';

/**
 * The decision's details (UX-DR62): a grid of labels and values for the decision itself, never for a step. Tokens name the four
 * kinds with their thousands separators, in the monospace type; then the model's display name, the agent steps (0 when the
 * decision has none), the duration, the decision message's reference in the monospace type, and the cost, with the turn's cost
 * after the decision's when the turn cost more. The model, the duration and the reference are left out when the decision has none.
 * Every value is bound by interpolation.
 */
@Component({
  selector: 'app-decision-details',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <dl class="details">
      <dt>{{ texts.rowTokens }}</dt>
      <dd class="mono">{{ tokens() }}</dd>
      @if (decision().model) {
        <dt>{{ texts.rowModel }}</dt>
        <dd>{{ decision().model }}</dd>
      }
      <dt>{{ texts.rowSteps }}</dt>
      <dd>{{ steps() }}</dd>
      @if (duration(); as shown) {
        <dt>{{ texts.rowDuration }}</dt>
        <dd>{{ shown }}</dd>
      }
      @if (decision().ref) {
        <dt>{{ texts.rowMessage }}</dt>
        <dd class="mono">{{ decision().ref }}</dd>
      }
      <dt>{{ texts.rowCost }}</dt>
      <dd>{{ cost() }}</dd>
    </dl>
  `,
  styles: `
    :host {
      display: block;
    }
    .details {
      display: grid;
      grid-template-columns: max-content 1fr;
      gap: 3px 14px;
      align-items: baseline;
      margin: 0;
      padding: var(--space-2) var(--space-3);
      background: var(--sunken);
      border-radius: var(--rounded-sm);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    dt {
      color: var(--ink-muted);
    }
    dd {
      margin: 0;
      color: var(--ink);
      overflow-wrap: anywhere;
    }
    .mono {
      font-family: var(--font-mono);
      font-size: var(--type-mono-sm-font-size);
      line-height: var(--type-mono-sm-line-height);
    }
  `,
})
export class DecisionDetails {
  readonly decision = input.required<DecisionPayload>();
  /** The cost of the whole turn, when the decision belongs to a turn. */
  readonly turnCost = input<Cost | undefined>();
  protected readonly texts = DECISION_TEXTS;

  protected readonly tokens = computed(() => tokensLine(this.decision()));
  protected readonly steps = computed(() => formatTokens(this.decision().agentStepCount));
  protected readonly duration = computed(() => {
    const ms = this.decision().durationMs;
    return ms === undefined ? '' : formatDuration(ms);
  });
  protected readonly cost = computed(() => costRow(this.decision().costUSD, this.turnCost()?.costUSD));
}
