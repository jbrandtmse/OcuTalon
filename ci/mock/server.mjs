// The entry point of the CI model mock (AD-22): loads the scenario files, then serves the mock over plain HTTP.
//   node server.mjs [--port <n>] [--log-dir <folder>] [--scenarios <folder>] [--pop3-port <n>] [--smtp-port <n>]
//   --port       default 8080; with 0 the OS picks a port, and the bound port is in the listening line
//   --pop3-port  default 1110; the plain-TCP POP3 stub (mail.mjs) listens there, and /_mock/mail/ on --port controls it. A port that
//                cannot be taken is no start failure: the stub is then absent and the line {"event":"pop3-unavailable"} says so
//   --smtp-port  default 1025; the plain-TCP SMTP stub (smtp.mjs) listens there, and /_mock/smtp/ on --port controls it. A port that
//                cannot be taken is no start failure: the stub is then absent and the line {"event":"smtp-unavailable"} says so
//   --log-dir    the folder of requests.jsonl; absent means stdout only. A folder that cannot be written is a start failure
//   --scenarios  default: the scenarios/ folder beside this file
// /_mock/oauth/ on --port is the fake OAuth2 authorization server (oauth.mjs): its authorize and token endpoints and its control routes.
// It prints {"event":"listening","port":<p>,"scenarios":<n>} on stdout when it serves, then one JSON line per request.
// A scenario file that breaks the format, an unreadable log folder or a bad argument stops the start: the problems go to
// stderr, one per line, and the exit status is 1.
// SIGTERM and SIGINT end the process at once with status 0 (it may be PID 1 of its container, where an unhandled signal is
// ignored, and a held reply would otherwise make the stop wait out the grace period).

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMail } from './mail.mjs';
import { createMock, LOG_FILE } from './mock.mjs';
import { createOAuth } from './oauth.mjs';
import { loadScenarios } from './scenarios.mjs';
import { createSmtp } from './smtp.mjs';

function parseArgs(argv) {
  const opts = { port: 8080, pop3Port: 1110, smtpPort: 1025, logDir: null, scenarios: path.join(path.dirname(fileURLToPath(import.meta.url)), 'scenarios') };
  const problems = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = argv[i + 1];
    if (arg === '--port' || arg === '--pop3-port' || arg === '--smtp-port' || arg === '--log-dir' || arg === '--scenarios') {
      if (value === undefined) {
        problems.push(`${arg} needs a value`);
        continue;
      }
      i += 1;
      if (arg === '--port' || arg === '--pop3-port' || arg === '--smtp-port') {
        if (!/^[0-9]{1,5}$/.test(value) || Number(value) > 65535) problems.push(`${arg} is not a port number: ${value}`);
        else if (arg === '--port') opts.port = Number(value);
        else if (arg === '--pop3-port') opts.pop3Port = Number(value);
        else opts.smtpPort = Number(value);
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
const mail = createMail();
const smtp = createSmtp();
const oauth = createOAuth();
const server = http.createServer((req, res) => {
  const url = req.url || '/';
  if (url.startsWith('/_mock/mail/')) {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => mail.handleControl(req, res, url.split('?')[0], Buffer.concat(chunks).toString('utf8')));
    return;
  }
  if (url.startsWith('/_mock/smtp/')) {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => smtp.handleControl(req, res, url.split('?')[0], Buffer.concat(chunks).toString('utf8')));
    return;
  }
  if (url.startsWith('/_mock/oauth/')) {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => oauth.handle(req, res, url.split('?')[0], Buffer.concat(chunks).toString('utf8')));
    return;
  }
  mock.handle(req, res);
});

process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));

server.on('error', (e) => fail([`cannot listen on port ${opts.port} (${e.code})`]));
server.listen(opts.port, () => {
  process.stdout.write(`${JSON.stringify({ event: 'listening', port: server.address().port, scenarios: scenarios.all.length })}\n`);
});
mail.listen(opts.pop3Port, '0.0.0.0', (e, bound) => {
  process.stdout.write(`${JSON.stringify(e ? { event: 'pop3-unavailable', code: e.code } : { event: 'pop3', port: bound })}\n`);
});
smtp.listen(opts.smtpPort, '0.0.0.0', (e, bound) => {
  process.stdout.write(`${JSON.stringify(e ? { event: 'smtp-unavailable', code: e.code } : { event: 'smtp', port: bound })}\n`);
});
