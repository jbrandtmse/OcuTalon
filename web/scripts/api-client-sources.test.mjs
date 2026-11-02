// Tests the shape of the page's one typed API client (Story 10.3; AD-13, AD-29; DW-231), which no unit of a view model can see: the three methods that
// the Telegram pairing and Break the feed need call the verbs, addresses and bodies that the server's routes take, `inject(HttpClient)` is in
// api/api-client.ts and nowhere else, the second client of Story 4.4 (feed/break-feed-api.ts) is gone, and the Break the feed box calls
// ApiClient.breakFeed(). The browser envelope (Content-Type and X-OcuTalon-Request) is added by the one interceptor to every POST, PUT, PATCH
// and DELETE, so a client that built its own requests would lose it; this keeps the page to one client. The browser cases (e2e/api/pairing.spec.ts
// and the demo path) pin what the running routes do; this reads the sources. It also pins the two Telegram parts of the demo path
// (e2e/demo-path/telegram-page.spec.ts and telegram-approval.spec.ts): each exists, declares one not-built part that names the Lane A story
// that replaces it, and is a part that demo-path-summary.mjs accepts for its step.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { stepOfFile } from './demo-path-summary.mjs';
import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const files = sourceFiles(app, ['.ts']);

const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

/** The code of one method of the client: from its name to the closing brace at the method's own indent. */
const method = (source, name) => {
  const found = new RegExp(`\\n  ${name}\\([^)]*\\)[^{]*\\{\\n([\\s\\S]*?)\\n  \\}\\n`).exec(source.code);
  assert.ok(found, `ApiClient has the method ${name}`);
  return found[1].trim();
};

const client = file('api/api-client.ts');
const types = file('api/api-types.ts');

describe('the three methods', () => {
  it('pairingCode() is a POST of {} to /pairing/code that answers the PairingCode', () => {
    assert.equal(method(client, 'pairingCode'), 'return this.http.post<PairingCode>(`${BASE}/pairing/code`, {});');
  });

  it('unpair() is a DELETE of /pairing with the body {} that answers the UnpairDone', () => {
    assert.equal(method(client, 'unpair'), 'return this.http.delete<UnpairDone>(`${BASE}/pairing`, { body: {} });');
  });

  it('breakFeed() is a POST of {} to /demo/break-feed that answers the BreakFeedSent', () => {
    assert.equal(method(client, 'breakFeed'), 'return this.http.post<BreakFeedSent>(`${BASE}/demo/break-feed`, {});');
  });

  it('BASE is /ocutalon/api/v1, so the three addresses are those of the server routes', () => {
    assert.match(client.code, /const BASE = '\/ocutalon\/api\/v1';/);
  });

  it('none of the three names a session or builds its own headers: the interceptor adds the envelope', () => {
    for (const name of ['pairingCode', 'unpair', 'breakFeed']) {
      const code = method(client, name);
      assert.doesNotMatch(code, /sessionRef|headers|X-OcuTalon|Content-Type/i, name);
    }
  });
});

describe('the answer types', () => {
  it('PairingCode holds the code and its expiry, UnpairDone the result done, BreakFeedSent the state sent and its start', () => {
    assert.match(types.code, /export interface PairingCode \{\s*code: string;\s*expiresAt: string;\s*\}/);
    assert.match(types.code, /export interface UnpairDone \{\s*result: 'done';\s*\}/);
    assert.match(types.code, /export interface BreakFeedSent \{\s*state: 'sent';\s*startedAt: string;\s*\}/);
  });

  it('the client imports all three from api-types.ts', () => {
    const imported = /import type \{([^}]*)\} from '\.\/api-types';/.exec(client.code);
    assert.ok(imported, 'the client imports its types from api-types.ts');
    for (const name of ['PairingCode', 'UnpairDone', 'BreakFeedSent']) assert.match(imported[1], new RegExp(`\\b${name}\\b`), name);
  });

  it('TelegramState names its server source in a doc comment', () => {
    assert.match(types.text, /\/\*\*[^]*?Web\.Api\.StateBody[^]*?StatusMark\.RecordTelegram[^]*?\*\/\s*export interface TelegramState/);
  });
});

describe('one typed client (DW-231)', () => {
  it('inject(HttpClient) is in api/api-client.ts and in no other source', () => {
    const injecting = files.filter((one) => /inject\(\s*HttpClient\s*\)/.test(one.code)).map((one) => one.name);
    assert.deepEqual(injecting, ['api/api-client.ts']);
  });

  it('no other source imports HttpClient for a call of its own', () => {
    const importing = files.filter((one) => /import\s*\{[^}]*\bHttpClient\b[^}]*\}\s*from\s*'@angular\/common\/http'/.test(one.code)).map((one) => one.name);
    assert.deepEqual(importing, ['api/api-client.ts']);
  });

  it('feed/break-feed-api.ts is gone, and nothing names it or BreakFeedApi', () => {
    assert.equal(existsSync(join(app, 'feed', 'break-feed-api.ts')), false);
    assert.deepEqual(files.filter((one) => /break-feed-api|BreakFeedApi/.test(one.code)).map((one) => one.name), []);
  });

  it('the Break the feed box injects ApiClient and presses through breakFeed()', () => {
    const box = file('feed/break-feed-box.ts');
    assert.match(box.code, /import \{ ApiClient \} from '\.\.\/api\/api-client';/);
    assert.match(box.code, /private readonly api = inject\(ApiClient\);/);
    assert.match(box.code, /return this\.api\.breakFeed\(\)\.pipe\(/);
    assert.doesNotMatch(box.code, /\.press\(\)/);
  });

  it('the client has no other method that posts to the break-feed address', () => {
    assert.equal((client.code.match(/demo\/break-feed/g) ?? []).length, 1);
  });
});

describe('the Telegram parts of the demo path', () => {
  const e2e = join(here, '..', 'e2e', 'demo-path');
  const parts = [
    ['telegram-page.spec.ts', 'page', 0, '12.4'],
    ['telegram-approval.spec.ts', 'approval', 4, '12.7'],
  ];

  for (const [name, step, index, story] of parts) {
    it(`${name} declares one not-built part, owned by Story ${story}, and is a part of the ${step} step`, () => {
      const code = readFileSync(join(e2e, name), 'utf8');
      assert.match(code, /import \{ notBuilt \} from '\.\/not-built';/);
      assert.equal((code.match(/\bnotBuilt\(/g) ?? []).length, 1, 'one declaration');
      assert.match(code, new RegExp(`^notBuilt\\('[^']+', '${story.replace('.', '\\.')}'\\);$`, 'm'));
      assert.doesNotMatch(code, /\btest\(|\btest\.(skip|only)\(/, 'no test of its own yet: Lane A replaces the call');
      assert.deepEqual(stepOfFile(name), { index, numbered: false });
    });
  }
});
