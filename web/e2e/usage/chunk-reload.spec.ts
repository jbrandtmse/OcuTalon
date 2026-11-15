import { expect, test, type Page, type Route } from '../support/fixtures';

import { signIn, signInReadme } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { fixtureUser } from '../support/iris';

/**
 * Story 36.7, the reload after an upgrade took a lazy page's chunk away, in a real browser against a real stack, signed in as the LIVE fixture user.
 * The first lazy chunk that the page asks for after sign-in (the "victim") answers 404, and the Usage link in the header is pressed:
 *   R1: the chunk is missing for that one request only: the page loads once more in full at #/usage (exactly one more document load) and Usage renders;
 *   R2: the chunk is missing for good: the page loads once more in full and no more (the flag of the address stops a second reload), and Usage does not render;
 *   R3: sessionStorage throws: the page does not reload (today's behaviour), however often the chunk fails;
 *   R4 (QA): the same reload for the other lazy pages: History (as the LIVE user) and Settings (as the README admin) each load once more in full and render;
 *   R5 (QA): a lazy chunk that is fetched but cannot run (a script error, not a failed fetch) is not a chunk failure: no reload and no flag.
 * Document loads are counted from the request side (a navigation request of the main frame), so a hash change is never counted.
 */
const CHUNK = /\/chunk-[A-Za-z0-9]+\.js(\?.*)?$/;
const FLAG_PREFIX = 'ocutalon.chunkReload:';

const live = (): { user: string; password: string } => fixtureUser('LIVE');

interface Watch {
  /** Main-frame document requests since the page was signed in. */
  documents(): number;
  /** The answers given to the victim chunk: 404 for each refusal (also when a script that does not parse is the answer), 200 for each pass. */
  victimAnswers(): number[];
}

/** Who signs in and which header link is pressed: the LIVE fixture user (Usage, History) or the README admin (Settings, which only an admin has). */
type As = 'LIVE' | 'README';

/**
 * Signs in, then watches the document loads and makes the first lazy chunk of the next page the victim: it answers 404 for its first `refusals` requests, or,
 * with `broken`, answers 200 with a script that does not parse (so the fetch works and the import fails with a script error instead of a failed fetch).
 */
async function signedInWithVictim(page: Page, refusals: number, as: As = 'LIVE', link = 'Usage', broken = false): Promise<Watch> {
  const requested = new Set<string>();
  page.on('request', (request) => {
    if (CHUNK.test(request.url())) {
      requested.add(request.url());
    }
  });
  await loadedAfter(page, () => (as === 'README' ? signInReadme(page) : signIn(page, live().user, live().password)));
  await expect(page.getByRole('navigation', { name: 'Pages', exact: true }).getByRole('link', { name: link, exact: true })).toBeVisible();
  const initial = new Set(requested);
  let documents = 0;
  page.on('request', (request) => {
    if (request.isNavigationRequest() && request.frame() === page.mainFrame()) {
      documents += 1;
    }
  });
  let victim: string | null = null;
  const answers: number[] = [];
  await page.route(CHUNK, async (route: Route) => {
    const url = route.request().url();
    if (initial.has(url)) {
      await route.continue();
      return;
    }
    victim ??= url;
    if (url === victim && answers.filter((code) => code === 404).length < refusals) {
      answers.push(404);
      if (broken) {
        await route.fulfill({ status: 200, contentType: 'text/javascript', body: 'export default {' });
      } else {
        await route.fulfill({ status: 404, contentType: 'text/plain', body: 'gone' });
      }
      return;
    }
    if (url === victim) {
      answers.push(200);
    }
    await route.continue();
  });
  return { documents: () => documents, victimAnswers: () => answers };
}

const pageLink = (page: Page, name: string) => page.getByRole('navigation', { name: 'Pages', exact: true }).getByRole('link', { name, exact: true });
const usageLink = (page: Page) => pageLink(page, 'Usage');
const flags = (page: Page): Promise<string[]> => page.evaluate((prefix) => Object.keys(sessionStorage).filter((key) => key.startsWith(prefix)), FLAG_PREFIX);

// mutation: the router's navigation error handler removed from app.config.ts (withNavigationErrorHandler) -> R1 and R2 (the one reload) red.
test('R1: a lazy chunk that answers 404 once makes the page load once more in full, and the page then renders', async ({ page }) => {
  const watch = await signedInWithVictim(page, 1);
  await usageLink(page).click();
  await expect.poll(() => watch.documents(), { message: 'one more document load' }).toBe(1);
  await expect(page, 'at the address #/usage').toHaveURL(/#\/usage$/);
  await expect(page.getByRole('heading', { level: 1 }), 'the Usage page renders').toHaveText('Usage');
  expect(watch.victimAnswers(), 'the chunk was refused once, then served').toEqual([404, 200]);
  expect(watch.documents(), 'and the page loaded in full exactly once').toBe(1);
  expect(await flags(page), 'one flag, for the address').toHaveLength(1);
});

test('R2: a lazy chunk that stays missing gets one reload and no second', async ({ page }) => {
  const watch = await signedInWithVictim(page, Number.POSITIVE_INFINITY);
  await usageLink(page).click();
  await expect.poll(() => watch.victimAnswers().length, { message: 'the chunk is asked for again after the reload' }).toBe(2);
  await page.waitForLoadState('networkidle');
  expect(watch.victimAnswers(), 'refused before and after the reload').toEqual([404, 404]);
  expect(watch.documents(), 'exactly one reload, and no second').toBe(1);
  await expect(page, 'at the address #/usage').toHaveURL(/#\/usage$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Usage' }), 'the Usage page does not render').toHaveCount(0);
  expect(await flags(page), 'the flag of the address stays').toHaveLength(1);
});

test('R3: with sessionStorage unusable the page does not reload', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'sessionStorage', {
      get() {
        throw new DOMException('denied', 'SecurityError');
      },
    });
  });
  const watch = await signedInWithVictim(page, Number.POSITIVE_INFINITY);
  await usageLink(page).click();
  await expect.poll(() => watch.victimAnswers().length, { message: 'the chunk is asked for and refused' }).toBe(1);
  await page.waitForLoadState('networkidle');
  expect(watch.documents(), 'no reload').toBe(0);
  await expect(page.getByRole('heading', { level: 1, name: 'Usage' }), 'the Usage page does not render').toHaveCount(0);
});

// mutation: the router's navigation error handler removed from app.config.ts -> R4 (both pages) red.
for (const { as, link, hash, title } of [
  { as: 'LIVE', link: 'History', hash: /#\/history$/, title: 'History \u00B7 OcuTalon' },
  { as: 'README', link: 'Settings', hash: /#\/settings(\/.*)?$/, title: 'Settings \u00B7 OcuTalon' },
] as const) {
  test(`R4: a missing ${link} chunk gets one reload at its own address, and the page then renders`, async ({ page }) => {
    const watch = await signedInWithVictim(page, 1, as, link);
    await pageLink(page, link).click();
    await expect.poll(() => watch.documents(), { message: 'one more document load' }).toBe(1);
    await expect(page, `at the address of ${link}`).toHaveURL(hash);
    await expect(page, `${link} renders`).toHaveTitle(title);
    expect(watch.victimAnswers(), 'the chunk was refused once, then served').toEqual([404, 200]);
    expect(watch.documents(), 'and the page loaded in full exactly once').toBe(1);
    expect(await flags(page), 'one flag, for the address').toHaveLength(1);
  });
}

// mutation: isChunkLoadError (chunk-reload.ts) answers true for every error -> R5 red (one reload, and a flag).
test('R5: a lazy chunk that fetches but fails to run is no chunk failure: no reload and no flag', async ({ page }) => {
  const watch = await signedInWithVictim(page, Number.POSITIVE_INFINITY, 'LIVE', 'Usage', true);
  await usageLink(page).click();
  await expect.poll(() => watch.victimAnswers().length, { message: 'the chunk is asked for and fails to run' }).toBe(1);
  await page.waitForLoadState('networkidle');
  expect(watch.documents(), 'no reload').toBe(0);
  expect(watch.victimAnswers(), 'and the chunk is not asked for again').toEqual([404]);
  await expect(page.getByRole('heading', { level: 1, name: 'Usage' }), 'the Usage page does not render').toHaveCount(0);
  expect(await flags(page), 'no flag was taken').toEqual([]);
});
