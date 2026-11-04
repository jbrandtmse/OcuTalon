import { expect, test, type Locator, type Page } from '@playwright/test';

import {
  ON_MOCK,
  checkRow,
  dismissIncident,
  expectIncidentAwaitingApproval,
  incidentCardOf,
  incidentRefs,
  incidentRows,
  newIncidentRef,
  phoneNotes,
  pressBreakFeed,
  rejectOnPhone,
} from '../support/demo-path';
import { pointKeys, restoreKeys } from '../support/devices';
import { signInReadmeLoaded, railOf } from '../support/floor';
import { chk, irisScript, quoted, readApproval, setTelegramIncluded } from '../support/iris';
import { clock } from '../support/page';

/**
 * UJ-1 step 5, the Telegram part (Story 12.7; FR-8, FR-9, FR-20, AD-11, AD-14, AD-32, REL-1, REL-2, UX-DR101, UX-DR103): the same approval
 * request answered from the paired Telegram chat. Lane A owns this file from Epic 12 (AD-29). web/scripts/demo-path-summary.mjs counts it
 * as a part of step 5 (the `approval` in the file name).
 * T8, on the demo-path stack after steps 01 to 08, against the CI mock and its dummy token (Rule 21: no real bot, no call to the public
 * Telegram API): the README account pairs chat 84017734115 from the card's code, ends any incident that 07 and 08 left in progress (07's
 * way: Reject on the simulated phone, then Dismiss), presses Break the feed once more, and the chat gets the request's notice with the
 * buttons approve:<Ref> and reject:<Ref>. The press of Approve, queued as the paired chat's callback_query, is answered, and within 5 s
 * the chat card's request reads "Approved from Telegram at HH:MM", the simulated phone's note "Approved from Telegram at HH:MM.", the
 * rail has no row for the request, the press got "Approved. Repairing and resending 50 orders." and the Telegram message is edited
 * to the notice, a blank line and the same status. Then the chat gets "All 50 orders went through." as a new message, and the IRIS audit
 * entry of the answer names the channel telegram and holds neither the chat id nor the chat's name. HH:MM is the row's AnsweredAt.
 * The page's checks hold the 5 s from the time IRIS queued the press (the fixture's queuedAt, after the clocks are checked to agree, as T5
 * does), with no grace after it. The fixture's reads go through IRIS scripts, which take a second or so each, so the IRIS reads are
 * allowed ten.
 * The incident is raised after the pairing, because a Telegram notice reaches only a chat that is paired when it is sent. The test depends
 * on step 2's watch of the Orders production, as 05 and 07 do (one journey on one stack, AD-29), and asserts that the watch is there.
 * The runners' keys are pointed at the mock again for the diagnosis (08 put them back), and put back at the end.
 */
const BOT = 'ocutalon_approve_bot';
const CHAT = 84017734115;
const NAME = 'Zqapprove';
const CONFIRMATION = "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair).";

/** How long the page may take to show the answer after the press was queued (NFR-9). */
const WITHIN_MS = 5_000;
/** The longest a read of the IRIS side may take to show what the press caused. */
const READ_MS = 10_000;
/** How long a card waits for what a reloaded snapshot brings. */
const LOADED_MS = 10_000;

const cardOf = (page: Page): Locator => railOf(page).locator('app-telegram-card');

/** The fixture class of the IRIS side. */
const FIXTURE = '##class(OcuTalon.Test.Channel.TelegramPageFixture)';

/**
 * Calls one method of the fixture in an IRIS script and returns its reason ("" when it worked) with the values of its output variables.
 * The script prints its CHK lines on every path, because irisScript runs a session again that printed none and Start is not idempotent.
 */
async function fixture(call: string, outputs: string[] = []): Promise<{ reason: string; values: Record<string, string> }> {
  const lines = await irisScript(
    [
      ['Set r=""', ...outputs.map((name) => `${name}=""`)].join(','),
      `Try { Set r=${FIXTURE}.${call} } Catch ex { Set r="the call threw "_ex.Name }`,
      'Write !,"CHK|reason|",$Translate(r,$Char(13,10),"  ")',
      ...outputs.map((name) => `Write !,"CHK|${name}|",${name}`),
    ].join('\n'),
  );
  const reason = chk(lines, 'reason');
  if (reason === undefined) return { reason: 'the IRIS script printed no answer', values: {} };
  return { reason, values: Object.fromEntries(outputs.map((name) => [name, chk(lines, name) ?? ''])) };
}

/** The pairing code in the card's "Open in Telegram" link, or "" when there is none. */
async function codeOf(card: Locator): Promise<string> {
  const href = (await card.getByRole('link', { name: /Open in Telegram/ }).getAttribute('href')) ?? '';
  return new RegExp(`^https://t\\.me/${BOT}\\?start=([A-Za-z0-9_-]{22})$`).exec(href)?.[1] ?? '';
}

/** The text of every sendMessage to the chat, in order. */
async function repliesOf(): Promise<string[]> {
  return JSON.parse((await fixture(`Replies(${CHAT}, .texts)`, ['texts'])).values['texts'] ?? '[]') as string[];
}

/** The text of every editMessageText to the chat, in order. */
async function editsOf(): Promise<string[]> {
  return JSON.parse((await fixture(`Edits(${CHAT}, .texts)`, ['texts'])).values['texts'] ?? '[]') as string[];
}

test.describe('approve from the paired Telegram chat (Story 12.7)', () => {
  test.use({ timezoneId: 'UTC', locale: 'en-GB' });

  /**
   * T8: the paired chat's Approve answers the request, and every copy shows who answered. The matrix rows "REL-2 step 5's Telegram part" and
   * "Every copy shows who answered" in a browser.
   */
  test('T8: Approve from the paired Telegram chat answers the request, the page and the phone show it within 5 s, and the chat gets the edit and the result', { tag: ['@floor', '@ci-only'] }, async ({ page }) => {
    test.setTimeout(240_000);
    const was = await setTelegramIncluded(1);
    let saved = '';
    let pointed = false;
    let passed = false;
    try {
      if (ON_MOCK) {
        pointed = true;
        await pointKeys();
      }
      const started = await fixture(`Start(.saved, ${quoted(BOT)}, 1)`, ['saved']);
      saved = started.values['saved'] ?? '';
      expect(started.reason, 'TelegramIn and TelegramOut start against the mock, which names the bot').toBe('');

      // The README account pairs the chat from the card's code (T5's way).
      await signInReadmeLoaded(page);
      const card = cardOf(page);
      await expect(card.locator('[data-state="unpaired"]'), 'the card is unpaired with a code').toHaveCount(1, { timeout: LOADED_MS });
      const code = await codeOf(card);
      expect(code, 'the "Open in Telegram" link carries the code').not.toBe('');
      expect((await fixture(`Pair(${quoted(code)}, ${CHAT}, ${quoted(NAME)}, .queuedAt)`, ['queuedAt'])).reason, 'the chat pairs with the code').toBe('');
      await expect(card.locator('[data-state="paired"]'), 'the card is paired').toHaveCount(1, { timeout: LOADED_MS });
      await expect.poll(repliesOf, { message: 'the chat has exactly the confirmation', timeout: LOADED_MS, intervals: [1000] }).toEqual([CONFIRMATION]);

      // Clear the way: end any incident that is still in progress, as 07 does.
      await expect(checkRow(page), "step 2's watch of the Orders production is in place").toHaveCount(1, { timeout: LOADED_MS });
      for (const row of await incidentRows(page)) {
        if (row.state !== 'open' && row.state !== 'awaiting_approval') continue;
        const old = incidentCardOf(page, row.ref);
        const pending = row.requests.find((one) => one.state === 'pending');
        if (pending) await rejectOnPhone(page, pending.ref, old);
        await dismissIncident(page, old, row.ref);
      }

      // Raise: the notice reaches the paired chat with the two buttons.
      const known = await incidentRefs(page);
      await pressBreakFeed(page);
      const ref = await newIncidentRef(page, known);
      const incident = incidentCardOf(page, ref);
      const key = await expectIncidentAwaitingApproval(page, incident);
      await expect
        .poll(async () => JSON.parse((await fixture(`Buttons(${CHAT}, .data)`, ['data'])).values['data'] ?? '[]') as string[], {
          message: "the chat's notice has the buttons approve:<Ref> and reject:<Ref>",
          timeout: 30_000,
          intervals: [1000],
        })
        .toEqual([`approve:${key}`, `reject:${key}`]);
      const notice = (await repliesOf()).find((text) => text.includes('Approve?')) ?? '';
      expect(notice, "the chat got the incident's notice").not.toBe('');

      // Press Approve from the chat. The 5 s run from the moment IRIS queued the press, so the two clocks must agree (T5's check).
      const before = Date.now();
      const reading = Number((await fixture('Now()')).reason);
      const after = Date.now();
      expect(reading, "the IRIS clock agrees with the test's clock (lower bound)").toBeGreaterThanOrEqual(before - 250);
      expect(reading, 'and (upper bound)').toBeLessThanOrEqual(after + 250);
      const pressed = await fixture(`Press(${CHAT}, ${quoted(NAME)}, ${quoted(`approve:${key}`)}, .queuedAt)`, ['queuedAt']);
      expect(pressed.reason, 'the press is queued while a long poll is open').toBe('');
      const queued = Number(pressed.values['queuedAt']);
      expect(queued, 'the fixture gives the time the press was queued').toBeGreaterThan(0);
      const left = (): number => Math.max(1, WITHIN_MS - (Date.now() - queued));

      // Within 5 s: the chat card, the phone and the rail show the answer.
      const request = incident.locator('[data-part="approval"]');
      await expect(request.locator('p.status'), "the chat card's request shows the answer from Telegram").toHaveText(/^Approved from Telegram at \d{1,2}:\d{2}$/, { timeout: left() });
      const answeredNote = phoneNotes(page).locator('p[data-part="answer"]').filter({ hasText: 'Approved from Telegram' });
      await expect(answeredNote, "the phone's note shows it too").toHaveText(/^Approved from Telegram at \d{2}:\d{2}\.$/, { timeout: left() });
      await expect(railOf(page).locator(`li.row[data-row-key="approvals:${key}"]`), 'the rail has no row for the request').toHaveCount(0, { timeout: left() });

      // The row says the same, from Telegram, and the times agree.
      const answered = await readApproval(key);
      expect([answered.action, answered.channel], 'the request is approved from Telegram').toEqual(['approve', 'telegram']);
      expect(['approved', 'executing', 'done'], 'and the real fix has taken it on').toContain(answered.state);
      await expect(request.locator('p.status'), "the card's time is the row's answered time").toHaveText(`Approved from Telegram at ${clock(answered.at, 'en-GB', 'UTC')}`);
      const status = `Approved from Telegram at ${answered.at.slice(11, 16)}.`;
      await expect(answeredNote, "the phone's time is the row's answered time").toHaveText(status);

      // The press was answered, and the Telegram message was edited.
      await expect
        .poll(async () => JSON.parse((await fixture('PressAnswers(.answers)', ['answers'])).values['answers'] ?? '[]') as Array<{ text: string; show_alert: number }>, {
          message: 'the press got its answer, with no alert',
          timeout: READ_MS,
          intervals: [500],
        })
        .toEqual([{ text: ON_MOCK ? 'Approved. Repairing and resending 50 orders.' : expect.stringMatching(/^Approved\. Repairing and resending \d+ \S+\.$/), show_alert: 0 }]);
      await expect.poll(editsOf, { message: 'the Telegram message is edited to the notice, a blank line and the status', timeout: READ_MS, intervals: [500] }).toEqual([`${notice}\n\n${status}`]);

      // Then the result is a new message, after the edit, and the audit entry names the channel and no identity.
      await expect
        .poll(async () => (await repliesOf()).filter((text) => (ON_MOCK ? text === 'All 50 orders went through.' : /^All \d+ \S+ went through\.$/.test(text))).length, {
          message: 'the chat gets the result as a new message',
          timeout: 120_000,
          intervals: [1000],
        })
        .toBe(1);
      expect(await editsOf(), 'the result edited nothing').toHaveLength(1);
      const audit = await fixture(`Audit(${quoted(key)}, ${CHAT}, ${quoted(NAME)}, .found)`, ['found']);
      expect(audit.reason, "the IRIS audit log holds the answer's entry").toBe('');
      expect(JSON.parse(audit.values['found'] ?? '{}'), 'which names the channel telegram and holds neither the chat id nor the chat\'s name').toEqual({ channel: 'telegram', holdsChatId: 0, holdsName: 0 });
      passed = true;
    } finally {
      let finished = { reason: '' };
      try {
        try {
          if (pointed) {
            await restoreKeys();
            const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
            expect(chk(lines, 'records'), 'the runners recorded the restored keys').toBe('1');
          }
        } finally {
          finished = await fixture(`Finish(${quoted(saved)})`);
        }
      } finally {
        await setTelegramIncluded(was);
      }
      if (finished.reason !== '') {
        if (passed) expect(finished.reason, 'the fixture puts everything back').toBe('');
        else test.info().annotations.push({ type: 'finish', description: finished.reason });
      }
    }
  });
});
