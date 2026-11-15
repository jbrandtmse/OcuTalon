import { DialogRef } from '@angular/cdk/dialog';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import { SHELL_TEXTS } from '../shared/page-shell-view';

/** The id of the sentence, which names the dialog. */
export const UNSAVED_TEXT_ID = 'unsaved-text';

/** The selector of the button that takes the dialog's first focus: Stay, so that a stray Enter never discards the changes. */
export const UNSAVED_FOCUS = '.stay';

/**
 * The prompt that a leave from a section with unsaved changes opens (Story 33.2; UX: Settings, Saving). It is opened through Dialogs by the
 * settings page's guard and is named by its one sentence. Its two buttons close it with the answer: Stay (first focus; the same as Esc or a press on
 * the backdrop) keeps the page and its values, and Leave without saving lets the navigation go on and discards the values. The shape is the Sign
 * out dialog's; its buttons and its result differ.
 */
@Component({
  selector: 'app-unsaved-dialog',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <p class="text" [id]="textId">{{ texts.unsaved }}</p>
    <div class="actions">
      <button type="button" class="button button-secondary stay" (click)="answer(false)">{{ texts.stay }}</button>
      <button type="button" class="button button-primary leave" (click)="answer(true)">{{ texts.leave }}</button>
    </div>
  `,
  styles: `
    :host {
      display: block;
      width: min(400px, calc(100vw - 32px));
      padding: var(--space-6);
      background: var(--dialog-background);
      border-radius: var(--dialog-radius);
      box-shadow: var(--dialog-shadow);
      color: var(--ink);
    }
    .text {
      margin: 0 0 var(--space-5);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      justify-content: flex-end;
      gap: var(--space-3);
    }
  `,
})
export class UnsavedDialog {
  private readonly dialogRef = inject<DialogRef<boolean>>(DialogRef);

  protected readonly textId = UNSAVED_TEXT_ID;
  protected readonly texts = SHELL_TEXTS;

  /** Closes the dialog with the answer: true leaves, false stays. */
  protected answer(leave: boolean): void {
    this.dialogRef.close(leave);
  }
}
