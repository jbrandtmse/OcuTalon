import { expect, test, type Locator, type Page, type Request } from '../support/fixtures';

import { signIn, signInOverHttp } from '../sign-in/helpers';
import { changeSnapshot, post } from '../support/api';
import { loadedAfter } from '../support/floor';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { sessionRefOfUser } from '../support/memory';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 25.3, sending a file from the chat, in a real browser against a real stack. Every case stubs /state with `changeSnapshot`, setting `filesReadable` and
 * `onlineDemo` itself, so that no case depends on this branch's flag (the paperclip is hidden on every real state until Story 26.2 makes the install able to read a file);
 * the route and the turn are the real ones, so the reply is the real no-reader reply, "I got {name}, but I can't read files yet.". Each case signs in as the panel
 * fixture user and removes the file rows and the file turns of its session afterwards. A fixture file has the real signature of its type.
 */
const FILES = '/ocutalon/api/v1/files';
const MB = 1048576;
const DOT = ' \u00B7 ';
const WRONG_TYPE = "I couldn't read that file: it isn't a PDF, Word (.docx), JPEG or PNG file.";
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

const TYPES: Array<{ name: string; mimeType: string; buffer: () => Buffer }> = [
  { name: 'zz-report.pdf', mimeType: 'application/pdf', buffer: pdf },
  { name: 'zz-letter.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', buffer: docx },
  { name: 'zz-photo.jpg', mimeType: 'image/jpeg', buffer: jpeg },
  { name: 'zz-scan.png', mimeType: 'image/png', buffer: png },
];

for (const type of TYPES) {
  test(`the paperclip by keyboard sends ${type.name}: the chip shows its name and size, the reply is the fixed one, and both survive a reload`, async ({ page }) => {
    const posts = watchFilePosts(page);
    await open(page, { filesReadable: true, onlineDemo: false });
    const button = paperclip(page);
    await expect(button, 'the paperclip has its accessible name').toBeVisible();
    // Tab order: the paperclip comes before the field, so Shift+Tab from the field reaches it.
    await page.getByRole('textbox', { name: 'Message OcuTalon' }).focus();
    await page.keyboard.press('Shift+Tab');
    await expect(button).toBeFocused();
    const chooser = page.waitForEvent('filechooser');
    await page.keyboard.press('Enter');
    const bytes = type.buffer();
    await (await chooser).setFiles({ name: type.name, mimeType: type.mimeType, buffer: bytes });
    const line = `${type.name}${DOT}${sizeOf(bytes.length)}`;
    await expect(chips(page).filter({ hasText: line }), "the user's message shows the file's name and size").toBeVisible({ timeout: 30_000 });
    await expect(chat(page).getByText(`I got ${type.name}, but I can't read files yet.`)).toBeVisible({ timeout: 60_000 });
    expect(posts(), 'one request').toBe(1);
    await expect(refusal(page)).toHaveCount(0);
    await loadedAfter(page, () => page.reload());
    await expect(chips(page).filter({ hasText: line })).toBeVisible();
    await expect(chat(page).getByText(`I got ${type.name}, but I can't read files yet.`)).toBeVisible();
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
  await surface.dispatchEvent('dragover', { dataTransfer: transfer });
  await expect(surface, 'the chat shows the outline while a file is over it').toHaveClass(/dragging/);
  await surface.dispatchEvent('drop', { dataTransfer: transfer });
  await expect(surface).not.toHaveClass(/dragging/);
  await expect(chips(page).filter({ hasText: `zz-dropped.pdf${DOT}1 KB` })).toBeVisible({ timeout: 30_000 });
  await expect(chat(page).getByText("I got zz-dropped.pdf, but I can't read files yet.")).toBeVisible({ timeout: 60_000 });
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
  await fileInput(page).setInputFiles({ name: 'zz-empty.pdf', mimeType: 'application/pdf', buffer: Buffer.alloc(0) });
  await expect(refusal(page)).toHaveText("I couldn't read that file: the file is empty.");
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

test('a name with markup renders as text in the chip and in the reply', async ({ page }) => {
  await open(page, { filesReadable: true, onlineDemo: false });
  const name = 'zz<b>bold</b><script>x</script>.pdf';
  await fileInput(page).setInputFiles({ name, mimeType: 'application/pdf', buffer: pdf() });
  await expect(chips(page).filter({ hasText: name })).toBeVisible({ timeout: 30_000 });
  await expect(chat(page).getByText(`I got ${name}, but I can't read files yet.`)).toBeVisible({ timeout: 60_000 });
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
  await surface.dispatchEvent('dragover', { dataTransfer: transfer });
  await surface.dispatchEvent('drop', { dataTransfer: transfer });
  await expect(surface).not.toHaveClass(/dragging/);
  await expect(refusal(page)).toHaveCount(0);
  await expect(page.getByText(OFF_ON_DEMO)).toHaveCount(0);
  expect(posts()).toBe(0);
});

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
  const session = await sessionRefOfUser(live.user);
  try {
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
