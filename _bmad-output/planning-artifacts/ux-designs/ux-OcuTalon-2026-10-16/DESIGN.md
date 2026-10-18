---
name: OcuTalon
description: Visual identity for OcuTalon's web app, online demo and simulated devices. Navy, teal and orange taken from the logo; calm, dense and evidence-first; light and dark themes.
status: final
created: 2026-10-16
updated: 2026-10-16
colors:
  # Light theme. In dark mode every {colors.<name>} resolves to {colors.<name>-dark};
  # exceptions are listed under "Colors". Contrast for load-bearing pairs is there too.
  bg: '#F4F7FA'
  surface: '#FFFFFF'
  raised: '#FFFFFF'
  sunken: '#EAEFF4'
  header-bg: '#FFFFFF'
  border: '#D3DCE5'
  border-strong: '#76879B'
  ink: '#102A45'
  ink-muted: '#4A5C72'
  ink-disabled: '#98A4B3'
  brand-navy: '#102A45'
  brand-teal: '#399897'
  brand-orange: '#DE5034'
  action: '#1A6F6D'
  action-hover: '#145958'
  on-action: '#FFFFFF'
  action-ink: '#1A6F6D'
  action-soft: '#E3F2F1'
  attention: '#B83A1E'
  attention-hover: '#9A2F17'
  on-attention: '#FFFFFF'
  attention-ink: '#B03519'
  attention-soft: '#FDEDE8'
  success-ink: '#146C43'
  success-soft: '#E5F3EB'
  warning-ink: '#8A5300'
  warning-soft: '#FFF4DC'
  danger-ink: '#B42318'
  danger-soft: '#FDECEA'
  info-ink: '#2D5788'
  info-soft: '#E7EEF7'
  neutral-soft: '#ECEFF3'
  focus: '#1A6F6D'
  scrim: '#102A4573'
  phone-frame: '#102A45'
  chart-tokens: '#1A6F6D'
  chart-cost: '#102A45'
  bg-dark: '#11192B'
  surface-dark: '#18233A'
  raised-dark: '#202D48'
  sunken-dark: '#0C1322'
  header-bg-dark: '#161D2F'
  border-dark: '#2E3D5A'
  border-strong-dark: '#6B7C99'
  ink-dark: '#EEF2F7'
  ink-muted-dark: '#AAB6C8'
  ink-disabled-dark: '#5F6D86'
  brand-navy-dark: '#11192B'
  brand-teal-dark: '#329C97'
  brand-orange-dark: '#DB482B'
  action-dark: '#45B9B3'
  action-hover-dark: '#5FC7C1'
  on-action-dark: '#0B1220'
  action-ink-dark: '#5CC9C3'
  action-soft-dark: '#173A43'
  attention-dark: '#F26B4F'
  attention-hover-dark: '#F5826A'
  on-attention-dark: '#0B1220'
  attention-ink-dark: '#F47A60'
  attention-soft-dark: '#3B2128'
  success-ink-dark: '#5CCB93'
  success-soft-dark: '#16362E'
  warning-ink-dark: '#F1B656'
  warning-soft-dark: '#3A2F1A'
  danger-ink-dark: '#F7867B'
  danger-soft-dark: '#3D1E24'
  info-ink-dark: '#8DB3E6'
  info-soft-dark: '#1B2E4C'
  neutral-soft-dark: '#222E44'
  focus-dark: '#5CC9C3'
  scrim-dark: '#05091299'
  phone-frame-dark: '#6B7C99'
  chart-tokens-dark: '#45B9B3'
  chart-cost-dark: '#AAB6C8'
typography:
  display-lg:
    fontFamily: Montserrat
    fontSize: 28px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  display-md:
    fontFamily: Montserrat
    fontSize: 20px
    fontWeight: '700'
    lineHeight: '1.3'
  wordmark:
    fontFamily: Montserrat
    fontSize: 20px
    fontWeight: '800'
    lineHeight: '1'
    letterSpacing: -0.005em
  headline:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: '1.35'
  title:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '600'
    lineHeight: '1.4'
  body-chat:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: '1.55'
  body:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  body-strong:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.5'
  body-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: '1.45'
  label:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: '1.3'
    letterSpacing: 0.06em
  caption:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: '1.4'
  mono:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '400'
    lineHeight: '1.5'
  mono-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: '1.45'
  phone-body:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.45'
rounded:
  xs: 4px
  sm: 6px
  md: 10px
  lg: 16px
  xl: 28px
  full: 9999px
spacing:
  '1': 4px
  '2': 8px
  '3': 12px
  '4': 16px
  '5': 20px
  '6': 24px
  '8': 32px
  '10': 40px
  '12': 48px
  header-height: 56px
  guide-min-height: 92px
  guide-compact-height: 56px
  banner-min-height: 44px
  rail-width: 288px
  rail-width-wide: 320px
  device-width: 352px
  device-width-wide: 384px
  chat-text-max: 72ch
  phone-screen-width: 296px
  phone-screen-min-height: 360px
  control-height: 36px
  control-height-sm: 32px
  control-height-lg: 40px
  target-min: 32px
  scroll-gutter: 4px
  splash-max-width: 960px
  sign-in-card-width: 400px
components:
  app-header:
    background: '{colors.header-bg}'
    foreground: '{colors.ink}'
    border-bottom: '1px solid {colors.border}'
    min-height: '{spacing.header-height}'
  wordmark:
    typography: '{typography.wordmark}'
    ocu: '{colors.ink}'
    talon: '{colors.brand-orange}'
  context-badge:
    background: '{colors.neutral-soft}'
    foreground: '{colors.ink-muted}'
    radius: '{rounded.full}'
    typography: '{typography.label}'
  header-nav-item:
    foreground: '{colors.ink-muted}'
    foreground-current: '{colors.ink}'
    indicator-current: '2px bottom bar {colors.action}'
    typography: '{typography.body-strong}'
  status-banner-warning:
    background: '{colors.warning-soft}'
    foreground: '{colors.ink}'
    accent: '{colors.warning-ink}'
    min-height: '{spacing.banner-min-height}'
  status-banner-danger:
    background: '{colors.danger-soft}'
    foreground: '{colors.ink}'
    accent: '{colors.danger-ink}'
    min-height: '{spacing.banner-min-height}'
  status-banner-info:
    background: '{colors.info-soft}'
    foreground: '{colors.ink}'
    accent: '{colors.info-ink}'
    min-height: '{spacing.banner-min-height}'
  inline-notice-warning:
    background: '{colors.warning-soft}'
    foreground: '{colors.ink}'
    icon-color: '{colors.warning-ink}'
    radius: '{rounded.sm}'
    typography: '{typography.body-sm}'
  inline-notice-info:
    background: '{colors.info-soft}'
    foreground: '{colors.ink}'
    icon-color: '{colors.info-ink}'
    radius: '{rounded.sm}'
    typography: '{typography.body-sm}'
  field-error:
    foreground: '{colors.danger-ink}'
    icon: circle-alert
    typography: '{typography.body-sm}'
  button-primary:
    background: '{colors.action}'
    background-hover: '{colors.action-hover}'
    foreground: '{colors.on-action}'
    radius: '{rounded.sm}'
    min-height: '{spacing.control-height}'
    typography: '{typography.body-strong}'
  button-secondary:
    background: '{colors.surface}'
    background-hover: '{colors.action-soft}'
    foreground: '{colors.action-ink}'
    border: '1px solid {colors.border-strong}'
    radius: '{rounded.sm}'
    min-height: '{spacing.control-height}'
  button-attention:
    background: '{colors.attention}'
    background-hover: '{colors.attention-hover}'
    foreground: '{colors.on-attention}'
    radius: '{rounded.sm}'
    min-height: '{spacing.control-height}'
  button-ghost:
    background: transparent
    background-hover: '{colors.action-soft}'
    foreground: '{colors.action-ink}'
    radius: '{rounded.sm}'
    min-height: '{spacing.control-height-sm}'
  button-inactive:
    background: '{colors.neutral-soft}'
    foreground: '{colors.ink-muted}'
    border: '1px dashed {colors.border-strong}'
  button-busy:
    spinner: '{colors.on-action}'
    note: 'Label unchanged; spinner before the label; aria-disabled and aria-busy, never the disabled attribute'
  link:
    foreground: '{colors.action-ink}'
    decoration: 'underline 1px, offset 2px; 2px on hover and focus'
  focus-ring:
    outline: '2px solid {colors.focus}'
    offset: 2px
    halo: '0 0 0 2px {colors.surface} inside the offset'
  tooltip:
    background: '{colors.ink}'
    foreground: '{colors.surface}'
    radius: '{rounded.xs}'
    typography: '{typography.caption}'
  skeleton:
    background: '{colors.sunken}'
    radius: '{rounded.xs}'
  demo-guide:
    background: '{colors.surface}'
    border-bottom: '1px solid {colors.border}'
    min-height: '{spacing.guide-min-height}'
  guide-step-done:
    marker: 'check in {colors.success-ink}'
    foreground: '{colors.ink-muted}'
  guide-step-current:
    marker: 'filled disc {colors.action} with number in {colors.on-action}'
    foreground: '{colors.ink}'
    typography: '{typography.body-strong}'
  guide-step-upcoming:
    marker: 'hollow circle {colors.border-strong} with number in {colors.ink-muted}'
    foreground: '{colors.ink-muted}'
  guide-step-selected:
    indicator: '2px bottom bar {colors.ink}'
  guide-collapsed-bar:
    background: '{colors.surface}'
    min-height: '{spacing.control-height-lg}'
    typography: '{typography.body-sm}'
  break-the-feed:
    background: '{colors.attention}'
    foreground: '{colors.on-attention}'
    radius: '{rounded.sm}'
    box-label: '{typography.label}'
    box-label-color: '{colors.attention-ink}'
    next-step-accent: '4px left bar {colors.action}'
    next-step-tag-background: '{colors.action-soft}'
    next-step-tag-foreground: '{colors.action-ink}'
  status-rail:
    background: '{colors.bg}'
    border-right: '1px solid {colors.border}'
    width: '{spacing.rail-width}'
    padding-inline: '{spacing.scroll-gutter}'
  status-rail-section:
    heading: '{typography.label}'
    heading-color: '{colors.ink-muted}'
    row-typography: '{typography.body-sm}'
    row-title: '{typography.body-strong}'
    divider: '1px solid {colors.border}'
  telegram-card:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    paired-icon: '{colors.success-ink}'
    paused-icon: '{colors.warning-ink}'
  qr-code-block:
    background: '#FFFFFF'
    foreground: '#102A45'
    size: 132px
    quiet-zone: '{spacing.3}'
    radius: '{rounded.sm}'
  decision-row:
    typography: '{typography.body-sm}'
    meta: '{typography.caption}'
    divider: '1px solid {colors.border}'
  chat-panel:
    background: '{colors.surface}'
    text-max: '{spacing.chat-text-max}'
    padding-inline: '{spacing.scroll-gutter}'
  chat-message-user:
    background: '{colors.sunken}'
    foreground: '{colors.ink}'
    radius: '{rounded.md}'
    typography: '{typography.body-chat}'
  chat-message-ocutalon:
    background: transparent
    foreground: '{colors.ink}'
    typography: '{typography.body-chat}'
    avatar-size: 24px
  decision-strip:
    typography: '{typography.caption}'
    foreground: '{colors.ink-muted}'
    reasons-typography: '{typography.body-sm}'
  check-row:
    typography: '{typography.body-sm}'
    meta: '{typography.caption}'
  turn-indicator:
    foreground: '{colors.ink-muted}'
    typography: '{typography.body-sm}'
  new-messages-button:
    background: '{colors.raised}'
    foreground: '{colors.action-ink}'
    border: '1px solid {colors.border-strong}'
    radius: '{rounded.sm}'
    min-height: '{spacing.control-height-sm}'
  outcome-chip-ignore:
    background: '{colors.neutral-soft}'
    foreground: '{colors.ink-muted}'
    icon: eye-off
    radius: '{rounded.full}'
  outcome-chip-digest:
    background: '{colors.info-soft}'
    foreground: '{colors.info-ink}'
    icon: inbox
    radius: '{rounded.full}'
  outcome-chip-tell-now:
    background: '{colors.attention-soft}'
    foreground: '{colors.attention-ink}'
    icon: bell-ring
    radius: '{rounded.full}'
  outcome-chip-act:
    background: '{colors.action-soft}'
    foreground: '{colors.action-ink}'
    icon: zap
    radius: '{rounded.full}'
  fallback-flag:
    background: '{colors.warning-soft}'
    foreground: '{colors.warning-ink}'
    icon: life-buoy
    radius: '{rounded.full}'
  composer:
    background: '{colors.surface}'
    border: '1px solid {colors.border-strong}'
    placeholder: '{colors.ink-muted}'
    radius: '{rounded.md}'
    typography: '{typography.body-chat}'
  notice-card:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    accent-bar: '4px {colors.info-ink}'
    accent-bar-tell-now: '4px {colors.attention}'
    radius: '{rounded.md}'
    title: '{typography.title}'
  incident-card:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    accent-bar: '4px {colors.attention}'
    accent-bar-fixing: '4px {colors.info-ink}'
    accent-bar-resolved: '4px {colors.success-ink}'
    accent-bar-closed: '4px {colors.border-strong}'
    radius: '{rounded.md}'
    headline: '{typography.headline}'
    evidence-line: '{typography.body-sm}'
  incident-state-open:
    background: '{colors.attention-soft}'
    foreground: '{colors.attention-ink}'
  incident-state-awaiting-approval:
    background: '{colors.attention-soft}'
    foreground: '{colors.attention-ink}'
  incident-state-fixing:
    background: '{colors.info-soft}'
    foreground: '{colors.info-ink}'
  incident-state-resolved:
    background: '{colors.success-soft}'
    foreground: '{colors.success-ink}'
  incident-state-closed:
    background: '{colors.neutral-soft}'
    foreground: '{colors.ink-muted}'
  approval-request-card:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    accent-bar-pending: '4px {colors.attention}'
    accent-bar-approved: '4px {colors.success-ink}'
    accent-bar-closed: '4px {colors.border-strong}'
    radius: '{rounded.md}'
    label: '{typography.label}'
  answered-status:
    approved: '{colors.success-ink}'
    rejected: '{colors.ink-muted}'
    expired: '{colors.ink-muted}'
    typography: '{typography.body-strong}'
  dry-run-block:
    background: '{colors.sunken}'
    radius: '{rounded.sm}'
    before: '{colors.danger-ink}'
    after: '{colors.success-ink}'
    value-typography: '{typography.mono}'
  evidence-panel:
    background: '{colors.sunken}'
    radius: '{rounded.sm}'
    typography: '{typography.mono-sm}'
  result-success:
    background: '{colors.success-soft}'
    foreground: '{colors.success-ink}'
    radius: '{rounded.sm}'
  result-partial:
    background: '{colors.warning-soft}'
    foreground: '{colors.warning-ink}'
    radius: '{rounded.sm}'
  simulated-device-panel:
    background: '{colors.bg}'
    border-left: '1px solid {colors.border}'
    width: '{spacing.device-width}'
  device-tab:
    foreground: '{colors.ink-muted}'
    foreground-selected: '{colors.ink}'
    indicator-selected: '3px bottom bar {colors.action}'
    typography: '{typography.body-strong}'
  tab-badge:
    background: '{colors.action}'
    foreground: '{colors.on-action}'
    radius: '{rounded.full}'
    typography: '{typography.caption}'
  simulated-label:
    background: '{colors.warning-soft}'
    foreground: '{colors.warning-ink}'
    border: '1px solid {colors.warning-ink}'
    radius: '{rounded.full}'
    typography: '{typography.label}'
  simulated-phone:
    frame: '{colors.phone-frame}'
    frame-radius: '{rounded.xl}'
    screen: '{colors.surface}'
    screen-radius: '{rounded.lg}'
    screen-width: '{spacing.phone-screen-width}'
    screen-min-height: '{spacing.phone-screen-min-height}'
    shadow: '0 12px 32px #102A452E'
    shadow-dark: '0 12px 32px #00000080'
  phone-notification:
    background: '{colors.sunken}'
    foreground: '{colors.ink}'
    radius: '{rounded.md}'
    typography: '{typography.phone-body}'
    button-height: '{spacing.control-height-lg}'
  simulated-mailbox:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
  email-row:
    typography: '{typography.body-sm}'
    unread-marker: '{colors.action}'
  sample-email-chip:
    background: '{colors.surface}'
    background-hover: '{colors.action-soft}'
    foreground: '{colors.action-ink}'
    border: '1px solid {colors.border-strong}'
    radius: '{rounded.full}'
    icon: mail
  reset-countdown:
    background: '{colors.neutral-soft}'
    foreground: '{colors.ink}'
    radius: '{rounded.full}'
    typography: '{typography.caption}'
  reset-countdown-urgent:
    background: '{colors.warning-soft}'
    foreground: '{colors.warning-ink}'
  trace-link:
    foreground: '{colors.action-ink}'
    icon: external-link
    typography: '{typography.caption}'
  popover:
    background: '{colors.raised}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    shadow: '0 8px 24px #102A4529'
  dialog:
    background: '{colors.raised}'
    radius: '{rounded.lg}'
    scrim: '{colors.scrim}'
    shadow: '0 16px 48px #102A4540'
  splash-canvas:
    background: '{colors.surface}'
    background-dark: '{colors.bg-dark}'
    max-width: '{spacing.splash-max-width}'
  credential-card:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    radius: '{rounded.md}'
    value-typography: '{typography.mono}'
  text-input:
    background: '{colors.surface}'
    border: '1px solid {colors.border-strong}'
    border-error: '1px solid {colors.danger-ink}'
    placeholder: '{colors.ink-muted}'
    radius: '{rounded.xs}'
    min-height: '{spacing.control-height-lg}'
  digest-card:
    background: '{colors.surface}'
    border: '1px solid {colors.border}'
    accent-bar: '4px {colors.brand-teal}'
    radius: '{rounded.md}'
  check-result-passed:
    foreground: '{colors.success-ink}'
    icon: circle-check
  check-result-failed:
    foreground: '{colors.danger-ink}'
    icon: circle-x
  check-result-not-checked:
    foreground: '{colors.warning-ink}'
    icon: circle-dashed
  citation-chip:
    background: '{colors.info-soft}'
    foreground: '{colors.info-ink}'
    border: '1px solid {colors.info-ink}'
    radius: '{rounded.xs}'
    typography: '{typography.caption}'
  classification-unclassified:
    background: '{colors.warning-soft}'
    foreground: '{colors.warning-ink}'
  classification-read-only:
    background: '{colors.success-soft}'
    foreground: '{colors.success-ink}'
  classification-risky:
    background: '{colors.attention-soft}'
    foreground: '{colors.attention-ink}'
  usage-chart:
    tokens-series: '{colors.chart-tokens}'
    cost-series: '{colors.chart-cost}'
    gridline: '{colors.border}'
---

## Brand & Style

This file covers how OcuTalon looks. `EXPERIENCE.md` beside it covers how it behaves and what it says, and component names match across both files. Visual references live in `mockups/`; if a mock and this file disagree, this file wins.

OcuTalon is an assistant that lives inside an integration engine, so the interface should feel like a well-run operations console, not a consumer chatbot. The page has one job above all: **show your work**. Every decision appears with its outcome, reasons, confidence, cost, and a path to its trace. Visual weight goes to evidence: counts, causes, dry runs, and who approved what. It never goes to decoration or to signals that "AI is happening".

The identity comes straight from the final logo: an eye split into **teal** and **orange** on **navy**, with a geometric sans wordmark ("Ocu" in navy or white, "Talon" in orange). The interface turns that split into meaning. Teal is the color of doing: actions, links, and focus. Orange is the color of noticing: incidents, tell-now items, and the Break the feed control. Navy carries the text in light mode and the canvas in dark mode, matching the two logo variants exactly.

The posture is calm and dense. Judges try the demo in about two minutes at 1280×720, so the page shows a lot at once without shouting. Hierarchy comes from type and spacing on quiet surfaces, with color reserved for state. The one deliberate moment of physical metaphor is the simulated phone, which carries a "Simulated" label that is never subtle.

## Colors

The colors and their jobs:

- **Navy (`{colors.brand-navy}` `#102A45`; dark canvas `{colors.bg-dark}` `#11192B`).** Body text in light mode, and the canvas in dark mode. The canvas color was sampled from the dark logo's background, so the logo image sits on the page with no visible box. In dark mode the header uses `{colors.header-bg-dark}` (`#161D2F`), the logo mark's own tile color, so the mark sits on it seamlessly.
- **Brand teal (`{colors.brand-teal}` `#399897`) and action teal (`{colors.action}` `#1A6F6D` light, `#45B9B3` dark).** The logo's teal is too light for white button text (3.4:1), so actions use a deeper teal in light mode and a brighter one in dark mode, where button labels switch to dark ink. Action teal is used for primary buttons, links, focus rings, the current guide step, the selected tab, and the **act** outcome. Brand teal itself appears only in large graphics, such as the digest card's accent bar.
- **Brand orange (`{colors.brand-orange}` `#DE5034`) and attention orange (`{colors.attention}` `#B83A1E` light, `#F26B4F` dark).** Brand orange appears only in the wordmark and in large graphics. Attention orange marks things that need a person: incident cards, pending approval requests, the **tell now** outcome, and the Break the feed button. Orange never decorates.
- **Status colors.** Success green means "went through" and "passed". Warning amber marks the fallback flag, "not checked", the "Simulated" label, and an imminent reset. Danger red is for system failures, a failed check result, field errors, and the "before" value in a dry run. Info blue marks the **digest** outcome and the fixing state.
- **Neutrals.** `{colors.bg}`, `{colors.surface}`, `{colors.sunken}`, and `{colors.border}` build the layout. The **ignore** outcome uses `{colors.neutral-soft}`, because ignoring is a quiet, correct result, not a warning.
- **The simulated phone's frame** is navy in light mode and slate (`{colors.phone-frame-dark}`) in dark mode, so the device stays visible against the dark canvas.

The four outcomes stay distinct even with color removed. Each chip carries its text label and its own icon: `eye-off` for ignore, `inbox` for digest, `bell-ring` for tell now, and `zap` for act.

Avoid gradients, glows, and sparkle colors, a fifth outcome color, and red for anything that merely needs attention. Orange is attention; red is failure.

**Dark mode.** Every `{colors.<name>}` resolves to `{colors.<name>-dark}`. There are four exceptions:

- The QR code block is always `#102A45` on `#FFFFFF`.
- Each shadow names its own dark value.
- `{colors.brand-navy-dark}` is the canvas color itself, used where the navy logo background must blend into the canvas.
- The splash canvas uses `{colors.bg-dark}` in dark mode, not `{colors.surface-dark}`, so the dark logo's background matches.

**Contrast.** Every load-bearing text pair meets WCAG 2.1 AA (4.5:1) in both themes. Every *interactive* boundary (inputs, the composer, secondary buttons, actionable chips) meets 3:1. Decorative card borders (`{colors.border}`) are lighter by design, because cards are separated by tone as well. The inactive Break the feed control is exempt from the 3:1 boundary rule, as WCAG allows for inactive controls, but its label still uses `{colors.ink-muted}`, so it stays readable.

| Pair | Light ratio | Dark ratio |
| --- | --- | --- |
| `{colors.ink}` on `{colors.surface}` | 14.6 | 13.9 |
| `{colors.ink-muted}` on `{colors.sunken}` | 5.9 | 9.0 |
| `{colors.ink-muted}` on `{colors.neutral-soft}` (inactive Break the feed, Ignore chip) | 5.9 | 6.6 |
| `{colors.on-action}` on `{colors.action}` (primary button) | 5.9 | 7.9 |
| `{colors.action-ink}` on `{colors.bg}` (links, always underlined) | 5.5 | 8.9 |
| `{colors.on-attention}` on `{colors.attention}` (Break the feed) | 5.7 | 6.2 |
| `{colors.attention-ink}` on `{colors.attention-soft}` (tell-now chip) | 5.5 | 5.4 |
| `{colors.info-ink}` on `{colors.info-soft}` (digest chip) | 6.4 | 6.3 |
| `{colors.success-ink}` on `{colors.success-soft}` | 5.6 | 6.5 |
| `{colors.warning-ink}` on `{colors.warning-soft}` ("Simulated" label) | 5.8 | 7.2 |
| `{colors.danger-ink}` on `{colors.danger-soft}` | 5.8 | 6.1 |
| `{colors.focus}` on `{colors.sunken}` (focus ring, 3:1 needed) | 5.1 | 9.4 |
| `{colors.border-strong}` on `{colors.sunken}` (input border, 3:1 needed) | 3.2 | 4.4 |
| `{colors.brand-orange}` "Talon" wordmark on its header (large bold text, 3:1 needed) | 4.0 | 3.7 |
| `{colors.phone-frame}` on `{colors.bg}` (phone outline) | 13.6 | 4.2 |

## Typography

Three families, bundled with the app so the page never depends on a font CDN:

- **Montserrat** (weights 700–800) echoes the logo's geometric wordmark. It sets only the wordmark, display titles, and the empty-chat headline. It never sets body text.
- **Inter** carries the interface.
- **JetBrains Mono** sets values a person might compare or copy: dry-run before and after values, credentials on the splash, decision-message references, token counts in Details, and evidence excerpts.

| Token | Family, size, weight | Used for |
| --- | --- | --- |
| `{typography.wordmark}` | Montserrat 20px, 800 | The header wordmark |
| `{typography.display-lg}` | Montserrat 28px, 700 | Splash, sign-in, and resetting-view titles |
| `{typography.display-md}` | Montserrat 20px, 700 | Page titles on later surfaces; the empty-chat headline |
| `{typography.headline}` | Inter 17px, 600 | Reserved for an incident's headline ("50 orders failed since 14:12 ET"), the demo's climax |
| `{typography.title}` | Inter 15px, 600 | Dialog titles; the splash subheading |
| `{typography.body-chat}` | Inter 15px, 400 | Conversation text and the guide's quoted prompt |
| `{typography.body}` | Inter 14px, 400 | The dense default for rails, lists, settings, and splash paragraphs |
| `{typography.body-strong}` | Inter 14px, 600 | Button labels, rail row titles, answered statuses, tab labels |
| `{typography.body-sm}` | Inter 13px, 400 | Reasons, detail lines, hints, inline notices, field errors, the run total |
| `{typography.label}` | Inter 12px, 600, tracked | Rail section headings and in-card labels ("Demo control", "Approval needed", "Dry run") |
| `{typography.caption}` | Inter 12px, 400 | Timestamps, costs, meta lines, expiry |
| `{typography.mono}` | JetBrains Mono 13px | Dry-run values and splash credentials |
| `{typography.mono-sm}` | JetBrains Mono 12px | Evidence excerpts, token breakdowns, references, and the phone's compact dry-run values |
| `{typography.phone-body}` | Inter 14px, 400 | Text on the simulated phone |

`{typography.label}` text is authored in sentence case and shown in capitals with `text-transform`, so screen readers say words, not letters.

The wordmark is never smaller than 19px at weight 700 or more. At that size it counts as large text, so the orange "Talon" meets the 3:1 large-text minimum. The smallest text is 12px. Numbers in costs, counts, and countdowns use tabular figures, so a ticking countdown never jitters.

## Layout & Spacing

The main page is designed for a **1280×720 browser viewport**. The page fills the viewport rather than scrolling as a whole, so each region scrolls on its own. **The acceptance test:** at a 1280×600 viewport (a 1280×720 *screen* with browser chrome), the incident card's headline, cause, dry-run count, Approve, and Reject are visible without scrolling the chat.

```
┌ app header (56) ─────────────────────────────────────────────────────┐
├ status banner slot (0 or 44+ each) ──────────────────────────────────┤
├ demo guide (min 92; 56 compact; demo mode only) ─────────────────────┤
│  steps and prompt bar (spans rail + chat)  │ Break the feed box (352) │
├ status rail (288) ┬ chat (fills, text ≤ 72ch) ┬ simulated devices (352) ┤
└───────────────────┴───────────────────────────┴─────────────────────────┘
```

Regions are separated by 1px borders, not gutters, so the page reads as one instrument panel.

The spacing scale is 4px-based (`{spacing.1}` to `{spacing.12}`). Rails and lists use 8px and 12px; cards use 16px inside and 12px between; the splash breathes at 24px to 48px.

- **Width.** At 1280px wide, the chat column is about 640px. Its text lines cap at `{spacing.chat-text-max}`, while cards may use the full column width. At 1440px and wider, the rail grows to `{spacing.rail-width-wide}` and the device column to `{spacing.device-width-wide}`.
- **Height.** At a 720px viewport the three columns get about 570px. When the viewport is shorter than 680px, the guide switches to its compact single-row form (`{spacing.guide-compact-height}`).
- **The phone** fills its column's height. Its screen keeps a fixed width of `{spacing.phone-screen-width}` and shrinks in height to no less than `{spacing.phone-screen-min-height}`. When the column is shorter than that, the screen's content scrolls.
- **Minimum heights, not fixed heights.** The header, guide, buttons, and inputs use minimum heights, so text can grow to 200% without clipping.
- **Scroll gutters.** Every scrolling region keeps `{spacing.scroll-gutter}` of inline padding, so focus rings aren't clipped at its edges.
- **Without demo mode,** the guide strip and device column disappear and the chat widens.
- **Narrower windows** and the stacked fallback are specified in `EXPERIENCE.md`, under Responsive & Platform.

**The splash** sits on `{components.splash-canvas}`: white in light mode, so the light logo's white background disappears, and `{colors.bg-dark}` in dark mode. It is a centered column, at most `{spacing.splash-max-width}` wide: the full logo, the heading and subheading, two cards side by side (sign-in and "Before you start"), then the Visual Trace card and the footer. In the normal state the sign-in button sits above the fold at a 1280×600 viewport, the same acceptance test as the main page; the full logo shows at 240px wide here to make room.

**The sign-in page and the resetting view** use the same canvas, with one centered card (`{spacing.sign-in-card-width}`) under the logo.

→ Composition reference: [mockups/main-page.html](mockups/main-page.html) (the main page at 1280×720, light and dark) and [mockups/splash.html](mockups/splash.html) (the splash, sign-in page, and resetting view).

## Elevation & Depth

The page is flat. Depth comes from tone: `{colors.bg}` for rails, `{colors.surface}` for the chat and cards, and `{colors.sunken}` for user messages, dry runs, and evidence. In dark mode the order is the same, with `{colors.raised-dark}` for anything that floats.

Shadows appear in four places only:

- **Popovers** (the Visual Trace sign-in hint, menus).
- **Dialogs** (About, the Sign out warning), over `{colors.scrim}`.
- **The new-messages button**, which floats over the chat.
- **The simulated phone**, whose shadow is the one physical-object cue on the page. It reads as a device on a desk, which helps the "Simulated" label land. In dark mode its slate frame carries that cue, because the shadow barely shows.

Cards never lift on hover.

## Shapes

- `{rounded.xs}` (4px): text inputs, citation chips, tooltips, and skeleton blocks.
- `{rounded.sm}` (6px): buttons, inline notices, dry-run and evidence blocks, and the QR code's tile.
- `{rounded.md}` (10px): cards, chat bubbles, the composer, and the mailbox.
- `{rounded.lg}` (16px): dialogs and the phone screen.
- `{rounded.xl}` (28px): the phone frame only.
- `{rounded.full}`: chips and badges.

**Pills mean state or category:** outcome chips, state chips, the context badge, and the reset countdown are borderless; the "Simulated" label is the one outlined state pill, in amber. **An actionable chip always carries a `{colors.border-strong}` outline and a hover fill;** currently, only the sample email chips. Buttons, including the new-messages button, are never pill-shaped.

## Components

Visual specs live here; behavior lives in `EXPERIENCE.md`'s Component Patterns, under the same names and groups. Every interactive target is at least `{spacing.target-min}` tall, and phone buttons are `{spacing.control-height-lg}` tall. The release-plan steps (step 1 is release 1, 0.1.0, with Telegram in 0.1.1; steps 2 to 6 follow) mark components that arrive later.

→ State reference: [mockups/states.html](mockups/states.html) shows the alternate states of the incident card, approval request card, decision strip, demo guide, Break the feed, Telegram card, banners, and simulated devices.

### Frame

- **App header.** On `{colors.header-bg}`, from left to right:
  - the logo mark (`logo/web/icon-192.png`, shown at 28px, its navy tile intact);
  - the wordmark ("Ocu" `{colors.ink}`, "Talon" `{colors.brand-orange}`);
  - the context badge, a neutral pill reading "Online demo" or "Demo mode";
  - the header navigation, from step 2 of the release plan (the current item in `{colors.ink}` with a teal bottom bar, the others in `{colors.ink-muted}`);
  - right-aligned: the reset countdown, the Visual Trace menu, the theme menu, and the account menu.
- **Buttons and focus ring.**
  - **Variants:** primary (teal fill), secondary (surface with a `{colors.border-strong}` outline), attention (orange fill, for Break the feed only), and ghost (text only). Each has a hover fill from its tokens.
  - **Inactive:** a `{colors.neutral-soft}` fill, a dashed border, and an `{colors.ink-muted}` label.
  - **Busy:** the label stays and a spinner appears before it.
  - **The focus ring:** 2px solid `{colors.focus}` at a 2px offset, with a `{colors.surface}` halo filling the offset. Nothing else on the page uses this double ring.
- **Status banner.** Full width under the header. A 4px left accent and an icon in the variant's ink (`triangle-alert` for warning, `circle-alert` for danger, `info` for info), the message in `{colors.ink}`, at most one underlined action link, and an optional close button. Variants: warning, danger, and info.
- **Inline notice.** A compact notice inside a card or page: an icon and text on a tinted background, with no accent bar. It carries the Visual Trace warning and the reset-soon note on the splash, the post-reset note above the splash cards, the narrow-window note, and the "unreachable" note under a button whose server call failed. Warning and info variants.
- **Field error.** Text in `{colors.danger-ink}` with a `circle-alert` icon, under the field or button it belongs to. When the error belongs to particular fields (wrong credentials, an empty Subject), those fields' borders turn `{colors.danger-ink}`. An error about the request as a whole (too many sessions) marks no field.
- **Reset countdown.** A neutral pill showing "Next reset 16:00 · in 1 h 42 min". It switches to `reset-countdown-urgent` (amber) from 10 minutes before the reset.
- **Visual Trace menu.** A ghost button with an `external-link` icon that opens a popover. The popover holds the whole-conversation link and, on the online demo, the read-only credential rows.
- **Popover and dialog.** A raised surface, a border, and a shadow, from their tokens. The Visual Trace sign-in popover's visible heading is "Sign in to Visual Trace".
- **Tooltip.** Light text on `{colors.ink}`, 12px.
- **Skeleton.** Static `{colors.sunken}` blocks in the shape of the expected rows. They never shimmer.
- **Link and trace link.** Links are underlined by default, more heavily on hover and focus. The trace link is an `external-link` icon plus an underlined "Trace" in `{colors.action-ink}` caption text; the icon doesn't replace the underline.

### Demo guide and controls

- **Demo guide.** A strip on `{colors.surface}`.
  - **Row 1** (left area, spanning the rail and chat width): the label "Demo guide", five steps joined by chevrons, "About 2 minutes", and a "Hide guide" ghost button.
  - **Row 2, the prompt bar:** on `{colors.sunken}`, so the exact prompt reads as a quotation. It holds "Next:", the selected step's exact prompt in quotes (`{typography.body-chat}`), and the step's action button.
  - **The right area,** aligned over the device column, is the Break the feed box.
  - **Step markers:** a check for done, a filled teal disc with the step number for current, and a hollow circle with the number for upcoming. The selected step also gets a 2px bottom bar. None of these markers is a teal ring, so none looks like the focus ring.
  - **The compact form** puts the steps (numbers only) and the prompt bar in one row.
  - **The finish state** replaces the prompt bar. Its run-total line ("This run: 3 decisions · 9,850 tokens · $0.0041 on Claude Haiku 5.5") is `{typography.body-sm}` in `{colors.ink-muted}` with tabular figures.
- **Guide collapsed bar.** One row ("Demo guide · step 2 of 5 · Show guide") at 40px minimum height. The Break the feed box keeps its place at the right end of the bar, with its "Demo control" label inline before the button.
- **Break the feed.** The box always carries its "Demo control" label (`{typography.label}` in `{colors.attention-ink}`), above the button. The label is the only demo marking; the button has no extra tag.
  - **Active:** a `button-attention` with a `zap` icon, labeled "Break the feed".
  - **Next step:** while it is the current step and active, the box adds a 4px teal left bar and a "Next step" tag (`{colors.action-soft}` with `{colors.action-ink}`). The marker leaves once the button is pressed.
  - **Step 5 current:** while "Open the trace" is the current step, the active button takes the secondary style, so the trace step leads; it returns to the attention style once the finish state shows.
  - **Inactive:** the inactive button style, with the hint as visible text beneath it in `{colors.ink-muted}`.
  - **Waiting:** the button shows as inactive. The waiting and live-status lines sit under it in `{typography.body-sm}`, with the elapsed time as "23 s".

### Status rail

- **Status rail section.** A `{typography.label}` heading, with a count where the section is a list, then rows divided by `{colors.border}`. A row has a title (`{typography.body-strong}`), a detail line (`{typography.body-sm}`), and a meta line (`{typography.caption}`) carrying the row's trace link.
- **Approval request row, background check row, reminder row.** These follow the section pattern. An approval request row carries a 3px attention bar on its left. A reminder row's countdown uses tabular figures.
- **Telegram card** (from 0.1.1; a release without Telegram has no Telegram section). The section heading is "Telegram", with no count.
  - **Unpaired:** the QR code block (132px, always navy on white in both themes), one line of instructions, an underlined "Open in Telegram" link, and "New code in 9 min" in caption.
  - **Paired:** one row with `circle-check` in `{colors.success-ink}`, "Telegram paired · {name}", and an "Unpair" ghost button.
  - **Not set up:** "Telegram not set up" with a "How to set it up" link.
  - **Paused:** `pause-circle` in `{colors.warning-ink}`, "Telegram paused", and "Trying again at {time}" in caption.
  - **Just unpaired:** `circle-slash` in `{colors.ink-muted}` and "Telegram unpaired".
- **Decision row.** Line 1: the outcome chip and a one-line item summary (the disclosure button, with a chevron). Line 2: the first line of the reasons. Line 3, the meta line: time, confidence, cost, and the trace link, placed beside the button, never inside it. A fallback decision adds the fallback flag.

### Chat

- **Chat message (user).** A right-aligned bubble on `{colors.sunken}`, `{rounded.md}`, at most 80% of the column width. Messages sent from the demo guide carry a small "From the demo guide" caption.
- **Chat message (OcuTalon).** Left-aligned and unboxed, under a 24px logo-mark avatar and the name "OcuTalon". The text is in `{typography.body-chat}`, with the decision strip directly underneath.
- **Decision strip.** Line 1: the outcome chip, the fallback flag if any, then "Confidence 0.94 · $0.0006 · Trace" in `{typography.caption}` and `{colors.ink-muted}`. Line 2: the reasons in `{typography.body-sm}`, up to three lines. For a fallback, the fallback reason is the first line of the reasons, in `{colors.warning-ink}`. Last comes the "Details" disclosure, which reveals the token breakdown and the decision-message reference in `{typography.mono-sm}`.
- **Check row.** One code-computed check result per row, shown under a chat reply that answers "is everything OK?" (release 1) and in the digest card (step 2). Each row has a check-result icon and word ("Passed", "Failed", "Not checked"), the entry name, and the finding or reason with its time in muted text.
- **Outcome chip.** A borderless pill with an icon and a label (Ignore, Digest, Tell now, Act), colored by the four `outcome-chip-*` tokens.
- **Fallback flag.** An amber pill with a `life-buoy` icon, labeled "Fallback". It sits beside the outcome chip, and beside the state chip on an incident card.
- **Turn indicator.** A row in `{colors.ink-muted}` with the 24px avatar and the text "Deciding…" or "Working…". With reduced motion it is static; otherwise three dots animate.
- **New-messages button.** A small raised secondary button, "New messages", with a `chevron-down` icon. It floats centered above the composer and casts a popover shadow.
- **Composer.** A text area on `{colors.surface}` with a `{colors.border-strong}` border, an `{colors.ink-muted}` placeholder, and a "Send" `button-primary`. It grows to 5 lines, then scrolls. When the composer can't send, its reason appears as a visible line above it in `{colors.ink-muted}`.
- **Notice card.** For reminders and tell-now notifications. A 4px accent bar (info for reminders, attention for tell now), an icon (`bell` for reminders, `bell-ring` for tell now), and the message text exactly as `EXPERIENCE.md`'s Message Catalog gives it ("Reminder: stretch."), with no separate title, so nothing repeats. A reminder shows its due and arrival times in caption. A tell-now card adds its "Why now:" line and decision strip.
- **Empty chat panel.** The headline in `{typography.display-md}`, the four outcome chips with their meanings in `{typography.body-sm}`, then the panel's remaining lines in `{typography.body}` and `{colors.ink-muted}`, centered in the chat.

### Incident and approval components

- **Incident card.** A full-width card with a 4px left accent bar: attention while the incident needs a person (including the fallback, rejected, and expired variants of open), info while fixing, success when resolved, and border-strong when closed. Anatomy, top to bottom:
  1. the state chip (and the fallback flag, if any) and the time;
  2. the headline in `{typography.headline}`;
  3. the cause sentence in `{typography.body-chat}`;
  4. the evidence line in `{typography.body-sm}` and `{colors.ink-muted}` ("Data format change · order date · 50 failures grouped into this incident");
  5. the proposed fix sentence, without the message's closing "Approve?", which belongs to phone and Telegram text only;
  6. the embedded approval request card, or, on a fallback card, the failure groups and a row with "Show details" and Dismiss;
  7. the evidence panel, when expanded;
  8. a footer with the decision strip and the trace link.
- **Incident state chip.** A borderless pill, colored by the five `incident-state-*` tokens.
- **Approval request card.** Inside an incident card, or on its own for other risky actions. While pending, it holds:
  - a `{typography.label}` reading "Approval needed";
  - the action in the imperative ("Repair and resend 50 orders."), followed, on standalone requests only, by "Why:" with the reason (inside an incident card the cause already sits just above);
  - the fixed-targets line in `{typography.body-sm}`;
  - the dry run block;
  - one row with Approve (`button-primary`) and Reject (`button-secondary`) side by side, Approve first, and "Show details" as a ghost button at the row's right end;
  - the expiry in caption.

  Once answered, the label reads "Approval request", the answered status replaces the two buttons in the same row, and "Show details" stays at the right. The fixed-targets line, the expiry, and the dry run's "Nothing has changed yet." are removed, and the dry run stays as a record.
- **Answered status.** One line in `{typography.body-strong}` with an icon: `circle-check` in `{colors.success-ink}` for approved, `circle-slash` in `{colors.ink-muted}` for rejected, and `clock` in `{colors.ink-muted}` for expired. Example: "Approved from Telegram at 14:15". When there is no result notice, Dismiss sits at the right end of this row.
- **Dry run block.** On `{colors.sunken}`. A "Dry run" label and a count line ("50 orders affected"). Then the example as two rows, each labeled in text so color is never the only cue: "Before" with its value in `{typography.mono}` and `{colors.danger-ink}`, and "After" with its value in `{typography.mono}` and `{colors.success-ink}`. Last come the "Will resend" line and, while pending, "Nothing has changed yet."
- **Evidence panel.** Revealed by "Show details", below the approval row. On `{colors.sunken}`, with message excerpts and errors in `{typography.mono-sm}`; its labels stay in Inter.
- **Result notice.** A band inside the incident card: `result-success` with `circle-check` for a full success ("All 50 orders went through."), or `result-partial` with `triangle-alert` for a partial result. Dismiss is a ghost button at the band's right end. The audit line ("Recorded in the IRIS audit log.") sits beneath the band in caption.

### Simulated device components

- **Simulated device panel.** A column on `{colors.bg}`. Its header holds the two device tabs ("Simulated phone" and "Simulated mailbox"). The selected tab has a 3px teal bottom bar and `{colors.ink}` text. An unselected tab with new content shows a tab badge with its count.
- **Simulated label.** An amber outlined pill reading "Simulated", always visible. It sits inside each device, in the phone's top bar and in the mailbox's header, so it travels with the device rather than crowding the tab row. It never sits on a color it could blend into.
- **Simulated phone.** A generic phone silhouette:
  - a frame in `{colors.phone-frame}` with `{rounded.xl}` corners;
  - a screen on `{colors.surface}`;
  - a device shadow (the light shadow, or the dark one in dark mode);
  - a top bar reading "OcuTalon", with the Simulated label where a carrier name would be.

  It has no clock, signal bars, or brand marks, and it never imitates the Telegram interface. Messages are phone notifications stacked newest at the bottom.
- **Phone notification.** A `{colors.sunken}` bubble in `{typography.phone-body}` with a caption timestamp. An approval request adds the compact dry run: an inset on `{colors.surface}` holding the Message Catalog's dry-run sentence, with the before and after values in `{typography.mono-sm}`, in danger and success ink respectively. Then come Approve and Reject **side by side**, each half the width and `{spacing.control-height-lg}` tall, with Approve on the left.
- **Simulated mailbox.** A header ("Simulated mailbox" with the Simulated label), then the sample email chips (always visible), a "Simulate an incoming email" `button-secondary`, and the inbox list of email rows. The compose form opens in place of the list.
- **Email row.** Sender, subject, and time. Unread rows carry a teal dot and the visually hidden word "Unread" (announced by screen readers). Once OcuTalon has decided, the row shows its outcome chip.
- **Sample email chip.** A bordered, actionable pill with a `mail` icon: "Sample: newsletter", "Sample: partner notice", or "Sample: suspicious request". The three chips wrap to a second row when the mailbox is narrow.

### Sign-in

- **Credential card.** On the splash: one row per credential, each with a label, a monospaced value, and a copy icon button. The password is shown in plain text, because it is public.
- **Sign-in form.** Inputs at `{spacing.control-height-lg}` minimum height with `{rounded.xs}`. On the sign-in page, labels sit above the inputs; on the splash, where the values are prefilled, labels sit beside them in an 88px column, which keeps the button above the 1280×600 fold. Both end with a full-width `button-primary` to submit ("Sign in and start" on the splash). Errors use the field error style under the button. On the splash, the heading is followed by its subheading in `{typography.title}`.
- **Full logo.** `logo/web/OcuTalon-Logo-light-640.png` in light mode and `…-dark-640.png` in dark mode, shown at 240px wide on the splash and 320px on the sign-in page and resetting view, using the 1280 files on high-density screens. It appears only on the splash canvas, the sign-in page, and the resetting view.

### Later-step components

- **Digest card** (step 2). A 4px brand-teal accent bar, the digest text, then check rows grouped under small labels.
- **Citation chip** (step 3). An `{colors.info-soft}` chip with a 1px `{colors.info-ink}` border and a `file-text` icon: "Results runbook § Rotating the certificate".
- **Classification control** (step 4). A segmented radio group: Unclassified (counts as risky), Read-only, Risky. The selected option uses its `classification-*` colors and a check icon; the others stay neutral.
- **Usage chart** (step 6). Token bars in `{colors.chart-tokens}` and the cost line in `{colors.chart-cost}`, each labeled directly as well as in the legend.
- **History table** (step 6). Rows at least 40px tall, with outcome chips in the first column.

## Do's and Don'ts

| Do | Don't |
| --- | --- |
| Use teal only for actions, links, focus, the selected tab, and the act outcome | Use teal as decoration or as a section background |
| Use orange only for things that need a person, plus the wordmark | Use orange for errors (red), warnings (amber), or decoration |
| Pair every state color with a text label and an icon | Signal outcome, state, or check result by color alone |
| Underline every link | Rely on teal alone to show a link |
| Draw the current guide step as a filled disc, and keep rings for focus only | Use a ring of the focus color as a "current" or "selected" marker |
| Set values a person might compare or copy in JetBrains Mono | Set reasons or chat messages in mono |
| Show the "Simulated" label on both devices at all times, in amber outline | Fade, shrink, or tooltip-hide the "Simulated" label |
| Draw a generic phone with "OcuTalon" in its top bar | Imitate Telegram's interface, colors, or icons, or any real phone brand |
| Place the full logo only on `{components.splash-canvas}` (white in light, `{colors.bg-dark}` in dark) | Put the logo images on `{colors.bg}` or any tinted surface, where their background box shows |
| Use the light logo in light mode and the dark logo in dark mode | Recolor, crop, outline, or animate the logo |
| Keep the QR code navy-on-white in both themes | Invert the QR code for dark mode |
| Keep surfaces flat and let tone separate regions | Add hover lift, glassmorphism, or gradient cards |
| Give actionable chips a border and a hover fill | Make a borderless pill do something when pressed |
| Show cost on every decision in quiet caption text | Hide cost, or make it loud |
| Mention OpenClaw only where the not-affiliated note appears with it | Use OpenClaw's name in the product's own name or labels, or its logo or artwork anywhere |

*OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.*
