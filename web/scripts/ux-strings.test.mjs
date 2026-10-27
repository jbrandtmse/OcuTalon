// Tests that every fixed string the page can show has one source (Story 2.16; UX-DR117, UX-DR138): the UX first. The inventory is the
// page's constants (imported as they are, the way trace-view.test.mjs imports its module), the constants that only the source text
// holds (read with the comments stripped), and every literal text run and literal aria-label, title, placeholder and alt value of
// each component template under src/app/. The SOURCES table gives each inventory string one source: `ux` (EXPERIENCE.md holds it
// verbatim), `design` (DESIGN.md does), `ac` (a story's acceptance criteria state it), `ruled` (the UX does not write it and a ruling of
// the cycle log fixed it), `calendar` or `format` (checked here, mechanically). The criteria and the rulings are bookkeeping paths that
// never run the web job, so they are written out here with their story; the two UX documents are web inputs and are read.
// It fails for an inventory string with no entry, an entry that matches no inventory string, a document that does not hold its
// entry's string, a string without a slot that EXPERIENCE.md holds while its entry names a later source, and a *_TEXTS constant that is
// not imported; no string holds "...", a string that holds the ellipsis holds U+2026 once and has the UX's, and the only non-ASCII
// characters are U+2026 and U+00B7. A string that none of these sources covers is public text that nobody ruled: it is never given an
// invented source, and the story's stage escalates it.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const appDir = join(here, '..', 'src', 'app');
const app = (...parts) => pathToFileURL(join(appDir, ...parts)).href;
const uxDir = join(here, '..', '..', '_bmad-output', 'planning-artifacts', 'ux-designs', 'ux-OcuTalon-2026-10-16');
const documents = {
  ux: readFileSync(join(uxDir, 'EXPERIENCE.md'), 'utf8'),
  design: readFileSync(join(uxDir, 'DESIGN.md'), 'utf8'),
};

// --- the inventory ---

/** Every string leaf of a constant, by its path. */
function leaves(name, value, into) {
  if (typeof value === 'string') into.push([name, value]);
  else if (Array.isArray(value)) value.forEach((one, i) => leaves(`${name}[${i}]`, one, into));
  else if (value !== null && typeof value === 'object') Object.entries(value).forEach(([key, one]) => leaves(`${name}.${key}`, one, into));
}

/** The constants of the page's view modules, imported as they are. */
const IMPORTED = [
  ['chat/chat-view.ts', ['CHAT_TEXTS', 'NOTICE_TEXTS']],
  ['chat/decision-view.ts', ['DECISION_TEXTS']],
  ['rail/rail-view.ts', ['RAIL_TEXTS']],
  ['shared/trace-view.ts', ['TRACE_TEXTS']],
  ['banners/banner-view.ts', ['BANNER_TEXTS']],
  ['shared/layout-view.ts', ['LAYOUT_TEXTS']],
  ['shared/announce-queue.ts', ['NEW_UPDATES']],
  ['chat/page-time.ts', ['WHEN_TEXTS']],
  ['incidents/incident-view.ts', ['INCIDENT_TEXTS']],
  ['approvals/approval-view.ts', ['APPROVAL_TEXTS']],
  ['msg/catalog.ts', ['PAGE_TEXTS', 'MESSAGE_TEXTS']],
  ['guide/guide-view.ts', ['GUIDE_TEXTS']],
  ['feed/break-feed-view.ts', ['FEED_TEXTS']],
  ['devices/device-view.ts', ['DEVICE_TEXTS']],
  ['phone/phone-view.ts', ['PHONE_TEXTS']],
  ['mailbox/mailbox-view.ts', ['MAILBOX_TEXTS']],
];
const modules = {};
const imported = [];
for (const [file, names] of IMPORTED) {
  modules[file] = await import(app(...file.split('/')));
  for (const name of names) {
    assert.ok(modules[file][name] !== undefined, `${file} exports ${name}`);
    leaves(name, modules[file][name], imported);
  }
}

const sources = sourceFiles(appDir, ['.ts']).filter((file) => !file.name.endsWith('.test.ts'));
const codeOf = (name) => {
  const file = sources.find((one) => one.name === name);
  assert.ok(file, `${name} is a source file of the page`);
  return file.code;
};

/** The literal strings that a pattern captures in a source's code: exactly `count` of them, so that a change to the source fails here. */
function grab(name, pattern, count) {
  const found = [...codeOf(name).matchAll(pattern)].map((match) => match[1] ?? match[2]);
  assert.equal(found.length, count, `${name}: ${pattern} matches ${count} time(s), found ${found.length}`);
  return found;
}
const QUOTED = "(?:'([^']*)'|\"([^\"]*)\")";

/** The constants that only the source text holds. */
const fromSource = [
  ['BUSY_NOTICE', grab('shared/server-button.ts', new RegExp(`export const BUSY_NOTICE = ${QUOTED};`, 'g'), 1)[0]],
  ['LOAD_FAILED', grab('live/live-state.ts', new RegExp(`export const LOAD_FAILED = ${QUOTED};`, 'g'), 1)[0]],
  ...grab('header/skip-links.ts', new RegExp(`\\{ text: ${QUOTED}, target: ${QUOTED}(?:, demo: true)? \\}`, 'g'), 3).map((text) => ['SKIP_LINKS', text]),
  ['ABOUT_CLOSE_NAME', grab('about/about-dialog.ts', new RegExp(`export const ABOUT_CLOSE_NAME = ${QUOTED};`, 'g'), 1)[0]],
  ['theme prefix', grab('header/header.ts', /`(Theme: )\$\{THEME_OPTIONS/g, 1)[0]],
  ['Online demo', grab('header/header.ts', new RegExp(`return ${QUOTED};\\s*\\}\\s*return snapshot\\?\\.demoMode`, 'g'), 1)[0]],
  ['Demo mode', grab('header/header.ts', new RegExp(`snapshot\\?\\.demoMode \\? ${QUOTED} :`, 'g'), 1)[0]],
  ['Account', grab('header/header.ts', new RegExp(`\\|\\| ${QUOTED}\\)`, 'g'), 1)[0]],
];
// The theme menu's labels are the second quoted string of each option.
const themeLabels = [...codeOf('header/header.ts').matchAll(new RegExp(`\\{ value: ${QUOTED}, label: ${QUOTED} \\}`, 'g'))].map((match) => match[3] ?? match[4]);
assert.equal(themeLabels.length, 3, 'header.ts: the theme menu has three options');
for (const label of themeLabels) fromSource.push(['THEME_OPTIONS', label]);

/** Collapses white space to one space and trims, as the page's text nodes render. */
const collapse = (text) => text.replace(/\s+/g, ' ').trim();
const SLOT = '{slot}';

/** The literal text runs and the literal aria-label, title, placeholder and alt values of one component template, with each interpolation as {slot}. */
function templateStrings(template) {
  const found = [];
  for (const match of template.matchAll(/\s(aria-label|title|placeholder|alt)="([^"]*)"/g)) {
    const value = collapse(match[2].replace(/\{\{[\s\S]*?\}\}/g, SLOT));
    if (value !== '') found.push([`@${match[1]}`, value]);
  }
  const text = template
    .replace(/<\/?[a-zA-Z][^\s>/]*(?:"[^"]*"|'[^']*'|[^>"'])*>/g, '\0')
    .replace(/\{\{[\s\S]*?\}\}/g, '\x01')
    .replace(/@(?:if|else if|for|switch|case)\s*\([^{]*\)\s*\{/g, '\0')
    .replace(/@(?:else|empty|default)\s*\{/g, '\0')
    .replace(/\}/g, '\0')
    .replace(/\x01/g, SLOT);
  for (const run of text.split('\0').map(collapse)) {
    if (run.replaceAll(SLOT, '').trim() !== '') found.push(['text', run]);
  }
  return found;
}

const fromTemplates = [];
const components = sources.filter((file) => /@Component\(/.test(file.code));
for (const file of components) {
  assert.ok(!/templateUrl\s*:/.test(file.code), `${file.name}: the template is inline, so that this test reads it`);
  const template = /template:\s*`([^`]*)`/.exec(file.code);
  assert.ok(template, `${file.name}: a component with an inline template`);
  for (const [kind, text] of templateStrings(template[1])) fromTemplates.push([`${file.name} ${kind}`, text]);
}

/** Every inventory string, with where it came from. */
const inventory = new Map();
for (const [name, text] of [...imported, ...fromSource, ...fromTemplates]) {
  if (!inventory.has(text)) inventory.set(text, []);
  inventory.get(text).push(name);
}

// --- the sources ---

/**
 * Each inventory string has exactly one source.
 * - ux, design: the document holds the string verbatim; each {slot} of a template matches a non-empty run on one line.
 * - ac: a story's acceptance criteria (epics.md) state it.
 * - ruled: the UX does not write it; the ruling of the cycle log (cycle-log-epic-2.md) fixed it.
 * - calendar: the English weekday and month names.
 * - format: a template whose text, with its slots removed, holds only punctuation, digits, the separator and unit words.
 */
const SOURCES = {
  ux: [
    'Message OcuTalon',
    'Send',
    'Not sent',
    'Retry sending',
    'Deciding\u2026',
    'Working\u2026',
    'Working \u00b7 {n} s',
    'Working \u00b7 {n} seconds',
    '{label}\u2026',
    'New messages',
    'OcuTalon',
    'via Telegram',
    'From the demo guide',
    '(opens in a new tab)',
    'For everything that arrives, OcuTalon makes one attention decision',
    'It watches your productions from inside IRIS, and every decision is a production message you can trace.',
    'Anything risky waits for your approval.',
    'Ask OcuTalon to watch a production, set a reminder, or say what you need.',
    'Ignore',
    'Digest',
    'Tell now',
    'Act',
    'Recorded; nobody notified',
    'Saved for later; nobody notified now',
    'Needs you now',
    'OcuTalon took or requested an action',
    'OcuTalon replied:',
    'Tell now:',
    'Message not sent',
    'Due {time}',
    'arrived {time}',
    'Confidence {n}',
    'Fallback',
    'Details',
    'Decision details',
    'Tokens',
    'Model',
    'Duration',
    'Cost',
    'Input',
    'Output (includes thinking)',
    'Cache read',
    'Cache write',
    'Decision {decision} \u00b7 Turn {turn}',
    '<$0.0001',
    'Passed',
    'Failed',
    'Not checked',
    'Telegram',
    'Approval requests',
    'Background checks',
    'Reminders',
    'Recent decisions',
    'None waiting.',
    'Ask OcuTalon to watch a production.',
    'None pending.',
    'No decisions yet.',
    'To stop, ask: "Stop watching Orders."',
    'To cancel, ask: "Cancel my reminder to stretch."',
    'Run {toolName}',
    'expires {when}',
    '{name} production',
    'Live, plus a check every minute',
    'Last run {when}',
    'Last run {when} (late)',
    'Telegram not set up',
    'How to set it up',
    'Trace',
    'Open in Visual Trace (shows sign-in help first)',
    'Sign in to Visual Trace',
    'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.',
    'Don\'t show this again',
    'Visual Trace',
    'Open my conversation in Visual Trace',
    'Status',
    '1 approval request',
    'This page is designed for a wider window. Everything still works.',
    '{n} new updates',
    'tomorrow at {time}',
    'I couldn\'t answer that: {fallbackReason}. Nothing was changed.',
    'Everything I checked passed.',
    'Everything else I checked passed.',
    'I\'m not watching any productions yet, so I can\'t say. Ask me to watch one.',
    'You\'ve used this session\'s {limit} messages for the hour (messages you send in the chat or Telegram). You can send more at {time}.',
    'The online demo has used today\'s model allowance. Decisions use fixed rules until {time}.',
    'Can\'t reach OcuTalon. Retrying every 10 seconds.',
    'OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon.',
    'OcuTalon has reached today\'s cost limit of {cap}. Decisions use fixed rules until {time}.',
    'Background checks have paused: the heartbeat last ran at {time}. Watches and reminders may be late until it recovers.',
    'Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at {time}. Each OcuTalon needs its own bot.',
    'The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.',
    'Reconnecting\u2026 New messages may be delayed.',
    'Install it yourself',
    'How to set a key',
    'Set up a bot',
    'the model didn\'t answer within 60 seconds',
    'the model\'s reply was empty',
    'the model\'s reply was cut off',
    'the model declined to answer',
    'the model returned an error',
    'the model was busy and retries ran out',
    'this would have gone over the token budget',
    'this request would have been too large to send',
    'today\'s cost limit has been reached',
    'no model key is set',
    'the model\'s reply couldn\'t be used',
    'Couldn\'t reach OcuTalon. Try again. Nothing was changed.',
    'Couldn\'t load your session.',
    'Skip to chat',
    'Skip to simulated devices',
    'Skip to status',
    'System',
    'Light',
    'Dark',
    'Theme: ',
    'Online demo',
    'Demo mode',
    'Account',
    'An OpenClaw-style assistant for InterSystems IRIS.',
    'An assistant that runs as an IRIS Interoperability production and decides, for everything that arrives, whether it deserves your attention.',
    'Default model: {slot}.',
    'README',
    'Built with the BMAD Method and Claude Code.',
    'OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.',
    'Ocu',
    'Talon',
    'About OcuTalon',
    'Sign out',
    'Theme',
    'Chat',
    'Retry',
    'Start with step 1 of the demo guide above.',
    'Nothing yet. Step 1 of the guide sets up a watch.',
    'Demo guide',
    'Hide guide',
    'Show guide',
    'Watch',
    'Reminder',
    'Break the feed',
    'Approve',
    'Open the trace',
    'Watch the Orders production and only tell me if something needs me.',
    'Remind me in 1 minute to stretch.',
    'Optional: scan the QR code in the Telegram card to get the notice on your own phone.',
    'Step {n}, {label}, current',
    'Step {n} of 5: {step}',
    'Demo control',
    'Next step',
    'Ask OcuTalon to watch the Orders production first (step 1).',
    'Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.',
    'Do step 1',
    'Sending 50 orders\u2026',
    'Sent. OcuTalon usually notices within a minute.',
    'OcuTalon noticed failures in the Orders production',
    'Waiting for the failures to settle',
    'Working out the cause from the failed messages',
    'Still waiting. The notice will appear in the chat and on the Simulated phone tab.',
    "No notice after 3 minutes, so something went wrong with this run. Open the Orders watch's trace in Background checks, or try again.",
    'Simulated devices',
    'Simulated phone',
    'Simulated mailbox',
    'Simulated',
    '{tab}, {n} new',
    "Notifications, reminders and approval requests appear here. The simulated phone is a real channel in the production; you'll see it in the trace.",
    'Send one and see what OcuTalon decides.',
    'Simulate an incoming email',
    'No emails yet. Simulate an incoming email, or send a sample.',
    "Email '{subject}': {outcome}",
    ', send sample email',
    'From',
    'Subject',
    'Body',
    'Back',
    'Results Partner IT <it@results-partner.example>',
    'Press Break the feed. The partner will send 50 orders in a new date format.',
    'Waiting for OcuTalon. The reminder may arrive first.',
    'Go to Break the feed',
    'Approve the fix in Telegram on your phone, or on the simulated phone.',
    'Approve the fix on the simulated phone, or in the chat.',
    'Rejected. Nothing was changed. Dismiss the incident in the chat, then press Break the feed again.',
    "OcuTalon couldn't diagnose this run, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again.",
    "OcuTalon found the cause but has no fix for it, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again.",
    'Show me',
    "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision.",
    'Done. You saw an AI Hub agent read 50 failed orders and name the cause. Every decision, with its cost, and every step it took landed in Visual Trace, and the fix waited for your approval and was recorded in the audit log.',
    'This run: {decisions} \u00b7 {tokens} \u00b7 {cost} on {models}.',
    'This run: {decisions} \u00b7 {tokens} \u00b7 {cost}.',
    '{n} decisions',
    '{n} tokens',
    'See the whole conversation in Visual Trace',
    'Install OcuTalon yourself',
    'More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production.',
    'Run again',
    '\u2197',
    'Open',
    'Error',
    'Awaiting approval',
    'Fixing',
    'Resolved',
    'Closed',
    '{count} {noun} failed since {time}',
    '{count} {noun} failed',
    '{n} more since the notice',
    '{count} failures grouped into this incident',
    'I can {fixSummary}.',
    'Repairing and resending {count} {noun}\u2026',
    'Show details',
    'message',
    'messages',
    'Held as an IRIS Workflow task until someone answers.',
    'Incident: {headline}. Approval needed.',
    '{time} ET',
    'Approval needed',
    'Approval request',
    'Reject',
    'Approve: {action}',
    'Approving runs exactly this change on these {count} {noun}, without asking the model again. New failures need their own approval.',
    'Dry run',
    'Before',
    'After',
    'Will resend',
    '1 repaired copy; the original stays unchanged.',
    'Nothing has changed yet.',
    'Only an approver for resends can answer this request.',
    'That request is no longer available.',
    'Approved from {channel} at {time}',
    'Approved by {user} from {channel} at {time}',
    'Approved from {channel} at {time}.',
    'Rejected from {channel} at {time}. Nothing was changed.',
    'Expired at {time}. Nothing was changed.',
    'Already answered: approved from {channel} at {time}.',
    'Already answered: rejected from {channel} at {time}.',
    'Already answered: approved by {user} from {channel} at {time}.',
    'Already answered: rejected by {user} from {channel} at {time}.',
    "I couldn't work out the cause ({reason}), so I'm not proposing a fix. Nothing was changed.",
    "None of my fixes applies to this, so I'm not proposing one. Nothing was changed.",
    "I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.",
    'Failures:',
    "{item}: {count}, '{summary}', first at {time}",
    'Dismiss',
    'All {count} {itemNoun} went through.',
    "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}). I won't retry them without a new approval.",
    '{completed} of {count} {itemNoun} went through. {skipped} had changed since the dry run, so I skipped them; they need a new approval.',
    "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}), and {skipped} had changed since the dry run, so I skipped them. I won't retry any of them without a new approval.",
    "Still resending: {completed} of {count} {itemNoun} have gone through so far. I'll tell you when it's done.",
    'The resend stopped when OcuTalon restarted: {completed} of {count} {itemNoun} went through. The other {remaining} need a new approval.',
    'Nothing was resent: {reason}. Nothing was changed.',
    'Recorded in the IRIS audit log.',
  ],
  design: [
    'Unread',
    'Repair and resend',
    'Repair and resend {n} {noun}',
    'step {n} of 5',
    'About 2 minutes',
    'Next:',
    '{count} {noun} affected',
  ],
  ac: {
    'Story 6.2: Approve or reject a fix from the web chat (the expiry caption "Expires {when}" and the busy notice of an unanswered press, which adds "The request is still waiting." to the busy and failure rule of EXPERIENCE.md)': [
      'Expires {when}',
      "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
    ],
    'Story 6.1: Show each incident as one card in the chat (the announcement "Incident: {headline}. No fix proposed." of a fallback or a cause with no fix)': ['Incident: {headline}. No fix proposed.'],
    'Story 2.6: Show every decision with its reasons and cost (the Details labels Tokens, Model, Agent steps, Duration, Decision message and Cost)': ['Agent steps', 'Decision message'],
    'Story 2.8: Show the status rail (the approval request row, "Raised 14:13 \u00b7 expires tomorrow at 14:13")': ['Raised {when}'],
    'Story 2.13: Open Visual Trace from the page (the optional "Open Visual Trace" button of the popover)': ['Open Visual Trace'],
  },
  ruled: {
    'Story 6.3 veto item V2 (the accessible name of the rail row\'s title button, "Show in the chat: {action}": the visible title is unchanged and the name contains it, WCAG 2.5.3; the UX gives the press its effect, not a name)': [
      'Show in the chat: {action}',
    ],
    'Story 6.3 (the message form of the Approved-by status, the catalog\'s answered.approvedBy text form: EXPERIENCE.md ends an answered status in message text with a period, and Formats: Who answered gives the Approved-by wording)': [
      'Approved by {user} from {channel} at {time}.',
    ],
    'Story 6.2 veto item V2 (the texts that the UX does not write: the fixed-targets line for one, the Will resend values from mockups/states.html A1 and EXPERIENCE.md "Forms for a count of one", and "Reject: {action}" from mockups/main-page.html)': [
      'Reject: {action}',
      'Approving runs exactly this change on this {noun}, without asking the model again. New failures need their own approval.',
      '{count} repaired copies; the originals stay unchanged.',
    ],
    'Story 6.2 veto item V5, kept with U-117 (the Rejected-by form of the named answerer, the catalog\'s answered.rejectedBy, beside the Approved-by form of EXPERIENCE.md Formats: Who answered)': [
      'Rejected by {user} from {channel} at {time}. Nothing was changed.',
    ],
    'Story 6.1 veto item V1, kept with U-108\'s condition (the labels and item lines of the evidence panel from mockups/states.html A1, apart from "Error", which EXPERIENCE.md holds, with the one-failure line naming its one time; the count of one of the grouping; and the state-change announcement; UX-DR72 says state changes are announced but gives no words)': [
      'Cause',
      'Sample failed message',
      'Failures by item',
      'Sample message',
      'First failure',
      '{item}: {count} failures, first {first}, last {last}',
      '{item}: 1 failure, at {time}',
      '1 failure grouped into this incident',
      'Incident: {headline}. {state}.',
    ],
    'Story 4.7 veto item V1 (the sign-in name of a trace link with its own label, the singular forms of the run line and the model list\'s "and")': [
      '{label} (shows sign-in help first)',
      '{n} decision',
      '{n} token',
      '{list} and {last}',
    ],
    'Story 4.6 veto item V2 (the field errors of the compose form)': ['Enter a subject.', 'Enter a body.'],
    'Story 2.14 ruling, cycle-log-epic-2.md 2026-10-24T16:21:41Z (new Close names, the inactive conversation link\'s reason; UX-DR130, UX-DR133, UX-DR134)': [
      'Close reset notice',
      'Close reconnecting notice',
      'Close About OcuTalon',
      'Available after your first message.',
    ],
    'Story 2.15 ruling, cycle-log-epic-2.md 2026-10-24T22:15:51Z (the Status button count and the narrow-window note\'s Close; UX-DR20, UX-DR35, UX-DR128, UX-DR130)': [
      '{n} approval requests',
      'Close narrow-window note',
    ],
    'Story 4.4 ruling, spec gate 2026-10-26, veto item V2 (U-85): the step names that carry the state words of DESIGN.md\'s step markers (UX-DR45)': [
      'Step {n}, {label}, done',
      'Step {n}, {label}, upcoming',
    ],
  },
  calendar: [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ],
  format: [
    '{label} \u00b7 {n} s',
    '{label} \u00b7 {n} seconds',
    '{n} seconds',
    ' \u00b7 ',
    '{n} s',
    '{n} second',
    '{n} min',
    '{n} minute',
    '{n} minutes',
    '"{text}"',
    '{m} min {s} s',
    '{label} ({n})',
    '{label}, {n}',
    ', ',
    '{text}{separator}{countdown}',
    '{day} at {time}',
    '{month} {day}, {year}',
    '{month} {day}',
    'in {n} s',
    'in {n} second',
    'in {n} seconds',
    'in {n} min',
    'in {n} minute',
    'in {n} minutes',
    'in {h} h {m} min',
    'in {h} hour {m} {minutes}',
    'in {h} hours {m} {minutes}',
    'minute',
    'minutes',
    '({slot})',
    '{slot}, {slot}',
    '{title}.',
  ],
};

/** The unit words that a format string may hold besides punctuation, digits and the separator. */
const UNIT_WORDS = new Set(['s', 'min', 'h', 'in', 'at', 'hour', 'hours', 'minute', 'minutes', 'second', 'seconds']);

/** True when the template, with its slots removed, holds only punctuation, digits, the separator and the unit words. */
function isFormat(text) {
  const rest = text.replace(/\{[A-Za-z]+\}/g, ' ');
  return /^[A-Za-z0-9\s.,:;()\u00b7'"-]*$/.test(rest) && (rest.match(/[A-Za-z]+/g) ?? []).every((word) => UNIT_WORDS.has(word));
}

/** True when the document holds the text verbatim, each {slot} standing for a non-empty run on one line. */
function holds(document, text) {
  const pattern = text
    .split(/\{[A-Za-z]+\}/)
    .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .join('[^\n]+');
  return new RegExp(pattern).test(document);
}

/** The entries of a SOURCES table as [string, kind, why] rows. */
function entries(table) {
  return [
    ...table.ux.map((text) => [text, 'ux', 'EXPERIENCE.md']),
    ...table.design.map((text) => [text, 'design', 'DESIGN.md']),
    ...Object.entries(table.ac).flatMap(([story, texts]) => texts.map((text) => [text, 'ac', story])),
    ...Object.entries(table.ruled).flatMap(([ruling, texts]) => texts.map((text) => [text, 'ruled', ruling])),
    ...table.calendar.map((text) => [text, 'calendar', 'the English weekday and month names']),
    ...table.format.map((text) => [text, 'format', 'punctuation, digits, the separator and unit words']),
  ];
}

/** What is wrong between an inventory (string -> origins) and a SOURCES table: the three failures of the test, and the strings that have two sources. */
function problems(strings, table, docs, calendar) {
  const rows = entries(table);
  const wrong = { missing: [], stale: [], unheld: [], twice: [], badFormat: [], badCalendar: [] };
  const kinds = new Map();
  for (const [text, kind] of rows) kinds.set(text, [...(kinds.get(text) ?? []), kind]);
  for (const [text, origins] of strings) if (!kinds.has(text)) wrong.missing.push(`${JSON.stringify(text)} (${origins.join(', ')})`);
  for (const [text, list] of kinds) {
    if (!strings.has(text)) wrong.stale.push(JSON.stringify(text));
    if (list.length > 1) wrong.twice.push(`${JSON.stringify(text)}: ${list.join(', ')}`);
  }
  for (const [text, kind, why] of rows) {
    if ((kind === 'ux' || kind === 'design') && !holds(docs[kind], text)) wrong.unheld.push(`${JSON.stringify(text)} is not in ${why}`);
    if (kind === 'format' && !isFormat(text)) wrong.badFormat.push(JSON.stringify(text));
    if (kind === 'calendar' && !calendar.includes(text)) wrong.badCalendar.push(JSON.stringify(text));
  }
  return wrong;
}

const CALENDAR = [...modules['chat/page-time.ts'].WHEN_TEXTS.weekdays, ...modules['chat/page-time.ts'].WHEN_TEXTS.months];

describe('the inventory', () => {
  it('holds the imported constants, the constants read from the source and the templates of every component', () => {
    assert.ok(imported.length > 150, `${imported.length} imported strings`);
    assert.ok(fromSource.length >= 12, `${fromSource.length} strings read from the source text`);
    for (const text of ['Skip to chat', 'Skip to status', 'System', 'Light', 'Dark', 'Theme: ', 'Online demo', 'Demo mode', 'Account', 'Close About OcuTalon']) {
      assert.ok(inventory.has(text), `the inventory holds ${JSON.stringify(text)}`);
    }
    for (const name of ['header/header.ts', 'main-page/main-page.ts', 'about/about-dialog.ts']) {
      assert.ok(fromTemplates.some(([origin]) => origin.startsWith(name)), `${name}'s template gives strings`);
    }
    assert.ok(inventory.has('Default model: {slot}.'), 'an interpolation inside a text node is a {slot}');
    assert.ok(inventory.has('Chat') && inventory.has('Status'), "main page's hidden headings");
  });

  it('imports every *_TEXTS constant of the page, so that a new text module joins the inventory', () => {
    const names = IMPORTED.flatMap(([, list]) => list);
    const exported = sources.flatMap((file) => [...file.code.matchAll(/export const ([A-Z][A-Z_]*_TEXTS)\b/g)].map((match) => [file.name, match[1]]));
    assert.ok(exported.length >= 9, `${exported.length} *_TEXTS constants`);
    assert.deepEqual(exported.filter(([, name]) => !names.includes(name)).map(([file, name]) => `${file} ${name}`), []);
  });
});

describe('the sources', () => {
  const wrong = problems(inventory, SOURCES, documents, CALENDAR);

  it('has an entry for every inventory string', () => {
    assert.deepEqual(wrong.missing, [], 'a string with no entry: give it its source in SOURCES (never an invented one)');
  });

  it('has no entry that matches no inventory string', () => {
    assert.deepEqual(wrong.stale, []);
  });

  it('gives each string one source', () => {
    assert.deepEqual(wrong.twice, []);
  });

  it('finds each ux and design string in its document', () => {
    assert.deepEqual(wrong.unheld, []);
  });

  it('names the UX first: no design, ac or ruled string without a slot is one that EXPERIENCE.md holds', () => {
    const second = entries(SOURCES).filter(([text, kind]) => ['design', 'ac', 'ruled'].includes(kind) && !/\{[A-Za-z]+\}/.test(text));
    assert.ok(second.length >= 9, `${second.length} strings with a source after the UX`);
    assert.deepEqual(second.filter(([text]) => holds(documents.ux, text)).map(([text, kind, why]) => `${JSON.stringify(text)} is in EXPERIENCE.md, not only ${kind} (${why})`), []);
  });

  it('holds every format string to punctuation, digits, the separator and unit words, and every calendar string to the names', () => {
    assert.deepEqual(wrong.badFormat, []);
    assert.deepEqual(wrong.badCalendar, []);
  });

  it('reports the three failures on a changed inventory, naming the string', () => {
    const extra = new Map(inventory).set('Hello there', ['a test template']);
    assert.deepEqual(problems(extra, SOURCES, documents, CALENDAR).missing.filter((one) => one.includes('Hello there')), ['"Hello there" (a test template)']);
    const fewer = new Map(inventory);
    fewer.delete('Retry');
    assert.deepEqual(problems(fewer, SOURCES, documents, CALENDAR).stale.filter((one) => one === '"Retry"'), ['"Retry"']);
    const moved = { ...SOURCES, ux: [...SOURCES.ux, 'A sentence that the UX never wrote.'] };
    const changed = new Map(inventory).set('A sentence that the UX never wrote.', ['a test constant']);
    assert.deepEqual(problems(changed, moved, documents, CALENDAR).unheld.filter((one) => one.includes('never wrote')), ['"A sentence that the UX never wrote." is not in EXPERIENCE.md']);
    assert.equal(holds('Working \u00b7 12 s', 'Working \u00b7 {n} s'), true);
    assert.equal(holds('Working \u00b7 s', 'Working \u00b7 {n} s'), false, 'a slot is a non-empty run');
  });
});

describe('the ellipsis and the characters', () => {
  const strings = [...inventory.keys()];

  it('never holds three dots', () => {
    assert.deepEqual(strings.filter((text) => text.includes('...')), []);
  });

  it('holds U+2026 once, from the UX, when a string holds it', () => {
    const marked = strings.filter((text) => text.includes('\u2026'));
    assert.ok(marked.length >= 4, `${marked.length} strings hold the ellipsis`);
    for (const text of marked) {
      assert.equal(text.split('\u2026').length - 1, 1, `${JSON.stringify(text)} holds U+2026 once`);
      assert.ok(SOURCES.ux.includes(text), `${JSON.stringify(text)} is a ux string`);
      assert.ok(holds(documents.ux, text), `${JSON.stringify(text)} appears with U+2026 in EXPERIENCE.md`);
    }
  });

  it('writes Deciding, Working and Reconnecting with the single ellipsis', () => {
    assert.equal(modules['chat/chat-view.ts'].CHAT_TEXTS.deciding, 'Deciding\u2026');
    assert.equal(modules['chat/chat-view.ts'].CHAT_TEXTS.working, 'Working\u2026');
    assert.equal(modules['msg/catalog.ts'].PAGE_TEXTS['banner.reconnecting'], 'Reconnecting\u2026 New messages may be delayed.');
  });

  it('holds no non-ASCII character but U+2026, U+00B7 and U+2197', () => {
    // U+2197 is UX-DR47's arrow of a link that opens a new tab, hidden from assistive technology (Story 4.7).
    for (const text of strings) {
      const stray = [...text].filter((char) => char.charCodeAt(0) > 127 && char !== '\u2026' && char !== '\u00b7' && char !== '\u2197');
      assert.deepEqual(stray, [], `${JSON.stringify(text)} holds only ASCII, U+2026, U+00B7 and U+2197`);
    }
    assert.ok(/^[\x00-\x7f]*$/.test(readFileSync(fileURLToPath(import.meta.url), 'utf8')), 'this test is written in ASCII, with escapes');
  });
});
