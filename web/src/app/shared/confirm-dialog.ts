import { DialogRef } from '@angular/cdk/dialog';
import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, DestroyRef, inject, Injectable, signal } from '@angular/core';
import { catchError, EMPTY, map, type Observable, of, tap } from 'rxjs';

import { Announcer } from './announcer';
import { InlineNotice } from './inline-notice';
import { ServerButton } from './server-button';

/** The id of the dialog's heading, which names the dialog. */
export const CONFIRM_TITLE_ID = 'confirm-dialog-title';

/** What the dialog closes with when the thing is gone: done (a 200) or already gone (a 404). */
export const CONFIRMED = 'confirmed';

/** What one confirmation says and does. */
export interface ConfirmContent {
  /** The question, which is the heading and names the dialog. */
  question: string;
  /** The confirm button's text. */
  confirm: string;
  /** The cancel button's text. */
  cancel: string;
  /** The notice that shows, and is announced, when the call fails. */
  failed: string;
  /** The call that the confirm button makes. */
  act: () => Observable<unknown>;
}

/** The count of the dialogs that have been made, which gives each one's notice an id of its own. */
let lastDialog = 0;

/** The confirmation that the dialog is about, set by the page just before it opens the dialog (Dialogs.open takes no data). */
@Injectable({ providedIn: 'root' })
export class ConfirmRequest {
  readonly content = signal<ConfirmContent>({ question: '', confirm: '', cancel: '', failed: '', act: () => EMPTY });
}

/**
 * The one confirm dialog of the page (Story 41.13; DW-996, DW-997): the Memory card's Forget of an answer and of a memory, and the Documents
 * page's Remove. A modal opened through Dialogs, named by its heading, which is its question. Focus starts on the heading; Esc closes the dialog
 * and focus returns to the control that opened it. Cancel closes it and changes nothing. The confirm button is a server button: an answer of 200
 * or 404 (the thing is gone either way) closes the dialog with CONFIRMED, and any other answer leaves it open with the request's failure notice,
 * which is announced once and named in the confirm button's description, so that a screen reader reads it with the button.
 */
@Component({
  selector: 'app-confirm-dialog',
  imports: [InlineNotice, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h2 [id]="titleId" tabindex="-1">{{ content.question }}</h2>
    @if (failed()) {
      <app-inline-notice variant="warning" class="notice" [id]="noticeId">{{ content.failed }}</app-inline-notice>
    }
    <div class="actions">
      <button type="button" class="button button-secondary cancel" (click)="cancel()">{{ content.cancel }}</button>
      <app-server-button variant="primary" class="confirm" [action]="confirm" [describedBy]="failed() ? [noticeId] : []">{{
        content.confirm
      }}</app-server-button>
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
    h2 {
      margin: 0 0 var(--space-5);
      font-size: var(--type-headline-font-size);
      font-weight: var(--type-headline-font-weight);
      line-height: var(--type-headline-line-height);
    }
    .notice {
      margin-bottom: var(--space-4);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      justify-content: flex-end;
      gap: var(--space-3);
    }
  `,
})
export class ConfirmDialog {
  private readonly dialogRef = inject(DialogRef);
  private readonly announcer = inject(Announcer);

  protected readonly content = inject(ConfirmRequest).content();
  protected readonly titleId = CONFIRM_TITLE_ID;
  protected readonly noticeId = `confirm-dialog-notice-${(lastDialog += 1)}`;
  protected readonly failed = signal(false);

  /** False once the dialog is gone: a reply that comes later shows and announces nothing. */
  private shown = true;

  constructor() {
    inject(DestroyRef).onDestroy(() => (this.shown = false));
  }

  /** Cancel: the dialog closes and nothing changes. */
  protected cancel(): void {
    this.dialogRef.close();
  }

  /** Confirm: asks the server; a 200 or 404 closes the dialog, any other answer shows the notice and announces it once. */
  protected readonly confirm = (): Observable<unknown> => {
    this.failed.set(false);
    return this.content.act().pipe(
      map(() => true),
      catchError((error: unknown) => of(error instanceof HttpErrorResponse && error.status === 404)),
      tap((gone) => {
        if (!this.shown) {
          return;
        }
        if (gone) {
          this.dialogRef.close(CONFIRMED);
        } else {
          this.failed.set(true);
          this.announcer.announce(this.content.failed);
        }
      }),
    );
  };
}
