/**
 * The demo guide's view model (Story 4.4, finished by Story 4.7): the fixed strings of the guide and what its steps, prompt bar and
 * finish state show for the server's guide view. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides none of the guide's progress (AD-12). The guide view is the server's: the latest `guide.state` of the live store, or
 * the snapshot's `guide` until one arrives, and only while the snapshot says demo mode is on. The page computes only which step is
 * selected, and whether an update is an advance to announce.
 *
 * - guideOf(snapshot, store) is the guide view, or undefined outside demo mode.
 * - guideView(view, selected, format) gives the steps with their markers and names, the prompt bar's entry for the selected step
 *   (promptOf: steps 1 and 2 send their prompt, step 3 sends the user to Break the feed or waits, step 4 shows the variant's text with
 *   Show me for a pair that can approve, step 5 opens the run's trace), the finish state that replaces the prompt bar once the view says
 *   `finished`, and the Telegram row.
 * - runTotalText(run, format) is the finish state's run line; format hands in the page's token and cost formats (chat/decision-view.ts).
 * - advance(previous, next) is the announcement of an advance, or null; followSelection(previous, next, selected) is the selected step
 *   after an update.
 */
import type { StateSnapshot } from '../api/api-types';
import type { GuideRun, GuideStatePayload } from '../live/payloads';

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
  promptBreakFeed: 'Press Break the feed. The partner will send 50 orders in a new date format.',
  waiting: 'Waiting for OcuTalon. The reminder may arrive first.',
  goToBreakFeed: 'Go to Break the feed',
  approvePaired: 'Approve the fix in Telegram on your phone, or on the simulated phone.',
  approveUnpaired: 'Approve the fix on the simulated phone, or in the chat.',
  rejected: 'Rejected. Nothing was changed. Dismiss the incident in the chat, then press Break the feed again.',
  fallback: "OcuTalon couldn't diagnose this run, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again.",
  noFix: "OcuTalon found the cause but has no fix for it, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again.",
  showMe: 'Show me',
  promptTrace: "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision.",
  openTrace: 'Open the trace',
  finishDone:
    'Done. You saw an AI Hub agent read 50 failed orders and name the cause. Every decision, with its cost, and every step it took landed in Visual Trace, and the fix waited for your approval and was recorded in the audit log.',
  runTotal: 'This run: {decisions} \u00B7 {tokens} \u00B7 {cost} on {models}.',
  runTotalNoModel: 'This run: {decisions} \u00B7 {tokens} \u00B7 {cost}.',
  decisionOne: '{n} decision',
  decisionMany: '{n} decisions',
  tokenOne: '{n} token',
  tokenMany: '{n} tokens',
  modelsAnd: '{list} and {last}',
  modelsComma: ', ',
  conversationLink: 'See the whole conversation in Visual Trace',
  installLink: 'Install OcuTalon yourself',
  moreToTry: 'More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production.',
  runAgain: 'Run again',
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

/** What the prompt bar's button does: sends the prompt, focuses Break the feed, shows the phone, opens the trace, or nothing (no button). */
export type PromptAction = 'send' | 'goToBreakFeed' | 'showMe' | 'openTrace' | 'none';

/** What the prompt bar holds for the selected step. */
export interface PromptView {
  /** The prompt as it is sent, with no quotes. */
  text: string;
  /** The prompt as it is shown, in quotes; the waiting line is shown as it is. */
  quoted: string;
  /** The button of the prompt. */
  action: PromptAction;
  /** True for step 3's waiting line, which has no "Next:", no quotes and no button. */
  waiting?: true;
}

/** The finish state, which replaces the prompt bar once the server's view is finished (the component adds the links). */
export interface FinishView {
  /** The run line, when the view carries the run's total. */
  runTotal?: string;
}

/** The page's token and cost formats (chat/decision-view.ts), which the run line is written with. */
export interface RunFormat {
  tokens: (count: number | undefined) => string;
  cost: (amount: number | undefined) => string;
}

/** The guide for one view and one selected step. */
export interface GuideView {
  steps: StepView[];
  current: number;
  selected: number;
  /** The prompt of the selected step; undefined once the guide is finished. */
  prompt?: PromptView;
  /** The finish state; set exactly when the view is finished. */
  finish?: FinishView;
  /** True when the optional Telegram line shows in the prompt bar. */
  telegramRow: boolean;
  /** The collapsed bar's step text: "step 2 of 5". */
  collapsed: string;
}

/** The stages of a run's batch in which step 3 waits for the notice. */
const WAITING_STAGES: readonly string[] = ['sending', 'waiting', 'still_waiting'];

/**
 * The prompt bar's entry for a step and the server's view (AD-12: the page chooses only what to render). Steps 1 and 2 send their prompt.
 * Step 3 waits while the batch is sending or waiting, else sends the user to Break the feed. Step 4 shows the view's variant, with Show me
 * only for a pair that can approve. Step 5 opens the run's trace when the view carries its URL.
 */
export function promptOf(step: number, view: GuideStatePayload): PromptView | undefined {
  const shown = (text: string, action: PromptAction): PromptView => ({ text, quoted: fill(GUIDE_TEXTS.quoted, { text }), action });
  switch (step) {
    case 1:
      return shown(GUIDE_TEXTS.promptWatch, 'send');
    case 2:
      return shown(GUIDE_TEXTS.promptReminder, 'send');
    case 3:
      if (WAITING_STAGES.includes(view.breakFeed?.stage ?? '')) {
        return { text: GUIDE_TEXTS.waiting, quoted: GUIDE_TEXTS.waiting, action: 'none', waiting: true };
      }
      return shown(GUIDE_TEXTS.promptBreakFeed, 'goToBreakFeed');
    case 4:
      switch (view.step4Variant) {
        case 'rejected':
          return shown(GUIDE_TEXTS.rejected, 'none');
        case 'fallback':
          return shown(GUIDE_TEXTS.fallback, 'none');
        case 'no_fix':
          return shown(GUIDE_TEXTS.noFix, 'none');
        case 'paired':
          return shown(GUIDE_TEXTS.approvePaired, 'showMe');
        default:
          return shown(GUIDE_TEXTS.approveUnpaired, 'showMe');
      }
    case 5:
      return shown(GUIDE_TEXTS.promptTrace, view.trace?.traceUrl ? 'openTrace' : 'none');
    default:
      return undefined;
  }
}

/** "{n} decision(s)" or "{n} token(s)": the singular at exactly 1. */
function counted(count: number | undefined, one: string, many: string, format: RunFormat): string {
  const n = Math.max(0, Math.round(Number.isFinite(count) ? (count as number) : 0));
  return fill(n === 1 ? one : many, { n: format.tokens(n) });
}

/** The models as a list: "A", "A and B" or "A, B and C". */
function modelsText(models: readonly string[]): string {
  if (models.length < 2) {
    return models[0] ?? '';
  }
  const last = models[models.length - 1] ?? '';
  return fill(GUIDE_TEXTS.modelsAnd, { list: models.slice(0, -1).join(GUIDE_TEXTS.modelsComma), last });
}

/**
 * The finish state's run line: "This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on Claude Haiku 5.5." The figures use the page's
 * formats; a run with no model drops " on {models}".
 */
export function runTotalText(run: GuideRun, format: RunFormat): string {
  const models = (run.models ?? []).filter((one) => one !== '');
  const values = {
    decisions: counted(run.decisions, GUIDE_TEXTS.decisionOne, GUIDE_TEXTS.decisionMany, format),
    tokens: counted(run.tokens, GUIDE_TEXTS.tokenOne, GUIDE_TEXTS.tokenMany, format),
    cost: format.cost(run.costUSD),
    models: modelsText(models),
  };
  return fill(models.length === 0 ? GUIDE_TEXTS.runTotalNoModel : GUIDE_TEXTS.runTotal, values);
}

/**
 * The guide for the server's view and the selected step. A step is done only when the view says so; the current step is the view's
 * step, whether or not the view marks it done; selecting a step changes only `selected` and the prompt. A finished view has the finish
 * state in place of the prompt, with the run line when the view carries `run` and the formats are given.
 */
export function guideView(view: GuideStatePayload, selected: number, format?: RunFormat): GuideView {
  const current = currentOf(view);
  const chosen = Math.min(STEP_COUNT, Math.max(1, Math.trunc(selected)));
  const steps: StepView[] = GUIDE_TEXTS.labels.map((label, index) => {
    const n = index + 1;
    const done = view.steps?.find((one) => one.step === n)?.done === true;
    const state: StepState = n === current ? 'current' : done ? 'done' : 'upcoming';
    const template = state === 'current' ? GUIDE_TEXTS.stepCurrent : state === 'done' ? GUIDE_TEXTS.stepDone : GUIDE_TEXTS.stepUpcoming;
    return { n, label, state, name: fill(template, { n: String(n), label }), current: n === current, selected: n === chosen };
  });
  const result: GuideView = {
    steps,
    current,
    selected: chosen,
    telegramRow: view.telegramRow === true,
    collapsed: fill(GUIDE_TEXTS.collapsedStep, { n: String(current) }),
  };
  if (view.finished === true) {
    result.finish = view.run !== undefined && format !== undefined ? { runTotal: runTotalText(view.run, format) } : {};
  } else {
    const prompt = promptOf(chosen, view);
    if (prompt !== undefined) {
      result.prompt = prompt;
    }
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
