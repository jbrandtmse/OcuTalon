// Tests the "Try it yourself" row's texts and in-flight reader (src/app/chat/try-it-view.ts, Story 4.10): the five strings, that each prompt
// is the exact text of its own CI mock prompt scenario under ci/mock/scenarios/B (so a changed prompt cannot leave the mock without its
// scenario), that no scenario reply holds a phrase the reply guard strips (AD-28), and when a turn is in flight. The modules are imported as
// they are: Node strips their types, which holds only while they keep to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { TRY_IT_TEXTS, turnInFlight } = await import(app('chat', 'try-it-view.ts'));
const { GUIDE_TEXTS } = await import(app('guide', 'guide-view.ts'));

const root = join(here, '..', '..');
const scenario = (name) => JSON.parse(readFileSync(join(root, 'ci', 'mock', 'scenarios', 'B', `${name}.json`), 'utf8'));
const replyGuard = readFileSync(join(root, 'src', 'ocutalon', 'cls', 'OcuTalon', 'Checks', 'ReplyGuard.cls'), 'utf8');
const parameter = (name) => {
  const found = replyGuard.match(new RegExp(`^Parameter ${name} = "([^"]*)";`, 'm'));
  assert.ok(found, `ReplyGuard has ${name}`);
  return found[1].split(',');
};

const FILES = [
  ['try-it-productions', 'Which productions are running?', [{ name: 'list_productions', input: {} }]],
  ['try-it-anything-wrong', 'Is anything wrong right now?', [{ name: 'check_status', input: {} }]],
  ['try-it-failure-earlier', 'What was that failure earlier?', [{ name: 'recent_activity', input: {} }]],
  ['try-it-what-can-you-do', 'What can you do?', []],
];

describe('TRY_IT_TEXTS', () => {
  it('is the label and the four prompts, in order', () => {
    assert.deepEqual({ ...TRY_IT_TEXTS, prompts: [...TRY_IT_TEXTS.prompts] }, {
      label: 'Try it yourself',
      prompts: ['Which productions are running?', 'Is anything wrong right now?', 'What was that failure earlier?', 'What can you do?'],
    });
  });

  it('holds only straight ASCII, and no prompt is one of the guide\'s', () => {
    for (const text of [TRY_IT_TEXTS.label, ...TRY_IT_TEXTS.prompts]) {
      assert.match(text, /^[\x20-\x7e]+$/, text);
    }
    for (const prompt of TRY_IT_TEXTS.prompts) {
      assert.notEqual(prompt, GUIDE_TEXTS.promptWatch);
      assert.notEqual(prompt, GUIDE_TEXTS.promptReminder);
    }
  });
});

describe('the CI mock scenarios of the chips\' prompts', () => {
  it('key the exact text of their chip, each prompt in exactly one B file, so a changed prompt cannot leave the mock without its scenario', () => {
    assert.equal(FILES.length, TRY_IT_TEXTS.prompts.length);
    FILES.forEach(([name], i) => {
      assert.equal(scenario(name).match.prompt, TRY_IT_TEXTS.prompts[i], `${name} keys prompt ${i + 1}`);
      assert.equal(scenario(name).name, name);
    });
  });

  it('call the tool each chip needs with no input and end in a text reply', () => {
    for (const [name, , tools] of FILES) {
      const replies = scenario(name).replies;
      assert.deepEqual(replies.filter((reply) => reply.toolUse !== undefined).map((reply) => reply.toolUse), tools, name);
      assert.equal(typeof replies.at(-1).text, 'string', `${name} ends in text`);
      assert.equal(replies.every((reply) => reply.status === 200), true, name);
    }
  });

  it('hold no reserved sentence and no banned phrase in any reply text (AD-28)', () => {
    const phrases = [...parameter('RESERVED'), ...parameter('BANNED')];
    assert.ok(phrases.length >= 9);
    for (const [name] of FILES) {
      for (const reply of scenario(name).replies) {
        for (const phrase of phrases) {
          assert.equal((reply.text ?? '').toLowerCase().includes(phrase.toLowerCase()), false, `${name}: ${phrase}`);
        }
      }
    }
  });
});

describe('turnInFlight', () => {
  const entry = (status) => ({ clientId: 'c', text: 't', fromGuide: false, sentAt: '2037-07-01T12:00:00Z', status });
  const message = (state) => ({ type: 'chat.message', payload: { ref: 'r', clientId: 'c', state } });

  it('is false for empty lists, for a failed entry only, and for done turns only', () => {
    assert.equal(turnInFlight([], []), false);
    assert.equal(turnInFlight([], [entry('failed')]), false);
    assert.equal(turnInFlight([message('done'), message('done')], []), false);
    assert.equal(turnInFlight([{ type: 'chat.message', payload: { ref: 'r' } }], []), false, 'a message with no state');
  });

  it('is true for a sending or sent entry, and for a queued or running turn', () => {
    assert.equal(turnInFlight([], [entry('sending')]), true);
    assert.equal(turnInFlight([], [entry('sent')]), true);
    assert.equal(turnInFlight([message('queued')], []), true);
    assert.equal(turnInFlight([message('done'), message('running')], []), true);
    assert.equal(turnInFlight([message('done')], [entry('failed'), entry('sent')]), true);
  });
});
