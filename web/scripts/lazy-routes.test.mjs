// Pins the lazy page routes (Story 36.5; DW-1282): the Settings, History and Usage pages load on demand, so they stay out of the initial bundle.
// (a) The static import graph from src/main.ts (relative `import ... from` and `export ... from`; `import type`, `export type` and every `import(` are
//     not followed) reaches nothing under app/history/ or app/usage/, and under app/settings/ only the unsaved guard and its dialog.
// (b) app.config.ts holds exactly the three `loadComponent` rows with their titles, and the settings row keeps its matcher and its guard.
// (c) While the installer's STALEFILES pattern admits no `_` or `-` in a bundle file's hash, the build turns Angular's chunk optimizer off, which
//     is the only thing that keeps chunk names inside the pattern (live:bundle-folder).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, '..');
const appDir = join(web, 'src', 'app');
const main = join(web, 'src', 'main.ts');

/** The source of a file without its comments, so that an example in a comment is never taken for an import. */
function code(file) {
  return readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

/** The file that a relative specifier names: as written, or with `.ts`. */
function resolveSpecifier(from, specifier) {
  const base = resolve(dirname(from), specifier);
  for (const candidate of [base, `${base}.ts`]) {
    if (existsSync(candidate) && candidate.endsWith('.ts')) {
      return candidate;
    }
  }
  assert.fail(`${relative(web, from)} imports ${specifier}, which is no .ts file`);
}

/** Every file that a static import of `file` pulls in: relative `import`/`export ... from` and `import './x'`, never `import type`, `export type` or `import(`. */
function staticImports(file) {
  const found = [];
  const source = code(file);
  const named = /(?:^|\n)\s*(import|export)(\s+type)?\b[^;'"()]*?\bfrom\s*['"](\.[^'"]+)['"]/g;
  const bare = /(?:^|\n)\s*import\s*['"](\.[^'"]+)['"]/g;
  for (const match of source.matchAll(named)) {
    if (!match[2]) {
      found.push(resolveSpecifier(file, match[3]));
    }
  }
  for (const match of source.matchAll(bare)) {
    found.push(resolveSpecifier(file, match[1]));
  }
  return found;
}

/** Every file reachable from `start` through static imports, as paths relative to src/app (or src/ for main.ts's own folder). */
function reachable(start) {
  const seen = new Set([start]);
  const queue = [start];
  while (queue.length > 0) {
    for (const next of staticImports(queue.pop())) {
      if (!seen.has(next)) {
        seen.add(next);
        queue.push(next);
      }
    }
  }
  return [...seen].map((file) => relative(join(web, 'src'), file).split('\\').join('/'));
}

describe('the pages load lazily', () => {
  const eager = reachable(main);

  it('the entry point reaches the app shell (the walk finds the files it should)', () => {
    for (const file of ['main.ts', 'app/app.ts', 'app/app.config.ts', 'app/header/current-page.ts', 'app/shared/page-shell-view.ts']) {
      assert.ok(eager.includes(file), `${file} is reached from main.ts`);
    }
  });

  it('no static import from the entry point reaches the History or Usage code', () => {
    assert.deepEqual(eager.filter((file) => file.startsWith('app/history/') || file.startsWith('app/usage/')), []);
  });

  it('only the unsaved guard and its dialog of the Settings code are reached from the entry point', () => {
    assert.deepEqual(
      eager.filter((file) => file.startsWith('app/settings/')).sort(),
      ['app/settings/unsaved-dialog.ts', 'app/settings/unsaved-guard.ts'],
    );
  });

  it('the shell module imports nothing, so the shell never pulls a page in through it', () => {
    assert.deepEqual(staticImports(join(appDir, 'shared', 'page-shell-view.ts')), []);
  });
});

describe('the routes', () => {
  const config = code(join(appDir, 'app.config.ts'));

  it('load Settings, History and Usage with loadComponent, and nothing else lazily', () => {
    assert.equal([...config.matchAll(/loadComponent:/g)].length, 3, 'three lazy rows');
    assert.equal([...config.matchAll(/\bimport\(/g)].length, 3, 'three dynamic imports');
    assert.match(config, /loadComponent: \(\) => import\('\.\/settings\/settings-page'\)\.then\(\(m\) => m\.SettingsPage\)/);
    assert.match(config, /loadComponent: \(\) => import\('\.\/history\/history-page'\)\.then\(\(m\) => m\.HistoryPage\)/);
    assert.match(config, /loadComponent: \(\) => import\('\.\/usage\/usage-page'\)\.then\(\(m\) => m\.UsagePage\)/);
    assert.doesNotMatch(config, /component: (SettingsPage|HistoryPage|UsagePage)/, 'no eager row for a lazy page');
  });

  it('keep the titles, the settings matcher and the unsaved-changes guard', () => {
    assert.match(config, /path: 'history',\s*loadComponent: [^\n]*title: SHELL_TEXTS\.historyTitle/);
    assert.match(config, /path: 'usage',\s*loadComponent: [^\n]*title: SHELL_TEXTS\.usageTitle/);
    assert.match(
      config,
      /matcher: settingsMatch,\s*loadComponent: [^\n]*SettingsPage\),\s*title: SHELL_TEXTS\.settingsTitle,\s*canDeactivate: \[unsavedGuard\]/,
    );
    assert.match(config, /path: 'documents', component: DocumentsPage/, 'Documents stays eager');
    assert.match(config, /path: '\*\*', component: MainPage/, 'the wildcard stays the chat');
  });
});

describe('the bundle file names', () => {
  it('stay inside the installer pattern while the optimizer is the only thing that keeps them there', () => {
    const installer = readFileSync(join(web, '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Install', 'Step', 'Web.cls'), 'utf8');
    const pattern = installer.match(/Parameter STALEFILES = "([^"]+)"/);
    assert.ok(pattern, 'the installer declares STALEFILES');
    const hashClass = pattern[1].match(/-\[([^\]]+)\]\+/);
    assert.ok(hashClass && hashClass[1], 'STALEFILES has a hash character class');
    const hashChars = new RegExp(`^[${hashClass[1]}]+$`);
    const admitsSeparators = hashChars.test('a_b') || hashChars.test('a-b');
    const build = JSON.parse(readFileSync(join(web, 'package.json'), 'utf8')).scripts.build;
    if (!admitsSeparators) {
      assert.match(build, /NG_BUILD_OPTIMIZE_CHUNKS=0 ng build$/, 'the build keeps the chunk optimizer off');
    }
  });
});
