// Helper of the mock's tests: server.mjs run as a child process. spawnServer(serverPath, args) returns
//   child        the child process; a test that starts one stops it with child.kill() in its finally block
//   out          the complete lines of its stdout so far; stdout() is all of it, and stderr() all of its stderr
//   exited       a promise of {code, signal, at}, settled after the exit and after both pipes have ended, so that stdout()
//                and stderr() hold everything the child wrote
//   exitWithin   exitWithin(ms) is that promise, or a rejection naming the output when the child is still running after ms
//   waitFor      waitFor(predicate, ms) is the first complete stdout line that satisfies the predicate, or a rejection
// makeTree(extra, omit) is a fresh copy of the committed scenarios plus the extra files ({'A/x.json': data}) minus the omitted names of A/,
// in a temporary folder that the caller removes. withServer({files, omit}, fn) runs fn({base, mock, lines, logFile, readLog}) against a
// fresh in-process server on 127.0.0.1 over such a tree and a fresh log folder, and removes both afterwards.
// spawnServer starts no server until it is called and removes nothing.

import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMock } from '../mock.mjs';
import { loadScenarios } from '../scenarios.mjs';

export const COMMITTED = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'scenarios');

export function makeTree(extra = {}, omit = []) {
  const tree = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-tree-'));
  fs.cpSync(COMMITTED, tree, { recursive: true });
  for (const name of omit) fs.rmSync(path.join(tree, 'A', `${name}.json`));
  for (const [rel, data] of Object.entries(extra)) {
    fs.mkdirSync(path.dirname(path.join(tree, rel)), { recursive: true });
    fs.writeFileSync(path.join(tree, rel), JSON.stringify(data, null, 2));
  }
  return tree;
}

export async function withServer(opts, fn) {
  const tree = makeTree(opts.files, opts.omit);
  const logDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ocu-mock-log-'));
  const logFile = path.join(logDir, 'requests.jsonl');
  let server = null;
  try {
    const { scenarios, problems } = loadScenarios(tree);
    assert.deepEqual(problems, []);
    const lines = [];
    const mock = createMock({ scenarios, logDir, out: { write: (s) => lines.push(s) } });
    server = http.createServer((req, res) => {
      mock.handle(req, res);
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const readLog = () => (fs.existsSync(logFile) ? fs.readFileSync(logFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
    await fn({ base, mock, lines, logFile, readLog });
  } finally {
    if (server !== null) {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    }
    fs.rmSync(tree, { recursive: true, force: true });
    fs.rmSync(logDir, { recursive: true, force: true });
  }
}

export function spawnServer(serverPath, args) {
  const child = spawn(process.execPath, [serverPath, ...args], { stdio: ['ignore', 'pipe', 'pipe'] });
  const out = [];
  const err = [];
  let stdout = '';
  let buffer = '';
  const waiters = [];
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    stdout += chunk;
    buffer += chunk;
    let i;
    while ((i = buffer.indexOf('\n')) !== -1) {
      out.push(buffer.slice(0, i));
      buffer = buffer.slice(i + 1);
    }
    for (const w of waiters.splice(0)) w();
  });
  child.stderr.on('data', (chunk) => err.push(chunk));
  const exited = new Promise((resolve) => child.on('close', (code, signal) => resolve({ code, signal, at: Date.now() })));
  const exitWithin = (ms = 8000) =>
    new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`the server was still running after ${ms} ms: ${out.join(' | ')} ${err.join('')}`)), ms);
      exited.then((e) => {
        clearTimeout(timer);
        resolve(e);
      });
    });
  const waitFor = async (predicate, ms = 8000) => {
    const until = Date.now() + ms;
    for (;;) {
      const hit = out.find(predicate);
      if (hit !== undefined) return hit;
      if (Date.now() > until) throw new Error(`the server printed no wanted line: ${out.join(' | ')} ${err.join('')}`);
      await new Promise((resolve) => {
        waiters.push(resolve);
        setTimeout(resolve, 50);
      });
    }
  };
  return { child, out, stdout: () => stdout, stderr: () => err.join(''), exited, exitWithin, waitFor };
}
