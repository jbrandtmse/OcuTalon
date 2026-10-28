// Tests of the scenario file format and its loader (Story 0.11, row 15 of the I/O matrix, and the Lane A rule of AC5): the
// committed files load, each fixture tree with one defect is refused with the file and the rule named, the mock server lists
// every problem and exits 1, and a valid file added to a tree is served with no code change. Each test makes its fixture tree
// in a fresh temporary folder and removes it. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { BOT_METHODS, checkTelegramReplies, findMarkers, KEY_PATTERN, loadScenarios, MATCH_TYPES, NAME_PATTERN, parseLabel, REPLY_FIELDS, STOP_REASONS, TELEGRAM_REPLY_FIELDS } from '../scenarios.mjs';
import { spawnServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MOCK_DIR = path.join(HERE, '..');
const COMMITTED = path.join(MOCK_DIR, 'scenarios');
const SERVER = path.join(MOCK_DIR, 'server.mjs');

const GOOD = { name: 'good', match: { marker: 'good' }, replies: [{ status: 200, text: 'ok' }] };

// tree(files): a fresh scenarios folder; a value that is an object is written as JSON, a string as is, and null makes a folder.
function tree(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-scn-'));
  for (const [rel, data] of Object.entries(files)) {
    const full = path.join(dir, rel);
    if (data === null) {
      fs.mkdirSync(full, { recursive: true });
    } else {
      fs.mkdirSync(path.dirname(full), { recursive: true });
      fs.writeFileSync(full, typeof data === 'string' ? data : JSON.stringify(data, null, 2));
    }
  }
  return dir;
}

function withTree(files, fn) {
  const dir = tree(files);
  try {
    return fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const reply = (extra) => ({ status: 200, ...extra });
const TG_REPLY = { status: 200, body: { ok: true, result: true } };

// Each defect: [what, files, text that the problem must hold (the file, then the rule)].
const DEFECTS = [
  ['a name that is not kebab-case', { 'A/bad.json': { name: 'Bad_Name', match: { marker: 'Bad_Name' }, replies: [reply({ text: 'x' })] } }, ['A/bad.json', 'kebab-case']],
  ['a name that differs from the file name', { 'A/one.json': { name: 'two', match: { marker: 'two' }, replies: [reply({ text: 'x' })] } }, ['A/one.json', 'differs from the file name']],
  ['an unknown field', { 'A/good.json': { ...GOOD, extra: 1 } }, ['A/good.json', 'unknown field "extra"']],
  ['a match with no key', { 'A/good.json': { ...GOOD, match: {} } }, ['A/good.json', 'exactly one key']],
  ['a match with two keys', { 'A/good.json': { ...GOOD, match: { marker: 'good', mockkey: 'good' } } }, ['A/good.json', 'exactly one key']],
  ['a match with an unknown key', { 'A/good.json': { ...GOOD, match: { header: 'good' } } }, ['A/good.json', 'unknown key']],
  ['a telegram match with a model reply', { 'A/good.json': { ...GOOD, match: { telegram: 'getUpdates' } } }, ['A/good.json', 'a reply has the unknown field "text"']],
  ['a telegram match with getFile', { 'A/good.json': { ...GOOD, match: { telegram: 'getFile' }, replies: [TG_REPLY] } }, ['A/good.json', 'getFile arrives in Story 25.3']],
  ['a telegram match with a method the mock does not serve', { 'A/good.json': { ...GOOD, match: { telegram: 'kick' }, replies: [TG_REPLY] } }, ['A/good.json', 'match telegram must be one of getMe, getUpdates, sendMessage, editMessageText, answerCallbackQuery']],
  ['a telegram match that is not a string', { 'A/good.json': { ...GOOD, match: { telegram: 5 }, replies: [TG_REPLY] } }, ['A/good.json', 'match telegram is not a non-empty string']],
  ['a telegram reply with no body', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200 }] } }, ['A/good.json', 'a telegram reply needs a body that is a JSON object']],
  ['a telegram reply with a body that is a list', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200, body: [1] }] } }, ['A/good.json', 'a telegram reply needs a body that is a JSON object']],
  ['a telegram reply with text', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200, body: {}, text: 'x' }] } }, ['A/good.json', 'a reply has the unknown field "text"']],
  ['a telegram reply with toolUse', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200, body: {}, toolUse: { name: 'a' } }] } }, ['A/good.json', 'a reply has the unknown field "toolUse"']],
  ['a telegram reply with a stopReason', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200, body: {}, stopReason: 'end_turn' }] } }, ['A/good.json', 'a reply has the unknown field "stopReason"']],
  ['a telegram reply with a status of 99', { 'B/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 99, body: {} }] } }, ['B/good.json', 'status must be an integer from 100 to 599']],
  ['a telegram reply with a Content-Length header', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200, body: {}, headers: { 'Content-Length': '5' } }] } }, ['A/good.json', 'is set by the mock, never by a scenario']],
  ['a telegram reply with a delayMs above 600000', { 'A/good.json': { ...GOOD, match: { telegram: 'getMe' }, replies: [{ status: 200, body: {}, delayMs: 600001 }] } }, ['A/good.json', 'delayMs must be an integer from 0 to 600000']],
  ['a marker that differs from the name', { 'A/good.json': { ...GOOD, match: { marker: 'other' } } }, ['A/good.json', 'differs from name']],
  ['a prompt scenario under A', { 'A/good.json': { ...GOOD, match: { prompt: 'Some guide prompt.' } } }, ['A/good.json', 'belongs under B/']],
  ['a repeated name', { 'A/good.json': GOOD, 'B/good.json': GOOD }, ['B/good.json', 'name "good" repeats']],
  ['a repeated mock key', { 'A/one.json': { ...GOOD, name: 'one', match: { mockkey: 'k' } }, 'B/two.json': { ...GOOD, name: 'two', match: { mockkey: 'k' } } }, ['B/two.json', 'mock key "k" repeats']],
  ['a repeated prompt', { 'B/one.json': { ...GOOD, name: 'one', match: { prompt: 'The same prompt.' } }, 'B/two.json': { ...GOOD, name: 'two', match: { prompt: 'The same prompt.' } } }, ['B/two.json', 'prompt repeats']],
  ['a prompt that contains another prompt', { 'B/one.json': { ...GOOD, name: 'one', match: { prompt: 'Summarize the open incidents.' } }, 'B/two.json': { ...GOOD, name: 'two', match: { prompt: 'Please. Summarize the open incidents. Thanks.' } } }, ['B/two.json', 'contains the prompt of B/one.json']],
  ['empty replies', { 'A/good.json': { ...GOOD, replies: [] } }, ['A/good.json', 'replies must be a non-empty list']],
  ['a reply with none of text, toolUse and body', { 'A/good.json': { ...GOOD, replies: [{ status: 200 }] } }, ['A/good.json', 'exactly one of text, toolUse and body']],
  ['a reply with two of text, toolUse and body', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', body: {} })] } }, ['A/good.json', 'exactly one of text, toolUse and body']],
  ['a status of 99', { 'A/good.json': { ...GOOD, replies: [{ status: 99, text: 'x' }] } }, ['A/good.json', 'status must be an integer from 100 to 599']],
  ['a status of 600', { 'A/good.json': { ...GOOD, replies: [{ status: 600, text: 'x' }] } }, ['A/good.json', 'status must be an integer from 100 to 599']],
  ['a status that is a string', { 'A/good.json': { ...GOOD, replies: [{ status: '200', text: 'x' }] } }, ['A/good.json', 'status must be an integer']],
  ['no status', { 'A/good.json': { ...GOOD, replies: [{ text: 'x' }] } }, ['A/good.json', 'status must be an integer']],
  ['a stopReason that is not an API value', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', stopReason: 'done' })] } }, ['A/good.json', 'stopReason is not one of']],
  ['a stopReason with a body', { 'A/good.json': { ...GOOD, replies: [reply({ body: {}, stopReason: 'end_turn' })] } }, ['A/good.json', 'stopReason cannot come with a body']],
  ['a stopReason with an error status', { 'A/good.json': { ...GOOD, replies: [{ status: 500, text: 'x', stopReason: 'end_turn' }] } }, ['A/good.json', 'stopReason cannot come with an error status']],
  ['a delayMs below 0', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', delayMs: -1 })] } }, ['A/good.json', 'delayMs must be an integer from 0 to 600000']],
  ['a delayMs above 600000', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', delayMs: 600001 })] } }, ['A/good.json', 'delayMs must be an integer from 0 to 600000']],
  ['a toolUse with no name', { 'A/good.json': { ...GOOD, replies: [reply({ toolUse: { input: {} } })] } }, ['A/good.json', 'a toolUse has no name']],
  ['a toolUse list with an item that has no name', { 'A/good.json': { ...GOOD, replies: [reply({ toolUse: [{ name: 'a' }, {}] })] } }, ['A/good.json', 'a toolUse has no name']],
  ['a reply with an unknown field', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', delayMS: 5 })] } }, ['A/good.json', 'a reply has the unknown field "delayMS"']],
  ['a reply that is not an object', { 'A/good.json': { ...GOOD, replies: ['x'] } }, ['A/good.json', 'a reply is not an object']],
  ['a text that is not a string', { 'A/good.json': { ...GOOD, replies: [reply({ text: 5 })] } }, ['A/good.json', 'text is not a string']],
  ['a body that is not an object or a list', { 'A/good.json': { ...GOOD, replies: [reply({ body: 'x' })] } }, ['A/good.json', 'body is not a JSON object or list']],
  ['headers that are not strings', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', headers: { a: 1 } })] } }, ['A/good.json', 'headers must be an object of strings']],
  ['a header name that is not an HTTP token', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', delayMs: 5, headers: { 'Retry After': '1' } })] } }, ['A/good.json', 'is not a valid HTTP header name and value']],
  ['a header value with a line break', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', headers: { 'Retry-After': '1\r\nX-Other: 2' } })] } }, ['A/good.json', 'is not a valid HTTP header name and value']],
  ['a Content-Length header', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', headers: { 'Content-Length': '5' } })] } }, ['A/good.json', 'is set by the mock, never by a scenario']],
  ['a Transfer-Encoding header', { 'A/good.json': { ...GOOD, replies: [reply({ text: 'x', headers: { 'transfer-encoding': 'chunked' } })] } }, ['A/good.json', 'is set by the mock, never by a scenario']],
  ['an empty toolUse list', { 'A/good.json': { ...GOOD, replies: [reply({ toolUse: [] })] } }, ['A/good.json', 'toolUse is an empty list']],
  ['a toolUse input that is not an object', { 'A/good.json': { ...GOOD, replies: [reply({ toolUse: { name: 'a', input: 5 } })] } }, ['A/good.json', 'a toolUse input is not an object']],
  ['a toolUse with an unknown field', { 'A/good.json': { ...GOOD, replies: [reply({ toolUse: { name: 'a', arguments: {} } })] } }, ['A/good.json', 'a toolUse has the unknown field "arguments"']],
  ['a toolUse with an error status', { 'A/good.json': { ...GOOD, replies: [{ status: 500, toolUse: { name: 'a' } }] } }, ['A/good.json', 'a toolUse reply needs a status below 400']],
  ['a match value that is empty', { 'A/good.json': { ...GOOD, match: { mockkey: '' } } }, ['A/good.json', 'match mockkey is not a non-empty string']],
  ['a mock key with white space', { 'A/good.json': { ...GOOD, match: { mockkey: 'a b' } } }, ['A/good.json', 'the mock key holds white space']],
  ['a file that is a JSON list', { 'A/good.json': '[1]' }, ['A/good.json', 'the file is not a JSON object']],
  ['a file that is not .json', { 'A/readme.md': 'text' }, ['A/readme.md', 'only .json files and dotfiles']],
  ['a folder other than A and B', { 'C/good.json': GOOD }, ['C', 'only the folders A and B']],
  ['a file next to the folders', { 'good.json': GOOD }, ['good.json', 'only the folders A and B']],
  ['a folder inside A', { 'A/sub': null }, ['A/sub', 'a folder inside A/']],
  ['a file that is not JSON', { 'A/good.json': '{ not json' }, ['A/good.json', 'not valid JSON']],
  ['a name of 65 characters', { [`A/${'a'.repeat(65)}.json`]: { ...GOOD, name: 'a'.repeat(65), match: { marker: 'a'.repeat(65) } } }, [`A/${'a'.repeat(65)}.json`, 'kebab-case']],
  ['no name', { 'A/good.json': { match: GOOD.match, replies: GOOD.replies } }, ['A/good.json', 'kebab-case']],
  ['no match', { 'A/good.json': { name: 'good', replies: GOOD.replies } }, ['A/good.json', 'exactly one key']],
  ['no replies', { 'A/good.json': { name: 'good', match: GOOD.match } }, ['A/good.json', 'replies must be a non-empty list']],
  ['replies that are not a list', { 'A/good.json': { ...GOOD, replies: { status: 200, text: 'x' } } }, ['A/good.json', 'replies must be a non-empty list']],
  ['a prompt scenario with an empty prompt', { 'B/guide.json': { name: 'guide', match: { prompt: '' }, replies: [reply({ text: 'x' })] } }, ['B/guide.json', 'match prompt is not a non-empty string']],
];

// The scenarios of Story 0.11: the three default scripts and the marker scenarios of Stories 1.6 to 1.9. Lane A and Lane B add
// files beside them, so the committed set is checked for these, never for a count.
const STORY_SCENARIOS = [
  'chat', 'diagnosis', 'empty', 'held-past-timer', 'invalid-input', 'invalid-reply', 'long-retry-after', 'max-tokens', 'overloaded',
  'provider-error', 'rate-limited', 'refusal', 'summary', 'summary-off-schema', 'tool-loop', 'triage',
];

test('row 15: the committed scenario files load with no problem, and hold the scenarios of this story', () => {
  const { scenarios, problems } = loadScenarios(COMMITTED);
  assert.deepEqual(problems, []);
  for (const name of STORY_SCENARIOS) assert.ok(scenarios.byName.has(name), `the scenario ${name} is committed`);
  for (const key of ['chat', 'diagnosis', 'triage']) assert.equal(scenarios.byMockKey.get(key).name, key);
  for (const name of STORY_SCENARIOS) assert.equal(scenarios.byName.get(name).folder, 'A', `${name} is Lane A's`);
});

for (const [what, files, [file, rule]] of DEFECTS) {
  test(`row 15: ${what} is refused, naming the file and the rule`, () => {
    withTree(files, (dir) => {
      const { problems } = loadScenarios(dir);
      assert.ok(problems.some((p) => p.includes(file) && p.includes(rule)), `${JSON.stringify(problems)} should name ${file} and "${rule}"`);
    });
  });
}

test('row 15: valid files, dotfiles and the two folders load; every problem is listed at once', () => {
  withTree({ 'A/good.json': GOOD, 'A/.gitkeep': '', 'B/.gitkeep': '', 'B/guide.json': { name: 'guide', match: { prompt: 'A guide prompt.' }, replies: [reply({ text: 'x' })] }, '.hidden': 'x' }, (dir) => {
    const { scenarios, problems } = loadScenarios(dir);
    assert.deepEqual(problems, []);
    assert.deepEqual(scenarios.all.map((s) => s.name), ['good', 'guide']);
    assert.equal(scenarios.prompts.length, 1);
  });
  withTree({ 'A/one.json': { ...GOOD, name: 'two' }, 'A/three.json': { ...GOOD, name: 'three', replies: [] }, 'C/x.json': GOOD }, (dir) => {
    const { problems } = loadScenarios(dir);
    assert.equal(problems.length >= 3, true, JSON.stringify(problems));
    for (const file of ['A/one.json', 'A/three.json', 'C']) assert.ok(problems.some((p) => p.includes(file)), file);
  });
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-gone-'));
  try {
    assert.equal(loadScenarios(path.join(parent, 'no-such-folder')).problems.length, 1);
  } finally {
    fs.rmSync(parent, { recursive: true, force: true });
  }
});

test('row 15: the limits of the format are inclusive, and every API stop reason is accepted', () => {
  const limit = (name, reply0) => [`A/${name}.json`, { name, match: { marker: name }, replies: [reply0] }];
  const longName = 'a'.repeat(64);
  const files = Object.fromEntries([
    limit('status-low', { status: 100, text: 'x' }),
    limit('status-high', { status: 599, text: 'x' }),
    limit('delay-none', reply({ text: 'x', delayMs: 0 })),
    limit('delay-max', reply({ text: 'x', delayMs: 600000 })),
    limit(longName, reply({ text: 'x' })),
    limit('empty-text', reply({ text: '' })),
    limit('body-list', reply({ body: [1, 2] })),
    limit('tool-list', reply({ toolUse: [{ name: 'a' }, { name: 'b', input: { all: true } }] })),
    ...STOP_REASONS.map((r, i) => limit(`stop-${i}`, reply({ text: 'x', stopReason: r }))),
  ]);
  withTree(files, (dir) => {
    const { scenarios, problems } = loadScenarios(dir);
    assert.deepEqual(problems, []);
    assert.equal(scenarios.all.length, Object.keys(files).length);
  });
});

test('row 15: the server lists every problem on stderr and exits 1, and serves nothing', async () => {
  const dir = tree({ 'A/one.json': { ...GOOD, name: 'two' }, 'A/three.json': { ...GOOD, name: 'three', replies: [] }, 'C/x.json': GOOD });
  const s = spawnServer(SERVER, ['--port', '0', '--scenarios', dir]);
  try {
    const exit = await s.exitWithin();
    assert.equal(exit.code, 1);
    assert.equal(s.stdout(), '');
    for (const file of ['A/one.json', 'A/three.json', 'C']) assert.ok(s.stderr().includes(file), `${file} in ${s.stderr()}`);
  } finally {
    s.child.kill('SIGKILL');
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('row 15 (AC5): a valid file added under A is served by the unchanged mock', async () => {
  const dir = tree({});
  fs.cpSync(COMMITTED, dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'A', 'lane-a-new.json'), JSON.stringify({ name: 'lane-a-new', match: { marker: 'lane-a-new' }, replies: [reply({ text: 'Added by Lane A.' })] }, null, 2));
  const s = spawnServer(SERVER, ['--port', '0', '--scenarios', dir]);
  try {
    const listening = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    assert.equal(listening.scenarios, loadScenarios(COMMITTED).scenarios.all.length + 1);
    const res = await fetch(`http://127.0.0.1:${listening.port}/v1/messages`, {
      method: 'POST',
      headers: { 'x-api-key': 'k'.repeat(10) },
      body: JSON.stringify({ model: 'claude-haiku-5-5', max_tokens: 8000, messages: [{ role: 'user', content: '[[mock:lane-a-new]]' }] }),
    });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).content[0].text, 'Added by Lane A.');
  } finally {
    s.child.kill('SIGKILL');
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('row 15 (Story 10.3): telegram scenarios load in either folder, several may name one method, and none is selectable by a model request', () => {
  const files = {
    'A/updates-one.json': { name: 'updates-one', match: { telegram: 'getUpdates' }, replies: [{ status: 200, body: { ok: true, result: [] } }] },
    'B/updates-two.json': { name: 'updates-two', match: { telegram: 'getUpdates' }, replies: [{ status: 409, body: { ok: false, error_code: 409, description: 'Conflict' } }, TG_REPLY] },
    'A/send-limited.json': { name: 'send-limited', match: { telegram: 'sendMessage' }, replies: [{ status: 429, delayMs: 5, headers: { 'Retry-After': '3' }, body: { ok: false, error_code: 429, parameters: { retry_after: 3 } } }] },
    'A/good.json': GOOD,
  };
  for (const method of BOT_METHODS) files[`B/method-${method.toLowerCase()}.json`] = { name: `method-${method.toLowerCase()}`, match: { telegram: method }, replies: [TG_REPLY] };
  withTree(files, (dir) => {
    const { scenarios, problems } = loadScenarios(dir);
    assert.deepEqual(problems, []);
    assert.equal(scenarios.all.length, Object.keys(files).length);
    assert.equal(scenarios.all.filter((s) => s.match.telegram === 'getUpdates').length, 3, 'updates-one, updates-two and the per-method file all name getUpdates');
    assert.equal(scenarios.byMockKey.size + scenarios.prompts.length, 0, 'a telegram scenario is no mock key and no guide prompt');
    assert.equal(scenarios.byName.get('send-limited').match.telegram, 'sendMessage');
  });
  assert.deepEqual(BOT_METHODS, ['getMe', 'getUpdates', 'sendMessage', 'editMessageText', 'answerCallbackQuery']);
  assert.deepEqual(TELEGRAM_REPLY_FIELDS, ['status', 'headers', 'delayMs', 'body']);
  assert.deepEqual(checkTelegramReplies([TG_REPLY, { status: 200, body: {} }], 'replies'), []);
  assert.equal(checkTelegramReplies([], 'replies').length, 1);
  assert.equal(checkTelegramReplies([{ status: 200 }, { status: 200, body: {}, text: 'x' }], 'replies').length, 2);
});

test('row 15: the format constants and the marker grammar', () => {
  assert.deepEqual(MATCH_TYPES, ['marker', 'prompt', 'mockkey', 'telegram']);
  assert.deepEqual(REPLY_FIELDS, ['status', 'headers', 'delayMs', 'stopReason', 'text', 'toolUse', 'body']);
  assert.deepEqual(STOP_REASONS, ['end_turn', 'max_tokens', 'stop_sequence', 'tool_use', 'pause_turn', 'refusal']);
  for (const ok of ['a', 'refusal', 'long-retry-after', 'a1-b2']) assert.ok(NAME_PATTERN.test(ok), ok);
  for (const bad of ['', 'Refusal', 'a_b', '-a', 'a-', 'a--b', 'a b']) assert.equal(NAME_PATTERN.test(bad), false, bad);
  for (const ok of ['t-1', 'A_z-9', 'k'.repeat(64)]) assert.ok(KEY_PATTERN.test(ok), ok);
  for (const bad of ['', 'a b', 'a:b', 'k'.repeat(65)]) assert.equal(KEY_PATTERN.test(bad), false, bad);
  assert.deepEqual(findMarkers('x [[mock:refusal]] y'), [{ ok: true, name: 'refusal', key: null, label: 'refusal' }]);
  assert.deepEqual(findMarkers('[[mock:rate-limited:t-3_A]]'), [{ ok: true, name: 'rate-limited', key: 't-3_A', label: 'rate-limited:t-3_A' }]);
  assert.equal(findMarkers('[[mock:Refusal]]')[0].ok, false);
  assert.equal(findMarkers('[[mock:a:]]')[0].ok, false);
  assert.equal(findMarkers('[[mock:a:' + 'k'.repeat(65) + ']]')[0].ok, false);
  assert.equal(findMarkers('[[mock:a:' + 'k'.repeat(64) + ']]')[0].ok, true);
  assert.equal(findMarkers('[[mock:unterminated')[0].ok, false);
  assert.deepEqual(findMarkers('no marker here'), []);
  assert.equal(parseLabel('rate-limited:t-3').key, 't-3');
  assert.equal(parseLabel('[[mock:rate-limited]]'), null);
  assert.equal(parseLabel('Bad'), null);
});
