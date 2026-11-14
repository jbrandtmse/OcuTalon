import { expect, test, type Page } from '../e2e/support/fixtures';

import { expectError } from '../e2e/sign-in/helpers';
import { STATE, post } from '../e2e/support/api';
import { loadedAfter } from '../e2e/support/floor';
import { chk, fixtureUser, irisScript, quoted } from '../e2e/support/iris';
import { signInFromSplash, signOutGroup } from './support';

/**
 * Story 26.2, sending a file stays OFF on the online demo (AD-25; the Planner gate (a)), on the real online-demo stack as the demo account.
 * - F1: the state says onlineDemo is true, the composer has no "Send a file" button, and a POST of a file to /api/v1/files is a 409 not_available
 *   with the text of Core.Files TEXTOFFONDEMO, with no SentFile row for the session.
 * The reader switch (filesReadable) is the product's: it is false until Story 25.6, so the paperclip is hidden on every real state and F1's two
 * composer checks cannot fail on this branch. Until 25.6 the `!onlineDemo` term of fileControls is pinned by web/e2e/files/files.spec.ts ("on the
 * online demo there is no paperclip", a stubbed state with filesReadable true); the composer checks become this spec's own when 25.6 turns the
 * reader on. The route refuses the file whatever the flag says, so the 409 and the row count are F1's live checks today. The texts are written out
 * here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 120_000 });

const KIND = 'DEMOACCOUNT';
const OFF_ON_DEMO = 'Sending files is off on the online demo. It works on your own install.';

const paperclip = (page: Page) => page.getByRole('button', { name: 'Send a file', exact: true });

test('F1: on the demo the composer has no Send a file button and the route answers 409 not_available, storing nothing', async ({ page }) => {
  const { user, password } = fixtureUser(KIND);
  try {
    await loadedAfter(page, () => signInFromSplash(page, user, password));
    const state = (await (await page.request.get(STATE)).json()) as { onlineDemo: unknown };
    expect(state.onlineDemo, 'the real state says this is the online demo').toBe(true);
    await expect(page.getByRole('textbox', { name: 'Message OcuTalon' }), 'the composer is on the page').toBeVisible();
    await expect(page.locator('app-composer input[type="file"]'), 'and has no file input').toHaveCount(0);
    await expect(paperclip(page), 'and has no Send a file button').toHaveCount(0);

    const bytes = Buffer.from('%PDF-1.4 zz26s2 demo');
    const posted = await post(page.request, '/ocutalon/api/v1/files', { clientId: `zz26s2-${Date.now()}`, name: 'demo.pdf', content: bytes.toString('base64') });
    await expectError(posted, 409, 'not_available', OFF_ON_DEMO);

    const lines = await irisScript(
      [
        `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.SentFile s JOIN OcuTalon_Data.Session t ON s.SessionRef = t.Ref WHERE t.IrisUser = ?",${quoted(user)})`,
        'Do rs.%Next()',
        'Write !,"CHK|n|",rs.%GetData(1)',
      ].join('\n'),
    );
    expect(chk(lines, 'n'), 'no SentFile row was stored for the demo account').toBe('0');
  } finally {
    await signOutGroup(page);
  }
});
