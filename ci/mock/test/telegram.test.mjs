// Tests of the Telegram Bot API side of the CI mock (Story 10.3; AD-22; the mock rows of the I/O matrix): the five methods and their
// defaults, the refusals, the update queue with its long poll and offset, the queued replies and the call list, the scenario form, the
// scenarios that no model request can select, and the rule that the token is logged by its length only, in stdout and in
// requests.jsonl. Each test makes its own fixture tree and log folder, starts its own server on 127.0.0.1 with port 0 and removes
// everything afterwards (helpers.mjs). The token-like strings are built at run time. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { BOT_PATH, MAX_POLL_SECONDS } from '../mock.mjs';
import { loadScenarios } from '../scenarios.mjs';
import { spawnServer, withServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, '..', 'server.mjs');
// The CI override's dummy token, which matches no key pattern, and a token of the real shape, which the key rule redacts.
const DUMMY = 'ocutalon-ci-dummy-bot-token';
const REAL_SHAPE = `${'1234567890'}:${'B'.repeat(35)}`;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const CONFLICT = { name: 'tg-conflict', match: { telegram: 'getUpdates' }, replies: [{ status: 409, body: { ok: false, error_code: 409, description: 'Conflict: terminated by other getUpdates request' } }] };
const LIMITED = {
  name: 'tg-limited',
  match: { telegram: 'sendMessage' },
  replies: [
    { status: 429, headers: { 'Retry-After': '3' }, body: { ok: false, error_code: 429, description: 'Too Many Requests: retry after 3', parameters: { retry_after: 3 } } },
    { status: 200, body: { ok: true, result: { message_id: 900, chat: { id: 1, type: 'private' }, text: 'scripted' } } },
  ],
};

// bot(base, token, method, {verb, params, json, form, headers}): a Bot API call; returns {status, json, text, headers}.
async function bot(base, token, method, { verb = 'POST', query = '', json, form, headers = {}, body, signal } = {}) {
  const init = { method: verb, headers: { ...headers }, signal };
  if (json !== undefined) {
    init.headers['content-type'] = 'application/json';
    init.body = JSON.stringify(json);
  } else if (form !== undefined) {
    init.headers['content-type'] = 'application/x-www-form-urlencoded';
    init.body = new URLSearchParams(form).toString();
  } else if (body !== undefined) {
    init.body = body;
  }
  const res = await fetch(`${base}/bot${token}/${method}${query}`, init);
  const text = await res.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = null;
  }
  return { status: res.status, json: parsed, text, headers: res.headers };
}

// pollArrived(base, count): waits until the mock lists count getUpdates calls in all; it lists a call as it arrives, before it waits.
async function pollArrived(base, count) {
  const until = Date.now() + 5000;
  while (Date.now() < until) {
    const calls = (await control(base, 'calls', 'GET')).json.calls;
    if (calls.filter((c) => c.method === 'getUpdates').length >= count) return;
    await sleep(10);
  }
  assert.fail(`the mock never listed getUpdates call ${count}`);
}

async function control(base, route, verb = 'POST', payload) {
  const res = await fetch(`${base}/_mock/telegram/${route}`, { method: verb, body: payload === undefined ? undefined : JSON.stringify(payload) });
  return { status: res.status, json: await res.json() };
}

test('the Bot API path grammar is /bot<token>/<method>, with the token possibly empty', () => {
  assert.deepEqual(BOT_PATH.exec('/bot123:abc/getMe').slice(1), ['123:abc', 'getMe']);
  assert.deepEqual(BOT_PATH.exec('/bot/getMe').slice(1), ['', 'getMe']);
  for (const other of ['/botx', '/bot1/a/b', '/v1/messages', '/_mock/health', '/bot']) assert.equal(BOT_PATH.test(other), false, other);
  assert.equal(MAX_POLL_SECONDS, 50);
});

test('mock getMe: GET and POST answer the default bot, with no model key, and the token is logged by its length only', async () => {
  await withServer({}, async ({ base, lines, logFile, readLog }) => {
    for (const verb of ['GET', 'POST']) {
      const r = await bot(base, DUMMY, 'getMe', { verb });
      assert.equal(r.status, 200, verb);
      assert.deepEqual(r.json, { ok: true, result: { id: 424242, is_bot: true, first_name: 'OcuTalon CI', username: 'ocutalon_ci_bot' } });
      assert.equal(r.headers.get('content-type'), 'application/json');
    }
    const r = await bot(base, REAL_SHAPE, 'getMe');
    assert.equal(r.status, 200);
    const entries = readLog();
    assert.equal(entries.length, 3);
    assert.equal(lines.length, 3);
    assert.deepEqual(entries.map((e) => [e.path, e.tokenLength]), [['/bot[redacted]/getMe', DUMMY.length], ['/bot[redacted]/getMe', DUMMY.length], ['/bot[redacted]/getMe', REAL_SHAPE.length]]);
    assert.deepEqual(Object.keys(JSON.parse(lines[0])), ['ts', 'id', 'method', 'path', 'status', 'scenario', 'selectedBy', 'marker', 'step', 'countdown', 'headerNames', 'keyLength', 'tokenLength', 'rejected', 'model', 'maxTokens']);
    assert.equal(entries[0].status, 200);
    assert.equal(entries[0].keyLength, 0);
    assert.deepEqual(entries[0].request, { botMethod: 'getMe', paramNames: [] });
    const everything = `${lines.join('')}${fs.readFileSync(logFile, 'utf8')}`;
    for (const secret of [DUMMY, REAL_SHAPE, 'B'.repeat(35), 'ocutalon-ci-dummy']) assert.equal(everything.includes(secret), false, `the log holds ${secret.slice(0, 12)}`);
    const calls = await control(base, 'calls', 'GET');
    assert.equal(JSON.stringify(calls.json).includes(DUMMY), false, 'and so does the call list not hold the token');
  });
});

test('mock refusals: an empty token is 401, getFile and an unknown method are 404, a multipart body is 400', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const unauthorized = await fetch(`${base}/bot/getMe`);
    assert.equal(unauthorized.status, 401);
    const unauthorizedBody = await unauthorized.json();
    assert.deepEqual(unauthorizedBody, { ok: false, error_code: 401, description: 'Unauthorized' });
    const file = await bot(base, DUMMY, 'getFile', { json: { file_id: 'x' } });
    assert.equal(file.status, 404);
    assert.equal(file.json.ok, false);
    assert.equal(file.json.error_code, 404);
    assert.ok(file.json.description.includes('Story 25.3'), file.text);
    const kick = await bot(base, DUMMY, 'kick');
    assert.equal(kick.status, 404);
    assert.deepEqual(Object.keys(kick.json), ['ok', 'error_code', 'description']);
    assert.equal(kick.json.description.includes('Story 25.3'), false);
    const multipart = await bot(base, DUMMY, 'sendMessage', { headers: { 'content-type': 'multipart/form-data; boundary=zz' }, body: '--zz\r\nContent-Disposition: form-data; name="text"\r\n\r\nhi\r\n--zz--\r\n' });
    assert.equal(multipart.status, 400);
    assert.equal(multipart.json.error_code, 400);
    const badJson = await bot(base, DUMMY, 'sendMessage', { headers: { 'content-type': 'application/json' }, body: '{ not json' });
    assert.equal(badJson.status, 400);
    const put = await bot(base, DUMMY, 'getMe', { verb: 'PUT' });
    assert.equal(put.status, 405);
    for (const text of [JSON.stringify(unauthorizedBody), file.text, kick.text, multipart.text, badJson.text, put.text]) assert.equal(text.includes(DUMMY), false);
    const entries = readLog();
    assert.deepEqual(entries.map((e) => e.rejected), ['no-token', 'get-file', 'unknown-method', 'multipart', 'bad-body', 'method']);
    assert.deepEqual(entries.map((e) => e.status), [401, 404, 404, 400, 400, 405]);
    assert.equal(entries[0].tokenLength, 0);
    assert.equal(entries[1].tokenLength, DUMMY.length);
    assert.equal(JSON.stringify(entries).includes(DUMMY), false);
    const calls = (await control(base, 'calls', 'GET')).json.calls;
    assert.deepEqual(calls.map((c) => c.method), ['getFile', 'kick', 'sendMessage', 'sendMessage'], 'the 401 and the 405 are no calls; the other refusals are');
  });
});

test('mock defaults: sendMessage and editMessageText answer a Message with a counted message_id, the chat id as given and the text; answerCallbackQuery true', async () => {
  await withServer({}, async ({ base }) => {
    const json = await bot(base, DUMMY, 'sendMessage', { json: { chat_id: 12345, text: 'hello json' } });
    assert.equal(json.status, 200);
    assert.equal(json.json.ok, true);
    assert.equal(json.json.result.message_id, 1);
    assert.deepEqual(json.json.result.chat, { id: 12345, type: 'private' });
    assert.equal(json.json.result.text, 'hello json');
    assert.equal(typeof json.json.result.date, 'number');
    const form = await bot(base, DUMMY, 'sendMessage', { form: { chat_id: '777', text: 'hello form' } });
    assert.equal(form.json.result.message_id, 2);
    assert.equal(form.json.result.chat.id, '777', 'as given');
    assert.equal(form.json.result.text, 'hello form');
    const query = await bot(base, DUMMY, 'sendMessage', { verb: 'GET', query: `?chat_id=55&text=${encodeURIComponent('hello query')}` });
    assert.equal(query.json.result.message_id, 3);
    assert.equal(query.json.result.text, 'hello query');
    const edit = await bot(base, DUMMY, 'editMessageText', { json: { chat_id: 12345, message_id: 1, text: 'edited' } });
    assert.equal(edit.status, 200);
    assert.equal(edit.json.result.message_id, 4);
    assert.equal(edit.json.result.text, 'edited');
    assert.equal(edit.json.result.chat.id, 12345);
    const answer = await bot(base, DUMMY, 'answerCallbackQuery', { json: { callback_query_id: 'cb1' } });
    assert.deepEqual(answer.json, { ok: true, result: true });
    const bare = await bot(base, DUMMY, 'sendMessage');
    assert.equal(bare.status, 200);
    assert.equal(bare.json.result.text, '');
    const reset = await control(base, 'reset');
    assert.equal(reset.status, 200);
    const again = await bot(base, DUMMY, 'sendMessage', { json: { chat_id: 1, text: 'x' } });
    assert.equal(again.json.result.message_id, 1, 'a reset restarts the counter');
  });
});

test('mock updates: two queued updates get update_id 1 and 2, and an offset confirms the earlier ones', async () => {
  await withServer({}, async ({ base }) => {
    const queued = await control(base, 'updates', 'POST', [{ message: { text: 'one' } }, { message: { text: 'two' }, update_id: 99 }]);
    assert.equal(queued.status, 200);
    assert.deepEqual(queued.json.updateIds, [1, 2]);
    const all = await bot(base, DUMMY, 'getUpdates');
    assert.equal(all.status, 200);
    assert.deepEqual(all.json.result.map((u) => u.update_id), [1, 2]);
    assert.equal(all.json.result[0].message.text, 'one');
    const again = await bot(base, DUMMY, 'getUpdates', { json: {} });
    assert.deepEqual(again.json.result.map((u) => u.update_id), [1, 2], 'updates stay until an offset confirms them');
    const dropped = await bot(base, DUMMY, 'getUpdates', { json: { offset: 2 } });
    assert.deepEqual(dropped.json.result.map((u) => u.update_id), [2], 'offset 2 drops the first');
    const after = await bot(base, DUMMY, 'getUpdates');
    assert.deepEqual(after.json.result.map((u) => u.update_id), [2], 'for good');
    const limited = await control(base, 'updates', 'POST', { updates: [{ a: 1 }, { a: 2 }, { a: 3 }] });
    assert.deepEqual(limited.json.updateIds, [3, 4, 5]);
    const two = await bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?limit=2' });
    assert.deepEqual(two.json.result.map((u) => u.update_id), [2, 3]);
    const everything = await bot(base, DUMMY, 'getUpdates', { json: { offset: 6 } });
    assert.deepEqual(everything.json.result, [], 'an offset past the last confirms all');
    const negative = await bot(base, DUMMY, 'getUpdates', { json: { offset: -1 } });
    assert.equal(negative.status, 400, 'a negative offset is refused, not read as no offset');
    assert.equal(negative.json.error_code, 400);
    for (const bad of [[], {}, 'x', [1], { updates: [] }]) {
      const r = await control(base, 'updates', 'POST', bad);
      assert.equal(r.status, 400, JSON.stringify(bad));
    }
  });
});

test('mock updates: with none queued getUpdates waits for the timeout or for an update, and a hung-up client ends the wait', async () => {
  await withServer({}, async ({ base, readLog }) => {
    const none = await bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?timeout=0' });
    assert.deepEqual(none.json, { ok: true, result: [] }, 'no timeout: an answer at once');
    const started = Date.now();
    const waited = await bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?timeout=1' });
    const took = Date.now() - started;
    assert.deepEqual(waited.json, { ok: true, result: [] });
    assert.ok(took >= 900 && took < 3000, `waited ${took} ms for a timeout of 1 second`);

    const begun = Date.now();
    const pending = bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?timeout=30' });
    await pollArrived(base, 3);
    await control(base, 'updates', 'POST', [{ message: { text: 'late' } }]);
    const woke = await pending;
    assert.ok(Date.now() - begun < 5000, 'the update ended the wait long before the timeout');
    assert.equal(woke.json.result[0].message.text, 'late');
    assert.equal(woke.json.result[0].update_id, 1);

    const controller = new AbortController();
    const hung = bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?timeout=30&offset=2', signal: controller.signal }).catch(() => null);
    await pollArrived(base, 4);
    controller.abort();
    await hung;
    const until = Date.now() + 3000;
    while (!readLog().some((e) => e.rejected === 'client-closed') && Date.now() < until) await sleep(20);
    assert.ok(readLog().some((e) => e.rejected === 'client-closed' && e.status === null), 'the log shows the hung-up poll');
    const reset = await control(base, 'reset');
    assert.equal(reset.status, 200);
  });
});

test('mock replies: a reply queued for getUpdates while a long poll waits answers that poll at once', async () => {
  await withServer({ files: { 'A/tg-conflict.json': CONFLICT } }, async ({ base, readLog }) => {
    const begun = Date.now();
    const pending = bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?timeout=30' });
    await pollArrived(base, 1);
    const queued = await control(base, 'replies', 'POST', { scenario: 'tg-conflict' });
    assert.equal(queued.status, 200);
    const answered = await pending;
    assert.ok(Date.now() - begun < 5000, 'the queued reply ended the wait long before the timeout');
    assert.equal(answered.status, 409);
    assert.equal(answered.json.error_code, 409);
    assert.equal(readLog().filter((e) => e.selectedBy === 'queued' && e.scenario === 'tg-conflict').length, 1, 'the log shows the poll answered by the queued reply');
    const next = await bot(base, DUMMY, 'getUpdates', { verb: 'GET', query: '?timeout=0' });
    assert.deepEqual(next.json, { ok: true, result: [] }, 'and the reply was used once');
  });
});

test('mock replies and calls: queued replies answer a method in order, then the defaults; calls lists every call; reset clears all', async () => {
  await withServer({ files: { 'A/tg-conflict.json': CONFLICT, 'B/tg-limited.json': LIMITED } }, async ({ base }) => {
    const byScenario = await control(base, 'replies', 'POST', { scenario: 'tg-limited' });
    assert.equal(byScenario.status, 200);
    assert.equal(byScenario.json.method, 'sendMessage');
    assert.equal(byScenario.json.queued, 2);
    const direct = await control(base, 'replies', 'POST', { method: 'getMe', replies: [{ status: 200, body: { ok: true, result: { id: 1, is_bot: true, first_name: 'Scripted', username: 'scripted_bot' } }, delayMs: 300 }, { status: 503, body: { ok: false, error_code: 503, description: 'down' } }] });
    assert.equal(direct.status, 200);
    assert.equal(direct.json.pending, 2);
    const first = await bot(base, DUMMY, 'sendMessage', { json: { chat_id: 1, text: 'a' } });
    assert.equal(first.status, 429);
    assert.equal(first.headers.get('retry-after'), '3');
    assert.equal(first.json.parameters.retry_after, 3);
    const second = await bot(base, DUMMY, 'sendMessage', { json: { chat_id: 1, text: 'b' } });
    assert.equal(second.status, 200);
    assert.equal(second.json.result.message_id, 900);
    const third = await bot(base, DUMMY, 'sendMessage', { json: { chat_id: 2, text: 'c' } });
    assert.equal(third.json.result.text, 'c', 'then the default');
    assert.equal(third.json.result.message_id, 1, 'which counts from the start: the scripted replies made no message');
    const started = Date.now();
    const slow = await bot(base, DUMMY, 'getMe');
    assert.ok(Date.now() - started >= 280, 'delayMs holds the reply');
    assert.equal(slow.json.result.username, 'scripted_bot');
    assert.equal((await bot(base, DUMMY, 'getMe')).status, 503);
    assert.equal((await bot(base, DUMMY, 'getMe')).json.result.username, 'ocutalon_ci_bot', 'then the default');
    await control(base, 'replies', 'POST', { scenario: 'tg-conflict' });
    await control(base, 'updates', 'POST', [{ message: { text: 'kept' } }]);
    const conflict = await bot(base, DUMMY, 'getUpdates');
    assert.equal(conflict.status, 409, 'a queued reply comes before the update queue');
    assert.equal((await bot(base, DUMMY, 'getUpdates')).json.result[0].message.text, 'kept', 'which it did not consume');

    const calls = (await control(base, 'calls', 'GET')).json.calls;
    assert.deepEqual(calls.map((c) => [c.seq, c.method]), [[1, 'sendMessage'], [2, 'sendMessage'], [3, 'sendMessage'], [4, 'getMe'], [5, 'getMe'], [6, 'getMe'], [7, 'getUpdates'], [8, 'getUpdates']]);
    assert.deepEqual(calls[0].params, { chat_id: 1, text: 'a' });
    assert.deepEqual(Object.keys(calls[0]), ['seq', 'ts', 'method', 'params']);
    assert.ok(!Number.isNaN(Date.parse(calls[0].ts)));

    await control(base, 'replies', 'POST', { method: 'answerCallbackQuery', replies: [{ status: 200, body: { ok: true, result: false } }] });
    await control(base, 'reset');
    assert.deepEqual((await control(base, 'calls', 'GET')).json.calls, [], 'reset clears the calls');
    assert.deepEqual((await bot(base, DUMMY, 'answerCallbackQuery')).json.result, true, 'and the queued replies');
    assert.deepEqual((await bot(base, DUMMY, 'getUpdates')).json.result, [], 'and the updates');
  });
});

test('mock replies: a scenario that is not telegram, a bad method or bad replies are 400', async () => {
  await withServer({ files: { 'A/tg-conflict.json': CONFLICT } }, async ({ base }) => {
    const cases = [
      [{ scenario: 'triage' }, 'a model scenario'],
      [{ scenario: 'no-such-scenario' }, 'an unknown scenario'],
      [{ scenario: 'tg-conflict', method: 'getUpdates', replies: [{ status: 200, body: {} }] }, 'a scenario with a method'],
      [{ method: 'getFile', replies: [{ status: 200, body: {} }] }, 'getFile'],
      [{ method: 'kick', replies: [{ status: 200, body: {} }] }, 'a method the mock does not serve'],
      [{ method: 'getMe' }, 'no replies'],
      [{ method: 'getMe', replies: [] }, 'empty replies'],
      [{ method: 'getMe', replies: [{ status: 200 }] }, 'a reply with no body'],
      [{ method: 'getMe', replies: [{ status: 200, body: {}, text: 'x' }] }, 'a reply with text'],
      [{ method: 'getMe', replies: [{ status: 99, body: {} }] }, 'a bad status'],
      [[1], 'a list'],
    ];
    for (const [payload, what] of cases) {
      const r = await control(base, 'replies', 'POST', payload);
      assert.equal(r.status, 400, what);
      assert.equal(r.json.error.type, 'invalid_request_error', what);
    }
    const file = await control(base, 'replies', 'POST', { method: 'getFile', replies: [{ status: 200, body: {} }] });
    assert.ok(file.json.error.message.includes('Story 25.3'));
    assert.equal((await bot(base, DUMMY, 'getMe')).json.result.username, 'ocutalon_ci_bot', 'a refused request queued nothing');
    const unknown = await control(base, 'nowhere', 'POST');
    assert.equal(unknown.status, 404);
  });
});

test('a telegram scenario is never selected by a model request or armed as a countdown', async () => {
  await withServer({ files: { 'A/tg-conflict.json': CONFLICT } }, async ({ base }) => {
    const model = {
      model: 'claude-haiku-5-5',
      max_tokens: 8000,
      messages: [{ role: 'user', content: '[[mock:tg-conflict]]' }],
    };
    const res = await fetch(`${base}/v1/messages`, { method: 'POST', headers: { 'x-api-key': 'k'.repeat(12) }, body: JSON.stringify(model) });
    assert.equal(res.status, 500);
    assert.ok((await res.json()).error.message.includes('no scenario named tg-conflict'));
    const armed = await fetch(`${base}/_mock/countdown`, { method: 'POST', body: JSON.stringify({ marker: 'tg-conflict', remaining: 1 }) });
    assert.equal(armed.status, 400);
    const keyed = await fetch(`${base}/v1/messages`, { method: 'POST', headers: { 'x-api-key': 'k'.repeat(12), 'x-ocutalon-mockkey': 'tg-conflict' }, body: JSON.stringify({ ...model, messages: [{ role: 'user', content: 'hello' }] }) });
    assert.equal(keyed.status, 500);
  });
});

test('the server refuses a telegram scenario file that breaks the format, naming the file, and exits 1', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-tg-'));
  try {
    fs.mkdirSync(path.join(dir, 'A'));
    fs.mkdirSync(path.join(dir, 'B'));
    fs.writeFileSync(path.join(dir, 'A', 'tg-bad.json'), JSON.stringify({ name: 'tg-bad', match: { telegram: 'getFile' }, replies: [{ status: 200, body: {} }] }));
    fs.writeFileSync(path.join(dir, 'B', 'tg-text.json'), JSON.stringify({ name: 'tg-text', match: { telegram: 'getMe' }, replies: [{ status: 200, text: 'x' }] }));
    const s = spawnServer(SERVER, ['--port', '0', '--scenarios', dir]);
    try {
      const exit = await s.exitWithin();
      assert.equal(exit.code, 1);
      assert.equal(s.stdout(), '');
      assert.ok(s.stderr().includes('A/tg-bad.json') && s.stderr().includes('Story 25.3'), s.stderr());
      assert.ok(s.stderr().includes('B/tg-text.json'), s.stderr());
    } finally {
      s.child.kill('SIGKILL');
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('over a real server process, the token appears in neither stdout nor requests.jsonl, and the committed scenarios still load', async () => {
  const logDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-tglog-'));
  const s = spawnServer(SERVER, ['--port', '0', '--log-dir', logDir]);
  try {
    const listening = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    const base = `http://127.0.0.1:${listening.port}`;
    assert.equal(listening.scenarios, loadScenarios(path.join(HERE, '..', 'scenarios')).scenarios.all.length);
    const r = await bot(base, DUMMY, 'sendMessage', { json: { chat_id: 5, text: 'a private message text' } });
    assert.equal(r.status, 200);
    await s.waitFor((l) => l.includes('sendMessage'));
    const file = fs.readFileSync(path.join(logDir, 'requests.jsonl'), 'utf8');
    for (const secret of [DUMMY, 'ocutalon-ci-dummy', 'a private message text']) {
      assert.equal(s.stdout().includes(secret), false, `stdout holds ${secret}`);
      assert.equal(file.includes(secret), false, `requests.jsonl holds ${secret}`);
    }
    const line = JSON.parse(file.trim().split('\n').pop());
    assert.equal(line.path, '/bot[redacted]/sendMessage');
    assert.equal(line.tokenLength, DUMMY.length);
    assert.deepEqual(line.request, { botMethod: 'sendMessage', paramNames: ['chat_id', 'text'] });
  } finally {
    s.child.kill('SIGKILL');
    fs.rmSync(logDir, { recursive: true, force: true });
  }
});
