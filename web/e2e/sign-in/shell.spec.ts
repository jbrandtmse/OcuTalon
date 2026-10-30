import { expect, test, type Page } from '@playwright/test';

import { signOutTrace } from '../support/trace';
import { README_ACCOUNT, signInReadme, watchViolations } from './helpers';

/** The value of a custom property on the root element, as the page computes it. */
const token = (page: Page, name: string): Promise<string> =>
  page.evaluate((n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim().toUpperCase(), name);

/** Row 8: the README account reaches the empty shell. */
test('row 8: the README sign-in loads the shell', async ({ page }) => {
  const violations = watchViolations(page);
  await page.goto('/ocutalon/');
  await page.getByLabel('User name').fill(README_ACCOUNT.user);
  await page.getByLabel('Password', { exact: true }).fill(README_ACCOUNT.password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page).toHaveTitle('OcuTalon');

  const mark = page.locator('app-header img.mark');
  await expect.poll(() => mark.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
  expect(await mark.boundingBox()).toMatchObject({ width: 28, height: 28 });

  await expect(page.locator('app-header .wordmark')).toHaveText('OcuTalon');
  await expect(page.locator('app-header .ocu')).toHaveCSS('color', 'rgb(16, 42, 69)');
  await expect(page.locator('app-header .talon')).toHaveCSS('color', 'rgb(222, 80, 52)');

  const home = page.locator('app-header a[href="#/"]');
  await expect.soft(home.locator('img.mark'), 'the mark links to the main page').toHaveCount(1);
  await expect.soft(home.locator('.wordmark'), 'the wordmark links to the main page').toHaveCount(1);

  const account = page.getByRole('button', { name: README_ACCOUNT.user, exact: true });
  await expect.soft(account.locator('svg[aria-hidden=true]'), 'the chevron').toHaveCount(1);
  await account.click();
  await expect(page.getByRole('menuitem', { name: 'Sign out' })).toBeVisible();
  await page.keyboard.press('Escape');

  const main = page.getByRole('main');
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect.soft(main.locator('> *'), 'main holds its hidden heading and the chat panel').toHaveCount(2);
  await expect.soft(main.locator('> app-chat-panel'), 'the chat panel follows the heading').toHaveCount(1);
  await expect.soft(main.locator('app-chat-panel app-empty-chat'), 'a fresh session shows the empty chat panel').toHaveCount(1);
  await expect.soft(main.getByRole('textbox', { name: 'Message OcuTalon' }), 'and the composer').toHaveCount(1);
  await expect.soft(main.getByRole('heading'), 'main has exactly one heading').toHaveCount(1);
  const chat = main.getByRole('heading', { level: 2 });
  await expect(chat).toHaveText('Chat');
  const chatBox = (await chat.boundingBox())!;
  expect(chatBox.width, 'the Chat heading is visually hidden').toBeLessThanOrEqual(1);
  expect(chatBox.height, 'the Chat heading is visually hidden').toBeLessThanOrEqual(1);

  const title = page.getByRole('heading', { level: 1 });
  await expect(title, 'the page has one h1').toHaveCount(1);
  await expect(title).toHaveText('OcuTalon');
  await expect(main.getByRole('heading', { level: 1 }), 'the h1 is outside main').toHaveCount(0);
  const titleBox = (await title.boundingBox())!;
  expect(titleBox.width, 'the h1 is visually hidden').toBeLessThanOrEqual(1);
  expect(titleBox.height, 'the h1 is visually hidden').toBeLessThanOrEqual(1);

  expect(violations).toEqual([]);

  for (const path of ['/ocutalon/', '/ocutalon/index.html']) {
    const index = await page.request.get(path);
    expect(index.status(), path).toBe(200);
    expect(index.headers()['content-security-policy'], path).toBe("script-src 'self'");
    expect(index.headers()['cache-control'], path).toBe('no-cache');
  }
  const font = await page.request.get('/ocutalon/assets/fonts/Inter-Regular.woff2');
  expect(font.status(), 'a built file is served').toBe(200);
  expect(font.headers()['content-security-policy'], 'only index.html carries the page policy').toBeUndefined();
});

/**
 * Row 8: a signed-in request for something that is not a file of the bundle is answered 404: a class or ZEN page
 * name reaches the shell, not the class, and a name that only IRIS's /csp/broker/ holds is not served from there.
 */
test('row 8: a missing file, a directory and a path that leaves the folder answer 404', async ({ page }) => {
  await signInReadme(page);
  for (const path of [
    '/ocutalon/no-such-file.js',
    '/ocutalon/assets/fonts/',
    '/ocutalon/assets/..%2findex.html',
    '/ocutalon/assets/fonts/..%5c..%5cindex.html',
    '/ocutalon/EnsPortal.MessageViewer.zen',
    '/ocutalon/%25CSP.Broker.cls',
    '/ocutalon/zenutils.js',
  ]) {
    const response = await page.request.get(path);
    expect(response.status(), path).toBe(404);
    expect(await response.text(), path).not.toContain('<app-root');
  }
});

/** Row 9: the shell is styled from the generated tokens, in both schemes. */
test('row 9: tokens, fonts and reduced motion', async ({ page }) => {
  await signInReadme(page);

  const light: Record<string, string> = {
    bg: '#F4F7FA',
    'brand-orange': '#DE5034',
    action: '#1A6F6D',
    attention: '#B83A1E',
    'danger-ink': '#B42318',
    scrim: '#102A4573',
    'rounded-xs': '4PX',
    'space-1': '4PX',
    'type-body-font-size': '14PX',
    'simulated-phone-shadow': '0 12PX 32PX #102A452E',
    'field-error-icon': 'CIRCLE-ALERT',
    'wordmark-typography-font-size': '20PX',
  };
  for (const [name, value] of Object.entries(light)) {
    expect(await token(page, `--${name}`), `--${name}`).toBe(value);
  }

  await page.emulateMedia({ colorScheme: 'dark' });
  const dark: Record<string, string> = {
    bg: '#11192B',
    'brand-orange': '#DB482B',
    action: '#45B9B3',
    attention: '#F26B4F',
    'danger-ink': '#F7867B',
    scrim: '#05091299',
    'rounded-xs': '4PX',
    'space-1': '4PX',
    'type-body-font-size': '14PX',
    'simulated-phone-shadow': '0 12PX 32PX #00000080',
    'field-error-icon': 'CIRCLE-ALERT',
    'wordmark-typography-font-size': '20PX',
  };
  for (const [name, value] of Object.entries(dark)) {
    expect(await token(page, `--${name}`), `--${name} in dark`).toBe(value);
  }
  await expect(page.locator('app-header .talon')).toHaveCSS('color', 'rgb(219, 72, 43)');
  await expect(page.locator('body')).toHaveCSS('background-color', 'rgb(17, 25, 43)');
  await page.emulateMedia({ colorScheme: 'light' });

  const fonts = await page.evaluate(async () => {
    const wanted = ['800 20px Montserrat', '400 14px Inter', '400 13px "JetBrains Mono"'];
    await Promise.all(wanted.map((font) => document.fonts.load(font)));
    return {
      checks: wanted.map((font) => document.fonts.check(font)),
      loaded: [...document.fonts].filter((face) => face.status === 'loaded').map((face) => `${face.family} ${face.weight}`),
    };
  });
  expect(fonts.checks).toEqual([true, true, true]);
  expect(fonts.loaded).toEqual(expect.arrayContaining(['Montserrat 800', 'Inter 400', 'JetBrains Mono 400']));

  const reducedMotion = await page.evaluate(() =>
    [...document.styleSheets].some((sheet) =>
      [...sheet.cssRules].some((rule) => rule instanceof CSSMediaRule && rule.conditionText.includes('prefers-reduced-motion')),
    ),
  );
  expect(reducedMotion, 'the reduced-motion rule is present').toBe(true);
});

/** Row 10: one sign-in group. */
test('row 10: the API and the trace application share the session', async ({ page }) => {
  await signInReadme(page);
  const api = await page.request.get('/ocutalon/api/v1/zz');
  expect(api.status(), 'the API session is the shell session: 404, not 401').toBe(404);

  await page.goto('/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen');
  await expect(page.locator('input[name=IRISPassword]')).toHaveCount(0);
  await expect(page).toHaveTitle(/Message Viewer/);

  const productions = await page.request.get('/ocutalon/trace/ocutalon/EnsPortal.Productions.zen');
  expect(productions.status(), 'a portal page outside the seven classes').toBe(404);

  // The API is in the sign-in group: the group's login opens it even without the shell's own session cookie.
  await page.context().clearCookies({ name: /CSPSESSIONID/, path: '/ocutalon/' });
  const grouped = await page.request.get('/ocutalon/api/v1/zz');
  expect(grouped.status(), 'the API signs in from the group').toBe(404);

  // DW-146: the trace page held a licence connection for this user until its session ends.
  await signOutTrace(page.request);
});

/** Row 11: Sign out ends the whole group. */
test('row 11: Sign out ends the shell, the API and the trace application', async ({ page }) => {
  await signInReadme(page);
  expect((await page.request.get('/ocutalon/api/v1/zz')).status()).toBe(404);
  const open = await page.request.get('/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen');
  expect(await open.text(), 'a trace session is open before Sign out').toContain('Message Viewer');

  await page.getByRole('button', { name: README_ACCOUNT.user, exact: true }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await expect(page).toHaveTitle('Sign in \u00b7 OcuTalon');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sign in to OcuTalon');

  expect((await page.request.get('/ocutalon/api/v1/zz')).status(), 'the API session ended').toBe(401);
  const trace = await page.request.get('/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen');
  const body = await trace.text();
  expect(body, 'the trace application asks for a sign-in').toContain('name="IRISPassword"');
  expect(body).not.toContain('Message Viewer');
});
