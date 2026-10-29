/**
 * The status banners of the page (Story 2.10, UX-DR34, UX-DR97 to UX-DR100, UX-DR116): the closed catalog of ten banners and the
 * view of the live store that the banner stack renders. A framework-free module: it imports only types and uses only erasable
 * TypeScript syntax, so Node runs it as it is. Every value it reuses (the catalog's texts, the page time, the cost format, the
 * README addresses of the install, set-a-key and Telegram sections) comes in through BannerFormat, which the component builds from the
 * real modules.
 *
 * - BANNERS is the table of the ten banners in the order they stack: each one's id (the data-banner), variant, icon, catalog
 *   key, action and whether it can be closed. Variants, icons, actions and closing are page presentation; the texts are the
 *   catalog's (AD-32).
 * - bannersView(input, format) gives the banners to show, in table order: the store's active conditions that the table knows
 *   (an unknown or inactive one shows nothing), the page's own conditions, and none that the user closed with the signature it
 *   has now. dailyCap is the online demo's danger banner when onlineDemo is true, and the warning costCap otherwise.
 * - A banner's text is the catalog's text with its slots as strings: {time} is a page time in the browser's zone and hour
 *   format with no suffix (DW-29), {cap} a cost, {limit} digits. A slot that is missing or unreadable is empty, and the banner
 *   still shows: a warning is never dropped. bannerText renders it, and the allowance reason of the composer and the guide is
 *   that same text (Story 16.9).
 * - Closing (only Reset soon and Reconnecting can be closed): closeBanner remembers the banner's signature, its id and slots;
 *   the banner stays away while its condition holds with that signature. retainClosed drops the records of a condition that
 *   has cleared or whose slots changed, so it shows again when the condition starts again or gets worse.
 * - demoBusy (Story 16.5) is the online demo's own condition: the demo cannot take another session, found by an API 503 or by a
 *   trace check that said busy (live/demo-busy.ts). It shows only when onlineDemo is true, and cannot be closed.
 * - REPLACED_BY names the banner that takes over another's place when it leaves (Story 2.11; UX-DR131): Unreachable replaces
 *   Reconnecting, and the stack moves focus there when the replaced banner held it.
 */
import type { StatusPayload, StatusSlots } from '../live/payloads';

/** The ten banners, by the id that the page marks them with (data-banner). */
export type BannerId =
  | 'allowance'
  | 'dailyCap'
  | 'unreachable'
  | 'demoBusy'
  | 'noModelKey'
  | 'costCap'
  | 'heartbeatStalled'
  | 'telegramPaused'
  | 'resetSoon'
  | 'reconnecting';

/** The conditions that only the page knows (Stories 2.11 and 16.5): no event carries them. */
export type OwnCondition = 'unreachable' | 'reconnecting' | 'demoBusy';

export type BannerVariant = 'danger' | 'warning' | 'info';

/** The icon of a banner, one of the page's own. */
export type BannerIcon = 'circle-alert' | 'triangle-alert' | 'info';

/** Where an action of a banner leads: the README's install section, its model-key section, or its Telegram section (DW-361). */
type ActionTarget = 'install' | 'setKey' | 'telegram';

/** A row of the table of banners. */
interface BannerSpec {
  id: BannerId;
  /** The status condition that raises it, or the page's own condition. */
  condition: string;
  /** When set, the banner shows only for this value of onlineDemo. */
  onlineDemo?: boolean;
  key: string;
  variant: BannerVariant;
  icon: BannerIcon;
  /** The catalog key of the action's text, and where it opens. */
  action?: { key: string; target: ActionTarget };
  closable: boolean;
}

/** The closed set of banners, in the order they stack (UX-DR100). */
export const BANNERS: readonly BannerSpec[] = [
  { id: 'allowance', condition: 'allowance', key: 'banner.allowance', variant: 'danger', icon: 'circle-alert', action: { key: 'bannerAction.installYourself', target: 'install' }, closable: false },
  { id: 'dailyCap', condition: 'dailyCap', onlineDemo: true, key: 'banner.dailyCap', variant: 'danger', icon: 'circle-alert', action: { key: 'bannerAction.installYourself', target: 'install' }, closable: false },
  { id: 'unreachable', condition: 'unreachable', key: 'banner.unreachable', variant: 'danger', icon: 'circle-alert', closable: false },
  { id: 'demoBusy', condition: 'demoBusy', onlineDemo: true, key: 'banner.demoBusy', variant: 'warning', icon: 'triangle-alert', action: { key: 'bannerAction.installYourself', target: 'install' }, closable: false },
  { id: 'noModelKey', condition: 'noModelKey', key: 'banner.noModelKey', variant: 'warning', icon: 'triangle-alert', action: { key: 'bannerAction.howToSetKey', target: 'setKey' }, closable: false },
  { id: 'costCap', condition: 'dailyCap', onlineDemo: false, key: 'banner.costCap', variant: 'warning', icon: 'triangle-alert', closable: false },
  { id: 'heartbeatStalled', condition: 'heartbeatStalled', key: 'banner.heartbeatStalled', variant: 'warning', icon: 'triangle-alert', closable: false },
  { id: 'telegramPaused', condition: 'telegramPaused', key: 'banner.telegramPaused', variant: 'warning', icon: 'triangle-alert', action: { key: 'bannerAction.setUpBot', target: 'telegram' }, closable: false },
  { id: 'resetSoon', condition: 'resetSoon', key: 'banner.resetSoon', variant: 'warning', icon: 'triangle-alert', closable: true },
  { id: 'reconnecting', condition: 'reconnecting', key: 'banner.reconnecting', variant: 'info', icon: 'info', closable: true },
];

/** The banners that another banner replaces when its condition worsens: the key is the one that leaves, the value the one that takes over. */
export const REPLACED_BY: Readonly<Partial<Record<BannerId, BannerId>>> = { reconnecting: 'unreachable' };

/** The conditions that only the page knows. */
const OWN_CONDITIONS: readonly string[] = ['unreachable', 'reconnecting', 'demoBusy'];

/**
 * Every fixed string of the banners that the catalog does not hold. The words that say a link opens a new tab are CHAT_TEXTS.opensInNewTab.
 * `close` is the name of each closable banner's icon-only Close button, by banner id: its action and its object (Story 2.14).
 */
export const BANNER_TEXTS = {
  close: { resetSoon: 'Close reset notice', reconnecting: 'Close reconnecting notice' },
} as const;

/** The name of a closable banner's Close button; "" for a banner that cannot be closed, which has none. */
export function closeName(id: BannerId): string {
  return (BANNER_TEXTS.close as Readonly<Partial<Record<BannerId, string>>>)[id] ?? '';
}

/** The values the view reuses from the page's other modules. */
export interface BannerFormat {
  /** The text of a catalog key that the page renders, its slots given as strings (renderPageText). */
  text(key: string, slots?: Readonly<Record<string, string>>): string;
  /** The hour and minute of a UTC time in the browser's zone and hour format, with no zone name; "" when the time is unreadable (pageTime). */
  time(iso: string): string;
  /** US dollars as the page shows a cost (formatCost). */
  cost(amount: number): string;
  /** The address of the README's "Install it yourself" section. */
  installUrl: string;
  /** The address of the README's "Set a model key" section. */
  setKeyUrl: string;
  /** The address of the README's Telegram section. */
  telegramUrl: string;
}

/** What the view reads. */
export interface BannerInput {
  /** The store's status conditions, by condition. */
  status: Readonly<Record<string, StatusPayload>>;
  /** The page's own conditions that hold now. */
  own: readonly OwnCondition[];
  onlineDemo: boolean;
  /** The signature of each banner the user closed, by id. */
  closed: Readonly<Partial<Record<BannerId, string>>>;
}

/** The action of a banner: a link that opens a new tab. */
export interface BannerAction {
  text: string;
  href: string;
}

/** One banner to show. */
export interface BannerView {
  id: BannerId;
  variant: BannerVariant;
  icon: BannerIcon;
  text: string;
  action?: BannerAction;
  closable: boolean;
  /** The banner's id and the slots of its condition: what closing remembers. */
  signature: string;
}

/** True when the store holds the condition as active. */
function holds(status: BannerInput['status'], condition: string): boolean {
  return Object.hasOwn(status, condition) && status[condition]?.active === true;
}

/** A count as digits; "" when it is not a count. */
function digits(value: unknown): string {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? String(Math.floor(value)) : '';
}

/** The banner's text slots, as strings, from its condition's slots. */
function textSlots(slots: StatusSlots, format: BannerFormat): Record<string, string> {
  return {
    limit: digits(slots.limit),
    cap: typeof slots.cap === 'number' && Number.isFinite(slots.cap) ? format.cost(slots.cap) : '',
    time: typeof slots.time === 'string' ? format.time(slots.time) : '',
  };
}

/**
 * The text of a banner: its catalog key with its condition's slots, as the stack shows it. The composer and the demo guide reuse it
 * for the allowance reason (Story 16.9), so that the reason they show is the banner's own text.
 */
export function bannerText(key: string, slots: StatusSlots, format: BannerFormat): string {
  return format.text(key, textSlots(slots, format));
}

/** The address an action opens, from its target. */
function hrefOf(target: ActionTarget, format: BannerFormat): string {
  return target === 'telegram' ? format.telegramUrl : target === 'setKey' ? format.setKeyUrl : format.installUrl;
}

/** The id of the banner and its condition's slots as the store holds them. */
function signatureOf(spec: BannerSpec, slots: StatusSlots): string {
  return `${spec.id}|${JSON.stringify([slots.limit ?? null, slots.cap ?? null, slots.time ?? null])}`;
}

/** The banners whose condition holds, in table order, whether the user closed them or not. */
export function activeBanners(input: Pick<BannerInput, 'status' | 'own' | 'onlineDemo'>, format: BannerFormat): BannerView[] {
  const views: BannerView[] = [];
  for (const spec of BANNERS) {
    if (spec.onlineDemo !== undefined && spec.onlineDemo !== input.onlineDemo) {
      continue;
    }
    const own = OWN_CONDITIONS.includes(spec.condition);
    if (own ? !input.own.includes(spec.condition as OwnCondition) : !holds(input.status, spec.condition)) {
      continue;
    }
    const slots = own ? {} : (input.status[spec.condition]?.slots ?? {});
    const view: BannerView = {
      id: spec.id,
      variant: spec.variant,
      icon: spec.icon,
      text: bannerText(spec.key, slots, format),
      closable: spec.closable,
      signature: signatureOf(spec, slots),
    };
    if (spec.action) {
      view.action = { text: format.text(spec.action.key), href: hrefOf(spec.action.target, format) };
    }
    views.push(view);
  }
  return views;
}

/** The banners to show: those whose condition holds, in table order, except the closed ones that still have the signature they were closed with. */
export function bannersView(input: BannerInput, format: BannerFormat): BannerView[] {
  return activeBanners(input, format).filter((banner) => input.closed[banner.id] !== banner.signature);
}

/** The closed records with this banner added, under its signature. A banner that cannot be closed is not remembered. */
export function closeBanner(closed: BannerInput['closed'], banner: BannerView): BannerInput['closed'] {
  return banner.closable ? { ...closed, [banner.id]: banner.signature } : closed;
}

/**
 * The closed records that still apply: those whose banner is active with the signature it was closed with. A condition that
 * cleared, or whose slots changed, loses its record, so that it shows when it starts again or gets worse. It answers the records
 * it was given when none is dropped.
 */
export function retainClosed(closed: BannerInput['closed'], active: readonly BannerView[]): BannerInput['closed'] {
  const kept: Partial<Record<BannerId, string>> = {};
  let dropped = false;
  for (const [id, signature] of Object.entries(closed) as Array<[BannerId, string]>) {
    if (active.some((banner) => banner.id === id && banner.signature === signature)) {
      kept[id] = signature;
    } else {
      dropped = true;
    }
  }
  return dropped ? kept : closed;
}
