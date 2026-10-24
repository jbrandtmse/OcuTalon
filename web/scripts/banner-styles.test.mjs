// Tests the styles of the status banner stack (src/app/banners/banner-stack.ts, Story 2.10 QA): that each of the three variants reads
// the tokens of its own variant (background, foreground, accent and minimum height), that the generated tokens give every variant
// the 44px minimum height and a colour for the light theme and both dark selectors, that a banner is full width with a 4px left
// accent in the variant's accent colour and the variant's minimum height, and that no banner is a live region. The info variant
// (Reconnecting, Story 2.11) is rendered by the browser case B13 in e2e/banners/banners.spec.ts, which checks its look; these scans
// check the styles the stack declares for it.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(join(here, '..', 'src', ...parts), 'utf8');
const tokens = read('styles', 'tokens.css');
const stack = read('app', 'banners', 'banner-stack.ts');

const VARIANTS = ['warning', 'danger', 'info'];
const PARTS = ['background', 'foreground', 'accent'];

/** The declarations of the rule that begins with this selector, as text. */
function rule(selector) {
  const start = stack.indexOf(`${selector} {`);
  assert.notEqual(start, -1, `${selector} is a rule of the stack`);
  return stack.slice(start, stack.indexOf('}', start));
}

describe('the banner tokens', () => {
  it('give every variant a minimum height of at least 44px (UX-DR34)', () => {
    for (const variant of VARIANTS) {
      const found = [...tokens.matchAll(new RegExp(`--status-banner-${variant}-min-height:\\s*(\\d+)px`, 'g'))];
      assert.equal(found.length, 1, `${variant}: one light value (the minimum height has no dark value)`);
      assert.ok(Number(found[0][1]) >= 44, `${variant}: ${found[0][1]}px is at least 44px`);
    }
  });

  it('give every variant a background, a foreground and an accent for the light theme and for both dark selectors', () => {
    for (const variant of VARIANTS) {
      for (const part of PARTS) {
        const found = [...tokens.matchAll(new RegExp(`--status-banner-${variant}-${part}:\\s*#[0-9A-Fa-f]{6}\\s*;`, 'g'))];
        assert.equal(found.length, 3, `${variant} ${part}: light, the dark media query and the dark theme`);
      }
    }
  });
});

describe('the stack of banners', () => {
  it('reads, for each variant, the tokens of that variant and no other', () => {
    for (const variant of VARIANTS) {
      const block = rule(`.banner[data-variant='${variant}']`);
      assert.match(block, new RegExp(`--banner-background:\\s*var\\(--status-banner-${variant}-background\\)`), `${variant} background`);
      assert.match(block, new RegExp(`--banner-foreground:\\s*var\\(--status-banner-${variant}-foreground\\)`), `${variant} foreground`);
      assert.match(block, new RegExp(`--banner-accent:\\s*var\\(--status-banner-${variant}-accent\\)`), `${variant} accent`);
      assert.match(block, new RegExp(`--banner-min-height:\\s*var\\(--status-banner-${variant}-min-height\\)`), `${variant} minimum height`);
      for (const other of VARIANTS.filter((one) => one !== variant)) {
        assert.ok(!block.includes(`--status-banner-${other}-`), `${variant} reads nothing of ${other}`);
      }
    }
    assert.equal([...stack.matchAll(/\.banner\[data-variant=/g)].length, 3, 'and there are three variants');
  });

  it('makes a banner full width, at least as tall as its variant says, with a 4px left accent in the variant\'s colour', () => {
    const banner = rule('.banner');
    assert.match(banner, /width:\s*100%/, 'full width');
    assert.match(banner, /box-sizing:\s*border-box/, 'the border counts inside the width');
    assert.match(banner, /min-height:\s*var\(--banner-min-height\)/, 'the variant\'s minimum height');
    assert.match(banner, /border-left:\s*4px solid var\(--banner-accent\)/, 'a 4px accent on the left edge');
    assert.match(banner, /background:\s*var\(--banner-background\)/, 'the variant\'s background');
    assert.match(banner, /color:\s*var\(--banner-foreground\)/, 'and its text colour');
    assert.match(rule('.mark'), /color:\s*var\(--banner-accent\)/, 'the icon is in the accent colour');
    assert.match(rule('.action'), /text-decoration-line:\s*underline/, 'the action is underlined');
  });

  it('is no live region: the template marks no banner with aria-live or a live role', () => {
    const template = stack.slice(stack.indexOf('template: `'), stack.indexOf('styles: `'));
    assert.ok(template.includes('data-banner'), 'the template is the banner\'s');
    assert.doesNotMatch(template, /aria-live|aria-atomic|role\s*=\s*["']?(status|alert|log|alertdialog)/i);
  });
});
