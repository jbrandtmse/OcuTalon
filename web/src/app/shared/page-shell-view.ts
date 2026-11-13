/**
 * What the eager app shell needs from the lazily loaded pages (Story 36.5; DW-1282): the three page titles, the unsaved-changes prompt's three
 * strings, pageOf (which page an address is, for the header) and settingsMatch (the Settings route's matcher). A framework-free module with no
 * imports and only erasable TypeScript syntax, so Node runs it as it is.
 *
 * The Settings, History and Usage pages load as lazy chunks (`loadComponent` in app.config.ts). Nothing under settings/ (but the unsaved guard and its
 * dialog), history/ or usage/ may be imported by code the entry point reaches, or that page rides in the initial bundle again; what the shell needs
 * from them lives here, and the pages' view modules reference these values instead of copying them.
 *
 * - SHELL_TEXTS: the page titles (the separator is U+00B7) and the unsaved prompt's sentence and button names.
 * - pageOf: which page an address is: settings, documents, history, usage or the chat.
 * - settingsMatch: the one route of #/settings and #/settings/<section>.
 */

/** The strings the shell shows for the lazy pages. The separator in the titles is U+00B7. */
export const SHELL_TEXTS = {
  settingsTitle: 'Settings \u00B7 OcuTalon',
  historyTitle: 'History \u00B7 OcuTalon',
  usageTitle: 'Usage \u00B7 OcuTalon',
  unsaved: 'You have unsaved changes in this section. Leave without saving?',
  stay: 'Stay',
  leave: 'Leave without saving',
};

/** Which page an address (the part after the hash, such as /settings/budgets?x=1) is: settings, documents (Story 34.2), history (Story 25.2), usage (Story 37.2) or the chat. */
export function pageOf(address: string): 'settings' | 'documents' | 'history' | 'usage' | 'chat' {
  const path = address.replace(/^#/, '').split(/[?#;]/)[0];
  if (path === '/documents') {
    return 'documents';
  }
  if (path === '/history') {
    return 'history';
  }
  if (path === '/usage') {
    return 'usage';
  }
  return path === '/settings' || path.startsWith('/settings/') ? 'settings' : 'chat';
}

/**
 * The route matcher of the settings page: #/settings and #/settings/<section> are one route, so that moving between sections keeps the
 * page (its values and the focus of the link pressed) instead of building it again. The section is the parameter `section`.
 */
export function settingsMatch<T extends { path: string }>(segments: T[]): { consumed: T[]; posParams: Record<string, T> } | null {
  if (segments.length < 1 || segments.length > 2 || segments[0].path !== 'settings') {
    return null;
  }
  return { consumed: segments, posParams: segments.length === 2 ? { section: segments[1] } : {} };
}
