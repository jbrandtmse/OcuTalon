import { ChangeDetectionStrategy, Component, computed, effect, inject, input, output, signal, untracked } from '@angular/core';
import { finalize, type Observable, tap } from 'rxjs';

import { elapsedText } from '../chat/page-time';
import { Icon } from '../icon/icon';
import { LiveState } from '../live/live-state';
import type { GuideStatePayload } from '../live/payloads';
import { Announcer } from '../shared/announcer';
import { BUSY_TIMEOUT_MS } from '../shared/busy-state';
import { LAYOUT_QUERIES } from '../shared/layout-view';
import { ServerButton } from '../shared/server-button';
import { BreakFeedApi } from './break-feed-api';
import { boxView, conflictOf, FEED_TEXTS, heldSent, type LocalPress, NO_PRESS, sentToAnnounce, watchLine } from './break-feed-view';

/** The ids of the box's status line and hint, which the button is described by. */
const LINE_ID = 'break-feed-line';
const HINT_ID = 'break-feed-hint';

/** The refs of the `watch.progress` entries that the page held before a run: none of them belongs to it. */
const NO_REFS: ReadonlySet<string> = new Set<string>();

/**
 * The Break the feed box of the demo guide (Story 4.4; UX-DR45). Its look and its lines come from the server's guide view, which the
 * guide hands in, from the answer to its own press and from `watch.progress` (break-feed-view.ts holds the rules); the page decides
 * nothing (AD-12). The box always shows "Demo control". The button is a ServerButton with `zap`: busy from the press to its answer
 * ("Sending 50 orders..."), and while the server says it cannot act it is aria-disabled but focusable, a press on it sends nothing,
 * and the hint or status line under it is its description. "Do step 1" asks the guide to select step 1.
 *
 * The answer to the press covers the gap until the next view: a 200 holds the sent line, a 409 shows the reason it named. A 1 s clock
 * runs only while the elapsed time shows, and nothing here is a live region: the box announces only "Sent. OcuTalon usually notices
 * within a minute." (through the Announcer, once for each run, from the 200 or from a live view; the first view is silent).
 */
@Component({
  selector: 'app-break-feed-box',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '[class.next-step]': 'box().nextStep', '[class.inline]': 'inline()' },
  template: `
    <div class="head">
      <span class="label">{{ texts.label }}</span>
      @if (box().nextStep) {
        <span class="tag">{{ texts.nextStep }}</span>
      }
    </div>
    <app-server-button [variant]="box().style" [action]="press" [inactive]="box().inactive" [describedBy]="described()">
      <app-icon name="zap" [size]="16" />
      {{ texts.button }}
    </app-server-button>
    @if (box().line !== '') {
      <p class="line" [id]="lineId">
        {{ box().line }}
        @if (box().elapsed; as elapsed) {
          <span class="elapsed"><span aria-hidden="true">{{ elapsed.text }}</span><span class="visually-hidden">{{ elapsed.spoken }}</span></span>
        }
      </p>
    }
    @if (box().hint !== '') {
      <p class="hint" [id]="hintId">{{ box().hint }}</p>
      @if (box().doStep1) {
        <button type="button" class="link step1" (click)="doStep1.emit()">{{ texts.doStep1 }}</button>
      }
    }
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      justify-content: center;
      gap: 3px;
      min-width: 0;
      padding: 6px var(--space-4);
      border-inline-start: 1px solid var(--border);
    }
    :host(.next-step) {
      padding-inline-start: 13px;
      border-inline-start: 4px solid var(--action);
    }
    :host(.inline) {
      flex-direction: row;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-1) var(--space-3);
    }
    @media ${LAYOUT_QUERIES.stacked} {
      :host {
        border-inline-start: 0;
        border-top: 1px solid var(--border);
      }
      :host(.next-step) {
        border-inline-start: 4px solid var(--action);
      }
    }
    .head {
      display: flex;
      align-items: center;
      gap: var(--space-2);
    }
    .label {
      color: var(--break-the-feed-box-label-color);
      font-size: var(--break-the-feed-box-label-font-size);
      font-weight: var(--break-the-feed-box-label-font-weight);
      line-height: var(--break-the-feed-box-label-line-height);
      letter-spacing: var(--break-the-feed-box-label-letter-spacing);
      text-transform: uppercase;
    }
    .tag {
      padding: 0 var(--space-2);
      border-radius: var(--rounded-full);
      background: var(--break-the-feed-next-step-tag-background);
      color: var(--break-the-feed-next-step-tag-foreground);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-caption-line-height);
    }
    .line,
    .hint {
      margin: 0;
      min-width: 0;
    }
    .line {
      color: var(--ink);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .hint {
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    :host(.inline) .line,
    :host(.inline) .hint {
      flex-basis: 100%;
    }
    .step1 {
      min-height: var(--space-target-min);
      padding: 0 var(--space-1);
      border: 0;
      background: none;
      font: inherit;
      font-size: var(--type-caption-font-size);
      cursor: pointer;
    }
  `,
})
export class BreakFeedBox {
  /** The server's guide view. */
  readonly view = input.required<GuideStatePayload>();

  /** True in the collapsed bar: "Demo control" sits inline before the button. */
  readonly inline = input(false);

  /** The Do step 1 button was pressed: the guide selects step 1. */
  readonly doStep1 = output<void>();

  protected readonly texts = FEED_TEXTS;
  protected readonly lineId = LINE_ID;
  protected readonly hintId = HINT_ID;

  private readonly live = inject(LiveState);
  private readonly api = inject(BreakFeedApi);
  private readonly announcer = inject(Announcer);

  /** The page's own press: in flight, answered 200, or refused 409. */
  private readonly local = signal<LocalPress>(NO_PRESS);

  /** The run that `refs` belongs to, and the `watch.progress` refs the page held before it. */
  private readonly baseline = signal<{ run: string; refs: ReadonlySet<string> } | undefined>(undefined);

  /** The 1 s clock: the view reads the time itself when it recomputes. */
  private readonly clock = signal(0);

  /** The runs whose "Sent" was announced, or was already on the page when it was first seen. */
  private readonly announced = new Set<string>();

  private lastView: GuideStatePayload | undefined;
  private pressRefs: ReadonlySet<string> = NO_REFS;

  /** The run the box is showing: the page's own sent press while it holds, else the view's. */
  private readonly run = computed(() => {
    const local = this.local();
    return heldSent(local, this.view()) ? (local.sentAt ?? '') : (this.view().breakFeed?.startedAt ?? '');
  });

  private readonly progress = computed(() => {
    const baseline = this.baseline();
    return baseline !== undefined && baseline.run === this.run() ? watchLine(this.live.store()?.watchProgress, baseline.refs) : '';
  });

  protected readonly box = computed(() => {
    this.clock();
    return boxView(this.view(), this.local(), this.progress(), Date.now(), elapsedText);
  });

  /** The ids of the text that describes the button: its status line and its hint, while they show. */
  protected readonly described = computed(() => {
    const box = this.box();
    return [...(box.line === '' ? [] : [LINE_ID]), ...(box.hint === '' ? [] : [HINT_ID])];
  });

  private readonly ticking = computed(() => this.box().elapsed !== undefined);

  constructor() {
    effect(() => {
      const view = this.view();
      untracked(() => this.follow(view));
    });
    effect((onCleanup) => {
      if (this.ticking()) {
        const id = globalThis.setInterval(() => this.clock.update((tick) => tick + 1), 1000);
        onCleanup(() => globalThis.clearInterval(id));
      }
    });
  }

  /** The press: it is busy until the answer. A 200 holds the sent line; a 409 holds the reason it names; any other failure adds no text. */
  protected readonly press = (): Observable<unknown> => {
    this.pressRefs = new Set(Object.keys(this.live.store()?.watchProgress ?? {}));
    this.local.set({ pressing: true });
    const timer = globalThis.setTimeout(() => this.local.update((local) => ({ ...local, pressing: false })), BUSY_TIMEOUT_MS);
    return this.api.press().pipe(
      tap({
        next: (answer) => this.sent(answer.startedAt),
        error: (error: unknown) => this.refused(conflictOf(error)),
      }),
      finalize(() => globalThis.clearTimeout(timer)),
    );
  };

  /** A view arrived: the run's baseline, and the "Sent" that a live view announces. */
  private follow(view: GuideStatePayload): void {
    const startedAt = view.breakFeed?.startedAt ?? '';
    if (startedAt !== '' && this.baseline()?.run !== startedAt) {
      this.baseline.set({ run: startedAt, refs: new Set(Object.keys(this.live.store()?.watchProgress ?? {})) });
    }
    if (this.lastView === undefined && startedAt !== '') {
      this.announced.add(startedAt);
    }
    const run = sentToAnnounce(this.lastView, view, this.announced);
    this.lastView = view;
    if (run !== null) {
      this.announced.add(run);
      this.announcer.announce(FEED_TEXTS.sent);
    }
  }

  private sent(startedAt: string): void {
    this.baseline.set({ run: startedAt, refs: this.pressRefs });
    this.local.set({ pressing: false, sentAt: startedAt, base: untracked(this.view) });
    if (!this.announced.has(startedAt)) {
      this.announced.add(startedAt);
      this.announcer.announce(FEED_TEXTS.sent);
    }
  }

  private refused(code: string | undefined): void {
    this.local.set(code === undefined ? NO_PRESS : { pressing: false, conflict: code, base: untracked(this.view) });
  }
}
