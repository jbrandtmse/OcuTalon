import { HttpErrorResponse } from '@angular/common/http';
import { afterNextRender, ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, input, output, signal } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { OnCallValues, SettingsSaved } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import {
  defaultChannels,
  fieldErrorText,
  isOnCallDirty,
  onCallBody,
  onCallFormOf,
  type OnCallField,
  type OnCallForm,
  type OnCallRole,
  type OnCallRoleForm,
  ONCALL_FIELDS,
  parsePerson,
  personOptions,
  personValue,
  telegramState,
  type OnCallUser,
} from './on-call-view';
import { refusalOf } from './refusal';
import { firstInError, SETTINGS_TEXTS } from './settings-view';

/** The id of the error under the button, which the button is described by. */
const FORM_ERROR_ID = 'oncall-error';

/** The two groups of the form: the role, its legend and the names of the fields that a refusal can name for it. */
const GROUPS = [
  { role: 'primary', legend: SETTINGS_TEXTS.onCall.primary, user: 'primaryUser', email: 'primaryEmail', channels: 'primaryChannels' },
  { role: 'backup', legend: SETTINGS_TEXTS.onCall.backup, user: 'backupUser', email: 'backupEmail', channels: 'backupChannels' },
] as const satisfies readonly { role: OnCallRole; legend: string; user: OnCallField; email: OnCallField; channels: OnCallField }[];

/**
 * The On call section (Story 36.4; FR-44): who OcuTalon pages and who it pages next. Two groups, "On-call person" and "Backup", each with a Person select
 * (Nobody, each OcuTalon user, "Someone else, by email"), the "Email address for pages" field and the "Page by" boxes (the last two hidden for Nobody); then
 * the minutes before the backup is paged, and **Save changes**. The Telegram box is disabled, with its text beside it, for a user without a paired chat and for
 * a person by email. While the on-call person is by email, the line `byEmailHelp` shows under their Person select. While OcuTalon.Data.Page is not
 * compiled, the `notYet` line says that no page is sent yet. A press posts the form's body to POST /v1/settings/on-call through the busy pattern
 * (ServerButton), which the server validates:
 *   - 200: the section shows "Saved. Applies within a minute. Recorded in the audit log." and the announcer reads it once; the saved values are the form's new
 *     baseline and the page is told (`saved`); a field edited while the save was pending keeps its value and the form stays dirty with no saved text;
 *   - 400 `bad_settings`: each named field shows its own accepted text, linked to it (aria-describedby) and marked invalid, and the first of them in the form's
 *     order takes focus; a refusal that names no field of the form shows the failed text under the button, and the announcer reads it;
 *   - 403: the user is no longer an admin, and the page is told (`denied`);
 *   - 409 `not_available`: the online demo; the section shows `offOnDemo` in place of the form, and the page is told that nothing is unsaved (`dirtyChange(false)`);
 *   - any other failure shows the failed text under the button, and the announcer reads it.
 * Typing or choosing clears the error of that control and the saved text. `dirtyChange` tells the page whether the form differs from its saved values.
 */
@Component({
  selector: 'app-on-call-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (offDemo()) {
      <p class="off" id="oncall-off">{{ texts.offOnDemo }}</p>
    } @else {
      <p class="help" id="oncall-help">{{ texts.help }}</p>
      @if (!pagesBuilt()) {
        <p class="help" id="oncall-not-yet">{{ texts.notYet }}</p>
      }
      @for (group of groups; track group.role) {
        <fieldset class="group">
          <legend>{{ group.legend }}</legend>
          <div class="field">
            <label [for]="'oncall-' + group.role + '-person'">{{ texts.person }}</label>
            <select
              [id]="'oncall-' + group.role + '-person'"
              class="input"
              [class.invalid]="errors()[group.user]"
              [attr.aria-invalid]="errors()[group.user] ? 'true' : null"
              [attr.aria-describedby]="personDescribed(group.role)"
              (change)="chose(group.role, $event)"
            >
              @for (option of options(group.role); track option.value) {
                <option [value]="option.value" [selected]="option.value === personValue(group.role)">{{ option.label }}</option>
              }
            </select>
            @if (group.role === 'primary' && form().primary.person === 'email') {
              <p class="help" id="oncall-primary-person-help">{{ texts.byEmailHelp }}</p>
            }
            @if (errors()[group.user]) {
              <p class="field-error" [id]="'oncall-' + group.role + '-person-error'"><app-icon name="circle-alert" [size]="16" />{{ errorText(group.user) }}</p>
            }
          </div>
          @if (form()[group.role].person !== 'nobody') {
            <div class="field">
              <label [for]="'oncall-' + group.role + '-email'">{{ texts.email }}</label>
              <input
                type="text"
                inputmode="email"
                autocomplete="off"
                class="input"
                [id]="'oncall-' + group.role + '-email'"
                [class.invalid]="errors()[group.email]"
                [attr.aria-invalid]="errors()[group.email] ? 'true' : null"
                [attr.aria-describedby]="errors()[group.email] ? 'oncall-' + group.role + '-email-error' : null"
                [value]="form()[group.role].email"
                (input)="typedEmail(group.role, value($event))"
              />
              @if (errors()[group.email]) {
                <p class="field-error" [id]="'oncall-' + group.role + '-email-error'"><app-icon name="circle-alert" [size]="16" />{{ errorText(group.email) }}</p>
              }
            </div>
            <fieldset
              class="field boxes"
              [id]="'oncall-' + group.role + '-channels'"
              [attr.aria-describedby]="errors()[group.channels] ? 'oncall-' + group.role + '-channels-error' : null"
            >
              <legend>{{ texts.channels }}</legend>
              <label class="box">
                <input
                  type="checkbox"
                  [id]="'oncall-' + group.role + '-telegram'"
                  [checked]="form()[group.role].telegram"
                  [disabled]="telegramText(group.role) !== ''"
                  [attr.aria-describedby]="telegramText(group.role) !== '' ? 'oncall-' + group.role + '-telegram-help' : null"
                  (change)="toggled(group.role, 'telegram', $event)"
                />
                {{ texts.telegram }}
              </label>
              @if (telegramText(group.role) !== '') {
                <p class="help" [id]="'oncall-' + group.role + '-telegram-help'">{{ telegramText(group.role) }}</p>
              }
              <label class="box">
                <input type="checkbox" [id]="'oncall-' + group.role + '-mail'" [checked]="form()[group.role].mail" (change)="toggled(group.role, 'mail', $event)" />
                {{ texts.channelEmail }}
              </label>
              @if (errors()[group.channels]) {
                <p class="field-error" [id]="'oncall-' + group.role + '-channels-error'"><app-icon name="circle-alert" [size]="16" />{{ errorText(group.channels) }}</p>
              }
            </fieldset>
          }
        </fieldset>
      }
      <div class="field">
        <label for="oncall-minutes">{{ texts.minutes }}</label>
        <input
          type="text"
          inputmode="numeric"
          autocomplete="off"
          class="input"
          id="oncall-minutes"
          [class.invalid]="errors().escalationMinutes"
          [attr.aria-invalid]="errors().escalationMinutes ? 'true' : null"
          [attr.aria-describedby]="errors().escalationMinutes ? 'oncall-minutes-help oncall-minutes-error' : 'oncall-minutes-help'"
          [value]="form().minutes"
          (input)="typedMinutes(value($event))"
        />
        <p class="help" id="oncall-minutes-help">{{ texts.minutesHelp }}</p>
        @if (errors().escalationMinutes) {
          <p class="field-error" id="oncall-minutes-error"><app-icon name="circle-alert" [size]="16" />{{ errorText('escalationMinutes') }}</p>
        }
      </div>
      <div class="actions">
        <app-server-button variant="primary" [action]="save" [describedBy]="described()">{{ saveLabel }}</app-server-button>
      </div>
      @if (formError()) {
        <p class="field-error" id="oncall-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
      }
      @if (done()) {
        <p class="saved">{{ savedText }}</p>
      }
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      max-width: 480px;
    }
    .group {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      margin: 0;
      padding: var(--space-3);
      border: 1px solid var(--border);
      border-radius: var(--rounded-sm);
      min-width: 0;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .boxes {
      margin: 0;
      padding: 0;
      border: 0;
      min-width: 0;
    }
    .box {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-target-min);
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
    .off {
      margin: 0;
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
export class OnCallSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The values the server holds, as the page loaded them. */
  readonly values = input.required<OnCallValues>();

  /** The new values after a save, for the page to keep. */
  readonly saved = output<OnCallValues>();

  /** Whether the form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly texts = SETTINGS_TEXTS.onCall;
  protected readonly groups = GROUPS;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;

  /** The OcuTalon users the server lists, with whether each has a paired chat. */
  protected readonly users = computed<readonly OnCallUser[]>(() => this.values().users);
  /** True once OcuTalon.Data.Page is compiled: the product sends pages. */
  protected readonly pagesBuilt = computed(() => this.values().pagesBuilt);

  /** The form; empty until the values arrive. */
  protected readonly form = signal<OnCallForm>(onCallFormOf({ primaryUser: '', primaryEmail: '', primaryChannels: '', backupUser: '', backupEmail: '', backupChannels: '', escalationMinutes: 15, users: [], pagesBuilt: true }));
  /** The form that the server holds: this form is dirty when it differs from it. */
  private readonly baseline = signal<OnCallForm>(this.form());
  protected readonly errors = signal<Partial<Record<OnCallField, boolean>>>({});
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  /** True once a save was answered 409: the online demo, which has no on-call person. */
  protected readonly offDemo = signal(false);
  protected readonly described = computed<readonly string[]>(() => (this.formError() ? [FORM_ERROR_ID] : []));

  constructor() {
    let started = false;
    effect(() => {
      const values = this.values();
      if (!started) {
        started = true;
        const form = onCallFormOf(values);
        this.form.set(form);
        this.baseline.set(form);
      }
    });
    let last = false;
    effect(() => {
      const dirty = isOnCallDirty(this.form(), this.baseline());
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  protected value(event: Event): string {
    return (event.target as HTMLInputElement).value;
  }

  protected personValue(role: OnCallRole): string {
    return personValue(this.form()[role]);
  }

  /** The Person select's choices for the role: the stored user stays listed when the server's list lacks them. */
  protected options(role: OnCallRole): { value: string; label: string }[] {
    return personOptions(this.users(), this.form()[role].user);
  }

  /** The text beside a Telegram box that cannot be chosen, or '' when it can. */
  protected telegramText(role: OnCallRole): string {
    const form = this.form()[role];
    const state = telegramState(form.person, form.user, this.users());
    return state.kind === 'enabled' ? '' : state.text;
  }

  protected errorText(name: OnCallField): string {
    return fieldErrorText(name, this.form());
  }

  /** The ids that describe a Person select: the by-email line (the on-call person's only) and its error. */
  protected personDescribed(role: OnCallRole): string | null {
    const ids = [
      role === 'primary' && this.form().primary.person === 'email' ? 'oncall-primary-person-help' : '',
      this.errors()[role === 'primary' ? 'primaryUser' : 'backupUser'] ? `oncall-${role}-person-error` : '',
    ].filter((id) => id !== '');
    return ids.length > 0 ? ids.join(' ') : null;
  }

  private change(role: OnCallRole, update: (form: OnCallRoleForm) => OnCallRoleForm, cleared: readonly OnCallField[]): void {
    this.form.update((one) => ({ ...one, [role]: update(one[role]) }));
    this.clear(cleared);
  }

  private clear(cleared: readonly OnCallField[]): void {
    if (cleared.some((name) => this.errors()[name])) {
      this.errors.update((one) => ({ ...one, ...Object.fromEntries(cleared.map((name) => [name, false])) }));
    }
    this.formError.set(false);
    this.done.set(false);
  }

  /** Choosing a person: the Page by boxes start where that person's can be, and the person's own errors go. */
  protected chose(role: OnCallRole, event: Event): void {
    const chosen = parsePerson((event.target as HTMLSelectElement).value);
    const paired = this.users().find((one) => one.user === chosen.user)?.paired === true;
    const boxes = defaultChannels(chosen.person, paired);
    this.change(role, (one) => ({ ...one, person: chosen.person, user: chosen.user, telegram: boxes.telegram, mail: boxes.mail }), [`${role}User`, `${role}Email`, `${role}Channels`] as OnCallField[]);
  }

  protected typedEmail(role: OnCallRole, text: string): void {
    this.change(role, (one) => ({ ...one, email: text }), [`${role}Email`] as OnCallField[]);
  }

  protected toggled(role: OnCallRole, box: 'telegram' | 'mail', event: Event): void {
    const checked = (event.target as HTMLInputElement).checked;
    this.change(role, (one) => ({ ...one, [box]: checked }), [`${role}Channels`] as OnCallField[]);
  }

  protected typedMinutes(text: string): void {
    this.form.update((one) => ({ ...one, minutes: text }));
    this.clear(['escalationMinutes']);
  }

  /** Save changes: posts the form's body; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.formError.set(false);
    this.done.set(false);
    this.errors.set({});
    const sent = this.form();
    return this.api.saveSettings('on-call', onCallBody(sent)).pipe(
      tap({
        next: (answer: SettingsSaved) => this.succeeded(sent, answer),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: OnCallForm, answer: SettingsSaved): void {
    const stored = answer.sections['on-call'];
    const form = stored === undefined ? sent : onCallFormOf(stored);
    const edited = isOnCallDirty(this.form(), sent);
    this.baseline.set(form);
    if (!edited) {
      this.form.set(form);
    }
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
    if (stored !== undefined) {
      this.saved.emit(stored);
    }
  }

  private refused(error: unknown): void {
    if (error instanceof HttpErrorResponse && error.status === 409) {
      this.offDemo.set(true);
      this.dirtyChange.emit(false);
      this.announcer.announce(SETTINGS_TEXTS.onCall.offOnDemo);
      return;
    }
    const refusal = refusalOf(error, ONCALL_FIELDS);
    if (refusal.kind === 'denied') {
      this.denied.emit();
      return;
    }
    if (refusal.kind === 'form') {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    const names = refusal.fields as OnCallField[];
    this.errors.set(Object.fromEntries(names.map((name) => [name, true])));
    const first = firstInError(names, ONCALL_FIELDS) as OnCallField;
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(this.focusSelector(first))?.focus(), { injector: this.injector });
  }

  /** The control that takes focus for a refused field: the Person select, the address, the first Page by box that can be chosen, or the minutes. */
  private focusSelector(name: OnCallField): string {
    if (name === 'escalationMinutes') {
      return '#oncall-minutes';
    }
    const role = name.startsWith('primary') ? 'primary' : 'backup';
    if (name.endsWith('User')) {
      return `#oncall-${role}-person`;
    }
    return name.endsWith('Email') ? `#oncall-${role}-email` : `#oncall-${role}-channels input:not(:disabled)`;
  }
}
