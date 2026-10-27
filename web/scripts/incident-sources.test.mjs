// Tests the shape of the incident card's components that Story 6.1 relies on and that no unit of the view model can see (QA): the card's
// root, headline and Show details row carry the attributes that the focus rule, the New messages button and the screen reader read; the
// evidence panel opens directly below the Show details row and only while it is open; the footer hands the strip the inputs of the
// design (reasons on, newest off, the decision's own cost, the served diagnosis URL); every text of the view is bound by interpolation;
// the page builds no trace URL; and each chip and bar class that the view can return has a rule that reads its own state tokens. The
// browser cases (floor/incident.spec.ts, I1 to I11) pin what the running page does for the states they reach; this reads the sources,
// so a chip, a bar or an attribute that no case reaches cannot be wired to the wrong token or lose its attribute without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const incidents = join(here, '..', 'src', 'app', 'incidents');
const files = sourceFiles(incidents, ['.ts']);
const { incidentView } = await import(pathToFileURL(join(incidents, 'incident-view.ts')).href);

const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};

/** The text of a component's template literal, or of its styles literal. */
const literal = (source, property) => {
  const found = new RegExp(`${property}: \`([\\s\\S]*?)\`,\\n`).exec(source.code);
  assert.ok(found, `${source.name} has a ${property} literal`);
  return found[1];
};

/** The declarations of the CSS rule with exactly this selector, or undefined when there is none. */
const rule = (css, selector) => {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(?:^|\\n)\\s*${escaped}\\s*\\{([^}]*)\\}`).exec(css)?.[1];
};

const card = file('incident-card.ts');
const panel = file('evidence-panel.ts');
const view = file('incident-view.ts');
const cardTemplate = literal(card, 'template');
const cardStyles = literal(card, 'styles');
const panelTemplate = literal(panel, 'template');
const panelStyles = literal(panel, 'styles');

describe('the scan', () => {
  it('reads the two components and the view model', () => {
    assert.deepEqual(files.map((one) => one.name).sort(), ['evidence-panel.ts', 'incident-card.ts', 'incident-view.ts']);
  });
});

describe('the card\'s root, headline and Show details row', () => {
  it('is an article that the focus rule and New messages find (data-part, data-key) and can focus (tabindex -1), named by its headline', () => {
    const root = /<article\s([\s\S]*?)>/.exec(cardTemplate)?.[1] ?? '';
    assert.match(root, /data-part="incident"/);
    assert.match(root, /\[attr\.data-key\]="view\(\)\.key"/);
    assert.match(root, /tabindex="-1"/);
    assert.match(root, /\[attr\.aria-labelledby\]="headingId"/);
  });

  it('has the headline as an h3 with the id that names the card, focusable for the compacted card (tabindex -1)', () => {
    const headline = /<h3\s([\s\S]*?)>\{\{ view\(\)\.headline \}\}<\/h3>/.exec(cardTemplate)?.[1] ?? '';
    assert.match(headline, /class="headline"/);
    assert.match(headline, /\[id\]="headingId"/);
    assert.match(headline, /tabindex="-1"/);
  });

  it('has the Show details button expand the panel by aria-expanded and aria-controls, only when the view has a panel', () => {
    assert.match(cardTemplate, /@if \(view\(\)\.panel; as panel\) \{\s*<div class="actions">/);
    const button = /<button\s([\s\S]*?)>/.exec(cardTemplate)?.[1] ?? '';
    assert.match(button, /type="button"/);
    assert.match(button, /\[attr\.aria-expanded\]="open\(\)"/);
    assert.match(button, /\[attr\.aria-controls\]="panelId"/);
    assert.match(button, /\(click\)="open\.set\(!open\(\)\)"/);
    assert.match(cardTemplate, /\{\{ texts\.showDetails \}\}/);
  });

  it('opens the panel directly below that row, in the element that aria-controls names, and only while it is open', () => {
    assert.match(
      cardTemplate,
      /<\/button>\s*<\/div>\s*<div class="panel" \[id\]="panelId">\s*@if \(open\(\)\) \{\s*<app-evidence-panel \[panel\]="panel" \/>\s*\}\s*<\/div>/,
    );
  });
});

describe('the footer', () => {
  it('hands the strip the decision, its own cost, the incident\'s fallback reason, the reasons on, newest off and the served diagnosis URL', () => {
    const strip = /<app-decision-strip([\s\S]*?)\/>/.exec(cardTemplate)?.[1] ?? '';
    for (const binding of ['[decision]="strip.decision"', '[cost]="strip.cost"', '[fallbackReason]="strip.fallbackReason"', '[reasons]="true"', '[newest]="false"', '[traceUrl]="view().diagnosisUrl"']) {
      assert.ok(strip.includes(binding), `the strip is bound with ${binding}`);
    }
  });

  it('shows the diagnosis trace link alone when there is no strip, and no footer when there is neither', () => {
    assert.match(cardTemplate, /@if \(view\(\)\.strip \|\| view\(\)\.diagnosisUrl\) \{\s*<div class="footer">/);
    assert.match(cardTemplate, /@else if \(view\(\)\.diagnosisUrl; as url\) \{\s*<app-trace-link \[url\]="url" \/>/);
  });
});

describe('the texts', () => {
  it('prints every text of the view by interpolation, in the order of the design', () => {
    const order = ['stateText', 'view().time', 'view().headline', 'view().more', 'view().causeSentence', 'view().evidenceLine', 'view().fixSentence', 'view().fixingLine'];
    let last = -1;
    for (const name of order) {
      const at = cardTemplate.indexOf(`{{ ${name} }}`);
      assert.ok(at > last, `{{ ${name} }} is printed, below the one before`);
      last = at;
    }
  });

  it('prints the panel\'s labels, lines, held note and links by interpolation, with the mono class from the view', () => {
    for (const bound of ['{{ row.label }}', '{{ line }}', '[class.mono]="row.mono"', '{{ texts.held }}', '[url]="link.url"', '[text]="link.text"']) {
      assert.ok(panelTemplate.includes(bound), `${bound} is bound in the panel`);
    }
  });

  it('binds no markup: not as innerHTML, outerHTML, a bypass or a sanitizer, in any of the three', () => {
    for (const one of files) {
      assert.doesNotMatch(one.code, /innerhtml|outerhtml|bypassSecurity|DomSanitizer/i, one.name);
    }
  });

  it('builds no trace URL: the links are the served traceUrl and nothing else (no header id, namespace or trace path)', () => {
    for (const one of files) {
      assert.doesNotMatch(one.code, /traceHeaderId|traceNamespace|\/ocutalon\/trace|SESSIONID|VisualTrace/, one.name);
    }
  });
});

describe('the styles', () => {
  const colours = /#[0-9a-fA-F]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|hwb|lab|lch|oklab|oklch|color-mix|color)\(/;

  it('hold no colour literal: every colour is a DESIGN.md token', () => {
    assert.doesNotMatch(cardStyles, colours, 'the card');
    assert.doesNotMatch(panelStyles, colours, 'the panel');
    assert.doesNotMatch(view.code, colours, 'the view');
  });

  it('read every colour, font and size of text through a token', () => {
    for (const [name, css] of [['the card', cardStyles], ['the panel', panelStyles]]) {
      const bad = [...css.matchAll(/^\s*(color|background|font-family|font-size|font-weight)\s*:\s*([^;]+);/gm)].filter(([, , value]) => !/var\(--/.test(value)).map(([line]) => line.trim());
      assert.deepEqual(bad, [], `${name}: a colour or a type setting without a token`);
    }
  });

  it('give every chip the view can return a rule that reads that state\'s own background and foreground tokens', () => {
    const chips = new Set();
    for (const state of ['open', 'awaiting_approval', 'fixing', 'resolved', 'closed']) {
      chips.add(incidentView({ ref: 'X', state }, { decisions: [], nowMs: 0, messageTime: () => '', topTime: () => '', itemTime: () => '' }).chip);
    }
    assert.deepEqual([...chips].sort(), ['awaiting-approval', 'closed', 'fixing', 'open', 'resolved']);
    assert.match(cardTemplate, /\[class\]="'chip chip-' \+ view\(\)\.chip"/);
    for (const chip of chips) {
      const declarations = rule(cardStyles, `.chip-${chip}`);
      assert.ok(declarations, `.chip-${chip} has a rule`);
      assert.ok(declarations.includes(`background: var(--incident-state-${chip}-background);`), `.chip-${chip} reads its own background`);
      assert.ok(declarations.includes(`color: var(--incident-state-${chip}-foreground);`), `.chip-${chip} reads its own foreground`);
    }
  });

  it('give every bar the view can return a rule that reads that bar\'s own token (attention is the card\'s own rule)', () => {
    assert.match(cardTemplate, /\[class\]="'incident bar-' \+ view\(\)\.bar"/);
    assert.ok(rule(cardStyles, '.incident')?.includes('border-inline-start: var(--incident-card-accent-bar);'), 'attention');
    for (const bar of ['fixing', 'resolved', 'closed']) {
      const declarations = rule(cardStyles, `.incident.bar-${bar}`);
      assert.ok(declarations, `.bar-${bar} has a rule`);
      assert.ok(declarations.includes(`border-inline-start: var(--incident-card-accent-bar-${bar});`), `.bar-${bar} reads its own token`);
    }
  });

  it('draw the panel\'s mono values in the mono face at the evidence panel\'s size', () => {
    const declarations = rule(panelStyles, '.value.mono');
    assert.ok(declarations?.includes('font-family: var(--font-mono);'));
    assert.ok(declarations?.includes('font-size: var(--evidence-panel-typography-font-size);'));
  });
});
