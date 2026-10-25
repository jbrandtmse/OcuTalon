// Tests the shape of the page's sources that Story 2.12 relies on (NFR-25, UX-DR58, UX-DR131, UX-DR132, AD-12): the page has one live
// region, the Announcer's, and speaks only through it; each event is announced from one place (the rail, the header and the reply,
// card and message components announce nothing); and focus moves only for the user's own action or through the page's one focus
// rule. The browser cases (A1 to A7, P1 to P4) pin what the running page does for the states they reach; this reads every source, so
// a state no case reaches cannot add a second live region, a second speaker or a stray focus call without a test turning red.
// Each list below names the files that may do the thing and why (the focus calls also how many); a story that needs another one adds
// it here, with its reason.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { code, sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const sources = join(here, '..', 'src');

const files = sourceFiles(sources, ['.ts', '.js', '.html']);
const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

/** The names of the files whose code (comments left out) matches the pattern. */
const filesWith = (pattern) => files.filter((one) => pattern.test(one.code)).map((one) => one.name);

describe('the scan', () => {
  it('reads the app, the sign-in script and the index', () => {
    const names = files.map((one) => one.name);
    for (const expected of ['index.html', 'app/shared/announcer.ts', 'app/shared/focus-rule.ts', 'app/chat/chat-panel.ts', 'app/rail/status-rail.ts', 'app/banners/banner-stack.ts', 'app/main-page/main-page.ts']) {
      assert.ok(names.includes(expected), `${expected} is scanned`);
    }
  });

  it('strips comments but keeps an address in code', () => {
    assert.equal(code('a /* aria-live */ b // aria-live\nc <!-- role="log" --> d "https://x.y/z"'), 'a  b \nc  d "https://x.y/z"');
  });
});

describe('the page has one live region', () => {
  it('has no element marked aria-live, aria-atomic or aria-relevant, and none given a live role, in any template or script', () => {
    const live = /aria-live|aria-atomic|aria-relevant|\baria(?:Live|Atomic|Relevant)\b|<output\b|\[attr\.role\][^\n]*\b(log|status|alert|timer|marquee)\b|\brole\]?['"]?\s*[:=,]\s*['"`]*\s*(log|status|alert|timer|marquee)\b/i;
    for (const form of ['role="status"', "setAttribute('role', 'alert')", "host: { role: 'log' }", `[role]="'timer'"`, "[attr.role]=\"on ? 'marquee' : null\"", 'el.ariaLive = "polite"', '<output>', '[attr.aria-atomic]="true"']) {
      assert.match(form, live, `${form} is caught`);
    }
    assert.doesNotMatch("setAttribute('role', 'dialog'); role: 'alertdialog'", live, 'a dialog is no live region');
    assert.deepEqual(filesWith(live), []);
  });

  it('keeps the CDK\'s live announcer to the Announcer, and never speaks assertively', () => {
    assert.deepEqual(filesWith(/\bLiveAnnouncer\b|cdkAriaLive|CdkAriaLive/), ['app/shared/announcer.ts']);
    assert.deepEqual(filesWith(/assertive/i), []);
    assert.match(file('app/shared/announcer.ts').code, /this\.live\.announce\(text, 'polite'\)/);
  });
});

describe('the page speaks only through the Announcer', () => {
  it('hands every message to the queue, which is the only way the Announcer speaks', () => {
    const { code: announcer } = file('app/shared/announcer.ts');
    assert.match(announcer, /new AnnounceQueue\(/);
    assert.match(announcer, /announce\(message: string\): void \{\s*this\.queue\.push\(message\);\s*\}/);
    assert.equal((announcer.match(/this\.live\.announce\(/g) ?? []).length, 1, 'one call to the live announcer');
  });

  it('reads a reply for the chat from the real modules: the first block with links as labels, the catalog\'s fallback sentence and CHAT_TEXTS', () => {
    const panel = file('app/chat/chat-panel.ts').code;
    const start = panel.indexOf('const ANNOUNCE_FORMAT');
    assert.ok(start >= 0, 'the chat panel builds the format');
    const format = panel.slice(start, panel.indexOf('};', start));
    assert.match(format, /announceReplied: CHAT_TEXTS\.announceReplied,/);
    assert.match(format, /announceTellNow: CHAT_TEXTS\.announceTellNow,/);
    assert.match(format, /replyText: \(replyText\) => plainText\(parseReply\(replyText\)\),/);
    assert.match(format, /fallbackText: replyFallbackText,/);
    assert.match(file('app/chat/chat-outbox.ts').code, /this\.announcer\.announce\(CHAT_TEXTS\.messageNotSent\)/);
  });

  it('keeps the timing of announcements in the queue: the banner stack has no gap, no waiting list, no drain and no timer of its own', () => {
    assert.deepEqual(filesWith(/ANNOUNCE_GAP_MS/), []);
    const stack = file('app/banners/banner-stack.ts').code;
    assert.doesNotMatch(stack, /\bsetTimeout\b|\bsetInterval\b|\bdrain\b|\bwaiting\b/);
    assert.match(stack, /this\.announcer\.announce\(banner\.text\)/);
  });

  it('announces from one place per event: the rail, the header and the reply, card and message components do not announce', () => {
    // A story that makes one of these announce moves the event's announcement from the chat or the control that owns it, so that the
    // event is still heard once (Story 2.12, Decided 4); it then edits this list with that reason.
    const silent = files.filter((one) => /^app\/(rail|header)\//.test(one.name) || ['app/chat/ocutalon-reply.ts', 'app/chat/notice-card.ts', 'app/chat/user-message.ts', 'app/chat/decision-strip.ts'].includes(one.name));
    assert.ok(silent.length >= 6, 'the silent files are found');
    assert.deepEqual(silent.filter((one) => /\bAnnouncer\b|\.announce\(/.test(one.code)).map((one) => one.name), []);
  });

  it('has these speakers and no others: banners, the chat and its outbox, the load failure, the busy notice and the narrow-window note', () => {
    assert.deepEqual(filesWith(/\bannouncer\.announce\(|\.announce\(/).sort(), [
      'app/banners/banner-stack.ts',
      'app/chat/chat-outbox.ts',
      'app/chat/chat-panel.ts',
      'app/live/live-state.ts',
      'app/shared/announcer.ts',
      'app/shared/narrow-note.ts',
      'app/shared/server-button.ts',
    ]);
  });
});

describe('focus moves only for the user or through the focus rule', () => {
  /** Every call that moves focus: how many each file has, and why they are allowed. */
  const FOCUS_CALLS = {
    'app/chat/composer.ts': [1, 'the field takes focus after the user\'s own Send'],
    'app/chat/chat-panel.ts': [1, 'the target of the New messages button, which the user pressed'],
    'app/shared/popover.ts': [2, 'a popover returns focus to its trigger when the user closes it, and takes it into its panel when the user opens it'],
    'app/shared/focus-rule.ts': [1, 'the page\'s one focus rule, for an update that removed the focused element'],
    'app/shared/layout.ts': [2, 'the region that the user\'s skip link or Status press reveals, and the Status button when the user closes the drawer from inside it (Story 2.15)'],
    'app/main-page/main-page.ts': [1, 'a focused element of the rail keeps its focus when the layout moves the rail (Story 2.15)'],
  };

  it('has a .focus( call only in the files that the user\'s own action or the focus rule moves focus from, and no more of them', () => {
    const found = files.map((one) => [one.name, (one.code.match(/\.focus\(/g) ?? []).length]).filter(([, count]) => count > 0);
    assert.deepEqual(Object.fromEntries(found), Object.fromEntries(Object.entries(FOCUS_CALLS).map(([name, [count]]) => [name, count])));
  });

  it('uses no other way to move focus: no autofocus, no focus trap, no focus monitor, no select()', () => {
    assert.deepEqual(filesWith(/\bautofocus\b|cdkTrapFocus|cdkFocusInitial|FocusTrap|FocusMonitor|focusVia|focusInitialElement|\.select\(\)/), []);
  });

  it('waits for a render only to scroll the chat, to focus a popover or the drawer that the user opened, and for the focus rule', () => {
    assert.deepEqual(filesWith(/\bafterNextRender\(|\bafterEveryRender\(|\bafterRenderEffect\(/).sort(), ['app/chat/chat-panel.ts', 'app/shared/focus-rule.ts', 'app/shared/layout.ts', 'app/shared/popover.ts']);
  });

  it('gives the banner stack, the rail, the chat panel, the main page and the header the shared rule, and each its own rule only', () => {
    const hosts = {
      'app/header/header.ts': /const STATUS_RULE: FocusRule = \{ within: '\.status-button' \}/,
      'app/banners/banner-stack.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{BANNER_ID\}\]`/,
      'app/rail/status-rail.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{ROW_KEY\}\]`/,
      'app/chat/chat-panel.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{PART\}\]\[\$\{KEY\}\]`/,
      'app/main-page/main-page.ts': /const LOAD_ERROR_RULE: FocusRule = \{ within: '\.load-error' \}[\s\S]*const NOTE_RULE: FocusRule = \{ within: '\.narrow-note' \}/,
    };
    for (const [name, rule] of Object.entries(hosts)) {
      const { code: text } = file(name);
      assert.match(text, /import \{ type FocusRule, keepFocus \} from '\.\.\/shared\/focus-rule';/, `${name} imports the shared rule`);
      assert.match(text, /untracked\(\(\) => keepFocus\(this\.host\.nativeElement, this\.injector, this\.popovers, [A-Z_]+\)\)/, `${name} calls it from an effect`);
      assert.match(text, rule, `${name} has its own rule`);
    }
    assert.deepEqual(filesWith(/(function|private|protected)\s+keepFocus\b/), ['app/shared/focus-rule.ts'], 'only the shared module defines keepFocus');
  });

  it('gives the chat\'s rule no whenGone, so that a message that is gone leaves focus to the main region, and the load error\'s, the note\'s and the Status button\'s no item', () => {
    const chat = file('app/chat/chat-panel.ts').code;
    assert.doesNotMatch(chat.slice(chat.indexOf('const FOCUS_RULE'), chat.indexOf('};', chat.indexOf('const FOCUS_RULE'))), /whenGone/);
    assert.doesNotMatch(file('app/main-page/main-page.ts').code, /(?:LOAD_ERROR|NOTE)_RULE: FocusRule = \{[^}]*item/);
    assert.doesNotMatch(file('app/header/header.ts').code, /STATUS_RULE: FocusRule = \{[^}]*item/);
  });
});
