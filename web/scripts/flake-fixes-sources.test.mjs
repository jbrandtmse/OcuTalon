// Pins the test-side fixes of Story 32.7 (DW-211, DW-639, DW-774's page.close, DW-973) by reading their sources, because the stack proofs
// run on a throwaway: each fix keeps the line that the flake needed changed.
// - Test.Agent.Runners AssertRefused settles on no Starting or Alive Ens.Job row of the item and an idle Ens.ScheduleHandler, twice in a row;
// - Test.Schedule.Heartbeat reads the production through RunnerFixture.NotRunningNow, in Restore and in TestAfterAllTestsNothingSaved;
// - leave.spec.ts closes a page only after it has left for the splash;
// - Test.Docs.ExtractMore TestTimeLeft takes the split from the holder's end node and bounds the part after the release at 20 s.
// Run with: node --test web/scripts/flake-fixes-sources.test.mjs
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { clsMethod as method, readRepo as read } from './repo-sources.mjs';

describe('DW-211: AssertRefused waits for the second refused start to end', () => {
  const body = method(read('src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls'), 'AssertRefused');
  const settled = body.split('\n').find((line) => line.includes('Set settled = '));

  it('settles on the row, no Starting or Alive Ens.Job row of the item, no alive job, the check and an idle Ens.ScheduleHandler', () => {
    assert.ok(settled, 'a settled line');
    assert.match(body, /\(result\.Get\("State"\) = "Starting"\) \|\| \(result\.Get\("State"\) = "Alive"\)/);
    assert.match(settled, /found && 'starting && '\$ListLength\(##class\(OcuTalon\.Test\.Agent\.RunnerFixture\)\.Jobs\(item\)\)/);
    assert.match(settled, /NotRunning\(\) \[ item\)/);
    assert.match(settled, /RunnerFixture\)\.Idle\("Ens\.ScheduleHandler", 0\)/);
  });

  it('ends the poll on the second settled poll in a row, or at the deadline, and keeps WAITSECONDS', () => {
    assert.match(body, /Set steady = \$Select\(settled: steady \+ 1, 1: 0\)/);
    assert.match(body, /If \(steady > 1\) \|\| \(\$ZHorolog > deadline\) Quit/);
    assert.match(body, /Set deadline = \$ZHorolog \+ \.\.#WAITSECONDS/);
  });

  it('names the state of the item in the two messages, and keeps the assertions', () => {
    assert.match(body, /\$\$\$AssertEquals\(\$ListLength\(##class\(OcuTalon\.Test\.Agent\.RunnerFixture\)\.Jobs\(item\)\), 0, item_" has no alive job: "_##class\(OcuTalon\.Test\.Agent\.RunnerFixture\)\.StateOf\(item\)\)/);
    assert.match(body, /\$\$\$AssertTrue\(##class\(OcuTalon\.Install\.Step\.Production\)\.NotRunning\(\) \[ item, "and the Production step's check names it as not running: "_##class\(OcuTalon\.Test\.Agent\.RunnerFixture\)\.StateOf\(item\)\)/);
    assert.match(read('src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls'), /^Parameter WAITSECONDS = 120;$/m);
  });
});

describe('DW-639: the Heartbeat tests read the production as the fixture does', () => {
  const source = read('src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls');

  it('reads NotRunningNow in Restore and in TestAfterAllTestsNothingSaved, and the product NotRunning nowhere in them', () => {
    for (const name of ['Restore', 'TestAfterAllTestsNothingSaved']) {
      const body = method(source, name);
      assert.match(body, /Set missing = \$ClassMethod\(\.\.#FIXTURE, "NotRunningNow"\)/, name);
      assert.doesNotMatch(body, /Production\)\.NotRunning\(\)/, name);
    }
  });

  it('keeps the message that names the items and their state', () => {
    assert.match(method(source, 'TestAfterAllTestsNothingSaved'), /\$\$\$AssertEquals\(missing, "", "and the production runs every item"_\$Select\(missing = "": "", 1: ": "_missing_" \("_\$ClassMethod\(\.\.#FIXTURE, "StateOf", missing\)_"\)"\)\)/);
  });
});

describe('DW-774: leave.spec closes a page that has left', () => {
  const source = read('web/e2e-online/session/leave.spec.ts');

  it('waits for the splash button and the load before it closes', () => {
    const body = source.slice(source.indexOf('async function closeSettled'));
    assert.match(body, /getByRole\('button', \{ name: 'Sign in and start', exact: true \}\)\.waitFor\(\{ state: 'visible' \}\)/);
    assert.match(body, /await page\.waitForLoadState\('load'\);[\s\S]*await page\.close\(\);/);
  });

  it('closes L5\'s second page and L6\'s page through it, and nowhere else', () => {
    assert.match(source, /await closeSettled\(second\);/);
    assert.match(source, /await signOutGroup\(context\);\n\s+await closeSettled\(page\);/);
    assert.equal((source.match(/\.close\(\)/g) ?? []).length, 1, 'the one direct close is the helper\'s');
  });
});

describe('DW-911: the retry-time page lines are redacted before they reach the retries file', () => {
  it('passes the lines of the retry through redactLine to reportRetry', () => {
    const source = read('web/e2e/support/floor.ts');
    assert.match(source, /reportRetry\(`loadedAfter the snapshot GET \$\{STATE\}`, retryLines\.map\(redactLine\)\);/);
    assert.match(source, /printDiagnosis\(retryLines, 'state-diagnosis'\);/);
  });
});

describe('DW-973: TestTimeLeft bounds the lock wait and the part after the release apart', () => {
  const body = method(read('src/ocutalon/cls/OcuTalon/Test/Docs/ExtractMore.cls'), 'TestTimeLeft');

  it('takes the split from the holder\'s end node', () => {
    assert.match(body, /\$\$\$AssertTrue\(\.\.WaitNode\("left", "end", 10\), "the holder set its end node when it released the lock"\)/);
    assert.match(body, /Set released = \$Get\(\^Ocu[A-Za-z]+\("ExtractMore", "left", "end"\), finished\)/);
    assert.match(body, /Set lockSeconds = released - began/);
    assert.match(body, /Set afterSeconds = finished - released/);
  });

  it('keeps elapsed above 4 s and the lock wait under 15 s, and bounds the rest at 20 s, with the split in the message', () => {
    assert.match(body, /\(elapsed > 4\) && \(lockSeconds < 15\) && \(afterSeconds < 20\)/);
    assert.match(body, /lock " _ \$FNumber\(lockSeconds, "", 2\) _ " s, after the release " _ \$FNumber\(afterSeconds, "", 2\) _ " s\)"/);
  });

  it('keeps the timed_out assertion', () => {
    assert.match(body, /"0\|timed_out"/);
  });
});
