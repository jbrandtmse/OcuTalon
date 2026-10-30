// Source ratchets for leaving the page (Story 16.4; AD-13): what the page's code must never contain, and the few places where the clauses of
// the story's Always list live in the code, so that a change that breaks one fails here at once, before a browser unit is built.
//   - nothing the page ships registers a handler for pagehide, beforeunload, unload or visibilitychange, or sends a beacon: a reload,
//     a closed tab and a hidden tab sign nothing out (the live case L1 pins the reload);
//   - IRISLogout is named only by the session gate: as a same-origin request for the group sign-out, and, on a local install, as the
//     address the page goes to when the sign-out call fails; the online demo never navigates to it (the splash's form would carry it);
//   - the group sign-out waits at most SIGN_OUT_LIMIT_MS (3 s) and the page leaves whatever it answers;
//   - the idle cap counts a key press and a click anywhere in the document (capture phase) and a message the chat outbox sends, and
//     nothing else: no pointer movement, scroll, focus or poll, and it is started in one place;
//   - every new branch runs on the online demo's flag only (the loaded snapshot's onlineDemo): the cap's start, the gate's exits, the
//     live state's epoch guard and the header's Sign out dialog.
// The scan reads the code of the sources without their comments (source-files.mjs), so a comment may name any of these words.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const files = sourceFiles(join(here, '..', 'src'), ['.ts', '.js', '.html']);
const fileNamed = (name) => {
  const found = files.find((file) => file.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};
const gate = fileNamed('app/session/session-gate.ts');

/** The text of the first method of the gate whose declaration starts with `head`, up to its closing brace at the class's indent. */
function methodOf(code, head) {
  const start = code.indexOf(head);
  assert.ok(start >= 0, `${head} is in the code`);
  const end = code.indexOf('\n  }\n', start);
  return code.slice(start, end < 0 ? undefined : end);
}

/** A page that is left: the events whose handlers must not exist, and the beacon. */
const LEAVING = /['"`](?:pagehide|beforeunload|unload|visibilitychange)['"`]|\bon(?:pagehide|beforeunload|unload|visibilitychange)\b|\bsendBeacon\b/;

describe('leaving the page signs nothing out (AC 1)', () => {
  it('the scan finds what it looks for (a control on samples) and covers the page, the sign-in script and the index', () => {
    for (const sample of [
      "window.addEventListener('pagehide', leave)",
      'document.addEventListener("visibilitychange", leave)',
      "globalThis.addEventListener(`beforeunload`, leave)",
      "addEventListener('unload', leave)",
      'window.onunload = leave',
      'navigator.sendBeacon("/x")',
    ]) {
      assert.ok(LEAVING.test(sample), sample);
    }
    assert.ok(!LEAVING.test("globalThis.document.addEventListener('keydown', touch, true)"));
    const names = files.map((file) => file.name);
    for (const expected of ['app/app.ts', 'app/session/session-gate.ts', 'app/live/live-state.ts', 'main.ts', 'index.html', 'signin/signin.js']) {
      assert.ok(names.includes(expected), `${expected} is scanned`);
    }
  });

  it('no source registers a handler for pagehide, beforeunload, unload or visibilitychange, or sends a beacon', () => {
    assert.deepEqual(
      files.filter((file) => LEAVING.test(file.code)).map((file) => file.name),
      [],
    );
  });

  it('IRISLogout is named by the session gate only: a fetch for the group sign-out, and the local install\'s address after a failed call', () => {
    assert.deepEqual(
      files.filter((file) => file.code.includes('IRISLogout')).map((file) => file.name),
      ['app/session/session-gate.ts'],
    );
    const lines = gate.code.split('\n').filter((line) => line.includes('IRISLogout'));
    assert.equal(lines.length, 2, 'two places');
    assert.ok(lines.some((line) => /globalThis\.fetch\(/.test(line)), 'one is the request of the group sign-out');
    const navigation = lines.filter((line) => /location\.replace\(/.test(line));
    assert.equal(navigation.length, 1, 'the other is a navigation');
    const signOut = methodOf(gate.code, 'signOut(): void {');
    const online = signOut.indexOf('if (online) {');
    const local = signOut.indexOf('IRISLogout');
    assert.ok(online >= 0 && local > online, 'and it comes after the online branch, which returns first');
    assert.ok(signOut.slice(online, local).includes('return;'), 'the online branch returns before the navigation');
  });
});

describe('the group sign-out is bounded (AC 3, AC 4)', () => {
  it('waits SIGN_OUT_LIMIT_MS = 3000 at most, with an abort signal on the request, and leaves whatever it answers', () => {
    assert.match(gate.code, /export const SIGN_OUT_LIMIT_MS = 3000;/);
    const group = methodOf(gate.code, 'private async groupSignOut(): Promise<void> {');
    assert.match(group, /signal:\s*AbortSignal\.timeout\(SIGN_OUT_LIMIT_MS\)/);
    assert.match(group, /credentials:\s*'same-origin'/);
    assert.match(group, /catch\s*\{/, 'a failed or aborted request is caught');
    const leave = methodOf(gate.code, 'private leave(exit: Exit): void {');
    assert.match(leave, /void this\.groupSignOut\(\)\.then\(\(\) => globalThis\.location\.replace\(address\)\)/, 'and the page leaves after it, whatever it came to');
  });
});

describe('the idle cap counts a key press, a click and a sent message only (AC 3)', () => {
  it('registers exactly two document listeners, keydown and click, in the capture phase', () => {
    const registered = [...gate.code.matchAll(/addEventListener\(\s*'(\w+)'\s*,\s*(\w+)\s*,\s*(\w+)\s*\)/g)].map((match) => `${match[1]}:${match[2]}:${match[3]}`);
    assert.deepEqual(registered, ['keydown:touch:true', 'click:touch:true']);
    assert.equal((gate.code.match(/addEventListener\(/g) ?? []).length, 2, 'and no other listener');
    assert.match(gate.code, /globalThis\.document\.addEventListener\('keydown'/, 'on the document');
  });

  it('touches the cap from one function, which the two listeners and the outbox\'s send count use', () => {
    assert.equal((gate.code.match(/\.touch\(\)/g) ?? []).length, 1, 'one call of touch()');
    assert.match(gate.code, /const touch = \(\): void => this\.cap\.touch\(\);/);
    assert.match(gate.code, /this\.outbox\.sendCount\(\);\s*untracked\(touch\);/, 'a message the outbox sends is activity');
  });

  it('starts the cap in one place, from the snapshot, and stops it with the live state', () => {
    assert.equal((gate.code.match(/this\.cap\.start\(/g) ?? []).length, 1, 'one start');
    assert.equal((gate.code.match(/new IdleCap\(/g) ?? []).length, 1, 'one cap');
    assert.deepEqual(
      files.filter((file) => /\bIdleCap\b/.test(file.code)).map((file) => file.name),
      ['app/session/idle-cap.ts', 'app/session/session-gate.ts'],
    );
    assert.match(gate.code, /if \(this\.live\.halted\(\)\) \{\s*untracked\(\(\) => this\.cap\.stop\(\)\);/, 'a halted live state stops the cap');
  });
});

describe('every new branch runs on the online demo\'s flag only (the flag decides)', () => {
  it('the gate\'s idle cap, 401 exit and Sign out follow the loaded snapshot\'s onlineDemo', () => {
    assert.match(methodOf(gate.code, 'private online(): boolean {'), /return this\.live\.snapshot\(\)\?\.onlineDemo === true;/);
    assert.match(methodOf(gate.code, 'private startIdle('), /snapshot\?\.onlineDemo !== true/, 'the cap starts only with the flag on');
    const unauthorized = methodOf(gate.code, 'onSignedOut(): void {');
    assert.ok(unauthorized.indexOf('this.online()') > unauthorized.indexOf('this.reset.enterIfDue()'), 'the reset check stays first');
    assert.match(unauthorized, /if \(this\.online\(\)\) \{\s*this\.leave\('unauthorized'\);\s*return;\s*\}/);
    assert.match(unauthorized, /location\.replace\(`\$\{HOME\}\?signedOut=1\$\{globalThis\.location\.hash\}`\)/, 'a local install keeps the signed-out page');
    assert.match(methodOf(gate.code, 'signOut(): void {'), /const online = this\.online\(\);/);
  });

  it('the live state\'s epoch guard and the header\'s dialog follow it too', () => {
    const live = fileNamed('app/live/live-state.ts');
    assert.match(methodOf(live.code, 'private otherEpoch(epoch: string): boolean {'), /this\.snapshot\(\)\?\.onlineDemo === true/);
    const header = fileNamed('app/header/header.ts');
    assert.match(methodOf(header.code, 'protected signOut(): void {'), /if \(this\.live\.snapshot\(\)\?\.onlineDemo === true\) \{[\s\S]*this\.dialogs\.open\(SignOutDialog[\s\S]*return;\s*\}\s*this\.gate\.signOut\(\);/);
  });
});
