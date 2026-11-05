import { DOCUMENT } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, DestroyRef, effect, ElementRef, inject, Injector, signal, untracked, viewChild } from '@angular/core';
import { type Observable, type Subscription, tap } from 'rxjs';

import { ApiClient } from '../../api/api-client';
import type { PersonaSaved, PersonaState } from '../../api/persona-types';
import { Icon } from '../../icon/icon';
import { LiveState } from '../../live/live-state';
import { type FocusRule, keepFocus } from '../../shared/focus-rule';
import { Layout } from '../../shared/layout';
import { Popovers } from '../../shared/popover';
import { BUSY_NOTICE, ServerButton } from '../../shared/server-button';
import { pendingApprovals } from '../rail-view';
import {
  APPROVALS_HEADING_ID,
  counterText,
  failureOf,
  languageHelpText,
  optionsFor,
  PERSONA_HEADING_ID,
  PERSONA_TEXTS,
  presetOf,
  saveBody,
} from './persona-card-view';

/** The count of the cards that have been made, which gives each one's ids a prefix of its own. */
let lastCard = 0;

/** The attribute that names the card's parts for its focus rule: the current choice, the pending line and the disclosure. */
const FOCUS_KEY = 'data-focus-key';

/**
 * Where focus goes when the card's own read removes the element that holds it (UX-DR131): the pending line that leaves with its
 * request, or the whole card after a failed read. Focus then goes to the Persona heading, as the rail's rule does for a row that leaves.
 */
const FOCUS_RULE: FocusRule = {
  item: `[${FOCUS_KEY}]`,
  keyOf: (item) => item.getAttribute(FOCUS_KEY) ?? '',
  whenGone: ({ host }) => host.ownerDocument.getElementById(PERSONA_HEADING_ID),
};

/** The line under Save or under a field: the text, and whether it is a refusal. */
interface Line {
  message: string;
  refused: boolean;
}

/** A refusal that shows beside a field. */
interface FieldLine {
  where: 'language' | 'custom';
  message: string;
}

/**
 * The Persona card (Story 40.4; FR-67, FR-68, FR-70, UX-DR117, AD-29): the body of the rail's Persona section. It reads `GET /api/v1/persona`
 * when it is made and whenever the set of pending approval requests in the live store changes, so that the pending line comes and goes with
 * the request. While that read has not answered, or failed, it shows nothing (the section's heading only) and tries again on the next change.
 * - Collapsed, it shows the current preset's name and description (the row title and detail of the rail's rows), the pending line when
 *   a proposal waits ("OcuTalon suggested a change. ..." as a link-styled button, whose press moves focus to the request's card in the chat
 *   when it is drawn, else to the Approval requests heading), and Change.
 * - Change is a disclosure (aria-expanded, aria-controls). Open, it shows the intro, on the online demo the demo note, the preset radio
 *   group (named by the section heading, described by the intro; each radio described by its description), under Another language the
 *   Language field, under Your own words (a local install only) the text area with its counter, and Save. Esc inside the open disclosure
 *   collapses it and moves focus to Change, unless a popover is open (Popovers.hasOpen), which takes the Esc alone; the event stops there,
 *   so the drawer around the rail does not close with it.
 * - Save is a ServerButton (busy, the 10 second notice). Its PUT carries only the values that the chosen preset uses. The server's message
 *   shows under Save; a `bad_language` or `bad_custom` refusal shows beside its field instead, marked aria-invalid and linked through
 *   aria-describedby; any other failure shows its message under Save, or the busy notice when it has none, and the card reads again. The
 *   page holds no copy of a message of the server.
 * The card announces nothing and is no live region. It moves focus only for the user's own press (Esc, and the pending link), and through
 * the page's focus rule when its own read removes the focused element (the pending line, or the card after a failed read): to the Persona
 * heading. Every text is bound by interpolation from persona-card-view.ts or is the server's.
 */
@Component({
  selector: 'app-persona-card',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (state(); as persona) {
      <div class="current" data-focus-key="current">
        @if (current(); as preset) {
          <span class="current-name">{{ preset.name }}</span>
          <span class="current-description">{{ preset.description }}</span>
        }
        @if (persona.pendingRef !== '') {
          <button type="button" class="pending" data-focus-key="pending" (click)="jump(persona.pendingRef)">{{ texts.pending }}</button>
        }
        <button
          #change
          type="button"
          class="button button-ghost change"
          [attr.aria-expanded]="open()"
          [attr.aria-controls]="panelId"
          (click)="toggle()"
        >
          {{ texts.change }}
        </button>
      </div>
      <div class="panel" data-focus-key="panel" [class.open]="open()" [id]="panelId" (keydown.escape)="collapse($event)">
        @if (open()) {
          <p class="note" [id]="introId">{{ texts.intro }}</p>
          @if (!persona.customOffered) {
            <p class="note">{{ texts.demoNote }}</p>
          }
          <div class="options" role="radiogroup" [attr.aria-labelledby]="headingId" [attr.aria-describedby]="introId">
            @for (option of options(); track option.id) {
              <div class="option">
                <label class="option-line">
                  <input
                    type="radio"
                    [name]="groupName"
                    [value]="option.id"
                    [checked]="choice() === option.id"
                    [attr.aria-describedby]="descriptionId(option.id)"
                    (change)="choose(option.id)"
                  />
                  <span>{{ option.name }}</span>
                </label>
                <span class="option-description" [id]="descriptionId(option.id)">{{ option.description }}</span>
                @if (option.id === 'language' && choice() === 'language') {
                  <div class="field">
                    <label [for]="languageId">{{ texts.language }}</label>
                    <input
                      type="text"
                      class="input"
                      autocomplete="off"
                      [id]="languageId"
                      [value]="language()"
                      [attr.aria-invalid]="languageRefusal() ? 'true' : null"
                      [attr.aria-describedby]="languageDescribed()"
                      (input)="typedLanguage($event)"
                    />
                    <p class="help" [id]="languageHelpId">{{ languageHelp }}</p>
                    @if (languageRefusal(); as refusal) {
                      <p class="field-error" [id]="languageErrorId"><app-icon name="circle-alert" [size]="16" />{{ refusal }}</p>
                    }
                  </div>
                }
                @if (option.id === 'custom' && choice() === 'custom') {
                  <div class="field">
                    <label [for]="customId">{{ texts.customLabel }}</label>
                    <textarea
                      class="input"
                      rows="5"
                      [id]="customId"
                      [value]="custom()"
                      [attr.aria-invalid]="customRefusal() ? 'true' : null"
                      [attr.aria-describedby]="customDescribed()"
                      (input)="typedCustom($event)"
                    ></textarea>
                    <p class="help" [id]="customHelpId">{{ texts.customAllClear }}</p>
                    <p class="help" [id]="counterId">{{ counter() }}</p>
                    @if (customRefusal(); as refusal) {
                      <p class="field-error" [id]="customErrorId"><app-icon name="circle-alert" [size]="16" />{{ refusal }}</p>
                    }
                  </div>
                }
              </div>
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
      min-width: 0;
    }
    .current-name {
      color: var(--ink);
      font-size: var(--type-body-strong-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-strong-line-height);
      overflow-wrap: anywhere;
    }
    .current-description {
      color: var(--ink);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .pending {
      display: inline;
      min-height: var(--space-target-min);
      margin: 0;
      padding: 0;
      border: 0;
      background: none;
      color: var(--action-ink);
      font-family: inherit;
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
      text-align: left;
      text-decoration: underline;
      cursor: pointer;
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
    .note,
    .help,
    .saved {
      margin: 0;
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .help {
      color: var(--ink-muted);
    }
    .options {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
    }
    .option {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
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
    .option-description {
      padding-left: var(--space-5);
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      padding-left: var(--space-5);
    }
    .field label {
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
export class PersonaCard {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly layout = inject(Layout);
  private readonly document = inject(DOCUMENT);
  private readonly popovers = inject(Popovers);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);

  protected readonly texts = PERSONA_TEXTS;
  protected readonly headingId = PERSONA_HEADING_ID;
  protected readonly languageHelp = languageHelpText();

  /** The ids of this card's elements, which no other card of the page shares. */
  private readonly prefix = `persona-card-${(lastCard += 1)}`;
  protected readonly panelId = `${this.prefix}-panel`;
  protected readonly introId = `${this.prefix}-intro`;
  protected readonly groupName = `${this.prefix}-preset`;
  protected readonly languageId = `${this.prefix}-language`;
  protected readonly languageHelpId = `${this.prefix}-language-help`;
  protected readonly languageErrorId = `${this.prefix}-language-error`;
  protected readonly customId = `${this.prefix}-custom`;
  protected readonly customHelpId = `${this.prefix}-custom-help`;
  protected readonly counterId = `${this.prefix}-counter`;
  protected readonly customErrorId = `${this.prefix}-custom-error`;
  protected readonly resultId = `${this.prefix}-result`;
  protected readonly descriptionId = (preset: string): string => `${this.prefix}-description-${preset}`;

  /** The server's persona, or none before the first answer and after a failed read. */
  protected readonly state = signal<PersonaState | undefined>(undefined);
  protected readonly open = signal(false);
  /** The form: the chosen preset id and the two fields' values. */
  protected readonly choice = signal('');
  protected readonly language = signal('');
  protected readonly custom = signal('');
  /** The refusal that shows beside a field, and the line under Save. */
  private readonly fieldLine = signal<FieldLine | undefined>(undefined);
  protected readonly line = signal<Line | undefined>(undefined);

  protected readonly current = computed(() => presetOf(this.state()?.preset ?? ''));
  protected readonly options = computed(() => optionsFor(this.state()?.customOffered ?? false));
  protected readonly counter = computed(() => counterText(this.custom()));
  protected readonly languageRefusal = computed(() => this.refusal('language'));
  protected readonly customRefusal = computed(() => this.refusal('custom'));
  protected readonly languageDescribed = computed(() => [this.languageHelpId, ...(this.languageRefusal() ? [this.languageErrorId] : [])].join(' '));
  protected readonly customDescribed = computed(() =>
    [this.customHelpId, this.counterId, ...(this.customRefusal() ? [this.customErrorId] : [])].join(' '),
  );
  protected readonly saveDescribed = computed(() => (this.line() ? [this.resultId] : []));

  /** The Refs of the pending approval requests, joined: the card reads again when they change. */
  private readonly pendingRefs = computed(() => {
    const store = this.live.store();
    return store === undefined ? '' : pendingApprovals(store).map((approval) => approval.ref ?? '').join('\n');
  });

  private readonly changeButton = viewChild<ElementRef<HTMLButtonElement>>('change');
  private reading: Subscription | undefined;

  constructor() {
    effect(() => {
      this.pendingRefs();
      untracked(() => this.read());
    });
    effect(() => {
      this.state();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, FOCUS_RULE));
    });
    inject(DestroyRef).onDestroy(() => this.reading?.unsubscribe());
  }

  /** The Save button's call. The server's answer, early or late, shows its line; the button only reports the busy state. */
  protected readonly save = (): Observable<PersonaSaved> => {
    this.line.set(undefined);
    this.fieldLine.set(undefined);
    return this.api.savePersona(saveBody(this.choice(), this.language(), this.custom())).pipe(
      tap({
        next: (saved) => this.saved(saved),
        error: (error: unknown) => this.failed(error),
      }),
    );
  };

  /** Opens or closes the disclosure; opening fills the form from the stored persona. */
  protected toggle(): void {
    const persona = this.state();
    if (!this.open() && persona !== undefined) {
      this.choice.set(persona.preset);
      this.language.set(persona.language);
      this.custom.set(persona.custom);
    }
    this.line.set(undefined);
    this.fieldLine.set(undefined);
    this.open.update((one) => !one);
  }

  /** Esc inside the open disclosure collapses it, stops the event, and moves focus to Change. */
  protected collapse(event: Event): void {
    if (this.popovers.hasOpen()) {
      return;
    }
    if (!this.open()) {
      return;
    }
    this.open.set(false);
    event.stopPropagation();
    this.changeButton()?.nativeElement.focus();
  }

  protected choose(preset: string): void {
    this.choice.set(preset);
    this.fieldLine.set(undefined);
    this.line.set(undefined);
  }

  protected typedLanguage(event: Event): void {
    this.language.set((event.target as HTMLInputElement).value);
    this.clearRefusal('language');
    this.line.set(undefined);
  }

  protected typedCustom(event: Event): void {
    this.custom.set((event.target as HTMLTextAreaElement).value);
    this.clearRefusal('custom');
    this.line.set(undefined);
  }

  /** The press of the pending line: the user's own move to the request's card in the chat, else to the Approval requests heading. */
  protected jump(ref: string): void {
    const card = `app-chat-panel [data-part="approval"][data-key="${CSS.escape(ref)}"]`;
    this.layout.focusRegion(this.document.querySelector(card) === null ? `#${APPROVALS_HEADING_ID}` : card);
  }

  private refusal(where: FieldLine['where']): string {
    const refusal = this.fieldLine();
    return refusal !== undefined && refusal.where === where ? refusal.message : '';
  }

  private clearRefusal(where: FieldLine['where']): void {
    if (this.fieldLine()?.where === where) {
      this.fieldLine.set(undefined);
    }
  }

  /** Reads the persona again; a read that is still out is dropped, and a failed one leaves the heading alone. */
  private read(): void {
    this.reading?.unsubscribe();
    this.reading = this.api.persona().subscribe({
      next: (persona) => this.state.set(persona),
      error: () => this.state.set(undefined),
    });
  }

  private saved(saved: PersonaSaved): void {
    this.reading?.unsubscribe();
    this.state.update((persona) => persona && { ...persona, preset: saved.preset, language: saved.language, custom: saved.custom });
    this.line.set({ message: saved.message, refused: false });
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
}
