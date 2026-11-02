// Pins the QR-code library of the Telegram pairing link (Story 10.3; AD-14, REL-2, the Stack row "QR-code library"): qrcode-generator at the
// exact version 2.0.4 in web/package.json and web/package-lock.json, an MIT library with no dependencies; that it renders the pairing link
// of the CI bot (https://t.me/ocutalon_ci_bot?start=<a 22-character code>) as an <svg string with no Node API, so the browser can draw it;
// and that the architecture spine's Stack section names the library and the version. Nothing in web/src imports it yet: Story 12.3 draws the code.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, '..');
const read = (path) => readFileSync(path, 'utf8');
const pkg = JSON.parse(read(join(web, 'package.json')));
const lock = JSON.parse(read(join(web, 'package-lock.json')));
const spine = join(web, '..', '_bmad-output', 'planning-artifacts', 'architecture', 'architecture-OcuTalon-2026-10-16', 'ARCHITECTURE-SPINE.md');
const LIBRARY = 'qrcode-generator';
const VERSION = '2.0.4';

describe('the pin', () => {
  it('package.json pins qrcode-generator at exactly 2.0.4, as a runtime dependency', () => {
    assert.equal(pkg.dependencies[LIBRARY], VERSION);
    assert.equal(pkg.devDependencies?.[LIBRARY], undefined);
    assert.match(pkg.dependencies[LIBRARY], /^\d+\.\d+\.\d+$/, 'no ^, ~ or range');
  });

  it('the lockfile root lists it with the same exact version', () => {
    assert.equal(lock.packages[''].dependencies[LIBRARY], VERSION);
  });

  it('the lockfile entry is 2.0.4, MIT, from the npm registry, with an integrity hash and no dependencies', () => {
    const entry = lock.packages[`node_modules/${LIBRARY}`];
    assert.ok(entry, 'the lockfile has the entry');
    assert.equal(entry.version, VERSION);
    assert.equal(entry.license, 'MIT');
    assert.match(entry.resolved, /^https:\/\/registry\.npmjs\.org\/qrcode-generator\/-\/qrcode-generator-2\.0\.4\.tgz$/);
    assert.match(entry.integrity, /^sha512-/);
    assert.equal(entry.dependencies, undefined);
    assert.equal(entry.peerDependencies, undefined);
    assert.equal(entry.optionalDependencies, undefined);
  });

  it('the installed package is the pinned one', () => {
    const installed = JSON.parse(read(join(web, 'node_modules', LIBRARY, 'package.json')));
    assert.equal(installed.version, VERSION);
    assert.equal(installed.license, 'MIT');
    assert.equal(installed.dependencies, undefined);
  });
});

describe('the library in a browser', () => {
  const dist = join(web, 'node_modules', LIBRARY, 'dist', 'qrcode.mjs');

  it('renders the pairing link of the CI bot as an <svg string', async () => {
    const { default: qrcode } = await import(pathToFileURL(dist).href);
    const link = `https://t.me/ocutalon_ci_bot?start=${'Ab-_1234567890CdEfGhIj'}`;
    assert.equal(link.length - 'https://t.me/ocutalon_ci_bot?start='.length, 22, 'a 22-character code');
    const qr = qrcode(0, 'M');
    qr.addData(link);
    qr.make();
    const svg = qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
    assert.equal(typeof svg, 'string');
    assert.ok(svg.startsWith('<svg'), svg.slice(0, 40));
    assert.ok(svg.endsWith('</svg>'));
    assert.ok(qr.getModuleCount() >= 21, 'a real symbol');
  });

  it('draws the same symbol for the same link and a different one for another', async () => {
    const { default: qrcode } = await import(pathToFileURL(dist).href);
    const draw = (text) => {
      const qr = qrcode(0, 'M');
      qr.addData(text);
      qr.make();
      return qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
    };
    assert.equal(draw('https://t.me/ocutalon_ci_bot?start=AAAAAAAAAAAAAAAAAAAAAA'), draw('https://t.me/ocutalon_ci_bot?start=AAAAAAAAAAAAAAAAAAAAAA'));
    assert.notEqual(draw('https://t.me/ocutalon_ci_bot?start=AAAAAAAAAAAAAAAAAAAAAA'), draw('https://t.me/ocutalon_ci_bot?start=BBBBBBBBBBBBBBBBBBBBBB'));
  });

  it('the browser build uses no Node API: no require, no node: import, no process, no Buffer, no fs', () => {
    const code = read(dist);
    assert.doesNotMatch(code, /\brequire\s*\(/);
    assert.doesNotMatch(code, /from\s*['"]node:/);
    assert.doesNotMatch(code, /\bprocess\.(env|argv|versions|platform)\b/);
    assert.doesNotMatch(code, /\bBuffer\b/);
    assert.doesNotMatch(code, /['"](fs|path|os|child_process)['"]/);
  });
});

describe('the record', () => {
  it("the spine's Stack section names qrcode-generator and 2.0.4 on one row", () => {
    const rows = read(spine)
      .split('\n')
      .filter((line) => line.startsWith('|') && line.includes(LIBRARY));
    assert.equal(rows.length >= 1, true, 'a Stack row names the library');
    assert.ok(rows.some((row) => row.includes(VERSION)), 'and its version');
    assert.ok(rows.some((row) => /\bMIT\b/.test(row)), 'and its licence');
  });
});
