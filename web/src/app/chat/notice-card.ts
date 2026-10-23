import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { Icon } from '../icon/icon';
import { CHAT_TEXTS, NOTICE_TEXTS, type NoticeView } from './chat-view';
import { DecisionStrip } from './decision-strip';
import { pageTimeBeside } from './page-time';

/**
 * A notice card (UX-DR69, FR-1): a tell-now notification or a reminder in the chat, in the conversation's order. It has no title
 * or heading: the message text stands as the catalog gives it, so nothing repeats.
 * - A tell-now card has the attention accent bar and the bell-ring icon in the attention ink, the text, the "Why now:" line, and a
 *   decision strip that holds line 1 and Details only (the "Why now:" line is the decision's first reason). The strip shows the
 *   decision's own cost; a fallback shows Tell now and the Fallback flag with no confidence; with no decision it shows no
 *   confidence, no cost and no Details.
 * - A reminder card has the info accent bar and the bell icon in the info ink, the text, and the caption "Due 14:12 \u00B7 arrived
 *   14:12" (left out when the reminder has no due time). Each time is in the browser's zone and hour format, followed by the
 *   zone's short name when the browser's UTC offset at that time differs from the instance's (UX-DR123).
 * Every text is bound by interpolation, never as markup. The card is not a live region and takes focus only when the New messages
 * button sends it there.
 */
@Component({
  selector: 'app-notice-card',
  imports: [DecisionStrip, Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="notice" [class.tell-now]="notice().kind === 'tellnow'" data-part="notice" [attr.data-key]="notice().key" tabindex="-1">
      <app-icon class="bell" [name]="icon()" [size]="16" />
      <div class="body">
        <p class="text">{{ notice().text }}</p>
        @if (notice().whyNow) {
          <p class="why">{{ notice().whyNow }}</p>
        }
        @if (caption(); as line) {
          <p class="caption">{{ line }}</p>
        }
        @if (notice().strip) {
          <app-decision-strip
            [decision]="notice().decision"
            [cost]="notice().decision?.costUSD"
            [fallbackReason]="notice().fallbackReason"
            [reasons]="false"
          />
        }
      </div>
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .notice {
      display: flex;
      align-items: flex-start;
      gap: var(--space-2);
      padding: var(--space-3) var(--space-4) var(--space-3) var(--space-5);
      background: var(--notice-card-background);
      border: var(--notice-card-border);
      border-inline-start: var(--notice-card-accent-bar);
      border-inline-start-style: solid;
      border-radius: var(--notice-card-radius);
      color: var(--ink);
    }
    .notice.tell-now {
      border-inline-start: var(--notice-card-accent-bar-tell-now);
      border-inline-start-style: solid;
    }
    .bell {
      margin-top: var(--space-1);
      color: var(--info-ink);
    }
    .tell-now .bell {
      color: var(--attention-ink);
    }
    .body {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      min-width: 0;
      max-width: var(--chat-panel-text-max);
    }
    p {
      margin: 0;
      overflow-wrap: anywhere;
    }
    .text,
    .why {
      font-size: var(--type-body-chat-font-size);
      font-weight: var(--type-body-chat-font-weight);
      line-height: var(--type-body-chat-line-height);
    }
    .caption {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
  `,
})
export class NoticeCard {
  readonly notice = input.required<NoticeView>();
  /** The instance's time zone, from the snapshot: the caption's times name the browser's zone when its offset differs. */
  readonly instanceZone = input('');

  /** The icon of the kind: bell-ring for a tell now, bell for a reminder. */
  protected readonly icon = computed(() => (this.notice().kind === 'tellnow' ? 'bell-ring' : 'bell'));

  /** "Due 14:12 \u00B7 arrived 14:12" for a reminder with a due time; "" for any other card. */
  protected readonly caption = computed(() => {
    const notice = this.notice();
    if (notice.kind !== 'reminder' || notice.dueAt === '') {
      return '';
    }
    const zone = this.instanceZone();
    const parts = [NOTICE_TEXTS.due.replace('{time}', () => pageTimeBeside(notice.dueAt, zone))];
    const arrived = pageTimeBeside(notice.time, zone);
    if (arrived !== '') {
      parts.push(NOTICE_TEXTS.arrived.replace('{time}', () => arrived));
    }
    return parts.join(CHAT_TEXTS.separator);
  });
}
