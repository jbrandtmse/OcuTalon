/// The catalog of the texts that OcuTalon sends or shows and that Lane A produces (AD-29, AD-32): the production state
/// changes, the watch tool's answers, the agent's no-commands answer, the checks' reserved sentences (AD-28), the incident
/// notices and the results of a resend. Epic 0 created every release-1 and 0.1.1 key; after Epic 0, Lane A adds its keys here.
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
  "source": "EXPERIENCE Voice and Tone / Reserved sentences / after a check that failed or was not checked, for the rest"
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
  "one": {
   "slot": "resendCount",
   "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
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
  "one": {
   "slot": "resendCount",
   "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
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
  "one": {
   "slot": "count",
   "text": "The {itemNoun} went through."
  }
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
  "one": {
   "slot": "failedAgain",
   "text": "{completed} of {count} {itemNoun} went through. 1 failed again ({failReason}). I won't retry it without a new approval."
  }
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
  "one": {
   "slot": "skipped",
   "text": "{completed} of {count} {itemNoun} went through. 1 had changed since the dry run, so I skipped it; it needs a new approval."
  }
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
  "one": {
   "slot": "skipped",
   "text": "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}), and 1 had changed since the dry run, so I skipped it. I won't retry any of them without a new approval."
  }
 },
 "result.stillResending": {
  "text": "Still resending: {completed} of {count} {itemNoun} have gone through so far. I'll tell you when it's done.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "completed": "count"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Still running after the wait",
  "one": {
   "slot": "completed",
   "text": "Still resending: 1 of {count} {itemNoun} has gone through so far. I'll tell you when it's done."
  }
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
  "one": {
   "slot": "remaining",
   "text": "The resend stopped when OcuTalon restarted: {completed} of {count} {itemNoun} went through. The other one needs a new approval."
  }
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
