import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal, untracked } from '@angular/core';
import type { Subscription } from 'rxjs';

import { ApiClient } from '../../api/api-client';
import type { PairingCode, TelegramState } from '../../api/api-types';
import { CHAT_TEXTS } from '../../chat/chat-view';
import { pageTime } from '../../chat/page-time';
import { Icon } from '../../icon/icon';
import { LiveState } from '../../live/live-state';
import { README_URL } from '../../links';
import { RAIL_TEXTS, readmeSection, TELEGRAM_ANCHOR } from '../rail-view';
import {
  asksForCode,
  CODE_RETRY_MS,
  CODE_SPACING_MS,
  dueTime,
  qrSymbol,
  TELEGRAM_CARD_TEXTS,
  telegramCardView,
  type HeldCode,
} from './telegram-card-view';

/**
 * The Telegram card (UX-DR55, UX-DR56, AD-29): the body of the rail's Telegram section, which the rail shows only when the release
 * includes Telegram. While the bot is off or was rejected it says "Telegram not set up" and links "How to set it up" to the README's
 * Telegram section in a new tab, saying so for assistive technology. It shows no banner and is not a live region.
 *
 * It is paused (Story 12.8; UX-DR56, UX-DR116) while the store holds the `telegramPaused` condition as active, the banner's own reading
 * (telegram-card-view.ts), ahead of every other state: the `circle-pause` icon, "Telegram paused" and "Trying again at {time}", with no
 * link, QR code or code.
 *
 * It is unpaired (Story 12.3; FR-18, AD-4, AD-14) while the snapshot says Telegram is `on` with a bot name, the session is not paired
 * and the card is not paused. It then asks the server for a pairing code through `ApiClient.pairingCode()` and shows, in this order, the
 * QR code of `https://t.me/<bot>?start=<code>` (drawn here by qrcode-generator in navy on white, bound as an SVG element through the
 * template), the scan line, and a foot with the "Open in Telegram" link and "New code in {n} min". The code lives only in this
 * component's memory and in the link and QR code it renders: it is written to no log, store, URL or announcement.
 *   - A code is due at the earlier of its expiry and ten minutes after it arrived; at that time the card asks again, never sooner than
 *     ten seconds after its previous request, so a browser clock ahead of the server's cannot make a loop. The new code is bound into the
 *     same link and SVG elements, so a focused link keeps its focus and nothing the user typed moves. The card moves focus nowhere and
 *     announces nothing.
 *   - A 409 (the server's state is not `on`) shows the not-set-up view and stops asking until the Telegram block's state, bot name or
 *     pairing, or the pause, changes. Any other failure shows nothing and asks again 30 seconds later.
 *   - Leaving the condition (paused, paired, not on) drops the code and every timer; coming back asks for a fresh code.
 * The root's `data-state` is `paused`, `not-set-up` or `unpaired`.
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
    } @else if (view().kind === 'unpaired') {
      <div class="card" data-state="unpaired">
        <div class="qr">
          <svg role="img" shape-rendering="crispEdges" [attr.aria-label]="cardTexts.qrAlt" [attr.viewBox]="viewBox()">
            <path [attr.d]="symbol().path" />
          </svg>
        </div>
        <span class="text">{{ cardTexts.scan }}</span>
        <div class="foot">
          <a class="link" [href]="view().link" target="_blank" rel="noopener noreferrer"
            >{{ cardTexts.open }}<span class="visually-hidden"> {{ cardTexts.opensTelegram }}</span></a
          >
          <span class="caption">{{ newCodeIn() }}</span>
        </div>
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
    .qr {
      box-sizing: border-box;
      width: var(--qr-code-block-size);
      padding: var(--qr-code-block-quiet-zone);
      background: var(--qr-code-block-background);
      border-radius: var(--qr-code-block-radius);
      forced-color-adjust: none;
    }
    .qr svg {
      display: block;
      width: 100%;
    }
    .qr path {
      fill: var(--qr-code-block-foreground);
    }
    .foot {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
    }
  `,
})
export class TelegramCard {
  /** The Telegram block of the snapshot. */
  readonly telegram = input.required<TelegramState>();

  private readonly live = inject(LiveState);
  private readonly api = inject(ApiClient);

  protected readonly texts = RAIL_TEXTS;
  protected readonly cardTexts = TELEGRAM_CARD_TEXTS;
  protected readonly pausedText = TELEGRAM_CARD_TEXTS.paused;
  protected readonly opensInNewTab = CHAT_TEXTS.opensInNewTab;
  protected readonly href = readmeSection(README_URL, TELEGRAM_ANCHOR);

  /** The code the card holds, with its due time; none before the first answer and after a failure. */
  private readonly held = signal<HeldCode | undefined>(undefined);
  /** The browser time, ticked every second while a code is held, for "New code in {n} min". */
  private readonly now = signal(Date.now());
  /** The asking key at which the server refused a code (409), or none. */
  private readonly refusedAt = signal<string | undefined>(undefined);
  /** When the latest request started, in browser milliseconds; it outlives the asking so that two requests are never closer than the spacing. */
  private lastRequest = Number.NEGATIVE_INFINITY;

  /** The key under which the card asks: the values of the Telegram block that a refusal depends on, or "" while it does not ask. */
  private readonly askKey = computed(() => {
    const telegram = this.telegram();
    return asksForCode(telegram, this.live.store()?.status) ? `${telegram.state}|${telegram.botUserName}|${telegram.paired}` : '';
  });
  private readonly refused = computed(() => this.askKey() !== '' && this.refusedAt() === this.askKey());
  private readonly holding = computed(() => this.held() !== undefined);

  protected readonly view = computed(() =>
    telegramCardView(
      this.telegram(),
      this.live.store()?.status,
      { code: this.held(), refused: this.refused(), now: this.now() },
      { time: (iso) => pageTime(iso) },
    ),
  );
  private readonly link = computed(() => this.view().link);
  /** The QR symbol of the link; drawn again only when the link changes, not at each tick. */
  protected readonly symbol = computed(() => {
    const link = this.link();
    return link === '' ? { size: 0, path: '' } : qrSymbol(link);
  });
  protected readonly viewBox = computed(() => `0 0 ${this.symbol().size} ${this.symbol().size}`);
  protected readonly newCodeIn = computed(() => TELEGRAM_CARD_TEXTS.newCodeIn.replace('{n}', String(this.view().minutes)));

  constructor() {
    // The asking: while the key holds, ask for a code, and again at each code's due time; a change of the key ends the old asking.
    effect((onCleanup) => {
      const key = this.askKey();
      untracked(() => {
        this.held.set(undefined);
        if (key === '') {
          this.refusedAt.set(undefined);
          return;
        }
        if (this.refusedAt() === key) return;
        this.refusedAt.set(undefined);
        onCleanup(this.ask(key));
      });
    });
    // The countdown's tick, while a code is held.
    effect((onCleanup) => {
      if (!this.holding()) return;
      untracked(() => this.now.set(Date.now()));
      const id = setInterval(() => this.now.set(Date.now()), 1000);
      onCleanup(() => clearInterval(id));
    });
  }

  /** Asks for a code now (or as soon as the spacing allows), and again at each due time; returns the function that ends it all. */
  private ask(key: string): () => void {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let request: Subscription | undefined;
    let ended = false;
    const later = (at: number): void => {
      timer = setTimeout(send, Math.max(0, Math.max(at, this.lastRequest + CODE_SPACING_MS) - Date.now()));
    };
    const send = (): void => {
      if (ended) return;
      this.lastRequest = Date.now();
      request = this.api.pairingCode().subscribe({
        next: (answer: PairingCode) => {
          const received = Date.now();
          const due = dueTime(answer.expiresAt, received);
          this.now.set(received);
          this.held.set({ code: answer.code, due });
          later(due);
        },
        error: (error: unknown) => {
          this.held.set(undefined);
          if (error instanceof HttpErrorResponse && error.status === 409) {
            this.refusedAt.set(key);
            return;
          }
          later(Date.now() + CODE_RETRY_MS);
        },
      });
    };
    later(0);
    return () => {
      ended = true;
      if (timer !== undefined) clearTimeout(timer);
      request?.unsubscribe();
    };
  }
}
