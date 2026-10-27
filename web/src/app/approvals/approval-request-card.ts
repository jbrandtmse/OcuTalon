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
  input,
  output,
  untracked,
} from '@angular/core';

import { ApiClient } from '../api/api-client';
import { pageTimeBeside, pageWhenBeside } from '../chat/page-time';
import { Icon } from '../icon/icon';
import { EvidencePanel } from '../incidents/evidence-panel';
import { INCIDENT_TEXTS, type PanelView } from '../incidents/incident-view';
import type { ApprovalPayload } from '../live/payloads';
import { renderPageText } from '../msg/catalog';
import { approvalTitle } from '../rail/rail-view';
import { Announcer } from '../shared/announcer';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { InlineNotice } from '../shared/inline-notice';
import { Popovers } from '../shared/popover';
import { AnswerPress } from './answer-press';
import { APPROVAL_TEXTS, approvalView, type ApprovalContext } from './approval-view';

/** The last id handed to a card, for the ids of its label and its notice. */
let lastId = 0;

/** The attributes that mark the answer row (the two buttons, or the status that replaces them) with its part and the request's key. */
const PART = 'data-part';
const KEY = 'data-key';

/**
 * Where focus goes when an update replaces the Approve or Reject button that holds it: the buttons and the status that replaces them
 * share one part and one key, so the shared rule finds the status (tabindex -1) by the key. Focus on Show details is not in the
 * answer part and is never moved.
 */
const ANSWER_RULE: FocusRule = {
  item: `[${PART}="answer"][${KEY}]`,
  keyOf: (item) => item.getAttribute(KEY) ?? '',
};

/**
 * The context the approval view reads, with the page's real time formats, the catalog's renderer and the rail's title of a
 * request: the times are page times beside message text, in the browser's zone and hour format.
 */
export function approvalContext(nowMs: number, instanceZone: string, onlineDemo: boolean, user: string): ApprovalContext {
  return {
    nowMs,
    instanceZone,
    onlineDemo,
    user,
    timeBeside: (iso) => pageTimeBeside(iso, instanceZone),
    whenBeside: (iso, now) => pageWhenBeside(iso, now, instanceZone),
    render: (key, slots) => renderPageText(key, slots),
    title: approvalTitle,
  };
}

/**
 * The approval request card (FR-8, FR-25, UX-DR79 to UX-DR83) inside an incident card, from one `approval` payload alone
 * (approval-view.ts). While the request is pending, top to bottom: the label ("Approval needed"), the action in the imperative,
 * the fixed-targets line, the dry run, one row with Approve (primary) and Reject (secondary) and, on the first card of an incident,
 * Show details at its right end, the expiry, and the evidence panel when Show details is open. Once answered, here or elsewhere,
 * the label reads "Approval request" and the answered status replaces the two buttons in the same row; the fixed-targets line, the
 * expiry and "Nothing has changed yet." go and the dry run stays. A 4px bar on the left follows the state. Every text is bound by
 * interpolation, never as markup.
 *
 * A press sends {action, channel: 'web'} through AnswerPress (answer-press.ts, which the simulated phone's request message uses too
 * with channel 'phone'; the server takes the session from the CSP session). Both buttons go busy together: a spinner, aria-busy and
 * aria-disabled, never `disabled`, and a repeat press sends nothing. With no answer in 10 s both are restored and the notice
 * "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting." is shown and announced; a later answer
 * still shows and clears it. An answered, late or expired reply carries the request's payload, which the card shows (and keeps
 * while the store's own payload is still pending); a late press also shows the page's "Already answered" notice, and the other
 * replies show their notice. A notice is announced.
 *
 * An answer that came from elsewhere (the phone, Telegram) reaches the card as the store's payload going from pending to answered.
 * The card then announces its status once ("Approved from the simulated phone at 14:15"), unless the card has a view of its own
 * (its own press, or one under way) or focus, after the render, is on the card's status or on the simulated phone's answer line
 * of this request: where the answer took focus it is already spoken.
 *
 * The card is a section that the chat's New messages button can focus (tabindex -1). Focus: when an update replaces the focused
 * Approve or Reject, the shared focus rule (shared/focus-rule.ts) puts it on the status line (tabindex -1). The card moves no
 * other focus.
 */
@Component({
  selector: 'app-approval-request-card',
  imports: [EvidencePanel, Icon, InlineNotice],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section [class]="'request bar-' + view().bar" data-part="approval" [attr.data-key]="view().ref" tabindex="-1" [attr.aria-labelledby]="labelId">
      <div class="label" [class.pending]="view().pending" [id]="labelId">{{ view().label }}</div>
      <p class="action">{{ view().action }}</p>
      @if (view().fixedTargets) {
        <p class="fixed">{{ view().fixedTargets }}</p>
      }
      @if (view().dryRun; as dry) {
        <div class="dry">
          <div class="dry-head">
            <span class="dry-label">{{ texts.dryRun }}</span>
            <span class="dry-count">{{ dry.countLine }}</span>
          </div>
          @if (dry.before) {
            <div class="dry-row">
              <span class="dry-key">{{ texts.before }}</span>
              <span class="mono before">{{ dry.before }}</span>
            </div>
          }
          @if (dry.after) {
            <div class="dry-row">
              <span class="dry-key">{{ texts.after }}</span>
              <span class="mono after">{{ dry.after }}</span>
            </div>
          }
          @if (dry.resendLine) {
            <div class="dry-row">
              <span class="dry-key">{{ texts.willResend }}</span>
              <span>{{ dry.resendLine }}</span>
            </div>
          }
          @if (dry.nothingYet) {
            <div class="dry-note">{{ dry.nothingYet }}</div>
          }
        </div>
      }
      <div class="answer-row">
        @if (view().pending) {
          <span class="buttons" data-part="answer" [attr.data-key]="view().ref">
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
        } @else if (view().status; as status) {
          <p [class]="'status tone-' + status.tone" data-part="answer" [attr.data-key]="view().ref" tabindex="-1">
            <app-icon [name]="status.icon" [size]="16" />
            <span>{{ status.text }}</span>
          </p>
        }
        @if (details()) {
          <button
            type="button"
            class="button button-ghost show-details"
            [attr.aria-expanded]="detailsOpen()"
            [attr.aria-controls]="detailsId()"
            (click)="toggleDetails.emit()"
          >
            {{ showDetails }}
            <app-icon [name]="detailsOpen() ? 'chevron-up' : 'chevron-down'" [size]="14" />
          </button>
        }
      </div>
      @if (view().expiry) {
        <p class="expiry">{{ view().expiry }}</p>
      }
      @if (notice()) {
        <app-inline-notice class="under" variant="warning" [id]="noticeId">{{ notice() }}</app-inline-notice>
      }
      @if (details(); as panel) {
        <div class="panel" [id]="detailsId()">
          @if (detailsOpen()) {
            <app-evidence-panel [panel]="panel" />
          }
        </div>
      }
    </section>
  `,
  styles: `
    :host {
      display: block;
    }
    .request {
      display: flex;
      flex-direction: column;
      margin-top: var(--space-1);
      padding: var(--space-1) var(--space-3) var(--space-1) var(--space-4);
      background: var(--approval-request-card-background);
      border: var(--approval-request-card-border);
      border-inline-start: var(--approval-request-card-accent-bar-pending);
      border-inline-start-style: solid;
      border-radius: var(--approval-request-card-radius);
      color: var(--ink);
    }
    .request.bar-approved {
      border-inline-start: var(--approval-request-card-accent-bar-approved);
      border-inline-start-style: solid;
    }
    .request.bar-closed {
      border-inline-start: var(--approval-request-card-accent-bar-closed);
      border-inline-start-style: solid;
    }
    p {
      margin: 0;
      max-width: var(--chat-panel-text-max);
      overflow-wrap: anywhere;
    }
    .label {
      color: var(--ink-muted);
      font-family: var(--approval-request-card-label-font-family), var(--font-ui);
      font-size: var(--approval-request-card-label-font-size);
      font-weight: var(--approval-request-card-label-font-weight);
      line-height: var(--approval-request-card-label-line-height);
      letter-spacing: var(--approval-request-card-label-letter-spacing);
      text-transform: uppercase;
    }
    .label.pending {
      color: var(--attention-ink);
    }
    .action {
      margin-top: var(--space-1);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-line-height);
    }
    .fixed {
      margin-top: var(--space-1);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .dry {
      margin-top: var(--space-1);
      padding: var(--space-1) var(--space-3);
      background: var(--dry-run-block-background);
      border-radius: var(--dry-run-block-radius);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .dry-head {
      display: flex;
      align-items: baseline;
      gap: var(--space-2);
    }
    .dry-label {
      color: var(--ink-muted);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-label-line-height);
      letter-spacing: var(--type-label-letter-spacing);
      text-transform: uppercase;
    }
    .dry-count {
      font-weight: var(--type-body-strong-font-weight);
    }
    .dry-row {
      display: grid;
      grid-template-columns: 84px 1fr;
      gap: var(--space-2);
      align-items: baseline;
    }
    .dry-key {
      color: var(--ink-muted);
      font-weight: var(--type-body-strong-font-weight);
    }
    .mono {
      font-family: var(--font-mono);
      font-size: var(--dry-run-block-value-typography-font-size);
      font-weight: var(--dry-run-block-value-typography-font-weight);
      line-height: var(--dry-run-block-value-typography-line-height);
      overflow-wrap: anywhere;
    }
    .before {
      color: var(--dry-run-block-before);
    }
    .after {
      color: var(--dry-run-block-after);
    }
    .dry-note {
      color: var(--ink-muted);
    }
    .answer-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
      margin-top: var(--space-1);
    }
    .buttons {
      display: inline-flex;
      gap: var(--space-2);
    }
    .show-details {
      margin-inline-start: auto;
      gap: var(--space-1);
      padding: 0 var(--space-2);
    }
    .status {
      display: inline-flex;
      align-items: center;
      gap: var(--space-2);
      font-size: var(--answered-status-typography-font-size);
      font-weight: var(--answered-status-typography-font-weight);
      line-height: var(--answered-status-typography-line-height);
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
    .expiry {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
      line-height: var(--type-caption-line-height);
    }
    .under {
      margin-top: var(--space-1);
    }
    .panel:empty {
      display: none;
    }
  `,
})
export class ApprovalRequestCard {
  /** The `approval` payload of the store, the full view of the request. */
  readonly approval = input.required<ApprovalPayload>();
  /** The page's readings: the clock, the user, the time formats, the catalog and the title (approvalContext). */
  readonly ctx = input.required<ApprovalContext>();
  /** The incident's evidence panel; set only on the first card of the incident, which then has Show details at the row's right end. */
  readonly details = input<PanelView | undefined>(undefined);
  /** The id of the element that holds the panel, which Show details controls. */
  readonly detailsId = input('');
  /** True while Show details is open. */
  readonly detailsOpen = input(false);
  /** Emits when Show details is pressed. */
  readonly toggleDetails = output<void>();

  protected readonly texts = APPROVAL_TEXTS;
  protected readonly showDetails = INCIDENT_TEXTS.showDetails;
  private readonly id = ++lastId;
  protected readonly labelId = `approval-label-${this.id}`;
  protected readonly noticeId = `approval-notice-${this.id}`;

  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly popovers = inject(Popovers);
  private readonly injector = inject(Injector);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly destroyRef = inject(DestroyRef);

  /** The press of Approve and Reject, channel web. */
  private readonly answer = new AnswerPress({
    answer: (ref, action, channel) => this.api.answerApproval(ref, action, channel),
    channel: 'web',
    context: () => this.ctx(),
    announcer: this.announcer,
    destroyRef: this.destroyRef,
  });
  /** What the card shows: the answer's request while the store's own is still pending, else the store's. */
  private readonly shown = computed(() => {
    const answered = this.answer.local();
    const stored = this.approval();
    return answered !== undefined && stored.state === 'pending' ? answered : stored;
  });
  protected readonly view = computed(() => approvalView(this.shown(), this.ctx()));

  /** True while a press is out: both buttons are busy. */
  protected readonly busy = this.answer.busy;
  /** The notice under the row: the last reply's, else the busy notice while it is raised. */
  protected readonly notice = this.answer.notice;

  /** Whether the store's payload was pending as of the last look; undefined before the first look. */
  private wasPending: boolean | undefined;

  constructor() {
    effect(() => {
      this.shown();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, ANSWER_RULE));
    });
    effect(() => {
      const pending = this.approval().state === 'pending';
      untracked(() => this.noteStore(pending));
    });
  }

  /** A press of Approve or Reject: one call for both buttons; a press while a call is out is ignored. */
  protected press(action: 'approve' | 'reject'): void {
    this.answer.press(this.view().ref, action);
  }

  /**
   * The store's payload went from pending to answered with no view of the card's own: the answer came from elsewhere. After the
   * render and once the hosts' focus rules have restored a lost focus, the status is announced once, unless focus is on the card's status
   * or on the phone's answer line of this request.
   */
  private noteStore(pending: boolean): void {
    const wasPending = this.wasPending;
    this.wasPending = pending;
    if (wasPending !== true || pending || this.answer.local() !== undefined || this.answer.busy()) {
      return;
    }
    afterNextRender(
      () => {
        // The other hosts' focus rules restore a lost focus in this same render pass; the decision waits until they have.
        queueMicrotask(() => {
          const status = this.view().status;
          if (status === undefined || this.focusOnAnswer(this.view().ref)) {
            return;
          }
          this.announcer.announce(status.text);
        });
      },
      { injector: this.injector },
    );
  }

  /** True when focus is on the card's answer line of the request, or on the simulated phone's answer line of it. */
  private focusOnAnswer(ref: string): boolean {
    const active = document.activeElement;
    if (!(active instanceof Element)) {
      return false;
    }
    const own = active.closest(`[${PART}="answer"][${KEY}]`);
    if (own !== null && this.host.nativeElement.contains(own) && own.getAttribute(KEY) === ref) {
      return true;
    }
    return active.closest(`app-simulated-phone [${PART}="answer"][data-approval]`)?.getAttribute('data-approval') === ref;
  }
}
