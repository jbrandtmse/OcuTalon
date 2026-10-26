import { ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, signal, untracked } from '@angular/core';

import { ChatOutbox } from '../chat/chat-outbox';
import { BreakFeedBox } from '../feed/break-feed-box';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import type { GuideStatePayload } from '../live/payloads';
import { Announcer } from '../shared/announcer';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { HEIGHT_QUERIES, LAYOUT_QUERIES } from '../shared/layout-view';
import { Popovers } from '../shared/popover';
import { readFlag, writeFlag } from '../shared/stored-flag';
import { advance, followSelection, GUIDE_HIDDEN_FLAG, GUIDE_HIDDEN_KEY, GUIDE_SHOWN_FLAG, GUIDE_TEXTS, guideOf, guideView, type GuideSnapshot } from './guide-view';

/** The attribute that marks the elements that focus may need to find again: the prompt bar's parts and the Hide and Show buttons. */
const FOCUS_KEY = 'data-guide-focus';

/** The prompt bar's action, its text and the bar itself, which take focus in that order when an advance replaces what held it. */
const PROMPT_KEYS = ['action', 'text', 'bar'] as const;

/**
 * Where focus goes when an update removes the element that holds it (UX-DR131, EXPERIENCE: focus replacement): Hide guide and Show guide
 * hand it to each other, and the prompt bar's action, text or the bar itself hand it to the first of the three that is still there (the
 * action button that now carries the next step, else the prompt text, else the bar). Focus anywhere else is never moved.
 */
const FOCUS_RULE: FocusRule = {
  item: `[${FOCUS_KEY}]`,
  keyOf: (item) => item.getAttribute(FOCUS_KEY) ?? '',
  whenGone: ({ host, key }) => {
    const find = (name: string) => host.querySelector<HTMLElement>(`[${FOCUS_KEY}="${name}"]`);
    if (key === 'hide' || key === 'show') {
      return find(key === 'hide' ? 'show' : 'hide');
    }
    return PROMPT_KEYS.map(find).find((element) => element !== null) ?? null;
  },
};

/**
 * The demo guide (Story 4.4; UX-DR45, UX-DR131): the region "Demo guide" between the banners and the rail and chat, in demo mode only. It
 * shows the server's guide view (AD-12; guide-view.ts) and decides none of its progress. Row 1 holds the label, the five steps (buttons in
 * a list, joined by decorative chevrons; the current step carries aria-current="step" and its state is in every step's name), "About
 * 2 minutes" and Hide guide. Row 2, the prompt bar, shows the selected step's exact prompt and its Send button, which sends the prompt
 * as the user's own message from the guide (ChatOutbox, fromGuide). Steps 3 to 5 hold no prompt yet (Story 4.7). Any step can be
 * selected in any order, and nothing is marked done by a click. The Break the feed box sits at the right.
 *
 * Hide guide collapses the region to one bar, "Demo guide - step n of 5 - Show guide" with Show guide aria-expanded, and the box keeps its
 * place at the bar's right end; the choice is stored in this browser (ocutalon.guide.hidden). Under 680px tall the steps (numbers only) and
 * the prompt bar share one compact row, from 1024 to 1279px wide the steps show numbers instead of labels, and below 1024px the box
 * follows the prompt bar.
 *
 * Announcements and focus: "Step {n} of 5: {step}" is announced once when the view advances to a later step of the same run (never for the
 * first view, a reload or a lower step), through the Announcer; the guide is not a live region. The selection follows the current step when
 * it changes. Focus moves only when an update removed the element that held it (shared/focus-rule.ts) or by the user's own action.
 */
@Component({
  selector: 'app-demo-guide',
  imports: [BreakFeedBox, Icon],
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
            <div class="prompt" tabindex="-1" data-guide-focus="bar">
              @if (guide.telegramRow) {
                <p class="telegram">{{ texts.telegram }}</p>
              }
              @if (guide.prompt; as prompt) {
                <div class="prompt-line">
                  <span class="next">{{ texts.next }}</span>
                  <span class="prompt-text" tabindex="-1" data-guide-focus="text">{{ prompt.quoted }}</span>
                  <button type="button" class="button button-primary" data-guide-focus="action" (click)="send(prompt.text)">{{ texts.send }}</button>
                </div>
              }
            </div>
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
      gap: 10px;
      min-height: 30px;
      flex-wrap: wrap;
      white-space: nowrap;
    }
    .row1 > * {
      flex: none;
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
      padding: 0 1px;
      color: var(--border-strong);
    }
    .step {
      position: relative;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      min-height: 30px;
      padding: 0 3px;
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
      inset-inline: 3px;
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
    .prompt-text {
      flex: 1;
      min-width: 0;
      color: var(--ink);
      font-size: var(--type-body-chat-font-size);
      line-height: var(--type-body-chat-line-height);
    }
    .prompt-line .button {
      flex: none;
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
      .prompt {
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
  private readonly outbox = inject(ChatOutbox);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);

  protected readonly texts = GUIDE_TEXTS;

  /** The guide view: the latest guide.state, else the snapshot's guide; undefined outside demo mode. */
  private readonly view = computed(() => guideOf(this.live.snapshot() as GuideSnapshot | undefined, this.live.store()));

  /** The step the user selected, or the current step until the first view. */
  private readonly selected = signal<number | undefined>(undefined);

  /** True while the guide is collapsed to its bar; the stored choice of this browser, until the user changes it. */
  protected readonly hidden = signal(readFlag(() => localStorage, GUIDE_HIDDEN_KEY, GUIDE_HIDDEN_FLAG));

  protected readonly model = computed(() => {
    const view = this.view();
    const selected = this.selected();
    return view === undefined || selected === undefined ? undefined : { ...guideView(view, selected), view };
  });

  private last: GuideStatePayload | undefined;

  constructor() {
    effect(() => {
      const view = this.view();
      untracked(() => this.follow(view));
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

  /** Sends the prompt as the user's own message from the guide; a press while the same prompt is still being sent sends nothing. */
  protected send(text: string): void {
    if (this.outbox.entries().some((entry) => entry.fromGuide && entry.text === text && entry.status === 'sending')) {
      return;
    }
    this.outbox.send(text, true);
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
