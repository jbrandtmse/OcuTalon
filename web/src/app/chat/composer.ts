import { ChangeDetectionStrategy, Component, computed, DestroyRef, ElementRef, inject, viewChild } from '@angular/core';

import { allowanceReason } from '../banners/banner-stack';
import { AllowanceState } from '../live/allowance-state';
import { ChatOutbox } from './chat-outbox';
import { CHAT_TEXTS } from './chat-view';

/** The most lines the field shows before it scrolls. */
const MAX_LINES = 5;

/** The id of the reason that the field and Send are described by while the message allowance is used up; the Try it yourself chips are described by it too. */
export const COMPOSER_REASON_ID = 'composer-allowance-reason';

/**
 * The composer (UX-DR68, UX-DR125): a text area labelled "Message OcuTalon" by a visually hidden label, so the name holds while
 * text is typed, and a Send button. Enter sends, except while an IME composition is open; Shift+Enter adds a line. The text is
 * trimmed at both ends and its inner line breaks are kept; empty text sends nothing. The field grows with its content, by script,
 * up to five lines, then scrolls. Its height is a count of lines in line-height units (lh) plus its padding, so a change of the text
 * size keeps the lines it holds in view with no keystroke; the lines are counted again at the next input. It is never disabled (a turn
 * running does not stop it: each message becomes its own turn), but while the session's message allowance is used up (Story 16.9;
 * AllowanceState.active) the field and Send are aria-disabled, not disabled, so they stay focusable: the reason, which is the allowance
 * banner's own text, is visible above the field, in the paragraph #composer-allowance-reason that both controls are described by. Send
 * and Enter then do nothing, and the typed text stays in the field. At the time the allowance returns the reason and the markings clear.
 * After a send the field is empty, shrunk and focused. It takes no focus on its own.
 * On the online demo a message that the server refused with 503 comes back (Story 16.5): the outbox offers its text and the field takes
 * it only while it is empty or blank, never moving focus; a field that holds other text keeps it.
 */
@Component({
  selector: 'app-composer',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (reason(); as text) {
      <p class="reason" [id]="reasonId">{{ text }}</p>
    }
    <div class="composer">
      <label class="visually-hidden" for="composer-field">{{ texts.composerLabel }}</label>
      <textarea
        #field
        id="composer-field"
        class="field"
        rows="1"
        [placeholder]="texts.composerPlaceholder"
        [attr.aria-disabled]="reason() ? 'true' : null"
        [attr.aria-describedby]="reason() ? reasonId : null"
        (keydown)="onKey($event)"
        (input)="grow()"
      ></textarea>
      <button
        type="button"
        class="button button-primary"
        [attr.aria-disabled]="reason() ? 'true' : null"
        [attr.aria-describedby]="reason() ? reasonId : null"
        (click)="send()"
      >{{ texts.send }}</button>
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .composer {
      display: flex;
      align-items: flex-end;
      gap: var(--space-2);
      padding: var(--space-2) var(--space-2) var(--space-2) var(--space-3);
      background: var(--composer-background);
      border: var(--composer-border);
      border-radius: var(--composer-radius);
    }
    .field {
      flex: 1;
      min-width: 0;
      box-sizing: border-box;
      margin: 0;
      padding: 6px 0;
      border: 0;
      background: transparent;
      color: var(--ink);
      font-family: var(--font-ui);
      font-size: var(--composer-typography-font-size);
      font-weight: var(--composer-typography-font-weight);
      line-height: var(--composer-typography-line-height);
      resize: none;
      overflow-y: auto;
    }
    .field::placeholder {
      color: var(--composer-placeholder);
      opacity: 1;
    }
    .reason {
      margin: 0 0 var(--space-2);
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
  `,
})
export class Composer {
  private readonly outbox = inject(ChatOutbox);
  private readonly allowance = inject(AllowanceState);
  private readonly field = viewChild.required<ElementRef<HTMLTextAreaElement>>('field');

  protected readonly texts = CHAT_TEXTS;

  /** The id of the reason that the field and Send are described by while the message allowance is used up. */
  protected readonly reasonId = COMPOSER_REASON_ID;

  /** The reason: the allowance banner's text while the allowance is used up, else empty. */
  protected readonly reason = computed(() => {
    const window = this.allowance.active();
    return window === undefined ? '' : allowanceReason(window);
  });

  constructor() {
    inject(DestroyRef).onDestroy(this.outbox.takeBackTo((text) => this.takeBack(text)));
  }

  /** Puts a refused message's text back into the field when the field is empty or blank, without a focus; false when the field holds text. */
  private takeBack(text: string): boolean {
    const field = this.field().nativeElement;
    if (field.value.trim() !== '') {
      return false;
    }
    field.value = text;
    this.grow();
    return true;
  }

  /** Enter sends; Shift+Enter, and Enter while an IME composition is open, do not. */
  protected onKey(event: KeyboardEvent): void {
    if (event.key !== 'Enter' || event.shiftKey || event.isComposing || event.keyCode === 229) {
      return;
    }
    event.preventDefault();
    this.send();
  }

  /** Sends the field's text, then empties, shrinks and focuses the field; empty text sends nothing, and nothing is sent while the allowance is used up (the text stays). */
  protected send(): void {
    if (this.allowance.active() !== undefined) {
      return;
    }
    const field = this.field().nativeElement;
    if (!this.outbox.send(field.value)) {
      return;
    }
    field.value = '';
    this.grow();
    field.focus();
  }

  /** Sizes the field to its content: the lines it holds, from one to MAX_LINES, as lh units plus its padding. */
  protected grow(): void {
    const field = this.field().nativeElement;
    const style = getComputedStyle(field);
    const padding = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
    field.style.height = 'auto';
    const lines = Math.round((field.scrollHeight - padding) / parseFloat(style.lineHeight));
    field.style.height = `calc(${Math.min(Math.max(lines, 1), MAX_LINES)} * 1lh + ${padding}px)`;
  }
}
