# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: documents/documents.spec.ts >> D5: Add documents works by keyboard, and a .png is refused with its reason
- Location: e2e/documents/documents.spec.ts:139:5

# Error details

```
TimeoutError: page.waitForEvent: Timeout 30000ms exceeded while waiting for event "filechooser"
=========================== logs ===========================
waiting for event "filechooser"
============================================================
```

```
TimeoutError: page.waitForResponse: Timeout 30000ms exceeded while waiting for event "response"
```

# Page snapshot

```yaml
- generic [ref=f1e2]:
  - banner [ref=f1e4]:
    - generic [ref=f1e5]:
      - link "OcuTalon" [ref=f1e6] [cursor=pointer]:
        - /url: "#/"
      - generic [ref=f1e8]: Demo mode
      - generic [ref=f1e9]:
        - switch "Demo view" [checked] [ref=f1e10] [cursor=pointer]
        - generic [ref=f1e14]: Off shows the page as it looks on your own install.
      - navigation "Pages" [ref=f1e16]:
        - link "Chat" [ref=f1e17] [cursor=pointer]:
          - /url: "#/"
        - link "Settings" [ref=f1e18] [cursor=pointer]:
          - /url: "#/settings"
        - link "Documents" [ref=f1e19] [cursor=pointer]:
          - /url: "#/documents"
    - generic [ref=f1e20]:
      - button "Visual Trace" [ref=f1e21] [cursor=pointer]
      - 'button "Theme: System" [ref=f1e28] [cursor=pointer]'
      - button "ocutalon" [ref=f1e36] [cursor=pointer]
  - generic [ref=f1e43]:
    - generic [ref=f1e47]: OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon.
    - link "How to set a key (opens in a new tab)" [ref=f1e48] [cursor=pointer]:
      - /url: https://github.com/jbrandtmse/OcuTalon#set-a-model-key
      - text: How to set a key
      - generic [ref=f1e54]: (opens in a new tab)
  - main [ref=f1e56]:
    - heading "Documents" [level=1] [ref=f1e57]
    - button "Add documents" [active] [ref=f1e59] [cursor=pointer]
    - region "Documents" [ref=f1e60]:
      - paragraph [ref=f1e61]: No documents yet. Add a runbook to get cited answers.
```

# Test source

```ts
  1   | import { expect, test, type Locator, type Page, type Response } from '../support/fixtures';
  2   | 
  3   | import { README_ACCOUNT, signIn } from '../sign-in/helpers';
  4   | import { CARD_MS, loadedAfter, signInReadmeLoaded, unique } from '../support/floor';
  5   | import { publishFixtureEvent } from '../support/devices';
  6   | import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted } from '../support/iris';
  7   | import { announcements, recordAnnouncements } from '../support/page';
  8   | 
  9   | /**
  10  |  * Story 34.2, the Documents page (D1 to D13), in a real browser against a real stack: the README account is signed in (D13: a user without
  11  |  * OcuTalonAdmin), the fixture documents are owned by `instance` (a local install shows them to every user) and are removed after each case. Until Story 19.4 builds DocumentOps, a
  12  |  * valid add and a remove reach a disabled item, so the real routes answer an error; the cases that need the done answer fulfil it in the
  13  |  * browser (page.route). The refusals (D5 to D7) and the 10 MB case (D8, which also measures that the web layer lets a 10 MB PDF through,
  14  |  * FR-54) use the real route.
  15  |  */
  16  | const DOCUMENTS = '/ocutalon/api/v1/documents';
  17  | const TITLE = 'Documents \u00B7 OcuTalon';
  18  | const INDEXING = 'Indexing\u2026';
  19  | const EMPTY = 'No documents yet. Add a runbook to get cited answers.';
  20  | const WRONG_TYPE = "Couldn't read it: it isn't a Markdown, plain-text, PDF or Word (.docx) file.";
  21  | const FAILED = "Couldn't read it: something went wrong inside OcuTalon.";
  22  | const UNREADABLE = "Couldn't read it: OcuTalon found no text in it.";
  23  | const NOT_BUILT = "Couldn't read it: this part of OcuTalon isn't built yet.";
  24  | const MB = 1048576;
  25  | 
  26  | const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
  27  | const documentsLink = (page: Page): Locator => pagesNav(page).getByRole('link', { name: 'Documents', exact: true });
  28  | const rowsOf = (page: Page, name: string): Locator => page.locator('li.row').filter({ hasText: name });
  29  | const listRegion = (page: Page): Locator => page.getByRole('region', { name: 'Documents', exact: true });
  30  | const fileInput = (page: Page): Locator => page.locator('input[type="file"]');
  31  | 
  32  | /** The refs of the fixture rows a case made, removed after it. */
  33  | const made: string[] = [];
  34  | 
  35  | test.afterEach(async () => {
  36  |   await cleanFixtureRows(made.splice(0));
  37  | });
  38  | 
  39  | /** A fixture document owned by the install, with its properties given as strings; returns its Ref. */
  40  | async function seed(name: string, fields: Record<string, string> = {}): Promise<string> {
  41  |   const lines = await irisScript(
  42  |     [
  43  |       `Set ref=##class(OcuTalon.Test.Data.Fixture).Document("instance",${quoted(name)},##class(%DynamicObject).%FromJSON(${quoted(JSON.stringify(fields))}))`,
  44  |       'Write !,"CHK|ref|",ref',
  45  |     ].join('\n'),
  46  |   );
  47  |   const ref = chk(lines, 'ref');
  48  |   if (!ref) throw new Error(`the fixture document could not be made (${lines.join(' ')})`);
  49  |   made.push(ref);
  50  |   return ref;
  51  | }
  52  | 
  53  | /** Publishes the `document` event of a document on the README account's session stream. */
  54  | function publish(ref: string, name: string, fields: Record<string, string>): Promise<number> {
  55  |   return publishFixtureEvent(README_ACCOUNT.user, 'document', 'OcuTalon.Live.Payload.Document', { Ref: ref, Name: name, ...fields });
  56  | }
  57  | 
  58  | /** Signs the README account in and opens the Documents page from the header. */
  59  | async function openDocuments(page: Page): Promise<void> {
  60  |   await signInReadmeLoaded(page);
  61  |   const listed = page.waitForResponse((response) => response.request().method() === 'GET' && new URL(response.url()).pathname === DOCUMENTS);
  62  |   listed.catch(() => undefined);
  63  |   await documentsLink(page).click();
  64  |   expect((await listed).status(), 'GET /v1/documents').toBe(200);
  65  |   await expect(page.getByRole('heading', { level: 1 })).toHaveText('Documents');
  66  | }
  67  | 
  68  | /** The answer of the next POST of a document. */
> 69  | const posted = (page: Page): Promise<Response> => page.waitForResponse((response) => response.request().method() === 'POST' && new URL(response.url()).pathname === DOCUMENTS);
      |                                                        ^ TimeoutError: page.waitForResponse: Timeout 30000ms exceeded while waiting for event "response"
  70  | 
  71  | /** D1: the header link, the address, the title, the h1 and the current mark, and no skip links. */
  72  | test('D1: Documents is in the header for every signed-in user and opens the page', async ({ page }) => {
  73  |   await signInReadmeLoaded(page);
  74  |   await expect(documentsLink(page), 'the link is in the header navigation').toBeVisible();
  75  |   await expect(documentsLink(page)).not.toHaveAttribute('aria-current', 'page');
  76  |   await documentsLink(page).click();
  77  |   expect(new URL(page.url()).hash, 'at the address #/documents').toBe('#/documents');
  78  |   await expect(page).toHaveTitle(TITLE);
  79  |   await expect(page.getByRole('heading', { level: 1 }), 'one h1').toHaveText('Documents');
  80  |   await expect(documentsLink(page), 'Documents is the current page').toHaveAttribute('aria-current', 'page');
  81  |   await expect(pagesNav(page).getByRole('link', { name: 'Chat', exact: true })).not.toHaveAttribute('aria-current', 'page');
  82  |   await expect(page.getByRole('link', { name: 'Skip to chat', exact: true }), 'the skip links belong to the main page').toHaveCount(0);
  83  | });
  84  | 
  85  | /** D2: with no documents the page says so. */
  86  | test('D2: with no documents the page reads "No documents yet. Add a runbook to get cited answers."', async ({ page }) => {
  87  |   await openDocuments(page);
  88  |   await expect(page.getByText(EMPTY)).toBeVisible();
  89  |   await expect(page.locator('li.row')).toHaveCount(0);
  90  | });
  91  | 
  92  | /** D3: the listed rows read Indexing, Ready and Couldn't read it, each with its name, date and size. */
  93  | test('D3: listed documents show their name, date, size and status', async ({ page }) => {
  94  |   const indexing = unique('indexing');
  95  |   const ready = unique('ready');
  96  |   const failed = unique('failed');
  97  |   await seed(`${indexing}.md`, { Size: '512' });
  98  |   await seed(`${ready}.pdf`, { State: 'ready', ContentType: 'pdf', Size: String(3 * MB) });
  99  |   await seed(`${failed}.txt`, { State: 'failed', Reason: 'unreadable', ContentType: 'text', Size: '2048' });
  100 |   await recordAnnouncements(page);
  101 |   await openDocuments(page);
  102 |   const one = rowsOf(page, indexing);
  103 |   await expect(one).toHaveCount(1);
  104 |   await expect(one.locator('.status')).toHaveText(INDEXING);
  105 |   await expect(one.locator('.size')).toHaveText('1 KB');
  106 |   await expect(one.locator('.when'), 'the date added reads as a time').toHaveText(/\d{1,2}:\d{2}/);
  107 |   await expect(one.getByRole('button', { name: `Remove ${indexing}.md`, exact: true })).toBeVisible();
  108 |   const two = rowsOf(page, ready);
  109 |   await expect(two.locator('.status')).toHaveText('Ready');
  110 |   await expect(two.locator('.size')).toHaveText('3 MB');
  111 |   const three = rowsOf(page, failed);
  112 |   await expect(three.locator('.status')).toHaveText(UNREADABLE);
  113 |   await expect(three.locator('.size')).toHaveText('2 KB');
  114 |   await expect(page.getByText(EMPTY), 'the empty text is gone').toHaveCount(0);
  115 |   await expect(page.getByRole('button', { name: 'Add documents', exact: true }), 'the picker is there beside the rows').toBeVisible();
  116 |   await page.waitForTimeout(2500);
  117 |   expect(await announcements(page, UNREADABLE), 'a failed row that is not of the user\'s own add is never announced').toBe(0);
  118 | });
  119 | 
  120 | /** D4: a published `document` event changes a row, and a removed one takes it away, with no reload. */
  121 | test('D4: document events turn a row Ready and then remove it, without a reload', async ({ page }) => {
  122 |   const name = `${unique('live')}.md`;
  123 |   const ref = await seed(name);
  124 |   await openDocuments(page);
  125 |   const row = rowsOf(page, name);
  126 |   await expect(row.locator('.status')).toHaveText(INDEXING);
  127 |   await page.evaluate(() => {
  128 |     (window as unknown as { documentsMarker: number }).documentsMarker = 7;
  129 |   });
  130 |   const addedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  131 |   await publish(ref, name, { AddedAt: addedAt, Size: '512', State: 'ready' });
  132 |   await expect(row.locator('.status'), 'the row reads Ready').toHaveText('Ready', { timeout: CARD_MS });
  133 |   await publish(ref, name, { Removed: '1' });
  134 |   await expect(row, 'the row leaves').toHaveCount(0, { timeout: CARD_MS });
  135 |   expect(await page.evaluate(() => (window as unknown as { documentsMarker?: number }).documentsMarker), 'the page was not reloaded').toBe(7);
  136 | });
  137 | 
  138 | /** D5: the keyboard reaches Add documents, Enter opens the file chooser, and a .png comes back refused by the real route. */
  139 | test('D5: Add documents works by keyboard, and a .png is refused with its reason', async ({ page }) => {
  140 |   await recordAnnouncements(page);
  141 |   await openDocuments(page);
  142 |   await page.locator('main.documents').focus();
  143 |   await page.keyboard.press('Tab');
  144 |   const add = page.getByRole('button', { name: 'Add documents', exact: true });
  145 |   await expect(add, 'Tab reaches Add documents').toBeFocused();
  146 |   const chooser = page.waitForEvent('filechooser');
  147 |   const answer = posted(page);
  148 |   await page.keyboard.press('Enter');
  149 |   await (await chooser).setFiles({ name: 'photo.png', mimeType: 'image/png', buffer: Buffer.from('not a document') });
  150 |   const response = await answer;
  151 |   expect(response.status(), 'the real route refuses a .png').toBe(400);
  152 |   const body = (await response.json()) as { error: { code: string }; reason: string };
  153 |   expect(`${body.error.code} ${body.reason}`).toBe('bad_document wrong_type');
  154 |   const row = rowsOf(page, 'photo.png');
  155 |   await expect(row.locator('.status')).toHaveText(WRONG_TYPE);
  156 |   await expect(row.getByRole('button', { name: /^Remove/ }), 'a refused file has no Remove').toHaveCount(0);
  157 |   await expect.poll(() => announcements(page, WRONG_TYPE), 'the refusal is announced').toBe(1);
  158 |   await page.waitForTimeout(2500);
  159 |   expect(await announcements(page, WRONG_TYPE), 'and announced once').toBe(1);
  160 | });
  161 | 
  162 | /** D6: files dropped on the page each go through the same route; the outline shows while they are over the page. */
  163 | test('D6: a dropped .exe and .png are each refused with their reason', async ({ page }) => {
  164 |   await openDocuments(page);
  165 |   const main = page.locator('main.documents');
  166 |   const transfer = await page.evaluateHandle(() => {
  167 |     const data = new DataTransfer();
  168 |     data.items.add(new File(['MZ'], 'setup.exe', { type: 'application/octet-stream' }));
  169 |     data.items.add(new File(['not a document'], 'diagram.png', { type: 'image/png' }));
```