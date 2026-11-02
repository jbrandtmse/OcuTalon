/**
 * The texts of the header's Demo view switch (Story 4.9; EXPERIENCE: Demo guide and controls). A framework-free module: it imports
 * nothing, so Node runs it as it is and the strings test reads it. The label names the switch; the help text is its description and,
 * outside the drawer band, its pointer tooltip.
 */

/** The id of the help text, which describes the switch. */
export const DEMO_VIEW_HELP_ID = 'demo-view-help';

/** The switch's label and its help text. */
export const DEMO_VIEW_TEXTS = {
  label: 'Demo view',
  help: 'Off shows the page as it looks on your own install.',
} as const;
