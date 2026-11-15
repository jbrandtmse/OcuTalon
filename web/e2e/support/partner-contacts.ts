import { expect, type APIRequestContext } from '@playwright/test';

import { chk, irisScript, quoted } from './iris';

/**
 * What the two Partner contacts specs (Story 24.2) share: the route, the real state of the Partner contacts switch, the member of GET /v1/settings as the
 * server's own PartnerValues() builds it (read in a fresh IRIS process: the TABLE 1 state that the UI spec simulates), the stored contacts, a production that
 * the instance offers, ForProduction as a fresh process (the reader of Story 23.13) answers it, the cleaning of the contacts that a case made, and the Settings
 * audit entries of the contacts since a mark. A contact that a case makes has a name that begins `zz-`.
 */
export const SETTINGS_API = '/ocutalon/api/v1/settings';
export const PARTNER_API = '/ocutalon/api/v1/settings/partner-contacts';

/** A production that a contact can concern, as the server lists it. */
export interface PartnerProduction {
  namespace: string;
  production: string;
  displayName: string;
}

/** A stored contact, as the server lists it. */
export interface PartnerStored {
  ref: string;
  name: string;
  email: string;
  productions: Array<{ namespace: string; production: string }>;
}

/** The member of GET /v1/settings. */
export interface PartnerMember {
  contacts: PartnerStored[];
  productions: PartnerProduction[];
}

/** An audit entry of a contact, as the scripts print it. */
export interface PartnerAudit {
  setting: string;
  from: string;
  to: string;
  irisUser: string;
  sessionRef: string;
  channel: string;
}

/** True when the real GET /v1/settings of the signed-in admin carries the partner-contacts member: OcuTalon.Fix.PartnerContacts has TABLE = 1. */
export async function partnerShown(request: APIRequestContext): Promise<boolean> {
  const response = await request.get(SETTINGS_API);
  expect(response.status(), 'GET /v1/settings as an admin').toBe(200);
  const body = (await response.json()) as { sections: Record<string, unknown> };
  return body.sections['partner-contacts'] !== undefined;
}

/** The real TABLE of OcuTalon.Fix.PartnerContacts as the class declares it ("" when it declares none). */
export async function realTable(): Promise<string> {
  const lines = await irisScript('Write !,"CHK|table|[",$Parameter("OcuTalon.Fix.PartnerContacts","TABLE"),"]"');
  const value = chk(lines, 'table');
  expect(value, 'the TABLE of OcuTalon.Fix.PartnerContacts can be read').toBeDefined();
  return (value as string).slice(1, -1);
}

/** The server's own PartnerValues(), read in a fresh process: the contacts and the productions, each printed on a line of its own. */
export async function partnerMember(): Promise<PartnerMember> {
  const lines = await irisScript(
    [
      'Set v=##class(OcuTalon.Core.SettingsOps).PartnerValues()',
      'Write !,"CHK|np|",v.productions.%Size()',
      'For i=0:1:v.productions.%Size()-1 { Write !,"CHK|p"_i_"|",v.productions.%Get(i).%ToJSON() }',
      'Write !,"CHK|nc|",v.contacts.%Size()',
      'For i=0:1:v.contacts.%Size()-1 { Write !,"CHK|c"_i_"|",v.contacts.%Get(i).%ToJSON() }',
    ].join('\n'),
  );
  const count = (name: string): number => Number(chk(lines, name) ?? '-1');
  expect(count('np'), 'PartnerValues() answered in a fresh process').toBeGreaterThanOrEqual(0);
  const read = <T>(prefix: string, size: number): T[] => Array.from({ length: size }, (_, i) => JSON.parse(chk(lines, `${prefix}${i}`) ?? 'null') as T);
  return { productions: read<PartnerProduction>('p', count('np')), contacts: read<PartnerStored>('c', count('nc')) };
}

/** The first production that the instance offers (the Orders production on a stack with the demo), which a case makes its contact concern. */
export async function aProduction(): Promise<PartnerProduction> {
  const member = await partnerMember();
  expect(member.productions.length, 'the instance offers at least one production').toBeGreaterThan(0);
  return member.productions[0];
}

/** The contacts that ForProduction(namespace, production) gives in a fresh process, as {id, name, address}. */
export async function forProduction(namespace: string, production: string): Promise<Array<{ id: number; name: string; address: string }>> {
  const lines = await irisScript(
    [
      `Set f=##class(OcuTalon.Data.PartnerContact).ForProduction(${quoted(namespace)},${quoted(production)})`,
      'Write !,"CHK|n|",f.%Size()',
      'For i=0:1:f.%Size()-1 { Write !,"CHK|f"_i_"|",f.%Get(i).%ToJSON() }',
    ].join('\n'),
  );
  const size = Number(chk(lines, 'n') ?? '-1');
  expect(size, 'ForProduction answered in a fresh process').toBeGreaterThanOrEqual(0);
  return Array.from({ length: size }, (_, i) => JSON.parse(chk(lines, `f${i}`) ?? 'null') as { id: number; name: string; address: string });
}

/** Deletes every contact whose name begins `zz-`: the contacts that the cases made. */
export async function removeZzContacts(): Promise<void> {
  await irisScript(
    [
      'Set id=""',
      'For  Set id=$Order(^OcuTalonP.PartnerContactD(id)) Quit:id=""  Set row=##class(OcuTalon.Data.PartnerContact).%OpenId(id) If $IsObject(row),$Extract(row.Name,1,3)="zz-" Do ##class(OcuTalon.Data.PartnerContact).%DeleteId(id)',
      'Write !,"CHK|cleaned|1"',
    ].join('\n'),
  );
}

/** The audit clock now, in the form that auditSince takes. */
export async function auditMark(): Promise<string> {
  const mark = chk(await irisScript('Write !,"CHK|now|",##class(OcuTalon.Test.Bridge.AuditLog).Now()'), 'now');
  expect(mark, 'the audit clock').toBeTruthy();
  return mark as string;
}

/** The Settings audit entries of the contacts (partnerContact.<Ref>) written at or after the mark, oldest first: waits up to `seconds` for `count` of them. */
export async function auditSince(mark: string, count: number, seconds = 60): Promise<PartnerAudit[]> {
  const lines = await irisScript(
    [
      `Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(${quoted(mark)},"OcuTalon","Settings","","partnerContact.","",${count},${seconds})`,
      'Write !,"CHK|n|",e.%Size()',
      'For i=0:1:e.%Size()-1 { Set d=e.%Get(i).data Write !,"CHK|e"_i_"|",d.setting_"|"_d.from_"|"_d.to_"|"_d.irisUser_"|"_d.sessionRef_"|"_d.channel }',
    ].join('\n'),
  );
  const found = Number(chk(lines, 'n') ?? '-1');
  expect(found, 'the audit entries could be read').toBeGreaterThanOrEqual(0);
  const entries: PartnerAudit[] = [];
  for (let i = 0; i < found; i += 1) {
    const [setting = '', from = '', to = '', irisUser = '', sessionRef = '', channel = ''] = (chk(lines, `e${i}`) ?? '').split('|');
    entries.push({ setting, from, to, irisUser, sessionRef, channel });
  }
  return entries;
}
