import { afterNextRender, ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, input, output, signal } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { AgentModels, Prices, ProviderRow } from '../api/api-types';
import { fallbackReasonText } from '../chat/decision-strip';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { refusalOf } from './refusal';
import {
  isModelsDirty,
  MODEL_AGENTS,
  modelOptions,
  modelsBody,
  modelsFieldNames,
  type ModelsForm,
  modelsFormOf,
  modelsView,
  type ProviderChoice,
  PRICE_KEYS,
  secondOptions,
  SETTINGS_TEXTS,
  testResultText,
} from './settings-view';

/** The id of the error under the button, which the button is described by. */
const FORM_ERROR_ID = 'models-error';

/** The id of the prices' help line. */
const PRICES_HELP_ID = 'models-prices-help';

/** An id part from a model name: the characters of an id only. */
function slug(text: string): string {
  return text.replace(/[^A-Za-z0-9_-]/g, '-');
}

/**
 * The Models section (Story 18.3; FR-39, AD-7, AD-19): one group per agent ("Triage agent", "Diagnosis agent", "Chat agent") with a Provider choice, a Model select,
 * a Second model select and a **Test** button with the line that its answer leaves, then the Prices of each listed model, then one **Save changes**.
 *   - Only the providers marked supported are listed. A provider whose key is not set stays focusable with `aria-disabled`, described by its reason
 *     ("No key set. Add {variable} to .env."), cannot be picked, and its models cannot be chosen. The page shows key variable names only.
 *   - **Test** posts `{agent}` to POST /v1/settings/models/test through the busy pattern (ServerButton) and shows "Answered in {seconds} s" or "Didn't answer:
 *     {reason}" under it; the announcer reads the line once. It tests the agent's saved model. A failed call shows "Couldn't run the test. Try again."; a 403 tells the page (`denied`).
 *   - **Save changes** posts `{agents, prices}` to POST /v1/settings/models (modelsBody). The server drops what is unchanged and judges the rest:
 *     - 200: "Saved. Applies within a minute. Recorded in the audit log." is shown and read once; the saved form is the new baseline and the page is told (`saved`); the Test line
 *       of an agent whose provider or model changed is cleared, since it described the model before;
 *       a choice made while the save was pending keeps its value, the form stays dirty and no saved text shows;
 *     - 400 `bad_settings`: each named field (an agent, "<Agent>.second" or "prices.<model>") shows the field error "Couldn't save. Nothing was changed.", linked to
 *       it and marked invalid, and the first takes focus; a refusal that names no field of the page shows the error under the button, and the announcer reads it;
 *     - 403: the page is told (`denied`); any other failure shows the error under the button, and the announcer reads it.
 * Choosing or typing clears the field's error and the saved text. `dirtyChange` tells the page whether the form differs from its saved values.
 */
@Component({
  selector: 'app-models-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <p class="help" id="models-applies">{{ texts.applies }}</p>
    @for (agent of agents; track agent.name) {
      <fieldset class="group" [attr.data-agent]="agent.name">
        <legend>{{ agent.label }}</legend>
        <div class="field">
          <span class="label" [id]="agent.id + '-provider-label'">{{ texts.provider }}</span>
          <div class="radios" role="radiogroup" [attr.aria-labelledby]="agent.id + '-provider-label'">
            @for (choice of view(); track choice.provider) {
              <label class="radio">
                <input
                  type="radio"
                  [name]="agent.id + '-provider'"
                  [value]="choice.provider"
                  [checked]="form().agents[agent.name].provider === choice.provider"
                  [attr.aria-disabled]="choice.choosable ? null : 'true'"
                  [attr.aria-describedby]="choice.choosable ? null : agent.id + '-' + choice.provider + '-reason'"
                  (click)="pickProvider(agent.name, choice, $event)"
                />
                {{ choice.label }}
              </label>
              @if (!choice.choosable) {
                <p class="help" [id]="agent.id + '-' + choice.provider + '-reason'">{{ choice.reason }}</p>
              }
            }
          </div>
        </div>
        <div class="field">
          <label [for]="agent.id + '-model'">{{ texts.model }}</label>
          <select
            class="input"
            [id]="agent.id + '-model'"
            [class.invalid]="errors()[agent.name]"
            [attr.aria-invalid]="errors()[agent.name] ? 'true' : null"
            [attr.aria-describedby]="errors()[agent.name] ? agent.id + '-model-error' : null"
            (change)="pickModel(agent.name, $event)"
          >
            @for (option of modelChoices(agent.name); track option.value) {
              <option [value]="option.value" [selected]="option.value === form().agents[agent.name].model" [disabled]="!option.choosable">{{ option.label }}</option>
            }
          </select>
          @if (errors()[agent.name]) {
            <p class="field-error" [id]="agent.id + '-model-error'"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
          }
        </div>
        <div class="field">
          <label [for]="agent.id + '-second'">{{ texts.secondModel }}</label>
          <select
            class="input"
            [id]="agent.id + '-second'"
            [class.invalid]="errors()[agent.name + '.second']"
            [attr.aria-invalid]="errors()[agent.name + '.second'] ? 'true' : null"
            [attr.aria-describedby]="errors()[agent.name + '.second'] ? agent.id + '-second-help ' + agent.id + '-second-error' : agent.id + '-second-help'"
            (change)="pickSecond(agent.name, $event)"
          >
            @for (option of secondChoices(agent.name); track option.value) {
              <option [value]="option.value" [selected]="option.value === form().agents[agent.name].second" [disabled]="!option.choosable">{{ option.label }}</option>
            }
          </select>
          <p class="help" [id]="agent.id + '-second-help'">{{ texts.secondHelp }}</p>
          @if (errors()[agent.name + '.second']) {
            <p class="field-error" [id]="agent.id + '-second-error'"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
          }
        </div>
        <div class="test">
          <app-server-button variant="secondary" [action]="tests[agent.name]" [describedBy]="[agent.id + '-test-help']">{{ texts.test }}</app-server-button>
          @if (results()[agent.name]; as line) {
            <p class="test-result" [attr.data-test-result]="agent.name">{{ line }}</p>
          }
        </div>
        <p class="help" [id]="agent.id + '-test-help'">{{ texts.testHelp }}</p>
      </fieldset>
    }
    @if (priceModels().length > 0) {
      <fieldset class="group">
        <legend>{{ texts.prices }}</legend>
        <p class="help" [id]="pricesHelpId">{{ texts.pricesHelp }}</p>
        @for (model of priceModels(); track model) {
          <fieldset class="group inner" [attr.data-prices]="model">
            <legend>{{ model }}</legend>
            @for (price of priceKeys; track price.key) {
              <div class="field">
                <label [for]="priceId(model, price.key)">{{ price.label }}</label>
                <input
                  type="text"
                  inputmode="decimal"
                  autocomplete="off"
                  class="input"
                  [id]="priceId(model, price.key)"
                  [class.invalid]="errors()['prices.' + model]"
                  [attr.aria-invalid]="errors()['prices.' + model] ? 'true' : null"
                  [attr.aria-describedby]="errors()['prices.' + model] ? pricesHelpId + ' ' + priceErrorId(model) : pricesHelpId"
                  [value]="form().prices[model][price.key]"
                  (input)="typedPrice(model, price.key, value($event))"
                />
              </div>
            }
            @if (errors()['prices.' + model]) {
              <p class="field-error" [id]="priceErrorId(model)"><app-icon name="circle-alert" [size]="16" />{{ failed }}</p>
            }
          </fieldset>
        }
      </fieldset>
    }
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
      max-width: 560px;
    }
    .group {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      margin: 0;
      padding: var(--space-3) var(--space-4);
      border: 1px solid var(--border);
      border-radius: var(--rounded-sm);
    }
    .group.inner {
      padding: var(--space-2) var(--space-3);
    }
    legend {
      padding: 0 var(--space-1);
      font-weight: 600;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .radios {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .radio {
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
    .test {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      gap: var(--space-3);
    }
    .test-result {
      margin: 0;
      align-self: center;
      color: var(--ink);
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
export class ModelsSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  /** The model of each agent, as the page loaded it. */
  readonly agentModels = input<Readonly<Record<string, AgentModels>> | undefined>(undefined);

  /** The prices of the listed models, as the page loaded them. */
  readonly pricesIn = input<Readonly<Prices> | undefined>(undefined);

  /** The provider table's rows (the key variable names and whether each key is set; never a key). */
  readonly providers = input.required<readonly ProviderRow[]>();

  /** The saved form after a save, for the page to keep. */
  readonly saved = output<ModelsForm>();

  /** Whether the form differs from its saved values. */
  readonly dirtyChange = output<boolean>();

  /** The user is no longer an admin. */
  readonly denied = output<void>();

  protected readonly texts = SETTINGS_TEXTS.models;
  protected readonly failed = SETTINGS_TEXTS.failed;
  protected readonly savedText = SETTINGS_TEXTS.saved;
  protected readonly saveLabel = SETTINGS_TEXTS.save;
  protected readonly formErrorId = FORM_ERROR_ID;
  protected readonly pricesHelpId = PRICES_HELP_ID;
  protected readonly priceKeys = PRICE_KEYS;
  protected readonly agents = MODEL_AGENTS.map((name) => ({ name, id: name.toLowerCase(), label: SETTINGS_TEXTS.models.agents[name] }));

  /** The supported providers, each choosable only while its key is set. */
  protected readonly view = computed<ProviderChoice[]>(() => modelsView(this.providers()));

  /** The form; the server's values until the user chooses or types. */
  protected readonly form = signal<ModelsForm>(modelsFormOf(undefined, undefined));
  /** The form that the server holds: the form is dirty when it differs from it. */
  private readonly baseline = signal<ModelsForm>(this.form());
  /** The refused fields, by name (an agent, "<Agent>.second" or "prices.<model>"). */
  protected readonly errors = signal<Record<string, boolean>>({});
  protected readonly formError = signal(false);
  protected readonly done = signal(false);
  /** The line under each Test button, by agent. */
  protected readonly results = signal<Record<string, string>>({});
  protected readonly described = computed<readonly string[]>(() => (this.formError() ? [FORM_ERROR_ID] : []));
  protected readonly priceModels = computed(() => Object.keys(this.form().prices));

  /** The Test action of each agent. */
  protected readonly tests: Record<string, () => Observable<unknown>> = Object.fromEntries(MODEL_AGENTS.map((name) => [name, () => this.runTest(name)]));

  constructor() {
    let started = false;
    effect(() => {
      const form = modelsFormOf(this.agentModels(), this.pricesIn());
      if (!started) {
        started = true;
        this.form.set(form);
        this.baseline.set(form);
      }
    });
    let last = false;
    effect(() => {
      const dirty = isModelsDirty(this.form(), this.baseline());
      if (dirty !== last) {
        last = dirty;
        this.dirtyChange.emit(dirty);
      }
    });
  }

  protected value(event: Event): string {
    return (event.target as HTMLInputElement).value;
  }

  protected modelChoices(agent: string) {
    const one = this.form().agents[agent];
    return modelOptions(this.view(), one.provider, one.model);
  }

  protected secondChoices(agent: string) {
    return secondOptions(this.view(), this.form().agents[agent].second);
  }

  protected priceId(model: string, key: string): string {
    return `price-${slug(model)}-${key}`;
  }

  protected priceErrorId(model: string): string {
    return `price-${slug(model)}-error`;
  }

  /** A choice or an edit clears the field's error and the saved text. */
  private touched(field: string): void {
    if (this.errors()[field]) {
      this.errors.update((one) => ({ ...one, [field]: false }));
    }
    this.formError.set(false);
    this.done.set(false);
  }

  /** Picks a provider: one without a key cannot be picked. The model stays when the provider lists it, else it becomes the provider's default. */
  protected pickProvider(agent: string, choice: ProviderChoice, event: Event): void {
    if (!choice.choosable) {
      event.preventDefault();
      return;
    }
    this.form.update((form) => {
      const one = form.agents[agent];
      const model = choice.models.includes(one.model) ? one.model : choice.defaultModel;
      return { ...form, agents: { ...form.agents, [agent]: { ...one, provider: choice.provider, model } } };
    });
    this.touched(agent);
  }

  protected pickModel(agent: string, event: Event): void {
    const model = (event.target as HTMLSelectElement).value;
    this.form.update((form) => ({ ...form, agents: { ...form.agents, [agent]: { ...form.agents[agent], model } } }));
    this.touched(agent);
  }

  protected pickSecond(agent: string, event: Event): void {
    const second = (event.target as HTMLSelectElement).value;
    this.form.update((form) => ({ ...form, agents: { ...form.agents, [agent]: { ...form.agents[agent], second } } }));
    this.touched(`${agent}.second`);
  }

  protected typedPrice(model: string, key: string, text: string): void {
    this.form.update((form) => ({ ...form, prices: { ...form.prices, [model]: { ...form.prices[model], [key]: text } } }));
    this.touched(`prices.${model}`);
  }

  /** Test: one short request to the agent's saved model; the answer decides the line under the button. */
  private runTest(agent: string): Observable<unknown> {
    this.results.update(({ [agent]: _gone, ...rest }) => rest);
    return this.api.testModel(agent).pipe(
      tap({
        next: (answer) => this.showResult(agent, testResultText(answer, fallbackReasonText)),
        error: (error: unknown) => {
          if (refusalOf(error, []).kind === 'denied') {
            this.denied.emit();
            return;
          }
          this.showResult(agent, SETTINGS_TEXTS.models.testFailed);
        },
      }),
    );
  }

  private showResult(agent: string, text: string): void {
    this.results.update((one) => ({ ...one, [agent]: text }));
    this.announcer.announce(text);
  }

  /** Save changes: posts the agents and the prices; the answer decides what the section shows. */
  protected readonly save = (): Observable<unknown> => {
    this.formError.set(false);
    this.done.set(false);
    this.errors.set({});
    const sent = this.form();
    return this.api.saveSettings('models', modelsBody(sent)).pipe(
      tap({
        next: () => this.succeeded(sent),
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  private succeeded(sent: ModelsForm): void {
    const edited = isModelsDirty(this.form(), sent);
    const was = this.baseline();
    const moved: string[] = MODEL_AGENTS.filter((name) => was.agents[name].provider !== sent.agents[name].provider || was.agents[name].model !== sent.agents[name].model);
    if (moved.length > 0) {
      this.results.update((one) => Object.fromEntries(Object.entries(one).filter(([name]) => !moved.includes(name))));
    }
    this.baseline.set(sent);
    this.done.set(!edited);
    if (!edited) {
      this.announcer.announce(SETTINGS_TEXTS.saved);
    }
    this.saved.emit(sent);
  }

  private refused(error: unknown): void {
    const known = modelsFieldNames(this.priceModels());
    const refusal = refusalOf(error, known);
    if (refusal.kind === 'denied') {
      this.denied.emit();
      return;
    }
    if (refusal.kind === 'form') {
      this.formError.set(true);
      this.announcer.announce(SETTINGS_TEXTS.failed);
      return;
    }
    this.errors.set(Object.fromEntries(refusal.fields.map((name) => [name, true])));
    const first = refusal.fields[0] ?? '';
    const target = first.startsWith('prices.')
      ? `#${this.priceId(first.slice('prices.'.length), PRICE_KEYS[0].key)}`
      : first.endsWith('.second')
        ? `#${first.slice(0, -'.second'.length).toLowerCase()}-second`
        : `#${first.toLowerCase()}-model`;
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(target)?.focus(), { injector: this.injector });
  }
}
