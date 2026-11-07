// Stack-free repro of D5's sequence: waitForEvent('filechooser') registered, then keyboard Enter on a focused button whose click
// calls a hidden <input type=file>.click(). MODE=old: the D5 sequence as written. MODE=armed: a filechooser listener registered
// (interception on) well before the press. Counts presses that never produce a filechooser event within TIMEOUT ms.
import { createRequire } from 'node:module';
const require = createRequire('/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-34/web/package.json');
const { chromium } = require('playwright');
const MODE = process.env.MODE ?? 'old';
const N = Number(process.env.N ?? 40);
const TIMEOUT = Number(process.env.TIMEOUT ?? 3000);
const html = `<main tabindex="-1" class="documents"><button id="add" type="button">Add documents</button>
<input id="picker" type="file" multiple hidden></main>
<script>
 window.log=[];document.getElementById('add').addEventListener('click',()=>{window.log.push('button-click '+navigator.userActivation.isActive);document.getElementById('picker').click();});
 document.getElementById('picker').addEventListener('click',()=>window.log.push('input-click'));
</script>`;
const browser = await chromium.launch();
let miss = 0;
for (let i = 0; i < N; i++) {
  const context = await browser.newContext();
  const page = await context.newPage();
  if (MODE === 'armed') page.on('filechooser', () => undefined);
  await page.setContent(html);
  await page.locator('main').focus();
  await page.keyboard.press('Tab');
  const chooser = page.waitForEvent('filechooser', { timeout: TIMEOUT });
  await page.keyboard.press('Enter');
  try { await chooser; } catch {
    miss++;
    const first = JSON.stringify(await page.evaluate(() => window.log));
    const again = page.waitForEvent('filechooser', { timeout: TIMEOUT });
    await page.waitForTimeout(500);
    await page.keyboard.press('Enter');
    let second = 'chooser';
    try { await again; } catch { second = 'MISSED-AGAIN'; }
    console.log(`MISS ${i} first=${first} active=${await page.evaluate(() => document.activeElement?.id)} second_press_after_500ms=${second}`);
  }
  await context.close();
}
console.log(`RESULT mode=${MODE} n=${N} missed=${miss}`);
await browser.close();
