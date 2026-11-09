import { ChangeDetectionStrategy, Component, computed, DestroyRef, ElementRef, inject, signal } from '@angular/core';
import { forkJoin, type Subscription } from 'rxjs';

import { ApiClient } from '../../api/api-client';
import type { PrecedentRow } from '../../api/memory-card-types';
import { CHAT_TEXTS } from '../../chat/chat-view';
import { pageWhen } from '../../chat/page-time';
import { Dialogs } from '../../shared/dialogs';
import { FORGET_TITLE_ID, FORGOTTEN, ForgetDialog, ForgetTarget } from './forget-dialog';
import { forgetName, isToolRow, MEMORY_HEADING_ID, MEMORY_TEXTS, type MemoryTab, metaParts, nextTab } from './memory-card-view';

/** The count of the cards that have been made, which gives each one's ids a prefix of its own. */
let lastCard = 0;

/** The tabs, in order. */
const TABS: readonly MemoryTab[] = ['notes', 'answers'];

/** The notes of the two days, as the notes route served them. */
interface Notes {
  today: string[];
  yesterday: string[];
}

/** A row of the Your answers list: the served row, its meta parts and whether it is a tool call's. */
interface AnswerLine {
  row: PrecedentRow;
  meta: string[];
  tool: boolean;
}

/**
 * The Memory card (Story 41.6; FR-71, FR-72, AD-4, AD-28): the body of the rail's Memory section, with two ARIA tabs.
 * - Notes shows its intro, then the label "Today" with the lines of `GET /api/v1/memory/notes?day=today` and the label "Yesterday" with the
 *   lines of `?day=yesterday`, one list item per served line, as served. A day with no lines shows its empty text.
 * - Your answers shows its intro, then one row per row of `GET /api/v1/memory/precedents`, in served order: the summary, a tool call's note,
 *   the meta line (when, the channel as served, the answer word) and Forget. With no rows it shows its empty text. Forget opens the Forget
 *   dialog; a confirmed Forget removes the row at once, with no new read, and moves focus to the Memory heading once the dialog has given
 *   focus back.
 * - The card reads all three answers when it is made, and a tab again each time it is selected. While a panel's read has not answered, or
 *   failed, the panel shows its intro and nothing else, so that a failure never reads as "nothing" (AD-28); an empty text shows only after
 *   a read that answered. The card keeps nothing across page loads, filters and sorts nothing, and holds no session Ref.
 * - The tabs follow the device panel's: a tab list named by the Memory heading, roving tabindex, ArrowLeft and ArrowRight move focus to the
 *   other tab, wrap and select it; each panel is named by its tab. The card announces nothing and is no live region. Every text is bound by
 *   interpolation from memory-card-view.ts or is the server's.
 */
@Component({
  selector: 'app-memory-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="tabs" role="tablist" [attr.aria-labelledby]="headingId" (keydown)="onKey($event)">
      @for (tab of tabs; track tab) {
        <button
          type="button"
          role="tab"
          class="tab"
          [id]="tabId(tab)"
          [class.selected]="selected() === tab"
          [attr.aria-selected]="selected() === tab"
          [attr.aria-controls]="panelId(tab)"
          [attr.tabindex]="selected() === tab ? 0 : -1"
          (click)="choose(tab)"
        >
          {{ nameOf(tab) }}
        </button>
      }
    </div>
    <div class="panel" role="tabpanel" [id]="panelId('notes')" [attr.aria-labelledby]="tabId('notes')" [hidden]="selected() !== 'notes'">
      <p class="note">{{ texts.notesIntro }}</p>
      @if (notes(); as shown) {
        <h4 class="day">{{ texts.today }}</h4>
        @if (shown.today.length === 0) {
          <p class="note muted">{{ texts.notesEmpty }}</p>
        } @else {
          <ul class="lines">
            @for (line of shown.today; track $index) {
              <li>{{ line }}</li>
            }
          </ul>
        }
        <h4 class="day">{{ texts.yesterday }}</h4>
        @if (shown.yesterday.length === 0) {
          <p class="note muted">{{ texts.yesterdayEmpty }}</p>
        } @else {
          <ul class="lines">
            @for (line of shown.yesterday; track $index) {
              <li>{{ line }}</li>
            }
          </ul>
        }
      }
    </div>
    <div class="panel" role="tabpanel" [id]="panelId('answers')" [attr.aria-labelledby]="tabId('answers')" [hidden]="selected() !== 'answers'">
      <p class="note">{{ texts.answersIntro }}</p>
      @if (lines(); as shown) {
        @if (shown.length === 0) {
          <p class="note muted">{{ texts.answersEmpty }}</p>
        } @else {
          <ul class="rows">
            @for (line of shown; track line.row.ref) {
              <li class="row">
                <span class="title">{{ line.row.summary }}</span>
                @if (line.tool) {
                  <span class="detail">{{ texts.toolNote }}</span>
                }
                <span class="meta">
                  @for (part of line.meta; track $index) {
                    @if ($index > 0) {
                      <span aria-hidden="true">{{ separator }}</span>
                    }
                    <span>{{ part }}</span>
                  }
                </span>
                <button type="button" class="button button-ghost forget" [attr.aria-label]="nameFor(line.row)" (click)="ask(line.row, $event)">
                  {{ texts.forget }}
                </button>
              </li>
            }
          </ul>
        }
      }
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .tabs {
      display: flex;
      gap: var(--space-1);
      border-bottom: 1px solid var(--border);
    }
    .tab {
      display: inline-flex;
      align-items: center;
      min-height: var(--space-control-height-lg);
      min-width: 0;
      margin-bottom: -1px;
      padding: 0 var(--space-2);
      background: none;
      border: 0;
      border-bottom: 3px solid transparent;
      color: var(--device-tab-foreground);
      font-family: var(--font-ui);
      font-size: var(--device-tab-typography-font-size);
      font-weight: var(--device-tab-typography-font-weight);
      line-height: var(--device-tab-typography-line-height);
      cursor: pointer;
    }
    .tab.selected {
      color: var(--device-tab-foreground-selected);
      border-bottom-color: var(--action);
    }
    .panel {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      min-width: 0;
      padding-top: var(--space-2);
    }
    .panel[hidden] {
      display: none;
    }
    .note {
      margin: 0;
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .muted {
      color: var(--ink-muted);
    }
    .day {
      margin: var(--space-1) 0 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-caption-line-height);
    }
    .lines,
    .rows {
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .lines li {
      color: var(--ink);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
      font-variant-numeric: tabular-nums;
      overflow-wrap: anywhere;
    }
    .row {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      min-width: 0;
      padding: var(--space-1) 0;
    }
    .row + .row {
      border-top: var(--status-rail-section-divider);
    }
    .title {
      color: var(--ink);
      font-size: var(--status-rail-section-row-title-font-size);
      font-weight: var(--status-rail-section-row-title-font-weight);
      line-height: var(--status-rail-section-row-title-line-height);
      overflow-wrap: anywhere;
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
    .forget {
      margin-top: var(--space-1);
    }
  `,
})
export class MemoryCard {
  private readonly api = inject(ApiClient);
  private readonly dialogs = inject(Dialogs);
  private readonly target = inject(ForgetTarget);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  protected readonly texts = MEMORY_TEXTS;
  protected readonly headingId = MEMORY_HEADING_ID;
  protected readonly separator = CHAT_TEXTS.separator;
  protected readonly tabs = TABS;

  /** The ids of this card's elements, which no other card of the page shares. */
  private readonly prefix = `memory-card-${(lastCard += 1)}`;
  protected readonly tabId = (tab: MemoryTab): string => `${this.prefix}-tab-${tab}`;
  protected readonly panelId = (tab: MemoryTab): string => `${this.prefix}-panel-${tab}`;

  protected readonly selected = signal<MemoryTab>('notes');

  /** The notes of both days, or none before the read answers and after a failed one. */
  protected readonly notes = signal<Notes | undefined>(undefined);
  /** The session's precedents, or none before the read answers and after a failed one. */
  private readonly answers = signal<PrecedentRow[] | undefined>(undefined);

  /** The rows of Your answers with their meta parts, in served order. */
  protected readonly lines = computed<AnswerLine[] | undefined>(() => {
    const now = Date.now();
    return this.answers()?.map((row) => ({ row, meta: metaParts(row, pageWhen(row.answeredAt, now)), tool: isToolRow(row) }));
  });

  private notesRead: Subscription | undefined;
  private answersRead: Subscription | undefined;

  constructor() {
    this.readNotes();
    this.readAnswers();
    inject(DestroyRef).onDestroy(() => {
      this.notesRead?.unsubscribe();
      this.answersRead?.unsubscribe();
    });
  }

  protected nameOf(tab: MemoryTab): string {
    return tab === 'notes' ? MEMORY_TEXTS.notes : MEMORY_TEXTS.answers;
  }

  protected nameFor(row: PrecedentRow): string {
    return forgetName(row.summary);
  }

  /** A click on a tab: the user's own selection. */
  protected choose(tab: MemoryTab): void {
    if (this.selected() === tab) {
      return;
    }
    this.selected.set(tab);
    this.readTab(tab);
  }

  /** Left and right arrows move from the focused tab to the other one, focusing and selecting it; they wrap, and no other key is handled. */
  protected onKey(event: KeyboardEvent): void {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
      return;
    }
    event.preventDefault();
    const focused = TABS.find((tab) => this.tabId(tab) === (event.target as HTMLElement | null)?.id) ?? this.selected();
    const next = nextTab(focused);
    this.choose(next);
    this.host.nativeElement.querySelector<HTMLElement>(`#${this.tabId(next)}`)?.focus();
  }

  /** Opens the Forget dialog for the row; the button that opened it gets focus back when the dialog closes without forgetting. */
  protected ask(row: PrecedentRow, event: Event): void {
    this.target.ref.set(row.ref);
    const ref = this.dialogs.open(ForgetDialog, { labelledBy: FORGET_TITLE_ID, restoreFocus: event.currentTarget as HTMLElement });
    ref.closed.subscribe((result) => {
      if (result === FORGOTTEN) {
        this.gone(row.ref);
      }
    });
  }

  /** The answer is gone: its row leaves with no new read, and focus goes to the Memory heading once the dialog has given focus back. */
  private gone(ref: string): void {
    this.answers.update((list) => list?.filter((one) => one.ref !== ref));
    globalThis.setTimeout(() => this.heading()?.focus(), 0);
  }

  /** The Memory heading of the rail section that holds the card. */
  private heading(): HTMLElement | null {
    return this.host.nativeElement.closest('app-status-rail')?.querySelector<HTMLElement>(`#${MEMORY_HEADING_ID}`) ?? null;
  }

  private readTab(tab: MemoryTab): void {
    if (tab === 'notes') {
      this.readNotes();
    } else {
      this.readAnswers();
    }
  }

  /** Reads both days; the panel shows them only when both answered. */
  private readNotes(): void {
    this.notesRead?.unsubscribe();
    this.notes.set(undefined);
    this.notesRead = forkJoin({ today: this.api.memoryNotes('today'), yesterday: this.api.memoryNotes('yesterday') }).subscribe({
      next: ({ today, yesterday }) => this.notes.set({ today: today.lines, yesterday: yesterday.lines }),
      error: () => this.notes.set(undefined),
    });
  }

  private readAnswers(): void {
    this.answersRead?.unsubscribe();
    this.answers.set(undefined);
    this.answersRead = this.api.precedents().subscribe({
      next: (list) => this.answers.set(list.precedents),
      error: () => this.answers.set(undefined),
    });
  }
}
