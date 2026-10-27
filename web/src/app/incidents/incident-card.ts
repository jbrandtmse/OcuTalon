import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';

import { DecisionStrip } from '../chat/decision-strip';
import { FallbackFlag } from '../chat/fallback-flag';
import { messageTime, pageWhen, pageWhenBeside } from '../chat/page-time';
import { Icon } from '../icon/icon';
import type { DecisionPayload, IncidentPayload } from '../live/payloads';
import { TraceLink } from '../shared/trace-link';
import { EvidencePanel } from './evidence-panel';
import { INCIDENT_TEXTS, incidentView, type IncidentContext } from './incident-view';

/** The last id handed to a card, for the ids of its headline and its panel. */
let lastId = 0;

/**
 * The context the incident view reads, with the page's real time formats: the headline's time is a message time (instance time,
 * " ET" on the online demo), the top time is the page's time with its day and the browser zone's name when its offset differs
 * from the instance's, and the panel's item times are page times with their day.
 */
export function incidentContext(decisions: readonly DecisionPayload[], nowMs: number, instanceZone: string, onlineDemo: boolean): IncidentContext {
  return {
    decisions,
    nowMs,
    messageTime: (iso, now) => messageTime(iso, now, instanceZone, onlineDemo),
    topTime: (iso, now) => pageWhenBeside(iso, now, instanceZone),
    itemTime: (iso, now) => pageWhen(iso, now),
  };
}

/**
 * The incident card (FR-24, UX-DR72 to UX-DR78): one card per incident Ref in the chat, from the incident payload alone
 * (incident-view.ts). Top to bottom: the chip row (the state pill, the Fallback flag, the time of the last failure), the headline
 * (an h3), the "more since the notice" line, the cause, the evidence line, the proposed fix, the fixing line, the actions row
 * with Show details (aria-expanded) and the evidence panel directly below it, and the footer with the diagnosis decision's strip
 * (or the diagnosis trace link alone when the store holds no such decision). A 4px bar on the left follows the state; a closed
 * card keeps the chip row, the headline and Show details. A part with no data is left out. Every text is bound by interpolation,
 * never as markup.
 * The card is an article that the chat's focus rule and the New messages button can focus (tabindex -1); it announces nothing
 * (the chat does, chat-announcements.ts) and moves no focus itself. The panel stays open while the card updates in place.
 */
@Component({
  selector: 'app-incident-card',
  imports: [DecisionStrip, EvidencePanel, FallbackFlag, Icon, TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article
      [class]="'incident bar-' + view().bar"
      data-part="incident"
      [attr.data-key]="view().key"
      tabindex="-1"
      [attr.aria-labelledby]="headingId"
    >
      <div class="chip-row">
        @if (view().stateText; as stateText) {
          <span [class]="'chip chip-' + view().chip">{{ stateText }}</span>
        }
        @if (view().fallback) {
          <app-fallback-flag />
        }
        @if (view().time) {
          <span class="time">{{ view().time }}</span>
        }
      </div>
      <h3 class="headline" [id]="headingId" tabindex="-1">{{ view().headline }}</h3>
      @if (view().more) {
        <p class="more">{{ view().more }}</p>
      }
      @if (view().causeSentence) {
        <p class="cause">{{ view().causeSentence }}</p>
      }
      @if (view().evidenceLine) {
        <p class="evidence-line">{{ view().evidenceLine }}</p>
      }
      @if (view().fixSentence) {
        <p class="fix">{{ view().fixSentence }}</p>
      }
      @if (view().fixingLine) {
        <p class="fixing">{{ view().fixingLine }}</p>
      }
      @if (view().panel; as panel) {
        <div class="actions">
          <button
            type="button"
            class="button button-ghost show-details"
            [attr.aria-expanded]="open()"
            [attr.aria-controls]="panelId"
            (click)="open.set(!open())"
          >
            {{ texts.showDetails }}
            <app-icon [name]="open() ? 'chevron-up' : 'chevron-down'" [size]="14" />
          </button>
        </div>
        <div class="panel" [id]="panelId">
          @if (open()) {
            <app-evidence-panel [panel]="panel" />
          }
        </div>
      }
      @if (view().strip || view().diagnosisUrl) {
        <div class="footer">
          @if (view().strip; as strip) {
            <app-decision-strip
              [decision]="strip.decision"
              [cost]="strip.cost"
              [fallbackReason]="strip.fallbackReason"
              [reasons]="true"
              [newest]="false"
              [traceUrl]="view().diagnosisUrl"
            />
          } @else if (view().diagnosisUrl; as url) {
            <app-trace-link [url]="url" />
          }
        </div>
      }
    </article>
  `,
  styles: `
    :host {
      display: block;
    }
    .incident {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      padding: var(--space-4) var(--space-4) var(--space-3) var(--space-5);
      background: var(--incident-card-background);
      border: var(--incident-card-border);
      border-inline-start: var(--incident-card-accent-bar);
      border-inline-start-style: solid;
      border-radius: var(--incident-card-radius);
      color: var(--ink);
    }
    .incident.bar-fixing {
      border-inline-start: var(--incident-card-accent-bar-fixing);
      border-inline-start-style: solid;
    }
    .incident.bar-resolved {
      border-inline-start: var(--incident-card-accent-bar-resolved);
      border-inline-start-style: solid;
    }
    .incident.bar-closed {
      border-inline-start: var(--incident-card-accent-bar-closed);
      border-inline-start-style: solid;
    }
    p {
      margin: 0;
      max-width: var(--chat-panel-text-max);
      overflow-wrap: anywhere;
    }
    .chip-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
      margin-bottom: var(--space-1);
    }
    .chip {
      display: inline-flex;
      align-items: center;
      min-height: 22px;
      padding: 0 var(--space-2);
      border-radius: var(--rounded-full);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1;
      white-space: nowrap;
    }
    .chip-open {
      background: var(--incident-state-open-background);
      color: var(--incident-state-open-foreground);
    }
    .chip-awaiting-approval {
      background: var(--incident-state-awaiting-approval-background);
      color: var(--incident-state-awaiting-approval-foreground);
    }
    .chip-fixing {
      background: var(--incident-state-fixing-background);
      color: var(--incident-state-fixing-foreground);
    }
    .chip-resolved {
      background: var(--incident-state-resolved-background);
      color: var(--incident-state-resolved-foreground);
    }
    .chip-closed {
      background: var(--incident-state-closed-background);
      color: var(--incident-state-closed-foreground);
    }
    .time {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .headline {
      margin: 0;
      max-width: var(--chat-panel-text-max);
      font-family: var(--incident-card-headline-font-family), var(--font-ui);
      font-size: var(--incident-card-headline-font-size);
      font-weight: var(--incident-card-headline-font-weight);
      line-height: var(--incident-card-headline-line-height);
      overflow-wrap: anywhere;
    }
    .more {
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .cause,
    .fix,
    .fixing {
      font-size: var(--type-body-chat-font-size);
      font-weight: var(--type-body-chat-font-weight);
      line-height: var(--type-body-chat-line-height);
    }
    .fixing {
      color: var(--info-ink);
    }
    .evidence-line {
      color: var(--ink-muted);
      font-size: var(--incident-card-evidence-line-font-size);
      font-weight: var(--incident-card-evidence-line-font-weight);
      line-height: var(--incident-card-evidence-line-line-height);
    }
    .actions {
      display: flex;
      justify-content: flex-end;
      margin-top: var(--space-2);
    }
    .show-details {
      gap: var(--space-1);
      padding: 0 var(--space-2);
    }
    .panel:empty {
      display: none;
    }
    .footer {
      margin-top: var(--space-3);
      padding-top: var(--space-2);
      border-top: 1px solid var(--border);
    }
  `,
})
export class IncidentCard {
  /** The incident payload, the full view of the incident. */
  readonly incident = input.required<IncidentPayload>();
  /** The live store's decisions, among which the footer's decision (decisionRef) is looked for. */
  readonly decisions = input<readonly DecisionPayload[]>([]);
  /** The instance's time zone, from the snapshot. */
  readonly instanceZone = input('');
  /** True on the online demo: the headline's time ends " ET". */
  readonly onlineDemo = input(false);

  protected readonly texts = INCIDENT_TEXTS;
  private readonly id = ++lastId;
  protected readonly headingId = `incident-headline-${this.id}`;
  protected readonly panelId = `incident-panel-${this.id}`;
  /** True while Show details is open; it survives updates of the card, because the chat tracks the card by its key. */
  protected readonly open = signal(false);

  protected readonly view = computed(() =>
    incidentView(this.incident(), incidentContext(this.decisions(), Date.now(), this.instanceZone(), this.onlineDemo())),
  );
}
