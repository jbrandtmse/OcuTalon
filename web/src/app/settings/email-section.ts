import { afterNextRender, ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, input, output, signal } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { EmailValues, SettingsSaved } from '../api/api-types';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { EMAIL_FIELDS, EMAIL_TEXTS, type EmailField, emailBody, emailTextsOf, type EmailTexts, fieldErrorText, isEmailDirty } from './email-view';
import { refusalOf } from './refusal';
import { firstInError, SETTINGS_TEXTS } from './settings-view';

/** The id of the error under the button, which the button is described by. */
const FORM_ERROR_ID = 'email-error';

/**
 * The Email group of Settings > Channels (Stories 21.2 and 21.6; FR-21, FR-22): the address, the incoming POP3 server and the outgoing SMTP server (each host, or
 * host:port; an empty outgoing server means none), the user name and the
 * write-only password of the admin's mailbox, and **Save changes**. The values come from the page's GET /v1/settings (`sections.channels`, passed in); the
 * password is never in them, so its field is empty, and a line under it says whether one is stored ("Saved, and never shown again. Type a new value to
 * replace it." or "Not set."). The group is absent while the snapshot says that this is the online demo, and when the server sends no channels values.
 *   - A press posts the typed values to POST /v1/settings/channels through the busy pattern (ServerButton); the password is in the body only when one was
 *     typed. The server judges every value:
 *   - 200: the group shows "Saved. Applies within a minute. Recorded in the audit log." and the announcer reads it once; the saved values are the form's
 *     new baseline, the password field is emptied and its line says that one is stored; a field edited while the save was pending keeps its value, the form
 *     stays dirty and no saved text shows or is announced;
 *   - 400 `bad_settings`: each named field shows its error, linked to it (aria-describedby) and marked invalid, and the first takes focus. The error is
 *     the setting-reference text when the field's typed value holds `@{`, else "Couldn't save. Nothing was changed."; a refusal that names no field shows
 *     "Couldn't save. Nothing was changed." under the button, and the announcer reads it;
 *   - 403 and any other failure show the error under the button, and the announcer reads it.
 * Typing in a field clears its error and the saved text. `saved` gives the page the new values and `dirtyChange` tells it whether the form differs from its saved values.
 */
@Component({
  selector: 'app-email-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (visible()) {
      <section class="email" aria-labelledby="email-heading" data-section="email">
        <h3 class="heading" id="email-heading">{{ t.heading }}</h3>
        <p class="help">{{ t.help }}</p>
        <div class="field">
          <label for="email-address">{{ t.address }}</label>
          <input
            id="email-address"
            type="text"
            inputmode="email"
            autocomplete="off"
            class="input"
            [class.invalid]="errors().address"
            [attr.aria-invalid]="errors().address ? 'true' : null"
            [attr.aria-describedby]="errors().address ? 'email-address-help email-address-error' : 'email-address-help'"
            [value]="texts().address"
            (input)="typed('address', value($event))"
          />
          <p class="help" id="email-address-help">{{ t.addressHelp }}</p>
          @if (errors().address) {
            <p class="field-error" id="email-address-error"><app-icon name="circle-alert" [size]="16" />{{ errorOf('address') }}</p>
          }
        </div>
        <div class="field">
          <label for="email-incoming">{{ t.incoming }}</label>
          <input
            id="email-incoming"
            type="text"
            autocomplete="off"
            class="input"
            [class.invalid]="errors().incoming"
            [attr.aria-invalid]="errors().incoming ? 'true' : null"
            [attr.aria-describedby]="errors().incoming ? 'email-incoming-error' : null"
            [value]="texts().incoming"
            (input)="typed('incoming', value($event))"
          />
          @if (errors().incoming) {
            <p class="field-error" id="email-incoming-error"><app-icon name="circle-alert" [size]="16" />{{ errorOf('incoming') }}</p>
          }
        </div>
        <div class="field">
          <label for="email-outgoing">{{ t.outgoing }}</label>
          <input
            id="email-outgoing"
            type="text"
            autocomplete="off"
            class="input"
            [class.invalid]="errors().outgoing"
            [attr.aria-invalid]="errors().outgoing ? 'true' : null"
            [attr.aria-describedby]="errors().outgoing ? 'email-outgoing-error' : null"
            [value]="texts().outgoing"
            (input)="typed('outgoing', value($event))"
          />
          @if (errors().outgoing) {
            <p class="field-error" id="email-outgoing-error"><app-icon name="circle-alert" [size]="16" />{{ errorOf('outgoing') }}</p>
          }
        </div>
        <div class="field">
          <label for="email-user">{{ t.user }}</label>
          <input
            id="email-user"
            type="text"
            autocomplete="off"
            class="input"
            [class.invalid]="errors().user"
            [attr.aria-invalid]="errors().user ? 'true' : null"
            [attr.aria-describedby]="errors().user ? 'email-user-error' : null"
            [value]="texts().user"
            (input)="typed('user', value($event))"
          />
          @if (errors().user) {
            <p class="field-error" id="email-user-error"><app-icon name="circle-alert" [size]="16" />{{ errorOf('user') }}</p>
          }
        </div>
        <div class="field">
          <label for="email-password">{{ t.password }}</label>
          <input
            id="email-password"
            type="password"
            autocomplete="new-password"
            class="input"
            [class.invalid]="errors().password"
            [attr.aria-invalid]="errors().password ? 'true' : null"
            [attr.aria-describedby]="errors().password ? 'email-password-status email-password-error' : 'email-password-status'"
            [value]="texts().password"
            (input)="typed('password', value($event))"
          />
          <p class="help" id="email-password-status">{{ passwordSet() ? t.secretSet : t.secretNotSet }}</p>
          @if (errors().password) {
            <p class="field-error" id="email-password-error"><app-icon name="circle-alert" [size]="16" />{{ errorOf('password') }}</p>
          }
        </div>
        <div class="actions">
          <app-server-button variant="primary" [action]="save" [describedBy]="described()">{{ saveLabel }}</app-server-button>
        </div>
        @if (formError()) {
          <p class="field-error" id="email-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
        }
        @if (done()) {
          <p class="saved">{{ savedText }}</p>
        }
      </section>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .email {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
    }
    .heading {
      margin: 0;
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
      font-family: var(--type-caption-font-family);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
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
  `,
})
export class EmailSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly live = inject(LiveState);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The mailbox values the server holds, as the page loaded them; nothing when the server sends none (the online demo). */
  readonly values = input<EmailValues | undefined>();

  /** The new values after a save, for the page to keep. */
  readonly saved = output<EmailValues>();

  /** Whether the form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  protected readonly t = EMAIL_TEXTS;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;

  protected readonly texts = signal<EmailTexts>(emailTextsOf(undefined));
  /** The texts that the server holds: the form is dirty when it differs from them. */
  private readonly baseline = signal<EmailTexts>(this.texts());
  protected readonly passwordSet = signal(false);
  protected readonly errors = signal<Partial<Record<EmailField, boolean>>>({});
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  protected readonly described = computed<readonly string[]>(() => (this.formError() ? [FORM_ERROR_ID] : []));

  /** The group shows on a local install, once the server's values have come. */
  protected readonly visible = computed(() => this.live.snapshot()?.onlineDemo === false && this.values() !== undefined);

  constructor() {
    let started = false;
    effect(() => {
      const values = this.values();
      if (!started && values !== undefined) {
        started = true;
        const texts = emailTextsOf(values);
        this.texts.set(texts);
        this.baseline.set(texts);
        this.passwordSet.set(values.passwordSet);
      }
    });
    let last = false;
    effect(() => {
      const dirty = isEmailDirty(this.texts(), this.baseline());
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  protected value(event: Event): string {
    return (event.target as HTMLInputElement).value;
  }

  /** The error text under a refused field. */
  protected errorOf(name: EmailField): string {
    return fieldErrorText(this.texts(), name, this.failed);
  }

  /** Typing clears the field's error and the saved text. */
  protected typed(name: EmailField, text: string): void {
    this.texts.update((one) => ({ ...one, [name]: text }));
    if (this.errors()[name]) {
      this.errors.update((one) => ({ ...one, [name]: false }));
    }
    this.formError.set(false);
    this.done.set(false);
  }

  /** Save changes: posts the typed values; the answer decides what the group shows. */
  protected readonly save = (): Observable<unknown> => {
    this.formError.set(false);
    this.done.set(false);
    this.errors.set({});
    const sent = this.texts();
    return this.api.saveSettings('channels', emailBody(sent)).pipe(
      tap({
        next: (answer: SettingsSaved) => this.succeeded(sent, answer),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: EmailTexts, answer: SettingsSaved): void {
    const stored = answer.sections.channels;
    const texts = stored === undefined ? { ...sent, password: '' } : emailTextsOf(stored);
    const edited = EMAIL_FIELDS.some((name) => this.texts()[name] !== sent[name]);
    this.baseline.set(texts);
    if (!edited) {
      this.texts.set(texts);
    }
    this.passwordSet.set(stored?.passwordSet ?? (this.passwordSet() || sent.password !== ''));
    if (stored !== undefined) {
      this.saved.emit(stored);
    }
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
  }

  private refused(error: unknown): void {
    const known: string[] = [...EMAIL_FIELDS];
    const refusal = refusalOf(error, known);
    if (refusal.kind !== 'field') {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    const names = refusal.fields as EmailField[];
    this.errors.set(Object.fromEntries(names.map((name) => [name, true])));
    const first = firstInError(names, known);
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(`#email-${first}`)?.focus(), { injector: this.injector });
  }
}
