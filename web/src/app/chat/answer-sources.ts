import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ViewContainerRef,
  computed,
  inject,
  input,
  signal,
  viewChild,
  type TemplateRef,
} from '@angular/core';
import { RouterLink } from '@angular/router';

import { Icon } from '../icon/icon';
import type { Citation, Memory } from '../live/payloads';
import { Popovers, type PopoverRef } from '../shared/popover';
import { ANSWER_SOURCES_TEXTS, citationChips, memoryChips, savedLine, type CitationChip, type MemoryChip } from './answer-sources-view';
import { pageWhen } from './page-time';

/** The last id handed to a sources row, for the id of the heading that names its popover. */
let lastId = 0;

/**
 * The sources under an answer (Story 20.2; FR-41, FR-42, UX-DR144, UX-DR106, UX-DR38, U-280): one chip for each document section the answer's
 * citations name, then one "From memory" chip for each memory it recalled, in a group named "Sources". The chips are made from the server's
 * `citations` and `memories` (answer-sources-view.ts), never from the reply's text.
 * - A chip is a native button with aria-haspopup="dialog" and aria-expanded. A citation chip shows the file-text icon and
 *   "{document} \u00A7 {section}" and is named "{document}, section {section}"; a memory chip shows "From memory" and is named "From memory: {text}".
 * - A press opens a popover (shared/popover.ts) named by its heading, and a second press closes it. A citation popover has the passages (each at
 *   most six lines, as plain text) and the link "Open document", which opens the Documents page on that document. A memory popover has the
 *   remembered text in a block that takes focus, and "Saved {when}". Esc, a press outside and focus leaving close it and return focus to the chip.
 * Every value is bound by interpolation, never as HTML, and nothing here is a live region or moves focus itself.
 */
@Component({
  selector: 'app-answer-sources',
  imports: [Icon, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (citationRow().length > 0 || memoryRow().length > 0) {
      <div class="sources" role="group" [attr.aria-label]="texts.group" data-part="sources">
        @for (chip of citationRow(); track chip.key) {
          <button
            #trigger
            type="button"
            class="chip"
            data-source="citation"
            aria-haspopup="dialog"
            [attr.aria-expanded]="openKey() === chip.key"
            [attr.aria-label]="chip.name"
            (click)="press(chip.key, trigger)"
          >
            <app-icon name="file-text" [size]="12" /><span>{{ chip.label }}</span>
          </button>
        }
        @for (chip of memoryRow(); track chip.key) {
          <button
            #trigger
            type="button"
            class="chip"
            data-source="memory"
            aria-haspopup="dialog"
            [attr.aria-expanded]="openKey() === chip.key"
            [attr.aria-label]="chip.name"
            (click)="press(chip.key, trigger)"
          >
            <span>{{ chip.label }}</span>
          </button>
        }
      </div>
    }
    <ng-template #panel>
      <div class="panel">
        @if (shownCitation(); as chip) {
          <h2 class="heading" [id]="headingId">{{ chip.label }}</h2>
          @for (passage of chip.passages; track $index) {
            <p class="passage" data-part="passage">{{ passage }}</p>
          }
          <a
            class="button button-secondary open"
            routerLink="/documents"
            [queryParams]="{ doc: chip.documentRef }"
            (click)="close()"
            >{{ texts.openDocument }}</a
          >
        } @else if (shownMemory(); as chip) {
          <h2 class="heading" [id]="headingId">{{ chip.label }}</h2>
          <div class="memory" tabindex="0" data-part="memory">{{ chip.text }}</div>
          @if (saved(); as line) {
            <p class="saved">{{ line }}</p>
          }
        }
      </div>
    </ng-template>
  `,
  styles: `
    :host {
      display: block;
    }
    .sources {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1);
      margin-top: var(--space-1);
    }
    .chip {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
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
      text-align: left;
      cursor: pointer;
    }
    .chip[aria-expanded='true'] {
      text-decoration-line: underline;
      text-decoration-thickness: 2px;
      text-underline-offset: 2px;
    }
    .chip span {
      min-width: 0;
      overflow-wrap: anywhere;
    }
    .panel {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
      width: min(360px, calc(100vw - 32px));
      padding: var(--space-4);
      color: var(--ink);
    }
    .heading {
      margin: 0;
      overflow-wrap: anywhere;
      font-size: var(--type-body-strong-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-strong-line-height);
    }
    .passage,
    .memory,
    .saved {
      margin: 0;
      max-width: 100%;
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-font-weight);
      line-height: var(--type-body-line-height);
      overflow-wrap: anywhere;
      white-space: pre-wrap;
    }
    .passage {
      display: -webkit-box;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 6;
      line-clamp: 6;
      overflow: hidden;
    }
    .memory {
      max-height: 12lh;
      overflow: auto;
      scroll-padding: var(--space-scroll-gutter);
    }
    .saved {
      color: var(--ink-muted);
    }
  `,
})
export class AnswerSources {
  /** The answer's citations, as its chat.message carries them. */
  readonly citations = input<readonly Citation[] | undefined>();
  /** The memories the answer recalled, as its chat.message carries them. */
  readonly memories = input<readonly Memory[] | undefined>();

  protected readonly texts = ANSWER_SOURCES_TEXTS;
  protected readonly headingId = `answer-sources-heading-${++lastId}`;
  protected readonly citationRow = computed<CitationChip[]>(() => citationChips(this.citations()));
  protected readonly memoryRow = computed<MemoryChip[]>(() => memoryChips(this.memories()));

  /** The key of the chip whose popover is open; "" when none is. */
  protected readonly openKey = signal('');
  protected readonly shownCitation = computed(() => this.citationRow().find((chip) => chip.key === this.openKey()));
  protected readonly shownMemory = computed(() => this.memoryRow().find((chip) => chip.key === this.openKey()));
  /** "Saved {when}" for the open memory, from the time in the browser's zone; "" when it has no readable time. */
  protected readonly saved = computed(() => {
    const chip = this.shownMemory();
    return chip === undefined ? '' : savedLine(pageWhen(chip.savedAt, Date.now()));
  });

  private readonly popovers = inject(Popovers);
  private readonly container = inject(ViewContainerRef);
  private readonly panel = viewChild.required<TemplateRef<unknown>>('panel');
  private popover: PopoverRef | undefined;

  constructor() {
    inject(DestroyRef).onDestroy(() => this.popover?.close());
  }

  /** A press on a chip opens its popover, or closes it when it is the open one. */
  protected press(key: string, trigger: HTMLElement): void {
    if (this.popover?.isOpen && this.openKey() === key) {
      this.popover.close();
      return;
    }
    this.popover?.close();
    this.openKey.set(key);
    const opened = this.popovers.show({ trigger, content: this.panel(), viewContainerRef: this.container, labelledBy: this.headingId });
    this.popover = opened;
    opened.closed.subscribe(() => {
      if (this.popover === opened) {
        this.openKey.set('');
      }
    });
  }

  protected close(): void {
    this.popover?.close();
  }
}
