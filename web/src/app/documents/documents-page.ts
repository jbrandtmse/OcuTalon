import { HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, DestroyRef, Injector, afterNextRender, computed, effect, inject, signal, untracked, viewChild, ElementRef } from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { DocumentRefusal } from '../api/api-types';
import { messageTime } from '../chat/page-time';
import { LiveState } from '../live/live-state';
import type { DocumentPayload } from '../live/payloads';
import { Announcer } from '../shared/announcer';
import { CONFIRM_TITLE_ID, CONFIRMED, ConfirmDialog, ConfirmRequest } from '../shared/confirm-dialog';
import { Dialogs } from '../shared/dialogs';
import { FileDrop } from '../shared/file-drop';
import { encode } from '../shared/file-encode';
import { ServerButton } from '../shared/server-button';
import { isViewer } from '../shared/viewer-view';
import { ACCEPT, DOCUMENTS_TEXTS, DOCUMENT_PARAM, docRef, formatSize, refusedText, rows, sampleListed, type DocumentRow, type LocalRow } from './documents-view';
import { SampleRunbook } from './sample-runbook';
import { SAMPLE_RUNBOOK_TEXTS } from './sample-runbook-view';

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
 * With a `doc` query parameter (#/documents?doc=<ref>, which an answer's "Open document" sets) the page also shows that document's text above
 * the list (GET /v1/documents/:ref): a region named by the document's name, then the text exactly as stored, as plain text with its line breaks
 * (interpolation and `white-space: pre-wrap`, never HTML or Markdown), and a Close button that removes the parameter. Focus goes to the region's
 * heading once the text is shown. A document that cannot be opened (a 404 for one that was removed or is not the session's, or a failure) shows
 * "Couldn't open that document. It may have been removed." in its place, with Close.
 *
 * Beside Add documents, **Add the sample runbook** (a ServerButton) gives the runbook bundled in the web app (sample-runbook-view.ts) to the same
 * `addFile` as a picked file: a `File` built from the text, so the request, the pending and refused rows and the announcement are the file's. It
 * shows once the list has loaded and while no row is named "Sample runbook.md" (documents-view.sampleListed), and also while its own add is out, so
 * that it stays busy; a refusal leaves it with focus, and a success takes it away and puts focus on the list region. When the demo guide's control
 * asked for it (SampleRunbook.take, the user's own press there), the page focuses the button and presses it once the list has loaded, or, with the
 * sample already listed, puts focus on the list region and posts nothing.
 *
 * Remove opens the shared confirm dialog (ConfirmDialog). When it reports the document gone, the row leaves and focus goes to the list region, which
 * has tabindex -1; Esc and Cancel leave the row and return focus to Remove.
 */
@Component({
  selector: 'app-documents-page',
  imports: [FileDrop, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main
      class="documents"
      tabindex="-1"
      appFileDrop
      (files)="addFiles($event)"
    >
      <h1 id="documents-heading" class="heading">{{ texts.heading }}</h1>
      @if (!viewer()) {
        <div class="bar">
          <button type="button" class="button button-primary add" (click)="picker.click()">{{ texts.add }}</button>
          @if (sampleShown()) {
            <app-server-button #sample variant="secondary" [action]="addSample">{{ texts.sample }}</app-server-button>
          }
          <input #picker type="file" multiple hidden [accept]="accept" (change)="picked(picker)" />
        </div>
      }
      @if (opened(); as shown) {
        @if (shown.kind === 'text') {
          <section class="opened" aria-labelledby="document-text-heading" data-part="document-text">
            <h2 #focusTarget id="document-text-heading" class="opened-heading" tabindex="-1">{{ shown.name }}</h2>
            <div class="opened-text">{{ shown.text }}</div>
            <button type="button" class="button button-secondary close" (click)="closeText()">{{ texts.close }}</button>
          </section>
        } @else {
          <div class="opened" data-part="document-text">
            <p #focusTarget class="opened-failed" tabindex="-1">{{ texts.openFailed }}</p>
            <button type="button" class="button button-secondary close" (click)="closeText()">{{ texts.close }}</button>
          </div>
        }
      }
      <div #list class="list-region" tabindex="-1" role="region" aria-labelledby="documents-heading">
        @if (items().length > 0) {
          <ul class="list">
            @for (row of items(); track row.key) {
              <li class="row" [attr.data-state]="row.state">
                <span class="name">{{ row.name }}</span>
                <span class="when">{{ row.when }}</span>
                <span class="size">{{ row.sizeText }}</span>
                <span class="status">{{ row.status }}</span>
                @if (row.removable && !viewer()) {
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
    .opened {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
      padding: var(--space-4);
      border: 1px solid var(--border);
    }
    .opened-heading {
      margin: 0;
      overflow-wrap: anywhere;
      font-size: var(--type-body-strong-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-strong-line-height);
    }
    .opened-text {
      max-width: 100%;
      overflow-wrap: anywhere;
      white-space: pre-wrap;
    }
    .opened-failed {
      margin: 0;
    }
  `,
})
export class DocumentsPage {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  /** True for a viewer (Story 25.4): no add, sample or remove. */
  protected readonly viewer = computed(() => isViewer(this.live.snapshot()));
  private readonly announcer = inject(Announcer);
  private readonly dialogs = inject(Dialogs);
  private readonly target = inject(ConfirmRequest);
  private readonly destroyed = inject(DestroyRef);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly injector = inject(Injector);
  private handOff = inject(SampleRunbook).take();

  protected readonly texts = DOCUMENTS_TEXTS;
  protected readonly accept = ACCEPT;
  protected readonly list = viewChild.required<ElementRef<HTMLElement>>('list');
  private readonly focusTarget = viewChild<ElementRef<HTMLElement>>('focusTarget');
  private readonly sampleHost = viewChild<unknown, ElementRef<HTMLElement>>('sample', { read: ElementRef });

  /** The document the page was asked to open: its text, or that it could not be opened; undefined while none is asked for or its text is on the way. */
  protected readonly opened = signal<{ kind: 'text'; name: string; text: string } | { kind: 'failed' } | undefined>(undefined);
  private readonly param = toSignal(this.route.queryParamMap);
  private opening = 0;

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

  /** True while the sample's own add is out: the button stays, busy, until the route has answered. */
  private readonly sampling = signal(false);

  /** The sample button shows once the list is loaded, while no row is named as the sample, and while its own add is out. */
  protected readonly sampleShown = computed(() => this.loaded() && (this.sampling() || !sampleListed(this.shown(), SAMPLE_RUNBOOK_TEXTS.name)));

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
      const ref = docRef(this.param()?.get(DOCUMENT_PARAM));
      untracked(() => this.open(ref));
    });
    effect(() => {
      if (this.handOff && this.loaded()) {
        this.handOff = false;
        untracked(() => this.handToSample());
      }
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

  /** Shows the text of the document, or nothing for an empty ref; an answer that arrives after a later ask is dropped. */
  private open(ref: string): void {
    const ask = (this.opening += 1);
    this.opened.set(undefined);
    if (ref === '') {
      return;
    }
    this.api
      .documentText(ref)
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (body) => {
          if (ask === this.opening) {
            this.show({ kind: 'text', name: body.name, text: body.text });
          }
        },
        error: () => {
          if (ask === this.opening) {
            this.show({ kind: 'failed' });
          }
        },
      });
  }

  /** Puts the opened document or its failure on the page and moves focus to it once it is drawn: the user asked for it. */
  private show(value: { kind: 'text'; name: string; text: string } | { kind: 'failed' }): void {
    this.opened.set(value);
    afterNextRender(() => this.focusTarget()?.nativeElement.focus(), { injector: this.injector });
  }

  /** Close: the `doc` parameter goes, which takes the text away, and focus goes to the list region. */
  protected closeText(): void {
    void this.router.navigate([], { queryParams: { [DOCUMENT_PARAM]: null }, queryParamsHandling: 'merge', replaceUrl: true });
    this.focusList();
  }

  /** Focus goes to the list region once the change that asked for it is drawn. */
  private focusList(): void {
    globalThis.setTimeout(() => this.list().nativeElement.focus(), 0);
  }

  /** The accessible name of a row's Remove button: "Remove {name}". */
  protected removeName(row: DocumentRow): string {
    return DOCUMENTS_TEXTS.removeName.replace('{name}', () => row.name);
  }

  protected picked(input: HTMLInputElement): void {
    const files = Array.from(input.files ?? []);
    input.value = '';
    void this.addFiles(files);
  }

  /** Opens the Remove dialog for the row; the button that opened it gets focus back when the dialog closes without removing. */
  protected askRemove(row: DocumentRow, event: Event): void {
    this.target.content.set({
      question: DOCUMENTS_TEXTS.question.replace('{name}', () => row.name),
      confirm: DOCUMENTS_TEXTS.remove,
      cancel: DOCUMENTS_TEXTS.cancel,
      failed: DOCUMENTS_TEXTS.removeFailed,
      act: () => this.api.removeDocument(row.ref),
    });
    const ref = this.dialogs.open(ConfirmDialog, { labelledBy: CONFIRM_TITLE_ID, restoreFocus: event.currentTarget as HTMLElement });
    ref.closed.subscribe((result) => {
      if (result === CONFIRMED) {
        this.gone(row.ref);
      }
    });
  }

  /** The document is gone: its row leaves, its text goes if it is the one open, and focus goes to the list region once the dialog has given focus back. */
  private gone(ref: string): void {
    this.server.update((list) => list.filter((one) => one.ref !== ref));
    this.local.update((list) => [{ id: (this.lastId += 1), kind: 'removed', name: '', size: 0, at: '', ref }, ...list]);
    if (docRef(this.param()?.get(DOCUMENT_PARAM)) === ref) {
      this.closeText();
      return;
    }
    this.focusList();
  }

  /**
   * The sample button's action: the bundled runbook as a `File` goes through `addFile` like a picked one. A press while its add is out is
   * ignored; on success focus goes to the list region, and on a refusal nothing moves.
   */
  protected readonly addSample = async (): Promise<void> => {
    if (this.sampling()) {
      return;
    }
    this.sampling.set(true);
    try {
      const file = new File([SAMPLE_RUNBOOK_TEXTS.text], SAMPLE_RUNBOOK_TEXTS.name, { type: 'text/markdown' });
      if (await this.addFile(file)) {
        this.focusList();
      }
    } finally {
      this.sampling.set(false);
    }
  };

  /** The guide asked for the sample: once the button is drawn it takes focus and is pressed; with the sample listed, focus goes to the list region. */
  private handToSample(): void {
    if (sampleListed(this.shown(), SAMPLE_RUNBOOK_TEXTS.name)) {
      this.focusList();
      return;
    }
    afterNextRender(
      () => {
        const control = this.sampleHost()?.nativeElement.querySelector('button');
        if (control) {
          control.focus();
          control.click();
        }
      },
      { injector: this.injector },
    );
  }

  /** Gives each file to the route, one after the other. */
  protected async addFiles(files: readonly File[]): Promise<void> {
    if (this.viewer()) {
      return;
    }
    for (const file of files) {
      await this.addFile(file);
    }
  }

  /** Gives one file to the route and returns true when the route took it, false when it refused it or failed. */
  private async addFile(file: File): Promise<boolean> {
    const id = (this.lastId += 1);
    this.local.update((list) => [{ id, kind: 'pending', name: file.name, size: file.size, at: new Date().toISOString() }, ...list]);
    try {
      const content = await encode(file);
      const answer = await firstValueFrom(this.api.addDocument(file.name, content));
      this.own.add(answer.ref);
      this.patch(id, { ref: answer.ref });
      this.fetch();
      return true;
    } catch (error) {
      this.refuse(id, file, error);
      return false;
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
