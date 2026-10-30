import { DialogRef } from '@angular/cdk/dialog';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import { SessionGate } from '../session/session-gate';
import { SIGN_OUT_TEXT_ID, SIGN_OUT_TEXTS } from './sign-out-texts';

/** The selector of the button that takes the dialog's first focus: Cancel, not the heading (UX-DR30 overrides UX-DR38). */
export const SIGN_OUT_FOCUS = '.cancel';

/**
 * The online demo's Sign out dialog (Story 16.4; UX-DR30). It is opened through Dialogs from the account menu, is named by its one sentence
 * and has two buttons: Cancel, which has the first focus and closes the dialog and changes nothing, and Sign out, which closes the dialog
 * and signs out through the session gate (it ends the OcuTalon session). Esc and a press on the backdrop close it as Cancel does.
 */
@Component({
  selector: 'app-sign-out-dialog',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <p class="text" [id]="textId">{{ texts.text }}</p>
    <div class="actions">
      <button type="button" class="button button-secondary cancel" (click)="cancel()">{{ texts.cancel }}</button>
      <button type="button" class="button button-primary confirm" (click)="signOut()">{{ texts.confirm }}</button>
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
export class SignOutDialog {
  private readonly dialogRef = inject(DialogRef);
  private readonly gate = inject(SessionGate);

  protected readonly textId = SIGN_OUT_TEXT_ID;
  protected readonly texts = SIGN_OUT_TEXTS;

  /** Cancel: the dialog closes, nothing is sent and nothing changes. */
  protected cancel(): void {
    this.dialogRef.close();
  }

  /** Sign out: the dialog closes and the session gate signs out. */
  protected signOut(): void {
    this.dialogRef.close();
    this.gate.signOut();
  }
}
