import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';

import { Icon } from '../icon/icon';
import type { Cost, DecisionPayload } from '../live/payloads';
import { PAGE_TEXTS, REASON_KEYS } from '../msg/catalog';
import { DecisionDetails } from './decision-details';
import { confidenceText, DECISION_TEXTS, formatCost, outcomeOf, reasonLines, sentenceOf } from './decision-view';
import { FallbackFlag } from './fallback-flag';
import { meaningOf, OutcomeChip } from './outcome-chip';

/** The last id handed to a strip, for the ids its name, description and details panel are referenced by. */
let lastId = 0;

/** The newest strip of the chat shows this many reason lines, and every other strip shows the first. */
const NEWEST_LINES = 3;

/**
 * The decision strip (UX-DR61, UX-DR62, UX-DR64, FR-1, FR-2, FR-4) under a reply: why OcuTalon answered as it did, what it cost.
 * - Line 1: the outcome chip (Tell now on a fallback, no chip for an outcome the page does not know), the Fallback flag on a
 *   fallback, then "Confidence 0.92" and the cost, joined by a decorative middle dot. A fallback omits the confidence, and the cost
 *   is the one given (the turn's, for a reply).
 * - Line 2: the reason lines, a fallback's reason as a sentence first and in the warning colour, then the decision's reasons: three
 *   lines on the newest strip, the first line only, on one line with an ellipsis, on the others.
 * - Last, when there is a decision, the Details button named "Decision details": it opens the details inline below, with
 *   aria-expanded; Esc collapses them and focus stays on the button.
 * The strip is a group named by its chip's label and described by the outcome's meaning, from a hidden element. A fallback with no
 * decision has the chip, the flag and the reason alone. It is not a live region, and nothing here moves focus. Every text is bound by
 * interpolation.
 */
@Component({
  selector: 'app-decision-strip',
  imports: [DecisionDetails, FallbackFlag, Icon, OutcomeChip],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="strip"
      role="group"
      [attr.aria-labelledby]="chip() ? chipId : null"
      [attr.aria-describedby]="chip() ? descriptionId : null"
      (keydown.escape)="collapse()"
    >
      <div class="line1">
        @if (chip(); as outcome) {
          <span [id]="chipId"><app-outcome-chip [outcome]="outcome" /></span>
        }
        @if (fallback()) {
          <app-fallback-flag />
        }
        @if (meta().length > 0) {
          <span class="meta">
            @for (item of meta(); track $index) {
              @if ($index > 0) {
                <span aria-hidden="true">{{ separator }}</span>
              }
              <span class="item">{{ item }}</span>
            }
          </span>
        }
      </div>
      <div class="line2" [class.collapsed]="!newest()">
        @if (lines().length > 0) {
          <div class="reasons">
            @for (line of lines(); track $index) {
              <p class="reason" [class.fallback]="$index === 0 && fallbackLine()">{{ line }}</p>
            }
          </div>
        }
        @if (decision()) {
          <button
            type="button"
            class="details-button"
            [attr.aria-label]="texts.detailsName"
            [attr.aria-expanded]="open()"
            [attr.aria-controls]="detailsId"
            (click)="open.set(!open())"
          >
            {{ texts.details }}
            <app-icon [name]="open() ? 'chevron-up' : 'chevron-down'" [size]="13" />
          </button>
        }
      </div>
      <div class="details" [id]="detailsId">
        @if (open() && decision(); as shown) {
          <app-decision-details [decision]="shown" [turnCost]="turnCost()" />
        }
      </div>
      <span hidden [id]="descriptionId">{{ description() }}</span>
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .strip {
      display: flex;
      flex-direction: column;
      gap: 6px;
      color: var(--decision-strip-foreground);
    }
    .line1 {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
      font-size: var(--decision-strip-typography-font-size);
      font-weight: var(--decision-strip-typography-font-weight);
      line-height: var(--decision-strip-typography-line-height);
    }
    .line2 {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: 2px;
      max-width: var(--chat-panel-text-max);
    }
    .details:empty {
      display: none;
    }
    .line2.collapsed {
      flex-direction: row;
      align-items: baseline;
      gap: 6px;
    }
    .reasons {
      min-width: 0;
      font-size: var(--decision-strip-reasons-typography-font-size);
      font-weight: var(--decision-strip-reasons-typography-font-weight);
      line-height: var(--decision-strip-reasons-typography-line-height);
    }
    .reason {
      margin: 0;
      overflow-wrap: anywhere;
    }
    .reason.fallback {
      color: var(--warning-ink);
    }
    .collapsed .reasons {
      flex: 0 1 auto;
    }
    .collapsed .reason {
      overflow: hidden;
      white-space: nowrap;
      text-overflow: ellipsis;
    }
    .details-button {
      display: inline-flex;
      align-items: center;
      flex: none;
      gap: 3px;
      min-height: var(--space-target-min);
      padding: 0 2px;
      border: 0;
      border-radius: var(--rounded-xs);
      background: none;
      color: var(--action-ink);
      font-family: var(--font-ui);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1.4;
      cursor: pointer;
    }
  `,
})
export class DecisionStrip {
  /** The decision the strip shows; none for a fallback that has no decision row. */
  readonly decision = input<DecisionPayload | undefined>();
  /** The cost for line 1: the turn's on a reply, the decision's own on a card. None leaves the cost out. */
  readonly cost = input<number | undefined>();
  /** The cost of the whole turn, which the details set beside the decision's. */
  readonly turnCost = input<Cost | undefined>();
  /** The fallback reason value when the strip is a fallback strip; undefined otherwise. */
  readonly fallbackReason = input<string | undefined>();
  /** True for the newest strip of the chat. */
  readonly newest = input(false);

  protected readonly texts = DECISION_TEXTS;
  protected readonly separator = DECISION_TEXTS.separator;
  protected readonly open = signal(false);
  private readonly id = ++lastId;
  protected readonly chipId = `strip-chip-${this.id}`;
  protected readonly descriptionId = `strip-description-${this.id}`;
  protected readonly detailsId = `strip-details-${this.id}`;

  protected readonly fallback = computed(() => this.fallbackReason() !== undefined);
  /** The chip: Tell now for a fallback, else the decision's outcome. */
  protected readonly chip = computed(() => outcomeOf(this.decision()?.outcome, this.fallback()));
  /** What the chip's outcome means, which describes the group. */
  protected readonly description = computed(() => {
    const chip = this.chip();
    return chip === undefined ? '' : meaningOf(chip);
  });

  /** The fallback's reason as a sentence, from the page's catalog; undefined when the strip is not a fallback strip. */
  private readonly fallbackSentence = computed(() => {
    const reason = this.fallbackReason();
    if (reason === undefined) {
      return undefined;
    }
    const suffix = Object.hasOwn(REASON_KEYS, reason) ? (REASON_KEYS[reason] ?? 'generic') : 'generic';
    return sentenceOf(PAGE_TEXTS[`fallbackReason.${suffix}`] ?? '');
  });
  protected readonly fallbackLine = computed(() => (this.fallbackSentence() ?? '') !== '');

  protected readonly lines = computed(() => reasonLines(this.decision()?.reasons, this.fallbackSentence(), this.newest() ? NEWEST_LINES : 1));

  /** The items after the chip and the flag: the confidence (not on a fallback) and the cost. */
  protected readonly meta = computed(() => {
    const items: string[] = [];
    const confidence = this.decision()?.confidence;
    if (!this.fallback() && confidence !== undefined) {
      items.push(confidenceText(confidence));
    }
    const cost = this.cost();
    if (cost !== undefined) {
      items.push(formatCost(cost));
    }
    return items;
  });

  /** Esc on the strip collapses the details when they are open; focus stays where it is. */
  protected collapse(): void {
    if (this.open()) {
      this.open.set(false);
    }
  }
}
