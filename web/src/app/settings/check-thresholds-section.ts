import { HttpErrorResponse } from '@angular/common/http';
import { afterNextRender, ChangeDetectionStrategy, Component, ElementRef, inject, Injector, input, output, signal, computed, effect } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { SettingsError, SettingsSaved, SettingsSections } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import {
  bodyOf,
  firstInError,
  isDirty,
  SETTINGS_TEXTS,
  textsOf,
  THRESHOLD_FIELDS,
  type ThresholdName,
  type ThresholdNumbers,
  type ThresholdTexts,
} from './settings-view';

/** The id of the error under the button, which the button is described by. */
const FORM_ERROR_ID = 'thresholds-error';

/**
 * The Check thresholds section (Story 33.2; FR-39): five fields of whole numbers and **Save changes**. A press posts the five values to
 * POST /v1/settings/check-thresholds through the busy pattern (ServerButton). The server judges every value:
 *   - 200: the section shows "Saved. Applies within a minute. Recorded in the audit log." and the announcer reads it once; the saved values are the
 *     form's new baseline and the page is told (`saved`); a field edited while the save was pending keeps its value, the form stays dirty and no
 *     saved text shows or is announced;
 *   - 400 `bad_settings`: each named field shows the field error "Couldn't save. Nothing was changed." linked to it (aria-describedby) and marked
 *     invalid, and the first of them takes focus; a refusal that names no field shows the error under the button, and the announcer reads it;
 *   - 403: the user is no longer an admin, and the page is told (`denied`); any other failure shows the error under the button, and the announcer
 *     reads it.
 * Typing in a field clears its error and the saved text. `dirtyChange` tells the page whether the form differs from its saved values.
 */
@Component({
  selector: 'app-check-thresholds-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (field of fields; track field.name) {
      <div class="field">
        <label [for]="'threshold-' + field.name">{{ field.label }}</label>
        <input
          type="text"
          inputmode="numeric"
          autocomplete="off"
          class="input"
          [id]="'threshold-' + field.name"
          [class.invalid]="errors()[field.name]"
          [attr.aria-invalid]="errors()[field.name] ? 'true' : null"
          [attr.aria-describedby]="errors()[field.name] ? 'threshold-' + field.name + '-error' : null"
          [value]="texts()[field.name]"
          (input)="typed(field.name, value($event))"
        />
        @if (errors()[field.name]) {
          <p class="field-error" [id]="'threshold-' + field.name + '-error'"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
        }
      </div>
    }
    <div class="actions">
      <app-server-button variant="primary" [action]="save" [describedBy]="described()">{{ saveLabel }}</app-server-button>
    </div>
    @if (formError()) {
      <p class="field-error" id="thresholds-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
    }
    @if (done()) {
      <p class="saved">{{ savedText }}</p>
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      max-width: 480px;
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
export class CheckThresholdsSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The values the server holds, as the page loaded them. */
  readonly values = input.required<ThresholdNumbers>();

  /** The new values after a save, for the page to keep. */
  readonly saved = output<SettingsSections['check-thresholds']>();

  /** Whether the form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly fields = THRESHOLD_FIELDS;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;

  /** The typed texts; empty until the values arrive. */
  protected readonly texts = signal<ThresholdTexts>(textsOf({ diskFreePercent: 0, journalFreePercent: 0, licenseUsePercent: 0, queueMessages: 0, queueWaitMinutes: 0 }));
  /** The texts that the server holds: the form is dirty when it differs from them. */
  private readonly baseline = signal<ThresholdTexts>(this.texts());
  protected readonly errors = signal<Partial<Record<ThresholdName, boolean>>>({});
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  protected readonly described = computed<readonly string[]>(() => (this.formError() ? [FORM_ERROR_ID] : []));

  constructor() {
    let started = false;
    effect(() => {
      const values = this.values();
      if (!started) {
        started = true;
        const texts = textsOf(values);
        this.texts.set(texts);
        this.baseline.set(texts);
      }
    });
    let last = false;
    effect(() => {
      const dirty = isDirty(this.texts(), this.baseline());
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  protected value(event: Event): string {
    return (event.target as HTMLInputElement).value;
  }

  /** Typing clears the field's error and the saved text. */
  protected typed(name: ThresholdName, text: string): void {
    this.texts.update((one) => ({ ...one, [name]: text }));
    if (this.errors()[name]) {
      this.errors.update((one) => ({ ...one, [name]: false }));
    }
    this.formError.set(false);
    this.done.set(false);
  }

  /** Save changes: posts the five values; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.formError.set(false);
    this.done.set(false);
    this.errors.set({});
    const sent = this.texts();
    return this.api.saveSettings('check-thresholds', bodyOf(sent)).pipe(
      tap({
        next: (answer: SettingsSaved) => this.succeeded(sent, answer),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: ThresholdTexts, answer: SettingsSaved): void {
    const stored = answer.sections['check-thresholds'];
    const texts = stored === undefined ? sent : textsOf(stored);
    const edited = isDirty(this.texts(), sent);
    this.baseline.set(texts);
    if (!edited) {
      this.texts.set(texts);
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
    if (error instanceof HttpErrorResponse && error.status === 403) {
      this.denied.emit();
      return;
    }
    const body = (error instanceof HttpErrorResponse ? error.error : undefined) as SettingsError | undefined;
    const named = error instanceof HttpErrorResponse && error.status === 400 && Array.isArray(body?.fields) ? body.fields : [];
    const known = THRESHOLD_FIELDS.map((field) => field.name as string);
    const names = named.filter((name) => known.includes(name)) as ThresholdName[];
    if (names.length === 0) {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    this.errors.set(Object.fromEntries(names.map((name) => [name, true])));
    const first = firstInError(names, known);
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(`#threshold-${first}`)?.focus(), { injector: this.injector });
  }
}
