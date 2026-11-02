/**
 * The queue behind the page's one announcer (Story 2.12; NFR-25, UX-DR132). A framework-free module: it imports nothing and uses
 * only erasable TypeScript syntax, so Node runs it as it is, and its timers, its clock and its speaker are injected.
 *
 * - push() trims a message, ignores an empty one and adds it to the waiting list. The flush runs at the later of now and the last
 *   text's time plus ANNOUNCE_MIN_GAP_MS; at the soonest that is a 0 ms timer, so everything pushed in one turn of the event loop
 *   (one update) flushes together.
 * - A flush counts `recent`, the messages spoken in the last ANNOUNCE_WINDOW_MS (a text counts as the messages it carries).
 *   - With `recent` and the waiting messages at most ANNOUNCE_MERGE_ABOVE together, the waiting messages are spoken as one text,
 *     in push order, joined by a space; in a joined text, a message that does not end in ".", "!", "?" or "\u2026" gets a full
 *     stop first, and a lone message is spoken as it is.
 *   - Otherwise, with two or more waiting, the text is NEW_UPDATES with n the number waiting.
 *   - Otherwise (one waiting, `recent` at least ANNOUNCE_MERGE_ABOVE) the queue waits until ANNOUNCE_WINDOW_MS after the newest
 *     spoken text, and flushes again; whatever arrives meanwhile joins that flush.
 * - Every pushed message is spoken once, alone, joined or counted: nothing is spoken twice and nothing is dropped.
 * - dispose() clears the timer and the waiting list; a push after it does nothing.
 */

/** The most messages that are spoken as themselves within ANNOUNCE_WINDOW_MS; beyond that two or more waiting become NEW_UPDATES. */
export const ANNOUNCE_MERGE_ABOVE = 3;

/** The window (ms) in which at most ANNOUNCE_MERGE_ABOVE messages are spoken as themselves. */
export const ANNOUNCE_WINDOW_MS = 2000;

/** The least time (ms) between the moments two texts are spoken, so a screen reader finishes one before the next replaces it. */
export const ANNOUNCE_MIN_GAP_MS = 1000;

/** The text of a burst; {n} is the number of messages it stands for, never below 2. */
export const NEW_UPDATES = '{n} new updates';

/** What an AnnounceQueue needs: the timer functions, the clock and the speaker, injected so a test can run them on a fake clock. */
export interface AnnounceQueueOptions {
  /** Arms a timer and returns its handle (the page passes globalThis.setTimeout). */
  setTimeout: (handler: () => void, ms: number) => unknown;
  /** Clears a timer that setTimeout armed, by its handle. */
  clearTimeout: (handle: unknown) => void;
  /** The clock in ms, monotonic (the page passes performance.now()). */
  now: () => number;
  /** Speaks one text: the page's polite live region. */
  speak: (text: string) => void;
}

/** A text that was spoken: when, and how many messages it carried. */
interface Spoken {
  at: number;
  messages: number;
}

/** The marks that end a sentence, so a message that ends in one needs no full stop before the next. */
const SENTENCE_END = /[.!?\u2026]$/;

/** Speaks what is pushed to it as the module doc says. */
export class AnnounceQueue {
  private readonly options: AnnounceQueueOptions;
  private readonly waiting: string[] = [];
  private spoken: Spoken[] = [];
  private timer: unknown = undefined;
  private ended = false;

  constructor(options: AnnounceQueueOptions) {
    this.options = options;
  }

  /** Adds a message to the waiting list; an empty one (after trimming) is ignored. */
  push(message: string): void {
    const text = message.trim();
    if (this.ended || text === '') {
      return;
    }
    this.waiting.push(text);
    if (this.timer === undefined) {
      this.arm(Math.max(0, this.lastAt() + ANNOUNCE_MIN_GAP_MS - this.options.now()));
    }
  }

  /** Drops the timer and the waiting messages; the page is done with the announcer. */
  dispose(): void {
    this.ended = true;
    this.waiting.length = 0;
    if (this.timer !== undefined) {
      this.options.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  /** When the last text was spoken, or minus infinity when none was. */
  private lastAt(): number {
    return this.spoken.at(-1)?.at ?? Number.NEGATIVE_INFINITY;
  }

  private arm(ms: number): void {
    this.timer = this.options.setTimeout(() => this.flush(), ms);
  }

  private flush(): void {
    this.timer = undefined;
    if (this.waiting.length === 0) {
      return;
    }
    const now = this.options.now();
    this.spoken = this.spoken.filter((one) => now - one.at < ANNOUNCE_WINDOW_MS);
    const recent = this.spoken.reduce((total, one) => total + one.messages, 0);
    const count = this.waiting.length;
    if (recent + count <= ANNOUNCE_MERGE_ABOVE) {
      this.say(this.waiting.map((message) => (SENTENCE_END.test(message) || count === 1 ? message : `${message}.`)).join(' '), count, now);
    } else if (count >= 2) {
      this.say(NEW_UPDATES.replace('{n}', String(count)), count, now);
    } else {
      this.arm(Math.max(0, this.lastAt() + ANNOUNCE_WINDOW_MS - now));
    }
  }

  private say(text: string, messages: number, now: number): void {
    this.waiting.length = 0;
    this.spoken.push({ at: now, messages });
    this.options.speak(text);
  }
}
