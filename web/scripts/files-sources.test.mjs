// Tests the source rules of the file store (Story 25.3; AD-3, AD-4, AD-13, AD-21): over the product's classes outside Test/, only the five that own the
// table name it, only Core.Files reads a row through Ownership.SentFile and reads its Content, no class under Web/ calls Core.Files.Open (no route serves
// a file's bytes) and Agent.Content alone calls it in the product (it opens the photo turn's file in the runner's job), the URL map of Web.Files holds
// exactly one route (POST, the empty remainder), and neither Core.Files nor Web.Files writes to a log.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const cls = join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon');

/** The class files under a folder, as { name (relative to cls, with /), text }. */
function classes(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return classes(path);
    return entry.name.endsWith('.cls') ? [{ name: relative(cls, path).split('\\').join('/'), text: readFileSync(path, 'utf8') }] : [];
  });
}

/** A class without its description and doc comments (lines that start with ///). */
const code = (text) => text.split('\n').filter((line) => !line.trimStart().startsWith('///')).join('\n');

/** Code without the class names it spells (the Class line and ##class(...) references), so that a name ending in .Content is not read as a property read. */
const noClassNames = (text) => text.replace(/^Class\b.*$/gm, '').replace(/##class\([^)]*\)/g, '');

const product = classes(cls)
  .filter((one) => !one.name.startsWith('Test/'))
  .map((one) => ({ ...one, code: code(one.text) }));
const named = (pattern) => product.filter((one) => pattern.test(one.code)).map((one) => one.name).sort();
const file = (name) => {
  const found = product.find((one) => one.name === name);
  assert.ok(found, `${name} is a class of the product`);
  return found;
};

describe('the SentFile table (AD-3, AD-4)', () => {
  it('is named by Data.SentFile, Data.Ownership, Core.Files, Core.SessionOps and Install/Step/Web only', () => {
    assert.deepEqual(named(/OcuTalon\.Data\.SentFile|OcuTalon_Data\.SentFile/), ['Core/Files.cls', 'Core/SessionOps.cls', 'Data/Ownership.cls', 'Data/SentFile.cls', 'Install/Step/Web.cls']);
  });

  it('is read through Ownership.SentFile by Core.Files alone (and Ownership itself), and its Content by Core.Files alone', () => {
    assert.deepEqual(named(/Ownership\)\.SentFile\(/), ['Core/Files.cls']);
    assert.deepEqual(product.filter((one) => one.code.includes('SentFile') && /\.Content\b/.test(noClassNames(one.code))).map((one) => one.name).sort(), ['Core/Files.cls', 'Data/SentFile.cls']);
    assert.match(file('Core/Files.cls').code, /row\.Content/, 'and Core.Files reads it');
    assert.doesNotMatch(file('Data/SentFile.cls').code, /\.Content\b(?!\s*=)(?!\.CopyFrom)/, 'Data.SentFile only fills Content');
  });
});

describe('no route serves a file\'s bytes (ruling 3 (ii))', () => {
  it('no class under Web/ calls Core.Files.Open', () => {
    assert.deepEqual(product.filter((one) => one.name.startsWith('Web/') && /Core\.Files\)\.Open\(/.test(one.code)).map((one) => one.name), []);
    assert.deepEqual(named(/Core\.Files\)\.Open\(/), ['Agent/Content.cls'], 'and the one product caller is Agent.Content, in the runner\'s job (AD-21 step 6, AD-31)');
  });

  it('Web.Files has one route: POST of the empty remainder', () => {
    const map = /XData UrlMap[\s\S]*?<Routes>([\s\S]*?)<\/Routes>/.exec(file('Web/Files.cls').text);
    assert.ok(map, 'Web.Files has a URL map');
    const routes = [...map[1].matchAll(/<(Route|Map)\b([^>]*)>/g)];
    assert.equal(routes.length, 1);
    assert.equal(routes[0][1], 'Route');
    assert.match(routes[0][2], /Url=""/);
    assert.match(routes[0][2], /Method="POST"/);
  });

  it('Web.Api maps /v1/files once, to Web.Files', () => {
    const maps = [...file('Web/Api.cls').text.matchAll(/<Map Prefix="\/v1\/files" Forward="([^"]*)"\/>/g)];
    assert.deepEqual(maps.map((one) => one[1]), ['OcuTalon.Web.Files']);
  });
});

describe('a file reaches no log (ruling 3 (iv))', () => {
  it('Core.Files and Web.Files hold no $$$LOG macro and no log call', () => {
    for (const name of ['Core/Files.cls', 'Web/Files.cls', 'Data/SentFile.cls']) {
      assert.doesNotMatch(file(name).code, /\$\$\$LOG|Ens\.Util\.Log|WriteToConsoleLog|LogInfo|LogWarning|LogError/, name);
    }
  });
});
