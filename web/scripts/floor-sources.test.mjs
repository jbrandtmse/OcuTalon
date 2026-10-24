// Tests the rules of the page's accessibility floor that no single browser state shows (Story 2.14; NFR-25, UX-DR14, UX-DR125,
// UX-DR129, UX-DR134, UX-DR135), by reading every source under web/src/ (.ts, .js, .html and .css, comments left out):
//   keys     only Enter and Escape are handled: no single-character shortcut, no accesskey, no keyup or keypress handler;
//   Esc      one Esc acts on one layer: a shown tooltip takes it in the capture phase, a disclosure asks the popovers first;
//   heights  a height is a minimum: every fixed height of the app and the styles is on the list below, with its reason;
//   motion   nothing scrolls smoothly, nothing transitions, and every animation stops under prefers-reduced-motion: reduce;
//   banned   none of the patterns UX-DR129 bans appears (toasts, sounds, drag and drop, progress bars, intersection observers,
//            self-switching tabs, native dialogs and alerts, celebrations, modal notifications, controls that exist only on hover).
// The browser cases K1 to K6 and W1 to W4 (web/e2e/floor/) pin what the running page does in the states they reach; this reads all the
// sources, so a state no case reaches cannot bring one of these back without a test turning red. Each list below names the files that
// may do the thing and why; a story that needs another entry adds it here, with its reason.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const sources = join(here, '..', 'src');

const files = sourceFiles(sources, ['.ts', '.js', '.html', '.css']);
const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

/** The names of the files whose code (comments left out) matches the pattern. */
const filesWith = (pattern) => files.filter((one) => pattern.test(one.code)).map((one) => one.name);

/** The text inside each block that opens with the head, up to its matching brace. */
function blocksAfter(text, head) {
  const found = [];
  let from = 0;
  for (;;) {
    const at = text.indexOf(head, from);
    if (at < 0) return found;
    const open = text.indexOf('{', at);
    let depth = 0;
    let end = open;
    for (; end < text.length; end += 1) {
      if (text[end] === '{') depth += 1;
      else if (text[end] === '}') {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    found.push(text.slice(open + 1, end));
    from = end;
  }
}

/** The blocks of a source that apply under prefers-reduced-motion: reduce. */
const reducedMotion = (text) => blocksAfter(text, '@media (prefers-reduced-motion: reduce)');

/** The CSS of a file: a style sheet as it is, and the template literals that follow `styles:` in a component. */
function cssOf(one) {
  if (one.name.endsWith('.css')) return one.code;
  if (!one.name.endsWith('.ts')) return '';
  return [...one.code.matchAll(/styles:\s*`([\s\S]*?)`/g)].map((match) => match[1]).join('\n');
}

/** The rules of some CSS that hold no rule of their own: the selector and the declarations. */
const rulesOf = (css) => [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((match) => ({ selector: match[1].trim(), body: match[2] }));

describe('the scan', () => {
  it('reads every .ts, .js, .html and .css file of web/src/, the index and the style sheets among them', () => {
    const names = files.map((one) => one.name);
    for (const expected of ['index.html', 'main.ts', 'app/app.ts', 'app/header/skip-links.ts', 'signin/signin.js', 'signin/signin.css', 'styles/base.css', 'styles/controls.css', 'styles/tokens.css']) {
      assert.ok(names.includes(expected), `${expected} is scanned`);
    }
    for (const extension of ['.ts', '.js', '.html', '.css']) {
      assert.ok(names.some((name) => name.endsWith(extension)), `a ${extension} file is scanned`);
    }
  });

  it('reads the code without its comments', () => {
    assert.doesNotMatch(file('app/chat/chat-panel.ts').code, /no smooth scroll/);
    assert.match(file('app/chat/chat-panel.ts').text, /no smooth scroll/);
  });
});

describe('keys: only Enter and Escape', () => {
  const KEY_LITERAL = /\.key\s*[!=]==?\s*(['"`])([^'"`]*)\1/g;
  const KEY_CODE = /\b(?:keyCode|charCode|which)\s*[!=]==?\s*(\d+)/g;
  const KEY_LOOKUP = /\.includes\(\s*(?:event|evt|ev|e)\.(?:key|code)\s*\)|\[\s*(?:event|evt|ev|e)\.(?:key|code)\s*\]|\b(?:event|evt|ev|e)\.code\b|switch\s*\(\s*(?:event|evt|ev|e)\.(?:key|code|keyCode|which)\s*\)/;
  const KEY_BINDING = /\(key(down|up|press)(?:\.([\w.]+))?\)/g;
  const KEY_LISTENER = /addEventListener\(\s*['"]key\w+['"]|keydownEvents\(|keyboardEvents\(|HostListener\(\s*['"][\w.:]*key|\(key(?:down|up|press)[.)]/;

  /** Every keyboard handler of the page, by file, and why it may exist. */
  const KEY_HANDLERS = {
    'app/chat/composer.ts': 'Enter sends and Shift+Enter adds a line; the IME guard (keyCode 229) keeps a composition open',
    'app/chat/decision-strip.ts': 'Escape collapses the details when focus is inside the strip',
    'app/rail/decision-row.ts': 'Escape collapses the row when focus is inside it',
    'app/shared/popover.ts': 'Escape closes the popover (the CDK overlay\'s keydown stream)',
    'app/shared/tooltip.ts': 'Escape hides the tooltip (a capture-phase listener on the document)',
  };

  it('catches the forms of a shortcut that it looks for', () => {
    assert.match("if (event.key === 'a') {", new RegExp(KEY_LITERAL.source));
    assert.match('if (e.key !== "/") return;', new RegExp(KEY_LITERAL.source));
    assert.match('if (event.keyCode === 191) {', new RegExp(KEY_CODE.source));
    assert.match('if (event.which == 83) {', new RegExp(KEY_CODE.source));
    assert.match("['a', 's'].includes(event.key)", KEY_LOOKUP);
    assert.match('const handler = SHORTCUTS[event.key];', KEY_LOOKUP);
    assert.match('if (event.code === "Slash") {', KEY_LOOKUP);
    assert.match('<div (keydown.control.k)="open()">', new RegExp(KEY_BINDING.source));
    assert.match('<button (keyup.enter)="go()">', new RegExp(KEY_BINDING.source));
    assert.match("document.addEventListener('keypress', onPress)", KEY_LISTENER);
    assert.match("host: { '(keydown.a)': 'go()' }", KEY_LISTENER);
    assert.match("@HostListener('document:keydown', ['$event'])", KEY_LISTENER);
  });

  it('compares a key only with Enter and Escape, and a key code only with the IME guard', () => {
    const literals = new Set();
    const codes = new Set();
    for (const one of files) {
      for (const match of one.code.matchAll(KEY_LITERAL)) literals.add(match[2]);
      for (const match of one.code.matchAll(KEY_CODE)) codes.add(match[1]);
    }
    assert.deepEqual([...literals].sort(), ['Enter', 'Escape']);
    assert.deepEqual([...codes], ['229']);
    assert.deepEqual(filesWith(new RegExp(KEY_CODE.source)), ['app/chat/composer.ts']);
    assert.deepEqual(filesWith(KEY_LOOKUP), [], 'no key is looked up in a table, a list or a switch');
  });

  it('binds a template key event only to Enter or Escape, and a bare keydown only on the composer', () => {
    const bindings = [];
    for (const one of files) {
      for (const match of one.code.matchAll(KEY_BINDING)) bindings.push(`${one.name} ${match[1]} ${match[2] ?? ''}`.trim());
    }
    assert.deepEqual(bindings.sort(), ['app/chat/composer.ts down', 'app/chat/decision-strip.ts down escape', 'app/rail/decision-row.ts down escape']);
  });

  it('has no keyup or keypress handler and no accesskey', () => {
    assert.deepEqual(filesWith(/keyup|keypress/i), []);
    assert.deepEqual(filesWith(/accesskey/i), []);
  });

  it('registers a keyboard handler only in the files that are listed, each with its reason', () => {
    assert.deepEqual(filesWith(KEY_LISTENER).sort(), Object.keys(KEY_HANDLERS).sort());
    for (const [name, why] of Object.entries(KEY_HANDLERS)) assert.ok(why.length > 20, `${name} says why`);
  });
});

describe('Esc acts on one layer, the topmost', () => {
  const ESC_HOSTS = ['app/chat/decision-strip.ts', 'app/rail/decision-row.ts'];

  it('has the popovers say whether any is open', () => {
    assert.match(file('app/shared/popover.ts').code, /hasOpen\(\): boolean \{\s*return this\.open\.size > 0;\s*\}/);
  });

  it('asks it before a disclosure collapses on Escape, in each host of (keydown.escape)', () => {
    assert.deepEqual(filesWith(/\(keydown\.escape\)/).sort(), ESC_HOSTS);
    for (const name of ESC_HOSTS) {
      const { code: text } = file(name);
      assert.match(text, /private readonly popovers = inject\(Popovers\);/, `${name} injects the popovers`);
      const handler = text.slice(text.indexOf('protected collapse(): void {'));
      assert.match(handler, /^protected collapse\(\): void \{\s*if \(this\.popovers\.hasOpen\(\)\) \{\s*return;\s*\}/, `${name} asks hasOpen() first`);
    }
  });

  it('listens for the tooltip\'s Escape on the document in the capture phase, and stops the event only when the tooltip showed', () => {
    const { code: text } = file('app/shared/tooltip.ts');
    assert.match(text, /this\.document\.addEventListener\('keydown', this\.onKeydown, true\);/);
    assert.match(text, /this\.document\.removeEventListener\('keydown', this\.onKeydown, true\);/);
    assert.match(text, /const shown = this\.overlayRef !== undefined;\s*this\.hide\(\);\s*if \(shown\) \{\s*event\.stopPropagation\(\);\s*\}/);
  });

  it('has no other listener for a document keydown that runs after an element\'s own handler', () => {
    const listeners = files.flatMap((one) => [...one.code.matchAll(/addEventListener\(\s*'keydown'\s*,\s*[\w.]+\s*(?:,\s*([^)]*))?\)/g)].map((match) => [one.name, match[1]]));
    assert.deepEqual(listeners, [['app/shared/tooltip.ts', 'true']]);
  });
});

describe('heights are minimums', () => {
  /** The fixed heights of the page, by file: every value a `height:` or `block-size:` declaration has there, and why it is fixed. */
  const FIXED_HEIGHTS = {
    'app/app.ts': { values: ['100dvh', '100vh'], why: 'the app root is the height of the viewport, so that the routed page\'s regions scroll on their own' },
    'app/chat/ocutalon-reply.ts': { values: ['var(--chat-message-ocutalon-avatar-size)'], why: 'the reply avatar is an image whose size is a token, and it holds no text' },
    'app/main-page/main-page.ts': { values: ['10px', '12px', '14px', '16px', '40px'], why: 'the static skeleton blocks: aria-hidden stand-ins for content on its way, with no text in them' },
    'styles/base.css': { values: ['1px'], why: '.visually-hidden clips its box to a pixel' },
  };
  const HEIGHT = /(?:^|[^-\w$.])(?:height|block-size)\s*:\s*([^;}\n`]+)/g;

  it('catches a fixed height and does not take a minimum or a custom property for one', () => {
    assert.match('  height: 22px;', new RegExp(HEIGHT.source));
    assert.match('block-size: 2rem;', new RegExp(HEIGHT.source));
    assert.doesNotMatch('  min-height: 22px;', new RegExp(HEIGHT.source));
    assert.doesNotMatch('  max-height: 100%;', new RegExp(HEIGHT.source));
    assert.doesNotMatch('  --space-control-height: 36px;', new RegExp(HEIGHT.source));
    assert.doesNotMatch('  min-block-size: 2rem;', new RegExp(HEIGHT.source));
  });

  it('has a fixed height of the app or the styles only where this list has it, with its values and its reason', () => {
    const found = {};
    for (const one of files.filter((one) => /^(app|styles)\//.test(one.name))) {
      const values = [...one.code.matchAll(HEIGHT)].map((match) => match[1].trim());
      if (values.length > 0) found[one.name] = values.sort();
    }
    assert.deepEqual(found, Object.fromEntries(Object.entries(FIXED_HEIGHTS).map(([name, { values }]) => [name, values])));
    for (const [name, { why }] of Object.entries(FIXED_HEIGHTS)) assert.ok(why.length > 20, `${name} says why`);
  });

  it('sets a height from a script or a binding only where this list has it, and only in line units', () => {
    // style.height = ..., [style.height...] and setProperty('height'/'block-size', ...): a height that no CSS declaration shows.
    const SCRIPT_HEIGHT = /\.style\.(?:height|blockSize)\s*=|\[style\.(?:height|block-size)\b|\bsetProperty\(\s*['"`](?:height|block-size)['"`]/;
    const SCRIPT_HEIGHTS = {
      'app/chat/composer.ts': { value: /\.style\.height = `calc\(\$\{[^}]+\} \* 1lh \+ \$\{padding\}px\)`;/, why: 'the composer sets its height as a count of lines in lh units plus its padding, so that it follows the text size' },
    };
    assert.ok(SCRIPT_HEIGHT.test('field.style.height = `${n}px`;'), 'a script-set height is caught');
    assert.ok(SCRIPT_HEIGHT.test('<div [style.height.px]="n">'), 'a bound height is caught');
    assert.ok(SCRIPT_HEIGHT.test("el.style.setProperty('height', value)"), 'a property set is caught');
    assert.equal(SCRIPT_HEIGHT.test('el.style.minHeight = value;'), false, 'a minimum is not');
    const found = files.filter((one) => /^(app|styles)\//.test(one.name) && SCRIPT_HEIGHT.test(one.code)).map((one) => one.name);
    assert.deepEqual(found.sort(), Object.keys(SCRIPT_HEIGHTS));
    for (const [name, { value, why }] of Object.entries(SCRIPT_HEIGHTS)) {
      assert.match(file(name).code, value, `${name} sets its height in lh units`);
      assert.ok(why.length > 20, `${name} says why`);
    }
  });

  it('declares no height of its own in the generated tokens, whose custom properties are not declarations of a height', () => {
    assert.deepEqual([...file('styles/tokens.css').code.matchAll(HEIGHT)], []);
    assert.match(file('styles/tokens.css').code, /--space-control-height: 36px;/);
  });

  it('gives the outcome chip and the Fallback flag a minimum of 22px', () => {
    for (const name of ['app/chat/outcome-chip.ts', 'app/chat/fallback-flag.ts']) {
      assert.match(file(name).code, /\bmin-height: 22px;/, name);
    }
  });
});

describe('scrollers keep the gutter', () => {
  /** The scrollers that need no gutter, with the reason. */
  const NO_GUTTER = {
    'app/chat/composer.ts': 'a text area that scrolls its own text beyond five lines: it has no focusable content to scroll into view',
  };
  const SCROLLER = /(?:^|[;\s])overflow(?:-y)?\s*:\s*(?:auto|scroll)\b/;

  it('declares a scroll-padding of the gutter in every rule that scrolls, so that a control scrolled into view keeps its whole ring', () => {
    assert.ok(SCROLLER.test('  overflow-y: auto;'));
    assert.equal(SCROLLER.test('  overflow: hidden;'), false);
    const scrollers = [];
    const unpadded = [];
    for (const one of files) {
      for (const rule of rulesOf(cssOf(one))) {
        if (!SCROLLER.test(rule.body)) continue;
        scrollers.push(one.name);
        if (!/scroll-padding\s*:\s*var\(--space-scroll-gutter\)/.test(rule.body)) unpadded.push(one.name);
      }
    }
    assert.deepEqual([...new Set(scrollers)].sort(), ['app/about/about-dialog.ts', 'app/chat/chat-panel.ts', 'app/chat/composer.ts', 'app/main-page/main-page.ts']);
    assert.deepEqual(unpadded.sort(), Object.keys(NO_GUTTER));
    for (const [name, why] of Object.entries(NO_GUTTER)) assert.ok(why.length > 20, `${name} says why`);
  });
});

describe('motion', () => {
  const ANIMATES = /(?:^|[^-\w])animation(?:-name)?\s*:\s*(?!none\b)[^;}\s]/;
  const STOPS = /(?:^|[^-\w])animation\s*:\s*none\b/;

  it('catches an animation, and does not take animation: none for one', () => {
    assert.match('animation: reveal 1.2s steps(3, start) infinite;', ANIMATES);
    assert.match('  animation-name: spin;', ANIMATES);
    assert.doesNotMatch('animation: none;', ANIMATES);
    assert.doesNotMatch('animation-duration: 0.01ms !important;', ANIMATES);
  });

  it('scrolls smoothly nowhere, in a style sheet or in a script', () => {
    assert.deepEqual(filesWith(/scroll-behavior\s*:\s*smooth/), []);
    assert.deepEqual(filesWith(/behavior\s*:\s*['"`]smooth['"`]/), []);
    assert.match("el.scrollTo({ top: 0, behavior: 'smooth' })", /behavior\s*:\s*['"`]smooth['"`]/);
  });

  it('transitions nowhere but in the reduced-motion rule of base.css that stops them, and uses no animation library', () => {
    assert.deepEqual(filesWith(/\btransition\b/), ['styles/base.css']);
    const { code: base } = file('styles/base.css');
    const reduced = reducedMotion(base).join('\n');
    assert.equal((base.match(/\btransition\b/g) ?? []).length, (reduced.match(/\btransition\b/g) ?? []).length, 'every transition of base.css is inside the rule that stops them');
    assert.deepEqual(filesWith(/@angular\/animations|\.animate\(|provideAnimations|provideNoopAnimations/), []);
  });

  it('stops every animation under prefers-reduced-motion: reduce, in the file that declares it', () => {
    const animating = files.filter((one) => ANIMATES.test(one.code)).map((one) => one.name);
    assert.deepEqual(animating.sort(), ['app/chat/ocutalon-reply.ts', 'styles/controls.css'], 'the animations of the page: the dots and the spinner');
    for (const name of animating) {
      assert.ok(reducedMotion(file(name).code).some((block) => STOPS.test(block)), `${name} sets animation: none under reduced motion`);
    }
  });

  it('keeps the global reduced-motion rule of base.css', () => {
    const [rule] = reducedMotion(file('styles/base.css').code);
    assert.ok(rule, 'base.css has the rule');
    for (const declaration of ['animation-duration: 0.01ms !important', 'animation-iteration-count: 1 !important', 'transition-duration: 0.01ms !important', 'scroll-behavior: auto !important']) {
      assert.ok(rule.includes(declaration), declaration);
    }
  });
});

describe('the banned patterns (UX-DR129)', () => {
  /**
   * Each pattern with the files that may have it (none yet), keyed by file with the reason. `sample` is a line that the pattern must
   * catch, so that a pattern that stopped matching cannot pass for a clean tree.
   */
  const BANNED = [
    { what: 'a toast or a snackbar', pattern: /toast|snackbar/i, sample: 'this.snackBar.open(text)', allowed: {} },
    { what: 'a sound', pattern: /\bAudio\b|\bAudioContext\b|<audio\b|\bwebkitAudioContext\b/, sample: "new Audio('ping.mp3').play()", allowed: {} },
    {
      what: 'drag and drop',
      pattern: /draggable|cdkDrag|DragDrop|drag-drop|dataTransfer|\(drag\w*\)|\(drop\)|\bondrag\w*|\bondrop\b|addEventListener\(\s*['"](?:drag\w*|drop)['"]/,
      sample: '<li draggable="true" (dragstart)="pick()">',
      allowed: {},
    },
    { what: 'a progress bar or a model-progress meter', pattern: /<progress\b|progressbar|aria-valuenow/, sample: '<div role="progressbar" aria-valuenow="40">', allowed: {} },
    { what: 'an intersection observer (infinite scroll)', pattern: /IntersectionObserver/, sample: 'new IntersectionObserver(load)', allowed: {} },
    { what: 'tabs', pattern: /role\s*=\s*["']tab(?:list|panel)?["']|tablist|tabpanel/i, sample: '<div role="tablist">', allowed: {} },
    { what: 'a native alert, confirm, prompt or modal dialog', pattern: /(?:^|[^\w$.])(?:window\.)?(?:alert|confirm|prompt)\s*\(|\bshowModal\b/, sample: "if (confirm('Sure?')) go();", allowed: {} },
    { what: 'a celebration', pattern: /confetti|celebrat/i, sample: 'launchConfetti()', allowed: {} },
    {
      what: 'a dialog opened by the page',
      pattern: /\bdialogs\.open\(|inject\(Dialogs\)|\bdialog\.open\b/,
      sample: 'this.dialogs.open(AboutDialog, options)',
      allowed: {
        'app/header/header.ts': 'the user\'s About: the only dialog, opened by the user from the account menu',
        'app/shared/dialogs.ts': 'the one place that opens a dialog, over the CDK dialog',
      },
    },
  ];

  for (const { what, pattern, sample, allowed } of BANNED) {
    it(`finds no occurrence of ${what} in web/src/${Object.keys(allowed).length > 0 ? ` but in ${Object.keys(allowed).join(' and ')}` : ''}`, () => {
      assert.match(sample, pattern, 'the pattern catches its sample');
      assert.deepEqual(filesWith(pattern).sort(), Object.keys(allowed).sort());
      for (const [name, why] of Object.entries(allowed)) assert.ok(why.length > 20, `${name} says why`);
    });
  }

  it('opens a dialog (Dialogs.open) only from the header, for the user\'s About', () => {
    assert.deepEqual(filesWith(/\bdialogs\.open\(/), ['app/header/header.ts']);
    assert.deepEqual(filesWith(/inject\(Dialogs\)/), ['app/header/header.ts']);
  });

  it('lets no :hover rule set display, visibility or opacity, so that no control exists only on hover', () => {
    const sample = rulesOf('.row:hover .actions { display: flex; }').filter((rule) => /:hover/.test(rule.selector));
    assert.equal(sample.length, 1);
    assert.match(sample[0].body, /(?:^|[;\s])(?:display|visibility|opacity)\s*:/);
    const offenders = [];
    let hovered = 0;
    for (const one of files) {
      for (const rule of rulesOf(cssOf(one)).filter((one) => /:hover/.test(one.selector))) {
        hovered += 1;
        if (/(?:^|[;\s])(?:display|visibility|opacity)\s*:/.test(rule.body)) offenders.push(`${one.name}: ${rule.selector}`);
      }
    }
    assert.ok(hovered >= 5, `the :hover rules are found (${hovered})`);
    assert.deepEqual(offenders, []);
  });
});
