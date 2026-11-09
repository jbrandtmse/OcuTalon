import { DialogRef } from '@angular/cdk/dialog';
import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, inject, Injectable, signal } from '@angular/core';
import { catchError, map, type Observable, of, tap } from 'rxjs';

import { ApiClient } from '../../api/api-client';
import { InlineNotice } from '../../shared/inline-notice';
import { ServerButton } from '../../shared/server-button';
import { MEMORY_TEXTS } from './memory-card-view';

/** The id of the dialog's heading, which names the dialog. */
export const FORGET_TITLE_ID = 'forget-answer-title';

/** What the dialog closes with when the answer is gone: forgotten (a 200) or already gone (a 404). */
export const FORGOTTEN = 'forgotten';

/** The answer that the dialog is about, set by the Memory card just before it opens the dialog (Dialogs.open takes no data). */
@Injectable({ providedIn: 'root' })
export class ForgetTarget {
  readonly ref = signal('');
}

/**
 * The Forget dialog of the Memory card (Story 41.6; FR-72): a modal opened through Dialogs, named by its heading, which is its question,
 * "Forget this answer? OcuTalon will stop using it.". Focus starts on the heading; Esc closes the dialog and focus returns to the row's Forget
 * button. Cancel closes it and changes nothing. Forget is a server button: an answer of 200 or 404 (the answer is gone either way) closes
 * the dialog with FORGOTTEN, and any other answer leaves it open with a notice, "Couldn't forget it. Nothing was changed."
 */
@Component({
  selector: 'app-forget-answer-dialog',
  imports: [InlineNotice, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h2 [id]="titleId" tabindex="-1">{{ texts.question }}</h2>
    @if (failed()) {
      <app-inline-notice variant="warning" class="notice">{{ texts.forgetFailed }}</app-inline-notice>
    }
    <div class="actions">
      <button type="button" class="button button-secondary cancel" (click)="cancel()">{{ texts.cancel }}</button>
      <app-server-button variant="primary" class="confirm" [action]="confirm">{{ texts.confirm }}</app-server-button>
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
export class ForgetDialog {
  private readonly dialogRef = inject(DialogRef);
  private readonly api = inject(ApiClient);
  private readonly ref = inject(ForgetTarget).ref();

  protected readonly titleId = FORGET_TITLE_ID;
  protected readonly texts = MEMORY_TEXTS;
  protected readonly failed = signal(false);

  /** Cancel: the dialog closes and nothing changes. */
  protected cancel(): void {
    this.dialogRef.close();
  }

  /** Forget: asks the server; its answer closes the dialog or shows the notice. */
  protected readonly confirm = (): Observable<unknown> => {
    this.failed.set(false);
    return this.api.forgetPrecedent(this.ref).pipe(
      map(() => true),
      catchError((error: unknown) => of(error instanceof HttpErrorResponse && error.status === 404)),
      tap((gone) => {
        if (gone) {
          this.dialogRef.close(FORGOTTEN);
        } else {
          this.failed.set(true);
        }
      }),
    );
  };
}
