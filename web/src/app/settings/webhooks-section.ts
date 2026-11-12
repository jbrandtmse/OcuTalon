import { afterNextRender, ChangeDetectionStrategy, Component, DestroyRef, ElementRef, inject, Injector, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { WebhookRow } from '../api/api-types';
import { Icon } from '../icon/icon';
import { LOAD_FAILED } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { SETTINGS_TEXTS } from './settings-view';
import { addressText, webhookOutcome } from './webhooks-view';

/** What one existing webhook's form shows: the error under its secret field, or the saved line. */
interface RowState {
  secretError: string;
  formError: boolean;
  done: boolean;
}

const BLANK: RowState = { secretError: '', formError: false, done: false };

/**
 * The Webhooks group of Settings > Channels (Story 35.3; FR-45): the form that makes a webhook and the list of the admin's webhooks, each with the address to
 * send events to and a field that replaces its secret. The secret fields are write-only (type password): a saved one is cleared from its field (a refused one stays for correcting), and nothing on the page
 * ever shows a secret or a hash. The server judges every value and answers each refused field with its text, which the group shows under that field:
 *   - 200: "Saved. Applies within a minute. Recorded in the audit log." shows and the announcer reads it once; a created webhook joins the list and the form's
 *     fields are emptied; a replaced secret's field is emptied;
 *   - 400 `bad_webhook`: the text of each refused field shows under it and the first takes focus; a 400 that names no field is the form error;
 *   - 403: "Only OcuTalon admins can open settings." shows in the group in place of the form (the page is not told);
 *   - 409 `not_available` (the online demo): the group shows its own text in place of the form;
 *   - any other failure: "Couldn't save. Nothing was changed." under the button, read once by the announcer.
 * A list that fails to load for any reason but 403 and 409 `not_available` shows the accepted load error (LOAD_FAILED, "Couldn't load your session.") with Retry in
 * place of the form, as the page does for its own load, and the announcer reads it once; Retry asks for the list again.
 * Typing in a field clears its error and the saved line. The group takes no part in the page's unsaved guard: a typed secret is not kept on leaving.
 */
@Component({
  selector: 'app-webhooks-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="group" aria-labelledby="webhooks-heading">
      <h3 id="webhooks-heading" class="heading">{{ texts.webhooks.heading }}</h3>
      @switch (state()) {
        @case ('off') {
          <p class="help" data-state="off">{{ texts.webhooks.offOnDemo }}</p>
        }
        @case ('failed') {
          <div class="load-error" data-state="failed">
            <p class="load-error-text" id="webhooks-load-error-text">{{ loadFailed }}</p>
            <app-server-button variant="secondary" [action]="retry" [describedBy]="['webhooks-load-error-text']">Retry</app-server-button>
          </div>
        }
        @case ('denied') {
          <p class="field-error" data-state="denied"><app-icon name="circle-alert" [size]="16" />{{ texts.denied }}</p>
        }
        @case ('ready') {
          <p class="help">{{ texts.webhooks.help }}</p>
          <div class="field">
            <label for="webhook-name">{{ texts.webhooks.name }}</label>
            <input
              id="webhook-name"
              class="input"
              type="text"
              autocomplete="off"
              [class.invalid]="nameError() !== ''"
              [attr.aria-invalid]="nameError() !== '' ? 'true' : null"
              [attr.aria-describedby]="nameError() !== '' ? 'webhook-name-error' : null"
              [value]="name()"
              (input)="typedName($event)"
            />
            @if (nameError() !== '') {
              <p class="field-error" id="webhook-name-error"><app-icon name="circle-alert" [size]="16" />{{ nameError() }}</p>
            }
          </div>
          <div class="field">
            <label for="webhook-secret">{{ texts.webhooks.secret }}</label>
            <input
              id="webhook-secret"
              class="input"
              type="password"
              autocomplete="new-password"
              [class.invalid]="secretError() !== ''"
              [attr.aria-invalid]="secretError() !== '' ? 'true' : null"
              [attr.aria-describedby]="secretError() !== '' ? 'webhook-secret-error' : null"
              [value]="secret()"
              (input)="typedSecret($event)"
            />
            @if (secretError() !== '') {
              <p class="field-error" id="webhook-secret-error"><app-icon name="circle-alert" [size]="16" />{{ secretError() }}</p>
            }
          </div>
          <div class="actions">
            <app-server-button variant="primary" [action]="create" [describedBy]="createDescribed()">{{ texts.webhooks.create }}</app-server-button>
          </div>
          @if (formError()) {
            <p class="field-error" id="webhook-form-error"><app-icon name="circle-alert" [size]="16" />{{ texts.failed }}</p>
          }
          @if (done()) {
            <p class="saved" data-saved="create">{{ texts.saved }}</p>
          }
          @for (webhook of webhooks(); track webhook.ref; let index = $index) {
            <div class="webhook" role="group" [attr.aria-label]="webhook.name">
              <h4 class="webhook-name">{{ webhook.name }}</h4>
              <p class="address">{{ address(webhook) }}</p>
              <div class="field">
                <label [for]="'webhook-secret-' + index">{{ texts.webhooks.secret }}</label>
                <input
                  [id]="'webhook-secret-' + index"
                  class="input"
                  type="password"
                  autocomplete="new-password"
                  [class.invalid]="rowState(webhook.ref).secretError !== ''"
                  [attr.aria-invalid]="rowState(webhook.ref).secretError !== '' ? 'true' : null"
                  [attr.aria-describedby]="rowState(webhook.ref).secretError !== '' ? 'webhook-secret-hint-' + index + ' webhook-secret-error-' + index : 'webhook-secret-hint-' + index"
                  [value]="rowSecret(webhook.ref)"
                  (input)="typedRowSecret(webhook.ref, $event)"
                />
                <p class="help" [id]="'webhook-secret-hint-' + index">{{ texts.webhooks.secretSet }}</p>
                @if (rowState(webhook.ref).secretError !== '') {
                  <p class="field-error" [id]="'webhook-secret-error-' + index"><app-icon name="circle-alert" [size]="16" />{{ rowState(webhook.ref).secretError }}</p>
                }
              </div>
              <div class="actions">
                <app-server-button variant="primary" [action]="saveRow(webhook.ref)" [describedBy]="rowDescribed(webhook.ref, index)">{{ texts.save }}</app-server-button>
              </div>
              @if (rowState(webhook.ref).formError) {
                <p class="field-error" [id]="'webhook-form-error-' + index"><app-icon name="circle-alert" [size]="16" />{{ texts.failed }}</p>
              }
              @if (rowState(webhook.ref).done) {
                <p class="saved" data-saved="rotate">{{ texts.saved }}</p>
              }
            </div>
          }
        }
      }
    </section>
  `,
  styles: `
    :host {
      display: block;
      max-width: 480px;
    }
    .group {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      margin-top: var(--space-6);
    }
    .heading,
    .webhook-name {
      margin: 0;
      color: var(--ink);
    }
    .webhook {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      padding-top: var(--space-4);
      border-top: var(--text-input-border);
    }
    .address {
      margin: 0;
      overflow-wrap: anywhere;
      color: var(--ink);
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .input {
      box-sizing: border-box;
      width: 100%;
      min-height: var(--space-target-min);
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
    .help {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
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
      gap: var(--space-3);
    }
    .saved {
      margin: 0;
      color: var(--ink);
    }
    .load-error {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
    }
    .load-error-text {
      margin: 0;
      color: var(--ink);
    }
  `,
})
export class WebhooksSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly destroyed = inject(DestroyRef);

  protected readonly texts = SETTINGS_TEXTS;
  protected readonly loadFailed = LOAD_FAILED;

  /** loading until the list answers; then ready, off (the online demo), denied, or failed (the list did not load). */
  protected readonly state = signal<'loading' | 'ready' | 'off' | 'denied' | 'failed'>('loading');
  protected readonly webhooks = signal<readonly WebhookRow[]>([]);

  protected readonly name = signal('');
  protected readonly secret = signal('');
  protected readonly nameError = signal('');
  protected readonly secretError = signal('');
  protected readonly formError = signal(false);
  protected readonly done = signal(false);

  /** The typed replacement secrets and the states of the existing webhooks' forms, by Ref. */
  private readonly rowSecrets = signal<Readonly<Record<string, string>>>({});
  private readonly rowStates = signal<Readonly<Record<string, RowState>>>({});

  constructor() {
    this.load();
  }

  /** Retry: asks for the list again; the Observable emits once and completes when the server has answered, whatever the answer. */
  protected readonly retry = (): Observable<void> =>
    new Observable<void>((subscriber) => {
      this.load(() => {
        subscriber.next();
        subscriber.complete();
      });
    });

  /** Loads the list; done is called once the server has answered. */
  private load(done?: () => void): void {
    this.api
      .webhooks()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (list) => {
          this.webhooks.set(list.webhooks);
          this.state.set('ready');
          done?.();
        },
        error: (error: unknown) => {
          const state = this.stateOf(error);
          this.state.set(state);
          if (state === 'failed') {
            this.announcer.announce(LOAD_FAILED);
          }
          done?.();
        },
      });
  }

  /** The line under a webhook: the sentence with the address on this page's origin. */
  protected address(webhook: WebhookRow): string {
    return addressText(SETTINGS_TEXTS.webhooks.address, window.location.origin, webhook.path);
  }

  protected createDescribed(): readonly string[] {
    return this.formError() ? ['webhook-form-error'] : [];
  }

  protected rowState(ref: string): RowState {
    return this.rowStates()[ref] ?? BLANK;
  }

  protected rowSecret(ref: string): string {
    return this.rowSecrets()[ref] ?? '';
  }

  protected rowDescribed(ref: string, index: number): readonly string[] {
    return this.rowState(ref).formError ? ['webhook-form-error-' + index] : [];
  }

  protected typedName(event: Event): void {
    this.name.set((event.target as HTMLInputElement).value);
    this.nameError.set('');
    this.formError.set(false);
    this.done.set(false);
  }

  protected typedSecret(event: Event): void {
    this.secret.set((event.target as HTMLInputElement).value);
    this.secretError.set('');
    this.formError.set(false);
    this.done.set(false);
  }

  protected typedRowSecret(ref: string, event: Event): void {
    this.rowSecrets.update((all) => ({ ...all, [ref]: (event.target as HTMLInputElement).value }));
    this.setRow(ref, BLANK);
  }

  /** Create webhook: posts the name and the secret; the answer decides what the group shows. */
  protected readonly create = (): Observable<unknown> => {
    this.nameError.set('');
    this.secretError.set('');
    this.formError.set(false);
    this.done.set(false);
    return this.api.createWebhook(this.name(), this.secret()).pipe(
      tap({
        next: (answer) => {
          this.webhooks.update((list) => [...list, answer.webhook]);
          this.name.set('');
          this.secret.set('');
          this.done.set(true);
          this.announcer.announce(SETTINGS_TEXTS.saved);
        },
        error: (error: unknown) => this.refusedCreate(error),
      }),
    );
  };

  /** Save changes under an existing webhook: replaces its secret. */
  protected saveRow(ref: string): () => Observable<unknown> {
    return () => {
      this.setRow(ref, BLANK);
      return this.api.setWebhookSecret(ref, this.rowSecret(ref)).pipe(
        tap({
          next: () => {
            this.rowSecrets.update((all) => ({ ...all, [ref]: '' }));
            this.setRow(ref, { secretError: '', formError: false, done: true });
            this.announcer.announce(SETTINGS_TEXTS.saved);
          },
          error: (error: unknown) => this.refusedRow(ref, error),
        }),
      );
    };
  }

  private setRow(ref: string, state: RowState): void {
    this.rowStates.update((all) => ({ ...all, [ref]: state }));
  }

  private stateOf(error: unknown): 'off' | 'denied' | 'failed' {
    if (!(error instanceof HttpErrorResponse)) {
      return 'failed';
    }
    const outcome = webhookOutcome(error.status, error.error);
    return outcome.kind === 'off' ? 'off' : outcome.kind === 'denied' ? 'denied' : 'failed';
  }

  private refusedCreate(error: unknown): void {
    const outcome = error instanceof HttpErrorResponse ? webhookOutcome(error.status, error.error) : ({ kind: 'form' } as const);
    if (outcome.kind === 'denied' || outcome.kind === 'off') {
      this.state.set(outcome.kind);
      return;
    }
    if (outcome.kind === 'fields') {
      this.nameError.set(outcome.name);
      this.secretError.set(outcome.secret);
      this.announcer.announce([outcome.name, outcome.secret].filter((text) => text !== '').join(' '));
      this.moveFocusTo(outcome.name !== '' ? '#webhook-name' : '#webhook-secret');
      return;
    }
    this.formError.set(true);
    this.announcer.announce(SETTINGS_TEXTS.failed);
  }

  private refusedRow(ref: string, error: unknown): void {
    const outcome = error instanceof HttpErrorResponse ? webhookOutcome(error.status, error.error) : ({ kind: 'form' } as const);
    if (outcome.kind === 'denied' || outcome.kind === 'off') {
      this.state.set(outcome.kind);
      return;
    }
    if (outcome.kind === 'fields' && outcome.secret !== '') {
      this.setRow(ref, { secretError: outcome.secret, formError: false, done: false });
      this.announcer.announce(outcome.secret);
      const index = this.webhooks().findIndex((webhook) => webhook.ref === ref);
      this.moveFocusTo('#webhook-secret-' + index);
      return;
    }
    this.setRow(ref, { secretError: '', formError: true, done: false });
    this.announcer.announce(SETTINGS_TEXTS.failed);
  }

  private moveFocusTo(selector: string): void {
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(selector)?.focus(), { injector: this.injector });
  }
}
