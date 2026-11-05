import { TELEGRAM_FIXTURE_MS, asCleanup } from '../e2e/support/bounds';
import { chk, irisScript, quoted } from '../e2e/support/iris';

/**
 * What the online units' Telegram cases share (Story 31.3: leave.spec.ts L6, messages.spec.ts A5 and daily-cap.spec.ts AT): a paired chat of
 * a demo session, driven through the CI mock bot and never the public Telegram API (Rule 21). It calls the IRIS fixture of the demo-path
 * run, OcuTalon.Test.Channel.TelegramPageFixture, from IRIS scripts, and needs a throwaway stack of the CI override: the Bot API base is the
 * mock's and the bot token a dummy, which the fixture's Start checks. Every method returns "" or a reason that holds no token.
 * A case calls startTelegram before it pairs a chat, and finishTelegram in `finally`, which puts back the items, the marks and the mock.
 * finishTelegram and unpairChat run as clean-ups (bounds.ts asCleanup): they may use the test's clean-up reserve.
 */

/** The fixture class of the IRIS side. */
const FIXTURE = '##class(OcuTalon.Test.Channel.TelegramPageFixture)';

/** The chat ids of the fixture are 11 digits that start with 840177341: Start and Finish clean the rows of such chats. */
export const CHAT_A = '84017734151';

/** A chat id as an ObjectScript number, as telegram-approval.spec.ts passes it (the fixture's chat ids are digits only). */
function id(chatId: string): string {
  if (!/^\d{1,15}$/.test(chatId)) throw new Error('a fixture chat id is digits');
  return chatId;
}

/** The longest the mock may take to show what a case waits for, in ms. */
export const MOCK_MS = 90_000;

/**
 * Calls one method of the fixture and returns its reason ("" when it worked) with the values of its output variables. The script's first
 * line names the method, so that a call stopped at its bound names it (irisScript's message quotes the first line).
 */
async function fixture(call: string, outputs: string[] = []): Promise<{ reason: string; values: Record<string, string> }> {
  const lines = await irisScript(
    [
      `Set call="TelegramPageFixture.${call.slice(0, call.indexOf('('))}"`,
      ['Set r=""', ...outputs.map((name) => `${name}=""`)].join(','),
      `Try { Set r=${FIXTURE}.${call} } Catch ex { Set r="the call threw "_ex.Name }`,
      'Write !,"CHK|reason|",$Translate(r,$Char(13,10),"  ")',
      ...outputs.map((name) => `Write !,"CHK|${name}|",${name}`),
    ].join('\n'),
    TELEGRAM_FIXTURE_MS,
  );
  const reason = chk(lines, 'reason');
  if (reason === undefined) return { reason: 'the IRIS script printed no answer', values: {} };
  return { reason, values: Object.fromEntries(outputs.map((name) => [name, chk(lines, name) ?? ''])) };
}

/**
 * Starts TelegramOut and TelegramIn against the mock, and returns what finishTelegram needs. When the start fails, it first puts back what
 * the partial start changed, then throws the fixture's reason.
 */
export async function startTelegram(): Promise<string> {
  const started = await fixture('Start(.saved, "", 1)', ['saved']);
  const saved = started.values['saved'] ?? '';
  if (started.reason !== '') {
    let undone = '';
    try {
      await finishTelegram(saved);
    } catch (error) {
      undone = ` (and ${(error as Error).message})`;
    }
    throw new Error(`TelegramIn and TelegramOut did not start against the mock: ${started.reason}${undone}`);
  }
  return saved;
}

/** Puts back what startTelegram changed. Safe with a saved of "" (nothing to put back); throws the fixture's reason when something was not put back. */
export async function finishTelegram(saved: string): Promise<void> {
  const finished = await asCleanup(() => fixture(`Finish(${quoted(saved)})`));
  if (finished.reason !== '') throw new Error(`the Telegram fixture did not put everything back: ${finished.reason}`);
}

/**
 * Pairs the chat with the session by a fixture Pairing row (OcuTalon.Test.Data.Fixture.Pairing) whose chat id is the given one, and returns
 * the row's Ref. unpairChat deletes it; finishTelegram deletes it too.
 */
export async function pairChat(sessionRef: string, chatId: string, name = 'Zz chat'): Promise<string> {
  const lines = await irisScript(
    [
      `Set ref=##class(OcuTalon.Test.Data.Fixture).Pairing(${quoted(sessionRef)},${quoted(name)})`,
      'Set row=##class(OcuTalon.Data.Pairing).RefIndexOpen(ref)',
      `Set row.ChatId=${quoted(id(chatId))}`,
      'Set sc=row.%Save()',
      'Write !,"CHK|pairing|",$Select($SYSTEM.Status.IsOK(sc):ref,1:"")',
    ].join('\n'),
  );
  const ref = chk(lines, 'pairing') ?? '';
  if (ref === '') throw new Error(`the chat could not be paired (${lines.join(' ')})`);
  return ref;
}

/** Deletes the fixture Pairing row of a Ref. */
export async function unpairChat(pairingRef: string): Promise<void> {
  await asCleanup(() => irisScript([`Do ##class(OcuTalon.Test.Data.Fixture).Clean(${quoted(pairingRef)})`, 'Write !,"CHK|cleaned|1"'].join('\n')));
}

/** Posts one private text message from the chat to the mock, once a long poll is open. Throws the fixture's reason when it was not queued. */
export async function sendFromChat(chatId: string, text: string): Promise<void> {
  const sent = await fixture(`Send(${id(chatId)}, "", ${quoted(text)}, .queuedAt)`, ['queuedAt']);
  if (sent.reason !== '') throw new Error(`the chat's message was not queued: ${sent.reason}`);
}

/** Posts the press of the button with this callback data from the chat, once a long poll is open. Throws the fixture's reason when it was not queued. */
export async function pressFromChat(chatId: string, data: string): Promise<void> {
  const pressed = await fixture(`Press(${id(chatId)}, "", ${quoted(data)}, .queuedAt)`, ['queuedAt']);
  if (pressed.reason !== '') throw new Error(`the chat's press was not queued: ${pressed.reason}`);
}

/** Reads one output of a fixture reader as JSON. Throws the fixture's reason when it could not be read. */
async function read<T>(call: string, output: string): Promise<T> {
  const result = await fixture(call, [output]);
  if (result.reason !== '') throw new Error(`the Telegram fixture could not be read: ${result.reason}`);
  return JSON.parse(result.values[output] || '[]') as T;
}

/** The text of every sendMessage to the chat, in order. */
export async function repliesOf(chatId: string): Promise<string[]> {
  return read<string[]>(`Replies(${id(chatId)}, .texts)`, 'texts');
}

/** The callback data of the buttons of the newest keyboard that the chat got. */
export async function buttonsOf(chatId: string): Promise<string[]> {
  return read<string[]>(`Buttons(${id(chatId)}, .data)`, 'data');
}

/** The answer of every press (answerCallbackQuery), in order. */
export async function pressAnswers(): Promise<Array<{ text: string; show_alert: number }>> {
  return read<Array<{ text: string; show_alert: number }>>('PressAnswers(.answers)', 'answers');
}

/** The State and Channel of the session's Turn rows that carry the text, as `state:channel`, oldest first. */
export async function chatTurnsOf(sessionRef: string, text: string): Promise<string[]> {
  const lines = await irisScript(
    [
      `Set t=##class(%SQL.Statement).%ExecDirect(,"SELECT State, Channel FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND Text = ? ORDER BY ID",${quoted(sessionRef)},${quoted(text)})`,
      'While t.%Next() { Write !,"CHK|turn|",t.%Get("State"),":",t.%Get("Channel") }',
      'Write !,"CHK|done|1"',
    ].join('\n'),
  );
  if (chk(lines, 'done') !== '1') throw new Error(`the turns could not be read (${lines.join(' ')})`);
  return lines.filter((line) => line.startsWith('CHK|turn|')).map((line) => line.slice('CHK|turn|'.length));
}

/**
 * Sends the session a request notice for the approval, as the product's own notices go (a Notification of the kind approval through
 * Notify), so that its paired chat gets a message with the buttons approve:<Ref> and reject:<Ref>. Throws the reason when it was not sent.
 */
export async function sendApprovalNotice(sessionRef: string, approvalRef: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set row=##class(OcuTalon.Data.Session).RefIndexOpen(${quoted(sessionRef)})`,
      'Set case="OcuTalon.Test.Channel.LiveCase"',
      `Set notice=$ClassMethod(case,"Notification",${quoted(sessionRef)},"approval","notice.tellNow",{"whatHappened":"zz an approval waits","reason":"the case asks you to approve."},${quoted(approvalRef)})`,
      'Set sc=$ClassMethod(case,"SendToNotify",notice,row.TraceRef)',
      'Write !,"CHK|notice|",$Select($SYSTEM.Status.IsOK(sc):"ok",1:$Translate($SYSTEM.Status.GetErrorText(sc),$Char(13,10),"  "))',
    ].join('\n'),
  );
  if (chk(lines, 'notice') !== 'ok') throw new Error(`the approval notice was not sent (${lines.join(' ')})`);
}
