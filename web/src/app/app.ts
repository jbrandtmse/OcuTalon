import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { Header } from './header/header';
import { LiveState } from './live/live-state';

/**
 * The page: the app header, the slot for the banners that sit under it, and the routed page. The snapshot loads once
 * per page load, through LiveState, and every part of the page reads it from there.
 */
@Component({
  selector: 'app-root',
  imports: [Header, RouterOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-header />
    <div class="banner-slot"></div>
    <router-outlet />
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      min-height: 100vh;
    }
  `,
})
export class App {
  constructor() {
    inject(LiveState).load();
  }
}
