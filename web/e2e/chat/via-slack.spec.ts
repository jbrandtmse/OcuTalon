import { expect, test, type Page } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { cleanFixtureRows, fixtureUser, seedTurns } from '../support/iris';
import { clock, plain } from '../support/page';

/**
 * Story 27.3, the chat's caption of a Slack turn, in a real browser against a real stack. A turn of channel slack that the stack holds shows "via Slack" in its caption,
 * as a Telegram turn shows "via Telegram", and a web turn shows none. The turns are seeded on the panel fixture user's own session (OCUTALON_PANEL_USER, which
 * test-sign-in.sh created), dated in the past so that they are among the newest 100 whatever else the stack holds, and are removed after the case.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US' });

/** The middle dot between the items of a caption line. */
const DOT = ' \u00B7 ';

const userOf = (page: Page, key: string) => page.locator(`app-chat-panel [data-part="user"][data-key="${key}"]`);

test('V1: a Slack turn is captioned "via Slack", a Telegram turn "via Telegram" and a web turn has no caption', async ({ page }) => {
  test.setTimeout(180_000);
  const stamp = Date.now().toString(36);
  const { user, password } = fixtureUser('PANEL');
  let refs: string[] = [];
  try {
    await loadedAfter(page, () => signIn(page, user, password));
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    const seeded = await seedTurns(user, [
      { createdAt: '2025-07-01T10:01:00Z', text: `zz V1 ${stamp} slack`, replyText: 'Sent from Slack.', channel: 'slack' },
      { createdAt: '2025-07-01T10:02:00Z', text: `zz V1 ${stamp} telegram`, replyText: 'Sent from Telegram.', channel: 'telegram' },
      { createdAt: '2025-07-01T10:03:00Z', text: `zz V1 ${stamp} web`, replyText: 'Sent from the web.' },
    ]);
    refs = seeded.refs;
    await page.reload();
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    const bubbles = page.locator('app-chat-panel .bubble').filter({ hasText: `zz V1 ${stamp}` });
    await expect(bubbles, 'the three turns are in the chat, in CreatedAt order').toHaveText([`zz V1 ${stamp} slack`, `zz V1 ${stamp} telegram`, `zz V1 ${stamp} web`]);
    const [slackRef, telegramRef, webRef] = refs as [string, string, string];
    expect(plain(await userOf(page, slackRef).locator('.when').textContent())).toBe(`via Slack${DOT}${clock('2025-07-01T10:01:00Z')}`);
    expect(plain(await userOf(page, telegramRef).locator('.when').textContent())).toBe(`via Telegram${DOT}${clock('2025-07-01T10:02:00Z')}`);
    expect(plain(await userOf(page, webRef).locator('.when').textContent()), 'a web turn has no caption').toBe(clock('2025-07-01T10:03:00Z'));
  } finally {
    await cleanFixtureRows(refs);
  }
});
