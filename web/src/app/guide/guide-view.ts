/**
 * The demo guide's view model (Story 4.4): the fixed strings of the guide and what its steps and prompt bar show for the server's
 * guide view. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides none of the guide's progress (AD-12). The guide view is the server's: the latest `guide.state` of the live store, or
 * the snapshot's `guide` until one arrives, and only while the snapshot says demo mode is on. The page computes only which step is
 * selected, and whether an update is an advance to announce.
 *
 * - guideOf(snapshot, store) is the guide view, or undefined outside demo mode.
 * - guideView(view, selected) gives the steps with their markers and names, the prompt bar's entry (steps 1 and 2 only; the other
 *   steps' texts and buttons are Story 4.7's) and the Telegram row.
 * - advance(previous, next) is the announcement of an advance, or null; followSelection(previous, next, selected) is the selected step
 *   after an update.
 */
import type { StateSnapshot } from '../api/api-types';
import type { GuideStatePayload } from '../live/payloads';

/** The snapshot as the guide reads it: `/state` carries `guide` only in demo mode. */
export type GuideSnapshot = StateSnapshot & { guide?: GuideStatePayload };

/** Every fixed string of the guide. The middle dot is U+00B7. The quotes of a prompt are straight ASCII quotes. */
export const GUIDE_TEXTS = {
  label: 'Demo guide',
  duration: 'About 2 minutes',
  hide: 'Hide guide',
  show: 'Show guide',
  next: 'Next:',
  labels: ['Watch', 'Reminder', 'Break the feed', 'Approve', 'Open the trace'],
  promptWatch: 'Watch the Orders production and only tell me if something needs me.',
  promptReminder: 'Remind me in 1 minute to stretch.',
  quoted: '"{text}"',
  send: 'Send',
  telegram: 'Optional: scan the QR code in the Telegram card to get the notice on your own phone.',
  stepCurrent: 'Step {n}, {label}, current',
  stepDone: 'Step {n}, {label}, done',
  stepUpcoming: 'Step {n}, {label}, upcoming',
  advanced: 'Step {n} of 5: {step}',
  collapsedStep: 'step {n} of 5',
  separator: ' \u00B7 ',
} as const;

/** The number of steps. */
export const STEP_COUNT = 5;

/** The localStorage key that says the guide was hidden in this browser. */
export const GUIDE_HIDDEN_KEY = 'ocutalon.guide.hidden';

/** The value the key holds when the guide is hidden, and when the user showed it again. */
export const GUIDE_HIDDEN_FLAG = '1';
export const GUIDE_SHOWN_FLAG = '0';

/** The guide view, or undefined when the snapshot is not loaded or demo mode is off, whatever else the snapshot carries. */
export function guideOf(snapshot: GuideSnapshot | undefined, store: { guideState?: GuideStatePayload } | undefined): GuideStatePayload | undefined {
  if (snapshot === undefined || snapshot.demoMode !== true) {
    return undefined;
  }
  return store?.guideState ?? snapshot.guide;
}

/** The text with each {name} replaced by its value. */
function fill(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (whole, name: string) => values[name] ?? whole);
}

/** The step number of a view: the server's current step, kept within 1 and the count. */
export function currentOf(view: GuideStatePayload): number {
  const step = Math.trunc(view.step ?? 1);
  return Math.min(STEP_COUNT, Math.max(1, Number.isFinite(step) ? step : 1));
}

/** The marker of a step: a check for a done step, the number for the others. */
export type StepState = 'done' | 'current' | 'upcoming';

/** One step of the guide's first row. */
export interface StepView {
  n: number;
  label: string;
  state: StepState;
  /** The step's accessible name: "Step 3, Break the feed, current". */
  name: string;
  /** True for the server's current step, which carries aria-current="step". */
  current: boolean;
  /** True for the step the user selected, which carries the bottom bar. */
  selected: boolean;
}

/** What the prompt bar holds for the selected step. */
export interface PromptView {
  /** The prompt as it is sent, with no quotes. */
  text: string;
  /** The prompt as it is shown, in quotes. */
  quoted: string;
}

/** The guide for one view and one selected step. */
export interface GuideView {
  steps: StepView[];
  current: number;
  selected: number;
  /** The prompt of the selected step; undefined for the steps whose prompts and buttons are Story 4.7's. */
  prompt?: PromptView;
  /** True when the optional Telegram line shows in the prompt bar. */
  telegramRow: boolean;
  /** The collapsed bar's step text: "step 2 of 5". */
  collapsed: string;
}

/** The exact prompt of a step that has a Send button in this release, by step number. */
function promptOf(step: number): string | undefined {
  if (step === 1) {
    return GUIDE_TEXTS.promptWatch;
  }
  return step === 2 ? GUIDE_TEXTS.promptReminder : undefined;
}

/**
 * The guide for the server's view and the selected step. A step is done only when the view says so; the current step is the view's
 * step, whether or not the view marks it done; selecting a step changes only `selected` and the prompt.
 */
export function guideView(view: GuideStatePayload, selected: number): GuideView {
  const current = currentOf(view);
  const chosen = Math.min(STEP_COUNT, Math.max(1, Math.trunc(selected)));
  const steps: StepView[] = GUIDE_TEXTS.labels.map((label, index) => {
    const n = index + 1;
    const done = view.steps?.find((one) => one.step === n)?.done === true;
    const state: StepState = n === current ? 'current' : done ? 'done' : 'upcoming';
    const template = state === 'current' ? GUIDE_TEXTS.stepCurrent : state === 'done' ? GUIDE_TEXTS.stepDone : GUIDE_TEXTS.stepUpcoming;
    return { n, label, state, name: fill(template, { n: String(n), label }), current: n === current, selected: n === chosen };
  });
  const text = promptOf(chosen);
  const result: GuideView = {
    steps,
    current,
    selected: chosen,
    telegramRow: view.telegramRow === true,
    collapsed: fill(GUIDE_TEXTS.collapsedStep, { n: String(current) }),
  };
  if (text !== undefined) {
    result.prompt = { text, quoted: fill(GUIDE_TEXTS.quoted, { text }) };
  }
  return result;
}

/**
 * The announcement of an update: "Step {n} of 5: {step}" when the update is a later step of the same run, null for the first view, a view
 * of the same step, a lower step (Run again) and another run.
 */
export function advance(previous: GuideStatePayload | undefined, next: GuideStatePayload | undefined): string | null {
  if (previous === undefined || next === undefined || (previous.runEpoch ?? 1) !== (next.runEpoch ?? 1)) {
    return null;
  }
  const step = currentOf(next);
  if (step <= currentOf(previous)) {
    return null;
  }
  return fill(GUIDE_TEXTS.advanced, { n: String(step), step: GUIDE_TEXTS.labels[step - 1] ?? '' });
}

/**
 * The selected step after an update: the new current step for the first view and whenever the current step changes (an advance, or Run
 * again), and the user's own selection otherwise. `selected` is undefined until the first view.
 */
export function followSelection(previous: GuideStatePayload | undefined, next: GuideStatePayload | undefined, selected: number | undefined): number | undefined {
  if (next === undefined) {
    return undefined;
  }
  if (selected === undefined || previous === undefined || currentOf(previous) !== currentOf(next) || (previous.runEpoch ?? 1) !== (next.runEpoch ?? 1)) {
    return currentOf(next);
  }
  return selected;
}
