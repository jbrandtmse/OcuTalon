import { expect, test, type Page } from '@playwright/test';

import {
  expectSignInPage,
  noRoleAccount,
  README_ACCOUNT,
  SIGN_IN_IMAGES,
  signIn,
  signInReadme,
  watchViolations,
} from './helpers';

const TITLE = 'Sign in \u00b7 OcuTalon';
const WRONG_CREDENTIALS = "That user name and password didn't work.";
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";

/**
 * The name of the main-*.js file that the stack serves, read from its own index.html after a sign-in in the page's
 * context, so the name is never a local build's. The caller's other requests carry no session.
 */
async function mainBundle(page: Page): Promise<string | undefined> {
  await signInReadme(page);
  const index = await (await page.request.get('/ocutalon/index.html')).text();
  return /src="(main-[A-Za-z0-9]+\.js)"/.exec(index)?.[1];
}

/** Rows 3 and 4: what answers a request that has no session. */
test.describe('without a session', () => {
  test('row 3: every page URL answers the sign-in page with the policy of its own style and script', async ({
    page,
    request,
  }) => {
    const main = await mainBundle(page);
    expect(main, 'the shell loads a main-*.js file').toBeTruthy();
    const served = await page.request.get(`/ocutalon/${main}`);
    expect(served.status(), `signed in, /ocutalon/${main} is served`).toBe(200);
    expect(served.headers()['content-type'], `signed in, /ocutalon/${main} is served`).toContain('javascript');

    for (const path of [
      '/ocutalon/',
      '/ocutalon/index.html',
      `/ocutalon/${main}`,
      '/ocutalon/x/y?a=1',
      '/ocutalon/EnsPortal.MessageViewer.zen',
      '/ocutalon/%25CSP.Broker.cls',
      '/ocutalon/OcuTalon.Web.Public.Login.cls',
    ]) {
      await expectSignInPage(await request.get(path), path);
    }
  });

  test('row 4: only the five images, an API 401 and the trace login form answer', async ({ request }) => {
    for (const image of SIGN_IN_IMAGES) {
      const response = await request.get(`/ocutalon/${image}`);
      expect(response.status(), image).toBe(200);
      expect(response.headers()['content-type'], image).toBe('image/png');
    }

    const icon = await request.get('/ocutalon/assets/brand/icon-192.png');
    expect(icon.status()).toBe(200);
    expect(icon.headers()['content-type']).toContain('text/html');
    expect(await icon.text()).toContain('Sign in to OcuTalon');

    const api = await request.get('/ocutalon/api/v1/zz');
    expect(api.status()).toBe(401);
    expect(api.headers()['www-authenticate'], 'no challenge, so no browser opens its own password prompt').toBeUndefined();
    expect(await api.json()).toEqual({ error: { code: 'signed_out', message: 'You were signed out. Sign in again to continue.' } });

    const trace = await request.get('/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen');
    const body = await trace.text();
    expect(body).toContain('name="IRISUsername"');
    expect(body).toContain('name="IRISPassword"');
    expect(body).not.toContain('Message Viewer');
  });
});

/** Rows 5 to 7: the sign-in page. */
test.describe('the sign-in page', () => {
  for (const scheme of ['light', 'dark'] as const) {
    test(`row 5: the page in the ${scheme} scheme`, async ({ browser }) => {
      const context = await browser.newContext({ colorScheme: scheme });
      const page = await context.newPage();
      const violations = watchViolations(page);
      await page.goto('/ocutalon/');

      await expect(page).toHaveTitle(TITLE);
      await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sign in to OcuTalon');

      const logo = page.locator('img.logo');
      await expect.poll(() => logo.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
      const source = await logo.evaluate((img: HTMLImageElement) => img.currentSrc);
      expect(source).toContain(scheme === 'dark' ? 'OcuTalon-Logo-dark-' : 'OcuTalon-Logo-light-');

      const user = page.getByLabel('User name');
      const password = page.getByLabel('Password', { exact: true });
      const userLabel = (await page.locator('label[for=ocu-user]').boundingBox())!;
      const passwordLabel = (await page.locator('label[for=ocu-pass]').boundingBox())!;
      const userField = (await user.boundingBox())!;
      const passwordField = (await password.boundingBox())!;
      expect(userLabel.y + userLabel.height, 'User name sits above its field').toBeLessThanOrEqual(userField.y);
      expect(passwordLabel.y + passwordLabel.height, 'Password sits above its field').toBeLessThanOrEqual(passwordField.y);

      const button = page.getByRole('button', { name: 'Sign in', exact: true });
      const form = (await page.locator('form[name=Login]').boundingBox())!;
      const buttonBox = (await button.boundingBox())!;
      expect(Math.abs(buttonBox.width - form.width), 'the button is as wide as the form').toBeLessThan(1);
      await expect(page.getByText('Use the IRIS account your install created; the README lists it.')).toBeVisible();

      // The inline stylesheet and script are the ones the policy pins: they are applied and they run.
      await expect(page.getByRole('heading', { level: 1 })).toHaveCSS('font-size', '28px');
      await expect(button).toHaveCSS('background-color', scheme === 'dark' ? 'rgb(69, 185, 179)' : 'rgb(26, 111, 109)');
      await page.getByRole('button', { name: 'Show password' }).click();
      await expect(password).toHaveAttribute('type', 'text');

      expect(violations).toEqual([]);
      await context.close();
    });
  }

  test('row 6: a wrong password keeps the user name, clears the password and focuses the error', async ({ page }) => {
    await signIn(page, README_ACCOUNT.user, 'wrong');
    const error = page.locator('#ocu-error');
    await expect(error).toHaveText(WRONG_CREDENTIALS);
    await expect(error).toBeFocused();
    await expect(error.locator('svg[aria-hidden=true]')).toHaveCount(1);

    const user = page.getByLabel('User name');
    const password = page.getByLabel('Password', { exact: true });
    await expect(user).toHaveValue(README_ACCOUNT.user);
    await expect(password).toHaveValue('');
    for (const field of [user, password]) {
      await expect(field).toHaveAttribute('aria-invalid', 'true');
      await expect(field).toHaveAttribute('aria-describedby', 'ocu-error');
    }
    const button = (await page.getByRole('button', { name: 'Sign in', exact: true }).boundingBox())!;
    const message = (await error.boundingBox())!;
    expect(message.y, 'the error sits under the button').toBeGreaterThanOrEqual(button.y + button.height);
  });

  test('row 7: the toggle shows and hides the password', async ({ page }) => {
    await page.goto('/ocutalon/');
    const toggle = page.getByRole('button', { name: 'Show password' });
    const password = page.locator('#ocu-pass');
    await expect(toggle).toHaveAttribute('aria-pressed', 'false');
    await expect(password).toHaveAttribute('type', 'password');
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-pressed', 'true');
    await expect(password).toHaveAttribute('type', 'text');
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-pressed', 'false');
    await expect(password).toHaveAttribute('type', 'password');
  });
});

/** Row 12: a user without the OcuTalon user role. */
test('row 12: a user without the user role sees the message and holds no session', async ({ page }) => {
  const account = noRoleAccount();
  const violations = watchViolations(page);
  const answer = await signIn(page, account.user, account.password);
  await expectSignInPage(answer, 'the answer to the no-role sign-in');

  const error = page.locator('#ocu-error');
  await expect(error).toHaveText(NO_ROLE);
  await expect(page).toHaveTitle(TITLE);
  await expect(page.locator('[aria-invalid]')).toHaveCount(0);
  await expect(page.locator('app-root')).toHaveCount(0);
  await expect(error).toBeFocused();
  await expect(page.locator('body'), 'no response header is written into the page').not.toContainText('HTTP/1.1');

  const api = await page.request.get('/ocutalon/api/v1/zz');
  expect(api.status(), 'the session ended').toBe(401);
  const shell = await page.request.get('/ocutalon/index.html');
  expect(await shell.text(), 'the shell is never served').not.toContain('<app-root');
  expect(violations).toEqual([]);
});

/**
 * Row 13: signing in at a deep link lands on it. The proof is the server's 303 and the document navigation it
 * leads to, not the address bar: the shell boots Angular with hash routing under <base href="/ocutalon/">, and the
 * router's first navigation rewrites the page's URL to /ocutalon/#/, so a URL read after the boot is not the target.
 */
test('row 13: sign-in at a deep link redirects to that URL, which serves the shell', async ({ page }) => {
  const target = '/ocutalon/index.html?x=1';
  await page.goto(target);
  await page.getByLabel('User name').fill(README_ACCOUNT.user);
  await page.getByLabel('Password', { exact: true }).fill(README_ACCOUNT.password);
  const answered = page.waitForResponse((r) => r.request().method() === 'POST');
  const landed = page.waitForResponse(
    (r) => r.request().method() === 'GET' && r.request().isNavigationRequest() && r.url().endsWith(target),
  );
  // The 303 is asserted first, so a wrong Location names itself; this keeps the unused wait from rejecting unhandled.
  landed.catch(() => undefined);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  const response = await answered;
  expect(response.status()).toBe(303);
  const location = new URL((await response.headerValue('location'))!, page.url());
  expect(location.pathname + location.search).toBe(target);
  const shell = await landed;
  expect(shell.status(), 'the redirect target answers 200').toBe(200);
  expect(await shell.text(), 'the redirect target serves the shell').toContain('<app-root');
  await expect(page).toHaveTitle('OcuTalon');
});
