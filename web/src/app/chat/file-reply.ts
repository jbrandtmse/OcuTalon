import { afterNextRender, ChangeDetectionStrategy, Component, computed, ElementRef, inject, Injector, input, signal } from '@angular/core';
import { catchError, type Observable, of, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { isViewer } from '../shared/viewer-view';
import { LiveState } from '../live/live-state';
import type { Caption, FileRead } from '../live/payloads';
import { FILE_REPLY_TEXTS, controlsOf } from './file-reply-view';

/**
 * The controls under the reply to a sent file (Story 25.6; FR-54, FR-73, UX-DR129): for a PDF or Word file that OcuTalon read, a native Add to documents button,
 * and for a photo whose caption was saved as a memory, a "Saved to memory" chip with no button. The button posts the file's ref to the documents route (the
 * server reads the bytes from its own store for this session) through the shared ServerButton, so a press is one call under the busy rule (a spinner, aria-busy and aria-disabled,
 * never `disabled`; a repeat press sends nothing; with no answer in 10 s the button is restored with the busy notice), on success it gives way to the line "Added to your
 * documents." and focus moves to that line (the pressed button is gone, so focus would otherwise fall to the page), and on a failure the line "Couldn't add it to your documents. Nothing was changed." shows under the button, which stays. Each line is spoken once through the Announcer, the page's one live
 * region (UX-DR132; the lines carry no live role of their own). A viewer (viewer-view.isViewer) gets no button, because the server refuses its add with 403 read_only, and keeps the chip. The component is a lazy chunk, mounted by the reply (DW-1282), and its texts are the view module's.
 */
@Component({
  selector: 'app-file-reply',
  imports: [ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (controls().add) {
      @if (state() === 'added') {
        <p class="line added" tabindex="-1">{{ texts.added }}</p>
      } @else {
        <app-server-button variant="secondary" [action]="add">{{ texts.addToDocuments }}</app-server-button>
        @if (state() === 'failed') {
          <p class="line">{{ texts.addFailed }}</p>
        }
      }
    }
    @if (controls().saved) {
      <span class="chip">{{ texts.savedToMemory }}</span>
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
      margin-top: var(--space-1);
    }
    .line {
      margin: 0;
      color: var(--ink);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .chip {
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      max-width: 100%;
      padding: 0 var(--space-2);
      background: var(--citation-chip-background);
      color: var(--citation-chip-foreground);
      border: var(--citation-chip-border);
      border-radius: var(--citation-chip-radius);
      font-family: var(--font-ui);
      font-size: var(--citation-chip-typography-font-size);
      font-weight: var(--citation-chip-typography-font-weight);
      line-height: var(--citation-chip-typography-line-height);
    }
  `,
})
export class FileReply {
  /** The read result of the turn's file, as its chat.message carries it. */
  readonly fileRead = input<FileRead | undefined>(undefined);
  /** The caption that the photo's reply saved as a memory, as its chat.message carries it. */
  readonly savedCaption = input<Caption | undefined>(undefined);

  protected readonly texts = FILE_REPLY_TEXTS;
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly live = inject(LiveState);

  /** The add: idle, added (the line replaces the button) or failed (the line shows and the button stays). ServerButton holds the busy state of a press. */
  protected readonly state = signal<'idle' | 'added' | 'failed'>('idle');

  /** True for a viewer (Story 25.4): no Add to documents button. */
  protected readonly viewer = computed(() => isViewer(this.live.snapshot()));

  protected readonly controls = computed(() => controlsOf(this.fileRead(), this.savedCaption(), this.viewer()));

  /** The press: posts the file's ref to the documents route (ServerButton ignores a second press while it is out). Its answer sets the line, announced once. */
  protected readonly add = (): Observable<unknown> => {
    const ref = this.fileRead()?.fileRef;
    if (ref === undefined || ref === '') {
      return of(undefined);
    }
    return this.api.addDocumentFromFile(ref).pipe(
      tap(() => {
        this.state.set('added');
        afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>('.added')?.focus(), { injector: this.injector });
        this.announcer.announce(FILE_REPLY_TEXTS.added);
      }),
      catchError(() => {
        this.state.set('failed');
        this.announcer.announce(FILE_REPLY_TEXTS.addFailed);
        return of(undefined);
      }),
    );
  };
}
