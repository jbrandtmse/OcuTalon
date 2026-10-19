import { ChangeDetectionStrategy, Component } from '@angular/core';

import { Header } from './header/header';

/** The page: the app header over an empty main region with its one visually hidden heading. */
@Component({
  selector: 'app-root',
  imports: [Header],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-header />
    <main class="main">
      <h1 class="visually-hidden">OcuTalon</h1>
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      min-height: 100vh;
    }
    .main {
      flex: 1;
      background: var(--bg);
    }
  `,
})
export class App {}
