// Tests of the viewer's read-only page (Story 25.4; viewer-view.ts): isViewer is true only for `viewer: true`, the text is the ruled one and equals the server's
// MESSAGEREADONLY, every component that mounts a control that changes state imports isViewer and calls it on the live snapshot, the Memory card and the other personal rail
// cards are not mounted for a viewer (so the page never calls the two memory reads that a viewer is refused), and the settings link of the header needs `admin`, which is
// false for a viewer.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const appDir = join(here, '..', 'src', 'app');
const { isViewer, VIEWER_TEXTS } = await import(pathToFileURL(join(appDir, 'shared', 'viewer-view.ts')).href);
const files = sourceFiles(appDir, ['.ts']);
const code = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found.code;
};
const api = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Web', 'Api.cls'), 'utf8');

/** The components that mount or render a control that changes state, each guarded by the viewer's flag. */
const GUARDED = [
  'chat/chat-panel.ts',
  'chat/chat-files.ts',
  'approvals/approval-request-card.ts',
  'phone/phone-request.ts',
  'incidents/incident-dismiss.ts',
  'feed/break-feed-box.ts',
  'guide/demo-guide.ts',
  'chat/try-it-row.ts',
  'guide/more-to-try.ts',
  'chat/got-it.ts',
  'chat/noise-control.ts',
  'rail/status-rail.ts',
  'documents/documents-page.ts',
  'mailbox/simulated-mailbox.ts',
];

describe('isViewer', () => {
  it('is true only for viewer: true', () => {
    assert.equal(isViewer({ viewer: true }), true);
    for (const snapshot of [{ viewer: false }, {}, undefined, null, { viewer: 1 }, { viewer: 'true' }, { viewer: undefined }]) {
      assert.equal(isViewer(snapshot), false, JSON.stringify(snapshot));
    }
  });
});

describe('the viewer line', () => {
  it('is the ruled text, equal to the server\'s refusal text', () => {
    assert.equal(VIEWER_TEXTS.line, 'You have the viewer role, so you can look but not change anything.');
    const match = api.match(/Parameter MESSAGEREADONLY = "([^"]*)";/);
    assert.ok(match, 'Web.Api has MESSAGEREADONLY');
    assert.equal(match[1], VIEWER_TEXTS.line);
  });
});

describe('the guards', () => {
  for (const name of GUARDED) {
    it(`${name} imports isViewer and asks the live snapshot`, () => {
      const source = code(name);
      assert.match(source, /import \{[^}]*\bisViewer\b[^}]*\} from '[./]*\/shared\/viewer-view'/, `${name} imports isViewer`);
      assert.match(source, /isViewer\(this\.live\.snapshot\(\)\)|isViewer\(snapshot\)/, `${name} calls it on the snapshot`);
    });
  }

  it('the chat panel puts the viewer line in the composer\'s place, and the composer shows only otherwise', () => {
    const source = code('chat/chat-panel.ts');
    assert.match(source, /@if \(viewer\(\)\) \{\s*<p class="viewer-line"[^>]*>\{\{ viewerLine \}\}<\/p>\s*\} @else \{\s*<app-composer \/>\s*\}/);
  });

  it('the chat takes no file drop and shows no paperclip for a viewer', () => {
    assert.match(code('chat/chat-files.ts'), /isViewer\(snapshot\) \? \{ paperclip: false, drop: 'none' as const \}/);
  });

  it('Approve and Reject show only for a request that is pending and a user who is no viewer', () => {
    assert.match(code('approvals/approval-request-card.ts'), /@if \(view\(\)\.pending && !viewer\(\)\)/);
  });

  it('the simulated phone shows no Approve or Reject for a viewer', () => {
    assert.match(code('phone/phone-request.ts'), /@if \(view\(\)\.buttons && !viewer\(\)\)/);
  });

  it('Dismiss, Break the feed, Run again, the guide\'s Send and markers, the chips and the more-to-try buttons need no viewer', () => {
    assert.match(code('incidents/incident-dismiss.ts'), /@if \(!viewer\(\)\) \{\s*<app-server-button/);
    assert.match(code('feed/break-feed-box.ts'), /template: `\s*@if \(!viewer\(\)\) \{/);
    const guide = code('guide/demo-guide.ts');
    assert.match(guide, /@if \(!viewer\(\)\) \{\s*<app-server-button class="run-again"/);
    assert.match(guide, /protected mark\(marker: GuideMarker\): void \{\s*if \(this\.viewer\(\)\) \{\s*return;/);
    assert.match(code('chat/try-it-row.ts'), /@if \(demoView\.on\(\) && !viewer\(\)\)/);
    assert.match(code('guide/more-to-try.ts'), /\} @else if \(!viewer\(\)\) \{\s*<button/);
    assert.match(code('chat/got-it.ts'), /@if \(!viewer\(\)\) \{\s*<app-server-button/);
    assert.match(code('chat/noise-control.ts'), /\} @else if \(!viewer\(\)\) \{\s*<app-server-button/);
  });

  it('the documents page and the mailbox show no add, sample, remove or simulate for a viewer', () => {
    const documents = code('documents/documents-page.ts');
    assert.match(documents, /@if \(!viewer\(\)\) \{\s*<div class="bar">/);
    assert.match(documents, /@if \(row\.removable && !viewer\(\)\)/);
    assert.match(documents, /protected async addFiles\(files: readonly File\[\]\): Promise<void> \{\s*if \(this\.viewer\(\)\) \{\s*return;/);
    assert.match(code('mailbox/simulated-mailbox.ts'), /@if \(!viewer\(\)\) \{\s*<div class="chips">/);
  });

  it('the rail leaves out the Telegram, persona, heartbeat and memory cards for a viewer, so the page calls neither memory read', () => {
    const rail = code('rail/status-rail.ts');
    assert.match(rail, /PERSONAL_SECTIONS: readonly SectionId\[\] = \['telegram', 'persona', 'heartbeat', 'memory'\]/);
    assert.match(rail, /isViewer\(this\.live\.snapshot\(\)\) \? this\.view\(\)\.sections\.filter\(\(section\) => !PERSONAL_SECTIONS\.includes\(section\.id\)\)/);
    assert.match(rail, /@for \(section of sections\(\); track section\.id\)/);
    assert.doesNotMatch(rail, /@for \(section of view\(\)\.sections/);
  });
});

describe('the Settings link and the snapshot', () => {
  it('the header shows the link for `admin`, which the server reads false for a viewer', () => {
    assert.match(code('header/header-nav.ts'), /admin/);
    assert.match(api, /Do body\.%Set\("admin", \.\.IsAdmin\(\) && 'readOnly, "boolean"\)/);
  });

  it('StateSnapshot has viewer and rolesAssignable right after filesReadable', () => {
    assert.match(code('api/api-types.ts'), /filesReadable: boolean;[\s\S]*?viewer: boolean;[\s\S]*?rolesAssignable: boolean;\s*models:/);
  });
});
