/**
 * The viewer's read-only page (Story 25.4; AD-13, AD-24; UX: viewers see everything read-only), as a framework-free module that imports only a type.
 * A viewer is a signed-in user who holds OcuTalonViewer and not OcuTalonUser: the server says so in the snapshot's `viewer`, and answers every
 * request that changes anything with 403 `read_only`. The page hides each control that would send such a request.
 * - isViewer is the one reader of the snapshot's `viewer`: true only for `viewer: true`, so a missing snapshot or flag keeps the controls.
 * - VIEWER_TEXTS.line is the line that the chat panel shows in the composer's place.
 */
import type { StateSnapshot } from '../api/api-types';

/** The fixed text of the viewer's page. */
export const VIEWER_TEXTS = {
  line: 'You have the viewer role, so you can look but not change anything.',
} as const;

/** True only when the snapshot says the signed-in user is a viewer. */
export function isViewer(snapshot: Pick<StateSnapshot, 'viewer'> | null | undefined): boolean {
  return snapshot?.viewer === true;
}
