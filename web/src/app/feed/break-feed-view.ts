/**
 * The Break the feed box's view model (Story 4.4): the fixed strings of the box and what its button, hint and status line show for the
 * server's guide view. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides none of the box's state (AD-12): whether the button can act, why it cannot, and the stage of the run come from the
 * guide view, and the button's activity follows the view's `active`, except that the page's own press holds it busy until the answer and
 * inactive after a 200 until a later view says otherwise. The page computes the elapsed time, the 90 s and 3 min lines
 * from that time (the server's stage may come first, but it moves on a 15 s tick), which `watch.progress` line is the newest, and
 * the local result of its own press, which covers the gap between the answer and the next view.
 *
 * - boxView(view, local, watchLine, nowMs, elapsed) gives the button's style and activity, the "Next step" tag, the status line, the hint and
 *   the elapsed time.
 * - watchLine(watchProgress, baselineRefs) is the newest `watch.progress` line of this run.
 * - heldSent and heldConflict say whether the local result of a press still holds; conflictOf reads a 409's code.
 * - sentToAnnounce says which run's "Sent" a live view announces.
 */
import type { Countdown } from '../chat/page-time';
import type { GuideBreakFeed, GuideStatePayload, WatchProgressPayload } from '../live/payloads';

/** Every fixed string of the box. The ellipsis is U+2026. */
export const FEED_TEXTS = {
  label: 'Demo control',
  button: 'Break the feed',
  nextStep: 'Next step',
  notWatching: 'Ask OcuTalon to watch the Orders production first (step 1).',
  incidentInProgress: 'Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.',
  doStep1: 'Do step 1',
  sending: 'Sending 50 orders\u2026',
  sent: 'Sent. OcuTalon usually notices within a minute.',
  noticed: 'OcuTalon noticed failures in the Orders production',
  settling: 'Waiting for the failures to settle',
  diagnosing: 'Working out the cause from the failed messages',
  stillWaiting: 'Still waiting. The notice will appear in the chat and on the Simulated phone tab.',
  noNotice: "No notice after 3 minutes, so something went wrong with this run. Open the Orders watch's trace in Background checks, or try again.",
} as const;

/** The seconds after which a run with no notice is still waiting, and after which no notice is coming (Demo.Guide). */
export const STILL_WAITING_S = 90;
export const NO_NOTICE_S = 180;

/** The reasons the server gives for an inactive button, with the hint of each. */
const HINTS: Readonly<Record<string, string>> = {
  not_watching: FEED_TEXTS.notWatching,
  incident_in_progress: FEED_TEXTS.incidentInProgress,
};

/** The line of each `watch.progress` stage. */
const PROGRESS: Readonly<Record<string, string>> = {
  noticed: FEED_TEXTS.noticed,
  settling: FEED_TEXTS.settling,
  diagnosing: FEED_TEXTS.diagnosing,
};

/** The page's own press: in flight, answered 200, or refused 409. `base` is the guide view when the answer came. */
export interface LocalPress {
  /** True while the press has no answer. */
  pressing: boolean;
  /** The `startedAt` of the 200. */
  sentAt?: string;
  /** The `error.code` of the 409. */
  conflict?: string;
  /** The guide view that the page held when the answer came: only a later view releases the local result. */
  base?: GuideStatePayload;
}

/** No press. */
export const NO_PRESS: LocalPress = { pressing: false };

const breakFeedOf = (view: GuideStatePayload | undefined): GuideBreakFeed => view?.breakFeed ?? {};

/**
 * True while the 200 of the page's own press holds: until a later guide view shows that run past `sending`, or a different run (another
 * `startedAt`, or none). A view that still carries the run's `sending` stage, or the view the page held when the answer came, cannot
 * undo it.
 */
export function heldSent(local: LocalPress, view: GuideStatePayload | undefined): boolean {
  if (local.sentAt === undefined) {
    return false;
  }
  const feed = breakFeedOf(view);
  if (feed.startedAt === local.sentAt) {
    return (feed.stage ?? '') === '' || feed.stage === 'sending';
  }
  return view === local.base;
}

/** True while the 409 of the page's own press holds: until the next guide view. */
export function heldConflict(local: LocalPress, view: GuideStatePayload | undefined): boolean {
  return local.conflict !== undefined && view === local.base;
}

/** The code of a 409 answer's error, or undefined for any other failure (a 500, a network error, a malformed body). */
export function conflictOf(error: unknown): string | undefined {
  const failed = error as { status?: unknown; error?: { error?: { code?: unknown } } } | null;
  const code = failed?.status === 409 ? failed.error?.error?.code : undefined;
  return typeof code === 'string' && code in HINTS ? code : undefined;
}

/** What the box shows. */
export interface BoxView {
  /** The button's variant: attention, secondary (step 5 current) or inactive. */
  style: 'attention' | 'secondary' | 'inactive';
  /** True while the button follows the server's `inactive`: it is aria-disabled and a press sends nothing. */
  inactive: boolean;
  /** True while the page's own press has no answer: spinner and aria-busy. */
  busy: boolean;
  /** True when the 4px bar and the "Next step" tag show. */
  nextStep: boolean;
  /** The status line of a run, or "". */
  line: string;
  /** The hint of the reason the button is inactive, or "". */
  hint: string;
  /** True when the hint is the not-watching one, which carries the Do step 1 button. */
  doStep1: boolean;
  /** The elapsed time of the run, when the line shows it. */
  elapsed?: Countdown;
}

/** The newest `watch.progress` line of the run, or "". Entries whose ref is in baselineRefs (seen before the run) are ignored. */
export function watchLine(watchProgress: Readonly<Record<string, WatchProgressPayload>> | undefined, baselineRefs: ReadonlySet<string>): string {
  let line = '';
  for (const [ref, progress] of Object.entries(watchProgress ?? {})) {
    if (!baselineRefs.has(ref)) {
      line = PROGRESS[progress.stage ?? ''] ?? line;
    }
  }
  return line;
}

/** The elapsed time from an ISO time to the clock (ms), as the page formats it (page-time.ts's elapsedText). */
export type ElapsedFormat = (sinceIso: string, nowMs: number) => Countdown;

/**
 * The box for the guide view, the page's own press, the newest `watch.progress` line of this run, the page's clock (ms) and the
 * format of the elapsed time.
 *
 * - The button is active only when the view says so, and never while the page's own press holds. On step 5 it is the secondary style.
 * - The stage line replaces the hint while the stage is sending, waiting or still waiting; a 409's reason replaces the view's reason
 *   until the next view.
 * - The 90 s and 3 min lines show from the page's elapsed time or from the server's stage, whichever comes first, over a waiting run
 *   and a sent press. They never change the button: only the view's `active` does.
 * - While a sent press holds over a view of another run (the view the page held when the answer came), that view's stage is not this
 *   run's: the box shows the sent press, never the earlier run's lines.
 * - The "Next step" tag leaves once the button is pressed: while the press has no answer, after its 200, and while its 409 holds.
 */
export function boxView(view: GuideStatePayload, local: LocalPress, progressLine: string, nowMs: number, elapsed: ElapsedFormat): BoxView {
  const feed = breakFeedOf(view);
  const sent = heldSent(local, view);
  const stage = sent && feed.startedAt !== local.sentAt ? '' : (feed.stage ?? '');
  const pressing = local.pressing;
  const conflict = heldConflict(local, view) ? local.conflict : undefined;
  const reason = conflict ?? feed.reason ?? '';
  const inactive = pressing ? false : sent || feed.active !== true;
  const current = view.step ?? 1;
  const result: BoxView = {
    style: inactive ? 'inactive' : current === 5 ? 'secondary' : 'attention',
    inactive,
    busy: pressing,
    nextStep: false,
    line: '',
    hint: '',
    doStep1: false,
  };

  const startedAt = sent ? (local.sentAt ?? '') : (feed.startedAt ?? '');
  const waiting = sent || stage === 'waiting' || stage === 'still_waiting';
  if (pressing || (!sent && stage === 'sending')) {
    result.line = FEED_TEXTS.sending;
  } else if (waiting || stage === 'no_notice') {
    const since = startedAt === '' ? Number.NaN : Date.parse(startedAt);
    const seconds = Number.isNaN(since) ? 0 : Math.max(0, (nowMs - since) / 1000);
    if (stage === 'no_notice' || (waiting && seconds >= NO_NOTICE_S)) {
      result.line = FEED_TEXTS.noNotice;
    } else {
      if (stage === 'still_waiting' || seconds >= STILL_WAITING_S) {
        result.line = FEED_TEXTS.stillWaiting;
      } else {
        result.line = progressLine === '' ? FEED_TEXTS.sent : progressLine;
      }
      result.elapsed = elapsed(startedAt, nowMs);
    }
  }

  const inFlight = pressing || sent || stage === 'sending' || waiting;
  const wantsHint = !inFlight && (inactive || conflict !== undefined);
  result.hint = wantsHint ? (HINTS[reason] ?? '') : '';
  result.doStep1 = result.hint === FEED_TEXTS.notWatching;
  result.nextStep = current === 3 && !inactive && !pressing && !sent && conflict === undefined;
  return result;
}

/**
 * The run whose "Sent" a live view announces: the view's `startedAt` when this is a later view than the first one, the run is past
 * `sending` (waiting or still waiting, so a press made elsewhere is heard once the server has the batch) and it was not announced yet;
 * null otherwise. The first view is silent, so a reload never announces a run that already began.
 */
export function sentToAnnounce(previous: GuideStatePayload | undefined, next: GuideStatePayload | undefined, announced: ReadonlySet<string>): string | null {
  const feed = breakFeedOf(next);
  const startedAt = feed.startedAt ?? '';
  if (previous === undefined || startedAt === '' || announced.has(startedAt)) {
    return null;
  }
  return feed.stage === 'waiting' || feed.stage === 'still_waiting' ? startedAt : null;
}
