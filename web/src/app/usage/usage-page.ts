import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, computed, effect, inject, signal, untracked, viewChild } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { ApiClient } from '../api/api-client';
import type { UsageDays, UsageResponse } from '../api/usage-types';
import { DECISION_TEXTS, formatCost, formatTokens } from '../chat/decision-view';
import { SETTINGS_TEXTS } from '../settings/settings-view';
import {
  DEFAULT_GROUPING,
  DEFAULT_RANGE,
  GROUPINGS,
  RANGES,
  USAGE_TEXTS,
  chartGeometry,
  dayLabel,
  groupRows,
  largestByDay,
  largestText,
  round,
  type Grouping,
} from './usage-view';

/** The height of the chart, in pixels; its width follows the page. */
const CHART_HEIGHT = 240;

/** The width the chart is drawn at before the page has measured its room. */
const CHART_WIDTH = 640;

/**
 * The Usage page (Story 37.2; FR-52; UX: Step 6), at #/usage for every signed-in user and titled "Usage \u00B7 OcuTalon" by its route. It has the one h1
 * "Usage", the Range control (a native select: Today, Last 7 days, Last 30 days; 7 is the default) and the Group by control (a radio group: Day, Agent, Channel,
 * Model), a "Tokens and cost" region and a "Largest request per day" region.
 *
 * The page asks GET /v1/usage?days= when it opens, on a range change and on Retry; a grouping change regroups the buckets it holds, with no request. It shows
 * nothing before the first answer, "No model use in this period." for an answer with no bucket (and no chart or table), and "Couldn't load your usage." with
 * Retry for a failed read. A range change shows nothing until its answer, so a table never sits under another range's name.
 *
 * The "Tokens and cost" region is a figure and a table. The figure is an inline SVG hidden from assistive technology: one bar for each row's tokens (input plus
 * output) on the token scale and one point on the cost line, on its own scale, in the usage chart tokens, with a gridline each quarter and the series named
 * at their ends; a visible legend names them by a square and by a line with a dot, so neither relies on colour. The bars and points carry data-key,
 * data-tokens and data-cost. The table beneath it has one row for every bar and point, with the four token kinds, the tokens, the cost, and the words
 * "estimated" or "includes estimates" for a group that is, or includes, an estimate (the compaction rows are the agent "Chat summaries"). It scrolls in its
 * own region, so the page never scrolls sideways. The "Largest request per day" table lists each day with use as "{tokens} of {limit} tokens", the limit being the
 * server's.
 *
 * The SVG is drawn at the width the figure has (a ResizeObserver), so its text keeps its size at any width.
 */
@Component({
  selector: 'app-usage-page',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="usage" tabindex="-1">
      <h1 class="heading">{{ texts.heading }}</h1>
      <div class="controls">
        <div class="field">
          <label for="usage-range">{{ texts.range }}</label>
          <select id="usage-range" class="input" (change)="pickRange($event)">
            @for (days of ranges; track days) {
              <option [value]="days" [selected]="days === range()">{{ texts.rangeOptions[days] }}</option>
            }
          </select>
        </div>
        <fieldset class="field grouping">
          <legend>{{ texts.groupBy }}</legend>
          <div class="radios">
            @for (option of groupings; track option) {
              <label class="radio">
                <input type="radio" name="usage-grouping" [value]="option" [checked]="option === grouping()" (change)="pickGrouping(option)" />
                {{ texts.groupings[option] }}
              </label>
            }
          </div>
        </fieldset>
      </div>
      @if (failed()) {
        <div class="failed" data-part="usage-failed">
          <p class="failed-text">{{ texts.error }}</p>
          <button type="button" class="button button-secondary" (click)="load()">{{ texts.retry }}</button>
        </div>
      } @else if (answer(); as shown) {
        @if (shown.buckets.length === 0) {
          <p class="empty">{{ texts.empty }}</p>
        } @else {
          <section class="region" aria-labelledby="usage-chart-heading" data-part="usage-chart">
            <h2 id="usage-chart-heading" class="region-heading">{{ texts.chartHeading }}</h2>
            <figure #figure class="figure">
              <svg
                class="chart"
                aria-hidden="true"
                focusable="false"
                [attr.viewBox]="'0 0 ' + geometry().width + ' ' + geometry().drawHeight"
              >
                @for (line of geometry().gridlines; track $index) {
                  <line class="gridline" x1="0" [attr.x2]="geometry().width" [attr.y1]="line.y" [attr.y2]="line.y" />
                }
                @for (bar of geometry().bars; track bar.key; let i = $index) {
                  <rect
                    class="bar"
                    [attr.x]="bar.x"
                    [attr.y]="bar.y"
                    [attr.width]="bar.width"
                    [attr.height]="bar.length"
                    [attr.data-key]="bar.key"
                    [attr.data-tokens]="rows()[i].tokens"
                    [attr.data-cost]="rows()[i].costUSD"
                  />
                }
                <polyline class="cost-line" fill="none" [attr.points]="geometry().line" />
                @for (point of geometry().points; track point.key; let i = $index) {
                  <circle
                    class="point"
                    r="4"
                    [attr.cx]="point.x"
                    [attr.cy]="point.y"
                    [attr.data-key]="point.key"
                    [attr.data-tokens]="rows()[i].tokens"
                    [attr.data-cost]="rows()[i].costUSD"
                  />
                }
                @if (geometry().tokensLabel; as label) {
                  <text class="series-label tokens-label" [attr.x]="label.x" [attr.y]="label.y">{{ decision.rowTokens }}</text>
                }
                @if (geometry().costLabel; as label) {
                  <text class="series-label cost-label" [attr.x]="label.x" [attr.y]="label.y">{{ decision.rowCost }}</text>
                }
                @for (category of geometry().categories; track category.key) {
                  <text class="category" text-anchor="middle" [attr.x]="category.x" [attr.y]="category.y">{{ category.text }}</text>
                }
              </svg>
              <figcaption class="legend">
                <span class="legend-item"><svg class="swatch-bar" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true" focusable="false"><rect width="12" height="12" /></svg>
                  {{ decision.rowTokens }}
                </span>
                <span class="legend-item">
                  <svg class="swatch-line" width="24" height="12" viewBox="0 0 24 12" aria-hidden="true" focusable="false">
                    <line x1="0" y1="6" x2="24" y2="6" />
                    <circle cx="12" cy="6" r="4" />
                  </svg>
                  {{ decision.rowCost }}
                </span>
              </figcaption>
            </figure>
            <div class="scroll" role="group" tabindex="0" aria-labelledby="usage-chart-heading">
              <table class="table" aria-labelledby="usage-chart-heading" data-part="usage-table">
                <thead>
                  <tr>
                    <th scope="col">{{ texts.groupings[grouping()] }}</th>
                    <th scope="col" class="number">{{ decision.tokenInput }}</th>
                    <th scope="col" class="number">{{ decision.tokenOutput }}</th>
                    <th scope="col" class="number">{{ decision.tokenCacheRead }}</th>
                    <th scope="col" class="number">{{ decision.tokenCacheWrite }}</th>
                    <th scope="col" class="number">{{ decision.rowTokens }}</th>
                    <th scope="col" class="number">{{ decision.rowCost }}</th>
                  </tr>
                </thead>
                <tbody>
                  @for (row of rows(); track row.key) {
                    <tr [attr.data-key]="row.key">
                      <th scope="row" class="row-name">
                        {{ row.label }}
                        @if (row.estimated) {
                          <span class="marker">{{ texts.estimated }}</span>
                        } @else if (row.includesEstimates) {
                          <span class="marker">{{ texts.includesEstimates }}</span>
                        }
                      </th>
                      <td class="number tabular">{{ tokens(row.inputTokens) }}</td>
                      <td class="number tabular">{{ tokens(row.outputTokens) }}</td>
                      <td class="number tabular">{{ tokens(row.cacheReadTokens) }}</td>
                      <td class="number tabular">{{ tokens(row.cacheWriteTokens) }}</td>
                      <td class="number tabular">{{ tokens(row.tokens) }}</td>
                      <td class="number tabular">{{ cost(row.costUSD) }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </section>
          <section class="region" aria-labelledby="usage-largest-heading" data-part="usage-largest">
            <h2 id="usage-largest-heading" class="region-heading">{{ texts.largestHeading }}</h2>
            <div class="scroll" role="group" tabindex="0" aria-labelledby="usage-largest-heading">
              <table class="table" aria-labelledby="usage-largest-heading">
                <thead>
                  <tr>
                    <th scope="col">{{ texts.groupings.day }}</th>
                    <th scope="col" class="number">{{ texts.largestColumn }}</th>
                  </tr>
                </thead>
                <tbody>
                  @for (day of largest(); track day.day) {
                    <tr [attr.data-day]="day.day">
                      <th scope="row" class="row-name">{{ day.label }}</th>
                      <td class="number tabular">{{ day.text }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </section>
        }
      }
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      min-height: 0;
    }
    .usage {
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
    .heading {
      margin: 0;
      font-family: var(--font-display);
      font-size: var(--type-display-lg-font-size);
      font-weight: var(--type-display-lg-font-weight);
      line-height: var(--type-display-lg-line-height);
    }
    .controls {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      gap: var(--space-4) var(--space-6);
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      margin: 0;
      padding: 0;
      border: 0;
      min-width: 0;
    }
    legend {
      padding: 0;
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
    .radios {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1) var(--space-4);
    }
    .radio {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-target-min);
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
    .region {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      min-width: 0;
    }
    .region-heading {
      margin: 0;
      font-size: var(--type-headline-font-size);
      font-weight: var(--type-headline-font-weight);
      line-height: var(--type-headline-line-height);
    }
    .figure {
      margin: 0;
      min-width: 0;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
    }
    .chart {
      display: block;
      width: 100%;
    }
    .gridline {
      stroke: var(--usage-chart-gridline);
      stroke-width: 1;
    }
    .bar {
      fill: var(--usage-chart-tokens-series);
    }
    .cost-line {
      stroke: var(--usage-chart-cost-series);
      stroke-width: 2;
    }
    .point {
      fill: var(--surface);
      stroke: var(--usage-chart-cost-series);
      stroke-width: 2;
    }
    .series-label,
    .category {
      font-family: var(--font-ui);
      font-size: var(--type-label-font-size);
      font-weight: 600;
    }
    .category {
      font-weight: 400;
      fill: var(--ink-muted);
    }
    .tokens-label {
      fill: var(--usage-chart-tokens-series);
    }
    .cost-label {
      fill: var(--usage-chart-cost-series);
    }
    .legend {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1) var(--space-4);
    }
    .legend-item {
      display: inline-flex;
      align-items: center;
      gap: var(--space-2);
    }
    .swatch-bar rect {
      fill: var(--usage-chart-tokens-series);
    }
    .swatch-line line {
      stroke: var(--usage-chart-cost-series);
      stroke-width: 2;
    }
    .swatch-line circle {
      fill: var(--surface);
      stroke: var(--usage-chart-cost-series);
      stroke-width: 2;
    }
    .scroll {
      max-width: 100%;
      overflow-x: auto;
      scroll-padding: var(--space-scroll-gutter);
    }
    .table {
      border-collapse: collapse;
      width: 100%;
    }
    .table th,
    .table td {
      padding: var(--space-2) var(--space-3);
      border-bottom: 1px solid var(--border);
      text-align: start;
      vertical-align: top;
    }
    .table th {
      font-weight: 600;
    }
    .table .number {
      text-align: end;
      white-space: nowrap;
    }
    .row-name {
      overflow-wrap: anywhere;
    }
    .marker {
      margin-inline-start: var(--space-2);
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: 400;
      white-space: nowrap;
    }
  `,
})
export class UsagePage {
  private readonly api = inject(ApiClient);
  private readonly destroyed = inject(DestroyRef);

  protected readonly texts = USAGE_TEXTS;
  protected readonly decision = DECISION_TEXTS;
  protected readonly ranges = RANGES;
  protected readonly groupings = GROUPINGS;
  private readonly figure = viewChild<ElementRef<HTMLElement>>('figure');

  /** The range asked for, in days. */
  protected readonly range = signal<UsageDays>(DEFAULT_RANGE);

  /** How the rows are grouped. */
  protected readonly grouping = signal<Grouping>(DEFAULT_GROUPING);

  /** The last answer of the current range; undefined before it and while the next one is on the way. */
  protected readonly answer = signal<UsageResponse | undefined>(undefined);

  /** True when the last read failed. */
  protected readonly failed = signal(false);

  /** The width the chart is drawn at. */
  private readonly width = signal(CHART_WIDTH);
  private asked = 0;
  private observer: ResizeObserver | undefined;

  /** The rows of the grouping. */
  protected readonly rows = computed(() => {
    const answer = this.answer();
    return answer === undefined ? [] : groupRows(answer, this.grouping(), SETTINGS_TEXTS.models.agents);
  });

  /** The chart's marks for the rows at the figure's width. */
  protected readonly geometry = computed(() => chartGeometry(this.rows(), this.width(), CHART_HEIGHT));

  /** The days with use and their largest request against the server's limit. */
  protected readonly largest = computed(() => {
    const answer = this.answer();
    if (answer === undefined) {
      return [];
    }
    const today = answer.days.length > 0 ? answer.days[answer.days.length - 1] : '';
    const limit = formatTokens(answer.limit);
    return largestByDay(answer).map((day) => ({ day: day.day, label: dayLabel(day.day, today), text: largestText(formatTokens(day.tokens), limit) }));
  });

  constructor() {
    this.load();
    effect(() => {
      const host = this.figure()?.nativeElement;
      untracked(() => this.watch(host));
    });
    this.destroyed.onDestroy(() => this.observer?.disconnect());
  }

  /** Reads the usage of the current range; an answer that arrives after a later read is dropped. */
  protected load(): void {
    const ask = (this.asked += 1);
    this.failed.set(false);
    this.answer.set(undefined);
    this.api
      .usage(this.range())
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (answer) => {
          if (ask === this.asked) {
            this.answer.set(answer);
          }
        },
        error: () => {
          if (ask === this.asked) {
            this.failed.set(true);
          }
        },
      });
  }

  protected pickRange(event: Event): void {
    const value = Number((event.target as HTMLSelectElement).value);
    const days = RANGES.find((range) => range === value);
    if (days !== undefined && days !== this.range()) {
      this.range.set(days);
      this.load();
    }
  }

  protected pickGrouping(option: Grouping): void {
    this.grouping.set(option);
  }

  protected tokens(count: number): string {
    return formatTokens(count);
  }

  protected cost(amount: number): string {
    return formatCost(amount);
  }

  /** Draws the chart at the figure's width, now and whenever the figure changes size. */
  private watch(host: HTMLElement | undefined): void {
    this.observer?.disconnect();
    this.observer = undefined;
    if (host === undefined) {
      return;
    }
    this.width.set(round(host.clientWidth) || CHART_WIDTH);
    if (typeof ResizeObserver === 'undefined') {
      return;
    }
    this.observer = new ResizeObserver((entries) => {
      const width = Math.floor(entries[0]?.contentRect.width ?? 0);
      if (width > 0 && width !== this.width()) {
        this.width.set(width);
      }
    });
    this.observer.observe(host);
  }
}
