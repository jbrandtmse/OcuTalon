// Tests of the Slack group's view rules (Story 27.3; slack-view.ts), of its fixed strings and the chat caption, and of how its code is loaded: the strings are the approved
// wording of the Message Catalog keys (src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls), the member ID check, the classification of a refused or failed call, the list's
// view, and the lazy chunk (the Channels section imports the group with a dynamic import and nothing else).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { SLACK_TEXTS, memberIdProblem, slackOutcome, slackState } = await import(app('settings', 'slack-view.ts'));
const { CHAT_TEXTS } = await import(app('chat', 'chat-view.ts'));
const core = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Msg', 'Catalog', 'Core.cls'), 'utf8');

/** The text of a catalog key of Core.cls, as the XData holds it (JSON escapes undone). */
function catalogText(key) {
  const match = core.match(new RegExp(`"${key.replace('.', '\\.')}": \\{\\s*"text": ("(?:[^"\\\\]|\\\\.)*")`));
  assert.ok(match, `${key} is in the Core catalog`);
  return JSON.parse(match[1]);
}

describe('the group\'s fixed strings', () => {
  it('are the texts of the catalog keys, word for word', () => {
    const keys = {
      heading: 'settings.slackHeading',
      notSetUp: 'settings.slackNotSetUp',
      howTo: 'settings.slackHowTo',
      on: 'settings.slackOn',
      address: 'settings.slackAddress',
      offOnDemo: 'settings.slackOffOnDemo',
      membersHeading: 'settings.slackMembersHeading',
      membersHelp: 'settings.slackMembersHelp',
      memberId: 'settings.slackMemberId',
      memberUser: 'settings.slackMemberUser',
      link: 'settings.slackLink',
      unlink: 'settings.slackUnlink',
      noMembers: 'settings.slackNoMembers',
      badMemberId: 'settings.slackBadMemberId',
      memberTaken: 'settings.slackMemberTaken',
      userTaken: 'settings.slackUserTaken',
      linked: 'settings.slackLinked',
      unlinked: 'settings.slackUnlinked',
      noWorkspace: 'settings.slackNoWorkspace',
      unknownUser: 'settings.slackUnknownUser',
    };
    assert.deepEqual(Object.keys(SLACK_TEXTS).sort(), Object.keys(keys).sort(), 'every string of the group has a key, and every key a string');
    for (const [name, key] of Object.entries(keys)) {
      assert.equal(SLACK_TEXTS[name], catalogText(key), `${name} is ${key}`);
    }
  });

  it('give the chat caption of a Slack turn, word for word', () => {
    assert.equal(CHAT_TEXTS.viaSlack, catalogText('chat.viaSlack'));
    assert.equal(CHAT_TEXTS.viaSlack, 'via Slack');
  });
});

describe('memberIdProblem', () => {
  it('accepts a U or W and 2 to 31 letters or digits, after trimming and upper-casing', () => {
    for (const ok of ['U012AB3CDE', 'W012AB3CDE', 'u012ab3cde', '  U012AB3CDE  ', 'UAB', 'U' + 'A'.repeat(31)]) {
      assert.equal(memberIdProblem(ok), '', ok);
    }
  });

  it('answers the text of slackBadMemberId for anything else', () => {
    for (const bad of ['', '   ', 'U', 'UA', 'U' + 'A'.repeat(32), 'T012AB3CDE', 'U012-AB3CDE', 'U012 AB3CDE', '012AB3CDE', 'U01\u00E9AB']) {
      assert.equal(memberIdProblem(bad), SLACK_TEXTS.badMemberId, JSON.stringify(bad));
    }
  });
});

describe('slackOutcome', () => {
  const refused = (message, fields, reason) => ({ error: { code: 'bad_slack_link', message }, fields, reason });

  it('is denied for a 403', () => {
    assert.deepEqual(slackOutcome(403, { error: { code: 'not_admin', message: 'x' } }), { kind: 'denied' });
    assert.deepEqual(slackOutcome(403, null), { kind: 'denied' });
  });

  it('is off for a 409 not_available only', () => {
    assert.deepEqual(slackOutcome(409, { error: { code: 'not_available', message: 'x' } }), { kind: 'off' });
    assert.deepEqual(slackOutcome(409, { error: { code: 'other', message: 'x' } }), { kind: 'failed' });
    assert.deepEqual(slackOutcome(409, undefined), { kind: 'failed' });
  });

  it('shows the text of a 400 bad_slack_link under the field it names, or under the form when it names none', () => {
    assert.deepEqual(slackOutcome(400, refused('Taken.', ['member'], 'member_taken')), { kind: 'field', field: 'member', text: 'Taken.' });
    assert.deepEqual(slackOutcome(400, refused('Has one.', ['user'], 'user_taken')), { kind: 'field', field: 'user', text: 'Has one.' });
    assert.deepEqual(slackOutcome(400, refused('No workspace.', [], 'no_workspace')), { kind: 'form', text: 'No workspace.' });
    assert.deepEqual(slackOutcome(400, refused('No fields.', undefined, 'x')), { kind: 'form', text: 'No fields.' });
  });

  it('is failed for a 400 of another kind or with no text, and for every other answer', () => {
    assert.deepEqual(slackOutcome(400, { error: { code: 'bad_settings', message: 'x' }, fields: ['member'] }), { kind: 'failed' });
    assert.deepEqual(slackOutcome(400, refused('', ['member'], 'x')), { kind: 'failed' });
    assert.deepEqual(slackOutcome(400, refused(5, ['member'], 'x')), { kind: 'failed' });
    assert.deepEqual(slackOutcome(404, { error: { code: 'not_found' } }), { kind: 'failed' });
    assert.deepEqual(slackOutcome(500, { error: { code: 'server_error' } }), { kind: 'failed' });
    assert.deepEqual(slackOutcome(0, null), { kind: 'failed' });
  });
});

describe('slackState', () => {
  const links = [{ ref: 'r1', user: 'sam', member: 'U012AB3CDE' }];

  it('is on only when the server says on, and carries the path, the members and the users', () => {
    assert.deepEqual(slackState({ state: 'on', path: '/ocutalon/hook/slack/events', links, users: ['sam', 'pat'] }), { on: true, path: '/ocutalon/hook/slack/events', members: links, users: ['sam', 'pat'] });
    assert.equal(slackState({ state: 'off', path: '/p', links: [], users: [] }).on, false);
    assert.equal(slackState({ state: 'ON', path: '/p', links: [], users: [] }).on, false);
  });
});

describe('the lazy chunk', () => {
  const channels = readFileSync(join(here, '..', 'src', 'app', 'settings', 'channels-section.ts'), 'utf8');

  it('is never imported statically by the Channels section', () => {
    assert.doesNotMatch(channels, /^\s*import\b[^;]*from\s+'\.\/slack-section'/m);
    assert.doesNotMatch(channels, /^\s*import\s+'\.\/slack-section'/m);
  });

  it('is imported once, with a dynamic import', () => {
    assert.equal([...channels.matchAll(/\bimport\('\.\/slack-section'\)/g)].length, 1);
    assert.match(channels, /host\.createComponent\(loaded\.SlackSection\)/);
  });
});
