import { expect, test, type Locator, type Page } from './support/fixtures';

import { README_ACCOUNT } from './sign-in/helpers';
import { dropPhone, pointKeys, restoreKeys } from './support/devices';
import { composerOf, inMs, railOf, replyOf, signInReadmeLoaded } from './support/floor';
import { chk, irisScript, quoted } from './support/iris';
import { forget, prepare, sessionRef } from './support/persona';

/**
 * Story 40.6 (PA1 and PA2), a proposed persona answered on the page, in a real browser against the stack that test-sign-in.sh seeds, signed
 * in as the README account, with the CI mock scripting the model. The user types "[[mock:persona-propose]] ..." into the composer and
 * presses Send; the real Conversation and Chat call propose_persona, the real SettingsOps raises the `setting` request and sends the
 * approval.persona notice, and nothing here stands in for them:
 *   - PA1: the chat shows the request as a setting card (the title, "Now: Professional (default)", "Proposed: Pirate", the note and both
 *     buttons), the rail lists it under its title, and the Persona card shows the pending note. Approve: the card's status line reads
 *     "Approved from the web chat at ..." with no note, the chat shows "Persona updated. It applies from your next message." and GET
 *     /v1/persona reads pirate;
 *   - PA2: the same with Reject: "Rejected from the web chat at ... Nothing was changed.", the persona stays Professional and no applied
 *     notice shows.
 * beforeAll points the runners' keys at the CI mock; afterAll puts them back, drops the AI sessions the turns saved and waits until the
 * runners have recorded their restored keys. After each case the account's persona keys, its `setting` requests, its turns and the
 * notices of the case are removed again, because other specs expect the defaults.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const MESSAGES = '/ocutalon/api/v1/messages';
const PERSONA = '/ocutalon/api/v1/persona';
const TITLE = 'Change how OcuTalon talks to you';
const NOTE = 'Nothing changes unless you approve.';
const PENDING = 'OcuTalon suggested a change. It waits for your answer in Approval requests.';
const APPLIED = 'Persona updated. It applies from your next message.';

/** How long a reply, a card or a status may take to show: the turn, the live poll and the render. */
const WAIT_MS = 30_000;

/** The mark of the saved AI sessions before the first case (RunnerFixture.SessionMark), for the clean-up. */
let mark = '';

test.beforeAll(async () => {
  test.setTimeout(240_000);
  await pointKeys();
  const lines = await irisScript('Write !,"CHK|mark|",##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()');
  mark = chk(lines, 'mark') ?? '';
});

test.afterAll(async () => {
  test.setTimeout(240_000);
  try {
    if (/^\d+$/.test(mark)) {
      const lines = await irisScript(`Write !,"CHK|dropped|",$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(${mark}))`);
      expect(chk(lines, 'dropped'), `the AI sessions of the turns are dropped (${lines.join(' ')})`).toBe('1');
    }
  } finally {
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
    }
  }
});

/** The setting card that the chat draws for the proposal. */
const cardOf = (page: Page): Locator => page.locator('app-chat-panel app-approval-request-card').filter({ hasText: TITLE });

/** The Persona card of the status rail. */
const personaOf = (page: Page): Locator => railOf(page).locator('app-persona-card');

/** Types the text into the composer, presses the main Send button and returns the clientId of the POST /messages that it made. */
async function send(page: Page, text: string): Promise<string> {
  const request = page.waitForRequest((candidate) => candidate.method() === 'POST' && new URL(candidate.url()).pathname === MESSAGES);
  await composerOf(page).fill(text);
  await page.getByRole('main').getByRole('button', { name: 'Send', exact: true }).click();
  return ((await request).postDataJSON() as { clientId: string }).clientId;
}

/** The preset that GET /v1/persona reads for the signed-in page. */
async function presetRead(page: Page): Promise<string> {
  const response = await page.request.get(PERSONA);
  expect(response.status(), await response.text()).toBe(200);
  return ((await response.json()) as { preset: string }).preset;
}

/** Runs a case as the README account with the persona cleared before and the case's rows removed after, with the page signed in and loaded. */
async function withProposal(page: Page, body: () => Promise<void>): Promise<void> {
  const ref = await sessionRef();
  const since = inMs(0);
  await forget(ref);
  try {
    await prepare(ref);
    await signInReadmeLoaded(page);
    await body();
  } finally {
    try {
      await forget(ref);
      await prepare(ref);
      await irisScript(`Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(${quoted(ref)})`);
    } finally {
      await dropPhone(README_ACCOUNT.user, since);
    }
  }
}

/** Sends the proposing message and waits for the reply and the setting card; returns the card. */
async function propose(page: Page): Promise<Locator> {
  const clientId = await send(page, '[[mock:persona-propose]] Please talk like a pirate.');
  await expect(replyOf(page, clientId), "the scenario's reply shows").toContainText('The CI mock suggested the persona.', { timeout: WAIT_MS });
  const card = cardOf(page);
  await expect(card, 'the chat shows the proposal as one card').toHaveCount(1, { timeout: WAIT_MS });
  return card;
}

test('PA1: a proposed persona shows as a setting card in the chat, the rail and the Persona card, and approving it applies Pirate', async ({ page }) => {
  test.setTimeout(240_000);
  await withProposal(page, async () => {
    const card = await propose(page);
    await expect(card.locator('.action'), 'the title, with no period').toHaveText(TITLE);
    await expect(card.locator('.setting-now')).toHaveText('Now: Professional (default)');
    await expect(card.locator('.setting-proposed')).toHaveText('Proposed: Pirate');
    await expect(card.locator('.setting-note')).toHaveText(NOTE);
    await expect(card.locator('.dry-label'), 'no dry run block').toHaveCount(0);
    await expect(card.locator('.fixed'), 'and no fixed-targets line').toHaveCount(0);
    const approve = card.getByRole('button', { name: 'Approve: change how OcuTalon talks to you', exact: true });
    await expect(approve).toBeVisible();
    await expect(card.getByRole('button', { name: 'Reject: change how OcuTalon talks to you', exact: true })).toBeVisible();
    await expect(railOf(page).locator('li.row').filter({ hasText: TITLE }), 'the rail lists the request under its title').toHaveCount(1);
    await expect(personaOf(page).getByRole('button', { name: PENDING, exact: true }), 'the Persona card shows the pending note').toBeVisible();

    await approve.click();
    await expect(card.locator('p.status'), "the card's status line").toHaveText(/^Approved from the web chat at \S+/, { timeout: WAIT_MS });
    await expect(card.locator('.setting-note'), 'the note is gone').toHaveCount(0);
    await expect(page.locator('app-chat-panel').getByText(APPLIED, { exact: true }), 'the chat shows the applied notice').toBeVisible({ timeout: WAIT_MS });
    await expect.poll(() => presetRead(page), { message: 'GET /v1/persona reads pirate', timeout: WAIT_MS }).toBe('pirate');
  });
});

test('PA2: rejecting a proposed persona changes nothing and shows no applied notice', async ({ page }) => {
  test.setTimeout(240_000);
  await withProposal(page, async () => {
    const card = await propose(page);
    await card.getByRole('button', { name: 'Reject: change how OcuTalon talks to you', exact: true }).click();
    const status = card.locator('p.status');
    await expect(status, "the card's status line").toHaveText(/^Rejected from the web chat at \S+.* Nothing was changed\.$/, { timeout: WAIT_MS });
    await expect(card.locator('.setting-note'), 'the note is gone').toHaveCount(0);
    expect(await presetRead(page), 'the persona stays Professional').toBe('professional');
    await expect(page.locator('app-chat-panel').getByText(APPLIED, { exact: true }), 'no applied notice shows').toHaveCount(0);
  });
});
