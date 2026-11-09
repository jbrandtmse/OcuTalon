// Tests the Memory card's fixed texts and rules (src/app/rail/memory-card/memory-card-view.ts, Story 41.6; FR-71, FR-72, AD-28).
// The texts are EXPERIENCE.md's (Later Steps, Personality, the Memory card), the epics' (the day labels) or the Contest Planner's ruling of
// 2026-11-08 (the PUBLIC TEXT list of the story spec), each written out here word for word.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { ANSWER_WORDS, MEMORY_HEADING_ID, MEMORY_TEXTS, answerWord, forgetName, isToolRow, metaParts, nextTab } = await import(app('rail', 'memory-card', 'memory-card-view.ts'));

const PRECEDENT = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Data', 'Precedent.cls'), 'utf8');

describe('the texts', () => {
  it('are the UX wording, the epics\' day labels and the ruled strings, written out here', () => {
    assert.deepEqual(
      { ...MEMORY_TEXTS },
      {
        // EXPERIENCE 1050 to 1053.
        notes: 'Notes',
        answers: 'Your answers',
        notesIntro: "Built by OcuTalon from today's decisions, incidents, approvals and reminders. No model writes these notes.",
        notesEmpty: 'Nothing recorded yet today.',
        answersIntro: 'OcuTalon looks at these when it decides on similar items. Only your own answers are kept here.',
        forget: 'Forget',
        question: 'Forget this answer? OcuTalon will stop using it.',
        // epics.md, Story 41.6, AC 1.
        today: 'Today',
        yesterday: 'Yesterday',
        // The Contest Planner's ruling of 2026-11-08 (Spec Change Log): all approved as written.
        yesterdayEmpty: 'Nothing recorded yesterday.',
        answersEmpty: 'No answers yet.',
        forgetName: 'Forget {summary}',
        cancel: 'Cancel',
        confirm: 'Forget',
        forgetFailed: "Couldn't forget it. Nothing was changed.",
        toolNote: 'OcuTalon keeps this answer but does not use it when it decides.',
      },
    );
    for (const value of Object.values(MEMORY_TEXTS)) assert.match(value, /^[\x20-\x7e]+$/, `${value} is ASCII`);
  });

  it('give the ruled word to each stored answer, and the heading its id', () => {
    assert.deepEqual({ ...ANSWER_WORDS }, { noise: 'This was noise', approved: 'Approved', rejected: 'Rejected' });
    assert.equal(MEMORY_HEADING_ID, 'rail-heading-memory');
  });

  it('name every answer that the table can hold', () => {
    const answers = /Parameter ANSWERS \[ Final \] = "([^"]*)"/.exec(PRECEDENT)?.[1]?.split(',');
    assert.deepEqual(answers, ['noise', 'approved', 'rejected']);
    for (const answer of answers) assert.notEqual(answerWord(answer), answer, `${answer} has a word`);
  });
});

describe('answerWord', () => {
  it('gives the ruled word, and a value it does not know as served', () => {
    assert.equal(answerWord('noise'), 'This was noise');
    assert.equal(answerWord('approved'), 'Approved');
    assert.equal(answerWord('rejected'), 'Rejected');
    assert.equal(answerWord('maybe'), 'maybe');
    assert.equal(answerWord(''), '');
    assert.equal(answerWord('constructor'), 'constructor');
    assert.equal(answerWord('toString'), 'toString');
  });
});

describe('isToolRow', () => {
  it('is true for a row with no channel only', () => {
    assert.equal(isToolRow({ channel: '' }), true);
    for (const channel of ['mailbox', 'email', 'webhook', 'slack', 'system', 'heartbeat']) assert.equal(isToolRow({ channel }), false, channel);
  });
});

describe('metaParts', () => {
  it('gives when, the channel as served and the answer word, in that order', () => {
    assert.deepEqual(metaParts({ channel: 'mailbox', answer: 'noise' }, 'Monday at 14:13'), ['Monday at 14:13', 'mailbox', 'This was noise']);
    assert.deepEqual(metaParts({ channel: 'system', answer: 'approved' }, '14:13'), ['14:13', 'system', 'Approved']);
  });

  it('leaves the channel out for a tool row, and shows an unknown answer as served', () => {
    assert.deepEqual(metaParts({ channel: '', answer: 'rejected' }, '14:13'), ['14:13', 'Rejected']);
    assert.deepEqual(metaParts({ channel: 'slack', answer: 'maybe' }, '14:13'), ['14:13', 'slack', 'maybe']);
  });

  it('leaves out a part that is empty, and the page joins the rest with the rail\'s separator', () => {
    assert.deepEqual(metaParts({ channel: 'mailbox', answer: 'noise' }, ''), ['mailbox', 'This was noise']);
    assert.deepEqual(metaParts({ channel: 'mailbox', answer: '' }, '14:13'), ['14:13', 'mailbox']);
  });
});

describe('forgetName', () => {
  it('is "Forget" and the summary, so that the visible word starts the name', () => {
    assert.equal(forgetName('Invoice from Zz Dana'), 'Forget Invoice from Zz Dana');
    assert.ok(forgetName('x').startsWith(MEMORY_TEXTS.forget));
  });

  it('puts a summary with a replacement pattern in as it is', () => {
    assert.equal(forgetName('$& $1 {summary}'), 'Forget $& $1 {summary}');
  });
});

describe('nextTab', () => {
  it('is the other of the two tabs, both ways', () => {
    assert.equal(nextTab('notes'), 'answers');
    assert.equal(nextTab('answers'), 'notes');
  });
});
