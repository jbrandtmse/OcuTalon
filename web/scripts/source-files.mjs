// The listing of the page's source files that the source ratchets read (announce-focus-sources.test.mjs, floor-sources.test.mjs): every
// file of a folder by its extension, with its text and its code, which is the text without its comments. No test of its own: the two
// ratchets pin it, and announce-focus-sources.test.mjs checks that it strips comments and keeps an address.
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

/** The files under a folder whose names end with one of the extensions (for example ['.ts', '.html']), as paths. */
export function listFiles(dir, extensions) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return listFiles(path, extensions);
    return extensions.some((extension) => entry.name.endsWith(extension)) ? [path] : [];
  });
}

/** A source without its comments: block comments, HTML comments and line comments (a `//` after white space, so an address stays). */
export const code = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '').replace(/(^|\s)\/\/.*$/gm, '$1');

/** The files under a folder with one of the extensions, each as its name (relative to the folder, with `/`), its text and its code. */
export function sourceFiles(root, extensions) {
  return listFiles(root, extensions).map((path) => {
    const text = readFileSync(path, 'utf8');
    return { name: relative(root, path).split('\\').join('/'), text, code: code(text) };
  });
}
