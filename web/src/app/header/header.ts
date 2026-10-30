import { CdkMenu, CdkMenuItem, CdkMenuItemRadio, CdkMenuTrigger } from '@angular/cdk/menu';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  DOCUMENT,
  ElementRef,
  Injector,
  ViewContainerRef,
  computed,
  effect,
  inject,
  signal,
  untracked,
  viewChild,
  type TemplateRef,
} from '@angular/core';

import { ABOUT_TITLE_ID, AboutDialog } from '../about/about-dialog';
import { Icon } from '../icon/icon';
import { DemoBusyState } from '../live/demo-busy-state';
import { LiveState } from '../live/live-state';
import { SessionGate } from '../session/session-gate';
import { Dialogs } from '../shared/dialogs';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { Layout } from '../shared/layout';
import { LAYOUT_QUERIES, LAYOUT_TEXTS, statusCount } from '../shared/layout-view';
import { Popovers, type PopoverRef } from '../shared/popover';
import { pendingApprovals } from '../rail/rail-view';
import { Tooltip } from '../shared/tooltip';
import { TraceHelp } from '../shared/trace-help';
import { newTraceHeadingId, TraceHelpBlock } from '../shared/trace-link';
import { conversationUrl, TRACE_TEXTS } from '../shared/trace-view';
import { Theme, type ThemeChoice } from '../theme/theme';
import { CredentialRows } from './credential-rows';
import { SignOutDialog, SIGN_OUT_FOCUS } from './sign-out-dialog';
import { SIGN_OUT_TEXT_ID } from './sign-out-texts';
import { ResetCountdown } from './reset-countdown';

/** The theme menu's options, in order. */
const THEME_OPTIONS: ReadonlyArray<{ value: ThemeChoice; label: string }> = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

/** The custom property that holds the header's measured block size, on the root element. */
const HEADER_SIZE = '--app-header-block-size';

/** Where focus goes when the Status button that holds it leaves with its band (UX-DR131): the main region. */
const STATUS_RULE: FocusRule = { within: '.status-button' };

/**
 * The app header. Left: the mark and the wordmark (underlined, as every link is), both linking to the main page, and the context badge (Online demo,
 * or Demo mode, or none). Right: the Visual Trace menu, the theme menu and the account menu, which holds About and Sign
 * out. Sign out goes through the API (SessionGate), which ends the CSP session and the whole sign-in group; on the online demo it asks
 * first, in a small dialog (SignOutDialog, Story 16.4), and ends the OcuTalon session too.
 *
 * The Visual Trace menu (UX-DR29, UX-DR39) is a ghost button with aria-haspopup="dialog" and aria-expanded; a press opens
 * one popover through Popovers and a press while it is open closes it. The popover holds "Open my conversation in Visual
 * Trace", a link to the newest turn's traceUrl that opens a new tab; with no such turn the link is aria-disabled, stays
 * focusable, has no href and does nothing, and says why under it: "Available after your first message.", which the link is
 * described by (aria-describedby) and which goes with the description when a turn gives the link its address. It is one element
 * either way, so a turn that arrives while it has focus leaves the focus on it. While the sign-in help is needed (TraceHelp) the popover is the help: it is
 * headed "Sign in to Visual Trace", holds the help text and "Don't show this again", and showing it records that the help
 * was seen. Otherwise it is headed "Visual Trace" and records nothing. On the online demo, where the snapshot carries the read-only
 * account (traceAccount), the popover also shows its user name and password below the link, each with a copy button
 * (CredentialRows); a local install's snapshot has no traceAccount and its popover has no such rows.
 *
 * On the online demo the right group also holds the reset countdown pill (ResetCountdown, Story 16.8), after the Status button and before
 * the Visual Trace menu. It is silent: the header announces nothing.
 *
 * In the drawer band (1024 to 1279px, Layout) the right group starts with the Status button, which opens and closes the rail's drawer
 * (aria-controls="status-region", aria-expanded). It shows "Status" and a count pill of the approval requests (the same count as the
 * rail's heading), both hidden from assistive technology beside the spoken name ("Status, 2 approval requests"). Before the snapshot
 * has loaded, and when it failed, it shows "Status" alone: it never shows a zero that it does not know. When the band changes while the
 * button holds focus, the button leaves and focus goes to the main region without scrolling, through the page's focus rule.
 *
 * Below 1024px the header is the page's one sticky element and is compact (48px minimum, 12px inline padding, may wrap). It writes its
 * measured block size to --app-header-block-size on the root element, which the stacked layout's scroll-padding-top reads, so that
 * the focused element is never scrolled under it.
 */
@Component({
  selector: 'app-header',
  imports: [CdkMenuTrigger, CdkMenu, CdkMenuItem, CdkMenuItemRadio, CredentialRows, Icon, ResetCountdown, TraceHelpBlock, Tooltip],
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
        @if (layout.band() === 'drawer') {
          <button
            type="button"
            class="button button-ghost header-button status-button"
            aria-controls="status-region"
            [attr.aria-expanded]="layout.drawerOpen()"
            (click)="layout.toggleStatus()"
          >
            @if (count(); as shown) {
              <span aria-hidden="true">{{ texts.status }}</span>
              <span class="count" aria-hidden="true">{{ shown.pill }}</span>
              <span class="visually-hidden">{{ texts.status }}, {{ shown.spoken }}</span>
            } @else {
              <span>{{ texts.status }}</span>
            }
          </button>
        }
        <app-reset-countdown />
        <button
          #traceTrigger
          type="button"
          class="button button-ghost header-button"
          aria-haspopup="dialog"
          [attr.aria-expanded]="traceOpen()"
          (click)="toggleTrace()"
        >
          <span>{{ traceTexts.menu }}</span>
          <app-icon name="external-link" />
        </button>
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
    <ng-template #tracePanel>
      <app-trace-help
        [headingId]="traceHeadingId"
        [heading]="traceHelpShown() ? traceTexts.signInHeading : traceTexts.menu"
        [signIn]="traceHelpShown()"
        (dismissed)="closeTrace()"
      >
        <a
          class="button"
          [class.button-primary]="conversation() !== undefined"
          [class.button-inactive]="conversation() === undefined"
          [attr.href]="conversation() ?? null"
          target="_blank"
          rel="noopener noreferrer"
          [attr.role]="conversation() === undefined ? 'link' : null"
          [attr.tabindex]="conversation() === undefined ? 0 : null"
          [attr.aria-disabled]="conversation() === undefined ? 'true' : null"
          [attr.aria-describedby]="conversation() === undefined ? conversationReasonId : null"
          (click)="pressConversation($event)"
          >{{ traceTexts.openConversation }}<app-icon name="external-link" [size]="14" /><span class="visually-hidden">
            {{ traceTexts.opensInNewTab }}</span
          ></a
        >
        @if (conversation() === undefined) {
          <p class="reason" [id]="conversationReasonId">{{ traceTexts.conversationNotYet }}</p>
        }
        @if (traceAccount(); as account) {
          <app-credential-rows [account]="account" />
        }
      </app-trace-help>
    </ng-template>
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
        <button type="button" class="item" cdkMenuItem (cdkMenuItemTriggered)="signOut()">Sign out</button>
      </div>
    </ng-template>
  `,
  styles: `
    :host {
      display: block;
    }
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
      text-decoration-line: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
      font-family: var(--font-display);
      font-size: var(--wordmark-typography-font-size);
      font-weight: var(--wordmark-typography-font-weight);
      line-height: var(--wordmark-typography-line-height);
      letter-spacing: var(--wordmark-typography-letter-spacing);
    }
    .home:hover .wordmark,
    .home:focus-visible .wordmark {
      text-decoration-thickness: 2px;
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
    .count {
      padding: 0 var(--space-2);
      border-radius: var(--tab-badge-radius);
      background: var(--tab-badge-background);
      color: var(--tab-badge-foreground);
      font-family: var(--font-ui);
      font-size: var(--tab-badge-typography-font-size);
      font-weight: var(--tab-badge-typography-font-weight);
      line-height: var(--tab-badge-typography-line-height);
    }
    @media ${LAYOUT_QUERIES.stacked} {
      :host {
        position: sticky;
        top: 0;
        z-index: 1;
      }
      .header {
        flex-wrap: wrap;
        gap: var(--space-1) var(--space-3);
        min-height: var(--space-12);
        padding-inline: var(--space-3);
      }
    }
    .reason {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
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
  protected readonly layout = inject(Layout);
  protected readonly theme = inject(Theme);
  private readonly dialogs = inject(Dialogs);
  private readonly gate = inject(SessionGate);
  private readonly demoBusy = inject(DemoBusyState);
  private readonly accountTrigger = viewChild.required<ElementRef<HTMLElement>>('accountTrigger');
  private readonly traceTrigger = viewChild.required<ElementRef<HTMLElement>>('traceTrigger');
  private readonly tracePanel = viewChild.required<TemplateRef<unknown>>('tracePanel');
  private readonly popovers = inject(Popovers);
  private readonly traceHelp = inject(TraceHelp);
  private readonly container = inject(ViewContainerRef);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private tracePopover: PopoverRef | undefined;

  protected readonly texts = LAYOUT_TEXTS;
  protected readonly traceTexts = TRACE_TEXTS;
  protected readonly traceHeadingId = newTraceHeadingId();
  /** The id of the reason that the inactive conversation link is described by. */
  protected readonly conversationReasonId = 'trace-conversation-reason';
  /** True while the Visual Trace popover is open. */
  protected readonly traceOpen = signal(false);
  /** True when the open popover is the sign-in help; fixed when it opens, because opening records that the help was seen. */
  protected readonly traceHelpShown = signal(false);
  /** The read-only Visual Trace account of the snapshot: present on the online demo only. */
  protected readonly traceAccount = computed(() => this.live.snapshot()?.traceAccount);
  /** The target of "Open my conversation in Visual Trace": the newest turn's traceUrl, undefined with no such turn. */
  protected readonly conversation = computed(() => conversationUrl(this.live.store()?.chat));

  protected readonly themeOptions = THEME_OPTIONS;

  /** Online demo, else Demo mode, else nothing. */
  protected readonly badge = computed(() => {
    const snapshot = this.live.snapshot();
    if (snapshot?.onlineDemo) {
      return 'Online demo';
    }
    return snapshot?.demoMode ? 'Demo mode' : '';
  });

  /** The Status button's count: the pending approval requests of the loaded store, none before the snapshot has loaded or when it failed. */
  protected readonly count = computed(() => {
    const store = this.live.store();
    return statusCount(this.live.status() === 'loaded' && store !== undefined ? pendingApprovals(store).length : undefined);
  });

  /** The signed-in user's name, or Account until the snapshot loads (and when it fails). */
  protected readonly accountName = computed(() => this.live.snapshot()?.user || 'Account');

  /** The theme button's name and tooltip. */
  protected readonly themeName = computed(
    () => `Theme: ${THEME_OPTIONS.find((option) => option.value === this.theme.choice())?.label ?? 'System'}`,
  );

  constructor() {
    effect(() => {
      this.layout.band();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, STATUS_RULE));
    });
    const destroyed = inject(DestroyRef);
    const host = this.host.nativeElement;
    const root = inject(DOCUMENT).documentElement;
    const observer = new ResizeObserver(() => root.style.setProperty(HEADER_SIZE, `${host.getBoundingClientRect().height}px`));
    observer.observe(host);
    destroyed.onDestroy(() => {
      observer.disconnect();
      this.tracePopover?.close();
    });
  }

  /** Opens the Visual Trace popover, or closes it when it is open. */
  protected toggleTrace(): void {
    if (this.tracePopover?.isOpen) {
      this.tracePopover.close();
      return;
    }
    this.traceHelpShown.set(this.traceHelp.needed());
    const popover = this.popovers.show({
      trigger: this.traceTrigger().nativeElement,
      content: this.tracePanel(),
      viewContainerRef: this.container,
      labelledBy: this.traceHeadingId,
    });
    this.tracePopover = popover;
    this.traceOpen.set(true);
    popover.closed.subscribe(() => this.traceOpen.set(false));
    if (this.traceHelpShown()) {
      this.traceHelp.markSeen();
    }
  }

  protected closeTrace(): void {
    this.tracePopover?.close();
  }

  /**
   * "Open my conversation in Visual Trace": with a turn the press opens the tab and closes the popover; with none it does nothing.
   * On the online demo the press is taken over (Story 16.5): the page checks the public status first, and opens the tab only when
   * the demo is not busy (DemoBusyState.openTrace).
   */
  protected pressConversation(event: MouseEvent): void {
    const url = this.conversation();
    if (url === undefined) {
      event.preventDefault();
      return;
    }
    if (this.live.snapshot()?.onlineDemo === true) {
      event.preventDefault();
      this.closeTrace();
      void this.demoBusy.openTrace(url);
      return;
    }
    this.closeTrace();
  }

  /**
   * The account menu's Sign out. On the online demo it opens the confirm dialog (Story 16.4; UX-DR30), whose focus starts on Cancel and
   * returns to the account trigger when it closes; its Sign out signs out. Anywhere else it signs out at once.
   */
  protected signOut(): void {
    if (this.live.snapshot()?.onlineDemo === true) {
      this.dialogs.open(SignOutDialog, {
        labelledBy: SIGN_OUT_TEXT_ID,
        restoreFocus: this.accountTrigger().nativeElement,
        autoFocus: SIGN_OUT_FOCUS,
      });
      return;
    }
    this.gate.signOut();
  }

  protected openAbout(): void {
    this.dialogs.open(AboutDialog, { labelledBy: ABOUT_TITLE_ID, restoreFocus: this.accountTrigger().nativeElement });
  }
}
