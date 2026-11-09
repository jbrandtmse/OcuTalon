import { afterNextRender, ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, input, output, signal } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { refusalOf } from './refusal';
import { budgetsBody, isBudgetsDirty, SETTINGS_TEXTS } from './settings-view';

/** The two budget values as the form holds them: the typed text. */
export interface BudgetTexts {
  tokens: string;
  cap: string;
}

/** The id of the error under the button, which the button is described by. */
const FORM_ERROR_ID = 'budgets-error';

/**
 * The Budgets section (Story 18.3; FR-39, AD-20): two text fields, the token budget per decision and the daily cost cap in US dollars, each with its help
 * line, and **Save changes**. A press posts `{DecisionTokenBudget, DailyCostCapUSD}` to POST /v1/settings/budgets through the busy pattern (ServerButton).
 * The server judges the values (Bridge.Settings.Check) and applies them to the next decision:
 *   - 200: the section shows "Saved. Applies within a minute. Recorded in the audit log." and the announcer reads it once; the saved values are the form's
 *     new baseline and the page is told (`saved`); a field edited while the save was pending keeps its value, the form stays dirty and no saved text shows;
 *   - 400 `bad_settings`: each named field shows the field error "Couldn't save. Nothing was changed." linked to it and marked invalid, and the first
 *     of them takes focus; a refusal that names no field shows the error under the button, and the announcer reads it;
 *   - 403: the user is no longer an admin, and the page is told (`denied`); any other failure shows the error under the button, and the announcer reads it.
 * Typing in a field clears its error and the saved text. `dirtyChange` tells the page whether the form differs from its saved values.
 */
@Component({
  selector: 'app-budgets-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="field">
      <label for="budget-tokens">{{ texts.tokens }}</label>
      <input
        type="text"
        inputmode="numeric"
        autocomplete="off"
        class="input"
        id="budget-tokens"
        [class.invalid]="errors().DecisionTokenBudget"
        [attr.aria-invalid]="errors().DecisionTokenBudget ? 'true' : null"
        [attr.aria-describedby]="errors().DecisionTokenBudget ? 'budget-tokens-help budget-tokens-error' : 'budget-tokens-help'"
        [value]="form().tokens"
        (input)="typed('tokens', value($event))"
      />
      <p class="help" id="budget-tokens-help">{{ texts.tokensHelp }}</p>
      @if (errors().DecisionTokenBudget) {
        <p class="field-error" id="budget-tokens-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
      }
    </div>
    <div class="field">
      <label for="budget-cap">{{ texts.cap }}</label>
      <input
        type="text"
        inputmode="decimal"
        autocomplete="off"
        class="input"
        id="budget-cap"
        [class.invalid]="errors().DailyCostCapUSD"
        [attr.aria-invalid]="errors().DailyCostCapUSD ? 'true' : null"
        [attr.aria-describedby]="errors().DailyCostCapUSD ? 'budget-cap-help budget-cap-error' : 'budget-cap-help'"
        [value]="form().cap"
        (input)="typed('cap', value($event))"
      />
      <p class="help" id="budget-cap-help">{{ texts.capHelp }}</p>
      @if (errors().DailyCostCapUSD) {
        <p class="field-error" id="budget-cap-error"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
      }
    </div>
    <div class="actions">
      <app-server-button variant="primary" [action]="save" [describedBy]="described()">{{ saveLabel }}</app-server-button>
    </div>
    @if (formError()) {
      <p class="field-error" [id]="formErrorId"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
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
export class BudgetsSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The values the server holds, as the page loaded them. */
  readonly values = input.required<BudgetTexts>();

  /** The values after a save, for the page to keep. */
  readonly saved = output<BudgetTexts>();

  /** Whether the form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly texts = SETTINGS_TEXTS.budgets;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;
  protected readonly formErrorId = FORM_ERROR_ID;

  /** The typed texts; the saved ones until the user types. */
  protected readonly form = signal<BudgetTexts>({ tokens: '', cap: '' });
  /** The texts that the server holds: the form is dirty when it differs from them. */
  private readonly baseline = signal<BudgetTexts>({ tokens: '', cap: '' });
  protected readonly errors = signal<{ DecisionTokenBudget?: boolean; DailyCostCapUSD?: boolean }>({});
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  protected readonly described = computed<readonly string[]>(() => (this.formError() ? [FORM_ERROR_ID] : []));

  constructor() {
    let started = false;
    effect(() => {
      const values = this.values();
      if (!started) {
        started = true;
        this.form.set({ ...values });
        this.baseline.set({ ...values });
      }
    });
    let last = false;
    effect(() => {
      const dirty = isBudgetsDirty(this.form(), this.baseline());
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
  protected typed(name: 'tokens' | 'cap', text: string): void {
    this.form.update((one) => ({ ...one, [name]: text }));
    this.errors.update((one) => ({ ...one, [name === 'tokens' ? 'DecisionTokenBudget' : 'DailyCostCapUSD']: false }));
    this.formError.set(false);
    this.done.set(false);
  }

  /** Save changes: posts the two values; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.formError.set(false);
    this.done.set(false);
    this.errors.set({});
    const sent = this.form();
    return this.api.saveSettings('budgets', budgetsBody(sent.tokens, sent.cap)).pipe(
      tap({
        next: () => this.succeeded(sent),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: BudgetTexts): void {
    const edited = isBudgetsDirty(this.form(), sent);
    this.baseline.set(sent);
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
    this.saved.emit(sent);
  }

  private refused(error: unknown): void {
    const order = ['DecisionTokenBudget', 'DailyCostCapUSD'];
    const refusal = refusalOf(error, order);
    if (refusal.kind === 'denied') {
      this.denied.emit();
      return;
    }
    if (refusal.kind === 'form') {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    this.errors.set({ DecisionTokenBudget: refusal.fields.includes('DecisionTokenBudget'), DailyCostCapUSD: refusal.fields.includes('DailyCostCapUSD') });
    const target = refusal.fields.includes('DecisionTokenBudget') ? '#budget-tokens' : '#budget-cap';
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(target)?.focus(), { injector: this.injector });
  }
}
