// Stack-free probe: how many 'filechooser' events Chromium (via Playwright 1.64.1) reports for
// (a) one Enter whose click handler calls picker.click() twice, (b) a picker.click() on load with no gesture,
// (c) a picker.click() inside an earlier gesture (a link click) before the Enter, (d) the baseline single open.
import { createRequire } from 'node:module';
const require = createRequire('/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-34/web/package.json');
const { chromium } = require('playwright');
const page_ = (onClick, extra = '') => `<a id="nav" href="#d">Documents</a><main tabindex="-1" class="documents"><button id="add" type="button">Add documents</button>
<input id="picker" type="file" multiple hidden></main><script>const p=document.getElementById('picker');
document.getElementById('add').addEventListener('click',()=>{${onClick}});${extra}</script>`;
const cases = {
  single: page_('p.click();'),
  double: page_('p.click();p.click();'),
  doubleAsync: page_('p.click();setTimeout(()=>p.click(),50);'),
  onLoad: page_('p.click();', 'p.click();'),
  inEarlierGesture: page_('p.click();', "document.getElementById('nav').addEventListener('click',()=>p.click());"),
};
const browser = await chromium.launch();
for (const [name, html] of Object.entries(cases)) {
  const context = await browser.newContext();
  const page = await context.newPage();
  let n = 0;
  page.on('filechooser', () => { n += 1; });
  await page.waitForTimeout(300);
  await page.setContent(html);
  if (name === 'inEarlierGesture') await page.click('#nav');
  await page.waitForTimeout(500);
  const before = n;
  await page.locator('main').focus();
  await page.keyboard.press('Tab');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(2500);
  console.log(`CASE ${name} before_enter=${before} final=${n}`);
  await context.close();
}
await browser.close();
