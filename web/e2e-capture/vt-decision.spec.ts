import { writeFileSync } from 'node:fs';

import { expect, test, type Page } from '@playwright/test';

import { STATE } from '../e2e/support/api';
import { irisScript, chk } from '../e2e/support/iris';
import { signInReadmeLoaded } from '../e2e/support/floor';
import { TRACE_PAGE, drawnMessages, signOutTrace } from '../e2e/support/trace';

/**
 * Captures docs/images/vt-decision.png (Story 31.3): Visual Trace drawing the incident's whole diagnosis decision, the README's picture of
 * "what is interesting". It signs the README account in, reads the incident's diagnosis header from /state as 06-trace.spec.ts does, opens the
 * trace page of that session in a second page of the same signed-in context, and shoots the diagram element (the SVG embed, sized to the
 * SVG's full extent) at device scale factor 1.
 * Nothing is written unless every check holds: the page draws every message of the session (one page), at least two of them are
 * AgentStep messages, every host column of every lane lies inside the shot, and the SVG's text names no mock, test, CI, host, port or secret.
 * A PNG of 300,000 bytes or more is shrunk through a canvas in 10 % width steps down to 60 % of its width; it fails when it still does not fit.
 * It needs the stack of docker/tests/record-screenshot.sh after the demo-path steps 1 to 5 (playwright.capture.config.ts runs them first):
 * OCUTALON_URL, and OCUTALON_CAPTURE_OUT, the file to write. It prints CAPTURE agent-steps=<n> messages=<m> size=<w>x<h>.
 */

/** The size under which the PNG must stay, in bytes. */
const PNG_LIMIT = 300_000;

/** The names the shot must not show: a mock, test, CI, host, local address or port, or anything secret. */
const FORBIDDEN = /mock|test|\bci\b|localhost|127\.0\.0\.1|:5\d{4}\b|password|secret|api[_ ]?key|sk-ant/i;

/** What the page's SVG document holds. */
interface Reading {
  ids: string[];
  agentSteps: number;
  text: string;
  width: number;
  height: number;
  lanes: string[];
  hosts: string[];
  /** The host rectangles and titles that lie outside the diagram's extent. */
  outside: string[];
}

/** Reads the SVG document of the page's embed: its messages, text, extent, lanes and host columns. */
async function readSvg(page: Page): Promise<Reading> {
  return page.evaluate(() => {
    const frame = document.querySelector('embed[type="image/svg+xml"], object[type="image/svg+xml"]') as ({ getSVGDocument?: () => Document | null } & Element) | null;
    const svg = frame?.getSVGDocument?.();
    if (!svg) throw new Error('the page has no SVG document');
    const canvas = svg.getElementById('traceCanvas');
    const width = Number(canvas?.getAttribute('width') ?? 0);
    const height = Number(canvas?.getAttribute('height') ?? 0);
    const groups = Array.from(svg.querySelectorAll('g[id]')).filter((g) => /^\d+$/.test(g.id));
    const agentSteps = groups.filter((g) => Array.from(g.querySelectorAll('text.MsgLabel')).some((t) => (t.textContent ?? '').trim() === 'AgentStep')).length;
    const lanes = Array.from(svg.querySelectorAll('text.LaneTitle')).map((t) => (t.textContent ?? '').trim());
    const hosts = Array.from(svg.querySelectorAll('text.HostTitle')).map((t) => (t.textContent ?? '').trim());
    const outside: string[] = [];
    for (const shape of Array.from(svg.querySelectorAll('rect.HostRect, text.HostTitle, text.LaneTitle')) as unknown as SVGGraphicsElement[]) {
      const box = shape.getBBox();
      if (box.x < 0 || box.y < 0 || box.x + box.width > width || box.y + box.height > height) {
        outside.push(`${shape.getAttribute('class')} ${(shape.textContent ?? '').trim()} at ${Math.round(box.x)},${Math.round(box.y)} ${Math.round(box.width)}x${Math.round(box.height)}`);
      }
    }
    return { ids: groups.map((g) => g.id), agentSteps, text: svg.documentElement.textContent ?? '', width, height, lanes, hosts, outside };
  });
}

/** The width and height that a PNG's header holds. */
function pngSize(png: Buffer): { width: number; height: number } {
  if (png.length < 24 || png.subarray(1, 4).toString('latin1') !== 'PNG') throw new Error('the capture is not a PNG');
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

/** Draws the PNG at the given width in the page's canvas and returns the new PNG. */
async function shrink(page: Page, png: Buffer, width: number): Promise<Buffer> {
  const base64 = await page.evaluate(
    async ({ data, to }) => {
      const image = new Image();
      await new Promise<void>((resolve, reject) => {
        image.onload = () => resolve();
        image.onerror = () => reject(new Error('the PNG does not load'));
        image.src = `data:image/png;base64,${data}`;
      });
      const canvas = document.createElement('canvas');
      canvas.width = to;
      canvas.height = Math.round((image.naturalHeight * to) / image.naturalWidth);
      const context = canvas.getContext('2d');
      if (!context) throw new Error('no canvas context');
      context.imageSmoothingQuality = 'high';
      context.drawImage(image, 0, 0, canvas.width, canvas.height);
      return canvas.toDataURL('image/png').split(',')[1];
    },
    { data: png.toString('base64'), to: width },
  );
  return Buffer.from(base64, 'base64');
}

test.describe('Story 31.3: the README picture of one whole decision in Visual Trace', () => {
  test.skip(!process.env['OCUTALON_URL'], 'the capture needs the stack (OCUTALON_URL) after the demo-path steps 1 to 5');

  test('Visual Trace of the incident diagnosis decision is captured', async ({ page, context }) => {
    test.setTimeout(150_000);
    const out = process.env['OCUTALON_CAPTURE_OUT'];
    expect(out, 'OCUTALON_CAPTURE_OUT names the file to write').toBeTruthy();
    await signInReadmeLoaded(page);
    const state = await page.request.get(STATE);
    expect(state.status(), await state.text()).toBe(200);
    const chat = ((await state.json()) as { chat: Array<{ type: string; payload: { traceTargets?: { diagnosis?: { traceHeaderId?: number } } } }> }).chat;
    const header = chat.find((item) => item.type === 'incident')?.payload.traceTargets?.diagnosis?.traceHeaderId;
    expect(typeof header === 'number' && header > 0, "the incident's diagnosis has a trace header").toBe(true);

    const trace = await context.newPage();
    try {
      await trace.setViewportSize({ width: 2800, height: 1800 });
      await trace.goto(`${TRACE_PAGE}${header}`);
      expect(await trace.locator('input[name=IRISUsername]').count(), 'the trace page asks for no second sign-in').toBe(0);
      const drawn = await drawnMessages(trace);
      expect(drawn.ids, 'the page draws the diagnosis header').toContain(String(header));
      // (a) the whole decision: the page draws every message of the session, so there is no second page.
      const session = chk(await irisScript(`Set h=##class(Ens.MessageHeader).%OpenId(${header})\nWrite !,"CHK|session|",$Select($IsObject(h):h.SessionId,1:"")`), 'session');
      expect(session, 'the header has a session').toMatch(/^\d+$/);
      const rows = chk(
        await irisScript(`Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId=?",${session})\nDo rs.%Next()\nWrite !,"CHK|rows|",rs.%GetData(1)`),
        'rows',
      );
      // Visual Trace draws its list in steps; read again until it has drawn every message of the session, for 15 s at most.
      let reading = await readSvg(trace);
      for (let tries = 0; tries < 15 && reading.ids.length !== Number(rows); tries += 1) {
        await trace.waitForTimeout(1000);
        reading = await readSvg(trace);
      }
      console.log(`READ lanes=${reading.lanes.join('|')} hosts=${reading.hosts.join('|')} extent=${reading.width}x${reading.height} messages=${reading.ids.length}`);
      console.log(`READ session=${session} headers=${rows}`);
      expect(reading.ids.length, `the drawn messages (${reading.ids.join(' ')}) are all ${rows} messages of the session`).toBe(Number(rows));

      // (b) more than one agent step.
      expect(reading.agentSteps, 'the decision holds at least two AgentStep messages').toBeGreaterThanOrEqual(2);

      // (c) every lane fits in the clip.
      for (const lane of ['Services', 'Processes', 'Operations']) expect(reading.lanes, `the lane ${lane} is drawn`).toContain(lane);
      expect(reading.hosts, 'the AgentSteps operation is drawn').toContain('AgentSteps');
      expect(reading.width > 0 && reading.height > 0, 'the diagram has an extent').toBe(true);
      expect(reading.outside, 'every lane title and host column lies inside the diagram').toEqual([]);

      // (d) no forbidden name.
      const hit = FORBIDDEN.exec(reading.text);
      expect(hit, `the SVG text names none of the forbidden names (it holds ${hit ? JSON.stringify(reading.text.slice(Math.max(0, hit.index - 40), hit.index + 40)) : ''})`).toBeNull();

      // Size the embed to the SVG's full extent and let no ancestor cut it.
      await trace.evaluate(
        ({ width, height }) => {
          const frame = document.querySelector('embed[type="image/svg+xml"], object[type="image/svg+xml"]') as HTMLElement;
          frame.style.width = `${width}px`;
          frame.style.height = `${height}px`;
          frame.setAttribute('width', String(width));
          frame.setAttribute('height', String(height));
          for (let node = frame.parentElement; node && node !== document.documentElement; node = node.parentElement) {
            node.style.overflow = 'visible';
            node.style.maxHeight = 'none';
            node.style.maxWidth = 'none';
          }
          // The page's own panes (the contents pane, its expanders) are laid over the diagram: hide every sibling of the embed and of its ancestors.
          for (let node: HTMLElement | null = frame; node && node !== document.body; node = node.parentElement) {
            for (const sibling of Array.from(node.parentElement?.children ?? []) as HTMLElement[]) {
              if (sibling !== node) sibling.style.visibility = 'hidden';
            }
          }
        },
        { width: reading.width, height: reading.height },
      );
      const frame = trace.locator('embed[type="image/svg+xml"], object[type="image/svg+xml"]');
      await frame.scrollIntoViewIfNeeded();
      const covered = await frame.evaluate((element) => {
        const box = element.getBoundingClientRect();
        if (box.left < 0 || box.top < 0 || box.right > window.innerWidth || box.bottom > window.innerHeight) return ['the embed does not fit the viewport'];
        const hits: string[] = [];
        for (let row = 0; row <= 10; row += 1) {
          for (let column = 0; column <= 10; column += 1) {
            const x = Math.min(box.right - 1, box.left + (box.width * column) / 10);
            const y = Math.min(box.bottom - 1, box.top + (box.height * row) / 10);
            const top = document.elementFromPoint(x, y);
            if (top !== element) hits.push(`${Math.round(x)},${Math.round(y)} ${top?.tagName ?? 'none'}#${top?.id ?? ''}`);
          }
        }
        return hits;
      });
      expect(covered, 'nothing of the page lies over the diagram').toEqual([]);
      let png = await frame.screenshot({ scale: 'css' });
      let size = pngSize(png);
      console.log(`READ shot=${size.width}x${size.height} bytes=${png.length}`);
      expect(size, 'the shot is the SVG at its full extent').toEqual({ width: reading.width, height: reading.height });

      const first = size.width;
      for (let percent = 90; png.length >= PNG_LIMIT && percent >= 60; percent -= 10) {
        png = await shrink(trace, png, Math.round((first * percent) / 100));
      }
      size = pngSize(png);
      expect(png.length, `the PNG is under ${PNG_LIMIT} bytes (it is ${png.length} B at ${size.width}x${size.height})`).toBeLessThan(PNG_LIMIT);

      writeFileSync(out!, png);
      console.log(`CAPTURE agent-steps=${reading.agentSteps} messages=${reading.ids.length} size=${size.width}x${size.height}`);
    } finally {
      await signOutTrace(page.request);
      await trace.close();
    }
  });
});
