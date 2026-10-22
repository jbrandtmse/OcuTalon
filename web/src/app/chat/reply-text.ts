/**
 * The reply text of a done turn as blocks of runs: what the model wrote, parsed for plain paragraphs, two kinds of list and
 * http(s) links, and nothing else (UX-DR60, AD-13). Every other character is text, so `<`, `*`, `#` and backticks show as
 * typed; the page binds the runs by interpolation and `[href]`, never as HTML. A framework-free module: it imports nothing and
 * uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - A paragraph is the lines between blank lines, with its single line breaks kept (a run's text holds "\n").
 * - A list is consecutive lines that start with `- `, `* ` or the bullet U+2022 and a space (bulleted), or with `1. ` or `1) ` (numbered). A line of
 *   the other kind, or a line that is no list line, ends the list. A numbered list keeps its first number.
 * - A link is a bare `http://` or `https://` address, without the `.,;:!?` or the unmatched `)` that ends it, or
 *   `[label](http(s)://address)`. A link whose scheme is not http(s) is text.
 */

/** A piece of a paragraph or of a list item. */
export type Run = { kind: 'text'; text: string } | { kind: 'link'; href: string; label: string };

/** A paragraph, or a list whose items are runs. start is the number of a numbered list's first item. */
export type ReplyBlock =
  | { kind: 'paragraph'; runs: Run[] }
  | { kind: 'list'; ordered: boolean; start: number; items: Run[][] };

const BULLET = /^[ \t]*[-*\u2022][ \t]+(\S.*)$/;
const NUMBER = /^[ \t]*(\d{1,9})[.)][ \t]+(\S.*)$/;
const LINK = /\[([^[\]\n]+)\]\((https?:\/\/(?:[^\s()]|\([^\s()]*\))+)\)|(https?:\/\/[^\s<>]+)/gi;
const ENDING = '.,;:!?';

/** How many times `char` occurs in `text`. */
const count = (text: string, char: string): number => text.split(char).length - 1;

/** The address without what ends a sentence rather than the address; the rest is what was trimmed off. */
function trimAddress(address: string): { href: string; rest: string } {
  let href = address;
  for (;;) {
    const last = href.slice(-1);
    if (ENDING.includes(last) || (last === ')' && count(href, ')') > count(href, '('))) {
      href = href.slice(0, -1);
    } else {
      break;
    }
  }
  return { href, rest: address.slice(href.length) };
}

/** True for an address the browser can open as an http(s) link. */
function isWebAddress(href: string): boolean {
  try {
    const url = new URL(href);
    return (url.protocol === 'http:' || url.protocol === 'https:') && url.hostname !== '';
  } catch {
    return false;
  }
}

/** The runs of a text: its links found, everything else text, adjacent text joined. */
export function parseRuns(text: string): Run[] {
  const runs: Run[] = [];
  const addText = (value: string): void => {
    if (value === '') {
      return;
    }
    const last = runs[runs.length - 1];
    if (last?.kind === 'text') {
      last.text += value;
    } else {
      runs.push({ kind: 'text', text: value });
    }
  };
  let at = 0;
  for (const match of text.matchAll(LINK)) {
    const start = match.index;
    addText(text.slice(at, start));
    at = start + match[0].length;
    if (match[2] !== undefined) {
      if (isWebAddress(match[2])) {
        runs.push({ kind: 'link', href: match[2], label: match[1] ?? match[2] });
      } else {
        addText(match[0]);
      }
      continue;
    }
    const { href, rest } = trimAddress(match[3] ?? '');
    if (isWebAddress(href)) {
      runs.push({ kind: 'link', href, label: href });
      addText(rest);
    } else {
      addText(match[0]);
    }
  }
  addText(text.slice(at));
  return runs;
}

/** The reply text as blocks; text that is empty or only blank lines gives none. */
export function parseReply(text: string): ReplyBlock[] {
  const blocks: ReplyBlock[] = [];
  let lines: string[] = [];
  let list: Extract<ReplyBlock, { kind: 'list' }> | undefined;
  const endParagraph = (): void => {
    if (lines.length > 0) {
      blocks.push({ kind: 'paragraph', runs: parseRuns(lines.join('\n')) });
      lines = [];
    }
  };
  for (const line of text.replace(/\r\n?/g, '\n').split('\n')) {
    if (line.trim() === '') {
      endParagraph();
      list = undefined;
      continue;
    }
    const bullet = BULLET.exec(line);
    const number = bullet ? null : NUMBER.exec(line);
    if (!bullet && !number) {
      list = undefined;
      lines.push(line);
      continue;
    }
    endParagraph();
    const ordered = number !== null;
    if (list === undefined || list.ordered !== ordered) {
      list = { kind: 'list', ordered, start: number ? Number(number[1]) : 1, items: [] };
      blocks.push(list);
    }
    list.items.push(parseRuns((bullet ? bullet[1] : number?.[2]) ?? ''));
  }
  endParagraph();
  return blocks;
}
