#!/usr/bin/env node
// Turns the live-event payload classes into the page's TypeScript interfaces. Dependency-free.
//
//   node scripts/payloads.mjs            writes src/app/live/payloads.ts
//   node scripts/payloads.mjs --check    writes nothing; exits 1 when the file differs from its fresh output
//
// Options: --publish <file> --payload-dir <dir> --out <file> (the defaults are the repository's own files; tests
// point them at fixtures).
//
// It reads Live/Publish.cls for its TYPES parameter, the event table (type:Class pairs), and every .cls under
// Live/Payload/, the parts under Part/ included. Each class is one interface, every field optional, because IRIS
// omits an empty string and an empty list from the JSON. A payload class is named <Class>Payload and a part by its
// own name. Also written: LiveEventType, the union of the event types, and LivePayloads, the type to interface map.
// An interface with both traceHeaderId and traceNamespace also gets `traceUrl?: string;` as its last field: the web
// layer (Web.TraceLink) adds the URL to such an object when it serves the payload.
//
// A property is read as `Property <Name> As [list Of ]<Type>[(<parameters>)] [<keywords>];` on one line, from the
// first column; a line that starts with `property` in any case or indentation and is not in that form is refused.
//   %String -> string; %Integer, %Numeric -> number; %Boolean -> boolean; list Of %String -> string[];
//   a class of the Part package, or a list of one -> its interface;
//   a class that is one of the payload classes of TYPES (a property that nests another event's payload) -> <Class>Payload.
// It fails closed (exit 1, with file:line) on a property it cannot read, a missing %JSONFIELDNAME, a key that is not
// the property name with a lower-case first letter, a type it does not map, a type in TYPES with no class, and a
// payload class that is not in TYPES.

import { existsSync, readdirSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { emitOutputs } from './tokens.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const liveDir = resolve(repoRoot, 'src/ocutalon/cls/OcuTalon/Live');

const PAYLOAD_PACKAGE = 'OcuTalon.Live.Payload.';
const PART_PACKAGE = 'OcuTalon.Live.Payload.Part.';
const SCALARS = new Map([
  ['%String', 'string'],
  ['%Integer', 'number'],
  ['%Numeric', 'number'],
  ['%Boolean', 'boolean'],
]);

export class PayloadError extends Error {
  constructor(file, line, message) {
    super(line ? `${file}:${line}: ${message}` : `${file}: ${message}`);
    this.name = 'PayloadError';
  }
}

const shown = (path) => relative(process.cwd(), path) || path;

function listClasses(dir) {
  return readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) return listClasses(path);
      return entry.name.endsWith('.cls') ? [path] : [];
    })
    .sort();
}

/** The event table: [{ type, cls, line }] in the order of Publish.cls's TYPES parameter. */
export function readTypes(text, file) {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const match = /^Parameter TYPES = "([^"]*)";/.exec(lines[i]);
    if (!match) continue;
    return match[1].split(',').map((pair) => {
      const [type, cls] = pair.split(':');
      if (!type || !cls || !/^[a-z][a-z.]*$/.test(type) || !/^[A-Z][A-Za-z0-9]*$/.test(cls)) {
        throw new PayloadError(file, i + 1, `TYPES holds '${pair}', which is not <type>:<Class>`);
      }
      return { type, cls, line: i + 1 };
    });
  }
  throw new PayloadError(file, 0, 'there is no Parameter TYPES');
}

/** A class file read as { name, file, properties: [{ name, type, list, key, line }] }; file is only used in messages. */
export function readClass(text, file) {
  const lines = text.split('\n');
  let name = null;
  const properties = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const header = /^Class\s+([\w.]+)/.exec(line);
    if (header) name = header[1];
    if (!/^\s*property\s/i.test(line)) continue;
    const match = /^Property\s+(\w+)\s+As\s+(list\s+Of\s+)?([A-Za-z%][\w.%]*)\s*(?:\(([^)]*)\))?\s*(?:\[[^\]]*\])?\s*;\s*$/.exec(line);
    if (!match) throw new PayloadError(file, i + 1, 'cannot read this property: write it on one line, from the first column, as Property <Name> As [list Of ]<Type>(<parameters>);');
    const [, propertyName, listOf, type, parameters = ''] = match;
    const json = /%JSONFIELDNAME\s*=\s*"([^"]*)"/.exec(parameters);
    if (!json) throw new PayloadError(file, i + 1, `property ${propertyName} has no %JSONFIELDNAME`);
    const expected = propertyName[0].toLowerCase() + propertyName.slice(1);
    if (json[1] !== expected) {
      throw new PayloadError(file, i + 1, `property ${propertyName} has the JSON key '${json[1]}', not the property name with a lower-case first letter ('${expected}')`);
    }
    properties.push({ name: propertyName, type, list: Boolean(listOf), key: json[1], line: i + 1 });
  }
  if (!name) throw new PayloadError(file, 0, 'there is no Class line');
  return { name, file, properties };
}

function tsType(property, file, parts, direct) {
  const scalar = SCALARS.get(property.type);
  let element = scalar;
  if (!element && property.type.startsWith(PART_PACKAGE)) {
    const short = property.type.slice(PART_PACKAGE.length);
    if (parts.has(short)) element = short;
  } else if (!element && property.type.startsWith(PAYLOAD_PACKAGE)) {
    const short = property.type.slice(PAYLOAD_PACKAGE.length);
    if (direct.has(short)) element = `${short}Payload`;
  }
  if (!element || (property.list && scalar !== undefined && scalar !== 'string')) {
    throw new PayloadError(file, property.line, `property ${property.name} has the type ${property.list ? 'list Of ' : ''}${property.type}, which the generator does not map`);
  }
  return property.list ? `${element}[]` : element;
}

function renderInterface(name, cls, parts, direct) {
  const fields = cls.properties.map((property) => `  ${property.key}?: ${tsType(property, cls.file, parts, direct)};`);
  const keys = new Set(cls.properties.map((property) => property.key));
  if (keys.has('traceHeaderId') && keys.has('traceNamespace') && !keys.has('traceUrl')) fields.push('  traceUrl?: string;');
  return [`export interface ${name} {`, ...fields, '}'].join('\n');
}

/** The text of payloads.ts for the payload classes under payloadDir and the event table of publishFile. */
export function generate(opts) {
  const publishText = readFileSync(opts.publish, 'utf8');
  const types = readTypes(publishText, shown(opts.publish));
  const payloadDir = resolve(opts.payloadDir);
  const direct = new Map();
  const parts = new Map();
  for (const path of listClasses(payloadDir)) {
    const cls = readClass(readFileSync(path, 'utf8'), shown(path));
    const short = relative(payloadDir, path).replace(/\.cls$/, '').split('\\').join('/');
    const expected = PAYLOAD_PACKAGE + short.split('/').join('.');
    if (cls.name !== expected) throw new PayloadError(cls.file, 0, `the class is ${cls.name}, but its path says ${expected}`);
    if (short.startsWith('Part/')) parts.set(short.slice('Part/'.length), cls);
    else direct.set(short, cls);
  }
  for (const { type, cls, line } of types) {
    if (!direct.has(cls)) throw new PayloadError(shown(opts.publish), line, `the type '${type}' names ${PAYLOAD_PACKAGE}${cls}, which has no class file under ${shown(payloadDir)}`);
  }
  const named = new Set(types.map((entry) => entry.cls));
  for (const [short, cls] of direct) {
    if (!named.has(short)) throw new PayloadError(cls.file, 0, `the class ${cls.name} is not in the TYPES parameter of ${shown(opts.publish)}`);
  }

  const blocks = [];
  for (const short of [...parts.keys()].sort()) blocks.push(renderInterface(short, parts.get(short), parts, direct));
  for (const { cls } of types) blocks.push(renderInterface(`${cls}Payload`, direct.get(cls), parts, direct));
  const union = types.map(({ type }) => `  | '${type}'`).join('\n');
  const map = types.map(({ type, cls }) => `  '${type}': ${cls}Payload;`).join('\n');
  const text = [
    '// Generated by web/scripts/payloads.mjs from the OcuTalon.Live.Payload classes. Do not edit; run: npm --prefix web run payloads',
    '',
    blocks.join('\n\n'),
    '',
    `export type LiveEventType =\n${union};`,
    '',
    `export interface LivePayloads {\n${map}\n}`,
    '',
  ].join('\n');
  if (/[^\x20-\x7e\n]/.test(text)) throw new PayloadError(shown(opts.out), 0, 'the output holds a character that is not printable ASCII');
  return { outputs: [[opts.out, text]] };
}

function parseArgs(argv) {
  const opts = {
    check: false,
    publish: join(liveDir, 'Publish.cls'),
    payloadDir: join(liveDir, 'Payload'),
    out: resolve(repoRoot, 'web/src/app/live/payloads.ts'),
  };
  const names = { '--publish': 'publish', '--payload-dir': 'payloadDir', '--out': 'out' };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--check') opts.check = true;
    else if (names[a]) {
      if (i + 1 >= argv.length) throw new PayloadError('payloads', 0, `${a} needs a value`);
      opts[names[a]] = resolve(argv[(i += 1)]);
    } else throw new PayloadError('payloads', 0, `unknown option ${a}`);
  }
  return opts;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(opts.publish)) throw new PayloadError(shown(opts.publish), 0, 'the file does not exist');
  if (!existsSync(opts.payloadDir)) throw new PayloadError(shown(opts.payloadDir), 0, 'the folder does not exist');
  const { outputs } = generate(opts);
  emitOutputs('payloads', outputs, opts.check);
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  try {
    main();
  } catch (e) {
    if (e instanceof PayloadError) {
      console.error(`payloads: ${e.message}`);
      process.exit(1);
    }
    throw e;
  }
}
