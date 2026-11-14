// Tests the shape of the approval request card's sources that Story 6.2 relies on (and, since Story 6.3, of answer-press.ts, the press that
// the card shares with the simulated phone's request message: its one busy state, its post of {action, channel} and its notices) and that no unit of the view model can see (QA): the
// card's root and answer row carry the attributes that the focus rule and the New messages button read; the two buttons share one
// busy state and are never `disabled`; Show details sits outside the pending/answered choice; every text is bound by interpolation;
// the dry run's Before and After and each status tone read their own tokens; the call posts only {action, channel} to the answer
// route; and the incident card hands the first request card its panel. Story 6.4: the result band (result-band.ts) follows the answer
// row on the tokens of the result bands and holds the audit line and Dismiss; Dismiss ends the answer row of a request card with no band; and
// the incident card hands each request card its request, the item noun and, to the last, Dismiss. The browser cases (floor/approval.spec.ts A1 and cards/approval-card.spec.ts A2 to A10) pin
// what the running page does; this reads the sources, so a state no case reaches cannot lose an attribute or read the wrong token
// without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const files = sourceFiles(join(app, 'approvals'), ['.ts']);
const incidents = sourceFiles(join(app, 'incidents'), ['.ts']);
const api = sourceFiles(join(app, 'api'), ['.ts']);
const live = sourceFiles(join(app, 'live'), ['.ts']);

const file = (list, name) => {
  const found = list.find((one) => one.name === name);
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

const card = file(files, 'approval-request-card.ts');
const press = file(files, 'answer-press.ts');
const view = file(files, 'approval-view.ts');
const band = file(files, 'result-band.ts');
const template = literal(card, 'template');
const styles = literal(card, 'styles');
const bandTemplate = literal(band, 'template');
const bandStyles = literal(band, 'styles');

describe('the scan', () => {
  it('reads the card and the view model', () => {
    assert.deepEqual(files.map((one) => one.name).sort(), ['answer-press.ts', 'approval-request-card.ts', 'approval-view.ts', 'result-band.ts']);
  });
});

describe('the root and the answer row', () => {
  it('is a section that the focus rule and New messages find (data-part, data-key) and can focus (tabindex -1), named by its label', () => {
    const root = /<section\s([\s\S]*?)>/.exec(template)?.[1] ?? '';
    assert.match(root, /data-part="approval"/);
    assert.match(root, /\[attr\.data-key\]="view\(\)\.ref"/);
    assert.match(root, /tabindex="-1"/);
    assert.match(root, /\[attr\.aria-labelledby\]="labelId"/);
  });

  it('has the two buttons in a span of the answer part while pending, and the status in a paragraph of the same part and key, focusable, otherwise', () => {
    assert.match(template, /<div class="answer-row">\s*@if \(view\(\)\.pending && !viewer\(\) && !cannot\(\)\) \{\s*<span class="buttons" data-part="answer" \[attr\.data-key\]="view\(\)\.ref">/);
    const status = /<p \[class\]="'status tone-' \+ status\.tone"([^>]*)>/.exec(template)?.[1] ?? '';
    assert.match(status, /data-part="answer"/);
    assert.match(status, /\[attr\.data-key\]="view\(\)\.ref"/);
    assert.match(status, /tabindex="-1"/);
    assert.match(template, /@else if \(view\(\)\.status; as status\) \{/);
    // Story 25.5: a pending request that the user may not answer has its sentence in the same answer part and key, in place of the buttons, with no new layout.
    const cannot = /@else if \(view\(\)\.pending && !viewer\(\) && cannot\(\)\) \{\s*<p class="status tone-expired"([^>]*)>\s*<app-icon name="circle-slash" \[size\]="16" \/>\s*<span>\{\{ cannot\(\) \}\}<\/span>/.exec(template)?.[1] ?? '';
    assert.match(cannot, /data-part="answer"/);
    assert.match(cannot, /\[attr\.data-key\]="view\(\)\.ref"/);
    assert.match(cannot, /tabindex="-1"/);
    assert.match(card.code, /protected readonly cannot = computed\(\(\) => \(this\.answer\.refused\(\) !== '' \? this\.answer\.refused\(\) : this\.view\(\)\.cannotAnswer\)\);/);
    assert.match(template, /@if \(notice\(\) && notice\(\) !== cannot\(\)\) \{/);
  });

  it('keeps Show details outside the pending/answered choice, at the end of the row, expanding the incident\'s panel by aria-expanded and aria-controls', () => {
    assert.match(template, /<\/p>\s*\}\s*@if \(details\(\) \|\| \(!band\(\) && dismiss\(\)\)\) \{\s*<span class="row-end">\s*@if \(details\(\)\) \{\s*<button\s/);
    const button = /@if \(details\(\)\) \{\s*<button\s([\s\S]*?)>/.exec(template)?.[1] ?? '';
    assert.match(button, /class="button button-ghost show-details"/);
    assert.match(button, /\[attr\.aria-expanded\]="detailsOpen\(\)"/);
    assert.match(button, /\[attr\.aria-controls\]="detailsId\(\)"/);
    assert.match(button, /\(click\)="toggleDetails\.emit\(\)"/);
    assert.match(template, /<div class="panel" \[id\]="detailsId\(\)">\s*@if \(detailsOpen\(\)\) \{\s*<app-evidence-panel \[panel\]="panel" \/>/);
  });

  it('moves the focus of a replaced button through the shared rule on the answer part only', () => {
    assert.match(card.code, /item: `\[\$\{PART\}="answer"\]\[\$\{KEY\}\]`/);
    assert.match(card.code, /keepFocus\(this\.host\.nativeElement, this\.injector, this\.popovers, ANSWER_RULE\)/);
    assert.doesNotMatch(card.code, /\.focus\(|autofocus/);
  });
});

describe('the buttons', () => {
  const buttons = [...template.matchAll(/<button\s([\s\S]*?)>/g)].map((match) => match[1]);

  it('are Approve, Reject and Show details, each a type="button"', () => {
    assert.equal(buttons.length, 3);
    for (const one of buttons) assert.match(one, /type="button"/);
  });

  it('go busy together: aria-busy and aria-disabled from the one busy signal, a spinner in each, and never the disabled attribute', () => {
    const [approve, reject] = buttons;
    for (const [name, one] of [['Approve', approve], ['Reject', reject]]) {
      assert.match(one, /\[attr\.aria-busy\]="busy\(\) \? 'true' : null"/, name);
      assert.match(one, /\[attr\.aria-disabled\]="busy\(\) \? 'true' : null"/, name);
    }
    assert.equal((template.match(/<app-icon class="spinner" name="loader-circle"/g) ?? []).length, 2);
    assert.doesNotMatch(template, /\[disabled\]|\[attr\.disabled\]|\sdisabled[\s=>]/);
  });

  it('are named with the object, and are the primary and the secondary variant of controls.css', () => {
    const [approve, reject] = buttons;
    assert.match(approve, /class="button button-primary"/);
    assert.match(approve, /\[attr\.aria-label\]="view\(\)\.approveName"/);
    assert.match(approve, /\(click\)="press\('approve'\)"/);
    assert.match(reject, /class="button button-secondary"/);
    assert.match(reject, /\[attr\.aria-label\]="view\(\)\.rejectName"/);
    assert.match(reject, /\(click\)="press\('reject'\)"/);
  });

  it('share one BusyState (in answer-press.ts, the press that the card shares with the phone), whose notice is announced once and which is disposed with its host', () => {
    assert.equal((press.code.match(/new BusyState\(/g) ?? []).length, 1);
    assert.doesNotMatch(card.code, /BusyState/, 'the card holds none of its own');
    assert.match(press.code, /onNotice: \(\) => options\.announcer\.announce\(APPROVAL_TEXTS\.busyNotice\)/);
    assert.match(press.code, /options\.destroyRef\.onDestroy\(\(\) => this\.state\.dispose\(\)\)/);
    assert.match(press.code, /if \(!this\.state\.press\(\)\) \{\s*return;\s*\}/, 'a press while a call is out sends nothing');
    assert.doesNotMatch(press.code, /disabled/, 'and the buttons are never disabled');
  });

  it('describe themselves by the notice while it shows', () => {
    for (const one of buttons.slice(0, 2)) assert.match(one, /\[attr\.aria-describedby\]="notice\(\) \? noticeId : null"/);
    assert.match(template, /<app-inline-notice class="under" variant="warning" \[id\]="noticeId">\{\{ notice\(\) \}\}<\/app-inline-notice>/);
  });
});

describe('the call', () => {
  it('posts only {action, channel} to the answer route of the request, never a session or a user, with the channel web for the card', () => {
    const client = file(api, 'api-client.ts').code;
    const method = /answerApproval\([\s\S]*?\n  \}/.exec(client)?.[0] ?? '';
    assert.match(method, /channel: AnswerChannel = 'web'/);
    assert.match(method, /\/approvals\/\$\{encodeURIComponent\(ref\)\}\/answer`, \{ action, channel \}/);
    assert.doesNotMatch(method, /session|user/i);
    assert.match(card.code, /answer: \(ref, action, channel\) => this\.api\.answerApproval\(ref, action, channel\),\s*channel: 'web',/);
    assert.match(card.code, /this\.answer\.press\(this\.view\(\)\.ref, action\)/);
    assert.match(press.code, /\.answer\(ref, action, this\.options\.channel\)/, 'the press posts the channel it was given');
    assert.doesNotMatch(press.code, /session|user/i);
  });

  it('hands every reply that carries a payload to the host at once, right after it becomes local, and the card passes it to the live store', () => {
    assert.match(press.code, /if \(approval !== undefined\) \{\s*this\.local\.set\(approval\);\s*this\.options\.answered\(approval\);\s*\}/);
    assert.match(press.code, /answered: \(approval: ApprovalPayload\) => void;/);
    assert.match(card.code, /channel: 'web',\s*answered: \(approval\) => this\.live\.applyAnswer\(approval\),/);
    assert.match(card.code, /private readonly live = inject\(LiveState\);/);
  });

  it('takes the reply into the live store only while the page runs and holds a store, and sets it only when withAnswer gave another store', () => {
    const state = file(live, 'live-state.ts').code;
    const method = /applyAnswer\(approval: ApprovalPayload\): void \{[\s\S]*?\n  \}/.exec(state)?.[0] ?? '';
    assert.match(method, /const current = this\.store\(\);\s*if \(this\.stopped \|\| !current\) \{\s*return;\s*\}/);
    assert.match(method, /const next = withAnswer\(current, approval\);\s*if \(next !== current\) \{\s*this\.store\.set\(next\);\s*\}/);
  });

  it('keeps the notices of a reply in one place: a late press, a missing request, a refusal or failure and no connection', () => {
    assert.match(press.code, /case 'already':\s*return \(approval === undefined \? '' : latePressText\(approval, this\.options\.context\(\)\)\) \|\| outcome\.message;/);
    assert.match(press.code, /case 'gone':\s*return APPROVAL_TEXTS\.gone;/);
    assert.match(press.code, /case 'notAllowed':\s*case 'failed':\s*return outcome\.message;/);
    assert.match(press.code, /case 'unreachable':\s*return APPROVAL_TEXTS\.busyNotice;/);
    assert.match(press.code, /this\.replyNotice\.set\(''\);\s*const call/, 'a new press clears the notice');
    assert.match(press.code, /if \(text !== ''\) \{\s*this\.options\.announcer\.announce\(text\);/, 'and each notice is announced once');
  });
});

describe('an answer from elsewhere', () => {
  it('is announced by the card once, when the store goes from pending to answered and the card has no view of its own', () => {
    assert.match(card.code, /const pending = this\.approval\(\)\.state === 'pending';\s*untracked\(\(\) => this\.noteStore\(pending\)\);/);
    assert.match(card.code, /if \(wasPending !== true \|\| pending \|\| this\.answer\.local\(\) !== undefined \|\| this\.answer\.busy\(\)\) \{\s*return;\s*\}/);
    assert.equal((card.code.match(/this\.announcer\.announce\(/g) ?? []).length, 1, 'one announcement of its own');
    assert.match(card.code, /this\.announcer\.announce\(status\.text\);/);
  });

  it('reads focus after the render, and stays silent when it is on the card\'s answer line or on the phone\'s answer line of the same request', () => {
    assert.match(card.code, /afterNextRender\(\s*\(\) => \{[^]*?queueMicrotask\(\(\) => \{\s*const status = this\.view\(\)\.status;\s*if \(status === undefined \|\| this\.focusOnAnswer\(this\.view\(\)\.ref\)\) \{\s*return;\s*\}/);
    assert.match(card.code, /active\.closest\(`\[\$\{PART\}="answer"\]\[\$\{KEY\}\]`\)/);
    assert.match(card.code, /active\.closest\(`app-simulated-phone \[\$\{PART\}="answer"\]\[data-approval\]`\)\?\.getAttribute\('data-approval'\) === ref/);
  });
});

describe('the texts', () => {
  it('prints every text by interpolation: the label, action, fixed-targets line, dry run, status, expiry and notice', () => {
    const order = ['view().label', 'view().action', 'view().fixedTargets', 'texts.dryRun', 'dry.countLine', 'dry.before', 'dry.after', 'dry.eitherWay', 'dry.resendLine', 'dry.nothingYet', 'texts.approve', 'texts.reject', 'status.text', 'showDetails', 'view().expiry', 'notice()'];
    let last = -1;
    for (const name of order) {
      const at = template.indexOf(`{{ ${name} }}`);
      assert.ok(at > last, `{{ ${name} }} is printed, below the one before`);
      last = at;
    }
  });

  it('prints the either-way row (Story 7.8) as its own element between After and Will resend, never as the dry-note, and types none of its words on the page', () => {
    assert.match(template, /@if \(dry\.eitherWay\) \{\s*<div class="dry-either">\{\{ dry\.eitherWay \}\}<\/div>\s*\}/);
    assert.ok(!/class="dry-note"[^>]*>\{\{ dry\.eitherWay/.test(template), 'not in the dry-note');
    assert.equal(template.match(/class="dry-note"/g).length, 1, 'the dry-note is still the one element of the note');
    assert.ok(template.indexOf('{{ dry.eitherWay }}') < template.indexOf('{{ texts.willResend }}'), 'before Will resend');
    assert.ok(template.indexOf('{{ dry.eitherWay }}') > template.indexOf('{{ texts.after }}'), 'after After');
    assert.ok(!/<span class="dry-key">[^<]*dry\.eitherWay/.test(template), 'with no label');
    for (const one of files) {
      assert.doesNotMatch(one.code, /valid whether read|they match the day/i, `${one.name} holds none of the line's words`);
    }
    assert.match(view.code, /ctx\.render\('incident\.eitherWayLine'/);
  });

  it('prints a setting request\'s three lines (Story 40.6) by interpolation, in the dry run\'s place and above it, and types none of their words', () => {
    const order = ['view().action', 'setting.now', 'setting.proposed', 'setting.note'];
    let last = -1;
    for (const name of order) {
      const at = template.indexOf(`{{ ${name} }}`);
      assert.ok(at > last, `{{ ${name} }} is printed, below the one before`);
      last = at;
    }
    assert.match(template, /@if \(view\(\)\.setting; as setting\) \{/);
    assert.ok(template.indexOf('{{ setting.note }}') < template.indexOf('{{ texts.dryRun }}'), 'before the dry run block');
    assert.doesNotMatch(template, /Nothing changes unless you approve|Now:|Proposed:/, 'the template types none of the lines\' words');
  });

  it('prints a partner delay notice\'s lines (Story 23.5) by interpolation, in the dry run\'s place, with the Simulated label beside the To line, and types none of their words', () => {
    const order = ['view().action', 'partner.to', 'partner.notice', 'partner.note'];
    let last = -1;
    for (const name of order) {
      const at = template.indexOf(`{{ ${name} }}`);
      assert.ok(at > last, `{{ ${name} }} is printed, below the one before`);
      last = at;
    }
    assert.match(template, /@if \(view\(\)\.partner; as partner\) \{/);
    assert.match(template, /@if \(partner\.simulated\) \{\s*<app-simulated-label \/>/, 'the label stands beside the To line, while the payload says simulated');
    assert.ok(template.indexOf('{{ partner.note }}') < template.indexOf('{{ texts.dryRun }}'), 'before the dry run block');
    assert.doesNotMatch(template, /Nothing is sent unless you approve|To:|Simulated mailbox/, 'the template types none of the lines\' words');
    const card = file(files, 'approval-request-card.ts');
    assert.match(card.code, /import \{ SimulatedLabel \} from '\.\.\/devices\/simulated-label';/);
    assert.match(card.code, /imports: \[[^\]]*SimulatedLabel[^\]]*\]/);
    assert.match(literal(card, 'styles'), /\.partner-notice \{\s*white-space: pre-line;/, 'the notice keeps its line breaks');
  });

  it('binds no markup: not as innerHTML, outerHTML, a bypass or a sanitizer', () => {
    for (const one of files) assert.doesNotMatch(one.code, /innerhtml|outerhtml|bypassSecurity|DomSanitizer/i, one.name);
  });

  it('gives the status the icon and tone of its state: circle-check approved, circle-slash rejected, clock expired', () => {
    assert.match(view.code, /tone: 'approved', icon: 'circle-check'/);
    assert.match(view.code, /tone: 'rejected', icon: 'circle-slash'/);
    assert.match(view.code, /tone: 'expired', icon: 'clock'/);
  });
});

describe('the styles', () => {
  const colours = /#[0-9a-fA-F]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|hwb|lab|lch|oklab|oklch|color-mix|color)\(/;

  it('hold no colour literal: every colour is a DESIGN.md token', () => {
    assert.doesNotMatch(styles, colours, 'the card');
    assert.doesNotMatch(view.code, colours, 'the view');
  });

  it('read every colour, font and size of text through a token', () => {
    const bad = [...styles.matchAll(/^\s*(color|background|font-family|font-size|font-weight)\s*:\s*([^;]+);/gm)].filter(([, , value]) => !/var\(--/.test(value)).map(([line]) => line.trim());
    assert.deepEqual(bad, []);
  });

  it('draw Before in the danger ink and After in the success ink, both in the mono face', () => {
    assert.ok(rule(styles, '.before')?.includes('color: var(--dry-run-block-before);'), 'Before');
    assert.ok(rule(styles, '.after')?.includes('color: var(--dry-run-block-after);'), 'After');
    const mono = rule(styles, '.mono');
    assert.ok(mono?.includes('font-family: var(--font-mono);'));
    assert.ok(mono?.includes('font-size: var(--dry-run-block-value-typography-font-size);'));
    assert.match(template, /<span class="mono before">\{\{ dry\.before \}\}<\/span>/);
    assert.match(template, /<span class="mono after">\{\{ dry\.after \}\}<\/span>/);
  });

  it('give each status tone its own token, and each bar its own', () => {
    for (const tone of ['approved', 'rejected', 'expired']) {
      assert.ok(rule(styles, `.tone-${tone}`)?.includes(`color: var(--answered-status-${tone});`), `.tone-${tone}`);
    }
    assert.match(template, /\[class\]="'request bar-' \+ view\(\)\.bar"/);
    assert.ok(rule(styles, '.request')?.includes('border-inline-start: var(--approval-request-card-accent-bar-pending);'), 'pending');
    for (const bar of ['approved', 'closed']) {
      assert.ok(rule(styles, `.request.bar-${bar}`)?.includes(`border-inline-start: var(--approval-request-card-accent-bar-${bar});`), `.bar-${bar}`);
    }
  });
});

describe('the incident card', () => {
  const incident = file(incidents, 'incident-card.ts');
  const incidentTemplate = literal(incident, 'template');

  it('draws a request card for each request of the incident, the first with the panel, each with its request, the noun and (the last) Dismiss, and its own Show details row only without one', () => {
    assert.match(
      incidentTemplate,
      /@for \(request of requests\(\); track request\.ref; let first = \$first; let last = \$last\) \{\s*<app-approval-request-card\s+\[approval\]="request"\s+\[ctx\]="approvalCtx\(\)"\s+\[details\]="first \? view\(\)\.panel : undefined"\s+\[detailsId\]="panelId"\s+\[detailsOpen\]="open\(\)"\s+\[result\]="resultOf\(request\.ref\)"\s+\[itemNoun\]="incident\(\)\.itemNoun"\s+\[production\]="production\(\)"\s+\[dismiss\]="last \? dismissTarget\(\) : undefined"\s+\(toggleDetails\)="open\.set\(!open\(\)\)"\s+\/>\s*\}\s*@if \(requests\(\)\.length === 0\) \{\s*@if \(view\(\)\.panel \|\| dismissTarget\(\)\) \{\s*<div class="actions">/,
    );
    assert.match(incident.code, /result: \(request, itemNoun, production\) => resultView\(request, itemNoun, \(key, slots\) => renderPageText\(key, slots\), production\),/, 'the compact card\'s bands name the production');
    assert.match(incident.code, /production = computed\(\(\) => productionOf\(this\.incident\(\)\)\);/);
    assert.match(incident.code, /requests = computed\(\(\) => \(this\.view\(\)\.compact \? \[\] : requestsOf\(this\.incident\(\), this\.approvals\(\)\)\)\)/);
    assert.ok(incidentTemplate.indexOf('{{ view().fixingLine }}') < incidentTemplate.indexOf('<app-approval-request-card'), 'the request cards follow the fixing line');
    assert.ok(incidentTemplate.indexOf('<app-approval-request-card') < incidentTemplate.indexOf('class="footer"'), 'and come before the footer');
  });
});

describe('the result band and Dismiss on the request card (Story 6.4)', () => {
  it('draws the band between the answer row and the expiry, from the incident payload\'s request, and shows Dismiss at the row\'s end only when there is no band', () => {
    assert.match(template, /<\/button>\s*\}\s*@if \(!band\(\) && dismiss\(\); as target\) \{\s*<app-incident-dismiss \[target\]="target" \/>\s*\}\s*<\/span>\s*\}\s*<\/div>\s*@if \(band\(\); as result\) \{\s*<app-result-band \[result\]="result" \[dismiss\]="dismiss\(\)" \/>\s*\}\s*@if \(view\(\)\.expiry\) \{/);
    assert.match(card.code, /band = computed\(\(\) => \{\s*const request = this\.result\(\);\s*const ctx = this\.ctx\(\);\s*return request === undefined \? undefined : resultView\(request, this\.itemNoun\(\), \(key, slots\) => ctx\.render\(key, slots\), this\.production\(\)\);/);
    assert.match(card.code, /readonly result = input<IncidentRequest \| undefined>\(undefined\);/);
    assert.match(card.code, /readonly production = input\(''\);/, 'and names the incident\'s production for the band of a suspend or resume');
    assert.match(card.code, /readonly dismiss = input<DismissTarget \| undefined>\(undefined\);/);
    assert.doesNotMatch(card.code, /\.focus\(|autofocus/, 'and the card moves no focus for it');
    assert.equal((card.code.match(/this\.announcer\.announce\(/g) ?? []).length, 1, 'nor announces a band');
  });

  it('puts Show details and Dismiss together at the right end of the row, and lets them wrap together when the row is narrow', () => {
    const end = rule(styles, '.row-end');
    assert.ok(end?.includes('margin-inline-start: auto;'), 'at the right end');
    assert.ok(end?.includes('display: inline-flex;') && end.includes('flex-wrap: wrap;') && end.includes('justify-content: flex-end;'), 'together, and wrapping together');
    assert.doesNotMatch(rule(styles, '.show-details') ?? '', /margin-inline-start/, 'Show details is placed by the group');
  });

  it('is a band on the result tokens: the tone class, the icon, the text, Dismiss at the right end and the audit line beneath in caption', () => {
    assert.match(bandTemplate, /<div \[class\]="'band tone-' \+ result\(\)\.tone" data-part="result" \[attr\.data-tone\]="result\(\)\.tone">\s*<app-icon \[name\]="result\(\)\.icon" \[size\]="16" \/>\s*<span class="text">\{\{ result\(\)\.text \}\}<\/span>\s*@if \(dismiss\(\); as target\) \{\s*<app-incident-dismiss class="dismiss" \[target\]="target" \/>\s*\}\s*<\/div>\s*<p class="audit">\{\{ result\(\)\.audit \}\}<\/p>/);
    for (const tone of ['success', 'partial']) {
      const declarations = rule(bandStyles, `.tone-${tone}`);
      assert.ok(declarations?.includes(`background: var(--result-${tone}-background);`), `${tone} background`);
      assert.ok(declarations?.includes(`color: var(--result-${tone}-foreground);`), `${tone} foreground`);
      assert.ok(declarations?.includes(`border-radius: var(--result-${tone}-radius);`), `${tone} radius`);
    }
    assert.ok(rule(bandStyles, '.dismiss')?.includes('margin-inline-start: auto;'));
    assert.ok(rule(bandStyles, '.audit')?.includes('font-size: var(--type-caption-font-size);'));
    assert.doesNotMatch(bandStyles, /#[0-9a-fA-F]{3,8}\b/, 'no colour literal');
  });

  it('is not a live region, holds no focus call and no announcement, and binds no markup', () => {
    assert.doesNotMatch(band.code, /\.focus\(|\.announce\(|Announcer|aria-live|innerhtml|bypassSecurity/i);
    assert.match(bandTemplate, /^(?![\s\S]*role=)/);
  });

  it('reads the result from the view\'s mapping: success and circle-check for all through only, clock for still resending, triangle-alert for the rest', () => {
    assert.match(view.code, /key = 'result\.stillResending';\s*slots = counts;\s*icon = 'clock';/);
    assert.match(view.code, /key = 'result\.allThrough';[\s\S]*?tone = 'success';\s*icon = 'circle-check';/);
    assert.match(view.code, /let tone: ResultView\['tone'\] = 'partial';\s*let icon: ResultView\['icon'\] = 'triangle-alert';/);
  });
});

// Story 31.6 (QA): the chat panel draws a tool call's request as this card only while the store holds its approval payload, and as the
// plain notice card otherwise; the plain form carries none of the request card's pending cues (U-222). The browser case (answers X13)
// pins what the running page does; this reads the sources, so neither branch can lose its binding without a test turning red.
describe('a tool call\'s request in the chat panel (Story 31.6)', () => {
  const chat = sourceFiles(join(app, 'chat'), ['.ts']);
  const panel = file(chat, 'chat-panel.ts');
  const notice = file(chat, 'notice-card.ts');
  const panelTemplate = literal(panel, 'template');
  const noticeTemplate = literal(notice, 'template');
  const noticeStyles = literal(notice, 'styles');

  it('draws the request card for a notice the store holds a payload for, with the payload, the page context and the notice text as the request', () => {
    const branch = /@else if \(requestOf\(entry\); as request\) \{([\s\S]*?)\n\s*\} @else \{([\s\S]*?)\n\s*\}/.exec(panelTemplate);
    assert.ok(branch, 'the template has the request branch before the plain notice branch');
    assert.match(branch[1], /<div class="tool-call" data-part="notice" \[attr\.data-key\]="entry\.key" tabindex="-1">/, 'the wrapper keeps the notice\'s part and key for New messages');
    assert.match(branch[1], /<app-approval-request-card \[approval\]="request" \[ctx\]="approvalCtx\(\)" \[request\]="entry\.text" \/>/, 'the card gets the payload, the context and the notice\'s text');
    assert.match(branch[2], /<app-notice-card \[notice\]="entry" \[instanceZone\]="instanceZone\(\)" \/>/, 'any other notice stays a plain notice card');
  });

  it('asks the store for the payload: only a notice entry, and only through liveRequest on the live store\'s approvals', () => {
    assert.match(panel.code, /requestOf\(entry: ChatEntryView\): ApprovalPayload \| undefined \{\s*return entry\.entry === 'notice' \? liveRequest\(entry, this\.live\.store\(\)\?\.approvals \?\? \{\}\) : undefined;\s*\}/);
  });

  it('reads the clock of the card\'s context again at every change of the live store, so a card raised later is not timed at page load', () => {
    assert.match(panel.code, /approvalCtx = computed\(\(\) => \{\s*this\.live\.store\(\);\s*return approvalContext\(Date\.now\(\), this\.instanceZone\(\), this\.onlineDemo\(\), this\.user\(\)\);\s*\}\);/);
  });

  it('gives the plain notice no pending cue: no button, no label text, no request-card token, no pending class, and only the info bar', () => {
    // The digest card's "What I checked" disclosure (Story 18.4) is a button of the digest; it is taken out, as the request class is.
    const bare = noticeTemplate.replace(`[class.request]="notice().kind === 'approval'"`, '').replace(/@if \(notice\(\)\.kind === 'digest' && notice\(\)\.checks\.length > 0\) \{[\s\S]*?\n        \}\n/, '');
    assert.doesNotMatch(bare, /What I checked|what-i-checked|app-check-rows/, 'the digest disclosure was taken out whole');
    assert.match(noticeTemplate, /\[class\.request\]="notice\(\)\.kind === 'approval'"/, 'the request class is the only mention of the kind');
    assert.doesNotMatch(bare, /<button|pending|Approval needed|approval/i, 'the template holds no button, label or pending class');
    assert.doesNotMatch(notice.code, /pending|APPROVAL_TEXTS|approval-request-card|Approval needed/i, 'the sources hold no pending cue');
    assert.doesNotMatch(noticeStyles, /pending|--approval-request-card/, 'the styles read no pending token');
    assert.match(noticeStyles, /border-inline-start: var\(--notice-card-accent-bar\);/, 'the bar is the notice card\'s own');
    assert.match(noticeStyles, /(?:^|\n)\s*\.request \.text,\s*\.digest \.text,\s*\.summary \.text\s*\{\s*white-space: pre-line;\s*\}/, 'the request class (shared with the digest and incident summary cards, Story 23.6) only keeps line breaks');
    assert.match(notice.code, /if \(kind === 'approval' \|\| kind === 'result' \|\| kind === 'summary'\) \{\s*return 'info';\s*\}/, 'the icon is info (also for an incident summary, Story 23.6)');
  });
});
