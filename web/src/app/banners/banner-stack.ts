import { afterNextRender, ChangeDetectionStrategy, Component, computed, DestroyRef, effect, ElementRef, inject, Injector, signal, untracked } from '@angular/core';

import { CHAT_TEXTS } from '../chat/chat-view';
import { formatCost } from '../chat/decision-view';
import { pageTime } from '../chat/page-time';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import { README_URL } from '../links';
import { renderPageText } from '../msg/catalog';
import { readmeSection, TELEGRAM_ANCHOR } from '../rail/rail-view';
import { Announcer } from '../shared/announcer';
import { activeBanners, BANNER_TEXTS, type BannerFormat, type BannerId, type BannerInput, bannersView, type BannerView, closeBanner, retainClosed } from './banner-view';

/** The values banner-view.ts reuses, from the real modules. */
const FORMAT: BannerFormat = {
  text: (key, slots) => renderPageText(key, slots),
  time: (iso) => pageTime(iso),
  cost: (amount) => formatCost(amount),
  readmeUrl: README_URL,
  telegramUrl: readmeSection(README_URL, TELEGRAM_ANCHOR),
};

/** The attribute that marks a banner's element with its id. */
const BANNER_ID = 'data-banner';

/**
 * The announcer replaces a message that is still waiting, so banners that appear together are announced this far apart
 * (milliseconds), longer than the announcer's own delay before it reads one.
 */
const ANNOUNCE_GAP_MS = 150;

/**
 * The stack of status banners that sits under the header, in `.banner-slot` (Story 2.10; UX-DR34, UX-DR97 to UX-DR100, UX-DR116):
 * the banners of banner-view.ts for the live store, in the catalog's order. A banner is full width, at least 44px tall, with the
 * background and text colour of its variant, a 4px accent on its left edge and its icon in the accent colour. It has at most one
 * action, an underlined link that opens a new tab and says so for assistive technology, and only Reset soon and Reconnecting have
 * a Close button, an icon-only ghost button. The texts are the catalog's and are bound by interpolation.
 * - No banner is a live region. Once the first snapshot has loaded, each banner that appears is announced once through the
 *   polite announcer, whether an event or a reloaded snapshot brought it; the banners of the first snapshot are not announced.
 * - A closed banner stays away while its condition holds with the slots it had; it returns, announced, when the condition
 *   clears and starts again or its slots change. The records live for the page's life.
 * - A banner takes focus (tabindex -1) but is not in the tab order. When a banner that holds focus, or holds the focus in its
 *   link or Close button, leaves, focus moves without scrolling to the next banner, else the previous one, else the main
 *   region. Nothing else here moves focus.
 */
@Component({
  selector: 'app-banner-stack',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (banner of banners(); track banner.id) {
      <div class="banner" tabindex="-1" [attr.data-banner]="banner.id" [attr.data-variant]="banner.variant">
        <app-icon class="mark" [name]="banner.icon" [size]="20" />
        <span class="text">{{ banner.text }}</span>
        @if (banner.action; as action) {
          <a class="action" [href]="action.href" target="_blank" rel="noopener noreferrer"
            >{{ action.text }}<app-icon name="external-link" [size]="12" /><span class="visually-hidden"> {{ opensInNewTab }}</span></a
          >
        }
        @if (banner.closable) {
          <button type="button" class="button button-ghost close" [attr.aria-label]="texts.close" (click)="close(banner)">
            <app-icon name="x" [size]="16" />
          </button>
        }
      </div>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .banner {
      display: flex;
      align-items: center;
      gap: var(--space-3);
      box-sizing: border-box;
      width: 100%;
      min-height: var(--banner-min-height);
      padding: var(--space-2) var(--space-4);
      border-left: 4px solid var(--banner-accent);
      background: var(--banner-background);
      color: var(--banner-foreground);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-font-weight);
      line-height: var(--type-body-line-height);
    }
    .banner[data-variant='danger'] {
      --banner-background: var(--status-banner-danger-background);
      --banner-foreground: var(--status-banner-danger-foreground);
      --banner-accent: var(--status-banner-danger-accent);
      --banner-min-height: var(--status-banner-danger-min-height);
    }
    .banner[data-variant='warning'] {
      --banner-background: var(--status-banner-warning-background);
      --banner-foreground: var(--status-banner-warning-foreground);
      --banner-accent: var(--status-banner-warning-accent);
      --banner-min-height: var(--status-banner-warning-min-height);
    }
    .banner[data-variant='info'] {
      --banner-background: var(--status-banner-info-background);
      --banner-foreground: var(--status-banner-info-foreground);
      --banner-accent: var(--status-banner-info-accent);
      --banner-min-height: var(--status-banner-info-min-height);
    }
    .mark {
      flex: none;
      color: var(--banner-accent);
    }
    .text {
      flex: 1;
      min-width: 0;
    }
    .action {
      display: inline-flex;
      flex: none;
      align-items: center;
      gap: var(--space-1);
      color: var(--banner-foreground);
      text-decoration-line: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
    }
    .action:hover,
    .action:focus-visible {
      text-decoration-thickness: 2px;
    }
    .close {
      flex: none;
      padding: 0 var(--space-2);
      color: var(--banner-foreground);
    }
  `,
})
export class BannerStack {
  private readonly live = inject(LiveState);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  protected readonly texts = BANNER_TEXTS;
  protected readonly opensInNewTab = CHAT_TEXTS.opensInNewTab;

  /** The banners the user closed, by id, with the signature each had. */
  private readonly closed = signal<BannerInput['closed']>({});

  /** What the view reads, until the snapshot has loaded: nothing. */
  private readonly input = computed(() => {
    const store = this.live.store();
    if (store === undefined) {
      return undefined;
    }
    return { status: store.status, own: [], onlineDemo: this.live.snapshot()?.onlineDemo === true } satisfies Omit<BannerInput, 'closed'>;
  });

  /** Every banner whose condition holds, closed or not. */
  private readonly active = computed(() => {
    const input = this.input();
    return input === undefined ? [] : activeBanners(input, FORMAT);
  });

  protected readonly banners = computed(() => {
    const input = this.input();
    return input === undefined ? [] : bannersView({ ...input, closed: this.closed() }, FORMAT);
  });

  /** The ids of the banners that were shown at the last run of the announcing effect; undefined until the first snapshot has loaded. */
  private shown: ReadonlySet<BannerId> | undefined;
  private readonly waiting: string[] = [];
  private gap: ReturnType<typeof setTimeout> | undefined;

  constructor() {
    inject(DestroyRef).onDestroy(() => globalThis.clearTimeout(this.gap));
    effect(() => {
      const active = this.active();
      untracked(() => {
        const closed = this.closed();
        const kept = retainClosed(closed, active);
        if (kept !== closed) {
          this.closed.set(kept);
        }
      });
    });
    effect(() => {
      const banners = this.banners();
      const loaded = this.live.status() === 'loaded';
      untracked(() => this.announce(banners, loaded));
    });
    effect(() => {
      this.banners();
      untracked(() => this.keepFocus());
    });
  }

  protected close(banner: BannerView): void {
    this.closed.update((closed) => closeBanner(closed, banner));
  }

  /** Announces each banner that was not shown at the last run, once the first snapshot has loaded. */
  private announce(banners: readonly BannerView[], loaded: boolean): void {
    if (!loaded) {
      return;
    }
    const before = this.shown;
    this.shown = new Set(banners.map((banner) => banner.id));
    if (before === undefined) {
      return;
    }
    for (const banner of banners) {
      if (!before.has(banner.id)) {
        this.waiting.push(banner.text);
      }
    }
    this.drain();
  }

  /** Announces the waiting texts one at a time, ANNOUNCE_GAP_MS apart. */
  private drain(): void {
    if (this.gap !== undefined) {
      return;
    }
    const next = this.waiting.shift();
    if (next === undefined) {
      return;
    }
    this.announcer.announce(next);
    this.gap = globalThis.setTimeout(() => {
      this.gap = undefined;
      this.drain();
    }, ANNOUNCE_GAP_MS);
  }

  /**
   * Before the stack renders again: if a banner holds focus, or its link or Close button does, remembers the banners' order, and
   * after the render moves focus, when that banner is gone, to the next banner that is left, else the nearest one before it,
   * else the main region (UX-DR131). A banner that is still there keeps focus as it is.
   */
  private keepFocus(): void {
    const host = this.host.nativeElement;
    const active = document.activeElement;
    const focused = active instanceof Element && host.contains(active) ? active.closest(`[${BANNER_ID}]`) : null;
    if (focused === null) {
      return;
    }
    const order = Array.from(host.querySelectorAll(`[${BANNER_ID}]`)).map((one) => one.getAttribute(BANNER_ID) ?? '');
    const id = focused.getAttribute(BANNER_ID) ?? '';
    afterNextRender(
      () => {
        const left = new Set(Array.from(host.querySelectorAll(`[${BANNER_ID}]`)).map((one) => one.getAttribute(BANNER_ID) ?? ''));
        if (left.has(id)) {
          return;
        }
        const at = order.indexOf(id);
        const next = order.slice(at + 1).find((one) => left.has(one));
        const previous = order.slice(0, at).reverse().find((one) => left.has(one));
        const target = next ?? previous;
        const element = target === undefined ? document.querySelector<HTMLElement>('main.main') : host.querySelector<HTMLElement>(`[${BANNER_ID}="${target}"]`);
        element?.focus({ preventScroll: true });
      },
      { injector: this.injector },
    );
  }
}
