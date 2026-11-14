// Tests the pure logic of the chunk-load reload (src/app/shared/chunk-reload.ts; Story 36.7): which errors count as a failed chunk, the per-address flag in
// sessionStorage (first claim only; a missing, throwing or forgetful storage never claims), the target address, and the whole decision over fake browser
// objects: one reload per address, none for another error, none without usable storage, no reload loop. The module is imported as it is: Node strips its
// types, which holds only while it keeps to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { CHUNK_RELOAD_PREFIX, claimReload, isChunkLoadError, reloadOnChunkError, targetAddress } = await import(
  pathToFileURL(join(here, '..', 'src', 'app', 'shared', 'chunk-reload.ts')).href
);

const CHUNK_ERROR = new TypeError('Failed to fetch dynamically imported module: http://127.0.0.1:52802/ocutalon/chunk-ABCD1234.js');

/** A storage over a map. */
function memoryStorage() {
  const map = new Map();
  return { map, getItem: (key) => (map.has(key) ? map.get(key) : null), setItem: (key, value) => void map.set(key, value) };
}

/** Fake browser objects that record what happens: the reloads and the history writes. */
function environment(storage) {
  const log = { reloads: 0, replaced: [] };
  const env = {
    location: { pathname: '/ocutalon/', search: '?a=1', reload: () => void (log.reloads += 1) },
    history: { state: { n: 1 }, replaceState: (state, unused, url) => void log.replaced.push([state, unused, url]) },
    storage: () => storage,
  };
  return { env, log };
}

describe('isChunkLoadError', () => {
  it('knows the messages of the three engines and a ChunkLoadError', () => {
    assert.equal(isChunkLoadError(CHUNK_ERROR), true);
    assert.equal(isChunkLoadError(new TypeError('error loading dynamically imported module: https://x/chunk-A.js')), true);
    assert.equal(isChunkLoadError(new TypeError('Importing a module script failed.')), true);
    assert.equal(isChunkLoadError(new Error('Loading chunk 7 failed.')), true);
    assert.equal(isChunkLoadError(Object.assign(new Error('x'), { name: 'ChunkLoadError' })), true);
    assert.equal(isChunkLoadError({ message: 'Failed to fetch dynamically imported module: x' }), true);
  });

  it('is false for every other error and for what is no error', () => {
    for (const other of [new Error('NG04002: Cannot match any routes'), new TypeError('x is not a function'), new Error('Failed to fetch'), 'Failed to fetch dynamically imported module', null, undefined, 42, {}]) {
      assert.equal(isChunkLoadError(other), false, String(other));
    }
  });
});

describe('claimReload', () => {
  it('is true once per address and false after, and an address does not claim another', () => {
    const storage = memoryStorage();
    assert.equal(claimReload(storage, '/ocutalon/#/usage'), true);
    assert.equal(claimReload(storage, '/ocutalon/#/usage'), false);
    assert.equal(claimReload(storage, '/ocutalon/#/history'), true);
    assert.deepEqual([...storage.map.keys()].sort(), [`${CHUNK_RELOAD_PREFIX}/ocutalon/#/history`, `${CHUNK_RELOAD_PREFIX}/ocutalon/#/usage`]);
  });

  it('is false without a storage, with one that throws, and with one that does not keep the flag', () => {
    assert.equal(claimReload(null, '/a'), false);
    assert.equal(claimReload(undefined, '/a'), false);
    assert.equal(claimReload({ getItem: () => { throw new Error('denied'); }, setItem: () => {} }, '/a'), false);
    assert.equal(claimReload({ getItem: () => null, setItem: () => { throw new Error('quota'); } }, '/a'), false);
    assert.equal(claimReload({ getItem: () => null, setItem: () => {} }, '/a'), false, 'a storage that forgets would loop');
  });
});

describe('targetAddress', () => {
  it('writes the router address after the hash of the document path and query', () => {
    assert.equal(targetAddress({ pathname: '/ocutalon/', search: '' }, '/usage'), '/ocutalon/#/usage');
    assert.equal(targetAddress({ pathname: '/ocutalon/', search: '?a=1' }, '/settings/budgets?x=1'), '/ocutalon/?a=1#/settings/budgets?x=1');
  });
});

describe('reloadOnChunkError', () => {
  it('reloads once at the target address for a chunk failure, and not again for it', () => {
    const { env, log } = environment(memoryStorage());
    assert.equal(reloadOnChunkError(CHUNK_ERROR, '/usage', env), true);
    assert.equal(log.reloads, 1);
    assert.deepEqual(log.replaced, [[{ n: 1 }, '', '/ocutalon/?a=1#/usage']], 'the history entry takes the target address before the reload');
    assert.equal(reloadOnChunkError(CHUNK_ERROR, '/usage', env), false);
    assert.equal(reloadOnChunkError(CHUNK_ERROR, '/usage', env), false);
    assert.equal(log.reloads, 1, 'no second reload, however often it fails');
  });

  it('keeps one flag per address', () => {
    const { env, log } = environment(memoryStorage());
    assert.equal(reloadOnChunkError(CHUNK_ERROR, '/usage', env), true);
    assert.equal(reloadOnChunkError(CHUNK_ERROR, '/history', env), true);
    assert.equal(log.reloads, 2);
  });

  it('does nothing for an error that is not a chunk failure', () => {
    const { env, log } = environment(memoryStorage());
    assert.equal(reloadOnChunkError(new Error('NG04002: Cannot match any routes'), '/usage', env), false);
    assert.equal(log.reloads, 0);
    assert.deepEqual(log.replaced, []);
  });

  it('does not reload with no usable storage', () => {
    for (const storage of [() => null, () => { throw new Error('SecurityError'); }, () => ({ getItem: () => null, setItem: () => {} })]) {
      const { env, log } = environment(null);
      env.storage = storage;
      assert.equal(reloadOnChunkError(CHUNK_ERROR, '/usage', env), false);
      assert.equal(log.reloads, 0);
      assert.deepEqual(log.replaced, []);
    }
  });

  it('never throws, whatever the browser objects do', () => {
    const { env } = environment(memoryStorage());
    env.location.reload = () => { throw new Error('blocked'); };
    assert.equal(reloadOnChunkError(CHUNK_ERROR, '/usage', env), false);
  });
});

describe('the wiring', () => {
  it('app.config.ts gives the router the handler', () => {
    const config = readFileSync(join(here, '..', 'src', 'app', 'app.config.ts'), 'utf8');
    assert.match(config, /withNavigationErrorHandler\(\(failed\) => \{\s*reloadForChunkError\(failed\.error, failed\.url\);\s*\}\)/);
    assert.match(config, /import \{ reloadForChunkError \} from '\.\/shared\/chunk-reload';/);
  });
});
