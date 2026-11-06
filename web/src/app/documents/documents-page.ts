import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, DestroyRef, computed, effect, inject, signal, untracked, viewChild, type ElementRef } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { firstValueFrom } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { DocumentRefusal } from '../api/api-types';
import { messageTime } from '../chat/page-time';
import { LiveState } from '../live/live-state';
import type { DocumentPayload } from '../live/payloads';
import { Announcer } from '../shared/announcer';
import { Dialogs } from '../shared/dialogs';
import { ACCEPT, DOCUMENTS_TEXTS, formatSize, refusedText, rows, type DocumentRow, type LocalRow } from './documents-view';
import { REMOVE_TITLE_ID, REMOVED, RemoveDocumentDialog, RemoveTarget } from './remove-dialog';

/**
 * The Documents page (Story 34.2; FR-42; UX: Step 3, memory and documents), at #/documents for every signed-in user and titled "Documents \u00B7 OcuTalon" by
 * its route. It has the one h1 "Documents", the **Add documents** button (a file picker; drag and drop onto the page is a second way, shown by an
 * outline only), and the list: each row has the document's name, the date it was added, its size and its status, "Indexing\u2026", "Ready" or
 * "Couldn't read it: {reason}", and a Remove button. With no rows the list says "No documents yet. Add a runbook to get cited answers."
 *
 * The page asks GET /v1/documents when it opens and again whenever the snapshot reloads, and overlays the live store's `document` payloads by ref
 * (documents-view.rows), so a status changes, and a removed document leaves, without a reload. Each file that is given goes to POST /v1/documents at
 * once, one after the other, and has a row of the page's own: "Indexing\u2026" while the add is out, the server's row once the server lists the ref,
 * and "Couldn't read it: {reason}" when the route refused the file (the reason is the route's; a body or an answer it does not explain reads as
 * `failed`; a 501 as `not_built`). A refused file is not stored, so its row has no Remove and goes at the next reload. The page speaks a refused
 * row of the user's own add once, through the Announcer.
 *
 * Remove opens the Remove dialog (RemoveDocumentDialog). When it reports the document gone, the row leaves and focus goes to the list region, which
 * has tabindex -1; Esc and Cancel leave the row and return focus to Remove.
 */
@Component({
  selector: 'app-documents-page',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main
      class="documents"
      tabindex="-1"
      [class.dragging]="dragging()"
      (dragover)="dragOver($event)"
      (dragleave)="dragLeave($event)"
      (drop)="dropped($event)"
    >
      <h1 id="documents-heading" class="heading">{{ texts.heading }}</h1>
      <div class="bar">
        <button type="button" class="button button-primary add" (click)="picker.click()">{{ texts.add }}</button>
        <input #picker type="file" multiple hidden [accept]="accept" (change)="picked(picker)" />
      </div>
      <div #list class="list-region" tabindex="-1" role="region" aria-labelledby="documents-heading">
        @if (items().length > 0) {
          <ul class="list">
            @for (row of items(); track row.key) {
              <li class="row" [attr.data-state]="row.state">
                <span class="name">{{ row.name }}</span>
                <span class="when">{{ row.when }}</span>
                <span class="size">{{ row.sizeText }}</span>
                <span class="status">{{ row.status }}</span>
                @if (row.removable) {
                  <button type="button" class="button button-secondary remove" [attr.aria-label]="removeName(row)" (click)="askRemove(row, $event)">{{ texts.remove }}</button>
                }
              </li>
            }
          </ul>
        } @else if (loaded()) {
          <p class="empty">{{ texts.empty }}</p>
        }
      </div>
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      min-height: 0;
    }
    .documents {
      flex: 1;
      min-width: 0;
      overflow: auto;
      scroll-padding: var(--space-scroll-gutter);
      padding: var(--space-6);
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      outline-offset: calc(-1 * var(--space-2));
    }
    .documents.dragging {
      outline: 2px dashed var(--action);
    }
    .heading {
      margin: 0;
      font-family: var(--font-display);
      font-size: var(--type-display-lg-font-size);
      font-weight: var(--type-display-lg-font-weight);
      line-height: var(--type-display-lg-line-height);
    }
    .bar {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-3);
    }
    .list {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2) var(--space-4);
      padding: var(--space-2) 0;
      border-bottom: 1px solid var(--border);
    }
    .name {
      flex: 1 1 200px;
      min-width: 0;
      overflow-wrap: anywhere;
      font-weight: 600;
    }
    .when,
    .size,
    .status {
      flex: none;
    }
    .empty {
      margin: 0;
    }
  `,
})
export class DocumentsPage {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly announcer = inject(Announcer);
  private readonly dialogs = inject(Dialogs);
  private readonly target = inject(RemoveTarget);
  private readonly destroyed = inject(DestroyRef);

  protected readonly texts = DOCUMENTS_TEXTS;
  protected readonly accept = ACCEPT;
  protected readonly list = viewChild.required<ElementRef<HTMLElement>>('list');

  /** True while files are dragged over the page: the outline shows. */
  protected readonly dragging = signal(false);

  /** True once GET /v1/documents has answered; the empty text shows only then. */
  protected readonly loaded = signal(false);

  /** The documents as GET /v1/documents last listed them. */
  private readonly server = signal<readonly DocumentPayload[]>([]);

  /** The page's own rows: files being added or refused, and the documents the user removed. */
  private readonly local = signal<readonly LocalRow[]>([]);

  /** The refs of the user's own adds, and those whose refusal has been spoken. */
  private readonly own = new Set<string>();
  private readonly spoken = new Set<string>();
  private lastId = 0;

  private readonly shown = computed(() => rows(this.server(), this.live.store()?.documents ?? {}, this.local()));

  /** The rows with their date and size as text. */
  protected readonly items = computed(() => {
    const snapshot = this.live.snapshot();
    const zone = snapshot?.instanceZone ?? '';
    const online = snapshot?.onlineDemo === true;
    const now = Date.now();
    return this.shown().map((row) => ({ ...row, when: messageTime(row.addedAt, now, zone, online), sizeText: formatSize(row.size) }));
  });

  constructor() {
    effect(() => {
      this.live.snapshot();
      untracked(() => this.fetch());
    });
    effect(() => {
      const refused = this.shown().filter((row) => row.state === 'refused' && row.ref !== '' && this.own.has(row.ref) && !this.spoken.has(row.ref));
      untracked(() => {
        for (const row of refused) {
          this.spoken.add(row.ref);
          this.announcer.announce(row.status);
        }
      });
    });
  }

  /** The accessible name of a row's Remove button: "Remove {name}". */
  protected removeName(row: DocumentRow): string {
    return DOCUMENTS_TEXTS.removeName.replace('{name}', () => row.name);
  }

  protected dragOver(event: DragEvent): void {
    if (event.dataTransfer?.types.includes('Files')) {
      event.preventDefault();
      this.dragging.set(true);
    }
  }

  protected dragLeave(event: DragEvent): void {
    const host = event.currentTarget as HTMLElement;
    if (!(event.relatedTarget instanceof Node) || !host.contains(event.relatedTarget)) {
      this.dragging.set(false);
    }
  }

  protected dropped(event: DragEvent): void {
    event.preventDefault();
    this.dragging.set(false);
    void this.addFiles(Array.from(event.dataTransfer?.files ?? []));
  }

  protected picked(input: HTMLInputElement): void {
    const files = Array.from(input.files ?? []);
    input.value = '';
    void this.addFiles(files);
  }

  /** Opens the Remove dialog for the row; the button that opened it gets focus back when the dialog closes without removing. */
  protected askRemove(row: DocumentRow, event: Event): void {
    this.target.document.set({ ref: row.ref, name: row.name });
    const ref = this.dialogs.open(RemoveDocumentDialog, { labelledBy: REMOVE_TITLE_ID, restoreFocus: event.currentTarget as HTMLElement });
    ref.closed.subscribe((result) => {
      if (result === REMOVED) {
        this.gone(row.ref);
      }
    });
  }

  /** The document is gone: its row leaves, and focus goes to the list region once the dialog has given focus back. */
  private gone(ref: string): void {
    this.server.update((list) => list.filter((one) => one.ref !== ref));
    this.local.update((list) => [{ id: (this.lastId += 1), kind: 'removed', name: '', size: 0, at: '', ref }, ...list]);
    globalThis.setTimeout(() => this.list().nativeElement.focus(), 0);
  }

  /** Gives each file to the route, one after the other. */
  private async addFiles(files: readonly File[]): Promise<void> {
    for (const file of files) {
      await this.addFile(file);
    }
  }

  private async addFile(file: File): Promise<void> {
    const id = (this.lastId += 1);
    this.local.update((list) => [{ id, kind: 'pending', name: file.name, size: file.size, at: new Date().toISOString() }, ...list]);
    try {
      const content = await this.encode(file);
      const answer = await firstValueFrom(this.api.addDocument(file.name, content));
      this.own.add(answer.ref);
      this.patch(id, { ref: answer.ref });
      this.fetch();
    } catch (error) {
      this.refuse(id, file, error);
    }
  }

  /** The row of the file after a refusal or a failure: "Couldn't read it: {reason}", spoken once. */
  private refuse(id: number, file: File, error: unknown): void {
    const reason = this.reasonOf(error);
    this.patch(id, { kind: 'refused', reason });
    this.announcer.announce(refusedText(reason, file.size));
  }

  /**
   * The route's reason for a 400 `bad_document`, `too_large` for the route's own 413 `body_too_large` (its bound on the body is the 10 MB limit's
   * size in base64 and the JSON around it, so a body over it is a file over the limit), `not_built` for a 501, and `failed` for every other answer
   * or failure, a 413 from anything in front of the route among them.
   */
  private reasonOf(error: unknown): string {
    if (error instanceof HttpErrorResponse) {
      const body = error.error as DocumentRefusal | null;
      if (error.status === 400 && body?.error?.code === 'bad_document' && typeof body.reason === 'string') {
        return body.reason;
      }
      if (error.status === 413 && body?.error?.code === 'body_too_large') {
        return 'too_large';
      }
      if (error.status === 501) {
        return 'not_built';
      }
    }
    return 'failed';
  }

  private patch(id: number, change: Partial<LocalRow>): void {
    this.local.update((list) => list.map((entry) => (entry.id === id ? { ...entry, ...change } : entry)));
  }

  /** The file's bytes in base64, with no data-URL prefix. */
  private encode(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(reader.error);
      reader.onload = () => resolve(String(reader.result).replace(/^[^,]*,/, ''));
      reader.readAsDataURL(file);
    });
  }

  /** GET /v1/documents: the list the server holds now. */
  private fetch(): void {
    this.api
      .documents()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (body) => {
          this.server.set(body.documents ?? []);
          this.loaded.set(true);
        },
        error: () => undefined,
      });
  }
}
