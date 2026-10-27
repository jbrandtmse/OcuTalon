import { HttpErrorResponse, type HttpResponse } from '@angular/common/http';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  Injector,
  computed,
  effect,
  inject,
  input,
  output,
  signal,
  untracked,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import type { AnswerBody } from '../api/api-types';
import { ApiClient } from '../api/api-client';
import { pageTimeBeside, pageWhenBeside } from '../chat/page-time';
import { Icon } from '../icon/icon';
import { EvidencePanel } from '../incidents/evidence-panel';
import { INCIDENT_TEXTS, type PanelView } from '../incidents/incident-view';
import type { ApprovalPayload } from '../live/payloads';
import { renderPageText } from '../msg/catalog';
import { approvalTitle } from '../rail/rail-view';
import { Announcer } from '../shared/announcer';
import { BusyState } from '../shared/busy-state';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { InlineNotice } from '../shared/inline-notice';
import { Popovers } from '../shared/popover';
import { APPROVAL_TEXTS, answerOutcomeOf, approvalView, latePressText, type ApprovalContext, type AnswerOutcome } from './approval-view';

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
 * A press sends {action, channel: 'web'} (the server takes the session from the CSP session). Both buttons go busy together on
 * one BusyState: a spinner, aria-busy and aria-disabled, never `disabled`, and a repeat press sends nothing. With no answer in
 * 10 s both are restored and the notice "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting."
 * is shown and announced; a later answer still shows and clears it. The reply is read by answerOutcomeOf: an answered, late or
 * expired reply carries the request's payload, which the card shows (and keeps while the store's own payload is still pending), a
 * late press also shows the page's "Already answered" notice, and the other replies show their notice. A notice is announced.
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

  /** The request as an answer showed it: it wins while the store's payload is still pending. */
  private readonly local = signal<ApprovalPayload | undefined>(undefined);
  /** What the card shows: the answer's request while the store's own is still pending, else the store's. */
  private readonly shown = computed(() => {
    const answered = this.local();
    const stored = this.approval();
    return answered !== undefined && stored.state === 'pending' ? answered : stored;
  });
  protected readonly view = computed(() => approvalView(this.shown(), this.ctx()));

  /** True while a press is out: both buttons are busy. */
  protected readonly busy = signal(false);
  /** True after 10 s with no answer, until an answer comes or the next press. */
  private readonly timedOut = signal(false);
  /** The notice of the last reply, "" for none. */
  private readonly replyNotice = signal('');
  /** The notice under the row: the last reply's, else the busy notice while it is raised. */
  protected readonly notice = computed(() => (this.replyNotice() !== '' ? this.replyNotice() : this.timedOut() ? APPROVAL_TEXTS.busyNotice : ''));

  private readonly state = new BusyState({
    setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
    clearTimeout: (handle) => globalThis.clearTimeout(handle as number),
    onChange: (view) => {
      this.busy.set(view.busy);
      this.timedOut.set(view.notice);
    },
    onNotice: () => this.announcer.announce(APPROVAL_TEXTS.busyNotice),
  });

  constructor() {
    effect(() => {
      this.shown();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, ANSWER_RULE));
    });
    this.destroyRef.onDestroy(() => this.state.dispose());
  }

  /** A press of Approve or Reject: one call for both buttons; a press while a call is out is ignored. */
  protected press(action: 'approve' | 'reject'): void {
    if (!this.state.press()) {
      return;
    }
    this.replyNotice.set('');
    const call = this.state.call;
    this.api
      .answerApproval(this.view().ref, action)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (response: HttpResponse<AnswerBody>) => this.replied(call, response.status, response.body),
        error: (error: unknown) =>
          error instanceof HttpErrorResponse ? this.replied(call, error.status, error.error) : this.replied(call, 0, undefined),
      });
  }

  /** The reply to the call: it ends the busy state, early or late, and shows what the reply says. */
  private replied(call: number, status: number, body: unknown): void {
    this.state.answered(call);
    const outcome = answerOutcomeOf(status, body);
    const approval = 'approval' in outcome ? outcome.approval : undefined;
    if (approval !== undefined) {
      this.local.set(approval);
    }
    this.notify(this.noticeOf(outcome, approval));
  }

  /** The notice that a reply shows, "" for none. */
  private noticeOf(outcome: AnswerOutcome, approval: ApprovalPayload | undefined): string {
    switch (outcome.kind) {
      case 'already':
        return (approval === undefined ? '' : latePressText(approval, this.ctx())) || outcome.message;
      case 'gone':
        return APPROVAL_TEXTS.gone;
      case 'notAllowed':
      case 'failed':
        return outcome.message;
      case 'unreachable':
        return APPROVAL_TEXTS.busyNotice;
      default:
        return '';
    }
  }

  /** Shows the notice and announces it, once; "" clears it. */
  private notify(text: string): void {
    this.replyNotice.set(text);
    if (text !== '') {
      this.announcer.announce(text);
    }
  }
}
