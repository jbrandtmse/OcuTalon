// The entry point of the CI model mock (AD-22): loads the scenario files, then serves the mock over plain HTTP.
//   node server.mjs [--port <n>] [--log-dir <folder>] [--scenarios <folder>]
//   --port       default 8080; with 0 the OS picks a port, and the bound port is in the listening line
//   --log-dir    the folder of requests.jsonl; absent means stdout only. A folder that cannot be written is a start failure
//   --scenarios  default: the scenarios/ folder beside this file
// It prints {"event":"listening","port":<p>,"scenarios":<n>} on stdout when it serves, then one JSON line per request.
// A scenario file that breaks the format, an unreadable log folder or a bad argument stops the start: the problems go to
// stderr, one per line, and the exit status is 1.
// SIGTERM and SIGINT end the process at once with status 0 (it may be PID 1 of its container, where an unhandled signal is
// ignored, and a held reply would otherwise make the stop wait out the grace period).

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMock, LOG_FILE } from './mock.mjs';
import { loadScenarios } from './scenarios.mjs';

function parseArgs(argv) {
  const opts = { port: 8080, logDir: null, scenarios: path.join(path.dirname(fileURLToPath(import.meta.url)), 'scenarios') };
  const problems = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = argv[i + 1];
    if (arg === '--port' || arg === '--log-dir' || arg === '--scenarios') {
      if (value === undefined) {
        problems.push(`${arg} needs a value`);
        continue;
      }
      i += 1;
      if (arg === '--port') {
        if (!/^[0-9]{1,5}$/.test(value) || Number(value) > 65535) problems.push(`--port is not a port number: ${value}`);
        else opts.port = Number(value);
      } else if (arg === '--log-dir') {
        opts.logDir = value;
      } else {
        opts.scenarios = value;
      }
    } else {
      problems.push(`unknown argument ${arg}`);
    }
  }
  return { opts, problems };
}

function fail(problems) {
  for (const p of problems) process.stderr.write(`mock: ${p}\n`);
  process.exit(1);
}

const { opts, problems: argProblems } = parseArgs(process.argv.slice(2));
if (argProblems.length > 0) fail(argProblems);

const { scenarios, problems } = loadScenarios(opts.scenarios);
if (problems.length > 0) fail(problems);

if (opts.logDir !== null) {
  try {
    fs.mkdirSync(opts.logDir, { recursive: true });
    fs.appendFileSync(path.join(opts.logDir, LOG_FILE), '');
  } catch (e) {
    fail([`the log folder cannot be written (${e.code})`]);
  }
}

const mock = createMock({ scenarios, logDir: opts.logDir, out: process.stdout });
const server = http.createServer((req, res) => {
  mock.handle(req, res);
});

process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));

server.on('error', (e) => fail([`cannot listen on port ${opts.port} (${e.code})`]));
server.listen(opts.port, () => {
  process.stdout.write(`${JSON.stringify({ event: 'listening', port: server.address().port, scenarios: scenarios.all.length })}\n`);
});
