import { afterNextRender, ChangeDetectionStrategy, Component, computed, DestroyRef, effect, ElementRef, inject, Injector, signal, untracked } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { GuideMarker } from '../api/api-types';
import { allowanceReason } from '../banners/banner-stack';
import { ChatOutbox } from '../chat/chat-outbox';
import { formatCost, formatTokens } from '../chat/decision-view';
import { TryItRow } from '../chat/try-it-row';
import { DeviceTabs } from '../devices/device-tabs';
import { BreakFeedBox } from '../feed/break-feed-box';
import { Icon } from '../icon/icon';
import { BRIDGE_GUIDE_URL, README_URL } from '../links';
import { AllowanceState } from '../live/allowance-state';
import { LiveState } from '../live/live-state';
import type { GuideStatePayload } from '../live/payloads';
import { pendingRef, phoneOf, type PhoneSnapshot } from '../phone/phone-view';
import { Announcer } from '../shared/announcer';
import { DemoView } from '../shared/demo-view';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { Layout, RAIL_REGION } from '../shared/layout';
import { HEIGHT_QUERIES, LAYOUT_QUERIES, LAYOUT_TEXTS } from '../shared/layout-view';
import { isViewer } from '../shared/viewer-view';
import { Popovers } from '../shared/popover';
import { ServerButton } from '../shared/server-button';
import { readFlag, writeFlag } from '../shared/stored-flag';
import { TraceLink } from '../shared/trace-link';
import { conversationUrl, TRACE_TEXTS } from '../shared/trace-view';
import { advance, followSelection, GUIDE_HIDDEN_FLAG, GUIDE_HIDDEN_KEY, GUIDE_SHOWN_FLAG, GUIDE_TEXTS, guideOf, guideView, telegramRowOf, type GuideSnapshot, type RunFormat } from './guide-view';
import { MoreToTry } from './more-to-try';
import { BREAK_FEED_BUTTON, chatFloor, inCompactBand, itemsFor, MORE_TO_TRY_TEXTS } from './more-to-try-view';

/** The attribute that marks the elements that focus may need to find again: the prompt bar's parts, the Hide and Show buttons and the box's Do step 1. */
const FOCUS_KEY = 'data-guide-focus';

/** The attribute that marks the prompt bar while it shows step 3, so the focus rule can hand focus to the box beside it. */
const STEP_MARK = 'data-guide-step';

/** The prompt bar's action, its text and the bar itself, which take focus in that order when an advance replaces what held it. */
const PROMPT_KEYS = ['action', 'text', 'bar'] as const;

/** The Telegram row's Show me, which hands focus to the prompt bar (else the finish's first line) when it leaves. */
const TELEGRAM_KEY = 'telegram';

/** The id of the Telegram row's text, which its Show me is described by. */
const TELEGRAM_TEXT_ID = 'guide-telegram-text';

/** The finish state's first line and the parts that hand focus back to the prompt bar when the prompt bar replaces the finish. */
const FINISH_KEY = 'finish';
const FINISH_PARTS = ['finish', 'finishLink', 'moreItem', 'tryIt', 'runAgain'];

/** The id of the "Other things to try" panel, which the "More to try" link controls while the panel is open. */
const MORE_PANEL_ID = 'guide-more-to-try';

/** The page's token and cost formats, which the finish's run line is written with. */
const RUN_FORMAT: RunFormat = { tokens: formatTokens, cost: formatCost };

/** The newest phone message's container and the phone's feed, which Show me puts focus on. */
const PHONE_FEED = 'app-simulated-phone .feed';
const phoneMessage = (ref: string) => `app-simulated-phone .notification[data-key="${CSS.escape(ref)}"]`;

/**
 * Where focus goes when an update removes the element that holds it (UX-DR131, EXPERIENCE: focus replacement): Hide guide and Show guide
 * hand it to each other, the box's Do step 1 hands it to the Break the feed button beside it, and the prompt bar's action, text or the bar
 * itself hand it to the first of the three that is still there (the action button that now carries the next step, else the prompt text,
 * else the bar), else to the finish's first line. While the prompt bar shows step 3 (data-guide-step), a lost prompt part or finish
 * part hands focus to the box's Break the feed button instead, active or inactive; nothing is pressed. The finish's parts (its first
 * line, its links, the Other things to try panel's controls, the Try it yourself row and Run again) hand it to the prompt bar's parts in
 * the same order when Run again brings the prompt bar back; the panel's scrolling group counts among those parts, and a panel part whose
 * panel is still on the page hands it to that panel's first part. Focus
 * anywhere else is never moved. The Telegram row's Show me hands it to the prompt bar, else to the finish's first line, when the band or the
 * row takes the button away.
 */
const FOCUS_RULE: FocusRule = {
  item: `[${FOCUS_KEY}]`,
  keyOf: (item) => item.getAttribute(FOCUS_KEY) ?? '',
  whenGone: ({ host, key }) => {
    const find = (name: string) => host.querySelector<HTMLElement>(`[${FOCUS_KEY}="${name}"]`);
    if (key === 'hide' || key === 'show') {
      return find(key === 'hide' ? 'show' : 'hide');
    }
    if (key === 'step1') {
      return host.querySelector<HTMLElement>(BREAK_FEED_BUTTON);
    }
    if (key === TELEGRAM_KEY) {
      return find('bar') ?? find(FINISH_KEY);
    }
    if ((PROMPT_KEYS as readonly string[]).includes(key) || FINISH_PARTS.includes(key)) {
      const box = find('bar')?.getAttribute(STEP_MARK) === '3' ? host.querySelector<HTMLElement>(BREAK_FEED_BUTTON) : null;
      if (box !== null) {
        return box;
      }
    }
    const prompt = PROMPT_KEYS.map(find).find((element) => element !== null) ?? null;
    return FINISH_PARTS.includes(key) ? prompt : (prompt ?? find(FINISH_KEY));
  },
};

/**
 * The demo guide (Story 4.4; UX-DR45, UX-DR131): the region "Demo guide" between the banners and the rail and chat, in demo mode only. It
 * shows the server's guide view (AD-12; guide-view.ts) and decides none of its progress. Row 1 holds the label, the five steps (buttons in
 * a list, joined by decorative chevrons; the current step carries aria-current="step" and its state is in every step's name), "About
 * 2 minutes", the "More to try" link and Hide guide. Row 2, the prompt bar, shows the selected step's exact prompt and its action (guide-view.ts promptOf):
 * Send sends the prompt as the user's own message from the guide (ChatOutbox, fromGuide), Show me selects the Simulated phone tab and
 * focuses the pending notification, and Open the trace is the run's trace link, which writes the trace_opened marker once a Visual Trace
 * tab opens. Once the server's view is finished the finish state
 * replaces the prompt bar: the exact lines, the run total, the two links, the "Other things to try" panel (app-more-to-try), the
 * "Try it yourself" row (app-try-it-row, a finish part for focus) and Run again, which writes the run_again marker. The panel starts open in
 * the finish, except in the compact band (the viewport's height less the banners' is under 680px; the Planner, 2026-11-07), where it starts
 * closed; opened by the user there, the chat's list still keeps its 64px floor and the page scrolls vertically where the panel's shortest
 * window and that floor cannot both fit (never sideways; the Planner, 2026-11-07; more-to-try-room.ts). Above the band it also starts closed where the room is too small for it even at its shortest window (implement-stage decision 13 kept
 * by the lead's ruling, veto window, inbox U-299); the "More to try" link opens and closes it at any time. A marker's 200 answer is the guide view until the next live view arrives. Any step can be selected in any order, and nothing
 * is marked done by a click. The Break the feed box sits at the right.
 *
 * While the session's message allowance is used up (Story 16.9; AllowanceState.active) a prompt whose action is Send is aria-disabled, not
 * disabled, and described by the paragraph #guide-allowance-reason in the prompt bar, which holds the allowance banner's own text; a press
 * on it sends nothing. The other actions, Break the feed's box and the finish are unchanged, and at the time the allowance returns the
 * markings and the reason clear.
 *
 * Hide guide collapses the region to one bar, "Demo guide - step n of 5 - Show guide" with Show guide aria-expanded, and the box keeps its
 * place at the bar's right end; the choice is stored in this browser (ocutalon.guide.hidden). Under 680px tall the steps (numbers only) and
 * the prompt bar share one compact row, from 1024 to 1279px wide the steps show numbers instead of labels, and below 1024px the box
 * follows the prompt bar. The finish state leaves out "About 2 minutes" (row 1 then stays on one line at 1280px), takes the guide's whole width under its
 * first row wherever the page fills the viewport and is under 680px tall, and from 1024 to 1279px wide its line is body-sm, the Try it
 * yourself row's own margin gives way to the finish's gap, and Run again sits at the end of the row's last line, so that the chat keeps
 * its room.
 *
 * Announcements and focus: "Step {n} of 5: {step}" is announced once when the view advances to a later step of the same run (never for the
 * first view, a reload or a lower step), through the Announcer; the guide is not a live region, and the finish and Run again are silent.
 * The selection follows the current step when it changes. Focus moves only when an update removed the element that held it
 * (shared/focus-rule.ts; step 3 has no button of its own, so the box's Break the feed button takes the focus that Send or Run again held)
 * or by the user's own action (Show me).
 *
 * The Telegram row (guide-view.ts telegramRowOf) shows only while the server's view says so. In the drawer band (1024 to 1279px, where the
 * status rail starts closed) its hint names the header's Status button and a Show me follows it: it opens the drawer and focuses the
 * rail, which holds the Telegram card (Layout.focusRegion; a second press keeps the drawer open). Elsewhere the row is the original
 * line with no button. When that Show me leaves while it holds focus, focus goes to the prompt bar, or to the finish's first line when the
 * finish replaced the bar.
 */
@Component({
  selector: 'app-demo-guide',
  imports: [BreakFeedBox, Icon, MoreToTry, ServerButton, TraceLink, TryItRow],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (model(); as guide) {
      <section class="guide" [class.collapsed]="hidden()" aria-labelledby="demo-guide-label">
        @if (hidden()) {
          <div class="bar">
            <span class="bar-text">
              <span class="label" id="demo-guide-label">{{ texts.label }}</span>
              <span aria-hidden="true">{{ texts.separator }}</span>
              <span>{{ guide.collapsed }}</span>
              <span aria-hidden="true">{{ texts.separator }}</span>
            </span>
            <button type="button" class="button button-ghost" aria-expanded="false" data-guide-focus="show" (click)="setHidden(false)">{{ texts.show }}</button>
          </div>
        } @else {
          <div class="main">
            <div class="row1" [class.finished]="guide.finish !== undefined">
              <span class="label" id="demo-guide-label">{{ texts.label }}</span>
              <ol class="steps">
                @for (step of guide.steps; track step.n) {
                  <li>
                    @if (step.n > 1) {
                      <span class="chevron" aria-hidden="true"><app-icon name="chevron-right" /></span>
                    }
                    <button
                      type="button"
                      class="step"
                      [class.current]="step.state === 'current'"
                      [class.done]="step.state === 'done'"
                      [class.upcoming]="step.state === 'upcoming'"
                      [class.selected]="step.selected"
                      [attr.aria-current]="step.current ? 'step' : null"
                      [attr.aria-label]="step.name"
                      (click)="select(step.n)"
                    >
                      <span class="marker" aria-hidden="true">
                        @if (step.state === 'done') {
                          <app-icon name="circle-check" [size]="20" />
                        } @else {
                          {{ step.n }}
                        }
                      </span>
                      <span class="step-label">{{ step.label }}</span>
                    </button>
                  </li>
                }
              </ol>
              <span class="duration">{{ texts.duration }}</span>
              <button
                type="button"
                class="link more-link"
                data-guide-focus="moreLink"
                [attr.aria-expanded]="moreOpen()"
                [attr.aria-controls]="panelShown() ? morePanelId : null"
                (click)="toggleMore()"
              >{{ moreTexts.link }}</button>
              <button type="button" class="button button-ghost" data-guide-focus="hide" (click)="setHidden(true)">{{ texts.hide }}</button>
            </div>
            @if (guide.finish; as finish) {
              <div class="finish">
                <p class="finish-done" tabindex="-1" data-guide-focus="finish">{{ texts.finishDone }}</p>
                @if (finish.runTotal; as total) {
                  <p class="run-total">{{ total }}</p>
                }
                <p class="finish-links">
                  @if (guide.conversation; as conversation) {
                    <app-trace-link appearance="arrow" [text]="texts.conversationLink" [url]="conversation" guideFocus="finishLink" />
                  }
                  <a class="link" [href]="readme" target="_blank" rel="noopener noreferrer" data-guide-focus="finishLink"
                    >{{ texts.installLink }}<span aria-hidden="true"> {{ trace.arrow }}</span><span class="visually-hidden"> {{ trace.opensInNewTab }}</span></a
                  >
                  <a class="link" [href]="bridgeGuide" target="_blank" rel="noopener noreferrer" data-guide-focus="finishLink"
                    >{{ texts.bridgeLink }}<span aria-hidden="true"> {{ trace.arrow }}</span><span class="visually-hidden"> {{ trace.opensInNewTab }}</span></a
                  >
                </p>
                @if (panelShown()) {
                  <app-more-to-try [id]="morePanelId" [items]="items()" [floor]="floor()" (pressed)="chosen.set(true)" (squeezed)="squeezed.set(true)" />
                }
                <app-try-it-row data-guide-focus="tryIt" />
                @if (!viewer()) {
                  <app-server-button class="run-again" variant="secondary" [action]="runAgain" data-guide-focus="runAgain">{{ texts.runAgain }}</app-server-button>
                }
              </div>
            } @else {
              <div class="prompt" tabindex="-1" data-guide-focus="bar" [attr.data-guide-step]="guide.selected === 3 ? '3' : null">
                @if (guide.telegram; as telegram) {
                  <p class="telegram" [class.with-button]="telegram.showMe">
                    <span [id]="telegramTextId">{{ telegram.text }}</span>
                    @if (telegram.showMe) {
                      <button type="button" class="button button-secondary" data-guide-focus="telegram" [attr.aria-describedby]="telegramTextId" (click)="showTelegram()">{{ texts.showMe }}</button>
                    }
                  </p>
                }
                @if (guide.prompt; as prompt) {
                  <div class="prompt-line">
                    @if (!prompt.waiting) {
                      <span class="next">{{ texts.next }}</span>
                    }
                    <span class="prompt-text" tabindex="-1" data-guide-focus="text">{{ prompt.quoted }}</span>
                    @switch (prompt.action) {
                      @case ('send') {
                        @if (!viewer()) {
                        <button
                          type="button"
                          class="button button-primary"
                          data-guide-focus="action"
                          [attr.aria-disabled]="allowanceText() ? 'true' : null"
                          [attr.aria-describedby]="allowanceText() ? reasonId : null"
                          (click)="send(prompt.text)"
                        >{{ texts.send }}</button>
                        }
                      }
                      @case ('showMe') {
                        <button type="button" class="button button-primary" data-guide-focus="action" (click)="showMe()">{{ texts.showMe }}</button>
                      }
                      @case ('openTrace') {
                        <app-trace-link appearance="button" [text]="texts.openTrace" [url]="guide.view.trace?.traceUrl ?? ''" guideFocus="action" (opened)="mark('trace_opened')" />
                      }
                    }
                  </div>
                  @if (prompt.action === 'send' && allowanceText(); as reason) {
                    <p class="reason" [id]="reasonId">{{ reason }}</p>
                  }
                }
              </div>
              @if (panelShown()) {
                <app-more-to-try [id]="morePanelId" [items]="items()" [floor]="floor()" (pressed)="chosen.set(true)" (squeezed)="squeezed.set(true)" />
              }
            }
          </div>
        }
        <app-break-feed-box [view]="guide.view" [inline]="hidden()" (doStep1)="select(1)" />
      </section>
    }
  `,
  styles: `
    :host {
      display: block;
      flex: none;
    }
    .guide {
      display: grid;
      grid-template-columns: minmax(0, 1fr) var(--space-device-width);
      min-height: var(--space-guide-min-height);
      background: var(--demo-guide-background);
      border-bottom: var(--demo-guide-border-bottom);
    }
    .guide.collapsed {
      grid-template-columns: minmax(0, 1fr) auto;
      min-height: var(--guide-collapsed-bar-min-height);
    }
    .main {
      display: flex;
      flex-direction: column;
      justify-content: center;
      gap: 3px;
      min-width: 0;
      padding: 6px var(--space-4);
    }
    .row1 {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-target-min);
      flex-wrap: wrap;
      white-space: nowrap;
    }
    .row1 > * {
      flex: none;
    }
    .row1 > .button {
      padding-inline: var(--space-2);
    }
    /* The steps take a line of their own when the row is too narrow for them, and wrap inside it at large text sizes. */
    .row1 > .steps {
      flex: 0 1 auto;
      min-width: 0;
    }
    .label {
      color: var(--attention-ink);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-label-line-height);
      letter-spacing: var(--type-label-letter-spacing);
      text-transform: uppercase;
    }
    .more-link {
      min-height: var(--space-target-min);
      padding: 0 var(--space-2);
      border: 0;
      background: none;
      font: inherit;
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
      cursor: pointer;
    }
    .finish > app-more-to-try {
      align-self: stretch;
      justify-self: stretch;
    }
    .row1.finished > .duration {
      display: none;
    }
    .row1.finished > .more-link {
      margin-inline-start: auto;
    }
    .duration {
      margin-inline-start: auto;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .steps {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .steps li {
      display: flex;
      align-items: center;
    }
    .chevron {
      display: inline-flex;
      color: var(--border-strong);
    }
    .step {
      position: relative;
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      min-height: var(--space-target-min);
      padding: 0 2px;
      border: 0;
      background: none;
      color: var(--guide-step-upcoming-foreground);
      font-family: var(--font-ui);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-font-weight);
      line-height: var(--type-body-line-height);
      white-space: nowrap;
      cursor: pointer;
    }
    .step.done {
      color: var(--guide-step-done-foreground);
    }
    .step.current {
      color: var(--guide-step-current-foreground);
      font-size: var(--guide-step-current-typography-font-size);
      font-weight: var(--guide-step-current-typography-font-weight);
      line-height: var(--guide-step-current-typography-line-height);
    }
    /* The selected step's 2px bottom bar, in ink: never a teal ring, which is the focus ring's colour. */
    .step.selected::after {
      content: '';
      position: absolute;
      inset-inline: 2px;
      bottom: 0;
      border-bottom: 2px solid var(--ink);
    }
    .marker {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 20px;
      min-height: 20px;
      border-radius: var(--rounded-full);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1;
    }
    .done .marker {
      color: var(--success-ink);
    }
    .current .marker {
      background: var(--action);
      color: var(--on-action);
    }
    .upcoming .marker {
      box-shadow: inset 0 0 0 1.5px var(--border-strong);
      color: var(--ink-muted);
    }
    .prompt {
      display: flex;
      flex-direction: column;
      justify-content: center;
      gap: var(--space-1);
      min-height: 44px;
      padding: 2px var(--space-1) 2px var(--space-3);
      border-radius: var(--rounded-sm);
      background: var(--sunken);
    }
    .prompt:focus-visible {
      outline-offset: -2px;
    }
    .prompt-line {
      display: flex;
      align-items: center;
      gap: var(--space-2);
    }
    .telegram {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .telegram.with-button {
      display: flex;
      align-items: center;
      gap: var(--space-2);
    }
    .telegram .button {
      flex: none;
    }
    .next {
      flex: none;
      color: var(--ink-muted);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-line-height);
    }
    .reason {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .prompt-text {
      flex: 1;
      min-width: 0;
      color: var(--ink);
      font-size: var(--type-body-chat-font-size);
      line-height: var(--type-body-chat-line-height);
    }
    .prompt-line .button,
    .prompt-line app-trace-link {
      flex: none;
    }
    /* The finish state takes the prompt bar's place: the same sunken block, with its lines stacked and no fixed height. */
    .finish {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
      min-height: 44px;
      padding: var(--space-1) var(--space-3);
      border-radius: var(--rounded-sm);
      background: var(--sunken);
    }
    .finish p {
      margin: 0;
    }
    .finish-done {
      color: var(--ink);
      font-size: var(--type-body-chat-font-size);
      line-height: var(--type-body-chat-line-height);
    }
    .finish-done:focus-visible {
      outline-offset: -2px;
    }
    .run-total {
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .run-total {
      font-variant-numeric: tabular-nums;
    }
    .finish-links {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-1) var(--space-4);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .bar {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-width: 0;
      min-height: var(--guide-collapsed-bar-min-height);
      padding: var(--space-1) var(--space-2) var(--space-1) var(--space-4);
      color: var(--ink-muted);
      font-size: var(--guide-collapsed-bar-typography-font-size);
      line-height: var(--guide-collapsed-bar-typography-line-height);
    }
    .bar-text {
      white-space: pre;
    }
    @media ${LAYOUT_QUERIES.drawer} {
      .step-label {
        display: none;
      }
      .finish {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        justify-items: start;
        align-items: end;
        column-gap: var(--space-3);
      }
      .finish > * {
        grid-column: 1 / -1;
      }
      .finish-done {
        font-size: var(--type-body-sm-font-size);
        line-height: var(--type-body-sm-line-height);
      }
      .finish > app-try-it-row {
        grid-column: 1;
        margin-top: calc(var(--space-3) * -1);
      }
      .finish > .run-again {
        grid-column: 2;
      }
    }
    @media ${LAYOUT_QUERIES.wide} {
      .guide:not(.collapsed) {
        grid-template-columns: minmax(0, 1fr) var(--space-device-width-wide);
      }
    }
    @media ${HEIGHT_QUERIES.compact} {
      .guide:not(.collapsed) {
        min-height: var(--space-guide-compact-height);
      }
      .main {
        flex-direction: row;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--space-3);
      }
      .main > app-more-to-try {
        flex: 1 1 100%;
      }
      .step-label,
      .duration,
      .main .label {
        display: none;
      }
      /* Row 1 never passes the main column: where the column is narrower than the row's controls, the row shrinks and its link and
         Hide guide wrap to a second line. The prompt bar and the finish keep 12rem before they share a line with row 1, so the bar's
         Send button is never squeezed past the page's width. */
      .row1 {
        flex: 0 1 auto;
      }
      .prompt,
      .finish {
        flex: 1 1 12rem;
        min-width: 0;
      }
    }
    @media ${LAYOUT_QUERIES.stacked} {
      .guide,
      .guide.collapsed {
        grid-template-columns: minmax(0, 1fr);
      }
      .row1 {
        white-space: normal;
      }
      .main {
        flex-wrap: wrap;
      }
    }
    @media ${HEIGHT_QUERIES.compact} and ${LAYOUT_QUERIES.framed} {
      .main {
        justify-content: flex-start;
        row-gap: var(--space-1);
      }
      .finish {
        flex-basis: 100%;
      }
    }
    @media ${HEIGHT_QUERIES.compact} and ${LAYOUT_QUERIES.stacked} {
      .finish {
        flex-basis: 100%;
      }
    }
  `,
})
export class DemoGuide {
  private readonly live = inject(LiveState);
  /** True for a viewer (Story 25.4): no Run again, no Send and no marker post. */
  protected readonly viewer = computed(() => isViewer(this.live.snapshot()));
  private readonly demoView = inject(DemoView);
  private readonly outbox = inject(ChatOutbox);
  private readonly allowance = inject(AllowanceState);
  private readonly announcer = inject(Announcer);
  private readonly api = inject(ApiClient);
  private readonly tabs = inject(DeviceTabs);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);
  private readonly layout = inject(Layout);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly texts = GUIDE_TEXTS;
  protected readonly trace = TRACE_TEXTS;
  protected readonly readme = README_URL;
  protected readonly bridgeGuide = BRIDGE_GUIDE_URL;
  protected readonly telegramTextId = TELEGRAM_TEXT_ID;
  protected readonly moreTexts = MORE_TO_TRY_TEXTS;
  protected readonly morePanelId = MORE_PANEL_ID;

  /** The id of the reason that a Send prompt is described by while the message allowance is used up. */
  protected readonly reasonId = 'guide-allowance-reason';

  /** The allowance banner's text while the message allowance is used up, else empty. */
  protected readonly allowanceText = computed(() => {
    const window = this.allowance.active();
    return window === undefined ? '' : allowanceReason(window);
  });

  /** The guide view of the live state: the latest guide.state, else the snapshot's guide; undefined outside the demo view. */
  private readonly liveView = computed(() => guideOf(this.demoView.snapshot() as GuideSnapshot | undefined, this.live.store()));

  /** The 200 answer of the page's last marker, which stands as the guide view until the next live view arrives. */
  private readonly answered = signal<GuideStatePayload | undefined>(undefined);

  /** The guide view: the held answer of a marker, else the live view. */
  private readonly view = computed(() => {
    const live = this.liveView();
    return live === undefined ? undefined : (this.answered() ?? live);
  });

  /** The step the user selected, or the current step until the first view. */
  private readonly selected = signal<number | undefined>(undefined);

  /** True while the guide is collapsed to its bar; the stored choice of this browser, until the user changes it. */
  protected readonly hidden = signal(readFlag(() => localStorage, GUIDE_HIDDEN_KEY, GUIDE_HIDDEN_FLAG));

  /** The finish's whole-conversation link: a string, so the guide's model changes only when the link does, not on every store change. */
  private readonly conversation = computed(() => conversationUrl(this.live.store()?.chat));

  protected readonly model = computed(() => {
    const view = this.view();
    const selected = this.selected();
    if (view === undefined || selected === undefined) {
      return undefined;
    }
    const telegram = telegramRowOf(view, this.layout.band() === 'drawer', LAYOUT_TEXTS.status);
    return { ...guideView(view, selected, RUN_FORMAT), view, telegram, conversation: this.conversation() };
  });

  /** The items of the "Other things to try" panel: the registry's entries for the features that the server's view lists. */
  protected readonly items = computed(() => itemsFor(this.view()?.features));

  /** True while the server's view is finished. */
  private readonly finished = computed(() => this.view()?.finished === true);

  /** The viewport's height and the height of the banners above the guide, in px, as the page has them now. */
  private readonly viewport = signal(window.innerHeight);
  private readonly banners = signal(0);

  /** True while the height left after the banners is under the compact band's edge (680px; the Planner, 2026-11-07). */
  protected readonly compact = computed(() => inCompactBand(this.viewport(), this.banners()));

  /** The least height of the chat's list that the open panel leaves it: 64px in the compact band, 160px above it. */
  protected readonly floor = computed(() => chatFloor(this.compact()));

  /** True when the room is too small for the panel even at its shortest window (more-to-try-room.ts); it is cleared when the viewport or the banners change, and at each new finish. */
  protected readonly squeezed = signal(false);

  /** The user's choice for the panel: undefined until the user presses the link or one of its controls, and again after each new finish. */
  protected readonly chosen = signal<boolean | undefined>(undefined);

  /** True while the panel shows: the user's choice, else open in the finish state where the band and the room allow it, and closed elsewhere. */
  protected readonly moreOpen = computed(() => this.chosen() ?? (this.finished() && !this.compact() && !this.squeezed()));

  /** True while the panel is on the page: it is open and the server lists an item to show. */
  protected readonly panelShown = computed(() => this.moreOpen() && this.items().length > 0);

  private last: GuideStatePayload | undefined;

  constructor() {
    afterNextRender(() => this.watchRoom());
    effect(() => {
      const view = this.view();
      untracked(() => this.follow(view));
    });
    effect(() => {
      this.liveView();
      untracked(() => this.answered.set(undefined));
    });
    effect(() => {
      this.model();
      this.hidden();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, FOCUS_RULE));
    });
  }

  /** Keeps the viewport's height and the banners' height current: the band is decided on the space the banners leave. */
  private watchRoom(): void {
    const slot = this.host.nativeElement.parentElement?.querySelector<HTMLElement>(':scope > .banner-slot') ?? null;
    const read = (): void => {
      const [viewport, banners] = [window.innerHeight, slot?.offsetHeight ?? 0];
      if (viewport !== this.viewport() || banners !== this.banners()) {
        this.squeezed.set(false);
      }
      this.viewport.set(viewport);
      this.banners.set(banners);
    };
    const observer = new ResizeObserver(read);
    observer.observe(document.documentElement);
    if (slot !== null) {
      observer.observe(slot);
    }
    window.addEventListener('resize', read);
    this.destroyRef.onDestroy(() => {
      window.removeEventListener('resize', read);
      observer.disconnect();
    });
    read();
  }

  /** The user selected a step: only the selection and the prompt change. */
  protected select(step: number): void {
    this.selected.set(step);
  }

  /** The user pressed the "More to try" link: the panel opens, or closes when it is open. */
  protected toggleMore(): void {
    this.chosen.set(!this.moreOpen());
  }

  /** The user pressed Hide guide or Show guide; the choice is kept in this browser. */
  protected setHidden(hidden: boolean): void {
    this.hidden.set(hidden);
    writeFlag(() => localStorage, GUIDE_HIDDEN_KEY, hidden ? GUIDE_HIDDEN_FLAG : GUIDE_SHOWN_FLAG);
  }

  /** Sends the prompt as the user's own message from the guide; a press while the same prompt is still being sent, or while the message allowance is used up, sends nothing. */
  protected send(text: string): void {
    if (this.allowance.active() !== undefined) {
      return;
    }
    if (this.outbox.entries().some((entry) => entry.fromGuide && entry.text === text && entry.status === 'sending')) {
      return;
    }
    this.outbox.send(text, true);
  }

  /**
   * Show me: the Simulated phone tab is selected, then focus goes to the newest phone message that names a pending approval request,
   * else to the phone's feed. Never to a button inside the phone.
   */
  protected showMe(): void {
    const store = this.live.store();
    const list = phoneOf(this.demoView.snapshot() as PhoneSnapshot | undefined, store) ?? [];
    const ref = pendingRef(list, store?.approvals);
    this.tabs.select('phone');
    afterNextRender(
      () => {
        const message = ref === undefined ? null : document.querySelector<HTMLElement>(phoneMessage(ref));
        (message ?? document.querySelector<HTMLElement>(PHONE_FEED))?.focus();
      },
      { injector: this.injector },
    );
  }

  /** Telegram row's Show me: opens the status drawer when it is closed and focuses the rail, which holds the Telegram card. */
  protected showTelegram(): void {
    this.layout.focusRegion(RAIL_REGION);
  }

  /** Writes a marker and keeps its 200 answer as the guide view. A failure adds no text: a press of Open the trace writes it again. */
  protected mark(marker: GuideMarker): void {
    if (this.viewer()) {
      return;
    }
    this.post(marker).subscribe({ error: () => undefined });
  }

  /** Run again: the call of its server button, which is busy until the answer. */
  protected readonly runAgain = (): Observable<GuideStatePayload> => this.post('run_again');

  private post(marker: GuideMarker): Observable<GuideStatePayload> {
    return this.api.postGuideMarker(marker).pipe(tap((view) => this.answered.set(view)));
  }

  /** A view arrived: the panel's choice resets when a finish begins, the selection follows the current step when it changes, and an advance is announced once. */
  private follow(view: GuideStatePayload | undefined): void {
    if (view?.finished === true && this.last?.finished !== true) {
      this.chosen.set(undefined);
      this.squeezed.set(false);
    }
    const said = advance(this.last, view);
    this.selected.set(followSelection(this.last, view, this.selected()));
    this.last = view;
    if (said !== null) {
      this.announcer.announce(said);
    }
  }
}
