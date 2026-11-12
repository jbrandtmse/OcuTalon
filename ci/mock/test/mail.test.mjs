// Tests of the POP3 stub of the CI mock (Story 21.2; AD-22): the commands, the control routes, the failure modes, the rule that DELE is
// counted and never applied, and the rule that a password is never stored, logged or answered. Each test starts its own server on
// 127.0.0.1 with the OS picking both ports and stops it afterwards (helpers.mjs). The password is built at run time. Needs Node 24
// and nothing else.

import assert from 'node:assert/strict';
import net from 'node:net';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { build } from '../mail.mjs';
import { spawnServer } from './helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, '..', 'server.mjs');
const SECRET = `pw-${'q'.repeat(12)}-stub`;

async function withStub(fn) {
  const s = spawnServer(SERVER, ['--port', '0', '--pop3-port', '0']);
  try {
    const http = JSON.parse(await s.waitFor((l) => l.includes('"listening"')));
    const pop = JSON.parse(await s.waitFor((l) => l.includes('"event":"pop3"')));
    const base = `http://127.0.0.1:${http.port}`;
    const control = async (route, body, verb = 'POST') => {
      const res = await fetch(`${base}/_mock/mail/${route}`, { method: verb, headers: body === undefined ? {} : { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
      return { status: res.status, json: await res.json() };
    };
    await fn({ control, port: pop.port, s });
  } finally {
    s.child.kill();
    await s.exited;
  }
}

// client(port): a POP3 client; send(line) answers the first line, and multi(line) the lines up to the lone dot.
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
  const send = async (text) => {
    socket.write(`${text}\r\n`);
    return line();
  };
  const multi = async (text) => {
    const first = await send(text);
    const lines = [];
    if (!first.startsWith('+OK')) return { first, lines };
    for (;;) {
      const l = await line();
      if (l === '.') break;
      lines.push(l);
    }
    return { first, lines };
  };
  return { socket, line, send, multi, close: () => socket.destroy() };
}

async function login(port) {
  const c = client(port);
  assert.match(await c.line(), /^\+OK/);
  assert.match(await c.send('USER owner@example.com'), /^\+OK/);
  assert.match(await c.send(`PASS ${SECRET}`), /^\+OK/);
  return c;
}

test('the mailbox is read with STAT, LIST, UIDL, TOP and RETR, and no command changes it', async () => {
  await withStub(async ({ control, port }) => {
    const set = await control('mailbox', { messages: [{ uidl: 'u-1', from: 'a@example.com', subject: 'One', text: 'hello\n.dot line' }, { uidl: 'u-2', from: 'b@example.com', subject: 'Two', html: '<p>hi</p>' }] });
    assert.deepEqual(set, { status: 200, json: { count: 2 } });
    const c = await login(port);
    assert.match((await c.send('STAT')).trim(), /^\+OK 2 \d+$/);
    const uidl = await c.multi('UIDL');
    assert.deepEqual(uidl.lines, ['1 u-1', '2 u-2']);
    assert.equal(await c.send('UIDL 2'), '+OK 2 u-2');
    const list = await c.multi('LIST');
    assert.equal(list.lines.length, 2);
    const top = await c.multi('TOP 1 0');
    assert.ok(top.lines.includes('Subject: One'));
    assert.ok(top.lines.includes('Message-ID: <u-1@stub.example>'));
    assert.ok(!top.lines.some((l) => l.includes('hello')));
    const retr = await c.multi('RETR 1');
    assert.ok(retr.lines.includes('hello'));
    assert.ok(retr.lines.includes('..dot line'), 'a line that starts with a dot is stuffed');
    const html = await c.multi('RETR 2');
    assert.ok(html.lines.some((l) => l.startsWith('Content-Type: text/html')));
    assert.equal(await c.send('RETR 9'), '-ERR no such message');
    assert.equal(await c.send('NOOP'), '+OK');
    assert.match(await c.send('QUIT'), /^\+OK/);
    c.close();
    const state = await control('state', undefined, 'GET');
    assert.deepEqual(state.json.uidls, ['u-1', 'u-2']);
    assert.equal(state.json.commands.QUIT, 1);
  });
});

test('DELE is counted and answered +OK but never applied', async () => {
  await withStub(async ({ control, port }) => {
    await control('mailbox', { messages: [{ uidl: 'u-1', text: 'x' }] });
    const c = await login(port);
    assert.match(await c.send('DELE 1'), /^\+OK/);
    assert.equal(await c.send('DELE 5'), '-ERR no such message');
    await c.send('QUIT');
    c.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.equal(state.deletes, 1);
    assert.deepEqual(state.uidls, ['u-1']);
  });
});

test('a message can be added, removed and replaced, and reset empties everything', async () => {
  await withStub(async ({ control }) => {
    await control('mailbox', { messages: [{ uidl: 'a' }] });
    assert.deepEqual((await control('add', { messages: [{ uidl: 'b' }] })).json, { count: 2 });
    assert.equal((await control('add', { messages: [{ uidl: 'b' }] })).status, 400);
    assert.deepEqual((await control('remove', { uidl: 'a' })).json, { count: 1 });
    assert.deepEqual((await control('state', undefined, 'GET')).json.uidls, ['b']);
    await control('failure', { mode: 'auth' });
    await control('reset', {});
    const state = (await control('state', undefined, 'GET')).json;
    assert.deepEqual([state.uidls, state.failure, state.connections, state.deletes], [[], 'none', 0, 0]);
  });
});

test('a bad control body is a 400 and changes nothing', async () => {
  await withStub(async ({ control }) => {
    await control('mailbox', { messages: [{ uidl: 'keep' }] });
    for (const [route, body] of [
      ['mailbox', { messages: [{ uidl: 'has space' }] }],
      ['mailbox', { messages: [{ uidl: 'x'.repeat(71) }] }],
      ['mailbox', { messages: [{ uidl: 'a' }, { uidl: 'a' }] }],
      ['mailbox', { messages: [{ uidl: 'a', bytes: 5 * 1024 * 1024 }] }],
      ['mailbox', { messages: [{ uidl: 'a', subject: 7 }] }],
      ['mailbox', {}],
      ['failure', { mode: 'sideways' }],
      ['remove', {}],
    ]) {
      assert.equal((await control(route, body)).status, 400, `${route} ${JSON.stringify(body)}`);
    }
    assert.equal((await control('nothing', {})).status, 404);
    assert.deepEqual((await control('state', undefined, 'GET')).json.uidls, ['keep']);
  });
});

test('the failure modes: refuse closes with no greeting, auth refuses PASS, error refuses UIDL', async () => {
  await withStub(async ({ control, port }) => {
    await control('mailbox', { messages: [{ uidl: 'u-1' }] });
    await control('failure', { mode: 'refuse' });
    const closed = client(port);
    assert.equal(await closed.line(), null);
    await control('failure', { mode: 'auth' });
    const c = client(port);
    assert.match(await c.line(), /^\+OK/);
    assert.match(await c.send('USER owner@example.com'), /^\+OK/);
    assert.match(await c.send(`PASS ${SECRET}`), /^-ERR/);
    assert.match(await c.send('STAT'), /^-ERR/);
    c.close();
    await control('failure', { mode: 'error' });
    const e = await login(port);
    assert.match(await e.send('UIDL'), /^-ERR/);
    assert.match(await e.send('STAT'), /^\+OK 1 /);
    e.close();
    const state = (await control('state', undefined, 'GET')).json;
    assert.equal(state.logins, 1, 'only the accepted login counts');
    assert.equal(state.failure, 'error');
  });
});

test('a message over a size is built from a small request, and a non-ASCII message is encoded', async () => {
  await withStub(async ({ control, port }) => {
    await control('mailbox', { messages: [{ uidl: 'big', subject: 'Big', text: 'start', bytes: 1100000 }, { uidl: 'wide', from: 'Zo\u00eb <z@example.com>', subject: 'Gr\u00fc\u00dfe', text: 'caf\u00e9' }] });
    const c = await login(port);
    const list = await c.multi('LIST');
    assert.ok(Number(list.lines[0].split(' ')[1]) > 1048576, `the size is ${list.lines[0]}`);
    const top = await c.multi('TOP 2 0');
    assert.ok(top.lines.some((l) => l.startsWith('Subject: =?utf-8?B?')));
    assert.ok(top.lines.some((l) => l.startsWith('From: =?utf-8?B?')));
    const body = await c.multi('RETR 2');
    assert.ok(body.lines.includes('Content-Transfer-Encoding: base64'));
    c.close();
  });
});

test('an HTML-only message padded to a size stays HTML-only and reaches the size', () => {
  const built = build({ uidl: 'h', subject: 'Html', html: '<p>only html</p>', bytes: 4000 });
  assert.ok(built.raw.includes('Content-Type: text/html; charset=utf-8'));
  assert.ok(!built.raw.includes('multipart/alternative'));
  assert.ok(built.size > 3500, `the size is ${built.size}`);
});

test('a message with a plain and an HTML body is multipart/alternative, plain part first', async () => {
  await withStub(async ({ control, port }) => {
    await control('mailbox', { messages: [{ uidl: 'alt', subject: 'Both', text: 'plain words', html: '<p>html words</p>' }] });
    const c = await login(port);
    const retr = await c.multi('RETR 1');
    const lines = retr.lines;
    assert.ok(lines.some((l) => l.startsWith('Content-Type: multipart/alternative; boundary=')));
    const plain = lines.indexOf('plain words');
    const html = lines.indexOf('<p>html words</p>');
    assert.ok(plain !== -1 && html !== -1 && plain < html);
    assert.equal(lines.filter((l) => l.startsWith('--=_stub_alt_1')).length, 3);
    c.close();
  });
});

test('a message with headers serves them in RETR and TOP, after the headers that the stub writes and before the body', async () => {
  await withStub(async ({ control, port }) => {
    const set = await control('mailbox', { messages: [{ uidl: 'h-1', subject: 'Ref', text: 'body words', headers: { 'X-OcuTalon-Ref': 'ref-42', 'Auto-Submitted': 'auto-generated', 'X-Wide': 'caf\u00e9' } }, { uidl: 'h-2', text: 'plain', html: '<p>x</p>', headers: { 'X-OcuTalon-Ref': 'ref-43' } }, { uidl: 'h-3', text: 'none' }] });
    assert.equal(set.status, 200);
    const c = await login(port);
    const top = await c.multi('TOP 1 0');
    assert.ok(top.lines.includes('X-OcuTalon-Ref: ref-42'));
    assert.ok(top.lines.includes('Auto-Submitted: auto-generated'));
    assert.ok(top.lines.some((l) => l.startsWith('X-Wide: =?utf-8?B?')), 'a non-ASCII value is an encoded word');
    assert.ok(!top.lines.some((l) => l.includes('body words')));
    const retr = await c.multi('RETR 1');
    assert.ok(retr.lines.includes('X-OcuTalon-Ref: ref-42'));
    assert.ok(retr.lines.indexOf('X-OcuTalon-Ref: ref-42') < retr.lines.indexOf(''), 'the header is in the header block');
    assert.ok(retr.lines.indexOf('X-OcuTalon-Ref: ref-42') > retr.lines.indexOf('MIME-Version: 1.0'));
    assert.ok(retr.lines.includes('body words'));
    const alt = await c.multi('RETR 2');
    assert.ok(alt.lines.includes('X-OcuTalon-Ref: ref-43'));
    assert.ok(alt.lines.some((l) => l.startsWith('Content-Type: multipart/alternative')));
    const bare = await c.multi('RETR 3');
    assert.ok(!bare.lines.some((l) => l.startsWith('X-OcuTalon-Ref')));
    c.close();
    await control('reset', {});
    assert.deepEqual((await control('state', undefined, 'GET')).json.uidls, []);
  });
});

test('a bad headers value is a 400 and changes nothing', async () => {
  await withStub(async ({ control }) => {
    await control('mailbox', { messages: [{ uidl: 'keep' }] });
    for (const headers of [
      'X-A: b',
      ['X-A'],
      null,
      { 'X A': 'b' },
      { 'X-A:': 'b' },
      { '': 'b' },
      { 'X-A\r\nX-B': 'b' },
      { 'X-A': 'b\r\nX-Injected: 1' },
      { 'X-A': 'b\nc' },
      { 'X-A': 7 },
      { Subject: 'again' },
      { 'content-type': 'text/html' },
      { 'MESSAGE-ID': '<x@y>' },
    ]) {
      assert.equal((await control('mailbox', { messages: [{ uidl: 'a', headers }] })).status, 400, JSON.stringify(headers));
      assert.equal((await control('add', { messages: [{ uidl: 'b', headers }] })).status, 400, JSON.stringify(headers));
    }
    assert.deepEqual((await control('state', undefined, 'GET')).json.uidls, ['keep']);
    assert.equal((await control('add', { messages: [{ uidl: 'ok', headers: {} }] })).status, 200);
  });
});

test('build puts the headers in the header block that TOP serves', () => {
  const built = build({ uidl: 'b', subject: 'S', text: 'x', headers: { 'X-OcuTalon-Ref': 'r-1' } });
  assert.ok(built.headers.includes('\r\nX-OcuTalon-Ref: r-1\r\n'));
  assert.ok(built.raw.startsWith(built.headers));
  assert.ok(!build({ uidl: 'b', text: 'x' }).raw.includes('X-OcuTalon-Ref'));
});

test('the password is never stored, logged or answered', async () => {
  await withStub(async ({ control, port, s }) => {
    await control('mailbox', { messages: [{ uidl: 'u-1' }] });
    const c = await login(port);
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
