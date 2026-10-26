import { ChangeDetectionStrategy, Component, ElementRef, Injector, effect, inject, untracked } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { BannerStack } from './banners/banner-stack';
import { Header } from './header/header';
import { SkipLinks } from './header/skip-links';
import { LiveState } from './live/live-state';
import { ResetWatch } from './live/reset-watch';
import { ResettingView } from './live/resetting-view';
import { type FocusRule, keepFocus } from './shared/focus-rule';
import { LAYOUT_QUERIES } from './shared/layout-view';
import { Popovers } from './shared/popover';

/** The switch to the resetting view removes the whole app, so a focus anywhere in it goes to the view's main region. */
const RESETTING_RULE: FocusRule = {};

/**
 * The page: the skip links, which come first so that they are the first tab stops (Story 2.14), the app header, the slot for the
 * banners that sit under it, and the routed page. The slot holds the stack of status
 * banners (Story 2.10), which takes the height it needs and leaves the routed page the rest. The snapshot loads once
 * per page load, through LiveState, and every part of the page reads it from there. From 1024px wide the app is the viewport's height,
 * so the routed page's regions scroll on their own; below it (the stacked column, Story 2.15) it is at least the viewport's height and
 * the page itself scrolls. At the reset (ResetWatch) the whole app gives way to the resetting view (Story 16.8); the focus rule moves a
 * focus that the switch removed to the view's main region.
 */
@Component({
  selector: 'app-root',
  imports: [BannerStack, Header, ResettingView, RouterOutlet, SkipLinks],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (reset.resetting()) {
      <app-resetting-view />
    } @else {
      <app-skip-links />
      <app-header />
      <div class="banner-slot"><app-banner-stack /></div>
      <router-outlet />
    }
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
  protected readonly reset = inject(ResetWatch);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);

  constructor() {
    inject(LiveState).load();
    effect(() => {
      this.reset.resetting();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, RESETTING_RULE));
    });
  }
}
