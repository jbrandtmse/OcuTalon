#!/usr/bin/env node
// Summarises the Playwright JSON report of the demo path (project demo-path, OCUTALON_E2E_JSON) step by step, so that a
// skipped step is never read as a passed one. Dependency-free.
//
//   node scripts/demo-path-summary.mjs [--only-telegram-skips | --steps <id,...>] <report.json>
//
// With --only-telegram-skips (the demo-path unit's run, since Story 11.1) every web step runs: a skipped test of a numbered step file
// is a failure, and only the parts in telegram-<id>.spec.ts may skip. Without the flag a skip that names its story is accepted, as
// a hosted run with no stack (OCUTALON_URL) skips the whole of steps 2 to 8.
//
// The steps are fixed: 1 page, 2 watch, 3 reminder, 4 incident, 5 approval, 6 trace, 7 failure-paths, 8 quiet-outcomes (the last two are
// Story 11.10's). Step n is 0<n>-<id>.spec.ts, and a
// telegram-<id>.spec.ts file is a part of step <id>. It prints, in this order:
//   STEP <n> <id>: <verdict>, <p> passed, <s> skipped[, <f> failed][ (Story <x>: <title>; ...)]   one line per step
//   DEMO-PATH <r> of 8 steps ran (<k> partly skipped), <s> skipped, <f> failed; floor <p> of <n> passed
//   FAIL <reason>                                                                                 one line per failure
// The verdicts: passed (a test passed, none skipped or failed), partly skipped (a test passed, one skipped, none failed),
// skipped (none passed or failed), failed (a test failed, timed out, was interrupted or did not run). The story of a skipped
// test is the one that its skip text names: a test declared with notBuilt() (e2e/demo-path/not-built.ts) skips with
// "Story <n>.<m> turns this on".
// With --steps <id,...> (the clean-machine rehearsal's repeats, Story 11.12; web/e2e-rehearsal/) the steps are those ids, each in
// <id>.spec.ts: every test must pass, any skip is a failure, and there is no @floor rule. It prints one line per id
//   STEP <id>: <verdict>, <p> passed, <s> skipped[, <f> failed]
// then REHEARSAL <r> of <n> steps ran, <s> skipped, <f> failed, then the FAIL lines (<file> "<title>": <state>).
// It exits 1 on any FAIL line, and 0 otherwise. It fails on
//   - a report that is missing, unreadable, not JSON or holds no suites, and any error that Playwright put in the report
//     (a crash, a spec that failed to load, the global timeout);
//   - a step with no 0<n>-<id>.spec.ts, a spec file that maps to no step, and a telegram-<id>.spec.ts of an unknown step;
//   - a skipped test whose skip text does not start with "Story <n>.<m>";
//   - with --only-telegram-skips, a skipped test in a numbered step file;
//   - a test tagged @floor that did not pass, and a step 1 with no @floor test;
//   - a test that failed, timed out, was interrupted or did not run.

import { readFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** The steps of UJ-1, in order. */
export const STEPS = ['page', 'watch', 'reminder', 'incident', 'approval', 'trace', 'failure-paths', 'quiet-outcomes'];

const STORY = /^Story (\d+\.\d+)\b/;
const NUMBERED = /^(\d{2})-([a-z][a-z0-9-]*)\.spec\.ts$/;
const TELEGRAM = /^telegram-([a-z][a-z0-9-]*)\.spec\.ts$/;
const ANSI = /\u001b\[[0-9;]*m/g;

const STATE_WORDS = { failed: 'failed', timedOut: 'timed out', interrupted: 'was interrupted', notRun: 'did not run' };

const baseName = (file) => String(file).split(/[\\/]/).pop();

/** The step index of a spec file (numbered: the step's own file), or the reason that it maps to no step. */
export function stepOfFile(file) {
  const name = baseName(file);
  const numbered = NUMBERED.exec(name);
  if (numbered) {
    const index = Number(numbered[1]) - 1;
    if (STEPS[index] === numbered[2]) return { index, numbered: true };
    return { error: `the report holds ${name}, which maps to no step` };
  }
  const telegram = TELEGRAM.exec(name);
  if (telegram) {
    const index = STEPS.indexOf(telegram[1]);
    if (index >= 0) return { index, numbered: false };
    return { error: `the report holds ${name}, but ${telegram[1]} is not a step (${STEPS.join(', ')})` };
  }
  return { error: `the report holds ${name}, which maps to no step` };
}

function* specsOf(suite) {
  for (const spec of suite.specs ?? []) yield spec;
  for (const child of suite.suites ?? []) yield* specsOf(child);
}

/** How one test ended: passed, skipped (with the text of its skip) or failed (with its state). */
function outcome(test) {
  const results = test.results ?? [];
  const status = results.length > 0 ? results[results.length - 1].status : 'notRun';
  if (status === 'passed') return { kind: 'passed' };
  if (status === 'skipped') {
    const annotations = [...(test.annotations ?? []), ...results.flatMap((result) => result.annotations ?? [])];
    const texts = annotations
      .filter((annotation) => annotation.type === 'skip' || annotation.type === 'fixme')
      .map((annotation) => annotation.description)
      .filter((text) => typeof text === 'string' && text !== '');
    const text = texts.find((candidate) => STORY.test(candidate)) ?? texts[0] ?? '';
    return { kind: 'skipped', story: STORY.exec(text)?.[1] ?? '' };
  }
  return { kind: 'failed', state: STATE_WORDS[status] ?? `ended ${status}` };
}

function verdictOf(step) {
  if (step.failed > 0) return 'failed';
  if (step.passed === 0) return 'skipped';
  return step.skipped > 0 ? 'partly skipped' : 'passed';
}

/**
 * Summarises a parsed Playwright JSON report. Returns the output lines and the reasons of the failures (without the
 * FAIL prefix). With onlyTelegramSkips, a skipped test of a numbered step file is a failure too.
 */
export function summarize(report, { onlyTelegramSkips = false } = {}) {
  const failures = [];
  if (!report || typeof report !== 'object' || !Array.isArray(report.suites)) {
    return { lines: [], failures: ['no usable report: it holds no suites list'] };
  }
  for (const error of Array.isArray(report.errors) ? report.errors : []) {
    const first = String(error?.message ?? error).replace(ANSI, '').split('\n')[0].trim();
    failures.push(`Playwright reported an error: ${first.slice(0, 200)}`);
  }

  const steps = STEPS.map((id, i) => ({ n: i + 1, id, passed: 0, skipped: 0, failed: 0, floor: 0, stories: [], numbered: false }));
  let floorTotal = 0;
  let floorPassed = 0;
  for (const suite of report.suites) {
    const mapped = stepOfFile(suite.file ?? suite.title ?? '');
    if (mapped.error) {
      failures.push(mapped.error);
      continue;
    }
    const step = steps[mapped.index];
    const file = baseName(suite.file ?? suite.title);
    if (mapped.numbered) step.numbered = true;
    for (const spec of specsOf(suite)) {
      const floor = (spec.tags ?? []).some((tag) => String(tag).replace(/^@/, '') === 'floor');
      for (const test of spec.tests ?? []) {
        const result = outcome(test);
        const label = `"${spec.title}"`;
        if (floor) {
          step.floor += 1;
          floorTotal += 1;
          if (result.kind === 'passed') floorPassed += 1;
        }
        if (result.kind === 'passed') {
          step.passed += 1;
        } else if (result.kind === 'skipped') {
          step.skipped += 1;
          if (onlyTelegramSkips && mapped.numbered) {
            failures.push(`${file} ${label}: skipped, but every web step runs since Story 11.1 (REL-2); only telegram-*.spec.ts parts may skip`);
          } else if (result.story) {
            step.stories.push(`Story ${result.story}: ${spec.title}`);
          } else {
            failures.push(`${file} ${label}: its skip names no story`);
          }
          if (floor) failures.push(`floor test ${label} (${file}) was skipped`);
        } else {
          step.failed += 1;
          if (floor) failures.push(`floor test ${label} (${file}) ${result.state}`);
          else failures.push(`${file} ${label}: ${result.state}`);
        }
      }
    }
  }

  for (const step of steps) {
    const total = step.passed + step.skipped + step.failed;
    const wanted = `0${step.n}-${step.id}.spec.ts`;
    if (!step.numbered) failures.push(`step ${step.n} ${step.id} has no ${wanted} in the report`);
    else if (total === 0) failures.push(`step ${step.n} ${step.id}: ${wanted} holds no test`);
    step.verdict = !step.numbered || total === 0 ? 'failed' : verdictOf(step);
  }
  if (steps[0].numbered && steps[0].floor === 0) failures.push(`step 1 ${STEPS[0]} has no @floor test`);

  const lines = steps.map((step) => {
    const failed = step.failed > 0 ? `, ${step.failed} failed` : '';
    const stories = step.stories.length > 0 ? ` (${step.stories.join('; ')})` : '';
    return `STEP ${step.n} ${step.id}: ${step.verdict}, ${step.passed} passed, ${step.skipped} skipped${failed}${stories}`;
  });
  const count = (verdicts) => steps.filter((step) => verdicts.includes(step.verdict)).length;
  const sum = (key) => steps.reduce((total, step) => total + step[key], 0);
  lines.push(
    `DEMO-PATH ${count(['passed', 'partly skipped'])} of ${STEPS.length} steps ran (${count(['partly skipped'])} partly skipped), ` +
      `${sum('skipped')} skipped, ${sum('failed')} failed; floor ${floorPassed} of ${floorTotal} passed`,
  );
  return { lines, failures };
}

/**
 * Summarises a parsed Playwright JSON report of the rehearsal's repeats: the steps are `ids`, each in <id>.spec.ts; a test that did not
 * pass is a failure (a skip too), and a step with no file or no test is one. Returns the output lines and the failure reasons.
 */
export function summarizeSteps(report, ids) {
  const failures = [];
  if (!report || typeof report !== 'object' || !Array.isArray(report.suites)) {
    return { lines: [], failures: ['no usable report: it holds no suites list'] };
  }
  for (const error of Array.isArray(report.errors) ? report.errors : []) {
    const first = String(error?.message ?? error).replace(ANSI, '').split('\n')[0].trim();
    failures.push(`Playwright reported an error: ${first.slice(0, 200)}`);
  }
  const steps = ids.map((id) => ({ id, passed: 0, skipped: 0, failed: 0, seen: false }));
  for (const suite of report.suites) {
    const file = baseName(suite.file ?? suite.title ?? '');
    const step = steps.find((one) => file === `${one.id}.spec.ts`);
    if (!step) {
      failures.push(`the report holds ${file}, which is not a step of this run (${ids.join(', ')})`);
      continue;
    }
    step.seen = true;
    for (const spec of specsOf(suite)) {
      for (const test of spec.tests ?? []) {
        const result = outcome(test);
        if (result.kind === 'passed') {
          step.passed += 1;
        } else if (result.kind === 'skipped') {
          step.skipped += 1;
          failures.push(`${file} "${spec.title}": skipped, but every test of a rehearsal step runs`);
        } else {
          step.failed += 1;
          failures.push(`${file} "${spec.title}": ${result.state}`);
        }
      }
    }
  }
  for (const step of steps) {
    const total = step.passed + step.skipped + step.failed;
    if (!step.seen) failures.push(`step ${step.id} has no ${step.id}.spec.ts in the report`);
    else if (total === 0) failures.push(`step ${step.id}: ${step.id}.spec.ts holds no test`);
    step.verdict = !step.seen || total === 0 || step.failed > 0 ? 'failed' : step.skipped > 0 ? 'skipped' : 'passed';
  }
  const lines = steps.map((step) => `STEP ${step.id}: ${step.verdict}, ${step.passed} passed, ${step.skipped} skipped${step.failed > 0 ? `, ${step.failed} failed` : ''}`);
  const sum = (key) => steps.reduce((total, step) => total + step[key], 0);
  lines.push(`REHEARSAL ${steps.filter((step) => step.verdict === 'passed').length} of ${steps.length} steps ran, ${sum('skipped')} skipped, ${sum('failed')} failed`);
  return { lines, failures };
}

/** Reads the report file and summarises it (options as for summarize); a file that cannot be used is one failure and no lines. */
export function summarizeFile(path, options = {}) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (error) {
    return { lines: [], failures: [`no usable report: the file cannot be read (${error.code ?? error.message})`] };
  }
  let report;
  try {
    report = JSON.parse(text);
  } catch (error) {
    return { lines: [], failures: [`no usable report: the file is not JSON (${error.message})`] };
  }
  return Array.isArray(options.steps) ? summarizeSteps(report, options.steps) : summarize(report, options);
}

const USAGE = 'usage: node scripts/demo-path-summary.mjs [--only-telegram-skips | --steps <id,...>] <report.json>';

function main(argv) {
  const onlyTelegramSkips = argv[0] === '--only-telegram-skips';
  const stepsMode = argv[0] === '--steps';
  const ids = stepsMode ? (argv[1] ?? '').split(',') : undefined;
  if (stepsMode && (ids.some((id) => !/^[a-z][a-z0-9-]*$/.test(id)) || new Set(ids).size !== ids.length)) {
    console.error(USAGE);
    return 2;
  }
  const rest = onlyTelegramSkips ? argv.slice(1) : stepsMode ? argv.slice(2) : argv;
  if (rest.length !== 1 || rest[0].startsWith('--')) {
    console.error(USAGE);
    return 2;
  }
  const { lines, failures } = summarizeFile(rest[0], stepsMode ? { steps: ids } : { onlyTelegramSkips });
  for (const line of lines) console.log(line);
  for (const failure of failures) console.log(`FAIL ${failure}`);
  return failures.length > 0 ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.exit(main(process.argv.slice(2)));
}
