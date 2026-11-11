import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { LiveState } from '../live/live-state';
import { CurrentPage } from './current-page';

/**
 * The header navigation (Stories 33.2, 34.2, 37.2 and 25.2; UX-DR21): a navigation landmark named "Pages" with "Chat", for an admin "Settings", and "Documents",
 * "History" and "Usage" for every signed-in user (steps 3 and 6), each a link
 * (header-nav-item) whose current page is marked aria-current="page". The header sets --header-nav-gap and --header-nav-item-inline in the drawer
 * band (1024 to 1279px), where the links sit closer together so that the header fits on one line, and below 1024px, where they sit closer
 * together so that the left group of a signed-in user who is not an admin (Chat, Documents, History and Usage) fits one row at 640px (the header's
 * stacked band states the values). Whether the user is an admin is the snapshot's `admin`; it only decides the link, since the settings API refuses anyone else
 * (403 not_admin). The links wrap onto a second line when the window is too narrow for them in a row, so no link is hidden and the page
 * never scrolls sideways. It sits after the Demo view switch.
 */
@Component({
  selector: 'app-header-nav',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <nav class="nav" aria-label="Pages">
      <a class="header-nav-item" routerLink="/" [attr.aria-current]="page.page() === 'chat' ? 'page' : null">Chat</a>
      @if (admin()) {
        <a class="header-nav-item" routerLink="/settings" [attr.aria-current]="page.page() === 'settings' ? 'page' : null">Settings</a>
      }
      <a class="header-nav-item" routerLink="/documents" [attr.aria-current]="page.page() === 'documents' ? 'page' : null">Documents</a>
      <a class="header-nav-item" routerLink="/history" [attr.aria-current]="page.page() === 'history' ? 'page' : null">History</a>
      <a class="header-nav-item" routerLink="/usage" [attr.aria-current]="page.page() === 'usage' ? 'page' : null">Usage</a>
    </nav>
  `,
  styles: `
    :host {
      display: contents;
    }
    .nav {
      display: flex;
      flex-wrap: wrap;
      align-items: stretch;
      gap: var(--header-nav-gap, var(--space-2));
    }
    .header-nav-item {
      display: inline-flex;
      align-items: center;
      min-height: var(--space-target-min);
      padding: 0 var(--header-nav-item-inline, var(--space-2));
      color: var(--header-nav-item-foreground);
      font-family: var(--font-ui);
      font-size: var(--header-nav-item-typography-font-size);
      font-weight: var(--header-nav-item-typography-font-weight);
      line-height: var(--header-nav-item-typography-line-height);
      text-decoration-line: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
      border-bottom: 2px solid transparent;
    }
    .header-nav-item:hover {
      text-decoration-thickness: 2px;
    }
    .header-nav-item[aria-current='page'] {
      color: var(--header-nav-item-foreground-current);
      border-bottom-color: var(--action);
    }
  `,
})
export class HeaderNav {
  private readonly live = inject(LiveState);
  protected readonly page = inject(CurrentPage);

  /** True when the snapshot says the signed-in user holds OcuTalonAdmin. */
  protected readonly admin = computed(() => this.live.snapshot()?.admin === true);
}
