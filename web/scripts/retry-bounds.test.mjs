// QA pins for Story 32.6 (DW-550, DW-774) that state-wait.test.mjs does not hold:
// - retryLocation inside a test: relative to the config folder, to the working folder, and the base name for a file outside both;
// - the RETRY line that retryLine prints is a line that ci/iris.sh's retry_lines counts, for every spec file of web/e2e and web/e2e-online;
// - no bound of the shared helpers was raised (the story is test-only: the retry splits today's bound, it does not lengthen it);
// - no story file names an absolute local path.
// The modules are imported as they are, as state-wait.test.mjs does: erasable TypeScript with no relative import.
// Run with: node --test web/scripts/retry-bounds.test.mjs
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { after, afterEach, beforeEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = join(here, '..');
const repoRoot = join(webRoot, '..');
const support = (name) => pathToFileURL(join(webRoot, 'e2e', 'support', name)).href;
const { test } = await import('@playwright/test');
const bounds = await import(support('bounds.ts'));

const STEP = 'loadedAfter the snapshot GET /ocutalon/api/v1/state';
const RELOAD_STEP = 'reloadSettled the snapshot GET /ocutalon/api/v1/state';

describe('retryLocation inside a test', () => {
  const original = test.info;
  const asTest = (info) => {
    test.info = () => info;
  };
  const restore = () => {
    test.info = original;
  };

  it('is the spec relative to the folder of the Playwright config, with / separators', () => {
    const configFile = join(webRoot, 'playwright.config.ts');
    asTest({ file: join(webRoot, 'e2e', 'cards', 'incident-card.spec.ts'), line: 454, config: { configFile } });
    try {
      assert.equal(bounds.retryLocation(), 'e2e/cards/incident-card.spec.ts:454');
    } finally {
      restore();
    }
  });

  it('is relative to the working folder when the config names no file', () => {
    asTest({ file: join(process.cwd(), 'e2e', 'live', 'socket.spec.ts'), line: 151, config: {} });
    try {
      assert.equal(bounds.retryLocation(), 'e2e/live/socket.spec.ts:151');
    } finally {
      restore();
    }
  });

  it('is the base name for a file outside the config folder, never an absolute or ../ path', () => {
    asTest({ file: join(repoRoot, 'elsewhere', 'other.spec.ts'), line: 9, config: { configFile: join(webRoot, 'playwright.config.ts') } });
    try {
      const location = bounds.retryLocation();
      assert.equal(location, 'other.spec.ts:9');
      assert.ok(!location.startsWith('/') && !location.includes('..') && !location.includes(sep === '/' ? 'elsewhere' : '\\'));
    } finally {
      restore();
    }
  });

  it('is unknown:0 when the test info cannot be read', () => {
    test.info = () => {
      throw new Error('outside a test');
    };
    try {
      assert.equal(bounds.retryLocation(), 'unknown:0');
    } finally {
      restore();
    }
  });
});

describe('the RETRY line and the line that ci/iris.sh counts', () => {
  const script = readFileSync(join(repoRoot, 'ci', 'iris.sh'), 'utf8');
  const shape = /^\s*LC_ALL=C grep -E '(\^RETRY [^']+\$)' "\$\(retry_log_of/m.exec(script)?.[1];

  function specFiles(dir) {
    const out = [];
    for (const name of readdirSync(dir)) {
      if (name === 'node_modules') continue;
      const path = join(dir, name);
      if (statSync(path).isDirectory()) out.push(...specFiles(path));
      else if (name.endsWith('.spec.ts')) out.push(path);
    }
    return out;
  }

  it('finds the pattern of retry_lines in ci/iris.sh', () => {
    assert.ok(shape, 'the grep pattern of retry_lines');
  });

  it('counts the line of every spec file of web/e2e and web/e2e-online, so that a path the pattern cannot match is caught here, not in CI', () => {
    const pattern = new RegExp(shape);
    const online = specFiles(join(webRoot, 'e2e-online'));
    const specs = [...specFiles(join(webRoot, 'e2e')), ...online];
    assert.ok(specs.length > 20 && online.length > 5, `found ${specs.length} spec files, ${online.length} of them online`);
    for (const file of specs) {
      const location = `${relative(webRoot, file).split(sep).join('/')}:${12345}`;
      const line = bounds.retryLine(location, STEP);
      assert.match(line, pattern, line);
    }
  });

  it('counts the line of the base-name fallback and of unknown:0', () => {
    const pattern = new RegExp(shape);
    for (const location of ['other.spec.ts:9', 'unknown:0']) assert.match(bounds.retryLine(location, STEP), pattern, location);
  });

  it('does not count a line that carries a query, a quote or a shell expansion (a path is kept out by retryLocation, above)', () => {
    const pattern = new RegExp(shape);
    for (const step of [`${STEP}?sid=abc`, `${STEP} "x"`, `${STEP} \${HOME}`]) assert.doesNotMatch(bounds.retryLine('e2e/live/socket.spec.ts:1', step), pattern, step);
  });
});

describe('a site retries once per run (Story 0.39, AC2b)', () => {
  const original = test.info;
  const logVariable = bounds.RETRY_LOG_VARIABLE;
  const savedLog = process.env[logVariable];
  const savedConsole = console.log;
  const work = mkdtempSync(join(tmpdir(), 'retry-bounds-'));
  const SAME_SITE = [STEP, RELOAD_STEP];
  let printed = [];
  let counter = 0;

  /** The running test sits at this line of a spec of web/e2e. */
  const at = (line) => {
    test.info = () => ({ file: join(webRoot, 'e2e', 'history', 'history.spec.ts'), line, config: { configFile: join(webRoot, 'playwright.config.ts') } });
  };
  const here_ = (line) => `e2e/history/history.spec.ts:${line}`;
  const logFile = () => join(work, `retries-${(counter += 1)}.txt`);

  beforeEach(() => {
    printed = [];
    console.log = (...args) => printed.push(args.join(' '));
  });
  afterEach(() => {
    console.log = savedConsole;
    test.info = original;
    if (savedLog === undefined) delete process.env[logVariable];
    else process.env[logVariable] = savedLog;
  });
  after(() => rmSync(work, { recursive: true, force: true }));

  it('lets the first retry at a site proceed, and fails the second at the same site with the named error, after still reporting its RETRY and DIAG lines', () => {
    const file = logFile();
    process.env[logVariable] = file;
    at(111);
    assert.equal(bounds.reportRetryOnce(STEP, ['DIAG first'], SAME_SITE), undefined);
    const second = bounds.reportRetryOnce(STEP, ['DIAG second'], SAME_SITE);
    assert.ok(second instanceof Error);
    assert.equal(second.message, `${here_(111)} needed its one logged retry a second time in this run; a second retry is a failure (Story 0.39)`);
    assert.equal(readFileSync(file, 'utf8'), `RETRY ${here_(111)} ${STEP}\nDIAG first\nRETRY ${here_(111)} ${STEP}\nDIAG second\n`);
    assert.deepEqual(printed, [`RETRY ${here_(111)} ${STEP}`, `RETRY ${here_(111)} ${STEP}`]);
  });

  it('lets a retry at another site proceed', () => {
    process.env[logVariable] = logFile();
    at(111);
    assert.equal(bounds.reportRetryOnce(STEP, [], SAME_SITE), undefined);
    at(222);
    assert.equal(bounds.reportRetryOnce(STEP, [], SAME_SITE), undefined);
  });

  it('counts a loadedAfter retry and a reloadSettled retry at one site as the same site, and not another step such as page.close', () => {
    process.env[logVariable] = logFile();
    at(333);
    assert.equal(bounds.reportRetryOnce('page.close', [], SAME_SITE), undefined);
    assert.equal(bounds.reportRetryOnce(RELOAD_STEP, [], SAME_SITE), undefined, 'a page.close retry is no snapshot retry');
    assert.ok(bounds.reportRetryOnce(STEP, [], SAME_SITE) instanceof Error, 'the reloadSettled retry already used the site');
  });

  it('reads the unit\'s retry file, so that another process\'s line counts', () => {
    const file = logFile();
    process.env[logVariable] = file;
    writeFileSync(file, `RETRY ${here_(444)} ${STEP}\nDIAG /state page: 2 requests\n`);
    at(444);
    assert.ok(bounds.reportRetryOnce(STEP, [], SAME_SITE) instanceof Error);
  });

  it('keeps a record of its own when no retry file is named', () => {
    delete process.env[logVariable];
    at(555);
    assert.equal(bounds.reportRetryOnce(STEP, [], SAME_SITE), undefined);
    assert.ok(bounds.reportRetryOnce(STEP, [], SAME_SITE) instanceof Error);
    at(556);
    assert.equal(bounds.reportRetryOnce(STEP, [], SAME_SITE), undefined);
  });

  it('counts the lines of another test\'s file no more: a fresh file is a fresh run', () => {
    process.env[logVariable] = logFile();
    at(111);
    assert.equal(bounds.reportRetryOnce(STEP, [], SAME_SITE), undefined);
    process.env[logVariable] = logFile();
    assert.equal(bounds.reportRetryOnce(STEP, [], SAME_SITE), undefined);
  });

  it('writes a RETRY line for the reload step that ci/iris.sh counts', () => {
    const script = readFileSync(join(repoRoot, 'ci', 'iris.sh'), 'utf8');
    const shape = /^\s*LC_ALL=C grep -E '(\^RETRY [^']+\$)' "\$\(retry_log_of/m.exec(script)?.[1];
    assert.match(bounds.retryLine(here_(111), RELOAD_STEP), new RegExp(shape));
  });
});

describe('the bounds that the story must leave as they are', () => {
  it('keeps the share, the caps, the slack and the clean-up reserve of the shared waits', () => {
    assert.equal(bounds.WAIT_SHARE, 2 / 3);
    assert.deepEqual(bounds.WAIT_CAPS, { actionTimeout: 60_000, navigationTimeout: 90_000 });
    assert.deepEqual(bounds.ONLINE_WAITS, { actionTimeout: 30_000, navigationTimeout: 60_000 });
    assert.equal(bounds.WAIT_SLACK_MS, 5_000);
    assert.equal(bounds.CLEANUP_RESERVE_MS, 60_000);
    assert.equal(bounds.CLEANUP_RESERVE_SHARE, 1 / 4);
    assert.equal(bounds.DEADLINE_MARGIN_MS, 10_000);
    assert.equal(bounds.CLEANUP_MARGIN_MS, 2_000);
    assert.equal(bounds.DEADLINE_FLOOR_MS, 5_000);
  });

  it('keeps the diagnosis bound of 11.27 (diagnose.ts cannot be imported into Node, so its source is read)', () => {
    const source = readFileSync(join(webRoot, 'e2e', 'support', 'diagnose.ts'), 'utf8');
    assert.match(source, /^export const DIAG_BOUND_MS = 15_000;$/m);
  });

  it('keeps the first attempt of a split bound inside it: half of B, the reload gets the rest, the total is B', () => {
    for (const whole of [20_000, 20_001, 30_000, 45_000, 60_000]) {
      const first = bounds.firstAttemptMs(whole);
      assert.ok(first !== undefined && first <= whole / 2 && whole - first >= bounds.RETRY_MIN_ATTEMPT_MS, String(whole));
    }
  });
});

describe('the files of the story', () => {
  const files = [
    'ci/iris.sh',
    'web/e2e/live/helper-waits.spec.ts',
    'web/e2e/live/state-retry.spec.ts',
    'web/e2e/support/api.ts',
    'web/e2e/support/bounds.ts',
    'web/e2e/support/diagnose.ts',
    'web/e2e/support/fixtures.ts',
    'web/e2e/support/floor.ts',
    'web/e2e/support/host.ts',
    'web/scripts/bounded-waits.test.mjs',
    'web/scripts/state-wait.test.mjs',
    'web/scripts/retry-bounds.test.mjs',
  ];

  it('name no absolute local path', () => {
    // Built from parts, so that this file does not hold what it looks for.
    const local = new RegExp(`(?:${['', 'Users'].join('/')}/|${['', 'home'].join('/')}/[a-z]|${['', 'private', 'tmp'].join('/')}|[A-Z]:\\\\Users)`);
    for (const file of files) assert.doesNotMatch(readFileSync(join(repoRoot, file), 'utf8'), local, file);
  });
});
