// Tests of the Tools and MCP servers section's view rules (Story 21.4; mcp-view.ts) and of its fixed strings (MCP_TEXTS): the online demo's line is the accepted wording of the
// Message Catalog key settings.mcpOffOnDemo (src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls); the Remove sentence has the forms of T7; the filter, the body of an add and
// the classification of a refused or failed call are the section's rules.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { SETTINGS_SECTIONS, SETTINGS_TEXTS } = await import(app('settings', 'settings-view.ts'));
const { addBody, CLASSIFICATION_OPTIONS, classificationName, MCP_TEXTS, mcpOutcome, removeName, removeQuestion, statusText, toolKey, toolStatusText, visibleTools, withClassification } = await import(
  app('settings', 'mcp-view.ts')
);
const core = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Msg', 'Catalog', 'Core.cls'), 'utf8');

/** The text of a catalog key of Core.cls, as the XData holds it (JSON escapes undone). */
function catalogText(key) {
  const match = core.match(new RegExp(`"${key.replace('.', '\\.')}": \\{\\s*"text": ("(?:[^"\\\\]|\\\\.)*")`));
  assert.ok(match, `${key} is in the Core catalog`);
  return JSON.parse(match[1]);
}

describe('the section in the page\'s navigation', () => {
  it('is the eighth section, last, with the slug mcp', () => {
    assert.equal(SETTINGS_SECTIONS.length, 8);
    assert.deepEqual(SETTINGS_SECTIONS[7], { slug: 'mcp', label: 'Tools and MCP servers' });
    assert.equal(SETTINGS_TEXTS.sections.mcp, 'Tools and MCP servers');
  });
});

describe('the section\'s fixed strings', () => {
  it('say what the online demo shows in the words of the catalog key, and none of the secret handling is a string of the page', () => {
    assert.equal(MCP_TEXTS.offOnDemo, catalogText('settings.mcpOffOnDemo'));
  });

  it('are the accepted texts T2 to T5 and T8', () => {
    assert.deepEqual([MCP_TEXTS.servers, MCP_TEXTS.tools], ['Servers', 'Tools']);
    assert.deepEqual(Object.values(MCP_TEXTS.columns), ['Server', 'Address', 'Status', 'Tools', 'Unclassified']);
    assert.equal(MCP_TEXTS.noServers, 'No MCP servers yet.');
    assert.deepEqual(Object.values(MCP_TEXTS.status), ['Connected', 'Unavailable', 'Not checked yet']);
    assert.equal(MCP_TEXTS.statusHelp, "A new server's tools show here once OcuTalon next uses its agents. They count as risky until you classify them.");
    assert.deepEqual(Object.values(MCP_TEXTS.form).slice(0, 3), ['Name', 'Address', 'Secret (optional)']);
    assert.equal(MCP_TEXTS.form.secretHelp, 'Sent to the server with every request. It is kept in the IRIS Wallet and never shown again.');
    assert.deepEqual(Object.values(MCP_TEXTS.toolColumns), ['Tool', 'Server', 'Status', 'Classification']);
    assert.deepEqual(Object.values(MCP_TEXTS.toolStatus), ['Available', 'Unavailable', 'Refused: a built-in tool has this name']);
    assert.equal(MCP_TEXTS.noTools, 'No tools yet.');
    assert.equal(MCP_TEXTS.noUnclassified, 'No unclassified tools.');
    assert.equal(MCP_TEXTS.unclassifiedOnly, 'Unclassified only');
  });

  it('list the three classifications in the order of the radiogroup, with the labels of the story', () => {
    assert.deepEqual(
      CLASSIFICATION_OPTIONS.map((option) => [option.value, option.label]),
      [
        ['unclassified', 'Unclassified (counts as risky)'],
        ['read-only', 'Read-only'],
        ['risky', 'Risky'],
      ],
    );
    assert.equal(MCP_TEXTS.saved, 'Saved');
  });

  it('give the accessible names of T10 and T11', () => {
    assert.equal(classificationName('search', 'Jira'), 'Classification of search on Jira');
    assert.equal(removeName('Jira'), 'Remove Jira');
    assert.equal(removeName('a$&b'), 'Remove a$&b', 'a name is put in as it is');
  });
});

describe('removeQuestion', () => {
  it('is the accepted sentence of the story for Jira with 12 tools and 1 pending request', () => {
    assert.equal(removeQuestion('Jira', 12, 1), 'Remove Jira? Its 12 tools go at once, and 1 pending approval request for them is canceled.');
  });

  it('has the three forms for more than one tool', () => {
    assert.equal(removeQuestion('Jira', 12, 0), 'Remove Jira? Its 12 tools go at once.');
    assert.equal(removeQuestion('Jira', 2, 3), 'Remove Jira? Its 2 tools go at once, and 3 pending approval requests for them are canceled.');
  });

  it('has the three forms for one tool', () => {
    assert.equal(removeQuestion('Jira', 1, 0), 'Remove Jira? Its 1 tool goes at once.');
    assert.equal(removeQuestion('Jira', 1, 1), 'Remove Jira? Its 1 tool goes at once, and 1 pending approval request for it is canceled.');
    assert.equal(removeQuestion('Jira', 1, 4), 'Remove Jira? Its 1 tool goes at once, and 4 pending approval requests for it are canceled.');
  });

  it('has the three forms for no tool', () => {
    assert.equal(removeQuestion('Jira', 0, 0), 'Remove Jira? It has no tools.');
    assert.equal(removeQuestion('Jira', 0, 1), 'Remove Jira? 1 pending approval request for its tools is canceled.');
    assert.equal(removeQuestion('Jira', 0, 2), 'Remove Jira? 2 pending approval requests for its tools are canceled.');
  });

  it('puts a name that holds a replacement pattern in as it is', () => {
    assert.equal(removeQuestion('a$&b', 3, 0), 'Remove a$&b? Its 3 tools go at once.');
    assert.equal(removeQuestion('{n}', 3, 2), 'Remove {n}? Its 3 tools go at once, and 2 pending approval requests for them are canceled.');
  });
});

describe('the status words', () => {
  it('turn attached, unavailable and never checked into the words of T4', () => {
    assert.equal(statusText('attached'), 'Connected');
    assert.equal(statusText('unavailable'), 'Unavailable');
    assert.equal(statusText(''), 'Not checked yet');
    assert.equal(statusText('anything else'), 'Not checked yet');
  });

  it('turn a tool\'s status into the words of T8, and show nothing for a word it does not know', () => {
    assert.equal(toolStatusText('available'), 'Available');
    assert.equal(toolStatusText('unavailable'), 'Unavailable');
    assert.equal(toolStatusText('refused'), 'Refused: a built-in tool has this name');
    assert.equal(toolStatusText('weird'), '');
  });
});

describe('visibleTools', () => {
  const tools = [
    { server: 'a', name: 'one', classification: 'unclassified' },
    { server: 'a', name: 'two', classification: 'read-only' },
    { server: 'b', name: 'one', classification: 'risky' },
    { server: 'b', name: 'three', classification: 'unclassified' },
  ];

  it('lists every tool with the filter off', () => {
    assert.deepEqual(visibleTools(tools, false), tools);
  });

  it('lists only the unclassified tools with the filter on', () => {
    assert.deepEqual(
      visibleTools(tools, true).map((tool) => `${tool.server}/${tool.name}`),
      ['a/one', 'b/three'],
    );
  });

  it('keeps a row that was classified since the section opened, and only that server\'s tool of that name', () => {
    assert.deepEqual(
      visibleTools(tools, true, new Set([toolKey('b', 'one')])).map((tool) => `${tool.server}/${tool.name}`),
      ['a/one', 'b/one', 'b/three'],
    );
  });
});

describe('addBody', () => {
  it('trims the name and the address and leaves the secret out when none was typed', () => {
    assert.deepEqual(addBody(' Jira ', ' https://x.example/mcp ', ''), { name: 'Jira', address: 'https://x.example/mcp' });
  });

  it('sends the secret as it was typed, spaces and all (the server judges it)', () => {
    assert.deepEqual(addBody('Jira', 'https://x.example/mcp', ' s e '), { name: 'Jira', address: 'https://x.example/mcp', secret: ' s e ' });
  });
});

describe('mcpOutcome', () => {
  const bad = (fields) => ({ error: { code: 'bad_mcp_server', message: "Couldn't save. Nothing was changed." }, fields });

  it('is denied for a 403', () => {
    assert.deepEqual(mcpOutcome(403, { error: { code: 'not_admin', message: 'x' } }), { kind: 'denied' });
    assert.deepEqual(mcpOutcome(403, null), { kind: 'denied' });
  });

  it('is off for a 409 not_available only', () => {
    assert.deepEqual(mcpOutcome(409, { error: { code: 'not_available', message: 'x' } }), { kind: 'off' });
    assert.deepEqual(mcpOutcome(409, { error: { code: 'other', message: 'x' } }), { kind: 'form', message: 'x' });
    assert.deepEqual(mcpOutcome(409, undefined), { kind: 'form', message: '' });
  });

  it('takes the text of each refused field of a 400 bad_mcp_server', () => {
    assert.deepEqual(mcpOutcome(400, bad({ name: 'A.', address: 'B.', secret: 'C.' })), { kind: 'fields', name: 'A.', address: 'B.', secret: 'C.' });
    assert.deepEqual(mcpOutcome(400, bad({ address: 'B.' })), { kind: 'fields', name: '', address: 'B.', secret: '' });
    assert.deepEqual(mcpOutcome(400, bad({ secret: 'C.' })), { kind: 'fields', name: '', address: '', secret: 'C.' });
  });

  it('is a form error with the server\'s message for a 400 that names no field, or the wrong kind of field, and for every other answer', () => {
    const message = "Couldn't save. Nothing was changed.";
    assert.deepEqual(mcpOutcome(400, bad({})), { kind: 'form', message });
    assert.deepEqual(mcpOutcome(400, bad({ name: 5, secret: null })), { kind: 'form', message });
    assert.deepEqual(mcpOutcome(400, bad(undefined)), { kind: 'form', message });
    assert.deepEqual(mcpOutcome(400, { error: { code: 'bad_settings' }, fields: { name: 'x' } }), { kind: 'form', message: '' });
    assert.deepEqual(mcpOutcome(404, { error: { code: 'not_found', message: 'Gone.' } }), { kind: 'form', message: 'Gone.' });
    assert.deepEqual(mcpOutcome(500, { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } }), {
      kind: 'form',
      message: 'Something went wrong inside OcuTalon. Try again.',
    });
    assert.deepEqual(mcpOutcome(0, null), { kind: 'form', message: '' });
  });
});

describe('withClassification', () => {
  const settings = {
    servers: [
      { name: 'a', address: 'x', status: 'attached', tools: 2, unclassified: 2, pending: 0 },
      { name: 'b', address: 'y', status: '', tools: 1, unclassified: 1, pending: 0 },
    ],
    tools: [
      { server: 'a', name: 'one', classification: 'unclassified', status: 'available' },
      { server: 'a', name: 'two', classification: 'unclassified', status: 'available' },
      { server: 'b', name: 'one', classification: 'unclassified', status: 'available' },
    ],
  };

  it('changes one tool of one server and works out that server\'s unclassified count again', () => {
    const next = withClassification(settings, 'a', 'one', 'read-only');
    assert.deepEqual(next.tools.map((tool) => tool.classification), ['read-only', 'unclassified', 'unclassified']);
    assert.deepEqual(next.servers.map((server) => server.unclassified), [1, 1]);
    assert.equal(settings.tools[0].classification, 'unclassified', 'the settings it was given are not changed');
  });

  it('puts the old value back', () => {
    const there = withClassification(settings, 'a', 'one', 'risky');
    assert.deepEqual(withClassification(there, 'a', 'one', 'unclassified'), settings);
  });
});
