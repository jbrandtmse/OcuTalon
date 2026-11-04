// Tests the page's live-events socket (src/app/live/live-socket.ts, Story 31.1) with a fake clock and a fake WebSocket: the address with
// both cursors over ws: and wss:; frames reaching onEvents, a malformed or foreign frame ignored; frames dropped while the page is not
// accepting them (contact not ok); the reconnect 1 s after a socket that delivered a frame, the backoff 1, 2, 4 ... 30 s after
// sockets that did not; the silence watchdog; stop() closing, cancelling a pending reconnect and never opening again; a second start()
// opening nothing; and the online demo constructing no WebSocket at all.
// The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { fakeClock } from './fake-clock.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'live', 'live-socket.ts');
const { LiveSocket, MAX_BACKOFF_MS, RECONNECT_MS, SILENT_MS, SOCKET_PATH } = await import(pathToFileURL(source).href);

/** A socket on a fake clock whose opened WebSockets are recorded; accepting and the cursors are the test's to change. */
function setup(overrides = {}) {
  const clock = fakeClock();
  const state = { accepting: true, cursors: { session: 3, instance: 7 }, throwOnOpen: false };
  const opened = [];
  const received = [];
  const socket = new LiveSocket({
    open: (url) => {
      if (state.throwOnOpen) throw new Error('refused');
      const fake = { url, closed: 0, onmessage: null, onclose: null, onerror: null, close() { this.closed += 1; } };
      opened.push(fake);
      return fake;
    },
    setTimeout: (handler, ms) => clock.setTimeout(handler, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    location: { protocol: 'http:', host: 'localhost:52773' },
    cursors: () => state.cursors,
    accepting: () => state.accepting,
    onEvents: (response) => received.push(response),
    ...overrides,
  });
  return { clock, opened, received, socket, state };
}

const frame = (events = [], epoch = 'E1') => ({ data: JSON.stringify({ epoch, events }) });

describe('the constants', () => {
  it('are the shell address, a 1 s reconnect, a 30 s ceiling and a 60 s silence', () => {
    assert.equal(SOCKET_PATH, '/ocutalon/OcuTalon.Web.Live.cls');
    assert.equal(RECONNECT_MS, 1000);
    assert.equal(MAX_BACKOFF_MS, 30_000);
    assert.equal(SILENT_MS, 60_000);
  });
});

describe('opening', () => {
  it('opens ws: with both cursors for an http page', () => {
    const { opened, socket } = setup();
    socket.start({ onlineDemo: false });
    assert.deepEqual(opened.map((one) => one.url), ['ws://localhost:52773/ocutalon/OcuTalon.Web.Live.cls?after=3&afterInstance=7']);
  });

  it('opens wss: for an https page', () => {
    const { opened, socket } = setup({ location: { protocol: 'https:', host: 'example.test' } });
    socket.start({ onlineDemo: false });
    assert.equal(opened[0].url, 'wss://example.test/ocutalon/OcuTalon.Web.Live.cls?after=3&afterInstance=7');
  });

  it('opens once: a second start opens nothing', () => {
    const { opened, socket } = setup();
    socket.start({ onlineDemo: false });
    socket.start({ onlineDemo: false });
    assert.equal(opened.length, 1);
  });

  it('constructs no WebSocket on the online demo, now or ever', () => {
    const { clock, opened, socket } = setup();
    socket.start({ onlineDemo: true });
    socket.start({ onlineDemo: false });
    clock.advance(10 * SILENT_MS);
    assert.equal(opened.length, 0);
    assert.equal(clock.pending, 0, 'and arms no timer');
  });

  it('opens with the cursors of the moment of each attempt', () => {
    const { clock, opened, socket, state } = setup();
    socket.start({});
    state.cursors = { session: 10, instance: 12 };
    opened[0].onclose();
    clock.advance(RECONNECT_MS);
    assert.equal(opened[1].url.split('?')[1], 'after=10&afterInstance=12');
  });

  it('treats a WebSocket that cannot be constructed as a failed attempt, with the backoff', () => {
    const { clock, opened, socket, state } = setup();
    state.throwOnOpen = true;
    socket.start({});
    state.throwOnOpen = false;
    clock.advance(RECONNECT_MS - 1);
    assert.equal(opened.length, 0);
    clock.advance(1);
    assert.equal(opened.length, 1);
  });
});

describe('frames', () => {
  it('reach onEvents as parsed', () => {
    const { opened, received, socket } = setup();
    socket.start({});
    const event = { seq: 4, stream: 'session', ts: 't', type: 'reminder', payload: {} };
    opened[0].onmessage(frame([event]));
    opened[0].onmessage(frame([]));
    assert.deepEqual(received, [{ epoch: 'E1', events: [event] }, { epoch: 'E1', events: [] }]);
  });

  it('are ignored when malformed, not text or not an events body', () => {
    const { opened, received, socket } = setup();
    socket.start({});
    opened[0].onmessage({ data: '{not json' });
    opened[0].onmessage({ data: 42 });
    opened[0].onmessage({ data: 'null' });
    opened[0].onmessage({ data: '{"epoch": 1, "events": []}' });
    opened[0].onmessage({ data: '{"epoch": "E1"}' });
    opened[0].onmessage({ data: '[]' });
    assert.deepEqual(received, []);
  });

  it('are dropped while the page is not accepting them, and handed on again once it is', () => {
    const { opened, received, socket, state } = setup();
    socket.start({});
    state.accepting = false;
    opened[0].onmessage(frame([{ seq: 4 }]));
    assert.deepEqual(received, [], 'contact not ok: nothing is applied');
    state.accepting = true;
    opened[0].onmessage(frame([{ seq: 5 }]));
    assert.equal(received.length, 1);
  });
});

describe('reconnecting', () => {
  it('opens again 1 s after a socket that delivered a frame, every time', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    for (let round = 1; round <= 4; round += 1) {
      opened[round - 1].onmessage(frame());
      opened[round - 1].onclose();
      clock.advance(RECONNECT_MS - 1);
      assert.equal(opened.length, round, 'not yet');
      clock.advance(1);
      assert.equal(opened.length, round + 1, 'after 1 s');
    }
  });

  it('backs off 1, 2, 4 ... 30 s after sockets that delivered nothing, and starts again at 1 s after one that did', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    const waits = [];
    for (let round = 0; round < 8; round += 1) {
      const before = opened.length;
      opened[before - 1].onerror();
      opened[before - 1].onclose?.();
      let waited = 0;
      while (opened.length === before && waited < 2 * MAX_BACKOFF_MS) {
        clock.advance(1000);
        waited += 1000;
      }
      waits.push(waited);
    }
    assert.deepEqual(waits, [1000, 2000, 4000, 8000, 16_000, 30_000, 30_000, 30_000]);
    opened[opened.length - 1].onmessage(frame());
    opened[opened.length - 1].onclose();
    const before = opened.length;
    clock.advance(RECONNECT_MS);
    assert.equal(opened.length, before + 1, 'a delivered frame resets the wait to 1 s');
    opened[opened.length - 1].onclose();
    clock.advance(RECONNECT_MS);
    assert.equal(opened.length, before + 2, 'and the next failed socket starts the backoff at 1 s again');
  });

  it('counts the error and the close of one socket as one ending', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    const { onclose, onerror } = opened[0];
    onerror();
    onclose();
    clock.advance(RECONNECT_MS * 3);
    assert.equal(opened.length, 2, 'one new socket, not two');
  });

  it('closes a socket that is silent for SILENT_MS and opens another after the backoff', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    clock.advance(SILENT_MS - 1);
    assert.equal(opened[0].closed, 0);
    clock.advance(1);
    assert.equal(opened[0].closed, 1, 'closed at 60 s');
    assert.equal(opened.length, 1);
    clock.advance(RECONNECT_MS);
    assert.equal(opened.length, 2, 'and opened again after the first backoff');
  });

  it('counts every frame, a heartbeat too, as life', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    for (let beat = 0; beat < 5; beat += 1) {
      clock.advance(SILENT_MS - 1000);
      opened[0].onmessage(frame());
    }
    assert.equal(opened[0].closed, 0);
    assert.equal(opened.length, 1);
  });

  it('ignores a socket that was replaced or closed by the page', () => {
    const { clock, opened, received, socket } = setup();
    socket.start({});
    const { onclose, onmessage } = opened[0];
    onclose();
    clock.advance(RECONNECT_MS);
    onmessage(frame([{ seq: 4 }]));
    assert.deepEqual(received, []);
    assert.equal(opened.length, 2);
  });
});

describe('stop', () => {
  it('closes the socket, clears every timer and never opens again', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    socket.stop();
    assert.equal(opened[0].closed, 1);
    assert.equal(clock.pending, 0);
    assert.equal(opened[0].onmessage, null);
    clock.advance(10 * MAX_BACKOFF_MS);
    assert.equal(opened.length, 1);
    socket.start({});
    assert.equal(opened.length, 1, 'a start after the stop opens nothing');
  });

  it('cancels a pending reconnect', () => {
    const { clock, opened, socket } = setup();
    socket.start({});
    opened[0].onclose();
    assert.equal(clock.pending, 1);
    socket.stop();
    assert.equal(clock.pending, 0);
    clock.advance(10 * MAX_BACKOFF_MS);
    assert.equal(opened.length, 1);
  });

  it('before any start leaves nothing to open', () => {
    const { clock, opened, socket } = setup();
    socket.stop();
    socket.start({});
    clock.advance(SILENT_MS);
    assert.equal(opened.length, 0);
  });
});
