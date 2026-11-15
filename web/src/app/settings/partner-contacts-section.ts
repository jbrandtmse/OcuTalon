import { DialogRef } from '@angular/cdk/dialog';
import { HttpErrorResponse } from '@angular/common/http';
import { NgTemplateOutlet } from '@angular/common';
import { afterNextRender, ChangeDetectionStrategy, Component, effect, ElementRef, inject, Injector, input, output, signal } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { PartnerContact, PartnerContactsValues, PartnerProductionRow, SettingsSaved } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { CONFIRM_TITLE_ID, CONFIRMED, ConfirmDialog, ConfirmRequest } from '../shared/confirm-dialog';
import { Dialogs } from '../shared/dialogs';
import { ServerButton } from '../shared/server-button';
import { MCP_TEXTS } from './mcp-view';
import {
  emptyPartnerForm,
  fieldErrorText,
  isPartnerDirty,
  PARTNER_FIELDS,
  partnerBody,
  type PartnerField,
  partnerFormOf,
  type PartnerForm,
  productionOptions,
  type ProductionOption,
  removeBody,
  removeQuestion,
} from './partner-view';
import { refusalOf } from './refusal';
import { firstInError, SETTINGS_TEXTS } from './settings-view';

/** The key of the Add contact form; a contact's own form is keyed by its Ref. */
const NEW = 'new';

/**
 * The Partner contacts section (Story 24.2; FR-29): the people that partner warnings go to. It shows only while the server sends the `partner-contacts` values
 * (OcuTalon.Fix.PartnerContacts has TABLE = 1, and the install is not the online demo). The help line `partnersHelp` comes first. Each contact is a group named by
 * its saved name, with a Name field, an "Email address" field, a "Productions it concerns" group of boxes (one for each production the server lists, labelled by
 * its display name), **Save changes** and **Remove**; the Add contact form below has the same fields and a button. The row's Save changes and Remove take their accessible
 * names from their text and the contact's name. Remove opens the page's confirm dialog with `partnerRemoveConfirm` and Cancel. A press posts the form's body to
 * POST /v1/settings/partner-contacts through the busy pattern (ServerButton), which the server validates:
 *   - 200: the form shows "Saved. Applies within a minute. Recorded in the audit log." and the announcer reads it once; the list is the server's, the form is the saved
 *     contact (the Add contact form is empty again), and the page is told (`saved`); a field edited while the save was pending keeps its value and the form stays dirty
 *     with no saved text;
 *   - 400 `bad_settings`: each named field shows its own accepted text, linked to it (aria-describedby) and marked invalid, and the first of them in the form's order
 *     takes focus; a refusal that names no field of the form shows the failed text under the button, and the announcer reads it;
 *   - 403: the user is no longer an admin, and the page is told (`denied`);
 *   - 409 `not_available`: the online demo; the section shows `offOnDemo` in place of the forms, and the page is told that nothing is unsaved (`dirtyChange(false)`);
 *   - any other failure shows the failed text under the button, and the announcer reads it.
 * Typing or ticking clears the error of that control and the saved text. `dirtyChange` tells the page whether any form differs from its saved values.
 */
@Component({
  selector: 'app-partner-contacts-section',
  imports: [Icon, NgTemplateOutlet, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (offDemo()) {
      <p class="off" id="partner-off">{{ texts.offOnDemo }}</p>
    } @else {
      <p class="help" id="partner-help" tabindex="-1">{{ texts.help }}</p>
      @for (contact of contacts(); track contact.ref) {
        <fieldset class="group">
          <legend [id]="'partner-' + contact.ref + '-title'">{{ contact.name }}</legend>
          <ng-container *ngTemplateOutlet="fields; context: { key: contact.ref, form: formOf(contact.ref), options: optionsOf(contact.ref) }" />
          <div class="actions">
            <app-server-button variant="primary" [action]="saverOf(contact.ref)" [label]="saveLabel + ' ' + contact.name" [describedBy]="described(contact.ref)">{{ saveLabel }}</app-server-button>
            <button
              type="button"
              class="button button-secondary"
              [id]="'partner-' + contact.ref + '-remove'"
              [attr.aria-labelledby]="'partner-' + contact.ref + '-remove partner-' + contact.ref + '-title'"
              (click)="askRemove(contact, $event)"
            >
              {{ texts.remove }}
            </button>
          </div>
          @if (failedKey() === contact.ref) {
            <p class="field-error" [id]="'partner-' + contact.ref + '-error'"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
          }
          @if (doneKey() === contact.ref) {
            <p class="saved">{{ savedText }}</p>
          }
        </fieldset>
      }
      <fieldset class="group">
        <legend>{{ texts.add }}</legend>
        <ng-container *ngTemplateOutlet="fields; context: { key: newKey, form: formOf(newKey), options: optionsOf(newKey) }" />
        <div class="actions">
          <app-server-button variant="primary" [action]="saverOf(newKey)" [describedBy]="described(newKey)">{{ texts.add }}</app-server-button>
        </div>
        @if (failedKey() === newKey) {
          <p class="field-error" [id]="'partner-' + newKey + '-error'"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
        }
        @if (doneKey() === newKey) {
          <p class="saved">{{ savedText }}</p>
        }
      </fieldset>
    }

    <ng-template #fields let-key="key" let-form="form" let-options="options">
      <div class="field">
        <label [for]="'partner-' + key + '-name'">{{ texts.name }}</label>
        <input
          type="text"
          autocomplete="off"
          class="input"
          [id]="'partner-' + key + '-name'"
          [class.invalid]="errorOf(key, 'name')"
          [attr.aria-invalid]="errorOf(key, 'name') ? 'true' : null"
          [attr.aria-describedby]="errorOf(key, 'name') ? 'partner-' + key + '-name-error' : null"
          [value]="form.name"
          (input)="typed(key, 'name', value($event))"
        />
        @if (errorOf(key, 'name')) {
          <p class="field-error" [id]="'partner-' + key + '-name-error'"><app-icon name="circle-alert" [size]="16" />{{ errorText('name') }}</p>
        }
      </div>
      <div class="field">
        <label [for]="'partner-' + key + '-email'">{{ texts.email }}</label>
        <input
          type="text"
          inputmode="email"
          autocomplete="off"
          class="input"
          [id]="'partner-' + key + '-email'"
          [class.invalid]="errorOf(key, 'email')"
          [attr.aria-invalid]="errorOf(key, 'email') ? 'true' : null"
          [attr.aria-describedby]="errorOf(key, 'email') ? 'partner-' + key + '-email-error' : null"
          [value]="form.email"
          (input)="typed(key, 'email', value($event))"
        />
        @if (errorOf(key, 'email')) {
          <p class="field-error" [id]="'partner-' + key + '-email-error'"><app-icon name="circle-alert" [size]="16" />{{ errorText('email') }}</p>
        }
      </div>
      <fieldset class="field boxes" [id]="'partner-' + key + '-productions'" [attr.aria-describedby]="errorOf(key, 'productions') ? 'partner-' + key + '-productions-error' : null">
        <legend>{{ texts.productions }}</legend>
        @for (option of options; track option.key) {
          <label class="box">
            <input type="checkbox" [checked]="form.picked.includes(option.key)" (change)="toggled(key, option.key, $event)" />
            {{ option.label }}
          </label>
        }
        @if (errorOf(key, 'productions')) {
          <p class="field-error" [id]="'partner-' + key + '-productions-error'"><app-icon name="circle-alert" [size]="16" />{{ errorText('productions') }}</p>
        }
      </fieldset>
    </ng-template>
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
export class PartnerContactsSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly dialogs = inject(Dialogs);
  private readonly target = inject(ConfirmRequest);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The values the server holds, as the page loaded them. */
  readonly values = input.required<PartnerContactsValues>();

  /** The new values after a save or a removal, for the page to keep. */
  readonly saved = output<PartnerContactsValues>();

  /** Whether any form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly texts = SETTINGS_TEXTS.partners;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;
  protected readonly newKey = NEW;

  /** The stored contacts and the productions to choose from: the page's values at first, then each answer of the server. */
  protected readonly contacts = signal<readonly PartnerContact[]>([]);
  private readonly roster = signal<readonly PartnerProductionRow[]>([]);
  /** The forms that were typed in, by key (a contact's Ref, or NEW): a key with no entry shows its saved values. */
  private readonly edits = signal<Readonly<Record<string, PartnerForm>>>({});
  private readonly errors = signal<Readonly<Record<string, Partial<Record<PartnerField, boolean>>>>>({});
  /** The key of the form that shows the failed text, and of the one that shows the saved text. */
  protected readonly failedKey = signal<string | null>(null);
  protected readonly doneKey = signal<string | null>(null);
  /** True once a save was answered 409: the online demo, which has no partner contacts. */
  protected readonly offDemo = signal(false);

  private readonly savers = new Map<string, () => Observable<unknown>>();
  /** The answer of the removal that the confirm dialog made, and the text its failure notice shows. */
  private removed: SettingsSaved | undefined;
  private removeFailed: string = SETTINGS_TEXTS.failed;

  constructor() {
    let started = false;
    effect(() => {
      const values = this.values();
      if (!started) {
        started = true;
        this.contacts.set(values.contacts);
        this.roster.set(values.productions);
      }
    });
    let last = false;
    effect(() => {
      const edits = this.edits();
      const contacts = this.contacts();
      const dirty = Object.keys(edits).some((key) => {
        const contact = contacts.find((one) => one.ref === key);
        return isPartnerDirty(edits[key], key === NEW ? emptyPartnerForm() : contact === undefined ? edits[key] : partnerFormOf(contact));
      });
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  protected value(event: Event): string {
    return (event.target as HTMLInputElement).value;
  }

  /** The form of the key: what was typed, else the saved contact's values, else the empty form. */
  protected formOf(key: string): PartnerForm {
    const typed = this.edits()[key];
    if (typed !== undefined) {
      return typed;
    }
    const contact = this.contacts().find((one) => one.ref === key);
    return contact === undefined ? emptyPartnerForm() : partnerFormOf(contact);
  }

  /** The boxes of the key's form: the roster, and any production that the contact still names. */
  protected optionsOf(key: string): ProductionOption[] {
    const contact = this.contacts().find((one) => one.ref === key);
    return productionOptions(this.roster(), contact?.productions ?? []);
  }

  protected errorOf(key: string, name: PartnerField): boolean {
    return this.errors()[key]?.[name] === true;
  }

  protected errorText(name: PartnerField): string {
    return fieldErrorText(name);
  }

  /** The ids that describe a form's button: its failed text while it shows. */
  protected described(key: string): readonly string[] {
    return this.failedKey() === key ? [`partner-${key}-error`] : [];
  }

  private clear(key: string, name: PartnerField | null): void {
    if (name !== null && this.errorOf(key, name)) {
      this.errors.update((all) => ({ ...all, [key]: { ...all[key], [name]: false } }));
    }
    this.failedKey.set(null);
    this.doneKey.set(null);
  }

  protected typed(key: string, field: 'name' | 'email', text: string): void {
    this.edits.update((all) => ({ ...all, [key]: { ...this.formOf(key), [field]: text } }));
    this.clear(key, field);
  }

  protected toggled(key: string, option: string, event: Event): void {
    const checked = (event.target as HTMLInputElement).checked;
    const now = this.formOf(key).picked.filter((one) => one !== option);
    this.edits.update((all) => ({ ...all, [key]: { ...this.formOf(key), picked: checked ? [...now, option] : now } }));
    this.clear(key, 'productions');
  }

  /** The press handler of the key's Save changes or Add contact: one function for each key, so that the button's input stays the same. */
  protected saverOf(key: string): () => Observable<unknown> {
    let saver = this.savers.get(key);
    if (saver === undefined) {
      saver = () => this.save(key);
      this.savers.set(key, saver);
    }
    return saver;
  }

  /** Posts the key's form; the answer decides what the section shows. */
  private save(key: string): Observable<unknown> {
    this.failedKey.set(null);
    this.doneKey.set(null);
    this.errors.update((all) => ({ ...all, [key]: {} }));
    const sent = this.formOf(key);
    const body = partnerBody(key === NEW ? '' : key, sent, this.optionsOf(key));
    return this.api.savePartnerContact(body).pipe(
      tap({
        next: (answer: SettingsSaved) => this.succeeded(key, sent, answer),
        error: (error: unknown) => this.refused(key, error),
      }),
    );
  }

  private succeeded(key: string, sent: PartnerForm, answer: SettingsSaved): void {
    const stored = answer.sections['partner-contacts'];
    const edited = isPartnerDirty(this.formOf(key), sent);
    if (stored !== undefined) {
      this.contacts.set(stored.contacts);
      this.roster.set(stored.productions);
    }
    if (!edited) {
      this.edits.update((all) => Object.fromEntries(Object.entries(all).filter(([one]) => one !== key)));
    }
    this.doneKey.set(edited ? null : key);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
    if (stored !== undefined) {
      this.saved.emit(stored);
    }
  }

  private refused(key: string, error: unknown): void {
    if (error instanceof HttpErrorResponse && error.status === 409) {
      this.offDemo.set(true);
      this.dirtyChange.emit(false);
      this.announcer.announce(SETTINGS_TEXTS.partners.offOnDemo);
      return;
    }
    const refusal = refusalOf(error, PARTNER_FIELDS);
    if (refusal.kind === 'denied') {
      this.denied.emit();
      return;
    }
    if (refusal.kind === 'form') {
      this.failedKey.set(key);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    const names = refusal.fields as PartnerField[];
    this.errors.update((all) => ({ ...all, [key]: Object.fromEntries(names.map((name) => [name, true])) }));
    const first = firstInError(names, PARTNER_FIELDS) as PartnerField;
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(this.focusSelector(key, first))?.focus(), { injector: this.injector });
  }

  /** The control that takes focus for a refused field: the name, the address, or the first production box. */
  private focusSelector(key: string, name: PartnerField): string {
    return name === 'productions' ? `#partner-${key}-productions input` : `#partner-${key}-${name}`;
  }

  /** Opens the Remove dialog for a contact; the button that opened it gets focus back when the dialog closes without removing. */
  protected askRemove(contact: PartnerContact, event: Event): void {
    let dialog: DialogRef<unknown, ConfirmDialog> | undefined;
    const failed = (): string => this.removeFailed;
    this.removeFailed = SETTINGS_TEXTS.failed;
    this.removed = undefined;
    this.target.content.set({
      question: removeQuestion(contact),
      confirm: this.texts.remove,
      cancel: MCP_TEXTS.cancel,
      get failed(): string {
        return failed();
      },
      act: () =>
        this.api.savePartnerContact(removeBody(contact.ref)).pipe(
          tap({
            next: (answer) => (this.removed = answer),
            error: (error: unknown) => {
              this.removeFailed = error instanceof HttpErrorResponse && error.status === 409 ? SETTINGS_TEXTS.partners.offOnDemo : SETTINGS_TEXTS.failed;
              if (refusalOf(error, PARTNER_FIELDS).kind === 'denied') {
                dialog?.close();
                this.denied.emit();
              }
            },
          }),
        ),
    });
    dialog = this.dialogs.open(ConfirmDialog, { labelledBy: CONFIRM_TITLE_ID, restoreFocus: event.currentTarget as HTMLElement });
    dialog.closed.subscribe((result) => {
      if (result === CONFIRMED) {
        this.gone(contact.ref);
      }
    });
  }

  /** The contact is gone: the list is the server's answer (or without the contact), the saved text is announced once, and focus goes to the help line once the dialog has given it back. */
  private gone(ref: string): void {
    const stored = this.removed?.sections['partner-contacts'];
    this.contacts.set(stored !== undefined ? stored.contacts : this.contacts().filter((one) => one.ref !== ref));
    if (stored !== undefined) {
      this.roster.set(stored.productions);
      this.saved.emit(stored);
    }
    this.edits.update((all) => Object.fromEntries(Object.entries(all).filter(([one]) => one !== ref)));
    this.failedKey.set(null);
    this.doneKey.set(null);
    this.announcer.announce(SETTINGS_TEXTS.saved);
    globalThis.setTimeout(() => this.host.nativeElement.querySelector<HTMLElement>('#partner-help')?.focus(), 0);
  }
}
