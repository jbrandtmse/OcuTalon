import { HttpErrorResponse } from '@angular/common/http';
import { afterNextRender, ChangeDetectionStrategy, Component, ElementRef, inject, Injector, input, output, signal, computed, effect } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { SettingsError } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { SETTINGS_TEXTS, zoneBody, zoneOptions } from './settings-view';

/** The id of the field's error, which the select and the button are described by. */
const ERROR_ID = 'time-zone-error';

/** The id of the help line, which the select is described by. */
const HELP_ID = 'time-zone-help';

/** The zone names that the browser knows; empty where it cannot list them. */
function browserZones(): string[] {
  try {
    const list = (Intl as unknown as { supportedValuesOf?: (key: string) => string[] }).supportedValuesOf;
    return list === undefined ? [] : list('timeZone');
  } catch {
    return [];
  }
}

/**
 * The Time zone section (Story 18.2; FR-16): a select of the browser's IANA zone names with the stored zone kept in the list and the empty "Server default"
 * choice, preselected from the stored value, and **Save changes**. A press posts `{InstanceZone}` to POST /v1/settings/time-zone through the busy pattern
 * (ServerButton). The server judges the value (a zone that its system lacks is refused with the field error):
 *   - 200: the section shows "Saved. Applies within a minute. Recorded in the audit log." and the announcer reads it once; the saved zone is the form's
 *     new baseline and the page is told (`saved`); a choice made while the save was pending keeps its value, the form stays dirty and no saved text shows;
 *   - 400 `bad_settings`: the field error "Couldn't save. Nothing was changed." shows under the select, which takes focus; a refusal that names no
 *     field shows it under the button, and the announcer reads it;
 *   - 403: the user is no longer an admin, and the page is told (`denied`); any other failure shows the error under the button, and the announcer reads it.
 * Choosing a zone clears the error and the saved text. `dirtyChange` tells the page whether the choice differs from the saved zone. Times on this page stay in
 * the browser's zone; the section only changes the instance's.
 */
@Component({
  selector: 'app-time-zone-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="field">
      <label for="time-zone-select">{{ texts.timeZone.label }}</label>
      <select
        id="time-zone-select"
        class="input"
        [class.invalid]="fieldError()"
        [attr.aria-invalid]="fieldError() ? 'true' : null"
        [attr.aria-describedby]="fieldError() ? helpId + ' ' + errorId : helpId"
        (change)="chosen($event)"
      >
        @for (option of options(); track option.value) {
          <option [value]="option.value" [selected]="option.value === choice()">{{ option.label }}</option>
        }
      </select>
      <p class="help" [id]="helpId">{{ texts.timeZone.help }}</p>
      @if (fieldError()) {
        <p class="field-error" [id]="errorId"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
      }
    </div>
    <div class="actions">
      <app-server-button variant="primary" [action]="save" [describedBy]="described()">{{ saveLabel }}</app-server-button>
    </div>
    @if (formError()) {
      <p class="field-error" [id]="errorId"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
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
  `,
})
export class TimeZoneSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The zone the server holds, as the page loaded it: "" for the server's own. */
  readonly zone = input.required<string>();

  /** The zone after a save, for the page to keep. */
  readonly saved = output<string>();

  /** Whether the choice differs from the saved zone. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly texts = SETTINGS_TEXTS;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;
  protected readonly helpId = HELP_ID;
  protected readonly errorId = ERROR_ID;

  /** The chosen zone; the stored one until the user chooses. */
  protected readonly choice = signal('');
  /** The zone that the server holds: the form is dirty when the choice differs from it. */
  private readonly baseline = signal('');
  protected readonly fieldError = signal(false);
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  protected readonly described = computed<readonly string[]>(() => (this.formError() || this.fieldError() ? [ERROR_ID] : []));
  protected readonly options = computed(() => zoneOptions(browserZones(), this.baseline()));

  constructor() {
    let started = false;
    effect(() => {
      const zone = this.zone();
      if (!started) {
        started = true;
        this.choice.set(zone);
        this.baseline.set(zone);
      }
    });
    let last = false;
    effect(() => {
      const dirty = this.choice() !== this.baseline();
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  /** Choosing a zone clears the error and the saved text. */
  protected chosen(event: Event): void {
    this.choice.set((event.target as HTMLSelectElement).value);
    this.fieldError.set(false);
    this.formError.set(false);
    this.done.set(false);
  }

  /** Save changes: posts the zone; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.fieldError.set(false);
    this.formError.set(false);
    this.done.set(false);
    const sent = this.choice();
    return this.api.saveSettings('time-zone', zoneBody(sent)).pipe(
      tap({
        next: () => this.succeeded(sent),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: string): void {
    const edited = this.choice() !== sent;
    this.baseline.set(sent);
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
    this.saved.emit(sent);
  }

  private refused(error: unknown): void {
    if (error instanceof HttpErrorResponse && error.status === 403) {
      this.denied.emit();
      return;
    }
    const body = (error instanceof HttpErrorResponse ? error.error : undefined) as SettingsError | undefined;
    const named = error instanceof HttpErrorResponse && error.status === 400 && Array.isArray(body?.fields) && body.fields.includes('InstanceZone');
    if (!named) {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    this.fieldError.set(true);
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>('#time-zone-select')?.focus(), { injector: this.injector });
  }
}
