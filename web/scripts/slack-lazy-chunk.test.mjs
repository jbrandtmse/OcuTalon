// Pins the Slack group's lazy chunk across the whole app (Story 27.3 QA; AD-12 bundle budget): slack-section.ts is reached only by the one dynamic import in channels-section.ts,
// and slack-view.ts (its texts and rules) only by slack-section.ts, so no other file (settings-page.ts, app.ts, a shared module) can make the Slack code part of another chunk.
// slack-view.test.mjs pins the Channels section's own import lines; this scans every source file under web/src. (A static import from the entry point's graph is also caught by
// lazy-routes.test.mjs, and the initial bytes by initial-bundle.test.mjs; this is the pin for an import from any other file.)
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const src = join(dirname(fileURLToPath(import.meta.url)), '..', 'src');

/** Every .ts file under a folder, as paths relative to src with forward slashes. */
function sources(folder) {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory() ? sources(join(folder, entry.name)) : entry.name.endsWith('.ts') ? [relative(src, join(folder, entry.name)).split('\\').join('/')] : [],
  );
}

/** The source without its comments, so that a mention in a comment is never taken for an import. */
function code(file) {
  return readFileSync(join(src, file), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

/** How a file refers to a module by file name: static (`import ... from`, `export ... from`, `import 'x'`) and dynamic (`import('x')`) specifiers that end in the name. */
function references(file, name) {
  const text = code(file);
  const escaped = name.replace('-', '\\-');
  const staticOnes = [...text.matchAll(new RegExp(`(?:^|\\n)\\s*(?:import|export)\\b[^;'"()]*?(?:\\bfrom\\s*)?['"][^'"]*/${escaped}['"]`, 'g'))];
  const dynamicOnes = [...text.matchAll(new RegExp(`\\bimport\\(\\s*['"][^'"]*/${escaped}['"]\\s*\\)`, 'g'))];
  return { static: staticOnes.length, dynamic: dynamicOnes.length };
}

describe('the Slack group is its own lazy chunk', () => {
  const files = sources(src);

  it('the walk finds the app (control)', () => {
    for (const file of ['app/settings/channels-section.ts', 'app/settings/slack-section.ts', 'app/settings/slack-view.ts', 'app/settings/settings-page.ts']) {
      assert.ok(files.includes(file), `${file} is among the sources`);
    }
  });

  it('no source file imports slack-section statically', () => {
    assert.deepEqual(
      files.filter((file) => references(file, 'slack-section').static > 0),
      [],
    );
  });

  it('slack-section is imported dynamically once in the whole app, by the Channels section', () => {
    assert.deepEqual(
      files.filter((file) => references(file, 'slack-section').dynamic > 0),
      ['app/settings/channels-section.ts'],
    );
    assert.equal(references('app/settings/channels-section.ts', 'slack-section').dynamic, 1);
  });

  it('slack-view is imported by slack-section only, and never dynamically', () => {
    assert.deepEqual(
      files.filter((file) => references(file, 'slack-view').static > 0),
      ['app/settings/slack-section.ts'],
    );
    assert.deepEqual(
      files.filter((file) => references(file, 'slack-view').dynamic > 0),
      [],
    );
  });
});
