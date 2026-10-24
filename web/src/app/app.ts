import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { BannerStack } from './banners/banner-stack';
import { Header } from './header/header';
import { LiveState } from './live/live-state';

/**
 * The page: the app header, the slot for the banners that sit under it, and the routed page. The slot holds the stack of status
 * banners (Story 2.10), which takes the height it needs and leaves the routed page the rest. The snapshot loads once
 * per page load, through LiveState, and every part of the page reads it from there. The app is the viewport's height, so the
 * routed page's regions scroll on their own.
 */
@Component({
  selector: 'app-root',
  imports: [BannerStack, Header, RouterOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-header />
    <div class="banner-slot"><app-banner-stack /></div>
    <router-outlet />
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      height: 100vh;
      height: 100dvh;
    }
    .banner-slot {
      flex: none;
    }
  `,
})
export class App {
  constructor() {
    inject(LiveState).load();
  }
}
