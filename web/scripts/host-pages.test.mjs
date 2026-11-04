// Tests the two pages that the demo host serves (docker/busy.html and docker/maintenance.html, Story 16.5, matrix row 16): printable
// ASCII and lang="en"; the tab titles; the busy page's heading and paragraph equal the catalog's banner.demoBusy split at its first
// ". "; the link's label and the maintenance page's two texts occur word for word in EXPERIENCE.md; the README address is links.ts'
// README_URL; no script, no style attribute and exactly one link element (the data: icon); every href, src, srcset and refresh address
// is the README, the splash's address or one of the four logo names; and no address, localhost or host and port anywhere.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const { PAGE_TEXTS } = await import(pathToFileURL(join(root, 'web', 'src', 'app', 'msg', 'catalog.ts')).href);
const { RESET_TEXTS } = await import(pathToFileURL(join(root, 'web', 'src', 'app', 'live', 'reset-schedule.ts')).href);
const { README_URL } = await import(pathToFileURL(join(root, 'web', 'src', 'app', 'links.ts')).href);
const experience = readFileSync(join(root, '_bmad-output', 'planning-artifacts', 'ux-designs', 'ux-OcuTalon-2026-10-16', 'EXPERIENCE.md'), 'utf8');

const pages = {
  busy: readFileSync(join(root, 'docker', 'busy.html'), 'utf8'),
  maintenance: readFileSync(join(root, 'docker', 'maintenance.html'), 'utf8'),
};
const LOGOS = ['OcuTalon-Logo-light-640.png', 'OcuTalon-Logo-light-1280.png', 'OcuTalon-Logo-dark-640.png', 'OcuTalon-Logo-dark-1280.png'];

/** The text of the first element with this tag, with its tags removed and its white space joined. */
const textOf = (page, tag) => {
  const match = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`).exec(page);
  assert.ok(match, `a ${tag} element`);
  return match[1].replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
};

/** Every address the markup names (not the comment, and not the data: icon): href, src, srcset (each candidate) and the refresh's url. */
const addresses = (page) => {
  const markup = page.replace(/<!--[\s\S]*?-->/g, '').replace('<link rel="icon" href="data:,">', '');
  const found = [];
  for (const match of markup.matchAll(/\s(?:href|src)="([^"]*)"/g)) found.push(match[1]);
  for (const match of markup.matchAll(/\ssrcset="([^"]*)"/g)) for (const candidate of match[1].split(',')) found.push(candidate.trim().split(/\s+/)[0]);
  for (const match of markup.matchAll(/http-equiv="refresh"\s+content="[^"]*?url=([^"]*)"/g)) found.push(match[1]);
  return found;
};

describe('both pages', () => {
  for (const [name, page] of Object.entries(pages)) {
    it(`${name}: are printable ASCII with lang="en" and one style block`, () => {
      assert.ok(/^[\x09\x0a\x20-\x7e]*$/.test(page), 'printable ASCII only');
      assert.ok(page.includes('<html lang="en">'));
      assert.equal(page.split('<style>').length - 1, 1, 'one style block');
    });

    it(`${name}: hold no script, no style attribute and exactly one link element, the data: icon`, () => {
      assert.ok(!/<script/i.test(page), 'no script');
      assert.ok(!/\sstyle=/i.test(page), 'no style attribute');
      assert.deepEqual(page.match(/<link\b[^>]*>/g), ['<link rel="icon" href="data:,">']);
    });

    it(`${name}: name no address, localhost or host and port`, () => {
      assert.ok(!/\b\d{1,3}(?:\.\d{1,3}){3}\b/.test(page), 'no IPv4 address');
      assert.ok(!/\b(?:[0-9a-f]{1,4}:){3,}[0-9a-f]{1,4}\b|\b[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*::(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?(?![\w-])/i.test(page), 'no IPv6 address');
      assert.ok(!/localhost/i.test(page), 'no localhost');
      assert.ok(!/[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*:\d{2,5}\b/.test(page), 'no host and port');
    });
  }
});

describe('the busy page', () => {
  const page = pages.busy;

  it('is titled "Try OcuTalon" and says the catalog\'s busy text, split at its first ". "', () => {
    assert.equal(textOf(page, 'title'), 'Try OcuTalon');
    const text = PAGE_TEXTS['banner.demoBusy'];
    const cut = text.indexOf('. ') + 1;
    assert.equal(textOf(page, 'h1'), text.slice(0, cut));
    assert.equal(textOf(page.replace(/<h1[\s\S]*?<\/h1>/, ''), 'p'), text.slice(cut).trim());
    assert.equal(`${textOf(page, 'h1')} ${textOf(page.replace(/<h1[\s\S]*?<\/h1>/, ''), 'p')}`, text, 'whitespace-normalised, the text is unchanged');
  });

  it('links the README as the splash writes it, with the UX\'s label', () => {
    assert.ok(experience.includes('Install it yourself (README)'), 'EXPERIENCE.md holds the label');
    assert.ok(page.includes(`<a class="link" href="${README_URL}" target="_blank" rel="noopener noreferrer">Install it yourself (README)<span class="sr-only"> (opens in a new tab)</span><svg`));
    assert.equal(page.split('<a ').length - 1, 1, 'one link');
  });

  it('names no address but the README', () => {
    assert.deepEqual(addresses(page), [README_URL]);
    assert.ok(!/<img|srcset|<picture/.test(page), 'no image');
  });

  it('is the splash canvas, in both themes, with a 400px card', () => {
    assert.ok(/body \{[^}]*background: #FFFFFF;/.test(page));
    assert.ok(/html, body \{ background: #11192B; \}/.test(page));
    assert.ok(/\.card \{[^}]*width: 400px;/.test(page));
  });
});

describe('the maintenance page', () => {
  const page = pages.maintenance;

  it('is titled "Resetting \u00b7 OcuTalon" and holds the UX\'s two texts word for word', () => {
    assert.ok(page.includes('<title>Resetting &middot; OcuTalon</title>'));
    assert.ok(experience.includes('Resetting \u00b7 OcuTalon'), 'EXPERIENCE.md holds the title');
    for (const text of [textOf(page, 'h1'), textOf(page.replace(/<h1[\s\S]*?<\/h1>/, ''), 'p')]) {
      assert.ok(experience.includes(text), `EXPERIENCE.md holds "${text}"`);
    }
    assert.equal(textOf(page, 'h1'), 'The demo is resetting.');
    assert.equal(textOf(page.replace(/<h1[\s\S]*?<\/h1>/, ''), 'p'), 'It usually takes a few minutes. This page returns to the sign-in screen by itself.');
  });

  it('reloads itself at the splash\'s address every 10 seconds', () => {
    assert.ok(page.includes('<meta http-equiv="refresh" content="10; url=/ocutalon/">'));
  });

  it('shows the 320px logo, light and dark, 1x and 2x, from the four files beside it', () => {
    assert.ok(page.includes('<picture><source media="(prefers-color-scheme: dark)" srcset="OcuTalon-Logo-dark-640.png 1x, OcuTalon-Logo-dark-1280.png 2x">'));
    assert.ok(page.includes('<img class="logo" src="OcuTalon-Logo-light-640.png" srcset="OcuTalon-Logo-light-640.png 1x, OcuTalon-Logo-light-1280.png 2x" alt="OcuTalon" width="320" height="179">'));
    assert.ok(/\.logo \{[^}]*width: 320px;/.test(page));
  });

  it('names no address but the splash\'s and the four logo files, and no README link', () => {
    assert.deepEqual([...new Set(addresses(page))].sort(), ['/ocutalon/', ...LOGOS].sort());
    assert.ok(!page.includes(README_URL), 'the maintenance page has no README link');
  });
});

describe('the resetting view (Story 16.8)', () => {
  const page = pages.maintenance;
  const view = readFileSync(join(root, 'web', 'src', 'app', 'live', 'resetting-view.ts'), 'utf8');
  const withoutHeading = page.replace(/<h1[\s\S]*?<\/h1>/, '');

  it('has the maintenance page\'s heading, text and tab title', () => {
    assert.equal(RESET_TEXTS.heading, textOf(page, 'h1'));
    assert.equal(RESET_TEXTS.body, textOf(withoutHeading, 'p'));
    assert.equal(RESET_TEXTS.title, textOf(page, 'title').replace('&middot;', '\u00b7'));
  });

  it('shows the same four logo files at 320px, from the app\'s brand folder, and a 400px card', () => {
    const files = [...view.matchAll(/assets\/brand\/(OcuTalon-Logo-[a-z]+-\d+\.png)/g)].map((match) => match[1]);
    assert.deepEqual([...new Set(files)].sort(), [...LOGOS].sort());
    assert.equal((view.match(/width="320"/g) ?? []).length, 2, 'light and dark, each at width 320');
    assert.equal((view.match(/alt="OcuTalon"/g) ?? []).length, 2);
    assert.ok(/\.logo \{[^}]*width: 320px;/.test(view), 'the logo is 320px wide');
    assert.ok(/\.card \{[^}]*width: 400px;/.test(view), 'the card is 400px wide');
  });

  it('takes its colours from the tokens only: no colour literal in its styles', () => {
    const styles = /styles: `([^`]*)`/.exec(view)?.[1] ?? '';
    assert.ok(styles.length > 100, 'the view has styles');
    assert.ok(!/#[0-9A-Fa-f]{3,8}\b|\brgba?\(/.test(styles), 'no colour literal');
    assert.ok(styles.includes('var(--splash-canvas-background)'), 'the splash canvas');
  });
});

describe('the README address', () => {
  it('is links.ts\' README_URL, the repository\'s README', () => {
    assert.equal(README_URL, 'https://github.com/jbrandtmse/OcuTalon#readme');
  });
});
