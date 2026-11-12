// Tests of the fake OAuth2 authorization server of the CI mock (Story 21.3; AD-22): the authorize step (redirect with a code and the same state, the
// recorded request, deny mode), the token step (the dummy client pair, one use of a code, the redirect address, the error mode, other grants), the
// control routes, and the rule that no secret and no token value is ever in the state. Each test starts its own server on 127.0.0.1 with the OS picking
// the ports and stops it afterwards (helpers.mjs). The client pair is built at run time. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { spawnServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, '..', 'server.mjs');
const CLIENT_ID = `client-${'a'.repeat(8)}.example`;
const SECRET = `sec-${'z'.repeat(12)}-oauth`;
const BACK = 'http://127.0.0.1:52773/csp/sys/oauth2/OAuth2.Response.cls';

async function withMock(fn) {
  const s = spawnServer(SERVER, ['--port', '0', '--pop3-port', '0', '--smtp-port', '0']);
  try {
    const http = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    const base = `http://127.0.0.1:${http.port}/_mock/oauth`;
    const control = async (route, body, verb = 'POST') => {
      const res = await fetch(`${base}/${route}`, { method: verb, headers: body === undefined ? {} : { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
      return { status: res.status, json: await res.json() };
    };
    const authorize = (provider, params) => fetch(`${base}/${provider}/authorize?${new URLSearchParams(params)}`, { redirect: 'manual' });
    const token = async (provider, form) => {
      const res = await fetch(`${base}/${provider}/token`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form).toString() });
      return { status: res.status, json: await res.json() };
    };
    await fn({ control, authorize, token, base, s });
  } finally {
    s.child.kill();
    await s.exited;
  }
}

const query = { client_id: CLIENT_ID, redirect_uri: BACK, scope: 'https://mail.google.com/', response_type: 'code', state: 'st-1', access_type: 'offline', prompt: 'consent' };

async function consent(h, provider = 'google') {
  const res = await h.authorize(provider, query);
  return new URL(res.headers.get('location'));
}

test('authorize redirects to the redirect address with a consent code and the same state, and records the request', async () => {
  await withMock(async (h) => {
    const res = await h.authorize('google', query);
    assert.equal(res.status, 302);
    const target = new URL(res.headers.get('location'));
    assert.equal(`${target.origin}${target.pathname}`, BACK);
    assert.match(target.searchParams.get('code'), /^consent-[0-9a-f]{24}$/);
    assert.equal(target.searchParams.get('state'), 'st-1');
    const { json } = await h.control('state', undefined, 'GET');
    assert.deepEqual(json.authorize, [{ provider: 'google', clientId: CLIENT_ID, redirectUri: BACK, scope: 'https://mail.google.com/', responseType: 'code', hasState: true, pkce: false, extra: { access_type: 'offline', prompt: 'consent' } }]);
  });
});

test('authorize records a PKCE challenge without keeping its value, and refuses a request with no redirect address', async () => {
  await withMock(async (h) => {
    await h.authorize('microsoft', { ...query, code_challenge: 'abc', code_challenge_method: 'S256' });
    const { json } = await h.control('state', undefined, 'GET');
    assert.equal(json.authorize[0].pkce, true);
    assert.equal(JSON.stringify(json).includes('abc'), false);
    const bad = await h.authorize('google', { client_id: CLIENT_ID });
    assert.equal(bad.status, 400);
  });
});

test('deny mode answers error=access_denied with the state and no code', async () => {
  await withMock(async (h) => {
    assert.equal((await h.control('mode', { consent: 'deny' })).status, 200);
    const target = await consent(h);
    assert.equal(target.searchParams.get('error'), 'access_denied');
    assert.equal(target.searchParams.get('state'), 'st-1');
    assert.equal(target.searchParams.get('code'), null);
  });
});

test('token gives fresh dummy tokens for the dummy pair and a code once, and the state holds no secret and no token', async () => {
  await withMock(async (h) => {
    await h.control('client', { clientId: CLIENT_ID, clientSecret: SECRET });
    const code = (await consent(h)).searchParams.get('code');
    const form = { grant_type: 'authorization_code', code, redirect_uri: BACK, client_id: CLIENT_ID, client_secret: SECRET };
    const first = await h.token('google', form);
    assert.equal(first.status, 200);
    assert.match(first.json.access_token, /^mock-at-/);
    assert.match(first.json.refresh_token, /^mock-rt-/);
    assert.equal(first.json.token_type, 'Bearer');
    assert.equal(first.json.scope, 'https://mail.google.com/');
    const again = await h.token('google', form);
    assert.equal(again.status, 400);
    assert.equal(again.json.error, 'invalid_grant');
    const { json } = await h.control('state', undefined, 'GET');
    assert.equal(json.issued, 1);
    assert.deepEqual(json.token.map((t) => [t.secretMatched, t.codeOk]), [[true, true], [true, false]]);
    const text = JSON.stringify(json);
    assert.equal(text.includes(SECRET), false);
    assert.equal(text.includes(first.json.access_token), false);
    assert.equal(text.includes(first.json.refresh_token), false);
  });
});

test('token refuses a wrong secret, a wrong redirect address, a code of the other provider, and other grants', async () => {
  await withMock(async (h) => {
    await h.control('client', { clientId: CLIENT_ID, clientSecret: SECRET });
    const code = (await consent(h)).searchParams.get('code');
    const base = { grant_type: 'authorization_code', code, redirect_uri: BACK, client_id: CLIENT_ID, client_secret: SECRET };
    assert.equal((await h.token('google', { ...base, client_secret: 'wrong' })).status, 401);
    assert.equal((await h.token('google', { ...base, client_id: 'other' })).status, 401);
    assert.equal((await h.token('google', { ...base, redirect_uri: `${BACK}x` })).status, 400);
    assert.equal((await h.token('microsoft', base)).status, 400);
    assert.equal((await h.token('google', { ...base, grant_type: 'refresh_token' })).status, 400);
    assert.equal((await h.token('google', { ...base, code: 'not-a-consent-code' })).status, 400);
    assert.equal((await h.token('google', base)).status, 200);
  });
});

test('a consent code that the authorize step never issued is accepted once, with an empty scope', async () => {
  await withMock(async (h) => {
    await h.control('client', { clientId: CLIENT_ID, clientSecret: SECRET });
    const form = { grant_type: 'authorization_code', code: 'consent-made-by-a-browser-test', redirect_uri: BACK, client_id: CLIENT_ID, client_secret: SECRET };
    const first = await h.token('google', form);
    assert.equal(first.status, 200);
    assert.equal(first.json.scope, '');
    assert.equal((await h.token('google', form)).status, 400);
  });
});

test('with no client configured every token request is invalid_client', async () => {
  await withMock(async (h) => {
    const code = (await consent(h)).searchParams.get('code');
    const res = await h.token('google', { grant_type: 'authorization_code', code, redirect_uri: BACK, client_id: CLIENT_ID, client_secret: SECRET });
    assert.equal(res.status, 401);
  });
});

test('token mode error answers 400 invalid_request and keeps the code usable', async () => {
  await withMock(async (h) => {
    await h.control('client', { clientId: CLIENT_ID, clientSecret: SECRET });
    await h.control('mode', { token: 'error' });
    const code = (await consent(h)).searchParams.get('code');
    const form = { grant_type: 'authorization_code', code, redirect_uri: BACK, client_id: CLIENT_ID, client_secret: SECRET };
    const failed = await h.token('google', form);
    assert.equal(failed.status, 400);
    assert.equal(failed.json.error, 'invalid_request');
    await h.control('mode', { token: 'ok' });
    assert.equal((await h.token('google', form)).status, 200);
  });
});

test('the control routes validate their bodies, reset clears everything, and unknown paths are 404', async () => {
  await withMock(async (h) => {
    assert.equal((await h.control('client', { clientId: '', clientSecret: SECRET })).status, 400);
    assert.equal((await h.control('client', { clientId: CLIENT_ID })).status, 400);
    assert.equal((await h.control('mode', { consent: 'maybe' })).status, 400);
    assert.equal((await h.control('mode', { token: 'maybe' })).status, 400);
    await h.control('client', { clientId: CLIENT_ID, clientSecret: SECRET });
    await h.control('mode', { consent: 'deny' });
    await consent(h);
    await h.control('reset');
    const { json } = await h.control('state', undefined, 'GET');
    assert.deepEqual(json, { authorize: [], token: [], issued: 0, client: { clientId: '', secretSet: false }, mode: { consent: 'allow', token: 'ok' } });
    assert.equal((await h.control('nowhere')).status, 404);
    assert.equal((await h.control('state', undefined, 'POST')).status, 404);
    const res = await fetch(`${h.base}/google/other`);
    assert.equal(res.status, 404);
  });
});
