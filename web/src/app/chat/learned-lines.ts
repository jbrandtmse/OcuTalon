import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import type { Learned } from '../live/payloads';
import { renderPageText } from '../msg/catalog';

/** The catalog key of the line under a reply that announces a learned save (Story 41.15, AD-28). */
const LEARNED_KEY = 'memory.learnedSaved';

/**
 * The lines under a reply that announce the facts OcuTalon saved from the person's own words (Story 41.15, AD-21, AD-28): one line for each
 * entry of the chat.message's learned, the catalog text of memory.learnedSaved with the entry's fact. The server decided which entries show
 * (none when the reply already says "I'll remember") and shaped each fact, so the page only fills the slot. The fact comes from the
 * person's words and is bound by interpolation, never as HTML. The lines carry no label of their own.
 */
@Component({
  selector: 'app-learned-lines',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (line of lines(); track $index) {
      <p class="learned">{{ line }}</p>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .learned {
      margin: 0 0 var(--space-1);
      color: var(--ink);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
      overflow-wrap: anywhere;
    }
  `,
})
export class LearnedLines {
  /** The learned entries of the reply's chat.message. */
  readonly learned = input<readonly Learned[] | undefined>(undefined);

  /** One line for each entry that has a fact. */
  protected readonly lines = computed(() =>
    (this.learned() ?? []).filter((entry) => !!entry.fact).map((entry) => renderPageText(LEARNED_KEY, { fact: entry.fact ?? '' })),
  );
}
