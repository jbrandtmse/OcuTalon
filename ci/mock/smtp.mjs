// The SMTP stub of the CI mock (Story 21.6; AD-22, Lane B mock behaviour): a plain-TCP SMTP server that receives mail and a control side.
// It is a test fixture: no real mail server, no real address, no real credential, no relay, no TLS. createSmtp() returns
//   {listen(port, host, cb), close(), handleControl(req, res, pathname, raw), state(), reset()}.
// The SMTP side answers EHLO, HELO, AUTH PLAIN and AUTH LOGIN, MAIL, RCPT, DATA, RSET, NOOP and QUIT. EHLO advertises AUTH PLAIN LOGIN and
// never STARTTLS, so a client that asks for STARTTLS meets a server without it (the client must then send nothing). AUTH is accepted
// whatever it holds (unless the failure mode says otherwise); the password is discarded at once and never stored, logged or echoed: the
// stub keeps only the count of the logins that it accepted and the last user name. A mail is never relayed: it is parsed and kept in the
// state, up to MAX_MESSAGES (the oldest go first).
// The control side is served by the mock's HTTP port (server.mjs routes /_mock/smtp/ here):
//   POST /_mock/smtp/failure  {"mode":"none"|"refuse"|"auth"|"reject"|"error"}
//        refuse: the connection is closed at once, with no greeting; auth: AUTH is answered 535; reject: RCPT is answered 550;
//        error: DATA is answered 554
//   POST /_mock/smtp/reset    no mail, no failure, every count 0
//   GET  /_mock/smtp/state    {"messages":[{"from","to":[...],"subject","text","headerFrom","headerTo","contentType","parts","attachments","xOcutalonRef"}],
//                              "connections":n,"logins":n,"user":"<last user>","failure":"<mode>","commands":{"RCPT":n,...}}
//                             (a line that is not a command word, such as the bytes of a TLS handshake, is counted under "(other)")
// A message's from and to are the envelope (MAIL FROM and RCPT TO addresses); headerFrom and headerTo are the decoded header lines; subject
// and text are decoded (encoded words, base64, quoted-printable, UTF-8); text is the first text/plain part; parts counts the MIME leaf parts
// (1 for a message with no multipart) and attachments the parts that are marked as an attachment or carry a file name.
// xOcutalonRef is the value of the X-OcuTalon-Ref header (the name is matched without regard to case, a folded header is unfolded, the
// value is trimmed) and '' when the mail has none. Any other path is a 404.

import net from 'node:net';

export const FAILURES = ['none', 'refuse', 'auth', 'reject', 'error'];
export const MAX_MESSAGES = 100;
const MAX_BYTES = 8 * 1024 * 1024;

// Decodes the encoded words (RFC 2047) of a header value; adjacent words are joined without the white space between them.
export function decodeWords(value) {
  const joined = value.replace(/(\?=)\s+(=\?)/g, '$1$2');
  return joined.replace(/=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=/g, (_all, charset, kind, data) => {
    const bytes = kind.toUpperCase() === 'B' ? Buffer.from(data, 'base64') : quotedPrintableBytes(data.replace(/_/g, ' '));
    return textOf(bytes, charset);
  });
}

function textOf(bytes, charset) {
  const name = String(charset).toLowerCase();
  if (name === 'utf-8' || name === 'utf8' || name === 'us-ascii') return bytes.toString('utf8');
  if (name === 'iso-8859-1' || name === 'latin1') return bytes.toString('latin1');
  return bytes.toString('utf8');
}

function quotedPrintableBytes(text) {
  const soft = text.replace(/=\r?\n/g, '');
  const out = [];
  for (let i = 0; i < soft.length; i++) {
    if (soft[i] === '=' && /^[0-9A-Fa-f]{2}$/.test(soft.slice(i + 1, i + 3))) {
      out.push(parseInt(soft.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      out.push(soft.charCodeAt(i) & 0xff);
    }
  }
  return Buffer.from(out);
}

// Splits a raw message (latin1 text of the octets) into its header lines (unfolded, as a map of lower-cased names) and its body.
export function splitMessage(raw) {
  const at = raw.indexOf('\r\n\r\n');
  const head = at === -1 ? raw : raw.slice(0, at);
  const body = at === -1 ? '' : raw.slice(at + 4);
  const headers = {};
  const order = [];
  for (const line of head.replace(/\r\n[ \t]+/g, ' ').split('\r\n')) {
    const colon = line.indexOf(':');
    if (colon <= 0) continue;
    const name = line.slice(0, colon).toLowerCase();
    if (headers[name] === undefined) headers[name] = line.slice(colon + 1).trim();
    order.push(name);
  }
  return { headers, body };
}

function param(value, name) {
  const m = new RegExp(`${name}\\s*=\\s*(?:"([^"]*)"|([^;\\s]*))`, 'i').exec(value ?? '');
  return m === null ? null : (m[1] ?? m[2]);
}

function bodyText(part) {
  const encoding = (part.headers['content-transfer-encoding'] ?? '7bit').toLowerCase();
  const charset = param(part.headers['content-type'], 'charset') ?? 'utf-8';
  let bytes;
  if (encoding === 'base64') bytes = Buffer.from(part.body.replace(/\s+/g, ''), 'base64');
  else if (encoding === 'quoted-printable') bytes = quotedPrintableBytes(part.body);
  else bytes = Buffer.from(part.body, 'latin1');
  return textOf(bytes, charset).replace(/\r\n$/, '');
}

// Walks the MIME structure: the leaf parts in order, each with its headers and body.
function leaves(part) {
  const type = (part.headers['content-type'] ?? 'text/plain').toLowerCase();
  const boundary = type.startsWith('multipart/') ? param(part.headers['content-type'], 'boundary') : null;
  if (boundary === null) return [part];
  const out = [];
  for (const piece of part.body.split(`--${boundary}`).slice(1)) {
    if (piece.startsWith('--')) break;
    out.push(...leaves(splitMessage(piece.replace(/^\r\n/, ''))));
  }
  return out;
}

// parse(raw, envelope): the message as the state shows it.
export function parse(raw, envelope) {
  const top = splitMessage(raw);
  const all = leaves(top);
  const plain = all.find((p) => (p.headers['content-type'] ?? 'text/plain').toLowerCase().startsWith('text/plain') && !/attachment/i.test(p.headers['content-disposition'] ?? ''));
  return {
    from: envelope.from,
    to: [...envelope.to],
    subject: decodeWords(top.headers.subject ?? ''),
    text: plain === undefined ? '' : bodyText(plain),
    headerFrom: decodeWords(top.headers.from ?? ''),
    headerTo: decodeWords(top.headers.to ?? ''),
    contentType: top.headers['content-type'] ?? 'text/plain',
    parts: all.length,
    attachments: all.filter((p) => /attachment/i.test(p.headers['content-disposition'] ?? '') || param(p.headers['content-disposition'], 'filename') !== null || param(p.headers['content-type'], 'name') !== null).length,
    xOcutalonRef: top.headers['x-ocutalon-ref'] ?? '',
  };
}

function address(arg) {
  const m = /<([^>]*)>/.exec(arg);
  return m === null ? arg.trim() : m[1];
}

export function createSmtp() {
  let messages = [];
  let failure = 'none';
  let counts = { connections: 0, logins: 0, commands: {}, user: '' };
  const sockets = new Set();
  let server = null;

  function reset() {
    messages = [];
    failure = 'none';
    counts = { connections: 0, logins: 0, commands: {}, user: '' };
  }

  function state() {
    return { messages: messages.map((m) => ({ ...m, to: [...m.to] })), connections: counts.connections, logins: counts.logins, user: counts.user, failure, commands: { ...counts.commands } };
  }

  // The user name of an AUTH PLAIN payload (authzid NUL user NUL password); the password part is dropped here and goes no further.
  function plainUser(payload) {
    const parts = Buffer.from(payload, 'base64').toString('utf8').split('\0');
    return parts.length >= 2 ? parts[parts.length - 2] : '';
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
    socket.setEncoding('latin1');
    let buffer = '';
    let mode = 'command';
    let loginUser = null;
    let envelope = { from: '', to: [] };
    let data = '';
    const send = (text) => socket.write(`${text}\r\n`);
    const login = (user) => {
      counts.logins += 1;
      counts.user = user;
      send('235 2.7.0 authenticated');
    };
    const command = (line) => {
      const space = line.indexOf(' ');
      const word = (space === -1 ? line : line.slice(0, space)).toUpperCase();
      const verb = /^[A-Z]{1,12}$/.test(word) ? word : '(other)';
      const arg = space === -1 ? '' : line.slice(space + 1);
      counts.commands[verb] = (counts.commands[verb] ?? 0) + 1;
      if (verb === 'QUIT') {
        send('221 bye');
        socket.end();
      } else if (verb === 'EHLO') {
        send('250-stub.example hello');
        send('250-AUTH PLAIN LOGIN');
        send('250 8BITMIME');
      } else if (verb === 'HELO') {
        send('250 stub.example hello');
      } else if (verb === 'AUTH') {
        const [mechanism, payload] = arg.split(' ');
        if (failure === 'auth') {
          send('535 5.7.8 authentication failed');
        } else if ((mechanism ?? '').toUpperCase() === 'PLAIN') {
          if (payload !== undefined && payload !== '') {
            login(plainUser(payload));
          } else {
            mode = 'plain';
            send('334 ');
          }
        } else if ((mechanism ?? '').toUpperCase() === 'LOGIN') {
          if (payload !== undefined && payload !== '') {
            loginUser = Buffer.from(payload, 'base64').toString('utf8');
            mode = 'loginPassword';
            send('334 UGFzc3dvcmQ6');
          } else {
            mode = 'loginUser';
            send('334 VXNlcm5hbWU6');
          }
        } else {
          send('504 5.5.4 mechanism not supported');
        }
      } else if (verb === 'MAIL') {
        envelope = { from: address(arg), to: [] };
        send('250 2.1.0 ok');
      } else if (verb === 'RCPT') {
        if (failure === 'reject') {
          send('550 5.1.1 recipient rejected');
        } else {
          envelope.to.push(address(arg));
          send('250 2.1.5 ok');
        }
      } else if (verb === 'DATA') {
        if (failure === 'error') {
          send('554 5.3.0 transaction failed');
        } else if (envelope.to.length === 0) {
          send('503 5.5.1 need RCPT first');
        } else {
          mode = 'data';
          data = '';
          send('354 end data with <CR><LF>.<CR><LF>');
        }
      } else if (verb === 'RSET') {
        envelope = { from: '', to: [] };
        send('250 2.0.0 ok');
      } else if (verb === 'NOOP') {
        send('250 2.0.0 ok');
      } else if (verb === 'STARTTLS') {
        send('502 5.5.1 STARTTLS is not offered');
      } else {
        send('500 5.5.1 unknown command');
      }
    };
    const line = (text) => {
      if (mode === 'data') {
        if (text === '.') {
          mode = 'command';
          messages.push(parse(data, envelope));
          if (messages.length > MAX_MESSAGES) messages.shift();
          envelope = { from: '', to: [] };
          send('250 2.0.0 queued');
        } else if (data.length < MAX_BYTES) {
          data += `${text.startsWith('..') ? text.slice(1) : text}\r\n`;
        }
      } else if (mode === 'plain') {
        mode = 'command';
        login(plainUser(text));
      } else if (mode === 'loginUser') {
        loginUser = Buffer.from(text, 'base64').toString('utf8');
        mode = 'loginPassword';
        send('334 UGFzc3dvcmQ6');
      } else if (mode === 'loginPassword') {
        mode = 'command';
        login(loginUser ?? '');
        loginUser = null;
      } else {
        command(text);
      }
    };
    socket.on('data', (chunk) => {
      buffer += chunk;
      let i;
      while ((i = buffer.indexOf('\n')) !== -1) {
        const text = buffer.slice(0, i).replace(/\r$/, '');
        buffer = buffer.slice(i + 1);
        line(text);
      }
    });
    send('220 stub.example SMTP stub ready');
  }

  function json(res, status, body) {
    const text = JSON.stringify(body);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(text) });
    res.end(text);
  }

  function handleControl(req, res, pathname, raw) {
    const route = pathname.slice('/_mock/smtp/'.length);
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
    if (route === 'failure') {
      let data = null;
      try {
        data = JSON.parse(raw);
      } catch {
        data = null;
      }
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
