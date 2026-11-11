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
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { RAIL_TEXTS } = await import(app('rail', 'rail-view.ts'));
const { TELEGRAM_CARD_TEXTS, telegramCardView, telegramPaused } = await import(app('rail', 'telegram-card', 'telegram-card-view.ts'));
const {
  SETTINGS_TEXTS,
  SETTINGS_SECTIONS,
  THRESHOLD_FIELDS,
  bodyOf,
  channelsView,
  digestBody,
  digestChannelBoxes,
  digestChannelsBody,
  budgetsBody,
  firstInError,
  isBudgetsDirty,
  isDigestDirty,
  isDigestFormDirty,
  isDirty,
  isModelsDirty,
  modelOptions,
  modelsBody,
  modelsFieldNames,
  modelsFormOf,
  modelsValuesOf,
  modelsView,
  noKeyReason,
  pageOf,
  providerLabel,
  refusalKind,
  secondOptions,
  secondValue,
  splitSecond,
  testResultText,
  sectionLabel,
  sectionPath,
  sectionSlug,
  settingsMatch,
  stepFailedText,
  storedChannels,
  telegramBoxShown,
  textsOf,
  zoneBody,
  zoneOptions,
} = view;

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

  it('is documents for /documents, whatever the query, the matrix parameters or the hash mark (Story 34.2)', () => {
    for (const address of ['/documents', '#/documents', '/documents;x=1', '/documents?x=1', '/documents#top']) {
      assert.equal(pageOf(address), 'documents', address);
    }
  });

  it('is usage for /usage, whatever the query, the matrix parameters or the hash mark (Story 37.2)', () => {
    for (const address of ['/usage', '#/usage', '/usage;x=1', '/usage?x=1', '/usage#top']) {
      assert.equal(pageOf(address), 'usage', address);
    }
  });

  it('is history for /history, whatever the query, the matrix parameters or the hash mark (Story 25.2)', () => {
    for (const address of ['/history', '#/history', '/history;x=1', '/history?x=1', '/history?tab=incidents&page=2', '/history#top']) {
      assert.equal(pageOf(address), 'history', address);
    }
  });

  it('is the chat for every other address', () => {
    for (const address of ['', '/', '#/', '/settingsx', '/Settings', '/other/settings', '/chat', '#', '/documentsx', '/Documents', '/other/documents', '/documents/x', '/usagex', '/Usage', '/other/usage', '/usage/x', '/historyx', '/History', '/other/history', '/history/x']) {
      assert.equal(pageOf(address), 'chat', address);
    }
    assert.equal(pageOf('/settings/documents'), 'settings', 'a section named documents is still the settings page');
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
    assert.equal(
      SETTINGS_TEXTS.demoSaved,
      'Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change.',
    );
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

describe('the Time zone section (Story 18.2)', () => {
  it('lists the empty Server default first, then the browser zones, then UTC (which a browser list may leave out)', () => {
    const options = zoneOptions(['Africa/Cairo', 'Asia/Kolkata'], '');
    assert.deepEqual(options, [
      { value: '', label: 'Server default' },
      { value: 'Africa/Cairo', label: 'Africa/Cairo' },
      { value: 'Asia/Kolkata', label: 'Asia/Kolkata' },
      { value: 'UTC', label: 'UTC' },
    ]);
    assert.deepEqual(zoneOptions(['Africa/Cairo', 'UTC'], '').map((option) => option.value), ['', 'Africa/Cairo', 'UTC'], 'UTC is not listed twice');
  });

  it('keeps the stored zone in the list when the browser does not know it, right after the Server default', () => {
    const options = zoneOptions(['Africa/Cairo', 'Asia/Kolkata'], 'Etc/Unknown');
    assert.deepEqual(
      options.map((option) => option.value),
      ['', 'Etc/Unknown', 'Africa/Cairo', 'Asia/Kolkata', 'UTC'],
    );
    assert.equal(options.filter((option) => option.value === 'Asia/Kolkata').length, 1, 'a stored zone that the browser has is not listed twice');
    assert.deepEqual(zoneOptions(['Asia/Kolkata'], 'Asia/Kolkata').map((option) => option.value), ['', 'Asia/Kolkata', 'UTC']);
    assert.deepEqual(zoneOptions([], '').map((option) => option.value), ['', 'UTC']);
    assert.deepEqual(zoneOptions([], 'UTC').map((option) => option.value), ['', 'UTC'], 'a stored UTC is the listed UTC');
  });

  it('saves {InstanceZone} and nothing else, "" for the Server default', () => {
    assert.deepEqual(zoneBody('Europe/Berlin'), { InstanceZone: 'Europe/Berlin' });
    assert.deepEqual(zoneBody(''), { InstanceZone: '' });
  });
});

describe('the Daily digest section (Story 18.2)', () => {
  it('shows the web chat always, the simulated phone only in demo mode and Telegram only when it is shown', () => {
    assert.deepEqual(digestChannelBoxes(false, false), ['web']);
    assert.deepEqual(digestChannelBoxes(true, false), ['web', 'phone']);
    assert.deepEqual(digestChannelBoxes(false, true), ['web', 'telegram']);
    assert.deepEqual(digestChannelBoxes(true, true), ['web', 'phone', 'telegram']);
  });

  it('shows the Telegram box while Telegram is included and on, or paused, and not otherwise', () => {
    assert.equal(telegramBoxShown({ included: true, state: 'on' }, false), true);
    assert.equal(telegramBoxShown({ included: true, state: 'off' }, true), true, 'paused (a restart during a pause records off)');
    assert.equal(telegramBoxShown({ included: true, state: 'off' }, false), false);
    assert.equal(telegramBoxShown({ included: true, state: 'rejected' }, false), false);
    assert.equal(telegramBoxShown({ included: false, state: 'on' }, false), false, 'a release without Telegram');
    assert.equal(telegramBoxShown({ included: false, state: 'off' }, true), false);
    assert.equal(telegramBoxShown(undefined, false), false);
  });

  it('keeps a hidden channel as it is stored, and writes the channels in the order web, phone, telegram', () => {
    assert.equal(digestChannelsBody('web,phone', ['web'], ['web']), 'web,phone', 'demo mode off: the hidden phone stays');
    assert.equal(digestChannelsBody('web,phone', ['web'], []), '', 'unchecking the only shown box sends no channel (the server refuses it) rather than saving the hidden phone alone');
    assert.equal(digestChannelsBody('web,phone', ['web', 'phone'], ['phone']), 'phone', 'a shown box that stays checked keeps its channel');
    assert.equal(digestChannelsBody('web', ['web'], ['web']), 'web', 'a hidden channel that was not stored stays out');
    assert.equal(digestChannelsBody('phone,web', ['web', 'phone'], ['phone', 'web']), 'web,phone', 'the order is always web, phone, telegram');
    assert.equal(digestChannelsBody('telegram,web', ['web'], ['web']), 'web,telegram', 'a hidden Telegram keeps its stored state');
    assert.equal(digestChannelsBody('web,phone,telegram', ['web', 'phone', 'telegram'], ['telegram']), 'telegram');
    assert.equal(digestChannelsBody('web', ['web'], []), '', 'no channel at all is sent as it is, and the server refuses it');
    assert.equal(digestChannelsBody(' Telegram , WEB ,fax', ['phone'], ['phone']), 'web,phone,telegram', 'a stored value is read trimmed and lowercased, and a name that is no channel is dropped');
  });

  it('reads the stored channels as the channels they name', () => {
    assert.deepEqual(storedChannels('phone, WEB,fax,,web'), ['web', 'phone']);
    assert.deepEqual(storedChannels(''), []);
  });

  it('builds the body from the trimmed time and the channels', () => {
    assert.deepEqual(digestBody(' 07:30 ', 'web,phone'), { time: '07:30', channels: 'web,phone' });
  });

  it('is dirty when the time or a channel differs from the saved values', () => {
    const saved = { time: '08:00', channels: 'web,phone' };
    assert.equal(isDigestDirty({ time: '08:00', channels: 'web,phone' }, saved), false);
    assert.equal(isDigestDirty({ time: ' 08:00 ', channels: 'phone, web' }, saved), false, 'white space and order do not count');
    assert.equal(isDigestDirty({ time: '08:01', channels: 'web,phone' }, saved), true);
    assert.equal(isDigestDirty({ time: '08:00', channels: 'web' }, saved), true);
  });

  it('keeps the form clean on open when the saved channels are hidden ones, and dirty only for an edit of a shown box or the time', () => {
    const phoneOnly = { time: '08:00', channels: 'phone' };
    assert.equal(isDigestFormDirty('08:00', ['phone'], ['web'], phoneOnly), false, 'demo mode off, phone saved: nothing was edited');
    assert.equal(isDigestFormDirty('08:00', ['phone', 'web'], ['web'], phoneOnly), true, 'checking the web chat is an edit');
    assert.equal(isDigestFormDirty('08:30', ['phone'], ['web'], phoneOnly), true, 'so is a new time');
    assert.equal(isDigestFormDirty('08:00', ['web'], ['web', 'phone'], { time: '08:00', channels: 'web,phone' }), true, 'unchecking a shown box is an edit');
  });

  it('pins the ruled texts of the section, byte for byte', () => {
    const texts = SETTINGS_TEXTS.dailyDigest;
    assert.equal(texts.sendAt, 'Send at');
    assert.equal(texts.help, "In the instance's time zone. Applies from the next digest.");
    assert.equal(texts.sendTo, 'Send to');
    assert.equal(texts.web, 'The web chat');
    assert.equal(texts.phone, 'The simulated phone');
    assert.equal(texts.telegram, 'Telegram');
    assert.equal(texts.sendNow, 'Send my digest now');
    assert.equal(texts.sendNowDone, 'Sending your digest now.');
    assert.equal(texts.sendNowFailed, "Couldn't send your digest. Try again.");
  });

  it('pins the ruled texts of the Time zone section, byte for byte', () => {
    assert.equal(SETTINGS_TEXTS.timeZone.label, 'Time zone');
    assert.equal(
      SETTINGS_TEXTS.timeZone.help,
      "Message times, reminders, the daily digest and the current time that OcuTalon gives the model use this zone. Times on this page stay in your browser's zone.",
    );
    assert.equal(SETTINGS_TEXTS.timeZone.serverDefault, 'Server default');
  });
});

describe('the Channels section (Story 18.2)', () => {
  const NOW = { code: undefined, refused: false, justUnpaired: false, now: 0 };
  const FORMAT = { time: (iso) => iso.slice(11, 16) };
  const telegram = (state, extra = {}) => ({ included: true, state, botUserName: 'bot', paired: false, displayName: '', pausedUntil: '', ...extra });
  const paused = { telegramPaused: { active: true, slots: { time: '2026-11-08T14:30:00Z' } } };
  const viewOf = (block, status) => {
    const card = telegramCardView(block, status, NOW, FORMAT);
    return channelsView(block.included, card.kind, card.retry);
  };

  it('says "not set up" while the bot is off or was rejected', () => {
    assert.deepEqual(viewOf(telegram('off'), {}), { kind: 'not-set-up', retry: '' });
    assert.deepEqual(viewOf(telegram('rejected'), {}), { kind: 'not-set-up', retry: '' });
  });

  it('says "paused" with the retry line while the pause condition holds, whatever the state is', () => {
    for (const state of ['on', 'off', 'rejected']) {
      assert.equal(telegramPaused(paused), true);
      assert.deepEqual(viewOf(telegram(state), paused), { kind: 'paused', retry: 'Trying again at 14:30' }, state);
    }
    assert.deepEqual(viewOf(telegram('on'), { telegramPaused: { active: false } }), { kind: 'on', retry: '' }, 'a cleared pause is not paused');
  });

  it('says "on" while the bot is on, paired or not', () => {
    assert.deepEqual(viewOf(telegram('on'), {}), { kind: 'on', retry: '' });
    assert.deepEqual(viewOf(telegram('on', { paired: true, displayName: 'Dana' }), {}), { kind: 'on', retry: '' });
  });

  it('shows no Telegram block for a release that does not include Telegram, whatever the state', () => {
    for (const state of ['on', 'off', 'rejected']) {
      assert.deepEqual(viewOf(telegram(state, { included: false }), paused), { kind: 'hidden', retry: '' }, state);
    }
  });

  it('pins the texts it shows, byte for byte: the rail card\'s four and its own "Telegram on"', () => {
    assert.equal(RAIL_TEXTS.telegramNotSetUp, 'Telegram not set up');
    assert.equal(RAIL_TEXTS.telegramHowTo, 'How to set it up');
    assert.equal(TELEGRAM_CARD_TEXTS.paused, 'Telegram paused');
    assert.equal(TELEGRAM_CARD_TEXTS.tryingAgainAt, 'Trying again at {time}');
    assert.equal(SETTINGS_TEXTS.channels.telegramOn, 'Telegram on');
  });
});

const ROW = (provider, over = {}) => ({ provider, defaultModel: `${provider}-default`, models: [`${provider}-default`, `${provider}-big`], keyVariable: `${provider.toUpperCase()}_API_KEY`, keySet: true, supported: true, ...over });
const AGENTS = {
  TriageAgent: { provider: 'anthropic', model: 'claude-haiku-5-5', secondProvider: '', secondModel: '' },
  DiagnosisAgent: { provider: 'anthropic', model: 'claude-sonnet-5-5', secondProvider: 'anthropic', secondModel: 'claude-haiku-5-5' },
  ChatAgent: { provider: 'anthropic', model: 'claude-haiku-5-5', secondProvider: '', secondModel: '' },
};
const PRICES = { 'claude-haiku-5-5': { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 }, 'claude-sonnet-5-5': { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 } };

describe('the refusal classifier (DW-948)', () => {
  const known = ['time', 'channels'];

  it('says denied for a 403, whatever the body names', () => {
    assert.deepEqual(refusalKind(403, ['time'], known), { kind: 'denied', fields: [] });
    assert.deepEqual(refusalKind(403, undefined, known), { kind: 'denied', fields: [] });
  });

  it('says field for a 400 that names a known field, with the known fields it names in the order of the section', () => {
    assert.deepEqual(refusalKind(400, ['channels', 'time', 'zz'], known), { kind: 'field', fields: ['time', 'channels'] });
    assert.deepEqual(refusalKind(400, ['channels'], known), { kind: 'field', fields: ['channels'] });
  });

  it('says form for a 400 that names no known field, and for every other answer', () => {
    assert.deepEqual(refusalKind(400, [], known), { kind: 'form', fields: [] });
    assert.deepEqual(refusalKind(400, ['zz'], known), { kind: 'form', fields: [] });
    assert.deepEqual(refusalKind(400, undefined, known), { kind: 'form', fields: [] });
    assert.deepEqual(refusalKind(400, 'time', known), { kind: 'form', fields: [] });
    assert.deepEqual(refusalKind(400, ['time'], []), { kind: 'form', fields: [] }, 'a section with no field to name');
    for (const status of [0, 401, 404, 409, 500, 501, 503]) assert.deepEqual(refusalKind(status, ['time'], known), { kind: 'form', fields: [] }, String(status));
  });
});

describe('the Models section', () => {
  it('lists only the providers marked supported, a provider without a key not choosable and given its reason (UX-DR133)', () => {
    const view = modelsView([ROW('anthropic'), ROW('openai', { supported: false }), ROW('gemini', { keySet: false, keyVariable: 'GEMINI_API_KEY' })]);
    assert.deepEqual(view.map((one) => one.provider), ['anthropic', 'gemini']);
    assert.deepEqual(view.map((one) => one.choosable), [true, false]);
    assert.equal(view[0].reason, '');
    assert.equal(view[1].reason, 'No key set. Add GEMINI_API_KEY to .env.');
    assert.equal(noKeyReason('ANTHROPIC_API_KEY'), 'No key set. Add ANTHROPIC_API_KEY to .env.');
    assert.equal(view[0].label, 'Anthropic');
    assert.equal(providerLabel('gemini'), 'gemini', 'a provider without a ruled name shows as its id');
  });

  it('lets no model of a provider without a key be chosen, and keeps the saved model in the list', () => {
    const view = modelsView([ROW('anthropic'), ROW('gemini', { keySet: false })]);
    assert.deepEqual(modelOptions(view, 'anthropic', 'anthropic-default').map((one) => [one.value, one.choosable]), [['anthropic-default', true], ['anthropic-big', true]]);
    assert.deepEqual(modelOptions(view, 'gemini', 'gemini-big').map((one) => [one.value, one.choosable]), [['gemini-default', false], ['gemini-big', false]]);
    assert.deepEqual(modelOptions(view, 'anthropic', 'old-model').map((one) => [one.value, one.choosable]), [['old-model', false], ['anthropic-default', true], ['anthropic-big', true]]);
    assert.deepEqual(modelOptions(view, 'zz', ''), []);
  });

  it('offers None and the models of every supported provider with a key as the second model, and keeps a saved one that is not among them', () => {
    const view = modelsView([ROW('anthropic'), ROW('gemini', { keySet: false }), ROW('openai', { supported: false })]);
    assert.deepEqual(secondOptions(view, '').map((one) => [one.value, one.label]), [['', 'None'], ['anthropic/anthropic-default', 'anthropic-default'], ['anthropic/anthropic-big', 'anthropic-big']]);
    const kept = secondOptions(view, 'gemini/gemini-big');
    assert.deepEqual(kept[0], { value: 'gemini/gemini-big', label: 'gemini-big', choosable: false });
    assert.equal(secondValue('anthropic', 'm'), 'anthropic/m');
    assert.equal(secondValue('', ''), '');
    assert.deepEqual(splitSecond('anthropic/claude-sonnet-5-5'), { provider: 'anthropic', model: 'claude-sonnet-5-5' });
    assert.deepEqual(splitSecond(''), { provider: '', model: '' });
  });

  it('builds the form from the server values, and the body of a save from the form, prices as typed and trimmed', () => {
    const form = modelsFormOf(AGENTS, PRICES);
    assert.deepEqual(form.agents.DiagnosisAgent, { provider: 'anthropic', model: 'claude-sonnet-5-5', second: 'anthropic/claude-haiku-5-5' });
    assert.deepEqual(form.agents.TriageAgent, { provider: 'anthropic', model: 'claude-haiku-5-5', second: '' });
    assert.deepEqual(form.prices['claude-haiku-5-5'], { input: '1', output: '5', cacheRead: '0.1', cacheWrite: '1.25' });
    const edited = { ...form, prices: { ...form.prices, 'claude-haiku-5-5': { ...form.prices['claude-haiku-5-5'], input: ' 1.25 ' } } };
    const body = modelsBody(edited);
    assert.deepEqual(Object.keys(body), ['agents', 'prices']);
    assert.deepEqual(Object.keys(body.agents), ['TriageAgent', 'DiagnosisAgent', 'ChatAgent']);
    assert.deepEqual(body.agents.DiagnosisAgent, AGENTS.DiagnosisAgent);
    assert.deepEqual(body.agents.TriageAgent, AGENTS.TriageAgent);
    assert.equal(body.prices['claude-haiku-5-5'].input, '1.25');
    assert.deepEqual(modelsValuesOf(edited).prices['claude-haiku-5-5'], { input: 1.25, output: 5, cacheRead: 0.1, cacheWrite: 1.25 });
    assert.deepEqual(modelsValuesOf(edited).agents, AGENTS);
  });

  it('reads an agent the server does not list as empty', () => {
    const form = modelsFormOf(undefined, undefined);
    assert.deepEqual(form.agents.ChatAgent, { provider: '', model: '', second: '' });
    assert.deepEqual(form.prices, {});
  });

  it('is dirty when an agent\'s choice or a price differs, ignoring the white space around a price', () => {
    const saved = modelsFormOf(AGENTS, PRICES);
    assert.equal(isModelsDirty(modelsFormOf(AGENTS, PRICES), saved), false);
    const price = (text) => ({ ...saved, prices: { ...saved.prices, 'claude-sonnet-5-5': { ...saved.prices['claude-sonnet-5-5'], cacheWrite: text } } });
    assert.equal(isModelsDirty(price(' 3.75 '), saved), false);
    assert.equal(isModelsDirty(price('3.8'), saved), true);
    for (const change of [{ model: 'claude-sonnet-5-5' }, { second: 'anthropic/claude-sonnet-5-5' }, { provider: 'other' }]) {
      assert.equal(isModelsDirty({ ...saved, agents: { ...saved.agents, TriageAgent: { ...saved.agents.TriageAgent, ...change } } }, saved), true, JSON.stringify(change));
    }
  });

  it('names the fields a refusal can name: each agent, each second model and each model\'s prices', () => {
    assert.deepEqual(modelsFieldNames(['m1']), ['TriageAgent', 'TriageAgent.second', 'DiagnosisAgent', 'DiagnosisAgent.second', 'ChatAgent', 'ChatAgent.second', 'prices.m1']);
    assert.deepEqual(refusalKind(400, ['TriageAgent.second', 'prices.m1', 'zz'], modelsFieldNames(['m1'])), { kind: 'field', fields: ['TriageAgent.second', 'prices.m1'] });
  });

  it('words a Test result: "Answered in {seconds} s" with one decimal, or "Didn\'t answer: {reason}" with the reason as the catalog words it', () => {
    const reasons = { no_key: 'no model key is set', timeout: "the model didn't answer within the time allowed" };
    const reasonText = (reason) => reasons[reason] ?? 'x';
    assert.equal(testResultText({ answered: true, seconds: 1.2, reason: '' }, reasonText), 'Answered in 1.2 s');
    assert.equal(testResultText({ answered: true, seconds: 3, reason: '' }, reasonText), 'Answered in 3.0 s');
    assert.equal(testResultText({ answered: false, seconds: 0.1, reason: 'no_key' }, reasonText), "Didn't answer: no model key is set");
    assert.equal(testResultText({ answered: false, seconds: 45, reason: 'timeout' }, reasonText), "Didn't answer: the model didn't answer within the time allowed");
  });

  it('pins the texts it shows, byte for byte', () => {
    const t = SETTINGS_TEXTS.models;
    assert.deepEqual(
      [t.agents.TriageAgent, t.agents.DiagnosisAgent, t.agents.ChatAgent, t.provider, t.model, t.secondModel, t.none, t.providers.anthropic],
      ['Triage agent', 'Diagnosis agent', 'Chat agent', 'Provider', 'Model', 'Second model', 'None', 'Anthropic'],
    );
    assert.equal(t.applies, "A change applies from the agent's next model request.");
    assert.equal(t.secondHelp, "Used once when this agent's reply can't be used.");
    assert.equal(t.testHelp, "Test sends one short request to the agent's saved model.");
    assert.equal(t.test, 'Test');
    assert.equal(t.answeredIn, 'Answered in {seconds} s');
    assert.equal(t.didntAnswer, "Didn't answer: {reason}");
    assert.equal(t.testFailed, "Couldn't run the test. Try again.");
    assert.equal(t.noKey, 'No key set. Add {variable} to .env.');
    assert.deepEqual([t.prices, t.input, t.output, t.cacheRead, t.cacheWrite], ['Prices', 'Input', 'Output', 'Cache read', 'Cache write']);
    assert.equal(t.pricesHelp, 'US dollars per million tokens. New prices apply to later model requests; earlier costs stay as they were.');
  });
});

describe('the Budgets section', () => {
  it('sends the two typed values, trimmed, and is dirty when either differs', () => {
    assert.deepEqual(budgetsBody(' 8000 ', ' 7.50'), { DecisionTokenBudget: '8000', DailyCostCapUSD: '7.50' });
    assert.equal(isBudgetsDirty({ tokens: '0', cap: '0' }, { tokens: ' 0 ', cap: '0' }), false);
    assert.equal(isBudgetsDirty({ tokens: '1', cap: '0' }, { tokens: '0', cap: '0' }), true);
    assert.equal(isBudgetsDirty({ tokens: '0', cap: '5' }, { tokens: '0', cap: '0' }), true);
  });

  it('pins the texts it shows, byte for byte', () => {
    const t = SETTINGS_TEXTS.budgets;
    assert.equal(t.tokens, 'Token budget per decision');
    assert.equal(t.tokensHelp, 'A decision that would use more tokens than this uses fixed rules instead. 0 is off.');
    assert.equal(t.cap, 'Daily cost cap (US dollars)');
    assert.equal(t.capHelp, "When today's model cost reaches the cap, decisions use fixed rules until midnight in the instance's time zone. 0 is off.");
  });

  it('has no "not built" line any more: every section is built', () => {
    assert.equal(Object.hasOwn(SETTINGS_TEXTS, 'notBuilt'), false);
  });
});
