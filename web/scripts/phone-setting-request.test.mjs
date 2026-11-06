// Tests (Story 40.6, QA) the simulated phone's reading of a proposed persona: a message that names a `setting` request (AC 2, the phone
// surface). The phone draws the notice text as plain paragraphs (a setting has no dry run example to set as an inset), names its two
// buttons by the request's title, "Change how OcuTalon talks to you", and answers in message form like every request, with the winner of
// a late press; the title is the same whether or not the payload carries old and new. The module is imported as it is: Node strips its
// types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { requestView } = await import(app('phone', 'phone-view.ts'));
const { approvalView } = await import(app('approvals', 'approval-view.ts'));
const { messageTime } = await import(app('chat', 'page-time.ts'));
const { renderMessageText } = await import(app('msg', 'catalog.ts'));
const { approvalTitle } = await import(app('rail', 'rail-view.ts'));

const NOW = Date.parse('2026-10-16T18:20:00Z');
const TITLE = 'Change how OcuTalon talks to you';
const NOTICE = 'OcuTalon suggests a new persona for you. Now: Professional (default). Proposed: Pirate. Nothing changes unless you approve.';

const ctx = {
  nowMs: NOW,
  instanceZone: 'UTC',
  onlineDemo: false,
  user: 'zzana',
  timeBeside: (iso) => messageTime(iso, NOW, 'UTC', false),
  whenBeside: (iso, now) => messageTime(iso, now, 'UTC', false),
  render: (key, slots) => renderMessageText(key, slots),
  title: approvalTitle,
};
const context = { viewOf: (approval) => approvalView(approval, ctx) };

const message = (over = {}) => ({ ref: 'm1', direction: 'out', text: NOTICE, approvalRef: 'S', createdAt: '2026-10-16T18:12:00Z', ...over });
const setting = (over = {}) => ({
  ref: 'S',
  kind: 'setting',
  state: 'pending',
  dryRun: { before: 'Professional (default)', after: 'Pirate' },
  raisedAt: '2026-10-16T18:12:00Z',
  expiresAt: '2026-10-17T18:12:00Z',
  ...over,
});
const answered = (state, channel, over = {}) => setting({ state, answeredChannel: channel, answeredAt: '2026-10-16T18:15:00Z', answeredBy: 'zzana', ...over });

describe('a setting request on the simulated phone (Story 40.6)', () => {
  it('draws the notice as one plain paragraph, whole, with the old and new texts never set as an inset', () => {
    for (const payload of [setting(), undefined, setting({ dryRun: undefined })]) {
      const view = requestView(message(), payload, undefined, context);
      assert.deepEqual(view.blocks, [{ inset: false, text: NOTICE, parts: [{ text: NOTICE, kind: 'plain' }] }]);
    }
  });

  it('names Approve and Reject by the setting title, and has the buttons while nothing is answered', () => {
    const view = requestView(message(), setting(), undefined, context);
    assert.equal(view.approveName, 'Approve: change how OcuTalon talks to you');
    assert.equal(view.rejectName, 'Reject: change how OcuTalon talks to you');
    assert.equal(view.buttons, true);
    assert.equal(view.answer, undefined);
  });

  it('has the one title whatever the payload carries, for the phone and the rail alike', () => {
    for (const dryRun of [undefined, { before: '', after: '' }, { before: 'A', after: 'B', affected: 4, resend: 3, field: 'OrderDate' }]) {
      assert.equal(approvalTitle(setting({ dryRun })), TITLE);
      assert.equal(requestView(message(), setting({ dryRun }), undefined, context).approveName, 'Approve: change how OcuTalon talks to you');
    }
  });

  it('answers in message form with the status every request has, and the winner of a late press', () => {
    const approved = requestView(message(), setting(), answered('done', 'phone'), context);
    assert.deepEqual(approved.answer, { text: 'Approved from the simulated phone at 18:15.', tone: 'approved', icon: 'circle-check' });
    assert.equal(approved.buttons, false);
    const rejected = requestView(message(), setting(), answered('rejected', 'phone'), context).answer;
    assert.deepEqual(rejected, { text: 'Rejected from the simulated phone at 18:15. Nothing was changed.', tone: 'rejected', icon: 'circle-slash' });
    const late = requestView(message(), setting(), answered('done', 'telegram', { answeredBy: 'zzsam' }), context).answer;
    assert.equal(late.text, 'Approved by zzsam from Telegram at 18:15.', 'a late press names the winner');
    const server = requestView(message({ answer: 'Approved from the web chat at 18:15.' }), answered('done', 'web'), undefined, context);
    assert.deepEqual(server.answer, { text: 'Approved from the web chat at 18:15.', tone: 'approved', icon: 'circle-check' }, "the server's line wins");
    assert.equal(server.buttons, false);
  });
});
