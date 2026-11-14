// Tests of the On call section's rules and texts (Story 36.4): the accepted texts byte for byte, the person and the Page by boxes of each role, the body of a
// save, the dirty rule and the text of each refused field. The module is framework-free, so Node runs it as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { SETTINGS_TEXTS } = await import(app('settings', 'settings-view.ts'));
const { ONCALL_FIELDS, ONCALL_ROLES, defaultChannels, fieldErrorText, isOnCallDirty, onCallBody, onCallFormOf, parsePerson, personOf, personOptions, personValue, telegramState } = await import(
  app('settings', 'on-call-view.ts')
);

const USERS = [
  { user: 'alice', paired: true },
  { user: 'bob', paired: false },
];

/** The server's values with nobody chosen, then the changes. */
const values = (changes = {}) => ({
  primaryUser: '',
  primaryEmail: '',
  primaryChannels: 'telegram,email',
  backupUser: '',
  backupEmail: '',
  backupChannels: 'telegram,email',
  escalationMinutes: 15,
  users: USERS,
  pagesBuilt: true,
  ...changes,
});

describe('the accepted texts', () => {
  it('are shown byte for byte (EXPERIENCE.md, Settings (step 5))', () => {
    assert.equal(SETTINGS_TEXTS.sections.onCall, 'On call');
    assert.deepEqual(SETTINGS_TEXTS.onCall, {
      help: 'Choose who OcuTalon pages when an incident starts, and who it pages next if nobody presses Got it in time.',
      notYet: "OcuTalon doesn't send pages yet. It keeps these choices for when it does.",
      primary: 'On-call person',
      backup: 'Backup',
      person: 'Person',
      nobody: 'Nobody',
      byEmail: 'Someone else, by email',
      byEmailHelp: "Someone paged by email can't press Got it, so OcuTalon also pages the backup after the minutes below.",
      email: 'Email address for pages',
      channels: 'Page by',
      telegram: 'Telegram',
      channelEmail: 'Email',
      telegramUnpaired: "{user} hasn't paired Telegram, so OcuTalon can't message them there yet. They can pair it on their own OcuTalon page.",
      telegramEmailOnly: 'Telegram needs an OcuTalon user with a paired chat.',
      minutes: 'Minutes before paging the backup',
      minutesHelp: '15 unless you change it.',
      badEmail: 'Enter an email address such as name@example.com. Nothing was changed.',
      badMinutes: 'Enter a whole number of minutes from 1 to 1440. Nothing was changed.',
      noChannel: 'Choose a way to reach this person: Telegram needs a paired chat, email needs an address. Nothing was changed.',
      unknownUser: "{user} isn't an OcuTalon user any more. Choose again. Nothing was changed.",
      offOnDemo: "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.",
    });
  });
});

describe('the fields', () => {
  it('are the seven of the form in its order, which is where focus goes first', () => {
    assert.deepEqual([...ONCALL_FIELDS], ['primaryUser', 'primaryEmail', 'primaryChannels', 'backupUser', 'backupEmail', 'backupChannels', 'escalationMinutes']);
    assert.deepEqual([...ONCALL_ROLES], ['primary', 'backup']);
  });
});

describe('the person', () => {
  it('is a user when a user is stored, else someone by email when an address is, else nobody', () => {
    assert.equal(personOf('', ''), 'nobody');
    assert.equal(personOf('', 'a@x.io'), 'email');
    assert.equal(personOf('alice', ''), 'user');
    assert.equal(personOf('alice', 'a@x.io'), 'user');
  });

  it('is chosen by a select value in which no user name can be mistaken for a choice', () => {
    assert.equal(personValue({ person: 'nobody', user: '', email: '', telegram: true, mail: true }), 'nobody');
    assert.equal(personValue({ person: 'email', user: '', email: '', telegram: false, mail: true }), 'email');
    assert.equal(personValue({ person: 'user', user: 'alice', email: '', telegram: true, mail: true }), 'user:alice');
    assert.deepEqual(parsePerson('user:alice'), { person: 'user', user: 'alice' });
    assert.deepEqual(parsePerson('user:email'), { person: 'user', user: 'email' }, 'a user called email is a user');
    assert.deepEqual(parsePerson('user:nobody'), { person: 'user', user: 'nobody' }, 'and so is one called nobody');
    assert.deepEqual(parsePerson('email'), { person: 'email', user: '' });
    assert.deepEqual(parsePerson('nobody'), { person: 'nobody', user: '' });
    assert.deepEqual(parsePerson('zz'), { person: 'nobody', user: '' }, 'an unknown value is nobody');
  });

  it('is listed as Nobody, each user, then Someone else by email, and a stored user who has no session row stays listed', () => {
    assert.deepEqual(personOptions(USERS, ''), [
      { value: 'nobody', label: 'Nobody' },
      { value: 'user:alice', label: 'alice' },
      { value: 'user:bob', label: 'bob' },
      { value: 'email', label: 'Someone else, by email' },
    ]);
    assert.deepEqual(
      personOptions(USERS, 'gone').map((option) => option.label),
      ['Nobody', 'alice', 'bob', 'gone', 'Someone else, by email'],
    );
    assert.deepEqual(
      personOptions(USERS, 'bob').map((option) => option.label),
      ['Nobody', 'alice', 'bob', 'Someone else, by email'],
      'a stored user the list holds is listed once',
    );
  });
});

describe('Telegram', () => {
  it('can be chosen only for a user whose chat is paired', () => {
    assert.deepEqual(telegramState('user', 'alice', USERS), { kind: 'enabled' });
  });

  it("is disabled for a user who hasn't paired, with the accepted text for that user", () => {
    assert.deepEqual(telegramState('user', 'bob', USERS), {
      kind: 'unpaired',
      text: "bob hasn't paired Telegram, so OcuTalon can't message them there yet. They can pair it on their own OcuTalon page.",
    });
  });

  it('is not judged for a user the list does not hold, so the server decides at save', () => {
    assert.equal(telegramState('user', 'gone', USERS).kind, 'enabled', 'a user the list does not hold is not judged');
    assert.deepEqual(telegramState('user', 'alice', []), { kind: 'enabled' }, 'nor is any user while the list is empty');
    assert.equal(telegramState('user', 'bob', USERS).kind, 'unpaired', 'a listed user without a paired chat is still unpaired');
  });

  it('is disabled for a person by email, with its own text', () => {
    assert.deepEqual(telegramState('email', '', USERS), { kind: 'emailOnly', text: 'Telegram needs an OcuTalon user with a paired chat.' });
  });

  it('is not judged for nobody, whose boxes are hidden', () => {
    assert.deepEqual(telegramState('nobody', '', USERS), { kind: 'enabled' });
  });

  it('starts checked with Email for a paired user and for nobody, and with Email alone where it cannot be chosen', () => {
    assert.deepEqual(defaultChannels('nobody', false), { telegram: true, mail: true });
    assert.deepEqual(defaultChannels('user', true), { telegram: true, mail: true });
    assert.deepEqual(defaultChannels('user', false), { telegram: false, mail: true });
    assert.deepEqual(defaultChannels('email', false), { telegram: false, mail: true });
    assert.deepEqual(defaultChannels('email', true), { telegram: false, mail: true });
  });
});

describe('the form', () => {
  it('reads nobody from nothing stored, with the minutes as text and both default boxes', () => {
    assert.deepEqual(onCallFormOf(values()), {
      primary: { person: 'nobody', user: '', email: '', telegram: true, mail: true },
      backup: { person: 'nobody', user: '', email: '', telegram: true, mail: true },
      minutes: '15',
    });
  });

  it('reads a user, an address and the stored channels', () => {
    const form = onCallFormOf(values({ primaryUser: 'alice', primaryEmail: 'a@x.io', primaryChannels: 'email', backupEmail: 'b@x.io', backupChannels: 'email', escalationMinutes: 20 }));
    assert.deepEqual(form.primary, { person: 'user', user: 'alice', email: 'a@x.io', telegram: false, mail: true });
    assert.deepEqual(form.backup, { person: 'email', user: '', email: 'b@x.io', telegram: false, mail: true });
    assert.equal(form.minutes, '20');
  });

  it('shows no checked Telegram box that cannot be chosen now', () => {
    const form = onCallFormOf(values({ primaryUser: 'bob', primaryChannels: 'telegram,email', backupEmail: 'b@x.io', backupChannels: 'telegram,email' }));
    assert.equal(form.primary.telegram, false, 'a user who has unpaired since');
    assert.equal(form.backup.telegram, false, 'and a person by email');
    assert.equal(onCallFormOf(values({ primaryUser: 'alice', primaryChannels: 'telegram,email' })).primary.telegram, true, 'a paired user keeps it');
  });

  it('keeps the stored boxes of a user the list does not hold', () => {
    const gone = onCallFormOf(values({ primaryUser: 'gone', primaryChannels: 'telegram,email' }));
    assert.equal(gone.primary.telegram, true, 'a stored user the list lacks keeps Telegram');
    assert.equal(gone.primary.mail, true);
    assert.equal(onCallFormOf(values({ primaryUser: 'bob', primaryChannels: 'telegram,email' })).primary.telegram, false, 'bob, listed and unpaired, still reads false');
  });

  it("keeps both roles' stored boxes, and sends them, while the list is unavailable", () => {
    const form = onCallFormOf(
      values({ users: [], primaryUser: 'alice', primaryChannels: 'telegram,email', backupUser: 'gone', backupEmail: 'g@x.io', backupChannels: 'telegram,email' }),
    );
    assert.equal(form.primary.telegram, true, 'the primary keeps Telegram');
    assert.equal(form.backup.telegram, true, 'the backup keeps Telegram');
    const body = onCallBody(form);
    assert.equal(body.primaryChannels, 'telegram,email');
    assert.equal(body.backupChannels, 'telegram,email');
  });

  it('judges the backup by the list as it judges the on-call person, whoever the other role is', () => {
    const unpaired = onCallFormOf(values({ backupUser: 'bob', backupChannels: 'telegram,email' }));
    assert.equal(unpaired.primary.person, 'nobody', 'the on-call person is nobody');
    assert.equal(unpaired.backup.telegram, false, 'a backup the list shows unpaired has Telegram unchecked');
    assert.equal(onCallBody(unpaired).backupChannels, 'email', 'and a save sends Email alone');
    const gone = onCallFormOf(values({ backupUser: 'gone', backupChannels: 'telegram,email' }));
    assert.equal(gone.backup.telegram, true, 'a backup the list lacks keeps Telegram');
    assert.equal(onCallBody(gone).backupChannels, 'telegram,email', 'and a save sends both boxes');
    assert.equal(onCallFormOf(values({ backupUser: 'alice', backupChannels: 'telegram,email' })).backup.telegram, true, 'a paired backup keeps it');
  });

  it('keeps a stored Telegram-only channel of a user the list does not hold, with Email unchecked, and sends it alone', () => {
    const form = onCallFormOf(values({ users: [], primaryUser: 'alice', primaryChannels: 'telegram', backupUser: 'gone', backupEmail: 'g@x.io', backupChannels: 'telegram' }));
    for (const role of [form.primary, form.backup]) {
      assert.equal(role.telegram, true, 'Telegram stays checked');
      assert.equal(role.mail, false, 'and Email stays unchecked');
    }
    const body = onCallBody(form);
    assert.equal(body.primaryChannels, 'telegram', 'the on-call person is sent with Telegram alone');
    assert.equal(body.backupChannels, 'telegram', 'and so is the backup');
  });
});

describe('the body of a save', () => {
  it('names each person and sends nobody as the defaults, whatever the hidden boxes hold', () => {
    const form = onCallFormOf(values());
    form.primary.email = 'left@x.io';
    form.primary.telegram = false;
    assert.deepEqual(onCallBody(form), {
      primaryPerson: 'nobody',
      primaryUser: '',
      primaryEmail: '',
      primaryChannels: 'telegram,email',
      backupPerson: 'nobody',
      backupUser: '',
      backupEmail: '',
      backupChannels: 'telegram,email',
      escalationMinutes: 15,
    });
  });

  it('sends a user with the typed address trimmed and the checked boxes in the order telegram, email', () => {
    const form = onCallFormOf(values({ primaryUser: 'alice', primaryEmail: 'a@x.io', backupEmail: 'b@x.io', backupChannels: 'email', escalationMinutes: 20 }));
    form.primary.email = '  a@x.io ';
    assert.deepEqual(onCallBody(form), {
      primaryPerson: 'user',
      primaryUser: 'alice',
      primaryEmail: 'a@x.io',
      primaryChannels: 'telegram,email',
      backupPerson: 'email',
      backupUser: '',
      backupEmail: 'b@x.io',
      backupChannels: 'email',
      escalationMinutes: 20,
    });
    form.primary.telegram = false;
    assert.equal(onCallBody(form).primaryChannels, 'email');
    form.primary.mail = false;
    assert.equal(onCallBody(form).primaryChannels, '', 'with no box checked the body names no channel, which the server refuses');
  });

  it('sends the minutes as a number when they are digits, else as typed, so that the server refuses them', () => {
    const form = onCallFormOf(values());
    for (const [typed, sent] of [['20', 20], [' 20 ', 20], ['0', 0], ['1441', 1441], ['15.5', '15.5'], ['abc', 'abc'], ['', ''], ['-3', '-3'], ['1234567890', '1234567890']]) {
      form.minutes = typed;
      assert.strictEqual(onCallBody(form).escalationMinutes, sent, JSON.stringify(typed));
    }
  });
});

describe('the dirty rule', () => {
  const saved = () => onCallFormOf(values({ primaryUser: 'alice', primaryEmail: 'a@x.io', backupEmail: 'b@x.io', backupChannels: 'email' }));

  it('is clean for the saved form, for white space around a value, and for what a nobody hides', () => {
    const form = saved();
    assert.equal(isOnCallDirty(form, saved()), false);
    form.primary.email = ' a@x.io ';
    form.minutes = ' 15 ';
    assert.equal(isOnCallDirty(form, saved()), false);
    const nobody = onCallFormOf(values());
    nobody.backup.email = 'zz@x.io';
    nobody.backup.telegram = false;
    assert.equal(isOnCallDirty(nobody, onCallFormOf(values())), false);
  });

  it('is dirty for a changed person, address, box or minutes', () => {
    const changes = [
      (form) => (form.primary.user = 'bob'),
      (form) => (form.primary.person = 'nobody'),
      (form) => (form.primary.email = 'c@x.io'),
      (form) => (form.primary.telegram = false),
      (form) => (form.primary.mail = false),
      (form) => (form.backup.email = 'c@x.io'),
      (form) => (form.backup.person = 'user'),
      (form) => (form.backup.mail = false),
      (form) => (form.minutes = '16'),
    ];
    for (const [index, change] of changes.entries()) {
      const form = saved();
      change(form);
      assert.equal(isOnCallDirty(form, saved()), true, `change ${index}`);
    }
  });
});

describe('a refused field', () => {
  it('shows its own accepted text, and the unknown user text names the role\'s user', () => {
    const form = onCallFormOf(values({ primaryUser: 'gone', backupUser: 'also-gone' }));
    assert.equal(fieldErrorText('primaryUser', form), "gone isn't an OcuTalon user any more. Choose again. Nothing was changed.");
    assert.equal(fieldErrorText('backupUser', form), "also-gone isn't an OcuTalon user any more. Choose again. Nothing was changed.");
    for (const name of ['primaryEmail', 'backupEmail']) {
      assert.equal(fieldErrorText(name, form), 'Enter an email address such as name@example.com. Nothing was changed.', name);
    }
    for (const name of ['primaryChannels', 'backupChannels']) {
      assert.equal(fieldErrorText(name, form), 'Choose a way to reach this person: Telegram needs a paired chat, email needs an address. Nothing was changed.', name);
    }
    assert.equal(fieldErrorText('escalationMinutes', form), 'Enter a whole number of minutes from 1 to 1440. Nothing was changed.');
  });

  it('has a text for every field that the form can have refused', () => {
    const form = onCallFormOf(values());
    for (const name of ONCALL_FIELDS) {
      assert.ok(fieldErrorText(name, form).endsWith('Nothing was changed.'), name);
    }
  });
});
