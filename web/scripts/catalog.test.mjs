// Tests of the page's catalog generator (catalog.mjs) and of the module it writes (src/app/msg/catalog.ts): the real tree's
// check, the fallback sentence for each of the 12 reasons and for one that is none, the five check sentences from the Watch
// catalog (the two that name what failed take a text slot), the 15 banner and action keys with their slot types (Stories 2.10, 16.5 and 12.9), the
// nine answered keys with their channel and text slots (Story 6.2), the message form of the answered texts (Story 6.3:
// MESSAGE_TEXTS and renderMessageText, with the dated time's "on"), and fixtures for the output's shape, the web text over the
// text, the merge of the Core and Watch catalogs, the time, cost, count and text slots that take the caller's string, the channel
// slot that gives a channel's name, a text slot accepted on the keys of TEXT_SLOT_KEYS only, and each way the generator refuses (a
// missing listed key, a key in both catalogs, a slot type the page does not render, a text slot on any other key, a broken XData
// block or CHANNELNAMES parameter, a reason with no text) and a stale file. Story 6.4: the eight result texts and the audit line
// as Catalog.RenderAt gives them (the Fixtures XData of Test.Msg.Catalog), every count-of-one form of them, the noun slot that
// the count slot chooses, and the generator's one forms (emitted, and refused when they name no count slot or have no text).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, 'catalog.mjs');
const repoRoot = resolve(here, '..', '..');
const realOut = join(repoRoot, 'web/src/app/msg/catalog.ts');
const enumFile = join(repoRoot, 'src/ocutalon/cls/OcuTalon/Msg/Enum.cls');
const real = await import(pathToFileURL(realOut).href);

const work = mkdtempSync(join(tmpdir(), 'ocutalon-catalog-'));
after(() => rmSync(work, { recursive: true, force: true }));

const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });

/** The ten banner texts, the two chat-only forms (Story 12.9) and the four action texts that the page renders (Stories 2.10, 16.5 and 18.3), in the generator's order. */
const BANNER_KEYS = [
  'banner.allowance',
  'banner.allowanceChat',
  'banner.dailyCap',
  'banner.unreachable',
  'banner.noModelKey',
  'banner.costCap',
  'banner.heartbeatStalled',
  'banner.telegramPaused',
  'banner.resetSoon',
  'banner.resetSoonChat',
  'banner.reconnecting',
  'banner.demoBusy',
  'bannerAction.installYourself',
  'bannerAction.howToSetKey',
  'bannerAction.budgets',
  'bannerAction.setUpBot',
];

/** The five check sentences that the page renders, in the generator's order. */
const CHECK_KEYS = ['checks.allPassed', 'checks.everythingElsePassed', 'checks.nothingWatched', 'checks.notEverything', 'checks.notEverythingRestPassed'];

/** The answered texts that the page renders (Story 6.2; the last nine are Story 25.5's refusal sentences), in the generator's order. */
const ANSWERED_KEYS = [
  'answered.approved',
  'answered.approvedBy',
  'answered.rejected',
  'answered.rejectedBy',
  'answered.expired',
  'answered.alreadyApproved',
  'answered.alreadyRejected',
  'answered.alreadyApprovedBy',
  'answered.alreadyRejectedBy',
  'answered.notApproverResend',
  'answered.notApproverReroute',
  'answered.notApproverSuspend',
  'answered.notApproverRollback',
  'answered.notApproverPartner',
  'answered.notApproverEmail',
  'answered.notApproverTool',
  'answered.notApprover',
  'answered.notAdmin',
];

/** The thirteen result texts and the audit line that the page renders (Story 6.4; the last five are Story 23.2's fixes the user asks for in the chat), in the generator's order. */
const RESULT_KEYS = [
  'result.allThrough',
  'result.failedAgain',
  'result.skipped',
  'result.failedAndSkipped',
  'result.stillResending',
  'result.interrupted',
  'result.couldNotStart',
  'result.stoppedPartway',
  'result.itemSuspended',
  'result.itemResumed',
  'result.itemSkipped',
  'result.itemNotChanged',
  'result.rerouted',
  'audit.recorded',
];

/** The Got it button text and the handled line of a tell-now notice (Story 18.4), listed after the either-way line. */
const GOT_IT_KEYS = ['button.gotIt', 'handled.marked'];

/** The line that announces a learned save (Story 41.15), listed after the Got it keys; its fact slot is a text slot. */
const LEARNED_KEY = 'memory.learnedSaved';

/** The page key of the either-way line (Story 7.8): derived by the generator from the two catalog entries that hold it, listed last. */
const LINE_KEY = 'incident.eitherWayLine';
const LINE_PARENTS = ['incident.withFixEitherWay', 'incident.laterRequestEitherWay'];
/** U-249's line, as the notice shows it: the many form and the one form. */
const LINE_MANY = 'All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived.';
const LINE_ONE = 'The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived.';

describe('the real tree', () => {
  it('has a current catalog.ts', () => {
    const r = run('--check');
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /catalog: generated files are current/);
  });

  it('writes printable ASCII under a generated-file header', () => {
    const text = readFileSync(realOut, 'utf8');
    assert.match(text.split('\n')[0], /^\/\/ Generated by web\/scripts\/catalog\.mjs/);
    assert.ok(!/[^\x20-\x7e\n]/.test(text), 'ASCII only');
  });

  it('holds the 12 fallback reasons of Msg.Enum, and the 11 reason texts, the sentence, the five check sentences, the 15 banner and action keys, the 18 answered keys (the last nine are the refusal sentences of Story 25.5), the fourteen result keys, the either-way line and the two Got it keys', () => {
    const enumReasons = /Parameter FALLBACKREASON = "([^"]*)";/.exec(readFileSync(enumFile, 'utf8'))[1].split(',');
    assert.equal(enumReasons.length, 12);
    assert.deepEqual(Object.keys(real.REASON_KEYS), enumReasons);
    const suffixes = ['timeout', 'empty', 'cutOff', 'refusal', 'error', 'rateLimited', 'budget', 'tooLarge', 'dailyCap', 'noKey', 'generic'];
    assert.equal(CHECK_KEYS.length, 5);
    assert.deepEqual(Object.keys(real.PAGE_TEXTS).sort(), ['conversation.turnFallback', ...CHECK_KEYS, ...BANNER_KEYS, ...ANSWERED_KEYS, ...RESULT_KEYS, LINE_KEY, ...GOT_IT_KEYS, LEARNED_KEY, ...suffixes.map((suffix) => `fallbackReason.${suffix}`)].sort());
    assert.equal(Object.keys(real.PAGE_TEXTS).length, 69);
  });

  it('holds the 16 banner and action keys, the 18 answered keys and the fourteen result keys with the slot types of the catalog, and no key that waits for another story', () => {
    assert.equal(BANNER_KEYS.length, 16);
    assert.equal(ANSWERED_KEYS.length, 18);
    assert.equal(RESULT_KEYS.length, 14);
    assert.deepEqual(Object.keys(real.PAGE_SLOTS), ['conversation.turnFallback', ...CHECK_KEYS, ...BANNER_KEYS, ...ANSWERED_KEYS, ...RESULT_KEYS, LINE_KEY, ...GOT_IT_KEYS, LEARNED_KEY]);
    const slots = {
      'checks.notEverything': { whatFailed: 'text' },
      'checks.notEverythingRestPassed': { whatFailed: 'text' },
      'banner.allowance': { limit: 'count', time: 'time' },
      'banner.allowanceChat': { limit: 'count', time: 'time' },
      'banner.dailyCap': { time: 'time' },
      'banner.costCap': { cap: 'cost', time: 'time' },
      'banner.heartbeatStalled': { time: 'time' },
      'banner.telegramPaused': { time: 'time' },
      'conversation.turnFallback': { fallbackReason: 'fallbackReason' },
      'answered.approved': { channel: 'channel', time: 'time' },
      'answered.approvedBy': { user: 'text', channel: 'channel', time: 'time' },
      'answered.rejected': { channel: 'channel', time: 'time' },
      'answered.rejectedBy': { user: 'text', channel: 'channel', time: 'time' },
      'answered.expired': { time: 'time' },
      'answered.alreadyApproved': { channel: 'channel', time: 'time' },
      'answered.alreadyRejected': { channel: 'channel', time: 'time' },
      'answered.alreadyApprovedBy': { user: 'text', channel: 'channel', time: 'time' },
      'answered.alreadyRejectedBy': { user: 'text', channel: 'channel', time: 'time' },
      'answered.notApproverResend': {},
      'answered.notApproverReroute': {},
      'answered.notApproverSuspend': {},
      'answered.notApproverRollback': {},
      'answered.notApproverPartner': {},
      'answered.notApproverEmail': {},
      'answered.notApproverTool': {},
      'answered.notApprover': {},
      'answered.notAdmin': {},
      'result.allThrough': { count: 'count', itemNoun: 'noun' },
      'result.failedAgain': { count: 'count', itemNoun: 'noun', completed: 'count', failedAgain: 'count', failReason: 'text' },
      'result.skipped': { count: 'count', itemNoun: 'noun', completed: 'count', skipped: 'count' },
      'result.failedAndSkipped': { count: 'count', itemNoun: 'noun', completed: 'count', failedAgain: 'count', failReason: 'text', skipped: 'count' },
      'result.stillResending': { count: 'count', itemNoun: 'noun', completed: 'count' },
      'result.interrupted': { count: 'count', itemNoun: 'noun', completed: 'count', remaining: 'count' },
      'result.couldNotStart': { reason: 'text' },
      'result.stoppedPartway': { count: 'count', itemNoun: 'noun', resent: 'count', completed: 'count', notTried: 'count' },
      'result.itemSuspended': { item: 'text', production: 'text' },
      'result.itemResumed': { item: 'text', production: 'text' },
      'result.itemSkipped': { item: 'text', reason: 'sentence' },
      'result.itemNotChanged': { reason: 'sentence' },
      'result.rerouted': { count: 'count', itemNoun: 'noun', to: 'text' },
      [LINE_KEY]: { resendCount: 'count', reading: 'text', item: 'text' },
      'handled.marked': { time: 'time' },
      [LEARNED_KEY]: { fact: 'text' },
    };
    for (const key of Object.keys(real.PAGE_SLOTS)) assert.deepEqual({ ...real.PAGE_SLOTS[key] }, slots[key] ?? {}, key);
    assert.equal(real.PAGE_TEXTS['bannerAction.budgets'], 'Budgets');
    assert.equal(real.renderPageText(LEARNED_KEY, { fact: "The Results partner's contact is Lee" }), 'I\'ll remember this: "The Results partner\'s contact is Lee". You can tell me to forget it.', 'the ruled line of Story 41.15');
    assert.equal(real.renderPageText(LEARNED_KEY, { fact: ' <b>Lee</b>\n& co ' }), 'I\'ll remember this: "<b>Lee</b> & co". You can tell me to forget it.', 'a text slot is cleaned and never treated as markup');
    for (const key of BANNER_KEYS) assert.equal(typeof real.PAGE_TEXTS[key], 'string', key);
  });

  it('renders the banner texts of the catalog, with the slots as the caller formatted them', () => {
    assert.equal(real.renderPageText('banner.noModelKey'), 'OcuTalon has no model key, so every decision uses fixed rules. Add a key for a supported provider (for example, ANTHROPIC_API_KEY) to the .env file and restart OcuTalon.');
    assert.equal(
      real.renderPageText('banner.costCap', { cap: '$20.00', time: '17:30' }),
      "OcuTalon has reached today's cost limit of $20.00. Decisions use fixed rules until 17:30.",
    );
    assert.equal(
      real.renderPageText('banner.allowance', { limit: '20', time: '5:30 PM' }),
      "You've used this session's 20 messages for the hour (messages you send in the chat or Telegram). You can send more at 5:30 PM.",
    );
    assert.equal(real.renderPageText('banner.reconnecting'), 'Reconnecting\u2026 New messages may be delayed.');
    assert.equal(real.renderPageText('banner.demoBusy'), 'The demo is busy right now. Try again in a few minutes, or install it yourself.');
    assert.equal(real.renderPageText('banner.dailyCap', { time: '$&' }), "The online demo has used today's model allowance. Decisions use fixed rules until $&.", 'a value is never read as a replacement pattern');
    assert.equal(real.renderPageText('banner.dailyCap'), "The online demo has used today's model allowance. Decisions use fixed rules until .", 'a missing slot renders empty');
    assert.equal(real.renderPageText('banner.dailyCap', { time: 5 }), "The online demo has used today's model allowance. Decisions use fixed rules until .", 'a value that is no string renders empty');
    assert.equal(real.renderPageText('banner.dailyCap', { time: ' 17:30\n' }), "The online demo has used today's model allowance. Decisions use fixed rules until 17:30.", 'and a string is cleaned like any string slot');
    assert.equal(real.renderPageText('bannerAction.installYourself'), 'Install it yourself');
    assert.equal(real.renderPageText('bannerAction.howToSetKey'), 'How to set a key');
    assert.equal(real.renderPageText('bannerAction.setUpBot'), 'Set up a bot');
  });
});

describe('the answered texts', () => {
  const at = { time: '14:15' };

  it('read as the UX words them, with the channel by its name, the web wording where the catalog has one', () => {
    assert.deepEqual({ ...real.CHANNEL_NAMES }, { web: 'the web chat', phone: 'the simulated phone', telegram: 'Telegram' });
    assert.equal(real.renderPageText('answered.approved', { channel: 'web', ...at }), 'Approved from the web chat at 14:15');
    assert.equal(real.renderPageText('answered.approvedBy', { user: 'zzsam', channel: 'phone', ...at }), 'Approved by zzsam from the simulated phone at 14:15');
    assert.equal(real.renderPageText('answered.rejected', { channel: 'web', ...at }), 'Rejected from the web chat at 14:15. Nothing was changed.');
    assert.equal(real.renderPageText('answered.rejectedBy', { user: 'zzsam', channel: 'telegram', ...at }), 'Rejected by zzsam from Telegram at 14:15. Nothing was changed.');
    assert.equal(real.renderPageText('answered.expired', { time: '14:13' }), 'Expired at 14:13. Nothing was changed.');
    assert.equal(real.renderPageText('answered.alreadyApproved', { channel: 'phone', ...at }), 'Already answered: approved from the simulated phone at 14:15.');
    assert.equal(real.renderPageText('answered.alreadyRejected', { channel: 'web', ...at }), 'Already answered: rejected from the web chat at 14:15.');
    assert.equal(real.renderPageText('answered.alreadyApprovedBy', { user: 'zzsam', channel: 'phone', ...at }), 'Already answered: approved by zzsam from the simulated phone at 14:15.');
    assert.equal(real.renderPageText('answered.alreadyRejectedBy', { user: 'zzsam', channel: 'telegram', ...at }), 'Already answered: rejected by zzsam from Telegram at 14:15.');
  });

  it('give an unknown channel code as it is, clean a text slot like any string, and never read a value as a placeholder', () => {
    assert.equal(real.renderPageText('answered.approved', { channel: 'slack', ...at }), 'Approved from slack at 14:15');
    for (const channel of ['constructor', '__proto__', 'toString', '', 5, null, undefined]) {
      assert.equal(real.renderPageText('answered.approved', { channel, ...at }), `Approved from ${typeof channel === 'string' ? channel : ''} at 14:15`, String(channel));
    }
    assert.equal(real.renderPageText('answered.approvedBy', { user: ' zz\nsam\u200B ', channel: ' web ', ...at }), 'Approved by zz sam from the web chat at 14:15');
    assert.equal(real.renderPageText('answered.approvedBy', { user: '{time}', channel: 'web', time: '$&' }), 'Approved by {time} from the web chat at $&');
  });
});

describe('the result texts of a fix the user asks for in the chat (Story 23.2, DW-1067)', () => {
  const noun = { one: 'order', other: 'orders' };

  it('read as the Public Text gives them, with the count-of-one form of the reroute and no doubled full stop after a sentence', () => {
    assert.equal(real.renderPageText('result.itemSuspended', { item: 'OrdersToWarehouse', production: 'Demo.Orders' }), 'OrdersToWarehouse in Demo.Orders is suspended: it is disabled now. To undo it while this incident is open, ask me to resume OrdersToWarehouse. After the incident closes, enable OrdersToWarehouse again on the production\'s configuration page in the Management Portal.');
    assert.equal(real.renderPageText('result.itemResumed', { item: 'OrdersToWarehouse', production: 'Demo.Orders' }), 'OrdersToWarehouse in Demo.Orders is enabled again.');
    assert.equal(real.renderPageText('result.itemSkipped', { item: 'OrdersToWarehouse', reason: 'OrdersToWarehouse is already disabled' }), 'OrdersToWarehouse was not changed: OrdersToWarehouse is already disabled. It needs a new approval.');
    assert.equal(real.renderPageText('result.itemNotChanged', { reason: "OcuTalon couldn't change the item" }), "Nothing was changed: OcuTalon couldn't change the item.");
    assert.equal(real.renderPageText('result.rerouted', { count: '50', itemNoun: noun, to: 'OrdersForReview' }), 'All 50 orders were rerouted to OrdersForReview and completed there. The originals stay unchanged.');
    assert.equal(real.renderPageText('result.rerouted', { count: '1', itemNoun: noun, to: 'OrdersForReview' }), 'The order was rerouted to OrdersForReview and completed there. The original stays unchanged.');
    assert.equal(real.renderPageText('result.itemNotChanged', { reason: 'It failed.' }), 'Nothing was changed: It failed.', 'a sentence that ends with a full stop keeps one');
    assert.equal(real.renderPageText('result.itemNotChanged', { reason: 'Why?' }), 'Nothing was changed: Why?', 'a question mark ends the sentence in place of the full stop');
    assert.equal(real.renderPageText('result.itemSkipped', { item: 'A', reason: 'gone\u2026' }), 'A was not changed: gone\u2026 It needs a new approval.', 'and so does an ellipsis');
    assert.equal(real.renderPageText('result.itemNotChanged', { reason: '' }), 'Nothing was changed: .', 'an empty sentence takes the full stop of the text');
    assert.equal(real.renderPageText('result.couldNotStart', { reason: 'it failed.' }), 'Nothing was resent: it failed.. Nothing was changed.', 'a text slot is as before');
  });

  it('allows a sentence slot on the two keys of SENTENCE_SLOT_KEYS only, and a text slot on the keys that name an item, a production or a target', async () => {
    const { LISTED_KEYS, SENTENCE_SLOT_KEYS } = await import(pathToFileURL(script).href);
    assert.deepEqual(SENTENCE_SLOT_KEYS, ['result.itemSkipped', 'result.itemNotChanged']);
    for (const key of LISTED_KEYS.filter((one) => one !== LINE_KEY)) {
      const inWatch = Object.hasOwn(WATCH, key);
      const entry = (inWatch ? WATCH : GOOD)[key];
      const withSentence = { ...entry, slots: { ...entry.slots, extra: 'sentence' } };
      const r = run(...fixture(`extra-sentence-${key}`, inWatch ? { watchEntries: { ...WATCH, [key]: withSentence } } : { entries: { ...GOOD, [key]: withSentence } }));
      if (SENTENCE_SLOT_KEYS.includes(key)) {
        assert.equal(r.status, 0, `${key}: ${r.stderr}`);
      } else {
        assert.equal(r.status, 1, key);
        assert.ok(r.stderr.includes(`'${key}' has the slot 'extra' of type 'sentence'`), `${key}: ${r.stderr}`);
      }
    }
  });

  it('renders a sentence slot with the full stop rule of the server and a text slot unchanged, in the page text and in the message text', async () => {
    const args = fixture('sentence-stop');
    assert.equal(run(...args).status, 0);
    const module = await import(pathToFileURL(args[5]).href);
    for (const render of [module.renderPageText, module.renderMessageText]) {
      assert.equal(render('result.itemNotChanged', { reason: 'it broke' }), 'Not changed: it broke.');
      assert.equal(render('result.itemNotChanged', { reason: 'it broke.' }), 'Not changed: it broke.');
      assert.equal(render('result.itemNotChanged', { reason: 'it broke!' }), 'Not changed: it broke!');
      assert.equal(render('result.itemSkipped', { item: 'A', reason: ' it\n broke. ' }), 'A skipped: it broke.', 'cleaned like any string slot');
      assert.equal(render('result.couldNotStart', { reason: 'it broke.' }), 'Not started: it broke..', 'a text slot keeps the full stop of the text');
    }
  });
});

describe('the result texts', () => {
  const noun = { one: 'order', other: 'orders' };
  const reason = "the order date still wasn't accepted";

  it('read as Catalog.RenderAt gives them for 50 orders (the Fixtures XData of Test.Msg.Catalog)', () => {
    assert.equal(real.renderPageText('result.allThrough', { count: '50', itemNoun: noun }), 'All 50 orders went through.');
    assert.equal(
      real.renderPageText('result.failedAgain', { count: '50', itemNoun: noun, completed: '48', failedAgain: '2', failReason: reason }),
      "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval.",
    );
    assert.equal(
      real.renderPageText('result.skipped', { count: '50', itemNoun: noun, completed: '47', skipped: '3' }),
      '47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.',
    );
    assert.equal(
      real.renderPageText('result.failedAndSkipped', { count: '50', itemNoun: noun, completed: '45', failedAgain: '2', failReason: reason, skipped: '3' }),
      "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval.",
    );
    assert.equal(
      real.renderPageText('result.stillResending', { count: '50', itemNoun: noun, completed: '30' }),
      "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done.",
    );
    assert.equal(
      real.renderPageText('result.interrupted', { count: '50', itemNoun: noun, completed: '30', remaining: '20' }),
      'The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval.',
    );
    assert.equal(
      real.renderPageText('result.couldNotStart', { reason: "OcuTalon isn't allowed to resend messages in that production" }),
      "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed.",
    );
    assert.equal(
      real.renderPageText('result.stoppedPartway', { count: '3', itemNoun: noun, resent: '2', completed: '2', notTried: '0' }),
      "The resend stopped partway: I resent 2 of the 3 orders (2 went through), the next one couldn't be resent, and 0 more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
    );
    assert.equal(real.renderPageText('audit.recorded'), 'Recorded in the IRIS audit log.');
  });

  it('reads the Got it button and the handled line as the catalog gives them (Story 18.4)', () => {
    assert.equal(real.renderPageText('button.gotIt'), 'Got it');
    assert.equal(real.renderPageText('handled.marked', { time: '14:12' }), 'Marked as handled at 14:12');
  });

  it('read the catalog\'s count-of-one form where the named count slot is 1, and the noun by the count slot', () => {
    assert.deepEqual(Object.keys(real.PAGE_ONE_FORMS), ['result.allThrough', 'result.failedAgain', 'result.skipped', 'result.failedAndSkipped', 'result.stillResending', 'result.interrupted', 'result.stoppedPartway', 'result.rerouted', LINE_KEY]);
    assert.deepEqual(Object.fromEntries(Object.entries(real.PAGE_ONE_FORMS).map(([key, form]) => [key, form.slot])), {
      'result.allThrough': 'count',
      'result.failedAgain': 'failedAgain',
      'result.skipped': 'skipped',
      'result.failedAndSkipped': 'skipped',
      'result.stillResending': 'completed',
      'result.interrupted': 'remaining',
      'result.stoppedPartway': 'notTried',
      'result.rerouted': 'count',
      [LINE_KEY]: 'resendCount',
    });
    assert.equal(real.renderPageText('result.allThrough', { count: '1', itemNoun: noun }), 'The order went through.');
    assert.equal(
      real.renderPageText('result.failedAgain', { count: '50', itemNoun: noun, completed: '49', failedAgain: '1', failReason: reason }),
      "49 of 50 orders went through. 1 failed again (the order date still wasn't accepted). I won't retry it without a new approval.",
    );
    assert.equal(
      real.renderPageText('result.failedAgain', { count: '1', itemNoun: noun, completed: '0', failedAgain: '1', failReason: 'X' }),
      "0 of 1 order went through. 1 failed again (X). I won't retry it without a new approval.",
      'the noun follows the count slot, the one form the failedAgain slot',
    );
    assert.equal(
      real.renderPageText('result.skipped', { count: '50', itemNoun: noun, completed: '49', skipped: '1' }),
      '49 of 50 orders went through. 1 had changed since the dry run, so I skipped it; it needs a new approval.',
    );
    assert.equal(
      real.renderPageText('result.failedAndSkipped', { count: '50', itemNoun: noun, completed: '47', failedAgain: '2', failReason: reason, skipped: '1' }),
      "47 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 1 had changed since the dry run, so I skipped it. I won't retry any of them without a new approval.",
    );
    assert.equal(
      real.renderPageText('result.failedAndSkipped', { count: '50', itemNoun: noun, completed: '47', failedAgain: '1', failReason: reason, skipped: '2' }),
      "47 of 50 orders went through. 1 failed again (the order date still wasn't accepted), and 2 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval.",
      'the skipped slot decides, not failedAgain',
    );
    assert.equal(
      real.renderPageText('result.stillResending', { count: '50', itemNoun: noun, completed: '1' }),
      "Still resending: 1 of 50 orders has gone through so far. I'll tell you when it's done.",
    );
    assert.equal(
      real.renderPageText('result.interrupted', { count: '50', itemNoun: noun, completed: '49', remaining: '1' }),
      'The resend stopped when OcuTalon restarted: 49 of 50 orders went through. The other one needs a new approval.',
    );
    assert.equal(
      real.renderPageText('result.stoppedPartway', { count: '4', itemNoun: noun, resent: '3', completed: '2', notTried: '1' }),
      "The resend stopped partway: I resent 3 of the 4 orders (2 went through), the next one couldn't be resent, and 1 more wasn't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
      'the notTried slot decides the one form',
    );
    assert.equal(real.renderPageText('result.allThrough', { count: '2', itemNoun: noun }), 'All 2 orders went through.');
    assert.equal(real.renderPageText('result.allThrough', { count: 1, itemNoun: noun }), 'All  orders went through.', 'a count that is no string is not "1"');
  });

  it('clean the noun forms like any string slot, and never read a value as a placeholder', () => {
    assert.equal(real.renderPageText('result.allThrough', { count: '50', itemNoun: { one: 'order', other: ' ord\ners ' } }), 'All 50 ord ers went through.');
    assert.equal(real.renderPageText('result.allThrough', { count: '50', itemNoun: { one: 'order' } }), 'All 50  went through.', 'a missing form is empty');
    for (const bad of [null, undefined, 'orders', 5, []]) {
      assert.equal(real.renderPageText('result.allThrough', { count: '50', itemNoun: bad }), 'All 50  went through.', JSON.stringify(bad));
    }
    assert.equal(real.renderPageText('result.couldNotStart', { reason: '{reason} $&' }), 'Nothing was resent: {reason} $&. Nothing was changed.');
  });
});

describe('the message form', () => {
  const clock = { time: '14:15' };

  it('holds the text form of the listed keys that have a web form, and nothing else', () => {
    assert.deepEqual({ ...real.MESSAGE_TEXTS }, {
      'answered.approved': 'Approved from {channel} at {time}.',
      'answered.approvedBy': 'Approved by {user} from {channel} at {time}.',
    });
  });

  it('reads as the server renders the phone text, with the channel by its name', () => {
    assert.equal(real.renderMessageText('answered.approved', { channel: 'phone', ...clock }), 'Approved from the simulated phone at 14:15.');
    assert.equal(real.renderMessageText('answered.approved', { channel: 'web', ...clock }), 'Approved from the web chat at 14:15.');
    assert.equal(real.renderMessageText('answered.approvedBy', { user: 'zzsam', channel: 'telegram', ...clock }), 'Approved by zzsam from Telegram at 14:15.');
    assert.equal(real.renderMessageText('answered.rejected', { channel: 'phone', ...clock }), 'Rejected from the simulated phone at 14:15. Nothing was changed.');
    assert.equal(real.renderMessageText('answered.rejectedBy', { user: 'zzsam', channel: 'web', ...clock }), 'Rejected by zzsam from the web chat at 14:15. Nothing was changed.');
    assert.equal(real.renderMessageText('answered.expired', { time: '14:13' }), 'Expired at 14:13. Nothing was changed.');
  });

  it('turns the "at" before a dated time into "on", as the renderer does, and leaves a clock time and the online demo\'s ET alone', () => {
    assert.equal(real.renderMessageText('answered.approved', { channel: 'web', time: 'Thursday at 14:12' }), 'Approved from the web chat on Thursday at 14:12.');
    assert.equal(real.renderMessageText('answered.rejected', { channel: 'phone', time: 'Oct 16, 2026 at 14:12' }), 'Rejected from the simulated phone on Oct 16, 2026 at 14:12. Nothing was changed.');
    assert.equal(real.renderMessageText('answered.approved', { channel: 'web', time: '14:12 ET' }), 'Approved from the web chat at 14:12 ET.');
    assert.equal(real.renderMessageText('answered.approved', { channel: 'web', time: 'Thursday at 14:12 ET' }), 'Approved from the web chat on Thursday at 14:12 ET.');
    assert.equal(real.renderMessageText('answered.expired', { time: 'tomorrow at 14:12' }), 'Expired on tomorrow at 14:12. Nothing was changed.');
  });

  it('falls back to the page text for a key with no message form, and throws for an unknown key', () => {
    assert.equal(real.renderMessageText('answered.alreadyApproved', { channel: 'web', ...clock }), real.renderPageText('answered.alreadyApproved', { channel: 'web', ...clock }));
    assert.equal(real.renderMessageText('answered.alreadyApproved', { channel: 'web', ...clock }), 'Already answered: approved from the web chat at 14:15.');
    assert.equal(real.renderMessageText('answered.alreadyApproved', { channel: 'web', time: 'Thursday at 14:12' }), 'Already answered: approved from the web chat on Thursday at 14:12.');
    assert.equal(real.renderMessageText('checks.allPassed'), 'Everything I checked passed.');
    assert.equal(real.renderMessageText('result.allThrough', { count: '1', itemNoun: { one: 'order', other: 'orders' } }), 'The order went through.', 'and its count-of-one form');
    assert.throws(() => real.renderMessageText('zz.unknown'), /no catalog text for 'zz.unknown'/);
    assert.throws(() => real.renderMessageText('constructor'), /no catalog text/);
  });

  it('fills in one pass: a value is never a placeholder or a replacement pattern, and a non-time slot named like a time never makes an "on"', () => {
    assert.equal(real.renderMessageText('answered.approvedBy', { user: '{time}', channel: 'web', time: '$&' }), 'Approved by {time} from the web chat on $&.');
    assert.equal(real.renderMessageText('answered.approvedBy', { user: 'at', channel: 'web', ...clock }), 'Approved by at from the web chat at 14:15.');
    assert.equal(real.renderMessageText('answered.approved', { channel: 'web' }), 'Approved from the web chat on .', 'a missing time is not a clock time');
  });
});

describe('the check sentences', () => {
  it('read as the UX words them, from the Watch catalog', () => {
    assert.equal(real.renderPageText('checks.allPassed'), 'Everything I checked passed.');
    assert.equal(real.renderPageText('checks.everythingElsePassed'), 'Everything else I checked passed.');
    assert.equal(real.renderPageText('checks.nothingWatched'), "I'm not watching any productions yet, so I can't say. Ask me to watch one.");
  });

  it('render both whatFailed keys with the value the page built, cleaned like any string slot', () => {
    assert.equal(real.renderPageText('checks.notEverything', { whatFailed: 'Orders production (3 new failures, at 14:13)' }), 'Not everything: Orders production (3 new failures, at 14:13).');
    assert.equal(
      real.renderPageText('checks.notEverythingRestPassed', { whatFailed: ' A (x); B\n' }),
      'Not everything: A (x); B. Everything else I checked passed.',
    );
    assert.deepEqual({ ...real.PAGE_SLOTS['checks.notEverything'] }, { whatFailed: 'text' });
    assert.deepEqual({ ...real.PAGE_SLOTS['checks.notEverythingRestPassed'] }, { whatFailed: 'text' });
  });
});

describe('the fallback sentence', () => {
  /** Each FALLBACKREASON value with the UX's words for it. */
  const REASONS = {
    no_key: 'no model key is set',
    daily_cap: "today's cost limit has been reached",
    budget: 'this would have gone over the token budget',
    too_large: 'this request would have been too large to send',
    timeout: "the model didn't answer within the time allowed",
    rate_limited: 'the model was too busy to answer',
    error: 'the model returned an error',
    refusal: 'the model declined to answer',
    cut_off: "the model's reply was cut off",
    empty: "the model's reply was empty",
    invalid: "the model's reply couldn't be used",
    unusable: "the model's reply couldn't be used",
  };
  const sentence = (reason) => `I couldn't answer that: ${reason}. Nothing was changed.`;

  it('reads "I couldn\'t answer that: {reason}. Nothing was changed." for each of the 12 reasons', () => {
    assert.equal(Object.keys(REASONS).length, 12);
    for (const [value, words] of Object.entries(REASONS)) {
      assert.equal(real.renderPageText('conversation.turnFallback', { fallbackReason: value }), sentence(words), value);
    }
  });

  it('gives the generic reason for a value that is none of them', () => {
    const generic = sentence("the model's reply couldn't be used");
    for (const value of ['nonsense', '', ' ', 'TIMEOUT', 'constructor', '__proto__', 'toString', 'hasOwnProperty', 42, null, undefined, {}, ['timeout']]) {
      assert.equal(real.renderPageText('conversation.turnFallback', { fallbackReason: value }), generic, JSON.stringify(value));
    }
    assert.equal(real.renderPageText('conversation.turnFallback'), generic, 'a missing slot');
    assert.equal(real.renderPageText('conversation.turnFallback', { other: 'timeout' }), generic, 'another slot');
  });

  it('trims a slot value and drops its control characters, as the catalog does for a string slot', () => {
    const timeout = sentence("the model didn't answer within the time allowed");
    for (const value of [' timeout', 'timeout\n', '\ttimeout ', 'time\u0000out', 'time\u200Bout', '\u202Etimeout']) {
      assert.equal(real.renderPageText('conversation.turnFallback', { fallbackReason: value }), timeout, JSON.stringify(value));
    }
  });

  it('renders the reasons\' own keys and refuses a key that the page does not render', () => {
    assert.equal(real.renderPageText('fallbackReason.timeout'), "the model didn't answer within the time allowed");
    assert.throws(() => real.renderPageText('conversation.dailyCap'), /no catalog text for 'conversation\.dailyCap'/);
    assert.throws(() => real.renderPageText('constructor'), /no catalog text/);
  });
});

/** The text of a Core.cls fixture holding these entries in an XData block like the real one. */
const coreClass = (entries) => `/// A fixture.\nClass OcuTalon.Msg.Catalog.Core\n{\n\nXData Entries [ MimeType = application/json ]\n{\n${entries}\n}\n\n}\n`;
const watchClass = (entries) => `/// A fixture.\nClass OcuTalon.Msg.Catalog.Watch\n{\n\nXData Entries [ MimeType = application/json ]\n{\n${entries}\n}\n\n}\n`;
const catalogClass = (reasons, channels = 'web=the web chat,phone=the simulated phone') =>
  `/// A fixture.\nClass OcuTalon.Msg.Catalog\n{\n\nParameter REASONKEYS = "${reasons}";\n${channels === null ? '' : `\nParameter CHANNELNAMES = "${channels}";\n`}\n}\n`;

/** The banner and action entries of the fixtures: the slot types of the real ones, with texts of their own. */
const BANNERS = {
  'banner.allowance': { text: 'Used {limit} until {time}.', slots: { limit: 'count', time: 'time' }, source: 'fixture' },
  'banner.allowanceChat': { text: 'Used {limit} in chat until {time}.', slots: { limit: 'count', time: 'time' }, source: 'fixture' },
  'banner.dailyCap': { text: 'Capped until {time}.', slots: { time: 'time' }, source: 'fixture' },
  'banner.unreachable': { text: 'Unreachable.', slots: {}, source: 'fixture' },
  'banner.noModelKey': { text: 'No key.', slots: {}, source: 'fixture' },
  'banner.costCap': { text: 'Limit {cap} until {time}.', slots: { cap: 'cost', time: 'time' }, source: 'fixture' },
  'banner.heartbeatStalled': { text: 'Stalled at {time}.', slots: { time: 'time' }, source: 'fixture' },
  'banner.telegramPaused': { text: 'Paused until {time}.', slots: { time: 'time' }, source: 'fixture' },
  'banner.resetSoon': { text: 'Resets soon.', slots: {}, source: 'fixture' },
  'banner.resetSoonChat': { text: 'Resets soon, chat.', slots: {}, source: 'fixture' },
  'banner.reconnecting': { text: 'Reconnecting.', slots: {}, source: 'fixture' },
  'banner.demoBusy': { text: 'Busy.', slots: {}, source: 'fixture' },
  'bannerAction.installYourself': { text: 'Install.', slots: {}, source: 'fixture' },
  'bannerAction.howToSetKey': { text: 'Set a key.', slots: {}, source: 'fixture' },
  'bannerAction.budgets': { text: 'Budgets.', slots: {}, source: 'fixture' },
  'bannerAction.setUpBot': { text: 'Set up.', slots: {}, source: 'fixture' },
};

/** The answered entries of the fixtures: the slot types of the real ones, with texts of their own. */
const ANSWERED = {
  'answered.approved': { text: 'Yes from {channel} at {time}.', web: 'Yes from {channel} at {time}', slots: { channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.approvedBy': { text: 'Yes by {user} from {channel} at {time}.', slots: { user: 'text', channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.rejected': { text: 'No from {channel} at {time}.', slots: { channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.rejectedBy': { text: 'No by {user} from {channel} at {time}.', slots: { user: 'text', channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.expired': { text: 'Expired at {time}.', slots: { time: 'time' }, source: 'fixture' },
  'answered.alreadyApproved': { text: 'Late: yes from {channel} at {time}.', slots: { channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.alreadyRejected': { text: 'Late: no from {channel} at {time}.', slots: { channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.alreadyApprovedBy': { text: 'Late: yes by {user} from {channel} at {time}.', slots: { user: 'text', channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.alreadyRejectedBy': { text: 'Late: no by {user} from {channel} at {time}.', slots: { user: 'text', channel: 'channel', time: 'time' }, source: 'fixture' },
  'answered.notApproverResend': { text: 'Fixture notApproverResend.', slots: {}, source: 'fixture' },
  'answered.notApproverReroute': { text: 'Fixture notApproverReroute.', slots: {}, source: 'fixture' },
  'answered.notApproverSuspend': { text: 'Fixture notApproverSuspend.', slots: {}, source: 'fixture' },
  'answered.notApproverRollback': { text: 'Fixture notApproverRollback.', slots: {}, source: 'fixture' },
  'answered.notApproverPartner': { text: 'Fixture notApproverPartner.', slots: {}, source: 'fixture' },
  'answered.notApproverEmail': { text: 'Fixture notApproverEmail.', slots: {}, source: 'fixture' },
  'answered.notApproverTool': { text: 'Fixture notApproverTool.', slots: {}, source: 'fixture' },
  'answered.notApprover': { text: 'Fixture notApprover.', slots: {}, source: 'fixture' },
  'answered.notAdmin': { text: 'Fixture notAdmin.', slots: {}, source: 'fixture' },
};

/** The result and audit entries of the fixtures: the slot types and one forms of the real ones, with texts of their own. */
const RESULTS = {
  'result.allThrough': { text: 'All {count} {itemNoun} done.', slots: { count: 'count', itemNoun: 'noun' }, source: 'fixture', one: { slot: 'count', text: 'The {itemNoun} done.' } },
  'result.failedAgain': { text: '{completed}/{count} {itemNoun}; {failedAgain} failed ({failReason}).', slots: { count: 'count', itemNoun: 'noun', completed: 'count', failedAgain: 'count', failReason: 'text' }, source: 'fixture', one: { slot: 'failedAgain', text: '{completed}/{count} {itemNoun}; 1 failed ({failReason}).' } },
  'result.skipped': { text: '{completed}/{count} {itemNoun}; {skipped} skipped.', slots: { count: 'count', itemNoun: 'noun', completed: 'count', skipped: 'count' }, source: 'fixture', one: { slot: 'skipped', text: '{completed}/{count} {itemNoun}; 1 skipped.' } },
  'result.failedAndSkipped': { text: '{completed}/{count} {itemNoun}; {failedAgain} failed ({failReason}), {skipped} skipped.', slots: { count: 'count', itemNoun: 'noun', completed: 'count', failedAgain: 'count', failReason: 'text', skipped: 'count' }, source: 'fixture', one: { slot: 'skipped', text: '{completed}/{count} {itemNoun}; {failedAgain} failed ({failReason}), 1 skipped.' } },
  'result.stillResending': { text: 'Still: {completed}/{count} {itemNoun}.', slots: { count: 'count', itemNoun: 'noun', completed: 'count' }, source: 'fixture', one: { slot: 'completed', text: 'Still: 1/{count} {itemNoun}.' } },
  'result.interrupted': { text: 'Stopped: {completed}/{count} {itemNoun}; {remaining} left.', slots: { count: 'count', itemNoun: 'noun', completed: 'count', remaining: 'count' }, source: 'fixture', one: { slot: 'remaining', text: 'Stopped: {completed}/{count} {itemNoun}; one left.' } },
  'result.couldNotStart': { text: 'Not started: {reason}.', slots: { reason: 'text' }, source: 'fixture' },
  'result.stoppedPartway': { text: 'Partway: {resent}/{count} {itemNoun}, {completed} through; {notTried} not tried.', slots: { count: 'count', itemNoun: 'noun', resent: 'count', completed: 'count', notTried: 'count' }, source: 'fixture', one: { slot: 'notTried', text: 'Partway: {resent}/{count} {itemNoun}, {completed} through; 1 not tried.' } },
  'result.itemSuspended': { text: '{item} in {production} suspended.', slots: { item: 'text', production: 'text' }, source: 'fixture' },
  'result.itemResumed': { text: '{item} in {production} resumed.', slots: { item: 'text', production: 'text' }, source: 'fixture' },
  'result.itemSkipped': { text: '{item} skipped: {reason}.', slots: { item: 'text', reason: 'sentence' }, source: 'fixture' },
  'result.itemNotChanged': { text: 'Not changed: {reason}.', slots: { reason: 'sentence' }, source: 'fixture' },
  'result.rerouted': { text: 'All {count} {itemNoun} sent to {to}.', slots: { count: 'count', itemNoun: 'noun', to: 'text' }, source: 'fixture', one: { slot: 'count', text: 'The {itemNoun} sent to {to}.' } },
  'audit.recorded': { text: 'Logged.', slots: {}, source: 'fixture' },
};

const GOOD = {
  'conversation.turnFallback': { text: "I couldn't answer that: {fallbackReason}. Nothing was changed.", slots: { fallbackReason: 'fallbackReason' }, source: 'fixture' },
  ...BANNERS,
  ...ANSWERED,
  ...RESULTS,
  'fallbackReason.timeout': { text: 'it timed out', slots: {}, source: 'fixture' },
  'fallbackReason.generic': { text: 'it failed', slots: {}, source: 'fixture' },
  'pairing.paired': { text: 'Not listed: {time}', slots: { time: 'time' }, source: 'fixture' },
  [LEARNED_KEY]: { text: 'Learned: "{fact}".', slots: { fact: 'text' }, source: 'fixture' },
};

/**
 * One of the two entries that hold the either-way line, in the shape of the real ones: four forms (text, web, one.text, one.web), each with the line between
 * "becomes {after}. " and " I'll resend". A form can be given another line, or other words around it, to break one rule of the generator.
 */
function eitherParent(lead, forms = {}) {
  const { many = [LINE_MANY, LINE_MANY], one = [LINE_ONE, LINE_ONE], start = 'becomes {after}. ', end = " I'll resend" } = forms;
  const form = (line, tail) => `${lead} Example: x ${start}${line}${end} ${tail}`;
  return {
    text: form(many[0], '{resendCount} repaired copies. Approve?'),
    web: form(many[1], '{resendCount} repaired copies.'),
    slots: { count: 'count', itemNoun: 'noun', after: 'text', resendCount: 'count', reading: 'text', item: 'text' },
    source: 'fixture',
    one: { slot: 'resendCount', text: form(one[0], '1 repaired copy. Approve?'), web: form(one[1], '1 repaired copy.') },
  };
}

/** The Watch catalog of the fixtures: the five check sentences the page renders, the two Got it keys, and the two entries that hold the either-way line. */
const WATCH = {
  [LINE_PARENTS[0]]: eitherParent('{count} {itemNoun} failed.'),
  [LINE_PARENTS[1]]: eitherParent('{count} more {itemNoun} failed.'),
  'checks.allPassed': { text: 'All fine.', slots: {}, source: 'fixture' },
  'checks.everythingElsePassed': { text: 'The rest was fine.', slots: {}, source: 'fixture' },
  'checks.nothingWatched': { text: "Nothing's watched.", slots: {}, source: 'fixture' },
  'checks.notEverything': { text: 'Not everything: {whatFailed}.', slots: { whatFailed: 'text' }, source: 'fixture' },
  'checks.notEverythingRestPassed': { text: 'Not everything: {whatFailed}. The rest was fine.', slots: { whatFailed: 'text' }, source: 'fixture' },
  'button.gotIt': { text: 'Understood', slots: {}, source: 'fixture' },
  'handled.marked': { text: 'Handled at {time}', slots: { time: 'time' }, source: 'fixture' },
};

/** Writes a fixture trio and returns the arguments that point the generator at it (the --watch pair is last). */
function fixture(name, { entries = GOOD, reasons = 'timeout=timeout,invalid=generic', channels = undefined, core = coreClass(JSON.stringify(entries, null, 1)), watchEntries = WATCH, watch = watchClass(JSON.stringify(watchEntries, null, 1)) } = {}) {
  const dir = join(work, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'Core.cls'), core);
  writeFileSync(join(dir, 'Watch.cls'), watch);
  writeFileSync(join(dir, 'Catalog.cls'), catalogClass(reasons, channels));
  return ['--core', join(dir, 'Core.cls'), '--catalog', join(dir, 'Catalog.cls'), '--out', join(dir, 'catalog.ts'), '--watch', join(dir, 'Watch.cls')];
}

const without = (key) => Object.fromEntries(Object.entries(GOOD).filter(([name]) => name !== key));

describe('the generator on a fixture', () => {
  it('keeps the listed keys only, in the listed order and then the reasons\' in the Core order, and fills the reason map', async () => {
    const args = fixture('good');
    const r = run(...args);
    assert.equal(r.status, 0, r.stderr);
    const module = await import(pathToFileURL(args[5]).href);
    assert.deepEqual(Object.keys(module.PAGE_TEXTS), ['conversation.turnFallback', ...CHECK_KEYS, ...BANNER_KEYS, ...ANSWERED_KEYS, ...RESULT_KEYS, LINE_KEY, ...GOT_IT_KEYS, LEARNED_KEY, 'fallbackReason.timeout', 'fallbackReason.generic']);
    assert.deepEqual(Object.keys(module.PAGE_SLOTS), ['conversation.turnFallback', ...CHECK_KEYS, ...BANNER_KEYS, ...ANSWERED_KEYS, ...RESULT_KEYS, LINE_KEY, ...GOT_IT_KEYS, LEARNED_KEY]);
    assert.deepEqual({ ...module.PAGE_SLOTS['checks.notEverything'] }, { whatFailed: 'text' });
    assert.deepEqual({ ...module.PAGE_SLOTS['handled.marked'] }, { time: 'time' });
    assert.equal(module.renderPageText('handled.marked', { time: '14:12' }), 'Handled at 14:12');
    assert.equal(module.renderPageText('checks.notEverythingRestPassed', { whatFailed: 'A (x)' }), 'Not everything: A (x). The rest was fine.');
    assert.deepEqual(Object.keys(module.PAGE_ONE_FORMS), ['result.allThrough', 'result.failedAgain', 'result.skipped', 'result.failedAndSkipped', 'result.stillResending', 'result.interrupted', 'result.stoppedPartway', 'result.rerouted', LINE_KEY]);
    assert.deepEqual({ ...module.CHANNEL_NAMES }, { web: 'the web chat', phone: 'the simulated phone' });
    assert.deepEqual({ ...module.MESSAGE_TEXTS }, { 'answered.approved': 'Yes from {channel} at {time}.' }, 'the text form of the one listed key with a web form');
    assert.equal(module.renderMessageText('answered.approved', { channel: 'phone', time: 'Monday at 09:00' }), 'Yes from the simulated phone on Monday at 09:00.');
    assert.equal(module.renderMessageText('answered.rejected', { channel: 'phone', time: '09:00' }), 'No from the simulated phone at 09:00.');
    assert.deepEqual({ ...module.PAGE_SLOTS['banner.costCap'] }, { cap: 'cost', time: 'time' });
    assert.deepEqual({ ...module.PAGE_SLOTS['banner.allowance'] }, { limit: 'count', time: 'time' });
    assert.deepEqual({ ...module.PAGE_SLOTS['conversation.turnFallback'] }, { fallbackReason: 'fallbackReason' });
    assert.deepEqual({ ...module.PAGE_SLOTS['banner.resetSoon'] }, {});
    assert.equal(module.renderPageText('checks.allPassed'), 'All fine.');
    assert.equal(module.renderPageText('checks.nothingWatched'), "Nothing's watched.");
    assert.deepEqual({ ...module.REASON_KEYS }, { timeout: 'timeout', invalid: 'generic' });
    assert.equal(module.renderPageText('conversation.turnFallback', { fallbackReason: 'timeout' }), "I couldn't answer that: it timed out. Nothing was changed.");
    assert.equal(module.renderPageText('conversation.turnFallback', { fallbackReason: 'other' }), "I couldn't answer that: it failed. Nothing was changed.");
  });

  it('uses an entry\'s web text, else its text', async () => {
    const entries = { ...GOOD, 'fallbackReason.timeout': { text: 'it timed out', web: 'it timed out on the page', slots: {} } };
    const args = fixture('web', { entries });
    assert.equal(run(...args).status, 0);
    const module = await import(pathToFileURL(args[5]).href);
    assert.equal(module.PAGE_TEXTS['fallbackReason.timeout'], 'it timed out on the page');
    assert.equal(module.PAGE_TEXTS['fallbackReason.generic'], 'it failed');
  });

  it('renders a time, cost or count slot as the string it is given, and a fallbackReason slot as its reason text', async () => {
    const args = fixture('slots');
    assert.equal(run(...args).status, 0);
    const module = await import(pathToFileURL(args[5]).href);
    assert.equal(module.renderPageText('banner.costCap', { cap: '$20.00', time: '17:30' }), 'Limit $20.00 until 17:30.');
    assert.equal(module.renderPageText('banner.allowance', { limit: '20', time: '5:30 PM' }), 'Used 20 until 5:30 PM.');
    assert.equal(module.renderPageText('banner.costCap', { cap: ' $20.00\n', time: 'a\u200Bb' }), 'Limit $20.00 until ab.', 'cleaned like any string slot');
    assert.equal(module.renderPageText('banner.costCap', { cap: 20, time: null }), 'Limit  until .', 'a value that is no string, or absent, gives an empty string');
    assert.equal(module.renderPageText('banner.costCap', { cap: '{time}', time: '17:30' }), 'Limit {time} until 17:30.', 'one pass: a value is not read as a placeholder');
    assert.equal(module.renderPageText('banner.costCap', { cap: '$&', time: "$'" }), "Limit $& until $'.", 'and not as a replacement pattern');
    assert.equal(module.renderPageText('conversation.turnFallback', { fallbackReason: 'timeout' }), "I couldn't answer that: it timed out. Nothing was changed.");
    assert.equal(module.renderPageText('conversation.turnFallback', { fallbackReason: '17:30' }), "I couldn't answer that: it failed. Nothing was changed.");
  });

  it('fails on an entry whose text form uses a placeholder it does not declare, or has a stray brace', () => {
    for (const [name, text] of [['undeclared', 'Yes {nobody} at {time}.'], ['brace', 'Yes } at {time}.']]) {
      const entries = { ...GOOD, 'answered.approved': { ...GOOD['answered.approved'], text } };
      const r = run(...fixture(`message-${name}`, { entries }));
      assert.equal(r.status, 1, name);
      assert.match(r.stderr, /answered\.approved/, name);
    }
  });

  it('writes a non-ASCII character of a text as an escape sequence', async () => {
    const entries = { ...GOOD, 'fallbackReason.generic': { text: 'it failed \u2014 sorry', slots: {} } };
    const args = fixture('escape', { entries });
    assert.equal(run(...args).status, 0);
    const text = readFileSync(args[5], 'utf8');
    assert.ok(!/[^\x20-\x7e\n]/.test(text), 'ASCII only');
    assert.ok(text.includes('\\u2014'), 'the dash is an escape');
    assert.equal((await import(pathToFileURL(args[5]).href)).PAGE_TEXTS['fallbackReason.generic'], 'it failed \u2014 sorry');
  });

  it('fails, naming the file and the key, on a listed key that is missing', () => {
    const args = fixture('missing', { entries: without('conversation.turnFallback') });
    const r = run(...args);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Core\.cls/);
    assert.match(r.stderr, /conversation\.turnFallback/);
    assert.match(r.stderr, /missing/);
  });

  it('fails, naming the Watch file and the key, on a listed key that the Watch catalog lacks', () => {
    for (const key of [...CHECK_KEYS, ...GOT_IT_KEYS]) {
      const watchEntries = Object.fromEntries(Object.entries(WATCH).filter(([name]) => name !== key));
      const r = run(...fixture(`no-${key}`, { watchEntries }));
      assert.equal(r.status, 1, key);
      assert.match(r.stderr, /Watch\.cls/, key);
      assert.ok(r.stderr.includes(`'${key}'`), `${key}: ${r.stderr}`);
      assert.match(r.stderr, /missing/, key);
    }
  });

  it('fails on a key that both catalogs define', () => {
    const entries = { ...GOOD, 'checks.allPassed': { text: 'Twice.', slots: {} } };
    const r = run(...fixture('both', { entries }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Watch\.cls/);
    assert.match(r.stderr, /'checks\.allPassed' is in both/);
  });

  it('fails on a check sentence with a slot of a type the page cannot fill', () => {
    const watchEntries = { ...WATCH, 'checks.allPassed': { text: 'All fine: {what}.', slots: { what: 'sentence' } } };
    const r = run(...fixture('check-slot', { watchEntries }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Watch\.cls/);
    assert.match(r.stderr, /checks\.allPassed/);
    assert.match(r.stderr, /slot 'what' of type 'sentence'/);
  });

  it('allows a text slot on the two whatFailed check keys only: every other check key, a banner and a reason text still refuse it', () => {
    for (const key of ['checks.everythingElsePassed', 'checks.nothingWatched']) {
      const watchEntries = { ...WATCH, [key]: { text: 'Fine: {what}.', slots: { what: 'text' } } };
      const r = run(...fixture(`text-${key}`, { watchEntries }));
      assert.equal(r.status, 1, key);
      assert.ok(r.stderr.includes(`'${key}'`), r.stderr);
      assert.match(r.stderr, /slot 'what' of type 'text'/, key);
    }
    // A noun slot is a type the page renders, so a whatFailed of type noun is refused for the count slot that the entry lacks.
    for (const [type, refusal] of [['noun', "'checks.notEverything' has a noun slot"], ['sentence', "slot 'whatFailed' of type 'sentence'"]]) {
      const watchEntries = { ...WATCH, 'checks.notEverything': { text: 'Not everything: {whatFailed}.', slots: { whatFailed: type } } };
      const r = run(...fixture(`whatfailed-${type}`, { watchEntries }));
      assert.equal(r.status, 1, type);
      assert.ok(r.stderr.includes(refusal), r.stderr);
    }
    const entries = { ...GOOD, 'banner.unreachable': { text: 'Down {what}.', slots: { what: 'text' } } };
    const banner = run(...fixture('text-banner', { entries }));
    assert.equal(banner.status, 1);
    assert.match(banner.stderr, /banner\.unreachable/);
    assert.match(banner.stderr, /slot 'what' of type 'text'/);
    const reason = run(...fixture('text-reason', { entries: { ...GOOD, 'fallbackReason.timeout': { text: 'it {n}', slots: { n: 'text' } } } }));
    assert.equal(reason.status, 1);
    assert.match(reason.stderr, /fallbackReason\.timeout/);
  });

  it('reads the Watch catalog from the file that --watch names, and refuses one that is not there', () => {
    const args = fixture('watch-flag');
    const absent = [...args.slice(0, 6), '--watch', join(work, 'absent-watch.cls')];
    assert.equal(run(...absent).status, 1, 'a --watch file that does not exist is refused');
    const other = fixture('watch-flag-other', { watchEntries: { ...WATCH, 'checks.allPassed': { text: 'Another text.', slots: {} } } });
    assert.equal(run(...args.slice(0, 6), '--watch', other[7]).status, 0);
    assert.match(readFileSync(args[5], 'utf8'), /'checks\.allPassed': 'Another text\.'/, 'the text comes from the file --watch names');
  });

  it('fails on the generic reason when it is missing', () => {
    const r = run(...fixture('no-generic', { entries: without('fallbackReason.generic'), reasons: 'timeout=timeout' }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /fallbackReason\.generic/);
  });

  it('fails on a reason of REASONKEYS whose key has no entry', () => {
    const r = run(...fixture('no-reason', { reasons: 'timeout=timeout,boom=gone,invalid=generic' }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /fallbackReason\.gone/);
    assert.match(r.stderr, /boom/);
  });

  it('fails on a listed key with a slot of a type that the page does not render, and accepts time, count, cost and channel (text on a key of TEXT_SLOT_KEYS only)', () => {
    for (const type of ['groups', 'sentence']) {
      const entries = { ...GOOD, 'conversation.turnFallback': { text: 'At {what}: {fallbackReason}', slots: { fallbackReason: 'fallbackReason', what: type } } };
      const r = run(...fixture(`slot-${type}`, { entries }));
      assert.equal(r.status, 1, type);
      assert.match(r.stderr, /Core\.cls/, type);
      assert.match(r.stderr, /conversation\.turnFallback/, type);
      assert.ok(r.stderr.includes(`slot 'what' of type '${type}'`), `${type}: ${r.stderr}`);
    }
    for (const type of ['time', 'count', 'cost', 'channel']) {
      const entries = { ...GOOD, 'conversation.turnFallback': { text: 'At {what}: {fallbackReason}', slots: { fallbackReason: 'fallbackReason', what: type } } };
      const r = run(...fixture(`slot-ok-${type}`, { entries }));
      assert.equal(r.status, 0, `${type}: ${r.stderr}`);
    }
  });

  it('accepts a text slot on each key of TEXT_SLOT_KEYS, the listed keys whose entry declares one, and refuses it on every other listed key', async () => {
    const { LISTED_KEYS, TEXT_SLOT_KEYS } = await import(pathToFileURL(script).href);
    assert.deepEqual(TEXT_SLOT_KEYS, [
      'checks.notEverything',
      'checks.notEverythingRestPassed',
      'answered.approvedBy',
      'answered.rejectedBy',
      'answered.alreadyApprovedBy',
      'answered.alreadyRejectedBy',
      'result.failedAgain',
      'result.failedAndSkipped',
      'result.couldNotStart',
      'result.itemSuspended',
      'result.itemResumed',
      'result.itemSkipped',
      'result.rerouted',
      LINE_KEY,
      LEARNED_KEY,
    ]);
    assert.deepEqual(Object.keys(real.PAGE_SLOTS).filter((key) => Object.values(real.PAGE_SLOTS[key]).includes('text')), TEXT_SLOT_KEYS, 'the listed keys of the real catalog with a text slot');
    for (const key of LISTED_KEYS.filter((one) => one !== LINE_KEY)) {
      const inWatch = Object.hasOwn(WATCH, key);
      const entry = (inWatch ? WATCH : GOOD)[key];
      const withText = { ...entry, slots: { ...entry.slots, extra: 'text' } };
      const r = run(...fixture(`extra-text-${key}`, inWatch ? { watchEntries: { ...WATCH, [key]: withText } } : { entries: { ...GOOD, [key]: withText } }));
      if (TEXT_SLOT_KEYS.includes(key)) {
        assert.equal(r.status, 0, `${key}: ${r.stderr}`);
      } else {
        assert.equal(r.status, 1, key);
        assert.ok(r.stderr.includes(`'${key}' has the slot 'extra' of type 'text'`), `${key}: ${r.stderr}`);
      }
    }
  });

  it('renders a channel slot as the channel\'s name, an unknown code as given, and a text slot as the cleaned string', async () => {
    const args = fixture('channel');
    assert.equal(run(...args).status, 0);
    const module = await import(pathToFileURL(args[5]).href);
    assert.equal(module.renderPageText('answered.approved', { channel: 'phone', time: '14:15' }), 'Yes from the simulated phone at 14:15', 'the web text, with the name of the channel');
    assert.equal(module.renderPageText('answered.rejected', { channel: 'web', time: '14:15' }), 'No from the web chat at 14:15.');
    assert.equal(module.renderPageText('answered.rejected', { channel: 'telegram', time: '14:15' }), 'No from telegram at 14:15.', 'a code that is not in CHANNELNAMES renders as given');
    assert.equal(module.renderPageText('answered.rejected', { channel: 'constructor', time: '14:15' }), 'No from constructor at 14:15.');
    assert.equal(module.renderPageText('answered.rejectedBy', { user: ' zz\n sam ', channel: 'web', time: '1' }), 'No by zz sam from the web chat at 1.', 'a text slot is cleaned');
  });

  it('fails on a missing answered key, naming it', () => {
    for (const key of ANSWERED_KEYS) {
      const r = run(...fixture(`no-${key}`, { entries: Object.fromEntries(Object.entries(GOOD).filter(([name]) => name !== key)) }));
      assert.equal(r.status, 1, key);
      assert.ok(r.stderr.includes(`'${key}'`), `${key}: ${r.stderr}`);
      assert.match(r.stderr, /missing/, key);
    }
  });

  it('fails when the CHANNELNAMES parameter is missing or is not code=name pairs', () => {
    for (const [name, channels] of Object.entries({ missing: null, 'no-pair': 'web', 'no-name': 'web=', 'upper-code': 'Web=the web chat', 'bad-name': 'web=the web chat 2' })) {
      const r = run(...fixture(`channels-${name}`, { channels }));
      assert.equal(r.status, 1, name);
      assert.match(r.stderr, /Catalog\.cls/, name);
      assert.match(r.stderr, name === 'missing' ? /there is no Parameter CHANNELNAMES/ : /CHANNELNAMES holds/, name);
    }
  });

  it('fails on a banner key whose slot is a groups slot, which the page cannot fill from a string', () => {
    const entries = { ...GOOD, 'banner.costCap': { text: 'Limit {cap} until {time}.', slots: { cap: 'groups', time: 'time' } } };
    const r = run(...fixture('banner-groups', { entries }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /banner\.costCap/);
    assert.ok(r.stderr.includes("slot 'cap' of type 'groups'"), r.stderr);
  });

  it('fails on a missing banner or action key, naming it', () => {
    for (const key of BANNER_KEYS) {
      const r = run(...fixture(`no-${key}`, { entries: Object.fromEntries(Object.entries(GOOD).filter(([name]) => name !== key)) }));
      assert.equal(r.status, 1, key);
      assert.ok(r.stderr.includes(`'${key}'`), `${key}: ${r.stderr}`);
      assert.match(r.stderr, /missing/, key);
    }
  });

  it('fails on a reason text with a slot, a one form, an undeclared placeholder and a stray brace', () => {
    const cases = {
      'reason-slot': { text: 'it {n}', slots: { n: 'count' } },
      'reason-time-slot': { text: 'it {n}', slots: { n: 'time' } },
      'reason-noun-slot': { text: 'it {n}', slots: { n: 'noun' } },
      'one-form': { text: 'it timed out', slots: {}, one: { slot: 'n', text: 'x' } },
      undeclared: { text: 'it {what}', slots: {} },
      'stray-brace': { text: 'it } failed', slots: {} },
      'empty-text': { text: '', slots: {} },
      'no-slots': { text: 'it timed out' },
    };
    for (const [name, entry] of Object.entries(cases)) {
      const r = run(...fixture(name, { entries: { ...GOOD, 'fallbackReason.timeout': entry } }));
      assert.equal(r.status, 1, name);
      assert.match(r.stderr, /fallbackReason\.timeout/, name);
    }
  });

  it('renders a noun slot as the form that the count slot chooses, and a one form where its count slot is "1"', async () => {
    const args = fixture('one-forms');
    assert.equal(run(...args).status, 0);
    const module = await import(pathToFileURL(args[5]).href);
    const noun = { one: 'order', other: 'orders' };
    assert.equal(module.renderPageText('result.allThrough', { count: '5', itemNoun: noun }), 'All 5 orders done.');
    assert.equal(module.renderPageText('result.allThrough', { count: '1', itemNoun: noun }), 'The order done.');
    assert.equal(module.renderPageText('result.failedAgain', { count: '9', itemNoun: noun, completed: '7', failedAgain: '1', failReason: 'x' }), '7/9 orders; 1 failed (x).');
    assert.equal(module.renderPageText('result.failedAgain', { count: '9', itemNoun: noun, completed: '1', failedAgain: '2', failReason: 'x' }), '1/9 orders; 2 failed (x).', 'the named slot decides');
    assert.deepEqual({ ...module.PAGE_ONE_FORMS['result.interrupted'] }, { slot: 'remaining', text: 'Stopped: {completed}/{count} {itemNoun}; one left.' });
    assert.equal(module.renderMessageText('result.allThrough', { count: '1', itemNoun: noun }), 'The order done.');
  });

  it('fails on a one form that names no count slot, has no text, uses an undeclared placeholder, or comes with a web form', () => {
    const base = RESULTS['result.failedAgain'];
    const cases = {
      'one-undeclared-slot': { ...base, one: { slot: 'zz', text: 'x' } },
      'one-not-a-count': { ...base, one: { slot: 'failReason', text: 'x' } },
      'one-no-slot': { ...base, one: { text: 'x' } },
      'one-no-text': { ...base, one: { slot: 'failedAgain' } },
      'one-empty-text': { ...base, one: { slot: 'failedAgain', text: '' } },
      'one-undeclared-placeholder': { ...base, one: { slot: 'failedAgain', text: 'x {nobody}' } },
      'one-stray-brace': { ...base, one: { slot: 'failedAgain', text: 'x }' } },
      'one-not-an-object': { ...base, one: 'x' },
      'one-with-web': { ...base, web: 'web text', one: { slot: 'failedAgain', text: 'x' } },
    };
    for (const [name, entry] of Object.entries(cases)) {
      const r = run(...fixture(name, { entries: { ...GOOD, 'result.failedAgain': entry } }));
      assert.equal(r.status, 1, name);
      assert.match(r.stderr, /result\.failedAgain/, name);
    }
  });

  it('fails on a noun slot in an entry that has no count slot, and accepts one that has', () => {
    const none = { ...GOOD, 'result.allThrough': { text: 'All {itemNoun}.', slots: { itemNoun: 'noun' } } };
    const r = run(...fixture('noun-no-count', { entries: none }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /result\.allThrough/);
    assert.match(r.stderr, /noun slot/);
    const named = { ...GOOD, 'result.allThrough': { text: 'All {total} {itemNoun}.', slots: { total: 'count', itemNoun: 'noun' } } };
    assert.equal(run(...fixture('noun-wrong-count', { entries: named })).status, 1, 'the count slot is the one named count');
  });

  it('fails on a missing result or audit key, naming it', () => {
    for (const key of RESULT_KEYS) {
      const r = run(...fixture(`no-${key}`, { entries: Object.fromEntries(Object.entries(GOOD).filter(([name]) => name !== key)) }));
      assert.equal(r.status, 1, key);
      assert.ok(r.stderr.includes(`'${key}'`), `${key}: ${r.stderr}`);
      assert.match(r.stderr, /missing/, key);
    }
  });

  it('fails on an XData block it cannot parse', () => {
    const broken = coreClass(JSON.stringify(GOOD, null, 1).replace('"slots": {}', '"slots": {').replace(/,\n \"pairing\.paired\"/, '\n "pairing.paired"'));
    for (const [name, core] of Object.entries({
      'broken-json': broken,
      'not-an-object': coreClass('[\n]'),
      'no-xdata': '/// A fixture.\nClass OcuTalon.Msg.Catalog.Core\n{\n}\n',
      'unclosed': '/// A fixture.\nClass OcuTalon.Msg.Catalog.Core\n{\n\nXData Entries [ MimeType = application/json ]\n{\n{\n "a": {}\n}\n',
    })) {
      const r = run(...fixture(name, { core }));
      assert.equal(r.status, 1, name);
      assert.match(r.stderr, /Core\.cls/, name);
      assert.match(r.stderr, /XData/, name);
    }
  });

  it('fails on a Watch XData block it cannot parse', () => {
    for (const [name, watch] of Object.entries({
      'watch-not-an-object': watchClass('[\n]'),
      'watch-no-xdata': '/// A fixture.\nClass OcuTalon.Msg.Catalog.Watch\n{\n}\n',
    })) {
      const r = run(...fixture(name, { watch }));
      assert.equal(r.status, 1, name);
      assert.match(r.stderr, /Watch\.cls/, name);
      assert.match(r.stderr, /XData/, name);
    }
  });

  it('fails when the REASONKEYS parameter is missing or is not value=suffix pairs', () => {
    const args = fixture('no-parameter');
    writeFileSync(args[3], 'Class OcuTalon.Msg.Catalog\n{\n}\n');
    const r = run(...args);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Catalog\.cls/);
    assert.match(r.stderr, /REASONKEYS/);
    const bad = run(...fixture('bad-pair', { reasons: 'timeout' }));
    assert.equal(bad.status, 1);
    assert.match(bad.stderr, /REASONKEYS/);
  });

  it('fails on an unknown option and on a missing file', () => {
    assert.equal(run('--nope').status, 1);
    assert.equal(run('--core', join(work, 'absent.cls')).status, 1);
  });
});

describe('--check', () => {
  it('writes nothing, passes on a current file and fails, naming the file, on a stale or missing one', () => {
    const args = fixture('check');
    const out = args[5];
    const missing = run(...args, '--check');
    assert.equal(missing.status, 1);
    assert.match(missing.stderr, /catalog\.ts is stale/);
    assert.throws(() => readFileSync(out), /ENOENT/, 'a check writes nothing');
    assert.equal(run(...args).status, 0);
    const current = run(...args, '--check');
    assert.equal(current.status, 0, current.stderr);
    writeFileSync(out, `${readFileSync(out, 'utf8')}// edited\n`);
    const stale = run(...args, '--check');
    assert.equal(stale.status, 1);
    assert.match(stale.stderr, /catalog\.ts is stale: run npm --prefix web run catalog/);
    assert.match(readFileSync(out, 'utf8'), /\/\/ edited/, 'and still writes nothing');
  });

  it('fails when the catalog changed and the file did not', () => {
    const args = fixture('changed');
    assert.equal(run(...args).status, 0);
    writeFileSync(args[1], coreClass(JSON.stringify({ ...GOOD, 'fallbackReason.timeout': { text: 'it timed out later', slots: {} } }, null, 1)));
    assert.equal(run(...args, '--check').status, 1);
  });
});

describe('the either-way line of the real tree (Story 7.8; U-249)', () => {
  const watchFile = join(repoRoot, 'src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls');
  const fromClass = async () => {
    const { readEntries } = await import(pathToFileURL(script).href);
    return readEntries(readFileSync(watchFile, 'utf8'), watchFile).entries;
  };

  it('holds the line as U-249 words it, in a many form and a one form chosen by resendCount', () => {
    assert.equal(real.PAGE_TEXTS[LINE_KEY], LINE_MANY);
    assert.deepEqual({ ...real.PAGE_ONE_FORMS[LINE_KEY] }, { slot: 'resendCount', text: LINE_ONE });
    assert.deepEqual({ ...real.PAGE_SLOTS[LINE_KEY] }, { resendCount: 'count', reading: 'text', item: 'text' });
    assert.equal(real.renderPageText(LINE_KEY, { resendCount: '3', reading: 'month first', item: 'order' }), 'All 3 dates are valid whether read month first or day first. Read month first, they match the day each order arrived.');
    assert.equal(real.renderPageText(LINE_KEY, { resendCount: '1', reading: 'day first', item: 'message' }), 'The date is valid whether read month first or day first. Read day first, it matches the day the message arrived.');
  });

  it('is what each of the eight forms of the two catalog entries holds between its anchors, and nothing else of them is typed on the page', async () => {
    const entries = await fromClass();
    const forms = [];
    for (const key of LINE_PARENTS) {
      const entry = entries[key];
      forms.push([key + ' text', entry.text, LINE_MANY], [key + ' web', entry.web, LINE_MANY], [key + ' one.text', entry.one.text, LINE_ONE], [key + ' one.web', entry.one.web, LINE_ONE]);
    }
    assert.equal(forms.length, 8);
    for (const [name, text, line] of forms) assert.ok(text.includes('becomes {after}. ' + line + " I'll resend"), name);
    assert.ok(!Object.hasOwn(entries, LINE_KEY), 'no catalog class holds the derived key');
  });
});

describe('the either-way line on a fixture', () => {
  const refused = (name, watchEntries, pattern) => {
    const r = run(...fixture(name, { watchEntries }));
    assert.equal(r.status, 1, name);
    assert.ok(r.stderr.includes(LINE_KEY), `${name}: ${r.stderr}`);
    assert.match(r.stderr, pattern, `${name}: ${r.stderr}`);
  };

  it('cuts the line out of the eight forms and lists it with its slots and its one form', async () => {
    const args = fixture('line-good');
    const r = run(...args);
    assert.equal(r.status, 0, r.stderr);
    const module = await import(pathToFileURL(args[5]).href);
    assert.equal(module.PAGE_TEXTS[LINE_KEY], LINE_MANY);
    assert.deepEqual({ ...module.PAGE_SLOTS[LINE_KEY] }, { resendCount: 'count', reading: 'text', item: 'text' });
    assert.deepEqual({ ...module.PAGE_ONE_FORMS[LINE_KEY] }, { slot: 'resendCount', text: LINE_ONE });
    assert.equal(module.renderPageText(LINE_KEY, { resendCount: '2', reading: 'day first', item: 'order' }), 'All 2 dates are valid whether read month first or day first. Read day first, they match the day each order arrived.');
  });

  it('refuses a missing parent entry, naming the key', () => {
    for (const parent of LINE_PARENTS) {
      refused(`line-no-${parent}`, Object.fromEntries(Object.entries(WATCH).filter(([key]) => key !== parent)), new RegExp(`'${parent}'`));
    }
  });

  it('refuses a parent with no one form', () => {
    const { one, ...noOne } = WATCH[LINE_PARENTS[0]];
    refused('line-no-one', { ...WATCH, [LINE_PARENTS[0]]: noOne }, /no one form/);
  });

  it('refuses a form whose anchor is missing or occurs twice', () => {
    refused('line-no-start', { ...WATCH, [LINE_PARENTS[0]]: eitherParent('{count} {itemNoun} failed.', { start: 'turns into {after}. ' }) }, /does not hold/);
    refused('line-no-end', { ...WATCH, [LINE_PARENTS[1]]: eitherParent('{count} more {itemNoun} failed.', { end: ' We will resend' }) }, /does not hold/);
    refused('line-twice', { ...WATCH, [LINE_PARENTS[1]]: eitherParent('becomes {after}. x', {}) }, /does not hold/);
    refused('line-end-twice', { ...WATCH, [LINE_PARENTS[1]]: eitherParent('{count} more {itemNoun} failed.', { end: " I'll resend I'll resend" }) }, /does not hold/);
  });

  it('refuses a parent with a form missing, naming the form', () => {
    const parent = eitherParent('{count} {itemNoun} failed.');
    const { web, ...noWeb } = parent;
    refused('line-no-web', { ...WATCH, [LINE_PARENTS[0]]: noWeb }, /no web text/);
    const { web: oneWeb, ...oneNoWeb } = parent.one;
    refused('line-no-one-web', { ...WATCH, [LINE_PARENTS[1]]: { ...parent, one: oneNoWeb } }, /no one\.web text/);
  });

  it('refuses a form with nothing between its anchors', () => {
    refused('line-empty', { ...WATCH, [LINE_PARENTS[0]]: eitherParent('{count} {itemNoun} failed.', { many: ['', ''], one: ['', ''] }) }, /no sentence/);
  });

  it('refuses a one form that is not chosen by resendCount, as the card chooses it', () => {
    const parent = eitherParent('{count} {itemNoun} failed.');
    refused('line-one-slot', { ...WATCH, [LINE_PARENTS[0]]: { ...parent, one: { ...parent.one, slot: 'count' } } }, /not chosen by resendCount/);
  });

  it('refuses a slot of the line whose type differs between the parents', () => {
    const parent = eitherParent('{count} more {itemNoun} failed.');
    refused('line-slot-type', { ...WATCH, [LINE_PARENTS[1]]: { ...parent, slots: { ...parent.slots, item: 'time' } } }, /different type/);
  });

  it('refuses a many form that differs in one word of one form', () => {
    const changed = LINE_MANY.replace('valid', 'fine');
    refused('line-many-text', { ...WATCH, [LINE_PARENTS[0]]: eitherParent('{count} {itemNoun} failed.', { many: [changed, LINE_MANY] }) }, /many form/);
    refused('line-many-web', { ...WATCH, [LINE_PARENTS[1]]: eitherParent('{count} more {itemNoun} failed.', { many: [LINE_MANY, changed] }) }, /many form/);
  });

  it('refuses a one form that differs in one word of one form of one parent', () => {
    const changed = LINE_ONE.replace('matches', 'fits');
    refused('line-one-text', { ...WATCH, [LINE_PARENTS[1]]: eitherParent('{count} more {itemNoun} failed.', { one: [changed, LINE_ONE] }) }, /one form/);
    refused('line-one-web', { ...WATCH, [LINE_PARENTS[0]]: eitherParent('{count} {itemNoun} failed.', { one: [LINE_ONE, changed] }) }, /one form/);
  });

  it('refuses a slot of the line that a parent does not declare, and a catalog class that defines the derived key', () => {
    const parent = eitherParent('{count} {itemNoun} failed.');
    const { reading, ...slots } = parent.slots;
    refused('line-slot', { ...WATCH, [LINE_PARENTS[0]]: { ...parent, slots } }, /slot 'reading'/);
    const r = run(...fixture('line-defined', { watchEntries: { ...WATCH, [LINE_KEY]: { text: 'x', slots: {}, source: 'fixture' } } }));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /derived by the generator/);
  });
});
