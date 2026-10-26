// Tests the Break the feed box's view model (src/app/feed/break-feed-view.ts, Story 4.4): the button's style and activity follow the
// server's guide view, the stage lines and hints follow the matrix of the story, the page's own press covers the gap until the next view,
// the 90 s and 3 min lines come from the page's clock or the server's stage but never change the button, and only this run's
// `watch.progress` line shows. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { FEED_TEXTS, NO_PRESS, boxView, conflictOf, heldConflict, heldSent, sentToAnnounce, watchLine } = await import(app('feed', 'break-feed-view.ts'));
const { elapsedText } = await import(app('chat', 'page-time.ts'));

const STARTED = '2026-10-26T12:00:00Z';
const START_MS = Date.parse(STARTED);
const at = (seconds) => START_MS + seconds * 1000;

/** A guide view on `step` with the break-the-feed part given. */
const view = (breakFeed, step = 1) => ({ runEpoch: 1, step, breakFeed });
const idle = (step = 3) => view({ active: true }, step);
const run = (stage, over = {}, step = 3) => view({ active: false, reason: 'incident_in_progress', stage, startedAt: STARTED, ...over }, step);
const show = (guide, local = NO_PRESS, line = '', now = at(0)) => boxView(guide, local, line, now, elapsedText);

describe('the fixed strings', () => {
  it('are the UX\'s exact wording, with the ellipsis written as U+2026', () => {
    assert.deepEqual({ ...FEED_TEXTS }, {
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
    });
  });
});

describe('boxView: the button follows the server', () => {
  it('is inactive with the not-watching hint and Do step 1 when the server says not_watching (row 1)', () => {
    const box = show(view({ active: false, reason: 'not_watching' }, 1));
    assert.deepEqual([box.style, box.inactive, box.busy, box.nextStep, box.line, box.hint, box.doStep1], ['inactive', true, false, false, '', FEED_TEXTS.notWatching, true]);
    assert.equal(box.elapsed, undefined);
  });

  it('is inactive with the incident hint and no Do step 1 for incident_in_progress, with the stage "" or notice_arrived (row 9)', () => {
    for (const stage of [undefined, 'notice_arrived']) {
      const guide = view({ active: false, reason: 'incident_in_progress', ...(stage === undefined ? {} : { stage, startedAt: STARTED }) }, 4);
      const box = show(guide);
      assert.deepEqual([box.style, box.inactive, box.line, box.hint, box.doStep1, box.nextStep], ['inactive', true, '', FEED_TEXTS.incidentInProgress, false, false], String(stage));
    }
  });

  it('is the attention style when active, on any step but 3 and 5, with no tag (row 8)', () => {
    for (const step of [1, 2, 4]) {
      const box = show(idle(step));
      assert.deepEqual([box.style, box.inactive, box.nextStep, box.hint, box.line], ['attention', false, false, '', ''], `step ${step}`);
    }
  });

  it('adds the Next step tag on step 3 and is the secondary style with no tag on step 5 (row 8)', () => {
    assert.deepEqual([show(idle(3)).style, show(idle(3)).nextStep], ['attention', true]);
    assert.deepEqual([show(idle(5)).style, show(idle(5)).nextStep], ['secondary', false]);
  });

  it('keeps the tag off while a run is in flight and brings it back after no_notice frees the button', () => {
    assert.equal(show(run('waiting')).nextStep, false);
    assert.equal(show(run('no_notice', { active: true, reason: undefined })).nextStep, true, 'the tag returns once the server says active');
    assert.equal(show(run('no_notice', { active: true, reason: undefined }), NO_PRESS, '', at(200)).style, 'attention');
  });
});

describe('boxView: a press of this page (row 10)', () => {
  const base = idle(3);

  it('is busy with "Sending 50 orders\u2026" while the press has no answer, and the tag is gone', () => {
    const box = show(base, { pressing: true });
    assert.deepEqual([box.busy, box.line, box.nextStep, box.hint, box.elapsed], [true, FEED_TEXTS.sending, false, '', undefined]);
  });

  it('is inactive with the sent line and the elapsed time after a 200, whatever the view still says', () => {
    const local = { pressing: false, sentAt: STARTED, base };
    const box = show(base, local, '', at(23));
    assert.deepEqual([box.inactive, box.style, box.busy, box.line, box.hint, box.nextStep], [true, 'inactive', false, FEED_TEXTS.sent, '', false]);
    assert.deepEqual(box.elapsed, { text: '23 s', spoken: '23 seconds' });
  });

  it('holds the sent line through a view that still carries the run\'s sending stage, and ends it at the stage after', () => {
    const local = { pressing: false, sentAt: STARTED, base };
    assert.equal(heldSent(local, run('sending')), true);
    assert.equal(show(run('sending'), local, '', at(2)).line, FEED_TEXTS.sent);
    assert.equal(heldSent(local, run('waiting')), false, 'a view past sending releases it');
    assert.equal(show(run('waiting'), local, '', at(2)).line, FEED_TEXTS.sent, 'the waiting stage shows the same line, from the server');
    assert.equal(heldSent(local, run('still_waiting')), false);
  });

  it('releases the sent line for a view of another run or of none, but not for the view the page held when the answer came', () => {
    const local = { pressing: false, sentAt: STARTED, base };
    assert.equal(heldSent(local, base), true, 'the same view: no later view yet');
    assert.equal(heldSent(local, idle(3)), false, 'a later view with no run');
    assert.equal(heldSent(local, run('waiting', { startedAt: '2026-10-26T12:30:00Z' })), false, 'another run');
    assert.equal(heldSent(NO_PRESS, base), false);
  });

  it('shows the 409\'s reason until the next view, and the not-watching one with Do step 1', () => {
    const local = { pressing: false, conflict: 'not_watching', base };
    const box = show(base, local);
    assert.deepEqual([box.hint, box.doStep1, box.line], [FEED_TEXTS.notWatching, true, '']);
    assert.equal(show(base, { ...local, conflict: 'incident_in_progress' }).hint, FEED_TEXTS.incidentInProgress);
    assert.equal(heldConflict(local, base), true);
    assert.equal(heldConflict(local, idle(3)), false, 'the next view clears it');
    assert.equal(show(idle(3), local).hint, '');
  });

  it('shows the sent line for a press from an earlier run\'s no_notice view, not that run\'s 3 min line, until a later view', () => {
    const earlier = run('no_notice', { active: true, reason: undefined, startedAt: '2026-10-26T11:50:00Z' });
    const local = { pressing: false, sentAt: STARTED, base: earlier };
    const box = show(earlier, local, '', at(4));
    assert.deepEqual([box.line, box.inactive, box.style, box.hint, box.nextStep], [FEED_TEXTS.sent, true, 'inactive', '', false]);
    assert.deepEqual(box.elapsed, { text: '4 s', spoken: '4 seconds' }, 'with this run\'s elapsed time');
  });

  it('drops the Next step tag while a 409 holds, though the button still follows the view, and the next view brings it back', () => {
    const local = { pressing: false, conflict: 'not_watching', base };
    const box = show(base, local);
    assert.deepEqual([box.nextStep, box.style, box.hint], [false, 'attention', FEED_TEXTS.notWatching]);
    assert.equal(show(idle(3), local).nextStep, true, 'a later view ends the 409');
  });

  it('follows the view\'s activity under a 409: the button stays as the server says', () => {
    const local = { pressing: false, conflict: 'incident_in_progress', base };
    assert.equal(show(base, local).inactive, false);
    const inactive = view({ active: false, reason: 'not_watching' }, 1);
    assert.equal(show(inactive, { pressing: false, conflict: 'incident_in_progress', base: inactive }).inactive, true);
  });

  it('reads a 409\'s code, and nothing from a 500, a network error or an unknown code', () => {
    assert.equal(conflictOf({ status: 409, error: { error: { code: 'not_watching' } } }), 'not_watching');
    assert.equal(conflictOf({ status: 409, error: { error: { code: 'incident_in_progress' } } }), 'incident_in_progress');
    assert.equal(conflictOf({ status: 409, error: { error: { code: 'other' } } }), undefined);
    assert.equal(conflictOf({ status: 500, error: { error: { code: 'not_watching' } } }), undefined);
    assert.equal(conflictOf({ status: 0 }), undefined);
    assert.equal(conflictOf(new Error('x')), undefined);
    assert.equal(conflictOf(null), undefined);
  });
});

describe('boxView: the stages (rows 11 and 12)', () => {
  it('shows "Sending 50 orders\u2026" for a server sending stage with no press of this page, inactive, with no spinner', () => {
    const box = show(run('sending'));
    assert.deepEqual([box.line, box.busy, box.inactive, box.hint, box.elapsed], [FEED_TEXTS.sending, false, true, '', undefined]);
  });

  it('shows the sent line for waiting with no progress, and the newest progress line when there is one, with the elapsed time', () => {
    assert.equal(show(run('waiting'), NO_PRESS, '', at(10)).line, FEED_TEXTS.sent);
    for (const line of [FEED_TEXTS.noticed, FEED_TEXTS.settling, FEED_TEXTS.diagnosing]) {
      const box = show(run('waiting'), NO_PRESS, line, at(10));
      assert.equal(box.line, line);
      assert.deepEqual(box.elapsed, { text: '10 s', spoken: '10 seconds' }, 'the elapsed time stays');
      assert.equal(box.hint, '');
    }
  });

  it('shows no count in any line', () => {
    for (const text of [FEED_TEXTS.noticed, FEED_TEXTS.settling, FEED_TEXTS.diagnosing, FEED_TEXTS.sent, FEED_TEXTS.stillWaiting, FEED_TEXTS.noNotice]) {
      assert.doesNotMatch(text.replace('3 minutes', ''), /\d/, text);
    }
  });

  it('formats the elapsed time at 0, 59, 60, 89 s (seconds, then minutes)', () => {
    const elapsed = (seconds) => show(run('waiting'), NO_PRESS, '', at(seconds)).elapsed;
    assert.deepEqual(elapsed(0), { text: '0 s', spoken: '0 seconds' });
    assert.deepEqual(elapsed(59), { text: '59 s', spoken: '59 seconds' });
    assert.deepEqual(elapsed(60), { text: '1 min', spoken: '1 minute' });
    assert.deepEqual(elapsed(89), { text: '1 min', spoken: '1 minute' });
  });

  it('shows the 90 s line from the page\'s clock at 90 s, and the sent line at 89 s, while the server still says waiting', () => {
    assert.equal(show(run('waiting'), NO_PRESS, '', at(89)).line, FEED_TEXTS.sent);
    const box = show(run('waiting'), NO_PRESS, '', at(90));
    assert.equal(box.line, FEED_TEXTS.stillWaiting);
    assert.deepEqual(box.elapsed, { text: '1 min', spoken: '1 minute' });
    assert.equal(box.inactive, true, 'the button still follows the server');
  });

  it('shows the 90 s line instead of a progress line, and from the server\'s still_waiting stage whatever the page\'s clock says', () => {
    assert.equal(show(run('waiting'), NO_PRESS, FEED_TEXTS.diagnosing, at(120)).line, FEED_TEXTS.stillWaiting);
    assert.equal(show(run('still_waiting'), NO_PRESS, FEED_TEXTS.noticed, at(5)).line, FEED_TEXTS.stillWaiting);
  });

  it('shows the 3 min line from the page\'s clock at 180 s, with the button still inactive, and not at 179 s', () => {
    assert.equal(show(run('still_waiting'), NO_PRESS, '', at(179)).line, FEED_TEXTS.stillWaiting);
    const box = show(run('still_waiting'), NO_PRESS, '', at(180));
    assert.deepEqual([box.line, box.inactive, box.style, box.nextStep, box.elapsed], [FEED_TEXTS.noNotice, true, 'inactive', false, undefined]);
  });

  it('shows the 3 min line for the server\'s no_notice stage, with an active button only when the server says active', () => {
    const active = show(run('no_notice', { active: true, reason: undefined }), NO_PRESS, '', at(185));
    assert.deepEqual([active.line, active.inactive, active.style, active.hint], [FEED_TEXTS.noNotice, false, 'attention', '']);
    const early = show(run('no_notice', { active: true, reason: undefined }), NO_PRESS, '', at(100));
    assert.equal(early.line, FEED_TEXTS.noNotice, 'the server\'s stage comes first');
    const frozen = show(run('no_notice'), NO_PRESS, '', at(185));
    assert.deepEqual([frozen.line, frozen.inactive, frozen.hint], [FEED_TEXTS.noNotice, true, FEED_TEXTS.incidentInProgress], 'inactive: the line and the hint');
  });

  it('ends every line at notice_arrived, and shows the lines of a sent press over the page\'s clock too', () => {
    const arrived = show(run('notice_arrived'), NO_PRESS, FEED_TEXTS.noticed, at(30));
    assert.deepEqual([arrived.line, arrived.elapsed, arrived.hint], ['', undefined, FEED_TEXTS.incidentInProgress]);
    const held = idle(3);
    const local = { pressing: false, sentAt: STARTED, base: held };
    assert.equal(show(held, local, '', at(90)).line, FEED_TEXTS.stillWaiting);
    assert.equal(show(held, local, '', at(180)).line, FEED_TEXTS.noNotice);
  });

  it('reads the elapsed time as 0 s for a run that starts ahead of the page\'s clock', () => {
    assert.deepEqual(show(run('waiting'), NO_PRESS, '', at(-4)).elapsed, { text: '0 s', spoken: '0 seconds' });
  });
});

describe('watchLine (row 11)', () => {
  const progress = (entries) => Object.fromEntries(entries.map(([ref, stage]) => [ref, { ref, stage }]));

  it('is the newest stage\'s line of a ref that was not on the page before the run', () => {
    assert.equal(watchLine(progress([['w1', 'noticed']]), new Set()), FEED_TEXTS.noticed);
    assert.equal(watchLine(progress([['w1', 'settling']]), new Set()), FEED_TEXTS.settling);
    assert.equal(watchLine(progress([['w1', 'diagnosing']]), new Set()), FEED_TEXTS.diagnosing);
    assert.equal(watchLine(progress([['w1', 'noticed'], ['w2', 'settling']]), new Set()), FEED_TEXTS.settling, 'the newest ref wins');
  });

  it('ignores a ref that was in the store before the run, even when it is the newest', () => {
    assert.equal(watchLine(progress([['old', 'diagnosing']]), new Set(['old'])), '');
    assert.equal(watchLine(progress([['w1', 'noticed'], ['old', 'diagnosing']]), new Set(['old'])), FEED_TEXTS.noticed);
  });

  it('is empty with no entries, an unknown stage or no store', () => {
    assert.equal(watchLine({}, new Set()), '');
    assert.equal(watchLine(undefined, new Set()), '');
    assert.equal(watchLine(progress([['w1', 'something_else']]), new Set()), '');
  });
});

describe('sentToAnnounce (row 10: one "Sent" for each run)', () => {
  const announced = new Set();

  it('names the run when a live view first shows it past sending', () => {
    assert.equal(sentToAnnounce(idle(3), run('waiting'), announced), STARTED);
    assert.equal(sentToAnnounce(run('sending'), run('still_waiting'), announced), STARTED);
  });

  it('is silent for the first view, a view still sending, a run already announced and a view with no run', () => {
    assert.equal(sentToAnnounce(undefined, run('waiting'), announced), null, 'the first view');
    assert.equal(sentToAnnounce(idle(3), run('sending'), announced), null);
    assert.equal(sentToAnnounce(idle(3), run('waiting'), new Set([STARTED])), null, 'announced once');
    assert.equal(sentToAnnounce(idle(3), idle(3), announced), null);
    assert.equal(sentToAnnounce(idle(3), run('notice_arrived'), announced), null, 'a run seen only after its notice');
  });
});
