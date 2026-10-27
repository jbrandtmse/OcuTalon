#!/usr/bin/env node
// Turns the keys of the message catalog that the page renders into a TypeScript module. Dependency-free.
//
//   node scripts/catalog.mjs            writes src/app/msg/catalog.ts
//   node scripts/catalog.mjs --check    writes nothing; exits 1 when the file differs from its fresh output
//
// Options: --core <file> --watch <file> --catalog <file> --out <file> (the defaults are the repository's own files; tests
// point them at fixtures).
//
// It reads the XData block Entries of Msg/Catalog/Core.cls and of Msg/Catalog/Watch.cls (one JSON object each, the catalog
// keys with their texts and slot types; the two are merged, and a key in both is refused) and the REASONKEYS parameter of
// Msg/Catalog.cls (each fallback reason value with the suffix of its fallbackReason.* key), and keeps an allowlist of the
// keys the page renders: conversation.turnFallback, the check sentences checks.allPassed, checks.everythingElsePassed,
// checks.nothingWatched, checks.notEverything and checks.notEverythingRestPassed, the nine banner.* texts, the three bannerAction.* texts the page renders (installYourself, howToSetKey
// and setUpBot) and every fallbackReason.*. An entry's web text is used, else its text. The module holds PAGE_TEXTS, PAGE_SLOTS
// (the slot types of each listed key), REASON_KEYS and renderPageText. A fallbackReason slot renders as its reason text; a time,
// count or cost slot takes the string the caller formatted (the page formats times, costs and counts itself, AD-32), cleaned
// like any string slot. A text slot (the whatFailed of checks.notEverything and checks.notEverythingRestPassed, built by the
// page from the check rows, DW-90) is allowed for those two keys only and is cleaned the same way.
//
// It fails closed (exit 1, with the file) on a listed key that is missing from both files, a listed key with a slot of a type
// other than fallbackReason, time, count or cost (text for the two keys of TEXT_SLOT_KEYS only) or with a placeholder that is not a declared slot, a fallbackReason.* text
// with a slot of a type other than fallbackReason, a listed key with a one form, a reason value whose fallbackReason.* key is
// missing, a key that both catalogs define, and an XData block or a REASONKEYS parameter it cannot read.
// A later story that renders another key or slot type adds it here, to the allowlist and to renderPageText.

import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { emitOutputs } from './tokens.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const msgDir = resolve(repoRoot, 'src/ocutalon/cls/OcuTalon/Msg');

/** The keys the page renders, besides every key under REASON_PREFIX. */
export const LISTED_KEYS = [
  'conversation.turnFallback',
  'checks.allPassed',
  'checks.everythingElsePassed',
  'checks.nothingWatched',
  'checks.notEverything',
  'checks.notEverythingRestPassed',
  'banner.allowance',
  'banner.dailyCap',
  'banner.unreachable',
  'banner.noModelKey',
  'banner.costCap',
  'banner.heartbeatStalled',
  'banner.telegramPaused',
  'banner.resetSoon',
  'banner.reconnecting',
  'bannerAction.installYourself',
  'bannerAction.howToSetKey',
  'bannerAction.setUpBot',
];
export const REASON_PREFIX = 'fallbackReason.';
/** The slot types that every listed key may declare (a key of TEXT_SLOT_KEYS may also declare text): a fallbackReason slot gives its reason text, the others take the caller's formatted string. */
const SLOT_TYPES = ['fallbackReason', 'time', 'count', 'cost'];
/** The keys that may also declare a text slot, which the page fills from the check rows (DW-90); every other key refuses it. */
export const TEXT_SLOT_KEYS = ['checks.notEverything', 'checks.notEverythingRestPassed'];
const TEXT_SLOT_TYPE = 'text';
/** The one slot type a fallbackReason.* text may declare: the page renders a reason text as it is, with no slot filled. */
const REASON_SLOT_TYPE = 'fallbackReason';

export class CatalogError extends Error {
  constructor(file, line, message) {
    super(line ? `${file}:${line}: ${message}` : `${file}: ${message}`);
    this.name = 'CatalogError';
  }
}

const shown = (path) => relative(process.cwd(), path) || path;

/** The entries of the XData block Entries of a catalog class: { entries, line } with line where the JSON begins. */
export function readEntries(text, file) {
  const lines = text.split('\n');
  const header = lines.findIndex((line) => /^XData\s+Entries\b/.test(line));
  if (header < 0) throw new CatalogError(file, 0, 'there is no XData block Entries');
  if (lines[header + 1] !== '{' || lines[header + 2] !== '{') {
    throw new CatalogError(file, header + 1, 'the XData block Entries must open with { and then the JSON object on lines of their own');
  }
  let close = -1;
  for (let i = header + 3; i < lines.length - 1; i += 1) {
    if (lines[i] === '}' && lines[i + 1] === '}') {
      close = i;
      break;
    }
  }
  if (close < 0) throw new CatalogError(file, header + 1, 'the XData block Entries does not end with } and } on lines of their own');
  let entries;
  try {
    entries = JSON.parse(lines.slice(header + 2, close + 1).join('\n'));
  } catch (e) {
    throw new CatalogError(file, header + 3, `the XData block Entries is not valid JSON (${e.message})`);
  }
  if (entries === null || typeof entries !== 'object' || Array.isArray(entries)) {
    throw new CatalogError(file, header + 3, 'the XData block Entries is not one JSON object');
  }
  return { entries, line: header + 3 };
}

/** The REASONKEYS parameter of Catalog.cls as [value, suffix] pairs, in order. */
export function readReasonKeys(text, file) {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const match = /^Parameter REASONKEYS = "([^"]*)";/.exec(lines[i]);
    if (!match) continue;
    const pairs = match[1].split(',').map((pair) => pair.split('='));
    for (const pair of pairs) {
      if (pair.length !== 2 || !/^[a-z_]+$/.test(pair[0]) || !/^[A-Za-z]+$/.test(pair[1])) {
        throw new CatalogError(file, i + 1, `REASONKEYS holds '${pair.join('=')}', which is not <value>=<suffix>`);
      }
    }
    return pairs;
  }
  throw new CatalogError(file, 0, 'there is no Parameter REASONKEYS');
}

/** A listed entry's page text (web, else text) and slot types, checked: only the slot types the page renders, each placeholder declared, no one form. */
function pageText(key, entry, file) {
  if (entry === null || typeof entry !== 'object') throw new CatalogError(file, 0, `the entry '${key}' is not an object`);
  const slots = entry.slots;
  if (slots === null || typeof slots !== 'object' || Array.isArray(slots)) throw new CatalogError(file, 0, `the entry '${key}' declares no slots object`);
  for (const [name, type] of Object.entries(slots)) {
    const allowed = TEXT_SLOT_KEYS.includes(key) ? [...SLOT_TYPES, TEXT_SLOT_TYPE] : SLOT_TYPES;
    if (!allowed.includes(type)) {
      throw new CatalogError(file, 0, `the entry '${key}' has the slot '${name}' of type '${String(type)}', which the page does not render (only ${allowed.join(', ')})`);
    }
  }
  if ('one' in entry) throw new CatalogError(file, 0, `the entry '${key}' has a one form, which the page does not render`);
  const text = 'web' in entry ? entry.web : entry.text;
  if (typeof text !== 'string' || text === '') throw new CatalogError(file, 0, `the entry '${key}' has no ${'web' in entry ? 'web' : 'text'} text`);
  for (const match of text.matchAll(/\{([^{}]*)\}/g)) {
    if (!Object.hasOwn(slots, match[1])) throw new CatalogError(file, 0, `the text of '${key}' uses {${match[1]}}, which the entry does not declare as a slot`);
  }
  if (/[{}]/.test(text.replace(/\{[^{}]*\}/g, ''))) throw new CatalogError(file, 0, `the text of '${key}' has a brace that is not a {name} placeholder`);
  return { text, slots };
}

/** A string as a TypeScript literal in printable ASCII, single-quoted unless it holds a ' and no ": other characters are written as escape sequences. */
function quote(text) {
  const mark = text.includes("'") && !text.includes('"') ? '"' : "'";
  let out = '';
  for (const char of text) {
    const code = char.codePointAt(0);
    if (char === '\\' || char === mark) out += `\\${char}`;
    else if (code >= 0x20 && code <= 0x7e) out += char;
    else if (char === '\n') out += '\\n';
    else if (code <= 0xffff) out += `\\u${code.toString(16).toUpperCase().padStart(4, '0')}`;
    else out += `\\u{${code.toString(16).toUpperCase()}}`;
  }
  return `${mark}${out}${mark}`;
}

const RENDERER = `/** A slot value as the catalog reads a string slot: its whitespace runs become one space, the invisible control characters go, and the ends are trimmed. */
function cleanSlot(value: unknown): string {
  const text = typeof value === 'string' ? value : '';
  return text
    .replace(/[\\t\\n\\v\\f\\r\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]/g, ' ')
    .replace(/[\\u061C\\u180E\\u200B\\u200E\\u200F\\u202A-\\u202E\\u2060-\\u2064\\u2066-\\u2069\\uFEFF\\uFFF9-\\uFFFB]/g, '')
    .replace(/\\p{Cc}/gu, '')
    .replace(/ {2,}/g, ' ')
    .trim();
}

/** The text of a fallback reason value, or the generic reason's when the value is none of REASON_KEYS. */
function reasonText(value: unknown): string {
  const reason = cleanSlot(value);
  const suffix = Object.hasOwn(REASON_KEYS, reason) ? REASON_KEYS[reason] : 'generic';
  return PAGE_TEXTS['fallbackReason.' + suffix] ?? '';
}

/**
 * The text of a catalog key that the page renders, with its slots filled in one pass: a value is never read as a
 * placeholder. A fallbackReason slot takes a fallback reason value and gives its text; a value that is none of REASON_KEYS
 * gives the generic reason's. Every other slot takes the string the caller formatted (a time, a cost, a count or, for a text
 * slot, the whatFailed sentence part that the page built from the check rows), cleaned like any string slot, and an absent or non-string value gives an empty string. A key that is not in PAGE_TEXTS throws.
 */
export function renderPageText(key: string, slots: PageSlots = {}): string {
  const template = Object.hasOwn(PAGE_TEXTS, key) ? PAGE_TEXTS[key] : undefined;
  if (template === undefined) throw new Error("The page has no catalog text for '" + key + "'");
  const types = Object.hasOwn(PAGE_SLOTS, key) ? PAGE_SLOTS[key] : {};
  return template.replace(/\\{([^{}]*)\\}/g, (_placeholder: string, name: string) => {
    const value = Object.hasOwn(slots, name) ? slots[name] : undefined;
    return Object.hasOwn(types, name) && types[name] === 'fallbackReason' ? reasonText(value) : cleanSlot(value);
  });
}
`;

/** The text of catalog.ts for the catalog classes at opts.core, opts.watch and opts.catalog. */
export function generate(opts) {
  const coreName = shown(opts.core);
  const watchName = shown(opts.watch);
  const catalogName = shown(opts.catalog);
  const core = readEntries(readFileSync(opts.core, 'utf8'), coreName).entries;
  const watch = readEntries(readFileSync(opts.watch, 'utf8'), watchName).entries;
  /** Each key with its entry and the file it came from. */
  const entries = new Map();
  for (const [key, entry] of Object.entries(core)) entries.set(key, { entry, file: coreName });
  for (const [key, entry] of Object.entries(watch)) {
    if (entries.has(key)) throw new CatalogError(watchName, 0, `the key '${key}' is in both ${coreName} and ${watchName}`);
    entries.set(key, { entry, file: watchName });
  }
  const reasons = readReasonKeys(readFileSync(opts.catalog, 'utf8'), catalogName);

  const texts = new Map();
  /** The slot types of each listed key, in the listed order. */
  const slotTypes = new Map();
  for (const key of LISTED_KEYS) {
    if (!entries.has(key)) throw new CatalogError(`${coreName} and ${watchName}`, 0, `the key '${key}', which the page renders, is missing`);
    const { entry, file } = entries.get(key);
    const { text, slots } = pageText(key, entry, file);
    texts.set(key, text);
    slotTypes.set(key, slots);
  }
  for (const [key, { entry, file }] of entries) {
    if (!key.startsWith(REASON_PREFIX)) continue;
    const { text, slots } = pageText(key, entry, file);
    for (const [name, type] of Object.entries(slots)) {
      if (type !== REASON_SLOT_TYPE) {
        throw new CatalogError(file, 0, `the entry '${key}' has the slot '${name}' of type '${String(type)}', which a reason text cannot take (only ${REASON_SLOT_TYPE})`);
      }
    }
    texts.set(key, text);
  }
  for (const [value, suffix] of reasons) {
    if (!texts.has(REASON_PREFIX + suffix)) {
      throw new CatalogError(coreName, 0, `the key '${REASON_PREFIX}${suffix}', the text of the fallback reason '${value}' in REASONKEYS, is missing`);
    }
  }
  if (!texts.has(`${REASON_PREFIX}generic`)) throw new CatalogError(coreName, 0, `the key '${REASON_PREFIX}generic', which stands for an unknown reason, is missing`);

  const textLines = [...texts].map(([key, text]) => `  ${quote(key)}: ${quote(text)},`);
  const slotLines = [...slotTypes].map(([key, slots]) => `  ${quote(key)}: { ${Object.entries(slots).map(([name, type]) => `${quote(name)}: ${quote(type)}`).join(', ')} },`.replace('{  }', '{}'));
  const reasonLines = reasons.map(([value, suffix]) => `  ${quote(value)}: ${quote(suffix)},`);
  const text = [
    '// Generated by web/scripts/catalog.mjs from the OcuTalon message catalog classes. Do not edit; run: npm --prefix web run catalog',
    '',
    '/** The page wording of each catalog key that the page renders, with {name} placeholders for its slots. */',
    `export const PAGE_TEXTS: Readonly<Record<string, string>> = {\n${textLines.join('\n')}\n};`,
    '',
    '/** The slot types of each listed key, by slot name: fallbackReason gives its reason text, the others (time, count, cost and text) take the formatted string the caller passes. */',
    `export const PAGE_SLOTS: Readonly<Record<string, Readonly<Record<string, string>>>> = {\n${slotLines.join('\n')}\n};`,
    '',
    '/** Each fallback reason value with the suffix of its fallbackReason.* key. */',
    `export const REASON_KEYS: Readonly<Record<string, string>> = {\n${reasonLines.join('\n')}\n};`,
    '',
    '/** The slots of a page text, by name. */',
    'export type PageSlots = Readonly<Record<string, unknown>>;',
    '',
    RENDERER,
  ].join('\n');
  if (/[^\x20-\x7e\n]/.test(text)) throw new CatalogError(shown(opts.out), 0, 'the output holds a character that is not printable ASCII');
  return { outputs: [[opts.out, text]] };
}

function parseArgs(argv) {
  const opts = {
    check: false,
    core: join(msgDir, 'Catalog/Core.cls'),
    watch: join(msgDir, 'Catalog/Watch.cls'),
    catalog: join(msgDir, 'Catalog.cls'),
    out: resolve(repoRoot, 'web/src/app/msg/catalog.ts'),
  };
  const names = { '--core': 'core', '--watch': 'watch', '--catalog': 'catalog', '--out': 'out' };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--check') opts.check = true;
    else if (names[a]) {
      if (i + 1 >= argv.length) throw new CatalogError('catalog', 0, `${a} needs a value`);
      opts[names[a]] = resolve(argv[(i += 1)]);
    } else throw new CatalogError('catalog', 0, `unknown option ${a}`);
  }
  return opts;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  for (const file of [opts.core, opts.watch, opts.catalog]) {
    if (!existsSync(file)) throw new CatalogError(shown(file), 0, 'the file does not exist');
  }
  const { outputs } = generate(opts);
  emitOutputs('catalog', outputs, opts.check);
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  try {
    main();
  } catch (e) {
    if (e instanceof CatalogError) {
      console.error(`catalog: ${e.message}`);
      process.exit(1);
    }
    throw e;
  }
}
