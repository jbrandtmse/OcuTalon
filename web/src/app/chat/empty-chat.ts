import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { CHAT_TEXTS } from './chat-view';
import { OutcomeChip, type Outcome } from './outcome-chip';
import { TryItRow } from './try-it-row';

/** The four outcomes with the meaning each has in release 1, in the order the UX gives them. */
const MEANINGS: ReadonlyArray<{ outcome: Outcome; meaning: string }> = [
  { outcome: 'ignore', meaning: CHAT_TEXTS.meaningIgnore },
  { outcome: 'digest', meaning: CHAT_TEXTS.meaningDigest },
  { outcome: 'tell-now', meaning: CHAT_TEXTS.meaningTellNow },
  { outcome: 'act', meaning: CHAT_TEXTS.meaningAct },
];

/**
 * The empty chat panel (UX-DR70, UX-DR89), shown in a fresh session until the first message: the headline, the four outcome
 * chips with their meanings, and the panel's remaining lines. The headline is a paragraph, not a heading: the page's heading
 * lists are pinned. The last line is the demo mode's ("Start with step 1 of the demo guide above.") when `demo` is set, else the one for a session
 * outside the demo. In the demo view the "Try it yourself" row follows the last line (app-try-it-row; it renders nothing outside the demo view).
 */
@Component({
  selector: 'app-empty-chat',
  imports: [OutcomeChip, TryItRow],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="empty">
      <p class="headline">{{ texts.emptyHeadline }}</p>
      <ul class="meanings">
        @for (item of meanings; track item.outcome) {
          <li>
            <app-outcome-chip [outcome]="item.outcome" />
            <span class="meaning">{{ item.meaning }}</span>
          </li>
        }
      </ul>
      <p class="line">{{ texts.emptyWatches }}</p>
      <p class="line">{{ texts.emptyRisky }}</p>
      <p class="line">{{ demo() ? texts.emptyDemo : texts.emptyAsk }}</p>
      <app-try-it-row [centered]="true" />
    </div>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      min-height: 0;
    }
    .empty {
      width: 460px;
      max-width: 100%;
      margin: auto;
      padding: var(--space-6) 0;
      text-align: center;
    }
    .headline {
      margin: 0 0 var(--space-4);
      font-family: var(--font-display);
      font-size: var(--type-display-md-font-size);
      font-weight: var(--type-display-md-font-weight);
      line-height: var(--type-display-md-line-height);
      color: var(--ink);
    }
    .meanings {
      display: grid;
      grid-template-columns: max-content 1fr;
      gap: var(--space-2) var(--space-3);
      align-items: center;
      width: max-content;
      max-width: 100%;
      margin: 0 auto var(--space-4);
      padding: 0;
      list-style: none;
      text-align: left;
    }
    .meanings li {
      display: contents;
    }
    .meaning {
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .line {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-font-size);
      line-height: var(--type-body-line-height);
    }
    .line + .line {
      margin-top: 6px;
    }
  `,
})
export class EmptyChat {
  /** True in demo mode, where the demo guide above gives the first step. */
  readonly demo = input(false);

  protected readonly texts = CHAT_TEXTS;
  protected readonly meanings = MEANINGS;
}
