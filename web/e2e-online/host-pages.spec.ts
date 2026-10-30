import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { expect, test, type Browser, type BrowserContext, type Page } from '@playwright/test';

/**
 * Story 16.5, the two pages that the demo host serves (H1 and H2; matrix rows 14 and 15). The files are read from the repository with node
 * fs, relative to this spec, and served by `page.route` on http://demo.test/ at the addresses the proxy would serve them for; every other
 * request is aborted and recorded, so IRIS is unreachable and the case sees exactly what the page asks for. No request reaches the stack.
 * - H1: docker/busy.html, served for a path under /ocutalon/ that no file answers, in the light and the dark scheme: its lang, title,
 *   heading and paragraph, the README link (address, new tab, accessible name), a 400px card, the splash canvas colours and a visible focus
 *   ring on the link, and no request but the page itself.
 * - H2: docker/maintenance.html, served for /ocutalon/ with the four logo files of logo/web/ for their bare names beside it: its title, lang
 *   and texts, a 400px card and the logo drawn 320px wide from the light file in the light scheme and the dark file in the dark one, and
 *   only that one; no request but those. Then /ocutalon/ answers a stand-in page, and the maintenance page's own refresh lands on it.
 * The texts are written out here, as the independent oracle of the pages' own.
 */
test.describe.configure({ timeout: 120_000 });

const ORIGIN = 'http://demo.test';
const README = 'https://github.com/jbrandtmse/OcuTalon#readme';
const repo = (...parts: string[]): string => join(__dirname, '..', '..', ...parts);
const busyHtml = readFileSync(repo('docker', 'busy.html'), 'utf8');
const maintenanceHtml = readFileSync(repo('docker', 'maintenance.html'), 'utf8');
const logo = (name: string): Buffer => readFileSync(repo('logo', 'web', name));

/** The requests a context made, by address, with the aborted ones apart; data: addresses are not requests of a server. */
interface Recorded {
  served: string[];
  aborted: string[];
}

/** Routes every request of the context to `serve` (a body for the address, or undefined to abort it), recording what was asked. */
async function route(context: BrowserContext, serve: (url: URL) => { contentType: string; body: string | Buffer } | undefined): Promise<Recorded> {
  const recorded: Recorded = { served: [], aborted: [] };
  await context.route('**/*', async (handler) => {
    const url = new URL(handler.request().url());
    if (url.protocol === 'data:') {
      await handler.continue();
      return;
    }
    const answer = serve(url);
    if (answer === undefined) {
      recorded.aborted.push(handler.request().url());
      await handler.abort();
      return;
    }
    recorded.served.push(handler.request().url());
    await handler.fulfill({ status: 200, contentType: answer.contentType, body: answer.body });
  });
  return recorded;
}

async function inScheme(browser: Browser, colorScheme: 'light' | 'dark'): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext({ colorScheme, baseURL: ORIGIN });
  return { context, page: await context.newPage() };
}

const background = (page: Page): Promise<string> => page.evaluate(() => getComputedStyle(document.body).backgroundColor);

for (const scheme of ['light', 'dark'] as const) {
  test(`H1 (${scheme}): the busy page shows the busy text and the README link on the splash canvas and loads nothing else`, async ({ browser }) => {
    const { context, page } = await inScheme(browser, scheme);
    const address = `${ORIGIN}/ocutalon/trace/ocutalon/any.csp?probe=1`;
    try {
      const recorded = await route(context, (url) => (url.href === address ? { contentType: 'text/html; charset=utf-8', body: busyHtml } : undefined));
      await page.goto(address);
      await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      await expect(page).toHaveTitle('Try OcuTalon');
      await expect(page.getByRole('heading', { level: 1 })).toHaveText('The demo is busy right now.');
      await expect(page.locator('main p').first()).toHaveText('Try again in a few minutes, or install it yourself.');
      const link = page.getByRole('link', { name: 'Install it yourself (README) (opens in a new tab)', exact: true });
      await expect(link).toHaveAttribute('href', README);
      await expect(link).toHaveAttribute('target', '_blank');
      await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
      expect((await page.locator('.card').boundingBox())?.width, 'the card is 400px wide').toBe(400);
      expect(await background(page), 'the canvas is the splash canvas').toBe(scheme === 'light' ? 'rgb(255, 255, 255)' : 'rgb(17, 25, 43)');
      await page.keyboard.press('Tab');
      await expect(link, 'Tab focuses the link').toBeFocused();
      const ring = await link.evaluate((node) => {
        const style = getComputedStyle(node);
        return { style: style.outlineStyle, width: style.outlineWidth };
      });
      expect(ring, 'with a visible outline').toEqual({ style: 'solid', width: '2px' });
      expect(recorded.served, 'the page asked for nothing but itself').toEqual([address]);
      expect(recorded.aborted, 'and nobody was asked').toEqual([]);
    } finally {
      await context.close();
    }
  });
}

for (const scheme of ['light', 'dark'] as const) {
  test(`H2 (${scheme}): the maintenance page shows the logo and both texts with IRIS unreachable, and returns to the splash by itself`, async ({ browser }) => {
    test.slow();
    const { context, page } = await inScheme(browser, scheme);
    const logos = ['OcuTalon-Logo-light-640.png', 'OcuTalon-Logo-light-1280.png', 'OcuTalon-Logo-dark-640.png', 'OcuTalon-Logo-dark-1280.png'];
    let standIn = false;
    try {
      const recorded = await route(context, (url) => {
        if (url.href === `${ORIGIN}/ocutalon/`) {
          return standIn
            ? { contentType: 'text/html; charset=utf-8', body: '<!DOCTYPE html><html lang="en"><head><title>Try OcuTalon</title></head><body><h1>Try OcuTalon in two minutes</h1></body></html>' }
            : { contentType: 'text/html; charset=utf-8', body: maintenanceHtml };
        }
        const name = url.pathname.replace('/ocutalon/', '');
        return url.origin === ORIGIN && url.pathname.startsWith('/ocutalon/') && logos.includes(name) ? { contentType: 'image/png', body: logo(name) } : undefined;
      });
      await page.goto(`${ORIGIN}/ocutalon/`);
      await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      await expect(page).toHaveTitle('Resetting \u00b7 OcuTalon');
      await expect(page.getByRole('heading', { level: 1 })).toHaveText('The demo is resetting.');
      await expect(page.locator('main p')).toHaveText('It usually takes a few minutes. This page returns to the sign-in screen by itself.');
      expect((await page.locator('.card').boundingBox())?.width, 'the card is 400px wide').toBe(400);
      const image = page.getByRole('img', { name: 'OcuTalon', exact: true });
      await expect.poll(() => image.evaluate((node) => (node as HTMLImageElement).naturalWidth), { message: 'the logo loaded' }).toBeGreaterThan(0);
      expect((await image.boundingBox())?.width, 'the logo is drawn 320px wide').toBe(320);
      expect(await image.evaluate((node) => (node as HTMLImageElement).currentSrc), `the ${scheme} file is the one shown`).toBe(`${ORIGIN}/ocutalon/OcuTalon-Logo-${scheme}-640.png`);
      expect(recorded.served.sort(), 'the page and only that logo were asked for').toEqual([`${ORIGIN}/ocutalon/`, `${ORIGIN}/ocutalon/OcuTalon-Logo-${scheme}-640.png`].sort());
      expect(recorded.aborted, 'and nobody else was asked').toEqual([]);

      if (scheme === 'light') {
        standIn = true;
        await expect(page, 'the refresh lands on the splash address, which now answers').toHaveTitle('Try OcuTalon', { timeout: 15_000 });
        expect(page.url()).toBe(`${ORIGIN}/ocutalon/`);
      }
    } finally {
      await context.close();
    }
  });
}
