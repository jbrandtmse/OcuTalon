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
    assert.equal((announcer.match(/this\.live\.announce\(text, /g) ?? []).length, 1, 'one call that speaks a text');
    assert.equal((announcer.match(/this\.live\.announce\(/g) ?? []).length, 2, 'and one more, which empties the region for a retracted text');
    assert.match(announcer, /retract\(message: string\): void \{[^}]*this\.queue\.retract\(text\);\s*if \(text !== '' && this\.lastSpoken === text\) \{\s*this\.lastSpoken = '';\s*void this\.live\.announce\('', 'polite'\);/);
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

  it('announces from one place per event: the rail, the header and the reply, card (notice and incident) and message components do not announce', () => {
    // A story that makes one of these announce moves the event's announcement from the chat or the control that owns it, so that the
    // event is still heard once (Story 2.12, Decided 4); it then edits this list with that reason. The guide announces an advance and the
    // box announces "Sent" (Story 4.4): nothing else announces either.
    // Story 16.1: the header's credential rows speak (credential-rows.ts: "Copied" or the copy failure, once, after the user's own press on a
    // copy button), so that file is the one header file that is not silent; the header itself still is.
    // Story 41.13: the Memory card speaks (memory-card.ts: the one notice of a panel, once, when a Pin, Unpin or search fails), the second rail file that is not silent.
    // Stories 12.4 and 12.5: the Telegram card speaks (telegram-card.ts: "Telegram paired" or "Telegram unpaired", once each, when the pairing
    // changes), the one rail file that is not silent; the pairing change is announced once, from the card that shows it (UX-DR132).
    const silent = files.filter((one) => (one.name !== 'app/header/credential-rows.ts' && one.name !== 'app/rail/telegram-card/telegram-card.ts' && one.name !== 'app/rail/memory-card/memory-card.ts' && /^app\/(rail|header)\//.test(one.name)) || ['app/chat/ocutalon-reply.ts', 'app/chat/notice-card.ts', 'app/chat/user-message.ts', 'app/chat/decision-strip.ts', 'app/incidents/incident-card.ts', 'app/incidents/evidence-panel.ts'].includes(one.name));
    assert.ok(silent.length >= 8, 'the silent files are found');
    assert.ok(silent.some((one) => one.name === 'app/incidents/incident-card.ts'), 'the incident card is among them');
    assert.deepEqual(silent.filter((one) => /\bAnnouncer\b|\.announce\(/.test(one.code)).map((one) => one.name), []);
  });

  it('has these speakers and no others: banners, the chat and its outbox, the demo guide and the Break the feed box, the load failure, the simulated mailbox (a decided email and a sample that arrived), the busy notice, the narrow-window note, the press of Approve and Reject (the notices of the user\'s own press, on the chat\'s request card and on the simulated phone: busy, late, refused and failed), the approval request card (an answer that came from elsewhere, once), Dismiss (the message of an error reply, once, Story 6.4), the credential rows (Story 16.1) and the Telegram card (the pairing and the unpairing, once each, Stories 12.4 and 12.5) and the settings page (the saved text of a section, once, a failed save of the thresholds, and the load failure, Story 33.2; the saved and failed texts of the Models and Budgets sections and the Test result line, once, Story 18.3) and the Documents page (a refused file or a failed document of the user\'s own add, once, Story 34.2) and Got it (the message of an error reply, once, Story 18.4) and the Memory card (the one notice of a panel, once, Story 41.13) and the shared confirm dialog (its failure notice, once, Story 41.13)', () => {
    assert.deepEqual(filesWith(/\bannouncer\.announce\(|\.announce\(/).sort(), [
      'app/approvals/answer-press.ts',
      'app/approvals/approval-request-card.ts',
      'app/banners/banner-stack.ts',
      // Sending a file from the chat: a refusal or a failed send, once (Story 25.3).
      'app/chat/chat-files.ts',
      'app/chat/chat-outbox.ts',
      'app/chat/chat-panel.ts',
      'app/chat/got-it.ts',
      'app/chat/noise-control.ts',
      'app/documents/documents-page.ts',
      'app/feed/break-feed-box.ts',
      'app/guide/demo-guide.ts',
      'app/header/credential-rows.ts',
      // The History page: its load failure, "Couldn't load your history.", once per failed read (Story 25.2).
      'app/history/history-page.ts',
      'app/incidents/incident-dismiss.ts',
      'app/live/live-state.ts',
      'app/mailbox/simulated-mailbox.ts',
      'app/rail/memory-card/memory-card.ts',
      'app/rail/telegram-card/telegram-card.ts',
      'app/settings/budgets-section.ts',
      'app/settings/check-thresholds-section.ts',
      'app/settings/daily-digest-section.ts',
      'app/settings/demo-mode-section.ts',
      'app/settings/email-section.ts',
      // The Tools and MCP servers section (Story 21.4): the load failure, the saved or failed add, a removal and a classification, once each.
      'app/settings/mcp-section.ts',
      'app/settings/models-section.ts',
      'app/settings/roles-section.ts',
      'app/settings/settings-page.ts',
      'app/settings/time-zone-section.ts',
      // The Webhooks group (Story 35.3): the saved text of a create or a replacement, once, and a refused or failed one.
      'app/settings/webhooks-section.ts',
      'app/shared/announcer.ts',
      'app/shared/confirm-dialog.ts',
      'app/shared/narrow-note.ts',
      'app/shared/server-button.ts',
      // The Usage page: its load failure, "Couldn't load your usage.", once per failed read (Story 37.2).
      'app/usage/usage-page.ts',
    ]);
  });
});

describe('focus moves only for the user or through the focus rule', () => {
  /** Every call that moves focus: how many each file has, and why they are allowed. */
  const FOCUS_CALLS = {
    'app/chat/composer.ts': [1, 'the field takes focus after the user\'s own Send'],
    'app/chat/chat-panel.ts': [1, 'the target of the New messages button, which the user pressed'],
    'app/guide/demo-guide.ts': [1, 'Show me focuses the phone\'s pending notification or its feed, for the user\'s own press (Story 4.7)'],
    'app/guide/more-to-try.ts': [1, 'an item of Other things to try hands focus to the control it presses, for the user\'s own press (Story 4.11)'],
    'app/devices/device-panel.ts': [1, 'the tab that the user\'s arrow key moved to'],
    'app/history/history-page.ts': [3, 'the tab that the user\'s arrow key moved to, the first filter after the user\'s own Clear filters, whose button leaves with the filters, and the page\'s main region after the user\'s own Previous or Next page, whose pager leaves while the page loads (Story 25.2)'],
    'app/rail/heartbeat-card/heartbeat-card.ts': [1, 'Edit, after the user\'s own Esc collapses its disclosure'],
    'app/rail/persona-card/persona-card.ts': [1, 'Change, after the user\'s own Esc collapses its disclosure'],
    'app/rail/memory-card/memory-card.ts': [2, 'the tab that the user\'s arrow key moved to, and the Memory heading after the user\'s own confirmed Forget, or after an Unpin that took the row off Pinned, when the dialog or the button has given focus back and the row is gone (Stories 41.6 and 41.13)'],
    'app/mailbox/simulated-mailbox.ts': [2, 'the mailbox\'s own views move focus for the user\'s press (the form\'s From, the open email\'s heading, the row or Simulate after Back, the first field in error after Send, the sent email\'s row), through focusLater and focusSent'],
    'app/phone/simulated-phone.ts': [1, 'the target of the phone\'s New messages button, which the user pressed'],
    'app/shared/popover.ts': [2, 'a popover returns focus to its trigger when the user closes it, and takes it into its panel when the user opens it'],
    'app/documents/documents-page.ts': [3, 'the list region takes focus after the user\'s own confirmed Remove, when the dialog has given focus back and the row they pressed is gone (Story 34.2), and after the user\'s own Close of an opened document; the opened document\'s heading takes focus once its text is drawn, after the user\'s own Open document (Story 20.2); the Add the sample runbook button takes focus before it is pressed, when the user\'s own press of the demo guide\'s sample control asked for it (Story 20.3)'],
    'app/shared/focus-rule.ts': [1, 'the page\'s one focus rule, for an update that removed the focused element'],
    'app/shared/layout.ts': [2, 'the region that the user\'s skip link or Status press reveals, and the Status button when the user closes the drawer from inside it (Story 2.15)'],
    'app/main-page/main-page.ts': [1, 'a focused element of the rail keeps its focus when the layout moves the rail (Story 2.15)'],
    'app/settings/budgets-section.ts': [1, 'the first field in error takes focus after the user\'s own Save changes (Story 18.3)'],
    'app/settings/models-section.ts': [1, 'the first field in error takes focus after the user\'s own Save changes (Story 18.3)'],
    'app/settings/check-thresholds-section.ts': [1, 'the first field in error takes focus after the user\'s own Save changes (Story 33.2)'],
    'app/settings/daily-digest-section.ts': [1, 'the first field in error takes focus after the user\'s own Save changes (Story 18.2)'],
    'app/settings/demo-mode-section.ts': [1, 'the switch takes focus when the user\'s own Save changes is refused or the Demo step fails (Story 33.2)'],
    'app/settings/email-section.ts': [1, 'the first field in error takes focus after the user\'s own Save changes (Story 21.2)'],
    'app/settings/mcp-section.ts': [2, 'the first field in error takes focus after the user\'s own Add server, and the Servers heading takes focus after the user\'s own confirmed Remove, when the dialog has given focus back and the row they pressed is gone (Story 21.4)'],
    'app/settings/time-zone-section.ts': [1, 'the select takes focus after the user\'s own Save changes is refused for the zone (Story 18.2)'],
    'app/settings/webhooks-section.ts': [1, 'the first field in error takes focus after the user\'s own Create webhook or Save changes (Story 35.3)'],
    'app/settings/roles-section.ts': [1, 'the user name field takes focus after the user\'s own Grant is refused, and the list heading after the user\'s own Remove, whose button leaves with the role (Story 25.4)'],
    'signin/splash.js': [1, 'a copy that fails on the splash gives the focus to the input whose value it selects, after the user pressed the copy button (Story 16.2)'],
  };

  it('has a .focus( call only in the files that the user\'s own action or the focus rule moves focus from, and no more of them', () => {
    const found = files.map((one) => [one.name, (one.code.match(/\.focus\(/g) ?? []).length]).filter(([, count]) => count > 0);
    assert.deepEqual(Object.fromEntries(found), Object.fromEntries(Object.entries(FOCUS_CALLS).map(([name, [count]]) => [name, count])));
  });

  it('uses no other way to move focus: no autofocus, no focus trap, no focus monitor, no select()', () => {
    assert.deepEqual(filesWith(/\bautofocus\b|cdkTrapFocus|cdkFocusInitial|FocusTrap|FocusMonitor|focusVia|focusInitialElement|\.select\(\)/), []);
  });

  it('waits for a render only to scroll the chat, to focus a popover, the drawer, a mailbox view or the phone\'s notification (Show me) or the control an Other things to try item hands off to, that the user opened, to measure the room that the Other things to try panel and the banners leave, the heading of the document the user opened with Open document, the first field in error of a settings form that the user saved, for the focus rule, and for the request card to read where focus is before it announces an answer from elsewhere', () => {
    assert.deepEqual(filesWith(/\bafterNextRender\(|\bafterEveryRender\(|\bafterRenderEffect\(/).sort(), ['app/approvals/approval-request-card.ts', 'app/chat/chat-panel.ts', 'app/documents/documents-page.ts', 'app/guide/demo-guide.ts', 'app/guide/more-to-try-room.ts', 'app/guide/more-to-try.ts', 'app/mailbox/simulated-mailbox.ts', 'app/settings/budgets-section.ts', 'app/settings/check-thresholds-section.ts', 'app/settings/daily-digest-section.ts', 'app/settings/demo-mode-section.ts', 'app/settings/email-section.ts', 'app/settings/mcp-section.ts', 'app/settings/models-section.ts', 'app/settings/roles-section.ts', 'app/settings/time-zone-section.ts', 'app/settings/webhooks-section.ts', 'app/shared/focus-rule.ts', 'app/shared/layout.ts', 'app/shared/popover.ts']);
  });

  it('gives the banner stack, the rail, the chat panel, the device panel, the approval request card, the phone\'s request message, the demo guide, the main page, the header and the app (the resetting view, Story 16.8) the shared rule, and each its own rule only', () => {
    const hosts = {
      'app/app.ts': /const RESETTING_RULE: FocusRule = \{\};/,
      'app/header/header.ts': /const STATUS_RULE: FocusRule = \{ within: '\.status-button' \}/,
      'app/banners/banner-stack.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{BANNER_ID\}\]`/,
      'app/rail/status-rail.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{ROW_KEY\}\]`/,
      'app/chat/chat-panel.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{PART\}\]\[\$\{KEY\}\]`/,
      'app/devices/device-panel.ts': /const FOCUS_RULE: FocusRule = \{\s*item: '\[data-part\]\[data-key\]',\s*keyOf: \(item\) => `\$\{item\.getAttribute\('data-part'\) \?\? ''\}:\$\{item\.getAttribute\('data-key'\) \?\? ''\}`,\s*\};/,
      'app/approvals/approval-request-card.ts': /const ANSWER_RULE: FocusRule = \{\s*item: `\[\$\{PART\}="answer"\]\[\$\{KEY\}\]`,\s*keyOf: \(item\) => item\.getAttribute\(KEY\) \?\? '',\s*\};/,
      'app/phone/phone-request.ts': /const PHONE_ANSWER_RULE: FocusRule = \{\s*item: `\[\$\{PART\}="answer"\]\[\$\{KEY\}\]`,\s*keyOf: \(item\) => item\.getAttribute\(KEY\) \?\? '',\s*\};/,
      'app/guide/demo-guide.ts': /const FOCUS_RULE: FocusRule = \{[\s\S]*?item: `\[\$\{FOCUS_KEY\}\]`[\s\S]*?whenGone:/,
      'app/main-page/main-page.ts': /const LOAD_ERROR_RULE: FocusRule = \{ within: '\.load-error' \}[\s\S]*const NOTE_RULE: FocusRule = \{ within: '\.narrow-note' \}/,
    };
    for (const [name, rule] of Object.entries(hosts)) {
      const { code: text } = file(name);
      assert.match(text, /import \{ type FocusRule, keepFocus(?:, type LostFocus)? \} from '\.\.?\/shared\/focus-rule';/, `${name} imports the shared rule`);
      assert.match(text, /untracked\(\(\) => keepFocus\(this\.host\.nativeElement, this\.injector, this\.popovers, [A-Z_]+\)\)/, `${name} calls it from an effect`);
      assert.match(text, rule, `${name} has its own rule`);
    }
    assert.deepEqual(filesWith(/(function|private|protected)\s+keepFocus\b/), ['app/shared/focus-rule.ts'], 'only the shared module defines keepFocus');
  });

  it('gives the chat\'s rule one whenGone, for the Dismiss of an incident card (focus goes to the compacted headline), so that any other message that is gone leaves focus to the main region, and the load error\'s, the note\'s and the Status button\'s no item', () => {
    const chat = file('app/chat/chat-panel.ts').code;
    const rule = chat.slice(chat.indexOf('const FOCUS_RULE'), chat.indexOf('};', chat.indexOf('const FOCUS_RULE')));
    assert.match(rule, /whenGone: \(lost\) => incidentHeadline\(lost\),/);
    assert.equal((chat.match(/whenGone/g) ?? []).length, 1, 'one whenGone in the panel');
    const headline = chat.slice(chat.indexOf('function incidentHeadline'), chat.indexOf('\n}\n', chat.indexOf('function incidentHeadline')));
    assert.match(chat, /const DISMISS_PREFIX = 'dismiss:';/);
    assert.match(headline, /if \(!lost\.key\.startsWith\(DISMISS_PREFIX\)\) \{\s*return null;\s*\}/, 'any other lost item gives null');
    assert.match(headline, /lost\.host\.querySelector<HTMLElement>\(`\[\$\{PART\}="incident"\]\[\$\{KEY\}="\$\{CSS\.escape\(key\)\}"\] \.headline`\)/, 'the headline of the card with that key');
    assert.doesNotMatch(headline, /\.focus\(/, 'and the shared rule moves the focus');
    assert.doesNotMatch(file('app/main-page/main-page.ts').code, /(?:LOAD_ERROR|NOTE)_RULE: FocusRule = \{[^}]*item/);
    assert.doesNotMatch(file('app/header/header.ts').code, /STATUS_RULE: FocusRule = \{[^}]*item/);
  });
});

describe('the failure notices of the confirm dialog and the Memory card (Story 41.13; DW-996, DW-997, NFR-25)', () => {
  it('shows the confirm dialog\'s notice under an id of its own, names it in the confirm button\'s description, and announces it once', () => {
    const dialog = file('app/shared/confirm-dialog.ts').code;
    assert.match(dialog, /noticeId = `confirm-dialog-notice-\$\{\(lastDialog \+= 1\)\}`/, 'an id of its own for each dialog');
    assert.match(dialog, /<app-inline-notice [^>]*\[id\]="noticeId"/, 'the notice carries the id');
    assert.match(dialog, /\[describedBy\]="failed\(\) \? \[noticeId\] : \[\]"/, 'the confirm button is described by it while it shows');
    assert.equal((dialog.match(/\.announce\(/g) ?? []).length, 1, 'one place announces');
    assert.match(dialog, /this\.failed\.set\(true\);\s*this\.announcer\.announce\(this\.content\.failed\);/, 'when the notice is set, once');
  });

  it('replaces both old dialogs: nothing refers to the Forget or Remove dialogs any more', () => {
    assert.deepEqual(filesWith(/app-forget-answer-dialog|app-remove-document-dialog|forget-dialog|remove-dialog|FORGET_TITLE_ID|REMOVE_TITLE_ID|\bFORGOTTEN\b|\bREMOVED\b|ForgetTarget|RemoveTarget/), []);
    assert.deepEqual(filesWith(/\bConfirmDialog\b/).sort(), ['app/documents/documents-page.ts', 'app/rail/memory-card/memory-card.ts', 'app/settings/mcp-section.ts', 'app/shared/confirm-dialog.ts']);
  });

  it('shows the Memory card\'s notice of a panel under an id of its own, announces it once, and names it in the pressed control\'s description', () => {
    const card = file('app/rail/memory-card/memory-card.ts').code;
    assert.equal((card.match(/\.announce\(/g) ?? []).length, 1, 'one place announces');
    assert.match(card, /if \(notice !== undefined\) \{\s*this\.announcer\.announce\(notice\.text\);/);
    assert.equal((card.match(/\[id\]="noticeId\('(?:pinned|memories)'\)"/g) ?? []).length, 2, 'one notice for each panel, with its id');
    assert.match(card, /\[describedBy\]="describedBy\(panel, item\.ref\)"/, 'the Pin or Unpin button names it');
    assert.match(card, /\[attr\.aria-describedby\]="describing\('memories', ''\)"/, 'and so does the search');
  });

  it('searches only when the form is submitted: no input, keyup or change handler on the search box', () => {
    const card = file('app/rail/memory-card/memory-card.ts').code;
    assert.match(card, /<form class="search" role="search" \(submit\)="submit\(\$event, query\.value\)">/);
    assert.doesNotMatch(card, /\(input\)=|\(keyup\)=|\(keypress\)=|\(change\)=|valueChanges|debounce/);
  });
});
