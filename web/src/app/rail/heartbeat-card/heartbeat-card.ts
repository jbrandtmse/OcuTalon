import { DOCUMENT } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, DestroyRef, effect, ElementRef, inject, Injector, signal, untracked, viewChild } from '@angular/core';
import { type Observable, type Subscription, switchMap, tap } from 'rxjs';

import { ApiClient } from '../../api/api-client';
import type { HeartbeatSaved, HeartbeatState } from '../../api/heartbeat-types';
import { CHAT_TEXTS } from '../../chat/chat-view';
import { formatCost } from '../../chat/decision-view';
import { fallbackReasonText } from '../../chat/decision-strip';
import { pageWhen } from '../../chat/page-time';
import { Icon } from '../../icon/icon';
import { LiveState } from '../../live/live-state';
import { type FocusRule, keepFocus } from '../../shared/focus-rule';
import { Popovers } from '../../shared/popover';
import { BUSY_NOTICE, ServerButton } from '../../shared/server-button';
import { TraceLink } from '../../shared/trace-link';
import { heartbeatReadKey } from '../rail-view';
import { counterText } from '../persona-card/persona-card-view';
import {
  failureOf,
  type HeartbeatForm,
  type HeartbeatFormat,
  HEARTBEAT_HEADING_ID,
  HEARTBEAT_TEXTS,
  INTERVALS,
  lastLine,
  QUARTER_HOURS,
  RUN_NOW_SECONDS,
  saveBody,
  stateLine,
  todayLine,
  cooldownUntil,
  unavailable,
} from './heartbeat-card-view';

/** The count of the cards that have been made, which gives each one's ids a prefix of its own. */
let lastCard = 0;

/** The attribute that names the card's parts for its focus rule. */
const FOCUS_KEY = 'data-focus-key';

/** The hours that Active hours shows when the person turns All day off and the stored hours are empty: the install's defaults. */
const DEFAULT_FROM = '08:00';
const DEFAULT_TO = '20:00';

/** The slow clock, which keeps the card's day words current. */
const CLOCK_MS = 60_000;

/**
 * Where focus goes when the card's own read removes the element that holds it: the Heartbeat checklist heading, as the rail's rule does for
 * a row that leaves.
 */
const FOCUS_RULE: FocusRule = {
  item: `[${FOCUS_KEY}]`,
  keyOf: (item) => item.getAttribute(FOCUS_KEY) ?? '',
  whenGone: ({ host }) => host.ownerDocument.getElementById(HEARTBEAT_HEADING_ID),
};

/** The line under Save or under the run button: the text, and whether it is a refusal. */
interface Line {
  message: string;
  refused: boolean;
}

/** A refusal that shows beside a field. */
interface FieldLine {
  where: 'on' | 'interval' | 'hours' | 'checklist';
  message: string;
}

/** A run that the server accepted and the state has not yet shown: the LastRunNowAt it was pressed over and when the button may be pressed again. */
interface PendingRun {
  base: string;
  endMs: number;
}

/**
 * The Heartbeat checklist card (Story 39.5; FR-63 to FR-66, DW-634, DW-781, AD-12, AD-18): the body of the rail's Heartbeat checklist section.
 * It reads `GET /api/v1/heartbeat` when it is made and again whenever the live store keeps a new `heartbeat` event (heartbeatReadKey), so that it
 * shows the new state without a reload. While that read has not answered, or failed, it shows nothing (the section's heading only) and
 * tries again on the next event.
 * - Collapsed, it shows the state line (off, or the interval, hours and next check-in), the last line (the newer of the last check-in, with
 *   its outcome, cost and trace link, and the last skip), the Today line, the online-demo note on the online demo, an Edit disclosure and the
 *   "Run the heartbeat now" button with its describing line.
 * - Edit is a disclosure (aria-expanded, aria-controls). Open, it shows On, Interval, Active hours (All day, From, To), Checklist with its help
 *   and counter, and Save. Esc inside the open disclosure collapses it and moves focus to Edit, unless a popover is open (Popovers.hasOpen),
 *   which takes the Esc alone; the event stops there, so the drawer around the rail does not close with it.
 * - Save is a ServerButton whose PUT carries the form's values (all day is both hours empty). The server's message shows under Save; a
 *   `bad_on`, `bad_interval`, `bad_hours` or `bad_checklist` refusal shows beside its field, marked aria-invalid and linked through
 *   aria-describedby; any other failure shows its message under Save, or the busy notice when it has none, and the card reads again.
 * - Run is a ServerButton whose POST asks for a beat now. It is held (aria-disabled) while `dailyCap` or `noModelKey` is active, with the
 *   reason as its description (the cap first), and for 120 seconds after LastRunNowAt, with "You can run it again at {time}." as its
 *   description; a clock enables it again at the end. A 409 cooldown holds it to the answer's availableAt; any other 409 shows the server's
 *   message under it, and a 5xx the busy notice. On the online demo, while the shown checklist is the unsaved sample, the press first PUTs the shown values (the sample,
 *   the heartbeat as it is) and shows the server's saved line, and a refused PUT sends no POST. Run never saves unsaved edits of an open Edit.
 * The card announces nothing and is no live region. It moves focus only for the user's own Esc, and through the page's focus rule when its
 * own read removes the focused element: to the Heartbeat checklist heading. Every text is bound by interpolation from heartbeat-card-view.ts,
 * the persona view's counter or the server.
 */
@Component({
  selector: 'app-heartbeat-card',
  imports: [Icon, ServerButton, TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (state(); as heartbeat) {
      <div class="current" data-focus-key="current">
        @if (stateText(); as text) {
          <p class="line">{{ text }}</p>
        }
        @if (last(); as shown) {
          @if (shown.kind !== 'none') {
            <p class="line parts">
              @for (part of shown.parts; track $index) {
                @if ($index > 0) {
                  <span aria-hidden="true">{{ separator }}</span>
                }
                <span>{{ part }}</span>
              }
              @if (shown.traceUrl; as url) {
                <span aria-hidden="true">{{ separator }}</span>
                <app-trace-link [url]="url" />
              }
            </p>
          }
        }
        @if (today(); as text) {
          <p class="line">{{ text }}</p>
        }
        @if (heartbeat.onlineDemo) {
          <p class="note">{{ texts.demoNote }}</p>
        }
        <button
          #edit
          type="button"
          class="button button-ghost change"
          data-focus-key="edit"
          [attr.aria-expanded]="open()"
          [attr.aria-controls]="panelId"
          (click)="toggle()"
        >
          {{ texts.edit }}
        </button>
      </div>
      <div class="panel" data-focus-key="panel" [class.open]="open()" [id]="panelId" (keydown.escape)="collapse($event)">
        @if (open()) {
          <div class="field">
            <label class="option-line">
              <input
                type="checkbox"
                [checked]="form().on"
                [attr.aria-invalid]="onRefusal() ? 'true' : null"
                [attr.aria-describedby]="onRefusal() ? onErrorId : null"
                (change)="typedOn($event)"
              />
              <span>{{ texts.on }}</span>
            </label>
            @if (onRefusal(); as refusal) {
              <p class="field-error" [id]="onErrorId"><app-icon name="circle-alert" [size]="16" />{{ refusal }}</p>
            }
          </div>
          <div class="field">
            <label [for]="intervalId">{{ texts.interval }}</label>
            <select
              class="input"
              [id]="intervalId"
              [attr.aria-invalid]="intervalRefusal() ? 'true' : null"
              [attr.aria-describedby]="intervalRefusal() ? intervalErrorId : null"
              (change)="typedInterval($event)"
            >
              @for (option of intervals; track option.minutes) {
                <option [value]="option.minutes" [selected]="option.minutes === form().interval">{{ option.name }}</option>
              }
            </select>
            @if (intervalRefusal(); as refusal) {
              <p class="field-error" [id]="intervalErrorId"><app-icon name="circle-alert" [size]="16" />{{ refusal }}</p>
            }
          </div>
          <fieldset class="field hours">
            <legend>{{ texts.activeHours }}</legend>
            <label class="option-line">
              <input type="checkbox" [checked]="form().allDay" (change)="typedAllDay($event)" />
              <span>{{ texts.allDay }}</span>
            </label>
            @if (!form().allDay) {
              <label [for]="fromId">{{ texts.from }}</label>
              <select
                class="input"
                [id]="fromId"
                [attr.aria-invalid]="hoursRefusal() ? 'true' : null"
                [attr.aria-describedby]="hoursRefusal() ? hoursErrorId : null"
                (change)="typedFrom($event)"
              >
                @for (time of quarterHours; track time) {
                  <option [value]="time" [selected]="time === form().from">{{ time }}</option>
                }
              </select>
              <label [for]="toId">{{ texts.to }}</label>
              <select
                class="input"
                [id]="toId"
                [attr.aria-invalid]="hoursRefusal() ? 'true' : null"
                [attr.aria-describedby]="hoursRefusal() ? hoursErrorId : null"
                (change)="typedTo($event)"
              >
                @for (time of quarterHours; track time) {
                  <option [value]="time" [selected]="time === form().to">{{ time }}</option>
                }
              </select>
            }
            @if (hoursRefusal(); as refusal) {
              <p class="field-error" [id]="hoursErrorId"><app-icon name="circle-alert" [size]="16" />{{ refusal }}</p>
            }
          </fieldset>
          <div class="field">
            <label [for]="checklistId">{{ texts.checklist }}</label>
            <textarea
              class="input"
              rows="6"
              [id]="checklistId"
              [value]="form().checklist"
              [attr.aria-invalid]="checklistRefusal() ? 'true' : null"
              [attr.aria-describedby]="checklistDescribed()"
              (input)="typedChecklist($event)"
            ></textarea>
            <p class="help" [id]="helpId">{{ texts.help }}</p>
            <p class="help" [id]="counterId">{{ counter() }}</p>
            @if (checklistRefusal(); as refusal) {
              <p class="field-error" [id]="checklistErrorId"><app-icon name="circle-alert" [size]="16" />{{ refusal }}</p>
            }
          </div>
          <div class="actions">
            <app-server-button variant="primary" [action]="save" [describedBy]="saveDescribed()">{{ texts.save }}</app-server-button>
          </div>
          @if (line(); as shown) {
            @if (shown.refused) {
              <p class="field-error" [id]="resultId"><app-icon name="circle-alert" [size]="16" />{{ shown.message }}</p>
            } @else {
              <p class="saved" [id]="resultId">{{ shown.message }}</p>
            }
          }
        }
      </div>
      <div class="run" data-focus-key="run">
        <app-server-button variant="secondary" [action]="run" [inactive]="runHeld()" [describedBy]="runDescribed()">{{ texts.run }}</app-server-button>
        @if (runNote(); as note) {
          @if (note.refused) {
            <p class="field-error" [id]="runNoteId"><app-icon name="circle-alert" [size]="16" />{{ note.message }}</p>
          } @else {
            <p class="note" [id]="runNoteId">{{ note.message }}</p>
          }
        }
        @if (runSaved(); as saved) {
          <p class="saved">{{ saved }}</p>
        }
      </div>
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .current {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
      min-width: 0;
    }
    .line,
    .note,
    .help,
    .saved {
      margin: 0;
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
      overflow-wrap: anywhere;
    }
    .parts {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1);
      font-variant-numeric: tabular-nums;
    }
    .help {
      color: var(--ink-muted);
    }
    .change {
      margin-top: var(--space-1);
    }
    .panel {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      min-width: 0;
    }
    .panel.open {
      margin-top: var(--space-2);
    }
    .run {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-2);
      margin-top: var(--space-2);
      min-width: 0;
    }
    .option-line {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-target-min);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      min-width: 0;
      margin: 0;
      padding: 0;
      border: 0;
    }
    .field label:not(.option-line),
    .field legend {
      padding: 0;
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-label-line-height);
    }
    .input {
      box-sizing: border-box;
      width: 100%;
      min-height: var(--text-input-min-height);
      padding: var(--space-2) var(--space-3);
      background: var(--text-input-background);
      color: var(--ink);
      border: var(--text-input-border);
      border-radius: var(--text-input-radius);
      font-family: var(--font-ui);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .input[aria-invalid='true'] {
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
  `,
})
export class HeartbeatCard {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly document = inject(DOCUMENT);
  private readonly popovers = inject(Popovers);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  protected readonly texts = HEARTBEAT_TEXTS;
  protected readonly separator = CHAT_TEXTS.separator;
  protected readonly intervals = INTERVALS;
  protected readonly quarterHours = QUARTER_HOURS;

  /** The ids of this card's elements, which no other card of the page shares. */
  private readonly prefix = `heartbeat-card-${(lastCard += 1)}`;
  protected readonly panelId = `${this.prefix}-panel`;
  protected readonly intervalId = `${this.prefix}-interval`;
  protected readonly fromId = `${this.prefix}-from`;
  protected readonly toId = `${this.prefix}-to`;
  protected readonly checklistId = `${this.prefix}-checklist`;
  protected readonly helpId = `${this.prefix}-help`;
  protected readonly counterId = `${this.prefix}-counter`;
  protected readonly onErrorId = `${this.prefix}-on-error`;
  protected readonly intervalErrorId = `${this.prefix}-interval-error`;
  protected readonly hoursErrorId = `${this.prefix}-hours-error`;
  protected readonly checklistErrorId = `${this.prefix}-checklist-error`;
  protected readonly resultId = `${this.prefix}-result`;
  protected readonly runNoteId = `${this.prefix}-run-note`;

  /** The server's heartbeat, or none before the first answer and after a failed read. */
  protected readonly state = signal<HeartbeatState | undefined>(undefined);
  protected readonly open = signal(false);
  protected readonly form = signal<HeartbeatForm>({ on: false, interval: 30, allDay: false, from: DEFAULT_FROM, to: DEFAULT_TO, checklist: '' });
  /** The refusal that shows beside a field, the line under Save, and the lines under the run button. */
  private readonly fieldLine = signal<FieldLine | undefined>(undefined);
  protected readonly line = signal<Line | undefined>(undefined);
  private readonly runAnswer = signal<Line | undefined>(undefined);
  protected readonly runSaved = signal('');
  /** The answer's availableAt of a 409 cooldown, and the run that the server accepted before the state shows it. */
  private readonly availableAt = signal('');
  private readonly pending = signal<PendingRun | undefined>(undefined);
  /** The clock: the time in ms, renewed every minute and at the end of a cooldown. */
  private readonly clock = signal(Date.now());

  private readonly format = computed<HeartbeatFormat>(() => {
    const now = this.clock();
    return { when: (iso) => pageWhen(iso, now), cost: formatCost, reason: fallbackReasonText };
  });
  protected readonly stateText = computed(() => {
    const state = this.state();
    return state === undefined ? '' : stateLine(state, this.format().when);
  });
  protected readonly last = computed(() => {
    const state = this.state();
    return state === undefined ? undefined : lastLine(state, this.format());
  });
  protected readonly today = computed(() => todayLine(this.state()?.today, formatCost));
  protected readonly counter = computed(() => counterText(this.form().checklist));
  protected readonly onRefusal = computed(() => this.refusal('on'));
  protected readonly intervalRefusal = computed(() => this.refusal('interval'));
  protected readonly hoursRefusal = computed(() => this.refusal('hours'));
  protected readonly checklistRefusal = computed(() => this.refusal('checklist'));
  protected readonly checklistDescribed = computed(() => [this.helpId, this.counterId, ...(this.checklistRefusal() ? [this.checklistErrorId] : [])].join(' '));
  protected readonly saveDescribed = computed(() => (this.line() ? [this.resultId] : []));

  /** Why Run cannot be pressed (the cap, then the missing key, from the live store's conditions), or "". */
  private readonly reason = computed(() => unavailable(this.live.store()));
  /** When the button may be pressed again, in ms: the later of the state's LastRunNowAt plus 120 s, the 409's availableAt and the accepted run's; 0 for none. */
  private readonly cooldownEndMs = computed(() => {
    const state = this.state();
    const pending = this.pending();
    const server = Date.parse(cooldownUntil(state, this.availableAt()));
    const accepted = pending !== undefined && (state?.lastRunNowAt ?? '') === pending.base ? pending.endMs : 0;
    return Math.max(Number.isNaN(server) ? 0 : server, accepted);
  });
  private readonly cooling = computed(() => this.cooldownEndMs() > this.clock());
  protected readonly runHeld = computed(() => this.reason() !== '' || this.cooling());
  /** The one line that describes Run: the unavailable reason, else the cooldown, else the answer to the last press. */
  protected readonly runNote = computed<Line | undefined>(() => {
    const reason = this.reason();
    if (reason !== '') {
      return { message: reason === 'cap' ? HEARTBEAT_TEXTS.unavailableCap : HEARTBEAT_TEXTS.unavailableNoKey, refused: false };
    }
    if (this.cooling()) {
      const time = this.format().when(new Date(this.cooldownEndMs()).toISOString());
      return { message: HEARTBEAT_TEXTS.cooldown.replace('{time}', time), refused: false };
    }
    return this.runAnswer();
  });
  protected readonly runDescribed = computed(() => (this.runNote() ? [this.runNoteId] : []));

  /** The latest heartbeat event of the live store, as a key: the card reads again when it changes. */
  private readonly eventKey = computed(() => {
    const store = this.live.store();
    return store === undefined ? '' : heartbeatReadKey(store);
  });

  private readonly editButton = viewChild<ElementRef<HTMLButtonElement>>('edit');
  private reading: Subscription | undefined;

  constructor() {
    effect(() => {
      this.eventKey();
      untracked(() => this.read());
    });
    effect(() => {
      this.state();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, FOCUS_RULE));
    });
    effect((onCleanup) => {
      const id = globalThis.setInterval(() => this.clock.set(Date.now()), CLOCK_MS);
      onCleanup(() => globalThis.clearInterval(id));
    });
    effect((onCleanup) => {
      const end = this.cooldownEndMs();
      if (end > untracked(() => this.clock())) {
        const id = globalThis.setTimeout(() => this.clock.set(Date.now()), Math.max(end - Date.now(), 0) + 50);
        onCleanup(() => globalThis.clearTimeout(id));
      }
    });
    inject(DestroyRef).onDestroy(() => this.reading?.unsubscribe());
  }

  /** The Save button's call. The server's answer, early or late, shows its line; the button only reports the busy state. */
  protected readonly save = (): Observable<HeartbeatSaved> => {
    this.line.set(undefined);
    this.fieldLine.set(undefined);
    return this.api.saveHeartbeat(saveBody(this.form())).pipe(
      tap({
        next: (saved) => this.saved(saved),
        error: (error: unknown) => this.failed(error),
      }),
    );
  };

  /** The Run button's call: on the online demo, while the shown checklist is the sample, the shown values are saved first (DW-781); then the POST. */
  protected readonly run = (): Observable<unknown> => {
    this.runAnswer.set(undefined);
    this.runSaved.set('');
    const state = this.state();
    const post = this.api.runHeartbeat().pipe(
      tap({
        next: () => this.ran(),
        error: (error: unknown) => this.runFailed(error),
      }),
    );
    if (state === undefined || state.sample !== true) {
      return post;
    }
    const shown: HeartbeatForm = {
      on: state.on === true,
      interval: state.interval ?? 30,
      allDay: (state.from ?? '') === '' && (state.to ?? '') === '',
      from: state.from ?? '',
      to: state.to ?? '',
      checklist: state.checklist,
    };
    return this.api.saveHeartbeat(saveBody(shown)).pipe(
      tap({
        next: (saved) => this.runSaved.set(saved.message),
        error: (error: unknown) => this.runFailed(error),
      }),
      switchMap(() => post),
    );
  };

  /** Opens or closes the disclosure; opening fills the form from the stored values. */
  protected toggle(): void {
    const state = this.state();
    if (!this.open() && state !== undefined) {
      const from = state.from ?? '';
      const to = state.to ?? '';
      this.form.set({
        on: state.on === true,
        interval: state.interval ?? 30,
        allDay: from === '' && to === '',
        from: from === '' ? DEFAULT_FROM : from,
        to: to === '' ? DEFAULT_TO : to,
        checklist: state.checklist,
      });
    }
    this.line.set(undefined);
    this.fieldLine.set(undefined);
    this.open.update((one) => !one);
  }

  /** Esc inside the open disclosure collapses it, stops the event, and moves focus to Edit. */
  protected collapse(event: Event): void {
    if (this.popovers.hasOpen()) {
      return;
    }
    if (!this.open()) {
      return;
    }
    this.open.set(false);
    event.stopPropagation();
    this.editButton()?.nativeElement.focus();
  }

  protected typedOn(event: Event): void {
    this.change({ on: (event.target as HTMLInputElement).checked }, 'on');
  }

  protected typedInterval(event: Event): void {
    this.change({ interval: Number((event.target as HTMLSelectElement).value) }, 'interval');
  }

  protected typedAllDay(event: Event): void {
    this.change({ allDay: (event.target as HTMLInputElement).checked }, 'hours');
  }

  protected typedFrom(event: Event): void {
    this.change({ from: (event.target as HTMLSelectElement).value }, 'hours');
  }

  protected typedTo(event: Event): void {
    this.change({ to: (event.target as HTMLSelectElement).value }, 'hours');
  }

  protected typedChecklist(event: Event): void {
    this.change({ checklist: (event.target as HTMLTextAreaElement).value }, 'checklist');
  }

  /** Puts the changed values in the form, and clears the refusal beside the field and the line under Save. */
  private change(values: Partial<HeartbeatForm>, where: FieldLine['where']): void {
    this.form.update((form) => ({ ...form, ...values }));
    if (this.fieldLine()?.where === where) {
      this.fieldLine.set(undefined);
    }
    this.line.set(undefined);
  }

  private refusal(where: FieldLine['where']): string {
    const refusal = this.fieldLine();
    return refusal !== undefined && refusal.where === where ? refusal.message : '';
  }

  /** Reads the heartbeat again; a read that is still out is dropped, and a failed one leaves the heading alone. */
  private read(): void {
    this.reading?.unsubscribe();
    this.reading = this.api.heartbeat().subscribe({
      next: (heartbeat) => this.state.set(heartbeat),
      error: () => this.state.set(undefined),
    });
  }

  private saved(saved: HeartbeatSaved): void {
    this.line.set({ message: saved.message, refused: false });
    this.read();
  }

  private failed(error: unknown): void {
    const failure = failureOf(error);
    const message = failure.message === '' ? BUSY_NOTICE : failure.message;
    if (failure.where === 'save') {
      this.line.set({ message, refused: true });
      this.read();
    } else {
      this.fieldLine.set({ where: failure.where, message });
    }
  }

  /** The server accepted the run: the button is held for the cooldown until the state shows the run, and the card reads again. */
  private ran(): void {
    this.availableAt.set('');
    this.pending.set({ base: this.state()?.lastRunNowAt ?? '', endMs: Date.now() + RUN_NOW_SECONDS * 1000 });
    this.clock.set(Date.now());
    this.read();
  }

  /** A refused or failed press: a cooldown holds the button to the answer's availableAt; a 5xx, or an answer with no message, shows the busy notice; any other answer shows its message. */
  private runFailed(error: unknown): void {
    const failure = failureOf(error);
    const status = (error as { status?: unknown } | null)?.status;
    if (failure.code === 'cooldown' && failure.availableAt !== '') {
      this.availableAt.set(failure.availableAt);
      this.clock.set(Date.now());
    } else {
      const busy = failure.message === '' || (typeof status === 'number' && status >= 500);
      this.runAnswer.set({ message: busy ? BUSY_NOTICE : failure.message, refused: true });
    }
    this.read();
  }
}
