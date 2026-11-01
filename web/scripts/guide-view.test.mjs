// Tests the demo guide's view model (src/app/guide/guide-view.ts, Stories 4.4 and 4.7): the guide view is the server's and only in demo mode,
// the markers and names come from it, selecting changes only the selection and the prompt, the prompt of every step (promptOf: steps 1
// and 2 send, step 3 goes to Break the feed or waits, step 4 follows the variant, step 5 opens the trace), the finish state and its run line
// (runTotalText) once the view is finished, the Telegram row follows the view, and an advance is announced once for a later step of the same run. The module is imported as it
// is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { GUIDE_TEXTS, advance, currentOf, followSelection, guideOf, guideView, promptOf, runTotalText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'guide', 'guide-view.ts')).href);
const { formatCost, formatTokens } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'decision-view.ts')).href);

/** The page's token and cost formats, as the component hands them in. */
const FORMAT = { tokens: formatTokens, cost: formatCost };

const P1 = 'Watch the Orders production and only tell me if something needs me.';
const P2 = 'Remind me in 1 minute to stretch.';

/** A guide view whose first `done` steps are done and whose current step is the first one that is not. */
const view = (done = 0, over = {}) => ({
  runEpoch: 1,
  step: Math.min(5, done + 1),
  finished: false,
  steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: step <= done })),
  breakFeed: { active: false, reason: 'not_watching' },
  telegramRow: false,
  ...over,
});

describe('the fixed strings', () => {
  it('are the UX\'s exact wording, with straight ASCII quotes and the escapes of U+00B7', () => {
    assert.deepEqual({ ...GUIDE_TEXTS, labels: [...GUIDE_TEXTS.labels] }, {
      label: 'Demo guide',
      duration: 'About 2 minutes',
      hide: 'Hide guide',
      show: 'Show guide',
      next: 'Next:',
      labels: ['Watch', 'Reminder', 'Break the feed', 'Approve', 'Open the trace'],
      promptWatch: P1,
      promptReminder: P2,
      promptBreakFeed: 'Press Break the feed. The partner will send 50 orders in a new date format.',
      waiting: 'Waiting for OcuTalon. The reminder may arrive first.',
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
    });
  });
});

describe('guideOf', () => {
  const guide = view(1);
  const event = view(2);

  it('is the latest guide.state of the store, else the snapshot\'s guide, in demo mode', () => {
    assert.equal(guideOf({ demoMode: true, guide }, { guideState: event }), event);
    assert.equal(guideOf({ demoMode: true, guide }, { guideState: undefined }), guide);
    assert.equal(guideOf({ demoMode: true, guide }, undefined), guide);
  });

  it('is undefined outside demo mode, even for a snapshot that still carries a guide and a store that holds one', () => {
    assert.equal(guideOf({ demoMode: false, guide }, { guideState: event }), undefined);
    assert.equal(guideOf({ demoMode: false, guide }, undefined), undefined);
    assert.equal(guideOf(undefined, { guideState: event }), undefined);
  });

  it('is undefined for a demo snapshot with no guide and no event', () => {
    assert.equal(guideOf({ demoMode: true }, { guideState: undefined }), undefined);
  });
});

describe('guideView: markers and names', () => {
  it('shows a blank guide as step 1 current and 2 to 5 upcoming, each named with its state', () => {
    const steps = guideView(view(0), 1).steps;
    assert.deepEqual(
      steps.map((one) => [one.n, one.label, one.state, one.name, one.current]),
      [
        [1, 'Watch', 'current', 'Step 1, Watch, current', true],
        [2, 'Reminder', 'upcoming', 'Step 2, Reminder, upcoming', false],
        [3, 'Break the feed', 'upcoming', 'Step 3, Break the feed, upcoming', false],
        [4, 'Approve', 'upcoming', 'Step 4, Approve, upcoming', false],
        [5, 'Open the trace', 'upcoming', 'Step 5, Open the trace, upcoming', false],
      ],
    );
  });

  it('marks a step done only when the view says so, and gives the current marker to the view\'s step', () => {
    const steps = guideView(view(2), 3).steps;
    assert.deepEqual(steps.map((one) => one.state), ['done', 'done', 'current', 'upcoming', 'upcoming']);
    assert.equal(steps[0].name, 'Step 1, Watch, done');
    assert.equal(steps[2].name, 'Step 3, Break the feed, current');
    assert.deepEqual(steps.map((one) => one.current), [false, false, true, false, false]);
  });

  it('gives a done step after the current one a check, and the current step its marker even when the view also marks it done', () => {
    const later = view(0, { steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: step === 5 || step === 1 })), step: 2 });
    assert.deepEqual(guideView(later, 2).steps.map((one) => one.state), ['done', 'current', 'upcoming', 'upcoming', 'done']);
    const all = view(5);
    assert.deepEqual(guideView(all, 5).steps.map((one) => one.state), ['done', 'done', 'done', 'done', 'current']);
  });

  it('reads the current step from the view\'s step, kept within 1 and 5', () => {
    assert.equal(currentOf({ step: 4 }), 4);
    assert.equal(currentOf({}), 1);
    assert.equal(currentOf({ step: 0 }), 1);
    assert.equal(currentOf({ step: 9 }), 5);
    assert.equal(currentOf({ step: Number.NaN }), 1);
  });
});

describe('guideView: the selection', () => {
  it('marks the selected step and leaves the current step and the markers as the view has them', () => {
    const chosen = guideView(view(0), 2);
    assert.deepEqual(chosen.steps.map((one) => one.selected), [false, true, false, false, false]);
    assert.equal(chosen.selected, 2);
    assert.equal(chosen.current, 1);
    assert.deepEqual(chosen.steps.map((one) => one.state), guideView(view(0), 1).steps.map((one) => one.state), 'a click marks nothing done');
  });

  it('has the exact prompt of steps 1 and 2, quoted, each with a Send action', () => {
    assert.deepEqual(guideView(view(0), 1).prompt, { text: P1, quoted: `"${P1}"`, action: 'send' });
    assert.deepEqual(guideView(view(0), 2).prompt, { text: P2, quoted: `"${P2}"`, action: 'send' });
  });

  it('has a prompt for every step, and none once the guide is finished', () => {
    for (const step of [1, 2, 3, 4, 5]) assert.ok(guideView(view(0), step).prompt, `step ${step}`);
    for (const step of [1, 3, 5]) assert.equal(guideView(view(5, { finished: true }), step).prompt, undefined, `finished, step ${step}`);
  });

  it('keeps the selected step within 1 and 5', () => {
    assert.equal(guideView(view(0), 0).selected, 1);
    assert.equal(guideView(view(0), 9).selected, 5);
  });
});

describe('guideView: the Telegram row and the collapsed bar', () => {
  it('shows the Telegram row exactly when the view says so', () => {
    assert.equal(guideView(view(0, { telegramRow: true }), 1).telegramRow, true);
    assert.equal(guideView(view(0, { telegramRow: false }), 1).telegramRow, false);
    assert.equal(guideView({ step: 1 }, 1).telegramRow, false);
  });

  it('names the current step in the collapsed bar', () => {
    assert.equal(guideView(view(0), 1).collapsed, 'step 1 of 5');
    assert.equal(guideView(view(2), 1).collapsed, 'step 3 of 5');
  });
});

describe('advance', () => {
  it('announces "Step {n} of 5: {step}" for a later step of the same run', () => {
    assert.equal(advance(view(0), view(1)), 'Step 2 of 5: Reminder');
    assert.equal(advance(view(1), view(2)), 'Step 3 of 5: Break the feed');
    assert.equal(advance(view(2), view(4)), 'Step 5 of 5: Open the trace');
  });

  it('is silent for the first view, a view of the same step, a lower step and another run', () => {
    assert.equal(advance(undefined, view(1)), null, 'the first view');
    assert.equal(advance(view(1), view(1)), null, 'a reload with the same step');
    assert.equal(advance(view(2), view(1)), null, 'a lower step (Run again)');
    assert.equal(advance(view(1), view(2, { runEpoch: 2 })), null, 'another run');
    assert.equal(advance(view(1), undefined), null, 'no view');
  });
});

describe('followSelection', () => {
  it('selects the current step for the first view, and whenever the current step changes', () => {
    assert.equal(followSelection(undefined, view(1), undefined), 2);
    assert.equal(followSelection(view(1), view(2), 1), 3, 'an advance moves the selection');
    assert.equal(followSelection(view(2), view(0), 3), 1, 'Run again returns to the new current step');
    assert.equal(followSelection(view(1, { runEpoch: 1 }), view(1, { runEpoch: 2 }), 4), 2, 'another run');
  });

  it('keeps the user\'s selection when the current step does not change, and has none without a view', () => {
    assert.equal(followSelection(view(1), view(1), 4), 4);
    assert.equal(followSelection(view(1), undefined, 4), undefined);
  });
});

describe('the CI mock scenarios of the guide\'s prompts', () => {
  const scenario = (name) => JSON.parse(readFileSync(join(here, '..', '..', 'ci', 'mock', 'scenarios', 'B', `${name}.json`), 'utf8'));

  it('key the exact text of the guide\'s step 1 and step 2 prompts, so a changed prompt cannot leave the mock without its scenario', () => {
    assert.equal(scenario('guide-watch').match.prompt, GUIDE_TEXTS.promptWatch);
    assert.equal(scenario('guide-reminder').match.prompt, GUIDE_TEXTS.promptReminder);
    assert.equal(GUIDE_TEXTS.promptWatch, P1);
    assert.equal(GUIDE_TEXTS.promptReminder, P2);
  });
});

describe('promptOf: steps 3 to 5 (Story 4.7, rows 1 to 6)', () => {
  const quoted = (text) => `"${text}"`;
  const T = GUIDE_TEXTS;

  it('step 3 sends the user to Break the feed, quoted, for every stage but the waiting ones (row 1)', () => {
    for (const stage of [undefined, '', 'no_notice', 'notice_arrived']) {
      const prompt = promptOf(3, view(2, { breakFeed: { active: true, stage } }));
      assert.deepEqual(prompt, { text: T.promptBreakFeed, quoted: quoted(T.promptBreakFeed), action: 'none' }, String(stage));
    }
    assert.deepEqual(promptOf(3, { step: 3 }), { text: T.promptBreakFeed, quoted: quoted(T.promptBreakFeed), action: 'none' }, 'a view with no breakFeed');
  });

  it('step 3 shows only the waiting line, unquoted and with no action, while the batch is sending or waiting (row 2)', () => {
    for (const stage of ['sending', 'waiting', 'still_waiting']) {
      assert.deepEqual(promptOf(3, view(2, { breakFeed: { active: false, stage } })), { text: T.waiting, quoted: T.waiting, action: 'none', waiting: true }, stage);
    }
  });

  it('step 4 shows the approve text with Show me for a paired or unpaired view (row 3)', () => {
    assert.deepEqual(promptOf(4, view(3, { step4Variant: 'paired' })), { text: T.approvePaired, quoted: quoted(T.approvePaired), action: 'showMe' });
    assert.deepEqual(promptOf(4, view(3, { step4Variant: 'unpaired' })), { text: T.approveUnpaired, quoted: quoted(T.approveUnpaired), action: 'showMe' });
    assert.equal(promptOf(4, view(3)).text, T.approveUnpaired, 'no variant reads as unpaired');
  });

  it('step 4 shows the rejected, fallback and no-fix texts with no action (row 4)', () => {
    for (const [variant, text] of [['rejected', T.rejected], ['fallback', T.fallback], ['no_fix', T.noFix]]) {
      assert.deepEqual(promptOf(4, view(3, { step4Variant: variant })), { text, quoted: quoted(text), action: 'none' }, variant);
    }
  });

  it('step 5 gives Open the trace only with the view\'s trace URL, and the quoted prompt either way (rows 5 and 6)', () => {
    const withTrace = view(4, { trace: { traceHeaderId: 7, traceNamespace: 'OCUTALON', traceUrl: '/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=7' } });
    assert.deepEqual(promptOf(5, withTrace), { text: T.promptTrace, quoted: quoted(T.promptTrace), action: 'openTrace' });
    for (const trace of [undefined, {}, { traceHeaderId: 7, traceNamespace: 'OCUTALON' }, { traceUrl: '' }]) {
      assert.deepEqual(promptOf(5, view(4, { trace })), { text: T.promptTrace, quoted: quoted(T.promptTrace), action: 'none' }, JSON.stringify(trace));
    }
  });

  it('is what guideView gives the selected step, whatever the current step is', () => {
    const guide = view(2, { step4Variant: 'paired' });
    assert.deepEqual(guideView(guide, 4).prompt, promptOf(4, guide));
    assert.deepEqual(guideView(guide, 3).prompt, promptOf(3, guide));
  });
});

describe('guideView: the finish state (Story 4.7, row 7)', () => {
  const run = { decisions: 3, tokens: 9850, costUSD: 0.0041, models: ['Claude Haiku 5.5'] };

  it('replaces the prompt when the view is finished, with the run line when the view carries the run', () => {
    const done = guideView(view(5, { finished: true, run }), 5, FORMAT);
    assert.equal(done.prompt, undefined);
    assert.deepEqual(done.finish, { runTotal: 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on Claude Haiku 5.5.' });
  });

  it('has no run line without a run, and the step list stays', () => {
    const done = guideView(view(5, { finished: true }), 5, FORMAT);
    assert.deepEqual(done.finish, {});
    assert.equal(done.steps.length, 5);
  });

  it('has no finish while the view is not finished, whatever step is current or selected', () => {
    for (const finished of [false, undefined]) {
      for (const step of [3, 5]) assert.equal(guideView(view(4, { finished, run }), step, FORMAT).finish, undefined, `${finished}, step ${step}`);
    }
    assert.equal(guideView(view(4, { finished: 'yes' }), 5, FORMAT).finish, undefined, 'only a true finished counts');
  });
});

describe('runTotalText (Story 4.7, row 8)', () => {
  const total = (over = {}) => runTotalText({ decisions: 3, tokens: 9850, costUSD: 0.0041, models: ['Claude Haiku 5.5'], ...over }, FORMAT);

  it('reads the UX\'s example', () => {
    assert.equal(total(), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on Claude Haiku 5.5.');
  });

  it('uses the singular at exactly 1 and the plural at 0 and above 1', () => {
    assert.equal(total({ decisions: 1, tokens: 1 }), 'This run: 1 decision \u00B7 1 token \u00B7 $0.0041 on Claude Haiku 5.5.');
    assert.equal(total({ decisions: 0, tokens: 0 }), 'This run: 0 decisions \u00B7 0 tokens \u00B7 $0.0041 on Claude Haiku 5.5.');
    assert.equal(total({ decisions: 1200, tokens: 1234567 }), 'This run: 1,200 decisions \u00B7 1,234,567 tokens \u00B7 $0.0041 on Claude Haiku 5.5.');
  });

  it('shows a zero cost as "<$0.0001"', () => {
    assert.equal(total({ costUSD: 0 }), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 <$0.0001 on Claude Haiku 5.5.');
  });

  it('drops " on {models}" with no model, and joins two models with "and" and three or more with commas and "and"', () => {
    assert.equal(total({ models: [] }), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041.');
    assert.equal(total({ models: undefined }), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041.');
    assert.equal(total({ models: ['A', 'B'] }), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on A and B.');
    assert.equal(total({ models: ['A', 'B', 'C'] }), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on A, B and C.');
    assert.equal(total({ models: ['A', 'B', 'C', 'D'] }), 'This run: 3 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on A, B, C and D.');
  });

  it('reads an absent figure as 0', () => {
    assert.equal(runTotalText({}, FORMAT), 'This run: 0 decisions \u00B7 0 tokens \u00B7 <$0.0001.');
  });
});
