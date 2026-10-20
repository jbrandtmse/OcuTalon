/// The catalog of the texts that OcuTalon sends or shows and that Lane A produces (AD-29, AD-32): the production state
/// changes, the watch tool's answers, the agent's no-commands answer, the checks' reserved sentences (AD-28), the incident
/// notices and the results of a resend. Lane A adds its keys here from Epic 0 on; Epic 0 created every release-1 and 0.1.1 key.
/// The XData block Entries has the shape that OcuTalon.Msg.Catalog.Core describes, and OcuTalon.Msg.Catalog is the only
/// renderer. Each key prefix lives in one catalog class.
Class OcuTalon.Msg.Catalog.Watch
{

XData Entries [ MimeType = application/json ]
{
{
 "watch.productionStopped": {
  "text": "The {production} production stopped at {time}.\nWhy now: you asked me to watch the {production} production.",
  "slots": {
   "production": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Notifications and reminders / Production state change"
 },
 "watch.itemDisabled": {
  "text": "The {itemName} in the {production} production was disabled at {time}.\nWhy now: you asked me to watch the {production} production.",
  "slots": {
   "itemName": "text",
   "production": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Notifications and reminders / Production state change"
 },
 "watch.unknownProduction": {
  "text": "I can't find a production called '{name}'. I can see: {list}. Which one did you mean?",
  "slots": {
   "name": "text",
   "list": "text"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Unknown production name"
 },
 "watch.onlyOrders": {
  "text": "On the online demo I can only watch the Orders production. Install OcuTalon to watch your own productions: {readmeLink}",
  "slots": {
   "readmeLink": "text"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Asked to watch another production on the online demo"
 },
 "agent.noCommands": {
  "text": "I can't run commands. I can check productions, read failed messages and propose fixes that wait for your approval.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Asked to run a command"
 },
 "checks.notEverything": {
  "text": "Not everything: {whatFailed}.",
  "slots": {
   "whatFailed": "text"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Asked whether everything is fine, with a check failing"
 },
 "checks.notEverythingRestPassed": {
  "text": "Not everything: {whatFailed}. Everything else I checked passed.",
  "slots": {
   "whatFailed": "text"
  },
  "source": "EXPERIENCE Message Catalog / Conversation / Asked whether everything is fine, with a check failing and others passed"
 },
 "checks.everythingElsePassed": {
  "text": "Everything else I checked passed.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Asked whether everything is fine, with checks that could not run"
 },
 "checks.allPassed": {
  "text": "Everything I checked passed.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Asked whether everything is fine, with every check passing"
 },
 "checks.nothingWatched": {
  "text": "I'm not watching any productions yet, so I can't say. Ask me to watch one.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Conversation / Asked whether everything is fine, with nothing watched"
 },
 "incident.withFix": {
  "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "cause": "sentence",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request",
  "gap": "The UX fixes only the plural 'repaired copies'; the text renders it for a resend count of 1 too."
 },
 "incident.laterRequest": {
  "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count"
  },
  "source": "EXPERIENCE Message Catalog / Later approval request in the same incident",
  "gap": "The UX fixes only the plural 'repaired copies'; the text renders it for a resend count of 1 too."
 },
 "incident.fallback": {
  "text": "{count} {itemNoun} failed since {time}. I couldn't work out the cause ({fallbackReason}), so I'm not proposing a fix. Nothing was changed.\n\nFailures:\n{groups}\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "fallbackReason": "fallbackReason",
   "groups": "groups"
  },
  "source": "EXPERIENCE Message Catalog / Fallback incident notice"
 },
 "incident.noFix": {
  "text": "{count} {itemNoun} failed since {time}. {cause}. None of my fixes applies to this, so I'm not proposing one. Nothing was changed.\n\nFailures:\n{groups}\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "cause": "sentence",
   "groups": "groups"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice without a fix"
 },
 "incident.noFixUnknown": {
  "text": "{count} {itemNoun} failed since {time}. I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.\n\nFailures:\n{groups}\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "groups": "groups"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice without a fix / Unknown cause"
 },
 "result.allThrough": {
  "text": "All {count} {itemNoun} went through.",
  "slots": {
   "count": "count",
   "itemNoun": "noun"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / All went through",
  "gap": "The UX fixes no singular form for one item; the text renders 'All 1 order went through.'"
 },
 "result.failedAgain": {
  "text": "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}). I won't retry them without a new approval.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "completed": "count",
   "failedAgain": "count",
   "failReason": "text"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Some failed again",
  "gap": "The UX fixes only the plural wording for several messages ('them', 'they need'); the text renders it for one message too."
 },
 "result.skipped": {
  "text": "{completed} of {count} {itemNoun} went through. {skipped} had changed since the dry run, so I skipped them; they need a new approval.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "completed": "count",
   "skipped": "count"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Some skipped",
  "gap": "The UX fixes only the plural wording for several messages ('them', 'they need'); the text renders it for one message too."
 },
 "result.failedAndSkipped": {
  "text": "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}), and {skipped} had changed since the dry run, so I skipped them. I won't retry any of them without a new approval.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "completed": "count",
   "failedAgain": "count",
   "failReason": "text",
   "skipped": "count"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Some failed again and some skipped",
  "gap": "The UX fixes only the plural wording for several messages ('them', 'they need'); the text renders it for one message too."
 },
 "result.stillResending": {
  "text": "Still resending: {completed} of {count} {itemNoun} have gone through so far. I'll tell you when it's done.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "completed": "count"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Still running after the wait",
  "gap": "The UX fixes only the plural verb; the text renders 'have gone through' for one message too."
 },
 "result.interrupted": {
  "text": "The resend stopped when OcuTalon restarted: {completed} of {count} {itemNoun} went through. The other {remaining} need a new approval.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "completed": "count",
   "remaining": "count"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Cut off by a restart",
  "gap": "The UX fixes only the plural verb; the text renders 'need' for one message too."
 },
 "result.couldNotStart": {
  "text": "Nothing was resent: {reason}. Nothing was changed.",
  "slots": {
   "reason": "text"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Couldn't start"
 }
}
}

}
