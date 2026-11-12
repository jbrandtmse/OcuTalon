// Tests of the SMTP stub of the CI mock (Stories 21.6 and 21.8; AD-22): the commands, AUTH (PLAIN, LOGIN and XOAUTH2: accepted for an issued token,
// refused for an unknown, expired or revoked one and a malformed frame), the mail it keeps, the control routes, the failure modes, the
// rule that STARTTLS is never offered, and the rule that a password is never stored, logged or answered. Each test starts its own server on
// 127.0.0.1 with the OS picking the ports and stops it afterwards (helpers.mjs). The password is built at run time. Needs Node 24 and nothing else.

import assert from 'node:assert/strict';
import net from 'node:net';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { decodeWords, parse } from '../smtp.mjs';
import { oauthSession, spawnServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, '..', 'server.mjs');
const SECRET = `pw-${'q'.repeat(12)}-smtp`;

async function withStub(fn) {
  const s = spawnServer(SERVER, ['--port', '0', '--pop3-port', '0', '--smtp-port', '0']);
  try {
    const http = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    const smtp = JSON.parse(await s.waitFor((l) => l.includes('"event":"smtp"')));
    const base = `http://127.0.0.1:${http.port}`;
    const control = async (route, body, verb = 'POST') => {
      const res = await fetch(`${base}/_mock/smtp/${route}`, { method: verb, headers: body === undefined ? {} : { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
      return { status: res.status, json: await res.json() };
    };
    await fn({ control, port: smtp.port, s, oauth: oauthSession(base) });
  } finally {
    s.child.kill();
    await s.exited;
  }
}

// client(port): an SMTP client; send(line) answers the lines of one reply (the last one has a space after the code).
function client(port) {
  const socket = net.connect(port, '127.0.0.1');
  socket.setEncoding('latin1');
  let buffer = '';
  const waiters = [];
  const wake = () => waiters.splice(0).forEach((w) => w());
  socket.on('data', (c) => {
    buffer += c;
    wake();
  });
  socket.on('close', wake);
  socket.on('error', () => {});
  const line = async () => {
    for (let i = 0; i < 200; i++) {
      const at = buffer.indexOf('\r\n');
      if (at !== -1) {
        const text = buffer.slice(0, at);
        buffer = buffer.slice(at + 2);
        return text;
      }
      if (socket.destroyed) return null;
      await new Promise((resolve) => {
        waiters.push(resolve);
        setTimeout(resolve, 50);
      });
    }
    throw new Error('no line from the stub');
  };
  const reply = async () => {
    const lines = [];
    for (;;) {
      const l = await line();
      if (l === null) return lines;
      lines.push(l);
      if (l[3] !== '-') return lines;
    }
  };
  const send = async (text) => {
    socket.write(`${text}\r\n`);
    return reply();
  };
  return { socket, line, reply, send, raw: (t) => socket.write(t), close: () => socket.destroy() };
}

async function hello(port) {
  const c = client(port);
  assert.match((await c.reply())[0], /^220 /);
  const ehlo = await c.send('EHLO client.example');
  assert.match(ehlo[ehlo.length - 1], /^250 /);
  return { c, ehlo };
}

const b64 = (text) => Buffer.from(text, 'utf8').toString('base64');

async function mail(c, { from = 'me@example.com', to = ['me@example.com'], head = [], body }) {
  assert.match((await c.send(`MAIL FROM: <${from}>`))[0], /^250/);
  for (const t of to) assert.match((await c.send(`RCPT TO: <${t}>`))[0], /^250/);
  assert.match((await c.send('DATA'))[0], /^354/);
  const text = [...head, '', body].join('\r\n');
  c.raw(`${text.split('\r\n').map((l) => (l.startsWith('.') ? `.${l}` : l)).join('\r\n')}\r\n.\r\n`);
  return c.reply();
}

test('EHLO advertises AUTH PLAIN LOGIN XOAUTH2, XOAUTH2 last, and never STARTTLS, and STARTTLS is refused', async () => {
  await withStub(async ({ port }) => {
    const { c, ehlo } = await hello(port);
    assert.ok(ehlo.some((l) => l === '250-AUTH PLAIN LOGIN XOAUTH2'));
    assert.ok(!ehlo.some((l) => /STARTTLS/i.test(l)));
    assert.match((await c.send('STARTTLS'))[0], /^502/);
    assert.match((await c.send('HELO client.example'))[0], /^250/);
    assert.match((await c.send('NOOP'))[0], /^250/);
    assert.match((await c.send('BOGUS'))[0], /^500/);
    assert.match((await c.send('QUIT'))[0], /^221/);
    c.close();
  });
});

test('AUTH PLAIN (with and without an initial response) and AUTH LOGIN are accepted and keep the user name only', async () => {
  await withStub(async ({ control, port }) => {
    const one = await hello(port);
    assert.match((await one.c.send(`AUTH PLAIN ${b64(`\0plain-user\0${SECRET}`)}`))[0], /^235/);
    one.c.close();
    const two = await hello(port);
    assert.match((await two.c.send('AUTH PLAIN'))[0], /^334/);
    assert.match((await two.c.send(b64(`\0second-user\0${SECRET}`)))[0], /^235/);
    two.c.close();
    const three = await hello(port);
    assert.match((await three.c.send('AUTH LOGIN'))[0], /^334/);
    assert.match((await three.c.send(b64('login-user')))[0], /^334/);
    assert.match((await three.c.send(b64(SECRET)))[0], /^235/);
    assert.match((await three.c.send('AUTH CRAM-MD5'))[0], /^504/);
    three.c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.equal(state.logins, 3);
    assert.equal(state.user, 'login-user');
    assert.equal(JSON.stringify(state).includes(SECRET), false);
    assert.equal(JSON.stringify(state).includes(b64(SECRET)), false);
  });
});

test('a mail is kept decoded: envelope, an encoded-word subject, a quoted-printable UTF-8 body, one plain part and no attachment', async () => {
  await withStub(async ({ control, port }) => {
    const { c } = await hello(port);
    const done = await mail(c, {
      from: 'owner@example.com',
      to: ['owner@example.com', 'second@example.com'],
      head: ['From: owner@example.com', 'To: owner@example.com, second@example.com', `Subject: =?utf-8?B?${b64('Gr\u00fc\u00dfe \u20ac')}?=`, 'MIME-Version: 1.0', 'Content-Type: text/plain; charset="UTF-8"', 'Content-Transfer-Encoding: quoted-printable'],
      body: 'one=0Atwo =C3=A4=C3=B6=C3=BC =E2=82=AC\r\n.dot line',
    });
    assert.match(done[0], /^250/);
    const m = (await control('state', undefined, 'GET')).json.messages[0];
    assert.equal(m.from, 'owner@example.com');
    assert.deepEqual(m.to, ['owner@example.com', 'second@example.com']);
    assert.equal(m.subject, 'Gr\u00fc\u00dfe \u20ac');
    assert.equal(m.text, 'one\ntwo \u00e4\u00f6\u00fc \u20ac\r\n.dot line');
    assert.equal(m.headerTo, 'owner@example.com, second@example.com');
    assert.equal(m.parts, 1);
    assert.equal(m.attachments, 0);
    assert.match(m.contentType, /^text\/plain/);
    await c.send('QUIT');
    c.close();
  });
});

test('a multipart mail counts its parts and its attachments, and a base64 body is decoded', () => {
  const raw = [
    'Subject: Both',
    'Content-Type: multipart/mixed; boundary="B1"',
    '',
    '--B1',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    b64('caf\u00e9 text'),
    '--B1',
    'Content-Type: application/octet-stream; name="a.bin"',
    'Content-Disposition: attachment; filename="a.bin"',
    '',
    'AAAA',
    '--B1--',
    '',
  ].join('\r\n');
  const m = parse(raw, { from: 'a@example.com', to: ['b@example.com'] });
  assert.equal(m.parts, 2);
  assert.equal(m.attachments, 1);
  assert.equal(m.text, 'caf\u00e9 text');
  assert.equal(m.subject, 'Both');
});

test('the state carries the X-OcuTalon-Ref header of a mail: any case of the name, trimmed, unfolded, and empty when absent', async () => {
  await withStub(async ({ control, port }) => {
    const { c } = await hello(port);
    await mail(c, { head: ['Subject: plain', 'X-OcuTalon-Ref: ref-1'], body: 'one' });
    await mail(c, { head: ['Subject: lower', 'x-ocutalon-ref:   ref-2 \t'], body: 'two' });
    await mail(c, { head: ['Subject: folded', 'X-OCUTALON-REF:', ' ref-3-part-a', '\tref-3-part-b'], body: 'three' });
    await mail(c, { head: ['Subject: none', 'X-Other-Ref: not-this'], body: 'four' });
    await c.send('QUIT');
    c.close();
    const messages = (await control('state', undefined, 'GET')).json.messages;
    assert.deepEqual(messages.map((m) => m.subject), ['plain', 'lower', 'folded', 'none']);
    assert.deepEqual(messages.map((m) => m.xOcutalonRef), ['ref-1', 'ref-2', 'ref-3-part-a ref-3-part-b', '']);
    await control('reset', {});
    assert.deepEqual((await control('state', undefined, 'GET')).json.messages, []);
  });
});

test('parse reads the X-OcuTalon-Ref header of the top of a multipart mail, not one inside a part', () => {
  const raw = [
    'Subject: Both',
    'X-OcuTalon-Ref: top-ref',
    'Content-Type: multipart/alternative; boundary="B1"',
    '',
    '--B1',
    'Content-Type: text/plain; charset=utf-8',
    'X-OcuTalon-Ref: part-ref',
    '',
    'words',
    '--B1--',
    '',
  ].join('\r\n');
  assert.equal(parse(raw, { from: 'a@example.com', to: ['b@example.com'] }).xOcutalonRef, 'top-ref');
  assert.equal(parse('Subject: x\r\n\r\nbody', { from: 'a@example.com', to: [] }).xOcutalonRef, '');
});

test('decodeWords joins adjacent encoded words and reads the Q encoding', () => {
  assert.equal(decodeWords(`=?utf-8?B?${b64('Gr')}?= =?utf-8?B?${b64('\u00fc')}?=`), 'Gr\u00fc');
  assert.equal(decodeWords('=?utf-8?Q?caf=C3=A9_au_lait?='), 'caf\u00e9 au lait');
  assert.equal(decodeWords('plain'), 'plain');
});

test('the failure modes: refuse closes with no greeting, auth answers 535, reject answers RCPT 550, error answers DATA 554', async () => {
  await withStub(async ({ control, port }) => {
    await control('failure', { mode: 'refuse' });
    const closed = client(port);
    assert.equal(await closed.line(), null);
    await control('failure', { mode: 'auth' });
    const a = await hello(port);
    assert.match((await a.c.send(`AUTH PLAIN ${b64(`\0u\0${SECRET}`)}`))[0], /^535/);
    a.c.close();
    await control('failure', { mode: 'reject' });
    const r = await hello(port);
    assert.match((await r.c.send('MAIL FROM: <a@example.com>'))[0], /^250/);
    assert.match((await r.c.send('RCPT TO: <b@example.com>'))[0], /^550/);
    assert.match((await r.c.send('DATA'))[0], /^503/);
    r.c.close();
    await control('failure', { mode: 'error' });
    const e = await hello(port);
    assert.match((await e.c.send('MAIL FROM: <a@example.com>'))[0], /^250/);
    assert.match((await e.c.send('RCPT TO: <b@example.com>'))[0], /^250/);
    assert.match((await e.c.send('DATA'))[0], /^554/);
    e.c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.equal(state.logins, 0);
    assert.equal(state.failure, 'error');
    assert.deepEqual(state.messages, []);
    assert.equal(state.connections, 4);
  });
});

test('reset empties the mail, the failure and every count; a bad control body is a 400 and an unknown route a 404', async () => {
  await withStub(async ({ control, port }) => {
    const { c } = await hello(port);
    await mail(c, { head: ['Subject: x'], body: 'text' });
    c.close();
    await control('failure', { mode: 'auth' });
    assert.equal((await control('failure', { mode: 'sideways' })).status, 400);
    assert.equal((await control('failure', undefined)).status, 400);
    assert.equal((await control('state', {}, 'POST')).status, 404);
    assert.equal((await control('nothing', {})).status, 404);
    assert.equal((await control('reset', {})).status, 200);
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([state.messages, state.failure, state.connections, state.logins, state.user, state.commands], [[], 'none', 0, 0, '', {}]);
  });
});

test('a line that is not a command word, such as the bytes of a TLS handshake, is counted under (other)', async () => {
  await withStub(async ({ control, port }) => {
    const c = client(port);
    await c.reply();
    c.raw(Buffer.from([0x16, 0x03, 0x01, 0x00, 0xc8, 0x01, 0x00, 0x0a]).toString('latin1') + '\r\n');
    await c.reply();
    c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual(Object.keys(state.commands), ['(other)']);
  });
});

test('the password is never stored, logged or answered', async () => {
  await withStub(async ({ control, port, s }) => {
    const { c } = await hello(port);
    await c.send(`AUTH PLAIN ${b64(`\0owner@example.com\0${SECRET}`)}`);
    await c.send('QUIT');
    c.close();
    const state = await control('state', undefined, 'GET');
    assert.equal(JSON.stringify(state.json).includes(SECRET), false);
    assert.equal(state.json.user, 'owner@example.com');
    assert.equal(state.json.logins, 1);
    assert.equal(s.stdout().includes(SECRET), false);
    assert.equal(s.stderr().includes(SECRET), false);
  });
});

test('a port that cannot be taken is no start failure: the stub is absent and the line says so', async () => {
  const taken = net.createServer();
  await new Promise((resolve) => taken.listen(0, '0.0.0.0', resolve));
  const s = spawnServer(SERVER, ['--port', '0', '--pop3-port', '0', '--smtp-port', String(taken.address().port)]);
  try {
    await s.waitFor((l) => l.includes('"listening"'));
    const line = JSON.parse(await s.waitFor((l) => l.includes('smtp-unavailable')));
    assert.equal(line.event, 'smtp-unavailable');
  } finally {
    s.child.kill();
    await s.exited;
    await new Promise((resolve) => taken.close(resolve));
  }
});

const frame = (user, token) => Buffer.from(`user=${user}\x01auth=Bearer ${token}\x01\x01`, 'utf8').toString('base64');

test('AUTH XOAUTH2 with the response in the command, or after "334 ", logs in for an issued token and keeps neither the token nor a password', async () => {
  await withStub(async ({ control, port, s, oauth }) => {
    const { accessToken } = await oauth.issue();
    const one = await hello(port);
    assert.match((await one.c.send(`AUTH XOAUTH2 ${frame('first@example.com', accessToken)}`))[0], /^235/);
    one.c.close();
    const two = await hello(port);
    assert.deepEqual(await two.c.send('AUTH XOAUTH2'), ['334 ']);
    assert.match((await two.c.send(frame('second@example.com', accessToken)))[0], /^235/);
    assert.match((await two.c.send('MAIL FROM: <second@example.com>'))[0], /^250/);
    two.c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([state.logins, state.xoauth2, state.xoauth2Refused, state.user], [2, 2, 0, 'second@example.com']);
    for (const text of [JSON.stringify(state), s.stdout(), s.stderr()]) assert.equal(text.includes(accessToken), false);
  });
});

test('AUTH XOAUTH2 is answered 535 for an unknown token, a malformed frame and the failure mode auth', async () => {
  await withStub(async ({ control, port, oauth }) => {
    const { accessToken } = await oauth.issue();
    for (const response of [frame('owner@example.com', 'mock-at-never-issued'), 'bm90IGEgZnJhbWU=', frame('owner@example.com', '')]) {
      const { c } = await hello(port);
      assert.match((await c.send(`AUTH XOAUTH2 ${response}`))[0], /^535/);
      c.close();
    }
    await control('failure', { mode: 'auth' });
    const { c } = await hello(port);
    assert.match((await c.send(`AUTH XOAUTH2 ${frame('owner@example.com', accessToken)}`))[0], /^535/);
    c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([state.logins, state.xoauth2, state.xoauth2Refused], [0, 0, 3], 'the failure mode answers 535 before it checks the token');
  });
});

test('AUTH XOAUTH2 is answered 535 for an expired token and for a revoked one, and 235 for a token issued afterwards', async () => {
  await withStub(async ({ control, port, oauth }) => {
    const short = await oauth.issue('google', 1);
    await new Promise((resolve) => setTimeout(resolve, 2100));
    const expired = await hello(port);
    assert.match((await expired.c.send(`AUTH XOAUTH2 ${frame('owner@example.com', short.accessToken)}`))[0], /^535/);
    expired.c.close();
    const long = await oauth.issue('google', 3600);
    await oauth.control('revoke');
    const revoked = await hello(port);
    assert.match((await revoked.c.send(`AUTH XOAUTH2 ${frame('owner@example.com', long.accessToken)}`))[0], /^535/);
    revoked.c.close();
    const again = await oauth.issue('google', 3600);
    const ok = await hello(port);
    assert.match((await ok.c.send(`AUTH XOAUTH2 ${frame('owner@example.com', again.accessToken)}`))[0], /^235/);
    ok.c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([state.logins, state.xoauth2, state.xoauth2Refused], [1, 1, 2]);
  });
});

test('a password login is unchanged by XOAUTH2 and counts no XOAUTH2 login; reset clears the XOAUTH2 counts', async () => {
  await withStub(async ({ control, port }) => {
    const { c } = await hello(port);
    assert.match((await c.send(`AUTH PLAIN ${b64(`\0owner@example.com\0${SECRET}`)}`))[0], /^235/);
    c.close();
    const bad = await hello(port);
    assert.match((await bad.c.send(`AUTH XOAUTH2 ${frame('owner@example.com', 'mock-at-never-issued')}`))[0], /^535/);
    bad.c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([state.logins, state.xoauth2, state.xoauth2Refused], [1, 0, 1]);
    await control('reset');
    const clear = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([clear.logins, clear.xoauth2, clear.xoauth2Refused], [0, 0, 0]);
  });
});
