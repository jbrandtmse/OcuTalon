// Tests the parse of a model's reply text (src/app/chat/reply-text.ts) into paragraphs, lists and links: blank lines and
// single line breaks, the two kinds of list, bare and bracketed http(s) links, and that every other character stays text
// (HTML-like text, a javascript: or data: link, Markdown the page does not render). The module is imported as it is.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { parseReply, plainText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'reply-text.ts')).href);

const text = (value) => ({ kind: 'text', text: value });
const link = (href, label = href, host = '') => ({ kind: 'link', href, label, host });
const para = (...runs) => ({ kind: 'paragraph', runs });
const list = (ordered, items, start = 1) => ({ kind: 'list', ordered, start, items });

describe('paragraphs', () => {
  it('splits at blank lines, which may hold spaces, and keeps a single line break', () => {
    assert.deepEqual(parseReply('one\ntwo\n\nthree'), [para(text('one\ntwo')), para(text('three'))]);
    assert.deepEqual(parseReply('a\n   \n\n\nb\n'), [para(text('a')), para(text('b'))]);
  });

  it('gives no block for empty text or only blank lines', () => {
    assert.deepEqual(parseReply(''), []);
    assert.deepEqual(parseReply('\n  \n\n'), []);
  });

  it('reads CRLF and CR as line breaks', () => {
    assert.deepEqual(parseReply('a\r\nb\r\n\r\nc'), [para(text('a\nb')), para(text('c'))]);
    assert.deepEqual(parseReply('- x\r\n- y\r\n\r\n1. z'), [list(false, [[text('x')], [text('y')]]), list(true, [[text('z')]])]);
  });
});

describe('lists', () => {
  it('reads -, * and the bullet U+2022 as one bulleted list', () => {
    assert.deepEqual(parseReply('- a\n* b\n\u2022 c'), [list(false, [[text('a')], [text('b')], [text('c')]])]);
  });

  it('reads 1. and 1) as one numbered list, which keeps its first number', () => {
    assert.deepEqual(parseReply('1. a\n2) b'), [list(true, [[text('a')], [text('b')]])]);
    assert.deepEqual(parseReply('3. c\n4. d'), [list(true, [[text('c')], [text('d')]], 3)]);
  });

  it('ends a list at a list of the other kind, a plain line or a blank line', () => {
    assert.deepEqual(parseReply('- a\n1. b'), [list(false, [[text('a')]]), list(true, [[text('b')]])]);
    assert.deepEqual(parseReply('Intro:\n- a\n- b\nafter'), [para(text('Intro:')), list(false, [[text('a')], [text('b')]]), para(text('after'))]);
    assert.deepEqual(parseReply('- a\n\n- b'), [list(false, [[text('a')]]), list(false, [[text('b')]])]);
  });

  it('does not take other lines for list lines', () => {
    for (const line of ['**bold** word', '-x', '1.5 is a number', '- ', '*', 'a - b']) {
      assert.deepEqual(parseReply(line), [para(text(line))], line);
    }
  });

  it('finds links in an item', () => {
    assert.deepEqual(parseReply('- see https://example.com/a.'), [list(false, [[text('see '), link('https://example.com/a'), text('.')]])]);
  });
});

describe('links', () => {
  it('links a bare address without the punctuation that ends a sentence', () => {
    assert.deepEqual(parseReply('See https://example.com/a.'), [para(text('See '), link('https://example.com/a'), text('.'))]);
    assert.deepEqual(parseReply('Try http://example.com/x?y=1&z=2, then stop'), [
      para(text('Try '), link('http://example.com/x?y=1&z=2'), text(', then stop')),
    ]);
    for (const end of ['.', ',', ';', ':', '!', '?']) {
      assert.deepEqual(parseReply(`go https://example.com${end}`), [para(text('go '), link('https://example.com'), text(end))], end);
    }
  });

  it('leaves an unmatched closing parenthesis out of the address, and keeps a balanced one in', () => {
    assert.deepEqual(parseReply('(see https://example.com/a).'), [para(text('(see '), link('https://example.com/a'), text(').'))]);
    assert.deepEqual(parseReply('https://en.wikipedia.org/wiki/Foo_(bar)'), [para(link('https://en.wikipedia.org/wiki/Foo_(bar)'))]);
    assert.deepEqual(parseReply('https://en.wikipedia.org/wiki/Foo_(bar).'), [para(link('https://en.wikipedia.org/wiki/Foo_(bar)'), text('.'))]);
  });

  it('links [label](https://address) with the label as its text and the host it opens', () => {
    assert.deepEqual(parseReply('Read [the docs](https://example.com/docs).'), [para(text('Read '), link('https://example.com/docs', 'the docs', 'example.com'), text('.'))]);
    assert.deepEqual(parseReply('[w](https://en.wikipedia.org/wiki/Foo_(bar)) ok'), [para(link('https://en.wikipedia.org/wiki/Foo_(bar)', 'w', 'en.wikipedia.org'), text(' ok'))]);
    assert.deepEqual(parseReply('[https://a.example](https://b.example)'), [para(link('https://b.example', 'https://a.example', 'b.example'))]);
  });

  it('names the host a labelled link opens, so a label cannot pass for another address', () => {
    assert.deepEqual(parseReply('[https://bank.example/login](https://evil.example/x)'), [para(link('https://evil.example/x', 'https://bank.example/login', 'evil.example'))]);
    assert.deepEqual(parseReply('[bank.example](https://bank.example:8443/a)'), [para(link('https://bank.example:8443/a', 'bank.example', 'bank.example:8443'))], 'the port is part of the host');
    assert.deepEqual(parseReply('[bank](https://b\u0430nk.example/)'), [para(link('https://b\u0430nk.example/', 'bank', 'xn--bnk-6cd.example'))], 'a non-ASCII name shows as punycode');
    assert.deepEqual(parseReply('[https://example.com/a](https://example.com/a)'), [para(link('https://example.com/a', 'https://example.com/a'))], 'a label that is the address needs no host');
    assert.deepEqual(parseReply('[Example.com](https://example.com/a)'), [para(link('https://example.com/a', 'Example.com'))], 'nor does a label that is its host');
  });

  it('reads the scheme without regard to case', () => {
    assert.deepEqual(parseReply('HTTPS://EXAMPLE.COM/A'), [para(link('HTTPS://EXAMPLE.COM/A'))]);
  });

  it('keeps the line break and the words around a link', () => {
    assert.deepEqual(parseReply('a\nhttps://example.com\nb'), [para(text('a\n'), link('https://example.com'), text('\nb'))]);
  });

  it('keeps a link whose scheme is not http(s) as text', () => {
    for (const source of ['[x](javascript:alert(1))', '[x](data:text/html,<b>x</b>)', 'javascript:alert(1)', 'ftp://example.com/a', 'mailto:a@example.com', '[x](//example.com)']) {
      assert.deepEqual(parseReply(source), [para(text(source))], source);
    }
    assert.deepEqual(parseReply('[x](javascript:alert(1)) and https://ok.example'), [para(text('[x](javascript:alert(1)) and '), link('https://ok.example'))]);
  });

  it('keeps an address that is no address as text', () => {
    assert.deepEqual(parseReply('https://'), [para(text('https://'))]);
    assert.deepEqual(parseReply('see https:// and more'), [para(text('see https:// and more'))]);
  });
});

describe('everything else is text', () => {
  it('shows HTML-like text, asterisks, hashes and backticks as typed', () => {
    for (const source of ['<img src=x onerror=alert(1)>', '<b>bold</b> <script>alert(1)</script>', '**bold** and *it* and `code`', '# Heading', '> quote', '[not a link]', '&lt;b&gt;']) {
      assert.deepEqual(parseReply(source), [para(text(source))], source);
    }
  });

  it('shows an address in angle brackets with the brackets as text', () => {
    assert.deepEqual(parseReply('<https://example.com>'), [para(text('<'), link('https://example.com'), text('>'))]);
  });
});

describe('the plain text of the first block', () => {
  it('is a paragraph\'s runs with each link as its label, and keeps the line breaks', () => {
    assert.equal(plainText(parseReply('See [the guide](https://example.com/g) first. Then https://example.com/x\nnext line\n\nsecond paragraph')), 'See the guide first. Then https://example.com/x\nnext line');
  });

  it('is the first item of a list, bulleted or numbered, with its links as labels', () => {
    assert.equal(plainText(parseReply('- first [item](https://example.com)\n- second')), 'first item');
    assert.equal(plainText(parseReply('3. numbered one\n4. two')), 'numbered one');
  });

  it('is the first block only, whatever follows', () => {
    assert.equal(plainText(parseReply('- a\n\nafter')), 'a');
    assert.equal(plainText(parseReply('before\n\n- a')), 'before');
  });

  it('is empty for no block', () => {
    assert.equal(plainText(parseReply('')), '');
    assert.equal(plainText([]), '');
  });
});
