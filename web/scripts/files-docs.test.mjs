// Tests that the written rows of Story 25.3 are in the architecture spine, once each (AD-33): the Tables paragraph's SentFile sentence, the cross-area rows
// (the file-store call, the read-path probe and the paperclip and drop), the REST rows (the state row naming filesReadable, and the files route naming exactly
// the route that OcuTalon.Web.Files' URL map serves), the Conventions REST code bad_file, and the amendments of AD-4 (the sign-out list), AD-22 (the mock's
// getFile and download path) and AD-27 (the Web area's purge). No GUIDE.md or README line belongs to this story (the Planner's ruling 5).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const SPINE = readFileSync(join(root, '_bmad-output', 'planning-artifacts', 'architecture', 'architecture-OcuTalon-2026-10-16', 'ARCHITECTURE-SPINE.md'), 'utf8');
const FILES_CLASS = readFileSync(join(root, 'src', 'ocutalon', 'cls', 'OcuTalon', 'Web', 'Files.cls'), 'utf8');
const STORY = /\[(?:ADDED|AMENDED) \d{4}-\d{2}-\d{2}, Story 25\.3\]/;

/** The spine's lines that start with the text. */
const rows = (start) => SPINE.split('\n').filter((line) => line.startsWith(start));

describe('the spine rows of Story 25.3', () => {
  it('has the SentFile sentence once, at the end of the Tables paragraph, with the table\'s whole contract', () => {
    const lines = SPINE.split('\n').filter((line) => line.includes('From step 6 Lane B owns `SentFile`'));
    assert.equal(lines.length, 1);
    assert.ok(lines[0].includes('From step 4 Lane B also owns `MailSeen`'), 'in the paragraph that holds the earlier tables');
    assert.ok(lines[0].trimEnd().endsWith('[ADDED 2026-11-12, Story 25.3]'), 'and it ends the paragraph');
    for (const part of ['`Ref`, `SessionRef`, `Channel`, `Name`, `MediaType`, `Size`', '`Core.Files.Store`', '`Ownership.SentFile`', '`SentFile.DropSession`', 'no route serves its bytes']) {
      assert.ok(lines[0].includes(part), part);
    }
  });

  it('has the three cross-area rows once each, owned by Lane B', () => {
    for (const start of ['| `OcuTalon.Core.Files`: `Store(', '| The read-path probe: `OcuTalon.Core.Files.Readable()`', "| The composer's paperclip button and the chat's file drop"]) {
      const found = rows(start);
      assert.equal(found.length, 1, start);
      assert.match(found[0], STORY, start);
    }
    assert.ok(rows('| `OcuTalon.Core.Files`: `Store(')[0].endsWith('| B | Story 25.3 |'));
    assert.ok(rows('| The read-path probe')[0].includes('`READSFILES`'), 'the probe names the parameter that Story 26.2 adds');
  });

  it('has the state row, naming filesReadable right after demoMode', () => {
    const found = rows('| `GET /api/v1/state` from step 6 |');
    assert.equal(found.length, 1);
    assert.ok(found[0].includes('`filesReadable`') && found[0].includes('right after `demoMode`'));
    assert.match(found[0], STORY);
  });

  it('has the files REST row once, naming exactly the route that Web.Files serves', () => {
    const found = rows('| `POST /api/v1/files`');
    assert.equal(found.length, 1);
    const map = /XData UrlMap[\s\S]*?<Routes>([\s\S]*?)<\/Routes>/.exec(FILES_CLASS)[1];
    const routes = [...map.matchAll(/<Route Url="([^"]*)" Method="([A-Z]+)"/g)].map((one) => `${one[2]} /api/v1/files${one[1]}`);
    assert.deepEqual(routes, ['POST /api/v1/files'], 'Web.Files serves one route');
    assert.ok(found[0].startsWith(`| \`${routes[0]}\``), 'the row names it');
    for (const part of ['`OcuTalon.Web.Files`', '400 `bad_file`', '413 `body_too_large` over 13,985,112 bytes', '409 `not_available`', '404 `not_found`']) {
      assert.ok(found[0].includes(part), part);
    }
    assert.match(found[0], STORY);
  });

  it('adds bad_file to the Conventions REST codes', () => {
    const line = rows('| REST | `/ocutalon/api/v1/...`')[0];
    assert.ok(line.includes('`bad_file` (`POST /files`, with `reason` `too_large`, `empty` or `wrong_type`) [ADDED 2026-11-12, Story 25.3]'));
  });

  it('amends AD-4, AD-22 and AD-27', () => {
    assert.ok(SPINE.includes("from step 6 the session's sent files (`OcuTalon.Data.SentFile.DropSession`) [AMENDED 2026-11-12, Story 25.3]"));
    assert.ok(SPINE.includes('`getFile` and the file-download path (`/file/bot<token>/...`, the token logged by length there too) serve fixture files registered through the control endpoint (Story 25.3), for Story 26.2.'));
    assert.ok(!SPINE.includes('`getFile` and the file-download path arrive in Story 25.3'));
    assert.ok(SPINE.includes('and `SentFile` rows older than the task\'s days. [AMENDED 2026-11-05, Story 34.3] [AMENDED 2026-11-12, Story 25.3]'));
  });
});
