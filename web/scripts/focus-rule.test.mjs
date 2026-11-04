// Tests the page's one focus rule (src/app/shared/focus-rule.ts, Story 2.12; NFR-25, UX-DR126, UX-DR131) on a small fake DOM: it
// moves focus only when an update removed the element that held it, to the item that is still there, to what the rule names when
// the item is gone, or else to the main region, and always without scrolling. The browser cases (P1 to P4, B13, R9) pin the hosts'
// own rules against the real page; this pins every branch of the helper itself, including the ones no page can reach on demand.
// The module is imported as it is. Its one runtime import, Angular's afterNextRender, is replaced for this process by a resolve hook
// that queues the callback, and the test plays the render by calling the queued callbacks (flushRender). The fake DOM answers only
// what the helper asks: contains, closest, querySelector(All), getAttribute and focus.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { registerHooks } from 'node:module';
import { dirname, join } from 'node:path';
import { beforeEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'shared', 'focus-rule.ts');

const STUB = 'data:text/javascript,' + encodeURIComponent('export function afterNextRender(callback, options) { (globalThis.__renders ??= []).push({ callback, options }); }');
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === '@angular/core') return { url: STUB, shortCircuit: true, format: 'module' };
    return nextResolve(specifier, context);
  },
  // The module is TypeScript with an import: say so, instead of letting Node find out by parsing it as CommonJS first.
  load(url, context, nextLoad) {
    return nextLoad(url, url === pathToFileURL(source).href ? { ...context, format: 'module-typescript' } : context);
  },
});

/** The selector forms the page's rules use: a tag, then any of .class, #id, [attribute] and [attribute="value"], with no combinator. */
const COMPOUND = /^([a-z][a-z0-9-]*)?((?:\.[\w-]+|#[\w-]+|\[[\w-]+(?:="[^"]*")?\])*)$/;
const PART = /\.([\w-]+)|#([\w-]+)|\[([\w-]+)(?:="([^"]*)")?\]/g;

/** An element of the fake document. */
class FakeElement {
  constructor(tag, attributes = {}) {
    this.tag = tag;
    this.attributes = { ...attributes };
    this.children = [];
    this.parent = null;
    this.focusCalls = [];
  }

  append(...kids) {
    for (const kid of kids) {
      kid.parent?.remove(kid);
      kid.parent = this;
      this.children.push(kid);
    }
    return this;
  }

  /** Detaches a child; focus that was on it or in it falls to the body, as a browser does. */
  remove(kid) {
    const at = this.children.indexOf(kid);
    assert.ok(at >= 0, 'the element is a child');
    this.children.splice(at, 1);
    if (kid.contains(document.activeElement)) document.activeElement = document.body;
    kid.parent = null;
  }

  /** Replaces a child with another element at the same place. */
  replace(kid, other) {
    const at = this.children.indexOf(kid);
    this.remove(kid);
    other.parent?.remove(other);
    other.parent = this;
    this.children.splice(at, 0, other);
  }

  contains(other) {
    for (let node = other; node; node = node.parent) if (node === this) return true;
    return false;
  }

  getAttribute(name) {
    return Object.hasOwn(this.attributes, name) ? this.attributes[name] : null;
  }

  matches(selector) {
    const compound = COMPOUND.exec(selector);
    assert.ok(compound, `the fake DOM supports only compound selectors, not "${selector}"`);
    if (compound[1] !== undefined && compound[1] !== this.tag) return false;
    for (const [, className, id, name, value] of compound[2].matchAll(PART)) {
      if (className !== undefined && !(this.attributes['class'] ?? '').split(/\s+/).includes(className)) return false;
      if (id !== undefined && this.attributes['id'] !== id) return false;
      if (name !== undefined && (!Object.hasOwn(this.attributes, name) || (value !== undefined && this.attributes[name] !== value))) return false;
    }
    return true;
  }

  closest(selector) {
    for (let node = this; node; node = node.parent) if (node.matches(selector)) return node;
    return null;
  }

  querySelectorAll(selector) {
    const found = [];
    const walk = (node) => {
      for (const kid of node.children) {
        if (kid.matches(selector)) found.push(kid);
        walk(kid);
      }
    };
    walk(this);
    return found;
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  get focusable() {
    return ['button', 'a', 'input', 'textarea'].includes(this.tag) || Object.hasOwn(this.attributes, 'tabindex');
  }

  /** Like a browser: only a focusable element in the page takes focus. */
  focus(options) {
    this.focusCalls.push(options);
    if (this.focusable && document.documentElement.contains(this)) document.activeElement = this;
  }
}

const document = { documentElement: new FakeElement('html'), body: new FakeElement('body'), activeElement: null };
document.documentElement.append(document.body);
document.querySelector = (selector) => document.documentElement.querySelector(selector);
globalThis.document = document;
globalThis.Element = FakeElement;
globalThis.HTMLElement = FakeElement;

const { keepFocus } = await import(pathToFileURL(source).href);

/** An element with attributes and children. */
const el = (tag, attributes = {}, ...kids) => new FakeElement(tag, attributes).append(...kids);

/** The queued afterNextRender callbacks, which the test runs once the update has been applied. */
const queued = () => globalThis.__renders ?? [];
const flushRender = () => {
  const renders = queued().splice(0);
  for (const { callback } of renders) callback();
  return renders;
};

const INJECTOR = { name: 'the host\'s injector' };
const NO_POPOVERS = { triggerOf: () => undefined };

/** The rule of a list of keyed items, like the banner stack's and the rail's: the heading of the list when an item is gone. */
const LIST_RULE = {
  item: '[data-key]',
  keyOf: (item) => item.getAttribute('data-key') ?? '',
  whenGone: ({ host }) => host.querySelector('#heading'),
};

/** A page: a main region, a host with a heading and the keyed items, and a control outside the host. */
function page(keys = ['a', 'b', 'c']) {
  document.body.children.length = 0;
  document.activeElement = document.body;
  globalThis.__renders = [];
  const heading = el('h3', { id: 'heading', tabindex: '-1' });
  const items = keys.map((key) => el('li', { 'data-key': key, tabindex: '-1' }, el('button', { id: `button-${key}` })));
  const host = el('section', { class: 'host' }, heading, ...items);
  const outside = el('button', { id: 'outside' });
  const main = el('main', { class: 'main', tabindex: '-1' });
  document.body.append(outside, host, main);
  const buttons = Object.fromEntries(keys.map((key, i) => [key, items[i].children[0]]));
  const byKey = Object.fromEntries(keys.map((key, i) => [key, items[i]]));
  return { heading, items: byKey, buttons, host, outside, main };
}

/** Where focus is, as a word. */
const where = () => document.activeElement.attributes['id'] ?? document.activeElement.attributes['data-key'] ?? document.activeElement.tag;

beforeEach(() => {
  globalThis.__renders = [];
});

describe('when the rule does nothing', () => {
  it('does not wait for a render while focus is on the body', () => {
    const { host } = page();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    assert.equal(queued().length, 0);
  });

  it('does not wait for a render while focus is outside the host, and leaves it lost if that element goes', () => {
    const { host, outside, main } = page();
    outside.focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    assert.equal(queued().length, 0, 'nothing is queued');
    outside.parent.remove(outside);
    flushRender();
    assert.equal(document.activeElement, document.body, 'focus that is not the host\'s is not the host\'s to restore');
    assert.deepEqual(main.focusCalls, []);
  });

  it('limits itself to `within`: focus in the host outside it is left alone, focus inside it is watched', () => {
    const { host, buttons, main } = page(['a']);
    const rule = { within: '.load-error' };
    buttons['a'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, rule);
    assert.equal(queued().length, 0, 'the button is in the host but not in .load-error');
    const error = el('div', { class: 'load-error' }, el('button', { id: 'retry' }));
    host.append(error);
    error.children[0].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, rule);
    assert.equal(queued().length, 1);
    host.remove(error);
    flushRender();
    assert.equal(where(), 'main', 'focus lost with the error goes to the main region');
    assert.deepEqual(main.focusCalls, [{ preventScroll: true }]);
  });

  it('never moves focus that is still on an element in the page, whatever the update did', () => {
    const { host, buttons, items, outside } = page();
    buttons['b'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    host.remove(items['a']);
    flushRender();
    assert.equal(where(), 'button-b', 'an item left, the focused one stays');
    assert.ok(Object.values(items).every((item) => item.focusCalls.length === 0));

    buttons['c'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    outside.focus();
    flushRender();
    assert.equal(where(), 'outside', 'focus that the user moved is not moved back');
    assert.deepEqual(items['c'].focusCalls, []);
  });

  it('does not touch a focus that is still there even if the focused element is replaced in the page by another that is focused', () => {
    const { host, buttons, items } = page(['a']);
    buttons['a'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    const next = el('button', { id: 'next' });
    items['a'].replace(buttons['a'], next);
    next.focus();
    flushRender();
    assert.equal(where(), 'next');
    assert.deepEqual(items['a'].focusCalls, []);
  });
});

describe('when an update removes the element that holds focus', () => {
  it('gives it to the item that is still there when only the control inside it went (Retry sending)', () => {
    const { host, buttons, items } = page();
    buttons['b'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    assert.equal(queued().length, 1);
    items['b'].remove(buttons['b']);
    assert.equal(document.activeElement, document.body, 'the update dropped focus to the body');
    flushRender();
    assert.equal(where(), 'b', 'the item took it');
    assert.deepEqual(items['b'].focusCalls, [{ preventScroll: true }], 'once, without scrolling');
  });

  it('gives it to the replacement in place: the new element with the same key', () => {
    const { host, buttons, items, heading } = page();
    buttons['b'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    const replacement = el('li', { 'data-key': 'b', tabindex: '-1' }, el('button', { id: 'new-b' }));
    host.replace(items['b'], replacement);
    flushRender();
    assert.equal(document.activeElement, replacement);
    assert.deepEqual(replacement.focusCalls, [{ preventScroll: true }]);
    assert.deepEqual(items['b'].focusCalls, [], 'not the element that left');
    assert.deepEqual(heading.focusCalls, []);
  });

  it('gives it to what the rule names when the item itself is gone, with the keys before and after in DOM order', () => {
    const { host, buttons, items, heading } = page(['a', 'b', 'c']);
    buttons['b'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, { ...LIST_RULE, whenGone: (lost) => (seen.push(lost), host.querySelector('#heading')) });
    const seen = [];
    host.remove(items['b']);
    host.append(el('li', { 'data-key': 'd', tabindex: '-1' }));
    flushRender();
    assert.equal(seen.length, 1);
    assert.equal(seen[0].host, host);
    assert.equal(seen[0].item, items['b'], 'the item that held focus, now detached');
    assert.equal(seen[0].key, 'b');
    assert.deepEqual(seen[0].before, ['a', 'b', 'c']);
    assert.deepEqual(seen[0].after, ['a', 'c', 'd']);
    assert.equal(document.activeElement, heading);
    assert.deepEqual(heading.focusCalls, [{ preventScroll: true }]);
  });

  it('gives it to the main region when the rule names nothing (null), or names nothing that can take it', () => {
    const { host, buttons, items, main } = page();
    buttons['b'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, { ...LIST_RULE, whenGone: () => null });
    host.remove(items['b']);
    flushRender();
    assert.equal(where(), 'main');
    assert.deepEqual(main.focusCalls, [{ preventScroll: true }]);

    const again = page();
    again.buttons['b'].focus();
    keepFocus(again.host, INJECTOR, NO_POPOVERS, { item: '[data-key]', keyOf: LIST_RULE.keyOf });
    again.host.remove(again.items['b']);
    flushRender();
    assert.equal(where(), 'main', 'a rule with an item and no whenGone');

    const third = page();
    delete third.items['b'].attributes['tabindex'];
    third.buttons['b'].focus();
    keepFocus(third.host, INJECTOR, NO_POPOVERS, LIST_RULE);
    third.items['b'].remove(third.buttons['b']);
    flushRender();
    assert.deepEqual(third.items['b'].focusCalls, [{ preventScroll: true }], 'the item that is still there is asked first');
    assert.equal(where(), 'main', 'and, as it cannot take focus (a rail row has no tabindex), the main region takes it');
  });

  it('gives it to the main region when the rule has no item, as the load error\'s does', () => {
    const { host, main } = page([]);
    const error = el('div', { class: 'load-error' }, el('button', { id: 'retry' }));
    host.append(error);
    error.children[0].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, { within: '.load-error' });
    host.remove(error);
    flushRender();
    assert.equal(where(), 'main');
    assert.deepEqual(main.focusCalls, [{ preventScroll: true }]);
  });

  it('gives it to the main region when focus was in the host but in none of its items', () => {
    const { host, main } = page(['a']);
    const field = el('textarea', { id: 'field' });
    host.append(field);
    field.focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    host.remove(field);
    flushRender();
    assert.equal(where(), 'main');
    assert.deepEqual(main.focusCalls, [{ preventScroll: true }]);
  });

  it('treats a lost focus of null like the body', () => {
    const { host, buttons, items } = page();
    buttons['a'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    items['a'].remove(buttons['a']);
    document.activeElement = null;
    flushRender();
    assert.equal(where(), 'a');
  });

  it('does not take an ancestor of the host for the item that held focus', () => {
    const { host, buttons, main } = page(['a']);
    const wrapper = el('div', { 'data-key': 'outer' });
    document.body.replace(host, wrapper);
    wrapper.append(host);
    buttons['a'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, { item: '[data-key="outer"]', keyOf: LIST_RULE.keyOf, whenGone: () => wrapper });
    host.remove(host.children[1]);
    flushRender();
    assert.equal(where(), 'main', 'no item inside the host, so no item');
    assert.deepEqual(wrapper.focusCalls, []);
    assert.deepEqual(main.focusCalls, [{ preventScroll: true }]);
  });

  it('does nothing, and does not fail, when there is no main region and nothing else takes it', () => {
    const { host, buttons, items, main } = page();
    document.body.remove(main);
    buttons['a'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, { ...LIST_RULE, whenGone: () => null });
    host.remove(items['a']);
    flushRender();
    assert.equal(document.activeElement, document.body);
  });

  it('is told the injector of the host, so that the render it waits for is the host\'s', () => {
    const { host, buttons } = page();
    buttons['a'].focus();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    assert.equal(queued()[0].options.injector, INJECTOR);
  });
});

describe('a popover\'s focus', () => {
  /** A row whose trace help popover (a dialog in the page\'s overlay, outside the host) holds focus. */
  function withHelp() {
    const world = page(['a', 'b']);
    const trigger = el('a', { id: 'trace', href: '#' });
    world.items['b'].append(trigger);
    const pane = el('div', { id: 'pane', role: 'dialog' }, el('button', { id: 'got-it' }));
    document.body.append(pane);
    pane.children[0].focus();
    const popovers = { triggerOf: (element) => (pane.contains(element) ? trigger : undefined) };
    return { ...world, trigger, pane, popovers };
  }

  it('counts as focus on its trigger: the row that leaves with its help open is a row that leaves', () => {
    const { host, items, heading, pane, popovers } = withHelp();
    keepFocus(host, INJECTOR, popovers, LIST_RULE);
    assert.equal(queued().length, 1, 'focus in the pane, outside the host, is the trigger\'s');
    host.remove(items['b']);
    document.body.remove(pane);
    assert.equal(document.activeElement, document.body);
    flushRender();
    assert.equal(document.activeElement, heading);
  });

  it('is left alone when the popover is not the host\'s: focus in a pane whose trigger is outside the host', () => {
    const { host, outside } = withHelp();
    keepFocus(host, INJECTOR, { triggerOf: () => outside }, LIST_RULE);
    assert.equal(queued().length, 0);
  });

  it('is ordinary focus when no popover holds it', () => {
    const { host } = withHelp();
    keepFocus(host, INJECTOR, NO_POPOVERS, LIST_RULE);
    assert.equal(queued().length, 0, 'focus in a pane that no popover owns is not in the host');
  });
});

describe('the module', () => {
  it('imports only Angular\'s afterNextRender and types, keeps to erasable syntax and is ASCII', () => {
    const text = readFileSync(source, 'utf8');
    const imports = text.match(/^\s*import\s.*$/gm) ?? [];
    assert.deepEqual(imports.map((line) => line.trim()), ["import { afterNextRender, type Injector } from '@angular/core';", "import type { Popovers } from './popover';"]);
    assert.doesNotMatch(text, /\benum\b|\bnamespace\b/, 'no enum and no namespace');
    assert.doesNotMatch(text, /constructor\s*\([^)]*\b(?:private|public|protected|readonly)\s/, 'no parameter property');
    assert.doesNotMatch(text, /[^\x00-\x7F]/, 'non-ASCII characters are written as escapes');
  });

  it('moves focus only with preventScroll, in its one focus call', () => {
    const text = readFileSync(source, 'utf8');
    const calls = text.match(/\.focus\([^)]*\)/g) ?? [];
    assert.deepEqual(calls, ['.focus({ preventScroll: true })']);
  });
});
