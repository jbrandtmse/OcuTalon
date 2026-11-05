// Tests of the settings page's view model (Story 33.2): the sections and their order, the addresses, the Check thresholds' rules and the Demo step's
// text. The module is framework-free, so Node runs it as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const view = await import(pathToFileURL(join(here, '..', 'src', 'app', 'settings', 'settings-view.ts')).href);
const { SETTINGS_TEXTS, SETTINGS_SECTIONS, THRESHOLD_FIELDS, bodyOf, firstInError, isDirty, pageOf, sectionLabel, sectionPath, sectionSlug, settingsMatch, stepFailedText, textsOf } = view;

const DEFAULTS = { diskFreePercent: 10, journalFreePercent: 10, licenseUsePercent: 90, queueMessages: 100, queueWaitMinutes: 10 };

describe('the sections', () => {
  it('are the seven of the UX, in its order, each with a slug of its own', () => {
    assert.deepEqual(
      SETTINGS_SECTIONS.map((section) => section.label),
      ['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'Demo mode'],
    );
    assert.deepEqual(
      SETTINGS_SECTIONS.map((section) => section.slug),
      ['models', 'budgets', 'channels', 'daily-digest', 'time-zone', 'check-thresholds', 'demo-mode'],
    );
    assert.equal(new Set(SETTINGS_SECTIONS.map((section) => section.slug)).size, 7);
  });

  it('open Models for an unknown or a missing address part', () => {
    for (const part of [undefined, null, '', 'zz', 'Models', 'check-thresholds/', '..']) {
      assert.equal(sectionSlug(part), 'models', `'${part}'`);
    }
    for (const section of SETTINGS_SECTIONS) {
      assert.equal(sectionSlug(section.slug), section.slug);
      assert.equal(sectionLabel(section.slug), section.label);
    }
    assert.equal(sectionLabel('zz'), 'Models');
    assert.deepEqual(sectionPath('budgets'), ['/settings', 'budgets']);
  });
});

describe('the page of an address', () => {
  it('is settings for /settings and below it, whatever the query, the matrix parameters or the hash mark', () => {
    for (const address of ['/settings', '/settings/budgets', '#/settings', '#/settings/demo-mode', '/settings;x=1', '/settings?x=1', '/settings/budgets#top']) {
      assert.equal(pageOf(address), 'settings', address);
    }
  });

  it('is the chat for every other address', () => {
    for (const address of ['', '/', '#/', '/settingsx', '/Settings', '/other/settings', '/chat', '#']) {
      assert.equal(pageOf(address), 'chat', address);
    }
  });
});

describe('the Check thresholds form', () => {
  it('has the five fields of the UX, with the ranges of the server', () => {
    assert.deepEqual(
      THRESHOLD_FIELDS.map((field) => [field.name, field.min, field.max]),
      [
        ['diskFreePercent', 1, 100],
        ['journalFreePercent', 1, 100],
        ['licenseUsePercent', 1, 100],
        ['queueMessages', 1, 1000000],
        ['queueWaitMinutes', 1, 1000000],
      ],
    );
    assert.deepEqual(
      THRESHOLD_FIELDS.map((field) => field.label),
      [
        'Disk free space below (%)',
        'Journal free space below (%)',
        'License use above (%)',
        'Queue backlog above (messages)',
        'Oldest queued message waiting over (minutes)',
      ],
    );
  });

  it('sends a number for digits and the text as typed otherwise, so the server decides', () => {
    const texts = { diskFreePercent: ' 15 ', journalFreePercent: 'abc', licenseUsePercent: '95', queueMessages: '', queueWaitMinutes: '@{env:X}' };
    assert.deepEqual(bodyOf(texts), { diskFreePercent: 15, journalFreePercent: 'abc', licenseUsePercent: 95, queueMessages: '', queueWaitMinutes: '@{env:X}' });
    assert.deepEqual(Object.keys(bodyOf(textsOf(DEFAULTS))), THRESHOLD_FIELDS.map((field) => field.name));
  });

  it('is dirty when a text differs from the saved one, not for white space around it', () => {
    const saved = textsOf(DEFAULTS);
    assert.equal(isDirty(saved, saved), false);
    assert.equal(isDirty({ ...saved, diskFreePercent: ' 10 ' }, saved), false);
    assert.equal(isDirty({ ...saved, diskFreePercent: '11' }, saved), true);
    assert.equal(isDirty({ ...saved, queueWaitMinutes: '' }, saved), true);
  });

  it('names the first field in error in the form\'s order', () => {
    const order = THRESHOLD_FIELDS.map((field) => field.name);
    assert.equal(firstInError(['queueMessages', 'diskFreePercent'], order), 'diskFreePercent');
    assert.equal(firstInError(['zz'], order), undefined);
    assert.equal(firstInError([], order), undefined);
  });
});

describe('the texts', () => {
  it('give the Demo step\'s text for the value that was written, never "Nothing was changed."', () => {
    assert.equal(stepFailedText(true), "Demo mode is set to on, but the switch didn't finish. OcuTalon tries again at its next start.");
    assert.equal(stepFailedText(false), "Demo mode is set to off, but the switch didn't finish. OcuTalon tries again at its next start.");
    assert.ok(!stepFailedText(true).includes('Nothing was changed'));
  });

  it('are the UX\'s sentences where the UX writes them', () => {
    assert.equal(SETTINGS_TEXTS.title, 'Settings \u00B7 OcuTalon');
    assert.equal(SETTINGS_TEXTS.saved, 'Saved. Applies within a minute. Recorded in the audit log.');
    assert.equal(SETTINGS_TEXTS.failed, "Couldn't save. Nothing was changed.");
    assert.equal(SETTINGS_TEXTS.denied, 'Only OcuTalon admins can open settings.');
    assert.equal(SETTINGS_TEXTS.save, 'Save changes');
  });
});

describe('the routes', () => {
  const config = readFileSync(join(here, '..', 'src', 'app', 'app.config.ts'), 'utf8');

  it('open the settings page at #/settings and at #/settings/:section as one route, before the wildcard, titled and guarded against leaving with unsaved changes', () => {
    const settings = [...config.matchAll(/\{ matcher: settingsMatch, component: SettingsPage, title: SETTINGS_TEXTS\.title, canDeactivate: \[unsavedGuard\] \}/g)];
    assert.equal(settings.length, 1, 'one settings route, with the matcher, the title and the unsaved-changes guard');
    assert.doesNotMatch(config, /path: 'settings/, 'no second settings route, which would build the page again on a section change');
    assert.ok(config.indexOf('matcher: settingsMatch') < config.indexOf("path: '**'"), 'the wildcard comes last');
    assert.match(config, /\{ path: '\*\*', component: MainPage, title: 'OcuTalon' \}/, 'the wildcard is titled OcuTalon');
    assert.match(config, /withRouterConfig\(\{ canceledNavigationResolution: 'computed' \}\)/, 'a cancelled back keeps the history as it was');
  });

  it('match #/settings and #/settings/<section>, and nothing else', () => {
    const at = (...paths) => paths.map((path) => ({ path }));
    assert.deepEqual(settingsMatch(at('settings')), { consumed: at('settings'), posParams: {} });
    const two = at('settings', 'budgets');
    assert.deepEqual(settingsMatch(two), { consumed: two, posParams: { section: two[1] } });
    for (const paths of [[], ['chat'], ['Settings'], ['settings', 'budgets', 'x'], ['x', 'settings']]) {
      assert.equal(settingsMatch(at(...paths)), null, paths.join('/'));
    }
  });
});
