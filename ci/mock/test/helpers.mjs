// Helper of the mock's tests: server.mjs run as a child process. spawnServer(serverPath, args) returns
//   child        the child process; a test that starts one stops it with child.kill() in its finally block
//   out          the complete lines of its stdout so far; stdout() is all of it, and stderr() all of its stderr
//   exited       a promise of {code, signal, at}, settled after the exit and after both pipes have ended, so that stdout()
//                and stderr() hold everything the child wrote
//   exitWithin   exitWithin(ms) is that promise, or a rejection naming the output when the child is still running after ms
//   waitFor      waitFor(predicate, ms) is the first complete stdout line that satisfies the predicate, or a rejection
// It starts no server of its own and removes nothing.

import { spawn } from 'node:child_process';

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
