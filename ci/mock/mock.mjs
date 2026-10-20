// The request handler of the CI model mock (AD-22). createMock({scenarios, logDir, out}) returns {handle(req, res), countdowns}.
// It serves the Anthropic Messages API the way AI Hub's Anthropic provider calls it, over plain HTTP:
//   POST /v1/messages        the reply of the scenario that the request selects
//   GET  /v1/models/<id>     the model object, for any id
//   GET  /_mock/health       {"ok":true,"scenarios":<count>}
//   POST /_mock/countdown    {"marker":"<name>[:<key>]","remaining":0-1000|null}  arms (or clears) a countdown
//   GET  /_mock/countdown?marker=<name>[:<key>]   {"marker":...,"remaining":<n>|null}
// Any other path is a 404. The /v1/ paths need a non-empty x-api-key header (401 otherwise); /_mock/ takes no key.
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
// The only state is the countdown map, keyed by the marker without its brackets. Selection never reads wording.
// The log: one JSON line per request outside /_mock/, to out (stdout) and, with logDir, to logDir/requests.jsonl, written
// synchronously before the reply and before any delay. It holds header names, the x-api-key length and, in the file, the
// request with system text and tools reduced to size and names. It never holds a header value or a key; key-like text
// is replaced by [redacted]. A reply with delayMs waits on a timer that a hung-up client cancels.

import fs from 'node:fs';
import path from 'node:path';
import { findMarkers, isSummaryVariant, parseLabel } from './scenarios.mjs';

export const SUMMARIZER_PREFIX = 'OCUTALON-COMPACTION-V1';
export const MOCKKEY_HEADER = 'x-ocutalon-mockkey';
export const SAMPLING_FIELDS = ['temperature', 'top_p', 'top_k'];
export const MIN_MAX_TOKENS = 4000;
export const MAX_COUNTDOWN = 1000;
export const LOG_FILE = 'requests.jsonl';

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

function summarizeRequest(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return null;
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

export function createMock({ scenarios, logDir, out }) {
  const countdowns = new Map();
  const logPath = logDir ? path.join(logDir, LOG_FILE) : null;
  let counter = 0;

  function emit(entry, body) {
    const line = redact(JSON.stringify(entry));
    out.write(`${line}\n`);
    if (logPath) {
      fs.appendFileSync(logPath, `${redact(JSON.stringify({ ...entry, request: summarizeRequest(body) }))}\n`);
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
      if (data === null || typeof data !== 'object' || Array.isArray(data)) {
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
    sendJson(res, 404, errorBody(404, `CI mock: no route for ${req.method} ${shortPath(pathname)}`));
  }

  function markerScenario(name) {
    const s = scenarios.byName.get(name);
    return s && Object.hasOwn(s.match, 'marker') ? s : null;
  }

  // select(body, headers): {scenario, selectedBy, label, k} or {fail: {message, rejected}}.
  function select(body, headers) {
    const messages = body.messages;
    const at = newestTextIndex(messages);
    const text = at === -1 ? '' : userText(messages[at]);
    if (systemText(body.system).startsWith(SUMMARIZER_PREFIX)) {
      const variants = findMarkers(text).filter((m) => m.ok && isSummaryVariant(m.name));
      if (variants.length > 0) {
        const m = variants[variants.length - 1];
        const scenario = markerScenario(m.name);
        if (!scenario) return { fail: { message: `CI mock: no scenario named ${m.name} for the marker ${m.label}`, rejected: 'unknown-marker' } };
        return { scenario, selectedBy: 'marker', label: m.label, k: 0 };
      }
      const scenario = markerScenario('summary');
      if (!scenario) return { fail: { message: 'CI mock: no summary scenario for the summarizer request', rejected: 'no-scenario' } };
      return { scenario, selectedBy: 'summarizer', label: null, k: 0 };
    }
    const k = at === -1 ? 0 : messages.slice(at + 1).filter((m) => m && m.role === 'assistant').length;
    for (const m of findMarkers(text)) {
      if (!m.ok) return { fail: { message: `CI mock: the marker "[[mock:${m.snippet}" does not parse; use [[mock:<name>]] or [[mock:<name>:<key>]]`, rejected: 'bad-marker' } };
      if (isSummaryVariant(m.name)) continue;
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
      const keyHeader = headers['x-api-key'];
      let body = null;
      try {
        body = JSON.parse(raw);
      } catch {
        body = null;
      }
      const isObj = body !== null && typeof body === 'object' && !Array.isArray(body);
      const entry = {
        ts: new Date().toISOString(),
        id: n,
        method: req.method,
        path: shortPath(pathname),
        status: null,
        scenario: null,
        selectedBy: null,
        marker: null,
        step: null,
        countdown: null,
        headerNames: Object.keys(headers).map((h) => h.toLowerCase()),
        keyLength: typeof keyHeader === 'string' ? keyHeader.length : 0,
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
        const botSide = /^\/bot[^/]+\//.test(pathname);
        refuse(404, 'not-found', botSide
          ? `CI mock: the Telegram Bot API side arrives in Story 10.3: ${req.method} ${shortPath(pathname)}`
          : `CI mock: no route for ${req.method} ${shortPath(pathname)}`);
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
