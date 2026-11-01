import { afterNextRender, ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, signal, untracked } from '@angular/core';
import { type Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { GuideMarker } from '../api/api-types';
import { allowanceReason } from '../banners/banner-stack';
import { ChatOutbox } from '../chat/chat-outbox';
import { formatCost, formatTokens } from '../chat/decision-view';
import { DeviceTabs } from '../devices/device-tabs';
import { BreakFeedBox } from '../feed/break-feed-box';
import { Icon } from '../icon/icon';
import { README_URL } from '../links';
import { AllowanceState } from '../live/allowance-state';
import { LiveState } from '../live/live-state';
import type { GuideStatePayload } from '../live/payloads';
import { pendingRef, phoneOf, type PhoneSnapshot } from '../phone/phone-view';
import { Announcer } from '../shared/announcer';
import { DemoView } from '../shared/demo-view';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { HEIGHT_QUERIES, LAYOUT_QUERIES } from '../shared/layout-view';
import { Popovers } from '../shared/popover';
import { ServerButton } from '../shared/server-button';
import { readFlag, writeFlag } from '../shared/stored-flag';
import { TraceLink } from '../shared/trace-link';
import { conversationUrl, TRACE_TEXTS } from '../shared/trace-view';
import { advance, followSelection, GUIDE_HIDDEN_FLAG, GUIDE_HIDDEN_KEY, GUIDE_SHOWN_FLAG, GUIDE_TEXTS, guideOf, guideView, type GuideSnapshot, type RunFormat } from './guide-view';

/** The attribute that marks the elements that focus may need to find again: the prompt bar's parts, the Hide and Show buttons and the box's Do step 1. */
const FOCUS_KEY = 'data-guide-focus';

/** The Break the feed button of the box, which takes focus when an update removes Do step 1 beside it, or a prompt or finish part while the prompt bar shows step 3. */
const BREAK_FEED_BUTTON = 'app-break-feed-box app-server-button button';

/** The attribute that marks the prompt bar while it shows step 3, so the focus rule can hand focus to the box beside it. */
const STEP_MARK = 'data-guide-step';

/** The prompt bar's action, its text and the bar itself, which take focus in that order when an advance replaces what held it. */
const PROMPT_KEYS = ['action', 'text', 'bar'] as const;

/** The finish state's first line and the parts that hand focus back to the prompt bar when the prompt bar replaces the finish. */
const FINISH_KEY = 'finish';
const FINISH_PARTS = ['finish', 'finishLink', 'runAgain'];

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
 * line, its links and Run again) hand it to the prompt bar's parts in the same order when Run again brings the prompt bar back. Focus
 * anywhere else is never moved.
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
 * 2 minutes" and Hide guide. Row 2, the prompt bar, shows the selected step's exact prompt and its action (guide-view.ts promptOf):
 * Send sends the prompt as the user's own message from the guide (ChatOutbox, fromGuide), Show me selects the Simulated phone tab and
 * focuses the pending notification, and Open the trace is the run's trace link, which writes the trace_opened marker once a Visual Trace
 * tab opens. Once the server's view is finished the finish state
 * replaces the prompt bar: the exact lines, the run total, the two links, More to try and Run again, which writes the run_again
 * marker. A marker's 200 answer is the guide view until the next live view arrives. Any step can be selected in any order, and nothing
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
 * follows the prompt bar.
 *
 * Announcements and focus: "Step {n} of 5: {step}" is announced once when the view advances to a later step of the same run (never for the
 * first view, a reload or a lower step), through the Announcer; the guide is not a live region, and the finish and Run again are silent.
 * The selection follows the current step when it changes. Focus moves only when an update removed the element that held it
 * (shared/focus-rule.ts; step 3 has no button of its own, so the box's Break the feed button takes the focus that Send or Run again held)
 * or by the user's own action (Show me).
 */
@Component({
  selector: 'app-demo-guide',
  imports: [BreakFeedBox, Icon, ServerButton, TraceLink],
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
            <div class="row1">
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
                </p>
                <p class="more">{{ texts.moreToTry }}</p>
                <app-server-button class="run-again" variant="secondary" [action]="runAgain" data-guide-focus="runAgain">{{ texts.runAgain }}</app-server-button>
              </div>
            } @else {
              <div class="prompt" tabindex="-1" data-guide-focus="bar" [attr.data-guide-step]="guide.selected === 3 ? '3' : null">
                @if (guide.telegramRow) {
                  <p class="telegram">{{ texts.telegram }}</p>
                }
                @if (guide.prompt; as prompt) {
                  <div class="prompt-line">
                    @if (!prompt.waiting) {
                      <span class="next">{{ texts.next }}</span>
                    }
                    <span class="prompt-text" tabindex="-1" data-guide-focus="text">{{ prompt.quoted }}</span>
                    @switch (prompt.action) {
                      @case ('send') {
                        <button
                          type="button"
                          class="button button-primary"
                          data-guide-focus="action"
                          [attr.aria-disabled]="allowanceText() ? 'true' : null"
                          [attr.aria-describedby]="allowanceText() ? reasonId : null"
                          (click)="send(prompt.text)"
                        >{{ texts.send }}</button>
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
    .run-total,
    .more {
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
        align-items: center;
        gap: var(--space-3);
      }
      .step-label,
      .duration,
      .main .label {
        display: none;
      }
      .row1 {
        flex: none;
      }
      .prompt,
      .finish {
        flex: 1;
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
  `,
})
export class DemoGuide {
  private readonly live = inject(LiveState);
  private readonly demoView = inject(DemoView);
  private readonly outbox = inject(ChatOutbox);
  private readonly allowance = inject(AllowanceState);
  private readonly announcer = inject(Announcer);
  private readonly api = inject(ApiClient);
  private readonly tabs = inject(DeviceTabs);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);

  protected readonly texts = GUIDE_TEXTS;
  protected readonly trace = TRACE_TEXTS;
  protected readonly readme = README_URL;

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
    return { ...guideView(view, selected, RUN_FORMAT), view, conversation: this.conversation() };
  });

  private last: GuideStatePayload | undefined;

  constructor() {
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

  /** The user selected a step: only the selection and the prompt change. */
  protected select(step: number): void {
    this.selected.set(step);
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

  /** Writes a marker and keeps its 200 answer as the guide view. A failure adds no text: a press of Open the trace writes it again. */
  protected mark(marker: GuideMarker): void {
    this.post(marker).subscribe({ error: () => undefined });
  }

  /** Run again: the call of its server button, which is busy until the answer. */
  protected readonly runAgain = (): Observable<GuideStatePayload> => this.post('run_again');

  private post(marker: GuideMarker): Observable<GuideStatePayload> {
    return this.api.postGuideMarker(marker).pipe(tap((view) => this.answered.set(view)));
  }

  /** A view arrived: the selection follows the current step when it changes, and an advance is announced once. */
  private follow(view: GuideStatePayload | undefined): void {
    const said = advance(this.last, view);
    this.selected.set(followSelection(this.last, view, this.selected()));
    this.last = view;
    if (said !== null) {
      this.announcer.announce(said);
    }
  }
}
