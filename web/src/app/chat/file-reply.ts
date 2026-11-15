import { afterNextRender, ChangeDetectionStrategy, Component, computed, ElementRef, inject, Injector, input, signal } from '@angular/core';

import { ApiClient } from '../api/api-client';
import { Announcer } from '../shared/announcer';
import type { Caption, FileRead } from '../live/payloads';
import { FILE_REPLY_TEXTS, controlsOf } from './file-reply-view';

/**
 * The controls under the reply to a sent file (Story 25.6; FR-54, FR-73, UX-DR129): for a PDF or Word file that OcuTalon read, a native Add to documents button,
 * and for a photo whose caption was saved as a memory, a "Saved to memory" chip with no button. The button posts the file's ref to the documents route (the
 * server reads the bytes from its own store for this session); while the post is pending it is aria-disabled (a busy button, as the shared controls have it), on success it gives way to the line "Added to your
 * documents." and focus moves to that line (the pressed button is gone, so focus would otherwise fall to the page), and on a failure the line "Couldn't add it to your documents. Nothing was changed." shows under the button, which stays. Each line is spoken once through the Announcer, the page's one live
 * region (UX-DR132; the lines carry no live role of their own). The component is a lazy chunk, mounted by the reply (DW-1282), and its texts are the view module's.
 */
@Component({
  selector: 'app-file-reply',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (controls().add) {
      @if (state() === 'added') {
        <p class="line added" tabindex="-1">{{ texts.added }}</p>
      } @else {
        <button type="button" class="button button-secondary" [attr.aria-disabled]="state() === 'pending' ? 'true' : null" (click)="add()">{{ texts.addToDocuments }}</button>
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

  /** The add: idle, pending (the button is disabled), added (the line replaces the button) or failed (the line shows and the button stays). */
  protected readonly state = signal<'idle' | 'pending' | 'added' | 'failed'>('idle');

  protected readonly controls = computed(() => controlsOf(this.fileRead(), this.savedCaption()));

  /** Posts the file's ref to the documents route; a second press while it is pending does nothing. */
  protected add(): void {
    const ref = this.fileRead()?.fileRef;
    if (this.state() === 'pending' || ref === undefined || ref === '') {
      return;
    }
    this.state.set('pending');
    this.api.addDocumentFromFile(ref).subscribe({
      next: () => {
        this.state.set('added');
        afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>('.added')?.focus(), { injector: this.injector });
        this.announcer.announce(FILE_REPLY_TEXTS.added);
      },
      error: () => {
        this.state.set('failed');
        this.announcer.announce(FILE_REPLY_TEXTS.addFailed);
      },
    });
  }
}
