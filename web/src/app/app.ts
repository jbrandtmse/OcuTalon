import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { BannerStack } from './banners/banner-stack';
import { DemoGuide } from './guide/demo-guide';
import { Header } from './header/header';
import { SkipLinks } from './header/skip-links';
import { LiveState } from './live/live-state';
import { LAYOUT_QUERIES } from './shared/layout-view';

/**
 * The page: the skip links, which come first so that they are the first tab stops (Story 2.14), the app header, the slot for the
 * banners that sit under it, the demo guide (Story 4.4; it shows in demo mode only, between the banners and the rail and chat, and takes
 * the height it needs) and the routed page. The slot holds the stack of status
 * banners (Story 2.10), which takes the height it needs and leaves the routed page the rest. The snapshot loads once
 * per page load, through LiveState, and every part of the page reads it from there. From 1024px wide the app is the viewport's height,
 * so the routed page's regions scroll on their own; below it (the stacked column, Story 2.15) it is at least the viewport's height and
 * the page itself scrolls.
 */
@Component({
  selector: 'app-root',
  imports: [BannerStack, DemoGuide, Header, RouterOutlet, SkipLinks],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-skip-links />
    <app-header />
    <div class="banner-slot"><app-banner-stack /></div>
    <app-demo-guide />
    <router-outlet />
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      min-height: 100vh;
      min-height: 100dvh;
    }
    @media ${LAYOUT_QUERIES.framed} {
      :host {
        height: 100vh;
        height: 100dvh;
      }
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
