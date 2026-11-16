// Tests the controls under the reply to a sent file (src/app/chat/file-reply-view.ts, Story 25.6): the four fixed strings (the two that the Planner approved
// verbatim, P1, and the two from the UX spec), and which control a turn shows. Also that the control's code is lazy: neither ocutalon-reply.ts nor the memory
// card import file-reply or pin-photo-text statically, and the 409 pin_photo sentence is the server's (Web.Api MESSAGEPINPHOTO). The module is imported as it is:
// Node strips its types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', 'src', 'app');
const { FILE_REPLY_TEXTS, controlsOf } = await import(pathToFileURL(join(app, 'chat', 'file-reply-view.ts')).href);
const { PIN_PHOTO_TEXT } = await import(pathToFileURL(join(app, 'rail', 'memory-card', 'pin-photo-text.ts')).href);

describe('the fixed strings', () => {
  it('are the approved words, verbatim', () => {
    assert.deepEqual(
      { ...FILE_REPLY_TEXTS },
      {
        addToDocuments: 'Add to documents',
        added: 'Added to your documents.',
        addFailed: "Couldn't add it to your documents. Nothing was changed.",
        savedToMemory: 'Saved to memory',
      },
    );
  });

  it('keep the 409 pin_photo sentence of the server', () => {
    const api = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Web', 'Api.cls'), 'utf8');
    const server = /^Parameter MESSAGEPINPHOTO = "([^"]*)";$/m.exec(api);
    assert.ok(server, 'Web.Api has MESSAGEPINPHOTO');
    assert.equal(PIN_PHOTO_TEXT, server[1]);
    assert.equal(PIN_PHOTO_TEXT, "This memory came from a photo, so it can't be pinned.");
  });
});

describe('controlsOf', () => {
  it('shows the button for a document that was read and can be added', () => {
    assert.deepEqual(controlsOf({ read: 1, addable: 1 }, undefined, false), { add: true, saved: false });
  });

  it('shows the chip for a photo whose caption was saved, and no button', () => {
    assert.deepEqual(controlsOf({ read: 1, addable: 0 }, { memoryRef: 'm', text: 't' }, false), { add: false, saved: true });
    assert.deepEqual(controlsOf(undefined, { memoryRef: 'm', text: 't' }, false), { add: false, saved: true });
  });

  it('shows nothing for a failed read, a photo with no caption, a turn with neither and a document that is not addable', () => {
    assert.deepEqual(controlsOf({ read: 0, addable: 0 }, undefined, false), { add: false, saved: false });
    assert.deepEqual(controlsOf({ read: 1, addable: 0 }, undefined, false), { add: false, saved: false });
    assert.deepEqual(controlsOf({ read: 0, addable: 1 }, undefined, false), { add: false, saved: false });
    assert.deepEqual(controlsOf(undefined, undefined, false), { add: false, saved: false });
    assert.deepEqual(controlsOf({}, undefined, false), { add: false, saved: false });
  });

  it('shows a viewer no button, for a document that was read and can be added, and keeps the chip', () => {
    assert.deepEqual(controlsOf({ read: 1, addable: 1 }, undefined, true), { add: false, saved: false });
    assert.deepEqual(controlsOf({ read: 1, addable: 1 }, { memoryRef: 'm', text: 't' }, true), { add: false, saved: true });
    assert.deepEqual(controlsOf({ read: 1, addable: 0 }, { memoryRef: 'm', text: 't' }, true), { add: false, saved: true });
    assert.deepEqual(controlsOf(undefined, undefined, true), { add: false, saved: false });
  });
});

describe('the sources of the controls', () => {
  const source = (...parts) => readFileSync(join(app, ...parts), 'utf8');

  it('the reply loads file-reply only with a dynamic import', () => {
    const reply = source('chat', 'ocutalon-reply.ts');
    assert.match(reply, /import\('\.\/file-reply'\)/);
    assert.doesNotMatch(reply, /from '\.\/file-reply(-view)?'/);
    assert.match(reply, /ngComponentOutlet/);
  });

  it('the memory card loads pin-photo-text only with a dynamic import', () => {
    const card = source('rail', 'memory-card', 'memory-card.ts');
    assert.match(card, /import\('\.\/pin-photo-text'\)/);
    assert.doesNotMatch(card, /from '\.\/pin-photo-text'/);
    assert.doesNotMatch(source('rail', 'memory-card', 'memory-card-view.ts'), /came from a photo/, 'the sentence is in the lazy module only');
  });

  it('the button is the shared ServerButton (the busy rule) that posts the file ref, and each line is spoken once through the Announcer (the page has one live region)', () => {
    const component = source('chat', 'file-reply.ts');
    assert.match(component, /import \{ ServerButton \} from '\.\.\/shared\/server-button';/);
    assert.match(component, /<app-server-button variant="secondary" \[action\]="add">\{\{ texts\.addToDocuments \}\}<\/app-server-button>/, 'a native button with a spinner, aria-busy and aria-disabled while the post is out');
    assert.doesNotMatch(component, /<button\b/, 'no hand-made button beside it');
    assert.equal([...component.matchAll(/<p class="line[^"]*"/g)].length, 2, 'the added line and the failed line');
    assert.match(component, /<p class="line added" tabindex="-1">\{\{ texts\.added \}\}<\/p>/, 'the added line can take focus');
    assert.match(component, /afterNextRender\(\(\) => this\.host\.nativeElement\.querySelector<HTMLElement>\('\.added'\)\?\.focus\(\)/, 'and takes it once drawn, because the pressed button is gone');
    assert.doesNotMatch(component.replace(/\/\*[\s\S]*?\*\//g, ''), /role=|aria-live/, 'no live role of its own');
    assert.match(component, /this\.announcer\.announce\(FILE_REPLY_TEXTS\.added\)/);
    assert.match(component, /this\.announcer\.announce\(FILE_REPLY_TEXTS\.addFailed\)/);
    assert.match(component, /addDocumentFromFile\(ref\)/);
  });
});
