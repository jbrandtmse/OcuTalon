// The fake OAuth2 authorization server of the CI mock (Story 21.3; AD-22, Lane B mock behaviour): the authorize and token endpoints of a mail
// provider, for IRIS's OAuth2 client to sign in against. It is a test fixture: no real provider, no real client ID, no real secret, no real
// token. createOAuth() returns {handle(req, res, pathname, raw), handleControl(req, res, pathname, raw), state(), reset()}; server.mjs routes
// everything under /_mock/oauth/ to handle, with raw the request body as text.
// Per provider (google or microsoft), under /_mock/oauth/<provider>/:
//   GET  authorize   the consent step. It records client_id, redirect_uri, scope, response_type, the other query parameters, and whether a state
//                    and a PKCE challenge came, then answers 302 to redirect_uri with code=consent-<random> and the same state, or with
//                    error=access_denied (and the state) in deny mode. A request with no redirect_uri is a 400
//   POST token       the code exchange (application/x-www-form-urlencoded, client_secret_post). grant_type=authorization_code with a code that starts
//                    with consent- and was not used before, the configured client_id and client_secret, and (when the authorize step issued the code)
//                    the redirect_uri of that step answers 200 JSON {access_token, refresh_token, token_type:"Bearer", expires_in, scope} with fresh
//                    dummy values; a client that does not match is 401 invalid_client; a code that does not start with consent-, was used, or was issued
//                    for another redirect_uri is 400 invalid_grant; token mode "error" answers 400 invalid_request; any other grant_type is 400
//                    unsupported_grant_type (refresh and revoke are Story 21.8's). A code that this server never issued is accepted once, so that a
//                    test that answers the authorize step itself (a browser test) can still sign in against the real token step
// Control, under /_mock/oauth/:
//   POST client  {"clientId","clientSecret"}   the dummy pair that token accepts. The secret is kept in memory for the comparison only: no
//                                              answer, state or log line holds it
//   POST mode    {"consent":"allow"|"deny","token":"ok"|"error"}  (each member optional)
//   POST reset   no client, no record, allow/ok
//   GET  state   {"authorize":[{provider,clientId,redirectUri,scope,responseType,hasState,pkce,extra}],
//                 "token":[{provider,grantType,clientId,secretMatched,codeOk,redirectUri}],"issued":n,"client":{"clientId","secretSet"},"mode":{...}}
//                No secret and no token value is ever in it. Any other path is a 404.

import crypto from 'node:crypto';

export const PROVIDERS = ['google', 'microsoft'];
export const CONSENT_MODES = ['allow', 'deny'];
export const TOKEN_MODES = ['ok', 'error'];
export const MAX_RECORDS = 100;
const BASE = '/_mock/oauth/';
const KNOWN = new Set(['client_id', 'redirect_uri', 'scope', 'response_type', 'state', 'code_challenge', 'code_challenge_method']);

function json(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text), 'cache-control': 'no-store' });
  res.end(text);
}

function randomText() {
  return crypto.randomBytes(12).toString('hex');
}

function push(list, record) {
  list.push(record);
  while (list.length > MAX_RECORDS) list.shift();
}

export function createOAuth() {
  let client = null;
  let mode = { consent: 'allow', token: 'ok' };
  let authorize = [];
  let token = [];
  let codes = new Map();
  let used = new Set();
  let issued = 0;

  function reset() {
    client = null;
    mode = { consent: 'allow', token: 'ok' };
    authorize = [];
    token = [];
    codes = new Map();
    used = new Set();
    issued = 0;
  }

  function state() {
    return {
      authorize: authorize.map((a) => ({ ...a, extra: { ...a.extra } })),
      token: token.map((t) => ({ ...t })),
      issued,
      client: { clientId: client === null ? '' : client.clientId, secretSet: client !== null },
      mode: { ...mode },
    };
  }

  function doAuthorize(provider, req, res) {
    const query = new URL(req.url || '/', 'http://mock').searchParams;
    const redirect = query.get('redirect_uri') || '';
    if (redirect === '') {
      json(res, 400, { error: 'invalid_request', error_description: 'redirect_uri is required' });
      return;
    }
    const extra = {};
    for (const [name, value] of query) if (!KNOWN.has(name)) extra[name] = value;
    push(authorize, {
      provider,
      clientId: query.get('client_id') || '',
      redirectUri: redirect,
      scope: query.get('scope') || '',
      responseType: query.get('response_type') || '',
      hasState: (query.get('state') || '') !== '',
      pkce: (query.get('code_challenge') || '') !== '',
      extra,
    });
    let target;
    try {
      target = new URL(redirect);
    } catch {
      json(res, 400, { error: 'invalid_request', error_description: 'redirect_uri is not a URL' });
      return;
    }
    if (mode.consent === 'deny') {
      target.searchParams.set('error', 'access_denied');
    } else {
      const code = `consent-${randomText()}`;
      codes.set(code, { provider, redirectUri: redirect, scope: query.get('scope') || '' });
      target.searchParams.set('code', code);
    }
    if ((query.get('state') || '') !== '') target.searchParams.set('state', query.get('state'));
    res.writeHead(302, { location: target.toString(), 'cache-control': 'no-store', 'content-length': 0 });
    res.end();
  }

  function doToken(provider, req, res, raw) {
    const form = new URLSearchParams(raw);
    const grantType = form.get('grant_type') || '';
    const clientId = form.get('client_id') || '';
    const given = form.get('client_secret') || '';
    const secretMatched = client !== null && clientId === client.clientId && given === client.clientSecret;
    const code = form.get('code') || '';
    const entry = codes.get(code);
    const codeOk =
      grantType === 'authorization_code' &&
      code.startsWith('consent-') &&
      !used.has(code) &&
      (entry === undefined || (entry.provider === provider && entry.redirectUri === (form.get('redirect_uri') || '')));
    push(token, { provider, grantType, clientId, secretMatched, codeOk, redirectUri: form.get('redirect_uri') || '' });
    if (grantType !== 'authorization_code') {
      json(res, 400, { error: 'unsupported_grant_type' });
      return;
    }
    if (!secretMatched) {
      json(res, 401, { error: 'invalid_client' });
      return;
    }
    if (!codeOk) {
      json(res, 400, { error: 'invalid_grant' });
      return;
    }
    if (mode.token === 'error') {
      json(res, 400, { error: 'invalid_request' });
      return;
    }
    used.add(code);
    issued += 1;
    json(res, 200, {
      access_token: `mock-at-${randomText()}`,
      refresh_token: `mock-rt-${randomText()}`,
      token_type: 'Bearer',
      expires_in: 3600,
      scope: entry === undefined ? '' : entry.scope,
    });
  }

  function parseBody(raw) {
    try {
      const data = JSON.parse(raw);
      return data !== null && typeof data === 'object' && !Array.isArray(data) ? data : null;
    } catch {
      return null;
    }
  }

  function handleControl(req, res, pathname, raw) {
    const route = pathname.slice(BASE.length);
    if (route === 'state' && req.method === 'GET') {
      json(res, 200, state());
      return;
    }
    if (req.method !== 'POST') {
      json(res, 404, { error: `CI mock: no route for ${req.method} ${pathname}` });
      return;
    }
    if (route === 'reset') {
      reset();
      json(res, 200, { ok: true });
      return;
    }
    const data = parseBody(raw);
    if (route === 'client') {
      if (data === null || typeof data.clientId !== 'string' || typeof data.clientSecret !== 'string' || data.clientId === '' || data.clientSecret === '') {
        json(res, 400, { error: 'CI mock: clientId and clientSecret must be non-empty strings' });
        return;
      }
      client = { clientId: data.clientId, clientSecret: data.clientSecret };
      json(res, 200, { clientId: client.clientId, secretSet: true });
      return;
    }
    if (route === 'mode') {
      if (data === null || (data.consent !== undefined && !CONSENT_MODES.includes(data.consent)) || (data.token !== undefined && !TOKEN_MODES.includes(data.token))) {
        json(res, 400, { error: `CI mock: consent must be one of ${CONSENT_MODES.join(', ')} and token one of ${TOKEN_MODES.join(', ')}` });
        return;
      }
      if (data.consent !== undefined) mode.consent = data.consent;
      if (data.token !== undefined) mode.token = data.token;
      json(res, 200, { ...mode });
      return;
    }
    json(res, 404, { error: `CI mock: no route for ${req.method} ${pathname}` });
  }

  function handle(req, res, pathname, raw) {
    const route = pathname.slice(BASE.length);
    const provider = route.split('/')[0];
    const step = route.split('/')[1];
    if (PROVIDERS.includes(provider) && route.split('/').length === 2) {
      if (step === 'authorize' && req.method === 'GET') {
        doAuthorize(provider, req, res);
        return;
      }
      if (step === 'token' && req.method === 'POST') {
        doToken(provider, req, res, raw);
        return;
      }
      json(res, 404, { error: `CI mock: no route for ${req.method} ${pathname}` });
      return;
    }
    handleControl(req, res, pathname, raw);
  }

  return { handle, handleControl, state, reset };
}
