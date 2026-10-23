import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ViewContainerRef,
  inject,
  input,
  output,
  viewChild,
  type ElementRef,
  type TemplateRef,
} from '@angular/core';

import { Icon } from '../icon/icon';
import { Popovers, type PopoverRef } from './popover';
import { TraceHelp } from './trace-help';
import { TRACE_TEXTS } from './trace-view';

/** The last id handed to a help block's heading. */
let lastHeading = 0;

/** A new id for the heading of a sign-in help block, which names the popover that holds it. */
export function newTraceHeadingId(): string {
  lastHeading += 1;
  return `trace-help-heading-${lastHeading}`;
}

/**
 * The block that a Visual Trace popover shows (UX-DR38, UX-DR140): the heading, the sign-in text when `signIn` is set, the
 * projected action, and, with the text, the ghost button "Don't show this again", which records the flag and emits
 * `dismissed` for the host to close its popover. The host gives the heading's id, because the popover is named by it.
 */
@Component({
  selector: 'app-trace-help',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h2 class="heading" [id]="headingId()">{{ heading() }}</h2>
    @if (signIn()) {
      <p class="text">{{ texts.signInText }}</p>
    }
    <ng-content />
    @if (signIn()) {
      <button type="button" class="button button-ghost" (click)="dontShow()">{{ texts.dontShow }}</button>
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
      width: min(340px, calc(100vw - 32px));
      padding: var(--space-4);
      color: var(--ink);
    }
    .heading {
      margin: 0;
      font-size: var(--type-body-strong-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-strong-line-height);
    }
    .text {
      margin: 0;
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-font-weight);
      line-height: var(--type-body-line-height);
    }
  `,
})
export class TraceHelpBlock {
  /** The id of the heading, which names the popover. */
  readonly headingId = input.required<string>();
  readonly heading = input.required<string>();
  /** True for the sign-in help: the text and "Don't show this again". */
  readonly signIn = input(true);
  /** Emits after "Don't show this again" has recorded the flag. */
  readonly dismissed = output<void>();

  private readonly help = inject(TraceHelp);
  protected readonly texts = TRACE_TEXTS;

  protected dontShow(): void {
    this.help.dontShowAgain();
    this.dismissed.emit();
  }
}

/**
 * A Visual Trace link (UX-DR42, UX-DR61, UX-DR57): an underlined "Trace" with the external-link icon, opening the payload's
 * `url` exactly as served in a new tab. It sits beside a row's button and never inside one, and its owner renders it only
 * when the payload has a `traceUrl`.
 * - Its name is "Trace (opens in a new tab)": the visible text and a visually hidden suffix.
 * - While the sign-in help is needed (TraceHelp) its name is "Open in Visual Trace (shows sign-in help first)" with
 *   aria-haspopup="dialog", and a press opens no tab: it shows the help popover with the link as its trigger and records that
 *   the help was seen. The popover's "Open Visual Trace" opens the link's target and closes the popover.
 */
@Component({
  selector: 'app-trace-link',
  imports: [Icon, TraceHelpBlock],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <a
      #anchor
      class="trace-link"
      [href]="url()"
      target="_blank"
      rel="noopener noreferrer"
      [attr.aria-label]="help.needed() ? texts.signInName : null"
      [attr.aria-haspopup]="help.needed() ? 'dialog' : null"
      (click)="press($event)"
      ><span>{{ texts.trace }}</span><app-icon name="external-link" [size]="12" /><span class="visually-hidden"> {{ texts.opensInNewTab }}</span></a
    >
    <ng-template #panel>
      <app-trace-help [headingId]="headingId" [heading]="texts.signInHeading" (dismissed)="close()">
        <a class="button button-primary" [href]="url()" target="_blank" rel="noopener noreferrer" (click)="close()"
          >{{ texts.openVisualTrace }}<app-icon name="external-link" [size]="14" /><span class="visually-hidden">
            {{ texts.opensInNewTab }}</span
          ></a
        >
      </app-trace-help>
    </ng-template>
  `,
  styles: `
    :host {
      display: inline;
    }
    .trace-link {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      color: var(--trace-link-foreground);
      font-family: var(--font-ui);
      font-size: var(--trace-link-typography-font-size);
      font-weight: var(--trace-link-typography-font-weight);
      line-height: var(--trace-link-typography-line-height);
      text-decoration-line: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
    }
    .trace-link:hover,
    .trace-link:focus-visible {
      text-decoration-thickness: 2px;
    }
  `,
})
export class TraceLink {
  /** The payload's traceUrl, as served. */
  readonly url = input.required<string>();

  protected readonly help = inject(TraceHelp);
  protected readonly texts = TRACE_TEXTS;
  protected readonly headingId = newTraceHeadingId();
  private readonly popovers = inject(Popovers);
  private readonly container = inject(ViewContainerRef);
  private readonly anchor = viewChild.required<ElementRef<HTMLAnchorElement>>('anchor');
  private readonly panel = viewChild.required<TemplateRef<unknown>>('panel');
  private popover: PopoverRef | undefined;

  constructor() {
    inject(DestroyRef).onDestroy(() => this.popover?.close());
  }

  /** While the help is needed, a press shows it in place of opening the tab. */
  protected press(event: MouseEvent): void {
    if (!this.help.needed()) {
      return;
    }
    event.preventDefault();
    this.popover = this.popovers.show({
      trigger: this.anchor().nativeElement,
      content: this.panel(),
      viewContainerRef: this.container,
      labelledBy: this.headingId,
    });
    this.help.markSeen();
  }

  protected close(): void {
    this.popover?.close();
  }
}
