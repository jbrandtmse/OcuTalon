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
//                    unsupported_grant_type. A code that this server never issued is accepted once, so that a test that answers the authorize
//                    step itself (a browser test) can still sign in against the real token step
//                    grant_type=refresh_token (Story 21.8): a refresh token that this server issued and that is not revoked, with the configured client
//                    pair, answers 200 JSON {access_token, token_type:"Bearer", expires_in, scope} with a fresh access token and no refresh_token (the client
//                    keeps the one it has); a bad pair is 401 invalid_client; an unknown or revoked refresh token, or one of the other provider, is 400
//                    invalid_grant; token mode "error" answers 400 invalid_request. For microsoft the scope in every token answer leaves out
//                    offline_access (inference from Microsoft's documentation: the token answer lists the scopes that were granted for the resource)
// Control, under /_mock/oauth/:
//   POST client  {"clientId","clientSecret"}   the dummy pair that token accepts. The secret is kept in memory for the comparison only: no
//                                              answer, state or log line holds it
//   POST mode    {"consent":"allow"|"deny","token":"ok"|"error","expiresIn":1..3600}  (each member optional). expiresIn is the expires_in of the
//                access tokens issued afterwards (default 3600); the stubs accept a token only until that many seconds (plus one second of grace) have passed
//   POST revoke  every access and refresh token issued so far becomes invalid (as when the user withdraws the grant at the provider); tokens
//                issued afterwards are valid
//   POST reset   no client, no record, no token, allow/ok/3600
//   GET  state   {"authorize":[{provider,clientId,redirectUri,scope,responseType,hasState,pkce,extra}],
//                 "token":[{provider,grantType,clientId,secretMatched,codeOk,refreshOk,redirectUri}],"issued":n,"refreshed":n,"revoked":n,
//                 "client":{"clientId","secretSet"},"mode":{...}}
//                issued counts the code exchanges that gave tokens, refreshed the refresh grants that gave a fresh access token, revoked the
//                revoke calls. No secret and no token value is ever in it. Any other path is a 404.
// Two functions serve the stubs: parseXoauth2(base64) answers {user, token} for an XOAUTH2 initial response (user=<u>, ^A, auth=Bearer <t>, ^A^A) and
// null for anything else, and createOAuth().checkAccessToken(token) answers true only for an access token that this server issued and that is neither
// revoked nor past its expires_in plus a grace of one second (a client that counts expiry in whole seconds, as IRIS's OAuth2 client does, thinks a token valid for
// up to a second longer than expires_in, and must never be refused a token that it still thinks valid).

import crypto from 'node:crypto';

export const PROVIDERS = ['google', 'microsoft'];
export const CONSENT_MODES = ['allow', 'deny'];
export const TOKEN_MODES = ['ok', 'error'];
export const MAX_RECORDS = 100;
export const EXPIRES_MIN = 1;
export const EXPIRES_MAX = 3600;
export const EXPIRY_GRACE_MS = 1000;
const BASE = '/_mock/oauth/';
const XOAUTH2 = /^user=([^\x01]*)\x01auth=Bearer ([^\x01]+)\x01\x01$/;
const KNOWN = new Set(['client_id', 'redirect_uri', 'scope', 'response_type', 'state', 'code_challenge', 'code_challenge_method']);

function json(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text), 'cache-control': 'no-store' });
  res.end(text);
}

// parseXoauth2(base64): {user, token} of an XOAUTH2 initial response, or null when it is not one.
export function parseXoauth2(base64) {
  if (typeof base64 !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64.trim())) return null;
  const match = XOAUTH2.exec(Buffer.from(base64.trim(), 'base64').toString('utf8'));
  return match === null ? null : { user: match[1], token: match[2] };
}

// The scope of a token answer: microsoft leaves out offline_access.
function grantedScope(provider, scope) {
  return provider === 'microsoft' ? scope.split(' ').filter((s) => s !== 'offline_access').join(' ') : scope;
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
  let mode = { consent: 'allow', token: 'ok', expiresIn: EXPIRES_MAX };
  let authorize = [];
  let token = [];
  let codes = new Map();
  let used = new Set();
  let issued = 0;
  let refreshed = 0;
  let revoked = 0;
  let accessTokens = new Map();
  let refreshTokens = new Map();

  function reset() {
    client = null;
    mode = { consent: 'allow', token: 'ok', expiresIn: EXPIRES_MAX };
    authorize = [];
    token = [];
    codes = new Map();
    used = new Set();
    issued = 0;
    refreshed = 0;
    revoked = 0;
    accessTokens = new Map();
    refreshTokens = new Map();
  }

  function checkAccessToken(value) {
    const known = accessTokens.get(value);
    return known !== undefined && !known.revoked && Date.now() < known.expiresAt + EXPIRY_GRACE_MS;
  }

  function newAccessToken(provider) {
    const value = `mock-at-${randomText()}`;
    accessTokens.set(value, { provider, revoked: false, expiresAt: Date.now() + mode.expiresIn * 1000 });
    return value;
  }

  function state() {
    return {
      authorize: authorize.map((a) => ({ ...a, extra: { ...a.extra } })),
      token: token.map((t) => ({ ...t })),
      issued,
      refreshed,
      revoked,
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
    const known = refreshTokens.get(form.get('refresh_token') || '');
    const refreshOk = grantType === 'refresh_token' && known !== undefined && known.provider === provider && !known.revoked;
    push(token, { provider, grantType, clientId, secretMatched, codeOk, refreshOk, redirectUri: form.get('redirect_uri') || '' });
    if (grantType === 'refresh_token') {
      doRefresh(provider, res, secretMatched, refreshOk, known);
      return;
    }
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
    const scope = entry === undefined ? '' : grantedScope(provider, entry.scope);
    const refreshToken = `mock-rt-${randomText()}`;
    refreshTokens.set(refreshToken, { provider, revoked: false, scope });
    json(res, 200, { access_token: newAccessToken(provider), refresh_token: refreshToken, token_type: 'Bearer', expires_in: mode.expiresIn, scope });
  }

  function doRefresh(provider, res, secretMatched, refreshOk, known) {
    if (!secretMatched) {
      json(res, 401, { error: 'invalid_client' });
      return;
    }
    if (!refreshOk) {
      json(res, 400, { error: 'invalid_grant' });
      return;
    }
    if (mode.token === 'error') {
      json(res, 400, { error: 'invalid_request' });
      return;
    }
    refreshed += 1;
    json(res, 200, { access_token: newAccessToken(provider), token_type: 'Bearer', expires_in: mode.expiresIn, scope: known.scope });
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
    if (route === 'revoke') {
      for (const entry of accessTokens.values()) entry.revoked = true;
      for (const entry of refreshTokens.values()) entry.revoked = true;
      revoked += 1;
      json(res, 200, { revoked });
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
      const badExpiry = data !== null && data.expiresIn !== undefined && !(Number.isInteger(data.expiresIn) && data.expiresIn >= EXPIRES_MIN && data.expiresIn <= EXPIRES_MAX);
      if (data === null || (data.consent !== undefined && !CONSENT_MODES.includes(data.consent)) || (data.token !== undefined && !TOKEN_MODES.includes(data.token)) || badExpiry) {
        json(res, 400, { error: `CI mock: consent must be one of ${CONSENT_MODES.join(', ')}, token one of ${TOKEN_MODES.join(', ')} and expiresIn a whole number from ${EXPIRES_MIN} to ${EXPIRES_MAX}` });
        return;
      }
      if (data.consent !== undefined) mode.consent = data.consent;
      if (data.token !== undefined) mode.token = data.token;
      if (data.expiresIn !== undefined) mode.expiresIn = data.expiresIn;
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

  return { handle, handleControl, state, reset, checkAccessToken };
}
