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
const { BREAK_FEED_BUTTON, CHAT_FLOOR, COMPACT_BAND_HEIGHT, DISMISS_BUTTON, INCIDENT_CARD, MORE_TO_TRY_GROUPS, MORE_TO_TRY_ITEMS, MORE_TO_TRY_TEXTS, RESOLVED_CHIP, chatFloor, groupsOf, inCompactBand, itemsFor, windowBound } = await import(app('guide', 'more-to-try-view.ts'));
const { HEIGHT_QUERIES } = await import(app('shared', 'layout-view.ts'));
const { RAIL_TEXTS } = await import(app('rail', 'rail-view.ts'));
const { MEMORY_HEADING_ID, MEMORY_TEXTS } = await import(app('rail', 'memory-card', 'memory-card-view.ts'));
const { HEARTBEAT_HEADING_ID, HEARTBEAT_TEXTS } = await import(app('rail', 'heartbeat-card', 'heartbeat-card-view.ts'));
const { PERSONA_TEXTS, PRESETS } = await import(app('rail', 'persona-card', 'persona-card-view.ts'));
const { TRY_IT_TEXTS } = await import(app('chat', 'try-it-view.ts'));
const { SAMPLES } = await import(app('mailbox', 'mailbox-view.ts'));
const { DEVICE_TEXTS } = await import(app('devices', 'device-view.ts'));
const { FEED_TEXTS } = await import(app('feed', 'break-feed-view.ts'));
const { MESSAGE_TEXTS, PAGE_TEXTS } = await import(app('msg', 'catalog.ts'));
const { INCIDENT_TEXTS } = await import(app('incidents', 'incident-view.ts'));
const { ANSWER_SOURCES_TEXTS } = await import(app('chat', 'answer-sources-view.ts'));
const { DOCUMENTS_TEXTS } = await import(app('documents', 'documents-view.ts'));
const { SAMPLE_RUNBOOK_TEXTS } = await import(app('documents', 'sample-runbook-view.ts'));
const { REQUEST_NAMES } = await import(app('phone', 'phone-view.ts'));
const { DEMO_VIEW_TEXTS } = await import(app('header', 'demo-view-texts.ts'));

const GUARD = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Checks', 'ReplyGuard.cls'), 'utf8');

/** The ruling's strings (Story 4.11, Design Notes: Public text), written out here. */
const RULED = {
  link: 'More to try',
  label: 'Other things to try',
  rememberPrompt: "Remember that the Results partner's contact is Lee.",
  summaryPrompt: 'Show me the incident summary',
  items: {
    incidentSummary: {
      label: 'Read the incident summary',
      lookFor:
        'This closes the guide\'s resolved incident, as Dismiss on its card does. Look for the incident summary in the chat and on the Simulated phone: what happened and when, the cause and the evidence, each approval, the orders affected and the model cost. Later, ask "Show me the incident summary" to get it again.',
      button: 'Close the incident',
    },
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
    memoryCard: {
      label: 'Pin a memory',
      lookFor:
        'First do "Ask it to remember something". Then open All memories in the Memory card and press Pin on the memory marked Told. Open Pinned to see it: pinned facts are read at the start of each conversation, up to 1,000 tokens.',
      button: 'Go to the Memory card',
    },
    documents: {
      label: 'Ask about a document',
      lookFor:
        'On the Documents page, press Add the sample runbook, or add a short file of your own (nothing personal: Visual Trace on the demo is shared). When it reads Ready, ask in the chat "According to the runbook, what should I do when partner orders fail with a date error?", or ask about your own file, and look for the chip under the answer that names the document and its section.',
      button: 'Open the Documents page',
    },
    heartbeat: {
      label: 'Run a heartbeat check-in',
      lookFor: 'In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in\'s outcome and its cost in the card.',
      button: 'Go to the Heartbeat checklist card',
    },
    sources: {
      label: 'See where an answer came from',
      lookFor:
        'Under an answer from your documents, press the chip that names the document and section to read the passage, then Open document to see the whole file. Under an answer that recalls something you asked it to remember, press From memory to see what it remembered and when.',
      button: 'Open the Documents page',
    },
  },
};

// The registry's own ids, so that an item another story adds joins the count and the order pins; RULED is the independent text oracle, and
// a registry entry with no RULED text (or a RULED text with no entry) fails the tests below.
const IDS = MORE_TO_TRY_ITEMS.map((item) => item.id);
/** The items that name no memory, document or heartbeat: every item before memory (the registry puts the incident summary item first, Story 23.6). */
const BEFORE_MEMORY = IDS.slice(0, IDS.indexOf('memory'));
// The item whose control hands off to another item's control (Story 20.2: See where an answer came from opens the Documents page).
const ACTION_OF = { sources: 'documents' };
// The panel's group of each item (the Contest Planner's More to try groups ruling, 2026-11-10).
const GROUP_OF = {
  incidentSummary: 'Incidents and fixes',
  rejectFix: 'Incidents and fixes',
  memory: 'Memory and documents',
  memoryCard: 'Memory and documents',
  documents: 'Memory and documents',
  sources: 'Memory and documents',
  suspiciousEmail: 'Safety and settings',
  heartbeat: 'Safety and settings',
  persona: 'Safety and settings',
  demoView: 'Safety and settings',
};
const idsOf = (items) => items.map((item) => item.id);

describe('(a) the fixed strings', () => {
  it('are the ruled strings, exactly', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(MORE_TO_TRY_TEXTS)), RULED);
  });

  it('are in the registry in order: ids, labels, look-fors and button texts', () => {
    assert.deepEqual([...IDS].sort(), Object.keys(RULED.items).sort(), 'each registry entry has its ruled text, and each ruled text its entry');
    assert.equal(new Set(IDS).size, IDS.length, 'the ids are unique');
    assert.ok(IDS.indexOf('heartbeat') < IDS.indexOf('sources'), 'See where an answer came from comes after the heartbeat item');
    assert.deepEqual(
      MORE_TO_TRY_ITEMS.map(({ id, label, lookFor, button }) => ({ id, label, lookFor, button })),
      IDS.map((id) => ({ id, ...RULED.items[id] })),
    );
  });

  it('give each entry a hand-off named by its id', () => {
    assert.deepEqual(MORE_TO_TRY_ITEMS.map((item) => item.action), IDS.map((id) => ACTION_OF[id] ?? id));
  });

  it('give every entry its ruled group', () => {
    assert.deepEqual(MORE_TO_TRY_ITEMS.map((item) => [item.id, item.group]), IDS.map((id) => [id, GROUP_OF[id]]));
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

  it('gives the items before memory for their ids', () => {
    assert.deepEqual(idsOf(itemsFor(BEFORE_MEMORY)), BEFORE_MEMORY);
  });

  it('shows exactly its item, in its place, when memory, documents or heartbeat is added', () => {
    for (const id of ['memory', 'memoryCard', 'documents', 'heartbeat', 'sources']) {
      assert.deepEqual(idsOf(itemsFor([...BEFORE_MEMORY, id])), IDS.filter((one) => BEFORE_MEMORY.includes(one) || one === id), id);
    }
    assert.deepEqual(idsOf(itemsFor(IDS)), IDS);
  });

  it('ignores an id it does not know', () => {
    assert.deepEqual(idsOf(itemsFor([...BEFORE_MEMORY, 'somethingNew'])), BEFORE_MEMORY);
    assert.deepEqual(itemsFor(['somethingNew']), []);
  });

  it('follows the registry order, not the input order', () => {
    assert.deepEqual(idsOf(itemsFor([...IDS].reverse())), IDS);
    assert.deepEqual(idsOf(itemsFor(['demoView', 'persona'])), ['persona', 'demoView']);
  });
});

describe('(b2) groupsOf', () => {
  const item = (id, group) => ({ id, label: id, lookFor: id, button: id, action: 'persona', group });
  const headings = (sets) => sets.map((set) => set.heading);
  const flat = (sets) => sets.flatMap((set) => idsOf(set.items));

  it('holds the ruled headings, in the ruled order', () => {
    assert.deepEqual(MORE_TO_TRY_GROUPS, ['Incidents and fixes', 'Memory and documents', 'Safety and settings']);
  });

  it('knows every group that the registry declares', () => {
    for (const entry of MORE_TO_TRY_ITEMS) {
      assert.ok(MORE_TO_TRY_GROUPS.includes(entry.group), `${entry.id} declares ${JSON.stringify(entry.group)}`);
    }
  });

  it('gives the whole registry under the headings in order, and each group in registry order', () => {
    const sets = groupsOf(itemsFor(IDS));
    assert.deepEqual(headings(sets), MORE_TO_TRY_GROUPS.filter((group) => IDS.some((id) => GROUP_OF[id] === group)));
    for (const set of sets) {
      assert.deepEqual(idsOf(set.items), IDS.filter((id) => GROUP_OF[id] === set.heading), set.heading);
    }
    assert.deepEqual(flat(sets).sort(), [...IDS].sort(), 'every item once');
  });

  it('leaves out a group with no item, and gives nothing for no items', () => {
    const sets = groupsOf(itemsFor(BEFORE_MEMORY));
    assert.deepEqual(headings(sets), MORE_TO_TRY_GROUPS.filter((group) => BEFORE_MEMORY.some((id) => GROUP_OF[id] === group)));
    assert.ok(!headings(sets).includes('Memory and documents'));
    assert.deepEqual(groupsOf([]), []);
    assert.deepEqual(groupsOf(itemsFor(undefined)), []);
  });

  it('puts the items with no group, or a blank one, first and with no heading', () => {
    const items = [item('a', 'Safety and settings'), item('b', undefined), item('c', '  '), item('d', ''), item('e', 'Incidents and fixes')];
    const sets = groupsOf(items);
    assert.equal(sets[0].heading, undefined);
    assert.deepEqual(idsOf(sets[0].items), ['b', 'c', 'd']);
    assert.deepEqual(headings(sets), [undefined, 'Incidents and fixes', 'Safety and settings']);
    assert.ok(sets.every((set, i) => i === 0 || (typeof set.heading === 'string' && set.heading.trim() !== '')), 'no empty heading');
  });

  it('puts a group the constant does not hold after the ordered groups, in order of first appearance', () => {
    const items = [item('a', 'Zed'), item('b', 'Safety and settings'), item('c', 'Alpha'), item('d', 'Zed'), item('e', 'Incidents and fixes')];
    const sets = groupsOf(items);
    assert.deepEqual(headings(sets), ['Incidents and fixes', 'Safety and settings', 'Zed', 'Alpha']);
    assert.deepEqual(idsOf(sets[2].items), ['a', 'd']);
  });

  it('keeps an Incidents and fixes item that comes first in the input first overall', () => {
    const sets = groupsOf([item('first', 'Incidents and fixes'), ...itemsFor(IDS)]);
    assert.equal(flat(sets)[0], 'first');
  });

  it('gives every input item once, and the flattened sets are the focus order', () => {
    for (const id of IDS) {
      const input = itemsFor([...BEFORE_MEMORY, id]);
      const sets = groupsOf(input);
      assert.deepEqual(flat(sets).sort(), idsOf(input).sort(), id);
      assert.equal(new Set(flat(sets)).size, input.length, id);
      assert.deepEqual(flat(sets), MORE_TO_TRY_GROUPS.flatMap((group) => idsOf(input).filter((one) => GROUP_OF[one] === group)), `${id}: the order shown`);
    }
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

  it('names the Heartbeat checklist card and its Run button as the card does', () => {
    has(items.heartbeat.lookFor, `In the ${RAIL_TEXTS.heartbeat} card`);
    assert.equal(RAIL_TEXTS.heartbeat, 'Heartbeat checklist');
    has(items.heartbeat.lookFor, `press ${HEARTBEAT_TEXTS.run}.`);
    assert.equal(HEARTBEAT_TEXTS.run, 'Run the heartbeat now');
    has(items.heartbeat.button, `the ${RAIL_TEXTS.heartbeat} card`);
    assert.equal(HEARTBEAT_HEADING_ID, 'rail-heading-heartbeat', 'the heading that the heartbeat item hands focus to');
  });

  it('names the Memory card, its tabs and its controls as the card does, and the item it follows by its label', () => {
    has(items.memoryCard.lookFor, `"${items.memory.label}"`);
    has(items.memoryCard.lookFor, `open ${MEMORY_TEXTS.memories} in the ${RAIL_TEXTS.memory} card`);
    has(items.memoryCard.lookFor, `press ${MEMORY_TEXTS.pin} on the memory marked ${MEMORY_TEXTS.told}`);
    has(items.memoryCard.lookFor, `Open ${MEMORY_TEXTS.pinned} to see it`);
    has(items.memoryCard.lookFor, 'up to 1,000 tokens');
    assert.equal(MEMORY_TEXTS.used, '{used} of 1,000 tokens (estimated).', 'the limit the line quotes');
    has(items.memoryCard.button, `the ${RAIL_TEXTS.memory} card`);
    assert.equal(MEMORY_HEADING_ID, 'rail-heading-memory', 'the heading that the button hands focus to');
  });

  it('puts the Memory card item right after the memory item', () => {
    const at = MORE_TO_TRY_ITEMS.findIndex((item) => item.id === 'memory');
    assert.equal(MORE_TO_TRY_ITEMS[at + 1]?.id, 'memoryCard');
  });

  it('names Dismiss, the Simulated phone and the summary prompt as the page does (Story 23.6)', () => {
    has(items.incidentSummary.lookFor, `as ${INCIDENT_TEXTS.dismiss} on its card does`);
    has(items.incidentSummary.lookFor, `on the ${DEVICE_TEXTS.phoneTab}:`);
    has(items.incidentSummary.lookFor, `"${RULED.summaryPrompt}"`);
    assert.equal(MORE_TO_TRY_TEXTS.summaryPrompt, RULED.summaryPrompt);
    assert.equal(DISMISS_BUTTON, 'app-incident-dismiss button');
    assert.equal(INCIDENT_CARD, 'article[data-part="incident"]');
    assert.equal(RESOLVED_CHIP, '.chip-resolved');
  });

  it('counts the items by the registry: the header comment of the module says how many there are', () => {
    const header = readFileSync(join(here, '..', 'src', 'app', 'guide', 'more-to-try-view.ts'), 'utf8');
    const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
    assert.match(header, new RegExp(`the registry of\\s+\\*\\s+its ${words[MORE_TO_TRY_ITEMS.length]} items`), `the header comment says ${words[MORE_TO_TRY_ITEMS.length]} items`);
  });

  it('counts the items by the registry in the README (line 30) and in EXPERIENCE.md, whatever the number is after the merges (Story 23.6, AC 18)', () => {
    const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
    const word = words[MORE_TO_TRY_ITEMS.length];
    const readme = readFileSync(join(here, '..', '..', 'README.md'), 'utf8');
    assert.match(readme, new RegExp(`its More to try panel has ${word} more things to try`), `the README says ${word} more things to try`);
    assert.match(readme, /Incident summaries\.\*\* When an incident closes/, 'and holds the incident summary bullet');
    const ux = readFileSync(join(here, '..', '..', '_bmad-output', 'planning-artifacts', 'ux-designs', 'ux-OcuTalon-2026-10-16', 'EXPERIENCE.md'), 'utf8');
    assert.match(ux, new RegExp(`There are ${word} items, in this order`), `EXPERIENCE.md says ${word} items`);
  });

  it('names the Documents page as the header does', () => {
    has(items.documents.lookFor, 'On the Documents page');
    has(items.documents.lookFor, `press ${DOCUMENTS_TEXTS.sample},`);
    has(items.documents.lookFor, `When it reads ${DOCUMENTS_TEXTS.ready},`);
    has(items.documents.lookFor, `"${SAMPLE_RUNBOOK_TEXTS.question}"`);
    has(items.documents.lookFor, 'look for the chip under the answer that names the document and its section');
    has(items.documents.button, 'the Documents page');
    has(items.sources.button, 'the Documents page');
    assert.equal(items.sources.button, items.documents.button, 'the last item uses the existing control text');
    const header = readFileSync(join(here, '..', 'src', 'app', 'header', 'header-nav.ts'), 'utf8');
    assert.match(header, />Documents<\/a>/);
  });
});

describe('(c2) the sources item names the chips as the page does (Story 20.2)', () => {
  it('names Open document and From memory as the sources row does', () => {
    const lookFor = RULED.items.sources.lookFor;
    assert.ok(lookFor.includes(`then ${ANSWER_SOURCES_TEXTS.openDocument} to see the whole file`));
    assert.ok(lookFor.includes(`press ${ANSWER_SOURCES_TEXTS.fromMemory} to see what it remembered and when`));
  });

  it('says provenance only: no "used", "relied on" or "based on" in the text of the item or of the chips (U-280)', () => {
    const texts = [RULED.items.sources.label, RULED.items.sources.lookFor, RULED.items.documents.lookFor, ...Object.values(ANSWER_SOURCES_TEXTS)];
    for (const text of texts) assert.doesNotMatch(text, /\bused\b|relied on|based on/i, text);
  });
});

describe('(d) the look-for lines of the items before memory', () => {
  const phrases = (name) => {
    const match = new RegExp(`^Parameter ${name} = "([^"]*)";`, 'm').exec(GUARD);
    assert.ok(match, `ReplyGuard.cls holds Parameter ${name}`);
    return match[1].split(',').map((one) => one.trim()).filter((one) => one !== '');
  };
  const folded = (text) => text.toLowerCase().replace(/\u2019/g, "'").replace(/\s+/g, ' ');

  it('name no memory, document or heartbeat', () => {
    for (const id of BEFORE_MEMORY) {
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

describe('(f) the panel\'s room: the compact band is decided on the height left after the banners (the Planner, 2026-11-07)', () => {
  it('has the band\'s edge at the height query\'s 680px', () => {
    assert.equal(COMPACT_BAND_HEIGHT, 680);
    assert.equal(HEIGHT_QUERIES.compact, `(height < ${COMPACT_BAND_HEIGHT}px)`);
  });

  it('puts the page in the band when the viewport less the banners is under 680px, so a banner moves the edge up by its height', () => {
    assert.equal(inCompactBand(679, 0), true);
    assert.equal(inCompactBand(680, 0), false);
    assert.equal(inCompactBand(720, 40), false, '720 less a 40px banner leaves 680');
    assert.equal(inCompactBand(719, 40), true);
    assert.equal(inCompactBand(700, 40), true, 'the same viewport is above the band without the banner');
    assert.equal(inCompactBand(700, 0), false);
    assert.equal(inCompactBand(1080, 40), false);
  });

  it('floors the chat\'s list at 64px in the band and 160px above it', () => {
    assert.deepEqual({ ...CHAT_FLOOR }, { compact: 64, tall: 160 });
    assert.equal(chatFloor(true), 64);
    assert.equal(chatFloor(false), 160);
  });

  it('bounds the window by its height now plus the list\'s height above the floor, in whole pixels, and lowers it when the list is under the floor', () => {
    assert.equal(windowBound(100, 160, 160), 100, 'a list at its floor keeps the window');
    assert.equal(windowBound(100, 200.6, 160), 140, 'room above the floor goes to the window');
    assert.equal(windowBound(100, 130, 160), 70, 'a list under the floor takes from the window');
    assert.equal(windowBound(55, 64, 64), 55);
  });
});
