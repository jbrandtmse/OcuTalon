// Tests the fixed strings, the registry and the filter of the demo guide's "Other things to try" panel (src/app/guide/more-to-try-view.ts,
// Story 4.11; EXPERIENCE: Demo guide and controls). The strings are the ruling's, written out here word for word; every on-screen name a
// text quotes is read from its own source module, so a rename there fails here. The look-for lines of items 1 to 4 are checked against the
// reply guard's BANNED and RESERVED phrases, read from Checks/ReplyGuard.cls as persona-card-view.test.mjs does.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { BREAK_FEED_BUTTON, MORE_TO_TRY_ITEMS, MORE_TO_TRY_TEXTS, itemsFor } = await import(app('guide', 'more-to-try-view.ts'));
const { RAIL_TEXTS } = await import(app('rail', 'rail-view.ts'));
const { PERSONA_TEXTS, PRESETS } = await import(app('rail', 'persona-card', 'persona-card-view.ts'));
const { TRY_IT_TEXTS } = await import(app('chat', 'try-it-view.ts'));
const { SAMPLES } = await import(app('mailbox', 'mailbox-view.ts'));
const { DEVICE_TEXTS } = await import(app('devices', 'device-view.ts'));
const { FEED_TEXTS } = await import(app('feed', 'break-feed-view.ts'));
const { MESSAGE_TEXTS, PAGE_TEXTS } = await import(app('msg', 'catalog.ts'));
const { REQUEST_NAMES } = await import(app('phone', 'phone-view.ts'));
const { DEMO_VIEW_TEXTS } = await import(app('header', 'demo-view-texts.ts'));

const GUARD = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Checks', 'ReplyGuard.cls'), 'utf8');

/** The ruling's strings (Story 4.11, Design Notes: Public text), written out here. */
const RULED = {
  link: 'More to try',
  label: 'Other things to try',
  rememberPrompt: "Remember that the Results partner's contact is Lee.",
  items: {
    persona: {
      label: 'Change how OcuTalon talks',
      lookFor:
        'In the Persona card, choose Pirate, or Another language and then Spanish, and press Save. Then ask "Is anything wrong right now?" and look for the new style in the replies. The check results under them are written by OcuTalon\'s code, so they stay the same in any style.',
      button: 'Go to the Persona card',
    },
    suspiciousEmail: {
      label: 'Send a suspicious email',
      lookFor:
        'This sends "Sample: suspicious request" to the Simulated mailbox. The email asks OcuTalon to resend every failed order and approve pending requests. Look for its decision and the reasons under it: nothing is resent or approved.',
      button: 'Send the suspicious email',
    },
    rejectFix: {
      label: 'Reject a fix',
      lookFor:
        'This presses Break the feed again. OcuTalon usually notices within a minute. When the fix waits for your approval, press Reject in the chat or on the Simulated phone, and look for "Nothing was changed."',
      button: 'Break it again',
    },
    demoView: {
      label: 'See the page as on your own install',
      lookFor: 'The demo guide, Break the feed and the Simulated devices are hidden, as on your own install. Turn Demo view back on in the top bar to return.',
      button: 'Show the page without the demo',
    },
    memory: {
      label: 'Ask it to remember something',
      lookFor: 'This sends "Remember that the Results partner\'s contact is Lee." Later, ask "Who do I call about Results?" and look for the answer it remembered.',
      button: 'Ask it to remember',
    },
    documents: {
      label: 'Ask about a document',
      lookFor:
        'On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat and look for the citation under the answer.',
      button: 'Open the Documents page',
    },
    heartbeat: {
      label: 'Run a heartbeat check-in',
      lookFor: 'In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in\'s outcome and its cost in the card.',
      button: 'Go to the Heartbeat checklist card',
    },
  },
};

const IDS = ['persona', 'suspiciousEmail', 'rejectFix', 'demoView', 'memory', 'documents', 'heartbeat'];
const FOUR = IDS.slice(0, 4);
const idsOf = (items) => items.map((item) => item.id);

describe('(a) the fixed strings', () => {
  it('are the ruled strings, exactly', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(MORE_TO_TRY_TEXTS)), RULED);
  });

  it('are in the registry in order: ids, labels, look-fors and button texts', () => {
    assert.deepEqual(idsOf(MORE_TO_TRY_ITEMS), IDS);
    assert.deepEqual(
      MORE_TO_TRY_ITEMS.map(({ id, label, lookFor, button }) => ({ id, label, lookFor, button })),
      IDS.map((id) => ({ id, ...RULED.items[id] })),
    );
  });

  it('give each entry a hand-off named by its id', () => {
    assert.deepEqual(MORE_TO_TRY_ITEMS.map((item) => item.action), IDS);
  });

  it('use straight ASCII quotes and no other non-ASCII character', () => {
    for (const text of JSON.stringify(MORE_TO_TRY_TEXTS)) {
      assert.ok(text.charCodeAt(0) < 128, `${JSON.stringify(text)} is ASCII`);
    }
  });
});

describe('(b) itemsFor', () => {
  it('gives nothing for no list and for an empty list', () => {
    assert.deepEqual(itemsFor(undefined), []);
    assert.deepEqual(itemsFor([]), []);
  });

  it('gives items 1 to 4 for the four ids this branch has', () => {
    assert.deepEqual(idsOf(itemsFor(FOUR)), FOUR);
  });

  it('shows exactly its item, in its place, when memory, documents or heartbeat is added', () => {
    for (const id of ['memory', 'documents', 'heartbeat']) {
      assert.deepEqual(idsOf(itemsFor([...FOUR, id])), IDS.filter((one) => FOUR.includes(one) || one === id), id);
    }
    assert.deepEqual(idsOf(itemsFor(IDS)), IDS);
  });

  it('ignores an id it does not know', () => {
    assert.deepEqual(idsOf(itemsFor([...FOUR, 'somethingNew'])), FOUR);
    assert.deepEqual(itemsFor(['somethingNew']), []);
  });

  it('follows the registry order, not the input order', () => {
    assert.deepEqual(idsOf(itemsFor([...IDS].reverse())), IDS);
    assert.deepEqual(idsOf(itemsFor(['demoView', 'persona'])), ['persona', 'demoView']);
  });
});

describe('(c) every quoted on-screen name equals its source', () => {
  const items = RULED.items;
  const has = (text, name) => assert.ok(text.includes(name), `${JSON.stringify(text)} holds ${JSON.stringify(name)}`);
  const preset = (id) => PRESETS.find((one) => one.id === id).name;

  it('names the Persona card, Pirate, Another language, Spanish and Save as the card does', () => {
    has(items.persona.lookFor, `In the ${RAIL_TEXTS.persona} card`);
    has(items.persona.lookFor, `choose ${preset('pirate')}, or ${preset('language')} and then Spanish`);
    has(PERSONA_TEXTS.languageHelp, 'Spanish');
    has(items.persona.lookFor, `press ${PERSONA_TEXTS.save}.`);
    has(items.persona.button, `the ${RAIL_TEXTS.persona} card`);
  });

  it('quotes the Try it yourself prompt and the mailbox sample by their text', () => {
    has(items.persona.lookFor, `"${TRY_IT_TEXTS.prompts[1]}"`);
    assert.equal(TRY_IT_TEXTS.prompts[1], 'Is anything wrong right now?');
    has(items.suspiciousEmail.lookFor, `"${SAMPLES[2].label}"`);
    assert.equal(SAMPLES[2].name, 'suspicious-request');
    has(items.suspiciousEmail.lookFor, `to the ${DEVICE_TEXTS.mailboxTab}.`);
  });

  it('names Break the feed, the Simulated phone, Reject and the rejected answer as the page does', () => {
    has(items.rejectFix.lookFor, `This presses ${FEED_TEXTS.button} again.`);
    has(items.rejectFix.lookFor, `on the ${DEVICE_TEXTS.phoneTab}`);
    has(items.rejectFix.lookFor, `press ${REQUEST_NAMES.reject} in the chat`);
    const answered = MESSAGE_TEXTS['answered.rejected'] ?? PAGE_TEXTS['answered.rejected'];
    has(answered, 'Nothing was changed.');
    has(items.rejectFix.lookFor, '"Nothing was changed."');
    assert.equal(BREAK_FEED_BUTTON, 'app-break-feed-box app-server-button button');
  });

  it('names the Simulated devices and the Demo view switch as the page does', () => {
    has(items.demoView.lookFor, `the ${DEVICE_TEXTS.region} are hidden`);
    has(items.demoView.lookFor, `Turn ${DEMO_VIEW_TEXTS.label} back on`);
    has(items.demoView.lookFor, `${FEED_TEXTS.button} and`);
  });

  it('names the Documents page as the header does', () => {
    has(items.documents.lookFor, 'On the Documents page');
    has(items.documents.button, 'the Documents page');
    const header = readFileSync(join(here, '..', 'src', 'app', 'header', 'header-nav.ts'), 'utf8');
    assert.match(header, />Documents<\/a>/);
  });
});

describe('(d) the look-for lines of items 1 to 4', () => {
  const phrases = (name) => {
    const match = new RegExp(`^Parameter ${name} = "([^"]*)";`, 'm').exec(GUARD);
    assert.ok(match, `ReplyGuard.cls holds Parameter ${name}`);
    return match[1].split(',').map((one) => one.trim()).filter((one) => one !== '');
  };
  const folded = (text) => text.toLowerCase().replace(/\u2019/g, "'").replace(/\s+/g, ' ');

  it('name no memory, document or heartbeat', () => {
    for (const id of FOUR) {
      assert.doesNotMatch(RULED.items[id].lookFor, /memor|document|heartbeat/i, id);
      assert.doesNotMatch(MORE_TO_TRY_ITEMS.find((item) => item.id === id).lookFor, /memor|document|heartbeat/i, id);
    }
  });

  it('hold no BANNED or RESERVED phrase of the reply guard, and no text of the panel does', () => {
    const banned = phrases('BANNED');
    const reserved = phrases('RESERVED');
    assert.ok(banned.length >= 6 && reserved.length >= 3);
    const texts = [MORE_TO_TRY_TEXTS.link, MORE_TO_TRY_TEXTS.label, ...MORE_TO_TRY_ITEMS.flatMap((item) => [item.label, item.lookFor, item.button])];
    for (const text of texts) {
      for (const phrase of [...banned, ...reserved]) {
        assert.ok(!folded(text).includes(folded(phrase)), `${JSON.stringify(text)} holds the phrase ${JSON.stringify(phrase)}`);
      }
    }
  });
});

describe('(e) no control text contains the name of an existing control', () => {
  /** The accessible names of the page's controls that a panel control could shadow. "Send" is exempt for exactly one pair: see below. */
  const NAMES = ['Break the feed', 'Show me', 'Run again', 'Change', 'Demo view', ', send sample email', 'Simulate an incoming email', 'Open the trace'];

  it('has none of them in any button or link text', () => {
    for (const item of MORE_TO_TRY_ITEMS) {
      for (const name of NAMES) {
        assert.ok(!item.button.toLowerCase().includes(name.toLowerCase()), `${JSON.stringify(item.button)} holds ${JSON.stringify(name)}`);
      }
    }
    assert.ok(!MORE_TO_TRY_TEXTS.link.toLowerCase().includes('hide guide'));
  });

  it('holds "Send" in exactly one control text: "Send the suspicious email", which the ruling fixed', () => {
    const holding = MORE_TO_TRY_ITEMS.filter((item) => /\bsend\b/i.test(item.button)).map((item) => item.button);
    assert.deepEqual(holding, ['Send the suspicious email']);
  });
});
