import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';

import { Icon } from '../icon/icon';
import { renderPageText } from '../msg/catalog';
import { CheckRows } from './check-rows';
import { CHAT_TEXTS, digestOpen, NOTICE_TEXTS, type NoticeView } from './chat-view';
import { DecisionStrip } from './decision-strip';
import { GotIt } from './got-it';
import { pageTimeBeside } from './page-time';

/** The last id handed to a card, for the id of its check rows. */
let lastId = 0;

/**
 * A notice card (UX-DR69, FR-1): a tell-now notification, a reminder or an allowance message in the chat, in the conversation's order. It has no title
 * or heading: the message text stands as the catalog gives it, so nothing repeats.
 * - A tell-now card has the attention accent bar and the bell-ring icon in the attention ink, the text, the "Why now:" line, and a
 *   decision strip that holds line 1 and Details only (the "Why now:" line is the decision's first reason). The strip shows the
 *   decision's own cost; a fallback shows Tell now and the Fallback flag with no confidence; with no decision it shows no
 *   confidence, no cost and no Details.
 * - A reminder card has the info accent bar and the bell icon in the info ink, the text, and the caption "Due 14:12 \u00B7 arrived
 *   14:12" (left out when the reminder has no due time). Each time is in the browser's zone and hour format, followed by the
 *   zone's short name when the browser's UTC offset at that time differs from the instance's (UX-DR123).
 * - An allowance card (Story 16.9: the session's message allowance, and the online demo's daily-cap message) has the danger accent bar and the
 *   circle-alert icon of the danger banner in the danger ink, and the text. It has no strip and no caption.
 * - A digest card (Stories 17.10 and 18.4) has the digest card's surface, border and medium radius with its 4px brand-teal accent bar
 *   (the --digest-card-* tokens) and the inbox icon in the info ink, and the digest's text, one piece on each line, with no strip and no caption.
 *   With check rows it adds a button "What I checked ({n})" with aria-expanded and aria-controls, over the check rows (app-check-rows, no
 *   sentence: the text already holds it), inline: it starts open when any row did not pass (digestOpen) and a press toggles it. With no rows
 *   there is no button.
 * - A tell-now card with a decision Ref (Story 18.4) ends with Got it (app-got-it, channel web) until the notice is marked handled, then with
 *   the line "Marked as handled at {time}" (the catalog text, the time in the browser's zone), also after a reload.
 * - A tool call's notice (Story 31.6; kinds approval and result) has the info accent bar and the info icon, and its text keeps its
 *   line breaks when it is a request. It is the plain form of a request that is no longer pending, and of a result: no label, badge
 *   or pending colour, and no button (a pending request is drawn as the approval request card instead).
 * Every text is bound by interpolation, never as markup. The card is not a live region and takes focus only when the New messages
 * button sends it there.
 */
@Component({
  selector: 'app-notice-card',
  imports: [CheckRows, DecisionStrip, GotIt, Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="notice" [class.tell-now]="notice().kind === 'tellnow'" [class.allowance]="notice().kind === 'allowance'" [class.request]="notice().kind === 'approval'" [class.digest]="notice().kind === 'digest'" data-part="notice" [attr.data-key]="notice().key" tabindex="-1">
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
            [traceUrl]="notice().decision?.traceUrl"
          />
        }
        @if (notice().kind === 'digest' && notice().checks.length > 0) {
          <button type="button" class="disclosure" data-part="what-i-checked" [attr.aria-expanded]="open()" [attr.aria-controls]="rowsId" (click)="toggle()">
            {{ whatIChecked() }}
            <app-icon [name]="open() ? 'chevron-up' : 'chevron-down'" [size]="13" />
          </button>
          <div class="rows" [id]="rowsId" [hidden]="!open()">
            <app-check-rows [checks]="notice().checks" />
          </div>
        }
        @if (notice().kind === 'tellnow' && notice().decisionRef) {
          @if (handled(); as line) {
            <p class="handled" data-part="handled">{{ line }}</p>
          } @else {
            <app-got-it [ref]="notice().decisionRef" channel="web" />
          }
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
    .notice.allowance {
      border-inline-start-color: var(--status-banner-danger-accent);
    }
    .notice.digest {
      background: var(--digest-card-background);
      border: var(--digest-card-border);
      border-inline-start: var(--digest-card-accent-bar);
      border-inline-start-style: solid;
      border-radius: var(--digest-card-radius);
    }
    .bell {
      margin-top: var(--space-1);
      color: var(--info-ink);
    }
    .request .text,
    .digest .text {
      white-space: pre-line;
    }
    .tell-now .bell {
      color: var(--attention-ink);
    }
    .allowance .bell {
      color: var(--status-banner-danger-accent);
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
    .caption,
    .handled {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .disclosure {
      display: inline-flex;
      align-items: center;
      align-self: flex-start;
      gap: 3px;
      min-height: var(--space-target-min);
      padding: 0 2px;
      border: 0;
      border-radius: var(--rounded-xs);
      background: none;
      color: var(--action-ink);
      font-family: var(--font-ui);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1.4;
      cursor: pointer;
    }
    .rows[hidden] {
      display: none;
    }
  `,
})
export class NoticeCard {
  readonly notice = input.required<NoticeView>();
  /** The instance's time zone, from the snapshot: the caption's times name the browser's zone when its offset differs. */
  readonly instanceZone = input('');

  protected readonly rowsId = `digest-rows-${(lastId += 1)}`;
  /** The reader's own choice of the disclosure; undefined until a press, so that digestOpen decides the start. */
  private readonly chosen = signal<boolean | undefined>(undefined);

  /** True while the check rows show: the reader's choice, else open when any row did not pass. */
  protected readonly open = computed(() => this.chosen() ?? digestOpen(this.notice().checks));

  /** "What I checked (2)": the disclosure's name, with the count of rows. */
  protected readonly whatIChecked = computed(() => NOTICE_TEXTS.whatIChecked.replace('{n}', () => String(this.notice().checks.length)));

  /** "Marked as handled at 14:12" for a handled tell-now card (the time in the browser's zone); "" while it is not handled. */
  protected readonly handled = computed(() => {
    const at = this.notice().handledAt;
    return at === '' ? '' : renderPageText('handled.marked', { time: pageTimeBeside(at, this.instanceZone()) });
  });

  protected toggle(): void {
    this.chosen.set(!this.open());
  }

  /** The icon of the kind: bell-ring for a tell now, circle-alert for an allowance message, inbox for a digest, info for a tool call's notice, bell for a reminder. */
  protected readonly icon = computed(() => {
    const kind = this.notice().kind;
    if (kind === 'approval' || kind === 'result') {
      return 'info';
    }
    if (kind === 'digest') {
      return 'inbox';
    }
    return kind === 'tellnow' ? 'bell-ring' : kind === 'allowance' ? 'circle-alert' : 'bell';
  });

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
