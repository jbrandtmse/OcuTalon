import { expect, test, type APIRequestContext, type APIResponse } from '../support/fixtures';

import { envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { STATE, post, sessionEvents } from '../support/api';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { logMark, removeDecisionsOf, sessionRefOfUser } from '../support/memory';

/**
 * Story 25.3, the Rule 3 evidence for POST /api/v1/files over real HTTP, on the stack that test-sign-in.sh seeds, as the unprivileged LIVE fixture user (role
 * OcuTalonUser only) with a second OcuTalonUser-only session (PANEL). On this branch nothing reads a sent file, so a file turn ends with the fixed reply and no model call
 * (the Planner's ruling 4); the tests that depend on that, `/v1/state` `filesReadable` false and the reply text, are the tripwires that Story 26.2 flips.
 *  - signed out the route is 401 signed_out; LIVE gets 202 with exactly clientId and file{ref,name,mediaType,size}, and its /v1/state and events carry the sentFile;
 *    PANEL's state and events never show LIVE's file, and LIVE's never show PANEL's;
 *  - every refusal code and every bad body has its exact answer; a 14 MB file is 413 body_too_large and 10,485,761 bytes within the bound is 400 too_large; the envelope's three 403s;
 *    the trace-only user is 403 no_role; a sessionRef in the body is ignored;
 *  - security condition (ii): GET, PUT, DELETE and PATCH on /v1/files, and every method on /v1/files/<ref>, /v1/files/<ref>/content and /v1/documents/<ref> (a ref of LIVE's stored
 *    file), are 404 not_found (the documents route keeps its own 405 for the verbs it does not serve), and no answer body holds the content marker;
 *  - security condition (iii): MZ bytes named setup.pdf and HTML bytes named page.png, each with a declared mediaType of application/pdf in the body, are 400 wrong_type with no row;
 *  - security condition (iv): after a mark, a PDF whose bytes hold a fresh marker and whose name holds <script> goes through to its done turn; the marker is in no production message
 *    (KeyProof.TraceHits; the file's ref is found as the positive control), no event log row, no Turn field and no mock log entry, and a name of 400 characters is refused and stored nowhere;
 *  - ruling 4: filesReadable is false, the done chat.message carries "I got {name}, but I can't read files yet.", the Item's ItemId has no Decision and no model request names the file.
 */
const FILES = '/ocutalon/api/v1/files';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const BAD_FILE = 'OcuTalon can read PDF, Word (.docx), JPEG and PNG files up to 10 MB.';
const TOO_LARGE = 'OcuTalon refused this request because its body is larger than it accepts.';
const NO_REQUEST_HEADER = "OcuTalon refused this request because it didn't come from the OcuTalon page.";
const NOT_JSON = "OcuTalon refused this request because it wasn't sent as JSON.";
const WRONG_ORIGIN = 'OcuTalon refused this request because it came from another site.';
const LIMIT = 10_485_760;

interface SentFile {
  ref: string;
  name: string;
  mediaType: string;
  size: number;
}

/** Bytes of a file of the kind, with the marker inside. */
function bytesOf(kind: 'pdf' | 'png' | 'jpeg' | 'docx' | 'exe' | 'html' | 'text', marker = 'zzfile'): Buffer {
  switch (kind) {
    case 'pdf':
      return Buffer.from(`%PDF-1.4 ${marker}`);
    case 'png':
      return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from(`IHDR ${marker}`)]);
    case 'jpeg':
      return Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from(`JFIF ${marker}`)]);
    case 'docx':
      return zipWithEntry('word/document.xml', marker);
    case 'exe':
      return Buffer.concat([Buffer.from('MZ'), Buffer.from([0x90, 0x00, 0x03, 0x00]), Buffer.from(marker)]);
    case 'html':
      return Buffer.from(`<html><script>alert('${marker}')</script></html>`);
    case 'text':
      return Buffer.from(`plain text ${marker}`);
  }
}

/** A stored zip with one entry (a local file header and its data), which is all that the server reads of a Word file. */
function zipWithEntry(entry: string, data: string): Buffer {
  const name = Buffer.from(entry);
  const body = Buffer.from(data);
  const header = Buffer.alloc(30);
  header.write('PK\u0003\u0004', 0, 'latin1');
  header.writeUInt16LE(20, 4);
  header.writeUInt32LE(body.length, 18);
  header.writeUInt32LE(body.length, 22);
  header.writeUInt16LE(name.length, 26);
  return Buffer.concat([header, name, body]);
}

/** The JSON text of a file post. */
function bodyOf(clientId: string, name: string, bytes: Buffer, extra: Record<string, unknown> = {}): string {
  return JSON.stringify({ clientId, name, content: bytes.toString('base64'), ...extra });
}

/** The state's chat.message payloads that carry a sentFile. */
async function filesInState(context: APIRequestContext): Promise<Array<Record<string, unknown>>> {
  const response = await context.get(STATE);
  expect(response.status(), await response.text()).toBe(200);
  const state = (await response.json()) as { chat: Array<{ type: string; payload: Record<string, unknown> }>; filesReadable: unknown };
  return state.chat.filter((item) => item.type === 'chat.message' && item.payload['sentFile'] !== undefined).map((item) => item.payload);
}

/** The number of SentFile rows of the session. */
async function rowsOf(session: string): Promise<number> {
  const lines = await irisScript(`Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.SentFile WHERE SessionRef = ?",${quoted(session)})\nDo rs.%Next()\nWrite !,"CHK|n|",rs.%GetData(1)`);
  return Number(chk(lines, 'n'));
}

/** Waits (bounded) until the state holds a done turn for the file, and answers its payload. */
async function doneTurn(context: APIRequestContext, ref: string, seconds = 60): Promise<Record<string, unknown>> {
  const deadline = Date.now() + seconds * 1000;
  for (;;) {
    const found = (await filesInState(context)).find((payload) => (payload['sentFile'] as SentFile).ref === ref && payload['state'] === 'done');
    if (found) return found;
    if (Date.now() > deadline) throw new Error(`the turn of the file ${ref} was not done within ${seconds} s`);
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
}

/** Deletes the SentFile rows, the Turns and the Decisions that the test made for the session (the Turns by their clientId prefix). */
async function clean(session: string, prefix: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ItemId FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ClientId %STARTSWITH ?",${quoted(session)},${quoted(prefix)})`,
      'Set items=""',
      'While rs.%Next() { Set items=items_$ListBuild(rs.%Get("ItemId")) }',
      `Do ##class(OcuTalon.Data.SentFile).DropSession(${quoted(session)})`,
      `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ClientId %STARTSWITH ?",${quoted(session)},${quoted(prefix)})`,
      'Write !,"CHK|items|",$ListToString(items)',
    ].join('\n'),
  );
  await removeDecisionsOf((chk(lines, 'items') ?? '').split(',').filter(Boolean));
}

test('the files route: signed out, the accepted types, the refusals, the bounds and the envelope', async ({ request, playwright, baseURL }) => {
  test.setTimeout(150_000);
  const live = fixtureUser('LIVE');
  await signInOverHttp(request, live.user, live.password);
  const session = await sessionRefOfUser(live.user);
  const prefix = `zzfilesapi${Date.now()}`;
  try {
    const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
    try {
      const response = await anonymous.fetch(FILES, { method: 'POST', headers: envelope(), data: bodyOf(`${prefix}a`, 'a.pdf', bytesOf('pdf')) });
      await expectError(response, 401, 'signed_out', SIGNED_OUT);
      expect(response.headers()['www-authenticate'], 'no challenge').toBeUndefined();
    } finally {
      await anonymous.dispose();
    }

    // Each accepted type: 202 with exactly clientId and file{ref,name,mediaType,size}.
    const types = [
      ['a.pdf', 'pdf', 'application/pdf'],
      ['b.docx', 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
      ['c.jpg', 'jpeg', 'image/jpeg'],
      ['d.png', 'png', 'image/png'],
    ] as const;
    const refs: string[] = [];
    for (const [index, [name, kind, mediaType]] of types.entries()) {
      const bytes = bytesOf(kind);
      const response = await post(request, FILES, bodyOf(`${prefix}t${index}`, name, bytes, { sessionRef: 'zzsomeoneelse', mediaType: 'text/plain', type: 'text/plain' }));
      expect(response.status(), await response.text()).toBe(202);
      expect(response.headers()['content-type']).toContain('application/json');
      const answer = (await response.json()) as { clientId: string; file: SentFile };
      expect(Object.keys(answer), name).toEqual(['clientId', 'file']);
      expect(Object.keys(answer.file), name).toEqual(['ref', 'name', 'mediaType', 'size']);
      expect(answer.clientId).toBe(`${prefix}t${index}`);
      expect(answer.file).toEqual({ ref: expect.stringMatching(/^[A-Za-z0-9_-]{22}$/), name, mediaType, size: bytes.length });
      refs.push(answer.file.ref);
    }
    expect(await rowsOf(session), 'one row for each file, all of the LIVE session').toBe(4);

    // The refusals, with their exact answers.
    const refused: Array<[string, string, Buffer, string, Record<string, unknown>?]> = [
      ['x.txt', 'text', bytesOf('text'), 'wrong_type'],
      ['x.gif', 'text', Buffer.from('GIF89a zz'), 'wrong_type'],
      ['x.png', 'pdf', bytesOf('pdf'), 'wrong_type'],
      ['x.pdf', 'none', Buffer.from('unknown bytes'), 'wrong_type'],
      ['x.docx', 'zip', zipWithEntry('readme.txt', 'zz'), 'wrong_type'],
      ['empty.pdf', 'empty', Buffer.alloc(0), 'empty'],
    ];
    for (const [index, [name, , bytes, reason]] of refused.entries()) {
      const response = await post(request, FILES, bodyOf(`${prefix}r${index}`, name, bytes));
      expect(response.status(), `${name}: ${await response.text()}`).toBe(400);
      expect(await response.json(), name).toEqual({ error: { code: 'bad_file', message: BAD_FILE }, reason, size: bytes.length });
    }

    // Bad bodies: 400 bad_file with no reason.
    const good = { clientId: `${prefix}b`, name: 'a.pdf', content: bytesOf('pdf').toString('base64') };
    const bad: unknown[] = [
      'not json',
      '[]',
      {},
      { ...good, clientId: undefined },
      { ...good, clientId: '' },
      { ...good, clientId: 'c'.repeat(129) },
      { ...good, name: undefined },
      { ...good, name: '' },
      { ...good, name: '   ' },
      { ...good, name: `a\nb.pdf` },
      { ...good, name: 'n'.repeat(252) + '.pdf' },
      { ...good, content: undefined },
      { ...good, content: 5 },
      { ...good, content: '!!!not base64!!!' },
    ];
    for (const [index, body] of bad.entries()) {
      const response = await post(request, FILES, typeof body === 'string' ? body : JSON.stringify(body));
      await expectError(response, 400, 'bad_file', BAD_FILE);
      expect(Object.keys(await response.json()), `bad body ${index}: no reason`).toEqual(['error']);
    }

    // The bounds: 10,485,761 bytes within the body bound is too_large; a 14 MB file is over the body bound.
    const over = Buffer.concat([Buffer.from('%PDF-'), Buffer.alloc(LIMIT + 1 - 5, 0x20)]);
    const tooLarge = await post(request, FILES, bodyOf(`${prefix}big1`, 'big.pdf', over));
    expect(tooLarge.status(), (await tooLarge.text()).slice(0, 300)).toBe(400);
    expect(await tooLarge.json()).toEqual({ error: { code: 'bad_file', message: BAD_FILE }, reason: 'too_large', size: LIMIT + 1 });
    const huge = Buffer.concat([Buffer.from('%PDF-'), Buffer.alloc(14 * 1024 * 1024 - 5, 0x20)]);
    const bodyTooLarge = await post(request, FILES, bodyOf(`${prefix}big2`, 'huge.pdf', huge));
    await expectError(bodyTooLarge, 413, 'body_too_large', TOO_LARGE);
    expect(await rowsOf(session), 'no refusal stored a row').toBe(4);

    // The envelope.
    const data = bodyOf(`${prefix}e`, 'a.pdf', bytesOf('pdf'));
    await expectError(await request.fetch(FILES, { method: 'POST', headers: envelope({ 'x-ocutalon-request': undefined }), data }), 403, 'no_request_header', NO_REQUEST_HEADER);
    await expectError(await request.fetch(FILES, { method: 'POST', headers: envelope({ 'content-type': 'text/plain' }), data }), 403, 'not_json', NOT_JSON);
    await expectError(await request.fetch(FILES, { method: 'POST', headers: envelope({ origin: 'http://evil.example' }), data }), 403, 'wrong_origin', WRONG_ORIGIN);
    expect(await rowsOf(session), 'and none stored a row').toBe(4);

    // A repeat of a clientId is 202 with the clientId alone, and keeps one row.
    const repeat = await post(request, FILES, bodyOf(`${prefix}t0`, 'a.pdf', bytesOf('pdf')));
    expect(repeat.status()).toBe(202);
    expect(await repeat.json()).toEqual({ clientId: `${prefix}t0` });
    expect(await rowsOf(session), 'the second file of the repeat is dropped').toBe(4);
  } finally {
    await clean(session, prefix);
  }
});

test('the trace-only user is refused: 403 no_role', async ({ playwright, baseURL }) => {
  const user = process.env['OCUTALON_TRACEONLY_USER'];
  const password = process.env['OCUTALON_TRACEONLY_PASSWORD'];
  expect(user && password, 'the trace-only fixture user is seeded').toBeTruthy();
  const trace = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  try {
    await expectError(await trace.post(STATE, { form: { IRISUsername: user!, IRISPassword: password!, IRISLogin: 'Sign in' } }), 403, 'no_role', NO_ROLE);
    await expectError(await trace.fetch(FILES, { method: 'POST', headers: envelope(), data: bodyOf('zzc', 'a.pdf', bytesOf('pdf')) }), 403, 'no_role', NO_ROLE);
  } finally {
    await trace.dispose();
  }
});

test('security (ii) and (iii): no route serves a file back, and the type comes from the bytes', async ({ request }) => {
  test.setTimeout(120_000);
  const live = fixtureUser('LIVE');
  await signInOverHttp(request, live.user, live.password);
  const session = await sessionRefOfUser(live.user);
  const prefix = `zzfilessec${Date.now()}`;
  const marker = `zzcontent${Date.now()}`;
  try {
    const stored = await post(request, FILES, bodyOf(`${prefix}a`, 'keep.pdf', bytesOf('pdf', marker)));
    expect(stored.status(), await stored.text()).toBe(202);
    const ref = ((await stored.json()) as { file: SentFile }).file.ref;
    const urls = [FILES, `${FILES}/${ref}`, `${FILES}/${ref}/content`, `/ocutalon/api/v1/documents/${ref}`];
    for (const url of urls) {
      for (const method of ['GET', 'PUT', 'DELETE', 'PATCH', 'POST'] as const) {
        if (method === 'POST' && url === FILES) continue;
        const response: APIResponse = await request.fetch(url, { method, headers: envelope(), data: method === 'GET' || method === 'DELETE' ? undefined : '{}' });
        const text = await response.text();
        // The documents route has its own verbs for /:ref (GET and DELETE answer 404 for a ref that is no document); its other verbs keep their 405.
        const documentsVerb = url.startsWith('/ocutalon/api/v1/documents/') && method !== 'GET' && method !== 'DELETE';
        expect(response.status(), `${method} ${url}: ${text}`).toBe(documentsVerb ? 405 : 404);
        if (!documentsVerb) expect(JSON.parse(text), `${method} ${url}`).toEqual({ error: { code: 'not_found', message: NOT_FOUND } });
        expect(text.includes(marker), `${method} ${url} sends no byte of the file`).toBe(false);
      }
    }

    // A renamed program or page is wrong_type whatever it is named and whatever type the body declares.
    const before = await rowsOf(session);
    const disguises: Array<[string, Buffer]> = [
      ['setup.pdf', bytesOf('exe')],
      ['page.png', bytesOf('html')],
      ['page.pdf', bytesOf('html')],
      ['setup.png', bytesOf('exe')],
      ['setup.docx', bytesOf('exe')],
    ];
    for (const [index, [name, bytes]] of disguises.entries()) {
      const response = await post(request, FILES, bodyOf(`${prefix}d${index}`, name, bytes, { mediaType: 'application/pdf', type: 'application/pdf' }));
      expect(response.status(), `${name}: ${await response.text()}`).toBe(400);
      expect(await response.json(), name).toEqual({ error: { code: 'bad_file', message: BAD_FILE }, reason: 'wrong_type', size: bytes.length });
    }
    expect(await rowsOf(session), 'and nothing was stored').toBe(before);
  } finally {
    await clean(session, prefix);
  }
});

test('isolation and the no-reader reply: a second session never sees the file, and the file turn gets the fixed reply with no model call', async ({ request, playwright, baseURL }) => {
  test.setTimeout(180_000);
  const live = fixtureUser('LIVE');
  const other = fixtureUser('PANEL');
  await signInOverHttp(request, live.user, live.password);
  const second = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  const first = await sessionRefOfUser(live.user);
  const prefix = `zzfilesiso${Date.now()}`;
  const marker = `zzmarker${Date.now()}`;
  const name = `zz<script>x-${Date.now()}.pdf`;
  let secondRef = '';
  try {
    await signInOverHttp(second, other.user, other.password);
    secondRef = await sessionRefOfUser(other.user);
    expect(secondRef, 'the second account is another session').not.toBe(first);

    // The mark: the highest message header, the highest event log row and the mock log's length.
    const marks = await irisScript(
      [
        'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(ID) FROM Ens.MessageHeader")',
        'Do rs.%Next()',
        'Write !,"CHK|header|",+rs.%GetData(1)',
        'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(ID) FROM Ens_Util.Log")',
        'Do rs.%Next()',
        'Write !,"CHK|log|",+rs.%GetData(1)',
      ].join('\n'),
    );
    const headerMark = Number(chk(marks, 'header'));
    const logMarkId = Number(chk(marks, 'log'));
    const mockMark = await logMark();
    const cursor = ((await (await request.get(STATE)).json()) as { streams: { session: number } }).streams.session;

    const sent = await post(request, FILES, bodyOf(`${prefix}a`, name, bytesOf('pdf', marker)));
    expect(sent.status(), await sent.text()).toBe(202);
    const file = ((await sent.json()) as { file: SentFile }).file;
    expect(file.name).toBe(name);
    const tooLongName = `${'q'.repeat(396)}.pdf`;
    expect(tooLongName.length).toBe(400);
    const longResponse = await post(request, FILES, bodyOf(`${prefix}b`, tooLongName, bytesOf('pdf', marker)));
    await expectError(longResponse, 400, 'bad_file', BAD_FILE);
    expect(await rowsOf(first), 'the 400-character name stored nothing: one row').toBe(1);

    // LIVE's state and events carry the sentFile; the second session's never do, and the second session's never reach LIVE.
    const done = await doneTurn(request, file.ref);
    expect(done['sentFile']).toEqual(file);
    expect(Object.keys(done['sentFile'] as object)).toEqual(['ref', 'name', 'mediaType', 'size']);
    expect(done['text'] ?? '', 'the turn has no text').toBe('');
    const events = await sessionEvents(request, cursor, (list) => list.some((event) => event.type === 'chat.message' && (event.payload['sentFile'] as SentFile | undefined)?.ref === file.ref && event.payload['state'] === 'done'));
    const published = events.filter((event) => event.type === 'chat.message' && (event.payload['sentFile'] as SentFile | undefined)?.ref === file.ref);
    expect(published.length, 'LIVE sees its own file in its events').toBeGreaterThanOrEqual(1);
    expect((await filesInState(second)).filter((payload) => (payload['sentFile'] as SentFile).ref === file.ref), "PANEL's state holds none of LIVE's files").toEqual([]);
    const otherStream = await second.get(`/ocutalon/api/v1/events?after=0&afterInstance=0`);
    expect(JSON.stringify(await otherStream.json()).includes(file.ref), "PANEL's events hold none of LIVE's files").toBe(false);
    const panelFile = await post(second, FILES, bodyOf(`${prefix}p`, 'panel.pdf', bytesOf('pdf', 'zzpanel')));
    expect(panelFile.status(), await panelFile.text()).toBe(202);
    const panelRef = ((await panelFile.json()) as { file: SentFile }).file.ref;
    await doneTurn(second, panelRef);
    expect((await filesInState(request)).some((payload) => (payload['sentFile'] as SentFile).ref === panelRef), "LIVE's state holds none of PANEL's files").toBe(false);

    // Ruling 4 (a tripwire for Story 26.2): the install cannot read a file, the reply is the fixed one, and no model was asked.
    const state = (await (await request.get(STATE)).json()) as { filesReadable: unknown };
    expect(state.filesReadable, 'filesReadable is false on this branch').toBe(false);
    expect(done['replyText']).toBe(`I got ${name}, but I can't read files yet.`);
    expect(done['fallbackReason'] ?? '', 'it is no fallback').toBe('');

    // Security condition (iv): the content marker is in no message, no log row, no Turn field and no mock request.
    const hits = await irisScript(
      [
        `Write !,"CHK|marker|",##class(OcuTalon.Test.Eval.KeyProof).TraceHits(${quoted(marker)},${headerMark})`,
        `Write !,"CHK|ref|",##class(OcuTalon.Test.Eval.KeyProof).TraceHits(${quoted(file.ref)},${headerMark})`,
        `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND (Text [ ? OR Text [ ? OR Text [ ?)",${logMarkId},${quoted(marker)},${quoted(name)},${quoted('q'.repeat(100))})`,
        'Do rs.%Next()',
        'Write !,"CHK|log|",rs.%GetData(1)',
        `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Text, SentFile, ReplyText, ItemId FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ClientId = ?",${quoted(first)},${quoted(`${prefix}a`)})`,
        'Do rs.%Next()',
        'Write !,"CHK|turntext|",rs.%GetData(1)',
        'Write !,"CHK|sentfile|",rs.%GetData(2)',
        'Write !,"CHK|reply|",rs.%GetData(3)',
        'Set item=rs.%GetData(4)',
        'Write !,"CHK|item|",item',
        'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?",item)',
        'Do rs.%Next()',
        'Write !,"CHK|decisions|",rs.%GetData(1)',
        `Set sc=##class(OcuTalon.Test.Contract.Mock).LogSince(${mockMark},.entries)`,
        `Set marker=${quoted(marker)},name=${quoted(name)},n=0,named=0,i=entries.%GetIterator()`,
        'While i.%GetNext(,.entry) { Set json=entry.%ToJSON() Set:$Find(json,marker) n=n+1 Set:((entry.path="/v1/messages")&&$Find(json,name)) named=named+1 }',
        'Write !,"CHK|mockmarker|",n',
        'Write !,"CHK|mocknamed|",named',
      ].join('\n'),
    );
    expect(Number(chk(hits, 'marker')), 'the marker is in no production message').toBe(0);
    expect(Number(chk(hits, 'ref')), 'the positive control: the file ref is found in the messages').toBeGreaterThanOrEqual(1);
    expect(Number(chk(hits, 'log')), 'the marker, the name and the long name are in no event log row').toBe(0);
    expect(chk(hits, 'turntext') ?? '', "the Turn's Text is empty").toBe('');
    const sentFile = JSON.parse(chk(hits, 'sentfile') ?? '{}') as Record<string, unknown>;
    expect(Object.keys(sentFile), "the Turn's SentFile has the four keys").toEqual(['ref', 'name', 'mediaType', 'size']);
    expect(JSON.stringify(sentFile).includes(marker)).toBe(false);
    expect(chk(hits, 'reply')).toBe(`I got ${name}, but I can't read files yet.`);
    expect(Number(chk(hits, 'decisions')), "the turn's Item has no Decision of any kind").toBe(0);
    expect(Number(chk(hits, 'mockmarker')), 'the marker is in no mock request').toBe(0);
    expect(Number(chk(hits, 'mocknamed')), 'no model request names the file').toBe(0);
  } finally {
    await clean(first, prefix);
    if (secondRef) await clean(secondRef, prefix);
    await second.dispose();
  }
});
