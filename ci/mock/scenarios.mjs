// The scenario files of the CI model mock (AD-22): one JSON file per scenario under scenarios/A/ (Lane A's) and
// scenarios/B/ (Lane B's), and the grammar of the markers that select them.
//
// loadScenarios(dir) reads dir/A/*.json and dir/B/*.json, applies every rule of the file format and returns
// {scenarios, problems}. problems holds one line per defect, each naming the file and the rule, and is empty when
// every file is valid. scenarios holds the lookups of the mock:
//   all       every valid scenario, in folder and file order
//   byName    name -> scenario
//   byMockKey mock key -> scenario (the match type mockkey)
//   prompts   [{prompt, scenario}] (the match type prompt, which is allowed only under B/)
// A scenario is {name, match, replies, file, folder}. The format:
//   {"name": "<kebab-case, the file's name>", "match": {"marker"|"prompt"|"mockkey": "<value>"}, "replies": [<reply>, ...]}
//   reply: {"status": 100-599, "headers": {...}, "delayMs": 0-600000, "stopReason": "<API value>",
//           and exactly one of "text": "<string>", "toolUse": {"name", "input"} or a list of them, "body": {...}}
//   headers: valid HTTP names and string values, never Content-Length or Transfer-Encoding, which the mock sets itself.
// A marker scenario's marker is its name. The match type telegram is reserved for Story 10.3 and refused.
// This module reads files and holds no state.

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

export const FOLDERS = ['A', 'B'];
export const MATCH_TYPES = ['marker', 'prompt', 'mockkey', 'telegram'];
export const SCENARIO_FIELDS = ['name', 'match', 'replies'];
export const REPLY_FIELDS = ['status', 'headers', 'delayMs', 'stopReason', 'text', 'toolUse', 'body'];
export const REPLY_BODY_FIELDS = ['text', 'toolUse', 'body'];
export const STOP_REASONS = ['end_turn', 'max_tokens', 'stop_sequence', 'tool_use', 'pause_turn', 'refusal'];
// The grammar of a scenario name and of a marker's test key, as regular expression source; every pattern below is built
// from these two.
const NAME_SOURCE = '[a-z0-9]+(?:-[a-z0-9]+)*';
const KEY_SOURCE = '[A-Za-z0-9_-]{1,64}';
export const NAME_PATTERN = new RegExp(`^${NAME_SOURCE}$`);
export const NAME_MAX = 64;
export const KEY_PATTERN = new RegExp(`^${KEY_SOURCE}$`);
export const MARKER_OPEN = '[[mock:';
export const MIN_STATUS = 100;
export const MAX_STATUS = 599;
export const MAX_DELAY_MS = 600000;
export const FRAMING_HEADERS = ['content-length', 'transfer-encoding'];

const MARKER_BODY = new RegExp(`^(${NAME_SOURCE})(?::(${KEY_SOURCE}))?\\]\\]`);
const LABEL = new RegExp(`^(${NAME_SOURCE})(?::(${KEY_SOURCE}))?$`);

// parseLabel('<name>[:<key>]'): {name, key, label}, or null when the text is not a marker without its brackets.
export function parseLabel(text) {
  if (typeof text !== 'string') return null;
  const m = LABEL.exec(text);
  if (!m || m[1].length > NAME_MAX) return null;
  return { name: m[1], key: m[2] === undefined ? null : m[2], label: text };
}

// findMarkers(text): every occurrence of "[[mock:" in the text, in order. A well-formed one is
// {ok: true, name, key, label}; any other is {ok: false, snippet}, the text that follows the opening.
export function findMarkers(text) {
  const found = [];
  if (typeof text !== 'string') return found;
  let at = text.indexOf(MARKER_OPEN);
  while (at !== -1) {
    const rest = text.slice(at + MARKER_OPEN.length);
    const m = MARKER_BODY.exec(rest);
    if (m && m[1].length <= NAME_MAX) {
      found.push({ ok: true, name: m[1], key: m[2] === undefined ? null : m[2], label: m[2] === undefined ? m[1] : `${m[1]}:${m[2]}` });
    } else {
      found.push({ ok: false, snippet: rest.slice(0, 40) });
    }
    at = text.indexOf(MARKER_OPEN, at + MARKER_OPEN.length);
  }
  return found;
}

// A summary variant: the marker names that only a summarizer request reads.
export function isSummaryVariant(name) {
  return typeof name === 'string' && name.startsWith('summary-');
}

// isObject(v): true for a plain JSON object, false for null, a list or any other value.
export function isObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function checkToolUse(use, where, bad) {
  const items = Array.isArray(use) ? use : [use];
  if (items.length === 0) bad(`${where}: toolUse is an empty list`);
  for (const item of items) {
    if (!isObject(item)) {
      bad(`${where}: a toolUse is not an object`);
      continue;
    }
    if (typeof item.name !== 'string' || item.name === '') bad(`${where}: a toolUse has no name`);
    if (item.input !== undefined && !isObject(item.input)) bad(`${where}: a toolUse input is not an object`);
    for (const k of Object.keys(item)) {
      if (k !== 'name' && k !== 'input') bad(`${where}: a toolUse has the unknown field "${k}"`);
    }
  }
}

function checkReply(reply, where, bad) {
  if (!isObject(reply)) {
    bad(`${where}: a reply is not an object`);
    return;
  }
  for (const k of Object.keys(reply)) {
    if (!REPLY_FIELDS.includes(k)) bad(`${where}: a reply has the unknown field "${k}"`);
  }
  const status = reply.status;
  if (!Number.isInteger(status) || status < MIN_STATUS || status > MAX_STATUS) {
    bad(`${where}: status must be an integer from ${MIN_STATUS} to ${MAX_STATUS}`);
  }
  const present = REPLY_BODY_FIELDS.filter((k) => Object.hasOwn(reply, k));
  if (present.length !== 1) bad(`${where}: a reply must hold exactly one of text, toolUse and body, found ${present.length}`);
  if (Object.hasOwn(reply, 'text') && typeof reply.text !== 'string') bad(`${where}: text is not a string`);
  if (Object.hasOwn(reply, 'toolUse')) checkToolUse(reply.toolUse, where, bad);
  if (Object.hasOwn(reply, 'body') && !(reply.body !== null && typeof reply.body === 'object')) {
    bad(`${where}: body is not a JSON object or list`);
  }
  if (reply.headers !== undefined) {
    if (!isObject(reply.headers) || !Object.values(reply.headers).every((v) => typeof v === 'string')) {
      bad(`${where}: headers must be an object of strings`);
    } else {
      for (const [name, value] of Object.entries(reply.headers)) {
        try {
          http.validateHeaderName(name);
          http.validateHeaderValue(name, value);
        } catch {
          bad(`${where}: the header ${JSON.stringify(name)} is not a valid HTTP header name and value`);
          continue;
        }
        if (FRAMING_HEADERS.includes(name.toLowerCase())) bad(`${where}: the header ${name} is set by the mock, never by a scenario`);
      }
    }
  }
  if (reply.delayMs !== undefined && (!Number.isInteger(reply.delayMs) || reply.delayMs < 0 || reply.delayMs > MAX_DELAY_MS)) {
    bad(`${where}: delayMs must be an integer from 0 to ${MAX_DELAY_MS}`);
  }
  const error = Number.isInteger(status) && status >= 400;
  if (reply.stopReason !== undefined) {
    if (!STOP_REASONS.includes(reply.stopReason)) bad(`${where}: stopReason is not one of ${STOP_REASONS.join(', ')}`);
    if (Object.hasOwn(reply, 'body')) bad(`${where}: stopReason cannot come with a body`);
    if (error) bad(`${where}: stopReason cannot come with an error status`);
  }
  if (error && Object.hasOwn(reply, 'toolUse')) bad(`${where}: a toolUse reply needs a status below 400`);
}

function checkScenario(rel, folder, base, data, bad) {
  if (!isObject(data)) {
    bad(`${rel}: the file is not a JSON object`);
    return;
  }
  for (const k of Object.keys(data)) {
    if (!SCENARIO_FIELDS.includes(k)) bad(`${rel}: unknown field "${k}"`);
  }
  if (typeof data.name !== 'string' || !NAME_PATTERN.test(data.name) || data.name.length > NAME_MAX) {
    bad(`${rel}: name is not kebab-case (a-z, 0-9 and single hyphens, at most ${NAME_MAX} characters)`);
  } else if (data.name !== base) {
    bad(`${rel}: name "${data.name}" differs from the file name "${base}"`);
  }
  const match = data.match;
  if (!isObject(match) || Object.keys(match).length !== 1) {
    bad(`${rel}: match must have exactly one key of marker, prompt and mockkey`);
  } else {
    const type = Object.keys(match)[0];
    const value = match[type];
    if (type === 'telegram') {
      bad(`${rel}: match telegram is reserved for Story 10.3`);
    } else if (!MATCH_TYPES.includes(type)) {
      bad(`${rel}: match has the unknown key "${type}"`);
    } else if (typeof value !== 'string' || value === '') {
      bad(`${rel}: match ${type} is not a non-empty string`);
    } else if (type === 'marker' && value !== data.name) {
      bad(`${rel}: marker "${value}" differs from name "${data.name}"`);
    } else if (type === 'prompt' && folder !== 'B') {
      bad(`${rel}: a prompt scenario belongs under B/`);
    } else if (type === 'mockkey' && /\s/.test(value)) {
      bad(`${rel}: the mock key holds white space`);
    }
  }
  if (!Array.isArray(data.replies) || data.replies.length === 0) {
    bad(`${rel}: replies must be a non-empty list`);
  } else {
    data.replies.forEach((reply, i) => checkReply(reply, `${rel} reply ${i + 1}`, bad));
  }
}

function listFolder(dir, folder, problems, files) {
  const full = path.join(dir, folder);
  let entries;
  try {
    entries = fs.readdirSync(full, { withFileTypes: true });
  } catch (e) {
    if (e.code === 'ENOENT') return;
    problems.push(`${folder}/: the folder cannot be read (${e.code})`);
    return;
  }
  entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const rel = `${folder}/${entry.name}`;
    if (entry.isDirectory()) {
      problems.push(`${rel}: a folder inside ${folder}/ is not read; scenarios are files directly in ${folder}/`);
    } else if (!entry.name.endsWith('.json')) {
      problems.push(`${rel}: only .json files and dotfiles belong in ${folder}/`);
    } else {
      files.push({ folder, rel, base: entry.name.slice(0, -'.json'.length), full: path.join(full, entry.name) });
    }
  }
}

export function loadScenarios(dir) {
  const problems = [];
  const files = [];
  const scenarios = { all: [], byName: new Map(), byMockKey: new Map(), prompts: [] };
  let top;
  try {
    top = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    problems.push(`the scenarios folder cannot be read (${e.code})`);
    return { scenarios, problems };
  }
  for (const entry of top) {
    if (entry.name.startsWith('.')) continue;
    if (!FOLDERS.includes(entry.name) || !entry.isDirectory()) {
      problems.push(`${entry.name}: only the folders ${FOLDERS.join(' and ')} belong in the scenarios folder`);
    }
  }
  for (const folder of FOLDERS) listFolder(dir, folder, problems, files);

  const seenNames = new Map();
  const seenKeys = new Map();
  const seenPrompts = new Map();
  for (const f of files) {
    const bad = (msg) => problems.push(msg);
    let data;
    try {
      data = JSON.parse(fs.readFileSync(f.full, 'utf8'));
    } catch (e) {
      bad(`${f.rel}: not valid JSON (${e.message})`);
      continue;
    }
    const before = problems.length;
    checkScenario(f.rel, f.folder, f.base, data, bad);
    if (problems.length !== before) continue;
    const scenario = { name: data.name, match: data.match, replies: data.replies, file: f.rel, folder: f.folder };
    if (seenNames.has(scenario.name)) {
      bad(`${f.rel}: the name "${scenario.name}" repeats the one of ${seenNames.get(scenario.name)}`);
      continue;
    }
    if (Object.hasOwn(scenario.match, 'mockkey')) {
      const key = scenario.match.mockkey;
      if (seenKeys.has(key)) {
        bad(`${f.rel}: the mock key "${key}" repeats the one of ${seenKeys.get(key)}`);
        continue;
      }
      seenKeys.set(key, f.rel);
      scenarios.byMockKey.set(key, scenario);
    }
    if (Object.hasOwn(scenario.match, 'prompt')) {
      const prompt = scenario.match.prompt;
      if (seenPrompts.has(prompt)) {
        bad(`${f.rel}: the prompt repeats the one of ${seenPrompts.get(prompt)}`);
        continue;
      }
      seenPrompts.set(prompt, f.rel);
      scenarios.prompts.push({ prompt, scenario });
    }
    seenNames.set(scenario.name, f.rel);
    scenarios.byName.set(scenario.name, scenario);
    scenarios.all.push(scenario);
  }
  for (const a of scenarios.prompts) {
    for (const b of scenarios.prompts) {
      if (a !== b && a.prompt.includes(b.prompt)) {
        problems.push(`${a.scenario.file}: its prompt contains the prompt of ${b.scenario.file}`);
      }
    }
  }
  return { scenarios, problems };
}
