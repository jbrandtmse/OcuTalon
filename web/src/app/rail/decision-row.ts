import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';

import { CHAT_TEXTS } from '../chat/chat-view';
import { FallbackFlag } from '../chat/fallback-flag';
import { meaningOf, OutcomeChip } from '../chat/outcome-chip';
import { Icon } from '../icon/icon';
import { Popovers } from '../shared/popover';
import { TraceLink } from '../shared/trace-link';
import type { RailRow } from './rail-view';

/** The last id handed to a row, for the ids of the reasons its button controls and of the meaning that describes it. */
let lastId = 0;

/**
 * A decision row of the status rail (UX-DR57, UX-DR127, FR-1, FR-4): a disclosure of one attention decision.
 * - Line 1 is the whole-line button, with aria-expanded and aria-controls: the outcome chip (Tell now on a fallback), the Fallback flag
 *   on a fallback, the item's summary on one line with an ellipsis, and the chevron (hidden from assistive technology). With a chip,
 *   the button is described by the outcome's meaning from a hidden element, so the chip's pointer tooltip is never its only copy.
 * - Line 2 is the first reason line on one line with an ellipsis, a fallback's sentence first and in the warning colour. Expanded, every
 *   reason line replaces it in place. Esc inside the row collapses it and focus stays where it is, unless a popover is open: Esc then closes
 *   the popover alone (Popovers.hasOpen), and a tooltip that shows takes the Esc before either.
 * - The meta line holds the time, the confidence (not on a fallback) and the decision's own cost, then the trace link beside the
 *   button (never inside it) when the decision has a traceUrl.
 * Every text is bound by interpolation. The row is not a live region.
 */
@Component({
  selector: 'app-decision-row',
  imports: [FallbackFlag, Icon, OutcomeChip, TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="row" (keydown.escape)="collapse()">
      <button
        type="button"
        class="line1"
        [attr.aria-expanded]="open()"
        [attr.aria-controls]="reasonsId"
        [attr.aria-describedby]="decision().chip ? descriptionId : null"
        (click)="open.set(!open())"
      >
        @if (decision().chip; as chip) {
          <app-outcome-chip [outcome]="chip" />
        }
        @if (decision().fallback) {
          <app-fallback-flag />
        }
        <span class="summary">{{ row().title }}</span>
        <app-icon [name]="open() ? 'chevron-up' : 'chevron-down'" [size]="14" />
      </button>
      <span hidden [id]="descriptionId">{{ description() }}</span>
      <div class="reasons" [id]="reasonsId">
        @if (open()) {
          @for (line of decision().reasons; track $index) {
            <p class="reason" [class.fallback]="$index === 0 && decision().fallbackLine">{{ line }}</p>
          }
        } @else if (decision().firstReason !== '') {
          <p class="reason one-line" [class.fallback]="decision().fallbackLine">{{ decision().firstReason }}</p>
        }
      </div>
      @if (row().meta.length > 0 || row().traceUrl) {
        <div class="meta">
          @for (part of row().meta; track $index) {
            @if ($index > 0) {
              <span aria-hidden="true">{{ separator }}</span>
            }
            <span>{{ part }}</span>
          }
          @if (row().traceUrl; as url) {
            @if (row().meta.length > 0) {
              <span aria-hidden="true">{{ separator }}</span>
            }
            <app-trace-link [url]="url" />
          }
        </div>
      }
    </div>
  `,
  styles: `
    :host {
      display: block;
      min-width: 0;
    }
    .row {
      display: flex;
      flex-direction: column;
      gap: 2px;
      min-width: 0;
    }
    .line1 {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      width: 100%;
      min-width: 0;
      min-height: var(--space-target-min);
      padding: 0;
      border: 0;
      border-radius: var(--rounded-xs);
      background: none;
      color: var(--ink);
      font-family: var(--font-ui);
      font-size: var(--decision-row-typography-font-size);
      font-weight: var(--decision-row-typography-font-weight);
      line-height: var(--decision-row-typography-line-height);
      text-align: left;
      cursor: pointer;
    }
    .summary {
      flex: 1;
      min-width: 0;
      overflow: hidden;
      white-space: nowrap;
      text-overflow: ellipsis;
    }
    app-icon {
      flex: none;
      color: var(--ink-muted);
    }
    .reasons {
      color: var(--ink-muted);
      font-size: var(--decision-row-typography-font-size);
      line-height: var(--decision-row-typography-line-height);
    }
    .reason {
      margin: 0;
      overflow-wrap: anywhere;
    }
    .one-line {
      overflow: hidden;
      white-space: nowrap;
      text-overflow: ellipsis;
    }
    .reason.fallback {
      color: var(--warning-ink);
    }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1);
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
      line-height: var(--type-caption-line-height);
      font-variant-numeric: tabular-nums;
    }
  `,
})
export class DecisionRow {
  /** The decision row: its title is the item's summary. */
  readonly row = input.required<RailRow>();

  private readonly popovers = inject(Popovers);
  protected readonly separator = CHAT_TEXTS.separator;
  protected readonly open = signal(false);
  private readonly id = ++lastId;
  protected readonly reasonsId = `rail-reasons-${this.id}`;
  protected readonly descriptionId = `rail-description-${this.id}`;
  protected readonly decision = computed(() => this.row().decision ?? { chip: undefined, fallback: false, fallbackLine: false, firstReason: '', reasons: [] });
  /** The outcome's meaning, which describes the button; empty with no chip. */
  protected readonly description = computed(() => {
    const chip = this.decision().chip;
    return chip === undefined ? '' : meaningOf(chip);
  });

  /** Esc inside the row collapses it when it is open and no popover is; focus stays where it is. */
  protected collapse(): void {
    if (this.popovers.hasOpen()) {
      return;
    }
    if (this.open()) {
      this.open.set(false);
    }
  }
}
