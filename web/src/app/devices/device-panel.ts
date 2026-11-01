import { ChangeDetectionStrategy, Component, ElementRef, Injector, computed, effect, inject, signal, untracked } from '@angular/core';

import { LiveState } from '../live/live-state';
import { DemoView } from '../shared/demo-view';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { LAYOUT_QUERIES } from '../shared/layout-view';
import { Popovers } from '../shared/popover';
import { revealRing } from '../shared/reveal-ring';
import { SimulatedMailbox } from '../mailbox/simulated-mailbox';
import { type MailboxSnapshot, mailOf } from '../mailbox/mailbox-view';
import { SimulatedPhone } from '../phone/simulated-phone';
import { type PhoneSnapshot, phoneOf } from '../phone/phone-view';
import { DeviceTabs } from './device-tabs';
import { DEVICE_TEXTS, type DeviceTab, baseName, newRefs, otherTab, tabName } from './device-view';
import { SimulatedLabel } from './simulated-label';

/**
 * Where focus goes when an update removes the element that holds it inside the panel (UX-DR131): an item that is still there takes
 * it (a request message's Approve and Reject replaced by the answer line, which shares their part and key), and one that is gone
 * leaves it to the main region. The panel's rule runs on every store change before a request message's own, so without the item
 * rule it would send a replaced button's focus to the main region first. The items are the elements with a part and a key; the
 * mailbox's rows carry a key and no part.
 */
const FOCUS_RULE: FocusRule = {
  item: '[data-part][data-key]',
  keyOf: (item) => `${item.getAttribute('data-part') ?? ''}:${item.getAttribute('data-key') ?? ''}`,
};

/** The tabs, in order. */
const TABS: readonly DeviceTab[] = ['phone', 'mailbox'];

/** The id of a tab, and of the panel that it controls. */
const tabId = (tab: DeviceTab): string => `device-tab-${tab}`;
const panelId = (tab: DeviceTab): string => `device-panel-${tab}`;

/**
 * The simulated device panel (Story 4.5; FR-13, UX-DR132): the region "Simulated devices", right of the chat in demo mode and nowhere
 * else. It is the column that the demo guide's right half lines up over: 352px wide, 384px from 1440px; below 1024px it follows main
 * in the single column (main, devices, rail). Its two ARIA tabs, "Simulated phone" and "Simulated mailbox", move with the left and
 * right arrow keys (automatic activation, wrapping) and the choice is remembered per browser (DeviceTabs). Content never switches a
 * tab: a tab that is not selected shows a badge with the count of what arrived live since it was last selected, and the count is part
 * of the tab's name ("Simulated mailbox, 2 new"). What was there when the page loaded is never new.
 *
 * The phone tab holds the simulated phone; the mailbox tab holds its header, "Simulated mailbox" and the Simulated label, and then the
 * simulated mailbox (Story 4.6), which has its own tab stops: the panel itself is none. The region takes focus for the skip link (tabindex -1). Nothing in it is a live region; the chat card
 * announces an event once. Beside the chat the phone fills the panel body: its screen keeps its minimum height while the column has
 * room for it and yields to the body's height when the column is shorter, so its feed scrolls inside the screen and New messages
 * stays in view; in the stacked column the screen keeps its minimum. The panel body scrolls on its own when what it holds is taller
 * than the column; it is no tab stop (tabindex -1, so that no engine makes a stop of it): the controls inside it scroll it as focus
 * reaches them.
 */
@Component({
  selector: 'app-device-panel',
  imports: [SimulatedLabel, SimulatedMailbox, SimulatedPhone],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '[class.on]': 'demo()' },
  template: `
    @if (demo()) {
      <section class="devices ring-inside" tabindex="-1" [attr.aria-label]="texts.region">
        <div class="tabs" role="tablist" (keydown)="onKey($event)">
          @for (tab of tabs; track tab) {
            <button
              type="button"
              role="tab"
              class="tab"
              [id]="idOf(tab)"
              [class.selected]="selected() === tab"
              [attr.aria-selected]="selected() === tab"
              [attr.aria-controls]="panelOf(tab)"
              [attr.aria-label]="nameOf(tab)"
              [attr.tabindex]="selected() === tab ? 0 : -1"
              (click)="choose(tab)"
            >
              {{ baseOf(tab) }}
              @if (count(tab) > 0) {
                <span class="badge" aria-hidden="true">{{ count(tab) }}</span>
              }
            </button>
          }
        </div>
        <div class="body" tabindex="-1" (focusin)="reveal($event)">
          <div class="panel" role="tabpanel" [id]="panelOf('phone')" [attr.aria-labelledby]="idOf('phone')" [hidden]="selected() !== 'phone'">
            <app-simulated-phone [labelledBy]="idOf('phone')" />
          </div>
          <div class="panel mailbox" role="tabpanel" [id]="panelOf('mailbox')" [attr.aria-labelledby]="idOf('mailbox')" [hidden]="selected() !== 'mailbox'">
            <div class="mailbox-header">
              <span class="mailbox-title">{{ texts.mailboxTab }}</span>
              <app-simulated-label />
            </div>
            <app-simulated-mailbox />
          </div>
        </div>
      </section>
    }
  `,
  styles: `
    :host {
      display: none;
    }
    :host(.on) {
      display: flex;
      flex: none;
      width: var(--space-device-width);
      min-height: 0;
    }
    @media ${LAYOUT_QUERIES.wide} {
      :host(.on) {
        width: var(--space-device-width-wide);
      }
    }
    @media ${LAYOUT_QUERIES.stacked} {
      :host(.on) {
        width: auto;
      }
    }
    .devices {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-width: 0;
      min-height: 0;
      background: var(--simulated-device-panel-background);
      border-left: var(--simulated-device-panel-border-left);
    }
    @media ${LAYOUT_QUERIES.stacked} {
      .devices {
        border-left: 0;
        border-top: var(--simulated-device-panel-border-left);
      }
    }
    .tabs {
      display: flex;
      flex: none;
      align-items: stretch;
      gap: var(--space-1);
      padding: 0 var(--space-2);
      border-bottom: 1px solid var(--border);
    }
    .tab {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      min-height: var(--space-control-height-lg);
      min-width: 0;
      margin-bottom: -1px;
      padding: 0 var(--space-2);
      background: none;
      border: 0;
      border-bottom: 3px solid transparent;
      color: var(--device-tab-foreground);
      font-family: var(--font-ui);
      font-size: var(--device-tab-typography-font-size);
      font-weight: var(--device-tab-typography-font-weight);
      line-height: var(--device-tab-typography-line-height);
      cursor: pointer;
    }
    .tab.selected {
      color: var(--device-tab-foreground-selected);
      border-bottom-color: var(--action);
    }
    .badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: var(--space-4);
      padding: 0 var(--space-1);
      background: var(--tab-badge-background);
      color: var(--tab-badge-foreground);
      border-radius: var(--tab-badge-radius);
      font-size: var(--tab-badge-typography-font-size);
      font-weight: var(--tab-badge-typography-font-weight);
      line-height: var(--tab-badge-typography-line-height);
    }
    /* The body scrolls on its own when what its panel holds is taller than the column. */
    .body {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-height: 0;
      padding: var(--space-3) var(--space-3) var(--space-6);
      overflow-y: auto;
      scroll-padding: var(--space-scroll-gutter);
    }
    /* Beside the chat the phone's panel is the body's height and the phone has no minimum of its own: its screen is at least its
       minimum high while the body has room for it, and yields to the body's height when the column is shorter, so that the feed
       scrolls inside the screen and New messages stays at the screen's visible bottom. */
    .panel {
      display: flex;
      flex: 1 1 0;
      flex-direction: column;
      min-width: 0;
      min-height: 0;
    }
    app-simulated-phone {
      --phone-screen-min: 0px;
    }
    @media ${LAYOUT_QUERIES.stacked} {
      /* In the one scrolling column the panel is as tall as the phone, and the phone's screen keeps its minimum, unless the window is
         so short that the screen would not fit under the sticky header: then it is 70% of the window, as the chat list is, so that a
         ring at its feed stays inside the window. */
      .panel {
        flex: 1 0 auto;
      }
      app-simulated-phone {
        --phone-screen-min: min(var(--space-phone-screen-min-height), 70vh);
      }
    }
    .panel[hidden] {
      display: none;
    }
    .mailbox {
      flex: none;
      gap: var(--space-3);
    }
    .mailbox-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--space-2);
      padding: var(--space-2) var(--space-3);
      background: var(--simulated-mailbox-background);
      border: var(--simulated-mailbox-border);
      border-radius: var(--simulated-mailbox-radius);
    }
    .mailbox-title {
      color: var(--ink);
      font-family: var(--font-ui);
      font-size: var(--device-tab-typography-font-size);
      font-weight: var(--device-tab-typography-font-weight);
      line-height: var(--device-tab-typography-line-height);
    }
  `,
})
export class DevicePanel {
  protected readonly live = inject(LiveState);
  private readonly demoView = inject(DemoView);
  protected readonly deviceTabs = inject(DeviceTabs);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);
  protected readonly texts = DEVICE_TEXTS;
  protected readonly tabs = TABS;

  /** True while the demo view is on: the only time the panel shows. */
  protected readonly demo = computed(() => this.demoView.on());

  /** The selected tab. */
  protected readonly selected = this.deviceTabs.selected;

  /** The count of live arrivals on each tab since it was last selected. */
  private readonly counts = signal<Readonly<Record<DeviceTab, number>>>({ phone: 0, mailbox: 0 });

  /** The snapshot that `seen` belongs to. */
  private looked: unknown;
  /** The refs each tab has shown, as of the last look. */
  private seen: Record<DeviceTab, Set<string>> = { phone: new Set(), mailbox: new Set() };

  constructor() {
    effect(() => {
      const snapshot = this.demoView.snapshot();
      const store = this.live.store();
      const selected = this.selected();
      untracked(() => this.note(snapshot as (PhoneSnapshot & MailboxSnapshot) | undefined, store, selected));
    });
    effect(() => {
      this.live.store();
      this.selected();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, FOCUS_RULE));
    });
  }

  protected idOf(tab: DeviceTab): string {
    return tabId(tab);
  }

  protected panelOf(tab: DeviceTab): string {
    return panelId(tab);
  }

  protected baseOf(tab: DeviceTab): string {
    return baseName(tab);
  }

  protected count(tab: DeviceTab): number {
    return this.counts()[tab];
  }

  /** The tab's accessible name, with its count of new content. */
  protected nameOf(tab: DeviceTab): string {
    return tabName(tab, this.count(tab));
  }

  /** Focus reached something in the panel body: the body scrolls just far enough to keep that element's ring inside it (Firefox leaves it clipped). */
  protected reveal(event: Event): void {
    revealRing(event.currentTarget as HTMLElement, event.target);
  }

  /** A click on a tab: the user's own selection. */
  protected choose(tab: DeviceTab): void {
    this.deviceTabs.select(tab);
  }

  /** Left and right arrows move from the focused tab to the other one, focusing and selecting it; they wrap, and no other key is handled. */
  protected onKey(event: KeyboardEvent): void {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') {
      return;
    }
    event.preventDefault();
    const focused = TABS.find((tab) => tabId(tab) === (event.target as HTMLElement | null)?.id) ?? this.selected();
    const next = otherTab(focused);
    this.deviceTabs.select(next);
    this.host.nativeElement.querySelector<HTMLElement>(`#${tabId(next)}`)?.focus();
  }

  /**
   * Counts what arrived live on each tab that is not selected. A new snapshot (the first load, or a reload) records what is there and
   * counts none of it; selecting a tab clears its count.
   */
  private note(snapshot: (PhoneSnapshot & MailboxSnapshot) | undefined, store: ReturnType<LiveState['store']>, selected: DeviceTab): void {
    const refs: Record<DeviceTab, string[]> = {
      phone: (phoneOf(snapshot, store) ?? []).map((one) => one.ref ?? ''),
      mailbox: (mailOf(snapshot, store) ?? []).map((one) => one.ref ?? ''),
    };
    if (snapshot !== this.looked) {
      this.looked = snapshot;
      this.seen = { phone: new Set(refs.phone), mailbox: new Set(refs.mailbox) };
      this.counts.set({ phone: 0, mailbox: 0 });
      return;
    }
    const counts = { ...this.counts() };
    for (const tab of TABS) {
      const fresh = newRefs(this.seen[tab], refs[tab]);
      for (const ref of fresh) {
        this.seen[tab].add(ref);
      }
      counts[tab] = tab === selected ? 0 : counts[tab] + fresh.length;
    }
    this.counts.set(counts);
  }
}
