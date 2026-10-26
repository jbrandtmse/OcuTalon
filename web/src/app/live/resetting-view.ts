import { ChangeDetectionStrategy, Component, DOCUMENT, DestroyRef, inject } from '@angular/core';

import { RESET_TEXTS } from './reset-schedule';

/**
 * The resetting view (EXPERIENCE: Pages, The resetting view; Story 16.8): what the page shows from the moment it enters the reset
 * until the demo is back and it goes to the splash. App renders it in place of the whole app. It has the maintenance page's logo
 * (320px, light or dark with the page's theme), card (400px), heading, text and tab title, on the splash canvas, with styles from the
 * tokens only. It is the page's main region, so the focus rule has a place for the focus that the switch removed. It shows nothing
 * else, announces nothing and calls nothing: ResetWatch waits for the demo.
 */
@Component({
  selector: 'app-resetting-view',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="main resetting" tabindex="-1">
      <picture class="logo logo-light">
        <img
          src="assets/brand/OcuTalon-Logo-light-640.png"
          srcset="assets/brand/OcuTalon-Logo-light-640.png 1x, assets/brand/OcuTalon-Logo-light-1280.png 2x"
          alt="OcuTalon"
          width="320"
        />
      </picture>
      <picture class="logo logo-dark">
        <img
          src="assets/brand/OcuTalon-Logo-dark-640.png"
          srcset="assets/brand/OcuTalon-Logo-dark-640.png 1x, assets/brand/OcuTalon-Logo-dark-1280.png 2x"
          alt="OcuTalon"
          width="320"
        />
      </picture>
      <div class="card">
        <h1>{{ texts.heading }}</h1>
        <p>{{ texts.body }}</p>
      </div>
    </main>
  `,
  styles: `
    :host {
      display: block;
      min-height: 100vh;
      min-height: 100dvh;
      background: var(--splash-canvas-background);
    }
    .resetting {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: inherit;
      padding: var(--space-6);
      outline: none;
    }
    .logo {
      display: block;
      width: 320px;
      max-width: 100%;
      margin: 0 auto -4px;
    }
    .logo img {
      display: block;
      width: 100%;
    }
    .logo-dark {
      display: none;
    }
    :host-context(html[data-theme='dark']) .logo-light {
      display: none;
    }
    :host-context(html[data-theme='dark']) .logo-dark {
      display: block;
    }
    @media (prefers-color-scheme: dark) {
      :host-context(html:not([data-theme='light'])) .logo-light {
        display: none;
      }
      :host-context(html:not([data-theme='light'])) .logo-dark {
        display: block;
      }
    }
    .card {
      width: 400px;
      max-width: 100%;
      padding: var(--space-6);
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--rounded-md);
    }
    h1 {
      margin: 0 0 var(--space-4);
      color: var(--ink);
      font-size: var(--type-display-lg-font-size);
      font-weight: var(--type-display-lg-font-weight);
      line-height: var(--type-display-lg-line-height);
      letter-spacing: var(--type-display-lg-letter-spacing);
    }
    p {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-font-size);
      line-height: var(--type-body-line-height);
    }
  `,
})
export class ResettingView {
  protected readonly texts = RESET_TEXTS;

  constructor() {
    const document = inject(DOCUMENT);
    const before = document.title;
    document.title = RESET_TEXTS.title;
    inject(DestroyRef).onDestroy(() => {
      document.title = before;
    });
  }
}
