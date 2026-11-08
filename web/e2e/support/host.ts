import { readFileSync } from 'node:fs';
import { cpus, loadavg } from 'node:os';

/**
 * What the Playwright worker's own host says about its load (DW-550, DW-774, Story 32.6), for the `DIAG /state host:` and
 * `DIAG page.close host:` lines: the 1-minute load and the CPU count (node:os), the `avg10` pressure of /proc/pressure/{cpu,memory,io}, and
 * the pages swapped in per second (`pswpin` of /proc/vmstat) between two readings. Linux's own counters, read on the host that runs the
 * worker: numbers only, never a path, a PID, a host name or an address. Where /proc/pressure is missing (macOS, a developer machine) the line
 * says `not measured (no /proc/pressure)`. The reads are file reads of a few lines and never throw.
 * Erasable TypeScript with no relative import only: web/scripts/state-wait.test.mjs imports this file into Node as it is.
 */

/** The pressure of one resource in percent (`avg10` of the `some` and `full` lines); a value the file did not hold is undefined. */
export interface Pressure {
  some?: number;
  full?: number;
}

/** One reading of the host; pressure is undefined when any of the three pressure files could not be read; swapIn when /proc/vmstat could not give two readings. */
export interface HostReading {
  load1: number;
  cpus: number;
  pressure?: { cpu: Pressure; memory: Pressure; io: Pressure };
  swapIn?: { pages: number; seconds: number };
}

/** A starting point for the swap-in rate: the pswpin count and the time (ms) it was read at. */
export interface SwapMark {
  pages: number;
  at: number;
}

/** Where the readings come from; a spec passes a stand-in. */
export interface HostSources {
  read(path: string): string | undefined;
  load1(): number;
  cpus(): number;
}

const OWN_SOURCES: HostSources = {
  read: (path) => {
    try {
      return readFileSync(path, 'utf8');
    } catch {
      return undefined;
    }
  },
  load1: () => loadavg()[0] ?? Number.NaN,
  cpus: () => cpus().length,
};

/** The `avg10` of the `some` and `full` lines of a /proc/pressure file's text. */
export function parsePressure(text: string): Pressure {
  const out: Pressure = {};
  for (const kind of ['some', 'full'] as const) {
    const found = new RegExp(`^${kind} avg10=(\\d{1,5}(?:\\.\\d{1,4})?)(?:\\s|$)`, 'm').exec(text);
    if (found?.[1] !== undefined) out[kind] = Number(found[1]);
  }
  return out;
}

/** The pages swapped in so far (`pswpin` of /proc/vmstat), or undefined when the file or the line is missing. */
export function swapInMark(now: number = Date.now(), sources: HostSources = OWN_SOURCES): SwapMark | undefined {
  const found = /^pswpin (\d{1,15})$/m.exec(sources.read('/proc/vmstat') ?? '');
  return found?.[1] === undefined ? undefined : { pages: Number(found[1]), at: now };
}

/** Reads the host now; since is the swap mark of the start of the wait, for the swap-in rate over the wait. */
export function readHost(since: SwapMark | undefined, now: number = Date.now(), sources: HostSources = OWN_SOURCES): HostReading {
  const reading: HostReading = { load1: sources.load1(), cpus: sources.cpus() };
  const files = (['cpu', 'memory', 'io'] as const).map((name) => sources.read(`/proc/pressure/${name}`));
  if (files.every((text) => text !== undefined)) {
    const [cpu = '', memory = '', io = ''] = files;
    reading.pressure = { cpu: parsePressure(cpu), memory: parsePressure(memory), io: parsePressure(io) };
  }
  const end = swapInMark(now, sources);
  if (since !== undefined && end !== undefined && end.at > since.at && end.pages >= since.pages) {
    reading.swapIn = { pages: end.pages - since.pages, seconds: (end.at - since.at) / 1000 };
  }
  return reading;
}

const fixed = (value: number | undefined): string => (value !== undefined && Number.isFinite(value) && value >= 0 ? value.toFixed(1) : 'n/a');

const pair = (pressure: Pressure): string => `some ${fixed(pressure.some)}, full ${fixed(pressure.full)}`;

/** The `<prefix>: ...` line for a reading; a value that is not a plain non-negative number prints as `n/a`. */
export function describeHost(prefix: string, reading: HostReading): string {
  const { pressure, swapIn } = reading;
  if (pressure === undefined) return `${prefix}: not measured (no /proc/pressure)`;
  const cpuCount = Number.isInteger(reading.cpus) && reading.cpus > 0 ? String(reading.cpus) : 'n/a';
  const swap =
    swapIn !== undefined && Number.isFinite(swapIn.pages) && swapIn.pages >= 0 && Number.isFinite(swapIn.seconds) && swapIn.seconds > 0
      ? `swap-in ${fixed(swapIn.pages / swapIn.seconds)} pages/s over ${fixed(swapIn.seconds)} s`
      : 'swap-in not measured';
  return `${prefix}: 1-minute load ${fixed(reading.load1)} on ${cpuCount} CPU(s), pressure avg10 in percent: cpu ${pair(pressure.cpu)}, memory ${pair(pressure.memory)}, io ${pair(pressure.io)}, ${swap}`;
}
