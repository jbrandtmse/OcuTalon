#!/usr/bin/env node
// Turns the front matter of DESIGN.md into the app's token stylesheet and into the sign-in page's
// inline assets. Dependency-free.
//
//   node scripts/tokens.mjs            writes src/styles/tokens.css and SignInAssets.cls
//   node scripts/tokens.mjs --check    writes nothing; exits 1 when either file differs from its fresh output
//
// Options: --design <file> --css-out <file> --cls-out <file> --signin-css <file> --signin-js <file>
// (the defaults are the repository's own files; tests point them at fixtures).
//
// The front matter shape this reads (anything else is refused with the line number):
//   - indentation of 0, 2 or 4 spaces, so at most 3 levels, and one-line values only;
//   - values are single-quoted strings, unquoted words, or numbers with units; '{group.key}' references may
//     stand alone or inside a compound string;
//   - full-line # comments (a # inside a quoted value is part of the value);
//   - no lists, flow style, anchors, tags, block scalars or double quotes.
// Every light colour has a <name>-dark. A component property <prop>-dark overrides <prop> in dark mode.
// The properties note, marker, halo and decoration are prose and are skipped.
//
// Output naming: --<color>, --type-<token>-<prop>, --rounded-<k>, --space-<k>, --<component>-<prop>; a component
// property that is a typography reference expands to --<component>-<prop>-<typography prop>. Dark values go
// under @media (prefers-color-scheme: dark) on :root:not([data-theme=light]) and again under [data-theme=dark].

import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');

export const PROSE = new Set(['note', 'marker', 'halo', 'decoration']);

export class TokenError extends Error {
  constructor(file, line, message) {
    super(line ? `${file}:${line}: ${message}` : `${file}: ${message}`);
    this.name = 'TokenError';
  }
}

// ---------------------------------------------------------------------------------------------------------
// Front matter

function parseValue(raw, file, line) {
  if (raw.startsWith("'")) {
    let out = '';
    let i = 1;
    for (;;) {
      if (i >= raw.length) throw new TokenError(file, line, 'unterminated single-quoted string');
      const c = raw[i];
      if (c === "'") {
        if (raw[i + 1] === "'") {
          out += "'";
          i += 2;
          continue;
        }
        i += 1;
        break;
      }
      out += c;
      i += 1;
    }
    if (raw.slice(i).trim() !== '') throw new TokenError(file, line, 'text after a quoted string (a trailing comment is not supported)');
    return out;
  }
  if (raw.startsWith('"')) throw new TokenError(file, line, 'unsupported YAML form: double-quoted string');
  if (/^[|>]/.test(raw)) throw new TokenError(file, line, 'unsupported YAML form: block scalar');
  if (/^[[{]/.test(raw)) throw new TokenError(file, line, 'unsupported YAML form: flow style');
  if (/^[&*!]/.test(raw)) throw new TokenError(file, line, 'unsupported YAML form: anchor, alias or tag');
  if (/\s#/.test(raw)) throw new TokenError(file, line, 'unsupported YAML form: trailing comment');
  if (/:(\s|$)/.test(raw)) throw new TokenError(file, line, 'unsupported YAML form: a mapping inside a value');
  return raw.trim();
}

function parseKey(raw) {
  return raw.startsWith("'") ? raw.slice(1, -1).replace(/''/g, "'") : raw;
}

/**
 * Parses the front matter into a Map of nodes. A node is { line, value } for a scalar or { line, children }
 * for a map, where children is a Map of nodes in file order.
 */
export function parseFrontMatter(text, file = 'DESIGN.md') {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== '---') throw new TokenError(file, 1, 'the file must start with a --- line');
  let end = -1;
  for (let i = 1; i < lines.length; i += 1) {
    if (lines[i] === '---') {
      end = i;
      break;
    }
  }
  if (end < 0) throw new TokenError(file, 1, 'the front matter has no closing --- line');

  const root = new Map();
  const stack = [{ map: root, node: null }];
  for (let i = 1; i < end; i += 1) {
    const lineNo = i + 1;
    const rawLine = lines[i].replace(/\s+$/, '');
    if (rawLine.trim() === '' || rawLine.trim().startsWith('#')) continue;
    if (/\t/.test(rawLine.match(/^\s*/)[0])) throw new TokenError(file, lineNo, 'tab indentation is not supported');
    const indent = rawLine.match(/^ */)[0].length;
    if (indent % 2 !== 0 || indent > 4) throw new TokenError(file, lineNo, 'indentation must be 0, 2 or 4 spaces');
    const level = indent / 2;
    const content = rawLine.slice(indent);
    if (content === '-' || content.startsWith('- ')) throw new TokenError(file, lineNo, 'unsupported YAML form: list');
    const m = /^('(?:[^']|'')*'|[A-Za-z0-9][A-Za-z0-9._-]*)[ ]*:(?:[ ]+(.*))?$/.exec(content);
    if (!m) throw new TokenError(file, lineNo, `unsupported YAML form: ${content.slice(0, 40)}`);
    if (level >= stack.length || !stack[level]) throw new TokenError(file, lineNo, 'unexpected indentation');
    const key = parseKey(m[1]);
    const parent = stack[level];
    if (parent.map.has(key)) throw new TokenError(file, lineNo, `duplicate key '${key}'`);
    stack.length = level + 1;
    if (m[2] === undefined) {
      const node = { line: lineNo, children: new Map() };
      parent.map.set(key, node);
      stack[level + 1] = { map: node.children, node };
    } else {
      parent.map.set(key, { line: lineNo, value: parseValue(m[2], file, lineNo) });
    }
  }
  const walk = (map) => {
    for (const [key, node] of map) {
      if (node.children) {
        if (node.children.size === 0) throw new TokenError(file, node.line, `'${key}' has no entries`);
        walk(node.children);
      }
    }
  };
  walk(root);
  return root;
}

// ---------------------------------------------------------------------------------------------------------
// Model

const kebab = (s) => s.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

function group(root, name, file) {
  const node = root.get(name);
  if (!node || !node.children) throw new TokenError(file, 0, `the front matter has no '${name}' group`);
  return node.children;
}

function scalarMap(map, file, what) {
  const out = new Map();
  for (const [key, node] of map) {
    if (node.children) throw new TokenError(file, node.line, `${what} '${key}' must be a single value`);
    out.set(key, { value: node.value, line: node.line });
  }
  return out;
}

export function buildModel(root, file = 'DESIGN.md') {
  const colorsRaw = scalarMap(group(root, 'colors', file), file, 'colour');
  const colors = [];
  const darkOf = new Map();
  for (const [name, { value, line }] of colorsRaw) {
    if (!/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(value)) throw new TokenError(file, line, `colour '${name}' is not #RRGGBB or #RRGGBBAA`);
    if (name.endsWith('-dark')) darkOf.set(name.slice(0, -5), { value, line });
  }
  for (const [name, { value, line }] of colorsRaw) {
    if (name.endsWith('-dark')) continue;
    const dark = darkOf.get(name);
    if (!dark) throw new TokenError(file, line, `colour '${name}' has no '${name}-dark'`);
    colors.push({ name, light: value, dark: dark.value, line });
  }
  for (const [name, { line }] of darkOf) {
    if (!colorsRaw.has(name)) throw new TokenError(file, line, `colour '${name}-dark' has no '${name}'`);
  }

  const typography = new Map();
  for (const [token, node] of group(root, 'typography', file)) {
    if (!node.children) throw new TokenError(file, node.line, `typography '${token}' must be a group`);
    typography.set(token, scalarMap(node.children, file, `typography property of '${token}'`));
  }
  const rounded = scalarMap(group(root, 'rounded', file), file, 'rounded');
  const spacing = scalarMap(group(root, 'spacing', file), file, 'spacing');
  const components = new Map();
  for (const [name, node] of group(root, 'components', file)) {
    if (!node.children) throw new TokenError(file, node.line, `component '${name}' must be a group`);
    components.set(name, scalarMap(node.children, file, `property of component '${name}'`));
  }
  return {
    file,
    colors,
    typography,
    rounded,
    spacing,
    components,
    counts: {
      colors: colorsRaw.size,
      colorPairs: colors.length,
      typography: typography.size,
      rounded: rounded.size,
      spacing: spacing.size,
      components: components.size,
    },
  };
}

function resolveText(model, value, mode, line) {
  const out = value.replace(/\{([^{}]*)\}/g, (all, ref) => {
    const parts = ref.split('.');
    const bad = () => new TokenError(model.file, line, `unresolved reference ${all}`);
    if (parts.length !== 2) throw bad();
    const [g, k] = parts;
    if (g === 'colors') {
      const explicitDark = k.endsWith('-dark') ? model.colors.find((e) => e.name === k.slice(0, -5)) : undefined;
      if (explicitDark) return explicitDark.dark;
      const c = model.colors.find((e) => e.name === k);
      if (!c) throw bad();
      return mode === 'dark' ? c.dark : c.light;
    }
    if (g === 'rounded' || g === 'spacing') {
      const entry = model[g].get(k);
      if (!entry) throw bad();
      return entry.value;
    }
    if (g === 'typography' && model.typography.has(k)) {
      throw new TokenError(model.file, line, `typography reference ${all} must be the whole value`);
    }
    throw bad();
  });
  if (/[{}]/.test(out)) throw new TokenError(model.file, line, `unresolved reference in '${value}'`);
  return out;
}

/** The [name, value] pairs of one mode, in a fixed order. Both modes list the same names. */
export function tokenEntries(model, mode) {
  const out = [];
  for (const c of model.colors) out.push([c.name, mode === 'dark' ? c.dark : c.light]);
  for (const [token, props] of model.typography) {
    for (const [prop, { value, line }] of props) {
      out.push([`type-${token}-${kebab(prop)}`, resolveText(model, value, mode, line)]);
    }
  }
  for (const [k, { value, line }] of model.rounded) out.push([`rounded-${k}`, resolveText(model, value, mode, line)]);
  for (const [k, { value, line }] of model.spacing) out.push([`space-${k}`, resolveText(model, value, mode, line)]);
  for (const [comp, props] of model.components) {
    for (const [prop, { value, line }] of props) {
      if (PROSE.has(prop)) continue;
      if (prop.endsWith('-dark')) {
        if (!props.has(prop.slice(0, -5))) throw new TokenError(model.file, line, `'${prop}' of '${comp}' has no '${prop.slice(0, -5)}'`);
        continue;
      }
      const own = mode === 'dark' && props.has(`${prop}-dark`) ? props.get(`${prop}-dark`) : { value, line };
      const whole = /^\{typography\.([^{}.]+)\}$/.exec(own.value);
      if (whole) {
        const t = model.typography.get(whole[1]);
        if (!t) throw new TokenError(model.file, own.line, `unresolved reference ${own.value}`);
        for (const [tprop, tv] of t) out.push([`${comp}-${prop}-${kebab(tprop)}`, tv.value]);
      } else {
        out.push([`${comp}-${prop}`, resolveText(model, own.value, mode, own.line)]);
      }
    }
  }
  const seen = new Set();
  for (const [name] of out) {
    if (seen.has(name)) throw new TokenError(model.file, 0, `two tokens are named --${name}`);
    seen.add(name);
  }
  return out;
}

function darkDifferences(model) {
  const light = tokenEntries(model, 'light');
  const dark = tokenEntries(model, 'dark');
  return { light, dark: dark.filter(([name, value], i) => light[i][0] === name && light[i][1] !== value) };
}

// ---------------------------------------------------------------------------------------------------------
// Output

const block = (indent, entries) => entries.map(([n, v]) => `${indent}--${n}: ${v};\n`).join('');

export function renderTokensCss(model) {
  const { light, dark } = darkDifferences(model);
  return (
    '/* Generated by web/scripts/tokens.mjs from DESIGN.md. Never edit: npm --prefix web run tokens rewrites it. */\n' +
    `:root {\n${block('  ', light)}}\n` +
    '@media (prefers-color-scheme: dark) {\n' +
    `  :root:not([data-theme=light]) {\n${block('    ', dark)}  }\n` +
    '}\n' +
    `:root[data-theme=dark] {\n${block('  ', dark)}}\n`
  );
}

export function minifyCss(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/ ?([{};,>]) ?/g, '$1')
    .replace(/ ?: ?/g, ':')
    .replace(/;}/g, '}');
}

export function minifyScript(source, file = 'signin.js') {
  const stripped = source.replace(/\/\*[\s\S]*?\*\//g, '');
  const at = stripped.search(/\/\//);
  if (at >= 0) {
    const lineNo = stripped.slice(0, at).split('\n').length;
    throw new TokenError(file, lineNo, 'a // comment is not supported: use /* */ so lines can be joined');
  }
  return stripped.replace(/\s+/g, ' ').trim();
}

function assertAscii(text, file, what) {
  const m = /[^\x20-\x7e\n\r\t]/.exec(text);
  if (m) {
    const lineNo = text.slice(0, m.index).split('\n').length;
    throw new TokenError(file, lineNo, `${what} holds a character that is not printable ASCII (code ${text.charCodeAt(m.index)})`);
  }
}

const cosString = (s) => `"${s.replace(/"/g, '""')}"`;

export function renderSignInAssets(model, signinCss, signinJs, files = {}) {
  const cssFile = files.css ?? 'signin.css';
  const jsFile = files.js ?? 'signin.js';
  assertAscii(signinCss, cssFile, 'the stylesheet');
  assertAscii(signinJs, jsFile, 'the script');
  const { light, dark } = darkDifferences(model);
  const known = new Set(light.map(([n]) => n));
  const used = new Set();
  const code = signinCss.replace(/\/\*[\s\S]*?\*\//g, (c) => c.replace(/[^\n]/g, ' '));
  const re = /var\(\s*--([A-Za-z0-9-]+)/g;
  let m;
  while ((m = re.exec(code)) !== null) {
    if (!known.has(m[1])) {
      throw new TokenError(cssFile, code.slice(0, m.index).split('\n').length, `var(--${m[1]}) is not a token`);
    }
    used.add(m[1]);
  }
  const pick = (entries) => entries.filter(([n]) => used.has(n)).map(([n, v]) => `--${n}:${v}`).join(';');
  const lightVars = pick(light);
  const darkVars = pick(dark);
  const css =
    `:root{${lightVars}}` +
    (darkVars ? `@media(prefers-color-scheme:dark){:root{${darkVars}}}` : '') +
    minifyCss(signinCss);
  const script = minifyScript(signinJs, jsFile);
  return (
    "/// The sign-in page's inline stylesheet and script, generated by web/scripts/tokens.mjs from DESIGN.md,\n" +
    '/// web/src/signin/signin.css and web/src/signin/signin.js. Never edited by hand: npm --prefix web run tokens rewrites it.\n' +
    '/// Login hashes both parameters for its Content-Security-Policy header.\n' +
    'Class OcuTalon.Web.Public.SignInAssets\n{\n\n' +
    '/// The minified stylesheet: the custom properties it uses (light, then dark through prefers-color-scheme), then its rules.\n' +
    `Parameter CSS = ${cosString(css)};\n\n` +
    '/// The script that toggles the password field.\n' +
    `Parameter SCRIPT = ${cosString(script)};\n\n` +
    'ClassMethod Css() As %String\n{\n\tQuit ..#CSS\n}\n\n' +
    'ClassMethod Script() As %String\n{\n\tQuit ..#SCRIPT\n}\n\n}\n'
  );
}

// ---------------------------------------------------------------------------------------------------------
// Command line

function parseArgs(argv) {
  const opts = {
    check: false,
    design: resolve(repoRoot, '_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/DESIGN.md'),
    cssOut: resolve(repoRoot, 'web/src/styles/tokens.css'),
    clsOut: resolve(repoRoot, 'src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls'),
    signinCss: resolve(repoRoot, 'web/src/signin/signin.css'),
    signinJs: resolve(repoRoot, 'web/src/signin/signin.js'),
  };
  const names = { '--design': 'design', '--css-out': 'cssOut', '--cls-out': 'clsOut', '--signin-css': 'signinCss', '--signin-js': 'signinJs' };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--check') opts.check = true;
    else if (names[a]) {
      if (i + 1 >= argv.length) throw new TokenError('tokens', 0, `${a} needs a value`);
      opts[names[a]] = resolve(argv[(i += 1)]);
    } else throw new TokenError('tokens', 0, `unknown option ${a}`);
  }
  return opts;
}

export function generate(opts) {
  const name = (p) => relative(process.cwd(), p) || p;
  const text = readFileSync(opts.design, 'utf8');
  const model = buildModel(parseFrontMatter(text, name(opts.design)), name(opts.design));
  const tokensCss = renderTokensCss(model);
  const assets = renderSignInAssets(model, readFileSync(opts.signinCss, 'utf8'), readFileSync(opts.signinJs, 'utf8'), {
    css: name(opts.signinCss),
    js: name(opts.signinJs),
  });
  return { model, outputs: [[opts.cssOut, tokensCss], [opts.clsOut, assets]] };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const { outputs } = generate(opts);
  if (opts.check) {
    const stale = outputs.filter(([file, text]) => !existsSync(file) || readFileSync(file, 'utf8') !== text);
    if (stale.length > 0) {
      for (const [file] of stale) console.error(`tokens: ${relative(process.cwd(), file) || file} is stale: run npm --prefix web run tokens`);
      process.exit(1);
    }
    console.log('tokens: generated files are current');
    return;
  }
  for (const [file, text] of outputs) {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, text);
    console.log(`tokens: wrote ${relative(process.cwd(), file) || file}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  try {
    main();
  } catch (e) {
    if (e instanceof TokenError) {
      console.error(`tokens: ${e.message}`);
      process.exit(1);
    }
    throw e;
  }
}
