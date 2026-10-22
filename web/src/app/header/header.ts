import { CdkMenu, CdkMenuItem, CdkMenuItemRadio, CdkMenuTrigger } from '@angular/cdk/menu';
import { ChangeDetectionStrategy, Component, computed, inject, viewChild, type ElementRef } from '@angular/core';

import { ABOUT_TITLE_ID, AboutDialog } from '../about/about-dialog';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import { Dialogs } from '../shared/dialogs';
import { Tooltip } from '../shared/tooltip';
import { Theme, type ThemeChoice } from '../theme/theme';

/** The theme menu's options, in order. */
const THEME_OPTIONS: ReadonlyArray<{ value: ThemeChoice; label: string }> = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

/**
 * The app header. Left: the mark and the wordmark, both linking to the main page, and the context badge (Online demo,
 * or Demo mode, or none). Right: the theme menu and the account menu, which holds About and Sign out. Sign out leaves
 * the application through IRIS's own sign-out, which ends the whole sign-in group.
 */
@Component({
  selector: 'app-header',
  imports: [CdkMenuTrigger, CdkMenu, CdkMenuItem, CdkMenuItemRadio, Icon, Tooltip],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="header">
      <div class="side">
        <a class="home" href="#/">
          <img class="mark" src="assets/brand/icon-192.png" alt="" width="28" height="28" />
          <span class="wordmark"><span class="ocu">Ocu</span><span class="talon">Talon</span></span>
        </a>
        @if (badge(); as text) {
          <span class="context-badge">{{ text }}</span>
        }
      </div>
      <div class="side right">
        <button
          type="button"
          class="button button-ghost header-button"
          [cdkMenuTriggerFor]="themeMenu"
          [attr.aria-label]="themeName()"
          [appTooltip]="themeName()"
        >
          <app-icon name="contrast" [size]="16" />
          <app-icon name="chevron-down" />
        </button>
        <button
          #accountTrigger
          type="button"
          class="button button-ghost header-button"
          [cdkMenuTriggerFor]="account"
        >
          <span>{{ accountName() }}</span>
          <app-icon name="chevron-down" />
        </button>
      </div>
    </header>
    <ng-template #themeMenu>
      <div class="menu" cdkMenu aria-label="Theme">
        @for (option of themeOptions; track option.value) {
          <button
            type="button"
            class="item"
            cdkMenuItemRadio
            [cdkMenuItemChecked]="theme.choice() === option.value"
            (cdkMenuItemTriggered)="theme.set(option.value)"
          >
            <span class="check">
              @if (theme.choice() === option.value) {
                <app-icon name="check" />
              }
            </span>
            <span>{{ option.label }}</span>
          </button>
        }
      </div>
    </ng-template>
    <ng-template #account>
      <div class="menu" cdkMenu aria-label="Account">
        <button type="button" class="item" cdkMenuItem (cdkMenuItemTriggered)="openAbout()">About OcuTalon</button>
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
    .side {
      display: flex;
      align-items: center;
      gap: var(--space-3);
    }
    .right {
      gap: var(--space-2);
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
    .context-badge {
      padding: 3px 10px;
      border-radius: var(--context-badge-radius);
      background: var(--context-badge-background);
      color: var(--context-badge-foreground);
      font-family: var(--font-ui);
      font-size: var(--context-badge-typography-font-size);
      font-weight: var(--context-badge-typography-font-weight);
      line-height: var(--context-badge-typography-line-height);
      letter-spacing: var(--context-badge-typography-letter-spacing);
    }
    .header-button {
      gap: 6px;
      padding: 0 var(--space-2);
      color: var(--ink);
      font-weight: var(--type-body-strong-font-weight);
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
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-target-min);
      padding: 6px var(--space-3);
      border: 0;
      border-radius: var(--rounded-sm);
      background: transparent;
      color: var(--ink);
      font: inherit;
      text-align: left;
      text-decoration: none;
      cursor: pointer;
    }
    .item:hover,
    .item:focus-visible {
      background: var(--action-soft);
    }
    .check {
      display: inline-flex;
      width: 14px;
      color: var(--action-ink);
    }
  `,
})
export class Header {
  protected readonly live = inject(LiveState);
  protected readonly theme = inject(Theme);
  private readonly dialogs = inject(Dialogs);
  private readonly accountTrigger = viewChild.required<ElementRef<HTMLElement>>('accountTrigger');

  protected readonly themeOptions = THEME_OPTIONS;

  /** Online demo, else Demo mode, else nothing. */
  protected readonly badge = computed(() => {
    const snapshot = this.live.snapshot();
    if (snapshot?.onlineDemo) {
      return 'Online demo';
    }
    return snapshot?.demoMode ? 'Demo mode' : '';
  });

  /** The signed-in user's name, or Account until the snapshot loads (and when it fails). */
  protected readonly accountName = computed(() => this.live.snapshot()?.user || 'Account');

  /** The theme button's name and tooltip. */
  protected readonly themeName = computed(
    () => `Theme: ${THEME_OPTIONS.find((option) => option.value === this.theme.choice())?.label ?? 'System'}`,
  );

  protected openAbout(): void {
    this.dialogs.open(AboutDialog, { labelledBy: ABOUT_TITLE_ID, restoreFocus: this.accountTrigger().nativeElement });
  }
}
