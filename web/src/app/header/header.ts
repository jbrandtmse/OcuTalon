import { CdkMenu, CdkMenuItem, CdkMenuTrigger } from '@angular/cdk/menu';
import { ChangeDetectionStrategy, Component } from '@angular/core';

import { Icon } from '../icon/icon';

/**
 * The app header: the mark and the wordmark, both linking to the main page, and the account menu.
 * Sign out leaves the application through IRIS's own sign-out, which ends the whole sign-in group.
 */
@Component({
  selector: 'app-header',
  imports: [CdkMenuTrigger, CdkMenu, CdkMenuItem, Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="header">
      <a class="home" href="#/">
        <img class="mark" src="assets/brand/icon-192.png" alt="" width="28" height="28" />
        <span class="wordmark"><span class="ocu">Ocu</span><span class="talon">Talon</span></span>
      </a>
      <button type="button" class="trigger" [cdkMenuTriggerFor]="account">
        <span>Account</span>
        <app-icon name="chevron-down" />
      </button>
    </header>
    <ng-template #account>
      <div class="menu" cdkMenu aria-label="Account">
        <a class="item" cdkMenuItem href="/ocutalon/?IRISLogout=end">Sign out</a>
      </div>
    </ng-template>
  `,
  styles: `
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: var(--space-header-height);
      padding: 0 var(--space-4);
      background: var(--app-header-background);
      border-bottom: var(--app-header-border-bottom);
      color: var(--app-header-foreground);
    }
    .home {
      display: inline-flex;
      align-items: center;
      gap: var(--space-3);
      color: inherit;
      text-decoration: none;
    }
    .mark {
      display: block;
    }
    .wordmark {
      margin-left: -2px;
      font-family: var(--font-display);
      font-size: var(--wordmark-typography-font-size);
      font-weight: var(--wordmark-typography-font-weight);
      line-height: var(--wordmark-typography-line-height);
      letter-spacing: var(--wordmark-typography-letter-spacing);
    }
    .ocu {
      color: var(--wordmark-ocu);
    }
    .talon {
      color: var(--wordmark-talon);
    }
    .trigger {
      display: inline-flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-control-height-sm);
      padding: 0 var(--space-2);
      border: 0;
      border-radius: var(--rounded-sm);
      background: transparent;
      color: var(--ink);
      font: inherit;
      font-weight: var(--type-body-strong-font-weight);
      cursor: pointer;
    }
    .trigger:hover {
      background: var(--action-soft);
    }
    .menu {
      display: flex;
      flex-direction: column;
      min-width: 160px;
      padding: var(--space-1);
      background: var(--popover-background);
      border: var(--popover-border);
      border-radius: var(--popover-radius);
      box-shadow: var(--popover-shadow);
    }
    .item {
      display: block;
      min-height: var(--space-target-min);
      padding: 6px var(--space-3);
      border-radius: var(--rounded-sm);
      color: var(--ink);
      font-size: var(--type-body-font-size);
      line-height: var(--type-body-line-height);
      text-decoration: none;
      cursor: pointer;
    }
    .item:hover,
    .item:focus-visible {
      background: var(--action-soft);
    }
  `,
})
export class Header {}
