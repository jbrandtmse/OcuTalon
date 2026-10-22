import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

import { Icon } from '../icon/icon';
import { CHAT_TEXTS, type TurnView } from './chat-view';
import { pageTime } from './page-time';

/**
 * The user's message (UX-DR59, UX-DR123): a right-aligned bubble on the sunken surface, at most 80% of the list's width and
 * with its text lines capped at chat-text-max (UX-DR58), with the text's line breaks kept. The line under it holds the caption ("via Telegram" or "From the demo guide") and the time,
 * in the browser's zone and hour format. A message whose post failed also says "Not sent" and offers Retry sending, which
 * posts the same message again. The element takes focus only when the New messages button sends it there.
 */
@Component({
  selector: 'app-user-message',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="message" data-part="user" [attr.data-key]="turn().key" tabindex="-1">
      <div class="bubble">{{ turn().text }}</div>
      <div class="line">
        <span class="when">{{ when() }}</span>
        @if (turn().send === 'failed') {
          <span class="failed">
            <app-icon name="circle-alert" />
            {{ texts.notSent }}
          </span>
          <button type="button" class="button button-secondary retry" (click)="retry.emit()">{{ texts.retrySending }}</button>
        }
      </div>
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .message {
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: var(--space-1);
    }
    .bubble {
      max-width: min(80%, calc(var(--chat-panel-text-max) + 2 * var(--space-3)));
      padding: var(--space-2) var(--space-3);
      background: var(--chat-message-user-background);
      color: var(--chat-message-user-foreground);
      border-radius: var(--chat-message-user-radius);
      font-size: var(--chat-message-user-typography-font-size);
      font-weight: var(--chat-message-user-typography-font-weight);
      line-height: var(--chat-message-user-typography-line-height);
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    .line {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: flex-end;
      gap: var(--space-2);
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .failed {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      color: var(--danger-ink);
    }
    .retry {
      min-height: var(--space-target-min);
      font-size: var(--type-caption-font-size);
    }
  `,
})
export class UserMessage {
  readonly turn = input.required<TurnView>();
  readonly retry = output<void>();
  protected readonly texts = CHAT_TEXTS;

  /** The caption, then the time, joined by the separator: the line under the bubble. */
  protected readonly when = computed(() => {
    const { caption, time } = this.turn();
    const clock = pageTime(time);
    return caption === '' ? clock : clock === '' ? caption : caption + CHAT_TEXTS.separator + clock;
  });
}
