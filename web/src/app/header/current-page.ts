import { DOCUMENT } from '@angular/common';
import { computed, inject, Injectable } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router } from '@angular/router';
import { filter, map } from 'rxjs';

import { pageOf } from '../shared/page-shell-view';

/**
 * Which page the app shows (Stories 33.2, 34.2 and 37.2): the chat (the main page), the settings page, the Documents page or the Usage page. It starts from the address the page was opened with, which
 * the hash location puts after the #, so that a deep link to #/settings never shows the main page's skip links for a moment, and follows the router.
 * The header navigation marks the current page with it, and the app shows the skip links and the demo guide on the main page only (D8).
 */
@Injectable({ providedIn: 'root' })
export class CurrentPage {
  private readonly address = toSignal(
    inject(Router).events.pipe(
      filter((event): event is NavigationEnd => event instanceof NavigationEnd),
      map((event) => event.urlAfterRedirects),
    ),
    { initialValue: inject(DOCUMENT).location?.hash ?? '' },
  );

  /** The page: settings, documents, usage or chat. */
  readonly page = computed(() => pageOf(this.address()));

  /** True on the main page, the chat. */
  readonly onMain = computed(() => this.page() === 'chat');
}
