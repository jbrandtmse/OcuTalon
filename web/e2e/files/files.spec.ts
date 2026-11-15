import { expect, test, type JSHandle, type Locator, type Page, type Request } from '../support/fixtures';

import { envelope, signIn, signInOverHttp } from '../sign-in/helpers';
import { STATE, changeSnapshot, post } from '../support/api';
import { pointKeys, restoreKeys } from '../support/devices';
import { loadedAfter } from '../support/floor';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { sessionRefOfUser } from '../support/memory';
import { announcements, recordAnnouncements } from '../support/page';
import { textPdf } from '../support/pdf';

/**
 * Story 25.3, sending a file from the chat, in a real browser against a real stack (Story 25.6 turned the reader on). Most cases stub /state with `changeSnapshot`, setting
 * `filesReadable` and `onlineDemo` itself; the real-state case does not, and shows the paperclip. The route and the turn are the real ones: a fixture file has the real signature of
 * its type but is no readable document, so its reply is the real failure sentence, "I couldn't read that file: it's damaged or incomplete."; a readable PDF (a text PDF built by
 * support/pdf.ts) gets the mock's reply and the Add to documents button, and a snapshot that holds a photo's caption shows the Saved to memory chip. Each case signs in as the
 * panel fixture user and removes the file rows, the file turns and the documents of its session afterwards.
 */
const FILES = '/ocutalon/api/v1/files';
const MB = 1048576;
const DOT = ' \u00B7 ';
const WRONG_TYPE = "I couldn't read that file: it isn't a PDF, Word (.docx), JPEG or PNG file.";
const DAMAGED = "I couldn't read that file: it's damaged or incomplete.";
const DOCUMENTS = '/ocutalon/api/v1/documents';
const OFF_ON_DEMO = 'Sending files is off on the online demo. It works on your own install.';

const pdf = (marker = 'zz'): Buffer => Buffer.from(`%PDF-1.4 ${marker}`);
const png = (): Buffer => Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from('IHDR zz')]);
const jpeg = (): Buffer => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from('JFIF zz')]);
const docx = (): Buffer => {
  const name = Buffer.from('word/document.xml');
  const body = Buffer.from('zz');
  const header = Buffer.alloc(30);
  header.write('PK\u0003\u0004', 0, 'latin1');
  header.writeUInt16LE(20, 4);
  header.writeUInt32LE(body.length, 18);
  header.writeUInt32LE(body.length, 22);
  header.writeUInt16LE(name.length, 26);
  return Buffer.concat([header, name, body]);
};

const paperclip = (page: Page): Locator => page.getByRole('button', { name: 'Send a file', exact: true });
const chips = (page: Page): Locator => page.locator('app-file-chip');
const refusal = (page: Page): Locator => page.locator('p.file-refusal');
const fileInput = (page: Page): Locator => page.locator('app-composer input[type="file"]');
const chat = (page: Page): Locator => page.locator('app-chat-panel');
const addButton = (page: Page): Locator => page.getByRole('button', { name: 'Add to documents', exact: true });
const savedChip = (page: Page): Locator => chat(page).getByText('Saved to memory', { exact: true });

/** Dispatches a drag event of that type with the transfer on the element and says whether a handler took it: true when one cancelled the browser's own handling. */
async function taken(target: Locator, type: 'dragover' | 'drop', transfer: JSHandle<DataTransfer>): Promise<boolean> {
  return target.evaluate(
    (element, [kind, data]) => {
      const event = new DragEvent(kind, { bubbles: true, cancelable: true, dataTransfer: data });
      element.dispatchEvent(event);
      return event.defaultPrevented;
    },
    [type, transfer] as const,
  );
}

/** A transfer that carries text and no file, as a drag of selected words does. */
async function textTransfer(page: Page): Promise<JSHandle<DataTransfer>> {
  return page.evaluateHandle(() => {
    const data = new DataTransfer();
    data.setData('text/plain', 'zz dragged words');
    return data;
  });
}

/** The bodies' paths of the page's file posts, as they are made. */
function watchFilePosts(page: Page): () => number {
  let count = 0;
  page.on('request', (request: Request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === FILES) count += 1;
  });
  return () => count;
}

/** Signs the panel user in with /state changed to the two flags, and waits for the loaded page with its composer. */
async function open(page: Page, flags: { filesReadable: boolean; onlineDemo: boolean }): Promise<void> {
  await changeSnapshot(page, (snapshot) => {
    snapshot['filesReadable'] = flags.filesReadable;
    snapshot['onlineDemo'] = flags.onlineDemo;
  });
  const { user, password } = fixtureUser('PANEL');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('textbox', { name: 'Message OcuTalon' })).toBeVisible();
}

/** Removes the file rows and the file turns of the panel session. */
async function clean(user: string): Promise<void> {
  const session = await sessionRefOfUser(user);
  await irisScript(
    [
      `Do ##class(OcuTalon.Data.SentFile).DropSession(${quoted(session)})`,
      `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND SentFile IS NOT NULL AND SentFile <> ''",${quoted(session)})`,
      'Write !,"CHK|cleaned|1"',
    ].join('\n'),
  );
}

test.afterEach(async () => {
  await clean(fixtureUser('PANEL').user);
});

/** The size line that the chip shows for a fixture file of that many bytes (under 1 MB it is whole KB, rounded up). */
const sizeOf = (bytes: number): string => `${Math.ceil(bytes / 1024)} KB`;

const TYPES: Array<{ name: string; mimeType: string; buffer: () => Buffer; way: 'Enter' | 'Space' | 'click' }> = [
  { name: 'zz-report.pdf', mimeType: 'application/pdf', buffer: pdf, way: 'Enter' },
  { name: 'zz-letter.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', buffer: docx, way: 'Space' },
  { name: 'zz-photo.jpg', mimeType: 'image/jpeg', buffer: jpeg, way: 'click' },
  { name: 'zz-scan.png', mimeType: 'image/png', buffer: png, way: 'Enter' },
];

for (const type of TYPES) {
  test(`the paperclip (${type.way === 'click' ? 'by mouse' : `by keyboard, ${type.way}`}) sends ${type.name}: the chip shows its name and size, the turn answers, and both survive a reload`, async ({ page }) => {
    const posts = watchFilePosts(page);
    await open(page, { filesReadable: true, onlineDemo: false });
    const button = paperclip(page);
    await expect(button, 'the paperclip has its accessible name').toBeVisible();
    // Tab order: the paperclip comes before the field, so Shift+Tab from the field reaches it.
    await page.getByRole('textbox', { name: 'Message OcuTalon' }).focus();
    await page.keyboard.press('Shift+Tab');
    await expect(button).toBeFocused();
    const chooser = page.waitForEvent('filechooser');
    if (type.way === 'click') await button.click();
    else await page.keyboard.press(type.way);
    const bytes = type.buffer();
    await (await chooser).setFiles({ name: type.name, mimeType: type.mimeType, buffer: bytes });
    const line = `${type.name}${DOT}${sizeOf(bytes.length)}`;
    await expect(chips(page).filter({ hasText: line }), "the user's message shows the file's name and size").toBeVisible({ timeout: 30_000 });
    // The fixture bytes carry the real signature but no readable document: a PDF or Word file is read as damaged. A photo is sent to the model, whose answer the stack decides.
    const answered = type.mimeType.startsWith('image/') ? chat(page).locator('app-ocutalon-reply .text') : chat(page).getByText(DAMAGED);
    await expect(answered.first()).toBeVisible({ timeout: 90_000 });
    expect(posts(), 'one request').toBe(1);
    await expect(refusal(page)).toHaveCount(0);
    await expect(addButton(page), 'a file that was not read has no Add to documents').toHaveCount(0);
    await loadedAfter(page, () => page.reload());
    await expect(chips(page).filter({ hasText: line })).toBeVisible();
    await expect(answered.first()).toBeVisible();
  });
}

test('a drop on the chat is the second way', async ({ page }) => {
  const posts = watchFilePosts(page);
  await open(page, { filesReadable: true, onlineDemo: false });
  const transfer = await page.evaluateHandle(() => {
    const data = new DataTransfer();
    data.items.add(new File(['%PDF-1.4 dropped'], 'zz-dropped.pdf', { type: 'application/pdf' }));
    return data;
  });
  const surface = page.locator('app-chat-panel');
  const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
  expect(await taken(field, 'drop', await textTransfer(page)), 'a drop of text on the field is left to the field').toBe(false);
  await surface.dispatchEvent('dragover', { dataTransfer: transfer });
  await expect(surface, 'the chat shows the outline while a file is over it').toHaveClass(/dragging/);
  await surface.dispatchEvent('drop', { dataTransfer: transfer });
  await expect(surface).not.toHaveClass(/dragging/);
  await expect(chips(page).filter({ hasText: `zz-dropped.pdf${DOT}1 KB` })).toBeVisible({ timeout: 30_000 });
  await expect(chat(page).getByText(DAMAGED)).toBeVisible({ timeout: 60_000 });
  expect(posts()).toBe(1);
});

test('refusals before anything is sent: 14 MB, a .txt and an empty .pdf, each with its sentence and announced', async ({ page }) => {
  const posts = watchFilePosts(page);
  await recordAnnouncements(page);
  await open(page, { filesReadable: true, onlineDemo: false });
  await fileInput(page).setInputFiles({ name: 'zz-big.pdf', mimeType: 'application/pdf', buffer: Buffer.alloc(14 * MB, 0x20) });
  await expect(refusal(page)).toHaveText('That file is 14 MB; the limit is 10 MB.');
  await expect.poll(() => announcements(page, 'That file is 14 MB; the limit is 10 MB.')).toBeGreaterThanOrEqual(1);
  await fileInput(page).setInputFiles({ name: 'zz-notes.txt', mimeType: 'text/plain', buffer: Buffer.from('plain text') });
  await expect(refusal(page)).toHaveText(WRONG_TYPE);
  await expect.poll(() => announcements(page, WRONG_TYPE)).toBeGreaterThanOrEqual(1);
  await fileInput(page).setInputFiles({ name: 'zz-empty.pdf', mimeType: 'application/pdf', buffer: Buffer.alloc(0) });
  await expect(refusal(page)).toHaveText("I couldn't read that file: the file is empty.");
  await expect.poll(() => announcements(page, "I couldn't read that file: the file is empty.")).toBeGreaterThanOrEqual(1);
  expect(posts(), 'no request was sent for any of the three').toBe(0);
  await expect(chips(page)).toHaveCount(0);
});

test('a renamed program: the page sends setup.pdf, the server reads its bytes and the page shows the wrong-type sentence, with no chip', async ({ page }) => {
  const posts = watchFilePosts(page);
  await open(page, { filesReadable: true, onlineDemo: false });
  const answered = page.waitForResponse((response) => response.request().method() === 'POST' && new URL(response.url()).pathname === FILES);
  await fileInput(page).setInputFiles({ name: 'setup.pdf', mimeType: 'application/pdf', buffer: Buffer.concat([Buffer.from('MZ'), Buffer.from([0x90, 0x00, 0x03, 0x00]), Buffer.from('zz')]) });
  expect((await answered).status()).toBe(400);
  await expect(refusal(page)).toHaveText(WRONG_TYPE);
  expect(posts(), 'the pre-check passed it by its extension').toBe(1);
  await expect(chips(page)).toHaveCount(0);
});

test('a refusal from the server shows its sentence: 400 with a reason and size, 413, 409, and any other failure as "File not sent"', async ({ page }) => {
  await recordAnnouncements(page);
  await open(page, { filesReadable: true, onlineDemo: false });
  const answers: Array<{ status: number; body: Record<string, unknown>; text: string }> = [
    { status: 400, body: { error: { code: 'bad_file', message: 'x' }, reason: 'too_large', size: 14 * MB }, text: 'That file is 14 MB; the limit is 10 MB.' },
    { status: 400, body: { error: { code: 'bad_file', message: 'x' }, reason: 'empty', size: 0 }, text: "I couldn't read that file: the file is empty." },
    { status: 413, body: { error: { code: 'body_too_large', message: 'x' } }, text: 'That file is 1 KB; the limit is 10 MB.' },
    { status: 409, body: { error: { code: 'not_available', message: 'x' } }, text: OFF_ON_DEMO },
    { status: 500, body: { error: { code: 'server_error', message: 'x' } }, text: 'File not sent' },
  ];
  for (const answer of answers) {
    await page.route(`**${FILES}`, (route) => route.fulfill({ status: answer.status, contentType: 'application/json', body: JSON.stringify(answer.body) }));
    await fileInput(page).setInputFiles({ name: 'zz-stub.pdf', mimeType: 'application/pdf', buffer: pdf() });
    await expect(refusal(page)).toHaveText(answer.text);
    await expect.poll(() => announcements(page, answer.text)).toBeGreaterThanOrEqual(1);
    await page.unroute(`**${FILES}`);
  }
  await expect(chips(page)).toHaveCount(0);
});

test('a name with markup renders as text in the chip', async ({ page }) => {
  await open(page, { filesReadable: true, onlineDemo: false });
  const name = 'zz<b>bold</b><script>x</script>.pdf';
  await fileInput(page).setInputFiles({ name, mimeType: 'application/pdf', buffer: pdf() });
  await expect(chips(page).filter({ hasText: name })).toBeVisible({ timeout: 30_000 });
  await expect(chat(page).getByText(DAMAGED)).toBeVisible({ timeout: 60_000 });
  await expect(chat(page).locator('b, script'), 'no such element in the chat').toHaveCount(0);
});

test('with filesReadable false there is no paperclip, and a drop sends nothing and shows nothing', async ({ page }) => {
  const posts = watchFilePosts(page);
  await open(page, { filesReadable: false, onlineDemo: false });
  await expect(paperclip(page)).toHaveCount(0);
  const transfer = await page.evaluateHandle(() => {
    const data = new DataTransfer();
    data.items.add(new File(['%PDF-1.4 dropped'], 'zz-ignored.pdf', { type: 'application/pdf' }));
    return data;
  });
  const surface = page.locator('app-chat-panel');
  expect(await taken(surface, 'dragover', transfer), 'no handler takes the drag').toBe(false);
  expect(await taken(surface, 'drop', transfer), 'nor the drop: the browser keeps its own handling').toBe(false);
  await expect(surface).not.toHaveClass(/dragging/);
  await expect(refusal(page)).toHaveCount(0);
  await expect(page.getByText(OFF_ON_DEMO)).toHaveCount(0);
  expect(posts()).toBe(0);
});

test('on the real state, with no stub, the paperclip is visible because the install reads files (Story 25.6 flipped the flag)', async ({ page }) => {
  // No changeSnapshot here: this is the page as every real install shows it. The stubbed cases above cannot hide a regression of the real flag.
  const { user, password } = fixtureUser('PANEL');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('textbox', { name: 'Message OcuTalon' })).toBeVisible();
  const state = (await (await page.request.get(STATE)).json()) as Record<string, unknown>;
  expect(state['filesReadable'], 'the real /v1/state says the install can read a file').toBe(true);
  expect(state['onlineDemo'], 'and it is no online demo').toBe(false);
  await expect(paperclip(page)).toBeVisible();
  await expect(fileInput(page)).toHaveCount(1);
});

test('a readable PDF: the reply shows Add to documents, Enter adds it, the line replaces the button, and the Documents page lists the file', async ({ page }) => {
  test.setTimeout(240_000);
  await recordAnnouncements(page);
  const name = `zz-readable-${Date.now()}.pdf`;
  await pointKeys();
  try {
    await open(page, { filesReadable: true, onlineDemo: false });
    const chooser = page.waitForEvent('filechooser');
    await paperclip(page).click();
    await (await chooser).setFiles({ name, mimeType: 'application/pdf', buffer: textPdf('[[mock:file-read]] zz25s6 readable page') });
    await expect(chat(page).getByText('The CI mock read the file you sent.')).toBeVisible({ timeout: 120_000 });
    const button = addButton(page);
    await expect(button, 'a native button under the reply').toBeVisible();
    expect(await button.evaluate((element) => element.tagName), 'it is a button').toBe('BUTTON');
    await expect(savedChip(page), 'and no memory chip for a document').toHaveCount(0);
    const posted = page.waitForRequest((request) => request.method() === 'POST' && new URL(request.url()).pathname === DOCUMENTS);
    await button.focus();
    await page.keyboard.press('Enter');
    expect(JSON.parse((await posted).postData() ?? '{}'), 'the page posts the fileRef, no bytes').toEqual({ fileRef: expect.stringMatching(/^[A-Za-z0-9_-]{22}$/) });
    await expect(chat(page).getByText('Added to your documents.')).toBeVisible({ timeout: 30_000 });
    await expect(chat(page).getByText('Added to your documents.'), 'focus moves to the added line, because the pressed button is gone').toBeFocused();
    await expect.poll(() => announcements(page, 'Added to your documents.'), { message: 'the line is announced once, through the one live region' }).toBe(1);
    await expect(button, 'the line replaces the button').toHaveCount(0);
    await page.getByRole('navigation', { name: 'Pages', exact: true }).getByRole('link', { name: 'Documents', exact: true }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Documents');
    await expect(page.locator('li.row').filter({ hasText: name }), 'the Documents page lists the file under its stored name').toBeVisible({ timeout: 90_000 });
  } finally {
    // Removes the document through the real route, also after a failure above, so that none is left behind.
    const listed = await page.request.get(DOCUMENTS);
    const refs = listed.ok() ? ((await listed.json()) as { documents: Array<{ ref: string; name: string }> }).documents.filter((one) => one.name === name).map((one) => one.ref) : [];
    for (const ref of refs) await page.request.fetch(`${DOCUMENTS}/${encodeURIComponent(ref)}`, { method: 'DELETE', headers: envelope(), data: '{}' });
    await restoreKeys();
  }
});

test('a turn that failed to add shows the failure line and keeps the button, and a pending add disables it', async ({ page }) => {
  await recordAnnouncements(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['filesReadable'] = true;
    snapshot['onlineDemo'] = false;
    snapshot['chat'] = [chatItem({ fileRead: { fileRef: 'zzAddFailRef0000000000', kind: 'document', read: 1, addable: 1 } })];
  });
  const { user, password } = fixtureUser('PANEL');
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  let documentPosts = 0;
  await page.route(`**${DOCUMENTS}`, async (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    documentPosts += 1;
    await gate;
    return route.fulfill({ status: 500, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"zz"}}' });
  });
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(addButton(page)).toBeVisible();
  await addButton(page).click();
  await expect(addButton(page), 'disabled while the post is out').toBeDisabled();
  await addButton(page).click({ force: true });
  await expect.poll(() => documentPosts, { message: 'one press and a forced second press while the post is out make exactly one post' }).toBe(1);
  release();
  await expect(chat(page).getByText("Couldn't add it to your documents. Nothing was changed.")).toBeVisible();
  await expect.poll(() => announcements(page, "Couldn't add it to your documents. Nothing was changed.")).toBe(1);
  await expect(addButton(page), 'the button stays').toBeEnabled();
  expect(documentPosts, 'a second press while the post was out sent nothing').toBe(1);
});

test('a snapshot item with a saved caption shows the Saved to memory chip and no button; a turn with neither shows no control', async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['filesReadable'] = true;
    snapshot['onlineDemo'] = false;
    snapshot['chat'] = [
      chatItem({ ref: 'zzCapturn00000000000a', fileRead: { fileRef: 'zzCapRef00000000000000', kind: 'photo', read: 1, addable: 0 }, caption: { memoryRef: 'zzmem1', text: 'A red square on white.' }, replyText: 'A red square on white.' }),
      chatItem({ ref: 'zzNonturn00000000000b', replyText: 'Plain answer with no file.' }),
    ];
  });
  const { user, password } = fixtureUser('PANEL');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(savedChip(page)).toHaveCount(1);
  await expect(addButton(page), 'a photo has no Add button').toHaveCount(0);
  await expect(chat(page).getByText('Plain answer with no file.')).toBeVisible();
  await expect(chat(page).locator('app-file-reply'), 'only the photo turn mounts the controls').toHaveCount(1);
});

/** A done chat.message for the stubbed snapshots, with the members that the case sets. */
function chatItem(over: Record<string, unknown>): { type: string; payload: Record<string, unknown> } {
  return {
    type: 'chat.message',
    payload: {
      ref: 'zzStubTurn0000000000c',
      clientId: 'zzstubclient',
      channel: 'web',
      fromGuide: false,
      state: 'done',
      text: '',
      replyText: 'The CI mock read the file you sent.',
      createdAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
      ...over,
    },
  };
}

test('on the online demo there is no paperclip, and a drop shows the off text', async ({ page }) => {
  const posts = watchFilePosts(page);
  await open(page, { filesReadable: true, onlineDemo: true });
  await expect(paperclip(page)).toHaveCount(0);
  const transfer = await page.evaluateHandle(() => {
    const data = new DataTransfer();
    data.items.add(new File(['%PDF-1.4 dropped'], 'zz-demo.pdf', { type: 'application/pdf' }));
    return data;
  });
  const surface = page.locator('app-chat-panel');
  // A drag of text into the field is the field's own: the drop is not taken, and no off text shows for it.
  expect(await taken(page.getByRole('textbox', { name: 'Message OcuTalon' }), 'drop', await textTransfer(page)), 'a drop of text on the field is left to the field').toBe(false);
  await expect(refusal(page)).toHaveCount(0);
  await surface.dispatchEvent('dragover', { dataTransfer: transfer });
  await surface.dispatchEvent('drop', { dataTransfer: transfer });
  await expect(refusal(page)).toHaveText(OFF_ON_DEMO);
  expect(posts(), 'nothing was sent').toBe(0);
});

test("a second session never sees another session's file", async ({ page, request }) => {
  const live = fixtureUser('LIVE');
  await signInOverHttp(request, live.user, live.password);
  const name = `zz-live-only-${Date.now()}.pdf`;
  const sent = await post(request, FILES, JSON.stringify({ clientId: `zzfilesui${Date.now()}`, name, content: pdf().toString('base64') }));
  expect(sent.status(), await sent.text()).toBe(202);
  const ref = ((await sent.json()) as { file: { ref: string } }).file.ref;
  const session = await sessionRefOfUser(live.user);
  try {
    // The positive control: LIVE's own state shows the file's turn, so its absence on PANEL's page is isolation, not a turn that never came.
    await expect.poll(async () => JSON.stringify(await (await request.get(STATE)).json()).includes(ref), { timeout: 30_000 }).toBe(true);
    await open(page, { filesReadable: true, onlineDemo: false });
    await expect(chat(page).getByText(name)).toHaveCount(0);
    await expect(chips(page).filter({ hasText: name })).toHaveCount(0);
  } finally {
    const lines = await irisScript(
      [
        `Do ##class(OcuTalon.Data.SentFile).DropSession(${quoted(session)})`,
        `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ClientId %STARTSWITH 'zzfilesui'",${quoted(session)})`,
        'Write !,"CHK|cleaned|1"',
      ].join('\n'),
    );
    expect(chk(lines, 'cleaned')).toBe('1');
  }
});
