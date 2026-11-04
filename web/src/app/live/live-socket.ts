/**
 * The page's WebSocket for live events (Story 31.1; AD-12, AD-13). A framework-free class: it imports only types and uses only
 * erasable TypeScript syntax, so Node runs it as it is, and the WebSocket factory, the timers and the page's location are injected.
 *
 * - The socket is the second live path, beside polling, which stays the contract: it only delivers sooner. Each text frame is the
 *   body of `GET /events`, `{epoch, events}`, and is handed to `onEvents` only while `accepting()` is true (the page's contact is
 *   `ok`), so the socket applies nothing that polling would not. A frame that is not that body is ignored.
 * - start() opens the socket once, after the first snapshot, with the cursors of that moment, and constructs nothing on the online
 *   demo (`snapshot.onlineDemo === true`), where polling is the only path (S13).
 * - A socket that closes or fails is opened again in the background with the cursors of that moment: RECONNECT_MS after a socket
 *   that delivered a frame, otherwise after a backoff that starts at RECONNECT_MS and doubles up to MAX_BACKOFF_MS. A socket that
 *   delivers nothing for SILENT_MS is closed and counts as failed (a refused upgrade can stay open with no frame).
 * - stop() closes the socket, clears every timer and never opens again.
 * - It shows nothing, announces nothing and moves no focus.
 */
import type { EventsResponse } from '../api/api-types';

/** The shell's address of the live-events WebSocket. */
export const SOCKET_PATH = '/ocutalon/OcuTalon.Web.Live.cls';

/** How long to wait before opening again after a socket that delivered a frame, and the first backoff after one that did not. */
export const RECONNECT_MS = 1000;

/** The longest backoff between two attempts. */
export const MAX_BACKOFF_MS = 30_000;

/** How long a socket may deliver no frame (the server sends a heartbeat every 25 s) before the page closes it. */
export const SILENT_MS = 60_000;

/** The part of a WebSocket that the class uses. */
export interface SocketLike {
  onmessage: ((event: MessageEvent) => void) | null;
  onclose: ((event: CloseEvent) => void) | null;
  onerror: ((event: Event) => void) | null;
  close(): void;
}

/** What a LiveSocket needs, injected so that a test can run it on a fake clock with a fake WebSocket. */
export interface LiveSocketOptions {
  /** Opens a WebSocket to the URL (the page passes `new WebSocket(url)`). */
  open: (url: string) => SocketLike;
  /** Arms a timer and returns its handle (the page passes globalThis.setTimeout). */
  setTimeout: (handler: () => void, ms: number) => unknown;
  /** Clears a timer that setTimeout armed, by its handle. */
  clearTimeout: (handle: unknown) => void;
  /** The page's protocol (`http:` or `https:`) and host, read each time a socket opens. */
  location: { protocol: string; host: string };
  /** The cursors of the live store now, once there is one. */
  cursors: () => { session: number; instance: number } | undefined;
  /** True while frames may be applied. */
  accepting: () => boolean;
  /** Takes a frame in. */
  onEvents: (response: EventsResponse) => void;
}

/** Keeps the page's live-events socket open, as the module doc says; LiveState owns one. */
export class LiveSocket {
  private readonly options: LiveSocketOptions;
  private started = false;
  private stopped = false;
  private current: SocketLike | undefined = undefined;
  private delivered = false;
  private backoff = RECONNECT_MS;
  private reconnectTimer: unknown = undefined;
  private silenceTimer: unknown = undefined;

  constructor(options: LiveSocketOptions) {
    this.options = options;
  }

  /** Opens the socket, once; a later call does nothing. On the online demo it constructs no WebSocket at all. */
  start(snapshot: { onlineDemo?: boolean }): void {
    if (this.started || this.stopped) {
      return;
    }
    this.started = true;
    if (snapshot.onlineDemo === true) {
      return;
    }
    this.connect();
  }

  /** Closes the socket and clears every timer; the socket is never opened again. */
  stop(): void {
    this.stopped = true;
    this.cancelTimers();
    this.release();
  }

  private connect(): void {
    this.reconnectTimer = undefined;
    if (this.stopped) {
      return;
    }
    const cursors = this.options.cursors();
    const { protocol, host } = this.options.location;
    let socket: SocketLike | undefined = undefined;
    if (cursors !== undefined) {
      try {
        const scheme = protocol === 'https:' ? 'wss:' : 'ws:';
        socket = this.options.open(`${scheme}//${host}${SOCKET_PATH}?after=${cursors.session}&afterInstance=${cursors.instance}`);
      } catch {
        socket = undefined;
      }
    }
    this.delivered = false;
    if (socket === undefined) {
      this.scheduleReconnect();
      return;
    }
    const mine = socket;
    this.current = mine;
    mine.onmessage = (event) => {
      if (this.current === mine) {
        this.take(event.data);
      }
    };
    mine.onclose = () => this.ended(mine);
    mine.onerror = () => this.ended(mine);
    this.armSilence(mine);
  }

  /** One frame arrived: the silence timer starts again, and a good frame is handed on while the page accepts it. */
  private take(data: unknown): void {
    if (this.current === undefined) {
      return;
    }
    this.delivered = true;
    this.armSilence(this.current);
    if (typeof data !== 'string') {
      return;
    }
    let response: unknown;
    try {
      response = JSON.parse(data);
    } catch {
      return;
    }
    if (!isEventsResponse(response) || !this.options.accepting()) {
      return;
    }
    this.options.onEvents(response);
  }

  /** The socket closed or failed, or was silent for too long: it is dropped and the next one is scheduled. */
  private ended(socket: SocketLike): void {
    if (this.current !== socket) {
      return;
    }
    this.release();
    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    if (this.stopped) {
      return;
    }
    let delay = RECONNECT_MS;
    if (this.delivered) {
      this.backoff = RECONNECT_MS;
    } else {
      delay = this.backoff;
      this.backoff = Math.min(this.backoff * 2, MAX_BACKOFF_MS);
    }
    this.reconnectTimer = this.options.setTimeout(() => this.connect(), delay);
  }

  private armSilence(socket: SocketLike): void {
    if (this.silenceTimer !== undefined) {
      this.options.clearTimeout(this.silenceTimer);
    }
    this.silenceTimer = this.options.setTimeout(() => {
      this.silenceTimer = undefined;
      this.ended(socket);
    }, SILENT_MS);
  }

  /** Detaches and closes the current socket, if there is one, and stops its silence timer. */
  private release(): void {
    if (this.silenceTimer !== undefined) {
      this.options.clearTimeout(this.silenceTimer);
      this.silenceTimer = undefined;
    }
    const socket = this.current;
    this.current = undefined;
    if (socket === undefined) {
      return;
    }
    socket.onmessage = null;
    socket.onclose = null;
    socket.onerror = null;
    try {
      socket.close();
    } catch {
      // A socket that cannot be closed is already gone.
    }
  }

  private cancelTimers(): void {
    if (this.reconnectTimer !== undefined) {
      this.options.clearTimeout(this.reconnectTimer);
      this.reconnectTimer = undefined;
    }
    if (this.silenceTimer !== undefined) {
      this.options.clearTimeout(this.silenceTimer);
      this.silenceTimer = undefined;
    }
  }
}

/** True for the body of /events: an epoch and a list of events. */
function isEventsResponse(value: unknown): value is EventsResponse {
  if (typeof value !== 'object' || value === null) {
    return false;
  }
  const body = value as { epoch?: unknown; events?: unknown };
  return typeof body.epoch === 'string' && Array.isArray(body.events);
}
