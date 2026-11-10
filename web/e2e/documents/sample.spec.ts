import { expect, test, type Locator, type Page } from '../support/fixtures';

import { SAMPLE_RUNBOOK_TEXTS } from '../../src/app/documents/sample-runbook-view.ts';
import { envelope, signIn } from '../sign-in/helpers';
import { pointKeys, publishFixtureEvent, restoreKeys } from '../support/devices';
import { CARD_MS, composerOf, loadedAfter, replyOf } from '../support/floor';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 20.3, the sample runbook in one press on the Documents page (E0 to E4), in a real browser against a real stack, as the chat fixture
 * user (OcuTalonUser only). On a local install the sample is an `instance` document, so every case first removes any row named "Sample
 * runbook.md" through the real route and removes what it added through the real DELETE, also on failure.
 *   - E0: the chat user holds exactly OcuTalonUser;
 *   - E1: the demo-visible path: a press posts the bundled runbook once (a second press while it is out posts nothing), the real row goes
 *     Indexing to Ready, the button leaves and focus is on the list region; then a real turn through the composer and the CI mock ends
 *     with the chip "Sample runbook \u00A7 When orders fail with a date error" over the real search of the real indexed runbook;
 *   - E2: a refused add (501) shows the page's own row text, announced once, and the button stays, with focus;
 *   - E3: a listed row named "Sample runbook.md" hides the button, and its removal brings it back;
 *   - E4: Tab reaches the button after Add documents, and Enter presses it.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US' });

const DOCUMENTS = '/ocutalon/api/v1/documents';
const MESSAGES = '/ocutalon/api/v1/messages';
const SAMPLE_BUTTON = 'Add the sample runbook';
const NOT_BUILT = "Couldn't read it: this part of OcuTalon isn't built yet.";
const SECTION = 'When orders fail with a date error';
const CHIP_NAME = `Sample runbook, section ${SECTION}`;
const CHIP_LABEL = `Sample runbook \u00A7 ${SECTION}`;
const REPLY = 'The CI mock answered from the sample runbook.';
const READY_MS = 120_000;
const REPLY_MS = 30_000;

const { name: SAMPLE_NAME, text: SAMPLE_TEXT, question: QUESTION } = SAMPLE_RUNBOOK_TEXTS;

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sampleButton = (page: Page): Locator => page.getByRole('button', { name: SAMPLE_BUTTON, exact: true });
const sampleRow = (page: Page): Locator => page.locator('li.row').filter({ hasText: SAMPLE_NAME });
const listRegion = (page: Page): Locator => page.getByRole('region', { name: 'Documents', exact: true });
const isPost = (method: string, url: string): boolean => method === 'POST' && new URL(url).pathname === DOCUMENTS;

/** The refs of the fixture rows a case made, removed after it. */
const made: string[] = [];

test.afterEach(async () => {
  await cleanFixtureRows(made.splice(0));
});

/** Signs the chat user in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('CHAT');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

/** Opens the Documents page from the header and waits for its list. */
async function openDocuments(page: Page): Promise<void> {
  const listed = page.waitForResponse((response) => response.request().method() === 'GET' && new URL(response.url()).pathname === DOCUMENTS);
  listed.catch(() => undefined);
  await pagesNav(page).getByRole('link', { name: 'Documents', exact: true }).click();
  expect((await listed).status(), 'GET /v1/documents').toBe(200);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Documents');
}

/** Removes every document named "Sample runbook.md" that the signed-in user can list, through the real DELETE route; returns how many it removed. */
async function removeSamples(page: Page): Promise<number> {
  const listed = await page.request.get(DOCUMENTS);
  expect(listed.status(), 'GET /v1/documents').toBe(200);
  const refs = ((await listed.json()) as { documents: Array<{ ref: string; name: string }> }).documents.filter((one) => one.name === SAMPLE_NAME).map((one) => one.ref);
  for (const ref of refs) {
    const removed = await page.request.fetch(`${DOCUMENTS}/${encodeURIComponent(ref)}`, { method: 'DELETE', headers: envelope(), data: '{}' });
    expect(removed.status(), `DELETE ${ref}: ${await removed.text()}`).toBe(200);
  }
  return refs.length;
}

/** Fulfils the next POSTs of a document with a 200 for a ref the stack never stored, and records their bodies. */
async function fakeAdds(page: Page): Promise<Array<{ name: string; content: string }>> {
  const bodies: Array<{ name: string; content: string }> = [];
  await page.route(`**${DOCUMENTS}`, (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    bodies.push(route.request().postDataJSON() as { name: string; content: string });
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', ref: `zzE${bodies.length}` }) });
  });
  return bodies;
}

/** E0: the chat user holds nothing but OcuTalonUser. */
test('E0: the chat user holds nothing but OcuTalonUser', async () => {
  const { user } = fixtureUser('CHAT');
  const lines = await irisScript(
    ['New $Namespace', 'Set $Namespace="%SYS"', `Set sc=##class(Security.Users).Get(${quoted(user)},.p)`, 'Write !,"CHK|roles|",$Get(p("Roles"))'].join('\n'),
  );
  expect(chk(lines, 'roles'), `the chat user holds exactly OcuTalonUser (${lines.join(' ')})`).toBe('OcuTalonUser');
});

/** E1: the demo-visible path, from the press to the cited chip. */
test.describe('E1: the sample runbook in one press', () => {
  /** The mark of the saved AI sessions before the case (RunnerFixture.SessionMark), for the clean-up. */
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
      await wipe();
    } finally {
      try {
        await restoreKeys();
      } finally {
        const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
        expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
      }
    }
  });

  /** Removes the chat user's turns and the AI sessions the case's turns saved. */
  async function wipe(): Promise<void> {
    const { user } = fixtureUser('CHAT');
    const drop = /^\d+$/.test(mark) ? [`Write !,"CHK|dropped|",$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(${mark}))`] : [];
    const lines = await irisScript(
      [`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`, 'Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(s.Ref)', 'Write !,"CHK|turns|1"', ...drop].join('\n'),
    );
    expect(chk(lines, 'turns'), `the turns of the case are removed (${lines.join(' ')})`).toBe('1');
    if (drop.length > 0) expect(chk(lines, 'dropped'), `the AI sessions of the turns are dropped (${lines.join(' ')})`).toBe('1');
  }

  /** Types the text into the composer, presses the main Send button and returns the clientId of the POST /messages. */
  async function send(page: Page, text: string): Promise<string> {
    const request = page.waitForRequest((candidate) => candidate.method() === 'POST' && new URL(candidate.url()).pathname === MESSAGES);
    await composerOf(page).fill(text);
    await page.getByRole('main').getByRole('button', { name: 'Send', exact: true }).click();
    return ((await request).postDataJSON() as { clientId: string }).clientId;
  }

  test('E1: a press adds the sample once, it reaches Ready, and the suggested question ends with a chip that names the runbook and its section', async ({ page }) => {
    test.setTimeout(300_000);
    await open(page);
    try {
      await removeSamples(page);
      const posts: Array<{ name: string; content: string }> = [];
      await page.route(`**${DOCUMENTS}`, async (route) => {
        if (route.request().method() !== 'POST') return route.fallback();
        posts.push(route.request().postDataJSON() as { name: string; content: string });
        await new Promise((resolve) => setTimeout(resolve, 1500));
        return route.continue();
      });
      await openDocuments(page);
      const button = sampleButton(page);
      await expect(button, 'no row is named the sample, so the button shows').toBeVisible();
      await expect(sampleRow(page)).toHaveCount(0);
      const answered = page.waitForResponse((response) => isPost(response.request().method(), response.url()));
      answered.catch(() => undefined);
      await button.click();
      await expect(button, 'the button is busy').toHaveAttribute('aria-busy', 'true');
      await expect(button).toHaveAttribute('aria-disabled', 'true');
      await expect(button).not.toHaveAttribute('disabled', /.*/);
      await expect(button, 'it keeps its label').toHaveText(SAMPLE_BUTTON);
      await expect(button.locator('app-icon.spinner'), 'and gains a spinner').toHaveCount(1);
      await expect(sampleRow(page).locator('.status'), 'the page\'s own row reads Indexing').toHaveText('Indexing\u2026');
      await button.focus();
      await page.keyboard.press('Enter');
      const response = await answered;
      expect(response.status(), await response.text()).toBe(200);
      const ref = ((await response.json()) as { ref: string }).ref;
      expect(posts.length, 'a second press while the add is out makes no second POST').toBe(1);
      expect(posts[0]!.name).toBe(SAMPLE_NAME);
      expect(Buffer.from(posts[0]!.content, 'base64').toString('utf8'), 'the content is the bundled runbook').toBe(SAMPLE_TEXT);

      await expect(sampleRow(page).locator('.status'), 'the real row reaches Ready, live').toHaveText('Ready', { timeout: READY_MS });
      await expect(sampleRow(page)).toHaveCount(1);
      await expect(button, 'the button has left').toHaveCount(0);
      await expect(listRegion(page), 'and focus is on the list region').toBeFocused();
      expect(posts.length, 'still one POST').toBe(1);
      expect(ref).not.toBe('');

      await pagesNav(page).getByRole('link', { name: 'Chat', exact: true }).click();
      await expect(composerOf(page)).toBeVisible();
      const askId = await send(page, `${QUESTION} [[mock:sample-runbook]]`);
      await expect(replyOf(page, askId), "the scenario's reply shows").toContainText(REPLY, { timeout: REPLY_MS });
      const chips = replyOf(page, askId).getByRole('group', { name: 'Sources', exact: true });
      const chip = chips.getByRole('button', { name: CHIP_NAME, exact: true });
      await expect(chip, 'the answer ends with a chip that names the runbook and its section').toHaveCount(1, { timeout: REPLY_MS });
      await expect(chip).toContainText(CHIP_LABEL);
      await expect(chips.getByRole('button'), 'and with no other chip').toHaveCount(1);
      await chip.click();
      const dialog = page.getByRole('dialog', { name: CHIP_LABEL, exact: true });
      await expect(dialog).toBeVisible();
      const passage = dialog.locator('[data-part="passage"]');
      await expect(passage, 'its popover holds the one passage of the section').toHaveCount(1);
      expect((await passage.textContent())?.startsWith('OrdersFromPartner accepts'), 'and the passage starts with the section\'s first words').toBe(true);
    } finally {
      await removeSamples(page).catch(() => undefined);
    }
  });
});

/** E2: a refused add shows the page's own row text once, and the button stays with focus. */
test('E2: a refused add reads "Couldn\'t read it: this part of OcuTalon isn\'t built yet.", announced once, and the button stays', async ({ page }) => {
  await recordAnnouncements(page);
  await open(page);
  await removeSamples(page);
  let posts = 0;
  await page.route(`**${DOCUMENTS}`, (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    posts += 1;
    return route.fulfill({ status: 501, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_built', message: 'zz' } }) });
  });
  await openDocuments(page);
  const button = sampleButton(page);
  await button.click();
  await expect(sampleRow(page).locator('.status'), 'the page\'s own row').toHaveText(NOT_BUILT);
  await expect(button, 'the button stays').toBeVisible();
  await expect(button).toBeFocused();
  await expect(button, 'and is not busy any more').not.toHaveAttribute('aria-busy', 'true');
  await page.waitForTimeout(1500);
  expect(await announcements(page, NOT_BUILT), 'announced once').toBe(1);
  await page.keyboard.press('Enter');
  await expect.poll(() => posts, 'it can be pressed again').toBe(2);
});

/** E3: a listed row named for the sample hides the button, and its removal brings the button back. */
test('E3: a row named "Sample runbook.md" hides the button until that row is removed', async ({ page }) => {
  await open(page);
  await removeSamples(page);
  const lines = await irisScript(
    [
      `Set ref=##class(OcuTalon.Test.Data.Fixture).Document("instance",${quoted(SAMPLE_NAME)},##class(%DynamicObject).%FromJSON(${quoted('{"State":"ready","Size":"512"}')}))`,
      'Write !,"CHK|ref|",ref',
    ].join('\n'),
  );
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`the fixture document could not be made (${lines.join(' ')})`);
  made.push(ref);
  await openDocuments(page);
  await expect(sampleRow(page), 'the seeded row is listed').toHaveCount(1);
  await expect(sampleButton(page), 'so there is no button').toHaveCount(0);
  await publishFixtureEvent(fixtureUser('CHAT').user, 'document', 'OcuTalon.Live.Payload.Document', { Ref: ref, Name: SAMPLE_NAME, Removed: '1' });
  await expect(sampleRow(page), 'the row leaves on its removed event').toHaveCount(0, { timeout: CARD_MS });
  await expect(sampleButton(page), 'and the button shows again').toBeVisible();
});

/** E4: Tab reaches the button after Add documents, and Enter presses it. */
test('E4: Tab from Add documents reaches Add the sample runbook, and Enter presses it', async ({ page }) => {
  await open(page);
  await removeSamples(page);
  const bodies = await fakeAdds(page);
  await openDocuments(page);
  await page.getByRole('button', { name: 'Add documents', exact: true }).focus();
  await page.keyboard.press('Tab');
  const button = sampleButton(page);
  await expect(button, 'Tab reaches it').toBeFocused();
  expect(await button.evaluate((node) => node.tagName), 'a native button').toBe('BUTTON');
  await page.keyboard.press('Enter');
  await expect.poll(() => bodies.length, 'Enter makes the add').toBe(1);
  expect(bodies[0]!.name).toBe(SAMPLE_NAME);
  await expect(button, 'the pending row lists the sample, so the button leaves').toHaveCount(0);
  await expect(listRegion(page)).toBeFocused();
});
