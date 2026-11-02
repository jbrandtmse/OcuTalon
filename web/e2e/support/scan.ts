import { expect, type Page } from '@playwright/test';

/**
 * The in-house accessibility scan of the floor (Story 2.16; NFR-25, UX-DR8, DW-178), run by the browser floor specs in every engine. It
 * pins that a page shows no unnamed control, no text or control boundary or focus ring below its WCAG ratio, and no link that points at
 * nothing. `scanPage(page, what)` returns its findings as strings, `${what}: ${rule}: ${element}: ${detail}`, and every case expects
 * `[]`. It needs only a loaded page (no stack of its own): it reads the accessibility tree and the computed styles through Playwright,
 * and runs under the page's CSP in Chromium, Firefox and WebKit. It adds no dependency, and it leaves nothing in the page: the marks and the probe it sets are removed before it returns.
 *
 * Three rules, each named in its findings:
 * - `names`: every widget of the accessibility tree has a name, no control is named "Close" alone, no image is read, every svg is hidden
 *   from assistive technology, and every visible element that is a tab stop only through tabindex="0" has a role and a name.
 * - `contrast text`, `contrast boundary`, `contrast ring` and `unmeasured`: WCAG's relative-luminance ratio, from computed styles, with
 *   each colour composited over its ancestors' backgrounds down to the first opaque one, over white. A run, a boundary or a backdrop
 *   that cannot be measured (a background image in its stack, a partial opacity, a colour that is not rgb) is an `unmeasured` finding,
 *   never a skip.
 * - `links`: an `a[href]` whose fragment names no element, whose href is empty, or which runs a script. A hash route (`#/` and `#!`) is
 *   the page's own address and passes.
 */

/** The widget roles whose lines of the accessibility snapshot must carry a name. */
const WIDGET_ROLES = [
  'button',
  'link',
  'textbox',
  'searchbox',
  'combobox',
  'checkbox',
  'radio',
  'switch',
  'slider',
  'spinbutton',
  'tab',
  'menuitem',
  'menuitemcheckbox',
  'menuitemradio',
  'option',
];

/** A line of the snapshot that holds a widget role and no quoted name after it. */
const UNNAMED_WIDGET = new RegExp(`^\\s*- (${WIDGET_ROLES.join('|')})(?!\\w)(?!\\s+")`);

/** The ratio that text, a boundary and a ring need: WCAG 2.x AA. */
const TEXT_RATIO = 4.5;
const LARGE_TEXT_RATIO = 3;
const GRAPHIC_RATIO = 3;

/** The names rule: widgets named, no icon read, svgs hidden, and named custom tab stops. */
export async function scanNames(page: Page, what: string): Promise<string[]> {
  const findings: string[] = [];
  const snapshot = await page.locator('body').ariaSnapshot();
  for (const line of snapshot.split('\n')) {
    if (UNNAMED_WIDGET.test(line)) findings.push(`${what}: names: ${line.trim()}: a widget without a name`);
    if (/^\s*- img\b/.test(line)) findings.push(`${what}: names: ${line.trim()}: an image that is read`);
    if (/"Close"/.test(line)) findings.push(`${what}: names: ${line.trim()}: a control named Close alone`);
  }
  const marked = await page.evaluate(() => {
    const describe = (el: Element): string => {
      const text = (el.getAttribute('aria-label') ?? el.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 30);
      const cls = typeof el.className === 'string' && el.className.trim() !== '' ? `.${el.className.trim().split(/\s+/)[0]}` : '';
      return `${el.tagName.toLowerCase()}${el.id ? `#${el.id}` : ''}${cls}${text ? ` "${text}"` : ''}`;
    };
    const visible = (el: Element): boolean => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
    const open: string[] = [];
    for (const svg of Array.from(document.querySelectorAll('svg'))) {
      if (svg.getAttribute('aria-hidden') !== 'true') open.push(describe(svg.parentElement ?? svg));
    }
    // A native control is named by its own markup; any other tab stop is a custom widget that names itself. An element that is aria-hidden
    // or inert, or inside such a subtree, is not in the accessibility tree: it is what a modal dialog hides behind itself (the page under
    // About) and the CDK's own focus-trap anchors, which hand focus back into the dialog, so it needs no role and no name.
    const native = 'a[href], button, input, select, textarea, summary, audio[controls], video[controls], [contenteditable]';
    const custom: Array<{ index: number; what: string }> = [];
    Array.from(document.querySelectorAll('[tabindex="0"]'))
      .filter((el) => !el.matches(native) && el.closest('[aria-hidden="true"], [inert]') === null && visible(el))
      .forEach((el, index) => {
        el.setAttribute('data-scan-stop', String(index));
        custom.push({ index, what: describe(el) });
      });
    return { open, custom };
  });
  for (const one of marked.open) findings.push(`${what}: names: svg in ${one}: an svg that is not aria-hidden`);
  try {
    for (const stop of marked.custom) {
      const stopLocator = page.locator(`[data-scan-stop="${stop.index}"]`);
      // The role is the one the accessibility tree gives it (explicit, or implied such as a section's region), as its snapshot's first line.
      const role = /^- ([a-z]+)/.exec(await stopLocator.ariaSnapshot())?.[1];
      if (role === undefined || role === 'generic') {
        findings.push(`${what}: names: ${stop.what}: a tab stop without a role`);
        continue;
      }
      try {
        await expect(stopLocator).toHaveAccessibleName(/\S/, { timeout: 2_000 });
      } catch {
        findings.push(`${what}: names: ${stop.what}: a tab stop without an accessible name`);
      }
    }
  } finally {
    await page.evaluate(() => document.querySelectorAll('[data-scan-stop]').forEach((el) => el.removeAttribute('data-scan-stop')));
  }
  return findings;
}

/** Expects the names rule to find nothing (K5). */
export async function expectNamed(page: Page, what: string): Promise<void> {
  expect(await scanNames(page, what), `${what}: every widget has a name, no icon is read and no control is named Close alone`).toEqual([]);
}

/** The links rule: every a[href] points at something. */
export function scanLinks(page: Page, what: string): Promise<string[]> {
  return page.evaluate((prefix) => {
    const findings: string[] = [];
    for (const link of Array.from(document.querySelectorAll('a[href]'))) {
      const href = (link.getAttribute('href') ?? '').trim();
      const text = (link.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 30);
      const name = `a "${text}" href="${href}"`;
      if (href === '') {
        findings.push(`${prefix}: links: ${name}: an empty href`);
      } else if (/^javascript:/i.test(href)) {
        findings.push(`${prefix}: links: ${name}: a link that runs a script`);
      } else if (href.startsWith('#')) {
        // #/ and #! are hash routes: the page's own addresses, which a middle-click opens as the same page.
        if (href.startsWith('#/') || href.startsWith('#!')) continue;
        let id = href.slice(1);
        try {
          id = decodeURIComponent(id);
        } catch {
          // an address that does not decode names its text as it is
        }
        if (id === '' || document.getElementById(id) === null) findings.push(`${prefix}: links: ${name}: a fragment that names no element`);
      }
    }
    return findings;
  }, what);
}

/**
 * The contrast rule: text, boundaries and the focus ring. The function runs in the page, so it holds everything it uses.
 *
 * Exempt, each for its reason:
 * - inactive controls and their text (`aria-disabled="true"` and `:disabled`): WCAG exempts inactive components, and DESIGN's inactive
 *   Break the feed is one;
 * - decorative borders: only the boundaries of a textarea, an input, a secondary button and a chip control are checked, and card
 *   borders in `--border` are decorative by design;
 * - text that is not painted: `visibility: hidden`, opacity 0, clipped by `clip` or `clip-path`, display none, and the visually hidden
 *   class, because nobody sees it;
 * - the boundary of a checkbox or a radio input, whose box the engine draws itself, so that its computed border is not what is painted,
 *   and of a hidden input, which shows nothing.
 */
export function scanContrast(page: Page, what: string): Promise<string[]> {
  return page.evaluate(
    ({ prefix, textRatio, largeRatio, graphicRatio }) => {
      type Rgba = [number, number, number, number];
      type Rgb = [number, number, number];
      const findings = new Set<string>();

      const describe = (el: Element): string => {
        const text = (el.getAttribute('aria-label') ?? el.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 30);
        const cls = typeof el.className === 'string' && el.className.trim() !== '' ? `.${el.className.trim().split(/\s+/)[0]}` : '';
        return `${el.tagName.toLowerCase()}${el.id ? `#${el.id}` : ''}${cls}${text ? ` "${text}"` : ''}`;
      };
      const unmeasured = (el: Element, why: string): void => {
        findings.add(`${prefix}: unmeasured: ${describe(el)}: ${why}`);
      };

      /** The channels of an rgb(), rgba() or color(srgb) value, else null. */
      const parse = (value: string): Rgba | null => {
        const text = value.trim().toLowerCase();
        if (text === 'transparent') return [0, 0, 0, 0];
        const rgb = /^rgba?\((.+)\)$/.exec(text);
        const srgb = /^color\(srgb\s+(.+)\)$/.exec(text);
        const match = rgb ?? srgb;
        if (match === null) return null;
        const parts = (match[1] ?? '').split(/[\s,/]+/).filter((part) => part !== '');
        if (parts.length < 3 || parts.length > 4) return null;
        const scale = srgb === null ? 1 : 255;
        const channel = (part: string): number => (part.endsWith('%') ? (parseFloat(part) / 100) * 255 : parseFloat(part) * scale);
        const out: Rgba = [channel(parts[0]!), channel(parts[1]!), channel(parts[2]!), 1];
        if (parts.length === 4) out[3] = parts[3]!.endsWith('%') ? parseFloat(parts[3]!) / 100 : parseFloat(parts[3]!);
        return out.some((n) => !Number.isFinite(n)) ? null : out;
      };
      const over = (top: Rgba, below: Rgb): Rgb => [
        top[0] * top[3] + below[0] * (1 - top[3]),
        top[1] * top[3] + below[1] * (1 - top[3]),
        top[2] * top[3] + below[2] * (1 - top[3]),
      ];
      const luminance = (c: Rgb): number => {
        const lin = (v: number): number => {
          const s = v / 255;
          return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
        };
        return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
      };
      const ratio = (a: Rgb, b: Rgb): number => {
        const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
        return (hi + 0.05) / (lo + 0.05);
      };

      /** The colour behind an element (its own background too, with `self`): its backgrounds composited down to the first opaque one, over white. */
      const backdrop = (el: Element, self: boolean): Rgb | string => {
        const layers: Rgba[] = [];
        for (let node: Element | null = self ? el : el.parentElement; node !== null; node = node.parentElement) {
          const style = getComputedStyle(node);
          if (style.backgroundImage !== 'none') return `a background image on ${describe(node)}`;
          const opacity = parseFloat(style.opacity);
          if (opacity > 0 && opacity < 1) return `a partial opacity on ${describe(node)}`;
          const colour = parse(style.backgroundColor);
          if (colour === null) return `a background colour it cannot parse on ${describe(node)}: ${style.backgroundColor}`;
          if (colour[3] > 0) layers.push(colour);
          if (colour[3] >= 1) break;
        }
        let base: Rgb = [255, 255, 255];
        for (const layer of layers.reverse()) base = over(layer, base);
        return base;
      };

      const visible = (el: Element): boolean => el.getClientRects().length > 0 && getComputedStyle(el).visibility === 'visible';
      /** Inactive controls and the text inside them are exempt. */
      const inactive = (el: Element): boolean => el.closest('[aria-disabled="true"], :disabled') !== null;
      /** Text that nobody sees: hidden, transparent, clipped to nothing, or in the visually hidden class. */
      const unpainted = (el: Element): boolean => {
        if (getComputedStyle(el).visibility !== 'visible' || el.closest('.visually-hidden') !== null) return true;
        for (let node: Element | null = el; node !== null; node = node.parentElement) {
          const style = getComputedStyle(node);
          if (style.opacity === '0' || style.display === 'none') return true;
          if (style.clip !== 'auto' && style.clip.startsWith('rect(') && /rect\(0(px)?[ ,]+0(px)?[ ,]+0(px)?[ ,]+0(px)?\)/.test(style.clip)) return true;
          if (style.clipPath.startsWith('inset(50%')) return true;
        }
        return false;
      };

      const checkText = (el: Element, colourValue: string, fontSize: string, fontWeight: string, label: string): void => {
        const fg = parse(colourValue);
        const bg = backdrop(el, true);
        if (fg === null) return unmeasured(el, `${label}: a text colour it cannot parse: ${colourValue}`);
        if (typeof bg === 'string') return unmeasured(el, `${label}: ${bg}`);
        const size = parseFloat(fontSize);
        const large = size >= 24 || (size >= 18.66 && parseInt(fontWeight, 10) >= 700);
        const needs = large ? largeRatio : textRatio;
        const got = ratio(over(fg, bg), bg);
        if (got < needs) findings.add(`${prefix}: contrast text: ${describe(el)}: ${label} ${got.toFixed(2)}:1 is under ${needs}:1`);
      };

      // Text: every painted text run.
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const seen = new Set<Element>();
      for (let node = walker.nextNode(); node !== null; node = walker.nextNode()) {
        const el = node.parentElement;
        if (el === null || seen.has(el) || (node.textContent ?? '').trim() === '' || el.closest('script, style, noscript, template') !== null) continue;
        if (inactive(el) || unpainted(el)) continue;
        const range = document.createRange();
        range.selectNodeContents(node);
        if (!Array.from(range.getClientRects()).some((rect) => rect.width > 0 && rect.height > 0)) continue;
        seen.add(el);
        const style = getComputedStyle(el);
        checkText(el, style.color, style.fontSize, style.fontWeight, 'text');
      }

      // Text: the placeholder of a field that shows it.
      for (const field of Array.from(document.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('input[placeholder], textarea[placeholder]'))) {
        if (field.value !== '' || !visible(field) || inactive(field)) continue;
        const placeholder = getComputedStyle(field, '::placeholder');
        const opacity = parseFloat(placeholder.opacity);
        if (opacity > 0 && opacity < 1) {
          unmeasured(field, 'placeholder: a partial opacity');
          continue;
        }
        const own = getComputedStyle(field);
        checkText(field, placeholder.color, own.fontSize, own.fontWeight, 'placeholder');
      }

      // Boundaries: the border when it has width, else the background, against the backdrop.
      const boundaries = Array.from(document.querySelectorAll('textarea, input, .button-secondary, button[class*="chip"]'));
      /** A control that draws no edge of its own (no border and a transparent background) is bounded by the first ancestor that does: the composer's field sits in its bordered box. */
      const edgeOf = (control: Element): Element => {
        let node: Element = control;
        for (;;) {
          const own = getComputedStyle(node);
          const drawsBorder = ['Top', 'Right', 'Bottom', 'Left'].some((edge) => parseFloat(own.getPropertyValue(`border-${edge.toLowerCase()}-width`)) > 0);
          const painted = parse(own.backgroundColor);
          if (drawsBorder || own.backgroundImage !== 'none' || painted === null || painted[3] > 0) return node;
          if (node.parentElement === null || node.parentElement === document.body) return control;
          node = node.parentElement;
        }
      };
      for (const control of boundaries) {
        if (!visible(control) || inactive(control) || (control instanceof HTMLInputElement && ['hidden', 'checkbox', 'radio'].includes(control.type))) continue;
        const edge = edgeOf(control);
        const style = getComputedStyle(edge);
        const behind = backdrop(edge, false);
        if (typeof behind === 'string') {
          unmeasured(control, `boundary: ${behind}`);
          continue;
        }
        const side = (['Top', 'Right', 'Bottom', 'Left'] as const).find((edge) => parseFloat(style.getPropertyValue(`border-${edge.toLowerCase()}-width`)) > 0);
        const value = side === undefined ? style.backgroundColor : style.getPropertyValue(`border-${side.toLowerCase()}-color`);
        const edgeColour = parse(value);
        if (edgeColour === null) {
          unmeasured(control, `boundary: a colour it cannot parse: ${value}`);
          continue;
        }
        if (side === undefined && style.backgroundImage !== 'none') {
          unmeasured(control, 'boundary: a background image');
          continue;
        }
        const got = ratio(over(edgeColour, behind), behind);
        if (got < graphicRatio) findings.add(`${prefix}: contrast boundary: ${describe(control)}: its ${side === undefined ? 'background' : 'border'} ${got.toFixed(2)}:1 is under ${graphicRatio}:1`);
      }

      // The focus ring: --focus against --surface (the halo) and against the backdrop of every visible focusable control.
      const token = (name: string): Rgba | null => {
        const probe = document.createElement('span');
        probe.style.color = `var(${name})`;
        document.body.append(probe);
        const value = getComputedStyle(probe).color;
        probe.remove();
        return parse(value);
      };
      const focus = token('--focus');
      const surface = token('--surface');
      if (focus === null || surface === null) {
        unmeasured(document.body, 'ring: --focus or --surface is not an rgb colour');
      } else {
        const ring = over(focus, [255, 255, 255]);
        const halo = ratio(ring, over(surface, [255, 255, 255]));
        if (halo < graphicRatio) findings.add(`${prefix}: contrast ring: --focus against --surface ${halo.toFixed(2)}:1 is under ${graphicRatio}:1`);
        // Every element that can take focus, a focus target that is no tab stop (tabindex -1: a banner, main, a heading) included.
        const focusables = 'a[href], button:not(:disabled), input:not(:disabled):not([type="hidden"]), select:not(:disabled), textarea:not(:disabled), summary, [tabindex]';
        for (const control of Array.from(document.querySelectorAll(focusables))) {
          if (!visible(control) || unpainted(control)) continue;
          // The halo lies on one side of the ring and the parent's backdrop on the other, whether the ring is drawn outside the
          // control or inside its own edge (the ring-inside class), so the ring is measured against the parent's backdrop.
          const behind = backdrop(control, false);
          if (typeof behind === 'string') {
            unmeasured(control, `ring: ${behind}`);
            continue;
          }
          const got = ratio(ring, behind);
          if (got < graphicRatio) findings.add(`${prefix}: contrast ring: ${describe(control)}: --focus against its backdrop ${got.toFixed(2)}:1 is under ${graphicRatio}:1`);
        }
      }
      return [...findings];
    },
    { prefix: what, textRatio: TEXT_RATIO, largeRatio: LARGE_TEXT_RATIO, graphicRatio: GRAPHIC_RATIO },
  );
}

/** Scans the page: the names, the contrast and the links, in this order. Returns the findings, each naming its rule and its element. */
export async function scanPage(page: Page, what: string): Promise<string[]> {
  return [...(await scanNames(page, what)), ...(await scanContrast(page, what)), ...(await scanLinks(page, what))];
}
