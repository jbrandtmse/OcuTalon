// Tests of the constants that the CI model mock shares with the product (Story 0.11, row 16 of the I/O matrix): the agents'
// MOCKKEY values, the tool names of OcuTalon.Tools.Names, the compaction prefix and the summary schema, read from the sources
// in src/ and from the committed scenarios. Every file read here must match WEB_INPUT_PATTERN of ci/units.sh, so that a change
// to it runs the web job. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { SUMMARIZER_PREFIX } from '../mock.mjs';
import { loadScenarios } from '../scenarios.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..', '..');
const SUMMARY_KEYS = ['user_goals', 'constraints', 'decisions', 'facts_learned', 'tool_actions', 'open_questions', 'next_steps'];

function rel(full) {
  return path.relative(ROOT, full).split(path.sep).join('/');
}

function listClasses(dir) {
  if (!fs.existsSync(dir)) return [];
  const found = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...listClasses(full));
    else if (entry.name.endsWith('.cls')) found.push(full);
  }
  return found.sort();
}

// readAll(): everything that the tests compare, and the repository-relative path of every file it read.
function readAll() {
  const filesRead = [];
  const read = (full) => {
    filesRead.push(rel(full));
    return fs.readFileSync(full, 'utf8');
  };
  const agents = [];
  const sources = [
    ...listClasses(path.join(ROOT, 'src/ocutalon/cls/OcuTalon/Agent')).filter((f) => path.dirname(f) === path.join(ROOT, 'src/ocutalon/cls/OcuTalon/Agent')),
    ...listClasses(path.join(ROOT, 'src/bridge/cls/OcuTalon/BridgeExample')),
  ];
  for (const full of sources) {
    const m = /^Parameter MOCKKEY = "([^"]*)";/m.exec(read(full));
    if (m) agents.push({ file: rel(full), key: m[1] });
  }
  const names = {};
  for (const m of read(path.join(ROOT, 'src/ocutalon/cls/OcuTalon/Tools/Names.cls')).matchAll(/^Parameter ([A-Z0-9]+) = "([^"]*)";/gm)) {
    if (m[1] !== 'RELEASE1') names[m[1]] = m[2];
  }
  const prefix = /^Parameter PREFIX = "([^"]*)";/m.exec(read(path.join(ROOT, 'src/bridge/cls/OcuTalon/Bridge/Compaction.cls')));
  const unitsText = read(path.join(ROOT, 'ci/units.sh'));
  const pattern = /^WEB_INPUT_PATTERN='([^']*)'$/m.exec(unitsText);
  const { scenarios, problems } = loadScenarios(path.join(ROOT, 'ci/mock/scenarios'));
  for (const s of scenarios.all) filesRead.push(`ci/mock/scenarios/${s.file}`);
  return { agents, toolNames: Object.values(names), prefix: prefix && prefix[1], pattern: pattern && pattern[1], scenarios, problems, filesRead };
}

function toolUseNames(scenario) {
  const out = [];
  for (const reply of scenario.replies) {
    if (!Object.hasOwn(reply, 'toolUse')) continue;
    for (const use of Array.isArray(reply.toolUse) ? reply.toolUse : [reply.toolUse]) out.push(use.name);
  }
  return out;
}

test('row 16: each agent MOCKKEY has exactly one mockkey scenario, and each mockkey scenario names an agent', () => {
  const { agents, scenarios, problems } = readAll();
  assert.deepEqual(problems, []);
  for (const key of ['chat', 'diagnosis', 'triage']) assert.ok(agents.some((a) => a.key === key), `the agent classes of Story 0.6 include the MOCKKEY ${key}`);
  assert.equal(new Set(agents.map((a) => a.key)).size, agents.length, 'the MOCKKEY values of the agent classes are distinct');
  const scenarioKeys = scenarios.all.filter((s) => Object.hasOwn(s.match, 'mockkey')).map((s) => s.match.mockkey);
  for (const agent of agents) {
    assert.equal(scenarioKeys.filter((k) => k === agent.key).length, 1, `${agent.file}: MOCKKEY ${agent.key}`);
  }
  for (const key of scenarioKeys) assert.ok(agents.some((a) => a.key === key), `a mockkey scenario ${key} names no agent`);
});

test('row 16: the tool names of the default scripts and of the summary are values of OcuTalon.Tools.Names', () => {
  const { toolNames, scenarios } = readAll();
  assert.ok(toolNames.length >= 11, `OcuTalon.Tools.Names holds ${toolNames.length} tool names`);
  assert.equal(new Set(toolNames).size, toolNames.length, 'the tool names are distinct');
  let used = 0;
  for (const s of scenarios.all.filter((x) => Object.hasOwn(x.match, 'mockkey'))) {
    for (const name of toolUseNames(s)) {
      used += 1;
      assert.ok(toolNames.includes(name), `${s.file}: ${name}`);
    }
  }
  assert.ok(used >= 2, 'the default scripts call tools');
  const summary = JSON.parse(scenarios.byName.get('summary').replies[0].text);
  for (const action of summary.tool_actions) assert.ok(toolNames.includes(action.tool), `summary: ${action.tool}`);
});

test("row 16: the mock's summarizer prefix is Bridge.Compaction's PREFIX", () => {
  const { prefix } = readAll();
  assert.equal(prefix, 'OCUTALON-COMPACTION-V1');
  assert.equal(SUMMARIZER_PREFIX, prefix);
});

test('row 16: summary parses to the seven schema keys with a fact and a tool action; summary-off-schema does not', () => {
  const { scenarios } = readAll();
  const text = scenarios.byName.get('summary').replies[0].text;
  const summary = JSON.parse(text);
  assert.deepEqual(Object.keys(summary), SUMMARY_KEYS);
  assert.ok(Array.isArray(summary.facts_learned) && summary.facts_learned.length >= 1);
  assert.ok(Array.isArray(summary.tool_actions) && summary.tool_actions.length >= 1);
  for (const action of summary.tool_actions) assert.equal(typeof action.tool, 'string');
  assert.equal(text.includes('\n'), false, 'one line of JSON');
  const off = scenarios.byName.get('summary-off-schema').replies[0].text;
  let parsed = null;
  try {
    parsed = JSON.parse(off);
  } catch {
    parsed = null;
  }
  assert.ok(parsed === null || typeof parsed !== 'object' || !SUMMARY_KEYS.every((k) => Object.hasOwn(parsed, k)));
});

test('row 16: every file that these tests read matches WEB_INPUT_PATTERN', () => {
  const { pattern, filesRead } = readAll();
  assert.ok(pattern, 'ci/units.sh defines WEB_INPUT_PATTERN');
  const re = new RegExp(pattern);
  assert.ok(filesRead.length >= 20, `read ${filesRead.length} files`);
  for (const file of ['src/ocutalon/cls/OcuTalon/Agent/Triage.cls', 'src/ocutalon/cls/OcuTalon/Tools/Names.cls', 'src/bridge/cls/OcuTalon/Bridge/Compaction.cls', 'ci/units.sh']) {
    assert.ok(filesRead.includes(file), `${file} was read`);
  }
  for (const file of filesRead) assert.ok(re.test(file), `${file} does not match WEB_INPUT_PATTERN`);
  assert.equal(re.test('src/ocutalon/cls/OcuTalon/Tools/Result.cls'), false);
});
