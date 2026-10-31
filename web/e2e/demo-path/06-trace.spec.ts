import { expect, test } from '@playwright/test';

import { STATE } from '../support/api';
import { restoreKeys } from '../support/devices';
import { CARD_MS, signInReadmeLoaded } from '../support/floor';
import { chk, irisScript } from '../support/iris';
import { TRACE_PAGE, drawnMessages, signOutTrace } from '../support/trace';

/** The finish state's first line (EXPERIENCE, the demo guide), written out here as the independent oracle of the page's own. */
const DONE =
  'Done. You saw an AI Hub agent read 50 failed orders and name the cause. Every decision, with its cost, and every step it took landed in Visual Trace, and the fix waited for your approval and was recorded in the audit log.';

/**
 * UJ-1 step 6: the trace (REL-2, Story 11.1; AD-26, UX-DR47, UX-DR139, UX-DR140). On the incident that step 5 resolved, the README account
 * presses Open the trace in the guide: the dialog "Sign in to Visual Trace" shows first, and its link "Open Visual Trace (opens in a new
 * tab)" opens a tab at the trace page with the SESSIONID of the incident's diagnosis header, which Visual Trace draws; the tab is already
 * signed in with the README account. The guide then shows its finish line with the run total: the decisions, tokens and cost of the run on
 * the model the mock stands in for. The runners' keys, pointed at the CI mock by 02, are put back after the test and the runners record
 * the restored keys.
 * It needs the first-start stack (OCUTALON_URL): without it the group skips as it is declared, before any hook starts.
 */
test.describe('Story 11.1: step 5 of the guide opens the incident trace', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.1 needs the first-start stack (OCUTALON_URL), which a run without one lacks');

  test('Open the trace opens Visual Trace at the incident diagnosis session, and the guide shows its finish line', async ({ page, context }) => {
    test.setTimeout(180_000);
    await signInReadmeLoaded(page);
    try {
      const state = await page.request.get(STATE);
      expect(state.status(), await state.text()).toBe(200);
      const chat = ((await state.json()) as { chat: Array<{ type: string; payload: { traceTargets?: { diagnosis?: { traceHeaderId?: number } } } }> }).chat;
      const header = chat.find((item) => item.type === 'incident')?.payload.traceTargets?.diagnosis?.traceHeaderId;
      expect(typeof header === 'number' && header > 0, "the incident's diagnosis has a trace header").toBe(true);

      const guide = page.getByRole('region', { name: 'Demo guide' });
      await expect(guide.getByRole('button', { name: 'Step 5, Open the trace, current', exact: true }), 'the guide is at step 5').toHaveCount(1, { timeout: CARD_MS });
      const link = guide.locator('.prompt app-trace-link a');
      await expect(link, "its address is the incident's diagnosis session").toHaveAttribute('href', `${TRACE_PAGE}${header}`);
      await link.click();
      const dialog = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
      await expect(dialog, 'the sign-in help shows first').toBeVisible();

      const opened = context.waitForEvent('page');
      await dialog.getByRole('link', { name: 'Open Visual Trace (opens in a new tab)', exact: true }).click();
      const popup = await opened;
      await popup.waitForLoadState('domcontentloaded');
      await expect.poll(() => new URL(popup.url()).pathname + new URL(popup.url()).search, { message: 'a tab opened at the incident trace', timeout: 30_000 }).toBe(`${TRACE_PAGE}${header}`);
      const drawn = await drawnMessages(popup);
      expect(drawn.ids, `Visual Trace draws the diagnosis session (it draws ${drawn.ids.join(' ')})`).toContain(String(header));
      await popup.close();

      const finish = guide.locator('.finish');
      await expect(finish, 'the finish replaces the prompt bar').toBeVisible({ timeout: CARD_MS });
      await expect(finish.locator('.finish-done'), 'the first line').toHaveText(DONE);
      await expect(finish.locator('.run-total'), 'the run total').toHaveText(/^This run: \d+ decisions \u00B7 [\d,]+ tokens \u00B7 \$\d+\.\d+ on Claude Haiku 5\.5\.$/);
    } finally {
      await signOutTrace(page.request);
    }
  });

  test.afterAll(async () => {
    test.setTimeout(240_000);
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
    }
  });
});
