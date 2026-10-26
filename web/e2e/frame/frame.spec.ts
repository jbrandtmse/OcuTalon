import { expect, test, type Locator, type Page, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme, watchViolations } from '../sign-in/helpers';
import { changeSnapshot } from '../support/api';

/**
 * Story 2.1, the main page frame (F1 to F9), against a real stack signed in as the README account. Where a variant of
 * the snapshot is needed, the page's /state answer is fetched from the real server and one field is changed.
 */
const STATE = '/ocutalon/api/v1/state';
const README = 'https://github.com/jbrandtmse/OcuTalon#readme';
const RAIL_LABELS = ['Approval requests', 'Background checks', 'Reminders', 'Recent decisions'];
/** The rail's headings for an account with nothing: the spoken name, and the visible text with its count. */
const RAIL_SPOKEN = RAIL_LABELS.map((label) => `${label}, 0`);
const RAIL_VISIBLE = RAIL_LABELS.map((label) => `${label} (0)`);

type Snapshot = Record<string, unknown>;

/** The README account's snapshot, as the server answers it. */
async function realSnapshot(page: Page): Promise<Snapshot> {
  const response = await page.request.get(STATE);
  expect(response.status()).toBe(200);
  return (await response.json()) as Snapshot;
}

const themeButton = (page: Page, name = 'Theme: System'): Locator => page.getByRole('button', { name, exact: true });
const accountButton = (page: Page): Locator => page.getByRole('button', { name: README_ACCOUNT.user, exact: true });
const traceButton = (page: Page): Locator => page.getByRole('button', { name: 'Visual Trace', exact: true });

/** The heading that the About dialog names itself with, for a snapshot's version. */
const aboutTitle = (version: unknown): string => (typeof version === 'string' && version !== '' ? `OcuTalon ${version}` : 'OcuTalon');

/** Opens the About dialog from the account menu and returns it. */
async function openAbout(page: Page, title: string): Promise<Locator> {
  await accountButton(page).click();
  await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
  const dialog = page.getByRole('dialog', { name: title, exact: true });
  await expect(dialog).toBeVisible();
  return dialog;
}

/** A box no bigger than a pixel: the visually hidden headings. */
async function expectVisuallyHidden(locator: Locator, what: string): Promise<void> {
  const box = (await locator.boundingBox())!;
  expect(box.width, `${what} is visually hidden`).toBeLessThanOrEqual(1);
  expect(box.height, `${what} is visually hidden`).toBeLessThanOrEqual(1);
}

/** The computed colour of a token, as the page paints it. */
function tokenColor(page: Page, token: string): Promise<string> {
  return page.evaluate((name) => {
    const probe = document.createElement('span');
    probe.style.color = `var(${name})`;
    document.body.append(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  }, token);
}

/** F1: the landmarks, the headings and the order of the page. */
test('F1: landmarks, headings and order', async ({ page }) => {
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page).toHaveTitle('OcuTalon');

  const h1 = page.getByRole('heading', { level: 1 });
  await expect(h1, 'the page has exactly one h1').toHaveCount(1);
  await expect(h1).toHaveText('OcuTalon');
  await expectVisuallyHidden(h1, 'the h1');
  await expect(page.getByRole('heading', { level: 2 })).toHaveText(['Status', 'Chat']);
  const rail = page.getByRole('heading', { level: 3 });
  await expect(rail, 'the rail has four headings').toHaveCount(RAIL_LABELS.length);
  for (const [i, name] of RAIL_SPOKEN.entries()) {
    await expect(rail.nth(i), `heading ${i + 1} is named "${name}"`).toHaveAccessibleName(name);
  }
  await expect(page.locator('section.rail h3 > [aria-hidden="true"]'), 'each shows its count').toHaveText(RAIL_VISIBLE);

  await expect(page.getByRole('banner')).toHaveCount(1);
  await expect(page.locator('app-header').getByRole('banner'), 'the banner is the app header').toHaveCount(1);
  const status = page.getByRole('region', { name: 'Status', exact: true });
  await expect(status, 'the rail is the region Status').toHaveCount(1);
  await expect(status).toHaveClass(/rail/);
  await expect(page.getByRole('main')).toHaveCount(1);
  await expect(page.getByRole('navigation'), 'the page has no nav landmark').toHaveCount(0);

  const inOrder = await page.evaluate(() => {
    const nodes = ['app-header', '.banner-slot', 'section.rail', 'main'].map((selector) => document.querySelector(selector));
    return nodes.map((node, i) => (i === 0 ? node !== null : !!node && !!nodes[i - 1] && !!(nodes[i - 1]!.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING)));
  });
  expect(inOrder, 'DOM order: banner, banner slot, Status region, main').toEqual([true, true, true, true]);
  await expect(page.locator('[tabindex]:not([tabindex="-1"]):not([tabindex="0"])'), 'tab order is DOM order').toHaveCount(0);
});

/** F2: with demo mode off there is no badge, no demo region, and main ends at the viewport's right edge. */
test('F2: demo mode off', async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['demoMode'] = false;
    snapshot['onlineDemo'] = false;
    snapshot['nextReset'] = '2099-01-01T00:00:00Z';
  });
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

  await expect(page.locator('.context-badge')).toHaveCount(0);
  await expect(page.locator('.reset-countdown, app-resetting-view'), 'no reset countdown and no resetting view off the online demo, whatever the snapshot says').toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Demo guide' })).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Simulated devices' })).toHaveCount(0);

  const rail = (await page.locator('section.rail').boundingBox())!;
  const main = (await page.getByRole('main').boundingBox())!;
  const viewport = await page.evaluate(() => document.documentElement.clientWidth);
  expect(main.x, "main starts at the rail's right edge").toBeCloseTo(rail.x + rail.width, 0);
  expect(main.x + main.width, "main ends at the viewport's right edge").toBeCloseTo(viewport, 0);
});

/** F3: the header, left to right, on the real stack (demo mode on): the Visual Trace button sits between the badge and the theme button. */
test('F3: the header', async ({ page }) => {
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

  const home = page.locator('app-header a[href="#/"]');
  const mark = home.locator('img.mark');
  const wordmark = home.locator('.wordmark');
  await expect(mark).toHaveCount(1);
  await expect(wordmark).toHaveText('OcuTalon');
  expect(await mark.boundingBox()).toMatchObject({ width: 28, height: 28 });

  const badge = page.locator('app-header .context-badge');
  await expect(badge).toHaveText('Demo mode');
  const boxes = {
    mark: (await mark.boundingBox())!,
    wordmark: (await wordmark.boundingBox())!,
    badge: (await badge.boundingBox())!,
    trace: (await traceButton(page).boundingBox())!,
    theme: (await themeButton(page).boundingBox())!,
    account: (await accountButton(page).boundingBox())!,
  };
  expect(boxes.mark.x + boxes.mark.width, 'the mark, then the wordmark').toBeLessThanOrEqual(boxes.wordmark.x + 2);
  expect(boxes.wordmark.x + boxes.wordmark.width, 'then the badge').toBeLessThanOrEqual(boxes.badge.x);
  expect(boxes.badge.x + boxes.badge.width, 'then the Visual Trace, theme and account buttons at the right').toBeLessThanOrEqual(boxes.trace.x);
  expect(boxes.trace.x + boxes.trace.width, 'the Visual Trace button comes before the theme button').toBeLessThanOrEqual(boxes.theme.x);
  expect(boxes.theme.x + boxes.theme.width).toBeLessThanOrEqual(boxes.account.x);
  const viewport = await page.evaluate(() => document.documentElement.clientWidth);
  expect(boxes.account.x + boxes.account.width, 'the account button ends at the right of the header').toBeGreaterThan(viewport - 40);

  expect(await badge.evaluate((el) => (el as HTMLElement).tabIndex), 'the badge takes no focus').toBe(-1);
  await home.focus();
  await page.keyboard.press('Tab');
  await expect(traceButton(page), 'Tab goes from the home link to the Visual Trace button, past the badge').toBeFocused();
  await page.keyboard.press('Tab');
  await expect(themeButton(page), 'and then to the theme button').toBeFocused();
});

/** F3: the online demo's badge, whatever the demo mode says. */
for (const demoMode of [true, false]) {
  test(`F3: the badge reads Online demo when the snapshot says so, with demoMode ${demoMode}`, async ({ page }) => {
    await changeSnapshot(page, (snapshot) => {
      snapshot['onlineDemo'] = true;
      snapshot['demoMode'] = demoMode;
    });
    await signInReadme(page);
    await expect(page.locator('app-header .context-badge')).toHaveText('Online demo');
  });
}

/** F4: the theme menu, the stored choice, and a storage that throws. */
test('F4: choosing Dark applies at once and survives a reload', async ({ page }) => {
  await signInReadme(page);
  await themeButton(page).click();
  await page.getByRole('menuitemradio', { name: 'Dark' }).click();

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(themeButton(page, 'Theme: Dark')).toBeVisible();

  await themeButton(page, 'Theme: Dark').click();
  const options = page.getByRole('menuitemradio');
  await expect(options).toHaveCount(3);
  await expect(options).toHaveText(['System', 'Light', 'Dark']);
  await expect(options.nth(0)).toHaveAttribute('aria-checked', 'false');
  await expect(options.nth(1)).toHaveAttribute('aria-checked', 'false');
  await expect(options.nth(2)).toHaveAttribute('aria-checked', 'true');
  await expect(options.nth(2).locator('svg[aria-hidden=true]'), 'the checked option also shows a check').toHaveCount(1);
  await page.keyboard.press('Escape');

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('html'), 'after a reload it is still Dark').toHaveAttribute('data-theme', 'dark');
  await expect(themeButton(page, 'Theme: Dark')).toBeVisible();

  await themeButton(page, 'Theme: Dark').click();
  await page.getByRole('menuitemradio', { name: 'System' }).click();
  await expect(page.locator('html'), 'System removes data-theme').not.toHaveAttribute('data-theme', /.*/);
});

test('F4: a storage that throws reads System, and a choice still applies', async ({ page }) => {
  await page.addInitScript(() => {
    const blocked = (): never => {
      throw new Error('storage is blocked');
    };
    Storage.prototype.getItem = blocked;
    Storage.prototype.setItem = blocked;
  });
  const violations = watchViolations(page);
  // Angular reports an error thrown in a template listener to its ErrorHandler, which logs it to the console and
  // raises no page error, so the console's errors are watched as well.
  const logged: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') logged.push(message.text());
  });
  await signInReadme(page);
  await expect(themeButton(page), 'a storage that throws reads System').toBeVisible();

  await themeButton(page).click();
  await page.getByRole('menuitemradio', { name: 'Light' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await expect(themeButton(page, 'Theme: Light')).toBeVisible();
  expect(violations, 'no page error').toEqual([]);
  expect(logged, 'no error is logged to the console').toEqual([]);
});

/** F5: the account menu. */
test('F5: the account menu holds About OcuTalon and Sign out', async ({ page }) => {
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  await accountButton(page).click();
  await expect(page.getByRole('menuitem')).toHaveText(['About OcuTalon', 'Sign out']);
});

/** F6: the About dialog. */
test('F6: the About dialog', async ({ page }) => {
  await signInReadme(page);
  const snapshot = await realSnapshot(page);
  const title = aboutTitle(snapshot['version']);
  await expect(accountButton(page)).toBeVisible();

  const dialog = await openAbout(page, title);
  await expect(page.getByRole('menuitem'), 'the account menu is closed').toHaveCount(0);
  await expect(page.locator('[role=dialog]'), 'exactly one dialog').toHaveCount(1);
  await expect(page.locator('[role=dialog][aria-modal=true]'), 'and it is modal').toHaveCount(1);

  const lines = (await dialog.locator('h2, p').allTextContents()).map((line) => line.replace(/\s+/g, ' ').trim());
  expect(lines, 'the seven lines, in order').toEqual([
    title,
    'An OpenClaw-style assistant for InterSystems IRIS.',
    'An assistant that runs as an IRIS Interoperability production and decides, for everything that arrives, whether it deserves your attention.',
    'Default model: Claude Haiku 5.5.',
    'README (opens in a new tab)',
    'Built with the BMAD Method and Claude Code.',
    'OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.',
  ]);
  const sameBody = await dialog.evaluate((root) => {
    const parentOf = (text: string): Element | null | undefined =>
      [...root.querySelectorAll('p')].find((p) => p.textContent?.trim() === text)?.parentElement;
    const tagline = parentOf('An OpenClaw-style assistant for InterSystems IRIS.');
    const note = parentOf('OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.');
    return !!tagline && tagline === note;
  });
  expect(sameBody, 'the tagline and the note are inside the same body element').toBe(true);

  const links = dialog.getByRole('link');
  await expect(links, 'its only link is README').toHaveCount(1);
  const readme = dialog.getByRole('link', { name: 'README (opens in a new tab)', exact: true });
  await expect(readme).toHaveAttribute('href', README);
  await expect(readme).toHaveAttribute('target', '_blank');
  await expect(readme).toHaveAttribute('rel', 'noopener noreferrer');

  await expect(dialog.getByRole('heading', { level: 2 }), 'focus starts on the heading').toBeFocused();
  for (const key of ['Tab', 'Tab', 'Tab', 'Tab', 'Shift+Tab', 'Shift+Tab', 'Shift+Tab', 'Shift+Tab']) {
    await page.keyboard.press(key);
    await expect(dialog.locator(':focus'), `${key} keeps focus inside the dialog`).toHaveCount(1);
  }

  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(accountButton(page), 'focus returns to the account trigger').toBeFocused();

  const reopened = await openAbout(page, title);
  await page.locator('.cdk-overlay-backdrop').click({ position: { x: 4, y: 4 } });
  await expect(reopened, 'a press on the backdrop closes it').toHaveCount(0);
});

test('F6: the README link opens a new tab', async ({ page, context }) => {
  await context.route('https://github.com/**', (route) => route.fulfill({ contentType: 'text/html', body: '<title>README</title>' }));
  await signInReadme(page);
  const snapshot = await realSnapshot(page);
  const dialog = await openAbout(page, aboutTitle(snapshot['version']));
  const [popup] = await Promise.all([context.waitForEvent('page'), dialog.getByRole('link', { name: 'README (opens in a new tab)' }).click()]);
  expect(popup.url()).toBe(README);
  await popup.close();
});

/** F6: an empty version names the dialog OcuTalon, and an empty model leaves its line out. */
test('F6: no version and no model', async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['version'] = '';
    snapshot['models'] = { triage: '', diagnosis: '', chat: '' };
  });
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  const dialog = await openAbout(page, 'OcuTalon');
  await expect(dialog.getByRole('heading', { level: 2 })).toHaveText('OcuTalon');
  await expect(dialog.getByText('Default model')).toHaveCount(0);
});

/**
 * F6: About reads the snapshot it is given: the version as it is, and the Triage agent's model name as it is (the
 * server has mapped it; an id it does not know arrives as the id). The three agents differ here, so a line that reads
 * another agent's model shows.
 */
test("F6: About names the snapshot's version and the Triage model, an unknown id as it is", async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['version'] = '9.8.7-qa';
    snapshot['models'] = { triage: 'claude-opus-9-9', diagnosis: 'Diagnosis QA model', chat: 'Chat QA model' };
  });
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  const dialog = await openAbout(page, 'OcuTalon 9.8.7-qa');
  await expect(dialog.getByText('Default model: claude-opus-9-9.', { exact: true })).toBeVisible();
  await expect(dialog.getByText('Default model'), 'one model line').toHaveCount(1);
  await expect(dialog.getByText(/Diagnosis QA model|Chat QA model/), "no other agent's model").toHaveCount(0);
});

test('F6: an empty Triage model leaves the Default model line out, whatever the other agents use', async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['version'] = '9.8.7-qa';
    snapshot['models'] = { triage: '', diagnosis: 'Diagnosis QA model', chat: 'Chat QA model' };
  });
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  const dialog = await openAbout(page, 'OcuTalon 9.8.7-qa');
  await expect(dialog.getByText('Default model')).toHaveCount(0);
  await expect(dialog.getByText(/Diagnosis QA model|Chat QA model/)).toHaveCount(0);
});

/** F6: the Close button sits at the dialog's top right, closes it, and returns focus to the account trigger. */
test('F6: the Close button closes the About dialog and focus returns to the account trigger', async ({ page }) => {
  await signInReadme(page);
  const snapshot = await realSnapshot(page);
  const dialog = await openAbout(page, aboutTitle(snapshot['version']));
  const close = dialog.getByRole('button', { name: 'Close About OcuTalon', exact: true });
  await expect(close).toBeVisible();

  const panel = (await page.locator('app-about-dialog').boundingBox())!;
  const button = (await close.boundingBox())!;
  expect(panel.width, 'the dialog is 480px wide').toBe(480);
  expect(button.x + button.width, "Close is at the dialog's right edge").toBeLessThanOrEqual(panel.x + panel.width);
  expect(panel.x + panel.width - (button.x + button.width), "Close is within 24px of the dialog's right edge").toBeLessThanOrEqual(24);
  expect(button.y - panel.y, "Close is at the dialog's top, within 24px of its edge").toBeGreaterThanOrEqual(0);
  expect(button.y - panel.y).toBeLessThanOrEqual(24);

  await close.click();
  await expect(dialog, 'Close closes the dialog').toHaveCount(0);
  await expect(page.locator('.cdk-overlay-backdrop'), 'and its scrim').toHaveCount(0);
  await expect(accountButton(page), 'focus returns to the account trigger').toBeFocused();
});

/** A snapshot that fails: the page says so in data-snapshot, the header keeps its placeholders, About shows OcuTalon. */
test('a failed snapshot: Account, no badge, and About without a model', async ({ page }) => {
  await page.route(`**${STATE}`, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } }));
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'failed');
  await expect(page.getByRole('button', { name: 'Account', exact: true })).toBeVisible();
  await expect(page.locator('.context-badge')).toHaveCount(0);

  await page.getByRole('button', { name: 'Account', exact: true }).click();
  await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
  const dialog = page.getByRole('dialog', { name: 'OcuTalon', exact: true });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByText('Default model')).toHaveCount(0);
});

/** F7: the ghost buttons are tall enough and round enough, and the keyboard focus ring comes from the base rule. */
test('F7: ghost buttons and the focus ring', async ({ page }) => {
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  const focus = await tokenColor(page, '--focus');
  const surface = await tokenColor(page, '--surface');

  const expectRing = async (button: Locator, what: string): Promise<void> => {
    const box = (await button.boundingBox())!;
    expect(box.height, `${what} is at least 32px tall`).toBeGreaterThanOrEqual(32);
    await expect(button, `${what} has a 6px radius`).toHaveCSS('border-top-left-radius', '6px');
    await expect(button, `${what} has a 2px solid ring`).toHaveCSS('outline-style', 'solid');
    await expect(button).toHaveCSS('outline-width', '2px');
    await expect(button, `${what}'s ring is the focus colour`).toHaveCSS('outline-color', focus);
    await expect(button, `${what}'s ring is 2px off`).toHaveCSS('outline-offset', '2px');
    await expect(button, `${what} has a surface halo`).toHaveCSS('box-shadow', `${surface} 0px 0px 0px 2px`);
  };

  await page.locator('app-header a.home').focus();
  await page.keyboard.press('Tab');
  await expect(traceButton(page)).toBeFocused();
  await expectRing(traceButton(page), 'the Visual Trace button');
  await page.keyboard.press('Tab');
  await expect(themeButton(page)).toBeFocused();
  await expectRing(themeButton(page), 'the theme button');
  await page.keyboard.press('Tab');
  await expect(accountButton(page)).toBeFocused();
  await expectRing(accountButton(page), 'the account button');

  await page.keyboard.press('Enter');
  await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
  const close = page.getByRole('button', { name: 'Close About OcuTalon', exact: true });
  await expect(close).toBeVisible();
  // The dialog moves focus to its heading after it renders; Tab only counts from there.
  await expect(page.getByRole('dialog').getByRole('heading', { level: 2 })).toBeFocused();
  await page.keyboard.press('Tab');
  await page.keyboard.press('Tab');
  await expect(close).toBeFocused();
  await expectRing(close, "the About dialog's Close button");
});

/** F8: the tooltip, for the pointer only. */
test('F8: the tooltip shows after 300 ms for the pointer, never for focus, and Escape hides it', async ({ page }) => {
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  const tooltip = page.locator('app-tooltip');
  const theme = themeButton(page);

  // The page times the gap itself, between the pointer entering the button and the tooltip appearing, so that a slow
  // test runner cannot make a late tooltip look right or an early one look late.
  await theme.evaluate((button) => {
    const seen: { entered?: number; shown?: number } = {};
    (window as unknown as { tooltipTimes: typeof seen }).tooltipTimes = seen;
    button.addEventListener('pointerenter', () => (seen.entered ??= performance.now()));
    new MutationObserver(() => {
      if (document.querySelector('app-tooltip')) seen.shown ??= performance.now();
    }).observe(document.body, { childList: true, subtree: true });
  });
  await theme.hover();
  await expect(tooltip).toHaveText('Theme: System');
  await expect(tooltip).toHaveAttribute('aria-hidden', 'true');
  const { entered, shown } = await page.evaluate(() => (window as unknown as { tooltipTimes: { entered: number; shown: number } }).tooltipTimes);
  expect(shown - entered, 'absent before 300 ms, then shown').toBeGreaterThanOrEqual(295);
  expect(shown - entered, 'shown once the 300 ms have passed, not seconds later').toBeLessThan(1500);

  await page.mouse.move(640, 400);
  await expect(tooltip, 'it hides when the pointer leaves').toHaveCount(0);

  await theme.focus();
  await page.keyboard.press('Shift+Tab');
  await page.keyboard.press('Tab');
  await expect(theme).toBeFocused();
  await page.waitForTimeout(600);
  await expect(tooltip, 'no tooltip on keyboard focus').toHaveCount(0);

  await accountButton(page).focus();
  await theme.hover();
  await expect(tooltip).toHaveCount(1);
  await page.keyboard.press('Escape');
  await expect(tooltip, 'Escape hides it').toHaveCount(0);
  await expect(accountButton(page), 'and focus stays where it was').toBeFocused();
});

/** F8: the tooltip is for a pointer resting on the button; one that leaves within the 300 ms shows nothing. */
test('F8: a pointer that leaves the theme button within 300 ms shows no tooltip', async ({ page }) => {
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  // The page drives the pointer's enter and leave itself, 250 ms apart, so that the runner's speed cannot move the gap.
  const appeared = await themeButton(page).evaluate(async (button) => {
    let seen = false;
    const observer = new MutationObserver(() => {
      if (document.querySelector('app-tooltip')) seen = true;
    });
    observer.observe(document.body, { childList: true, subtree: true });
    button.dispatchEvent(new PointerEvent('pointerenter', { pointerType: 'mouse' }));
    await new Promise((done) => setTimeout(done, 250));
    button.dispatchEvent(new PointerEvent('pointerleave', { pointerType: 'mouse' }));
    await new Promise((done) => setTimeout(done, 600));
    observer.disconnect();
    return seen;
  });
  expect(appeared, 'no tooltip appears after the pointer has left').toBe(false);
});

/** F8: no tooltip covers the theme menu while it is open, when the pointer comes back onto the button. */
test('F8: the tooltip stays away while the theme menu is open', async ({ page }) => {
  await signInReadme(page);
  await expect(accountButton(page)).toBeVisible();
  await themeButton(page).click();
  const dark = page.getByRole('menuitemradio', { name: 'Dark' });
  await dark.hover();
  await themeButton(page).hover();
  await page.waitForTimeout(600);
  await expect(page.locator('app-tooltip'), 'no tooltip over the open menu').toHaveCount(0);
  await expect(dark, 'the menu is still open').toBeVisible();
  await page.keyboard.press('Escape');
});

/** F9: the snapshot is requested once, and every part of the page reads that one load. */
test('F9: /state is requested once and answers the new keys', async ({ page }) => {
  const answered: Response[] = [];
  page.on('response', (response) => {
    if (new URL(response.url()).pathname === STATE) answered.push(response);
  });
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const body = (await answered[0]!.json()) as Snapshot;
  expect(Object.keys(body)).toEqual(['version', 'instanceZone', 'epoch', 'streams', 'chat', 'rail', 'user', 'onlineDemo', 'demoMode', 'models', 'telegram', 'status']);
  expect(body['user']).toBe(README_ACCOUNT.user);
  expect(body['onlineDemo']).toBe(false);
  expect(body['demoMode']).toBe(true);
  expect(body['models']).toEqual({ triage: 'Claude Haiku 5.5', diagnosis: 'Claude Haiku 5.5', chat: 'Claude Haiku 5.5' });

  await expect(accountButton(page), 'the header reads the user from it').toBeVisible();
  await expect(page.locator('.context-badge'), 'and the badge').toHaveText('Demo mode');
  const dialog = await openAbout(page, aboutTitle(body['version']));
  await expect(dialog.getByText('Default model: Claude Haiku 5.5.'), 'and About the model').toBeVisible();
  expect(answered.map((response) => response.status()), '/state was requested exactly once and answered 200').toEqual([200]);
});
