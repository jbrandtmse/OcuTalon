import { afterNextRender, ChangeDetectionStrategy, Component, computed, ElementRef, inject, Injector, input, output } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { ChatOutbox } from '../chat/chat-outbox';
import { COMPOSER_REASON_ID } from '../chat/composer';
import { turnInFlight } from '../chat/try-it-view';
import { DeviceTabs } from '../devices/device-tabs';
import { DOCUMENTS_TEXTS } from '../documents/documents-view';
import { SampleRunbook } from '../documents/sample-runbook';
import { AllowanceState } from '../live/allowance-state';
import { LiveState } from '../live/live-state';
import { chipName, SAMPLES } from '../mailbox/mailbox-view';
import { HEARTBEAT_HEADING_ID } from '../rail/heartbeat-card/heartbeat-card-view';
import { MEMORY_HEADING_ID } from '../rail/memory-card/memory-card-view';
import { PERSONA_HEADING_ID } from '../rail/persona-card/persona-card-view';
import { Layout, RAIL_REGION } from '../shared/layout';
import { LAYOUT_QUERIES } from '../shared/layout-view';
import { keepRoom } from './more-to-try-room';
import { BREAK_FEED_BUTTON, DISMISS_BUTTON, groupsOf, INCIDENT_CARD, MORE_TO_TRY_TEXTS, type MoreToTryItem, RESOLVED_CHIP } from './more-to-try-view';

/** The Persona card's Change button. */
const PERSONA_CHANGE = 'app-persona-card button.change';

/** The suspicious-request chip of the Simulated mailbox, found by its own name. */
const SUSPICIOUS_CHIP = `app-simulated-mailbox button[aria-label="${chipName(SAMPLES[2].label)}"]`;

/** The header's Demo view switch. */
const DEMO_VIEW_SWITCH = 'app-demo-view-switch [role="switch"]';

/** The count that gives each panel its own label id. */
let panels = 0;

/**
 * The "Other things to try" panel of the demo guide (Story 4.11; EXPERIENCE: Demo guide and controls): a labelled group, never a
 * heading, with one list item for each item it is given (more-to-try-view.ts itemsFor): the label, the look-for line and one native
 * control named by its visible text. It decides nothing about which items show; the guide gives it the server's.
 *
 * A control hands off to the control the page already has: it puts focus on that control and presses it, so the action is exactly that
 * control's own. The incident summary item presses the Dismiss of the newest incident card that is resolved (the incident's own close, which
 * writes its summary) and, when no card is resolved (the guide's incident was closed already, or the guide has not run), sends "Show me the incident
 * summary" through the chat's outbox instead; the Persona item opens the rail and the Persona card's Change, the suspicious email item selects the
 * Simulated mailbox tab and presses the suspicious-request chip, the Reject a fix item presses the box's Break the feed, the reroute item and the partner warning item (Story 23.5) send their prompts through the chat's outbox as the user's own message (Story 23.2), the Demo view item presses the
 * Demo view switch while it is on, the memory item sends its prompt through the chat's outbox (a new message of the user's), the Memory card item opens the rail and focuses the
 * Memory card's heading, the documents item is a link to the Documents page and the heartbeat item opens the rail and focuses the Heartbeat checklist card's heading, pressing nothing, and the sources item (Story 20.2) is a link to the Documents page. While the visitor has no documents (SampleRunbook.none, with the `documents` item listed) the documents and sources items are instead a button, Add the sample runbook, which asks the Documents page to press its own button of that name (SampleRunbook.ask) and opens the page; the panel posts nothing. Every action runs from the control's own click, and focus moves
 * only for that press. The panel announces nothing, and it emits `pressed` so that the guide keeps the panel open, and `squeezed` when the
 * room is too small for it even at its shortest window, so that the guide does not start it open.
 *
 * Where the page fills the viewport (LAYOUT_QUERIES.framed) the group is a vertical scroll region of its own, a Tab stop named by the
 * panel label (the project's rule for a scroller), with no gap under the label and no margin above the group, since the guide's own gap
 * separates it. Its window takes only the room that the chat's list leaves above its floor (the `floor` input; windowBound), measured
 * on the page as it is and kept in the host's `--more-max`, and never less than the label's line and one control. So the chat keeps its
 * floor and the page does not scroll as a whole, whatever fonts and banners the page has; the one exception is the compact band with the panel
 * opened by the user where its shortest window and the chat's floor cannot both fit: the window is at its shortest and the chat still
 * keeps its floor, so the page scrolls vertically, never sideways (the Planner, 2026-11-07; more-to-try-room.ts). Before the first measurement a fixed reserve
 * stands in. The items lay out in as many columns as fit, and the list ends in a gutter that holds the last control's ring. The group
 * carries the focus rule's `moreItem` key like the controls, so a focused group hands focus on when the finish leaves.
 * The items sit in the sets that groupsOf gives, each group with an item under its own h4 heading, in a list of its own; the items with no
 * group come first with no heading, and a heading never takes focus.
 * In the stacked column the page scrolls and the group grows with its items.
 *
 * The memory item, the reroute item and the partner warning item are aria-disabled, never disabled, while a turn is in flight or the message allowance is used up, and a press then sends nothing; the
 * incident summary item's press sends nothing in the same cases when it falls back to sending its prompt.
 */
@Component({
  selector: 'app-more-to-try',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="group ring-inside" role="group" tabindex="0" data-guide-focus="moreItem" [attr.aria-labelledby]="labelId">
      <p class="group-label" [id]="labelId">{{ texts.label }}</p>
      @for (set of groups(); track set.heading) {
        @if (set.heading) {
          <h4 class="set-heading">{{ set.heading }}</h4>
        }
        <ul class="items">
          @for (item of set.items; track item.id) {
            <li class="item">
              <p class="item-label">{{ item.label }}</p>
              <p class="look-for">{{ item.lookFor }}</p>
              @if (item.action === 'documents' && !sampleFirst()) {
                <a class="button button-secondary" routerLink="/documents" data-guide-focus="moreItem" (click)="pressed.emit()">{{ item.button }}</a>
              } @else if (item.action === 'webhooks') {
                <a class="button button-secondary" routerLink="/settings/channels" data-guide-focus="moreItem" (click)="pressed.emit()">{{ item.button }}</a>
              } @else if (item.action === 'usage' || item.action === 'history') {
                <a class="button button-secondary" [routerLink]="'/' + item.action" data-guide-focus="moreItem" (click)="pressed.emit()">{{ item.button }}</a>
              } @else {
                <button
                  type="button"
                  class="button button-secondary"
                  data-guide-focus="moreItem"
                  [attr.aria-disabled]="(item.action === 'memory' || item.action === 'reroute' || item.action === 'partnerWarning' || item.action === 'queueWatch') && blocked() ? 'true' : null"
                  [attr.aria-describedby]="item.action === 'memory' || item.action === 'reroute' || item.action === 'partnerWarning' || item.action === 'queueWatch' ? describedBy() : null"
                  (click)="press(item)"
                >{{ sampleFirst() && item.action === 'documents' ? documentsTexts.sample : item.button }}</button>
              }
            </li>
          }
        </ul>
      }
    </div>
  `,
  styles: `
    :host {
      display: block;
      margin-top: var(--space-1);
      --more-label-height: calc(var(--type-body-sm-font-size) * var(--type-body-sm-line-height));
      --more-gap: var(--space-1);
      --more-window-min: calc(var(--more-label-height) + var(--more-gap) + var(--space-control-height));
      --more-reserve: 685px;
      --more-max: calc(100dvh - var(--more-reserve));
    }
    .group {
      display: flex;
      flex-direction: column;
      align-items: stretch;
      gap: var(--more-gap);
      padding-inline: var(--space-1);
    }
    .group-label {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .set-heading {
      margin: var(--space-2) 0 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-caption-line-height);
    }
    .items {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(min(20rem, 100%), 1fr));
      gap: var(--space-2) var(--space-4);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .item {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
    }
    .item p {
      margin: 0;
    }
    .item-label {
      flex: 1 1 100%;
      color: var(--ink);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-line-height);
    }
    .look-for {
      flex: 1 1 20rem;
      min-width: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    /* A control keeps its whole text on one line while its item is wide enough, and wraps the text inside the control when the item
       is narrower (the narrowest page, whose width a classic scrollbar reduces), so no control passes the panel's width. */
    .item .button {
      flex: 0 1 auto;
      min-width: 0;
      max-width: 100%;
    }
    /* Where the page fills the viewport, the panel is a scroll region of its own: it leaves the chat the room it needs, so the page
       does not scroll as a whole (but for the compact-band case in the component's comment, the Planner, 2026-11-07). Its bound is --more-max, which the component measures (the chat's floor above the list's height now);
       --more-max starts as the viewport's height less a reserve, the first frame's stand-in. The window never gets shorter than the label's line and one control, so the
       label and a whole control show together and every control scrolls fully into view; the list's end gutter lets the last
       control scroll clear of the edge, so its focus ring is never clipped. */
    @media ${LAYOUT_QUERIES.framed} {
      :host {
        margin-top: 0;
        --more-gap: 0px;
      }
      .group {
        overflow-y: auto;
        scroll-padding: var(--space-scroll-gutter);
        max-height: max(var(--more-window-min), var(--more-max));
      }
      .items {
        padding-block-end: var(--space-scroll-gutter);
      }
    }
  `,
})
export class MoreToTry {
  private readonly layout = inject(Layout);
  private readonly tabs = inject(DeviceTabs);
  private readonly outbox = inject(ChatOutbox);
  private readonly live = inject(LiveState);
  private readonly allowance = inject(AllowanceState);
  private readonly sample = inject(SampleRunbook);
  private readonly router = inject(Router);
  private readonly injector = inject(Injector);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  /** The items to show, in the order to show them. */
  readonly items = input.required<readonly MoreToTryItem[]>();

  /** The least height, in px, of the chat's list that the panel's window leaves it (chatFloor). */
  readonly floor = input.required<number>();

  /** The room is too small for the panel: its window is as short as it may be and the chat is still under its floor (more-to-try-room.ts). */
  readonly squeezed = output<void>();

  /** Keeps the window's bound current while the panel is on the page (more-to-try-room.ts). */
  private readonly room = keepRoom(this.host.nativeElement, this.floor, () => this.squeezed.emit());

  /** A control was pressed: the guide keeps the panel open. */
  readonly pressed = output<void>();

  protected readonly texts = MORE_TO_TRY_TEXTS;
  protected readonly documentsTexts = DOCUMENTS_TEXTS;
  protected readonly labelId = `more-to-try-label-${++panels}`;

  /** True while the session's message allowance is used up. */
  private readonly used = computed(() => this.allowance.active() !== undefined);

  /** The items in their sets, each with its heading (groupsOf). */
  protected readonly groups = computed(() => groupsOf(this.items()));

  /** True while the visitor has no documents and the instance has them: items 6 and 8 offer the sample runbook in place of the link. */
  protected readonly sampleFirst = computed(() => this.sample.none() && this.items().some((item) => item.id === 'documents'));

  /** True while the memory item's press sends nothing: a turn is in flight (turnInFlight) or the allowance is used up. */
  protected readonly blocked = computed(() => this.used() || turnInFlight(this.live.store()?.chat ?? [], this.outbox.entries()));

  /** The composer's reason, while the allowance is used up; else none. */
  protected readonly describedBy = computed(() => (this.used() ? COMPOSER_REASON_ID : null));

  /** The user pressed an item's button: its hand-off. */
  protected press(item: MoreToTryItem): void {
    this.pressed.emit();
    switch (item.action) {
      case 'incidentSummary':
        this.closeIncident();
        break;
      case 'persona':
        this.layout.focusRegion(RAIL_REGION);
        this.handTo([PERSONA_CHANGE, `#${PERSONA_HEADING_ID}`], (control) => control.getAttribute('aria-expanded') !== 'true');
        break;
      case 'suspiciousEmail':
        this.tabs.select('mailbox');
        this.handTo([SUSPICIOUS_CHIP], () => true);
        break;
      case 'rejectFix':
        this.handTo([BREAK_FEED_BUTTON], () => true);
        break;
      case 'reroute':
        if (!this.blocked()) {
          this.outbox.send(MORE_TO_TRY_TEXTS.reroutePrompt);
        }
        break;
      case 'partnerWarning':
        if (!this.blocked()) {
          this.outbox.send(MORE_TO_TRY_TEXTS.partnerPrompt);
        }
        break;
      case 'queueWatch':
        if (!this.blocked()) {
          this.outbox.send(MORE_TO_TRY_TEXTS.queuePrompt);
        }
        break;
      case 'demoView':
        this.handTo([DEMO_VIEW_SWITCH], (control) => control.getAttribute('aria-checked') === 'true');
        break;
      case 'memory':
        if (!this.blocked()) {
          this.outbox.send(MORE_TO_TRY_TEXTS.rememberPrompt);
        }
        break;
      case 'memoryCard':
        this.layout.focusRegion(RAIL_REGION);
        this.handTo([`#${MEMORY_HEADING_ID}`], () => false);
        break;
      case 'heartbeat':
        this.layout.focusRegion(RAIL_REGION);
        this.handTo([`#${HEARTBEAT_HEADING_ID}`], () => false);
        break;
      case 'documents':
        this.sample.ask();
        void this.router.navigate(['/documents']);
        break;
      case 'usage':
        void this.router.navigate(['/usage']);
        break;
      case 'history':
        void this.router.navigate(['/history']);
        break;
      default:
        break;
    }
  }

  /**
   * After the next render, focuses the Dismiss of the newest resolved incident card and presses it; with no resolved card, sends the summary prompt
   * (unless a turn is in flight or the allowance is used up, as for the memory item).
   */
  private closeIncident(): void {
    afterNextRender(
      () => {
        const resolved = Array.from(document.querySelectorAll<HTMLElement>(INCIDENT_CARD)).filter((card) => card.querySelector(RESOLVED_CHIP) !== null);
        const dismiss = resolved.length === 0 ? null : resolved[resolved.length - 1].querySelector<HTMLElement>(DISMISS_BUTTON);
        if (dismiss !== null) {
          this.focusAndPress(dismiss, true);
        } else if (!this.blocked()) {
          this.outbox.send(MORE_TO_TRY_TEXTS.summaryPrompt);
        }
      },
      { injector: this.injector },
    );
  }

  /** After the next render, focuses the first control found and presses it when `press` says so: the control's own action runs. */
  private handTo(selectors: readonly string[], press: (control: HTMLElement) => boolean): void {
    afterNextRender(
      () => {
        for (const selector of selectors) {
          const control = document.querySelector<HTMLElement>(selector);
          if (control !== null) {
            this.focusAndPress(control, press(control));
            return;
          }
        }
      },
      { injector: this.injector },
    );
  }

  /** Puts focus on the control and presses it when `press` is true: the control's own action runs. The one place where this panel moves focus. */
  private focusAndPress(control: HTMLElement, press: boolean): void {
    control.focus();
    if (press) {
      control.click();
    }
  }
}
