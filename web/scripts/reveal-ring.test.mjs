// Tests revealRing (src/app/shared/reveal-ring.ts, Story 2.16) with stand-in elements, so that both of its directions run in every
// unit job: a target past the scroller's bottom scrolls it down, and one past its top scrolls it up, each by the overflow plus the
// scroller's own scroll-padding (the ring's reach); a target already inside, the scroller itself, a target outside it and a scroller
// that has no overflow change nothing; and only scrollBy is used, with an instant behaviour. The real engines are the floor unit's K4
// and G1 in Firefox. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { beforeEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

class FakeElement {}
globalThis.HTMLElement = FakeElement;
globalThis.getComputedStyle = (element) => ({ scrollPaddingTop: element.padding?.top ?? 'auto', scrollPaddingBottom: element.padding?.bottom ?? 'auto' });

const here = dirname(fileURLToPath(import.meta.url));
const { revealRing } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'shared', 'reveal-ring.ts')).href);

/** A scroller whose client box is the 100 px from y 100 to y 200, with a 4 px gutter, and the calls it receives. */
function scroller(overrides = {}) {
  const element = new FakeElement();
  Object.assign(element, {
    scrollHeight: 400,
    clientHeight: 100,
    clientTop: 0,
    padding: { top: '4px', bottom: '4px' },
    calls: [],
    inside: new Set(),
    getBoundingClientRect: () => ({ top: 100, bottom: 200 }),
    // As Node.contains does, a scroller contains itself, so that only revealRing's own check keeps it from scrolling for itself.
    contains(target) {
      return target === this || this.inside.has(target);
    },
    scrollBy(options) {
      this.calls.push(options);
    },
    ...overrides,
  });
  return element;
}

/** A control of the scroller at the given top and bottom (page y). */
function control(parent, top, bottom) {
  const element = new FakeElement();
  element.getBoundingClientRect = () => ({ top, bottom });
  parent.inside.add(element);
  return element;
}

describe('revealRing', () => {
  let list;
  beforeEach(() => {
    list = scroller();
  });

  it('scrolls down by the overflow and the gutter when the control passes the bottom', () => {
    revealRing(list, control(list, 170, 220));
    assert.deepEqual(list.calls, [{ top: 25, behavior: 'instant' }]);
  });

  it('scrolls up by the overflow and the gutter when the control passes the top', () => {
    revealRing(list, control(list, 80, 120));
    assert.deepEqual(list.calls, [{ top: -25, behavior: 'instant' }]);
  });

  it('does nothing for a control whose box, gutter and 1 px margin are inside', () => {
    revealRing(list, control(list, 105, 195));
    assert.deepEqual(list.calls, []);
    revealRing(list, control(list, 104, 196));
    assert.deepEqual(list.calls, [{ top: -1, behavior: 'instant' }], 'one pixel short of the margin scrolls that pixel');
  });

  it('scrolls a whole pixel, rounded up, for a fractional shortfall, in both directions (DW-198)', () => {
    revealRing(list, control(list, 170.2, 195.3));
    revealRing(list, control(list, 104.6, 150));
    assert.deepEqual(list.calls, [
      { top: 1, behavior: 'instant' },
      { top: -1, behavior: 'instant' },
    ]);
  });

  it('scrolls by the gutter alone when the box fits but the ring would not', () => {
    revealRing(list, control(list, 101, 150));
    assert.deepEqual(list.calls, [{ top: -4, behavior: 'instant' }]);
  });

  it('reads a scroll-padding that is not a length as 0', () => {
    list = scroller({ padding: { top: 'auto', bottom: 'auto' } });
    revealRing(list, control(list, 170, 220));
    assert.deepEqual(list.calls, [{ top: 21, behavior: 'instant' }]);
  });

  it('does nothing for the scroller itself, a target outside it, a null target and a scroller with no overflow', () => {
    revealRing(list, list);
    revealRing(list, new FakeElement());
    revealRing(list, null);
    const flat = scroller({ scrollHeight: 100 });
    revealRing(flat, control(flat, 170, 220));
    assert.deepEqual([list.calls, flat.calls], [[], []]);
  });
});
