import { ChangeDetectionStrategy, Component, computed, inject, input, output } from '@angular/core';

import type { EmailValues } from '../api/api-types';
import { CHAT_TEXTS } from '../chat/chat-view';
import { pageTime } from '../chat/page-time';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import { GUIDE_URL } from '../links';
import { RAIL_TEXTS, readmeSection, TELEGRAM_ANCHOR } from '../rail/rail-view';
import { TELEGRAM_CARD_TEXTS, telegramCardView } from '../rail/telegram-card/telegram-card-view';
import { EmailSection } from './email-section';
import { channelsView, SETTINGS_TEXTS } from './settings-view';
import { WebhooksSection } from './webhooks-section';

/**
 * The Channels section (Story 18.2; FR-21, FR-22): the state of Telegram, read from the snapshot's Telegram block and the live status conditions that the
 * status rail's card reads (telegramCardView), and below it the Email group (EmailSection, Story 21.2). The Telegram part has no form, no Save button and no
 * field for the bot token, which this page never shows or asks for:
 *   - not set up (the bot is off or was rejected): "Telegram not set up" and the link "How to set it up" to the README's Telegram section, in a new tab;
 *   - paused: "Telegram paused" and "Trying again at {time}", the time in the browser's zone;
 *   - otherwise (on): "Telegram on";
 *   - a release that does not include Telegram: no Telegram block.
 * The state follows the live updates, as the rail's card does. The Webhooks group (Story 35.3) follows the Email group: app-webhooks-section.
 */
@Component({
  selector: 'app-channels-section',
  imports: [EmailSection, Icon, WebhooksSection],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @switch (view().kind) {
      @case ('not-set-up') {
        <div class="telegram" data-state="not-set-up">
          <span class="text">{{ rail.telegramNotSetUp }}</span>
          <a class="link" [href]="href" target="_blank" rel="noopener noreferrer"
            >{{ rail.telegramHowTo }}<app-icon name="external-link" [size]="12" /><span class="visually-hidden"> {{ opensInNewTab }}</span></a
          >
        </div>
      }
      @case ('paused') {
        <div class="telegram" data-state="paused">
          <span class="text">{{ card.paused }}</span>
          <span class="caption">{{ view().retry }}</span>
        </div>
      }
      @case ('on') {
        <div class="telegram" data-state="on">
          <span class="text">{{ texts.channels.telegramOn }}</span>
        </div>
      }
    }
    <app-email-section [values]="email()" (saved)="emailSaved.emit($event)" (dirtyChange)="dirtyChange.emit($event)" />
    <app-webhooks-section />
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      max-width: 480px;
    }
    .telegram {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
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
export class ChannelsSection {
  private readonly live = inject(LiveState);

  /** The mailbox values that the settings page loaded; nothing on the online demo. */
  readonly email = input<EmailValues | undefined>();

  /** The new mailbox values after a save, for the page to keep. */
  readonly emailSaved = output<EmailValues>();

  /** Whether the Email form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  protected readonly texts = SETTINGS_TEXTS;
  protected readonly rail = RAIL_TEXTS;
  protected readonly card = TELEGRAM_CARD_TEXTS;
  protected readonly opensInNewTab = CHAT_TEXTS.opensInNewTab;
  protected readonly href = readmeSection(GUIDE_URL, TELEGRAM_ANCHOR);

  /** Which view shows: from the store's Telegram block and status conditions, through the Telegram card's own view. */
  protected readonly view = computed(() => {
    const telegram = this.live.store()?.telegram;
    if (telegram === undefined) {
      return channelsView(false, 'none', '');
    }
    const card = telegramCardView(telegram, this.live.store()?.status, { code: undefined, refused: false, justUnpaired: false, now: Date.now() }, { time: (iso) => pageTime(iso) });
    return channelsView(telegram.included, card.kind, card.retry);
  });
}
