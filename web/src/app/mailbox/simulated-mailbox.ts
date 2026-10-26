import { ChangeDetectionStrategy, Component, ElementRef, Injector, afterNextRender, computed, effect, inject, signal, untracked } from '@angular/core';
import { type Observable, of, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { fallbackSentence } from '../chat/decision-strip';
import { outcomeOf, reasonLines } from '../chat/decision-view';
import { CHAT_TEXTS } from '../chat/chat-view';
import { FallbackFlag } from '../chat/fallback-flag';
import { type Outcome, OutcomeChip } from '../chat/outcome-chip';
import { pageTimeBeside } from '../chat/page-time';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import type { DecisionPayload } from '../live/payloads';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { readText, writeFlag } from '../shared/stored-flag';
import { TraceLink } from '../shared/trace-link';
import {
  arrivedText,
  chipName,
  decidedText,
  decisionOf,
  fieldErrors,
  type MailboxEntry,
  MAILBOX_TEXTS,
  type MailboxSnapshot,
  mailOf,
  OPENED_KEY,
  openedRefs,
  SAMPLES,
  senderName,
  withOpened,
} from './mailbox-view';

/** The most reason lines the open email shows. */
const REASON_LINES = 10;

/** The label of each outcome, as its chip shows it. */
const LABELS: Readonly<Record<Outcome, string>> = {
  ignore: CHAT_TEXTS.chipIgnore,
  digest: CHAT_TEXTS.chipDigest,
  'tell-now': CHAT_TEXTS.chipTellNow,
  act: CHAT_TEXTS.chipAct,
};

/** One row of the list, with what the template shows of it. */
interface RowView {
  mail: MailboxEntry;
  ref: string;
  name: string;
  subject: string;
  time: string;
  unread: boolean;
  incoming: boolean;
  decision: DecisionPayload | undefined;
  chip: Outcome | undefined;
}

/** The field errors of the form, by field. */
interface FormErrors {
  subject?: string;
  body?: string;
}

/** The message of an error answer `{"error":{"code","message"}}`, or empty for any other failure (the server button's notice covers an unreachable server). */
function messageOf(error: unknown): string {
  const message = (error as { error?: { error?: { message?: unknown } } } | null)?.error?.error?.message;
  return typeof message === 'string' ? message : '';
}

/**
 * The simulated mailbox (Story 4.6; FR-13, UX-DR132): a real channel that stands in for the user's own inbox, on the device panel in
 * demo mode. It always shows the three sample email chips with their caption and the secondary "Simulate an incoming email"; below
 * them it shows one of three views:
 * - the list: the emails of the session, newest first. A row is a button with the sender's name, the subject, the time, the unread dot
 *   with the visually hidden word "Unread" (until the email is opened in this browser), and for an incoming email "Deciding\u2026" and then
 *   its outcome chip (Tell now on a fallback). Without emails it says so;
 * - the form (in place of the list): From (prefilled, editable), Subject and Body with visible labels, Send and Back. An empty Subject or
 *   Body shows its field error, marks the field, makes no request and moves focus to the first field in error. An error answer shows its
 *   message under Send and marks no field;
 * - the open email (in place of the list): Back, the subject as a heading that takes focus, the full From and the time, the body, and
 *   once decided the decision as the chat strip shows it: the chip, the Fallback flag, the reasons and the trace link.
 *
 * The page decides nothing (AD-12): the list is mailbox-view.ts's mailOf and the decision of an email is joined by its itemId. Everything
 * an email carries is untrusted (AD-13) and is bound as text; the body keeps its line breaks through white-space, never HTML.
 *
 * The component speaks only through the Announcer and moves focus only for the user's action: a chip press keeps focus on the chip, and
 * once its row is in the list it is announced; a decision that lands after the page loaded is announced once (the snapshot's own
 * decisions, at load or reload, are silent); a send moves focus to the new row; opening an email focuses its heading, Back from it
 * focuses its row and Back from the form focuses the Simulate button. What was opened is kept per browser (OPENED_KEY).
 */
@Component({
  selector: 'app-simulated-mailbox',
  imports: [FallbackFlag, Icon, OutcomeChip, ServerButton, TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="chips">
      @for (sample of samples; track sample.name) {
        <app-server-button variant="chip" [label]="nameOf(sample.label)" [action]="samplePress(sample.name)">
          <app-icon name="mail" [size]="16" />
          {{ sample.label }}
        </app-server-button>
      }
    </div>
    <p class="caption">{{ texts.caption }}</p>
    @if (chipError() !== '') {
      <p class="field-error" id="mailbox-chip-error"><app-icon name="circle-alert" [size]="16" />{{ chipError() }}</p>
    }
    <button type="button" class="button button-secondary simulate" (click)="openForm()">{{ texts.simulate }}</button>

    @switch (view()) {
      @case ('form') {
        <div class="form">
          <div class="field">
            <label for="mailbox-from">{{ texts.labelFrom }}</label>
            <input id="mailbox-from" type="text" class="input" maxlength="1000" [value]="from()" (input)="from.set(value($event))" />
          </div>
          <div class="field">
            <label for="mailbox-subject">{{ texts.labelSubject }}</label>
            <input
              id="mailbox-subject"
              type="text"
              class="input"
              maxlength="1000"
              [class.invalid]="errors().subject"
              [attr.aria-invalid]="errors().subject ? 'true' : null"
              [attr.aria-describedby]="errors().subject ? 'mailbox-subject-error' : null"
              [value]="subject()"
              (input)="typed('subject', value($event))"
            />
            @if (errors().subject; as message) {
              <p class="field-error" id="mailbox-subject-error"><app-icon name="circle-alert" [size]="16" />{{ message }}</p>
            }
          </div>
          <div class="field">
            <label for="mailbox-body">{{ texts.labelBody }}</label>
            <textarea
              id="mailbox-body"
              class="input"
              rows="5"
              [class.invalid]="errors().body"
              [attr.aria-invalid]="errors().body ? 'true' : null"
              [attr.aria-describedby]="errors().body ? 'mailbox-body-error' : null"
              [value]="body()"
              (input)="typed('body', value($event))"
            ></textarea>
            @if (errors().body; as message) {
              <p class="field-error" id="mailbox-body-error"><app-icon name="circle-alert" [size]="16" />{{ message }}</p>
            }
          </div>
          <div class="actions">
            <app-server-button variant="primary" [action]="send" [describedBy]="sendError() === '' ? [] : ['mailbox-send-error']">{{ texts.send }}</app-server-button>
            <button type="button" class="button button-secondary" (click)="backFromForm()">{{ texts.back }}</button>
          </div>
          @if (sendError() !== '') {
            <p class="field-error" id="mailbox-send-error"><app-icon name="circle-alert" [size]="16" />{{ sendError() }}</p>
          }
        </div>
      }
      @case ('open') {
        @if (current(); as row) {
          <div class="open">
            <div><button type="button" class="button button-secondary" (click)="backFromOpen()">{{ texts.back }}</button></div>
            <h3 id="mailbox-heading" class="heading" tabindex="-1">{{ row.subject }}</h3>
            <p class="meta">{{ row.mail.sender }}<span aria-hidden="true">{{ separator }}</span>{{ row.time }}</p>
            <p class="text">{{ row.mail.text }}</p>
            @if (row.incoming) {
              <div class="strip">
                @if (row.decision; as decision) {
                  <div class="line1">
                    @if (row.chip; as outcome) {
                      <app-outcome-chip [outcome]="outcome" />
                    }
                    @if (decision.fallback) {
                      <app-fallback-flag />
                    }
                    @if (decision.traceUrl; as url) {
                      <app-trace-link [url]="url" />
                    }
                  </div>
                  @for (line of reasonsOf(decision); track $index) {
                    <p class="reason" [class.fallback]="$index === 0 && decision.fallback">{{ line }}</p>
                  }
                } @else {
                  <span class="deciding">{{ texts.deciding }}</span>
                }
              </div>
            }
          </div>
        }
      }
      @default {
        @if (rows().length === 0) {
          <p class="empty">{{ texts.empty }}</p>
        } @else {
          <ul class="list">
            @for (row of rows(); track row.ref) {
              <li>
                <button type="button" class="row" [attr.data-key]="row.ref" (click)="openMail(row)">
                  <span class="top">
                    <span class="from">
                      @if (row.unread) {
                        <span class="dot" aria-hidden="true"></span>
                        <span class="visually-hidden">{{ texts.unread }}</span>
                      }
                      {{ row.name }}
                    </span>
                    <span class="time">{{ row.time }}</span>
                  </span>
                  <span class="subject">{{ row.subject }}</span>
                  @if (row.incoming) {
                    @if (row.chip; as outcome) {
                      <app-outcome-chip [outcome]="outcome" />
                    } @else if (!row.decision) {
                      <span class="deciding">{{ texts.deciding }}</span>
                    }
                  }
                </button>
              </li>
            }
          </ul>
        }
      }
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      min-width: 0;
      font-family: var(--font-ui);
      color: var(--ink);
    }
    .chips {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-2);
    }
    .caption {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .simulate {
      align-self: flex-start;
    }
    .empty {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--email-row-typography-font-size);
      line-height: var(--email-row-typography-line-height);
    }
    .list {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .row {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
      width: 100%;
      min-height: var(--space-target-min);
      padding: var(--space-2) var(--space-3);
      background: var(--simulated-mailbox-background);
      color: var(--ink);
      border: var(--simulated-mailbox-border);
      border-radius: var(--simulated-mailbox-radius);
      font-family: var(--font-ui);
      font-size: var(--email-row-typography-font-size);
      font-weight: var(--email-row-typography-font-weight);
      line-height: var(--email-row-typography-line-height);
      text-align: left;
      cursor: pointer;
    }
    .top {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: var(--space-2);
      width: 100%;
    }
    .from {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      min-width: 0;
      font-weight: 600;
      overflow-wrap: anywhere;
    }
    .dot {
      flex: none;
      width: 8px;
      min-height: 8px;
      aspect-ratio: 1;
      background: var(--email-row-unread-marker);
      border-radius: var(--rounded-full);
    }
    .time {
      flex: none;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .subject {
      overflow-wrap: anywhere;
    }
    .deciding {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .form,
    .open {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      min-width: 0;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    label {
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-label-line-height);
    }
    .input {
      box-sizing: border-box;
      width: 100%;
      min-height: var(--space-control-height-lg);
      padding: var(--space-2) var(--space-3);
      background: var(--text-input-background);
      color: var(--ink);
      border: var(--text-input-border);
      border-radius: var(--text-input-radius);
      font-family: var(--font-ui);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .input.invalid {
      border: var(--text-input-border-error);
    }
    .field-error {
      display: flex;
      align-items: flex-start;
      gap: var(--space-1);
      margin: 0;
      color: var(--field-error-foreground);
      font-size: var(--field-error-typography-font-size);
      font-weight: var(--field-error-typography-font-weight);
      line-height: var(--field-error-typography-line-height);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      gap: var(--space-2);
    }
    .heading {
      margin: 0;
      font-size: var(--type-body-strong-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-strong-line-height);
      overflow-wrap: anywhere;
    }
    .meta {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
      overflow-wrap: anywhere;
    }
    .text {
      margin: 0;
      white-space: pre-line;
      overflow-wrap: anywhere;
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .strip {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .line1 {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
    }
    .reason {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
      overflow-wrap: anywhere;
    }
    .reason.fallback {
      color: var(--warning-ink);
    }
  `,
})
export class SimulatedMailbox {
  protected readonly texts = MAILBOX_TEXTS;
  protected readonly samples = SAMPLES;
  protected readonly separator = CHAT_TEXTS.separator;

  private readonly live = inject(LiveState);
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly injector = inject(Injector);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  /** Which view shows under the chips. */
  protected readonly view = signal<'list' | 'form' | 'open'>('list');

  /** The ref of the open email. */
  private readonly openRef = signal('');

  /** The form's fields and errors. */
  protected readonly from = signal<string>(MAILBOX_TEXTS.fromPrefill);
  protected readonly subject = signal('');
  protected readonly body = signal('');
  protected readonly errors = signal<FormErrors>({});

  /** The message of an error answer to a send, shown under Send, and of one to a chip press, shown under the chips. */
  protected readonly sendError = signal('');
  protected readonly chipError = signal('');

  /** The refs of the emails opened in this browser, space-separated: the stored text, or what this page opened when storage fails. */
  private readonly opened = signal(readText(() => localStorage, OPENED_KEY));

  /** The instance's time zone, from the snapshot. */
  private readonly instanceZone = computed(() => this.live.snapshot()?.instanceZone ?? '');

  /** The rows of the list, newest first. */
  protected readonly rows = computed<readonly RowView[]>(() => {
    const list = mailOf(this.live.snapshot() as MailboxSnapshot | undefined, this.live.store()) ?? [];
    const decisions = this.live.store()?.decisions;
    const opened = new Set(openedRefs(this.opened()));
    const zone = this.instanceZone();
    return list.map((mail) => {
      const decision = decisionOf(mail, decisions);
      const ref = mail.ref ?? '';
      return {
        mail,
        ref,
        name: senderName(mail.sender),
        subject: mail.subject ?? '',
        time: pageTimeBeside(mail.createdAt ?? '', zone),
        unread: !opened.has(ref),
        incoming: mail.direction !== 'out',
        decision,
        chip: decision === undefined ? undefined : outcomeOf(decision.outcome, decision.fallback),
      };
    });
  });

  /** The open email's row. */
  protected readonly current = computed(() => this.rows().find((row) => row.ref === this.openRef()));

  /** The snapshot that `announced` belongs to. */
  private looked: unknown;
  /** The refs whose decision is announced or was there at load: nothing is announced for them again. */
  private readonly announced = new Set<string>();
  /** The refs of the emails whose chip press was accepted and whose row is not in the list yet. */
  private readonly awaiting = new Set<string>();
  /** The ref of the sent email whose row takes focus when it is in the list. */
  private focusRef = '';

  constructor() {
    effect(() => {
      const snapshot = this.live.snapshot();
      const rows = this.rows();
      untracked(() => this.note(snapshot, rows));
    });
  }

  protected nameOf(label: string): string {
    return chipName(label);
  }

  protected value(event: Event): string {
    return (event.target as HTMLInputElement | HTMLTextAreaElement).value;
  }

  protected reasonsOf(decision: DecisionPayload): string[] {
    return reasonLines(decision.reasons, decision.fallback ? fallbackSentence(decision.fallbackReason) : undefined, REASON_LINES);
  }

  /** A sample chip's press: the call that delivers the sample; the answer's ref is awaited in the list and announced when its row is there. */
  protected samplePress(name: string): () => Observable<unknown> {
    return () => {
      this.chipError.set('');
      return this.api.postMailboxSample(name).pipe(
        tap({
          next: (accepted) => {
            this.awaiting.add(accepted.ref);
            this.note(this.live.snapshot(), this.rows());
          },
          error: (error: unknown) => this.chipError.set(messageOf(error)),
        }),
      );
    };
  }

  /** Send: a field in error shows its error and takes focus, with no request; otherwise the email is posted, and its row takes focus. */
  protected readonly send = (): Observable<unknown> => {
    const errors = fieldErrors(this.subject(), this.body());
    this.errors.set(errors);
    this.sendError.set('');
    if (errors.subject !== undefined || errors.body !== undefined) {
      this.focusLater(() => this.host.nativeElement.querySelector<HTMLElement>(errors.subject !== undefined ? '#mailbox-subject' : '#mailbox-body'));
      return of(undefined);
    }
    return this.api.postMailboxIncoming({ from: this.from(), subject: this.subject(), body: this.body() }).pipe(
      tap({
        next: (accepted) => this.sent(accepted.ref),
        error: (error: unknown) => this.sendError.set(messageOf(error)),
      }),
    );
  };

  /** The form opens in place of the list, with From prefilled and focused. */
  protected openForm(): void {
    this.from.set(MAILBOX_TEXTS.fromPrefill);
    this.subject.set('');
    this.body.set('');
    this.errors.set({});
    this.sendError.set('');
    this.view.set('form');
    this.focusLater(() => this.host.nativeElement.querySelector<HTMLElement>('#mailbox-from'));
  }

  protected backFromForm(): void {
    this.view.set('list');
    this.focusLater(() => this.simulateButton());
  }

  /** Typing in a field clears its error. */
  protected typed(field: 'subject' | 'body', text: string): void {
    (field === 'subject' ? this.subject : this.body).set(text);
    if (this.errors()[field] !== undefined) {
      this.errors.update((one) => ({ ...one, [field]: undefined }));
    }
  }

  /** A press on a row: the email opens in place and is read; focus goes to its heading. */
  protected openMail(row: RowView): void {
    const text = withOpened(this.opened(), row.ref);
    this.opened.set(text);
    writeFlag(() => localStorage, OPENED_KEY, text);
    this.openRef.set(row.ref);
    this.view.set('open');
    this.focusLater(() => this.host.nativeElement.querySelector<HTMLElement>('#mailbox-heading'));
  }

  /** Back from the open email: the list, with focus on that email's row. */
  protected backFromOpen(): void {
    const ref = this.openRef();
    this.view.set('list');
    this.focusLater(() => this.rowOf(ref));
  }

  /** The email was accepted: the list returns, and focus is on the new row, or on Simulate until the row is in the list. */
  private sent(ref: string): void {
    this.view.set('list');
    this.focusRef = ref;
    this.focusLater(() => {
      const row = this.rowOf(ref);
      if (row === null) {
        return this.simulateButton();
      }
      this.focusRef = '';
      return row;
    });
  }

  /**
   * Announces what the list shows that the page has not said. A new snapshot (the first load, or a reload) records the decisions it
   * holds and says nothing about them. Later: the row of an accepted chip press is announced as arrived, or as decided when it
   * already is; any other decision that lands is announced once. A sent email's row takes focus when it arrives, if focus is
   * still on Simulate.
   */
  private note(snapshot: unknown, rows: readonly RowView[]): void {
    if (snapshot !== this.looked) {
      this.looked = snapshot;
      this.announced.clear();
      this.awaiting.clear();
      for (const row of rows) {
        if (row.decision !== undefined) {
          this.announced.add(row.ref);
        }
      }
      return;
    }
    for (const row of rows) {
      if (this.awaiting.delete(row.ref)) {
        if (row.chip !== undefined) {
          this.announced.add(row.ref);
          this.announcer.announce(decidedText(row.subject, LABELS[row.chip]));
        } else {
          this.announcer.announce(arrivedText(row.subject));
        }
      }
      if (row.chip !== undefined && !this.announced.has(row.ref)) {
        this.announced.add(row.ref);
        this.announcer.announce(decidedText(row.subject, LABELS[row.chip]));
      }
    }
    if (this.focusRef !== '' && rows.some((row) => row.ref === this.focusRef)) {
      afterNextRender(() => this.focusSent(), { injector: this.injector });
    }
  }

  /** The sent email's row is in the list: focus moves to it if it is still on Simulate (where a send left it until the row came), and the wait ends. */
  private focusSent(): void {
    const row = this.rowOf(this.focusRef);
    if (row === null || this.view() !== 'list') {
      return;
    }
    this.focusRef = '';
    if (document.activeElement === this.simulateButton()) {
      row.focus({ preventScroll: true });
    }
  }

  private simulateButton(): HTMLElement | null {
    return this.host.nativeElement.querySelector<HTMLElement>('.simulate');
  }

  private rowOf(ref: string): HTMLElement | null {
    return Array.from(this.host.nativeElement.querySelectorAll<HTMLElement>('[data-key]')).find((element) => element.dataset['key'] === ref) ?? null;
  }

  /** Moves focus to the element once the view has rendered; the one place where this component moves focus for a user's action. */
  private focusLater(find: () => HTMLElement | null): void {
    afterNextRender(() => find()?.focus({ preventScroll: false }), { injector: this.injector });
  }
}
