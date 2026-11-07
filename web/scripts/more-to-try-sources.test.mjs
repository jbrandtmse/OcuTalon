// Tests the shape of the sources of the demo guide's "Other things to try" panel (Story 4.11): the panel and its view never read the
// server's demo mode, move focus once (for the user's own press), send once through the outbox with the text alone, and call none of the
// controls' own APIs; every control is a native button or link whose action is in its click; the guide places the link in row 1 and the
// panel in the finish and after the prompt bar, and the focus rule lists the panel's controls. The browser cases (e2e/guide/more-to-try.spec.ts)
// pin what the running page does; this reads the sources, so a later change cannot break a rule without a test turning red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { sourceFiles } from './source-files.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const files = sourceFiles(join(here, '..', 'src', 'app'), ['.ts']);
const file = (name) => {
  const found = files.find((one) => one.name === name);
  assert.ok(found, `${name} is scanned`);
  return found;
};
const count = (text, pattern) => (text.match(pattern) ?? []).length;

describe('the panel (more-to-try.ts and more-to-try-view.ts)', () => {
  const { code } = file('guide/more-to-try.ts');

  it('never reads the server\'s demo mode', () => {
    assert.doesNotMatch(code, /\bdemoMode\b/);
    assert.doesNotMatch(file('guide/more-to-try-view.ts').code, /\bdemoMode\b/);
  });

  it('has no announcer, no server client, no key binding, and calls none of the controls\' own APIs', () => {
    assert.doesNotMatch(code, /\bAnnouncer\b|\.announce\(|\bApiClient\b|\bHttpClient\b|\(keydown|\(keyup|\(keypress/);
    assert.doesNotMatch(code, /postMailboxSample|postBreakFeed|\bDemoView\b|\.set\(false\)|\.set\(true\)/);
  });

  it('moves focus in one place, and sends once through the outbox with the text alone', () => {
    assert.equal(count(code, /\.focus\(/g), 1);
    const sends = [...code.matchAll(/\boutbox\.send\(([^)]*)\)/g)];
    assert.equal(sends.length, 1);
    assert.equal(sends[0][1].trim(), 'MORE_TO_TRY_TEXTS.rememberPrompt');
    assert.doesNotMatch(code, /fromGuide/);
  });

  it('has native controls only: every button has type="button", and every action is in a (click)', () => {
    const buttons = count(code, /<button\b/g);
    assert.equal(buttons, 1, 'one button in the template');
    assert.equal(count(code, /<button\s[^>]*type="button"/g), buttons);
    assert.equal(count(code, /<a\b/g), 1, 'and one link, to the Documents page');
    assert.match(code, /<a [^>]*routerLink="\/documents"/);
    assert.equal(count(code, /\(click\)=/g), 2, 'each control has a click and nothing else acts');
    assert.equal(count(code, /\(click\)="press\(item\)"/g), 1, 'the one button presses');
    assert.doesNotMatch(code, /\bconstructor\s*\(|ngOnInit|ngAfterViewInit|\beffect\(/, 'nothing runs at creation');
    assert.doesNotMatch(file('guide/more-to-try-room.ts').code, /\.focus\(|\.click\(|\.send\(|\bApiClient\b|\bAnnouncer\b/, 'the room measurement acts on nothing');
  });

  it('names no aria-label and no icon on a control, and no heading', () => {
    const template = /template:\s*`([^`]*)`/.exec(code);
    assert.ok(template, 'the template is inline');
    assert.doesNotMatch(template[1], /aria-label=|<app-icon|<h[1-6]\b/);
  });

  it('is a labelled group with a list, each control marked for the focus rule', () => {
    assert.match(code, /class="group ring-inside" role="group" tabindex="0" data-guide-focus="moreItem" \[attr\.aria-labelledby\]="labelId"/);
    assert.match(code, /<ul class="items">/);
    assert.equal(count(code, /data-guide-focus="moreItem"/g), 3, 'the group and the two kinds of control');
  });

  it('is bounded where the page fills the viewport: its own vertical scroll, with the room that the chat leaves above its floor', () => {
    const framed = /@media \$\{LAYOUT_QUERIES\.framed\} \{\s*:host \{[^}]*\}\s*\.group \{([^}]*)\}/.exec(code);
    assert.ok(framed, 'the bound sits under the framed width query');
    assert.match(framed[1], /overflow-y:\s*auto/);
    assert.match(framed[1], /max-height:\s*max\(var\(--more-window-min\), var\(--more-max\)\)/, 'the window is the measured bound, never under the label line and one control');
    assert.match(code, /:host \{[^}]*--more-max:\s*calc\(100dvh - var\(--more-reserve\)\)/, 'a viewport-based bound stands in until the first measurement');
    assert.match(code, /private readonly room = keepRoom\(this\.host\.nativeElement, this\.floor, \(\) => this\.squeezed\.emit\(\)\);/, 'the component keeps the bound current');
    const room = file('guide/more-to-try-room.ts').code;
    assert.match(room, /windowBound\(group\.getBoundingClientRect\(\)\.height, chat, floor\(\)\)/, 'from the panel and the chat list as they are');
    assert.match(room, /host\.style\.setProperty\(MAX_PROPERTY, `\$\{bound\}px`\)/);
    assert.match(room, /const chat = list\.getBoundingClientRect\(\)\.height;/);
    assert.match(room, /chat < floor\(\) - 1 && getComputedStyle\(group\)\.overflowY === 'auto'/, 'the room is too small only where the panel scrolls on its own');
    assert.match(room, /new ResizeObserver\(later\)/);
    assert.match(room, /window\.addEventListener\('resize', later\)/);
    assert.match(room, /observer\.disconnect\(\)/);
    assert.match(code, /grid-template-columns:\s*repeat\(auto-fill, minmax\(min\(20rem, 100%\), 1fr\)\)/, 'the items are a grid of columns that never outgrow a narrow container');
    assert.match(code, /--more-window-min:\s*calc\(var\(--more-label-height\) \+ var\(--more-gap\) \+ var\(--space-control-height\)\)/, 'the window holds the label line, the gap under it and one control at least');
    assert.match(code, /\.group \{[^}]*gap:\s*var\(--more-gap\)/, 'the gap under the label is the one the window counts');
    assert.match(code, /@media \$\{LAYOUT_QUERIES\.framed\} \{\s*:host \{\s*margin-top:\s*0;\s*--more-gap:\s*0px/, 'where the page fills the viewport there is no margin above the panel and no gap under the label');
    assert.match(code, /:host \{\s*display:\s*block;\s*margin-top:\s*var\(--space-1\);/, 'elsewhere the panel keeps its margin above');
    assert.match(code, /@media \$\{LAYOUT_QUERIES\.framed\} \{[^@]*\.items \{\s*padding-block-end:\s*var\(--space-scroll-gutter\)/, 'the list ends in a gutter that holds the last control\'s ring');
    assert.doesNotMatch(code, /@media \$\{LAYOUT_QUERIES\.stacked\}/, 'the stacked column has no bound of its own: the page scrolls');
  });

  it('hands item 7 to the Heartbeat checklist card\'s heading and presses nothing', () => {
    assert.match(code, /case 'heartbeat':\s*this\.layout\.focusRegion\(RAIL_REGION\);\s*this\.handTo\(\[`#\$\{HEARTBEAT_HEADING_ID\}`\], \(\) => false\);/);
    assert.match(code, /import \{ HEARTBEAT_HEADING_ID \} from '\.\.\/rail\/heartbeat-card\/heartbeat-card-view'/);
  });

  it('uses none of the class names the guide\'s other parts use', () => {
    assert.doesNotMatch(code, /class="[^"]*\b(?:more|line|chip|headline)\b[^"]*"/);
  });

  it('has no transition, no fixed height and width queries only through LAYOUT_QUERIES', () => {
    assert.doesNotMatch(code, /transition\s*:|[^-]height\s*:\s*\d|@media\s*\(/);
  });
});

describe('the guide (demo-guide.ts)', () => {
  const { code } = file('guide/demo-guide.ts');

  it('has the link in row 1 between "About 2 minutes" and Hide guide, with aria-expanded', () => {
    const duration = code.indexOf('class="duration"');
    const link = code.indexOf('data-guide-focus="moreLink"');
    const hide = code.indexOf('data-guide-focus="hide"');
    assert.ok(duration > 0 && link > duration && hide > link, 'duration < link < hide');
    const button = /<button\s[^>]*data-guide-focus="moreLink"[^>]*>/.exec(code.replace(/\s+/g, ' '));
    assert.ok(button, 'the link is a button');
    assert.match(button[0], /type="button"/);
    assert.match(button[0], /\[attr\.aria-expanded\]="moreOpen\(\)"/);
    assert.match(button[0], /\[attr\.aria-controls\]="panelShown\(\) \? morePanelId : null"/);
    assert.match(code, /class="link more-link"/);
  });

  it('has the finish hold the panel after the links and before the Try it yourself row', () => {
    const links = code.indexOf('class="finish-links"');
    const panel = code.indexOf('<app-more-to-try', links);
    const row = code.indexOf('<app-try-it-row');
    assert.ok(links > 0 && panel > links && row > panel, 'links < panel < row');
  });

  it('has the prompt branch hold the panel after the prompt bar, and the panel nowhere else', () => {
    const prompt = code.indexOf('class="prompt"');
    const panel = code.lastIndexOf('<app-more-to-try');
    assert.ok(prompt > 0 && panel > prompt, 'the prompt bar < the panel');
    assert.equal(count(code, /<app-more-to-try/g), 2, 'one in the finish and one after the prompt bar');
    assert.ok(code.indexOf('<app-break-feed-box') > panel, 'both are in the main column, before the box');
  });

  it('lays the finish out compactly: under its first row where the page is framed and short, with Run again beside Try it yourself from 1024 to 1279px', () => {
    const styles = /styles:\s*`([\s\S]*?)`,\n\}\)/.exec(code);
    assert.ok(styles, 'the styles are inline');
    const css = styles[1];
    const compact = /@media \$\{HEIGHT_QUERIES\.compact\} and \$\{LAYOUT_QUERIES\.framed\} \{\s*\.main \{([^}]*)\}\s*\.finish \{([^}]*)\}/.exec(css);
    assert.ok(compact, 'the short framed band places the finish under row 1');
    assert.match(compact[1], /justify-content:\s*flex-start/, 'row 1 starts at the left edge');
    assert.match(compact[1], /row-gap:\s*var\(--space-1\)/);
    assert.match(compact[2], /flex-basis:\s*100%/, 'and the finish takes the whole width');
    const drawer = /@media \$\{LAYOUT_QUERIES\.drawer\} \{([\s\S]*?)\n    \}\n/.exec(css);
    assert.ok(drawer, 'the drawer band has its own rules');
    assert.match(drawer[1], /\.finish \{[^}]*display:\s*grid;[^}]*grid-template-columns:\s*minmax\(0, 1fr\) auto/);
    assert.match(drawer[1], /\.finish > \* \{\s*grid-column:\s*1 \/ -1/);
    assert.match(drawer[1], /\.finish > app-try-it-row \{\s*grid-column:\s*1;\s*margin-top:\s*calc\(var\(--space-3\) \* -1\);/, 'the row\'s own margin gives way to the finish\'s gap');
    assert.match(drawer[1], /\.finish-done \{\s*font-size:\s*var\(--type-body-sm-font-size\);\s*line-height:\s*var\(--type-body-sm-line-height\);/, 'the finish line is body-sm');
    assert.match(drawer[1], /\.finish > \.run-again \{\s*grid-column:\s*2;/);
  });

  it('leaves out "About 2 minutes" once the guide is finished, so that row 1 stays on one line at 1280px', () => {
    assert.match(code, /<div class="row1" \[class\.finished\]="guide\.finish !== undefined">/);
    assert.match(code, /\.row1\.finished > \.duration \{\s*display:\s*none;\s*\}/);
    assert.match(code, /\.row1\.finished > \.more-link \{\s*margin-inline-start:\s*auto;\s*\}/, 'the link and Hide guide stay at the row\'s right end without the duration');
  });

  it('lists the panel\'s controls among the finish\'s parts for the focus rule', () => {
    assert.match(code, /const FINISH_PARTS = \[[^\]]*'moreItem'[^\]]*\]/);
  });

  it('opens the panel from the user\'s choice, else the finish, and resets the choice at a new finish', () => {
    assert.match(code, /moreOpen = computed\(\(\) => this\.chosen\(\) \?\? \(this\.finished\(\) && !this\.compact\(\) && !this\.squeezed\(\)\)\)/, 'the user\'s choice, else the finish outside the band and where the room allows');
    assert.match(code, /\(squeezed\)="squeezed\.set\(true\)"/, 'the panel says when the room is too small for it');
    assert.match(code, /compact = computed\(\(\) => inCompactBand\(this\.viewport\(\), this\.banners\(\)\)\)/, 'the band is the height left after the banners');
    assert.match(code, /floor = computed\(\(\) => chatFloor\(this\.compact\(\)\)\)/);
    assert.match(code, /<app-more-to-try [^>]*\[floor\]="floor\(\)"/);
    assert.match(code, /\[window\.innerHeight, slot\?\.offsetHeight \?\? 0\]/, 'the viewport\'s height and the banner slot\'s');
    assert.match(code, /toggleMore\(\): void \{\s*this\.chosen\.set\(!this\.moreOpen\(\)\);/);
    assert.match(code, /view\?\.finished === true && this\.last\?\.finished !== true\) \{\s*this\.chosen\.set\(undefined\);/);
    assert.match(code, /\(pressed\)="chosen\.set\(true\)"/);
  });

  it('takes its items from the server\'s list through the registry, and decides nothing else', () => {
    assert.match(code, /items = computed\(\(\) => itemsFor\(this\.view\(\)\?\.features\)\)/);
    assert.doesNotMatch(code, /\bdemoMode\b/);
  });
});
