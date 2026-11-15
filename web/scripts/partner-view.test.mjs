// Tests of the Partner contacts section's rules and texts (Story 24.2): the accepted texts byte for byte, both halves of the help line, the productions' boxes, the
// body of a save and of a removal, the dirty rule, and the text of each refused field. The module is framework-free, so Node runs it as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { SETTINGS_TEXTS } = await import(app('settings', 'settings-view.ts'));
const { PARTNER_FIELDS, emptyPartnerForm, fieldErrorText, isPartnerDirty, partnerBody, partnerFormOf, productionKey, productionOptions, removeBody, removeQuestion } = await import(
  app('settings', 'partner-view.ts')
);

const ORDERS = { namespace: 'OCUORDERS', production: 'OcuTalon.Demo.Orders.Production' };
const OTHER = { namespace: 'OCUTALON', production: 'Zz.Other.Production' };
const ROSTER = [
  { ...ORDERS, displayName: 'Orders' },
  { ...OTHER, displayName: 'Other' },
];
const CONTACT = { ref: 'zzref0123456789abcdefg', name: 'Orders Partner IT', email: 'it@orders-partner.example', productions: [ORDERS] };

describe('the accepted texts', () => {
  it('are shown byte for byte (EXPERIENCE.md, Settings (step 5))', () => {
    assert.equal(SETTINGS_TEXTS.sections.partners, 'Partner contacts');
    assert.deepEqual(SETTINGS_TEXTS.partners, {
      help: 'Partner warnings go only to the people listed here, and only after you approve each one.',
      name: 'Name',
      email: 'Email address',
      productions: 'Productions it concerns',
      add: 'Add contact',
      remove: 'Remove',
      removeConfirm: 'Remove {name}? Partner warnings will stop going to {address}.',
      badName: 'Enter a name of 1 to 128 characters. Nothing was changed.',
      noProduction: 'Choose at least one production. Nothing was changed.',
      offOnDemo: 'Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install.',
    });
  });

  it('say both halves of the help line: warnings go only to the listed people, and only after each one is approved', () => {
    const help = SETTINGS_TEXTS.partners.help;
    assert.match(help, /^Partner warnings go only to the people listed here, /);
    assert.match(help, /, and only after you approve each one\.$/);
  });

  it('do not include the refused "not yet" line', () => {
    assert.equal('notYet' in SETTINGS_TEXTS.partners, false);
    assert.equal(JSON.stringify(SETTINGS_TEXTS).includes('Partner contacts are not'), false);
  });

  it('reuse the On call section\'s address error, and the shared save, saved, failed and cancel texts', () => {
    assert.equal(fieldErrorText('email'), 'Enter an email address such as name@example.com. Nothing was changed.');
    assert.equal(SETTINGS_TEXTS.save, 'Save changes');
    assert.equal(SETTINGS_TEXTS.saved, 'Saved. Applies within a minute. Recorded in the audit log.');
    assert.equal(SETTINGS_TEXTS.failed, "Couldn't save. Nothing was changed.");
  });
});

describe('the fields and their texts', () => {
  it('are the three fields of the body, in the form\'s order', () => {
    assert.deepEqual([...PARTNER_FIELDS], ['name', 'email', 'productions']);
  });

  it('give each refused field its accepted text', () => {
    assert.equal(fieldErrorText('name'), 'Enter a name of 1 to 128 characters. Nothing was changed.');
    assert.equal(fieldErrorText('productions'), 'Choose at least one production. Nothing was changed.');
  });

  it('word the Remove question with the contact\'s name and address, once each, whatever they hold', () => {
    assert.equal(removeQuestion(CONTACT), 'Remove Orders Partner IT? Partner warnings will stop going to it@orders-partner.example.');
    assert.equal(removeQuestion({ ...CONTACT, name: '{address} $& $1', email: 'a@b.example' }), 'Remove {address} $& $1? Partner warnings will stop going to a@b.example.');
  });
});

describe('the productions\' boxes', () => {
  it('list the roster in its order, labelled by display name', () => {
    assert.deepEqual(
      productionOptions(ROSTER, []).map((option) => [option.label, option.namespace, option.production]),
      [
        ['Orders', 'OCUORDERS', 'OcuTalon.Demo.Orders.Production'],
        ['Other', 'OCUTALON', 'Zz.Other.Production'],
      ],
    );
  });

  it('keep a production that a contact still names but the roster no longer lists, labelled by its production', () => {
    const gone = { namespace: 'ZZNS', production: 'Zz.Gone' };
    const options = productionOptions(ROSTER, [ORDERS, gone]);
    assert.deepEqual(options.map((option) => option.label), ['Orders', 'Other', 'Zz.Gone']);
    assert.equal(options.filter((option) => option.production === ORDERS.production).length, 1, 'a listed one is not repeated');
  });

  it('are none for an empty roster and no stored production', () => {
    assert.deepEqual(productionOptions([], []), []);
  });

  it('key a production by its namespace and production, so that the same production in two namespaces is two boxes', () => {
    assert.notEqual(productionKey({ namespace: 'A', production: 'P' }), productionKey({ namespace: 'B', production: 'P' }));
    assert.notEqual(productionKey({ namespace: 'A.B', production: 'C' }), productionKey({ namespace: 'A', production: 'B.C' }));
  });
});

describe('the body of a save and of a removal', () => {
  it('is the form\'s name, address and ticked productions, in the boxes\' order, with the ref ("" for a new contact)', () => {
    const options = productionOptions(ROSTER, []);
    const form = { name: 'Zed', email: 'zed@example.com', picked: [productionKey(OTHER), productionKey(ORDERS)] };
    assert.deepEqual(partnerBody('', form, options), { action: 'save', ref: '', name: 'Zed', email: 'zed@example.com', productions: [ORDERS, OTHER] });
    assert.deepEqual(partnerBody(CONTACT.ref, form, options).ref, CONTACT.ref);
  });

  it('sends what was typed, so that the server decides what is valid', () => {
    const body = partnerBody('', { name: '', email: 'nope', picked: [] }, productionOptions(ROSTER, []));
    assert.deepEqual(body, { action: 'save', ref: '', name: '', email: 'nope', productions: [] });
  });

  it('holds only the action and the ref for a removal', () => {
    assert.deepEqual(removeBody(CONTACT.ref), { action: 'remove', ref: CONTACT.ref });
  });
});

describe('the dirty rule', () => {
  const saved = partnerFormOf(CONTACT);

  it('starts from a stored contact\'s values and from an empty form', () => {
    assert.deepEqual(saved, { name: CONTACT.name, email: CONTACT.email, picked: [productionKey(ORDERS)] });
    assert.deepEqual(emptyPartnerForm(), { name: '', email: '', picked: [] });
    assert.equal(isPartnerDirty(saved, saved), false);
    assert.equal(isPartnerDirty(emptyPartnerForm(), emptyPartnerForm()), false);
  });

  it('ignores the white space around a name or an address, and the order of the ticked productions', () => {
    assert.equal(isPartnerDirty({ ...saved, name: `  ${CONTACT.name} `, email: ` ${CONTACT.email}` }, saved), false);
    const two = { ...saved, picked: [productionKey(ORDERS), productionKey(OTHER)] };
    assert.equal(isPartnerDirty({ ...two, picked: [productionKey(OTHER), productionKey(ORDERS)] }, two), false);
  });

  it('is dirty for a changed name, address or set of productions', () => {
    assert.equal(isPartnerDirty({ ...saved, name: 'Other' }, saved), true);
    assert.equal(isPartnerDirty({ ...saved, email: 'x@example.com' }, saved), true);
    assert.equal(isPartnerDirty({ ...saved, picked: [] }, saved), true);
    assert.equal(isPartnerDirty({ ...saved, picked: [productionKey(OTHER)] }, saved), true);
    assert.equal(isPartnerDirty({ ...saved, picked: [productionKey(ORDERS), productionKey(OTHER)] }, saved), true);
    assert.equal(isPartnerDirty({ ...emptyPartnerForm(), name: 'x' }, emptyPartnerForm()), true);
  });
});
