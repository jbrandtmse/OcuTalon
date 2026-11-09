import { HttpErrorResponse } from '@angular/common/http';
import { afterNextRender, ChangeDetectionStrategy, Component, ElementRef, effect, inject, Injector, input, output, signal, computed } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { SettingsError, SettingsSaved, SettingsSections } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { refusalOf } from './refusal';
import { SETTINGS_TEXTS, stepFailedText } from './settings-view';

/** The ids of the help line and of the error, which the switch and the button are described by. */
const HELP_ID = 'demo-mode-help';
const ERROR_ID = 'demo-mode-error';

/**
 * The Demo mode section (Story 33.2; FR-16): one switch (role="switch", aria-checked) named "Demo mode", which shows its state, On or Off
 * (hidden from assistive technology, which hears aria-checked), its help line, and
 * **Save changes**. A press posts {demoMode} to POST /v1/settings/demo-mode through the busy pattern; the server switches it through the same
 * SettingsOps path as the terminal. The answers:
 *   - 200: "Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change." (announced once), and the saved value is the new baseline; a switch changed
 *     while the save was pending keeps its position, stays unsaved, and no saved text shows or is announced;
 *   - 409 `demo_step_failed`: the Demo step failed after the value was written, so the value stands (it is the new baseline) and the field shows the
 *     text of the step, never "Nothing was changed.";
 *   - 403: the page is told (`denied`); any other answer (400, 500, 501, no answer) shows the field error "Couldn't save. Nothing was changed." linked
 *     to the switch (aria-describedby), and the switch takes focus.
 * Changing the switch clears the error and the saved text. `dirtyChange` tells the page whether the switch differs from the saved value.
 */
@Component({
  selector: 'app-demo-mode-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="field">
      <button
        type="button"
        role="switch"
        id="demo-mode-switch"
        class="button button-secondary switch"
        [class.on]="on()"
        [attr.aria-checked]="on()"
        [attr.aria-invalid]="error() !== '' ? 'true' : null"
        [attr.aria-describedby]="switchDescribed()"
        (click)="toggle()"
      >
        <span class="track" aria-hidden="true"><span class="thumb"></span></span>
        <span class="label">{{ label }}</span>
        <span class="state" aria-hidden="true">{{ on() ? onText : offText }}</span>
      </button>
      <p class="help" [id]="helpId">{{ help }}</p>
      @if (error() !== '') {
        <p class="field-error" [id]="errorId"><app-icon name="circle-alert" [size]="16" />{{ error() }}</p>
      }
    </div>
    <div class="actions">
      <app-server-button variant="primary" [action]="save" [describedBy]="buttonDescribed()">{{ saveLabel }}</app-server-button>
    </div>
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
      gap: var(--space-2);
      align-items: flex-start;
    }
    .switch {
      gap: var(--space-2);
      white-space: nowrap;
    }
    .track {
      position: relative;
      flex: none;
      box-sizing: border-box;
      display: block;
      width: 32px;
      min-height: 18px;
      border: 1px solid var(--border-strong);
      border-radius: 9px;
      background: var(--surface);
    }
    .thumb {
      position: absolute;
      top: 2px;
      left: 2px;
      width: 12px;
      min-height: 12px;
      border-radius: 50%;
      background: var(--ink-muted);
    }
    .on .track {
      border-color: var(--action);
      background: var(--action);
    }
    .on .thumb {
      left: 16px;
      background: var(--on-action);
    }
    .state {
      color: var(--ink-muted);
    }
    .help {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
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
export class DemoModeSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The value the server holds, as the page loaded it. */
  readonly value = input.required<boolean>();

  /** The new value after a save (the Demo step's failure included, which leaves the value written), for the page to keep. */
  readonly saved = output<boolean>();

  /** Whether the switch differs from its saved value. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly label = SETTINGS_TEXTS.sections.demoMode;
  protected readonly onText = SETTINGS_TEXTS.on;
  protected readonly offText = SETTINGS_TEXTS.off;
  protected readonly help = SETTINGS_TEXTS.demoHelp;
  protected readonly savedText = SETTINGS_TEXTS.demoSaved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;
  protected readonly helpId = HELP_ID;
  protected readonly errorId = ERROR_ID;

  protected readonly on = signal(false);
  private readonly baseline = signal(false);
  /** The field error's text, empty for none. */
  protected readonly error = signal('');
  protected readonly done = signal(false);

  /** The switch is described by its help line, then by its error. */
  protected readonly switchDescribed = computed(() => (this.error() === '' ? HELP_ID : `${HELP_ID} ${ERROR_ID}`));
  protected readonly buttonDescribed = computed<readonly string[]>(() => (this.error() === '' ? [] : [ERROR_ID]));

  constructor() {
    let started = false;
    effect(() => {
      const value = this.value();
      if (!started) {
        started = true;
        this.on.set(value);
        this.baseline.set(value);
      }
    });
    let last = false;
    effect(() => {
      const dirty = this.on() !== this.baseline();
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  protected toggle(): void {
    this.on.update((one) => !one);
    this.error.set('');
    this.done.set(false);
  }

  /** Save changes: posts {demoMode}; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.error.set('');
    this.done.set(false);
    const sent = this.on();
    return this.api.saveSettings('demo-mode', { demoMode: sent }).pipe(
      tap({
        next: (answer: SettingsSaved) => this.succeeded(sent, answer),
        error: (error: unknown) => this.refused(sent, error),
      }),
    );
  };

  private succeeded(sent: boolean, answer: SettingsSaved): void {
    const stored: SettingsSections['demo-mode'] | undefined = answer.sections['demo-mode'];
    const value = stored === undefined ? sent : stored.demoMode;
    const edited = this.on() !== sent;
    this.baseline.set(value);
    if (!edited) {
      this.on.set(value);
    }
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.demoSaved);
    }
    this.saved.emit(value);
  }

  private refused(sent: boolean, error: unknown): void {
    if (refusalOf(error, []).kind === 'denied') {
      this.denied.emit();
      return;
    }
    const code = error instanceof HttpErrorResponse ? (error.error as SettingsError | undefined)?.error?.code : undefined;
    if (error instanceof HttpErrorResponse && error.status === 409 && code === 'demo_step_failed') {
      this.baseline.set(sent);
      this.error.set(stepFailedText(sent));
      this.saved.emit(sent);
    } else {
      this.error.set(SETTINGS_TEXTS.failed);
    }
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>('#demo-mode-switch')?.focus(), { injector: this.injector });
  }
}
