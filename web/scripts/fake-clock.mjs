// A clock for the Node tests of the framework-free modules (src/app/shared/busy-state.ts, src/app/live/contact-watch.ts,
// src/app/shared/announce-queue.ts): a timer runs only when the test advances the clock, `now` reads the clock in ms, and `pending`
// counts the timers still armed.

/** The most timers one advance() may run: far more than any test arms, so only a timer that keeps re-arming itself reaches it. */
const MOST_TIMERS = 100_000;

/** A clock that runs a timer only when the test advances it. */
export function fakeClock() {
  let now = 0;
  let next = 1;
  const timers = new Map();
  return {
    setTimeout(handler, ms) {
      const id = next++;
      timers.set(id, { at: now + ms, handler });
      return id;
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    advance(ms) {
      const target = now + ms;
      for (let fired = 0; ; fired += 1) {
        // A timer that arms itself again at the same instant would never let the clock reach its target: say so, instead of hanging.
        if (fired > MOST_TIMERS) throw new Error(`the fake clock ran ${MOST_TIMERS} timers inside one advance: a timer arms itself again at the same instant`);
        const due = [...timers.entries()].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        timers.delete(due[0]);
        now = due[1].at;
        due[1].handler();
      }
      now = target;
    },
    get now() {
      return now;
    },
    get pending() {
      return timers.size;
    },
  };
}
