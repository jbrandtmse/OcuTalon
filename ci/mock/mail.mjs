// The POP3 stub of the CI mock (Story 21.2; AD-22, Lane B mock behaviour): a plain-TCP POP3 server with a fixture mailbox and a control
// side. It is a test fixture: no real mail server, no real credentials, no TLS. createMail() returns
//   {listen(port, host, cb), close(), handleControl(req, res, pathname, raw), state(), reset()}.
// The POP3 side answers USER, PASS, AUTH XOAUTH2, STAT, LIST [n], UIDL [n], TOP n m, RETR n, DELE n, NOOP, RSET and QUIT. USER and PASS are accepted
// whatever they hold (unless the failure mode says otherwise); the password is never stored, logged or echoed: the stub keeps only
// the count of the logins that it accepted and the last user name. AUTH XOAUTH2 (Story 21.8) answers "+ ", reads one base64 line and checks it with the
// validator that createMail({checkAccessToken}) was given (the fake OAuth2 server's, so only an unexpired, unrevoked token passes; with none, nothing
// passes): "+OK" logs in, anything else is "-ERR [AUTH] invalid token"; the token is checked and dropped, never stored, logged or echoed. DELE is counted and answered +OK but never applied, so a test can
// see that a client asked for a deletion, and the mailbox stays as it is; no command changes the mailbox.
// The control side is served by the mock's HTTP port (server.mjs routes /_mock/mail/ here):
//   POST /_mock/mail/mailbox   {"messages":[<message>,...]}   replaces the mailbox
//   POST /_mock/mail/add       {"messages":[<message>,...]}   appends to the mailbox
//   POST /_mock/mail/remove    {"uidl":"<uidl>"}              takes one message out of the mailbox
//   POST /_mock/mail/failure   {"mode":"none"|"refuse"|"auth"|"error"}
//        refuse: the connection is closed at once, with no greeting; auth: PASS is answered -ERR; error: UIDL is answered -ERR
//   POST /_mock/mail/reset     the mailbox empty, no failure, every count 0
//   GET  /_mock/mail/state     {"uidls":[...],"connections":n,"logins":n,"xoauth2":n,"xoauth2Refused":n,"user":"<last user>","deletes":n,"failure":"<mode>",
//                              "commands":{"UIDL":n,...}}   (logins counts every accepted login, xoauth2 those that were XOAUTH2; the failure mode auth
//                              refuses XOAUTH2 too; no token value is ever in it)
// A <message> is {"uidl","from","subject","text","html","bytes","headers"}: uidl is required (1 to 70 printable characters, no space); text is the
// plain body and html the HTML body (html alone makes an HTML-only message, both make multipart/alternative); bytes pads the body with filler to that total size (at
// most 4 MiB; an HTML-only message pads its HTML body and stays HTML-only), so that a message over a size limit needs no large request. A non-ASCII subject or body is encoded as a real mail
// would send it (an encoded word, base64). headers is optional, an object {name: value} of extra RFC 5322 headers that RETR and TOP both
// serve (after MIME-Version, in the object's order): a name is one or more token characters (letters, digits and !#$%&'*+-.^_`|~) and
// may not be one of the headers that the stub writes itself (From, To, Subject, Date, Message-ID, MIME-Version, Content-Type,
// Content-Transfer-Encoding), a value is a string with no CR or LF (a non-ASCII value is sent as an encoded word). Any other path is a 404.

import net from 'node:net';
import { parseXoauth2 } from './oauth.mjs';

export const MAX_BYTES = 4 * 1024 * 1024;
export const FAILURES = ['none', 'refuse', 'auth', 'error'];
const UIDL = /^[\x21-\x7e]{1,70}$/;
const HEADER_NAME = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/;
const OWN_HEADERS = ['from', 'to', 'subject', 'date', 'message-id', 'mime-version', 'content-type', 'content-transfer-encoding'];

function encodeHeader(text) {
  return /^[\x20-\x7e]*$/.test(text) ? text : `=?utf-8?B?${Buffer.from(text, 'utf8').toString('base64')}?=`;
}

// payload(text): a body in the encoding that a real mail would use: 7bit for ASCII, else base64 (76 characters a line).
function payload(text) {
  const ascii = /^[\x09\x0a\x0d\x20-\x7e]*$/.test(text);
  return {
    encoding: ascii ? '7bit' : 'base64',
    body: ascii ? text.replace(/\r?\n/g, '\r\n') : Buffer.from(text, 'utf8').toString('base64').replace(/(.{76})/g, '$1\r\n'),
  };
}

// build(message): the message as a mail would arrive, with CRLF line ends, its headers and its size in octets. A message with both text and
// html is multipart/alternative (the plain part first); with html alone it is text/html; otherwise text/plain.
export function build(message) {
  let html = typeof message.html === 'string' ? message.html : null;
  let text = typeof message.text === 'string' ? message.text : '';
  const head = [
    `From: ${encodeHeader(message.from ?? 'sender@example.com')}`,
    'To: owner@example.com',
    `Subject: ${encodeHeader(message.subject ?? '')}`,
    'Date: Wed, 11 Nov 2026 12:00:00 +0000',
    `Message-ID: <${message.uidl}@stub.example>`,
    'MIME-Version: 1.0',
  ];
  for (const [name, value] of Object.entries(message.headers ?? {})) head.push(`${name}: ${encodeHeader(value)}`);
  if (Number.isInteger(message.bytes) && message.bytes > 0) {
    const need = message.bytes - (head.join('\r\n').length + 400 + text.length + (html ?? '').length);
    const filler = need > 0 ? `\n${'x'.repeat(77)}`.repeat(Math.ceil(need / 79)) : '';
    if (html !== null && text === '') html += filler;
    else text += filler;
  }
  let body;
  if (html !== null && text !== '') {
    const boundary = '=_stub_alt_1';
    const one = (type, content) => {
      const p = payload(content);
      return `--${boundary}\r\nContent-Type: ${type}; charset=utf-8\r\nContent-Transfer-Encoding: ${p.encoding}\r\n\r\n${p.body}\r\n`;
    };
    head.push(`Content-Type: multipart/alternative; boundary="${boundary}"`);
    body = `${one('text/plain', text)}${one('text/html', html)}--${boundary}--\r\n`;
  } else {
    const p = payload(html !== null ? html : text);
    head.push(`Content-Type: ${html !== null ? 'text/html' : 'text/plain'}; charset=utf-8`, `Content-Transfer-Encoding: ${p.encoding}`);
    body = `${p.body}\r\n`;
  }
  const raw = `${head.join('\r\n')}\r\n\r\n${body}`;
  return { raw, size: Buffer.byteLength(raw), headers: `${head.join('\r\n')}\r\n` };
}

function stuff(raw) {
  return raw.split('\r\n').map((line) => (line.startsWith('.') ? `.${line}` : line)).join('\r\n');
}

export function createMail({ checkAccessToken = () => false } = {}) {
  let mailbox = [];
  let failure = 'none';
  let counts = { connections: 0, logins: 0, xoauth2: 0, xoauth2Refused: 0, deletes: 0, commands: {}, user: '' };
  const sockets = new Set();
  let server = null;

  function reset() {
    mailbox = [];
    failure = 'none';
    counts = { connections: 0, logins: 0, xoauth2: 0, xoauth2Refused: 0, deletes: 0, commands: {}, user: '' };
  }

  function state() {
    return { uidls: mailbox.map((m) => m.uidl), connections: counts.connections, logins: counts.logins, xoauth2: counts.xoauth2, xoauth2Refused: counts.xoauth2Refused, user: counts.user, deletes: counts.deletes, failure, commands: { ...counts.commands } };
  }

  function session(socket) {
    counts.connections += 1;
    if (failure === 'refuse') {
      socket.destroy();
      return;
    }
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
    let user = null;
    let authed = false;
    let awaitingToken = false;
    let buffer = '';
    const send = (text) => socket.write(`${text}\r\n`);
    const nth = (arg) => {
      const n = Number(arg);
      return Number.isInteger(n) && n >= 1 && n <= mailbox.length ? n : 0;
    };
    const xoauth2 = (line) => {
      const parsed = failure === 'auth' ? null : parseXoauth2(line);
      if (parsed !== null && checkAccessToken(parsed.token)) {
        authed = true;
        counts.logins += 1;
        counts.xoauth2 += 1;
        counts.user = parsed.user;
        send('+OK logged in');
      } else {
        counts.xoauth2Refused += 1;
        send('-ERR [AUTH] invalid token');
      }
    };
    const handle = (line) => {
      if (awaitingToken) {
        awaitingToken = false;
        xoauth2(line);
        return;
      }
      const space = line.indexOf(' ');
      const verb = (space === -1 ? line : line.slice(0, space)).toUpperCase();
      const arg = space === -1 ? '' : line.slice(space + 1);
      counts.commands[verb] = (counts.commands[verb] ?? 0) + 1;
      if (verb === 'QUIT') {
        send('+OK bye');
        socket.end();
        return;
      }
      if (!authed) {
        if (verb === 'USER') {
          user = arg;
          counts.user = arg;
          send('+OK');
        } else if (verb === 'AUTH' && arg.trim().toUpperCase() === 'XOAUTH2') {
          awaitingToken = true;
          send('+ ');
        } else if (verb === 'PASS' && user !== null) {
          if (failure === 'auth') {
            send('-ERR [AUTH] authentication failed');
          } else {
            authed = true;
            counts.logins += 1;
            send('+OK logged in');
          }
        } else {
          send('-ERR authenticate first');
        }
        return;
      }
      if (verb === 'NOOP' || verb === 'RSET') {
        send('+OK');
      } else if (verb === 'STAT') {
        send(`+OK ${mailbox.length} ${mailbox.reduce((sum, m) => sum + m.size, 0)}`);
      } else if (verb === 'LIST' || verb === 'UIDL') {
        if (verb === 'UIDL' && failure === 'error') {
          send('-ERR internal error');
        } else if (arg !== '') {
          const n = nth(arg);
          if (n === 0) send('-ERR no such message');
          else send(`+OK ${n} ${verb === 'LIST' ? mailbox[n - 1].size : mailbox[n - 1].uidl}`);
        } else {
          send('+OK');
          mailbox.forEach((m, i) => send(`${i + 1} ${verb === 'LIST' ? m.size : m.uidl}`));
          send('.');
        }
      } else if (verb === 'RETR' || verb === 'TOP') {
        const n = nth(arg.split(' ')[0]);
        if (n === 0) {
          send('-ERR no such message');
        } else {
          const m = mailbox[n - 1];
          send('+OK');
          socket.write(verb === 'RETR' ? `${stuff(m.raw)}.\r\n` : `${stuff(m.headers)}\r\n.\r\n`);
        }
      } else if (verb === 'DELE') {
        if (nth(arg) === 0) {
          send('-ERR no such message');
        } else {
          counts.deletes += 1;
          send('+OK marked');
        }
      } else {
        send('-ERR unknown command');
      }
    };
    socket.setEncoding('latin1');
    socket.on('data', (chunk) => {
      buffer += chunk;
      let i;
      while ((i = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, i).replace(/\r$/, '');
        buffer = buffer.slice(i + 1);
        handle(line);
      }
    });
    send('+OK POP3 stub ready');
  }

  function messagesOf(data) {
    if (data === null || typeof data !== 'object' || !Array.isArray(data.messages)) return { problem: 'the body must be {"messages":[...]}' };
    const made = [];
    const seen = new Set();
    for (const m of data.messages) {
      if (m === null || typeof m !== 'object' || typeof m.uidl !== 'string' || !UIDL.test(m.uidl)) return { problem: 'a message needs a uidl of 1 to 70 printable characters without a space' };
      if (seen.has(m.uidl)) return { problem: `the uidl ${m.uidl} is repeated` };
      if (m.bytes !== undefined && (!Number.isInteger(m.bytes) || m.bytes < 0 || m.bytes > MAX_BYTES)) return { problem: `bytes must be a whole number up to ${MAX_BYTES}` };
      for (const key of ['from', 'subject', 'text', 'html']) {
        if (m[key] !== undefined && typeof m[key] !== 'string') return { problem: `${key} must be a string` };
      }
      if (m.headers !== undefined) {
        if (m.headers === null || typeof m.headers !== 'object' || Array.isArray(m.headers)) return { problem: 'headers must be an object of name and value' };
        for (const [name, value] of Object.entries(m.headers)) {
          if (!HEADER_NAME.test(name) || OWN_HEADERS.includes(name.toLowerCase())) return { problem: `the header name ${JSON.stringify(name)} is not allowed` };
          if (typeof value !== 'string' || /[\r\n]/.test(value)) return { problem: `the value of the header ${name} must be a string without CR or LF` };
        }
      }
      seen.add(m.uidl);
      made.push({ uidl: m.uidl, ...build(m) });
    }
    return { made };
  }

  function json(res, status, body) {
    const text = JSON.stringify(body);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text) });
    res.end(text);
  }

  function handleControl(req, res, pathname, raw) {
    const route = pathname.slice('/_mock/mail/'.length);
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
    let data = null;
    try {
      data = JSON.parse(raw);
    } catch {
      data = null;
    }
    if (route === 'mailbox' || route === 'add') {
      const { made, problem } = messagesOf(data);
      if (problem !== undefined) {
        json(res, 400, { error: `CI mock: ${problem}` });
        return;
      }
      if (route === 'add' && made.some((m) => mailbox.some((o) => o.uidl === m.uidl))) {
        json(res, 400, { error: 'CI mock: a uidl is already in the mailbox' });
        return;
      }
      mailbox = route === 'mailbox' ? made : [...mailbox, ...made];
      json(res, 200, { count: mailbox.length });
      return;
    }
    if (route === 'remove') {
      if (data === null || typeof data !== 'object' || typeof data.uidl !== 'string') {
        json(res, 400, { error: 'CI mock: the body must be {"uidl":"..."}' });
        return;
      }
      mailbox = mailbox.filter((m) => m.uidl !== data.uidl);
      json(res, 200, { count: mailbox.length });
      return;
    }
    if (route === 'failure') {
      if (data === null || typeof data !== 'object' || !FAILURES.includes(data.mode)) {
        json(res, 400, { error: `CI mock: mode must be one of ${FAILURES.join(', ')}` });
        return;
      }
      failure = data.mode;
      json(res, 200, { failure });
      return;
    }
    json(res, 404, { error: `CI mock: no route for ${req.method} ${pathname}` });
  }

  function listen(port, host, cb) {
    server = net.createServer(session);
    server.on('error', (e) => cb(e));
    server.listen(port, host, () => cb(null, server.address().port));
  }

  function close() {
    for (const s of sockets) s.destroy();
    if (server !== null) server.close();
  }

  return { listen, close, handleControl, state, reset };
}
