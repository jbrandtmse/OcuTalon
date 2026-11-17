// Tests of the Slack Web API side of the CI mock (Story 27.2; AD-22): chat.postMessage with a bearer token and its default answer, the refusals
// (no token, an unknown method such as apps.connections.open), the queued replies with Retry-After, the call list and reset, the scenario form,
// the scenarios that no model request can select, and the rule that the token, the member id and the text are logged by name or length only, in
// stdout and in requests.jsonl. Each test makes its own fixture tree and log folder, starts its own server on 127.0.0.1 with port 0 and removes
// everything afterwards (helpers.mjs). The token is built at run time. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { SLACK_PATH } from '../mock.mjs';
import { loadScenarios, MATCH_TYPES, SLACK_METHODS } from '../scenarios.mjs';
import { spawnServer, withServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, '..', 'server.mjs');
const TOKEN = `ci-dummy-${'t'.repeat(12)}-slack`;
const MEMBER = `U0${'Z'.repeat(8)}`;
const TEXT = 'a private reply text';

const LIMITED = { name: 'sl-limited', match: { slack: 'chat.postMessage' }, replies: [{ status: 429, headers: { 'Retry-After': '3' }, body: { ok: false, error: 'ratelimited' } }, { status: 200, body: { ok: true, channel: 'D0X', ts: '1.000900' } }] };

// post(base, method, {token, json, form, query, headers, verb}): a Web API call; returns {status, json, text, headers}.
async function post(base, method, { token = TOKEN, json, form, query = '', headers = {}, body, verb = 'POST' } = {}) {
  const init = { method: verb, headers: { ...headers } };
  if (token !== null) init.headers.authorization = `Bearer ${token}`;
  if (json !== undefined) {
    init.headers['content-type'] = 'application/json; charset=utf-8';
    init.body = JSON.stringify(json);
  } else if (form !== undefined) {
    init.headers['content-type'] = 'application/x-www-form-urlencoded';
    init.body = new URLSearchParams(form).toString();
  } else if (body !== undefined) {
    init.body = body;
  }
  const res = await fetch(`${base}/api/${method}${query}`, init);
  const text = await res.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = null;
  }
  return { status: res.status, json: parsed, text, headers: res.headers };
}

async function control(base, route, verb = 'POST', payload) {
  const res = await fetch(`${base}/_mock/slack/${route}`, { method: verb, body: payload === undefined ? undefined : JSON.stringify(payload) });
  return { status: res.status, json: await res.json() };
}

test('the Web API path grammar is /api/<method>, with letters and dots', () => {
  assert.deepEqual(SLACK_PATH.exec('/api/chat.postMessage').slice(1), ['chat.postMessage']);
  assert.deepEqual(SLACK_PATH.exec('/api/apps.connections.open').slice(1), ['apps.connections.open']);
  for (const other of ['/api', '/api/', '/api/a/b', '/api/a_b', '/v1/messages', '/_mock/health', '/bot1/getMe']) assert.equal(SLACK_PATH.test(other), false, other);
  assert.deepEqual(SLACK_METHODS, ['chat.postMessage']);
  assert.ok(MATCH_TYPES.includes('slack'));
});

test('mock chat.postMessage: the default answer is ok with a channel and a ts that counts, from a JSON body, a form body or the query', async () => {
  await withServer({}, async ({ base }) => {
    const first = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: TEXT, mrkdwn: false } });
    assert.equal(first.status, 200);
    assert.equal(first.json.ok, true);
    assert.equal(first.json.channel, 'D0MOCK1');
    assert.match(first.json.ts, /^[0-9]{10}\.000001$/);
    assert.equal(first.headers.get('content-type'), 'application/json; charset=utf-8');
    const second = await post(base, 'chat.postMessage', { form: { channel: MEMBER, text: TEXT } });
    assert.equal(second.json.channel, 'D0MOCK2');
    assert.match(second.json.ts, /\.000002$/);
    const third = await post(base, 'chat.postMessage', { query: `?channel=${MEMBER}&text=x`, body: '' });
    assert.match(third.json.ts, /\.000003$/);
    const calls = (await control(base, 'calls', 'GET')).json.calls;
    assert.deepEqual(calls.map((c) => [c.seq, c.method]), [[1, 'chat.postMessage'], [2, 'chat.postMessage'], [3, 'chat.postMessage']]);
    assert.deepEqual(Object.keys(calls[0]), ['seq', 'ts', 'method', 'params']);
    assert.deepEqual(calls[0].params, { channel: MEMBER, text: TEXT, mrkdwn: false });
    assert.deepEqual(calls[1].params, { channel: MEMBER, text: TEXT });
    assert.equal(JSON.stringify(calls).includes(TOKEN), false, 'the call list holds no token');
  });
});

test('mock refusals: no token is not_authed, apps.connections.open is unknown_method, a bad body is invalid_json', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const none = await post(base, 'chat.postMessage', { token: null, json: { channel: MEMBER, text: TEXT } });
    assert.deepEqual([none.status, none.json], [200, { ok: false, error: 'not_authed' }]);
    const empty = await post(base, 'chat.postMessage', { token: '', json: { channel: MEMBER, text: TEXT } });
    assert.deepEqual(empty.json, { ok: false, error: 'not_authed' });
    const socket = await post(base, 'apps.connections.open', { json: {} });
    assert.deepEqual([socket.status, socket.json], [200, { ok: false, error: 'unknown_method' }]);
    const other = await post(base, 'auth.test');
    assert.deepEqual(other.json, { ok: false, error: 'unknown_method' });
    const badJson = await post(base, 'chat.postMessage', { headers: { 'content-type': 'application/json' }, body: '{ not json' });
    assert.deepEqual(badJson.json, { ok: false, error: 'invalid_json' });
    const multipart = await post(base, 'chat.postMessage', { headers: { 'content-type': 'multipart/form-data; boundary=zz' }, body: '--zz--\r\n' });
    assert.deepEqual(multipart.json, { ok: false, error: 'invalid_json' });
    assert.deepEqual(readLog().map((e) => e.rejected), ['no-token', 'no-token', 'unknown-method', 'unknown-method', 'bad-body', 'multipart']);
    const calls = (await control(base, 'calls', 'GET')).json.calls;
    assert.deepEqual(calls.map((c) => c.method), ['apps.connections.open', 'auth.test', 'chat.postMessage', 'chat.postMessage'], 'a call with no token is no call; a refused one with a token is listed');
    const unknown = await fetch(`${base}/api/chat.postMessage/extra`);
    assert.equal(unknown.status, 404, 'a path with a part more is no Web API path');
  });
});

test('mock replies and calls: queued replies answer a method in order, with their headers and delay, then the default; reset clears all', async () => {
  await withServer({ files: { 'B/sl-limited.json': LIMITED } }, async ({ base }) => {
    const byScenario = await control(base, 'replies', 'POST', { scenario: 'sl-limited' });
    assert.deepEqual(byScenario.json, { ok: true, method: 'chat.postMessage', queued: 2, pending: 2 });
    const first = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: 'a' } });
    assert.equal(first.status, 429);
    assert.equal(first.headers.get('retry-after'), '3');
    assert.deepEqual(first.json, { ok: false, error: 'ratelimited' });
    const second = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: 'b' } });
    assert.equal(second.json.ts, '1.000900');
    const third = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: 'c' } });
    assert.equal(third.json.channel, 'D0MOCK3', 'then the default, which counts every call');
    const direct = await control(base, 'replies', 'POST', { method: 'chat.postMessage', replies: [{ status: 200, delayMs: 300, body: { ok: false, error: 'channel_not_found' } }] });
    assert.equal(direct.json.pending, 1);
    const started = Date.now();
    const slow = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: 'd' } });
    assert.ok(Date.now() - started >= 280, 'delayMs holds the reply');
    assert.deepEqual(slow.json, { ok: false, error: 'channel_not_found' });
    await control(base, 'replies', 'POST', { scenario: 'sl-limited' });
    await control(base, 'reset');
    assert.deepEqual((await control(base, 'calls', 'GET')).json.calls, [], 'reset clears the calls');
    const afterReset = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: 'e' } });
    assert.equal(afterReset.json.channel, 'D0MOCK1', 'and the queued replies and the counter');
  });
});

test('mock replies: a scenario that is not slack, a bad method or bad replies are 400', async () => {
  await withServer({ files: { 'B/sl-limited.json': LIMITED } }, async ({ base }) => {
    const cases = [
      [{ scenario: 'triage' }, 'a model scenario'],
      [{ scenario: 'no-such-scenario' }, 'an unknown scenario'],
      [{ scenario: 'sl-limited', method: 'chat.postMessage', replies: [{ status: 200, body: {} }] }, 'a scenario with a method'],
      [{ method: 'apps.connections.open', replies: [{ status: 200, body: {} }] }, 'a method the mock does not serve'],
      [{ method: 'chat.postMessage' }, 'no replies'],
      [{ method: 'chat.postMessage', replies: [] }, 'empty replies'],
      [{ method: 'chat.postMessage', replies: [{ status: 200 }] }, 'a reply with no body'],
      [{ method: 'chat.postMessage', replies: [{ status: 200, body: {}, text: 'x' }] }, 'a reply with text'],
      [{ method: 'chat.postMessage', replies: [{ status: 99, body: {} }] }, 'a bad status'],
      [[1], 'a list'],
    ];
    for (const [payload, what] of cases) {
      const r = await control(base, 'replies', 'POST', payload);
      assert.equal(r.status, 400, what);
      assert.equal(r.json.error.type, 'invalid_request_error', what);
    }
    assert.equal((await post(base, 'chat.postMessage', { json: {} })).json.ok, true, 'a refused request queued nothing');
    assert.equal((await control(base, 'nowhere', 'POST')).status, 404);
  });
});

test('a slack scenario is never selected by a model request or armed as a countdown', async () => {
  await withServer({ files: { 'B/sl-limited.json': LIMITED } }, async ({ base }) => {
    const model = { model: 'claude-haiku-5-5', max_tokens: 8000, messages: [{ role: 'user', content: '[[mock:sl-limited]]' }] };
    const res = await fetch(`${base}/v1/messages`, { method: 'POST', headers: { 'x-api-key': 'k'.repeat(12) }, body: JSON.stringify(model) });
    assert.equal(res.status, 500);
    assert.ok((await res.json()).error.message.includes('no scenario named sl-limited'));
    const armed = await fetch(`${base}/_mock/countdown`, { method: 'POST', body: JSON.stringify({ marker: 'sl-limited', remaining: 1 }) });
    assert.equal(armed.status, 400);
    const keyed = await fetch(`${base}/v1/messages`, { method: 'POST', headers: { 'x-api-key': 'k'.repeat(12), 'x-ocutalon-mockkey': 'sl-limited' }, body: JSON.stringify({ ...model, messages: [{ role: 'user', content: 'hello' }] }) });
    assert.equal(keyed.status, 500);
  });
});

test('the committed slack scenarios load and answer through the queue', async () => {
  const { scenarios, problems } = loadScenarios(path.join(HERE, '..', 'scenarios'));
  assert.deepEqual(problems, []);
  assert.deepEqual(scenarios.all.filter((s) => s.match.slack !== undefined).map((s) => [s.name, s.folder, s.replies[0].status]), [
    ['slack-not-found', 'B', 200],
    ['slack-posted', 'B', 200],
    ['slack-rate-limited', 'B', 429],
  ]);
  await withServer({}, async ({ base }) => {
    await control(base, 'replies', 'POST', { scenario: 'slack-rate-limited' });
    const limited = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: 'a' } });
    assert.equal(limited.status, 429);
    assert.equal(limited.headers.get('retry-after'), '1');
    await control(base, 'replies', 'POST', { scenario: 'slack-not-found' });
    assert.deepEqual((await post(base, 'chat.postMessage', { json: {} })).json, { ok: false, error: 'channel_not_found' });
    await control(base, 'replies', 'POST', { scenario: 'slack-posted' });
    const posted = await post(base, 'chat.postMessage', { json: {} });
    assert.deepEqual(posted.json, { ok: true, channel: 'D0MOCKSCN', ts: '1700000000.000100' });
  });
});

test('the server refuses a slack scenario file that breaks the format, naming the file, and exits 1', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-sl-'));
  try {
    fs.mkdirSync(path.join(dir, 'A'));
    fs.mkdirSync(path.join(dir, 'B'));
    fs.writeFileSync(path.join(dir, 'A', 'sl-bad.json'), JSON.stringify({ name: 'sl-bad', match: { slack: 'apps.connections.open' }, replies: [{ status: 200, body: {} }] }));
    fs.writeFileSync(path.join(dir, 'B', 'sl-text.json'), JSON.stringify({ name: 'sl-text', match: { slack: 'chat.postMessage' }, replies: [{ status: 200, text: 'x' }] }));
    const s = spawnServer(SERVER, ['--port', '0', '--scenarios', dir]);
    try {
      const exit = await s.exitWithin();
      assert.equal(exit.code, 1);
      assert.equal(s.stdout(), '');
      assert.ok(s.stderr().includes('A/sl-bad.json') && s.stderr().includes('match slack must be one of chat.postMessage'), s.stderr());
      assert.ok(s.stderr().includes('B/sl-text.json'), s.stderr());
    } finally {
      s.child.kill('SIGKILL');
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('over a real server process, the token, the member id and the text appear in neither stdout nor requests.jsonl', async () => {
  const logDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-sllog-'));
  const s = spawnServer(SERVER, ['--port', '0', '--log-dir', logDir]);
  try {
    const listening = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    const base = `http://127.0.0.1:${listening.port}`;
    const r = await post(base, 'chat.postMessage', { json: { channel: MEMBER, text: TEXT } });
    assert.equal(r.status, 200);
    await post(base, 'apps.connections.open', { json: {} });
    await s.waitFor((l) => l.includes('apps.connections.open'));
    const file = fs.readFileSync(path.join(logDir, 'requests.jsonl'), 'utf8');
    for (const secret of [TOKEN, 'ci-dummy', MEMBER, TEXT]) {
      assert.equal(s.stdout().includes(secret), false, `stdout holds ${secret}`);
      assert.equal(file.includes(secret), false, `requests.jsonl holds ${secret}`);
    }
    const lines = file.trim().split('\n').map((l) => JSON.parse(l));
    assert.equal(lines[0].path, '/api/chat.postMessage');
    assert.equal(lines[0].tokenLength, TOKEN.length);
    assert.equal(lines[0].selectedBy, 'default');
    assert.deepEqual(lines[0].request, { slackMethod: 'chat.postMessage', paramNames: ['channel', 'text'] });
    assert.deepEqual(lines[1].request, { slackMethod: 'apps.connections.open', paramNames: [] });
  } finally {
    s.child.kill('SIGKILL');
    fs.rmSync(logDir, { recursive: true, force: true });
  }
});
