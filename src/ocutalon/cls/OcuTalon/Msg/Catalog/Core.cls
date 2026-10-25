/// The catalog of the texts that OcuTalon sends or shows and that Lane B produces (AD-29, AD-32): the pairing replies and
/// press alerts of Telegram, the answered statuses, the conversation and allowance texts, the fallback reasons, tell now and
/// reminders, the status banners and their actions, the sign-in page's and the splash screen's texts and the audit line. The XData block Entries holds
/// one JSON object whose names are the catalog keys, <prefix>.<name>, and whose values are
///   {"text": fixed text with {camelCase} placeholders, "web": the page wording when it differs from text,
///    "slots": {"<placeholder>": "<type>"}, "source": the UX section, "gap": the form the UX does not fix,
///    "one": {"slot": a count slot, "text": the form for that slot being 1, "web": the page wording of the form}}.
/// The form of "one" holds every declared slot but its own, and OcuTalon.Msg.Catalog uses it when that slot is 1.
/// The slot types are time, count, noun, text, sentence, channel, fallbackReason, groups and cost. OcuTalon.Msg.Catalog
/// reads the block and is the only renderer. Each key prefix lives in one catalog class; a Lane B story adds its keys here.
Class OcuTalon.Msg.Catalog.Core
{

XData Entries [ MimeType = application/json ]
{
{
 "pairing.paired": {
  "text": "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair).",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / Valid code"
 },
 "pairing.badCode": {
  "text": "That code didn't work. Open the OcuTalon page and scan the QR code there for a new one.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / Unknown, expired, or used code"
 },
 "pairing.start": {
  "text": "This is OcuTalon, an assistant that runs inside InterSystems IRIS. To use it here, open your OcuTalon page and scan the QR code there; that pairs this chat with your session.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / Bare /start, or /help"
 },
 "pairing.notPaired": {
  "text": "This chat isn't paired yet. Open your OcuTalon page and scan the QR code there.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / Any other message from an unpaired chat"
 },
 "pairing.stopped": {
  "text": "Unpaired. This chat won't get OcuTalon messages anymore. Scan the QR code on the OcuTalon page to pair again.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / /stop"
 },
 "pairing.unpairedFromPage": {
  "text": "Unpaired from the OcuTalon page. Scan the QR code there to pair again.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / Unpaired from the page"
 },
 "pairing.otherChatPaired": {
  "text": "Another Telegram chat was paired with this OcuTalon session, so this chat is no longer paired.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Pairing (Telegram) / The session paired a different chat"
 },
 "press.approved": {
  "text": "Approved. Repairing and resending {count} {itemNoun}.",
  "slots": {
   "count": "count",
   "itemNoun": "noun"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request / Approve pressed"
 },
 "press.rejected": {
  "text": "Rejected. Nothing was changed.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request / Reject pressed"
 },
 "press.notPairedChat": {
  "text": "Only the paired chat can answer this request.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request / Press from a chat that is not the paired chat"
 },
 "press.unavailable": {
  "text": "That request is no longer available.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request / Press on an unknown request"
 },
 "press.rejectedFollowUp": {
  "text": "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request / Rejected follow-up"
 },
 "answered.approved": {
  "text": "Approved from {channel} at {time}.",
  "web": "Approved from {channel} at {time}",
  "slots": {
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Approved"
 },
 "answered.approvedBy": {
  "text": "Approved by {user} from {channel} at {time}.",
  "web": "Approved by {user} from {channel} at {time}",
  "slots": {
   "user": "text",
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Approved, with Who answered (Formats)"
 },
 "answered.rejected": {
  "text": "Rejected from {channel} at {time}. Nothing was changed.",
  "slots": {
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Rejected"
 },
 "answered.rejectedBy": {
  "text": "Rejected by {user} from {channel} at {time}. Nothing was changed.",
  "slots": {
   "user": "text",
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Rejected, with Who answered (Formats)"
 },
 "answered.expired": {
  "text": "Expired at {time}. Nothing was changed.",
  "slots": {
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Expired"
 },
 "answered.alreadyApproved": {
  "text": "Already answered: approved from {channel} at {time}.",
  "slots": {
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Already answered"
 },
 "answered.alreadyRejected": {
  "text": "Already answered: rejected from {channel} at {time}.",
  "slots": {
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / Already answered, rejected"
 },
 "answered.alreadyApprovedBy": {
  "text": "Already answered: approved by {user} from {channel} at {time}.",
  "slots": {
   "user": "text",
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / Already answered, with a user"
 },
 "answered.alreadyRejectedBy": {
  "text": "Already answered: rejected by {user} from {channel} at {time}.",
  "slots": {
   "user": "text",
   "channel": "channel",
   "time": "time"
  },
  "source": "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / Already answered, with a user"
 },
 "conversation.turnFallback": {
  "text": "I couldn't answer that: {fallbackReason}. Nothing was changed.",
  "slots": {
   "fallbackReason": "fallbackReason"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Chat turn fallback"
 },
 "conversation.dailyCap": {
  "text": "The online demo has used today's model allowance. Decisions use fixed rules until {time}. You can install OcuTalon yourself to keep going: {readmeLink}",
  "slots": {
   "time": "time",
   "readmeLink": "text"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Demo allowance used up: daily cap"
 },
 "conversation.sessionAllowance": {
  "text": "You've used this session's {limit} messages for the hour. You can send more at {time}, or install OcuTalon yourself to keep going: {readmeLink}",
  "slots": {
   "limit": "count",
   "time": "time",
   "readmeLink": "text"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Demo allowance used up: session"
 },
 "fallbackReason.timeout": {
  "text": "the model didn't answer within 60 seconds",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / timeout"
 },
 "fallbackReason.empty": {
  "text": "the model's reply was empty",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / empty"
 },
 "fallbackReason.cutOff": {
  "text": "the model's reply was cut off",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / cutOff"
 },
 "fallbackReason.refusal": {
  "text": "the model declined to answer",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / refusal"
 },
 "fallbackReason.error": {
  "text": "the model returned an error",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / error"
 },
 "fallbackReason.rateLimited": {
  "text": "the model was busy and retries ran out",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / rateLimited"
 },
 "fallbackReason.budget": {
  "text": "this would have gone over the token budget",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / budget"
 },
 "fallbackReason.tooLarge": {
  "text": "this request would have been too large to send",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / tooLarge"
 },
 "fallbackReason.dailyCap": {
  "text": "today's cost limit has been reached",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / dailyCap"
 },
 "fallbackReason.noKey": {
  "text": "no model key is set",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / noKey"
 },
 "fallbackReason.generic": {
  "text": "the model's reply couldn't be used",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Fallback reasons / generic"
 },
 "notice.tellNow": {
  "text": "{whatHappened}\nWhy now: {reason}",
  "slots": {
   "whatHappened": "text",
   "reason": "sentence"
  },
  "source": "EXPERIENCE Message Catalog / Notifications and reminders / Tell now"
 },
 "notice.tellNowFallback": {
  "text": "{whatHappened}\nWhy now: {reason}",
  "slots": {
   "whatHappened": "text",
   "reason": "fallbackReason"
  },
  "source": "EXPERIENCE Message Catalog / Notifications and reminders / Tell now; Component Patterns / Fallback flag"
 },
 "reminder.due": {
  "text": "Reminder: {text}.",
  "slots": {
   "text": "sentence"
  },
  "source": "EXPERIENCE Message Catalog / Notifications and reminders / Reminder"
 },
 "reminder.late": {
  "text": "Reminder (late; it was due at {time}): {text}.",
  "slots": {
   "time": "time",
   "text": "sentence"
  },
  "source": "EXPERIENCE Message Catalog / Notifications and reminders / Reminder, late"
 },
 "banner.allowance": {
  "text": "You've used this session's {limit} messages for the hour (messages you send in the chat or Telegram). You can send more at {time}.",
  "slots": {
   "limit": "count",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Allowance used up: session"
 },
 "banner.dailyCap": {
  "text": "The online demo has used today's model allowance. Decisions use fixed rules until {time}.",
  "slots": {
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Allowance used up: daily cap"
 },
 "banner.unreachable": {
  "text": "Can't reach OcuTalon. Retrying every 10 seconds.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Unreachable"
 },
 "banner.noModelKey": {
  "text": "OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / No model key (step 1)"
 },
 "banner.costCap": {
  "text": "OcuTalon has reached today's cost limit of {cap}. Decisions use fixed rules until {time}.",
  "slots": {
   "cap": "cost",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Daily cost cap reached"
 },
 "banner.heartbeatStalled": {
  "text": "Background checks have paused: the heartbeat last ran at {time}. Watches and reminders may be late until it recovers.",
  "slots": {
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Heartbeat stalled"
 },
 "banner.telegramPaused": {
  "text": "Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at {time}. Each OcuTalon needs its own bot.",
  "slots": {
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Bot in use"
 },
 "banner.resetSoon": {
  "text": "The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Reset soon"
 },
 "banner.reconnecting": {
  "text": "Reconnecting\u2026 New messages may be delayed.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Reconnecting"
 },
 "bannerAction.installYourself": {
  "text": "Install it yourself",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Action of the allowance banners"
 },
 "bannerAction.howToSetKey": {
  "text": "How to set a key",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Action of the no model key banner"
 },
 "bannerAction.budgets": {
  "text": "Budgets",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Action of the daily cost cap banner"
 },
 "bannerAction.setUpBot": {
  "text": "Set up a bot",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Status banners (web) / Action of the bot in use banner"
 },
 "signIn.title": {
  "text": "Sign in \u00B7 OcuTalon",
  "slots": {},
  "source": "EXPERIENCE Information Architecture / Titles and headings"
 },
 "signIn.heading": {
  "text": "Sign in to OcuTalon",
  "slots": {},
  "source": "EXPERIENCE Pages / The sign-in page"
 },
 "signIn.submit": {
  "text": "Sign in",
  "slots": {},
  "source": "EXPERIENCE Pages / The sign-in page"
 },
 "signIn.help": {
  "text": "Use the IRIS account your install created; the README lists it.",
  "slots": {},
  "source": "EXPERIENCE Pages / The sign-in page"
 },
 "signIn.errorCredentials": {
  "text": "That user name and password didn't work.",
  "slots": {},
  "source": "EXPERIENCE State Patterns / Sign-in errors"
 },
 "signIn.errorNoRole": {
  "text": "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.",
  "slots": {},
  "source": "EXPERIENCE State Patterns / Sign-in errors"
 },
 "signIn.logoAlt": {
  "text": "OcuTalon",
  "slots": {},
  "source": "EXPERIENCE Component Patterns / Sign-in / Full logo"
 },
 "signIn.signedOut": {
  "text": "You were signed out. Sign in again to continue.",
  "slots": {},
  "source": "EXPERIENCE State Patterns / Session ended (local)"
 },
 "signIn.userLabel": {
  "text": "User name",
  "slots": {},
  "source": "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / Sign-in page labels"
 },
 "signIn.passwordLabel": {
  "text": "Password",
  "slots": {},
  "source": "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / Sign-in page labels"
 },
 "signIn.showPassword": {
  "text": "Show password",
  "slots": {},
  "source": "EXPERIENCE Incidents and Approvals / Forms for a count of one, the late press, and the sign-in labels / Sign-in page labels"
 },
 "splash.title": {
  "text": "Try OcuTalon",
  "slots": {},
  "source": "EXPERIENCE Information Architecture / Titles and headings"
 },
 "splash.heading": {
  "text": "Try OcuTalon in two minutes",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo)"
 },
 "splash.subheading": {
  "text": "Break the feed, and approve the fix from your phone.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo)"
 },
 "splash.description": {
  "text": "OcuTalon is an assistant that lives inside InterSystems IRIS Interoperability. When a feed breaks, it reads the failed messages and the trace, names the cause in plain English, and proposes a fix that waits for your approval. For everything that arrives, an AI Hub agent makes one attention decision (ignore it, save it for your daily digest, tell you now, or act), and every decision, with its reasons and cost, is a production message you can open in Visual Trace. No API key needed.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / What it is"
 },
 "splash.signInHeading": {
  "text": "Sign in to the demo",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Sign in to the demo"
 },
 "splash.sessionNote": {
  "text": "Your session is yours alone and lasts until the next reset. Signing in again from this browser picks it up.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Sign in to the demo"
 },
 "splash.warning": {
  "text": "Other visitors can see messages in Visual Trace, so don't type personal information.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Sign in to the demo"
 },
 "splash.submit": {
  "text": "Sign in and start",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Sign in to the demo"
 },
 "splash.copyUserName": {
  "text": "Copy user name",
  "slots": {},
  "source": "EXPERIENCE Component Patterns / Sign-in / Credential card"
 },
 "splash.copyPassword": {
  "text": "Copy password",
  "slots": {},
  "source": "EXPERIENCE Component Patterns / Sign-in / Credential card"
 },
 "splash.copied": {
  "text": "Copied",
  "slots": {},
  "source": "EXPERIENCE Component Patterns / Sign-in / Credential card"
 },
 "splash.copyFailed": {
  "text": "Couldn't copy. Select the text and copy it yourself.",
  "slots": {},
  "source": "EXPERIENCE Component Patterns / Sign-in / Credential card"
 },
 "splash.beforeHeading": {
  "text": "Before you start",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"
 },
 "splash.resetLine": {
  "text": "The demo resets every {interval}. Next reset: {time} ({countdown}).",
  "slots": {"interval": "text", "time": "text", "countdown": "text"},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"
 },
 "splash.ownLine": {
  "text": "Your chat, phone, mailbox and orders are yours alone.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"
 },
 "splash.telegramLine": {
  "text": "Have Telegram? You can scan a QR code inside to get the notices on your own phone.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"
 },
 "splash.limitLine": {
  "text": "Each session can send {limit} messages an hour in the chat or Telegram.",
  "slots": {"limit": "count"},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"
 },
 "splash.shellLine": {
  "text": "OcuTalon can't run shell commands, and every action it takes is recorded in the IRIS audit log.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / Before you start"
 },
 "splash.visualTrace": {
  "text": "Read-only Visual Trace account, for opening Visual Trace in the portal yourself (trace links on the page are already signed in). See each decision with its cost, and every step.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / The Visual Trace card"
 },
 "splash.copyTraceUserName": {
  "text": "Copy Visual Trace user name",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / The Visual Trace card"
 },
 "splash.copyTracePassword": {
  "text": "Copy Visual Trace password",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / The Visual Trace card"
 },
 "splash.footerNote": {
  "text": "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / The footer"
 },
 "splash.install": {
  "text": "Install it yourself (README)",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / The footer"
 },
 "splash.newTab": {
  "text": "(opens in a new tab)",
  "slots": {},
  "source": "EXPERIENCE Pages / The splash screen (online demo) / The footer"
 },
 "audit.recorded": {
  "text": "Recorded in the IRIS audit log.",
  "slots": {},
  "source": "EXPERIENCE Incidents and Approvals / Results"
 }
}
}

}
