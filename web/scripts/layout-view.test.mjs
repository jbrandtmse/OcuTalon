// Tests the page's width bands and layout strings (src/app/shared/layout-view.ts; Story 2.15; FR-12, UX-DR35, UX-DR128, UX-DR137,
// UX-DR138): the four query strings, written out here, which the CSS and Layout both read; the fixed strings against the UX's wording,
// with an ASCII check; the note's storage keys; and statusCount, which gives the Status button's pill and spoken part and nothing
// while the count is unknown. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax
// and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { LAYOUT_QUERIES, LAYOUT_TEXTS, NOTE_CLOSED_KEY, NOTE_FLAG, NOTE_SHOWN_KEY, statusCount } = await import(app('shared', 'layout-view.ts'));

describe('the width queries', () => {
  it('are the four range queries of the bands, with no gap at a fractional width', () => {
    assert.deepEqual(
      { ...LAYOUT_QUERIES },
      {
        stacked: '(width < 1024px)',
        framed: '(width >= 1024px)',
        drawer: '(1024px <= width < 1280px)',
        wide: '(width >= 1440px)',
      },
    );
  });

  /** Whether a width matches a query of the range forms used above. */
  const matches = (query, width) => {
    const bounds = /^\((?:(\d+)px <= )?width (?:(<) (\d+)px|>= (\d+)px)\)$/.exec(query);
    assert.ok(bounds, `${query} is a range query`);
    const [, lower, , upper, from] = bounds;
    if (from !== undefined) return width >= Number(from);
    return (lower === undefined || width >= Number(lower)) && width < Number(upper);
  };

  it('put every width, a fractional one included, in exactly one of the stacked and the framed layout', () => {
    for (const width of [0, 639.5, 1023, 1023.4, 1023.99, 1024, 1024.5, 1279.99, 1280, 1439.99, 1440, 2560]) {
      assert.notEqual(matches(LAYOUT_QUERIES.stacked, width), matches(LAYOUT_QUERIES.framed, width), `${width}`);
    }
  });

  it('give the drawer 1024 to 1279.99px, the reference band 1280 to 1439.99px and the wide band 1440px up', () => {
    const band = (width) => (matches(LAYOUT_QUERIES.stacked, width) ? 'stacked' : matches(LAYOUT_QUERIES.drawer, width) ? 'drawer' : matches(LAYOUT_QUERIES.wide, width) ? 'wide' : 'reference');
    assert.deepEqual([1023.99, 1024, 1279.99, 1280, 1439.99, 1440].map(band), ['stacked', 'drawer', 'drawer', 'reference', 'reference', 'wide']);
  });
});

describe('the fixed strings', () => {
  it("are the AC's and the UX's wording, written out here, in ASCII", () => {
    assert.deepEqual(
      { ...LAYOUT_TEXTS },
      {
        status: 'Status',
        approvalsOne: '1 approval request',
        approvalsMany: '{n} approval requests',
        note: 'This page is designed for a wider window. Everything still works.',
        closeNote: 'Close narrow-window note',
      },
    );
    for (const value of Object.values(LAYOUT_TEXTS)) {
      assert.match(value, /^[\x20-\x7e]+$/, `${value} is ASCII`);
    }
  });

  it('keep the note\'s two storage keys and the value they hold', () => {
    assert.equal(NOTE_SHOWN_KEY, 'ocutalon.narrowNote.shown');
    assert.equal(NOTE_CLOSED_KEY, 'ocutalon.narrowNote.closed');
    assert.equal(NOTE_FLAG, '1');
  });
});

describe('statusCount', () => {
  it('gives nothing while the count is unknown, so that the button never shows a zero it does not know', () => {
    assert.equal(statusCount(undefined), undefined);
  });

  it('gives the pill and the spoken part for 0, 1 and more', () => {
    assert.deepEqual(statusCount(0), { pill: '0', spoken: '0 approval requests' });
    assert.deepEqual(statusCount(1), { pill: '1', spoken: '1 approval request' });
    assert.deepEqual(statusCount(2), { pill: '2', spoken: '2 approval requests' });
    assert.deepEqual(statusCount(12), { pill: '12', spoken: '12 approval requests' });
  });
});
