import { ChangeDetectionStrategy, Component, ElementRef, inject, viewChild } from '@angular/core';

import { ChatOutbox } from './chat-outbox';
import { CHAT_TEXTS } from './chat-view';

/** The most lines the field shows before it scrolls. */
const MAX_LINES = 5;

/**
 * The composer (UX-DR68, UX-DR125): a text area labelled "Message OcuTalon" by a visually hidden label, so the name holds while
 * text is typed, and a Send button. Enter sends, except while an IME composition is open; Shift+Enter adds a line. The text is
 * trimmed at both ends and its inner line breaks are kept; empty text sends nothing. The field grows with its content, by script,
 * up to five lines, then scrolls. It is never disabled: each message becomes its own turn, also while another turn runs. After a
 * send the field is empty, shrunk and focused. It takes no focus on its own.
 */
@Component({
  selector: 'app-composer',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="composer">
      <label class="visually-hidden" for="composer-field">{{ texts.composerLabel }}</label>
      <textarea
        #field
        id="composer-field"
        class="field"
        rows="1"
        [placeholder]="texts.composerPlaceholder"
        (keydown)="onKey($event)"
        (input)="grow()"
      ></textarea>
      <button type="button" class="button button-primary" (click)="send()">{{ texts.send }}</button>
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
  `,
})
export class Composer {
  private readonly outbox = inject(ChatOutbox);
  private readonly field = viewChild.required<ElementRef<HTMLTextAreaElement>>('field');

  protected readonly texts = CHAT_TEXTS;

  /** Enter sends; Shift+Enter, and Enter while an IME composition is open, do not. */
  protected onKey(event: KeyboardEvent): void {
    if (event.key !== 'Enter' || event.shiftKey || event.isComposing || event.keyCode === 229) {
      return;
    }
    event.preventDefault();
    this.send();
  }

  /** Sends the field's text, then empties, shrinks and focuses the field; empty text sends nothing. */
  protected send(): void {
    const field = this.field().nativeElement;
    if (!this.outbox.send(field.value)) {
      return;
    }
    field.value = '';
    this.grow();
    field.focus();
  }

  /** Sizes the field to its content, up to MAX_LINES lines. */
  protected grow(): void {
    const field = this.field().nativeElement;
    const style = getComputedStyle(field);
    const padding = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
    const max = parseFloat(style.lineHeight) * MAX_LINES + padding;
    field.style.height = 'auto';
    field.style.height = `${Math.min(field.scrollHeight, max)}px`;
  }
}
