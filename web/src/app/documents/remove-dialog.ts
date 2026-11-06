import { DialogRef } from '@angular/cdk/dialog';
import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, inject, Injectable, signal } from '@angular/core';
import { catchError, map, type Observable, of, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { InlineNotice } from '../shared/inline-notice';
import { ServerButton } from '../shared/server-button';
import { DOCUMENTS_TEXTS } from './documents-view';

/** The id of the dialog's heading, which names the dialog. */
export const REMOVE_TITLE_ID = 'remove-document-title';

/** What the dialog closes with when the document is gone: removed (a 200) or already gone (a 404). */
export const REMOVED = 'removed';

/** The document that the dialog is about, set by the Documents page just before it opens the dialog (Dialogs.open takes no data). */
@Injectable({ providedIn: 'root' })
export class RemoveTarget {
  readonly document = signal<{ ref: string; name: string }>({ ref: '', name: '' });
}

/**
 * The Remove dialog of the Documents page (Story 34.2; EXPERIENCE: Step 3, Removing): a modal opened through Dialogs, named by its heading, which is its
 * question, "Remove '{name}'? Answers will stop citing it.". Focus starts on the heading; Esc closes the dialog and focus returns to the row's Remove
 * button. Cancel closes it and changes nothing. Remove is a server button: an answer of 200 or 404 (the document is gone either way) closes the dialog
 * with REMOVED, and any other answer leaves it open with a notice, "Couldn't remove it. Nothing was changed."
 */
@Component({
  selector: 'app-remove-document-dialog',
  imports: [InlineNotice, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h2 [id]="titleId" tabindex="-1">{{ question() }}</h2>
    @if (failed()) {
      <app-inline-notice variant="warning" class="notice">{{ texts.removeFailed }}</app-inline-notice>
    }
    <div class="actions">
      <button type="button" class="button button-secondary cancel" (click)="cancel()">{{ texts.cancel }}</button>
      <app-server-button variant="primary" class="confirm" [action]="confirm">{{ texts.remove }}</app-server-button>
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
export class RemoveDocumentDialog {
  private readonly dialogRef = inject(DialogRef);
  private readonly api = inject(ApiClient);
  private readonly target = inject(RemoveTarget).document();

  protected readonly titleId = REMOVE_TITLE_ID;
  protected readonly texts = DOCUMENTS_TEXTS;
  protected readonly failed = signal(false);
  protected readonly question = signal(DOCUMENTS_TEXTS.question.replace('{name}', () => this.target.name));

  /** Cancel: the dialog closes and nothing changes. */
  protected cancel(): void {
    this.dialogRef.close();
  }

  /** Remove: asks the server; its answer closes the dialog or shows the notice. */
  protected readonly confirm = (): Observable<unknown> => {
    this.failed.set(false);
    return this.api.removeDocument(this.target.ref).pipe(
      map(() => true),
      catchError((error: unknown) => of(error instanceof HttpErrorResponse && error.status === 404)),
      tap((gone) => {
        if (gone) {
          this.dialogRef.close(REMOVED);
        } else {
          this.failed.set(true);
        }
      }),
    );
  };
}
