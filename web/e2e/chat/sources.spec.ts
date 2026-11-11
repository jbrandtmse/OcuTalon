import { expect, test, type APIRequestContext, type Locator, type Page } from '../support/fixtures';

import { expectError, signIn, signInOverHttp } from '../sign-in/helpers';
import { STATE } from '../support/api';
import { pointKeys, restoreKeys } from '../support/devices';
import { composerOf, loadedAfter, replyOf } from '../support/floor';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted, seedTurns, turnRows, type SeedCitation, type SeedMemory, type SeedTurn } from '../support/iris';
import { clock, plain, tokenColor } from '../support/page';

/**
 * Story 20.2, the sources under an answer and the document text they open (S0 to S9), in a real browser against a real stack. The seeded
 * cases sign in as the decision fixture user (OCUTALON_DECISION_USER), seed turns that carry citations and memories as Lane A's HostData
 * carries them into its own session, and read what the page draws; S5 asks GET /v1/documents/:ref over real HTTP as the decision user and
 * the chat user, who hold nothing but OcuTalonUser (S0 reads their roles); S7 drives a real turn through the composer and the CI mock as
 * the chat user. The browser runs in Asia/Kolkata with the en-US locale, so a time is the same wherever the specs run.
 *   - S0: both fixture users hold exactly OcuTalonUser;
 *   - S1: a cited answer ends with a group "Sources" of one chip for each document section after the reply text and the check rows; the
 *     chip is a button named "{document}, section {section}" (no section sign) that reads "{document} \u00A7 {section}", draws the
 *     citation-chip tokens with the file-text icon, is underlined while open, and opens a dialog named by its heading with every passage
 *     of the section, each clamped to six lines and shown as plain text; Enter or a press opens it with focus on Open document, Esc, a
 *     press outside and Shift+Tab out of it close it and return focus to the chip, and a second press closes it;
 *   - S2: a section-less passage is the document alone; a memory is a "From memory" chip named with its text cut to 80 characters,
 *     after the citation chips, whose dialog holds the text, focused, and "Saved {when}";
 *   - S3 (DW-721, U-280): a reply that says the none-line with no citations shows it and no chip, and a reply with citations has chips
 *     and never says it;
 *   - S4: Open document opens #/documents?doc=<ref>: the document's name as a heading with focus on it, its text exactly as stored as
 *     plain text (markup and Markdown stay characters), Close; a removed or unknown document reads the failure line;
 *   - S4b: removing the document whose text is open takes its text away;
 *   - S5: GET /v1/documents/:ref over real HTTP: an own document and an instance document are 200 with their text; another session's
 *     document and an unknown ref are 404 not_found with no text;
 *   - S6: the markup in a document is text on the Documents page and in a passage popover;
 *   - S7: a memory saved and recalled through the composer and the CI mock shows the "From memory" chip under the recall;
 *   - S8, S9 (QA): the memory chip's Enter, outside press, Shift+Tab and Esc rules and its plain text; a second chip swaps the popover;
 *   - S10 (Story 41.15): a turn that learned facts shows one line for each after the check rows and before the source chips, `I'll remember this: "{fact}". You can tell me to forget it.`,
 *     with one trailing full stop removed and a long fact cut to 200 characters with an ellipsis, and markup shown as characters (no element is made);
 *   - S11 (Story 41.15): a reply that already says "I'll remember" shows no line;
 *   - S12 (Story 41.15): a learned fact sent through the composer and the CI mock shows the line live and after a reload, and a told save shows none.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US' });

const NONE_LINE = 'None of your documents cover that.';
const DOCUMENTS = '/ocutalon/api/v1/documents';
const MESSAGES = '/ocutalon/api/v1/messages';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const FAILED = "Couldn't open that document. It may have been removed.";
/** A document text with markup, a script and Markdown, which must show as characters. */
const RAW = '<b>bold</b> <script>window.__x=1</script> **md** # Heading';
/** How long a reply may take to show after the send: the turn, the live poll and the render. */
const REPLY_MS = 30_000;

/** The refs of the fixture rows a case made, removed after it. */
const made: string[] = [];

test.afterEach(async () => {
  await cleanFixtureRows(made.splice(0));
});

/** A citation of the fixture document. */
const cite = (documentRef: string, section: string, passage: string, chunkIndex: number, document = 'Results runbook'): SeedCitation => ({ documentRef, document, section, passage, chunkIndex });

/** A done turn with the sources given; it has no decision, so it has no strip. */
const turn = (label: string, over: Partial<SeedTurn> = {}): SeedTurn => ({ createdAt: '2025-03-02T10:00:00Z', text: `zz ${label}`, replyText: `zz reply to ${label}`, ...over });

/** Seeds turns into the decision user's session and records their rows for the clean-up. */
async function seed(turns: SeedTurn[]): Promise<string[]> {
  const seeded = await seedTurns(fixtureUser('DECISION').user, turns);
  made.push(...turnRows(seeded));
  return seeded.refs;
}

/** Seeds a ready document of the owner (a user name, or "instance") whose text is the text; returns its Ref. */
async function seedDocument(owner: string, name: string, text: string): Promise<string> {
  const lines = await irisScript(
    [
      ...(owner === 'instance' ? [] : [`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(owner)},.sc)`]),
      `Set ref=##class(OcuTalon.Test.Data.Fixture).Document(${owner === 'instance' ? '"instance"' : 's.Ref'},${quoted(name)},##class(%DynamicObject).%FromJSON(${quoted('{"State":"ready"}')}))`,
      'Set d=##class(OcuTalon.Data.Document).RefIndexOpen(ref)',
      `Do d.Text.Write(${quoted(text)})`,
      'Set sc=d.%Save()',
      'Write !,"CHK|ref|",ref,"|",$System.Status.IsOK(sc)',
    ].join('\n'),
  );
  const [ref, saved] = (chk(lines, 'ref') ?? '').split('|');
  if (!ref || saved !== '1') throw new Error(`the fixture document could not be made (${lines.join(' ')})`);
  made.push(ref);
  return ref;
}

/** Signs a fixture user in and waits for the loaded page with its composer. */
async function open(page: Page, kind: 'DECISION' | 'CHAT'): Promise<void> {
  const { user, password } = fixtureUser(kind);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

const sourcesOf = (page: Page, key: string): Locator => replyOf(page, key).getByRole('group', { name: 'Sources', exact: true });
const chipOf = (page: Page, key: string, name: string): Locator => sourcesOf(page, key).getByRole('button', { name, exact: true });
const dialogOf = (page: Page, name: string): Locator => page.getByRole('dialog', { name, exact: true });

/** S0: the two users that the cases use hold exactly the OcuTalonUser role. */
test('S0: the decision user and the chat user hold nothing but OcuTalonUser', async () => {
  for (const kind of ['DECISION', 'CHAT'] as const) {
    const { user } = fixtureUser(kind);
    const lines = await irisScript(
      ['New $Namespace', 'Set $Namespace="%SYS"', `Set sc=##class(Security.Users).Get(${quoted(user)},.p)`, 'Write !,"CHK|roles|",$Get(p("Roles"))'].join('\n'),
    );
    expect(chk(lines, 'roles'), `${kind} holds exactly OcuTalonUser (${lines.join(' ')})`).toBe('OcuTalonUser');
  }
});

/** S1: a cited answer ends with citation chips, and a chip opens a popover with the passages and Open document. */
test('S1: a cited answer ends with one chip for each document section, and a chip opens its passages', async ({ page }) => {
  const twelve = Array.from({ length: 12 }, (_, i) => `Line ${i + 1} of the passage`).join('\n');
  const [ref] = await seed([
    turn('S1', {
      replyText: 'Rotate the certificate from the Certificates page.',
      checkKey: 'checks.allPassed',
      checks: [{ result: 'passed', entry: 'Orders production', finding: '', checkedAt: '2025-03-01T10:00:00Z' }],
      citations: [
        cite('zzDocS1', 'Rotating the certificate', twelve, 3),
        cite('zzDocS1', 'Checking the expiry', RAW, 5),
        cite('zzDocS1', 'Rotating the certificate', 'Second passage of the same section.', 4),
      ],
    }),
  ]);
  await open(page, 'DECISION');
  const group = sourcesOf(page, ref!);
  await expect(group, 'one group named Sources').toHaveCount(1);
  const chips = group.getByRole('button');
  await expect(chips, 'two chips: the same section twice is one chip').toHaveCount(2);

  const first = chipOf(page, ref!, 'Results runbook, section Rotating the certificate');
  await expect(first, 'the accessible name has no section sign').toHaveCount(1);
  await expect(first).toHaveAttribute('aria-haspopup', 'dialog');
  await expect(first).toHaveAttribute('aria-expanded', 'false');
  await expect(first.locator('span'), 'the visible label has the section sign').toHaveText('Results runbook \u00A7 Rotating the certificate');
  await expect(first.locator('svg[aria-hidden="true"]'), 'with the file-text icon').toHaveCount(1);
  await expect(first.locator('svg path[d="M10 9H8"]'), 'which is Lucide file-text').toHaveCount(1);
  await expect(first).toHaveCSS('background-color', await tokenColor(page, '--citation-chip-background'));
  await expect(first).toHaveCSS('color', await tokenColor(page, '--citation-chip-foreground'));
  await expect(first).toHaveCSS('border-top-width', '1px');
  await expect(first).toHaveCSS('border-top-color', await tokenColor(page, '--citation-chip-foreground'));
  await expect(first).toHaveCSS('border-top-left-radius', '4px');
  await expect(first).toHaveCSS('font-size', '12px');
  expect(((await first.boundingBox())?.height ?? 0), 'a target of at least 24px').toBeGreaterThanOrEqual(24);

  const reply = replyOf(page, ref!);
  const textBox = (await reply.locator('.text').boundingBox())!;
  const rowsBox = (await reply.locator('app-check-rows').boundingBox())!;
  const groupBox = (await group.boundingBox())!;
  expect(groupBox.y, 'the chips come after the reply text and the check rows').toBeGreaterThanOrEqual(Math.max(textBox.y + textBox.height, rowsBox.y + rowsBox.height) - 1);
  await expect(reply.locator('.text'), 'the reply text holds no chip text').not.toContainText('Results runbook');

  // Enter opens it with focus inside, on Open document.
  await first.focus();
  await page.keyboard.press('Enter');
  const dialog = dialogOf(page, 'Results runbook \u00A7 Rotating the certificate');
  await expect(dialog, 'the popover is a dialog named by its heading').toBeVisible();
  await expect(first).toHaveAttribute('aria-expanded', 'true');
  await expect(first, 'the open chip is underlined, not marked by colour alone').toHaveCSS('text-decoration-line', 'underline');
  await expect(dialog.getByRole('heading', { level: 2 })).toHaveText('Results runbook \u00A7 Rotating the certificate');
  const passages = dialog.locator('[data-part="passage"]');
  await expect(passages, 'both passages of the section, in order').toHaveCount(2);
  expect(await passages.nth(0).evaluate((el) => el.textContent), 'the passage is its text, line breaks included').toBe(twelve);
  await expect(passages.nth(1)).toHaveText('Second passage of the same section.');
  const clamp = await passages.nth(0).evaluate((el) => {
    const style = getComputedStyle(el);
    return { client: el.clientHeight, scroll: el.scrollHeight, line: parseFloat(style.lineHeight), white: style.whiteSpace };
  });
  expect(clamp.client, 'at most 6 lines').toBeLessThanOrEqual(clamp.line * 6 + 1);
  expect(clamp.scroll, 'of a 12-line passage, which is cut').toBeGreaterThan(clamp.client);
  expect(clamp.white, 'with its line breaks kept').toBe('pre-wrap');
  const openLink = dialog.getByRole('link', { name: 'Open document', exact: true });
  await expect(openLink).toHaveAttribute('href', new RegExp(`#/documents\\?doc=zzDocS1$`));
  await expect(openLink, 'focus is inside the popover, on its first control').toBeFocused();

  // Esc closes it and returns focus to the chip.
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(first).toBeFocused();
  await expect(first).toHaveAttribute('aria-expanded', 'false');
  await expect(first, 'and no longer underlined').toHaveCSS('text-decoration-line', 'none');

  // A press outside closes it, and focus is on the chip again.
  await first.click();
  await expect(dialog).toBeVisible();
  await page.getByRole('banner').click({ position: { x: 2, y: 2 } });
  await expect(dialog).toHaveCount(0);
  await expect(first).toBeFocused();

  // Shift+Tab out of it (focus then sits on neither the chip nor the popover) closes it, and focus is on the chip again.
  await first.click();
  await expect(openLink).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(dialog).toHaveCount(0);
  await expect(first).toBeFocused();

  // A second press of the same chip closes it.
  await first.click();
  await expect(dialog).toBeVisible();
  await first.click();
  await expect(dialog).toHaveCount(0);

  // The other chip: its passage is plain text, whatever it holds (S6 reads it on the Documents page too).
  const second = chipOf(page, ref!, 'Results runbook, section Checking the expiry');
  await second.click();
  const other = dialogOf(page, 'Results runbook \u00A7 Checking the expiry');
  await expect(other).toBeVisible();
  expect(await other.locator('[data-part="passage"]').evaluate((el) => el.textContent), 'the markup stays characters').toBe(RAW);
  await expect(other.locator('b, script, h1, strong, em'), 'and makes no element').toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { __x?: number }).__x), 'and runs no script').toBeUndefined();
  await page.keyboard.press('Escape');
});

/** S2: a section-less passage, and a memory chip with its popover. */
test('S2: a passage under no heading is the document alone, and a memory is a From memory chip after the citations', async ({ page }) => {
  const remembered = `Lee is the Results partner's contact. ${'The contact is reachable on weekdays. '.repeat(4)}`.trim();
  const cut = `${plain(remembered).slice(0, 80)}\u2026`;
  const saved: SeedMemory = { memoryRef: 'zzMemS2', text: remembered, savedAt: '2025-03-01T10:00:00Z' };
  const [ref] = await seed([
    turn('S2', {
      citations: [cite('zzDocS2', '', 'An intro under no heading.', 0)],
      memories: [saved],
    }),
  ]);
  await open(page, 'DECISION');
  const group = sourcesOf(page, ref!);
  const chips = group.getByRole('button');
  await expect(chips).toHaveCount(2);
  const citation = chipOf(page, ref!, 'Results runbook');
  await expect(citation, 'the section-less chip is named by the document alone').toHaveCount(1);
  await expect(citation.locator('span')).toHaveText('Results runbook');
  const memory = chipOf(page, ref!, `From memory: ${cut}`);
  await expect(memory, 'the memory chip is named with its text cut to 80 characters').toHaveCount(1);
  await expect(memory.locator('span'), 'and reads From memory').toHaveText('From memory');
  await expect(memory).toHaveAttribute('aria-haspopup', 'dialog');
  await expect(memory.locator('svg'), 'it has no icon').toHaveCount(0);
  await expect(memory).toHaveCSS('background-color', await tokenColor(page, '--citation-chip-background'));
  expect(await chips.evaluateAll((all) => all.map((one) => one.getAttribute('data-source'))), 'the citation chips come first').toEqual(['citation', 'memory']);

  await memory.click();
  const dialog = dialogOf(page, 'From memory');
  await expect(dialog).toBeVisible();
  const text = dialog.locator('[data-part="memory"]');
  expect(await text.evaluate((el) => el.textContent), 'the whole remembered text').toBe(remembered);
  await expect(text, 'focus goes into the popover, onto the text').toBeFocused();
  await expect(dialog.getByText(/^Saved /), 'the date it was saved').toContainText('Mar 1, 2025');
  await expect(dialog.getByText(/^Saved /)).toContainText(clock('2025-03-01T10:00:00Z'));
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(memory).toBeFocused();
});

/** S3 (DW-721, U-280): the none-line and the chips never come together. */
test('S3: a reply that says no document covers it has no chip, and a reply with chips never says it', async ({ page }) => {
  const [noneRef, citedRef, bareRef] = await seed([
    turn('S3 none', { createdAt: '2025-03-02T10:00:00Z', replyText: NONE_LINE }),
    turn('S3 cited', { createdAt: '2025-03-02T10:05:00Z', replyText: 'The steps are in the runbook.', citations: [cite('zzDocS3', 'Steps', 'Do the steps.', 1)] }),
    turn('S3 bare', { createdAt: '2025-03-02T10:10:00Z', replyText: 'Nothing about documents here.' }),
  ]);
  await open(page, 'DECISION');
  await expect(replyOf(page, noneRef!).locator('.text'), 'the sentence is shown as sent').toHaveText(NONE_LINE);
  await expect(replyOf(page, noneRef!).getByRole('button'), 'with no chip').toHaveCount(0);
  await expect(sourcesOf(page, noneRef!)).toHaveCount(0);
  await expect(replyOf(page, citedRef!).locator('.text')).toHaveText('The steps are in the runbook.');
  await expect(replyOf(page, citedRef!).locator('.text'), 'a reply with chips never says it').not.toContainText(NONE_LINE);
  await expect(chipOf(page, citedRef!, 'Results runbook, section Steps')).toHaveCount(1);
  await expect(sourcesOf(page, bareRef!), 'a reply with no sources has no group').toHaveCount(0);
  for (const group of await page.getByRole('group', { name: 'Sources', exact: true }).all()) {
    const text = await group.evaluate((el) => el.closest('[data-part="reply"]')?.querySelector('.text')?.textContent ?? '');
    expect(text, 'every reply that has a Sources group omits the sentence').not.toContain(NONE_LINE);
  }
});

/** S4: Open document shows the document's name and text on the Documents page. */
test('S4: Open document shows the document name and its text, and Close puts the page back', async ({ page }) => {
  const { user } = fixtureUser('DECISION');
  const name = `zz S4 runbook ${Date.now().toString(36)}.md`;
  const text = `${RAW}\nSecond line of the document.\n\nAfter a blank line.`;
  const docRef = await seedDocument(user, name, text);
  const [ref] = await seed([turn('S4', { citations: [cite(docRef, 'Steps', 'Do the steps.', 1, name)] })]);
  await open(page, 'DECISION');
  await chipOf(page, ref!, `${name}, section Steps`).click();
  const dialog = dialogOf(page, `${name} \u00A7 Steps`);
  await expect(dialog).toBeVisible();
  const fetched = page.waitForResponse((response) => response.request().method() === 'GET' && new URL(response.url()).pathname === `${DOCUMENTS}/${docRef}`);
  await dialog.getByRole('link', { name: 'Open document', exact: true }).click();
  expect((await fetched).status(), 'GET /v1/documents/:ref').toBe(200);
  expect(new URL(page.url()).hash, 'at #/documents?doc=<ref>').toBe(`#/documents?doc=${docRef}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Documents');
  const region = page.getByRole('region', { name, exact: true });
  await expect(region, 'a region named by the document').toHaveCount(1);
  const heading = region.getByRole('heading', { level: 2 });
  await expect(heading).toHaveText(name);
  await expect(heading, 'focus is on the heading').toBeFocused();
  const body = region.locator('.opened-text');
  expect(await body.evaluate((el) => el.textContent), 'the whole text exactly as stored').toBe(text);
  expect(await body.evaluate((el) => getComputedStyle(el).whiteSpace), 'with its line breaks').toBe('pre-wrap');
  await expect(region.locator('b, script, h1'), 'markup and Markdown make no element').toHaveCount(0);
  await expect(page.getByRole('heading', { level: 1 }), 'the page keeps its one h1').toHaveCount(1);
  expect(await page.evaluate(() => (window as unknown as { __x?: number }).__x), 'no script ran').toBeUndefined();

  await region.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(region).toHaveCount(0);
  expect(new URL(page.url()).hash, 'the parameter is gone').toBe('#/documents');
  await expect(page.getByRole('region', { name: 'Documents', exact: true }), 'focus goes to the list').toBeFocused();

  // A document that is gone, one that is another session's and one that never was read the failure line.
  const removed = await seedDocument(user, `zz S4 removed ${Date.now().toString(36)}.md`, 'zz removed text');
  await cleanFixtureRows([removed]);
  const theirs = await seedDocument(fixtureUser('CHAT').user, `zz S4 theirs ${Date.now().toString(36)}.md`, RAW);
  for (const gone of ['zzNoSuchDocument00000', removed, theirs]) {
    await page.evaluate((value) => {
      window.location.hash = `#/documents?doc=${value}`;
    }, gone);
    const failure = page.locator('[data-part="document-text"] .opened-failed');
    await expect(failure, `'${gone}' cannot be opened`).toHaveText(FAILED);
    await expect(failure).toBeFocused();
    await expect(page.locator('[data-part="document-text"]').getByText(RAW), 'no text leaks').toHaveCount(0);
    await page.getByRole('button', { name: 'Close', exact: true }).click();
    await expect(failure).toHaveCount(0);
  }
});

/** S4b: removing the document whose text is open takes the text away and drops the parameter. */
test('S4b: removing the open document closes its text', async ({ page }) => {
  const { user } = fixtureUser('DECISION');
  const name = `zz S4b runbook ${Date.now().toString(36)}.md`;
  const docRef = await seedDocument(user, name, 'zz S4b text');
  await open(page, 'DECISION');
  await page.evaluate((value) => {
    window.location.hash = `#/documents?doc=${value}`;
  }, docRef);
  const region = page.getByRole('region', { name, exact: true });
  await expect(region, 'the text is open').toHaveCount(1);
  await page.route(`**${DOCUMENTS}/*`, (route) => (route.request().method() === 'DELETE' ? route.fulfill({ status: 200, contentType: 'application/json', body: '{"result":"done"}' }) : route.fallback()));
  await page.getByRole('button', { name: `Remove ${name}`, exact: true }).click();
  await dialogOf(page, `Remove '${name}'? Answers will stop citing it.`).getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(region, 'the removed document\'s text leaves with its row').toHaveCount(0);
  await expect.poll(() => new URL(page.url()).hash, 'the parameter is gone').toBe('#/documents');
});

/** S5: GET /v1/documents/:ref over real HTTP, as two users that hold OcuTalonUser only. */
test.describe('S5: GET /v1/documents/:ref', () => {
  let a: APIRequestContext;
  let b: APIRequestContext;

  test.beforeAll(async ({ playwright }) => {
    a = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    b = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    const first = fixtureUser('DECISION');
    const second = fixtureUser('CHAT');
    await signInOverHttp(a, first.user, first.password);
    await signInOverHttp(b, second.user, second.password);
  });

  test.afterAll(async () => {
    await a.dispose();
    await b.dispose();
  });

  test('an own document and an instance document are 200 with their text, and another session\'s document is 404 for B', async () => {
    const text = `${RAW}\nS5 text`;
    const own = await seedDocument(fixtureUser('DECISION').user, 'zz S5 own.md', text);
    const shared = await seedDocument('instance', 'zz S5 instance.md', 'zz S5 instance text');

    const mine = await a.get(`${DOCUMENTS}/${own}`);
    expect(mine.status(), await mine.text()).toBe(200);
    expect(mine.headers()['content-type']).toContain('application/json');
    const body = (await mine.json()) as { ref: string; name: string; text: string };
    expect(Object.keys(body), 'the keys of the answer').toEqual(['ref', 'name', 'text']);
    expect([body.ref, body.name, body.text], 'A reads its own document').toEqual([own, 'zz S5 own.md', text]);

    const instance = await a.get(`${DOCUMENTS}/${shared}`);
    expect(instance.status(), 'on a local install A reads the instance\'s document').toBe(200);
    expect(((await instance.json()) as { text: string }).text).toBe('zz S5 instance text');
    const instanceForB = await b.get(`${DOCUMENTS}/${shared}`);
    expect(instanceForB.status(), 'and so does B').toBe(200);

    const theirs = await b.get(`${DOCUMENTS}/${own}`);
    await expectError(theirs, 404, 'not_found', NOT_FOUND);
    expect(await theirs.text(), 'with no text of A\'s document').not.toContain('S5 text');

    await expectError(await a.get(`${DOCUMENTS}/zzNoSuchDocument00000`), 404, 'not_found', NOT_FOUND);
    await expectError(await b.get(`${DOCUMENTS}/zzNoSuchDocument00000`), 404, 'not_found', NOT_FOUND);
    const stillMine = await a.get(`${DOCUMENTS}/${own}`);
    expect(stillMine.status(), 'A still reads it').toBe(200);
  });

  test('the route submits and publishes nothing: the list and the session stream are as they were', async () => {
    const own = await seedDocument(fixtureUser('DECISION').user, 'zz S5 quiet.md', 'zz quiet');
    const read = async (): Promise<{ refs: string[]; seq: number }> => {
      const listed = (await (await a.get(DOCUMENTS)).json()) as { documents: Array<{ ref: string }> };
      const state = (await (await a.get(STATE)).json()) as { streams: { session: number } };
      return { refs: listed.documents.map((one) => one.ref), seq: state.streams.session };
    };
    const before = await read();
    for (let i = 0; i < 3; i += 1) expect((await a.get(`${DOCUMENTS}/${own}`)).status()).toBe(200);
    expect(await read(), 'the same documents and the same last Seq').toEqual(before);
  });
});

/** S6: markup in a document is text on the Documents page. */
test('S6: markup in a document shows as characters on the Documents page', async ({ page }) => {
  const { user } = fixtureUser('DECISION');
  const name = `zz S6 markup ${Date.now().toString(36)}.md`;
  const docRef = await seedDocument(user, name, RAW);
  await open(page, 'DECISION');
  await page.evaluate((value) => {
    window.location.hash = `#/documents?doc=${value}`;
  }, docRef);
  const region = page.getByRole('region', { name, exact: true });
  const body = region.locator('.opened-text');
  await expect(body).toBeVisible();
  expect(await body.evaluate((el) => el.textContent), 'textContent is the raw text').toBe(RAW);
  expect(await body.evaluate((el) => el.children.length), 'it has no child element').toBe(0);
  await expect(region.locator('b, script, h1'), 'no b, script or h1 was made').toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { __x?: number }).__x), 'window.__x is undefined').toBeUndefined();
});

/**
 * S8 (QA, the memory chip's keyboard and pointer rules and plain text): Enter opens the popover with focus on the remembered text, which
 * is plain text whatever it holds; an outside press, Shift+Tab and Esc close it, and focus is on the chip that opened it
 * (the citation chip's rules are S1; the memory chip is a second trigger with a text block of its own to focus).
 */
test('S8: the From memory chip opens with Enter, shows its text as characters, and an outside press, Shift+Tab and Esc close it onto the chip', async ({ page }) => {
  const saved: SeedMemory = { memoryRef: 'zzMemS8', text: RAW, savedAt: '2025-03-01T10:00:00Z' };
  const [ref] = await seed([turn('S8', { citations: [cite('zzDocS8', 'Steps', 'Do the steps.', 1)], memories: [saved] })]);
  await open(page, 'DECISION');
  const memory = chipOf(page, ref!, `From memory: ${RAW}`);
  await expect(memory, 'the chip is named with the whole text, which is under 80 characters').toHaveCount(1);
  const dialog = dialogOf(page, 'From memory');

  await memory.focus();
  await page.keyboard.press('Enter');
  await expect(dialog).toBeVisible();
  await expect(memory).toHaveAttribute('aria-expanded', 'true');
  const text = dialog.locator('[data-part="memory"]');
  await expect(text, 'Enter puts focus inside the popover, on the text').toBeFocused();
  expect(await text.evaluate((el) => el.textContent), 'the memory is its raw text').toBe(RAW);
  expect(await text.evaluate((el) => el.children.length), 'with no child element').toBe(0);
  await expect(dialog.locator('b, script, h1, strong, em'), 'markup and Markdown make no element').toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { __x?: number }).__x), 'no script ran').toBeUndefined();

  // A press outside closes it, and focus is on the chip.
  await page.getByRole('banner').click({ position: { x: 2, y: 2 } });
  await expect(dialog).toHaveCount(0);
  await expect(memory).toBeFocused();
  await expect(memory).toHaveAttribute('aria-expanded', 'false');

  // Shift+Tab out of it closes it, and focus is on the chip.
  await page.keyboard.press('Enter');
  await expect(text).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(dialog).toHaveCount(0);
  await expect(memory).toBeFocused();

  // Esc closes it too (S2 reads the same on a memory chip with a citation chip before it), and a second Enter on the chip opens it again.
  await page.keyboard.press('Enter');
  await expect(dialog).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(memory).toBeFocused();
});

/** S9 (QA): a press of another chip leaves one popover, the other chip's, with focus inside it. */
test('S9: pressing another chip swaps the popover, and only one is open', async ({ page }) => {
  const saved: SeedMemory = { memoryRef: 'zzMemS9', text: 'Lee is the Results contact.', savedAt: '2025-03-01T10:00:00Z' };
  const [ref] = await seed([turn('S9', { citations: [cite('zzDocS9', 'Steps', 'Do the steps.', 1)], memories: [saved] })]);
  await open(page, 'DECISION');
  const citation = chipOf(page, ref!, 'Results runbook, section Steps');
  const memory = chipOf(page, ref!, 'From memory: Lee is the Results contact.');
  const cited = dialogOf(page, 'Results runbook \u00A7 Steps');
  const remembered = dialogOf(page, 'From memory');

  await citation.focus();
  await page.keyboard.press('Enter');
  await expect(cited.getByRole('link', { name: 'Open document', exact: true })).toBeFocused();
  await memory.click();
  await expect(remembered, 'the other chip opens its own popover').toBeVisible();
  await expect(cited, 'and the first one is gone').toHaveCount(0);
  await expect(page.getByRole('dialog'), 'only one popover is open').toHaveCount(1);
  await expect(citation).toHaveAttribute('aria-expanded', 'false');
  await expect(memory).toHaveAttribute('aria-expanded', 'true');
  await expect(remembered.locator('[data-part="memory"]'), 'focus is inside the new popover').toBeFocused();
});

/** The learned line of a fact (the ruled catalog text of memory.learnedSaved), written out here as the independent oracle of the page's own. */
const learnedLine = (fact: string): string => `I'll remember this: "${fact}". You can tell me to forget it.`;
const learnedOf = (page: Page, key: string): Locator => replyOf(page, key).locator('p.learned');

/** S10: the learned lines under a reply: placement, one stop removed, the 200-character cut, and markup as characters. */
test('S10: a learned save is announced under the reply, after the check rows and before the source chips, as plain text', async ({ page }) => {
  const long = `${'x'.repeat(299)}.`;
  const markup = '<b>Lee</b> & <script>window.__x=1</script>';
  const [first, second] = await seed([
    turn('S10a', {
      replyText: 'Noted.',
      checkKey: 'checks.allPassed',
      checks: [{ result: 'passed', entry: 'Orders production', finding: '', checkedAt: '2025-03-01T10:00:00Z' }],
      memories: [{ memoryRef: 'zzMemS10', text: 'Lee is the Results contact.', savedAt: '2025-03-01T10:00:00Z' } satisfies SeedMemory],
      learned: [
        { memoryRef: 'zzLearnedA', text: 'Lee is the contact.' },
        { memoryRef: 'zzLearnedB', text: long },
      ],
    }),
    turn('S10b', { replyText: 'Noted again.', learned: [{ memoryRef: 'zzLearnedC', text: markup }] }),
  ]);
  await open(page, 'DECISION');
  const lines = learnedOf(page, first!);
  await expect(lines, 'one line for each entry').toHaveCount(2);
  await expect(lines.nth(0), 'one trailing full stop is removed').toHaveText(learnedLine('Lee is the contact'));
  await expect(lines.nth(1), '300 characters are cut to 199 and an ellipsis').toHaveText(learnedLine(`${'x'.repeat(199)}\u2026`));
  await expect(replyOf(page, first!).locator('p.sentence'), 'the check sentence is above the lines').toHaveCount(1);
  const top = async (locator: Locator): Promise<number> => (await locator.boundingBox())?.y ?? Number.NaN;
  const sentence = await top(replyOf(page, first!).locator('p.sentence'));
  const firstLine = await top(lines.nth(0));
  const secondLine = await top(lines.nth(1));
  const chips = await top(sourcesOf(page, first!));
  expect(sentence, 'the check rows come before the lines').toBeLessThan(firstLine);
  expect(firstLine, 'the lines are in order').toBeLessThan(secondLine);
  expect(secondLine, 'and the source chips come after them').toBeLessThan(chips);
  await expect(lines.nth(0), 'the lines carry no label of their own').not.toHaveAttribute('aria-label', /.+/);

  const marked = learnedOf(page, second!);
  await expect(marked, 'markup in the fact is shown as characters').toHaveText(learnedLine(markup));
  await expect(replyOf(page, second!).locator('b, script'), 'and makes no element').toHaveCount(0);
});

/** S11: a reply that already says it gets no line, though its turn kept the entry. */
test('S11: a reply that already says "I\'ll remember" shows no learned line', async ({ page }) => {
  const [said, willSaid, silent] = await seed([
    turn('S11a', { replyText: "I'll remember that Lee is the contact.", learned: [{ memoryRef: 'zzLearnedD', text: 'Lee is the contact.' }] }),
    turn('S11b', { replyText: 'I  WILL\u00A0remember Lee.', learned: [{ memoryRef: 'zzLearnedE', text: 'Lee is the contact.' }] }),
    turn('S11c', { replyText: 'Noted.', learned: [{ memoryRef: 'zzLearnedF', text: 'Lee is the contact.' }] }),
  ]);
  await open(page, 'DECISION');
  await expect(learnedOf(page, silent!), 'a silent reply is announced').toHaveCount(1);
  await expect(replyOf(page, said!), 'the reply that says it is shown').toContainText("I'll remember that Lee is the contact.");
  await expect(learnedOf(page, said!), 'no line under it').toHaveCount(0);
  await expect(learnedOf(page, willSaid!), 'nor under "I will remember" in any case and white space').toHaveCount(0);
});

/** S7: a memory saved and recalled through the real composer and the CI mock shows its chip. */
test.describe('S7: the From memory chip on a real turn', () => {
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

  /** Removes the chat user's turns, the memories the case saved and the AI sessions the case's turns saved, so that nothing of the case stays. */
  async function wipe(): Promise<void> {
    const { user } = fixtureUser('CHAT');
    const drop = /^\d+$/.test(mark) ? [`Write !,"CHK|dropped|",$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(${mark}))`] : [];
    const lines = await irisScript(
      [
        `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
        'Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(s.Ref)',
        'Write !,"CHK|memories|",$System.Status.IsOK(##class(OcuTalon.Memory).DropSession(s.Ref))',
        ...drop,
      ].join('\n'),
    );
    expect(chk(lines, 'memories'), `the memories of the case are dropped (${lines.join(' ')})`).toBe('1');
    if (drop.length > 0) expect(chk(lines, 'dropped'), `the AI sessions of the turns are dropped (${lines.join(' ')})`).toBe('1');
  }

  /** Types the text into the composer, presses the main Send button and returns the clientId of the POST /messages. */
  async function send(page: Page, text: string): Promise<string> {
    const request = page.waitForRequest((candidate) => candidate.method() === 'POST' && new URL(candidate.url()).pathname === MESSAGES);
    await composerOf(page).fill(text);
    await page.getByRole('main').getByRole('button', { name: 'Send', exact: true }).click();
    return ((await request).postDataJSON() as { clientId: string }).clientId;
  }

  test('S7: remembering Lee and asking about the Results contact ends the answer with a From memory chip', async ({ page }) => {
    test.setTimeout(180_000);
    await wipe();
    await open(page, 'CHAT');
    const saveId = await send(page, "Remember that the Results partner's contact is Lee. [[mock:memory-save]]");
    await expect(replyOf(page, saveId), "the save scenario's reply shows").toContainText('The CI mock will remember that.', { timeout: REPLY_MS });
    await expect(sourcesOf(page, saveId), 'a save recalls nothing, so it has no chip').toHaveCount(0);
    await expect(learnedOf(page, saveId), 'a told save is not announced').toHaveCount(0);

    const askId = await send(page, 'Who do I call about Results? [[mock:memory-recall-keyword]]');
    await expect(replyOf(page, askId), "the recall scenario's reply shows").toContainText('The CI mock found the memory.', { timeout: REPLY_MS });
    const chip = sourcesOf(page, askId).getByRole('button', { name: /^From memory: .*Lee/ });
    await expect(chip, 'the answer ends with a From memory chip that names the memory').toHaveCount(1, { timeout: REPLY_MS });
    await expect(chip.locator('span')).toHaveText('From memory');
    await chip.click();
    const dialog = dialogOf(page, 'From memory');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('[data-part="memory"]'), 'the popover shows what was remembered').toContainText("the Results partner's contact is Lee");
    await expect(dialog.getByText(/^Saved /), 'and when').toBeVisible();
    await page.keyboard.press('Escape');
    await expect(chip).toBeFocused();

    // After a reload the chat item comes from /v1/state and shows the same chip.
    await page.reload();
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    await expect(sourcesOf(page, askId).getByRole('button', { name: /^From memory: .*Lee/ }), 'a reload shows it again').toHaveCount(1);
  });

  test('S12: a learned fact sent through the composer is announced by code, live and after a reload', async ({ page }) => {
    test.setTimeout(180_000);
    await wipe();
    await open(page, 'CHAT');
    const id = await send(page, "The Results partner's contact is Lee. [[mock:memory-learned-line]]");
    await expect(replyOf(page, id), "the scenario's silent reply shows").toContainText('Noted.', { timeout: REPLY_MS });
    await expect(learnedOf(page, id), 'the line follows the reply').toHaveText(learnedLine("the Results partner's contact is Lee"), { timeout: REPLY_MS });
    await expect(learnedOf(page, id)).toHaveCount(1);

    // After a reload the chat item comes from /v1/state and shows the same line.
    await page.reload();
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    await expect(learnedOf(page, id), 'a reload shows it again').toHaveText(learnedLine("the Results partner's contact is Lee"));
  });
});
