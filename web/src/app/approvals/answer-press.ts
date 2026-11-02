import { HttpErrorResponse, type HttpResponse } from '@angular/common/http';
import { type DestroyRef, computed, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import type { Observable } from 'rxjs';

import type { AnswerBody, AnswerChannel } from '../api/api-types';
import type { ApprovalPayload } from '../live/payloads';
import type { Announcer } from '../shared/announcer';
import { BusyState } from '../shared/busy-state';
import { APPROVAL_TEXTS, answerOutcomeOf, latePressText, type AnswerOutcome, type ApprovalContext } from './approval-view';

/** What an AnswerPress needs from its host. */
export interface AnswerPressOptions {
  /** The call: the answer endpoint, with the channel of the press (ApiClient.answerApproval). */
  answer: (ref: string, action: 'approve' | 'reject', channel: AnswerChannel) => Observable<HttpResponse<AnswerBody>>;
  /** The channel the press answers from: 'web' for the chat's request card, 'phone' for the simulated phone's message. */
  channel: AnswerChannel;
  /** The context the late press's text is read with (the card's page times, or the phone's message times). */
  context: () => ApprovalContext;
  /** The page's one announcer, for the notices. */
  announcer: Announcer;
  /** The host's lifetime: the press is disposed with it and an answer that arrives after it is dropped. */
  destroyRef: DestroyRef;
}

/**
 * The press of Approve or Reject, shared by the chat's approval request card and the simulated phone's request message (Stories
 * 6.2 and 6.3). One class, so the two cannot differ:
 *
 * - Both buttons go busy together on one BusyState (`busy`: a spinner, aria-busy and aria-disabled, never `disabled`), and a repeat
 *   press while a call is out sends nothing. With no answer in 10 s both are restored and the busy notice is shown and announced;
 *   a later answer still shows and clears it.
 * - A press sends {action, channel} for the given request (the server takes the session from the CSP session).
 * - The reply is read by answerOutcomeOf. A done, late or expired reply carries the request's payload, which becomes `local`: the
 *   view the host shows while the store's own payload is still pending. The notice of a reply is `notice` (a late press reads
 *   latePressText, a missing request the "no longer available" text, a refusal or a failure the reply's own message, no connection
 *   the busy notice), and each notice is announced once. A new press clears it.
 */
export class AnswerPress {
  /** True while a press is out: both buttons are busy. */
  readonly busy = signal(false);
  /** The request as a reply showed it, until the host drops it; undefined before any such reply. */
  readonly local = signal<ApprovalPayload | undefined>(undefined);
  /** The notice under the buttons: the last reply's, else the busy notice while it is raised, else "". */
  readonly notice = computed(() => (this.replyNotice() !== '' ? this.replyNotice() : this.timedOut() ? APPROVAL_TEXTS.busyNotice : ''));

  /** True after 10 s with no answer, until an answer comes or the next press. */
  private readonly timedOut = signal(false);
  /** The notice of the last reply, "" for none. */
  private readonly replyNotice = signal('');
  private readonly options: AnswerPressOptions;
  private readonly state: BusyState;

  constructor(options: AnswerPressOptions) {
    this.options = options;
    this.state = new BusyState({
      setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
      clearTimeout: (handle) => globalThis.clearTimeout(handle as number),
      onChange: (view) => {
        this.busy.set(view.busy);
        this.timedOut.set(view.notice);
      },
      onNotice: () => options.announcer.announce(APPROVAL_TEXTS.busyNotice),
    });
    options.destroyRef.onDestroy(() => this.state.dispose());
  }

  /** A press of Approve or Reject for the request: one call for both buttons; a press while a call is out is ignored. */
  press(ref: string, action: 'approve' | 'reject'): void {
    if (!this.state.press()) {
      return;
    }
    this.replyNotice.set('');
    const call = this.state.call;
    this.options
      .answer(ref, action, this.options.channel)
      .pipe(takeUntilDestroyed(this.options.destroyRef))
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
        return (approval === undefined ? '' : latePressText(approval, this.options.context())) || outcome.message;
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
      this.options.announcer.announce(text);
    }
  }
}
