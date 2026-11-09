// Tests the "This was noise" control's view (src/app/chat/noise-view.ts; Story 41.5, FR-72): its fixed texts, the status line, and where the control shows (a
// tell-now notice with a decision in the chat, a phone message with a noiseRef and no approvalRef, nothing else). It also pins the sources: the control
// is drawn by the notice card (channel web) and the simulated phone (channel phone) only, and the client posts the noise path with { channel }. The view is
// imported as it is: Node strips its types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const { NOISE_TEXTS, markedLine, noticeNoiseRef, phoneNoiseRef } = await import(pathToFileURL(join(app, 'chat', 'noise-view.ts')).href);
const { pageTime } = await import(pathToFileURL(join(app, 'chat', 'page-time.ts')).href);

const read = (...parts) => readFileSync(join(app, ...parts), 'utf8');

describe('the texts', () => {
  it('are the fixed strings of EXPERIENCE', () => {
    assert.deepEqual({ ...NOISE_TEXTS }, {
      label: 'This was noise',
      marked: 'Marked as noise at {time}. Similar items will take this into account.',
    });
  });

  it('put the first mark\'s time, as the page writes it, in the status line', () => {
    const beside = (iso, zone) => pageTime(iso, 'en-GB', zone);
    assert.equal(markedLine('2026-11-08T14:11:42Z', 'UTC', beside), 'Marked as noise at 14:11. Similar items will take this into account.');
    assert.equal(markedLine('2026-11-08T14:11:42Z', 'Europe/Berlin', beside), 'Marked as noise at 15:11. Similar items will take this into account.');
  });

  it('puts the time in literally, whatever characters it holds', () => {
    assert.equal(markedLine('x', 'UTC', () => "$& $1 $'"), "Marked as noise at $& $1 $'. Similar items will take this into account.");
  });
});

describe('noticeNoiseRef', () => {
  const decision = { ref: 'ZzDecision000000000001' };
  const notice = (kind, extra = {}) => ({ entry: 'notice', key: `notification:${kind}`, kind, text: 't', whyNow: '', time: '', dueAt: '', strip: false, ...extra });

  it('gives the decision\'s Ref for a tell-now notice that has one', () => {
    assert.equal(noticeNoiseRef(notice('tellnow', { decision, strip: true })), 'ZzDecision000000000001');
  });

  it('gives "" for a tell-now notice with no decision, or a decision with no Ref (a fallback)', () => {
    assert.equal(noticeNoiseRef(notice('tellnow', { strip: true })), '');
    assert.equal(noticeNoiseRef(notice('tellnow', { decision: {}, strip: true })), '');
  });

  it('gives "" for every other kind, even one that carries a decision', () => {
    for (const kind of ['reminder', 'allowance', 'approval', 'result', 'digest', 'incident']) {
      assert.equal(noticeNoiseRef(notice(kind, { decision })), '', kind);
    }
  });
});

describe('phoneNoiseRef', () => {
  it('gives the noiseRef of a message with no approvalRef, never its decisionRef (Got it reads that)', () => {
    assert.equal(phoneNoiseRef({ ref: 'm', noiseRef: 'ZzDecision000000000001' }), 'ZzDecision000000000001');
    assert.equal(phoneNoiseRef({ ref: 'm', noiseRef: 'ZzDecision000000000001', approvalRef: '' }), 'ZzDecision000000000001');
    assert.equal(phoneNoiseRef({ ref: 'm', noiseRef: 'ZzDecision000000000001', decisionRef: '' }), 'ZzDecision000000000001');
    assert.equal(phoneNoiseRef({ ref: 'm', decisionRef: 'ZzDecision000000000002' }), '');
  });

  it('gives "" for a message that names an approval request, or has no noiseRef', () => {
    assert.equal(phoneNoiseRef({ ref: 'm', noiseRef: 'ZzDecision000000000001', approvalRef: 'ZzApproval00000000001' }), '');
    assert.equal(phoneNoiseRef({ ref: 'm', text: 'x' }), '');
    assert.equal(phoneNoiseRef({ ref: 'm', noiseRef: '' }), '');
  });
});

describe('the sources', () => {
  const files = sourceFiles(app, ['.ts']);
  const draws = files.filter((one) => one.code.includes('<app-noise-control'));

  it('draw the control in the notice card (channel web) and the simulated phone (channel phone) only', () => {
    assert.deepEqual(draws.map((one) => one.name).sort(), ['chat/notice-card.ts', 'phone/simulated-phone.ts']);
    const card = draws.find((one) => one.name === 'chat/notice-card.ts').code;
    const phone = draws.find((one) => one.name === 'phone/simulated-phone.ts').code;
    assert.match(card, /<app-noise-control \[decisionRef\]="noiseRef\(\)" channel="web" \[instanceZone\]="instanceZone\(\)" \/>/);
    assert.match(card, /noticeNoiseRef\(this\.notice\(\)\)/);
    assert.match(phone, /@if \(phoneNoiseRef\(one\); as ref\) \{\s*<app-noise-control \[decisionRef\]="ref" channel="phone" \[instanceZone\]="instanceZone\(\)" \/>/);
  });

  it('post the noise path with the channel from the one client', () => {
    const client = read('api', 'api-client.ts');
    assert.match(client, /markNoise\(ref: string, channel: import\('\.\/memory-types'\)\.NoiseChannel\)/);
    assert.match(client, /this\.http\.post<import\('\.\/memory-types'\)\.NoiseMarked>\(`\$\{BASE\}\/decisions\/\$\{encodeURIComponent\(ref\)\}\/noise`, \{ channel \}\)/);
    assert.match(read('chat', 'noise-control.ts'), /this\.api\.markNoise\(this\.decisionRef\(\), this\.channel\(\)\)/);
  });

  it('make the control a ghost server button with the visible label, shown for a Ref only, and move no focus itself', () => {
    const control = files.find((one) => one.name === 'chat/noise-control.ts').code;
    assert.match(control, /<app-server-button variant="ghost" \[action\]="press"/);
    assert.match(control, /\{\{ texts\.label \}\}/);
    assert.doesNotMatch(control, /aria-label|\[label\]|\.focus\(/);
    assert.match(control, /@if \(decisionRef\(\)\) \{/);
    assert.match(control, /pageTimeBeside/);
    assert.match(control, /untracked\(\(\) => keepFocus\(this\.host\.nativeElement, this\.injector, this\.popovers, NOISE_RULE\)\)/);
    assert.match(control, /messageOf\(error\) \|\| BUSY_NOTICE/);
    assert.doesNotMatch(control, /aria-live|role="(status|alert|log)"/);
  });
});
