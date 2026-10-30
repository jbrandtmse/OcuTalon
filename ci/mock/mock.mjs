// The request handler of the CI model mock (AD-22). createMock({scenarios, logDir, out}) returns {handle(req, res), countdowns}.
// It serves the Anthropic Messages API the way AI Hub's Anthropic provider calls it, over plain HTTP:
//   POST /v1/messages        the reply of the scenario that the request selects
//   GET  /v1/models/<id>     the model object, for any id
//   GET  /_mock/health       {"ok":true,"scenarios":<count>}
//   POST /_mock/countdown    {"marker":"<name>[:<key>]","remaining":0-1000|null}  arms (or clears) a countdown
//   GET  /_mock/countdown?marker=<name>[:<key>]   {"marker":...,"remaining":<n>|null}
// Any other path is a 404. The /v1/ paths need a non-empty x-api-key header (401 otherwise); /_mock/ takes no key.
// It also serves the Telegram Bot API the way the Telegram service calls it (Story 10.3; AD-22), before the model API's key check:
//   GET or POST /bot<token>/<method>   getMe, getUpdates, sendMessage, editMessageText and answerCallbackQuery; the parameters
//                                      come from the query, a JSON object body or a form body (a multipart body is a 400)
//   POST /_mock/telegram/updates       a JSON list of updates, or {"updates":[...]}, queued with update_id 1, 2, ...
//   POST /_mock/telegram/replies       {"scenario":"<telegram scenario>"} or {"method":"<method>","replies":[<telegram reply>,...]}:
//                                      the replies answer that method's next calls in order
//   GET  /_mock/telegram/calls         {"calls":[{seq, ts, method, params}, ...]}, every Bot API call with a token, in order
//   POST /_mock/telegram/reset         clears the updates, the queued replies, the calls and the counters
// A Bot API call is answered by the first queued reply of its method; else getUpdates by the update queue (updates below the offset
// are dropped, and a negative offset is a 400; with none queued it waits until one is queued or min(timeout, 50) seconds pass, then answers an empty list, and a
// client that hangs up ends the wait; a reply queued for getUpdates while it waits answers it at once); else by the default of the method: getMe the bot ocutalon_ci_bot, sendMessage and
// editMessageText a Message with a counted message_id, the chat.id as given and the text, answerCallbackQuery true. An empty token is a
// 401, getFile (Story 25.3) and any other method a 404, all as Bot API errors {"ok":false,"error_code","description"}. The token is
// never logged: the path is /bot[redacted]/<method> and the entry holds tokenLength; a Bot API call logs its method and parameter names
// (never their values) as the file line's request. A telegram scenario is never selected by a model request.
// The checks of POST /v1/messages run in this order: the key; a JSON object body; no stream:true; messages a non-empty list;
// no temperature, top_p or top_k (NFR-1); max_tokens an integer of at least 4000 (NFR-2). Then the scenario is selected:
//   1. a summarizer request (the system text starts with OCUTALON-COMPACTION-V1) reads only the last summary-* marker of its
//      transcript, and is answered by that scenario, or by the scenario summary;
//   2. else the first [[mock:<name>]] or [[mock:<name>:<key>]] marker of the newest user message that has text, with summary-*
//      markers skipped; a [[mock: that does not parse, or names no marker scenario, is a 500;
//   3. else the one guide prompt scenario whose exact prompt text the same message contains (two matches are a 500);
//   4. else the scenario whose mock key is in the request header x-ocutalon-mockkey;
//   5. else a 500: there is no default reply.
// The reply index (replies[i]) follows the reply rule. k is the number of assistant messages after the newest user message
// with text, and 0 for a summarizer request; last is the index of the final reply:
//   unarmed marker, prompt or mock key:                  replies[min(k, last)]
//   marker armed with remaining > 0:                     replies[0], and remaining decreases by one
//   marker armed with remaining = 0:                     replies[min(1 + k, last)]
// The state of the model side is the countdown map, keyed by the marker without its brackets; the Bot API side keeps the queues above.
// Selection never reads wording.
// The log: one JSON line per request outside /_mock/, to out (stdout) and, with logDir, to logDir/requests.jsonl, written
// synchronously before the reply and before any delay. It holds header names, the x-api-key length, the length of a Bot API token
// (tokenLength, null for a model call) and, in the file, the
// request with system text and tools reduced to size and names. It never holds a header value or a key; key-like text
// is replaced by [redacted]. Its marker is the label of the marker that the request carries, as selection reads it, on a
// refused request too, so a test finds every request of its own marker. A reply with delayMs waits on a timer that a
// hung-up client cancels.

import fs from 'node:fs';
import path from 'node:path';
import { BOT_METHODS, checkTelegramReplies, findMarkers, isObject, isSummaryVariant, parseLabel } from './scenarios.mjs';

export const SUMMARIZER_PREFIX = 'OCUTALON-COMPACTION-V1';
export const MOCKKEY_HEADER = 'x-ocutalon-mockkey';
export const SAMPLING_FIELDS = ['temperature', 'top_p', 'top_k'];
export const MIN_MAX_TOKENS = 4000;
export const MAX_COUNTDOWN = 1000;
export const LOG_FILE = 'requests.jsonl';
// A Bot API path: /bot<token>/<method>. The token may be empty (a 401).
export const BOT_PATH = /^\/bot([^/]*)\/([^/]*)$/;
// The longest that getUpdates waits for an update, in seconds.
export const MAX_POLL_SECONDS = 50;
export const MAX_UPDATES = 100;

// A copy of the key_like alternatives of docker/tests/test-boundaries.sh, as JavaScript regular expressions.
export const KEY_LIKE = [
  /sk-ant-[A-Za-z0-9_-]{8,}/g,
  /[0-9]{8,10}:[A-Za-z0-9_-]{35}/g,
  /gh[pousr]_[A-Za-z0-9]{20,}/g,
  /github_pat_[A-Za-z0-9_]{20,}/g,
  /dop_v1_[a-f0-9]{20,}/g,
  /AKIA[0-9A-Z]{16}/g,
  /-----BEGIN [A-Z ]*PRIVATE KEY/g,
];

// redact(text): the text with every key-like string replaced by [redacted].
export function redact(text) {
  let out = text;
  for (const re of KEY_LIKE) out = out.replace(re, '[redacted]');
  return out;
}

const ERROR_TYPES = {
  400: 'invalid_request_error',
  401: 'authentication_error',
  403: 'permission_error',
  404: 'not_found_error',
  413: 'request_too_large',
  429: 'rate_limit_error',
  500: 'api_error',
  529: 'overloaded_error',
};

export function errorBody(status, message) {
  return { type: 'error', error: { type: ERROR_TYPES[status] || 'api_error', message } };
}

export function modelObject(id) {
  return {
    type: 'model',
    id,
    display_name: id,
    created_at: '2026-01-01T00:00:00Z',
    max_input_tokens: 1000000,
    max_tokens: 128000,
    capabilities: {
      thinking: { supported: true, types: { adaptive: { supported: true }, disabled: { supported: true } } },
      effort: { supported: true },
    },
    lifecycle: 'active',
    deprecated_at: null,
    retires_at: null,
  };
}

function userText(message) {
  const c = message && message.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    return c.filter((b) => b && b.type === 'text' && typeof b.text === 'string').map((b) => b.text).join('\n');
  }
  return '';
}

// The index of the newest user message that has text of its own (a message of tool_result blocks has none), or -1.
function newestTextIndex(messages) {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m && m.role === 'user' && userText(m).trim() !== '') return i;
  }
  return -1;
}

function systemText(system) {
  if (typeof system === 'string') return system;
  if (Array.isArray(system)) {
    return system.filter((b) => b && typeof b.text === 'string').map((b) => b.text).join('\n');
  }
  return '';
}

function summarizeSystem(system) {
  let cacheControl = null;
  if (Array.isArray(system)) {
    for (const b of system) if (b && b.cache_control !== undefined) cacheControl = b.cache_control;
  }
  return { chars: systemText(system).length, cacheControl };
}

function summarizeTools(tools) {
  if (!Array.isArray(tools)) return [];
  return tools.map((t) => ({
    name: t && typeof t.name === 'string' ? t.name : null,
    cacheControl: t && t.cache_control !== undefined ? t.cache_control : null,
  }));
}

// readMarker(body): the marker that selection reads, {summarizer, at, text, marker}. at and text are the newest user message
// with text and its text. For a summarizer request marker is the last summary-* marker of that text, or null. For any other
// request it is the first marker of that text that does not parse or is not summary-*, or null: a parsed marker is
// {ok: true, name, key, label}, one that does not parse {ok: false, snippet}.
function readMarker(body) {
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const at = newestTextIndex(messages);
  const text = at === -1 ? '' : userText(messages[at]);
  const found = findMarkers(text);
  if (systemText(body.system).startsWith(SUMMARIZER_PREFIX)) {
    const variants = found.filter((m) => m.ok && isSummaryVariant(m.name));
    return { summarizer: true, at, text, marker: variants.length > 0 ? variants[variants.length - 1] : null };
  }
  const marker = found.find((m) => !m.ok || !isSummaryVariant(m.name));
  return { summarizer: false, at, text, marker: marker === undefined ? null : marker };
}

function summarizeRequest(body) {
  if (!isObject(body)) return null;
  const { messages, system, tools, ...rest } = body;
  return {
    ...rest,
    messages: messages === undefined ? null : messages,
    system: system === undefined ? null : summarizeSystem(system),
    tools: summarizeTools(tools),
  };
}

function shortPath(p) {
  const cut = p.length > 200 ? `${p.slice(0, 200)}...` : p;
  return cut.replace(/^\/bot[^/]+/, '/bot[redacted]');
}

// botError(status, description): the body of a Bot API error.
export function botError(status, description) {
  return { ok: false, error_code: status, description };
}

// The default answer of a Bot API method that is not scripted; nextMessageId() counts the messages that it makes.
function defaultAnswer(method, params, nextMessageId) {
  if (method === 'getMe') return { ok: true, result: { id: 424242, is_bot: true, first_name: 'OcuTalon CI', username: 'ocutalon_ci_bot' } };
  if (method === 'answerCallbackQuery') return { ok: true, result: true };
  return {
    ok: true,
    result: {
      message_id: nextMessageId(),
      date: Math.floor(Date.now() / 1000),
      chat: { id: params.chat_id === undefined ? null : params.chat_id, type: 'private' },
      text: typeof params.text === 'string' ? params.text : '',
    },
  };
}

// botParams(req, query, raw): {params, multipart, error}: the query parameters, then those of a JSON object body or a form body.
function botParams(req, query, raw) {
  const params = Object.fromEntries(new URLSearchParams(query));
  const type = String((req.headers && req.headers['content-type']) || '').toLowerCase();
  if (type.startsWith('multipart/')) return { params, multipart: true, error: null };
  if (raw.trim() === '') return { params, multipart: false, error: null };
  if (type.includes('json') || raw.trimStart().startsWith('{')) {
    let data = null;
    try {
      data = JSON.parse(raw);
    } catch {
      data = null;
    }
    if (!isObject(data)) return { params, multipart: false, error: "Bad Request: can't parse the JSON object" };
    return { params: { ...params, ...data }, multipart: false, error: null };
  }
  return { params: { ...params, ...Object.fromEntries(new URLSearchParams(raw)) }, multipart: false, error: null };
}

export function createMock({ scenarios, logDir, out }) {
  const countdowns = new Map();
  const logPath = logDir ? path.join(logDir, LOG_FILE) : null;
  let counter = 0;
  // The Bot API side: the queued updates, the queued replies by method, the calls, the counters, and the long polls that wait.
  const tg = { updates: [], replies: new Map(), calls: [], nextUpdateId: 1, nextMessageId: 1, waiters: new Set() };

  function emit(entry, body, summary = summarizeRequest(body)) {
    const line = redact(JSON.stringify(entry));
    out.write(`${line}\n`);
    if (logPath) {
      fs.appendFileSync(logPath, `${redact(JSON.stringify({ ...entry, request: summary }))}\n`);
    }
  }

  function send(res, status, headers, payload) {
    if (res.destroyed || res.writableEnded) return;
    const text = typeof payload === 'string' ? payload : JSON.stringify(payload);
    res.writeHead(status, { ...headers, 'content-length': String(Buffer.byteLength(text)) });
    res.end(text);
  }

  function sendJson(res, status, payload, extra = {}) {
    send(res, status, { 'content-type': 'application/json', ...extra }, payload);
  }

  function control(req, res, pathname, query, raw) {
    if (pathname === '/_mock/health' && req.method === 'GET') {
      sendJson(res, 200, { ok: true, scenarios: scenarios.all.length });
      return;
    }
    if (pathname === '/_mock/countdown' && req.method === 'GET') {
      const label = new URLSearchParams(query).get('marker');
      const parsed = parseLabel(label);
      if (!parsed) {
        sendJson(res, 400, errorBody(400, 'CI mock: the marker query is missing or malformed'));
        return;
      }
      sendJson(res, 200, { marker: parsed.label, remaining: countdowns.has(parsed.label) ? countdowns.get(parsed.label) : null });
      return;
    }
    if (pathname === '/_mock/countdown' && req.method === 'POST') {
      let data;
      try {
        data = JSON.parse(raw);
      } catch {
        data = null;
      }
      if (!isObject(data)) {
        sendJson(res, 400, errorBody(400, 'CI mock: the countdown body is not a JSON object'));
        return;
      }
      const parsed = parseLabel(data.marker);
      if (!parsed) {
        sendJson(res, 400, errorBody(400, 'CI mock: the marker is malformed (<name> or <name>:<key>)'));
        return;
      }
      const scenario = scenarios.byName.get(parsed.name);
      if (!scenario || !Object.hasOwn(scenario.match, 'marker')) {
        sendJson(res, 400, errorBody(400, `CI mock: no marker scenario named ${parsed.name}`));
        return;
      }
      const remaining = data.remaining;
      if (remaining === null) {
        countdowns.delete(parsed.label);
      } else if (Number.isInteger(remaining) && remaining >= 0 && remaining <= MAX_COUNTDOWN) {
        countdowns.set(parsed.label, remaining);
      } else {
        sendJson(res, 400, errorBody(400, `CI mock: remaining must be null or an integer from 0 to ${MAX_COUNTDOWN}`));
        return;
      }
      sendJson(res, 200, { marker: parsed.label, remaining: countdowns.has(parsed.label) ? countdowns.get(parsed.label) : null });
      return;
    }
    if (pathname.startsWith('/_mock/telegram/')) {
      telegramControl(req, res, pathname, raw);
      return;
    }
    sendJson(res, 404, errorBody(404, `CI mock: no route for ${req.method} ${shortPath(pathname)}`));
  }

  function wakeWaiters() {
    for (const wake of [...tg.waiters]) wake();
  }

  // Queues the replies of a method and wakes the long polls, so that a getUpdates call that is already waiting takes a queued reply at once.
  function queueReplies(method, replies, scenario) {
    if (!tg.replies.has(method)) tg.replies.set(method, []);
    for (const reply of replies) tg.replies.get(method).push({ reply, scenario });
    wakeWaiters();
  }

  // The control routes of the Bot API side.
  function telegramControl(req, res, pathname, raw) {
    const route = pathname.slice('/_mock/telegram/'.length);
    if (route === 'calls' && req.method === 'GET') {
      sendJson(res, 200, { calls: tg.calls });
      return;
    }
    if (route === 'reset' && req.method === 'POST') {
      tg.updates = [];
      tg.replies = new Map();
      tg.calls = [];
      tg.nextUpdateId = 1;
      tg.nextMessageId = 1;
      wakeWaiters();
      sendJson(res, 200, { ok: true });
      return;
    }
    if ((route === 'updates' || route === 'replies') && req.method === 'POST') {
      let data;
      try {
        data = JSON.parse(raw);
      } catch {
        data = null;
      }
      if (route === 'updates') {
        const list = Array.isArray(data) ? data : isObject(data) && Array.isArray(data.updates) ? data.updates : null;
        if (list === null || list.length === 0 || !list.every(isObject)) {
          sendJson(res, 400, errorBody(400, 'CI mock: the updates body is a non-empty JSON list of objects, or {"updates": [...]}'));
          return;
        }
        const ids = [];
        for (const update of list) {
          const queued = { ...update, update_id: tg.nextUpdateId };
          tg.nextUpdateId += 1;
          tg.updates.push(queued);
          ids.push(queued.update_id);
        }
        wakeWaiters();
        sendJson(res, 200, { ok: true, updateIds: ids });
        return;
      }
      if (!isObject(data)) {
        sendJson(res, 400, errorBody(400, 'CI mock: the replies body is not a JSON object'));
        return;
      }
      if (data.scenario !== undefined) {
        const scenario = typeof data.scenario === 'string' ? scenarios.byName.get(data.scenario) : undefined;
        if (data.method !== undefined || data.replies !== undefined || !scenario || !Object.hasOwn(scenario.match, 'telegram')) {
          sendJson(res, 400, errorBody(400, 'CI mock: give {"scenario": "<name of a telegram scenario>"} alone, or {"method", "replies"}'));
          return;
        }
        queueReplies(scenario.match.telegram, scenario.replies, scenario.name);
        sendJson(res, 200, { ok: true, method: scenario.match.telegram, queued: scenario.replies.length, pending: tg.replies.get(scenario.match.telegram).length });
        return;
      }
      if (typeof data.method !== 'string' || !BOT_METHODS.includes(data.method)) {
        const hint = data.method === 'getFile' ? 'getFile arrives in Story 25.3' : `the method must be one of ${BOT_METHODS.join(', ')}`;
        sendJson(res, 400, errorBody(400, `CI mock: ${hint}`));
        return;
      }
      const problems = checkTelegramReplies(data.replies, 'replies');
      if (problems.length > 0) {
        sendJson(res, 400, errorBody(400, `CI mock: ${problems.join('; ')}`));
        return;
      }
      queueReplies(data.method, data.replies, null);
      sendJson(res, 200, { ok: true, method: data.method, queued: data.replies.length, pending: tg.replies.get(data.method).length });
      return;
    }
    sendJson(res, 404, errorBody(404, `CI mock: no route for ${req.method} ${shortPath(pathname)}`));
  }

  // The updates that getUpdates answers: those below the offset are confirmed and dropped, then at most limit are listed.
  function pendingUpdates(offset, limit) {
    if (offset !== null) tg.updates = tg.updates.filter((u) => u.update_id >= offset);
    return tg.updates.slice(0, limit);
  }

  // Waits up to ms for the next change of the queues (an update queued or a reset) or for the end of the connection.
  function pollWait(res, ms) {
    return new Promise((resolve) => {
      const done = () => {
        clearTimeout(timer);
        tg.waiters.delete(done);
        res.removeListener('close', done);
        resolve();
      };
      const timer = setTimeout(done, ms);
      tg.waiters.add(done);
      res.once('close', done);
    });
  }

  function markerScenario(name) {
    const s = scenarios.byName.get(name);
    return s && Object.hasOwn(s.match, 'marker') ? s : null;
  }

  // select(body, headers): {scenario, selectedBy, label, k} or {fail: {message, rejected}}.
  function select(body, headers) {
    const messages = body.messages;
    const { summarizer, at, text, marker: m } = readMarker(body);
    if (summarizer) {
      if (m) {
        const scenario = markerScenario(m.name);
        if (!scenario) return { fail: { message: `CI mock: no scenario named ${m.name} for the marker ${m.label}`, rejected: 'unknown-marker' } };
        return { scenario, selectedBy: 'marker', label: m.label, k: 0 };
      }
      const scenario = markerScenario('summary');
      if (!scenario) return { fail: { message: 'CI mock: no summary scenario for the summarizer request', rejected: 'no-scenario' } };
      return { scenario, selectedBy: 'summarizer', label: null, k: 0 };
    }
    const k = at === -1 ? 0 : messages.slice(at + 1).filter((x) => x && x.role === 'assistant').length;
    if (m) {
      if (!m.ok) return { fail: { message: `CI mock: the marker "[[mock:${m.snippet}" does not parse; use [[mock:<name>]] or [[mock:<name>:<key>]]`, rejected: 'bad-marker' } };
      const scenario = markerScenario(m.name);
      if (!scenario) return { fail: { message: `CI mock: no scenario named ${m.name} for the marker [[mock:${m.label}]]`, rejected: 'unknown-marker' } };
      return { scenario, selectedBy: 'marker', label: m.label, k };
    }
    const hits = scenarios.prompts.filter((p) => text.includes(p.prompt));
    if (hits.length > 1) {
      return { fail: { message: `CI mock: two guide prompts match: ${hits[0].scenario.name} and ${hits[1].scenario.name}`, rejected: 'ambiguous-prompt' } };
    }
    if (hits.length === 1) return { scenario: hits[0].scenario, selectedBy: 'prompt', label: null, k };
    const key = headers[MOCKKEY_HEADER];
    const byKey = typeof key === 'string' ? scenarios.byMockKey.get(key) : undefined;
    if (byKey) return { scenario: byKey, selectedBy: 'mockkey', label: null, k };
    return { fail: { message: 'CI mock: no scenario: no marker, no guide prompt and no known mock key', rejected: 'no-scenario' } };
  }

  // pickReply(scenario, label, k): {index, countdown}; consumes the countdown of an armed marker.
  function pickReply(scenario, label, k) {
    const last = scenario.replies.length - 1;
    if (label !== null && countdowns.has(label)) {
      const remaining = countdowns.get(label);
      if (remaining > 0) {
        countdowns.set(label, remaining - 1);
        return { index: 0, countdown: remaining - 1 };
      }
      return { index: Math.min(1 + k, last), countdown: 0 };
    }
    return { index: Math.min(k, last), countdown: null };
  }

  // The status, headers and payload of a scenario reply.
  function build(reply, n, body, rawLength) {
    const headers = { 'content-type': 'application/json', 'request-id': `req_mock_${n}` };
    for (const [k, v] of Object.entries(reply.headers || {})) {
      for (const existing of Object.keys(headers)) if (existing.toLowerCase() === k.toLowerCase()) delete headers[existing];
      headers[k] = v;
    }
    if (Object.hasOwn(reply, 'body')) return { status: reply.status, headers, payload: reply.body };
    if (reply.status >= 400) return { status: reply.status, headers, payload: errorBody(reply.status, reply.text) };
    let content;
    let stop = reply.stopReason;
    if (Object.hasOwn(reply, 'toolUse')) {
      const uses = Array.isArray(reply.toolUse) ? reply.toolUse : [reply.toolUse];
      content = uses.map((u, i) => ({ type: 'tool_use', id: `toolu_mock_${n}_${i + 1}`, name: u.name, input: u.input === undefined ? {} : u.input }));
      stop = stop || 'tool_use';
    } else {
      content = reply.text === '' ? [] : [{ type: 'text', text: reply.text }];
      stop = stop || 'end_turn';
    }
    return {
      status: reply.status,
      headers,
      payload: {
        id: `msg_mock_${n}`,
        type: 'message',
        role: 'assistant',
        model: typeof body.model === 'string' ? body.model : 'mock-model',
        content,
        stop_reason: stop,
        stop_sequence: null,
        usage: {
          input_tokens: Math.ceil(rawLength / 4),
          output_tokens: content.length === 0 ? 0 : Math.ceil(JSON.stringify(content).length / 4),
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
        },
      },
    };
  }

  async function readBody(req) {
    const chunks = [];
    for await (const chunk of req) chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
    return Buffer.concat(chunks).toString('utf8');
  }

  // One Bot API call (Story 10.3): /bot<token>/<method>. The log entry has the shape of a model call's, with tokenLength.
  async function handleBot(req, res, match, query, raw, headers, n, pathname) {
    const token = match[1];
    const method = match[2];
    const entry = {
      ts: new Date().toISOString(),
      id: n,
      method: req.method,
      path: shortPath(pathname),
      status: null,
      scenario: null,
      selectedBy: 'telegram',
      marker: null,
      step: null,
      countdown: null,
      headerNames: Object.keys(headers).map((h) => h.toLowerCase()),
      keyLength: typeof headers['x-api-key'] === 'string' ? headers['x-api-key'].length : 0,
      tokenLength: token.length,
      rejected: null,
      model: null,
      maxTokens: null,
    };
    let summary = { botMethod: method, paramNames: [] };
    const refuse = (status, rejected, description) => {
      entry.status = status;
      entry.rejected = rejected;
      emit(entry, null, summary);
      sendJson(res, status, botError(status, description), { 'request-id': `req_mock_${n}` });
    };
    if (token === '') {
      refuse(401, 'no-token', 'Unauthorized');
      return;
    }
    if (req.method !== 'GET' && req.method !== 'POST') {
      refuse(405, 'method', `CI mock: the Bot API takes GET and POST, not ${req.method}`);
      return;
    }
    const { params, multipart, error } = botParams(req, query, raw);
    summary = { botMethod: method, paramNames: Object.keys(params) };
    tg.calls.push({ seq: tg.calls.length + 1, ts: entry.ts, method, params });
    if (multipart) {
      refuse(400, 'multipart', 'Bad Request: the CI mock takes query, JSON and form parameters, not multipart/form-data');
      return;
    }
    if (error !== null) {
      refuse(400, 'bad-body', error);
      return;
    }
    if (method === 'getFile') {
      refuse(404, 'get-file', 'CI mock: getFile arrives in Story 25.3');
      return;
    }
    if (!BOT_METHODS.includes(method)) {
      refuse(404, 'unknown-method', `CI mock: the Bot API method ${method.slice(0, 40)} is not served`);
      return;
    }
    let reply = null;
    // Takes the method's next queued reply, if there is one.
    const takeQueued = () => {
      const queue = tg.replies.get(method);
      if (queue === undefined || queue.length === 0) return false;
      const queued = queue.shift();
      reply = queued.reply;
      entry.scenario = queued.scenario;
      entry.selectedBy = 'queued';
      return true;
    };
    if (takeQueued()) {
      // A queued reply comes before the defaults and the update queue.
    } else if (method === 'getUpdates') {
      if (/^-[0-9]+$/.test(String(params.offset))) {
        refuse(400, 'bad-offset', 'Bad Request: the CI mock takes an offset of 0 or more');
        return;
      }
      const offset = /^[0-9]+$/.test(String(params.offset)) ? Number(params.offset) : null;
      const limit = /^[0-9]+$/.test(String(params.limit)) ? Math.min(Math.max(Number(params.limit), 1), MAX_UPDATES) : MAX_UPDATES;
      const seconds = /^[0-9]+$/.test(String(params.timeout)) ? Math.min(Number(params.timeout), MAX_POLL_SECONDS) : 0;
      let ready = pendingUpdates(offset, limit);
      const until = Date.now() + seconds * 1000;
      while (ready.length === 0 && Date.now() < until && !res.destroyed) {
        await pollWait(res, until - Date.now());
        if (res.destroyed || res.writableEnded) break;
        if ((tg.replies.get(method) ?? []).length > 0) break;
        ready = pendingUpdates(offset, limit);
      }
      if (res.destroyed || res.writableEnded) {
        entry.rejected = 'client-closed';
        emit(entry, null, summary);
        return;
      }
      if (!takeQueued()) {
        entry.selectedBy = ready.length > 0 ? 'updates' : 'empty';
        reply = { status: 200, body: { ok: true, result: ready } };
      }
    } else {
      entry.selectedBy = 'default';
      reply = { status: 200, body: defaultAnswer(method, params, () => tg.nextMessageId++) };
    }
    const built = build(reply, n, null, raw.length);
    entry.status = built.status;
    emit(entry, null, summary);
    const deliver = () => send(res, built.status, built.headers, built.payload);
    if (reply.delayMs > 0) {
      const timer = setTimeout(deliver, reply.delayMs);
      res.once('close', () => clearTimeout(timer));
    } else {
      deliver();
    }
  }

  async function handle(req, res) {
    try {
      const url = req.url || '/';
      const q = url.indexOf('?');
      const pathname = q === -1 ? url : url.slice(0, q);
      const query = q === -1 ? '' : url.slice(q + 1);
      const raw = await readBody(req);
      if (pathname.startsWith('/_mock/')) {
        control(req, res, pathname, query, raw);
        return;
      }
      counter += 1;
      const n = counter;
      const headers = req.headers || {};
      const botMatch = BOT_PATH.exec(pathname);
      if (botMatch !== null) {
        await handleBot(req, res, botMatch, query, raw, headers, n, pathname);
        return;
      }
      const keyHeader = headers['x-api-key'];
      let body = null;
      try {
        body = JSON.parse(raw);
      } catch {
        body = null;
      }
      const isObj = isObject(body);
      const carried = isObj ? readMarker(body).marker : null;
      const entry = {
        ts: new Date().toISOString(),
        id: n,
        method: req.method,
        path: shortPath(pathname),
        status: null,
        scenario: null,
        selectedBy: null,
        marker: carried && carried.ok ? carried.label : null,
        step: null,
        countdown: null,
        headerNames: Object.keys(headers).map((h) => h.toLowerCase()),
        keyLength: typeof keyHeader === 'string' ? keyHeader.length : 0,
        tokenLength: null,
        rejected: null,
        model: isObj && typeof body.model === 'string' ? body.model : null,
        maxTokens: isObj && typeof body.max_tokens === 'number' ? body.max_tokens : null,
      };
      const refuse = (status, rejected, message, headersOut = {}) => {
        entry.status = status;
        entry.rejected = rejected;
        emit(entry, isObj ? body : null);
        sendJson(res, status, errorBody(status, message), { 'request-id': `req_mock_${n}`, ...headersOut });
      };

      const modelMatch = /^\/v1\/models\/([^/]+)$/.exec(pathname);
      const isMessages = req.method === 'POST' && pathname === '/v1/messages';
      const isModel = req.method === 'GET' && modelMatch !== null;
      if (!isMessages && !isModel) {
        refuse(404, 'not-found', `CI mock: no route for ${req.method} ${shortPath(pathname)}`);
        return;
      }
      if (entry.keyLength === 0) {
        refuse(401, 'no-key', 'CI mock: the request has no x-api-key header');
        return;
      }
      if (isModel) {
        let id = modelMatch[1];
        try {
          id = decodeURIComponent(id);
        } catch {
          // an id that is not percent-encoded text is served as written
        }
        entry.status = 200;
        entry.scenario = 'model';
        emit(entry, null);
        sendJson(res, 200, modelObject(id), { 'request-id': `req_mock_${n}` });
        return;
      }
      if (!isObj) {
        refuse(400, 'not-json', 'CI mock: the request body is not a JSON object');
        return;
      }
      if (body.stream === true) {
        refuse(400, 'stream', 'CI mock: stream: true is not supported; the mock answers non-streaming requests only');
        return;
      }
      if (!Array.isArray(body.messages) || body.messages.length === 0) {
        refuse(400, 'messages', 'CI mock: messages must be a non-empty list');
        return;
      }
      const sampling = SAMPLING_FIELDS.filter((f) => Object.hasOwn(body, f));
      if (sampling.length > 0) {
        refuse(400, 'sampling', `CI mock: sampling parameters are not allowed (NFR-1): ${sampling.join(', ')}`);
        return;
      }
      if (!Number.isInteger(body.max_tokens) || body.max_tokens < MIN_MAX_TOKENS) {
        const seen = body.max_tokens === undefined ? 'no value' : JSON.stringify(body.max_tokens);
        refuse(400, 'max_tokens', `CI mock: max_tokens must be an integer of at least ${MIN_MAX_TOKENS} (NFR-2), got ${seen}`);
        return;
      }
      const picked = select(body, headers);
      if (picked.fail) {
        refuse(500, picked.fail.rejected, picked.fail.message);
        return;
      }
      const { index, countdown } = pickReply(picked.scenario, picked.label, picked.k);
      const reply = picked.scenario.replies[index];
      const built = build(reply, n, body, raw.length);
      entry.status = built.status;
      entry.scenario = picked.scenario.name;
      entry.selectedBy = picked.selectedBy;
      entry.marker = picked.label;
      entry.step = picked.k;
      entry.countdown = countdown;
      emit(entry, body);
      const deliver = () => send(res, built.status, built.headers, built.payload);
      if (reply.delayMs > 0) {
        const timer = setTimeout(deliver, reply.delayMs);
        res.once('close', () => clearTimeout(timer));
      } else {
        deliver();
      }
    } catch (err) {
      if (res.destroyed || res.writableEnded) return;
      try {
        out.write(`${JSON.stringify({ event: 'error', message: String(err && err.message) })}\n`);
        sendJson(res, 500, errorBody(500, 'CI mock: internal error'));
      } catch {
        // the connection is gone
      }
    }
  }

  return { handle, countdowns };
}
