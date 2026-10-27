import { ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, signal, untracked } from '@angular/core';

import { CHAT_TEXTS, NOTICE_TEXTS } from '../chat/chat-view';
import { fallbackSentence } from '../chat/decision-strip';
import { confidenceText, DECISION_TEXTS, formatCost, outcomeOf, reasonLines } from '../chat/decision-view';
import { countdownText, pageWhen } from '../chat/page-time';
import type { TelegramState } from '../api/api-types';
import { LiveState } from '../live/live-state';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { Popovers } from '../shared/popover';
import { TraceLink } from '../shared/trace-link';
import { DecisionRow } from './decision-row';
import { type RailFormat, railView, type RailView } from './rail-view';
import { TelegramCard } from './telegram-card/telegram-card';

/** The clock ticks every second while a reminder shows a countdown, and every minute otherwise, for the day words. */
const FAST_TICK_MS = 1000;
const SLOW_TICK_MS = 60_000;

const NO_VIEW: RailView = { sections: [], telegramShown: false };

const TELEGRAM_OFF: TelegramState = { included: false, state: 'off', botUserName: '', paired: false, displayName: '', pausedUntil: '' };

/** The attribute that marks a row element with its key, and the one that names its section, for the focus rule. */
const ROW_KEY = 'data-row-key';
const ROW_SECTION = 'data-section';

/** The id of a section's heading. */
const headingId = (section: string): string => `rail-heading-${section}`;

/**
 * Where focus goes when the row that holds it, or a control in it (a trace link, the help it opened), leaves (UX-DR131): the
 * heading of the row's section. A row that is still there keeps it.
 */
const FOCUS_RULE: FocusRule = {
  item: `[${ROW_KEY}]`,
  keyOf: (row) => row.getAttribute(ROW_KEY) ?? '',
  whenGone: ({ host, item }) => host.querySelector<HTMLElement>(`#${headingId(item.getAttribute(ROW_SECTION) ?? '')}`),
};

/** The values railView reuses, from the real modules, with the times counted from now. */
function formatAt(now: number): RailFormat {
  return {
    when: (iso) => pageWhen(iso, now),
    countdown: (dueIso) => countdownText(dueIso, now),
    cost: formatCost,
    confidence: confidenceText,
    reasonLines,
    outcome: outcomeOf,
    fallbackSentence,
    separator: CHAT_TEXTS.separator,
    due: NOTICE_TEXTS.due,
    words: { passed: DECISION_TEXTS.passed, failed: DECISION_TEXTS.failed, notChecked: DECISION_TEXTS.notChecked },
  };
}

/**
 * The status rail (UX-DR51 to UX-DR57, FR-12): the sections of the live store, in order, as rail-view.ts shows them. Each list section
 * has an h3 with a live count (the visible "Background checks (1)" is hidden from assistive technology beside the spoken "Background
 * checks, 1"), its rows and, under an empty list, its empty text; the hints sit under the check and reminder lists. The Telegram
 * section comes first, only when the release includes it, with the Telegram card and no count.
 * - Rows are read-only: an approval row with a 3px attention bar, a check row, a reminder row with a ticking countdown in tabular
 *   figures, and a decision row as a disclosure. A row whose payload has a traceUrl ends its meta line with a trace link.
 * - A clock ticks every second while a countdown shows and every 60 seconds otherwise.
 * - When an update removes the row that holds focus (or the trace help that a row's link opened), focus moves to that section's
 *   heading without scrolling, through the page's focus rule (shared/focus-rule.ts); nothing else here moves focus. The headings
 *   take focus (tabindex -1) but are not in the tab order.
 * - The rail has no live region and announces nothing. Every text is bound by interpolation.
 */
@Component({
  selector: 'app-status-rail',
  imports: [DecisionRow, TelegramCard, TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (section of view().sections; track section.id) {
      <div class="section" [attr.data-section]="section.id">
        <h3 class="heading" tabindex="-1" [id]="headingId(section.id)">
          @if (section.count === undefined) {
            <span>{{ section.heading }}</span>
          } @else {
            <span aria-hidden="true">{{ section.heading }}</span>
            <span class="visually-hidden">{{ section.spoken }}</span>
          }
        </h3>
        @if (section.id === 'telegram') {
          <app-telegram-card [telegram]="telegram()" />
        } @else {
          @if (section.rows.length === 0) {
            <p class="empty">{{ section.empty }}</p>
          } @else {
            <ul class="rows">
              @for (row of section.rows; track row.key) {
                <li class="row" [class.request]="row.kind === 'approval'" [attr.data-row-key]="row.key" [attr.data-section]="section.id">
                  @if (row.decision) {
                    <app-decision-row [row]="row" />
                  } @else {
                    <span class="title">
                      <span class="lead">{{ row.lead }}</span>
                      @if (row.countdown; as countdown) {
                        <span aria-hidden="true">{{ separator }}</span>
                        <span class="countdown" aria-hidden="true">{{ countdown.text }}</span>
                        <span class="visually-hidden"> {{ countdown.spoken }}</span>
                      }
                    </span>
                    @if (row.detail) {
                      <span class="detail">{{ row.detail }}</span>
                    }
                    @if (row.meta.length > 0 || row.traceUrl) {
                      <span class="meta">
                        @for (part of row.meta; track $index) {
                          @if ($index > 0) {
                            <span aria-hidden="true">{{ separator }}</span>
                          }
                          <span>{{ part }}</span>
                        }
                        @if (row.traceUrl; as url) {
                          @if (row.meta.length > 0) {
                            <span aria-hidden="true">{{ separator }}</span>
                          }
                          <app-trace-link [url]="url" />
                        }
                      </span>
                    }
                  }
                </li>
              }
            </ul>
          }
          @if (section.hint !== '') {
            <p class="hint">{{ section.hint }}</p>
          }
        }
      </div>
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .heading {
      margin: 0 0 var(--space-1);
      color: var(--status-rail-section-heading-color);
      font-size: var(--status-rail-section-heading-font-size);
      font-weight: var(--status-rail-section-heading-font-weight);
      line-height: var(--status-rail-section-heading-line-height);
      letter-spacing: var(--status-rail-section-heading-letter-spacing);
      text-transform: uppercase;
    }
    .rows {
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .row {
      display: flex;
      flex-direction: column;
      min-width: 0;
      padding: var(--space-1) 0;
    }
    .row + .row {
      border-top: var(--status-rail-section-divider);
    }
    .row.request {
      padding-left: 9px;
      border-left: 3px solid var(--attention);
    }
    .title {
      color: var(--ink);
      font-size: var(--status-rail-section-row-title-font-size);
      font-weight: var(--status-rail-section-row-title-font-weight);
      line-height: var(--status-rail-section-row-title-line-height);
      overflow-wrap: anywhere;
    }
    .countdown {
      font-variant-numeric: tabular-nums;
    }
    .detail {
      color: var(--ink);
      font-size: var(--status-rail-section-row-typography-font-size);
      font-weight: var(--status-rail-section-row-typography-font-weight);
      line-height: var(--status-rail-section-row-typography-line-height);
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
    .empty,
    .hint {
      margin: 0;
      color: var(--ink-muted);
    }
    .empty {
      font-size: var(--status-rail-section-row-typography-font-size);
      line-height: var(--status-rail-section-row-typography-line-height);
    }
    .hint {
      margin-top: 2px;
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
  `,
})
export class StatusRail {
  private readonly live = inject(LiveState);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);

  protected readonly separator = CHAT_TEXTS.separator;
  protected readonly headingId = headingId;

  /** The 1 s or 60 s clock; the view reads the time itself when it recomputes. */
  private readonly clock = signal(0);

  /** True while a pending reminder with a due time shows a countdown. */
  private readonly counting = computed(() =>
    Object.values(this.live.store()?.reminders ?? {}).some((reminder) => reminder.state === 'pending' && (reminder.dueAt ?? '') !== ''),
  );

  protected readonly telegram = computed(() => this.live.store()?.telegram ?? TELEGRAM_OFF);

  protected readonly view = computed(() => {
    const store = this.live.store();
    if (store === undefined) {
      return NO_VIEW;
    }
    this.clock();
    return railView(store, formatAt(Date.now()), this.live.snapshot()?.demoMode === true);
  });

  constructor() {
    effect((onCleanup) => {
      const id = globalThis.setInterval(() => this.clock.update((tick) => tick + 1), this.counting() ? FAST_TICK_MS : SLOW_TICK_MS);
      onCleanup(() => globalThis.clearInterval(id));
    });
    effect(() => {
      this.view();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, FOCUS_RULE));
    });
  }
}
