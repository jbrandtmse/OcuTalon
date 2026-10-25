import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  Injector,
  afterNextRender,
  computed,
  effect,
  inject,
  signal,
  untracked,
  viewChild,
} from '@angular/core';

import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { LAYOUT_QUERIES } from '../shared/layout-view';
import { Popovers } from '../shared/popover';
import { type ChatAnnounceFormat, chatAnnouncements, type ChatHeard, landed } from './chat-announcements';
import { ChatOutbox } from './chat-outbox';
import { CHAT_TEXTS, chatView, isFreshChat, type ChatEntryView } from './chat-view';
import { Composer } from './composer';
import { EmptyChat } from './empty-chat';
import { NoticeCard } from './notice-card';
import { OcutalonReply, replyFallbackText } from './ocutalon-reply';
import { parseReply, plainText } from './reply-text';
import { UserMessage } from './user-message';

/** How far from the bottom (px) the list still counts as at the bottom. */
const BOTTOM_SLACK_PX = 24;

/** An element of the list that the New messages button focuses: a user message or a reply, by the turn's key, or a notice card. */
interface Target {
  key: string;
  part: 'user' | 'reply' | 'notice';
}

/** The attributes that mark an item of the list (a user message, a reply or a notice card) with its part and its key. */
const PART = 'data-part';
const KEY = 'data-key';

/**
 * Where focus goes when an update removes the element that holds it inside the list (UX-DR131): an item that is still there takes
 * it (Retry sending leaves focus on its message), and one that is gone leaves it to the main region.
 */
const FOCUS_RULE: FocusRule = {
  item: `[${PART}][${KEY}]`,
  keyOf: (item) => `${item.getAttribute(PART) ?? ''}:${item.getAttribute(KEY) ?? ''}`,
};

/** The texts of the chat's announcements and the reads of a reply, from the real modules. */
const ANNOUNCE_FORMAT: ChatAnnounceFormat = {
  announceReplied: CHAT_TEXTS.announceReplied,
  announceTellNow: CHAT_TEXTS.announceTellNow,
  replyText: (replyText) => plainText(parseReply(replyText)),
  fallbackText: replyFallbackText,
};

/**
 * The chat panel (UX-DR58, UX-DR67, UX-DR126), inside the page's main landmark once the snapshot has loaded. The list shows the
 * live store's chat.message entries and its tell-now and reminder notice cards in store order and then this page's own messages
 * that the store does not hold yet; a fresh session shows the empty chat panel instead. The composer sits under the list. Nothing here is a live region.
 * From 1024px wide the panel fills main and the list takes the height that is left. Below it (the stacked column, Story 2.15) the list is
 * as tall as its content up to 70vh and scrolls on its own beyond that, with the composer under it.
 *
 * Announcements (chat-announcements.ts, through the polite Announcer): the chat announces its own entries, once each, and the first
 * look at the entries is silent. A reply that has landed is "OcuTalon replied:" and its first sentence, a new tell-now card is
 * "Tell now:" and its first sentence, and a new reminder card is its text. The user's messages, Deciding and Working, the
 * seconds and a card updated in place are silent.
 *
 * Focus: only the user's New messages button moves it, and the page's focus rule (shared/focus-rule.ts) when an update removes the
 * element that holds it inside the list: an item that is still there takes it (the message of Retry sending), else the main region.
 *
 * Scrolling: the list scrolls on its own and is at the bottom when within 24 px of it. On the first load, and whenever it is at
 * the bottom, new content keeps it there (a ResizeObserver on the list and its content). It leaves the bottom only when it is
 * scrolled up (its scrollTop falls), so content that grows between the panel's own scroll to the bottom and that scroll's
 * event does not stop it following. When it is scrolled up, content from
 * elsewhere (a new entry, a notice card or a reply that lands) changes nothing about its scroll, and the New messages button shows. Pressing
 * it scrolls to the bottom with no smooth scroll and focuses the first entry that arrived or changed meanwhile; it hides once
 * the list is at the bottom. A new message that this page sends (ChatOutbox.send, from the composer or later from the demo guide) scrolls the list to the bottom, as the user's own action.
 *
 * A 1 s clock ticks only while a turn is running, for the elapsed seconds that the indicator adds after 10 s. The page notes
 * when it first saw each turn running. The step labels of the live store (turn.step events, by the running turn's ref) reach the
 * indicator through chatView.
 */
@Component({
  selector: 'app-chat-panel',
  imports: [Composer, EmptyChat, Icon, NoticeCard, OcutalonReply, UserMessage],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="list" #list (scroll)="onScroll()">
      <div class="content" #content>
        @if (fresh()) {
          <app-empty-chat />
        } @else {
          <div class="entries">
            @for (entry of entries(); track entry.key) {
              @if (entry.entry === 'turn') {
                <div class="turn">
                  <app-user-message [turn]="entry" (retry)="outbox.retry(entry.key)" />
                  <app-ocutalon-reply [turn]="entry" />
                </div>
              } @else {
                <app-notice-card [notice]="entry" [instanceZone]="instanceZone()" />
              }
            }
          </div>
        }
      </div>
    </div>
    <div class="dock">
      @if (unseen()) {
        <button type="button" class="new-messages" (click)="showNew()">
          <app-icon name="chevron-down" />
          {{ texts.newMessages }}
        </button>
      }
      <app-composer />
    </div>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-height: 0;
    }
    /* The list is the containing block of the visually hidden texts of its entries, so that they scroll with it and never lengthen the page. */
    .list {
      position: relative;
      flex: 1;
      display: flex;
      flex-direction: column;
      min-height: 0;
      padding-inline: var(--chat-panel-padding-inline);
      overflow-y: auto;
      scroll-padding: var(--space-scroll-gutter);
    }
    @media ${LAYOUT_QUERIES.stacked} {
      :host {
        flex: none;
      }
      .list {
        flex: none;
        max-height: 70vh;
      }
    }
    .content {
      flex: 1 0 auto;
      display: flex;
      flex-direction: column;
    }
    .entries {
      display: flex;
      flex-direction: column;
      gap: var(--space-5);
      padding: var(--space-5) var(--space-6);
    }
    .turn {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
    }
    .dock {
      position: relative;
      flex: none;
      padding: var(--space-3) var(--space-6) var(--space-4);
    }
    .new-messages {
      position: absolute;
      left: 50%;
      bottom: 100%;
      transform: translateX(-50%);
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      min-height: var(--new-messages-button-min-height);
      padding: 0 var(--space-3);
      background: var(--new-messages-button-background);
      color: var(--new-messages-button-foreground);
      border: var(--new-messages-button-border);
      border-radius: var(--new-messages-button-radius);
      box-shadow: var(--popover-shadow);
      font-family: var(--font-ui);
      font-size: var(--button-primary-typography-font-size);
      font-weight: var(--button-primary-typography-font-weight);
      line-height: var(--button-primary-typography-line-height);
      cursor: pointer;
    }
    /* The button's own shadow adds to the focus halo of base.css; it does not replace it. */
    .new-messages:focus-visible {
      box-shadow:
        0 0 0 2px var(--surface),
        var(--popover-shadow);
    }
  `,
})
export class ChatPanel {
  protected readonly live = inject(LiveState);
  protected readonly outbox = inject(ChatOutbox);
  protected readonly texts = CHAT_TEXTS;
  private readonly injector = inject(Injector);
  private readonly announcer = inject(Announcer);
  private readonly popovers = inject(Popovers);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly list = viewChild.required<ElementRef<HTMLElement>>('list');
  private readonly content = viewChild.required<ElementRef<HTMLElement>>('content');

  /** When (ms, the page's clock) the page first saw each turn running. */
  private readonly since = new Map<string, number>();
  /** The 1 s clock; it only changes while a turn is running. */
  private readonly clock = signal(0);
  /** Whether the list is at the bottom, as of its last scroll or the last time the panel put it there. */
  private atBottom = true;
  /** The list's scrollTop at its last scroll event, or where the panel last put it: a scroll event below it is a scroll up. */
  private lastTop = 0;
  /** Whether each turn's reply has landed, as of the last look. */
  private readonly landedBefore = new Map<string, boolean>();
  /** The entries as of the last look of the announcing effect; undefined until its first run. */
  private heard: ChatHeard | undefined;
  /** The first entry that arrived or changed while the list was scrolled up. */
  private target: Target | undefined;

  /** True while the empty chat panel shows. */
  protected readonly fresh = computed(() => isFreshChat(this.live.store()?.chat ?? [], this.outbox.entries()));

  /** True while a turn of the store is running. */
  private readonly running = computed(() =>
    (this.live.store()?.chat ?? []).some((item) => item.type === 'chat.message' && item.payload.state === 'running'),
  );

  /** The instance's time zone, from the snapshot; the notice cards' times name the browser's zone when its offset differs. */
  protected readonly instanceZone = computed(() => this.live.snapshot()?.instanceZone ?? '');

  /** The entries to render: turns and notice cards in the store's order, then the page's own messages. */
  protected readonly entries = computed(() => {
    const chat = this.live.store()?.chat ?? [];
    this.clock();
    const now = Date.now();
    for (const item of chat) {
      if (item.type === 'chat.message' && item.payload.state === 'running') {
        const key = item.payload.clientId || item.payload.ref || '';
        if (!this.since.has(key)) {
          this.since.set(key, now);
        }
      }
    }
    return chatView(chat, this.outbox.entries(), this.since, now, this.live.store()?.turnSteps);
  });

  /** True while the New messages button shows. */
  protected readonly unseen = signal(false);

  constructor() {
    effect(() => this.noteArrivals(this.entries()));
    effect(() => {
      const entries = this.entries();
      untracked(() => this.announce(entries));
    });
    effect(() => {
      this.entries();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, FOCUS_RULE));
    });
    let sends = this.outbox.sendCount();
    effect(() => {
      const count = this.outbox.sendCount();
      untracked(() => {
        if (count !== sends) {
          sends = count;
          this.onSent();
        }
      });
    });
    effect((onCleanup) => {
      if (this.running()) {
        const id = globalThis.setInterval(() => this.clock.update((tick) => tick + 1), 1000);
        onCleanup(() => globalThis.clearInterval(id));
      }
    });
    const destroyRef = inject(DestroyRef);
    afterNextRender(() => {
      const observer = new ResizeObserver(() => {
        if (this.atBottom) {
          this.scrollToBottom();
        }
      });
      observer.observe(this.list().nativeElement);
      observer.observe(this.content().nativeElement);
      destroyRef.onDestroy(() => observer.disconnect());
    });
  }

  /** Announces what the entries show that the last look did not (chat-announcements.ts); the first look only records them. */
  private announce(entries: readonly ChatEntryView[]): void {
    const { texts, heard } = chatAnnouncements(this.heard, entries, ANNOUNCE_FORMAT);
    this.heard = heard;
    for (const text of texts) {
      this.announcer.announce(text);
    }
  }

  /** At the bottom (within 24 px) the list is at the bottom; away from it, it has left the bottom only if it was scrolled up. */
  protected onScroll(): void {
    const list = this.list().nativeElement;
    const top = list.scrollTop;
    const up = top < this.lastTop;
    this.lastTop = top;
    if (list.scrollHeight - top - list.clientHeight <= BOTTOM_SLACK_PX) {
      this.atBottom = true;
      this.seenAll();
    } else if (up) {
      this.atBottom = false;
    }
  }

  /** This page sent a new message: the user's own action, so the list goes to the bottom. */
  private onSent(): void {
    this.seenAll();
    this.atBottom = true;
    afterNextRender(() => this.scrollToBottom(), { injector: this.injector });
  }

  /** The New messages button: the bottom, with no smooth scroll, and the focus on the first entry that arrived or changed. */
  protected showNew(): void {
    const target = this.target;
    this.seenAll();
    this.atBottom = true;
    this.scrollToBottom();
    if (target !== undefined) {
      const found = Array.from(this.list().nativeElement.querySelectorAll<HTMLElement>('[data-part]')).find(
        (element) => element.dataset['key'] === target.key && element.dataset['part'] === target.part,
      );
      found?.focus({ preventScroll: true });
    }
  }

  /** Remembers the first entry that arrived or whose reply landed since the last look; with the list scrolled up it shows the button. */
  private noteArrivals(entries: readonly ChatEntryView[]): void {
    let first: Target | undefined;
    for (const entry of entries) {
      const before = this.landedBefore.get(entry.key);
      const now = landed(entry);
      if (first === undefined && before === undefined) {
        first = { key: entry.key, part: entry.entry === 'notice' ? 'notice' : 'user' };
      } else if (first === undefined && !before && now) {
        first = { key: entry.key, part: 'reply' };
      }
      this.landedBefore.set(entry.key, now);
    }
    if (first !== undefined && !this.atBottom) {
      this.target ??= first;
      this.unseen.set(true);
    }
  }

  private seenAll(): void {
    this.target = undefined;
    this.unseen.set(false);
  }

  private scrollToBottom(): void {
    const list = this.list().nativeElement;
    list.scrollTop = list.scrollHeight;
    this.lastTop = list.scrollTop;
  }
}
