// Tests of the Roles section's view rules (Story 25.4; roles-view.ts) and of its fixed strings (ROLES_TEXTS): the strings are the ruled PUBLIC TEXT of the story, equal to
// the parameters of Web.RoleSettings that the server answers the same refusals with (read from the class source), and the classification of a refused or failed call.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { ASSIGNABLE, ROLES_REASONS, ROLES_TEXTS, heldAssignable, removeLabel, roleOutcome, saveLine } = await import(app('settings', 'roles-view.ts'));
const { SETTINGS_TEXTS } = await import(app('settings', 'settings-view.ts'));
const section = readFileSync(join(here, '..', 'src', 'app', 'settings', 'roles-section.ts'), 'utf8');
const server = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Web', 'RoleSettings.cls'), 'utf8');

/** The text of a Parameter of Web.RoleSettings, as the class source holds it. */
function parameter(name) {
  const match = server.match(new RegExp(`Parameter ${name} = "((?:[^"\\\\]|\\\\.)*)";`));
  assert.ok(match, `${name} is a parameter of Web.RoleSettings`);
  return JSON.parse(`"${match[1]}"`);
}

describe('the section\'s fixed strings', () => {
  it('are the ruled PUBLIC TEXT, word for word', () => {
    assert.equal(ROLES_TEXTS.heading, 'Roles');
    assert.equal(
      ROLES_TEXTS.intro,
      "Approvers can answer the approval requests that reach them, for every kind of risky action. Viewers can open OcuTalon but can't chat, answer or change anything.",
    );
    assert.equal(ROLES_TEXTS.perKind, 'An approver role for one kind, such as OcuTalonApprover_resend, is granted in IRIS.');
    assert.equal(ROLES_TEXTS.listHeading, 'People with an OcuTalon role');
    assert.equal(ROLES_TEXTS.empty, 'No IRIS user holds an OcuTalon role yet.');
    assert.equal(ROLES_TEXTS.managed, 'Managed by OcuTalon');
    assert.equal(ROLES_TEXTS.userLabel, 'IRIS user name');
    assert.equal(ROLES_TEXTS.roleLabel, 'Role');
    assert.equal(ROLES_TEXTS.approverOption, 'Approver (all risky actions)');
    assert.equal(ROLES_TEXTS.viewerOption, 'Viewer (read-only)');
    assert.equal(ROLES_TEXTS.grant, 'Grant');
    assert.equal(ROLES_TEXTS.removeApprover, 'Remove approver');
    assert.equal(ROLES_TEXTS.removeViewer, 'Remove viewer');
    assert.equal(ROLES_TEXTS.loadFailed, "Couldn't load the roles.");
    assert.equal(ROLES_TEXTS.retry, 'Retry');
    assert.equal(ROLES_TEXTS.off, "Roles can't be changed on the online demo.");
    assert.equal(ROLES_TEXTS.noChange, "No change: {user}'s roles are already as you set them.");
  });

  it('name the section like the navigation does, and reuse the page\'s saved, failed and denied texts', () => {
    assert.equal(SETTINGS_TEXTS.sections.roles, ROLES_TEXTS.heading);
    assert.equal(SETTINGS_TEXTS.saved, 'Saved. Applies within a minute. Recorded in the audit log.');
    assert.equal(SETTINGS_TEXTS.failed, "Couldn't save. Nothing was changed.");
    assert.equal(SETTINGS_TEXTS.denied, 'Only OcuTalon admins can open settings.');
  });

  it('give each refusal reason the text that the server answers it with', () => {
    assert.equal(ROLES_REASONS.role, parameter('MESSAGEREASONROLE'));
    assert.equal(ROLES_REASONS.user_unknown, parameter('MESSAGEREASONUNKNOWN'));
    assert.equal(ROLES_REASONS.user_managed, parameter('MESSAGEREASONMANAGED'));
    assert.equal(ROLES_REASONS.user_system, parameter('MESSAGEREASONSYSTEM'));
    assert.equal(ROLES_TEXTS.off, parameter('MESSAGEROLESOFF'));
    assert.deepEqual(Object.keys(ROLES_REASONS).sort(), ['role', 'user_managed', 'user_system', 'user_unknown']);
  });
});

describe('the two assignable roles', () => {
  it('are the approver and the viewer, in the select\'s order, with their option and button texts', () => {
    assert.deepEqual(
      ASSIGNABLE.map((one) => [one.role, one.option, one.remove]),
      [
        ['OcuTalonApprover', 'Approver (all risky actions)', 'Remove approver'],
        ['OcuTalonViewer', 'Viewer (read-only)', 'Remove viewer'],
      ],
    );
  });

  it('name the user in the accessible name of each Remove button', () => {
    assert.equal(removeLabel(ASSIGNABLE[0], 'ZzTarget'), 'Remove approver from ZzTarget');
    assert.equal(removeLabel(ASSIGNABLE[1], 'ZzTarget'), 'Remove viewer from ZzTarget');
  });

  it('are the only roles that get a Remove button: a per-kind role and the user role get none', () => {
    assert.deepEqual(heldAssignable(['OcuTalonApprover', 'OcuTalonApprover_resend', 'OcuTalonUser', 'OcuTalonViewer']).map((one) => one.role), ['OcuTalonApprover', 'OcuTalonViewer']);
    assert.deepEqual(heldAssignable(['OcuTalonApprover_resend', 'OcuTalonUser']), []);
    assert.deepEqual(heldAssignable([]), []);
  });
});

describe('roleOutcome', () => {
  it('is denied for a 403 and off for a 409 not_available', () => {
    assert.deepEqual(roleOutcome(403, { error: { code: 'not_admin' } }), { kind: 'denied' });
    assert.deepEqual(roleOutcome(403, null), { kind: 'denied' });
    assert.deepEqual(roleOutcome(409, { error: { code: 'not_available' } }), { kind: 'off' });
  });

  it('is the text of the reason for a 400 that names one', () => {
    for (const [reason, text] of Object.entries(ROLES_REASONS)) {
      assert.deepEqual(roleOutcome(400, { error: { code: 'bad_settings' }, fields: ['user'], reason }), { kind: 'refused', reason, text }, reason);
    }
  });

  it('is failed for everything else', () => {
    assert.deepEqual(roleOutcome(400, { error: { code: 'bad_settings' }, fields: ['user'], reason: '' }), { kind: 'failed' }, 'a 400 with no reason');
    assert.deepEqual(roleOutcome(400, { reason: 'zz' }), { kind: 'failed' }, 'a reason the page does not know');
    assert.deepEqual(roleOutcome(400, { reason: 'toString' }), { kind: 'failed' }, 'a reason that is a property of every object');
    assert.deepEqual(roleOutcome(409, { error: { code: 'other' } }), { kind: 'failed' }, 'a 409 that is not not_available');
    for (const status of [0, 401, 404, 500, 501, 503]) {
      assert.deepEqual(roleOutcome(status, { error: { code: 'server_error' } }), { kind: 'failed' }, String(status));
    }
    assert.deepEqual(roleOutcome(500, 'text'), { kind: 'failed' });
    assert.deepEqual(roleOutcome(400, undefined), { kind: 'failed' });
  });
});

describe('saveLine', () => {
  const SAVED = SETTINGS_TEXTS.saved;

  it('is the saved text when the roles changed', () => {
    assert.deepEqual(saveLine({ changed: true }, 'ZzTarget', SAVED), { changed: true, text: SAVED });
  });

  it('is the no-change text, with the user\'s name, when the roles did not change: a role already held that was granted, or one not held that was removed', () => {
    assert.deepEqual(saveLine({ changed: false }, 'ZzTarget', SAVED), { changed: false, text: "No change: ZzTarget's roles are already as you set them." });
  });

  it('keeps the name as it is, whatever characters it holds', () => {
    assert.equal(saveLine({ changed: false }, '<b>$&x</b>', SAVED).text, "No change: <b>$&x</b>'s roles are already as you set them.");
  });

  it('counts an answer that does not say changed false as a change', () => {
    assert.equal(saveLine({}, 'ZzTarget', SAVED).changed, true);
    assert.equal(saveLine(null, 'ZzTarget', SAVED).changed, true);
    assert.equal(saveLine(undefined, 'ZzTarget', SAVED).changed, true);
  });
});

describe('the section\'s saved line', () => {
  it('comes from saveLine for the accepted answer, is announced once, and is drawn as text, never as HTML', () => {
    assert.match(section, /const shown = saveLine\(answer, user, SETTINGS_TEXTS\.saved\);/);
    assert.match(section, /this\.announcer\.announce\(shown\.text\);/);
    assert.match(section, /\{\{ shown\.text \}\}/);
    assert.doesNotMatch(section, /innerHTML|bypassSecurityTrust/);
  });
});
