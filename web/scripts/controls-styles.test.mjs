// Tests the button variants of src/styles/controls.css: each of the five declares its minimum height (ghost at least
// 32px, the others at least 36px) and the small radius, and no rule of a button uses the pill radius. A height or a
// radius written another way, or a misspelt token, is not an error in CSS, it silently drops the declaration, so only
// this scan notices it.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const styles = join(here, '..', 'src', 'styles');

const stripComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '');
const controls = stripComments(readFileSync(join(styles, 'controls.css'), 'utf8'));
const tokensText = stripComments(readFileSync(join(styles, 'tokens.css'), 'utf8'));

/** The light values of the tokens: the first :root block, before the dark overrides. */
const tokens = new Map();
for (const match of tokensText.slice(0, tokensText.indexOf('@media')).matchAll(/--([A-Za-z0-9_-]+)\s*:\s*([^;]+);/g)) {
  tokens.set(match[1], match[2].trim());
}

/** The rules of the sheet as { selector, body }; the steps of an @keyframes are rules too, which no test here reads. */
const rules = [...controls.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((match) => ({ selector: match[1].trim(), body: match[2] }));

/** The value of a declaration in a rule body, or undefined. */
function declared(body, property) {
  return new RegExp(`(?:^|[;\\s])${property}\\s*:\\s*([^;]+)`).exec(body)?.[1].trim();
}

/** A length in px, following one var(--token) to the token's value. */
function pixels(value) {
  const reference = /^var\(\s*--([A-Za-z0-9_-]+)\s*\)$/.exec(value ?? '');
  const resolved = reference ? tokens.get(reference[1]) : value;
  const match = /^(\d+(?:\.\d+)?)px$/.exec(resolved ?? '');
  return match ? Number(match[1]) : undefined;
}

const VARIANTS = { primary: 36, secondary: 36, attention: 36, ghost: 32, inactive: 36 };

describe('the button variants of controls.css', () => {
  it('reads the tokens that it resolves against', () => {
    assert.ok(tokens.size > 300, `the light tokens are read (${tokens.size})`);
    assert.equal(tokens.get('rounded-sm'), '6px');
    assert.equal(tokens.get('space-control-height'), '36px');
    assert.equal(tokens.get('space-target-min'), '32px');
  });

  for (const [variant, minimum] of Object.entries(VARIANTS)) {
    const own = rules.filter((rule) => rule.selector === `.button-${variant}`);

    it(`declares .button-${variant} once, with a minimum height of at least ${minimum}px`, () => {
      assert.equal(own.length, 1, `.button-${variant} is one rule`);
      const height = pixels(declared(own[0].body, 'min-height'));
      assert.ok(height !== undefined && height >= minimum, `.button-${variant} min-height is ${height}px`);
    });

    it(`gives .button-${variant} the small radius`, () => {
      assert.equal(declared(own[0]?.body ?? '', 'border-radius'), 'var(--rounded-sm)');
    });
  }

  it('uses no pill radius in any rule of a button', () => {
    const buttonRules = rules.filter((rule) => /\.button\b/.test(rule.selector));
    assert.ok(buttonRules.length >= 6, `the button rules are found (${buttonRules.length})`);
    for (const rule of buttonRules) {
      assert.doesNotMatch(rule.body, /--rounded-full|9999px/, `${rule.selector} has no pill radius`);
    }
  });
});
