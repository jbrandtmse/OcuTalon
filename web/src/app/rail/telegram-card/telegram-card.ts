import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { CHAT_TEXTS } from '../../chat/chat-view';
import type { TelegramState } from '../../api/api-types';
import { Icon } from '../../icon/icon';
import { README_URL } from '../../links';
import { RAIL_TEXTS, readmeSection, TELEGRAM_ANCHOR } from '../rail-view';

/**
 * The Telegram card (UX-DR55, UX-DR56, AD-29): the body of the rail's Telegram section, which the rail shows only when the release
 * includes Telegram. While the bot is off or was rejected it says "Telegram not set up" and links "How to set it up" to the README's
 * Telegram section in a new tab, saying so for assistive technology. The other states show nothing under the heading until Story
 * 12.3 adds them. It shows no banner and is not a live region.
 */
@Component({
  selector: 'app-telegram-card',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (notSetUp()) {
      <div class="card">
        <span class="text">{{ texts.telegramNotSetUp }}</span>
        <a class="link" [href]="href" target="_blank" rel="noopener noreferrer"
          >{{ texts.telegramHowTo }}<app-icon name="external-link" [size]="12" /><span class="visually-hidden"> {{ opensInNewTab }}</span></a
        >
      </div>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .card {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
      padding: var(--space-2) var(--space-3);
      background: var(--telegram-card-background);
      border: var(--telegram-card-border);
      border-radius: var(--telegram-card-radius);
      color: var(--ink);
      font-size: var(--status-rail-section-row-typography-font-size);
      line-height: var(--status-rail-section-row-typography-line-height);
    }
    .link {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
    }
  `,
})
export class TelegramCard {
  /** The Telegram block of the snapshot. */
  readonly telegram = input.required<TelegramState>();

  protected readonly texts = RAIL_TEXTS;
  protected readonly opensInNewTab = CHAT_TEXTS.opensInNewTab;
  protected readonly href = readmeSection(README_URL, TELEGRAM_ANCHOR);
  protected readonly notSetUp = computed(() => this.telegram().state === 'off' || this.telegram().state === 'rejected');
}
