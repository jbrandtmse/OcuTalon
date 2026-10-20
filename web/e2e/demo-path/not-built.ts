import { test } from '@playwright/test';

/** The id of a story, such as 4.7. */
export type StoryId = `${number}.${number}`;

/**
 * Declares one part of a UJ-1 step that no story has built yet, as a skipped test. Its skip text is
 * `Story <story> turns this on`, which web/scripts/demo-path-summary.mjs reads to name the story that owns the part. The
 * story that builds the part replaces this call with the real test.
 */
export function notBuilt(title: string, story: StoryId): void {
  test(title, () => {
    test.skip(true, `Story ${story} turns this on`);
  });
}
