// Tests of the CI model mock's HTTP behaviour (Story 0.11, rows 1-14, 17 and 18 of the I/O matrix). Each test makes its own
// fixture tree (a copy of the committed scenarios plus its extras) and log folder in a fresh temporary folder, starts its own
// server on 127.0.0.1 with port 0 and removes everything afterwards, so no test depends on another. The key-like strings are
// built at run time. Row 18 and the unwritable log folder spawn server.mjs. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createMock } from '../mock.mjs';
import { loadScenarios } from '../scenarios.mjs';
import { spawnServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MOCK_DIR = path.join(HERE, '..');
const COMMITTED = path.join(MOCK_DIR, 'scenarios');
const SERVER = path.join(MOCK_DIR, 'server.mjs');
const MODEL = 'claude-haiku-5-5';
const KEY = 'sk-' + 'ant-' + 'k'.repeat(24);
const PLAIN_KEY = 'dummy-key-' + 'q'.repeat(12);

const user = (content) => ({ role: 'user', content });
const assistant = (content) => ({ role: 'assistant', content });
const request = (messages, extra = {}) => ({ model: MODEL, max_tokens: 8000, messages, ...extra });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const SLOW = { name: 'slow-fixture', match: { marker: 'slow-fixture' }, replies: [{ status: 200, delayMs: 300, text: 'Slow answer.' }] };
const GUIDE_ONE = { name: 'guide-one', match: { prompt: 'Guide prompt one: summarize the open incidents.' }, replies: [{ status: 200, text: 'Guide one answer.' }] };
const GUIDE_TWO = { name: 'guide-two', match: { prompt: 'Guide prompt two: check the status.' }, replies: [{ status: 200, text: 'Guide two answer.' }] };

const SHAPES = {
  name: 'shapes-fixture',
  match: { marker: 'shapes-fixture' },
  replies: [
    { status: 200, toolUse: [{ name: 'check_status', input: { all: true } }, { name: 'read_event_log' }] },
    { status: 200, body: { custom: 'raw' }, headers: { 'X-Extra': 'one' } },
    { status: 200, text: 'Typed.', headers: { 'Content-Type': 'text/x-test' } },
  ],
};
const STEPS = {
  name: 'steps-fixture',
  match: { marker: 'steps-fixture' },
  replies: [
    { status: 429, headers: { 'Retry-After': '1' }, text: 'Limited.' },
    { status: 200, toolUse: { name: 'check_status', input: {} } },
    { status: 200, text: 'Done.' },
  ],
};

function makeTree(extra = {}, omit = []) {
  const tree = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-tree-'));
  fs.cpSync(COMMITTED, tree, { recursive: true });
  for (const name of omit) fs.rmSync(path.join(tree, 'A', `${name}.json`));
  for (const [rel, data] of Object.entries(extra)) {
    fs.mkdirSync(path.dirname(path.join(tree, rel)), { recursive: true });
    fs.writeFileSync(path.join(tree, rel), JSON.stringify(data, null, 2));
  }
  return tree;
}

// withServer({files, omit}, fn): fn({base, mock, lines, logFile, readLog}) runs against a fresh in-process server.
async function withServer(opts, fn) {
  const tree = makeTree(opts.files, opts.omit);
  const logDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-log-'));
  const logFile = path.join(logDir, 'requests.jsonl');
  const { scenarios, problems } = loadScenarios(tree);
  assert.deepEqual(problems, []);
  const lines = [];
  const mock = createMock({ scenarios, logDir, out: { write: (s) => lines.push(s) } });
  const server = http.createServer((req, res) => {
    mock.handle(req, res);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const readLog = () => (fs.existsSync(logFile) ? fs.readFileSync(logFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
  try {
    await fn({ base, mock, lines, logFile, readLog });
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(tree, { recursive: true, force: true });
    fs.rmSync(logDir, { recursive: true, force: true });
  }
}

async function post(base, body, headers = {}, key = KEY) {
  const h = { 'content-type': 'application/json', ...(key === null ? {} : { 'x-api-key': key }), ...headers };
  const res = await fetch(`${base}/v1/messages`, { method: 'POST', headers: h, body: typeof body === 'string' ? body : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { status: res.status, headers: res.headers, text, json };
}

async function getJson(url, headers = {}) {
  const res = await fetch(url, { headers });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { status: res.status, headers: res.headers, text, json };
}

async function arm(base, marker, remaining) {
  const res = await fetch(`${base}/_mock/countdown`, { method: 'POST', body: JSON.stringify({ marker, remaining }) });
  return { status: res.status, json: await res.json() };
}

test('row 1: the model lookup returns the model object for any id', async () => {
  await withServer({}, async ({ base }) => {
    for (const id of [MODEL, 'any-other-model']) {
      const r = await getJson(`${base}/v1/models/${id}`, { 'x-api-key': KEY });
      assert.equal(r.status, 200);
      assert.equal(r.json.type, 'model');
      assert.equal(r.json.id, id);
      assert.equal(r.json.display_name, id);
      assert.equal(r.json.created_at, '2026-01-01T00:00:00Z');
      assert.equal(r.json.max_input_tokens, 1000000);
      assert.equal(r.json.max_tokens, 128000);
      assert.match(r.headers.get('request-id'), /^req_mock_[0-9]+$/);
    }
  });
});

test('row 2: no key, or an empty one, is a 401 on a /v1/ path and runs no scenario; /_mock/ takes no key', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const none = await post(base, request([user('hi')]), { 'x-ocutalon-mockkey': 'triage' }, null);
    assert.equal(none.status, 401);
    assert.equal(none.json.type, 'error');
    assert.equal(none.json.error.type, 'authentication_error');
    assert.equal(none.json.error.message, 'CI mock: the request has no x-api-key header');
    const empty = await post(base, request([user('hi')]), { 'x-ocutalon-mockkey': 'triage' }, '');
    assert.equal(empty.status, 401);
    const lookup = await getJson(`${base}/v1/models/${MODEL}`);
    assert.equal(lookup.status, 401);
    assert.equal(lookup.json.error.type, 'authentication_error');
    const lines = readLog();
    assert.equal(lines.length, 3);
    for (const line of lines) {
      assert.equal(line.keyLength, 0);
      assert.equal(line.status, 401);
      assert.equal(line.scenario, null);
    }
    assert.equal((await getJson(`${base}/_mock/health`)).status, 200);
    assert.equal((await fetch(`${base}/_mock/countdown?marker=rate-limited:t-1`)).status, 200);
  });
});

test('row 3: a sampling parameter, whatever its value, is a 400 that names every such field and NFR-1', async () => {
  await withServer({}, async ({ base, readLog }) => {
    for (const field of ['temperature', 'top_p', 'top_k']) {
      for (const value of [0, 0.7, null]) {
        const r = await post(base, request([user('hi')], { [field]: value }), { 'x-ocutalon-mockkey': 'triage' });
        assert.equal(r.status, 400, `${field}=${value}`);
        assert.equal(r.json.error.type, 'invalid_request_error');
        assert.ok(r.json.error.message.includes(field));
        assert.ok(r.json.error.message.includes('NFR-1'));
      }
    }
    const all = await post(base, request([user('hi')], { temperature: 0.5, top_p: 1, top_k: 3 }), { 'x-ocutalon-mockkey': 'triage' });
    for (const field of ['temperature', 'top_p', 'top_k']) assert.ok(all.json.error.message.includes(field));
    const last = readLog().pop();
    assert.equal(last.status, 400);
    assert.equal(last.rejected, 'sampling');
    const ok = await post(base, request([user('hi')]), { 'x-ocutalon-mockkey': 'triage' });
    assert.equal(ok.status, 200);
  });
});

test('row 4: max_tokens absent, not an integer or 3999 is a 400 naming the value and NFR-2; 4000, 8000 and 8192 pass', async () => {
  await withServer({}, async ({ base }) => {
    const mockkey = { 'x-ocutalon-mockkey': 'triage' };
    const body = (extra) => ({ model: MODEL, messages: [user('hi')], ...extra });
    const absent = await post(base, body({}), mockkey);
    assert.equal(absent.status, 400);
    assert.ok(absent.json.error.message.includes('NFR-2'));
    assert.equal(absent.json.error.type, 'invalid_request_error');
    for (const [value, shown] of [['8000', '"8000"'], [3999, '3999'], [4000.5, '4000.5'], [null, 'null']]) {
      const r = await post(base, body({ max_tokens: value }), mockkey);
      assert.equal(r.status, 400, String(value));
      assert.ok(r.json.error.message.includes(shown), r.json.error.message);
      assert.ok(r.json.error.message.includes('NFR-2'));
    }
    for (const value of [4000, 8000, 8192]) {
      assert.equal((await post(base, body({ max_tokens: value }), mockkey)).status, 200, String(value));
    }
  });
});

test('row 5: stream true, a body that is not JSON and messages that are not a non-empty list are each a 400 that says which', async () => {
  await withServer({}, async ({ base }) => {
    const mockkey = { 'x-ocutalon-mockkey': 'triage' };
    const stream = await post(base, request([user('hi')], { stream: true }), mockkey);
    assert.equal(stream.status, 400);
    assert.equal(stream.json.error.type, 'invalid_request_error');
    assert.ok(stream.json.error.message.includes('stream'));
    assert.equal((await post(base, request([user('hi')], { stream: false }), mockkey)).status, 200);
    const notJson = await post(base, '{not json', mockkey);
    assert.equal(notJson.status, 400);
    assert.ok(notJson.json.error.message.includes('not a JSON'));
    const array = await post(base, '[1,2]', mockkey);
    assert.equal(array.status, 400);
    for (const messages of [undefined, [], 'hi', {}]) {
      const r = await post(base, { model: MODEL, max_tokens: 8000, messages }, mockkey);
      assert.equal(r.status, 400, JSON.stringify(messages));
      assert.ok(r.json.error.message.includes('messages'));
    }
  });
});

test('row 6: the first marker of the newest user message with text picks the scenario; no other place does', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const triage = { 'x-ocutalon-mockkey': 'triage' };
    const hit = await post(base, request([user('please [[mock:refusal]] now')]));
    assert.equal(hit.status, 200);
    assert.equal(hit.json.stop_reason, 'refusal');
    const line = readLog().pop();
    assert.equal(line.scenario, 'refusal');
    assert.equal(line.selectedBy, 'marker');
    assert.equal(line.marker, 'refusal');

    const first = await post(base, request([user('[[mock:empty]] and then [[mock:refusal]]')]));
    assert.equal(first.json.stop_reason, 'end_turn');
    assert.deepEqual(first.json.content, []);

    const blocks = await post(base, request([user([{ type: 'text', text: 'a block [[mock:refusal]]' }])]));
    assert.equal(blocks.json.stop_reason, 'refusal');

    const keyed = await post(base, request([user('[[mock:refusal:t-1]]')]));
    assert.equal(keyed.json.stop_reason, 'refusal');
    const keyedLine = readLog().pop();
    assert.equal(keyedLine.scenario, 'refusal');
    assert.equal(keyedLine.marker, 'refusal:t-1');

    const places = {
      'an older user message': [user('[[mock:refusal]] earlier'), assistant('ok'), user('plain')],
      'a tool_result block': [user('plain'), assistant([{ type: 'tool_use', id: 'toolu_x', name: 'check_status', input: {} }]), user([{ type: 'tool_result', tool_use_id: 'toolu_x', content: '[[mock:refusal]]' }])],
      'an assistant message': [user('plain'), assistant('[[mock:refusal]]'), user('more')],
    };
    for (const [place, messages] of Object.entries(places)) {
      const r = await post(base, request(messages), triage);
      assert.equal(r.status, 200, place);
      assert.notEqual(r.json.stop_reason, 'refusal', place);
      const l = readLog().pop();
      assert.equal(l.scenario, 'triage', place);
      assert.equal(l.selectedBy, 'mockkey', place);
    }
    const inSystem = await post(base, request([user('plain')], { system: '[[mock:refusal]]' }), triage);
    assert.equal(readLog().pop().scenario, 'triage');
    assert.notEqual(inSystem.json.stop_reason, 'refusal');

    const unknown = await post(base, request([user('[[mock:no-such-scenario]]')]), triage);
    assert.equal(unknown.status, 500);
    assert.equal(unknown.json.error.type, 'api_error');
    assert.ok(unknown.json.error.message.includes('no-such-scenario'));
    const malformed = await post(base, request([user('[[mock:Bad Name]]')]), triage);
    assert.equal(malformed.status, 500);
    assert.ok(malformed.json.error.message.includes('Bad Name'));
    const mockkeyAsMarker = await post(base, request([user('[[mock:triage]]')]), triage);
    assert.equal(mockkeyAsMarker.status, 500);
  });
});

test('row 7: a guide prompt is its exact text inside the newest user message, after any preamble', async () => {
  await withServer({ files: { 'B/guide-one.json': GUIDE_ONE, 'B/guide-two.json': GUIDE_TWO } }, async ({ base, readLog }) => {
    const text = (p) => `Agent.Input preamble: item 7 from the Orders production.\n\n${p}\nTrailing text.`;
    const hit = await post(base, request([user(text(GUIDE_ONE.match.prompt))]));
    assert.equal(hit.status, 200);
    assert.equal(hit.json.content[0].text, 'Guide one answer.');
    const line = readLog().pop();
    assert.equal(line.scenario, 'guide-one');
    assert.equal(line.selectedBy, 'prompt');
    assert.equal(line.marker, null);

    const beatsMockKey = await post(base, request([user(text(GUIDE_TWO.match.prompt))]), { 'x-ocutalon-mockkey': 'triage' });
    assert.equal(beatsMockKey.json.content[0].text, 'Guide two answer.');
    const markerWins = await post(base, request([user(`${text(GUIDE_ONE.match.prompt)} [[mock:refusal]]`)]));
    assert.equal(markerWins.json.stop_reason, 'refusal');

    const oneCharacter = GUIDE_ONE.match.prompt.replace('incidents.', 'incidents,');
    const wrongCase = GUIDE_ONE.match.prompt.replace('Guide', 'guide');
    for (const near of [oneCharacter, wrongCase]) {
      const r = await post(base, request([user(text(near))]));
      assert.equal(r.status, 500, near);
      assert.equal(r.json.error.message, 'CI mock: no scenario: no marker, no guide prompt and no known mock key');
    }

    const both = await post(base, request([user(`${text(GUIDE_ONE.match.prompt)}\n${GUIDE_TWO.match.prompt}`)]));
    assert.equal(both.status, 500);
    assert.ok(both.json.error.message.includes('guide-one'));
    assert.ok(both.json.error.message.includes('guide-two'));
  });
});

test('row 8: the mock key header picks a default script when there is no marker and no prompt', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const r = await post(base, request([user('hello')]), { 'x-ocutalon-mockkey': 'triage' });
    assert.equal(r.status, 200);
    assert.equal(JSON.parse(r.json.content[0].text).outcome, 'digest');
    const line = readLog().pop();
    assert.equal(line.scenario, 'triage');
    assert.equal(line.selectedBy, 'mockkey');

    const marker = await post(base, request([user('[[mock:refusal]]')]), { 'x-ocutalon-mockkey': 'triage' });
    assert.equal(marker.json.stop_reason, 'refusal');

    const message = 'CI mock: no scenario: no marker, no guide prompt and no known mock key';
    const absent = await post(base, request([user('hello')]));
    assert.equal(absent.status, 500);
    assert.equal(absent.json.error.type, 'api_error');
    assert.equal(absent.json.error.message, message);
    const unknown = await post(base, request([user('hello')]), { 'x-ocutalon-mockkey': 'nobody' });
    assert.equal(unknown.status, 500);
    assert.equal(unknown.json.error.message, message);
    const wrongName = await post(base, request([user('hello')]), { 'x-mock-key': 'triage' });
    assert.equal(wrongName.status, 500);
  });
});

test('row 9: the turn step counts the assistant messages after the newest user text', async () => {
  await withServer({}, async ({ base }) => {
    const chat = { 'x-ocutalon-mockkey': 'chat' };
    const first = await post(base, request([user('what runs?')]), chat);
    assert.equal(first.status, 200);
    assert.equal(first.json.stop_reason, 'tool_use');
    assert.equal(first.json.content.length, 1);
    assert.deepEqual(first.json.content[0], { type: 'tool_use', id: 'toolu_mock_1_1', name: 'list_productions', input: {} });
    const use = assistant([{ type: 'tool_use', id: 'toolu_mock_1_1', name: 'list_productions', input: {} }]);
    const result = user([{ type: 'tool_result', tool_use_id: 'toolu_mock_1_1', content: '[]' }]);
    const second = await post(base, request([user('what runs?'), use, result]), chat);
    assert.equal(second.json.stop_reason, 'end_turn');
    assert.deepEqual(second.json.content, [{ type: 'text', text: 'The CI mock looked at the productions.' }]);
    const third = await post(base, request([user('what runs?'), use, result, assistant('done'), user([{ type: 'tool_result', tool_use_id: 'x', content: 'y' }])]), chat);
    assert.deepEqual(third.json.content, [{ type: 'text', text: 'The CI mock looked at the productions.' }]);
    assert.equal(third.json.id, 'msg_mock_3');
    assert.equal(third.json.model, MODEL);
    assert.equal(third.headers.get('request-id'), 'req_mock_3');
    assert.ok(third.json.usage.input_tokens > 0);
    assert.equal(third.json.usage.cache_read_input_tokens, 0);
  });
});

test('row 9: a toolUse list gives one block per item, a body reply is sent as written, and a reply header replaces a default one', async () => {
  await withServer({ files: { 'A/shapes-fixture.json': SHAPES } }, async ({ base }) => {
    const marked = user('[[mock:shapes-fixture]]');
    const use = assistant([{ type: 'tool_use', id: 'toolu_s', name: 'check_status', input: {} }]);
    const result = user([{ type: 'tool_result', tool_use_id: 'toolu_s', content: 'ok' }]);
    const first = await post(base, request([marked]));
    assert.equal(first.status, 200);
    assert.equal(first.json.stop_reason, 'tool_use');
    assert.deepEqual(first.json.content, [
      { type: 'tool_use', id: 'toolu_mock_1_1', name: 'check_status', input: { all: true } },
      { type: 'tool_use', id: 'toolu_mock_1_2', name: 'read_event_log', input: {} },
    ]);
    const second = await post(base, request([marked, use, result]));
    assert.deepEqual(second.json, { custom: 'raw' });
    assert.equal(second.headers.get('x-extra'), 'one');
    assert.equal(second.headers.get('content-type'), 'application/json');
    assert.equal(second.headers.get('request-id'), 'req_mock_2');
    const third = await post(base, request([marked, use, result, assistant('more'), result]));
    assert.equal(third.json.content[0].text, 'Typed.');
    assert.equal(third.headers.get('content-type'), 'text/x-test');
  });
});

test('row 10: a summarizer request reads only the last summary-* marker of its transcript', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const prompt = 'OCUTALON-COMPACTION-V1 You are a compression engine for an IRIS operations assistant.';
    const transcript = (extra) => user([{ type: 'text', text: `Transcript: [[mock:refusal]] the user asked about it.${extra}` }]);
    const triage = { 'x-ocutalon-mockkey': 'triage' };

    const variant = await post(base, request([transcript(' [[mock:summary-off-schema:t-2]]')], { system: prompt }), triage);
    assert.equal(variant.status, 200);
    assert.equal(variant.json.stop_reason, 'end_turn');
    assert.equal(variant.json.content[0].text, 'The conversation was about the Orders production.');
    const line = readLog().pop();
    assert.equal(line.scenario, 'summary-off-schema');
    assert.equal(line.marker, 'summary-off-schema:t-2');

    const blocks = [{ type: 'text', text: prompt, cache_control: { type: 'ephemeral' } }];
    const plain = await post(base, request([transcript('')], { system: blocks }), triage);
    assert.equal(plain.status, 200);
    const summary = JSON.parse(plain.json.content[0].text);
    assert.deepEqual(Object.keys(summary), ['user_goals', 'constraints', 'decisions', 'facts_learned', 'tool_actions', 'open_questions', 'next_steps']);
    assert.equal(readLog().pop().scenario, 'summary');

    const lastWins = await post(base, request([transcript(' [[mock:summary-off-schema]] [[mock:summary-no-such]]')], { system: prompt }));
    assert.equal(lastWins.status, 500);
    assert.ok(lastWins.json.error.message.includes('summary-no-such'));

    const normal = await post(base, request([user('hi [[mock:summary-off-schema]]')]), triage);
    assert.equal(readLog().pop().scenario, 'triage');
    assert.equal(normal.status, 200);
    const notFirst = await post(base, request([user('hi')], { system: `Not the prefix. ${prompt}` }), triage);
    assert.equal(readLog().pop().scenario, 'triage');
    assert.equal(notFirst.status, 200);
  });
  await withServer({ omit: ['summary'] }, async ({ base }) => {
    const r = await post(base, request([user('Transcript')], { system: 'OCUTALON-COMPACTION-V1 compress' }), { 'x-ocutalon-mockkey': 'triage' });
    assert.equal(r.status, 500);
    assert.equal(r.json.error.type, 'api_error');
  });
});

test('row 11: a countdown arms the first reply for a number of requests, per full marker', async () => {
  await withServer({}, async ({ base, mock, readLog }) => {
    const marker = 'rate-limited:t-3';
    const armed = await arm(base, marker, 2);
    assert.equal(armed.status, 200);
    assert.deepEqual(armed.json, { marker, remaining: 2 });
    const ask = () => post(base, request([user(`go [[mock:${marker}]]`)]));
    const a = await ask();
    assert.equal(a.status, 429);
    assert.equal(a.headers.get('retry-after'), '1');
    assert.equal(a.json.error.type, 'rate_limit_error');
    assert.equal((await ask()).status, 429);
    const c = await ask();
    assert.equal(c.status, 200);
    assert.equal(c.json.content[0].text, 'Answered after the rate limit.');
    assert.deepEqual((await getJson(`${base}/_mock/countdown?marker=${marker}`)).json, { marker, remaining: 0 });
    assert.deepEqual(readLog().map((l) => l.countdown), [1, 0, 0]);
    assert.equal((await ask()).status, 200);

    for (let i = 0; i < 3; i++) {
      assert.equal((await post(base, request([user('go [[mock:rate-limited:t-4]]')]))).status, 429, 'unarmed');
    }
    assert.deepEqual((await getJson(`${base}/_mock/countdown?marker=rate-limited:t-4`)).json, { marker: 'rate-limited:t-4', remaining: null });

    await arm(base, 'rate-limited:t-5', 3);
    await arm(base, 'rate-limited:t-6', 1);
    assert.equal((await post(base, request([user('[[mock:rate-limited:t-6]]')]))).status, 429);
    assert.equal(mock.countdowns.get('rate-limited:t-5'), 3);
    assert.equal(mock.countdowns.get('rate-limited:t-6'), 0);
    assert.deepEqual((await arm(base, 'rate-limited:t-5', null)).json, { marker: 'rate-limited:t-5', remaining: null });
    assert.equal(mock.countdowns.has('rate-limited:t-5'), false);
    assert.equal(mock.countdowns.get('rate-limited:t-6'), 0);

    assert.equal((await arm(base, 'no-such-scenario:t-1', 1)).status, 400);
    assert.equal((await arm(base, 'triage:t-1', 1)).status, 400);
    assert.equal((await arm(base, 'Rate Limited', 1)).status, 400);
    assert.equal((await arm(base, 'rate-limited:' + 'x'.repeat(65), 1)).status, 400);
    for (const remaining of [-1, 1001, 1.5, '2', true, undefined]) {
      assert.equal((await arm(base, 'rate-limited:t-7', remaining)).status, 400, String(remaining));
    }
    assert.equal((await arm(base, 'rate-limited:t-7', 1000)).status, 200);
    assert.equal((await arm(base, 'rate-limited:t-7', 0)).status, 200);
    assert.equal((await fetch(`${base}/_mock/countdown`)).status, 400);
  });
});

test('row 11: an armed countdown answers the first reply while it counts, then the reply of the turn step plus one', async () => {
  await withServer({ files: { 'A/steps-fixture.json': STEPS } }, async ({ base }) => {
    const label = 'steps-fixture:t-8';
    const marked = user(`[[mock:${label}]]`);
    const use = assistant([{ type: 'tool_use', id: 'toolu_s', name: 'check_status', input: {} }]);
    const result = user([{ type: 'tool_result', tool_use_id: 'toolu_s', content: 'ok' }]);
    const atStep = (k) => {
      const messages = [marked];
      for (let i = 0; i < k; i++) messages.push(use, result);
      return post(base, request(messages));
    };
    assert.equal((await atStep(0)).status, 429, 'unarmed, step 0: the first reply');
    assert.equal((await atStep(1)).json.stop_reason, 'tool_use', 'unarmed, step 1: the second reply');
    assert.equal((await atStep(2)).json.content[0].text, 'Done.', 'unarmed, step 2: the third reply');
    assert.equal((await atStep(5)).json.content[0].text, 'Done.', 'unarmed, past the last reply: the last reply again');

    await arm(base, label, 1);
    assert.equal((await atStep(0)).status, 429, 'armed with 1: the first reply');
    assert.equal((await atStep(0)).json.stop_reason, 'tool_use', 'counted out, step 0: the second reply');
    assert.equal((await atStep(1)).json.content[0].text, 'Done.', 'counted out, step 1: the third reply');
    assert.equal((await atStep(2)).json.content[0].text, 'Done.', 'counted out, past the last reply: the last reply again');
  });
});

test('row 12: a reply with delayMs waits on a timer while other requests are answered; a hung-up client gets no write', async () => {
  await withServer({ files: { 'A/slow-fixture.json': SLOW } }, async ({ base }) => {
    const started = Date.now();
    const slow = post(base, request([user('[[mock:slow-fixture]]')])).then((r) => ({ r, at: Date.now() }));
    await sleep(30);
    const fast = await post(base, request([user('[[mock:refusal]]')]));
    const fastAt = Date.now();
    assert.equal(fast.status, 200);
    const done = await slow;
    assert.equal(done.r.json.content[0].text, 'Slow answer.');
    assert.ok(done.at - started >= 290, `answered after ${done.at - started} ms`);
    assert.ok(fastAt < done.at, 'the second request was answered while the first waited');
  });

  const tree = makeTree({ 'A/slow-fixture.json': SLOW });
  try {
    const { scenarios } = loadScenarios(tree);
    for (const hangUp of [true, false]) {
      const lines = [];
      const mock = createMock({ scenarios, logDir: null, out: { write: (s) => lines.push(s) } });
      const req = Readable.from([JSON.stringify(request([user('[[mock:slow-fixture]]')]))]);
      Object.assign(req, { method: 'POST', url: '/v1/messages', headers: { 'x-api-key': KEY } });
      const res = Object.assign(new EventEmitter(), {
        destroyed: false,
        writableEnded: false,
        calls: [],
        writeHead() {
          this.calls.push('writeHead');
        },
        end() {
          this.calls.push('end');
          this.writableEnded = true;
        },
      });
      await mock.handle(req, res);
      assert.equal(lines.length, 1, 'the log line is written before the delay');
      if (hangUp) {
        res.destroyed = true;
        res.emit('close');
      }
      await sleep(450);
      if (hangUp) {
        assert.deepEqual(res.calls, [], 'no write to a hung-up client');
        assert.equal(lines.length, 1, 'no error line');
      } else {
        assert.deepEqual(res.calls, ['writeHead', 'end']);
      }
    }
  } finally {
    fs.rmSync(tree, { recursive: true, force: true });
  }
});

test('row 13: the error scenarios answer the API error shapes', async () => {
  await withServer({}, async ({ base }) => {
    const expected = [
      ['provider-error', 500, 'api_error', 'CI mock: the provider failed.', null],
      ['invalid-input', 400, 'invalid_request_error', 'CI mock: messages: the stored conversation is not valid input.', null],
      ['overloaded', 529, 'overloaded_error', 'CI mock: overloaded.', '1'],
    ];
    for (const [name, status, type, message, retryAfter] of expected) {
      const r = await post(base, request([user(`[[mock:${name}]]`)]));
      assert.equal(r.status, status, name);
      assert.deepEqual(r.json, { type: 'error', error: { type, message } }, name);
      assert.equal(r.headers.get('retry-after'), retryAfter, name);
      assert.equal(r.headers.get('content-type'), 'application/json');
    }
    const other = await post(base, request([user('[[mock:max-tokens]]')]));
    assert.equal(other.json.stop_reason, 'max_tokens');
    const rejected = await post(base, request([user('[[mock:invalid-reply]]')]));
    assert.equal(rejected.json.content[0].text, '{"outcome":"maybe","reasons":"none","confidence":2}');
    const toolLoop = await post(base, request([user('[[mock:tool-loop]]'), assistant([{ type: 'tool_use', id: 'a', name: 'b', input: {} }]), user([{ type: 'tool_result', tool_use_id: 'a', content: 'c' }])]));
    assert.equal(toolLoop.json.stop_reason, 'tool_use');
  });
});

test('row 14: one stdout line and one file line per request, written before the reply, with no header value and no key', async () => {
  const keyText = 'sk-' + 'ant-' + 'x'.repeat(20);
  const botText = '1234567890' + ':' + 'A'.repeat(35);
  const secretValue = 'secret-header-value-1234';
  await withServer({ files: { 'A/slow-fixture.json': SLOW } }, async ({ base, lines, readLog, logFile }) => {
    const system = [{ type: 'text', text: 'You are the triage agent.', cache_control: { type: 'ephemeral' } }];
    const tools = [{ name: 'check_status', description: 'd', input_schema: { type: 'object' }, cache_control: { type: 'ephemeral' } }, { name: 'read_event_log', description: 'd', input_schema: { type: 'object' } }];
    const body = request([user(`here is a key ${keyText} and a token ${botText}`)], { system, tools, output_config: { effort: 'low' } });
    const r = await post(base, body, { 'x-ocutalon-mockkey': 'triage', authorization: `Bearer ${secretValue}`, 'X-Other-Header': secretValue }, PLAIN_KEY);
    assert.equal(r.status, 200);
    assert.equal(lines.length, 1);
    const stdoutLine = JSON.parse(lines[0]);
    const fileLines = readLog();
    assert.equal(fileLines.length, 1);
    const { request: logged, ...fileFields } = fileLines[0];
    assert.deepEqual(fileFields, stdoutLine);
    assert.equal(Object.hasOwn(stdoutLine, 'request'), false);
    assert.deepEqual(Object.keys(stdoutLine), ['ts', 'id', 'method', 'path', 'status', 'scenario', 'selectedBy', 'marker', 'step', 'countdown', 'headerNames', 'keyLength', 'rejected', 'model', 'maxTokens']);
    assert.equal(stdoutLine.id, 1);
    assert.equal(stdoutLine.method, 'POST');
    assert.equal(stdoutLine.path, '/v1/messages');
    assert.equal(stdoutLine.status, 200);
    assert.equal(stdoutLine.scenario, 'triage');
    assert.equal(stdoutLine.selectedBy, 'mockkey');
    assert.equal(stdoutLine.step, 0);
    assert.equal(stdoutLine.keyLength, PLAIN_KEY.length);
    assert.equal(stdoutLine.rejected, null);
    assert.equal(stdoutLine.model, MODEL);
    assert.equal(stdoutLine.maxTokens, 8000);
    for (const name of ['x-api-key', 'authorization', 'x-other-header', 'x-ocutalon-mockkey']) assert.ok(stdoutLine.headerNames.includes(name), name);
    assert.ok(stdoutLine.headerNames.every((n) => n === n.toLowerCase()));

    assert.deepEqual(logged.system, { chars: 'You are the triage agent.'.length, cacheControl: { type: 'ephemeral' } });
    assert.deepEqual(logged.tools, [{ name: 'check_status', cacheControl: { type: 'ephemeral' } }, { name: 'read_event_log', cacheControl: null }]);
    assert.deepEqual(logged.output_config, { effort: 'low' });
    assert.equal(logged.max_tokens, 8000);
    assert.equal(logged.messages[0].content, 'here is a key [redacted] and a token [redacted]');

    const everything = `${lines.join('')}${fs.readFileSync(logFile, 'utf8')}`;
    for (const secret of [PLAIN_KEY, keyText, botText, secretValue, 'Bearer']) assert.equal(everything.includes(secret), false, secret);
    const keyLike = await post(base, request([user('hello')]), { 'x-ocutalon-mockkey': 'triage' }, KEY);
    assert.equal(keyLike.status, 200);
    const keyLikeLine = readLog()[1];
    assert.equal(keyLikeLine.keyLength, KEY.length);
    assert.equal(JSON.stringify(keyLikeLine).includes('[redacted]'), false, 'a logged key-like x-api-key value would show as [redacted]');
    assert.equal(readLog().length, 2);
    assert.equal((await fetch(`${base}/_mock/health`)).status, 200);
    assert.equal(readLog().length, 2, '/_mock/ requests are not logged');

    const pending = post(base, request([user('[[mock:slow-fixture]]')]));
    await sleep(100);
    assert.equal(readLog().length, 3, 'the file line is there while the reply waits');
    assert.equal(lines.length, 3, 'and so is the stdout line');
    assert.equal(readLog()[2].scenario, 'slow-fixture');
    await pending;

    const samples = [
      keyText,
      botText,
      'gh' + 'p_' + 'a'.repeat(24),
      'github_' + 'pat_' + 'a'.repeat(24),
      'dop_' + 'v1_' + 'a'.repeat(24),
      'AK' + 'IA' + 'A'.repeat(16),
      '-----' + 'BEGIN RSA ' + 'PRIVATE KEY',
    ];
    const each = await post(base, request([user(`samples: ${samples.join(' | ')}`)]), { 'x-ocutalon-mockkey': 'triage' }, PLAIN_KEY);
    assert.equal(each.status, 200);
    const sampleLine = readLog().pop();
    assert.equal(sampleLine.request.messages[0].content, `samples: ${samples.map(() => '[redacted]').join(' | ')}`, 'each key-like alternative is redacted');
  });

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-blocked-'));
  try {
    const blocker = path.join(dir, 'a-file');
    fs.writeFileSync(blocker, 'x');
    const s = spawnServer(SERVER, ['--port', '0', '--log-dir', path.join(blocker, 'logs')]);
    try {
      const exit = await s.exitWithin();
      assert.equal(exit.code, 1);
      assert.match(s.stderr(), /log folder/);
      assert.equal(s.stdout().includes('listening'), false);
    } finally {
      s.child.kill('SIGKILL');
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('row 17: other paths are 404s, the Bot API one names Story 10.3, and health answers', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const wrong = await fetch(`${base}/messages`, { method: 'POST', headers: { 'x-api-key': KEY }, body: '{}' });
    const wrongBody = await wrong.json();
    assert.equal(wrong.status, 404);
    assert.equal(wrongBody.error.type, 'not_found_error');
    assert.ok(wrongBody.error.message.includes('/messages'));
    const list = await getJson(`${base}/v1/models`, { 'x-api-key': KEY });
    assert.equal(list.status, 404);
    assert.equal(list.json.error.type, 'not_found_error');
    assert.ok(list.json.error.message.includes('/v1/models'));
    const bot = await getJson(`${base}/bot${'1234567890'}:${'A'.repeat(35)}/getMe`);
    assert.equal(bot.status, 404);
    assert.equal(bot.json.error.type, 'not_found_error');
    assert.ok(bot.json.error.message.includes('Story 10.3'));
    assert.equal(bot.text.includes('A'.repeat(35)), false);
    const getMessages = await getJson(`${base}/v1/messages`, { 'x-api-key': KEY });
    assert.equal(getMessages.status, 404);
    assert.equal(readLog().some((l) => JSON.stringify(l).includes('A'.repeat(35))), false);
    const health = await getJson(`${base}/_mock/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(health.json, { ok: true, scenarios: loadScenarios(COMMITTED).scenarios.all.length });
  });
});

test('row 18: SIGTERM ends server.mjs with status 0 within a second, with a reply held open', async () => {
  const tree = makeTree({ 'A/held-fixture.json': { name: 'held-fixture', match: { marker: 'held-fixture' }, replies: [{ status: 200, delayMs: 60000, text: 'never' }] } });
  const s = spawnServer(SERVER, ['--port', '0', '--scenarios', tree]);
  try {
    const listening = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    assert.equal(listening.event, 'listening');
    assert.ok(listening.port > 0);
    assert.equal(listening.scenarios, loadScenarios(COMMITTED).scenarios.all.length + 1);
    const controller = new AbortController();
    const held = fetch(`http://127.0.0.1:${listening.port}/v1/messages`, {
      method: 'POST',
      headers: { 'x-api-key': KEY },
      body: JSON.stringify(request([user('[[mock:held-fixture]]')])),
      signal: controller.signal,
    }).catch(() => null);
    await s.waitFor((l) => l.includes('held-fixture') && !l.includes('listening'));
    const sent = Date.now();
    s.child.kill('SIGTERM');
    const exit = await s.exitWithin();
    assert.equal(exit.code, 0);
    assert.ok(exit.at - sent < 1000, `exited after ${exit.at - sent} ms`);
    controller.abort();
    await held;
  } finally {
    s.child.kill('SIGKILL');
    fs.rmSync(tree, { recursive: true, force: true });
  }
});
