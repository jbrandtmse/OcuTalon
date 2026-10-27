import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { Icon } from '../icon/icon';
import { PAGE_SLOTS, PAGE_TEXTS, renderPageText } from '../msg/catalog';
import type { CheckRow } from '../live/payloads';
import { checkSentence, type CheckCatalog } from '../shared/check-sentence';
import { checkRowView, CHECK_KEY_PREFIX, DECISION_TEXTS } from './decision-view';
import { pageTime } from './page-time';

const CATALOG: CheckCatalog = { texts: PAGE_TEXTS, slots: PAGE_SLOTS, render: renderPageText };

/**
 * The check results under a reply (UX-DR65, FR-37, AD-28), code-computed and never model-written. The sentence above the rows is
 * the catalog text of the check key, when the page renders that key (checks.allPassed, checks.everythingElsePassed,
 * checks.nothingWatched, and checks.notEverything and checks.notEverythingRestPassed, whose {whatFailed} comes from the rows that did
 * not pass); any other key shows no sentence, so an all-clear never comes from the rows, only from its own key. Each row has the result's icon
 * and word in the result's colour, the entry, and in muted text the finding or reason and the time in the browser's zone. A result
 * that is not "passed" or "failed" is shown as Not checked, never as Passed. Every value is bound by interpolation.
 */
@Component({
  selector: 'app-check-rows',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (sentence(); as text) {
      <p class="sentence">{{ text }}</p>
    }
    @if (rows().length > 0) {
      <ul class="rows">
        @for (row of rows(); track $index) {
          <li class="row">
            <span class="result" [class]="row.view.result"><app-icon [name]="row.view.icon" [size]="14" /><span class="word">{{ row.view.word }}</span></span>
            <span class="entry">{{ row.entry }}</span>
            @if (row.finding || row.time) {
              <span class="meta">
                @if (row.finding) {
                  <span class="finding">{{ row.finding }}</span>
                }
                @if (row.finding && row.time) {
                  <span aria-hidden="true">{{ separator }}</span>
                }
                @if (row.time) {
                  <span class="time">{{ row.time }}</span>
                }
              </span>
            }
          </li>
        }
      </ul>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .sentence {
      margin: 0 0 var(--space-1);
      color: var(--ink);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .rows {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .row {
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      column-gap: var(--space-2);
      color: var(--ink);
      font-size: var(--check-row-typography-font-size);
      font-weight: var(--check-row-typography-font-weight);
      line-height: var(--check-row-typography-line-height);
    }
    .result {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      font-weight: 600;
    }
    .result app-icon {
      align-self: center;
    }
    .passed {
      color: var(--check-result-passed-foreground);
    }
    .failed {
      color: var(--check-result-failed-foreground);
    }
    .not-checked {
      color: var(--check-result-not-checked-foreground);
    }
    .entry {
      overflow-wrap: anywhere;
    }
    .meta {
      color: var(--ink-muted);
      font-size: var(--check-row-meta-font-size);
      font-weight: var(--check-row-meta-font-weight);
      line-height: var(--check-row-meta-line-height);
      overflow-wrap: anywhere;
    }
  `,
})
export class CheckRows {
  /** The catalog key of the check results; "" when the reply has none. */
  readonly checkKey = input<string | undefined>();
  readonly checks = input<readonly CheckRow[] | undefined>();
  protected readonly separator = DECISION_TEXTS.separator;

  /** The key's sentence when the page renders the key as a check sentence, else "". */
  protected readonly sentence = computed(() => {
    const key = this.checkKey() ?? '';
    return key.startsWith(CHECK_KEY_PREFIX) ? checkSentence(key, this.checks() ?? [], CATALOG, pageTime) : '';
  });

  /** One entry per check result, with the view of its result and its time in the browser's zone. */
  protected readonly rows = computed(() =>
    (this.checks() ?? []).map((row) => ({
      view: checkRowView(row),
      entry: row.entry ?? '',
      finding: row.finding ?? '',
      time: pageTime(row.checkedAt ?? ''),
    })),
  );
}
