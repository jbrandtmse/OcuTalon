import { DOCUMENT, Injectable, Injector, afterNextRender, computed, inject, signal } from '@angular/core';

import { LAYOUT_QUERIES } from './layout-view';
import { Popovers } from './popover';

/** The width bands, narrowest last: see LAYOUT_QUERIES. */
export type Band = 'wide' | 'reference' | 'drawer' | 'stacked';

/** The status region, which is the rail, and the header's button that shows it in the drawer band. */
const RAIL_REGION = 'section.rail';
const STATUS_BUTTON = 'button.status-button';

/**
 * The page's width band and the status drawer (Story 2.15; FR-12, UX-DR20, UX-DR137), read from the one set of queries of
 * layout-view.ts through matchMedia, so that the CSS and the code agree on the bands. The service never reads a zoom level.
 * - `band` is wide (1440px and up), reference (1280 to 1439px), drawer (1024 to 1279px) or stacked (below 1024px); `stacked` says the last.
 * - `drawerOpen` is the drawer's state and matters only in the drawer band. On entering the band the drawer is closed, unless focus is
 *   inside the rail (a popover whose trigger is inside the rail counts), where it is open, so that focus survives the change.
 * - `focusRegion(selector)` focuses the region at once when it shows, and scrolls its top into view (below the sticky header, in the
 *   column). The rail in a closed drawer is opened first and focused after the next render, since it is not displayed until then. This
 *   is the user's own move: a skip link or the Status button.
 * - `toggleStatus()` opens the drawer and focuses the rail, or closes it. `closeDrawer()` closes it, and moves focus to the Status
 *   button when focus was inside the rail, so that it does not fall to the page.
 * The drawer pushes the chat aside; it is no overlay and no modal.
 */
@Injectable({ providedIn: 'root' })
export class Layout {
  private readonly document = inject(DOCUMENT);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);
  private readonly stackedQuery = this.query(LAYOUT_QUERIES.stacked);
  private readonly drawerQuery = this.query(LAYOUT_QUERIES.drawer);
  private readonly wideQuery = this.query(LAYOUT_QUERIES.wide);
  private readonly bandState = signal<Band>(this.read());
  private readonly drawerState = signal(false);

  /** The current band. */
  readonly band = this.bandState.asReadonly();

  /** True below 1024px, where the page is one scrolling column. */
  readonly stacked = computed(() => this.bandState() === 'stacked');

  /** True while the drawer shows (in the drawer band). */
  readonly drawerOpen = this.drawerState.asReadonly();

  constructor() {
    for (const query of [this.stackedQuery, this.drawerQuery, this.wideQuery]) {
      query?.addEventListener('change', () => this.changed());
    }
  }

  /** Opens the drawer and focuses the rail, or closes the drawer when it is open. */
  toggleStatus(): void {
    if (this.drawerState()) {
      this.closeDrawer();
    } else {
      this.focusRegion(RAIL_REGION);
    }
  }

  /** Focuses the region at once when it shows; the rail in a closed drawer opens the drawer and is focused after the next render. */
  focusRegion(selector: string): void {
    if (selector === RAIL_REGION && this.bandState() === 'drawer' && !this.drawerState()) {
      this.drawerState.set(true);
      afterNextRender(() => this.focusTarget(selector), { injector: this.injector });
      return;
    }
    this.focusTarget(selector);
  }

  /** Closes the drawer; focus that was inside the rail moves to the Status button. */
  closeDrawer(): void {
    if (this.bandState() !== 'drawer' || !this.drawerState()) {
      return;
    }
    if (this.focusInRail()) {
      this.document.querySelector<HTMLElement>(STATUS_BUTTON)?.focus();
    }
    this.drawerState.set(false);
  }

  /** The media query list for the query, or undefined where the page has no window. */
  private query(text: string): MediaQueryList | undefined {
    return this.document.defaultView?.matchMedia(text);
  }

  /** The band that the queries say. */
  private read(): Band {
    if (this.stackedQuery?.matches) {
      return 'stacked';
    }
    if (this.drawerQuery?.matches) {
      return 'drawer';
    }
    return this.wideQuery?.matches ? 'wide' : 'reference';
  }

  /** A query changed: on entering the drawer band the drawer is open only when focus is inside the rail. */
  private changed(): void {
    const before = this.bandState();
    const now = this.read();
    if (now === before) {
      return;
    }
    if (now === 'drawer') {
      this.drawerState.set(this.focusInRail());
    }
    this.bandState.set(now);
  }

  /** Whether focus is inside the rail, directly or through a popover whose trigger is inside it. */
  private focusInRail(): boolean {
    const active = this.document.activeElement;
    if (active === null) {
      return false;
    }
    const focused = this.popovers.triggerOf(active) ?? active;
    return this.document.querySelector(RAIL_REGION)?.contains(focused) ?? false;
  }

  /** Focuses the region and scrolls its top into view, clear of the sticky header: a region of the column is taller than the window. */
  private focusTarget(selector: string): void {
    const region = this.document.querySelector<HTMLElement>(selector);
    region?.focus({ preventScroll: true });
    region?.scrollIntoView({ block: 'start', inline: 'nearest' });
  }
}
