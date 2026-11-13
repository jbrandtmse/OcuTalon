// Tests the chat's file view model (src/app/chat/files-view.ts, Story 25.3): the pre-check of a file by its size, its emptiness and its extension (a name that
// ends .pdf passes whatever its bytes; the server reads the bytes), the refusal sentences, the line under a sent file, the four combinations of the paperclip
// and the drop, and that the page's texts are the ones Core.Files holds (read from the class source). The module is imported as it is: Node strips its types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { ACCEPT_FILES, FILE_MAX, FILES_TEXTS, checkFile, fileControls, fileLine, refusalText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'files-view.ts')).href);
const FILES = readFileSync(join(here, '..', '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Core', 'Files.cls'), 'utf8');

/** The value of a string parameter of Core.Files. */
const parameter = (name) => {
  const found = new RegExp(`^Parameter ${name} = "([^"]*)";$`, 'm').exec(FILES);
  assert.ok(found, `Core.Files has the parameter ${name}`);
  return found[1];
};

describe('checkFile', () => {
  it('accepts each extension in any case, whatever the bytes are, up to 10,485,760 bytes', () => {
    for (const name of ['a.pdf', 'A.PDF', 'b.docx', 'c.jpg', 'c.JPEG', 'd.png', 'e.f.png', 'x.pdf ']) {
      assert.equal(checkFile({ name: name.trim(), size: 1 }), '', name);
    }
    assert.equal(checkFile({ name: 'big.pdf', size: FILE_MAX }), '');
    assert.equal(FILE_MAX, 10485760);
  });

  it('refuses a file over the limit as too_large before anything else', () => {
    assert.equal(checkFile({ name: 'big.pdf', size: FILE_MAX + 1 }), 'too_large');
    assert.equal(checkFile({ name: 'big.exe', size: FILE_MAX + 1 }), 'too_large', 'the size comes before the extension');
  });

  it('refuses a file of 0 bytes as empty, before its extension', () => {
    assert.equal(checkFile({ name: 'a.pdf', size: 0 }), 'empty');
    assert.equal(checkFile({ name: 'a.txt', size: 0 }), 'empty');
  });

  it('refuses any other extension, and a name with none, as wrong_type', () => {
    for (const name of ['a.txt', 'a.md', 'a.gif', 'a.doc', 'a.exe', 'a.html', 'noextension', 'a.pdf.exe', '.', '']) {
      assert.equal(checkFile({ name, size: 5 }), 'wrong_type', JSON.stringify(name));
    }
  });
});

describe('the texts', () => {
  it('are the sentences of the Planner\'s ruling', () => {
    assert.deepEqual(FILES_TEXTS, {
      send: 'Send a file',
      tooLarge: 'That file is {size}; the limit is 10 MB.',
      unreadable: "I couldn't read that file: {reason}.",
      reasons: { wrong_type: "it isn't a PDF, Word (.docx), JPEG or PNG file", empty: 'the file is empty' },
      offOnDemo: 'Sending files is off on the online demo. It works on your own install.',
      notSent: 'File not sent',
    });
    assert.equal(ACCEPT_FILES, '.pdf,.docx,.jpg,.jpeg,.png');
  });

  it('are equal to the parameters of Core.Files', () => {
    assert.equal(FILES_TEXTS.tooLarge, parameter('TEXTTOOLARGE'));
    assert.equal(FILES_TEXTS.unreadable, parameter('TEXTUNREADABLE'));
    assert.equal(FILES_TEXTS.reasons.wrong_type, parameter('REASONWRONGTYPE'));
    assert.equal(FILES_TEXTS.reasons.empty, parameter('REASONEMPTY'));
    assert.equal(FILES_TEXTS.offOnDemo, parameter('TEXTOFFONDEMO'));
  });

  it('keep the fixed no-reader reply out of the page\'s constants and equal to the ruled row 14 in Core.Files', () => {
    assert.equal(parameter('TEXTNOREADER'), "I got {name}, but I can't read files yet.");
    assert.equal(JSON.stringify(FILES_TEXTS).includes("can't read files yet"), false);
  });
});

describe('refusalText', () => {
  it('writes the size as the Documents page does', () => {
    assert.equal(refusalText('too_large', 14 * 1048576), 'That file is 14 MB; the limit is 10 MB.');
    assert.equal(refusalText('too_large', FILE_MAX + 1), 'That file is 10.1 MB; the limit is 10 MB.');
  });

  it('frames the reason of any other code, and reads an unknown code as wrong_type', () => {
    assert.equal(refusalText('empty', 0), "I couldn't read that file: the file is empty.");
    assert.equal(refusalText('wrong_type', 5), "I couldn't read that file: it isn't a PDF, Word (.docx), JPEG or PNG file.");
    assert.equal(refusalText('zz', 5), refusalText('wrong_type', 5));
  });
});

describe('fileLine', () => {
  it('is the name, a middle dot and the size, and keeps markup as it is', () => {
    assert.equal(fileLine('report.pdf', 2202009), 'report.pdf \u00B7 2.1 MB');
    assert.equal(fileLine('<b>x</b>.pdf', 1000), '<b>x</b>.pdf \u00B7 1 KB');
  });
});

describe('fileControls', () => {
  it('shows the paperclip only while the install can read a file and it is not the online demo', () => {
    assert.deepEqual(fileControls(true, false), { paperclip: true, drop: 'send' });
    assert.deepEqual(fileControls(false, false), { paperclip: false, drop: 'none' });
    assert.deepEqual(fileControls(true, true), { paperclip: false, drop: 'off' });
    assert.deepEqual(fileControls(false, true), { paperclip: false, drop: 'off' });
  });
});
