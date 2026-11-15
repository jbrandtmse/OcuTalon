/**
 * The reload that answers a lazy page whose code can no longer be fetched (Story 36.7): an upgrade removes the previous build's hashed files from
 * the served folder, so a tab that was open across the upgrade asks for a chunk that is gone. The router's navigation error handler
 * (app.config.ts) hands the failure here. When it is a chunk load failure, one full page load of the target address follows, and a flag per address
 * in sessionStorage stops a second one: a chunk that is still missing after the reload leaves today's behaviour, and so does a browser whose
 * storage can't be used. No text is shown. A framework-free module with no imports and only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - isChunkLoadError: whether an error is a failed dynamic import (the messages of Chromium, Firefox and Safari, or a ChunkLoadError).
 * - claimReload: takes the flag of an address; true only for the first claim, and false whenever the storage is missing, throws or does not keep the flag.
 * - targetAddress: the page address of a router address, as the hash-based routing writes it.
 * - reloadOnChunkError: the whole decision, over the browser's objects passed in.
 */

/** The key of an address's flag in sessionStorage is this prefix and the address. */
export const CHUNK_RELOAD_PREFIX = 'ocutalon.chunkReload:';

const CHUNK_MESSAGE = /Failed to fetch dynamically imported module|error loading dynamically imported module|Importing a module script failed|Loading chunk \S+ failed/i;

/** The part of sessionStorage that the flag needs. */
export interface FlagStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** The parts of the browser that the reload needs: where the page is, its history entry and its storage (null when there is none). */
export interface ReloadEnvironment {
  location: { pathname: string; search: string; reload(): void };
  history: { state: unknown; replaceState(data: unknown, unused: string, url?: string | null): void };
  storage(): FlagStorage | null;
}

/** Whether an error is a failed fetch of a lazily loaded chunk. */
export function isChunkLoadError(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) {
    return false;
  }
  const { name, message } = error as { name?: unknown; message?: unknown };
  return name === 'ChunkLoadError' || (typeof message === 'string' && CHUNK_MESSAGE.test(message));
}

/** The page address of a router address such as /usage: the document's own path and query, then the hash. */
export function targetAddress(location: { pathname: string; search: string }, routerAddress: string): string {
  return `${location.pathname}${location.search}#${routerAddress}`;
}

/** Takes the flag of an address: true for the first claim, false when it is taken, and false when the storage is missing, throws or does not keep the flag. */
export function claimReload(storage: FlagStorage | null, address: string): boolean {
  try {
    if (!storage) {
      return false;
    }
    const key = CHUNK_RELOAD_PREFIX + address;
    if (storage.getItem(key) !== null) {
      return false;
    }
    storage.setItem(key, '1');
    return storage.getItem(key) === '1';
  } catch {
    return false;
  }
}

/**
 * Reloads the page at the target address once when the error is a chunk load failure: the history entry takes the target address (a hash change alone
 * would not reload), then the page loads again. Returns whether it reloaded. Nothing else happens, and nothing is thrown.
 */
export function reloadOnChunkError(error: unknown, routerAddress: string, env: ReloadEnvironment): boolean {
  if (!isChunkLoadError(error)) {
    return false;
  }
  let storage: FlagStorage | null = null;
  try {
    storage = env.storage();
  } catch {
    return false;
  }
  const address = targetAddress(env.location, routerAddress);
  if (!claimReload(storage, address)) {
    return false;
  }
  try {
    env.history.replaceState(env.history.state, '', address);
    env.location.reload();
  } catch {
    return false;
  }
  return true;
}

/** The handler of the router: the browser's own objects. */
export function reloadForChunkError(error: unknown, routerAddress: string): boolean {
  return reloadOnChunkError(error, routerAddress, {
    location: window.location,
    history: window.history,
    storage: () => window.sessionStorage,
  });
}
