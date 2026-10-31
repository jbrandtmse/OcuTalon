import { ChangeDetectionStrategy, Component, computed, inject, input } from '@angular/core';

import { CHAT_TEXTS } from '../../chat/chat-view';
import { pageTime } from '../../chat/page-time';
import type { TelegramState } from '../../api/api-types';
import { Icon } from '../../icon/icon';
import { LiveState } from '../../live/live-state';
import { README_URL } from '../../links';
import { RAIL_TEXTS, readmeSection, TELEGRAM_ANCHOR } from '../rail-view';
import { TELEGRAM_CARD_TEXTS, telegramCardView } from './telegram-card-view';

/**
 * The Telegram card (UX-DR55, UX-DR56, AD-29): the body of the rail's Telegram section, which the rail shows only when the release
 * includes Telegram. While the bot is off or was rejected it says "Telegram not set up" and links "How to set it up" to the README's
 * Telegram section in a new tab, saying so for assistive technology. The other states show nothing under the heading until Story
 * 12.3 adds them. It shows no banner and is not a live region.
 *
 * It is paused (Story 12.8; UX-DR56, UX-DR116) while the store holds the `telegramPaused` condition as active, the banner's own reading
 * (telegram-card-view.ts), ahead of every other state: the `circle-pause` icon, "Telegram paused" and "Trying again at {time}", with no
 * link, QR code or code. The root's `data-state` is `paused` or `not-set-up`.
 */
@Component({
  selector: 'app-telegram-card',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (view().kind === 'paused') {
      <div class="card" data-state="paused">
        <span class="paused"><app-icon class="paused-icon" name="circle-pause" [size]="16" /><span class="text">{{ pausedText }}</span></span>
        <span class="caption">{{ view().retry }}</span>
      </div>
    } @else if (view().kind === 'not-set-up') {
      <div class="card" data-state="not-set-up">
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
    .paused {
      display: inline-flex;
      align-items: center;
      gap: var(--space-2);
    }
    .paused-icon {
      color: var(--telegram-card-paused-icon);
    }
    .caption {
      font-family: var(--type-caption-font-family);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
      line-height: var(--type-caption-line-height);
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

  private readonly live = inject(LiveState);

  protected readonly texts = RAIL_TEXTS;
  protected readonly pausedText = TELEGRAM_CARD_TEXTS.paused;
  protected readonly opensInNewTab = CHAT_TEXTS.opensInNewTab;
  protected readonly href = readmeSection(README_URL, TELEGRAM_ANCHOR);
  protected readonly view = computed(() => telegramCardView(this.telegram(), this.live.store()?.status, { time: (iso) => pageTime(iso) }));
}
