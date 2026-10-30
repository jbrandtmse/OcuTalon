import { DialogRef } from '@angular/cdk/dialog';
import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';

import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import { README_URL } from '../links';

/** The id of the dialog's heading, which names the dialog. */
export const ABOUT_TITLE_ID = 'about-title';

/** The name of the dialog's icon-only Close button: its action and its object (Story 2.14). */
export const ABOUT_CLOSE_NAME = 'Close About OcuTalon';

/**
 * The About dialog: what OcuTalon is, its version and its default model. It is opened through Dialogs. It is at most as tall as the
 * viewport less 16px above and below, and it scrolls, keeping the scroll gutter, when its text is taller (a large text size, a short
 * window). Its Close button is at the dialog's top right.
 */
@Component({
  selector: 'app-about-dialog',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="body">
      <h2 [id]="titleId" tabindex="-1">{{ title() }}</h2>
      <p>An AI assistant for InterSystems IRIS.</p>
      <p>
        An assistant that runs as an IRIS Interoperability production and decides, for everything that arrives, whether
        it deserves your attention.
      </p>
      @if (model(); as name) {
        <p>Default model: {{ name }}.</p>
      }
      <p>
        <a class="link" [href]="readme" target="_blank" rel="noopener noreferrer">
          README
          <app-icon name="external-link" />
          <span class="visually-hidden"> (opens in a new tab)</span>
        </a>
      </p>
      <p>Built with the BMAD Method and Claude Code.</p>
      <p>OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.</p>
    </div>
    <button type="button" class="button button-ghost close" [attr.aria-label]="closeName" (click)="close()">
      <app-icon name="x" [size]="16" />
    </button>
  `,
  styles: `
    :host {
      position: relative;
      display: block;
      width: min(480px, calc(100vw - 32px));
      max-height: calc(100vh - 2 * var(--space-4));
      max-height: calc(100dvh - 2 * var(--space-4));
      padding: var(--space-6);
      overflow-y: auto;
      scroll-padding: var(--space-scroll-gutter);
      background: var(--dialog-background);
      border-radius: var(--dialog-radius);
      box-shadow: var(--dialog-shadow);
      color: var(--ink);
    }
    .body p {
      margin: 0 0 var(--space-3);
    }
    .body p:last-child {
      margin-bottom: 0;
    }
    h2 {
      margin: 0 var(--space-8) var(--space-3) 0;
      font-size: var(--type-headline-font-size);
      font-weight: var(--type-headline-font-weight);
      line-height: var(--type-headline-line-height);
    }
    .link {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
    }
    .close {
      position: absolute;
      top: var(--space-3);
      right: var(--space-3);
      padding: 0 var(--space-2);
    }
  `,
})
export class AboutDialog {
  private readonly dialogRef = inject(DialogRef);
  private readonly live = inject(LiveState);

  protected readonly titleId = ABOUT_TITLE_ID;
  protected readonly closeName = ABOUT_CLOSE_NAME;
  protected readonly readme = README_URL;
  protected readonly title = computed(() => {
    const version = this.live.snapshot()?.version ?? '';
    return version ? `OcuTalon ${version}` : 'OcuTalon';
  });
  protected readonly model = computed(() => this.live.snapshot()?.models.triage ?? '');

  protected close(): void {
    this.dialogRef.close();
  }
}
