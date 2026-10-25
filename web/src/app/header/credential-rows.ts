import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, computed, inject, input, signal } from '@angular/core';

import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { TRACE_TEXTS } from '../shared/trace-view';

/** How long a row shows "Copied", in milliseconds. */
const COPIED_MS = 2000;

/** The read-only Visual Trace account that the online demo publishes (the snapshot's traceAccount). */
export interface TraceAccount {
  user: string;
  password: string;
}

/** One credential row: what the row is, its label, its value and the name of its copy button. */
interface CredentialRow {
  key: 'user' | 'password';
  label: string;
  value: string;
  copyName: string;
}

/**
 * The read-only Visual Trace account's credentials, one row each ("User name", "Password"): the label, the value in the mono
 * type on a credential card, and an icon button that copies the value (UX-DR39, UX-DR87). The Visual Trace menu shows it on the
 * online demo only.
 * - A copy that succeeds writes exactly the value to the clipboard, shows "Copied" in that row for 2 seconds and announces
 *   "Copied" through the Announcer.
 * - A copy that fails (a rejected promise, or no clipboard) shows "Couldn't copy. Select the text and copy it yourself." under
 *   the rows until the next copy or until the rows go away with their popover, announces it, and selects that row's value text.
 */
@Component({
  selector: 'app-credential-rows',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (row of rows(); track row.key) {
      <div class="row">
        <span class="label">{{ row.label }}</span>
        <div class="card">
          <span class="value" [attr.data-credential]="row.key">{{ row.value }}</span>
          @if (copied() === row.key) {
            <span class="copied">{{ texts.copied }}</span>
          }
          <button type="button" class="button button-ghost copy" [attr.aria-label]="row.copyName" (click)="copy(row)">
            <app-icon name="copy" [size]="16" />
          </button>
        </div>
      </div>
    }
    @if (failed()) {
      <p class="failure">{{ texts.copyFailed }}</p>
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      align-self: stretch;
    }
    .row {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .label {
      color: var(--ink-muted);
      font-family: var(--type-caption-font-family);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
      line-height: var(--type-caption-line-height);
    }
    .card {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      padding: var(--space-1) var(--space-1) var(--space-1) var(--space-3);
      background: var(--credential-card-background);
      border: var(--credential-card-border);
      border-radius: var(--credential-card-radius);
    }
    .value {
      flex: 1 1 auto;
      min-width: 0;
      color: var(--ink);
      font-family: var(--credential-card-value-typography-font-family), monospace;
      font-size: var(--credential-card-value-typography-font-size);
      font-weight: var(--credential-card-value-typography-font-weight);
      line-height: var(--credential-card-value-typography-line-height);
      overflow-wrap: anywhere;
      user-select: all;
    }
    .copied {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .copy {
      flex: 0 0 auto;
      min-width: var(--space-target-min);
      padding: 0;
    }
    .failure {
      margin: 0;
      color: var(--danger-ink);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
  `,
})
export class CredentialRows {
  /** The account whose user name and password the rows show. */
  readonly account = input.required<TraceAccount>();

  protected readonly texts = TRACE_TEXTS;
  /** The row that shows "Copied", for COPIED_MS after its copy. */
  protected readonly copied = signal<CredentialRow['key'] | undefined>(undefined);
  /** True while the failure line is shown. */
  protected readonly failed = signal(false);
  protected readonly rows = computed<CredentialRow[]>(() => [
    { key: 'user', label: TRACE_TEXTS.userNameLabel, value: this.account().user, copyName: TRACE_TEXTS.copyUserName },
    { key: 'password', label: TRACE_TEXTS.passwordLabel, value: this.account().password, copyName: TRACE_TEXTS.copyPassword },
  ]);

  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly announcer = inject(Announcer);
  private timer: ReturnType<typeof setTimeout> | undefined;
  private gone = false;

  constructor() {
    inject(DestroyRef).onDestroy(() => {
      this.gone = true;
      clearTimeout(this.timer);
    });
  }

  /** Copies the row's value; a failure of any kind shows the failure line, announces it and selects the row's value. */
  protected async copy(row: CredentialRow): Promise<void> {
    clearTimeout(this.timer);
    this.copied.set(undefined);
    this.failed.set(false);
    try {
      const clipboard = globalThis.navigator?.clipboard;
      if (clipboard === undefined) {
        throw new Error('no clipboard');
      }
      await clipboard.writeText(row.value);
    } catch {
      if (!this.gone) {
        this.failed.set(true);
        this.announcer.announce(TRACE_TEXTS.copyFailed);
        this.select(row.key);
      }
      return;
    }
    if (this.gone) {
      return;
    }
    this.copied.set(row.key);
    this.announcer.announce(TRACE_TEXTS.copied);
    this.timer = setTimeout(() => this.copied.set(undefined), COPIED_MS);
  }

  /** Makes the page's selection exactly the row's value text. */
  private select(key: CredentialRow['key']): void {
    const value = this.host.nativeElement.querySelector(`[data-credential="${key}"]`);
    const selection = globalThis.getSelection?.();
    if (value === null || !selection) {
      return;
    }
    const range = document.createRange();
    range.selectNodeContents(value);
    selection.removeAllRanges();
    selection.addRange(range);
  }
}
