// Tests what an answer press hands to its host (src/app/approvals/answer-press.ts, Story 23.12, DW-1159) by running the real class: a
// reply that carries the request (200, 409 already_answered, 409 expired) is handed to `answered` once, after `local` holds it; a
// reply with no payload (403, 404, 400, 500, no connection, an empty 200) hands nothing over and leaves the notice; and the hand-over
// into the live store (withAnswer) takes the request off the rail's pending list. The browser cases (RA1, RA2) pin the same in the page.
// The class is imported as it is. Angular's signals, the HTTP error class and RxJS are the real ones; the only stand-in is a resolve
// hook that gives the sources' extensionless relative imports their .ts, as the bundler does.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const sources = join(here, '..', 'src', 'app');

registerHooks({
  resolve(specifier, context, nextResolve) {
    const inSources = context.parentURL?.startsWith(pathToFileURL(sources).href);
    return nextResolve(inSources && specifier.startsWith('.') && !/\.\w+$/.test(specifier) ? `${specifier}.ts` : specifier, context);
  },
});

// Angular's partially compiled libraries need the JIT compiler once, before the first of them loads.
await import('@angular/compiler');
const { HttpErrorResponse } = await import('@angular/common/http');
const { of, throwError } = await import('rxjs');
const { AnswerPress } = await import(app('approvals', 'answer-press.ts'));
const { APPROVAL_TEXTS } = await import(app('approvals', 'approval-view.ts'));
const { fromSnapshot, withAnswer } = await import(app('live', 'live-store.ts'));
const { pendingApprovals } = await import(app('rail', 'rail-view.ts'));

const ask = (ref, state) => ({ ref, state, title: `request ${ref}` });

/** A press whose answer call returns what `reply` says (a status and a body), with every hand-over and announcement recorded. */
function press(reply) {
  const handed = [];
  const announced = [];
  const asked = [];
  const subject = new AnswerPress({
    answer: (ref, action, channel) => {
      asked.push({ ref, action, channel });
      return reply.status >= 200 && reply.status < 300
        ? of({ status: reply.status, body: reply.body })
        : throwError(() => new HttpErrorResponse({ status: reply.status, error: reply.body }));
    },
    channel: 'web',
    answered: (approval) => handed.push({ approval, localThen: subject.local() }),
    context: () => ({ render: () => 'late-press text', user: 'FLOOR', onlineDemo: false, nowMs: 0, instanceZone: 'UTC', timeBeside: () => '', whenBeside: () => '', title: () => '' }),
    announcer: { announce: (text) => announced.push(text) },
    destroyRef: { onDestroy: () => () => undefined },
  });
  return { subject, handed, announced, asked };
}

describe('what a reply hands to the host (answered)', () => {
  it('hands the request of a 200 over once, after local holds it, for Reject and for Approve', () => {
    for (const [action, state] of [['reject', 'rejected'], ['approve', 'approved']]) {
      const view = ask('app-1', state);
      const { subject, handed, asked } = press({ status: 200, body: { result: 'done', approval: view } });
      subject.press('app-1', action);
      assert.deepEqual(asked, [{ ref: 'app-1', action, channel: 'web' }]);
      assert.equal(handed.length, 1, action);
      assert.deepEqual(handed[0].approval, view);
      assert.deepEqual(handed[0].localThen, view, 'local is set before the host hears of it');
      assert.deepEqual(subject.local(), view);
    }
  });

  it('hands over the winner\'s request of a 409 already_answered and the expired request of a 409 expired, each with its notice', () => {
    const won = ask('app-1', 'approved');
    const late = press({ status: 409, body: { error: { code: 'already_answered', message: 'Already answered.' }, approval: won } });
    late.subject.press('app-1', 'reject');
    assert.deepEqual(late.handed.map((one) => one.approval), [won]);
    assert.deepEqual(late.handed[0].localThen, won, 'local is set before the host hears of it');
    assert.equal(late.subject.notice(), 'late-press text');

    const gone = ask('app-1', 'expired');
    const expired = press({ status: 409, body: { error: { code: 'expired', message: 'Expired. Nothing was changed.' }, approval: gone } });
    expired.subject.press('app-1', 'approve');
    assert.deepEqual(expired.handed.map((one) => one.approval), [gone]);
    assert.deepEqual(expired.handed[0].localThen, gone, 'local is set before the host hears of it');
    assert.equal(expired.subject.notice(), '', 'the expired request shows itself; the reply adds no notice');
  });

  it('hands nothing over for a reply with no payload (403, 404, 400, 500, no connection, an empty 200, a 409 without the request), and leaves the notice', () => {
    const failed = { error: { code: 'server_error', message: 'OcuTalon could not answer. Nothing was changed.' } };
    const cases = [
      [{ status: 500, body: failed }, 'OcuTalon could not answer. Nothing was changed.'],
      [{ status: 403, body: { error: { code: 'not_allowed', message: 'Only an approver can answer this request.' } } }, 'Only an approver can answer this request.'],
      [{ status: 404, body: { error: { code: 'not_found', message: 'x' } } }, APPROVAL_TEXTS.gone],
      [{ status: 400, body: { error: { code: 'bad_answer', message: 'An answer needs an action.' } } }, 'An answer needs an action.'],
      [{ status: 0, body: undefined }, APPROVAL_TEXTS.busyNotice],
      [{ status: 200, body: null }, ''],
      [{ status: 409, body: { error: { code: 'already_answered', message: 'x' } } }, 'x'],
    ];
    for (const [reply, notice] of cases) {
      const { subject, handed } = press(reply);
      subject.press('app-1', 'reject');
      assert.equal(handed.length, 0, String(reply.status));
      assert.equal(subject.local(), undefined, `${reply.status}: local stays empty`);
      assert.equal(subject.notice(), notice, String(reply.status));
    }
  });

  it('takes the request into its can\'t-answer state at once after a refused press (403 not_allowed, Story 25.5), with the server\'s sentence, until clearRefused', () => {
    const sentence = 'Only an approver for reroutes can answer this request.';
    const { subject, handed, announced } = press({ status: 403, body: { error: { code: 'not_allowed', message: sentence } } });
    assert.equal(subject.refused(), '', 'before any press');
    subject.press('app-1', 'approve');
    assert.equal(subject.refused(), sentence, 'a refused press sets refused to the server\'s sentence');
    assert.equal(subject.notice(), sentence, 'and the notice is that sentence too, announced once');
    assert.deepEqual(announced, [sentence]);
    assert.equal(handed.length, 0, 'it hands nothing to the store');
    subject.clearRefused();
    assert.equal(subject.refused(), '', 'clearRefused ends the state');
    assert.equal(subject.notice(), '', 'and drops the notice that repeated the sentence, so restored buttons carry no stale refusal');
    for (const reply of [{ status: 404, body: { error: { code: 'not_found', message: 'x' } } }, { status: 500, body: { error: { code: 'server_error', message: 'y' } } }, { status: 0, body: undefined }, { status: 200, body: null }]) {
      const other = press(reply);
      other.subject.press('app-1', 'approve');
      assert.equal(other.subject.refused(), '', `${reply.status} is not a refusal`);
    }
    const fallback = press({ status: 403, body: undefined });
    fallback.subject.press('app-1', 'reject');
    assert.equal(fallback.subject.refused(), 'Only an approver can answer this request.', 'a refusal with no message has the fallback sentence');
  });

  it('takes the request off the rail through the store: the handed-over reply removes it, the failed press leaves it', () => {
    const snapshot = {
      epoch: 'epoch-1',
      streams: { session: 5, instance: 2 },
      chat: [],
      status: [],
      telegram: {},
      rail: { approvals: [ask('app-1', 'pending'), ask('app-2', 'pending')], checks: [], reminders: [], decisions: [] },
    };
    let store = fromSnapshot(snapshot);
    assert.equal(pendingApprovals(store).length, 2);

    const failed = press({ status: 500, body: { error: { code: 'server_error', message: 'OcuTalon could not answer. Nothing was changed.' } } });
    failed.subject.press('app-1', 'reject');
    for (const { approval } of failed.handed) store = withAnswer(store, approval);
    assert.equal(pendingApprovals(store).length, 2, 'a failed press changes nothing');

    const ok = press({ status: 200, body: { result: 'done', approval: ask('app-1', 'rejected') } });
    ok.subject.press('app-1', 'reject');
    for (const { approval } of ok.handed) store = withAnswer(store, approval);
    assert.deepEqual(pendingApprovals(store).map((one) => one.ref), ['app-2']);
  });
});
