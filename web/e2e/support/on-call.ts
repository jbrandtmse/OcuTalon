import { expect, type APIRequestContext } from '@playwright/test';

import { envelope } from '../sign-in/helpers';
import { chk, irisScript, quoted } from './iris';

/**
 * What the two On call specs (Story 36.4) share: the on-call member of GET /v1/settings, the body that puts values back, the seven stored keys as a fresh
 * process reads them (the read path of Stories 23.4 and 24.3), and the IRIS audit entries of the on-call keys since a mark.
 */
export const SETTINGS_API = '/ocutalon/api/v1/settings';
export const ON_CALL_API = '/ocutalon/api/v1/settings/on-call';

/** The on-call member of GET /v1/settings, as the page reads it. */
export interface OnCallStored {
  primaryUser: string;
  primaryEmail: string;
  primaryChannels: string;
  backupUser: string;
  backupEmail: string;
  backupChannels: string;
  escalationMinutes: number;
  users: Array<{ user: string; paired: boolean }>;
  pagesBuilt: boolean;
}

/** The seven keys, in the form's order, with the field of the member that each one holds. */
export const ON_CALL_KEYS = [
  ['oncall.primary.user', 'primaryUser'],
  ['oncall.primary.email', 'primaryEmail'],
  ['oncall.primary.channels', 'primaryChannels'],
  ['oncall.backup.user', 'backupUser'],
  ['oncall.backup.email', 'backupEmail'],
  ['oncall.backup.channels', 'backupChannels'],
  ['oncall.escalationMinutes', 'escalationMinutes'],
] as const;

/** An audit entry of a setting, as the scripts print it. */
export interface AuditSetting {
  setting: string;
  from: string;
  to: string;
  irisUser: string;
  sessionRef: string;
  channel: string;
}

/** The on-call member of GET /v1/settings for the signed-in admin of the request context. */
export async function readOnCall(request: APIRequestContext): Promise<OnCallStored> {
  const response = await request.get(SETTINGS_API);
  expect(response.status(), 'GET /v1/settings as an admin').toBe(200);
  const body = (await response.json()) as { sections: { 'on-call'?: OnCallStored } };
  expect(body.sections['on-call'], 'the on-call member').toBeTruthy();
  return body.sections['on-call'] as OnCallStored;
}

/** The body of a save that gives every field the value that the stored members hold. */
export function bodyOfStored(values: OnCallStored): Record<string, string | number> {
  const role = (user: string, email: string, channels: string, prefix: 'primary' | 'backup'): Record<string, string> => ({
    [`${prefix}Person`]: user !== '' ? 'user' : email !== '' ? 'email' : 'nobody',
    [`${prefix}User`]: user,
    [`${prefix}Email`]: email,
    [`${prefix}Channels`]: channels,
  });
  return {
    ...role(values.primaryUser, values.primaryEmail, values.primaryChannels, 'primary'),
    ...role(values.backupUser, values.backupEmail, values.backupChannels, 'backup'),
    escalationMinutes: values.escalationMinutes,
  };
}

/** The body of a save that chooses Nobody for both roles, with the default channels and 15 minutes: the section's default state. */
export const NOBODY_BODY: Readonly<Record<string, string | number>> = {
  primaryPerson: 'nobody',
  primaryUser: '',
  primaryEmail: '',
  primaryChannels: 'telegram,email',
  backupPerson: 'nobody',
  backupUser: '',
  backupEmail: '',
  backupChannels: 'telegram,email',
  escalationMinutes: 15,
};

/** Saves the default state (Nobody for both roles) through the route, so that a case starts from known values whatever an earlier run or an operator left. */
export async function resetOnCall(request: APIRequestContext): Promise<void> {
  const response = await request.post(ON_CALL_API, { headers: envelope(), data: NOBODY_BODY });
  expect(response.status(), `the on-call values are reset to Nobody: ${await response.text()}`).toBe(200);
}

/** Puts the stored values back through the route (a save of what they were). */
export async function restoreOnCall(request: APIRequestContext, values: OnCallStored): Promise<void> {
  const response = await request.post(ON_CALL_API, { headers: envelope(), data: bodyOfStored(values) });
  expect(response.status(), `the on-call values are restored: ${await response.text()}`).toBe(200);
}

/** The seven values as a fresh IRIS process reads them through Data.Setting.Get (which has no cache entry in a new process). */
export async function freshValues(): Promise<Record<string, string>> {
  const lines = await irisScript(ON_CALL_KEYS.map(([key], index) => `Write !,"CHK|k${index}|",##class(OcuTalon.Data.Setting).Get(${quoted(key)})`).join('\n'));
  return Object.fromEntries(ON_CALL_KEYS.map(([key], index) => [key, chk(lines, `k${index}`) ?? '(none)']));
}

/** The audit clock now, in the form that auditSince takes. */
export async function auditMark(): Promise<string> {
  const mark = chk(await irisScript('Write !,"CHK|now|",##class(OcuTalon.Test.Bridge.AuditLog).Now()'), 'now');
  expect(mark, 'the audit clock').toBeTruthy();
  return mark as string;
}

/** The Settings audit entries of the on-call keys written at or after the mark, oldest first: waits up to `seconds` for `count` of them. */
export async function auditSince(mark: string, count: number, seconds = 60): Promise<AuditSetting[]> {
  const lines = await irisScript(
    [
      `Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(${quoted(mark)},"OcuTalon","Settings","","oncall.","",${count},${seconds})`,
      'Write !,"CHK|n|",e.%Size()',
      'For i=0:1:e.%Size()-1 { Set d=e.%Get(i).data Write !,"CHK|e"_i_"|",d.setting_"|"_d.from_"|"_d.to_"|"_d.irisUser_"|"_d.sessionRef_"|"_d.channel }',
    ].join('\n'),
  );
  const found = Number(chk(lines, 'n') ?? '-1');
  expect(found, 'the audit entries could be read').toBeGreaterThanOrEqual(0);
  const entries: AuditSetting[] = [];
  for (let i = 0; i < found; i += 1) {
    const [setting = '', from = '', to = '', irisUser = '', sessionRef = '', channel = ''] = (chk(lines, `e${i}`) ?? '').split('|');
    entries.push({ setting, from, to, irisUser, sessionRef, channel });
  }
  return entries;
}
