// Tests of the CI model mock's HTTP behaviour (Story 0.11, rows 1-14, 17 and 18 of the I/O matrix). Each test makes its own
// fixture tree (a copy of the committed scenarios plus its extras) and log folder in a fresh temporary folder, starts its own
// server on 127.0.0.1 with port 0 and removes everything afterwards, so no test depends on another. The key-like strings are
// built at run time. Row 18 and the unwritable log folder spawn server.mjs. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createMock, redact } from '../mock.mjs';
import { loadScenarios } from '../scenarios.mjs';
import { makeTree, spawnServer, withServer } from './helpers.mjs';

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

// waitUntil(predicate, what, ms): resolves once predicate() holds, polling every 5 ms; rejects naming what after ms.
async function waitUntil(predicate, what, ms = 2000) {
  const until = Date.now() + ms;
  while (!predicate()) {
    if (Date.now() > until) throw new Error(`${what}: not seen within ${ms} ms`);
    await sleep(5);
  }
}

// AD-5: the bridge timer stays at or under 110 seconds. AD-8: the retry block's back-off cap is 2000 ms.
const BRIDGE_TIMER_MAX_MS = 110000;
const BACKOFF_CAP_MS = 2000;

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
    { status: 403, body: 'daily cost cap reached', headers: { 'Content-Type': 'text/plain' } },
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

// fakeCall(body): a request and a response that record their writes, for a test that drives handle() under its own timers.
function fakeCall(body) {
  const req = Readable.from([JSON.stringify(body)]);
  Object.assign(req, { method: 'POST', url: '/v1/messages', headers: { 'x-api-key': KEY } });
  const res = Object.assign(new EventEmitter(), {
    destroyed: false,
    writableEnded: false,
    calls: [],
    payload: null,
    writeHead() {
      this.calls.push('writeHead');
    },
    end(text) {
      this.payload = text;
      this.calls.push('end');
      this.writableEnded = true;
    },
  });
  return { req, res };
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
    const fourth = await post(base, request([marked, use, result, assistant('more'), result, assistant('more'), result]));
    assert.equal(fourth.status, 403);
    assert.equal(fourth.text, 'daily cost cap reached');
    assert.equal(fourth.headers.get('content-type'), 'text/plain');
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
  await withServer({ files: { 'A/slow-fixture.json': SLOW } }, async ({ base, lines }) => {
    const started = Date.now();
    const slow = post(base, request([user('[[mock:slow-fixture]]')])).then((r) => ({ r, at: Date.now() }));
    await waitUntil(() => lines.some((l) => JSON.parse(l).scenario === 'slow-fixture'), 'the log line of the held request');
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
      const { req, res } = fakeCall(request([user('[[mock:slow-fixture]]')]));
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
    const plain = await post(base, request([user('[[mock:daily-cap-text]]')]));
    assert.equal(plain.status, 403);
    assert.equal(plain.text, 'daily cost cap reached');
    assert.equal(plain.headers.get('content-type'), 'text/plain');
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
    assert.deepEqual(Object.keys(stdoutLine), ['ts', 'id', 'method', 'path', 'status', 'scenario', 'selectedBy', 'marker', 'step', 'countdown', 'headerNames', 'keyLength', 'tokenLength', 'rejected', 'model', 'maxTokens']);
    assert.equal(stdoutLine.id, 1);
    assert.equal(stdoutLine.method, 'POST');
    assert.equal(stdoutLine.path, '/v1/messages');
    assert.equal(stdoutLine.status, 200);
    assert.equal(stdoutLine.scenario, 'triage');
    assert.equal(stdoutLine.selectedBy, 'mockkey');
    assert.equal(stdoutLine.step, 0);
    assert.equal(stdoutLine.keyLength, PLAIN_KEY.length);
    assert.equal(stdoutLine.tokenLength, null, 'a model call has no Bot API token');
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

    let answered = false;
    const pending = post(base, request([user('[[mock:slow-fixture]]')])).then(() => {
      answered = true;
    });
    await waitUntil(() => readLog().length === 3, 'the file line of the held request, within its 300 ms hold', 250);
    assert.equal(answered, false, 'the file line is there while the reply waits');
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

test('row 17: other paths are 404s, a Bot API path is served without the model key rule, and health answers', async () => {
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
    assert.equal(bot.status, 200, 'the Bot API is served, with no x-api-key header');
    assert.equal(bot.json.ok, true);
    assert.equal(bot.json.result.username, 'ocutalon_ci_bot');
    assert.equal(bot.text.includes('A'.repeat(35)), false);
    const notBot = await getJson(`${base}/botnotapi`);
    assert.equal(notBot.status, 404, 'a path that is no /bot<token>/<method> is the generic 404');
    assert.equal(notBot.json.error.type, 'not_found_error');
    assert.equal(notBot.json.error.message.includes('Story 10.3'), false);
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

test('rows 2 to 5: the checks run in the stated order, and a rejected request runs no scenario, spends no countdown and is logged with the marker it carries', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const mockkey = { 'x-ocutalon-mockkey': 'triage' };
    const label = 'rate-limited:t-order';
    const marked = user(`go [[mock:${label}]]`);
    await arm(base, label, 2);
    const rejected = async (body, key = KEY) => {
      const r = await post(base, body, mockkey, key);
      return { r, line: readLog().pop() };
    };
    for (const body of ['{not json', request([marked], { stream: true, temperature: 0.5, max_tokens: 10 })]) {
      const { r, line } = await rejected(body, null);
      assert.equal(r.status, 401, 'the key is checked before the body');
      assert.equal(line.rejected, 'no-key');
      assert.equal(line.marker, typeof body === 'string' ? null : label, 'a refused request is logged with the marker it carries');
    }
    const steps = [
      ['not-json', '{not json', null],
      ['stream', request([marked], { stream: true, messages: [], temperature: 0.5, max_tokens: 10 }), null],
      ['messages', request([], { temperature: 0.5, max_tokens: 10 }), null],
      ['sampling', request([marked], { temperature: 0.5, max_tokens: 10 }), label],
      ['max_tokens', request([marked], { max_tokens: 10 }), label],
    ];
    for (const [reason, body, carried] of steps) {
      const { r, line } = await rejected(body);
      assert.equal(r.status, 400, reason);
      assert.equal(line.rejected, reason, `a body that breaks this rule and every later one is rejected for ${reason}`);
      assert.equal(line.scenario, null, reason);
      assert.equal(line.countdown, null, reason);
      assert.equal(line.marker, carried, `${reason}: the marker the request carries`);
    }
    const unknown = await post(base, request([user('go [[mock:no-such-scenario:t-order]]')]), mockkey);
    assert.equal(unknown.status, 500);
    assert.equal(readLog().pop().marker, 'no-such-scenario:t-order', 'a marker that names no scenario is logged too');
    const remaining = async () => (await getJson(`${base}/_mock/countdown?marker=${label}`)).json;
    assert.deepEqual(await remaining(), { marker: label, remaining: 2 }, 'no rejection spent the countdown');
    assert.equal((await post(base, request([marked]))).status, 429);
    assert.deepEqual(await remaining(), { marker: label, remaining: 1 });
  });
});

test('rows 3 and 4: a summarizer request is held to the same rules, and needs no mock key', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const system = 'OCUTALON-COMPACTION-V1 compress the transcript';
    const ask = (extra) => post(base, request([user('Transcript of the earlier turns.')], { system, ...extra }));
    const sampled = await ask({ temperature: 0 });
    assert.equal(sampled.status, 400);
    assert.ok(sampled.json.error.message.includes('temperature') && sampled.json.error.message.includes('NFR-1'));
    assert.equal(readLog().pop().rejected, 'sampling');
    const low = await ask({ max_tokens: 3999 });
    assert.equal(low.status, 400);
    assert.ok(low.json.error.message.includes('NFR-2'));
    assert.equal(readLog().pop().rejected, 'max_tokens');
    for (const cap of [4000, 8192]) {
      const r = await ask({ max_tokens: cap });
      assert.equal(r.status, 200, String(cap));
      const line = readLog().pop();
      assert.equal(line.scenario, 'summary', String(cap));
      assert.equal(line.selectedBy, 'summarizer', String(cap));
      assert.equal(line.maxTokens, cap);
    }
  });
});

test('row 6: the first marker wins whatever its key; summary-* markers are skipped for the next marker, a guide prompt or the mock key; a first marker that fails ends the selection', async () => {
  await withServer({ files: { 'B/guide-one.json': GUIDE_ONE } }, async ({ base, readLog }) => {
    const triage = { 'x-ocutalon-mockkey': 'triage' };
    const last = () => readLog().pop();

    const keyed = await post(base, request([user('[[mock:refusal:t-1]] and [[mock:empty:t-2]] and [[mock:provider-error]]')]));
    assert.equal(keyed.json.stop_reason, 'refusal');
    assert.equal(last().marker, 'refusal:t-1');

    const skipped = await post(base, request([user('[[mock:summary-off-schema:t-3]] then [[mock:refusal]]')]), triage);
    assert.equal(skipped.json.stop_reason, 'refusal', 'a summary-* marker does not end the search');
    assert.equal(last().marker, 'refusal');
    assert.equal(last().selectedBy, 'marker');

    await post(base, request([user(`[[mock:summary-off-schema]] ${GUIDE_ONE.match.prompt}`)]), triage);
    assert.equal(last().scenario, 'guide-one');
    assert.equal(last().selectedBy, 'prompt');

    const unnamed = await post(base, request([user('[[mock:summary-off-schema]] [[mock:summary-no-such]]')]), triage);
    assert.equal(unnamed.status, 200, 'a summary-* marker is skipped even when it names no scenario');
    assert.equal(last().scenario, 'triage');
    assert.equal(last().selectedBy, 'mockkey');

    for (const first of ['[[mock:Bad Name]]', '[[mock:no-such-scenario]]', '[[mock:triage]]']) {
      const r = await post(base, request([user(`${first} [[mock:refusal]]`)]), triage);
      assert.equal(r.status, 500, first);
      assert.notEqual(last().rejected, null, first);
    }
    const laterBad = await post(base, request([user('[[mock:refusal]] [[mock:Bad Name]]')]), triage);
    assert.equal(laterBad.json.stop_reason, 'refusal', 'a marker after the winning one is never read');
  });
});

test('row 7: a guide prompt is read from the newest user message with text, a tool step included, and from no other place', async () => {
  await withServer({ files: { 'B/guide-one.json': GUIDE_ONE } }, async ({ base, readLog }) => {
    const prompt = GUIDE_ONE.match.prompt;
    const triage = { 'x-ocutalon-mockkey': 'triage' };
    const use = assistant([{ type: 'tool_use', id: 'toolu_g', name: 'check_status', input: {} }]);
    const result = (text) => user([{ type: 'tool_result', tool_use_id: 'toolu_g', content: text }]);
    const places = {
      'an older user message': request([user(prompt), assistant('ok'), user('something else')]),
      'the system text': request([user('plain')], { system: prompt }),
      'an assistant message': request([user('plain'), assistant(prompt), user('more')]),
      'a tool result': request([user('plain'), use, result(prompt)]),
    };
    for (const [place, body] of Object.entries(places)) {
      const r = await post(base, body, triage);
      assert.equal(r.status, 200, place);
      assert.equal(readLog().pop().scenario, 'triage', place);
    }
    const step = await post(base, request([user(`Agent.Input preamble.\n\n${prompt}`), use, result('ok')]));
    assert.equal(step.json.content[0].text, 'Guide one answer.');
    const line = readLog().pop();
    assert.equal(line.scenario, 'guide-one');
    assert.equal(line.selectedBy, 'prompt');
    assert.equal(line.step, 1, 'the step counts the assistant messages after the newest user text');
    const blocks = await post(base, request([user([{ type: 'text', text: 'Agent.Input preamble.' }, { type: 'text', text: prompt }])]));
    assert.equal(blocks.json.content[0].text, 'Guide one answer.');
  });
});

test('row 10: the summarizer prefix is exact and leads the system text; a summarizer request ignores a guide prompt, the mock key and a marker in its system text', async () => {
  await withServer({ files: { 'B/guide-one.json': GUIDE_ONE } }, async ({ base, readLog }) => {
    const triage = { 'x-ocutalon-mockkey': 'triage' };
    const last = () => readLog().pop();
    for (const system of ['ocutalon-compaction-v1 compress', 'OCUTALON-COMPACTION-V2 compress', 'compress. OCUTALON-COMPACTION-V1']) {
      const r = await post(base, request([user('Transcript')], { system }), triage);
      assert.equal(r.status, 200, system);
      assert.equal(last().scenario, 'triage', `${system} is not a summarizer request`);
    }
    const summarizer = 'OCUTALON-COMPACTION-V1 compress the transcript';
    await post(base, request([user(`Transcript quoting a guide prompt: ${GUIDE_ONE.match.prompt}`)], { system: summarizer }), { 'x-ocutalon-mockkey': 'chat' });
    assert.equal(last().scenario, 'summary');
    assert.equal(last().selectedBy, 'summarizer');
    await post(base, request([user('Transcript')], { system: `${summarizer} [[mock:summary-off-schema]] [[mock:refusal]]` }), triage);
    assert.equal(last().scenario, 'summary', 'markers in the system text are not read');
  });
});

test('row 11: two keys of one scenario and its unkeyed marker count down independently', async () => {
  await withServer({}, async ({ base, mock }) => {
    const a = 'rate-limited:t-a';
    const b = 'rate-limited:t-b';
    await arm(base, a, 1);
    await arm(base, b, 2);
    const ask = async (label) => (await post(base, request([user(`[[mock:${label}]]`)]))).status;
    const seen = [];
    for (const label of [a, b, a, b, b]) seen.push(await ask(label));
    assert.deepEqual(seen, [429, 429, 200, 429, 200]);
    for (let i = 0; i < 3; i++) assert.equal(await ask('rate-limited'), 429, 'the unkeyed marker is not armed by the keyed ones');
    assert.deepEqual([...mock.countdowns.keys()].sort(), [a, b]);
    assert.equal(mock.countdowns.get(a), 0);
    assert.equal(mock.countdowns.get(b), 0);
  });
});

test('row 13: the retry scenarios send their Retry-After while armed and answer after it, and a long Retry-After exceeds the back-off cap', async () => {
  await withServer({}, async ({ base }) => {
    const cases = [
      ['rate-limited', 429, 'rate_limit_error', '1', 'Answered after the rate limit.'],
      ['overloaded', 529, 'overloaded_error', '1', 'Answered after the overload.'],
      ['long-retry-after', 429, 'rate_limit_error', '30', 'Answered after a capped wait.'],
    ];
    for (const [name, status, type, retryAfter, text] of cases) {
      const label = `${name}:t-retry`;
      await arm(base, label, 1);
      const first = await post(base, request([user(`[[mock:${label}]]`)]));
      assert.equal(first.status, status, name);
      assert.equal(first.json.error.type, type, name);
      assert.equal(first.headers.get('retry-after'), retryAfter, name);
      const second = await post(base, request([user(`[[mock:${label}]]`)]));
      assert.equal(second.status, 200, name);
      assert.equal(second.json.content[0].text, text, name);
      assert.equal(second.headers.get('retry-after'), null, name);
      if (name === 'long-retry-after') assert.ok(Number(retryAfter) * 1000 > BACKOFF_CAP_MS, 'S18: the wait that AI Hub caps');
    }
  });
});

test('row 13: held-past-timer holds its reply past the bridge timer, and the request is logged before the hold', async (t) => {
  const { scenarios, problems } = loadScenarios(COMMITTED);
  assert.deepEqual(problems, []);
  const held = scenarios.byName.get('held-past-timer').replies;
  assert.equal(held.length, 1);
  assert.equal(held[0].status, 200);
  assert.ok(held[0].delayMs > BRIDGE_TIMER_MAX_MS, `a hold of ${held[0].delayMs} ms must outlast the bridge timer`);
  const lines = [];
  const mock = createMock({ scenarios, logDir: null, out: { write: (s) => lines.push(s) } });
  const { req, res } = fakeCall(request([user('[[mock:held-past-timer]]')]));
  t.mock.timers.enable({ apis: ['setTimeout'] });
  await mock.handle(req, res);
  assert.equal(lines.length, 1, 'the log line comes before the hold');
  assert.equal(JSON.parse(lines[0]).scenario, 'held-past-timer');
  t.mock.timers.tick(held[0].delayMs - 1);
  assert.deepEqual(res.calls, [], 'nothing is written before the hold ends');
  t.mock.timers.tick(1);
  assert.deepEqual(res.calls, ['writeHead', 'end']);
  assert.equal(JSON.parse(res.payload).content[0].text, 'This reply arrives after the bridge timer.');
});

test('row 17: the path and the method are checked before the key, so no 404 needs one', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const routes = [
      ['POST', '/messages'],
      ['GET', '/v1/messages'],
      ['PUT', '/v1/messages'],
      ['DELETE', '/v1/messages'],
      ['POST', '/v1/models/claude-haiku-5-5'],
      ['GET', '/v1/models'],
      ['GET', '/v1/models/'],
      ['GET', '/v1/models/a/b'],
      ['GET', '/'],
      ['POST', '/_mock/health'],
      ['GET', '/_mock/nothing'],
      ['DELETE', '/_mock/countdown'],
    ];
    for (const [method, route] of routes) {
      const res = await fetch(`${base}${route}`, { method, body: method === 'POST' || method === 'PUT' ? '{}' : undefined });
      const json = await res.json();
      assert.equal(res.status, 404, `${method} ${route}`);
      assert.equal(json.error.type, 'not_found_error', `${method} ${route}`);
    }
    const logged = readLog();
    assert.equal(logged.length, routes.filter(([, route]) => !route.startsWith('/_mock/')).length, '/_mock/ requests are not logged');
    for (const line of logged) {
      assert.equal(line.status, 404);
      assert.equal(line.rejected, 'not-found');
      assert.equal(line.keyLength, 0);
    }
  });
});

test('row 14: redact replaces each key-like shape from its shortest length and leaves a shape that is one short', () => {
  const run = (c, n) => c.repeat(n);
  const shapes = [
    ['an Anthropic key', 'sk-' + 'ant-' + run('a', 8), 'sk-' + 'ant-' + run('a', 7)],
    ['a bot token', run('1', 8) + ':' + run('A', 35), run('1', 7) + ':' + run('A', 35)],
    ['a bot token with a short tail', run('1', 10) + ':' + run('A', 35), run('1', 10) + ':' + run('A', 34)],
    ['a GitHub personal token', 'gh' + 'p_' + run('a', 20), 'gh' + 'p_' + run('a', 19)],
    ['a GitHub fine-grained token', 'github_' + 'pat_' + run('a', 20), 'github_' + 'pat_' + run('a', 19)],
    ['a DigitalOcean token', 'dop_' + 'v1_' + run('a', 20), 'dop_' + 'v1_' + run('a', 19)],
    ['an AWS access key', 'AK' + 'IA' + run('A', 16), 'AK' + 'IA' + run('A', 15)],
    ['a private key header', '-----' + 'BEGIN PRIVATE KEY', '-----' + 'BEGIN PUBLIC KEY'],
  ];
  for (const [what, key, near] of shapes) {
    assert.equal(redact(`before ${key} after`), 'before [redacted] after', what);
    assert.equal(redact(`before ${near} after`), `before ${near} after`, `${what}, one short`);
  }
  for (const letter of ['p', 'o', 'u', 's', 'r']) assert.equal(redact('gh' + `${letter}_` + run('a', 20)), '[redacted]', `gh${letter}_`);
  assert.equal(redact('dop_' + 'v1_' + run('g', 20)), 'dop_' + 'v1_' + run('g', 20), 'only hexadecimal digits follow dop_v1_');
  assert.equal(redact('no secret here'), 'no secret here');
});
