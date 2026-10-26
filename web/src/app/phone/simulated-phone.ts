import { AfterViewInit, ChangeDetectionStrategy, Component, DestroyRef, ElementRef, computed, effect, inject, input, signal, untracked, viewChild } from '@angular/core';

import { pageTimeBeside } from '../chat/page-time';
import { CHAT_TEXTS } from '../chat/chat-view';
import { SimulatedLabel } from '../devices/simulated-label';
import { newRefs } from '../devices/device-view';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import type { PhonePayload } from '../live/payloads';
import { atBottom, BOTTOM_SLACK_PX } from '../shared/follow-bottom';
import { revealRing } from '../shared/reveal-ring';
import { PHONE_TEXTS, type PhoneSnapshot, pendingApproval, phoneOf } from './phone-view';

/**
 * The simulated phone (Story 4.5; FR-13, UX-DR132): a generic phone silhouette on the device panel. A frame in the phone-frame colour
 * with large corners and the device shadow, a screen on the surface colour, a top bar that reads "OcuTalon" with the Simulated label,
 * and the feed of the session's phone messages, newest at the bottom. No clock, signal bars, brand or composer. Each message is a
 * sunken notification whose text keeps its line breaks (an interpolation, never HTML) and a caption time beside it.
 *
 * The phone decides nothing and renders no text (AD-12, AD-32): its list is the snapshot's `phone` and the store's phone events
 * (phone-view.ts), and each message's text is the server's. Nothing here is a live region: the chat card announces the event once.
 *
 * The feed is a tab stop and the scroller (a region named by its tab). It follows like the chat list: it is at the bottom when within
 * 24 px of it, and a message that arrives while it is at the bottom scrolls into view, with no New messages button. When the feed is
 * scrolled up, or a message of the list names an approval request that is pending, an arriving message changes nothing about its
 * scroll (a late arrival cannot shift Approve and Reject under the pointer) and the New messages button shows. Pressing it scrolls to
 * the bottom and focuses the first message that arrived meanwhile. Focus moves only for that press.
 */
@Component({
  selector: 'app-simulated-phone',
  imports: [Icon, SimulatedLabel],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="frame">
      <div class="screen">
        <div class="bar">
          <span class="name">{{ texts.name }}</span>
          <app-simulated-label />
        </div>
        <div class="feed ring-inside" #feed tabindex="0" role="region" [attr.aria-labelledby]="labelledBy()" (scroll)="onScroll()" (focusin)="reveal($event)">
          <div class="content" #content>
            @if (messages().length === 0) {
              <p class="empty">{{ texts.empty }}</p>
            } @else {
              <div class="notifications">
                @for (one of messages(); track one.ref) {
                  <div class="notification" tabindex="-1" [attr.data-key]="one.ref">
                    <p class="text">{{ one.text }}</p>
                    <span class="time">{{ timeOf(one) }}</span>
                  </div>
                }
              </div>
            }
          </div>
        </div>
        @if (unseen()) {
          <button type="button" class="new-messages" (click)="showNew()">
            <app-icon name="chevron-down" />
            {{ newMessages }}
          </button>
        }
      </div>
    </div>
  `,
  styles: `
    :host {
      --phone-screen-min: var(--space-phone-screen-min-height);
      display: flex;
      flex: 1 1 0;
      justify-content: center;
      min-height: calc(var(--phone-screen-min) + 2 * var(--space-2));
    }
    .frame {
      display: flex;
      flex-direction: column;
      flex: none;
      width: calc(var(--space-phone-screen-width) + 2 * var(--space-2));
      max-width: 100%;
      padding: var(--space-2);
      background: var(--simulated-phone-frame);
      border-radius: var(--rounded-xl);
      box-shadow: var(--simulated-phone-shadow);
    }
    .screen {
      position: relative;
      display: flex;
      flex: 1 1 0;
      flex-direction: column;
      min-height: var(--phone-screen-min);
      background: var(--simulated-phone-screen);
      border-radius: var(--simulated-phone-screen-radius);
      overflow: hidden;
    }
    .bar {
      display: flex;
      flex: none;
      align-items: center;
      justify-content: space-between;
      gap: var(--space-2);
      min-height: var(--space-target-min);
      padding: var(--space-1) var(--space-3);
      border-bottom: 1px solid var(--border);
    }
    .name {
      color: var(--ink);
      font-family: var(--font-ui);
      font-size: var(--device-tab-typography-font-size);
      font-weight: var(--device-tab-typography-font-weight);
      line-height: var(--device-tab-typography-line-height);
    }
    /* The feed is the containing block of its notifications and the scroller; it is a tab stop. */
    .feed {
      position: relative;
      flex: 1 1 0;
      display: flex;
      flex-direction: column;
      min-height: 0;
      overflow-y: auto;
      scroll-padding: var(--space-scroll-gutter);
    }
    .content {
      flex: 1 0 auto;
      display: flex;
      flex-direction: column;
    }
    .notifications {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      padding: var(--space-3) var(--space-3) var(--space-4);
    }
    .notification {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      padding: var(--space-3);
      background: var(--phone-notification-background);
      color: var(--phone-notification-foreground);
      border-radius: var(--phone-notification-radius);
      font-family: var(--font-ui);
      font-size: var(--phone-notification-typography-font-size);
      font-weight: var(--phone-notification-typography-font-weight);
      line-height: var(--phone-notification-typography-line-height);
    }
    .text {
      margin: 0;
      white-space: pre-line;
      overflow-wrap: anywhere;
    }
    .time {
      align-self: flex-end;
      color: var(--ink-muted);
      font-size: var(--tab-badge-typography-font-size);
      line-height: var(--tab-badge-typography-line-height);
    }
    .empty {
      margin: 0;
      padding: var(--space-4) var(--space-3);
      color: var(--ink-muted);
      font-family: var(--font-ui);
      font-size: var(--phone-notification-typography-font-size);
      line-height: var(--phone-notification-typography-line-height);
    }
    .new-messages {
      position: absolute;
      left: 50%;
      bottom: var(--space-3);
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
      white-space: nowrap;
      cursor: pointer;
    }
    .new-messages:focus-visible {
      box-shadow:
        0 0 0 2px var(--surface),
        var(--popover-shadow);
    }
  `,
})
export class SimulatedPhone implements AfterViewInit {
  /** The id of the tab that names the feed's region. */
  readonly labelledBy = input.required<string>();

  private readonly live = inject(LiveState);
  private readonly destroyRef = inject(DestroyRef);
  private readonly feed = viewChild.required<ElementRef<HTMLElement>>('feed');
  private readonly content = viewChild.required<ElementRef<HTMLElement>>('content');

  protected readonly texts = PHONE_TEXTS;
  protected readonly newMessages = CHAT_TEXTS.newMessages;

  /** The refs the phone has shown, as of its last look; undefined until the first look, which records the messages and counts none as new. */
  private seen: Set<string> | undefined;
  /** Whether the feed is at the bottom, as of its last scroll or the last time the phone put it there; a held arrival clears it. */
  private following = true;
  /** The feed's scrollTop at its last scroll event, or where the phone last put it: a scroll event below it is a scroll up. */
  private lastTop = 0;
  /** The first message that arrived while the feed was held. */
  private target: string | undefined;

  /** The phone's list; empty outside demo mode, where the panel shows no phone. */
  protected readonly messages = computed<readonly PhonePayload[]>(() => phoneOf(this.live.snapshot() as PhoneSnapshot | undefined, this.live.store()) ?? []);

  /** The instance's time zone, from the snapshot; the captions name the browser's zone when its offset differs. */
  private readonly instanceZone = computed(() => this.live.snapshot()?.instanceZone ?? '');

  /** True while the New messages button shows. */
  protected readonly unseen = signal(false);

  constructor() {
    effect(() => {
      const list = this.messages();
      const approvals = this.live.store()?.approvals;
      untracked(() => this.noteArrivals(list, approvals));
    });
  }

  ngAfterViewInit(): void {
    const observer = new ResizeObserver(() => {
      if (this.following) {
        this.scrollToBottom();
      }
    });
    observer.observe(this.feed().nativeElement);
    observer.observe(this.content().nativeElement);
    this.destroyRef.onDestroy(() => observer.disconnect());
  }

  /** The caption beside a message: its time, with the browser's zone named when it differs from the instance's. */
  protected timeOf(message: PhonePayload): string {
    return pageTimeBeside(message.createdAt ?? '', this.instanceZone());
  }

  /** Focus reached something in the feed: it scrolls just far enough to keep that element's ring inside it. */
  protected reveal(event: Event): void {
    revealRing(this.feed().nativeElement, event.target);
  }

  /** At the bottom (within 24 px) the feed is at the bottom; away from it, it has left the bottom only if it was scrolled up. */
  protected onScroll(): void {
    const feed = this.feed().nativeElement;
    const up = feed.scrollTop < this.lastTop;
    this.lastTop = feed.scrollTop;
    if (atBottom(feed, BOTTOM_SLACK_PX)) {
      this.following = true;
      this.seenAll();
    } else if (up) {
      this.following = false;
    }
  }

  /** The New messages button: the bottom, with no smooth scroll, and the focus on the first message that arrived meanwhile. */
  protected showNew(): void {
    const target = this.target;
    this.seenAll();
    this.following = true;
    this.scrollToBottom();
    if (target !== undefined) {
      const found = Array.from(this.feed().nativeElement.querySelectorAll<HTMLElement>('[data-key]')).find((element) => element.dataset['key'] === target);
      found?.focus({ preventScroll: true });
    }
  }

  /**
   * The first look records the list; later, a message that arrives is followed at the bottom, and held (the New messages button
   * shows, the feed does not move) when the feed is scrolled up or the list holds a pending approval request.
   */
  private noteArrivals(list: readonly PhonePayload[], approvals: Readonly<Record<string, { state?: string }>> | undefined): void {
    const refs = list.map((one) => one.ref ?? '');
    if (this.seen === undefined) {
      this.seen = new Set(refs);
      return;
    }
    const fresh = newRefs(this.seen, refs);
    for (const ref of fresh) {
      this.seen.add(ref);
    }
    if (fresh.length > 0 && (!this.following || pendingApproval(list, approvals))) {
      this.following = false;
      this.target ??= fresh[0];
      this.unseen.set(true);
    }
  }

  private seenAll(): void {
    this.target = undefined;
    this.unseen.set(false);
  }

  private scrollToBottom(): void {
    const feed = this.feed().nativeElement;
    feed.scrollTop = feed.scrollHeight;
    this.lastTop = feed.scrollTop;
  }
}
