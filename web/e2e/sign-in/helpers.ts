import { createHash } from 'node:crypto';

import { expect, type APIRequestContext, type APIResponse, type Page, type Response } from '@playwright/test';

/** The README account of a local install. */
export const README_ACCOUNT = { user: 'ocutalon', password: 'ocutalon' } as const;

/** The five files that anyone may fetch before sign-in, relative to /ocutalon/. */
export const SIGN_IN_IMAGES = [
  'assets/brand/OcuTalon-Logo-light-640.png',
  'assets/brand/OcuTalon-Logo-light-1280.png',
  'assets/brand/OcuTalon-Logo-dark-640.png',
  'assets/brand/OcuTalon-Logo-dark-1280.png',
  'assets/brand/favicon-32.png',
] as const;

/** The fixture user without roles that the test script creates; its password is random and never printed. */
export function noRoleAccount(): { user: string; password: string } {
  const user = process.env['OCUTALON_NOROLE_USER'];
  const password = process.env['OCUTALON_NOROLE_PASSWORD'];
  if (!user || !password) {
    throw new Error('OCUTALON_NOROLE_USER and OCUTALON_NOROLE_PASSWORD must name the fixture user without roles');
  }
  return { user, password };
}

/**
 * Collects what the browser reports as a Content-Security-Policy violation or a page error. The list grows as the
 * page loads; read it after the page has settled.
 */
export function watchViolations(page: Page): string[] {
  const seen: string[] = [];
  page.on('console', (message) => {
    if (/content security policy|refused to (load|execute|apply|connect|frame)/i.test(message.text())) {
      seen.push(message.text());
    }
  });
  page.on('pageerror', (error) => seen.push(`page error: ${error.message}`));
  return seen;
}

/** Opens the sign-in page at path (or follows the page that the server answers with) and fills the form in. */
export async function fillSignIn(page: Page, user: string, password: string, path = '/ocutalon/'): Promise<void> {
  await page.goto(path);
  await page.getByLabel('User name').fill(user);
  await page.getByLabel('Password', { exact: true }).fill(password);
}

/** Presses Sign in and returns the server's answer to the form. */
export async function submitSignIn(page: Page): Promise<Response> {
  const answered = page.waitForResponse((response) => response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  return answered;
}

/**
 * Signs in at path. It returns the server's answer to the form; the caller then asserts what the next page
 * shows, with an assertion that waits for it.
 */
export async function signIn(page: Page, user: string, password: string, path = '/ocutalon/'): Promise<Response> {
  await fillSignIn(page, user, password, path);
  return submitSignIn(page);
}

/** Signs a user in over HTTP, the way a script does: the sign-in page of the path, then the three fields of its form. */
export async function signInOverHttp(request: APIRequestContext, user: string, password: string, path = '/ocutalon/'): Promise<APIResponse> {
  await request.get(path);
  return request.post(path, { form: { IRISUsername: user, IRISPassword: password, IRISLogin: 'Sign in' } });
}

/** The origin of the stack under test: OCUTALON_URL, which the config also uses as baseURL. */
export function stackOrigin(): string {
  const url = process.env['OCUTALON_URL'];
  if (!url) throw new Error('OCUTALON_URL must name the stack');
  return new URL(url).origin;
}

/**
 * The headers of the browser envelope of a state-changing call (AD-13): the JSON content type, X-OcuTalon-Request: 1 and the
 * stack's own Origin, which an APIRequestContext does not send by itself. An override replaces one part, or with undefined
 * leaves it out.
 */
export function envelope(overrides: Record<string, string | undefined> = {}): Record<string, string> {
  const headers: Record<string, string | undefined> = {
    'content-type': 'application/json',
    'x-ocutalon-request': '1',
    origin: stackOrigin(),
    ...overrides,
  };
  return Object.fromEntries(Object.entries(headers).filter((entry): entry is [string, string] => entry[1] !== undefined));
}

/** Signs the README account in and waits for the shell, with its stylesheets and images loaded. */
export async function signInReadme(page: Page): Promise<void> {
  await signIn(page, README_ACCOUNT.user, README_ACCOUNT.password);
  await expect(page).toHaveTitle('OcuTalon');
  await page.waitForLoadState('load');
}

const sha256 = (text: string): string => createHash('sha256').update(text, 'utf8').digest('base64');

/**
 * Asserts that a response is the sign-in page: 200 HTML with no shell markup, an inline style and an inline script,
 * AD-13's Content-Security-Policy over the hashes of exactly those two blocks, and Cache-Control: no-store.
 * Returns the body.
 */
export async function expectSignInPage(response: Pick<APIResponse, 'status' | 'headers' | 'text'>, label: string): Promise<string> {
  expect(response.status(), label).toBe(200);
  expect(response.headers()['content-type'], label).toContain('text/html');
  const body = await response.text();
  expect(body, label).toContain('<title>Sign in &middot; OcuTalon</title>');
  expect(body, label).not.toContain('<app-root');
  expect(body, label).not.toContain('<script src');
  const style = /<style>([\s\S]*?)<\/style>/.exec(body)?.[1] ?? '';
  const script = /<script>([\s\S]*?)<\/script>/.exec(body)?.[1] ?? '';
  expect(style.length, `${label} has an inline style`).toBeGreaterThan(500);
  expect(script.length, `${label} has an inline script`).toBeGreaterThan(50);
  expect(response.headers()['content-security-policy'], label).toBe(
    `default-src 'none'; script-src 'sha256-${sha256(script)}'; style-src 'sha256-${sha256(style)}'; ` +
      "img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
  );
  expect(response.headers()['cache-control'], label).toBe('no-store');
  return body;
}
