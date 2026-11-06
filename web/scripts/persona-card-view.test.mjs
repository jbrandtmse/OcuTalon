// Tests the Persona card's fixed texts and rules (src/app/rail/persona-card/persona-card-view.ts, Story 40.4; FR-67, FR-68, FR-70, UX-DR117, U-278).
// The texts are EXPERIENCE.md's, written out here word for word, but for the two all-clear sentences of the Language and "Your own words" help
// texts, which U-278 fixed in epics.md. The U-278 test also reads the reply guard's BANNED and RESERVED lists from the class itself and asserts
// that neither help text holds a phrase of either, so that the help never tells the person something the guard would delete from a reply.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { PERSONA_TEXTS, PRESETS, counterText, failureOf, languageHelpText, optionsFor, presetOf, saveBody } = await import(app('rail', 'persona-card', 'persona-card-view.ts'));

const GUARD = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Checks', 'ReplyGuard.cls'), 'utf8');

const UX_LANGUAGE_HELP = 'Name a language, such as Spanish or Portuguese (Brazil). Notices, cards and buttons stay in English.';
const U278_LANGUAGE =
  "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. In another language, the model is only told not to say so.";
const U278_CUSTOM =
  "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. If this persona writes in another language, the model is only told not to say so.";

describe('the texts', () => {
  it('are the UX wording of the Persona card, written out here', () => {
    assert.deepEqual(
      { ...PERSONA_TEXTS },
      {
        intro:
          'Choose how OcuTalon words its chat replies and the reasons for its decisions. What OcuTalon may do, and what needs your approval, never changes.',
        change: 'Change',
        save: 'Save',
        language: 'Language',
        languageHelp: UX_LANGUAGE_HELP,
        languageAllClear: U278_LANGUAGE,
        customAllClear: U278_CUSTOM,
        customLabel: 'Your own words',
        counter: '{n} of 1,000 characters',
        pending: 'OcuTalon suggested a change. It waits for your answer in Approval requests.',
        demoNote: 'On the online demo you can choose a preset or a language. Your choice lasts for this visit.',
      },
    );
    for (const value of Object.values(PERSONA_TEXTS)) assert.match(value, /^[\x20-\x7e]+$/, `${value} is ASCII`);
  });

  it('name the six presets in the UX table\'s order, with the table\'s descriptions', () => {
    assert.deepEqual(
      PRESETS.map((one) => [one.id, one.name, one.description]),
      [
        ['professional', 'Professional (default)', 'Calm, short and plain.'],
        ['starship', 'Starship computer', 'Crisp status reports, formal and brief.'],
        ['pirate', 'Pirate', 'Sailing words and a good-humoured tone; the facts stay exact.'],
        ['kindfriend', 'Kind friend', 'Warm, patient and encouraging.'],
        ['language', 'Another language', 'Replies and reasons in the language you name.'],
        ['custom', 'Your own words', 'Describe the tone, style and preferences you want.'],
      ],
    );
    assert.equal(presetOf('pirate')?.name, 'Pirate');
    assert.equal(presetOf('nonsense'), undefined);
  });

  it('leave "Your own words" out of the options on the online demo only', () => {
    assert.deepEqual(optionsFor(true).map((one) => one.id), ['professional', 'starship', 'pirate', 'kindfriend', 'language', 'custom']);
    assert.deepEqual(optionsFor(false).map((one) => one.id), ['professional', 'starship', 'pirate', 'kindfriend', 'language']);
  });
});

describe('the help texts of U-278', () => {
  it('(a) are the UX help plus the sentence for the Language field, and the sentence alone for Your own words, word for word', () => {
    assert.equal(PERSONA_TEXTS.languageAllClear, U278_LANGUAGE);
    assert.equal(PERSONA_TEXTS.customAllClear, U278_CUSTOM);
    assert.equal(languageHelpText(), `${UX_LANGUAGE_HELP} ${U278_LANGUAGE}`);
    assert.equal(languageHelpText(), "Name a language, such as Spanish or Portuguese (Brazil). Notices, cards and buttons stay in English. OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. In another language, the model is only told not to say so.");
  });

  /** The phrases of a comma-separated Parameter of ReplyGuard. */
  const phrases = (name) => {
    const match = new RegExp(`^Parameter ${name} = "([^"]*)";`, 'm').exec(GUARD);
    assert.ok(match, `ReplyGuard.cls holds Parameter ${name}`);
    return match[1].split(',').map((one) => one.trim()).filter((one) => one !== '');
  };
  /** The guard's reading of a text: case folded, any whitespace run a single space, U+2019 an apostrophe. */
  const folded = (text) => text.toLowerCase().replace(/\u2019/g, "'").replace(/\s+/g, ' ');

  it('(b) hold no BANNED or RESERVED phrase of the reply guard, read from ReplyGuard.cls', () => {
    const banned = phrases('BANNED');
    const reserved = phrases('RESERVED');
    assert.ok(banned.length >= 6, `found ${banned.length} banned phrases`);
    assert.ok(reserved.length >= 3, `found ${reserved.length} reserved phrases`);
    for (const [label, text] of [['the Language help', languageHelpText()], ['the Your own words help', PERSONA_TEXTS.customAllClear], ['the UX language help', PERSONA_TEXTS.languageHelp]]) {
      for (const phrase of [...banned, ...reserved]) {
        assert.ok(!folded(text).includes(folded(phrase)), `${label} holds "${phrase}"`);
      }
    }
  });

  it('(b) would catch a banned phrase in a help text (the check itself)', () => {
    const banned = phrases('BANNED');
    assert.ok(banned.some((phrase) => folded(`${U278_LANGUAGE} It has no problems.`).includes(folded(phrase))));
    assert.ok(banned.some((phrase) => folded('Everything\u2019s fine').includes(folded(phrase))));
  });
});

describe('the counter', () => {
  it('counts UTF-16 units, which is what IRIS $Length counts: an emoji is 2', () => {
    assert.equal(counterText(''), '0 of 1,000 characters');
    assert.equal(counterText('Ahoy!'), '5 of 1,000 characters');
    assert.equal(counterText('\u{1F6A2}'), '2 of 1,000 characters');
    assert.equal(counterText('a'.repeat(1001)), '1001 of 1,000 characters');
  });
});

describe('the save body', () => {
  it('carries the language only for Another language and the custom text only for Your own words', () => {
    assert.deepEqual(saveBody('professional', 'Spanish', 'text'), { preset: 'professional', language: '', custom: '' });
    assert.deepEqual(saveBody('starship', 'Spanish', 'text'), { preset: 'starship', language: '', custom: '' });
    assert.deepEqual(saveBody('pirate', 'Spanish', 'text'), { preset: 'pirate', language: '', custom: '' });
    assert.deepEqual(saveBody('kindfriend', 'Spanish', 'text'), { preset: 'kindfriend', language: '', custom: '' });
    assert.deepEqual(saveBody('language', 'Spanish', 'text'), { preset: 'language', language: 'Spanish', custom: '' });
    assert.deepEqual(saveBody('custom', 'Spanish', 'text'), { preset: 'custom', language: '', custom: 'text' });
  });

  it('keeps the three keys in order, every value a string', () => {
    assert.deepEqual(Object.keys(saveBody('pirate', '', '')), ['preset', 'language', 'custom']);
  });
});

describe('a failed save', () => {
  const refused = (code, message) => ({ status: 400, error: { error: { code, message } } });

  it('shows a bad_language refusal beside the Language field and a bad_custom one beside the text area, with the server\'s message', () => {
    assert.deepEqual(failureOf(refused('bad_language', 'Use a language name only.')), { where: 'language', message: 'Use a language name only.' });
    assert.deepEqual(failureOf(refused('bad_custom', 'Use up to 1,000 characters.')), { where: 'custom', message: 'Use up to 1,000 characters.' });
  });

  it('shows every other code under Save, with the server\'s message', () => {
    for (const code of ['bad_preset', 'custom_not_offered', 'bad_persona', 'not_saved', 'server_error', 'not_built']) {
      assert.deepEqual(failureOf(refused(code, `message of ${code}`)), { where: 'save', message: `message of ${code}` }, code);
    }
  });

  it('has no message for a failure with no body, no error object or no message, and shows it under Save', () => {
    assert.deepEqual(failureOf(null), { where: 'save', message: '' });
    assert.deepEqual(failureOf(undefined), { where: 'save', message: '' });
    assert.deepEqual(failureOf(new Error('x')), { where: 'save', message: '' });
    assert.deepEqual(failureOf({ status: 0, error: null }), { where: 'save', message: '' });
    assert.deepEqual(failureOf({ status: 502, error: '<html>' }), { where: 'save', message: '' });
    assert.deepEqual(failureOf({ status: 500, error: { error: null } }), { where: 'save', message: '' });
    assert.deepEqual(failureOf({ status: 500, error: { error: { code: 'server_error' } } }), { where: 'save', message: '' });
    assert.deepEqual(failureOf({ status: 500, error: { error: { code: 'server_error', message: 7 } } }), { where: 'save', message: '' });
  });

  it('keeps a field refusal that came with no message beside its field (the component shows the busy notice there)', () => {
    assert.deepEqual(failureOf({ status: 400, error: { error: { code: 'bad_language' } } }), { where: 'language', message: '' });
  });
});
