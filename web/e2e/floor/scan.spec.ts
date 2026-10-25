import { expect, test, type Page } from '@playwright/test';

import { STATE } from '../support/api';
import { signIn } from '../sign-in/helpers';
import { addReminder, addResetSoon, clearFullPage, mainOf, openFloor, seedFullPage, settled } from '../support/floor';
import { fixtureUser } from '../support/iris';
import { scanPage } from '../support/scan';

/**
 * Story 2.16, the scan (U1 to U4), in a real browser against a real stack, in Chromium, Firefox and WebKit. It pins that the in-house
 * scan of support/scan.ts finds nothing on the page: no widget without a name, no text, boundary or focus ring under its WCAG ratio, no
 * link that points at nothing (DW-178), on the full page at 1280x720 and 1280x600 and on its overlays, in the light and the dark theme
 * (U1, U2); that it does report a planted fault of each kind, and a backdrop it cannot measure (U3); and that it reports each branch that
 * U3 leaves out (U4, QA): a visible svg, a control named Close alone, a read image, a tab stop with no role or with no name, a placeholder,
 * a focus ring and the ring of a focus target that is no tab stop under their ratio, text between 3:1 and 4.5:1 that is not large, a
 * border between 2:1 and 3:1, and an empty, a bare # and a javascript: link. It needs the stack that docker/tests/test-floor.sh starts: U1 and U2 sign in as the floor user
 * (OCUTALON_FLOOR_USER, the user role) over real HTTP, in a fresh browser context. U1 removes the rows it seeds with clearFullPage and
 * turns Reset soon off in finally; U3 removes its plant in finally; U4 sets each fragment into a blank page and needs neither the stack
 * nor a sign-in. All four run in every engine (tag @browsers); no case lets a chat post reach the server.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A held poll or a held snapshot that a routed handler still holds when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';
const SCHEMES = ['light', 'dark'] as const;
const SERVER_ERROR = '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}';

/** Scans the page in the light and then the dark theme, and expects no finding in either. */
async function expectClean(page: Page, what: string): Promise<void> {
  for (const scheme of SCHEMES) {
    await page.emulateMedia({ colorScheme: scheme });
    await settled(page);
    expect(await scanPage(page, `${what} (${scheme})`), `${what}, ${scheme}: the scan finds nothing`).toEqual([]);
  }
}

/** U1: the full page, with a row of every rail kind, a done turn and two banners, at both window heights and in both themes. */
test('U1: the full page has no unnamed control, no contrast failure and no link to nothing, at 1280x720 and 1280x600', { tag: '@browsers' }, async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const full = await seedFullPage(user, refs);
    await openFloor(page);
    await addReminder(page, user, full.stamp);
    await addResetSoon(page, user);
    for (const height of [720, 600]) {
      await page.setViewportSize({ width: 1280, height });
      await expectClean(page, `the full page at 1280x${height}`);
    }
  } finally {
    await clearFullPage(user, refs);
  }
});

/** U2: the overlays and the failed load, at 1280x720, in both themes. */
test('U2: Visual Trace, the account menu, About and the failed load have no finding, in both themes', { tag: '@browsers' }, async ({ page }) => {
  const { user, password } = fixtureUser(KIND);
  await page.setViewportSize({ width: 1280, height: 720 });

  // The failed load: the first /state answers 500, and Retry's request is held until the page's clock has passed 10 s, which shows its busy notice.
  await page.clock.install();
  const waiting: Array<() => void> = [];
  let answers = 0;
  let released = false;
  await page.route(`**${STATE}`, async (route) => {
    answers += 1;
    if (answers === 1) {
      await route.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
      return;
    }
    if (!released) await new Promise<void>((resolve) => waiting.push(resolve));
    await route.continue().catch(() => undefined);
  });
  try {
    await signIn(page, user, password);
    const main = mainOf(page);
    await expect(main, 'the first load fails').toHaveAttribute('data-snapshot', 'failed');
    const retry = main.getByRole('button', { name: 'Retry', exact: true });
    await retry.click();
    await expect.poll(() => answers, { message: 'Retry asks for the snapshot again' }).toBe(2);
    await page.clock.runFor(10_000);
    await expect(main.locator('app-inline-notice'), "Retry's busy notice shows").toHaveCount(1);
    await expectClean(page, 'the failed load');
  } finally {
    released = true;
    for (const resolve of waiting.splice(0)) resolve();
  }
  await expect(mainOf(page), 'the held answer loads the page').toHaveAttribute('data-snapshot', 'loaded');

  const traceButton = page.getByRole('button', { name: 'Visual Trace', exact: true });
  await traceButton.click();
  await expect(page.locator('.app-popover'), 'the Visual Trace popover is open').toHaveCount(1);
  await expectClean(page, 'with Visual Trace open');
  await page.keyboard.press('Escape');
  await expect(page.locator('.app-popover')).toHaveCount(0);

  await page.locator('app-header button.header-button').last().click();
  const about = page.getByRole('menuitem', { name: 'About OcuTalon' });
  await expect(about, 'the account menu is open').toBeVisible();
  await expectClean(page, 'with the account menu open');
  await about.click();
  await expect(page.getByRole('dialog'), 'About is open').toBeVisible();
  await expectClean(page, 'with About open');
});

/** U3: a planted fault of each kind is reported, and nothing else is: five findings, one for each rule. */
test('U3: a planted unnamed button, low text, dead fragment, faint border and image backdrop are the scan\'s five findings', { tag: '@browsers' }, async ({ page }) => {
  await openFloor(page);
  await page.emulateMedia({ colorScheme: 'light' });
  // What the page gives without the plant is U1's to judge: the plant must add exactly its five findings to it.
  const before = await scanPage(page, 'the plant');
  try {
    await page.evaluate(() => {
      const plant = document.createElement('div');
      plant.id = 'scan-plant';
      Object.assign(plant.style, { background: '#ffffff', color: '#000000', padding: '8px' });
      const add = <K extends keyof HTMLElementTagNameMap>(tag: K, style: Partial<CSSStyleDeclaration>): HTMLElementTagNameMap[K] => {
        const el = document.createElement(tag);
        Object.assign(el.style, { display: 'block', margin: '4px', background: '#ffffff', color: '#000000' }, style);
        plant.append(el);
        return el;
      };
      // An icon-only button with no name: its icon is hidden from assistive technology, so nothing names it.
      const button = add('button', { width: '24px', height: '24px' });
      button.type = 'button';
      const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      icon.setAttribute('aria-hidden', 'true');
      icon.setAttribute('width', '16');
      icon.setAttribute('height', '16');
      button.append(icon);
      // Text at about 2.8:1.
      add('p', { color: '#9a9a9a' }).textContent = 'plant low text';
      // A link to a fragment that no element has.
      const link = add('a', {});
      link.href = '#nowhere';
      link.textContent = 'plant dead link';
      // An input whose border is about 1.4:1.
      const input = add('input', { border: '1px solid #dadada' });
      input.setAttribute('aria-label', 'plant field');
      // Text on a background image: a backdrop that cannot be measured.
      add('div', { backgroundImage: 'linear-gradient(#ffffff, #eeeeee)' }).textContent = 'plant image text';
      document.body.append(plant);
    });
    const findings = (await scanPage(page, 'the plant')).filter((one) => !before.includes(one));
    expect(findings.map((one) => one.split(': ')[1]).sort(), `exactly one finding for each rule: ${findings.join(' | ')}`).toEqual([
      'contrast boundary',
      'contrast text',
      'links',
      'names',
      'unmeasured',
    ]);
    for (const [rule, element] of [
      ['names', 'button'],
      ['contrast text', 'plant low text'],
      ['links', '#nowhere'],
      ['contrast boundary', 'input'],
      ['unmeasured', 'plant image text'],
    ] as const) {
      expect(findings.some((one) => one.includes(`: ${rule}: `) && one.includes(element)), `the ${rule} finding names ${element}: ${findings.join(' | ')}`).toBe(true);
    }
  } finally {
    await page.evaluate(() => document.getElementById('scan-plant')?.remove());
  }
  expect(await page.evaluate(() => document.getElementById('scan-plant')), 'the plant is gone').toBeNull();
});

/** The two tokens that the ring rule reads, with stand-in values for the fragments of U4 (a good pair: 10.0:1 against the surface). */
const TOKENS = ':root{--focus:#0b3d91;--surface:#ffffff}';
const GIF = 'data:image/gif;base64,R0lGODlhAQABAAAAACw=';

/** One finding that a fragment must give: its rule, and a word of its element and of its detail. */
interface Finding {
  readonly rule: string;
  readonly element: string;
  readonly detail: string;
}

/**
 * One fragment of U4: its markup, the style it needs, and the findings it must give, and no other (none for a clean twin). An svg that is
 * not hidden is also read as an image by the accessibility tree, so that fault gives two findings of the names rule.
 */
interface Fragment {
  readonly name: string;
  readonly html: string;
  readonly css?: string;
  readonly finds: readonly Finding[];
}

const FRAGMENTS: readonly Fragment[] = [
  // The clean twin first: a scan that reports on everything would pass the faulty fragments below.
  {
    name: 'a clean twin of every fragment below',
    html: `<button type="button" aria-label="Go"><svg aria-hidden="true" width="10" height="10"></svg></button>
      <button type="button">Dismiss</button>
      <img alt="" src="${GIF}">
      <textarea aria-label="Note" placeholder="Write a note" style="border:1px solid #000000"></textarea>
      <div role="region" aria-label="Chat" tabindex="0" style="width:20px;height:20px"></div>
      <a href="#/">Home</a>
      <p style="font-size:24px;color:#898989">Large text</p>
      <p style="font-size:19px;font-weight:700;color:#898989">Bold large text</p>
      <input aria-label="Name" style="border:1px solid #767676">
      <div class="ring-inside" tabindex="-1" style="width:20px;height:20px;background:#ffffff"></div>`,
    css: 'textarea::placeholder{color:#595959;opacity:1}',
    finds: [],
  },
  {
    // 3.5:1 is enough for large text (the clean twin's) and not for text under 18.66px bold or 24px.
    name: 'text under 4.5:1 that is not large',
    html: '<p style="font-size:14px;color:#898989">Small text</p>',
    finds: [{ rule: 'contrast text', element: 'Small text', detail: 'is under 4.5:1' }],
  },
  {
    name: 'a field whose border is under 3:1',
    html: '<input aria-label="Name" style="border:1px solid #9e9e9e">',
    finds: [{ rule: 'contrast boundary', element: 'input', detail: 'is under 3:1' }],
  },
  {
    name: 'links that point at nothing',
    html: '<a href="">Empty</a> <a href="#">Top</a> <a href="javascript:void 0">Run</a>',
    finds: [
      { rule: 'links', element: 'href=""', detail: 'an empty href' },
      { rule: 'links', element: 'href="#"', detail: 'names no element' },
      { rule: 'links', element: 'href="javascript:void 0"', detail: 'runs a script' },
    ],
  },
  {
    // A focus target that is no tab stop and draws its ring inside its own white edge: the ring's other neighbour is the dark page.
    name: 'a focus target whose ring is under 3:1 against the backdrop around it',
    html: '<div class="ring-inside" tabindex="-1" style="width:20px;height:20px;background:#ffffff"></div>',
    css: 'body{background:#123f9a}',
    finds: [{ rule: 'contrast ring', element: 'div.ring-inside', detail: 'against its backdrop' }],
  },
  {
    name: 'an svg that is not aria-hidden',
    html: '<button type="button" aria-label="Go"><svg width="10" height="10"></svg></button>',
    finds: [
      { rule: 'names', element: 'svg in button', detail: 'not aria-hidden' },
      { rule: 'names', element: 'img', detail: 'image that is read' },
    ],
  },
  {
    name: 'a control named Close alone',
    html: '<button type="button">Close</button>',
    finds: [{ rule: 'names', element: 'Close', detail: 'named Close alone' }],
  },
  {
    name: 'an image that is read',
    html: `<img alt="a logo" src="${GIF}">`,
    finds: [{ rule: 'names', element: 'img', detail: 'image that is read' }],
  },
  {
    name: 'a tab stop with no role',
    html: '<div tabindex="0" style="width:20px;height:20px"></div>',
    finds: [{ rule: 'names', element: 'div', detail: 'without a role' }],
  },
  {
    name: 'a tab stop with a role and no name',
    html: '<div role="region" tabindex="0" style="width:20px;height:20px"></div>',
    finds: [{ rule: 'names', element: 'div', detail: 'without an accessible name' }],
  },
  {
    name: 'a placeholder under 4.5:1',
    html: '<textarea aria-label="Note" placeholder="Write a note" style="border:1px solid #000000"></textarea>',
    css: 'textarea::placeholder{color:#b5b5b5;opacity:1}',
    finds: [{ rule: 'contrast text', element: 'textarea', detail: 'placeholder' }],
  },
  {
    // --focus is as dark as the halo's colour, but the control sits on white, so only the halo fails.
    name: 'a focus ring under 3:1 against the halo',
    html: '<a href="#/">Home</a>',
    css: ':root{--surface:#123f9a}',
    finds: [{ rule: 'contrast ring', element: '--focus against --surface', detail: 'is under 3:1' }],
  },
  {
    // The halo is white and the ring is dark, but the control sits on a backdrop as dark as the ring.
    name: 'a focus ring under 3:1 against its control\'s backdrop',
    html: '<a href="#/" style="color:#ffffff">Home</a>',
    css: 'body{background:#123f9a}',
    finds: [{ rule: 'contrast ring', element: 'a "Home"', detail: 'against its backdrop' }],
  },
];

/**
 * U4: each rule branch that U3's five plants leave out reports its own planted fault, in a page of its own that holds nothing else, and a
 * clean twin of them all reports nothing; the faults between 3:1 and 4.5:1 and between 2:1 and 3:1 pin the ratios themselves. It needs no
 * stack: the fragments are set into a blank page.
 */
test('U4: each remaining scan branch reports its planted fault, and a clean twin reports none', { tag: '@browsers' }, async ({ page }) => {
  for (const fragment of FRAGMENTS) {
    await page.setContent(`<!doctype html><html lang="en"><head><title>scan fragment</title><style>${TOKENS}${fragment.css ?? ''}</style></head><body>${fragment.html}</body></html>`);
    const findings = await scanPage(page, fragment.name);
    const said = `${fragment.name}: ${findings.join(' | ') || 'no finding'}`;
    expect.soft(findings.map((one) => one.split(': ')[1]).sort(), `exactly its findings, by rule: ${said}`).toEqual(fragment.finds.map((one) => one.rule).sort());
    for (const { rule, element, detail } of fragment.finds) {
      expect.soft(
        findings.some((one) => one.includes(`: ${rule}: `) && one.includes(element) && one.includes(detail)),
        `a ${rule} finding names ${element} and ${detail}: ${said}`,
      ).toBe(true);
    }
  }
});
