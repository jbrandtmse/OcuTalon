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
import { ChatOutbox } from './chat-outbox';
import { CHAT_TEXTS, chatView, isFreshChat, type TurnView } from './chat-view';
import { Composer } from './composer';
import { EmptyChat } from './empty-chat';
import { OcutalonReply } from './ocutalon-reply';
import { UserMessage } from './user-message';

/** How far from the bottom (px) the list still counts as at the bottom. */
const BOTTOM_SLACK_PX = 24;

/** An element of the list that the New messages button focuses: a user message or a reply, by the turn's key. */
interface Target {
  key: string;
  part: 'user' | 'reply';
}

/** True once a turn's reply is the model's text or a fallback: the reply has landed. */
const landed = (turn: TurnView): boolean => turn.reply.kind === 'text' || turn.reply.kind === 'fallback';

/**
 * The chat panel (UX-DR58, UX-DR67, UX-DR126), inside the page's main landmark once the snapshot has loaded. The list shows the
 * live store's chat.message entries in store order and then this page's own messages that the store does not hold yet; a fresh
 * session shows the empty chat panel instead. The composer sits under the list. Nothing here is a live region and nothing moves
 * focus except the New messages button.
 *
 * Scrolling: the list scrolls on its own and is at the bottom when within 24 px of it. On the first load, and whenever it is at
 * the bottom, new content keeps it there (a ResizeObserver on the list and its content). When it is scrolled up, content from
 * elsewhere (a new entry, or a reply that lands) changes nothing about its scroll, and the New messages button shows. Pressing
 * it scrolls to the bottom with no smooth scroll and focuses the first entry that arrived or changed meanwhile; it hides once
 * the list is at the bottom. A new message that this page sends (ChatOutbox.send, from the composer or later from the demo guide) scrolls the list to the bottom, as the user's own action.
 *
 * A 1 s clock ticks only while a turn is running, for the elapsed seconds that the indicator adds after 10 s. The page notes
 * when it first saw each turn running.
 */
@Component({
  selector: 'app-chat-panel',
  imports: [Composer, EmptyChat, Icon, OcutalonReply, UserMessage],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="list" #list (scroll)="onScroll()">
      <div class="content" #content>
        @if (fresh()) {
          <app-empty-chat />
        } @else {
          <div class="entries">
            @for (turn of turns(); track turn.key) {
              <div class="turn">
                <app-user-message [turn]="turn" (retry)="outbox.retry(turn.key)" />
                <app-ocutalon-reply [turn]="turn" />
              </div>
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
    .list {
      flex: 1;
      display: flex;
      flex-direction: column;
      min-height: 0;
      padding-inline: var(--chat-panel-padding-inline);
      overflow-y: auto;
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
  `,
})
export class ChatPanel {
  protected readonly live = inject(LiveState);
  protected readonly outbox = inject(ChatOutbox);
  protected readonly texts = CHAT_TEXTS;
  private readonly injector = inject(Injector);
  private readonly list = viewChild.required<ElementRef<HTMLElement>>('list');
  private readonly content = viewChild.required<ElementRef<HTMLElement>>('content');

  /** When (ms, the page's clock) the page first saw each turn running. */
  private readonly since = new Map<string, number>();
  /** The 1 s clock; it only changes while a turn is running. */
  private readonly clock = signal(0);
  /** Whether the list is at the bottom, as of its last scroll or the last time the panel put it there. */
  private atBottom = true;
  /** Whether each turn's reply has landed, as of the last look. */
  private readonly landedBefore = new Map<string, boolean>();
  /** The first entry that arrived or changed while the list was scrolled up. */
  private target: Target | undefined;

  /** True while the empty chat panel shows. */
  protected readonly fresh = computed(() => isFreshChat(this.live.store()?.chat ?? [], this.outbox.entries()));

  /** True while a turn of the store is running. */
  private readonly running = computed(() =>
    (this.live.store()?.chat ?? []).some((item) => item.type === 'chat.message' && item.payload.state === 'running'),
  );

  /** The entries to render. */
  protected readonly turns = computed(() => {
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
    return chatView(chat, this.outbox.entries(), this.since, now);
  });

  /** True while the New messages button shows. */
  protected readonly unseen = signal(false);

  constructor() {
    effect(() => this.noteArrivals(this.turns()));
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

  protected onScroll(): void {
    const list = this.list().nativeElement;
    this.atBottom = list.scrollHeight - list.scrollTop - list.clientHeight <= BOTTOM_SLACK_PX;
    if (this.atBottom) {
      this.seenAll();
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
  private noteArrivals(turns: readonly TurnView[]): void {
    let first: Target | undefined;
    for (const turn of turns) {
      const before = this.landedBefore.get(turn.key);
      const now = landed(turn);
      if (first === undefined && before === undefined) {
        first = { key: turn.key, part: 'user' };
      } else if (first === undefined && !before && now) {
        first = { key: turn.key, part: 'reply' };
      }
      this.landedBefore.set(turn.key, now);
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
  }
}
