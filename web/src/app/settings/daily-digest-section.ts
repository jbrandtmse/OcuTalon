import { afterNextRender, ChangeDetectionStrategy, Component, ElementRef, inject, Injector, input, output, signal, computed, effect } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { SettingsSaved, SettingsSections } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { refusalOf } from './refusal';
import { digestBody, digestChannelBoxes, digestChannelsBody, type DigestChannel, isDigestDirty, isDigestFormDirty, SETTINGS_TEXTS, storedChannels } from './settings-view';

/** The id of the error under the Save button, which the button is described by. */
const FORM_ERROR_ID = 'digest-error';

/**
 * The Daily digest section (Story 18.2; FR-35 to FR-37): the time of day of the digest (HH:MM, in the instance's time zone), the channels it goes to, and
 * **Save changes**, and apart from the form **Send my digest now**.
 *   - The channel boxes: the web chat always, the simulated phone only while demo mode is on, Telegram only while it is included and on or paused. A channel
 *     whose box is hidden keeps its stored state in the body, and the body names the channels in the order web, phone, telegram.
 *   - Save changes posts `{time, channels}` to POST /v1/settings/daily-digest through the busy pattern (ServerButton). The server judges both values:
 *     200 shows "Saved. Applies within a minute. Recorded in the audit log.", announces it once, makes the saved values the form's baseline and tells the
 *     page (`saved`); a change made while the save was pending keeps its value and the form stays dirty with no saved text. 400 `bad_settings` shows the
 *     field error "Couldn't save. Nothing was changed." under each named field (the first takes focus), or under the button when it names none. 403 tells the
 *     page (`denied`). Any other failure shows the error under the button and the announcer reads it.
 *   - Send my digest now posts to POST /v1/settings/daily-digest/send through its own busy button: 202 shows "Sending your digest now." and announces
 *     it; a failure shows "Couldn't send your digest. Try again." and announces it; a 403 tells the page. A press after the busy notice may send a second
 *     digest.
 * Typing or checking clears the errors and the saved text. `dirtyChange` tells the page whether the form differs from its saved values.
 */
@Component({
  selector: 'app-daily-digest-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="field">
      <label for="digest-time">{{ texts.dailyDigest.sendAt }}</label>
      <input
        id="digest-time"
        type="time"
        class="input"
        [class.invalid]="errors().time"
        [attr.aria-invalid]="errors().time ? 'true' : null"
        [attr.aria-describedby]="errors().time ? 'digest-time-help digest-time-error' : 'digest-time-help'"
        [value]="timeText()"
        (input)="typedTime($event)"
      />
      <p class="help" id="digest-time-help">{{ texts.dailyDigest.help }}</p>
      @if (errors().time) {
        <p class="field-error" id="digest-time-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
      }
    </div>
    <fieldset class="field channels" [attr.aria-describedby]="errors().channels ? 'digest-channels-error' : null">
      <legend>{{ texts.dailyDigest.sendTo }}</legend>
      @for (box of boxes(); track box.channel) {
        <label class="box">
          <input type="checkbox" [id]="'digest-channel-' + box.channel" [checked]="box.checked" (change)="toggled(box.channel, $event)" />
          {{ box.label }}
        </label>
      }
      @if (errors().channels) {
        <p class="field-error" id="digest-channels-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
      }
    </fieldset>
    <div class="actions">
      <app-server-button variant="primary" [action]="save" [describedBy]="described()">{{ saveLabel }}</app-server-button>
    </div>
    @if (formError()) {
      <p class="field-error" id="digest-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
    }
    @if (done()) {
      <p class="saved">{{ savedText }}</p>
    }
    <div class="actions send">
      <app-server-button variant="secondary" [action]="send" [describedBy]="sendDescribed()">{{ texts.dailyDigest.sendNow }}</app-server-button>
    </div>
    @if (sent() === 'done') {
      <p class="saved" id="digest-send-result">{{ texts.dailyDigest.sendNowDone }}</p>
    } @else if (sent() === 'failed') {
      <p class="field-error" id="digest-send-result"><app-icon name="circle-alert" [size]="16" />{{ texts.dailyDigest.sendNowFailed }}</p>
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
    .channels {
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
    .send {
      margin-top: var(--space-2);
    }
    .saved {
      margin: 0;
      color: var(--ink);
    }
  `,
})
export class DailyDigestSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The time of day the server holds, HH:MM. */
  readonly time = input.required<string>();

  /** The channels the server holds, comma-separated. */
  readonly channels = input.required<string>();

  /** True while demo mode is on: the simulated phone's box shows. */
  readonly demoMode = input(false);

  /** True while Telegram is included and on or paused: its box shows. */
  readonly telegramShown = input(false);

  /** True while the mailbox has an address and an outgoing mail server saved: the Email box shows. */
  readonly emailShown = input(false);

  /** The saved values, for the page to keep. */
  readonly saved = output<SettingsSections['daily-digest']>();

  /** Whether the form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly texts = SETTINGS_TEXTS;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;

  /** The typed time. */
  protected readonly timeText = signal('');
  /** The channels that are checked, in the order web, phone, telegram, email. */
  private readonly checked = signal<DigestChannel[]>([]);
  /** The values that the server holds: the form is dirty when it differs from them. */
  private readonly baseline = signal<{ time: string; channels: string }>({ time: '', channels: '' });
  protected readonly errors = signal<{ time?: boolean; channels?: boolean }>({});
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  /** How the last press of Send my digest now went: nothing yet, done or failed. */
  protected readonly sent = signal<'none' | 'done' | 'failed'>('none');
  protected readonly described = computed<readonly string[]>(() => (this.formError() ? [FORM_ERROR_ID] : []));
  protected readonly sendDescribed = computed<readonly string[]>(() => (this.sent() === 'none' ? [] : ['digest-send-result']));

  /** The channel boxes that show, with their labels and whether they are checked. */
  protected readonly boxes = computed(() =>
    digestChannelBoxes(this.demoMode(), this.telegramShown(), this.emailShown()).map((channel) => ({
      channel,
      label: SETTINGS_TEXTS.dailyDigest[channel],
      checked: this.checked().includes(channel),
    })),
  );

  /** The channels that a save would send: the boxes that show as they are checked, the others as the server holds them. */
  private readonly body = computed(() => digestBody(this.timeText(), digestChannelsBody(this.baseline().channels, digestChannelBoxes(this.demoMode(), this.telegramShown(), this.emailShown()), this.checked())));

  constructor() {
    let started = false;
    effect(() => {
      const time = this.time();
      const channels = this.channels();
      if (!started) {
        started = true;
        this.timeText.set(time);
        this.checked.set(storedChannels(channels));
        this.baseline.set({ time, channels: storedChannels(channels).join(',') });
      }
    });
    let last = false;
    effect(() => {
      const dirty = isDigestFormDirty(this.timeText(), this.checked(), digestChannelBoxes(this.demoMode(), this.telegramShown(), this.emailShown()), this.baseline());
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  /** Typing the time clears the errors and the saved text. */
  protected typedTime(event: Event): void {
    this.timeText.set((event.target as HTMLInputElement).value);
    this.cleared();
  }

  /** Checking or unchecking a channel clears the errors and the saved text. */
  protected toggled(channel: DigestChannel, event: Event): void {
    const on = (event.target as HTMLInputElement).checked;
    this.checked.update((one) => (on ? [...one.filter((name) => name !== channel), channel] : one.filter((name) => name !== channel)));
    this.cleared();
  }

  private cleared(): void {
    this.errors.set({});
    this.formError.set(false);
    this.done.set(false);
  }

  /** Save changes: posts the time and the channels; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.cleared();
    const sent = this.body();
    return this.api.saveSettings('daily-digest', sent).pipe(
      tap({
        next: (answer: SettingsSaved) => this.succeeded(sent, answer),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: { time: string; channels: string }, answer: SettingsSaved): void {
    const stored = answer.sections['daily-digest'] ?? sent;
    const kept = { time: stored.time, channels: storedChannels(stored.channels).join(',') };
    const edited = isDigestDirty(this.body(), sent);
    this.baseline.set(kept);
    if (!edited) {
      this.timeText.set(kept.time);
      this.checked.set(storedChannels(kept.channels));
    }
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
    this.saved.emit(stored);
  }

  private refused(error: unknown): void {
    const refusal = refusalOf(error, ['time', 'channels']);
    if (refusal.kind === 'denied') {
      this.denied.emit();
      return;
    }
    if (refusal.kind === 'form') {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    const time = refusal.fields.includes('time');
    this.errors.set({ time, channels: refusal.fields.includes('channels') });
    const target = time ? '#digest-time' : '#digest-channel-web';
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(target)?.focus(), { injector: this.injector });
  }

  /** Send my digest now: the digest goes out for the admin's session; the answer decides the line under the button. */
  protected readonly send = (): Observable<unknown> => {
    this.sent.set('none');
    return this.api.sendDigest().pipe(
      tap({
        next: () => {
          this.sent.set('done');
          this.announcer.announce(SETTINGS_TEXTS.dailyDigest.sendNowDone);
        },
        error: (error: unknown) => {
          if (refusalOf(error, []).kind === 'denied') {
            this.denied.emit();
            return;
          }
          this.sent.set('failed');
          this.announcer.announce(SETTINGS_TEXTS.dailyDigest.sendNowFailed);
        },
      }),
    );
  };
}
