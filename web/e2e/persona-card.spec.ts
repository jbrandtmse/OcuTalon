import { expect, test, type Locator, type Page } from '@playwright/test';

import { README_ACCOUNT } from './sign-in/helpers';
import { raise, refOf } from './support/approvals';
import { applied, signInReadmeLoaded } from './support/floor';
import { chk, cleanFixtureRows, irisScript, quoted, seedApproval, setApprovalState, sinkEvent } from './support/iris';
import { forget, prepare, sessionRef } from './support/persona';

/**
 * Story 40.4 (PC1 to PC7), the Persona card in the status rail, in a real browser against the stack that test-sign-in.sh seeds, signed in as the
 * README account. Every case clears the account's persona keys and its `setting` requests first and removes them again in `finally`, because
 * other specs expect the defaults. The saved line and the refusals are the server's own texts (OcuTalon.Core.SettingsOps), so these cases hold
 * them as the routes' spec (api/persona.spec.ts) does. The values behind the page are read through irisScript. PC6 alone rewrites one field of
 * the real GET answer, `customOffered`: the real onlineDemo flag would switch the whole page to the online demo.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const SAVED = 'Saved. Applies from your next message. Recorded in the audit log.';
const BAD_LANGUAGE = 'Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters.';
const BAD_CUSTOM = 'Use up to 1,000 characters, without {{ or @{.';
const INTRO =
  'Choose how OcuTalon words its chat replies and the reasons for its decisions. What OcuTalon may do, and what needs your approval, never changes.';
const LANGUAGE_HELP =
  "Name a language, such as Spanish or Portuguese (Brazil). Notices, cards and buttons stay in English. OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. In another language, the model is only told not to say so.";
const CUSTOM_HELP =
  "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. If this persona writes in another language, the model is only told not to say so.";
const PENDING = 'OcuTalon suggested a change. It waits for your answer in Approval requests.';
const DEMO_NOTE = 'On the online demo you can choose a preset or a language. Your choice lasts for this visit.';
const PERSONA = '/ocutalon/api/v1/persona';
const BUSY = "Couldn't reach OcuTalon. Try again. Nothing was changed.";

/** The six presets as the card shows them: name and description, in the UX table's order. */
const PRESETS: Array<[string, string]> = [
  ['Professional (default)', 'Calm, short and plain.'],
  ['Starship computer', 'Crisp status reports, formal and brief.'],
  ['Pirate', 'Sailing words and a good-humoured tone; the facts stay exact.'],
  ['Kind friend', 'Warm, patient and encouraging.'],
  ['Another language', 'Replies and reasons in the language you name.'],
  ['Your own words', 'Describe the tone, style and preferences you want.'],
];

const rail = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
const card = (page: Page): Locator => rail(page).locator('app-persona-card');
const changeOf = (page: Page): Locator => card(page).getByRole('button', { name: 'Change', exact: true });
const saveOf = (page: Page): Locator => card(page).getByRole('button', { name: 'Save', exact: true });
const radioOf = (page: Page, name: string): Locator => card(page).getByRole('radio', { name, exact: true });
const titleOf = (page: Page): Locator => card(page).locator('.current-name');
const languageOf = (page: Page): Locator => card(page).getByRole('textbox', { name: 'Language', exact: true });
const wordsOf = (page: Page): Locator => card(page).getByRole('textbox', { name: 'Your own words', exact: true });

/** The stored value of one persona key of the session, or "none" when there is no row. */
async function stored(ref: string, name: 'preset' | 'language' | 'custom'): Promise<string> {
  const lines = await irisScript(
    [
      `Set k=##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Core.SettingsOps).PersonaKey(${quoted(ref)},${quoted(name)}))`,
      'Write !,"CHK|value|",$Select($IsObject(k):k.Value,1:"none")',
    ].join('\n'),
  );
  return chk(lines, 'value') ?? 'unread';
}

/** The element that an aria-describedby id list of the control ends with the given suffix. */
async function describer(control: Locator, suffix: string): Promise<string> {
  const ids = ((await control.getAttribute('aria-describedby')) ?? '').split(' ');
  const id = ids.find((one) => one.endsWith(suffix));
  expect(id, `${suffix} is among the ids that describe the control (${ids.join(' ')})`).toBeTruthy();
  return id as string;
}

/** Runs a case with the account's persona cleared before and after, and with the page signed in and loaded. */
async function withCard(page: Page, body: (ref: string, rows: string[]) => Promise<void>, before?: (rows: string[]) => Promise<void>): Promise<void> {
  const ref = await sessionRef();
  const rows: string[] = [];
  await forget(ref);
  try {
    await prepare(ref);
    await before?.(rows);
    await signInReadmeLoaded(page);
    await body(ref, rows);
  } finally {
    await forget(ref);
    await prepare(ref);
    await cleanFixtureRows(rows);
  }
}

/** PC1: the defaults. */
test('PC1: the rail ends with the Persona card, Professional (default) with its description, and Change opens the six presets', async ({ page }) => {
  await withCard(page, async () => {
    const headings = rail(page).getByRole('heading', { level: 3 });
    await expect(headings.last(), 'the last section is Persona, with no count').toHaveAccessibleName('Persona');
    await expect(headings.last().locator('[aria-hidden="true"]'), 'and has no count').toHaveCount(0);
    await expect(card(page), 'the card is in the Persona section').toHaveCount(1);
    await expect(titleOf(page)).toHaveText('Professional (default)');
    await expect(card(page)).toContainText('Calm, short and plain.');
    await expect(card(page).getByText(PENDING), 'no proposal waits').toHaveCount(0);
    await expect(changeOf(page)).toHaveAttribute('aria-expanded', 'false');
    await expect(card(page).getByRole('radio'), 'collapsed, the card shows no radio').toHaveCount(0);
    await expect(card(page).locator('[aria-live], [role="status"], [role="alert"]'), 'the card is no live region').toHaveCount(0);

    await changeOf(page).focus();
    await page.keyboard.press('Enter');
    await expect(changeOf(page)).toHaveAttribute('aria-expanded', 'true');
    const panelId = await changeOf(page).getAttribute('aria-controls');
    expect(panelId, 'Change names the panel it controls').toBeTruthy();
    await expect(page.locator(`#${panelId}`).getByText(INTRO), 'the intro opens the disclosure').toBeVisible();
    const group = card(page).getByRole('radiogroup', { name: 'Persona', exact: true });
    await expect(group, 'the radio group is named by the heading').toHaveCount(1);
    await expect(group).toHaveAccessibleDescription(INTRO);
    await expect(card(page).getByRole('radio'), 'six radios').toHaveCount(6);
    for (const [name, description] of PRESETS) {
      await expect(radioOf(page, name), `${name} is described by its description`).toHaveAccessibleDescription(description);
    }
    await expect(radioOf(page, 'Professional (default)'), 'the current preset is checked').toBeChecked();
    await expect(card(page).getByText(DEMO_NOTE), 'no online-demo note on a local install').toHaveCount(0);
    await expect(languageOf(page), 'no field before its option is chosen').toHaveCount(0);
    await expect(wordsOf(page)).toHaveCount(0);
  });
});

/** PC2: the keyboard alone. */
test('PC2: with the keyboard alone, Change, an arrow to Pirate and Save store Pirate, and the saved line and the new title show', async ({ page }) => {
  await withCard(page, async (ref) => {
    await changeOf(page).focus();
    await page.keyboard.press('Enter');
    await expect(radioOf(page, 'Professional (default)'), 'Enter on Change opens the presets').toBeVisible();
    await page.keyboard.press('Tab');
    await expect(radioOf(page, 'Professional (default)'), 'Tab from Change reaches the checked radio').toBeFocused();
    await page.keyboard.press('ArrowDown');
    await expect(radioOf(page, 'Starship computer'), 'an arrow moves to the next preset').toBeFocused();
    await page.keyboard.press('ArrowDown');
    await expect(radioOf(page, 'Pirate'), 'and again').toBeFocused();
    await expect(radioOf(page, 'Pirate')).toBeChecked();
    await page.keyboard.press('Tab');
    await expect(saveOf(page), 'Tab leaves the group for Save').toBeFocused();
    await page.keyboard.press('Enter');
    await expect(card(page).getByText(SAVED, { exact: true }), 'the server\'s saved line shows under Save').toBeVisible();
    await expect(titleOf(page)).toHaveText('Pirate');
    await expect(card(page)).toContainText('Sailing words and a good-humoured tone; the facts stay exact.');
    await expect(changeOf(page), 'the disclosure stays open').toHaveAttribute('aria-expanded', 'true');
    expect(await stored(ref, 'preset'), 'the preset is stored').toBe('pirate');
    expect(await stored(ref, 'language'), 'a value the preset does not use is stored empty or not at all').toMatch(/^(|none)$/);

    await page.reload();
    await expect(titleOf(page), 'after a reload the card reads Pirate again').toHaveText('Pirate');
  });
});

/** PC3: Another language. */
test('PC3: Another language shows the Language field with its help, saves Spanish, and refuses "Spanish!" beside the field', async ({ page }) => {
  await withCard(page, async (ref) => {
    await changeOf(page).click();
    await radioOf(page, 'Another language').check();
    const field = languageOf(page);
    await expect(field, 'the Language input appears below its option').toBeVisible();
    await expect(field).toHaveValue('');
    await expect(field, 'it is described by the UX help and the all-clear sentence').toHaveAccessibleDescription(LANGUAGE_HELP);
    await field.fill('Spanish');
    await saveOf(page).click();
    await expect(card(page).getByText(SAVED, { exact: true })).toBeVisible();
    await expect(titleOf(page)).toHaveText('Another language');
    expect(await stored(ref, 'language')).toBe('Spanish');
    expect(await stored(ref, 'preset')).toBe('language');

    await field.fill('Spanish!');
    await expect(field).toHaveValue('Spanish!');
    await expect(card(page).getByText(SAVED, { exact: true }), 'editing the field takes the saved line away').toHaveCount(0);
    await saveOf(page).click();
    await expect(field, 'the refused field is marked invalid').toHaveAttribute('aria-invalid', 'true');
    const errorId = await describer(field, '-language-error');
    await expect(page.locator(`#${errorId}`), 'the server\'s refusal shows beside the field').toHaveText(BAD_LANGUAGE);
    await expect(field, 'the field keeps the typed text').toHaveValue('Spanish!');
    await expect(titleOf(page), 'the title is unchanged').toHaveText('Another language');
    expect(await stored(ref, 'language'), 'the stored name is still Spanish').toBe('Spanish');

    await field.fill('Spanish');
    await expect(field, 'typing clears the refusal').not.toHaveAttribute('aria-invalid', 'true');
  });
});

/** PC4: Your own words. */
test('PC4: Your own words shows the text area with its help and counter, saves, and refuses "{{" beside the text area', async ({ page }) => {
  await withCard(page, async (ref) => {
    await changeOf(page).click();
    await radioOf(page, 'Your own words').check();
    const area = wordsOf(page);
    await expect(area, 'the text area is labelled "Your own words"').toBeVisible();
    await expect(card(page).getByText(CUSTOM_HELP, { exact: true }), 'its help is the all-clear sentence').toBeVisible();
    await expect(card(page).getByText('0 of 1,000 characters', { exact: true })).toBeVisible();
    await expect(area).toHaveAccessibleDescription(`${CUSTOM_HELP} 0 of 1,000 characters`);
    await area.fill('Ahoy!');
    await expect(card(page).getByText('5 of 1,000 characters', { exact: true }), 'the counter follows the text').toBeVisible();
    await saveOf(page).click();
    await expect(card(page).getByText(SAVED, { exact: true })).toBeVisible();
    await expect(titleOf(page)).toHaveText('Your own words');
    expect(await stored(ref, 'custom')).toBe('Ahoy!');

    await area.fill('Use {{ here');
    await saveOf(page).click();
    await expect(area, 'the refused text area is marked invalid').toHaveAttribute('aria-invalid', 'true');
    const errorId = await describer(area, '-custom-error');
    await expect(page.locator(`#${errorId}`), 'the server\'s refusal shows beside the text area').toHaveText(BAD_CUSTOM);
    await expect(area, 'the text area keeps the text').toHaveValue('Use {{ here');
    expect(await stored(ref, 'custom'), 'the stored text is unchanged').toBe('Ahoy!');
    await expect(area, 'no maxlength cuts a paste').not.toHaveAttribute('maxlength', /.*/);
  });
});

/** PC5: a pending proposal. */
test('PC5: a pending setting request shows the suggestion line, and a press focuses the Approval requests heading', async ({ page }) => {
  await withCard(
    page,
    async () => {
      await expect(card(page).getByRole('button', { name: PENDING, exact: true }), 'the suggestion line is one button').toBeVisible();
      await expect(titleOf(page), 'the title is the stored choice').toHaveText('Professional (default)');
      await card(page).getByRole('button', { name: PENDING, exact: true }).click();
      await expect(page.locator('#rail-heading-approvals'), 'no chat card is drawn, so the heading takes focus').toBeFocused();
    },
    async (rows) => {
      rows.push(await seedApproval(README_ACCOUNT.user, { kind: 'setting' }));
    },
  );
});

/** PC6: the online demo's variant. */
test('PC6: with customOffered false, the card offers five presets and the Language field, and the online-demo note', async ({ page }) => {
  await page.route(`**${PERSONA}`, async (route) => {
    if (route.request().method() !== 'GET') return route.continue();
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    return route.fulfill({ response, json: { ...body, customOffered: false } });
  });
  await withCard(page, async () => {
    await changeOf(page).click();
    await expect(card(page).getByRole('radio'), 'five radios').toHaveCount(5);
    await expect(radioOf(page, 'Your own words'), 'no Your own words').toHaveCount(0);
    await expect(card(page).getByText(DEMO_NOTE, { exact: true }), 'the note follows the intro').toBeVisible();
    await radioOf(page, 'Another language').check();
    await expect(languageOf(page), 'the Language field is still there').toBeVisible();
    await expect(wordsOf(page)).toHaveCount(0);
  });
});

/** PC7: Esc. */
test('PC7: Esc inside the open disclosure collapses it and puts focus on Change', async ({ page }) => {
  await withCard(page, async () => {
    await changeOf(page).click();
    await radioOf(page, 'Pirate').focus();
    await expect(changeOf(page)).toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(changeOf(page), 'the disclosure is collapsed').toHaveAttribute('aria-expanded', 'false');
    await expect(card(page).getByRole('radio')).toHaveCount(0);
    await expect(changeOf(page), 'and Change has focus').toBeFocused();
  });
});

/** PC8: the suggestion line comes with a request raised during the visit and leaves with its answer. */
test('PC8: a setting request raised live shows the suggestion line, and answering it takes the line away', async ({ page }) => {
  await withCard(page, async (_ref, rows) => {
    await expect(titleOf(page)).toHaveText('Professional (default)');
    await expect(card(page).getByRole('button', { name: PENDING, exact: true }), 'no line before a request').toHaveCount(0);
    const request = await seedApproval(README_ACCOUNT.user, { kind: 'setting' });
    rows.push(request);
    await applied(page, await sinkEvent(README_ACCOUNT.user, 'approval.raised', { ref: request }));
    await expect(card(page).getByRole('button', { name: PENDING, exact: true }), 'the line appears with the request').toBeVisible();
    await setApprovalState(request, 'approved');
    await applied(page, await sinkEvent(README_ACCOUNT.user, 'approval.answered', { ref: request }));
    await expect(card(page).getByRole('button', { name: PENDING, exact: true }), 'and leaves with its answer').toHaveCount(0);
  });
});

/** PC9: the suggestion line's press focuses the request's card in the chat when it is drawn. */
test('PC9: with the request\'s card drawn in the chat, a press on the suggestion line focuses that card', async ({ page }) => {
  const request = refOf('pc9');
  let pendingRef = '';
  await page.route(`**${PERSONA}`, async (route) => {
    if (route.request().method() !== 'GET') return route.continue();
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    return route.fulfill({ response, json: { ...body, pendingRef } });
  });
  await withCard(page, async (_ref, rows) => {
    pendingRef = request;
    await raise(page, README_ACCOUNT.user, rows, refOf('pc9i'), [], { ref: request });
    const drawn = page.locator(`app-chat-panel [data-part="approval"][data-key="${request}"]`);
    await expect(drawn, 'the request\'s card is drawn in the chat').toBeVisible();
    await card(page).getByRole('button', { name: PENDING, exact: true }).click();
    await expect(drawn, 'the press focuses that card').toBeFocused();
  });
});

/** PC10: a refusal that is not a field's, a failure with no message, and a field refusal with no message. */
test('PC10: other refusals show the server\'s message under Save and read again; a failure with no message shows the busy sentence', async ({ page }) => {
  const REFUSED = 'zz The server refused this choice.';
  let gets = 0;
  page.on('request', (request) => {
    if (request.method() === 'GET' && new URL(request.url()).pathname === PERSONA) gets += 1;
  });
  let answer: { status: number; json: unknown } = { status: 400, json: { error: { code: 'custom_not_offered', message: REFUSED } } };
  await page.route(`**${PERSONA}`, (route) => (route.request().method() === 'PUT' ? route.fulfill(answer) : route.continue()));
  await withCard(page, async (ref) => {
    await changeOf(page).click();
    await radioOf(page, 'Pirate').check();
    const reads = gets;
    await saveOf(page).click();
    await expect(card(page).locator('.field-error'), 'the server\'s message shows under Save').toHaveText(REFUSED);
    await expect.poll(() => gets, { message: 'the card reads again' }).toBeGreaterThan(reads);
    await expect(titleOf(page), 'the title is what is stored').toHaveText('Professional (default)');
    expect(await stored(ref, 'preset'), 'nothing was stored').toBe('none');

    answer = { status: 500, json: {} };
    await saveOf(page).click();
    await expect(card(page).locator('.field-error'), 'a failure with no message shows the busy sentence under Save').toHaveText(BUSY);
    await expect(titleOf(page)).toHaveText('Professional (default)');

    answer = { status: 400, json: { error: { code: 'bad_language' } } };
    await radioOf(page, 'Another language').check();
    await languageOf(page).fill('Spanish');
    await saveOf(page).click();
    await expect(languageOf(page), 'a field refusal with no message is still marked invalid').toHaveAttribute('aria-invalid', 'true');
    await expect(page.locator(`#${await describer(languageOf(page), '-language-error')}`), 'and shows the busy sentence beside the field').toHaveText(BUSY);
  });
});

/** PC11: a failed read leaves the heading only, and the next change of the pending requests reads again. */
test('PC11: when the read fails the Persona section shows its heading only, and the next pending change reads again', async ({ page }) => {
  let failing = true;
  await page.route(`**${PERSONA}`, (route) =>
    failing && route.request().method() === 'GET' ? route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } }) : route.continue(),
  );
  await withCard(page, async (_ref, rows) => {
    await expect(rail(page).getByRole('heading', { level: 3, name: 'Persona', exact: true }), 'the heading shows').toBeVisible();
    await expect(card(page), 'the card is drawn').toHaveCount(1);
    await expect(changeOf(page), 'with no Change').toHaveCount(0);
    expect(((await card(page).textContent()) ?? '').trim(), 'and no text').toBe('');
    failing = false;
    const request = await seedApproval(README_ACCOUNT.user, { kind: 'setting' });
    rows.push(request);
    await applied(page, await sinkEvent(README_ACCOUNT.user, 'approval.raised', { ref: request }));
    await expect(titleOf(page), 'the next pending change reads again').toHaveText('Professional (default)');
    await expect(changeOf(page)).toBeVisible();
  });
});

/** PC12: a call with no answer in 10 seconds shows the busy notice, and the late answer still shows its line. */
test('PC12: a save with no answer in 10 seconds shows the busy notice, and the late answer still shows its saved line', async ({ page }) => {
  test.setTimeout(75_000);
  await page.route(`**${PERSONA}`, async (route) => {
    if (route.request().method() !== 'PUT') return route.continue();
    await new Promise((resolve) => setTimeout(resolve, 11_000));
    return route.continue();
  });
  await withCard(page, async (ref) => {
    await changeOf(page).click();
    await radioOf(page, 'Pirate').check();
    await saveOf(page).click();
    await expect(card(page).getByText(BUSY, { exact: true }), 'the notice shows at 10 seconds').toBeVisible({ timeout: 10_500 });
    await expect(card(page).getByText(SAVED, { exact: true }), 'the late answer shows its line').toBeVisible({ timeout: 10_000 });
    await expect(card(page).getByText(BUSY, { exact: true }), 'and the notice leaves').toHaveCount(0);
    await expect(titleOf(page)).toHaveText('Pirate');
    expect(await stored(ref, 'preset')).toBe('pirate');
  });
});

/** PC7b: in the drawer band, Esc collapses the disclosure and leaves the drawer open. */
test('PC7b: in the drawer band the first Esc collapses the disclosure only, and the next one closes the drawer', async ({ page }) => {
  await withCard(page, async () => {
    await page.setViewportSize({ width: 1100, height: 720 });
    const status = page.locator('button.status-button');
    await status.click();
    await expect(status, 'the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await changeOf(page).click();
    await radioOf(page, 'Pirate').focus();
    await page.keyboard.press('Escape');
    await expect(changeOf(page), 'the disclosure is collapsed').toHaveAttribute('aria-expanded', 'false');
    await expect(changeOf(page), 'Change has focus').toBeFocused();
    await expect(status, 'and the drawer stays open').toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(status, 'the next Esc closes the drawer').toHaveAttribute('aria-expanded', 'false');
  });
});
