#!/usr/bin/env node
// Cuts the spec files of the Playwright chromium project into n parts and names the files of part k, so that the sign-in unit
// (docker/tests/test-sign-in.sh --part k/n) runs one part on its own stack. Dependency-free.
//
//   node scripts/e2e-part.mjs <k/n> <listing.json>
//
// The listing is Playwright's own JSON listing of the project, made with
//   npm --silent --prefix web run e2e -- --list --reporter=json
// so that playwright.config.ts's testIgnore stays the one source of which files belong to the project, and a spec file that
// is added to the project joins a part with no change to any list.
//
// The rule. The tests of the listing, T of them in run order, are cut into n contiguous ranges whose sizes differ by at most one,
// the first T mod n ranges being the larger. A spec file stays whole and goes to the part whose range holds its first test. Every
// listed test counts, whatever its status at load, so that the cut is the same wherever the listing is made. Taken in order, the
// n parts hold every file of the listing exactly once, in the order the whole unit runs them.
//
// It prints, on stdout:
//   PART k/n: <f> of <F> spec files, <t> of <T> tests: <file> <file> ...       the first line
//   <file>                                                                    one line per file of the part, as the listing names it
// and exits 2 for a bad value (a malformed part, k outside 1 to n, n above the number of files, a part that holds no file) and
// 1 for a listing that is missing, unreadable, not JSON, holds no suites or holds errors[]; the message goes to stderr.

import { readFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const PART = /^([0-9]{1,6})\/([0-9]{1,6})$/;

/** A bad value: the CLI exits 2. */
export class BadValue extends Error {}
/** A listing that cannot be cut: the CLI exits 1. */
export class BadListing extends Error {}

/** `{k, n}` of a text such as `1/2`, with 1 <= k <= n. Anything else is a BadValue that names the text. */
export function parsePart(text) {
  const found = PART.exec(String(text));
  const k = found ? Number(found[1]) : 0;
  const n = found ? Number(found[2]) : 0;
  if (!found || k < 1 || k > n) throw new BadValue(`bad --part value '${text}': use k/n with 1 <= k <= n`);
  return { k, n };
}

function countTests(suite) {
  let count = 0;
  for (const spec of suite.specs ?? []) count += (spec.tests ?? []).length;
  for (const child of suite.suites ?? []) count += countTests(child);
  return count;
}

/** The spec files of a listing, in run order, each with its number of tests. */
export function filesOf(report) {
  if (report === null || typeof report !== 'object') throw new BadListing('the listing is not a JSON object');
  if (Array.isArray(report.errors) && report.errors.length > 0) {
    const messages = report.errors.map((error) => String(error?.message ?? error?.value ?? JSON.stringify(error)));
    throw new BadListing(`the listing holds errors: ${messages.join(' | ')}`);
  }
  if (!Array.isArray(report.suites) || report.suites.length === 0) throw new BadListing('the listing holds no spec files');
  return report.suites.map((suite) => ({ file: String(suite.file ?? suite.title), tests: countTests(suite) }));
}

/** Part k of n of a listing: `{files: [{file, tests}], totalFiles, totalTests}`. */
export function partOf(report, k, n) {
  const all = filesOf(report);
  if (n > all.length) throw new BadValue(`part ${k}/${n}: the listing holds ${all.length} spec files, so use at most ${all.length} parts`);
  let total = 0;
  for (const entry of all) total += entry.tests;
  const size = Math.floor(total / n);
  const larger = total % n;
  const start = (k - 1) * size + Math.min(k - 1, larger);
  const end = start + size + (k <= larger ? 1 : 0);
  const files = [];
  let first = 0;
  for (const entry of all) {
    // The last part also takes the files whose first test is past the last test, which are the files with no test at the end.
    if (first >= start && (first < end || k === n)) files.push(entry);
    first += entry.tests;
  }
  if (files.length === 0) throw new BadValue(`part ${k}/${n} holds no spec file, so use fewer parts`);
  return { files, totalFiles: all.length, totalTests: total };
}

/** The stdout of the CLI for a cut: the PART line, then one line per file. */
export function describePart(report, k, n) {
  const part = partOf(report, k, n);
  const tests = part.files.reduce((sum, entry) => sum + entry.tests, 0);
  const names = part.files.map((entry) => entry.file);
  return [`PART ${k}/${n}: ${part.files.length} of ${part.totalFiles} spec files, ${tests} of ${part.totalTests} tests: ${names.join(' ')}`, ...names].join('\n') + '\n';
}

function main(argv) {
  if (argv.length !== 2) {
    process.stderr.write('usage: node scripts/e2e-part.mjs <k/n> <listing.json>\n');
    return 2;
  }
  try {
    const { k, n } = parsePart(argv[0]);
    let text;
    try {
      text = readFileSync(argv[1], 'utf8');
    } catch (error) {
      throw new BadListing(`the listing could not be read: ${error.message}`);
    }
    let report;
    try {
      report = JSON.parse(text);
    } catch {
      throw new BadListing(`the listing is not JSON: ${text.slice(0, 300)}`);
    }
    process.stdout.write(describePart(report, k, n));
    return 0;
  } catch (error) {
    if (error instanceof BadValue) {
      process.stderr.write(`${error.message}\n`);
      return 2;
    }
    if (error instanceof BadListing) {
      process.stderr.write(`${error.message}\n`);
      return 1;
    }
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.exitCode = main(process.argv.slice(2));
}
