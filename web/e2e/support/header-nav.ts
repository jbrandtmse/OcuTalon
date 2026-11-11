/**
 * The header navigation's links in their order (web/src/app/header/header-nav.ts), the list that the specs which pin the whole link list share.
 * A signed-in user has Chat, Documents, History and Usage; an admin also has Settings, after Chat. A spec that expects the whole list
 * reads it from here, and the admin list is the user list with Settings inserted. Tests that reach each link by name (a Tab walk, a
 * box-by-box order) name their links themselves.
 */

/** The links of a signed-in user who is not an admin. */
export const NAV_LINKS_USER: readonly string[] = ['Chat', 'Documents', 'History', 'Usage'];

/** The links of an admin: the user's links with Settings after Chat. */
export const NAV_LINKS_ADMIN: readonly string[] = [NAV_LINKS_USER[0], 'Settings', ...NAV_LINKS_USER.slice(1)];
