// What the stack-free pins of the repo's ObjectScript classes and of ci/iris.sh read (flake-fixes-sources.test.mjs,
// flake-fixes-behaviour.test.mjs, state-wait.test.mjs): a file of the repo by its path, one method of a class's source, and the
// bash line that defines one function of a script. No test of its own: those three pin it.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** The repo's root folder. */
export const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** The text of a file of the repo, by its path from the root. */
export const readRepo = (path) => readFileSync(join(repoRoot, path), 'utf8');

/** The text of a class's `Method` or `ClassMethod` <name>, from its declaration to its closing brace (the source must have it). */
export function clsMethod(source, name) {
  const start = source.search(new RegExp(`^(?:Class)?Method ${name}\\(`, 'm'));
  if (start === -1) throw new Error(`${name} exists`);
  const rest = source.slice(start);
  return rest.slice(0, rest.search(/^\}/m));
}

/** A bash line that defines the script's function <name> (from its `<name>() {` line to the first `}` line) in the shell that runs it. */
export const shellFunction = (script, name) => `eval "$(sed -n '/^${name}() {/,/^}/p' ${JSON.stringify(script)})"`;
