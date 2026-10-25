import { expect, test, type APIRequestContext } from '@playwright/test';

import { STATE, post, sessionEvents, type LiveEvent } from '../support/api';
import { README_ACCOUNT, signInOverHttp } from '../sign-in/helpers';

/**
 * The server-derived guide over real HTTP (Story 4.2): the README account signs in and the spec uses only HTTP (/state, /events and
 * POST /v1/guide/markers), with the demo mode that the stack is in (docker/tests/test-demo-switch.sh, OCUTALON_E2E_DEMO_MODE).
 * With demo mode on, /state carries the guide, the two markers answer 200 with the guide view and publish a guide.state, and a
 * bad body is 400 bad_marker. With demo mode off, /state has no guide and both markers answer 404 not_found. Every assertion is
 * relative to the values first read, so that a second run on the same stack passes.
 */
const MARKERS = '/ocutalon/api/v1/guide/markers';

interface Guide {
  runEpoch: number;
  step: number;
  finished: boolean;
  steps: Array<{ step: number; done: boolean }>;
  breakFeed: { active: boolean; reason?: string; stage?: string; startedAt?: string };
  step4Variant: string;
  telegramRow: boolean;
}

interface Snapshot {
  streams: { session: number; instance: number };
  chat: unknown[];
  rail: unknown;
  guide?: Guide;
}

function stackMode(): '0' | '1' {
  const mode = process.env['OCUTALON_E2E_DEMO_MODE'];
  if (mode !== '0' && mode !== '1') {
    throw new Error('OCUTALON_E2E_DEMO_MODE must be 1 (demo mode on) or 0 (demo mode off)');
  }
  return mode;
}

async function state(request: APIRequestContext): Promise<Snapshot> {
  const response = await request.get(STATE);
  expect(response.status(), await response.text()).toBe(200);
  return (await response.json()) as Snapshot;
}

/** The guide events among the events, in the order served. */
function guides(events: LiveEvent[]): LiveEvent[] {
  return events.filter((event) => event.type === 'guide.state');
}

test('the guide follows the demo mode of the stack', async ({ request }) => {
  const mode = stackMode();
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const first = await state(request);

  if (mode === '0') {
    expect(Object.keys(first), 'demo mode is off: the snapshot has no guide').not.toContain('guide');
    for (const marker of ['trace_opened', 'run_again']) {
      const response = await post(request, MARKERS, { marker });
      expect(response.status(), `${marker}: ${await response.text()}`).toBe(404);
      const body = (await response.json()) as { error: { code: string } };
      expect(body.error.code).toBe('not_found');
    }
    const after = await state(request);
    expect(Object.keys(after), 'and the markers wrote nothing').not.toContain('guide');
    expect(after.streams.session, 'no event followed').toBe(first.streams.session);
    return;
  }

  const initial = first.guide;
  expect(initial, 'demo mode is on: the snapshot has a guide').toBeDefined();
  if (!initial) return;
  expect(Object.keys(first).pop(), 'guide is the last key').toBe('guide');
  expect(initial.breakFeed.active, 'the README session watches nothing').toBe(false);
  expect(initial.breakFeed.reason).toBe('not_watching');
  expect(initial.steps.map((one) => one.step)).toEqual([1, 2, 3, 4, 5]);
  const cursor = first.streams.session;
  const wasOpen = initial.steps[4].done;

  const opened = await post(request, MARKERS, { marker: 'trace_opened' });
  expect(opened.status(), await opened.text()).toBe(200);
  const afterOpen = (await opened.json()) as Guide;
  expect(afterOpen.steps[4].done, 'step 5 is done').toBe(true);
  expect(afterOpen.runEpoch, 'the epoch is unchanged').toBe(initial.runEpoch);

  if (!wasOpen) {
    const events = guides(await sessionEvents(request, cursor, (found) => guides(found).length >= 1));
    expect(events.length, 'a guide.state followed').toBeGreaterThanOrEqual(1);
    expect(events[events.length - 1].payload, 'it holds the answer').toEqual(afterOpen);
  }
  expect((await state(request)).guide, "/state's guide is the answer").toEqual(afterOpen);

  const again = await post(request, MARKERS, { marker: 'run_again' });
  expect(again.status(), await again.text()).toBe(200);
  const afterAgain = (await again.json()) as Guide;
  expect(afterAgain.runEpoch, 'the epoch rose by 1').toBe(initial.runEpoch + 1);
  expect(afterAgain.steps[4].done, 'step 5 is open again').toBe(false);
  const events = guides(await sessionEvents(request, cursor, (found) => guides(found).some((event) => (event.payload as unknown as Guide).runEpoch === afterAgain.runEpoch)));
  expect(events[events.length - 1].payload, 'the last guide.state is the new epoch').toEqual(afterAgain);
  expect((await state(request)).guide).toEqual(afterAgain);

  for (const data of [{ marker: 'other' }, {}, 'not json']) {
    const bad = await post(request, MARKERS, data);
    expect(bad.status(), JSON.stringify(data)).toBe(400);
    const body = (await bad.json()) as { error: { code: string; message: string } };
    expect(body.error).toEqual({ code: 'bad_marker', message: 'A guide marker must be trace_opened or run_again.' });
  }

  const last = await state(request);
  expect(last.chat, 'the chat is unchanged').toEqual(first.chat);
  expect(last.rail, 'the rail is unchanged').toEqual(first.rail);
  expect(last.guide, 'the bad bodies changed nothing').toEqual(afterAgain);
});
