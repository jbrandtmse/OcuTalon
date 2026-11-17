// Pins the four approved Slack setup steps (Story 27.3 QA; UX-DR117, the Contest Planner's R12 ruling): they are in GUIDE.md under "## Slack" (the anchor the Settings page's "How to set
// it up" link opens) and in EXPERIENCE.md under "### Step 7: Slack", word for word, with nothing else in the GUIDE section, a step 1 that names the im:history and chat:write scopes (Story 27.2), and the same
// events path that Settings shows (SettingsOps SLACKPATH). The oracle is written out here; the GUIDE section differs from it only by the backticks around the URL.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const guide = readFileSync(join(root, 'GUIDE.md'), 'utf8').split('\n');
const experience = readFileSync(join(root, '_bmad-output', 'planning-artifacts', 'ux-designs', 'ux-OcuTalon-2026-10-16', 'EXPERIENCE.md'), 'utf8').split('\n');
const settingsOps = readFileSync(join(root, 'src', 'ocutalon', 'cls', 'OcuTalon', 'Core', 'SettingsOps.cls'), 'utf8');

const STEPS = [
  'Create a Slack app for your workspace at api.slack.com/apps. In App Home, turn on the Messages Tab and allow users to send messages from it. Give its bot the im:history and chat:write scopes, and install it to the workspace.',
  'Copy the bot token and the signing secret into .env as SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET, then restart OcuTalon.',
  "Under Event Subscriptions, set the request URL to https://<your public address>/ocutalon/hook/slack/events and subscribe the bot to the message.im event. OcuTalon answers Slack's check at once.",
  "As an admin, open Settings \u203A Channels \u203A Slack and link each person's Slack member ID to their OcuTalon user. Only linked members' direct messages to the bot reach OcuTalon.",
];

/** The lines after the heading line up to the next line that starts with `stop` (or the end), or [] when the heading is missing. */
function sectionAfter(lines, heading, stop) {
  const at = lines.indexOf(heading);
  if (at < 0) {
    return [];
  }
  const rest = lines.slice(at + 1);
  const end = rest.findIndex((line) => line.startsWith(stop));
  return end < 0 ? rest : rest.slice(0, end);
}

/** The numbered list items of the lines, as [number, text]. */
const numbered = (lines) => lines.map((line) => line.match(/^(\d+)\. (.*)$/)).filter(Boolean).map((match) => [match[1], match[2]]);

describe('GUIDE.md > Slack', () => {
  const section = sectionAfter(guide, '## Slack', '## ');

  it('is one section with the anchor slack, which the Settings page links to', () => {
    assert.equal(guide.filter((line) => line === '## Slack').length, 1, 'one "## Slack" heading');
    assert.ok(section.length > 0, 'and it has a body');
  });

  it('holds the four approved steps word for word, as a numbered list', () => {
    assert.deepEqual(
      numbered(section).map(([number]) => number),
      ['1', '2', '3', '4'],
    );
    assert.deepEqual(
      numbered(section).map(([, text]) => text.replaceAll('`', '')),
      STEPS,
    );
  });

  it('holds nothing else (the heading is gated: the four steps and no other sentence)', () => {
    assert.equal(section.filter((line) => line.trim() !== '').length, 4, 'four non-blank lines, all of them the steps');
    assert.equal(numbered(section).length, 4);
  });

  it('writes the request URL of step 3 in backticks, so that <your public address> renders', () => {
    assert.match(section.join('\n'), /request URL to `https:\/\/<your public address>\/ocutalon\/hook\/slack\/events` and/);
  });

  it('step 1 names the chat:write scope that a reply needs (Story 27.2), with im:history', () => {
    assert.match(numbered(section)[0][1], /Give its bot the im:history and chat:write scopes, and install it to the workspace\./);
  });
});

describe('EXPERIENCE.md > Later Steps > Step 7: Slack', () => {
  const section = sectionAfter(experience, '### Step 7: Slack', '#');

  it('is there once', () => {
    assert.equal(experience.filter((line) => line === '### Step 7: Slack').length, 1);
    assert.ok(section.length > 0);
  });

  it('holds the same four steps word for word, in order', () => {
    assert.deepEqual(
      numbered(section).map(([number]) => number),
      ['1', '2', '3', '4'],
    );
    assert.deepEqual(
      numbered(section).map(([, text]) => text),
      STEPS,
    );
  });

  it('step 1 names the chat:write scope that a reply needs (Story 27.2), with im:history', () => {
    assert.match(numbered(section)[0][1], /Give its bot the im:history and chat:write scopes, and install it to the workspace\./);
  });
});

describe('the events path of step 3', () => {
  it('is the path that Settings shows and that the hook serves (SettingsOps SLACKPATH)', () => {
    const path = settingsOps.match(/Parameter SLACKPATH = "([^"]+)"/)?.[1];
    assert.ok(path, 'SettingsOps declares SLACKPATH');
    const url = STEPS[2].match(/set the request URL to (https:\/\/.+?) and subscribe/)?.[1];
    assert.ok(url, 'step 3 names a request URL');
    assert.ok(url.endsWith(path), `the URL of step 3 (${url}) ends with ${path}`);
    for (const lines of [guide, experience]) {
      assert.ok(lines.some((line) => line.includes(`<your public address>${path}`)), 'and each document writes it the same');
    }
  });
});
