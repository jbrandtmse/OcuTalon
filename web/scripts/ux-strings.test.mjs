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
  ['chat/answer-sources-view.ts', ['ANSWER_SOURCES_TEXTS']],
  ['chat/decision-view.ts', ['DECISION_TEXTS']],
  ['rail/rail-view.ts', ['RAIL_TEXTS']],
  ['rail/telegram-card/telegram-card-view.ts', ['TELEGRAM_CARD_TEXTS']],
  ['rail/persona-card/persona-card-view.ts', ['PERSONA_TEXTS']],
  ['rail/heartbeat-card/heartbeat-card-view.ts', ['HEARTBEAT_TEXTS']],
  ['shared/trace-view.ts', ['TRACE_TEXTS']],
  ['banners/banner-view.ts', ['BANNER_TEXTS']],
  ['shared/layout-view.ts', ['LAYOUT_TEXTS']],
  ['shared/announce-queue.ts', ['NEW_UPDATES']],
  ['chat/page-time.ts', ['WHEN_TEXTS']],
  ['incidents/incident-view.ts', ['INCIDENT_TEXTS']],
  ['approvals/approval-view.ts', ['APPROVAL_TEXTS']],
  ['msg/catalog.ts', ['PAGE_TEXTS', 'MESSAGE_TEXTS']],
  ['shared/check-sentence.ts', ['CHECK_TEXTS']],
  ['guide/guide-view.ts', ['GUIDE_TEXTS']],
  ['feed/break-feed-view.ts', ['FEED_TEXTS']],
  ['devices/device-view.ts', ['DEVICE_TEXTS']],
  ['phone/phone-view.ts', ['PHONE_TEXTS']],
  ['mailbox/mailbox-view.ts', ['MAILBOX_TEXTS']],
  ['live/reset-schedule.ts', ['RESET_TEXTS']],
  ['header/sign-out-texts.ts', ['SIGN_OUT_TEXTS']],
  ['header/demo-view-texts.ts', ['DEMO_VIEW_TEXTS']],
  ['chat/try-it-view.ts', ['TRY_IT_TEXTS']],
  ['guide/more-to-try-view.ts', ['MORE_TO_TRY_TEXTS', 'MORE_TO_TRY_GROUPS']],
  ['settings/settings-view.ts', ['SETTINGS_TEXTS']],
  ['settings/email-view.ts', ['EMAIL_TEXTS']],
  ['documents/documents-view.ts', ['DOCUMENTS_TEXTS', 'REASON_TEXTS']],
  ['chat/files-view.ts', ['FILES_TEXTS']],
  ['documents/sample-runbook-view.ts', ['SAMPLE_RUNBOOK_TEXTS']],
  ['chat/noise-view.ts', ['NOISE_TEXTS']],
  ['rail/memory-card/memory-card-view.ts', ['MEMORY_TEXTS', 'ANSWER_WORDS']],
  ['usage/usage-view.ts', ['USAGE_TEXTS']],
  ['history/history-view.ts', ['HISTORY_TEXTS']],
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

// The Persona card's six presets (DW-709): the name and the description of each, read from the source as the theme labels are. The ids are
// not UX text, so PRESETS is not imported with the constants above.
const presets = [...codeOf('rail/persona-card/persona-card-view.ts').matchAll(new RegExp(`\\{ id: ${QUOTED}, name: ${QUOTED}, description: ${QUOTED} \\}`, 'g'))];
assert.equal(presets.length, 6, 'persona-card-view.ts: PRESETS has six entries');
for (const match of presets) {
  fromSource.push(['PRESETS name', match[3] ?? match[4]]);
  fromSource.push(['PRESETS description', match[5] ?? match[6]]);
}

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
    'History',
    'Decisions',
    'Incidents',
    'Outcome',
    'Date',
    'No decisions match these filters.',
    'Look back at past decisions',
    'On the History page, filter the Decisions tab by outcome, channel, date or fallback, and open a decision to read its reasons, with a link to its trace. The Incidents tab lists your incidents with their state and, once an incident has closed, its summary. If it reads "No decisions yet.", run the guide first.',
    'Open the History page',
    'Usage',
    'See tokens and cost',
    'On the Usage page, choose a range and group by day, agent, channel or model. The tokens and cost come from your chat turns and from the agents\' decisions on your messages, and each day shows its largest model request against the 100,000-token limit. If it reads "No model use in this period.", chat or run the guide first.',
    'Open the Usage page',
    'Agent',
    'Channel',
    'Tokens and cost',
    'No model use in this period.',
    'Webhook',
    'Email',
    'Heartbeat',
    'estimated',
    'No key set. Add {variable} to .env.',
    'Test',
    'None',
    'Output',
    'That file is {size}; the limit is 10 MB.',
    "I couldn't read that file: {reason}.",
    'Documents',
    'Add documents',
    'Add the sample runbook',
    'Sample runbook.md',
    'According to the runbook, what should I do when partner orders fail with a date error?',
    'Remove',
    'No documents yet. Add a runbook to get cited answers.',
    'Indexing\u2026',
    'Ready',
    "Couldn't read it: {reason}",
    "Remove '{name}'? Answers will stop citing it.",
    'Settings \u00b7 OcuTalon',
    'Settings',
    'Models',
    'Budgets',
    'Channels',
    'Daily digest',
    'Time zone',
    'Send my digest now',
    'The simulated phone',
    'Telegram on',
    'Webhooks',
    'Other systems can send OcuTalon any JSON event. Each webhook has its own secret, which the sender puts in the X-OcuTalon-Webhook-Secret header.',
    'Name',
    'Secret',
    'Create webhook',
    'Send events with POST to {address}.',
    'Saved, and never shown again. Type a new value to replace it.',
    'Webhooks are off on the online demo, so it has no public webhook address. They work on your own install.',
    'Send an event through a webhook',
    'In Settings, Channels, create a webhook with a name and a secret of at least 16 characters. Then send it any JSON with POST to the address it shows, with the secret in the X-OcuTalon-Webhook-Secret header. On the History page, filter by the channel Webhook to read OcuTalon\'s decision on the event, with a link to its trace.',
    'Open Channels settings',
    'Connect your mailbox. OcuTalon decides on each email that arrives after you connect it, and leaves your mail on the server.',
    'Your email address',
    'OcuTalon emails this address without asking.',
    'Incoming mail server (POP3)',
    'Outgoing mail server (SMTP)',
    'Sign-in method',
    'Google',
    'Microsoft 365',
    'Client ID',
    'Client secret',
    'Redirect address',
    'Add this address to your OAuth2 client at {provider} as an authorized redirect URI.',
    'Signed in with {provider}.',
    'Not signed in yet. Save, then sign in with {provider}.',
    'Sign in with {provider}',
    'Not set.',
    "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.",
    'Check thresholds',
    'Save changes',
    'Saved. Applies within a minute. Recorded in the audit log.',
    "Couldn't save. Nothing was changed.",
    'Only OcuTalon admins can open settings.',
    'On',
    'Off',
    'Pages',
    'Stay',
    'Message OcuTalon',
    'Demo view',
    'Off shows the page as it looks on your own install.',
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
    'Saved for the daily digest',
    'Got it',
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
    '$0',
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
    'Telegram paused',
    'Trying again at {time}',
    "Scan with your phone's camera, then tap Start in Telegram.",
    'Open in Telegram',
    '(opens Telegram)',
    'New code in {n} min',
    'QR code that opens OcuTalon in Telegram to pair this session',
    'Telegram paired \u00b7 {name}',
    'Telegram paired',
    'Unpair',
    'Unpair Telegram',
    'Telegram unpaired',
    'Trace',
    'Open in Visual Trace (shows sign-in help first)',
    'Sign in to Visual Trace',
    'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.',
    'Don\'t show this again',
    'Visual Trace',
    'Open my conversation in Visual Trace',
    'User name',
    'Password',
    'Copy Visual Trace user name',
    'Copy Visual Trace password',
    'Copied',
    'Couldn\'t copy. Select the text and copy it yourself.',
    'Status',
    '1 approval request',
    'This page is designed for a wider window. Everything still works.',
    '{n} new updates',
    'tomorrow at {time}',
    'I couldn\'t answer that: {fallbackReason}. Nothing was changed.',
    'Everything I checked passed.',
    'Everything else I checked passed.',
    'Not everything: {whatFailed}.',
    'I\'m not watching any productions yet, so I can\'t say. Ask me to watch one.',
    'You\'ve used this session\'s {limit} messages for the hour (messages you send in the chat or Telegram). You can send more at {time}.',
    'You\'ve simulated 20 emails this hour. You can send more at {time}.',
    'The online demo has used today\'s model allowance. Decisions use fixed rules until {time}.',
    'Can\'t reach OcuTalon. Retrying every 10 seconds.',
    'OcuTalon has reached today\'s cost limit of {cap}. Decisions use fixed rules until {time}.',
    'Background checks have paused: the heartbeat last ran at {time}. Watches and reminders may be late until it recovers.',
    'Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at {time}. Each OcuTalon needs its own bot.',
    'The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.',
    'Reconnecting\u2026 New messages may be delayed.',
    'The demo is busy right now. Try again in a few minutes, or install it yourself.',
    'Install it yourself',
    'How to set a key',
    'Set up a bot',
    'the model didn\'t answer within the time allowed',
    'the model\'s reply was empty',
    'the model\'s reply was cut off',
    'the model declined to answer',
    'the model returned an error',
    'the model was too busy to answer',
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
    'An AI assistant for InterSystems IRIS.',
    'An assistant that runs as an IRIS Interoperability production and decides, for everything that arrives, whether it deserves your attention.',
    'Default model: {slot}.',
    'README',
    'Built with the BMAD Method and Claude Code.',
    'OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.',
    'Ocu',
    'Talon',
    'About OcuTalon',
    'Sign out',
    'Signing out ends this demo session. Signing in again starts a fresh one.',
    'Cancel',
    'Theme',
    'Chat',
    'Retry',
    'The demo is resetting.',
    'It usually takes a few minutes. This page returns to the sign-in screen by itself.',
    'Resetting \u00b7 OcuTalon',
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
    'Use the same bridge in your own production',
    'More to try',
    'Other things to try',
    'Read the incident summary',
    'This closes the guide\'s resolved incident, as Dismiss on its card does. Look for the incident summary in the chat and on the Simulated phone: what happened and when, the cause and the evidence, each approval, the orders affected and the model cost. Later, ask "Show me the incident summary" to get it again.',
    'Close the incident',
    'Show me the incident summary',
    'Change how OcuTalon talks',
    'In the Persona card, choose Pirate, or Another language and then Spanish, and press Save. Then ask "Is anything wrong right now?" and look for the new style in the replies. The check results under them are written by OcuTalon\'s code, so they stay the same in any style.',
    'Go to the Persona card',
    'Send a suspicious email',
    'This sends "Sample: suspicious request" to the Simulated mailbox. The email asks OcuTalon to resend every failed order and approve pending requests. Look for its decision and the reasons under it: nothing is resent or approved.',
    'Send the suspicious email',
    'Reject a fix',
    'This presses Break the feed again. OcuTalon usually notices within a minute. When the fix waits for your approval, press Reject in the chat or on the Simulated phone, and look for "Nothing was changed."',
    'Break it again',
    'Reroute the failed orders',
    'First do "Reject a fix", so the failed orders are still waiting. This asks OcuTalon in the chat to reroute them to OrdersForReview, the review queue. The approval request shows a dry run: how many orders, one example, and where they go now and where they would go. Approve it, then read the result in the chat and press Trace to see the copies go to OrdersForReview while the originals stay unchanged. On your own install, suspend and resume work the same way.',
    'Ask to reroute',
    'Reroute the failed orders to OrdersForReview.',
    'Warn the partner',
    'This asks OcuTalon in the chat to warn the partner about an incident\'s delay, so it needs an incident that isn\'t closed: if you closed the guide\'s incident, do "Reject a fix" first. OcuTalon drafts a short notice from the incident\'s counts, times and cause, and it comes as an approval request that shows the exact text and the recipients, simulated contacts. Approve it, then open the Simulated mailbox to read the notice exactly as you approved it. Nothing goes to a real inbox.',
    'Ask for a partner warning',
    'Warn the partner about the delay.',
    'Watch queue backlogs',
    'This asks OcuTalon in the chat to watch the queue backlogs. Look for the Queue-backlog check under Background checks, with its schedule, last run and result. Every minute it reads the Orders production\'s queues, and when one holds more than 100 messages, or its oldest message has waited over 10 minutes, OcuTalon decides once whether to tell you. On a quiet demo it reads Passed. To stop, ask "Stop watching the queue backlogs."',
    'Ask to watch queues',
    'See the page as on your own install',
    'The demo guide, Break the feed and the Simulated devices are hidden, as on your own install. Turn Demo view back on in the top bar to return.',
    'Show the page without the demo',
    'Ask it to remember something',
    'This sends "Remember that the Results partner\'s contact is Lee." Later, ask "Who do I call about Results?" and look for the answer it remembered.',
    'Ask it to remember',
    'Pin a memory',
    'First do "Ask it to remember something". Then open All memories in the Memory card and press Pin on the memory marked Told. Open Pinned to see it: pinned facts are read at the start of each conversation, up to 1,000 tokens.',
    'Go to the Memory card',
    'Ask about a document',
    'On the Documents page, press Add the sample runbook, or add a short file of your own (nothing personal: Visual Trace on the demo is shared). When it reads Ready, ask in the chat "According to the runbook, what should I do when partner orders fail with a date error?", or ask about your own file, and look for the chip under the answer that names the document and its section.',
    'Open the Documents page',
    'See where an answer came from',
    'Under an answer from your documents, press the chip that names the document and section to read the passage, then Open document to see the whole file. Under an answer that recalls something you asked it to remember, press From memory to see what it remembered and when.',
    '{document} \u00a7 {section}',
    'Open document',
    'From memory',
    'Sources',
    'Close',
    'Run a heartbeat check-in',
    "In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in's outcome and its cost in the card.",
    'Go to the Heartbeat checklist card',
    "Remember that the Results partner's contact is Lee.",
    'Incidents and fixes',
    'Memory and documents',
    'Safety and settings',
    'Usage and history',
    'Run again',
    'Try it yourself',
    'Which productions are running?',
    'Is anything wrong right now?',
    'What was that failure earlier?',
    'What can you do?',
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
    'Persona',
    'Choose how OcuTalon words its chat replies and the reasons for its decisions. What OcuTalon may do, and what needs your approval, never changes.',
    'Change',
    'Save',
    'Language',
    'Name a language, such as Spanish or Portuguese (Brazil). Notices, cards and buttons stay in English.',
    'Your own words',
    '{n} of 1,000 characters',
    'OcuTalon suggested a change. It waits for your answer in Approval requests.',
    'Professional (default)',
    'Calm, short and plain.',
    'Starship computer',
    'Crisp status reports, formal and brief.',
    'Pirate',
    'Sailing words and a good-humoured tone; the facts stay exact.',
    'Kind friend',
    'Warm, patient and encouraging.',
    'Another language',
    'Replies and reasons in the language you name.',
    'Describe the tone, style and preferences you want.',
    'Change how OcuTalon talks to you',
    'Now: {old}',
    'Proposed: {new}',
    'Nothing changes unless you approve.',
    'On the online demo you can choose a preset or a language. Your choice lasts for this visit.',
    'Heartbeat checklist',
    'Off. Turn it on to have OcuTalon look at your list every 30 minutes.',
    'Every {interval}',
    'Every {interval}, {from} to {to}',
    'Next check-in {time}',
    'Last check-in {time}',
    'Stayed quiet',
    'Told you now',
    'Saved for the digest',
    'Offered an action',
    "Couldn't decide: {reason}",
    'Skipped at {time}:',
    'your checklist is empty.',
    'outside your active hours.',
    'nothing has changed since the last quiet check-in.',
    "today's cost limit has been reached.",
    'no model key is set.',
    'waiting after a failed check-in, until {time}.',
    'Today: {n} check-ins, {cost}',
    'Write what OcuTalon should look for, one item per line. With an empty list, OcuTalon makes no model call. It looks at most once per interval, and only when something has changed.',
    'Run the heartbeat now',
    'You can run it again at {time}.',
    "On the online demo the heartbeat is off until you turn it on, and each check-in counts toward the demo's daily cost cap.",
    'Edit',
    '30 minutes',
    '1 hour',
    '4 hours',
    '8 hours',
    '24 hours',
    'To',
    'Checklist',
    'Memory',
    'Notes',
    'Your answers',
    "Built by OcuTalon from today's decisions, incidents, approvals and reminders. No model writes these notes.",
    'Nothing recorded yet today.',
    'OcuTalon looks at these when it decides on similar items. Only your own answers are kept here.',
    'Forget',
    'Forget this answer? OcuTalon will stop using it.',
    'Today',
    'Yesterday',
    'This was noise',
    'Marked as noise at {time}. Similar items will take this into account.',
    // Story 41.13 (EXPERIENCE.md, the Memory card: the tabs, the Pinned line and its figure, the chips, the refused pin) and the stored answers' words (DW-998).
    'Pinned',
    'All memories',
    'Pinned facts are read at the start of each conversation.',
    '{used} of 1,000 tokens (estimated).',
    'Told',
    'Learned',
    'Pin',
    'Unpin',
    'That would go over the 1,000-token limit. Unpin something first.',
    'Approved',
    'Rejected',
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
    'Story 18.3 AC 2 (the two lines under the Test button, from "Answered in 1.2 s" (the fixture) and "Didn\'t answer: {plain reason}")': ['Answered in {seconds} s', "Didn't answer: {reason}"],
    'Story 18.3 AC 5 (the step 2 text of the no-model-key banner, ruled planner-2026-11-08-18.3; EXPERIENCE.md holds its tail after "From step 2:", so the full text sits here and not under ux)': [
      'OcuTalon has no model key, so every decision uses fixed rules. Add a key for a supported provider (for example, ANTHROPIC_API_KEY) to the .env file and restart OcuTalon.',
    ],
    'Story 40.4 (U-278: the two help sentences of the Language and Your own words fields)': [
      "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. In another language, the model is only told not to say so.",
      "OcuTalon deletes common English phrases that say all is well from the model's replies, so its own checks give the verdict. If this persona writes in another language, the model is only told not to say so.",
    ],
    'Story 41.15 AC 3 (the line under a reply that announces a learned save, the ruled catalog text memory.learnedSaved; it is in epics.md, not in EXPERIENCE.md)': ['I\'ll remember this: "{fact}". You can tell me to forget it.'],
    'Story 6.2: Approve or reject a fix from the web chat (the expiry caption "Expires {when}" and the busy notice of an unanswered press, which adds "The request is still waiting." to the busy and failure rule of EXPERIENCE.md)': [
      'Expires {when}',
      "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
    ],
    'Story 6.1: Show each incident as one card in the chat (the announcement "Incident: {headline}. No fix proposed." of a fallback or a cause with no fix)': ['Incident: {headline}. No fix proposed.'],
    'Story 2.6: Show every decision with its reasons and cost (the Details labels Tokens, Model, Agent steps, Duration, Decision message and Cost)': ['Agent steps', 'Decision message'],
    'Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear (the failing entry first, then "Everything else I checked passed." only if other checks passed)': ['Not everything: {whatFailed}. Everything else I checked passed.'],
    'Story 2.8: Show the status rail (the approval request row, "Raised 14:13 \u00b7 expires tomorrow at 14:13")': ['Raised {when}'],
    'Story 2.13: Open Visual Trace from the page (the optional "Open Visual Trace" button of the popover)': ['Open Visual Trace'],
    'Story 16.8: The page counts down to the reset (the reset countdown reads "Next reset {time} \u00b7 in {countdown}")': ['Next reset {time} \u00b7 in {countdown}'],
    'Story 33.3: Epic 33 burn-down (the Demo mode section\'s own confirmation, DW-699)': [
      'Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change.',
    ],
    'Story 34.2: Add and remove documents on a Documents page (the page title "Documents \u00b7 OcuTalon")': ['Documents \u00b7 OcuTalon'],
    'Story 37.2: See tokens and cost over time on the Usage page (the page title "Usage \u00b7 OcuTalon", epics.md)': ['Usage \u00b7 OcuTalon'],
    'Story 25.2: Filter past decisions and incidents on the History page (AC 1, UX-DR22: the page title "History \u00b7 OcuTalon")': ['History \u00b7 OcuTalon'],
    'Story 39.9: Heartbeat follow-up (the 60-minute schedule line "Every hour, \u2026" and "Every hour" all day; PUBLIC TEXT ruled by the Contest Planner 2026-11-06, relayed by the orchestrator)': ['Every hour', 'Every hour, {from} to {to}'],
  },
  ruled: {
    'Story 25.3 rulings at the spec gate 2026-11-12 (the Contest Planner under the owner\'s delegation, story-253-rulings-20261112.md: PUBLIC TEXT rows 1 to 9 approved verbatim; rows 2 and 3 sit under ux, because EXPERIENCE.md holds them)': [
      'Send a file',
      "it isn't a PDF, Word (.docx), JPEG or PNG file",
      'the file is empty',
      'Sending files is off on the online demo. It works on your own install.',
      'File not sent',
    ],
    'Story 25.2 rulings at the spec gate 2026-11-10 (the Contest Planner under the owner\'s delegation, spec gate of Story 25.2, relayed by the orchestrator: PUBLIC TEXT approved as proposed: the Any outcome and Any channel options, the three Fallback options, Clear filters, the Noticed and Closed times, the two no-summary lines, the pager texts and the names of the two pagers, the empty line of no incidents, and the error line; the tab names, the Outcome and Date labels, the two empty lines of decisions and the More to try item sit under ux, because EXPERIENCE.md holds them)': [
      'Any outcome',
      'Any channel',
      'All decisions',
      'Fallback only',
      'Without fallback',
      'Clear filters',
      'Noticed {time}',
      'Closed {time}',
      'No summary yet. OcuTalon writes one when the incident closes.',
      'No summary was written for this incident.',
      'Previous page',
      'Next page',
      'Page {page} of {pages}',
      'Decision pages',
      'Incident pages',
      'No incidents yet.',
      "Couldn't load your history.",
    ],
    'Story 37.2 rulings at the spec gate 2026-11-10 (the Contest Planner under the owner\'s delegation, prompts/epic-37-rulings-372.md: the Usage page\'s Range and Group by labels, the range options, the Day grouping, the Tokens and cost, Largest request per day and Largest request (estimated) headings, the largest-request cell, the error line, the agent name Chat summaries, the channel names Web chat and Slack, and the includes estimates marker; the More to try item\'s label, look-for and control sit under ux, because EXPERIENCE.md holds them)': [
      'Range',
      'Last 7 days',
      'Last 30 days',
      'Group by',
      'Day',
      'Largest request per day',
      'Largest request (estimated)',
      '{tokens} of {limit} tokens',
      "Couldn't load your usage.",
      'Chat summaries',
      'Web chat',
      'Slack',
      'includes estimates',
    ],
    'Story 23.2 ruling (the Contest Planner under the owner\'s delegation, 2026-11-09, relayed by the orchestrator: Public Text, Web (Lane B): the titles of the suspend, resume and reroute requests, the incident card\'s fix and fixing sentences for them, the dry run rows of the approval card, and the refusal text of an item kind)': [
      'Suspend {item}',
      'Resume {item}',
      'Reroute {n} {noun} to {to}',
      'Suspending {item}\u2026',
      'Resuming {item}\u2026',
      'Rerouting {count} {noun}\u2026',
      'I can suspend {item}.',
      'I can resume {item}.',
      'I can reroute {count} {noun} to {to}.',
      '{item}: {state}',
      'Message {example}: {from}',
      'Message {example}: {to}',
      '{count} copies to {to}; the originals stay unchanged.',
      '1 copy to {to}; the original stays unchanged.',
      'Only an approver for fixes can answer this request.',
    ],
    'Story 23.5 ruling (the Contest Planner under the owner\'s delegation, 2026-11-09, relayed by the orchestrator: Public Text, Web (Lane B): the title of the partner delay notice request, its To line and note, and its result bands; each names the Simulated mailbox or the draft, and none says that an email was sent)': [
      'Send a delay notice',
      'To: {recipients}',
      'Nothing is sent unless you approve. It goes to the Simulated mailbox, not to a real inbox.',
      'Sent to the Simulated mailbox.',
      'Sent to the Simulated mailbox for {completed} of {total} contacts.',
      "Approved and kept as a draft: email delivery isn't set up yet.",
      'Not sent: {reason}.',
    ],
    'Story 18.4 ruling planner-2026-11-08-18.4 (the Contest Planner under the owner\'s delegation, 2026-11-08, relayed by the orchestrator: the digest card\'s disclosure "What I checked ({n})", the line "Marked as handled at {time}", which the catalog gives (the Got it button is the UX\'s and sits under ux); "Saved for the daily digest" is the UX\'s and sits under ux)': [
      'What I checked ({n})',
      'Marked as handled at {time}',
    ],
    'Story 18.3 ruling planner-2026-11-08-18.3 (the Contest Planner under the owner\'s delegation, 2026-11-08, relayed by the orchestrator: the Models and Budgets labels and help lines, the agent and provider names, the Test help and failure texts, and the price labels)': [
      'Triage agent',
      'Diagnosis agent',
      'Chat agent',
      'Provider',
      'Second model',
      'Anthropic',
      "A change applies from the agent's next model request.",
      "Used once when this agent's reply can't be used.",
      "Test sends one short request to the agent's saved model.",
      "Couldn't run the test. Try again.",
      'Prices',
      'US dollars per million tokens. New prices apply to later model requests; earlier costs stay as they were.',
      'Token budget per decision',
      'A decision that would use more tokens than this uses fixed rules instead. 0 is off.',
      'Daily cost cap (US dollars)',
      "When today's model cost reaches the cap, decisions use fixed rules until midnight in the instance's time zone. 0 is off.",
    ],
    'Story 39.5 ruling planner-2026-11-06-39.5 (the Contest Planner under the owner\'s delegation, 2026-11-06, relayed by the orchestrator: the Heartbeat card\'s Today singular, the labels of its Edit form, the interval names, and 39.2\'s two ruled unavailable reasons of DW-634; the skip line\'s cap fragment is the UX\'s since the same ruling amended EXPERIENCE.md; the labels To and Checklist and the names 4 hours and 8 hours of the same ruling sit under ux, because EXPERIENCE.md holds those words incidentally and this test names the UX first)': [
      'Today: 1 check-in, {cost}',
      'Interval',
      'Active hours',
      'All day',
      '2 hours',
      "Today's cost limit has been reached.",
      'No model key is set.',
    ],
    'Story 33.2 ruling U-269 (T1 to T8: the unsaved prompt and its Leave button, the denied view\'s link back to the chat, the five threshold labels, T7 the UX\'s Demo mode sentence without its FR reference, and the name of the settings navigation; T2\'s Stay, T6\'s On and Off, T8\'s Pages and T10\'s two API messages are sentences or words that the UX holds, and sit under ux)': [
      'Settings sections',
      'Back to the chat',
      'You have unsaved changes in this section. Leave without saving?',
      'Leave without saving',
      'Disk free space below (%)',
      'Journal free space below (%)',
      'License use above (%)',
      'Queue backlog above (messages)',
      'Oldest queued message waiting over (minutes)',
      'Demo mode adds the demo guide, Break the feed, and the simulated devices.',
    ],
    'Story 33.2 ruling U-270 (T9, the Demo mode field message when the Demo step failed after the value was written: the value stands, so the text never says that nothing was changed)': [
      "Demo mode is set to {v}, but the switch didn't finish. OcuTalon tries again at its next start.",
    ],
    'Story 18.2 ruling planner-2026-11-08-18.2 (the Contest Planner under the owner\'s delegation, 2026-11-08, relayed by the orchestrator: the Time zone help text (reworded by the ruling) and its Server default choice, the Daily digest labels Send at and Send to, its help line, the web chat and simulated phone channel names, the send-now confirmation and failure, and the Channels section\'s Telegram on)': [
      "Message times, reminders, the daily digest and the current time that OcuTalon gives the model use this zone. Times on this page stay in your browser's zone.",
      'Server default',
      'Send at',
      "In the instance's time zone. Applies from the next digest.",
      'Send to',
      'The web chat',
      'Sending your digest now.',
      "Couldn't send your digest. Try again.",
    ],
    'Story 12.10 veto item (U-244, orchestrator veto: the hint of the Telegram row in the drawer band, which names the header\'s Status button; EXPERIENCE.md gives only the line for the other bands)': [
      'Optional: press {status} at the top of the page, then scan the QR code in the Telegram card to get the notice on your own phone.',
    ],
    'Story 12.9 (DW-501, DW-506; the chat-only forms of the allowance and reset-soon banners, shown while Telegram is not on: EXPERIENCE.md:174 gives the allowance form with its slots, and the Contest Planner kept both texts as U-227)': [
      "You've used this session's {limit} messages for the hour. You can send more at {time}.",
      'The demo resets in 5 minutes. Your session will be cleared.',
    ],
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
    'Story 31.3 (the About links, EXPERIENCE.md About, item 5: README, the bridge developer guide and the security overview; FR-61)': ['Bridge developer guide', 'Security overview'],
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
    'Story 30.5 ruling U-182 (AD-16 as amended: the text of result.stoppedPartway, a resend that stops at the first copy that errs; the page renders the catalog\'s text)': [
      "The resend stopped partway: I resent {resent} of the {count} {itemNoun} ({completed} went through), the next one couldn't be resent, and {notTried} more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
    ],
    'Story 23.7 ruling (Contest Planner, Public Text 2026-11-11, the queue-backlog check: the rail\'s schedule line of its row and the prompt that the More to try item sends; the item\'s label, look-for and control sit under ux, because EXPERIENCE.md holds them)': [
      'A check every minute',
      'Watch the queue backlogs.',
    ],
    'Story 23.2 ruling (Contest Planner, Public Text 2026-11-09, texts of the result.item* and result.rerouted catalog keys, result.itemSuspended as re-ruled on 2026-11-10 for DW-1068; its DW-1067 ruling of 2026-11-10 has the request card show them in its result band, rendered from the catalog)': [
      "{item} in {production} is suspended: it is disabled now. To undo it while this incident is open, ask me to resume {item}. After the incident closes, enable {item} again on the production's configuration page in the Management Portal.",
      '{item} in {production} is enabled again.',
      '{item} was not changed: {reason}. It needs a new approval.',
      'Nothing was changed: {reason}.',
      'All {count} {itemNoun} were rerouted to {to} and completed there. The originals stay unchanged.',
    ],
    'Story 7.8 (U-249: the either-way sentence of the dry run, which the notice carries since Story 7.7; the page renders the catalog\'s text, cut by the generator from the two entries that hold it)': [
      'All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived.',
    ],
    'Story 34.2 rulings at the spec gate (DW-722, U-284; the lead, 2026-11-05: the reason texts of "Couldn\'t read it: {reason}" with the size ruling of U-285 #864, the Remove button and its accessible name, and the failure notice of the Remove dialog)': [
      'Remove {name}',
      "Couldn't remove it. Nothing was changed.",
      "it isn't a Markdown, plain-text, PDF or Word (.docx) file.",
      'that file is {size}; the limit is 10 MB.',
      'the file is empty.',
      'OcuTalon found no text in it.',
      "this part of OcuTalon isn't built yet.",
      'something went wrong inside OcuTalon.',
    ],
    'Story 19.7 ruling at the spec gate 2026-11-08 (Q1 (a), U-177 grant: the Planner\'s A1 reasons of Story 19.6 for the extraction codes, with the catalog\'s final period, each shown in "Couldn\'t read it: {reason}")': [
      'its text is too long to read.',
      "it's protected with a password.",
      "it's damaged or incomplete.",
      'it has no text to read, for example a scanned PDF without a text layer.',
      "it's an old Word file (.doc); save it as .docx and try again.",
      'reading it took too long.',
    ],
    'Story 41.6 ruling at the spec gate 2026-11-08 (the Contest Planner under the owner\'s delegation, relayed by the orchestrator: the PUBLIC TEXT list of the Memory card, all approved as written)': [
      'Nothing recorded yesterday.',
      'No answers yet.',
      'Forget {summary}',
      "Couldn't forget it. Nothing was changed.",
      'OcuTalon keeps this answer but does not use it when it decides.',
    ],
    'Story 41.13 ruling planner-2026-11-09-41.13 (the Contest Planner under the owner\'s delegation, relayed by the orchestrator: the PUBLIC TEXT list of the Memory card\'s Pinned and All memories tabs, with the two empty texts, the More to try item and the demo rule line; the Search is busy text is Story 41.9\'s ruling)': [
      'Nothing pinned yet. Pin a memory from All memories.',
      'No memories yet. Say "Remember that ..." in the chat.',
      'No memories match.',
      'Search your memories',
      'Search',
      'Showing the newest {shown} of {total}. Search to find the others.',
      'Forget this memory? OcuTalon will stop using it.',
      "Couldn't pin it. Nothing was changed.",
      "Couldn't unpin it. Nothing was changed.",
      'Search is busy right now. Try again in a moment.',
      "On the online demo, your memories and pins belong to this visit: they're deleted when you sign out or the demo resets. Each search counts as one of your messages.",
    ],
    'Story 20.2 ruling planner-2026-11-09-20.2 (the Contest Planner under the owner\'s delegation, 2026-11-09, relayed by the orchestrator: the accessible name of a citation chip without the section sign (text 1a), the memory chip\'s accessible name and the popover\'s "Saved {when}", and the Documents page\'s line for a document that cannot be opened)': [
      '{document}, section {section}',
      'From memory: {memory}',
      'Saved {when}',
      "Couldn't open that document. It may have been removed.",
    ],
    'Story 20.3 ruling planner-2026-11-09-20.3 (the Contest Planner under the owner\'s delegation, 2026-11-09: the text of the sample runbook that ships with the web app, public text 3)': [
      `# Sample runbook: the demo's Orders feed

This sample comes with OcuTalon's web app. It covers the Orders production that the demo runs in namespace OCUORDERS, where a simulated partner sends orders.

## How orders flow

The partner's orders arrive at PartnerOrdersIn. OrdersFromPartner turns each order into a warehouse order, and OrdersToWarehouse takes the orders that pass. Each order has a number such as PO-0001, an item and a quantity.

## When orders fail with a date error

OrdersFromPartner accepts an order date written YYYY-MM-DD and nothing else. When the partner sends dates in another format, such as MM/DD/YYYY, each of those orders fails with "The order date was not in the expected format." Break the feed plays this out with 50 orders.

1. Read the error of one failed order to see the format the partner sent.
2. Rewrite each failed order's date as YYYY-MM-DD and resend it.
3. Check how many orders went through to OrdersToWarehouse.

Then ask the partner to go back to YYYY-MM-DD, so that the next batch does not fail.

## When the Results partner changes its certificate

The Results partner gives notice before the TLS certificate on its results endpoint changes. Load the new certificate before the change, so that results keep flowing.
`,
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
    '{entry} ({detail})',
    '{finding}, at {time}',
    'at {time}',
    '; ',
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

  it('never holds three dots, but in the one text that the Contest Planner ruled with the user\'s own words in straight quotes', () => {
    // Story 41.13 (planner-2026-11-09-41.13): the Memory card's empty text quotes the phrase to type, "Remember that ...", as the other look-for lines quote theirs.
    assert.deepEqual(strings.filter((text) => text.includes('...')), ['No memories yet. Say "Remember that ..." in the chat.']);
  });

  it('holds U+2026 once, from the UX, when a string holds it', () => {
    const marked = strings.filter((text) => text.includes('\u2026'));
    assert.ok(marked.length >= 4, `${marked.length} strings hold the ellipsis`);
    const ruledEllipsis = entries(SOURCES).filter(([, kind, why]) => kind === 'ruled' && why.startsWith('Story 23.2 ruling')).map(([text]) => text);
    for (const text of marked) {
      assert.equal(text.split('\u2026').length - 1, 1, `${JSON.stringify(text)} holds U+2026 once`);
      if (ruledEllipsis.includes(text)) {
        continue;
      }
      assert.ok(SOURCES.ux.includes(text), `${JSON.stringify(text)} is a ux string`);
      assert.ok(holds(documents.ux, text), `${JSON.stringify(text)} appears with U+2026 in EXPERIENCE.md`);
    }
  });

  it('writes Deciding, Working and Reconnecting with the single ellipsis', () => {
    assert.equal(modules['chat/chat-view.ts'].CHAT_TEXTS.deciding, 'Deciding\u2026');
    assert.equal(modules['chat/chat-view.ts'].CHAT_TEXTS.working, 'Working\u2026');
    assert.equal(modules['msg/catalog.ts'].PAGE_TEXTS['banner.reconnecting'], 'Reconnecting\u2026 New messages may be delayed.');
  });

  it('holds no non-ASCII character but U+2026, U+00B7, U+2197 and U+00A7', () => {
    // U+2197 is UX-DR47's arrow of a link that opens a new tab, hidden from assistive technology (Story 4.7). U+00A7 is the section sign of a
    // citation chip's label, "{document} \u00a7 {section}" (DESIGN.md citation-chip, Story 20.2).
    for (const text of strings) {
      const stray = [...text].filter((char) => char.charCodeAt(0) > 127 && char !== '\u2026' && char !== '\u00b7' && char !== '\u2197' && char !== '\u00a7');
      assert.deepEqual(stray, [], `${JSON.stringify(text)} holds only ASCII, U+2026, U+00B7, U+2197 and U+00A7`);
    }
    assert.ok(/^[\x00-\x7f]*$/.test(readFileSync(fileURLToPath(import.meta.url), 'utf8')), 'this test is written in ASCII, with escapes');
  });
});
