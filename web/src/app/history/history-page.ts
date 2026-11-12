import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, computed, effect, inject, signal, untracked, viewChild } from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';

import { ApiClient } from '../api/api-client';
import type { HistoryDecisionsResponse, HistoryFallback, HistoryFilters, HistoryIncidentsResponse, HistoryOutcome } from '../api/history-types';
import { CHAT_TEXTS } from '../chat/chat-view';
import { FallbackFlag } from '../chat/fallback-flag';
import { messageTime, pageWhenBeside } from '../chat/page-time';
import { IncidentStateChip } from '../incidents/incident-state-chip';
import { headlineOf, INCIDENT_TEXTS, stateOf } from '../incidents/incident-view';
import { LiveState } from '../live/live-state';
import { DecisionRow } from '../rail/decision-row';
import { decisionRow, type RailRow } from '../rail/rail-view';
import { formatAt } from '../rail/status-rail';
import { Announcer } from '../shared/announcer';
import { TraceLink } from '../shared/trace-link';
import { channelLabel, USAGE_TEXTS } from '../usage/usage-view';
import {
  HISTORY_TABS,
  HISTORY_TEXTS,
  channelOptions,
  cleared,
  emptyText,
  fallbackOptions,
  filtered,
  incidentTimes,
  isCanonical,
  isDay,
  mergeQueryOf,
  noSummaryText,
  otherTab,
  outcomeOptions,
  pageText,
  paramsOf,
  summaryLines,
  type HistoryState,
  type HistoryTab,
  type ParamSource,
} from './history-view';

/** The outcome labels by the route's value: the chip's words (a fallback shows Tell now, as the filter does). */
const OUTCOME_LABELS: Readonly<Record<string, string>> = {
  ignore: CHAT_TEXTS.chipIgnore,
  digest: CHAT_TEXTS.chipDigest,
  tellnow: CHAT_TEXTS.chipTellNow,
  act: CHAT_TEXTS.chipAct,
};

/** An address with no parameter. */
const NO_PARAMS: ParamSource = { get: () => null };

/** The id of the hidden heading, which names the tab list. */
const HEADING_ID = 'history-heading';

/** One incident row as the page draws it. */
interface IncidentLine {
  ref: string;
  chip: ReturnType<typeof stateOf>;
  fallback: boolean;
  headline: string;
  times: string[];
  lines: string[];
  noSummary: string;
  traceUrl: string | undefined;
}

/**
 * The History page (Story 25.2; FR-53, FR-30; UX: Step 6), at #/history for every signed-in user and titled "History \u00B7 OcuTalon" by its route. It has a
 * hidden h1 "History", a tab list named by it with two tabs, Decisions and Incidents (ARIA tabs: aria-selected, a roving tabindex, ArrowLeft and ArrowRight
 * move to the other tab, and a tab changes only when it is pressed or an arrow is), and a tab panel for each, headed by a hidden h2.
 *
 * The Decisions panel has the filters Outcome, Channel, Fallback (native selects) and Date (a native date input), each with a label, and "Clear filters" while any
 * is set; then the list of the session's past decisions, each the rail's decision row (a disclosure of the reasons, expanded in place, with the trace link
 * beside its button) with the channel of the decision's usage rows after the time when it has one (a decision that no model call served has none, and shows no
 * channel text at all). The Incidents panel lists the incidents the session sees: the state chip, the Fallback flag, the headline, "Noticed {time}" and, once
 * closed, "Closed {time}", the stored summary as text (or why there is none), and the trace link to the diagnosis session.
 *
 * The state lives in the address (#/history?tab=&outcome=&channel=&day=&fallback=&page=; history-view.paramsOf and queryOf), so that a reload or a pasted link
 * shows the same list: a filter, tab or page change navigates (and so Back works), a filter change goes back to page 1, and an address with a value the
 * server would not take is replaced by the cleaned one. The lists page with Previous page and Next page ("Page n of N"), shown only with more than one page; a
 * page past the last (a stale link) is replaced in the address by the last page. The page asks the route when it opens, on each change of the address and
 * on Retry, shows nothing before the first answer, and shows "Couldn't load your history." with Retry for a failed read, announced through the live region.
 * An answer that follows withdraws that announcement when it still waits or was spoken alone (Announcer.retract).
 */
@Component({
  selector: 'app-history-page',
  imports: [DecisionRow, FallbackFlag, IncidentStateChip, TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="history" tabindex="-1">
      <h1 [id]="headingId" class="visually-hidden">{{ texts.heading }}</h1>
      <div class="tabs" role="tablist" [attr.aria-labelledby]="headingId" (keydown)="onKey($event)">
        @for (tab of tabs; track tab) {
          <button
            type="button"
            role="tab"
            class="tab"
            [id]="tabId(tab)"
            [class.selected]="state().tab === tab"
            [attr.aria-selected]="state().tab === tab"
            [attr.aria-controls]="panelId(tab)"
            [attr.tabindex]="state().tab === tab ? 0 : -1"
            (click)="choose(tab)"
          >
            {{ tabName(tab) }}
          </button>
        }
      </div>
      <div class="panel" role="tabpanel" [id]="panelId('decisions')" [attr.aria-labelledby]="tabId('decisions')" [hidden]="state().tab !== 'decisions'">
        <h2 class="visually-hidden">{{ texts.tabDecisions }}</h2>
        @if (state().tab === 'decisions') {
          <div class="filters">
            <div class="field">
              <label for="history-outcome">{{ texts.outcome }}</label>
              <select #outcomeSelect id="history-outcome" class="input" (change)="pick('outcome', $event)">
                @for (option of outcomes; track option.value) {
                  <option [value]="option.value" [selected]="option.value === state().outcome">{{ option.label }}</option>
                }
              </select>
            </div>
            <div class="field">
              <label for="history-channel">{{ texts.channel }}</label>
              <select id="history-channel" class="input" (change)="pick('channel', $event)">
                @for (option of channels; track option.value) {
                  <option [value]="option.value" [selected]="option.value === state().channel">{{ option.label }}</option>
                }
              </select>
            </div>
            <div class="field">
              <label for="history-day">{{ texts.date }}</label>
              <input id="history-day" class="input" type="date" [value]="state().day" (change)="pickDay($event)" />
            </div>
            <div class="field">
              <label for="history-fallback">{{ texts.fallback }}</label>
              <select id="history-fallback" class="input" (change)="pick('fallback', $event)">
                @for (option of fallbacks; track option.value) {
                  <option [value]="option.value" [selected]="option.value === state().fallback">{{ option.label }}</option>
                }
              </select>
            </div>
            @if (anyFilter()) {
              <button type="button" class="button button-secondary clear" (click)="clear()">{{ texts.clear }}</button>
            }
          </div>
          @if (failed()) {
            <div class="failed" data-part="history-failed">
              <p class="failed-text">{{ texts.error }}</p>
              <button type="button" class="button button-secondary" (click)="retry()">{{ texts.retry }}</button>
            </div>
          } @else if (decisions(); as shown) {
            @if (items().length === 0) {
              <p class="empty">{{ empty() }}</p>
            } @else {
              <ul class="list" data-part="history-decisions">
                @for (row of items(); track row.key) {
                  <li class="item">
                    <app-decision-row [row]="row" />
                  </li>
                }
              </ul>
            }
            @if (shown.pages > 1) {
              <nav class="pager" [attr.aria-label]="texts.decisionPages">
                <button type="button" class="button button-secondary" [attr.aria-disabled]="shown.page <= 1 ? 'true' : null" (click)="step(-1, shown.pages)">
                  {{ texts.previous }}
                </button>
                <span class="pager-text">{{ pageLabel(shown.page, shown.pages) }}</span>
                <button type="button" class="button button-secondary" [attr.aria-disabled]="shown.page >= shown.pages ? 'true' : null" (click)="step(1, shown.pages)">
                  {{ texts.next }}
                </button>
              </nav>
            }
          }
        }
      </div>
      <div class="panel" role="tabpanel" [id]="panelId('incidents')" [attr.aria-labelledby]="tabId('incidents')" [hidden]="state().tab !== 'incidents'">
        <h2 class="visually-hidden">{{ texts.tabIncidents }}</h2>
        @if (state().tab === 'incidents') {
          @if (failed()) {
            <div class="failed" data-part="history-failed">
              <p class="failed-text">{{ texts.error }}</p>
              <button type="button" class="button button-secondary" (click)="retry()">{{ texts.retry }}</button>
            </div>
          } @else if (incidents(); as shown) {
            @if (incidentLines().length === 0) {
              <p class="empty">{{ empty() }}</p>
            } @else {
              <ul class="list" data-part="history-incidents">
                @for (row of incidentLines(); track row.ref) {
                  <li class="item incident">
                    <div class="chip-row">
                      @if (row.chip; as entry) {
                        <app-incident-state-chip [chip]="entry.chip" [text]="entry.text" />
                      }
                      @if (row.fallback) {
                        <app-fallback-flag />
                      }
                    </div>
                    <p class="headline">{{ row.headline }}</p>
                    @if (row.times.length > 0) {
                      <p class="meta">
                        @for (part of row.times; track $index) {
                          @if ($index > 0) {
                            <span aria-hidden="true">{{ separator }}</span>
                          }
                          <span>{{ part }}</span>
                        }
                      </p>
                    }
                    @for (line of row.lines; track $index) {
                      <p class="summary-line">{{ line }}</p>
                    } @empty {
                      <p class="summary-none">{{ row.noSummary }}</p>
                    }
                    @if (row.traceUrl; as url) {
                      <div class="trace">
                        <app-trace-link [url]="url" />
                      </div>
                    }
                  </li>
                }
              </ul>
            }
            @if (shown.pages > 1) {
              <nav class="pager" [attr.aria-label]="texts.incidentPages">
                <button type="button" class="button button-secondary" [attr.aria-disabled]="shown.page <= 1 ? 'true' : null" (click)="step(-1, shown.pages)">
                  {{ texts.previous }}
                </button>
                <span class="pager-text">{{ pageLabel(shown.page, shown.pages) }}</span>
                <button type="button" class="button button-secondary" [attr.aria-disabled]="shown.page >= shown.pages ? 'true' : null" (click)="step(1, shown.pages)">
                  {{ texts.next }}
                </button>
              </nav>
            }
          }
        }
      </div>
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      min-height: 0;
    }
    .history {
      flex: 1;
      min-width: 0;
      overflow: auto;
      scroll-padding: var(--space-scroll-gutter);
      padding: var(--space-6);
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      outline-offset: calc(-1 * var(--space-2));
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
    .panel {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      min-width: 0;
    }
    .panel[hidden] {
      display: none;
    }
    .filters {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-end;
      gap: var(--space-4) var(--space-6);
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      min-width: 0;
    }
    .input {
      box-sizing: border-box;
      min-width: 12rem;
      max-width: 100%;
      min-height: var(--space-target-min);
      padding: var(--space-2) var(--space-3);
      background: var(--text-input-background);
      color: var(--ink);
      border: var(--text-input-border);
      border-radius: var(--text-input-radius);
      font-family: var(--font-ui);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .empty,
    .failed-text {
      margin: 0;
    }
    .failed {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-3);
    }
    .list {
      display: flex;
      flex-direction: column;
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .item {
      min-width: 0;
      min-height: var(--space-10);
      padding: var(--space-2) 0;
      border-bottom: 1px solid var(--border);
    }
    .incident {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .chip-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
    }
    .headline,
    .summary-line,
    .summary-none {
      margin: 0;
      overflow-wrap: anywhere;
    }
    .headline {
      font-weight: var(--type-body-strong-font-weight);
    }
    .summary-none {
      color: var(--ink-muted);
    }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1);
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
      line-height: var(--type-caption-line-height);
      font-variant-numeric: tabular-nums;
    }
    .pager {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-3);
    }
    .pager [aria-disabled='true'] {
      opacity: 0.55;
      cursor: default;
    }
  `,
})
export class HistoryPage {
  private readonly api = inject(ApiClient);
  private readonly destroyed = inject(DestroyRef);
  private readonly announcer = inject(Announcer);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly live = inject(LiveState);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly outcomeSelect = viewChild<ElementRef<HTMLSelectElement>>('outcomeSelect');

  protected readonly texts = HISTORY_TEXTS;
  protected readonly headingId = HEADING_ID;
  protected readonly tabs = HISTORY_TABS;
  protected readonly separator = INCIDENT_TEXTS.separator;
  protected readonly outcomes = outcomeOptions(OUTCOME_LABELS);
  protected readonly channels = channelOptions(USAGE_TEXTS.channels);
  protected readonly fallbacks = fallbackOptions();

  private readonly query = toSignal(this.route.queryParamMap);

  /** The state the address holds, every value that the server would not take dropped. */
  protected readonly state = computed<HistoryState>(() => paramsOf(this.query() ?? NO_PARAMS));

  /** The last answer of the Decisions tab; undefined before it and while the next one is on the way. */
  protected readonly decisions = signal<HistoryDecisionsResponse | undefined>(undefined);

  /** The last answer of the Incidents tab; undefined before it and while the next one is on the way. */
  protected readonly incidents = signal<HistoryIncidentsResponse | undefined>(undefined);

  /** True when the last read failed. */
  protected readonly failed = signal(false);

  /** When the shown answer arrived, in ms: the time the rows are read against. */
  private readonly loadedAt = signal(Date.now());
  private asked = 0;

  /** True when any of the four filters is set. */
  protected readonly anyFilter = computed(() => filtered(this.state()));

  /** What an empty list says. */
  protected readonly empty = computed(() => emptyText(this.state()));

  /** The decision rows: the rail's row of each decision, with the channel label after the time when the decision has a channel. */
  protected readonly items = computed<RailRow[]>(() => {
    const answer = this.decisions();
    if (answer === undefined) {
      return [];
    }
    const format = formatAt(this.loadedAt());
    return answer.decisions.map((decision) => {
      const row = decisionRow(decision, format);
      const label = decision.channel === '' ? '' : channelLabel(decision.channel);
      if (label === '') {
        return row;
      }
      const at = format.when(decision.recordedAt) !== '' ? 1 : 0;
      return { ...row, meta: [...row.meta.slice(0, at), label, ...row.meta.slice(at)] };
    });
  });

  /** The incident rows. */
  protected readonly incidentLines = computed<IncidentLine[]>(() => {
    const answer = this.incidents();
    if (answer === undefined) {
      return [];
    }
    const now = this.loadedAt();
    const snapshot = this.live.snapshot();
    const zone = snapshot?.instanceZone ?? '';
    const online = snapshot?.onlineDemo === true;
    return answer.incidents.map((incident) => {
      const lines = summaryLines(incident.summary);
      return {
        ref: incident.ref,
        chip: stateOf(incident.state),
        fallback: incident.fallback,
        headline: headlineOf(incident, { nowMs: now, messageTime: (iso, at) => messageTime(iso, at, zone, online) }),
        times: incidentTimes(incident, (iso) => pageWhenBeside(iso, now, zone)),
        lines,
        noSummary: lines.length === 0 ? noSummaryText(incident.state) : '',
        traceUrl: incident.traceUrl,
      };
    });
  });

  constructor() {
    effect(() => {
      const query = this.query();
      if (query !== undefined && !isCanonical(query)) {
        untracked(() => this.go(paramsOf(query), true));
      }
    });
    effect(() => {
      const query = this.query();
      const state = this.state();
      if (query === undefined || isCanonical(query)) {
        untracked(() => this.load(state));
      }
    });
  }

  protected tabId(tab: HistoryTab): string {
    return `history-tab-${tab}`;
  }

  protected panelId(tab: HistoryTab): string {
    return `history-panel-${tab}`;
  }

  protected tabName(tab: HistoryTab): string {
    return tab === 'decisions' ? HISTORY_TEXTS.tabDecisions : HISTORY_TEXTS.tabIncidents;
  }

  protected pageLabel(page: number, pages: number): string {
    return pageText(page, pages);
  }

  /** Moves the address to the state: a change the user made adds a history entry, so that Back works; a correction replaces the entry. */
  private go(state: HistoryState, replace = false): void {
    void this.router.navigate([], { queryParams: mergeQueryOf(state), queryParamsHandling: 'merge', replaceUrl: replace });
  }

  /** Reads the list of the state's tab; an answer that arrives after a later read is dropped. A failed read stays on screen until the next answer. */
  private load(state: HistoryState): void {
    const ask = (this.asked += 1);
    this.decisions.set(undefined);
    this.incidents.set(undefined);
    if (state.tab === 'incidents') {
      this.api
        .historyIncidents(state.page)
        .pipe(takeUntilDestroyed(this.destroyed))
        .subscribe({
          next: (answer) => this.arrived(ask, state, answer.pages, answer.incidents.length, () => this.incidents.set(answer)),
          error: () => this.refused(ask),
        });
      return;
    }
    this.api
      .historyDecisions({ ...filtersOf(state), page: state.page })
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (answer) => this.arrived(ask, state, answer.pages, answer.decisions.length, () => this.decisions.set(answer)),
        error: () => this.refused(ask),
      });
  }

  /** An answer: shown, or, for a page past the last (an empty list on a page above 1), the address goes to the last page. */
  private arrived(ask: number, state: HistoryState, pages: number, count: number, show: () => void): void {
    if (ask !== this.asked) {
      return;
    }
    if (this.failed()) {
      this.failed.set(false);
      this.announcer.retract(HISTORY_TEXTS.error);
    }
    if (count === 0 && state.page > Math.max(1, pages)) {
      this.go({ ...state, page: Math.max(1, pages) }, true);
      return;
    }
    this.loadedAt.set(Date.now());
    show();
  }

  private refused(ask: number): void {
    if (ask === this.asked) {
      this.failed.set(true);
      this.announcer.announce(HISTORY_TEXTS.error);
    }
  }

  protected retry(): void {
    this.load(this.state());
  }

  /** A tab press: the Decisions tab and the Incidents tab each start at page 1. */
  protected choose(tab: HistoryTab): void {
    if (tab !== this.state().tab) {
      this.go({ ...this.state(), tab, page: 1 });
    }
  }

  /** ArrowLeft and ArrowRight move from the focused tab to the other one, focusing and selecting it; no other key is handled. */
  protected onKey(event: KeyboardEvent): void {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
      return;
    }
    event.preventDefault();
    const next = otherTab(this.state().tab);
    this.choose(next);
    this.host.nativeElement.querySelector<HTMLElement>(`#${this.tabId(next)}`)?.focus();
  }

  /** A change of a select: that filter is set (or cleared for its first option) and the page goes back to 1. */
  protected pick(name: 'outcome' | 'channel' | 'fallback', event: Event): void {
    const value = (event.target as HTMLSelectElement).value;
    this.go({ ...this.state(), [name]: value, page: 1 });
  }

  /**
   * A change of the date: a readable date is the filter, an emptied input clears it, and any other value (such as the year 0002 that Chromium's
   * input reports while a year is typed digit by digit) changes nothing, so typing a date adds one history entry and one read.
   */
  protected pickDay(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    if (value !== '' && !isDay(value)) {
      return;
    }
    this.go({ ...this.state(), day: value, page: 1 });
  }

  /** Clear filters: every filter goes, the page goes back to 1, and focus goes to the first filter, since the button leaves. */
  protected clear(): void {
    this.outcomeSelect()?.nativeElement.focus();
    this.go(cleared(this.state()));
  }

  /** Previous page or Next page; at an end the control (aria-disabled) does nothing. The pager leaves while the page loads, so focus goes to the page's main region. */
  protected step(by: 1 | -1, pages: number): void {
    const page = this.state().page + by;
    if (page >= 1 && page <= pages) {
      this.host.nativeElement.querySelector<HTMLElement>('main')?.focus();
      this.go({ ...this.state(), page });
    }
  }
}

/** The filters of the state for the route: only those that are set. */
function filtersOf(state: HistoryState): HistoryFilters {
  const filters: HistoryFilters = {};
  if (state.outcome !== '') {
    filters.outcome = state.outcome as HistoryOutcome;
  }
  if (state.channel !== '') {
    filters.channel = state.channel;
  }
  if (state.day !== '') {
    filters.day = state.day;
  }
  if (state.fallback !== '') {
    filters.fallback = state.fallback as HistoryFallback;
  }
  return filters;
}
