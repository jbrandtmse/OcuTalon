import { notBuilt } from './not-built';

/**
 * UJ-1 step 1, the Telegram part: the page's pairing, shown only once a release includes Telegram. Lane A owns this file from Epic 12
 * (AD-29): Story 12.4 replaces the call below with the real test. web/scripts/demo-path-summary.mjs counts it as a part of step 1
 * (the `page` in the file name), skipped with the story that owns it.
 */
notBuilt('the page pairs a Telegram chat: a code and its QR code make the chat paired, and the paired chat shows its name', '12.4');
