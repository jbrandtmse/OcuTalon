// Tests the Visual Trace links' strings and rules (src/app/shared/trace-view.ts): the fixed strings against the UX's wording, written
// out here, with an ASCII check (UX-DR117); the two storage keys; the truth table of needsSignInHelp (the online demo never needs the
// help, nothing is needed before the snapshot has said which install it is, and a seen or switched-off help is not needed); and
// conversationUrl, which is the traceUrl of the newest chat.message that has one. The module is imported as it is: Node strips its
// types, which holds only while it keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { TRACE_DONT_SHOW_KEY, TRACE_FLAG, TRACE_SEEN_KEY, TRACE_TEXTS, conversationUrl, needsSignInHelp, signInNameOf } = await import(app('shared', 'trace-view.ts'));

const turn = (ref, traceUrl) => ({ type: 'chat.message', payload: { ref, ...(traceUrl === undefined ? {} : { traceUrl }) } });
const notice = (ref, traceUrl) => ({ type: 'notification', payload: { ref, kind: 'tellnow', decision: { ref: `d-${ref}`, traceUrl } } });
const incident = (ref, traceUrl) => ({ type: 'incident', payload: { ref, traceTargets: { diagnosis: { traceUrl } }, traceUrl } });

describe('the fixed strings', () => {
  it("are the AC's and the UX's wording, written out here, in ASCII", () => {
    assert.deepEqual(
      { ...TRACE_TEXTS },
      {
        trace: 'Trace',
        opensInNewTab: '(opens in a new tab)',
        signInName: 'Open in Visual Trace (shows sign-in help first)',
        signInFor: '{label} (shows sign-in help first)',
        arrow: '\u2197',
        signInHeading: 'Sign in to Visual Trace',
        signInText: 'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.',
        openVisualTrace: 'Open Visual Trace',
        dontShow: "Don't show this again",
        menu: 'Visual Trace',
        openConversation: 'Open my conversation in Visual Trace',
        conversationNotYet: 'Available after your first message.',
        userNameLabel: 'User name',
        passwordLabel: 'Password',
        copyUserName: 'Copy Visual Trace user name',
        copyPassword: 'Copy Visual Trace password',
        copied: 'Copied',
        copyFailed: "Couldn't copy. Select the text and copy it yourself.",
      },
    );
    for (const value of Object.values(TRACE_TEXTS).filter((one) => one !== '\u2197')) {
      assert.match(value, /^[\x20-\x7e]+$/, `${value} is ASCII`);
    }
  });

  it('keep the seen flag in the tab session and the switched-off flag in the browser, under their own keys', () => {
    assert.equal(TRACE_SEEN_KEY, 'ocutalon.traceHelp.seen');
    assert.equal(TRACE_DONT_SHOW_KEY, 'ocutalon.traceHelp.dontShow');
    assert.equal(TRACE_FLAG, '1');
  });
});

describe('signInNameOf', () => {
  it('is signInName for the default text, and the text with the help words for another (the visible label stays first, WCAG 2.5.3)', () => {
    assert.equal(signInNameOf('Trace'), 'Open in Visual Trace (shows sign-in help first)');
    assert.equal(signInNameOf('Open the trace'), 'Open the trace (shows sign-in help first)');
    assert.equal(signInNameOf('See the whole conversation in Visual Trace'), 'See the whole conversation in Visual Trace (shows sign-in help first)');
  });
});

describe('needsSignInHelp', () => {
  it('is true only on a local install, with the help neither seen nor switched off', () => {
    for (const onlineDemo of [false, true, undefined]) {
      for (const seen of [false, true]) {
        for (const dontShow of [false, true]) {
          const expected = onlineDemo === false && !seen && !dontShow;
          assert.equal(needsSignInHelp(onlineDemo, seen, dontShow), expected, `onlineDemo ${onlineDemo}, seen ${seen}, dontShow ${dontShow}`);
        }
      }
    }
  });

  it('is false on the online demo, whatever else holds', () => {
    assert.equal(needsSignInHelp(true, false, false), false);
  });

  it('is false until the snapshot has said which install it is', () => {
    assert.equal(needsSignInHelp(undefined, false, false), false);
  });

  it('is false once seen in this tab, and once switched off for the browser', () => {
    assert.equal(needsSignInHelp(false, true, false), false);
    assert.equal(needsSignInHelp(false, false, true), false);
  });
});

describe('conversationUrl', () => {
  it('is the traceUrl of the newest turn, over older turns', () => {
    const chat = [turn('t1', '/trace?SESSIONID=1&PAGE=1'), turn('t2', '/trace?SESSIONID=2&PAGE=1'), turn('t3', '/trace?SESSIONID=3&PAGE=2')];
    assert.equal(conversationUrl(chat), '/trace?SESSIONID=3&PAGE=2');
  });

  it('prefers the newest turn to an incident or a notice that comes after it', () => {
    const chat = [turn('t1', '/trace?SESSIONID=1'), turn('t2', '/trace?SESSIONID=2'), incident('i1', '/trace?SESSIONID=88'), notice('n1', '/trace?SESSIONID=99')];
    assert.equal(conversationUrl(chat), '/trace?SESSIONID=2');
  });

  it('skips a newer turn that has no traceUrl and takes the newest that has one', () => {
    const chat = [turn('t1', '/trace?SESSIONID=1'), turn('t2', '/trace?SESSIONID=2'), turn('t3')];
    assert.equal(conversationUrl(chat), '/trace?SESSIONID=2');
  });

  it('is undefined for an empty chat, an undefined one, and turns with no traceUrl', () => {
    assert.equal(conversationUrl([]), undefined);
    assert.equal(conversationUrl(undefined), undefined);
    assert.equal(conversationUrl([turn('t1'), turn('t2', '')]), undefined);
  });

  it('is undefined when only incidents and notices carry a target', () => {
    assert.equal(conversationUrl([incident('i1', '/trace?SESSIONID=88'), notice('n1', '/trace?SESSIONID=99')]), undefined);
  });

  it('moves to a turn that arrives later, with the chat read afresh', () => {
    const chat = [turn('t1', '/trace?SESSIONID=1')];
    assert.equal(conversationUrl(chat), '/trace?SESSIONID=1');
    assert.equal(conversationUrl([...chat, turn('t2', '/trace?SESSIONID=1&PAGE=2')]), '/trace?SESSIONID=1&PAGE=2');
  });
});
