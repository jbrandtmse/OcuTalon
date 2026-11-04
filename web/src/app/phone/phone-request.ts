import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, Injector, computed, effect, inject, input, untracked } from '@angular/core';

import { ApiClient } from '../api/api-client';
import { AnswerPress } from '../approvals/answer-press';
import { APPROVAL_TEXTS, approvalView, type ApprovalContext } from '../approvals/approval-view';
import { messageTime } from '../chat/page-time';
import { Icon } from '../icon/icon';
import type { ApprovalPayload, PhonePayload } from '../live/payloads';
import { renderMessageText } from '../msg/catalog';
import { approvalTitle } from '../rail/rail-view';
import { Announcer } from '../shared/announcer';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { InlineNotice } from '../shared/inline-notice';
import { Popovers } from '../shared/popover';
import { requestView } from './phone-view';

/** The last id handed to a request message, for the id of its notice. */
let lastId = 0;

/** The attributes that mark the answer part (the two buttons, or the line that replaces them) with its part and the message's key. */
const PART = 'data-part';
const KEY = 'data-key';

/**
 * Where focus goes when an update replaces the Approve or Reject button that holds it: the buttons and the answer line that
 * replaces them share one part and one key, so the shared rule finds the line (tabindex -1) by the key. The shape of the request
 * card's ANSWER_RULE.
 */
export const PHONE_ANSWER_RULE: FocusRule = {
  item: `[${PART}="answer"][${KEY}]`,
  keyOf: (item) => item.getAttribute(KEY) ?? '',
};

/**
 * The context the approval view reads on the phone: texts in message form (the catalog's `text` forms, renderMessageText) and times
 * as message times, in the instance's zone with " ET" on the online demo (messageTime), never the page's. The title of a request is
 * the rail's.
 */
export function messageContext(nowMs: number, instanceZone: string, onlineDemo: boolean, user: string): ApprovalContext {
  return {
    nowMs,
    instanceZone,
    onlineDemo,
    user,
    timeBeside: (iso) => messageTime(iso, nowMs, instanceZone, onlineDemo),
    whenBeside: (iso, now) => messageTime(iso, now, instanceZone, onlineDemo),
    render: (key, slots) => renderMessageText(key, slots),
    title: approvalTitle,
  };
}

/**
 * One request message of the simulated phone (Story 6.3; FR-8, AD-32, UX-DR132), drawn inside the phone's notification: the
 * server's text in blocks (the block that holds the dry run's example is an inset on the surface colour, with the example's before
 * and after values in mono-sm, in the danger and the success ink), then Approve (primary, left) and Reject (secondary) side by side,
 * each half the row and 40 px tall, named with the object ("Approve: repair and resend 50 orders"), and the caption time. Every text
 * is bound by interpolation, never as markup.
 *
 * The buttons are there only while the message names a request and has no answer, neither the server's (its edit of the message
 * when the request was answered) nor the phone's own press (phone-view.ts requestView). A press goes through AnswerPress with
 * channel 'phone', the same press as the chat's request card: both buttons go busy together (a spinner, aria-busy and aria-disabled,
 * never `disabled`), a repeat press sends nothing, and after 10 s with no answer both are restored with the busy notice. The answer
 * line, in message form ("Approved from the simulated phone at 14:15."), replaces the buttons in the same place; when a button had
 * focus, the shared focus rule (shared/focus-rule.ts) puts it on the line (tabindex -1).
 *
 * The phone is no live region. It announces only the notices of its own press (busy, late press, a refusal or a failure), once each,
 * through the page's Announcer; an answer from elsewhere is announced by the chat's request card. While a press is out the buttons'
 * part carries the request's Ref too (data-approval, as the answer line does), so that the card reads a focus on them as the
 * answer's own and does not announce an answer that arrives before the reply.
 */
@Component({
  selector: 'app-phone-request',
  imports: [Icon, InlineNotice],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="blocks">
      @for (block of view().blocks; track $index) {
        @if (block.inset) {
          <p class="text inset">
            @for (part of block.parts; track $index) {
              @if (part.kind === 'plain') {
                <span>{{ part.text }}</span>
              } @else {
                <span [class]="'mono ' + part.kind">{{ part.text }}</span>
              }
            }
          </p>
        } @else {
          <p class="text">{{ block.text }}</p>
        }
      }
    </div>
    @if (view().buttons) {
      <span class="buttons" data-part="answer" [attr.data-key]="message().ref" [attr.data-approval]="busy() ? message().approvalRef : null">
        <button
          type="button"
          class="button button-primary"
          [attr.aria-label]="view().approveName"
          [attr.aria-busy]="busy() ? 'true' : null"
          [attr.aria-disabled]="busy() ? 'true' : null"
          [attr.aria-describedby]="notice() ? noticeId : null"
          (click)="press('approve')"
        >
          @if (busy()) {
            <app-icon class="spinner" name="loader-circle" [size]="16" />
          }
          {{ texts.approve }}
        </button>
        <button
          type="button"
          class="button button-secondary"
          [attr.aria-label]="view().rejectName"
          [attr.aria-busy]="busy() ? 'true' : null"
          [attr.aria-disabled]="busy() ? 'true' : null"
          [attr.aria-describedby]="notice() ? noticeId : null"
          (click)="press('reject')"
        >
          @if (busy()) {
            <app-icon class="spinner" name="loader-circle" [size]="16" />
          }
          {{ texts.reject }}
        </button>
      </span>
    } @else if (view().answer; as line) {
      <p [class]="'answered tone-' + line.tone" data-part="answer" [attr.data-key]="message().ref" [attr.data-approval]="message().approvalRef" tabindex="-1">
        @if (line.icon; as icon) {
          <app-icon [name]="icon" [size]="16" />
        }
        <span>{{ line.text }}</span>
      </p>
    }
    @if (notice()) {
      <app-inline-notice variant="warning" [id]="noticeId">{{ notice() }}</app-inline-notice>
    }
    <span class="time">{{ caption() }}</span>
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .blocks {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
    }
    .text {
      margin: 0;
      white-space: pre-line;
      overflow-wrap: anywhere;
    }
    .inset {
      padding: var(--space-2) var(--space-3);
      background: var(--surface);
      border-radius: var(--dry-run-block-radius);
    }
    .mono {
      font-family: var(--type-mono-sm-font-family), var(--font-mono);
      font-size: var(--type-mono-sm-font-size);
      font-weight: var(--type-mono-sm-font-weight);
      line-height: var(--type-mono-sm-line-height);
    }
    .before {
      color: var(--danger-ink);
    }
    .after {
      color: var(--success-ink);
    }
    .buttons {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: var(--space-2);
    }
    .buttons .button {
      min-height: var(--phone-notification-button-height);
      min-width: 0;
      padding: 0 var(--space-2);
    }
    .answered {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      margin: 0;
      color: var(--ink);
      font-weight: var(--answered-status-typography-font-weight);
    }
    .tone-approved {
      color: var(--answered-status-approved);
    }
    .tone-rejected {
      color: var(--answered-status-rejected);
    }
    .tone-expired {
      color: var(--answered-status-expired);
    }
    .time {
      align-self: flex-end;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
  `,
})
export class PhoneRequest {
  /** The request message: its text, its Ref, the request it asks for and the answer line the server put on it. */
  readonly message = input.required<PhonePayload>();
  /** The store's `approval` payload for the message's request; undefined when the store has none. */
  readonly approval = input<ApprovalPayload | undefined>(undefined);
  /** The caption: the message's time, as the phone writes it. */
  readonly caption = input('');
  /** The instance's time zone, from the snapshot. */
  readonly instanceZone = input('');
  /** True on the online demo. */
  readonly onlineDemo = input(false);
  /** The signed-in user of the snapshot. */
  readonly user = input('');

  protected readonly texts = APPROVAL_TEXTS;
  protected readonly noticeId = `phone-notice-${++lastId}`;

  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly popovers = inject(Popovers);
  private readonly injector = inject(Injector);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly destroyRef = inject(DestroyRef);

  /** The press of Approve and Reject, channel phone. */
  private readonly answer = new AnswerPress({
    answer: (ref, action, channel) => this.api.answerApproval(ref, action, channel),
    channel: 'phone',
    context: () => this.context(),
    announcer: this.announcer,
    destroyRef: this.destroyRef,
  });

  protected readonly view = computed(() =>
    requestView(this.message(), this.approval(), this.answer.local(), { viewOf: (approval) => approvalView(approval, this.context()) }),
  );
  /** True while a press is out: both buttons are busy. */
  protected readonly busy = this.answer.busy;
  /** The notice under the buttons: the last reply's, else the busy notice while it is raised. */
  protected readonly notice = this.answer.notice;

  constructor() {
    effect(() => {
      this.view();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, PHONE_ANSWER_RULE));
    });
  }

  /** A press of Approve or Reject: one call for both buttons; a press while a call is out is ignored. */
  protected press(action: 'approve' | 'reject'): void {
    this.answer.press(this.approvalRef(), action);
  }

  private approvalRef(): string {
    return this.message().approvalRef ?? '';
  }

  /** The context of the phone's texts and times, at the moment it is read. */
  private context(): ApprovalContext {
    return messageContext(Date.now(), this.instanceZone(), this.onlineDemo(), this.user());
  }
}
