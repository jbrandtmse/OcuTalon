import { NgTemplateOutlet } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, computed, DestroyRef, ElementRef, inject, signal, viewChild } from '@angular/core';
import { catchError, forkJoin, type Observable, of, type Subscription, tap } from 'rxjs';

import { ApiClient } from '../../api/api-client';
import type { MemoryItem, PrecedentRow } from '../../api/memory-card-types';
import { CHAT_TEXTS } from '../../chat/chat-view';
import { pageWhen } from '../../chat/page-time';
import { messageOf } from '../../incidents/incident-dismiss';
import { LiveState } from '../../live/live-state';
import { Announcer } from '../../shared/announcer';
import { CONFIRM_TITLE_ID, CONFIRMED, ConfirmDialog, ConfirmRequest } from '../../shared/confirm-dialog';
import { Dialogs } from '../../shared/dialogs';
import { InlineNotice } from '../../shared/inline-notice';
import { ServerButton } from '../../shared/server-button';
import {
  forgetName,
  isToolRow,
  listMore,
  MEMORY_HEADING_ID,
  MEMORY_TABS,
  MEMORY_TEXTS,
  type MemoryTab,
  memoryName,
  metaParts,
  nextTab,
  sourceLabel,
  usedText,
} from './memory-card-view';

/** The count of the cards that have been made, which gives each one's ids a prefix of its own. */
let lastCard = 0;

/** The two panels whose rows carry Pin, Unpin and Forget. */
type MemoryPanel = 'pinned' | 'memories';

/** The Pinned panel's read: the pins, newest pin first, and the tokens the server counted for them. */
interface PinnedView {
  items: MemoryItem[];
  used: number;
}

/** The All memories panel's read: the newest memories (query "") or the matches of a search, and the count behind the list. */
interface ListingView {
  items: MemoryItem[];
  total: number;
  query: string;
}

/** A panel's one notice: its text, and the ref of the row whose button it explains ("" for the search). */
interface PanelNotice {
  ref: string;
  text: string;
}

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
 * The Memory card (Stories 41.6 and 41.13; FR-71 to FR-74, AD-4, AD-21, AD-28): the body of the rail's Memory section, with four ARIA tabs: Notes, Your
 * answers, Pinned and All memories.
 * - Notes shows its intro, then the label "Today" with the lines of `GET /api/v1/memory/notes?day=today` and the label "Yesterday" with the
 *   lines of `?day=yesterday`, one list item per served line, as served. A day with no lines shows its empty text.
 * - Your answers shows its intro, then one row per row of `GET /api/v1/memory/precedents`, in served order: the summary, a tool call's note,
 *   the meta line (when, the channel as served, the answer word) and Forget. With no rows it shows its empty text. Forget opens the Forget
 *   dialog; a confirmed Forget removes the row at once, with no new read, and moves focus to the Memory heading once the dialog has given
 *   focus back.
 * - Pinned shows its intro, then the figure "{used} of 1,000 tokens (estimated)." with the `used` that `GET /api/v1/memory/pinned` served (the page never
 *   computes it), then one row per pin, newest pin first, or "Nothing pinned yet. Pin a memory from All memories." for none.
 * - All memories shows a search form (a labelled box and a Search button; a search runs only when the form is submitted, never on typing, and a submit
 *   while one is out is ignored), then the newest 20 memories of `GET /api/v1/memory/items` (with the line "Showing the newest ... Search to find the
 *   others." when there are more) or the best matches of a submitted query, or an empty text. A blank submit shows the newest list again.
 * - A memory row has the text, a Told or Learned chip, when it was saved, a Pin / Unpin button (one button whose label switches, so focus stays) and
 *   Forget. Pin and Unpin ask the server and change the row only on a 200; a 404 means it is gone and the row leaves; any other failure shows the
 *   panel's one notice, which is announced once and named in the pressed button's description. Forget opens the shared ConfirmDialog; a confirmed
 *   Forget removes the row from both lists and re-reads Pinned when the row was pinned.
 * - On the online demo the card shows the per-session rule under its tabs.
 * - The card reads Notes and Your answers when it is made, and a tab again each time it is selected; Pinned and All memories read only when selected. While a panel's read has not answered, or
 *   failed, the panel shows its intro and nothing else, so that a failure never reads as "nothing" (AD-28); an empty text shows only after
 *   a read that answered. The card keeps nothing across page loads, filters and sorts nothing, and holds no session Ref.
 * - The tabs follow the header navigation's style (2px underline): a tab list named by the Memory heading, roving tabindex, ArrowLeft and ArrowRight move
 *   focus to the next or previous tab, wrap and select it; each panel is named by its tab. The card is no live region: its notices are announced once
 *   through the Announcer. Every text is bound by interpolation from memory-card-view.ts or is the server's.
 */
@Component({
  selector: 'app-memory-card',
  imports: [InlineNotice, NgTemplateOutlet, ServerButton],
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
    @if (onlineDemo()) {
      <p class="note demo-rule">{{ texts.demoRule }}</p>
    }
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
    <div class="panel" role="tabpanel" [id]="panelId('pinned')" [attr.aria-labelledby]="tabId('pinned')" [hidden]="selected() !== 'pinned'">
      <p class="note">{{ texts.pinnedIntro }}</p>
      @if (pinned(); as shown) {
        <p class="note figure">{{ usedOf(shown.used) }}</p>
        @if (pinnedNotice(); as notice) {
          <app-inline-notice variant="warning" [id]="noticeId('pinned')">{{ notice.text }}</app-inline-notice>
        }
        @if (shown.items.length === 0) {
          <p class="note muted">{{ texts.pinnedEmpty }}</p>
        } @else {
          <ul class="rows">
            @for (item of shown.items; track item.ref) {
              <ng-container [ngTemplateOutlet]="memoryRow" [ngTemplateOutletContext]="{ $implicit: item, panel: 'pinned' }" />
            }
          </ul>
        }
      }
    </div>
    <div class="panel" role="tabpanel" [id]="panelId('memories')" [attr.aria-labelledby]="tabId('memories')" [hidden]="selected() !== 'memories'">
      <form class="search" role="search" (submit)="submit($event, query.value)">
        <label class="search-label" [for]="queryId">{{ texts.searchLabel }}</label>
        <div class="search-line">
          <input
            #query
            type="search"
            class="input"
            autocomplete="off"
            maxlength="2000"
            [id]="queryId"
            [attr.aria-describedby]="describing('memories', '')"
          />
          <button
            type="submit"
            class="button button-secondary search-button"
            [attr.aria-disabled]="searching() ? 'true' : null"
            [attr.aria-describedby]="describing('memories', '')"
          >
            {{ texts.search }}
          </button>
        </div>
      </form>
      @if (memoriesNotice(); as notice) {
        <app-inline-notice variant="warning" [id]="noticeId('memories')">{{ notice.text }}</app-inline-notice>
      }
      @if (listing(); as shown) {
        @if (shown.items.length === 0) {
          <p class="note muted">{{ shown.query === '' ? texts.memoriesEmpty : texts.noMatch }}</p>
        } @else {
          <ul class="rows">
            @for (item of shown.items; track item.ref) {
              <ng-container [ngTemplateOutlet]="memoryRow" [ngTemplateOutletContext]="{ $implicit: item, panel: 'memories' }" />
            }
          </ul>
        }
        @if (moreOf(shown); as more) {
          <p class="note muted">{{ more }}</p>
        }
      }
    </div>
    <ng-template #memoryRow let-item let-panel="panel">
      <li class="row">
        <span class="title">{{ item.text }}</span>
        <span class="meta">
          <span class="chip">{{ sourceOf(item.source) }}</span>
          @if (whenOf(item.savedAt); as when) {
            <span>{{ when }}</span>
          }
        </span>
        <span class="actions">
          <app-server-button
            variant="ghost"
            [action]="toggler(item.ref)"
            [label]="toggleName(item)"
            [describedBy]="describedBy(panel, item.ref)"
            >{{ item.pinned ? texts.unpin : texts.pin }}</app-server-button
          >
          <button type="button" class="button button-ghost" [attr.aria-label]="memoryForgetName(item)" (click)="askMemory(item, $event)">
            {{ texts.forget }}
          </button>
        </span>
      </li>
    </ng-template>
  `,
  styles: `
    :host {
      display: block;
    }
    .tabs {
      display: flex;
      flex-wrap: wrap;
      gap: 0 var(--space-1);
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
      border-bottom: 2px solid transparent;
      color: var(--header-nav-item-foreground);
      font-family: var(--font-ui);
      font-size: var(--header-nav-item-typography-font-size);
      font-weight: var(--header-nav-item-typography-font-weight);
      line-height: var(--header-nav-item-typography-line-height);
      text-decoration-line: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
      cursor: pointer;
    }
    .tab:hover {
      text-decoration-thickness: 2px;
    }
    .tab.selected {
      color: var(--header-nav-item-foreground-current);
      border-bottom-color: var(--action);
    }
    .demo-rule {
      margin: var(--space-2) 0 0;
      color: var(--ink-muted);
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
      align-items: center;
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
    .figure {
      font-variant-numeric: tabular-nums;
      font-weight: var(--type-body-strong-font-weight);
    }
    .search {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      min-width: 0;
    }
    .search-label {
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-label-line-height);
    }
    .search-line {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-2);
    }
    .input {
      box-sizing: border-box;
      flex: 1 1 8rem;
      min-width: 0;
      min-height: var(--text-input-min-height);
      padding: var(--space-2) var(--space-3);
      background: var(--text-input-background);
      color: var(--ink);
      border: var(--text-input-border);
      border-radius: var(--text-input-radius);
      font-family: var(--font-ui);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .chip {
      padding: 1px 8px;
      border-radius: var(--context-badge-radius);
      background: var(--context-badge-background);
      color: var(--context-badge-foreground);
      font-family: var(--font-ui);
      font-size: var(--context-badge-typography-font-size);
      font-weight: var(--context-badge-typography-font-weight);
      line-height: var(--context-badge-typography-line-height);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1);
      margin-top: var(--space-1);
    }
  `,
})
export class MemoryCard {
  private readonly api = inject(ApiClient);
  private readonly dialogs = inject(Dialogs);
  private readonly request = inject(ConfirmRequest);
  private readonly announcer = inject(Announcer);
  private readonly live = inject(LiveState);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  protected readonly texts = MEMORY_TEXTS;
  protected readonly headingId = MEMORY_HEADING_ID;
  protected readonly separator = CHAT_TEXTS.separator;
  protected readonly tabs = MEMORY_TABS;

  /** The ids of this card's elements, which no other card of the page shares. */
  private readonly prefix = `memory-card-${(lastCard += 1)}`;
  protected readonly tabId = (tab: MemoryTab): string => `${this.prefix}-tab-${tab}`;
  protected readonly panelId = (tab: MemoryTab): string => `${this.prefix}-panel-${tab}`;
  protected readonly noticeId = (panel: MemoryPanel): string => `${this.prefix}-notice-${panel}`;
  protected readonly queryId = `${this.prefix}-query`;

  protected readonly selected = signal<MemoryTab>('notes');

  /** True on the online demo: the card shows the per-session rule under its tabs. */
  protected readonly onlineDemo = computed(() => this.live.snapshot()?.onlineDemo === true);

  /** The notes of both days, or none before the read answers and after a failed one. */
  protected readonly notes = signal<Notes | undefined>(undefined);
  /** The session's precedents, or none before the read answers and after a failed one. */
  private readonly answers = signal<PrecedentRow[] | undefined>(undefined);
  /** The session's pins and their tokens, or none before the read answers and after a failed one. */
  protected readonly pinned = signal<PinnedView | undefined>(undefined);
  /** The newest memories or the matches of the last search, or none before the read answers and after a failed one. */
  protected readonly listing = signal<ListingView | undefined>(undefined);
  /** True while a list or search read of All memories is out: a submit then is ignored. */
  protected readonly searching = signal(false);
  /** The Pinned panel's notice, or none. */
  protected readonly pinnedNotice = signal<PanelNotice | undefined>(undefined);
  /** The All memories panel's notice (a search failure, or a Pin or Unpin failure), or none. */
  protected readonly memoriesNotice = signal<PanelNotice | undefined>(undefined);

  /** The rows of Your answers with their meta parts, in served order. */
  protected readonly lines = computed<AnswerLine[] | undefined>(() => {
    const now = Date.now();
    return this.answers()?.map((row) => ({ row, meta: metaParts(row, pageWhen(row.answeredAt, now)), tool: isToolRow(row) }));
  });

  private readonly queryBox = viewChild<ElementRef<HTMLInputElement>>('query');
  private notesRead: Subscription | undefined;
  private answersRead: Subscription | undefined;
  private pinnedRead: Subscription | undefined;
  private memoriesRead: Subscription | undefined;
  /** The press of each memory's Pin or Unpin, one function for each ref, so that the button's input stays the same across updates. */
  private readonly togglers = new Map<string, () => Observable<unknown>>();
  /** False once the card is gone: a reply that comes later changes and announces nothing. */
  private shown = true;

  constructor() {
    this.readNotes();
    this.readAnswers();
    inject(DestroyRef).onDestroy(() => {
      this.shown = false;
      this.notesRead?.unsubscribe();
      this.answersRead?.unsubscribe();
      this.pinnedRead?.unsubscribe();
      this.memoriesRead?.unsubscribe();
    });
  }

  protected nameOf(tab: MemoryTab): string {
    switch (tab) {
      case 'notes':
        return MEMORY_TEXTS.notes;
      case 'answers':
        return MEMORY_TEXTS.answers;
      case 'pinned':
        return MEMORY_TEXTS.pinned;
      default:
        return MEMORY_TEXTS.memories;
    }
  }

  protected nameFor(row: PrecedentRow): string {
    return forgetName(row.summary);
  }

  protected usedOf(used: number): string {
    return usedText(used);
  }

  protected sourceOf(source: string): string {
    return sourceLabel(source);
  }

  /** When the memory was saved, in the page's time; "" for a time that cannot be read. */
  protected whenOf(savedAt: string): string {
    return pageWhen(savedAt, Date.now());
  }

  /** The line under the newest list when there are more memories than it shows; "" for a search and for a list that shows them all. */
  protected moreOf(view: ListingView): string {
    return view.query === '' ? listMore(view.items.length, view.total) : '';
  }

  /** The accessible name of a row's Pin or Unpin: the visible word, then the opening of the text. */
  protected toggleName(item: MemoryItem): string {
    return memoryName(item.pinned ? MEMORY_TEXTS.unpin : MEMORY_TEXTS.pin, item.text);
  }

  /** The accessible name of a row's Forget. */
  protected memoryForgetName(item: MemoryItem): string {
    return memoryName(MEMORY_TEXTS.forget, item.text);
  }

  /** The ids that describe the control of a row (or, with ref "", of the search): the panel's notice id while that notice is about this control. */
  protected describedBy(panel: MemoryPanel, ref: string): readonly string[] {
    const notice = panel === 'pinned' ? this.pinnedNotice() : this.memoriesNotice();
    return notice !== undefined && notice.ref === ref ? [this.noticeId(panel)] : [];
  }

  /** The aria-describedby of the search controls: the notice's id while the notice is about the search, else null. */
  protected describing(panel: MemoryPanel, ref: string): string | null {
    const ids = this.describedBy(panel, ref);
    return ids.length === 0 ? null : ids.join(' ');
  }

  /** The press of the row's Pin or Unpin button; one function for each ref. */
  protected toggler(ref: string): () => Observable<unknown> {
    let press = this.togglers.get(ref);
    if (press === undefined) {
      press = () => this.toggle(ref);
      this.togglers.set(ref, press);
    }
    return press;
  }

  /** A click on a tab: the user's own selection. */
  protected choose(tab: MemoryTab): void {
    if (this.selected() === tab) {
      return;
    }
    this.selected.set(tab);
    this.readTab(tab);
  }

  /** Left and right arrows move from the focused tab to the previous or next one, focusing and selecting it; they wrap, and no other key is handled. */
  protected onKey(event: KeyboardEvent): void {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
      return;
    }
    event.preventDefault();
    const focused = MEMORY_TABS.find((tab) => this.tabId(tab) === (event.target as HTMLElement | null)?.id) ?? this.selected();
    const next = nextTab(focused, event.key === 'ArrowRight' ? 1 : -1);
    this.choose(next);
    this.host.nativeElement.querySelector<HTMLElement>(`#${this.tabId(next)}`)?.focus();
  }

  /** Opens the confirm dialog for the answer; the button that opened it gets focus back when the dialog closes without forgetting. */
  protected ask(row: PrecedentRow, event: Event): void {
    this.openConfirm(
      { question: MEMORY_TEXTS.question, act: () => this.api.forgetPrecedent(row.ref) },
      event,
      () => this.gone(row.ref),
    );
  }

  /** Opens the confirm dialog for the memory; a confirmed Forget takes it out of both lists. */
  protected askMemory(item: MemoryItem, event: Event): void {
    this.openConfirm({ question: MEMORY_TEXTS.memoryQuestion, act: () => this.api.forgetMemory(item.ref) }, event, () => this.memoryGone(item.ref));
  }

  /** The search form's submit: a search of the box's text, or the newest list for a blank box; ignored while a read is out. Never called on typing. */
  protected submit(event: Event, text: string): void {
    event.preventDefault();
    if (this.searching()) {
      return;
    }
    this.readMemories(text.trim());
  }

  private openConfirm(content: { question: string; act: () => Observable<unknown> }, event: Event, done: () => void): void {
    this.request.content.set({
      question: content.question,
      confirm: MEMORY_TEXTS.confirm,
      cancel: MEMORY_TEXTS.cancel,
      failed: MEMORY_TEXTS.forgetFailed,
      act: content.act,
    });
    const ref = this.dialogs.open(ConfirmDialog, { labelledBy: CONFIRM_TITLE_ID, restoreFocus: event.currentTarget as HTMLElement });
    ref.closed.subscribe((result) => {
      if (result === CONFIRMED) {
        done();
      }
    });
  }

  /** The answer is gone: its row leaves with no new read, and focus goes to the Memory heading once the dialog has given focus back. */
  private gone(ref: string): void {
    this.answers.update((list) => list?.filter((one) => one.ref !== ref));
    this.focusHeading();
  }

  /** The memory is gone: its row leaves both lists, and Pinned is read again when the row was pinned. */
  private memoryGone(ref: string): void {
    const wasPinned = this.find(ref)?.pinned === true;
    this.leave(ref);
    if (wasPinned) {
      this.readPinned(true);
    }
    this.focusHeading();
  }

  /** Takes the memory out of the lists the card holds. */
  private leave(ref: string): void {
    this.togglers.delete(ref);
    this.pinned.update((view) => (view === undefined ? view : { ...view, items: view.items.filter((one) => one.ref !== ref) }));
    this.listing.update((view) => {
      if (view === undefined || !view.items.some((one) => one.ref === ref)) {
        return view;
      }
      return { ...view, items: view.items.filter((one) => one.ref !== ref), total: view.query === '' ? Math.max(0, view.total - 1) : view.total };
    });
  }

  /** The memory with the ref, looked for first in the list of the panel that is shown, so that its flag is the one the person sees. */
  private find(ref: string): MemoryItem | undefined {
    const inListing = this.listing()?.items.find((one) => one.ref === ref);
    const inPinned = this.pinned()?.items.find((one) => one.ref === ref);
    return this.selected() === 'pinned' ? (inPinned ?? inListing) : (inListing ?? inPinned);
  }

  /** The press of Pin or Unpin: the server decides; the row changes only on a 200. */
  private toggle(ref: string): Observable<unknown> {
    const panel: MemoryPanel = this.selected() === 'pinned' ? 'pinned' : 'memories';
    const item = this.find(ref);
    if (item === undefined) {
      return of(undefined);
    }
    this.setNotice(panel, undefined);
    const pinning = !item.pinned;
    return (pinning ? this.api.pinMemory(ref) : this.api.unpinMemory(ref)).pipe(
      tap(() => this.toggled(ref, pinning, panel)),
      catchError((error: unknown) => {
        this.toggleFailed(ref, pinning, panel, error);
        return of(undefined);
      }),
    );
  }

  /** The server pinned or unpinned the memory. */
  private toggled(ref: string, pinning: boolean, panel: MemoryPanel): void {
    if (!this.shown) {
      return;
    }
    this.listing.update((view) => (view === undefined ? view : { ...view, items: view.items.map((one) => (one.ref === ref ? { ...one, pinned: pinning } : one)) }));
    if (!pinning && panel === 'pinned') {
      this.pinned.update((view) => (view === undefined ? view : { ...view, items: view.items.filter((one) => one.ref !== ref) }));
      this.readPinned(true);
      this.focusHeading();
    } else if (pinning && this.selected() === 'pinned') {
      this.readPinned(true);
    }
  }

  /** A pin or unpin that did not go through: a 404 means the memory is gone, so its row leaves; anything else shows the panel's notice. */
  private toggleFailed(ref: string, pinning: boolean, panel: MemoryPanel, error: unknown): void {
    if (!this.shown) {
      return;
    }
    const status = error instanceof HttpErrorResponse ? error.status : 0;
    if (status === 404) {
      const wasPinned = this.find(ref)?.pinned === true;
      this.leave(ref);
      if (wasPinned || panel === 'pinned') {
        this.readPinned(true);
      }
      return;
    }
    const text = status === 409 && pinning ? MEMORY_TEXTS.overCap : pinning ? MEMORY_TEXTS.pinFailed : MEMORY_TEXTS.unpinFailed;
    this.setNotice(panel, { ref, text });
  }

  /** Sets (or clears) a panel's one notice; a notice is announced once, when it is set. */
  private setNotice(panel: MemoryPanel, notice: PanelNotice | undefined): void {
    (panel === 'pinned' ? this.pinnedNotice : this.memoriesNotice).set(notice);
    if (notice !== undefined) {
      this.announcer.announce(notice.text);
    }
  }

  /** Focus goes to the Memory heading once the dialog or the button has given focus back. */
  private focusHeading(): void {
    globalThis.setTimeout(() => this.heading()?.focus(), 0);
  }

  /** The Memory heading of the rail section that holds the card. */
  private heading(): HTMLElement | null {
    return this.host.nativeElement.closest('app-status-rail')?.querySelector<HTMLElement>(`#${MEMORY_HEADING_ID}`) ?? null;
  }

  private readTab(tab: MemoryTab): void {
    switch (tab) {
      case 'notes':
        this.readNotes();
        break;
      case 'answers':
        this.readAnswers();
        break;
      case 'pinned':
        this.readPinned(false);
        break;
      default: {
        const box = this.queryBox()?.nativeElement;
        if (box !== undefined) {
          box.value = '';
        }
        this.readMemories('');
      }
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

  /** Reads the pins. With keep, the rows that are shown stay until the answer, so that focus is not lost; a failed read then shows the intro only. */
  private readPinned(keep: boolean): void {
    this.pinnedRead?.unsubscribe();
    if (!keep) {
      this.pinned.set(undefined);
      this.pinnedNotice.set(undefined);
    }
    this.pinnedRead = this.api.pinnedMemories().subscribe({
      next: (answer) => this.pinned.set({ items: answer.items, used: answer.used }),
      error: () => this.pinned.set(undefined),
    });
  }

  /** Reads the newest memories (query "") or searches; a failed search shows its notice, a failed list read shows the search form only. */
  private readMemories(query: string): void {
    this.memoriesRead?.unsubscribe();
    this.listing.set(undefined);
    this.memoriesNotice.set(undefined);
    this.searching.set(true);
    this.memoriesRead = this.api.memoryItems(query).subscribe({
      next: (answer) => {
        this.listing.set({ items: answer.items, total: answer.total, query });
        this.searching.set(false);
      },
      error: (error: unknown) => {
        this.listing.set(undefined);
        this.searching.set(false);
        if (query !== '') {
          this.setNotice('memories', { ref: '', text: this.searchFailure(error) });
        }
      },
    });
  }

  /** What a failed search says: the busy text for a 503 search_busy, else the served message (the allowance's 429 included), else the busy text. */
  private searchFailure(error: unknown): string {
    if (error instanceof HttpErrorResponse && error.status === 503) {
      return MEMORY_TEXTS.searchBusy;
    }
    return messageOf(error) || MEMORY_TEXTS.searchBusy;
  }
}
