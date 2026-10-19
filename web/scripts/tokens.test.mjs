// Tests of the token generator (tokens.mjs): the real DESIGN.md's counts and output, and fixtures for the
// front matter shapes it accepts and refuses. Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { buildModel, parseFrontMatter, renderSignInAssets, renderTokensCss, tokenEntries } from './tokens.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, 'tokens.mjs');
const repoRoot = resolve(here, '..', '..');
const realDesign = readFileSync(
  join(repoRoot, '_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/DESIGN.md'),
  'utf8',
);
const realSigninCss = readFileSync(join(here, '..', 'src/signin/signin.css'), 'utf8');
const realSigninJs = readFileSync(join(here, '..', 'src/signin/signin.js'), 'utf8');

const work = mkdtempSync(join(tmpdir(), 'ocutalon-tokens-'));
after(() => rmSync(work, { recursive: true, force: true }));

const FIXTURE = `---
name: Fixture
colors:
  # a full-line comment; a # inside a quoted colour is part of the colour
  bg: '#FFFFFF'
  ink: '#102A45'
  bg-dark: '#111111'
  ink-dark: '#EEEEEE'
typography:
  body:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
    letterSpacing: -0.01em
rounded:
  sm: 6px
spacing:
  '1': 4px
  header: 56px
components:
  box:
    background: '{colors.bg}'
    border: '1px solid {colors.ink}'
    typography: '{typography.body}'
    radius: '{rounded.sm}'
    height: '{spacing.header}'
    icon: circle-alert
    shadow: '0 1px 2px #00000040'
    shadow-dark: '0 1px 2px #FFFFFF40'
    note: 'prose with {not.a.reference}'
  literal:
    background: '#FFFFFF'
    accent: '{colors.bg-dark}'
---

Prose below the front matter is ignored: {colors.nothing}.
`;

const FIXTURE_CSS = '.a { color: var(--ink); padding: var(--space-1); }\n';
const FIXTURE_JS = '(function () { return 1; }());\n';

function fixtureDir(name, design, css = FIXTURE_CSS, js = FIXTURE_JS) {
  const dir = join(work, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'DESIGN.md'), design);
  writeFileSync(join(dir, 'signin.css'), css);
  writeFileSync(join(dir, 'signin.js'), js);
  return dir;
}

function runWith(scriptPath, dir, ...extra) {
  return spawnSync(
    process.execPath,
    [
      scriptPath,
      '--design', join(dir, 'DESIGN.md'),
      '--css-out', join(dir, 'out', 'tokens.css'),
      '--cls-out', join(dir, 'out', 'SignInAssets.cls'),
      '--signin-css', join(dir, 'signin.css'),
      '--signin-js', join(dir, 'signin.js'),
      ...extra,
    ],
    { encoding: 'utf8' },
  );
}

const run = (dir, ...extra) => runWith(script, dir, ...extra);

const realModel = buildModel(parseFrontMatter(realDesign, 'DESIGN.md'), 'DESIGN.md');
const realCss = renderTokensCss(realModel);

function declarations(css) {
  return [...css.matchAll(/^\s*--([a-z0-9-]+): (.*);$/gm)].map((m) => [m[1], m[2]]);
}

describe('the real DESIGN.md', () => {
  it('has the documented counts', () => {
    assert.equal(realModel.counts.colors, 74);
    assert.equal(realModel.counts.colorPairs, 37);
    assert.equal(realModel.counts.typography, 14);
    assert.equal(realModel.counts.rounded, 6);
    assert.equal(realModel.counts.spacing, 27);
  });

  it('resolves every reference', () => {
    for (const [name, value] of declarations(realCss)) {
      assert.ok(!/[{}]/.test(value), `--${name} still holds a reference: ${value}`);
    }
    assert.ok(declarations(realCss).length > 500);
  });

  it('gives the dark values under both dark selectors, and keeps the dark exceptions', () => {
    const parts = realCss.split('@media (prefers-color-scheme: dark) {');
    assert.equal(parts.length, 2);
    const [mediaBlock, rest] = parts[1].split(':root[data-theme=dark] {');
    const attributeBlock = rest;
    assert.match(mediaBlock, /:root:not\(\[data-theme=light\]\) \{/);
    const media = new Map(declarations(mediaBlock));
    const attribute = new Map(declarations(attributeBlock));
    assert.deepEqual([...media], [...attribute]);
    assert.equal(media.get('bg'), '#11192B');
    assert.equal(media.get('brand-orange'), '#DB482B');
    assert.equal(media.get('action'), '#45B9B3');
    assert.equal(media.get('simulated-phone-shadow'), '0 12px 32px #00000080');
    assert.equal(media.get('splash-canvas-background'), '#11192B');
    assert.equal(media.get('brand-navy'), '#11192B');
    assert.equal(media.has('qr-code-block-background'), false);
    assert.equal(media.has('qr-code-block-foreground'), false);
    const light = new Map(declarations(parts[0]));
    assert.equal(light.get('simulated-phone-shadow'), '0 12px 32px #102A452E');
    assert.equal(light.get('splash-canvas-background'), '#FFFFFF');
    assert.equal(light.get('qr-code-block-background'), '#FFFFFF');
  });

  it('emits no property for prose', () => {
    const names = new Set(declarations(realCss).map(([name]) => name));
    for (const prose of ['button-busy-note', 'guide-step-done-marker', 'guide-step-current-marker', 'guide-step-upcoming-marker',
      'focus-ring-halo', 'link-decoration']) {
      assert.equal(names.has(prose), false, `--${prose} is prose`);
    }
    assert.equal(names.has('email-row-unread-marker'), true, 'unread-marker is a colour, not the prose property marker');
    assert.equal(names.has('focus-ring-outline'), true);
    assert.equal(names.has('link-foreground'), true);
  });

  it('is deterministic', () => {
    const again = buildModel(parseFrontMatter(realDesign, 'DESIGN.md'), 'DESIGN.md');
    assert.equal(renderTokensCss(again), realCss);
    assert.equal(
      renderSignInAssets(again, realSigninCss, realSigninJs),
      renderSignInAssets(realModel, realSigninCss, realSigninJs),
    );
  });

  it('names one custom property per group the shell reads', () => {
    const light = new Map(declarations(realCss.split('@media')[0]));
    assert.equal(light.get('bg'), '#F4F7FA');
    assert.equal(light.get('brand-orange'), '#DE5034');
    assert.equal(light.get('action'), '#1A6F6D');
    assert.equal(light.get('attention'), '#B83A1E');
    assert.equal(light.get('danger-ink'), '#B42318');
    assert.equal(light.get('scrim'), '#102A4573');
    assert.equal(light.get('rounded-xs'), '4px');
    assert.equal(light.get('space-1'), '4px');
    assert.equal(light.get('type-body-font-size'), '14px');
    assert.equal(light.get('popover-shadow'), '0 8px 24px #102A4529');
    assert.equal(light.get('field-error-icon'), 'circle-alert');
    assert.equal(light.get('wordmark-typography-font-size'), '20px');
  });

  it('keeps only the used custom properties in the sign-in assets', () => {
    const cls = renderSignInAssets(realModel, realSigninCss, realSigninJs);
    const css = /Parameter CSS = "(.*)";/.exec(cls)[1];
    assert.match(css, /^:root\{--surface:#FFFFFF;/);
    assert.match(css, /@media\(prefers-color-scheme:dark\)\{:root\{--surface:#18233A;/);
    assert.ok(!css.includes('--brand-orange'));
    assert.ok(css.length < 8000);
    assert.ok(!/[^\x20-\x7e\n\t]/.test(cls), 'ASCII only');
    assert.ok(!css.includes('\n'));
  });
});

describe('fixture front matter', () => {
  const model = buildModel(parseFrontMatter(FIXTURE, 'fixture.md'), 'fixture.md');

  it('names tokens as documented', () => {
    const light = new Map(tokenEntries(model, 'light'));
    assert.equal(light.get('bg'), '#FFFFFF');
    assert.equal(light.get('type-body-font-size'), '14px');
    assert.equal(light.get('type-body-letter-spacing'), '-0.01em');
    assert.equal(light.get('rounded-sm'), '6px');
    assert.equal(light.get('space-1'), '4px');
    assert.equal(light.get('space-header'), '56px');
    assert.equal(light.get('box-border'), '1px solid #102A45');
    assert.equal(light.get('box-typography-font-size'), '14px');
    assert.equal(light.get('box-icon'), 'circle-alert');
    assert.equal(light.get('box-shadow'), '0 1px 2px #00000040');
    assert.equal(light.has('box-shadow-dark'), false);
    assert.equal(light.has('box-note'), false);
    const dark = new Map(tokenEntries(model, 'dark'));
    assert.equal(dark.get('box-border'), '1px solid #EEEEEE');
    assert.equal(dark.get('box-shadow'), '0 1px 2px #FFFFFF40');
    assert.equal(dark.get('literal-background'), '#FFFFFF');
    assert.equal(dark.get('literal-accent'), '#111111');
    assert.equal(light.get('literal-accent'), '#111111');
  });

  it('treats a # in a quoted value as part of the value and a full-line # as a comment', () => {
    assert.equal(model.colors[0].light, '#FFFFFF');
  });

  it('writes, then checks, then finds a stale file', () => {
    const dir = fixtureDir('check', FIXTURE);
    let r = run(dir);
    assert.equal(r.status, 0, r.stderr);
    r = run(dir, '--check');
    assert.equal(r.status, 0, r.stderr);
    writeFileSync(join(dir, 'out', 'tokens.css'), `${readFileSync(join(dir, 'out', 'tokens.css'), 'utf8')}/* hand edit */\n`);
    r = run(dir, '--check');
    assert.equal(r.status, 1);
    assert.match(r.stderr, /tokens\.css is stale/);
    r = run(dir);
    assert.equal(r.status, 0, r.stderr);
    r = run(dir, '--check');
    assert.equal(r.status, 0, r.stderr);
    writeFileSync(join(dir, 'signin.css'), '.a { color: var(--ink); }\n.b { color: var(--bg); }\n');
    r = run(dir, '--check');
    assert.equal(r.status, 1);
    assert.match(r.stderr, /SignInAssets\.cls is stale/);
  });

  it('runs when the script is reached through a symbolic link', () => {
    const dir = fixtureDir('check-link', FIXTURE);
    const link = join(work, 'linked-scripts');
    symlinkSync(dirname(script), link);
    const r = runWith(join(link, 'tokens.mjs'), dir, '--check');
    assert.equal(r.status, 1, 'a stale check through a link must fail, not pass silently');
    assert.match(r.stderr, /is stale/);
  });

  it('fails on a missing file under --check', () => {
    const dir = fixtureDir('check-missing', FIXTURE);
    const r = run(dir, '--check');
    assert.equal(r.status, 1);
    assert.match(r.stderr, /is stale/);
  });
});

describe('refusals name the line', () => {
  const refuse = (name, design, pattern, css, js) => {
    const dir = fixtureDir(name, design, css, js);
    const r = run(dir);
    assert.notEqual(r.status, 0, `${name}: should exit non-zero`);
    assert.match(r.stderr, pattern, `${name}: ${r.stderr}`);
  };
  const withComponent = (line) => FIXTURE.replace("    icon: circle-alert\n", `    icon: circle-alert\n${line}\n`);

  it('an unresolved reference', () => {
    const design = withComponent("    outline: '2px solid {colors.nope}'");
    const line = design.split('\n').findIndex((l) => l.includes('colors.nope')) + 1;
    refuse('unresolved', design, new RegExp(`DESIGN\\.md:${line}: unresolved reference \\{colors\\.nope\\}`));
  });

  it('a reference to a missing typography token', () => {
    const design = withComponent("    face: '{typography.missing}'");
    const line = design.split('\n').findIndex((l) => l.includes('typography.missing')) + 1;
    refuse('typography', design, new RegExp(`DESIGN\\.md:${line}: unresolved reference`));
  });

  it('a list', () => {
    const design = FIXTURE.replace('rounded:\n', 'tags:\n  - one\nrounded:\n');
    const line = design.split('\n').findIndex((l) => l.includes('- one')) + 1;
    refuse('list', design, new RegExp(`DESIGN\\.md:${line}: unsupported YAML form: list`));
  });

  it('flow style', () => {
    const design = withComponent('    flow: { a: 1 }');
    const line = design.split('\n').findIndex((l) => l.includes('flow:')) + 1;
    refuse('flow', design, new RegExp(`DESIGN\\.md:${line}: unsupported YAML form: flow style`));
  });

  it('a double-quoted string', () => {
    const design = withComponent('    text: "double"');
    const line = design.split('\n').findIndex((l) => l.includes('text:')) + 1;
    refuse('double', design, new RegExp(`DESIGN\\.md:${line}: unsupported YAML form: double-quoted`));
  });

  it('an anchor and a block scalar', () => {
    let design = withComponent('    a: &anchor value');
    let line = design.split('\n').findIndex((l) => l.includes('&anchor')) + 1;
    refuse('anchor', design, new RegExp(`DESIGN\\.md:${line}: unsupported YAML form: anchor`));
    design = withComponent('    b: |');
    line = design.split('\n').findIndex((l) => l.includes('b: |')) + 1;
    refuse('block', design, new RegExp(`DESIGN\\.md:${line}: unsupported YAML form: block scalar`));
  });

  it('an odd indentation and a fourth level', () => {
    let design = withComponent('     odd: x');
    let line = design.split('\n').findIndex((l) => l.includes('odd:')) + 1;
    refuse('odd', design, new RegExp(`DESIGN\\.md:${line}: indentation must be 0, 2 or 4 spaces`));
    design = withComponent('        deep: x');
    line = design.split('\n').findIndex((l) => l.includes('deep:')) + 1;
    refuse('deep', design, new RegExp(`DESIGN\\.md:${line}: indentation must be 0, 2 or 4 spaces`));
  });

  it('a colour without its dark value', () => {
    const design = FIXTURE.replace("  ink-dark: '#EEEEEE'\n", '');
    const line = design.split('\n').findIndex((l) => l.startsWith('  ink:')) + 1;
    refuse('nodark', design, new RegExp(`DESIGN\\.md:${line}: colour 'ink' has no 'ink-dark'`));
  });

  it('a custom property that is not a token in the sign-in stylesheet', () => {
    refuse('badvar', FIXTURE, /signin\.css:2: var\(--nope\) is not a token/, '.a { color: var(--ink); }\n.b { color: var(--nope); }\n');
  });

  it('a non-ASCII character in the sign-in assets', () => {
    refuse('nonascii', FIXTURE, /signin\.js:1: the script holds a character that is not printable ASCII/, FIXTURE_CSS, '/* \u00e9 */\n');
  });

  it('a // comment in the sign-in script', () => {
    refuse('slashes', FIXTURE, /signin\.js:2: a \/\/ comment is not supported/, FIXTURE_CSS, 'var a = 1;\n// no\n');
  });
});
