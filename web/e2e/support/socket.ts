import { randomBytes } from 'node:crypto';
import { connect, type Socket } from 'node:net';

import type { Page, WebSocketRoute } from '@playwright/test';

/**
 * What the specs of the live-events WebSocket (Story 31.1; U-173) share. The server's address is the shell's: the WebSocket is
 * reached at /ocutalon/OcuTalon.Web.Live.cls, beside the polling, which stays the contract.
 *
 * - blockLiveSocket(page) closes every socket the page opens at once, so a spec that steers delivery through the polls (a poll held,
 *   one event per poll, an event dropped from an answer) keeps the polls as the only live path. Call it before the page loads.
 * - proxyLiveSocket(page) lets the page's sockets through and keeps them, so that the test can close one.
 * - socketFrames(page) records the frames the page's sockets receive.
 * - rawUpgrade(...) opens a socket the way a script does, over a plain TCP connection, so that the Origin and the cookie are the
 *   test's own, and reads the frames and the close frame.
 */

/** The address of the live-events WebSocket, whatever the origin. */
export const LIVE_SOCKET = /\/ocutalon\/OcuTalon\.Web\.Live\.cls/;

/** Closes every live-events socket of the page as it opens. Call it before the page loads. */
export async function blockLiveSocket(page: Page): Promise<void> {
  await page.routeWebSocket(LIVE_SOCKET, (socket) => {
    void socket.close();
  });
}

/** The sockets that proxyLiveSocket let through, in the order they opened, with the URLs they opened with. */
export interface ProxiedSockets {
  readonly urls: string[];
  /** Closes the n-th socket (0 for the first) from the page's side of the proxy. */
  close(n: number): Promise<void>;
}

/** Lets the page's live-events sockets reach the server and keeps them, for the test to close. Call it before the page loads. */
export async function proxyLiveSocket(page: Page): Promise<ProxiedSockets> {
  const kept: WebSocketRoute[] = [];
  const urls: string[] = [];
  await page.routeWebSocket(LIVE_SOCKET, (socket) => {
    kept.push(socket);
    urls.push(socket.url());
    socket.connectToServer();
  });
  return {
    urls,
    close: async (n: number) => {
      await kept[n]!.close();
    },
  };
}

/** One frame that a page's socket received. */
export interface ReceivedFrame {
  /** The test's clock when the frame was seen (Date.now()). */
  at: number;
  /** The text of the frame. */
  text: string;
}

/** Records the frames that the page's sockets receive and the URLs they open with. Call it before the page loads. */
export function socketFrames(page: Page): { frames: ReceivedFrame[]; urls: string[] } {
  const frames: ReceivedFrame[] = [];
  const urls: string[] = [];
  page.on('websocket', (socket) => {
    if (!LIVE_SOCKET.test(socket.url())) return;
    urls.push(socket.url());
    socket.on('framereceived', (frame) => frames.push({ at: Date.now(), text: typeof frame.payload === 'string' ? frame.payload : frame.payload.toString('utf8') }));
  });
  return { frames, urls };
}

/** The result of a raw upgrade, read as it goes. */
export interface RawUpgrade {
  /** The status line of the server's answer ("" until it came). */
  readonly status: string;
  /** The data frames (text) that came, with their times. */
  readonly frames: ReceivedFrame[];
  /** When the close frame came (Date.now()), 0 while none has. */
  readonly closeFrameAt: number;
  /** True once the connection has ended. */
  readonly ended: boolean;
  /** Sends a close frame, as a browser does when the page closes its socket. */
  sendClose(): void;
  /** Ends the connection. */
  close(): void;
}

/**
 * Opens GET <path> as a WebSocket upgrade over TCP to baseURL's host. origin and cookie are sent as given (left out when
 * undefined), so that a spec can send the wrong Origin or none, or no session. It returns once the server's answer has begun (or
 * after `wait` ms), and goes on collecting frames until close().
 */
export async function rawUpgrade(options: { baseURL: string; path: string; origin?: string; cookie?: string; wait?: number }): Promise<RawUpgrade> {
  const url = new URL(options.baseURL);
  const frames: ReceivedFrame[] = [];
  const state = { status: '', closeFrameAt: 0, ended: false };
  let buffer: Buffer = Buffer.alloc(0);
  let headersDone = false;
  const socket: Socket = connect({ host: url.hostname, port: Number(url.port || 80) });
  const lines = [
    `GET ${options.path} HTTP/1.1`,
    `Host: ${url.host}`,
    'Upgrade: websocket',
    'Connection: Upgrade',
    `Sec-WebSocket-Key: ${randomBytes(16).toString('base64')}`,
    'Sec-WebSocket-Version: 13',
    ...(options.origin === undefined ? [] : [`Origin: ${options.origin}`]),
    ...(options.cookie === undefined ? [] : [`Cookie: ${options.cookie}`]),
    '',
    '',
  ];
  let answered: () => void = () => undefined;
  const first = new Promise<void>((resolve) => {
    answered = resolve;
  });
  const readFrames = (): void => {
    for (;;) {
      if (buffer.length < 2) return;
      const opcode = buffer[0]! & 0x0f;
      let length = buffer[1]! & 0x7f;
      let offset = 2;
      if (length === 126) {
        if (buffer.length < 4) return;
        length = buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (buffer.length < 10) return;
        length = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }
      if (buffer.length < offset + length) return;
      const payload = buffer.subarray(offset, offset + length);
      buffer = buffer.subarray(offset + length);
      if (opcode === 1) frames.push({ at: Date.now(), text: payload.toString('utf8') });
      if (opcode === 8 && state.closeFrameAt === 0) state.closeFrameAt = Date.now();
    }
  };
  socket.on('data', (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk]);
    if (!headersDone) {
      const end = buffer.indexOf('\r\n\r\n');
      if (end < 0) return;
      state.status = buffer.subarray(0, buffer.indexOf('\r\n')).toString('latin1');
      headersDone = true;
      buffer = buffer.subarray(end + 4);
      answered();
    }
    readFrames();
  });
  socket.on('error', () => {
    state.ended = true;
    answered();
  });
  socket.on('close', () => {
    state.ended = true;
    answered();
  });
  socket.on('connect', () => socket.write(lines.join('\r\n')));
  await Promise.race([first, new Promise<void>((resolve) => setTimeout(resolve, options.wait ?? 5000))]);
  return {
    get status() {
      return state.status;
    },
    frames,
    get closeFrameAt() {
      return state.closeFrameAt;
    },
    get ended() {
      return state.ended;
    },
    sendClose: () => {
      socket.write(Buffer.concat([Buffer.from([0x88, 0x80]), randomBytes(4)]));
    },
    close: () => {
      socket.destroy();
    },
  };
}
