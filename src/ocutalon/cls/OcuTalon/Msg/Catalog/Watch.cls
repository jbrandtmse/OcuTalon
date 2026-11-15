/// The catalog of the texts that OcuTalon sends or shows and that Lane A produces (AD-29, AD-32): the production state
/// changes, the watch tool's answers, the agent's no-commands answer, the checks' reserved sentences (AD-28), the incident
/// notices and the results of a resend. Epic 0 created every release-1 and 0.1.1 key; after Epic 0, Lane A adds its keys here.
/// The digest texts (Story 33.1; EXPERIENCE, Daily digest) are the keys under digest.: the three greetings, the vital signs, what was checked,
/// the nothing-watched sentence, the coverage lines (passed, failed and the six not-checked reasons), what needs the person, what was saved
/// for later, and the cost (digest.cost, whose slot is of the type dailyCost); digest.needsYouMore ends a needs-you list that is cut. button.gotIt and
/// handled.marked are the Telegram Got it button and the line that a handled message ends with (UX-DR143). The slot named itemNoun of digest.healthy is the
/// noun of the days, as the catalog test allows a noun under that name only.
/// The step 4 texts (Story 35.1; EXPERIENCE, MCP servers and tools (step 4)) are the five keys under mcp. and digest.notCheckedStopped, the coverage line of a
/// source that stopped polling; the story that produces each one sends it.
/// The files.* keys (Story 26.2; EXPERIENCE Step 6, Send a file) are the replies that TelegramIn sends a paired chat for a document or photo as pairing Notifications: files.tooLarge,
/// files.unreadable and files.offOnDemo (the texts of Core.Files that the web chat shows) and files.noReader (Core.Files TEXTNOREADER, while no reader is on).
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
 "incident.withFixEitherWay": {
  "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "cause": "sentence",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count",
   "reading": "text",
   "item": "text"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request; dry-run line: U-249 (owner delegate, 2026-11-03)",
  "one": {
   "slot": "resendCount",
   "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
 },
 "incident.laterRequestEitherWay": {
  "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count",
   "reading": "text",
   "item": "text"
  },
  "source": "EXPERIENCE Message Catalog / Later approval request in the same incident; dry-run line: U-249 (owner delegate, 2026-11-03)",
  "one": {
   "slot": "resendCount",
   "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
 },
 "incident.withFixChecked": {
  "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "cause": "sentence",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count",
   "goodChecked": "count",
   "goodChanged": "count",
   "goodNoun": "text"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request; good-message line: Story 7.9 (owner decision 2026-11-06)",
  "one": {
   "slot": "resendCount",
   "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
 },
 "incident.laterRequestChecked": {
  "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count",
   "goodChecked": "count",
   "goodChanged": "count",
   "goodNoun": "text"
  },
  "source": "EXPERIENCE Message Catalog / Later approval request in the same incident; good-message line: Story 7.9 (owner decision 2026-11-06)",
  "one": {
   "slot": "resendCount",
   "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
 },
 "incident.withFixEitherWayChecked": {
  "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "cause": "sentence",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count",
   "reading": "text",
   "item": "text",
   "goodChecked": "count",
   "goodChanged": "count",
   "goodNoun": "text"
  },
  "source": "EXPERIENCE Message Catalog / Incident notice with approval request; dry-run line: U-249 (owner delegate, 2026-11-03); good-message line: Story 7.9 (owner decision 2026-11-06)",
  "one": {
   "slot": "resendCount",
   "text": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
 },
 "incident.laterRequestEitherWayChecked": {
  "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived. I'll resend {resendCount} repaired copies; the originals stay unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "fixSummary": "sentence",
   "field": "text",
   "before": "text",
   "after": "text",
   "resendCount": "count",
   "reading": "text",
   "item": "text",
   "goodChecked": "count",
   "goodChanged": "count",
   "goodNoun": "text"
  },
  "source": "EXPERIENCE Message Catalog / Later approval request in the same incident; dry-run line: U-249 (owner delegate, 2026-11-03); good-message line: Story 7.9 (owner decision 2026-11-06)",
  "one": {
   "slot": "resendCount",
   "text": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}.\n\nDry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived. I'll resend 1 repaired copy; the original stays unchanged. Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
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
 "result.stoppedPartway": {
  "text": "The resend stopped partway: I resent {resent} of the {count} {itemNoun} ({completed} went through), the next one couldn't be resent, and {notTried} more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "resent": "count",
   "completed": "count",
   "notTried": "count"
  },
  "source": "Story 30.5 (AD-16 as amended, U-182)",
  "one": {
   "slot": "notTried",
   "text": "The resend stopped partway: I resent {resent} of the {count} {itemNoun} ({completed} went through), the next one couldn't be resent, and 1 more wasn't tried. Nothing else was changed, and I won't resend the rest without a new approval."
  }
 },
 "result.couldNotStart": {
  "text": "Nothing was resent: {reason}. Nothing was changed.",
  "slots": {
   "reason": "text"
  },
  "source": "EXPERIENCE Incidents and Approvals / Results / Couldn't start"
 },
 "watch.time": {
  "text": "{time}",
  "slots": {
   "time": "time"
  },
  "source": "Story 30.5 (DW-519, DW-484): the catalog's time label alone, for a tool's answer to the model"
 },
 "button.approve": {
  "text": "Approve",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Telegram / word-labeled buttons"
 },
 "button.reject": {
  "text": "Reject",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Telegram / word-labeled buttons"
 },
 "button.gotIt": {
  "text": "Got it",
  "slots": {},
  "source": "UX-DR143"
 },
 "handled.marked": {
  "text": "Marked as handled at {time}",
  "slots": {
   "time": "time"
  },
  "source": "UX-DR143"
 },
 "digest.greetingMorning": {
  "text": "Good morning.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Daily digest / Greeting, morning"
 },
 "digest.greetingAfternoon": {
  "text": "Good afternoon.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Daily digest / Greeting, afternoon"
 },
 "digest.greetingEvening": {
  "text": "Good evening.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Daily digest / Greeting, evening"
 },
 "digest.healthy": {
  "text": "Your IRIS system is healthy: up {count} {itemNoun}, databases {databasesFull}% full, journal space fine, license use {licenseUse}%.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "databasesFull": "count",
   "licenseUse": "count"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Vital signs, all passed"
 },
 "digest.vitalsNotAll": {
  "text": "Not every vital sign passed: {whatFailed}.",
  "slots": {
   "whatFailed": "text"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Vital signs, not all passed"
 },
 "digest.checkedQuiet": {
  "text": "I checked {checked} (all running, no errors, no backlog).",
  "slots": {
   "checked": "text"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Checked, every production entry passed"
 },
 "digest.checked": {
  "text": "I checked {checked}.",
  "slots": {
   "checked": "text"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Checked, some entry failed or was not checked"
 },
 "digest.nothingWatched": {
  "text": "I'm not watching any productions yet, so this digest covers the vital signs only. Ask me to watch one.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Daily digest / Nothing watched"
 },
 "digest.passed": {
  "text": "Passed: {entry} (at {time}).",
  "slots": {
   "entry": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, passed"
 },
 "digest.failed": {
  "text": "Failed: {entry} ({finding}, at {time}).",
  "slots": {
   "entry": "text",
   "finding": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, failed"
 },
 "digest.notCheckedUnreachable": {
  "text": "Not checked: {entry} (unreachable since {time}).",
  "slots": {
   "entry": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, not checked: unreachable"
 },
 "digest.notCheckedError": {
  "text": "Not checked: {entry} (the check stopped with an error at {time}).",
  "slots": {
   "entry": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, not checked: error"
 },
 "digest.notCheckedTimeout": {
  "text": "Not checked: {entry} (the check timed out at {time}).",
  "slots": {
   "entry": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, not checked: timeout"
 },
 "digest.notCheckedMissed": {
  "text": "Not checked: {entry} (the check didn't run between {from} and {to}).",
  "slots": {
   "entry": "text",
   "from": "time",
   "to": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, not checked: missed"
 },
 "digest.notCheckedPaused": {
  "text": "Not checked: {entry} (background checks were paused between {from} and {to}).",
  "slots": {
   "entry": "text",
   "from": "time",
   "to": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, not checked: paused"
 },
 "digest.notCheckedStale": {
  "text": "Not checked: {entry} (its last check was at {time}, too long ago to count).",
  "slots": {
   "entry": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Coverage line, not checked: stale"
 },
 "digest.notCheckedSizeLimit": {
  "text": "Not checked: {entry} (OcuTalon can't read this database's size limit).",
  "slots": {
   "entry": "text"
  },
  "source": "Contest Planner ruling 2026-11-06 (owner delegation): Daily digest / Coverage line, not checked: capped database"
 },
 "digest.notCheckedStopped": {
  "text": "Not checked: {entry} (stopped polling at {time}: its tool is no longer Read-only).",
  "slots": {
   "entry": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / MCP servers and tools (step 4) / Digest, not checked: stopped"
 },
 "digest.needsYouOne": {
  "text": "One thing needs you: {what}.",
  "slots": {
   "what": "text"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Needs you, one thing"
 },
 "digest.needsYou": {
  "text": "{count} things need you: {what}.",
  "slots": {
   "count": "count",
   "what": "text"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Needs you, several things"
 },
 "digest.needsYouMore": {
  "text": "And {n} more on the OcuTalon page.",
  "slots": {
   "n": "count"
  },
  "source": "Contest Planner ruling 2026-11-06 (owner delegation): Daily digest / Needs you, overflow (Story 17.6, Q4 (b))"
 },
 "digest.saved": {
  "text": "Saved for later ({count}): {summary}",
  "slots": {
   "count": "count",
   "summary": "sentence"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Saved for later, with a summary"
 },
 "digest.savedNoSummary": {
  "text": "Saved for later ({count}): I couldn't summarize them this time ({fallbackReason}). The most recent are under Recent decisions on your OcuTalon page.",
  "slots": {
   "count": "count",
   "fallbackReason": "fallbackReason"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Saved for later, no summary"
 },
 "digest.savedNone": {
  "text": "Nothing was saved for later.",
  "slots": {},
  "source": "EXPERIENCE Message Catalog / Daily digest / Saved for later, nothing saved"
 },
 "digest.cost": {
  "text": "Yesterday's cost: {cost}.",
  "slots": {
   "cost": "dailyCost"
  },
  "source": "EXPERIENCE Message Catalog / Daily digest / Every digest (the cost)"
 },
 "summary.title": {
  "text": "Incident summary: {count} {itemNoun} failed in {production}.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "production": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.firstFailure": {
  "text": "{time}: first failure.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.noticed": {
  "text": "{time}: OcuTalon told you.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.requested": {
  "text": "{time}: OcuTalon asked for approval to repair and resend {count} {itemNoun}.",
  "slots": {
   "time": "time",
   "count": "count",
   "itemNoun": "noun"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text as ruled by the Contest Planner 2026-11-09"
 },
 "summary.approved": {
  "text": "{time}: approved from {channel}.",
  "slots": {
   "time": "time",
   "channel": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.approvedBy": {
  "text": "{time}: approved by {user} from {channel}.",
  "slots": {
   "time": "time",
   "user": "text",
   "channel": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.rejected": {
  "text": "{time}: rejected from {channel}.",
  "slots": {
   "time": "time",
   "channel": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.rejectedBy": {
  "text": "{time}: rejected by {user} from {channel}.",
  "slots": {
   "time": "time",
   "user": "text",
   "channel": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.expired": {
  "text": "{time}: the approval request expired.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.fixStarted": {
  "text": "{time}: the fix started.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.fixEnded": {
  "text": "{time}: the fix ended: {resent} resent, {completed} completed, {failedAgain} failed again, {skipped} skipped.",
  "slots": {
   "time": "time",
   "resent": "count",
   "completed": "count",
   "failedAgain": "count",
   "skipped": "count"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.fixInterrupted": {
  "text": "{time}: the fix was interrupted after resending {resent}.",
  "slots": {
   "time": "time",
   "resent": "count"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text as ruled by the Contest Planner 2026-11-09"
 },
 "summary.closedDismiss": {
  "text": "{time}: closed with Dismiss.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text as ruled by the Contest Planner 2026-11-09"
 },
 "summary.closedReplay": {
  "text": "{time}: closed when Break the feed was pressed again.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.closedQuiet": {
  "text": "{time}: closed after 15 minutes with no new failures.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text as ruled by the Contest Planner 2026-11-09"
 },
 "summary.cause": {
  "text": "Cause: {cause}",
  "slots": {
   "cause": "sentence"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.element": {
  "text": "Where it failed: {element}.",
  "slots": {
   "element": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text as ruled by the Contest Planner 2026-11-09"
 },
 "summary.noCause": {
  "text": "No cause was found: {fallbackReason}.",
  "slots": {
   "fallbackReason": "fallbackReason"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text as ruled by the Contest Planner 2026-11-09"
 },
 "summary.evidence": {
  "text": "Evidence: {evidence}.",
  "slots": {
   "evidence": "sentence"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09; full stop: Story 23.10, Contest Planner ruling 2026-11-11"
 },
 "summary.sampleError": {
  "text": "Sample error: {error}",
  "slots": {
   "error": "text"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.fix": {
  "text": "Fix: {fix}.",
  "slots": {
   "fix": "sentence"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09; full stop: Story 23.10, Contest Planner ruling 2026-11-11"
 },
 "summary.noFixRan": {
  "text": "No fix ran, so nothing was changed.",
  "slots": {},
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.groups": {
  "text": "Failure groups:\n{groups}",
  "slots": {
   "groups": "groups"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.messages": {
  "text": "Messages: {failed} failed, {resent} resent, {completed} completed, {failedAgain} failed again, {skipped} skipped.",
  "slots": {
   "failed": "count",
   "resent": "count",
   "completed": "count",
   "failedAgain": "count",
   "skipped": "count"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.cost": {
  "text": "Model cost of this incident: {cost}.",
  "slots": {
   "cost": "cost"
  },
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.costUnknown": {
  "text": "Model cost of this incident: not known.",
  "slots": {},
  "source": "Story 23.6 Write an incident summary when an incident closes, Public Text approved by the Contest Planner 2026-11-09"
 },
 "incident.suspendRequest": {
  "text": "I can suspend {item} in {production}. Approve?\n\nDry run: {item} is enabled now and would be disabled. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "I can suspend {item} in {production}.\n\nDry run: {item} is enabled now and would be disabled. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "item": "text",
   "production": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "incident.resumeRequest": {
  "text": "I can resume {item} in {production}. Approve?\n\nDry run: {item} is disabled now and would be enabled. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "I can resume {item} in {production}.\n\nDry run: {item} is disabled now and would be enabled. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "item": "text",
   "production": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "incident.rerouteRequest": {
  "text": "I can reroute {count} failed {itemNoun} from {from} to {to}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: message {example} would go to {to} instead of {from}. I'll resend {resendCount} copies to {to}; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "I can reroute {count} failed {itemNoun} from {from} to {to}.\n\nDry run: {count} {itemNoun} affected. Example: message {example} would go to {to} instead of {from}. I'll resend {resendCount} copies to {to}; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "from": "text",
   "to": "text",
   "example": "text",
   "resendCount": "count"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09",
  "one": {
   "slot": "resendCount",
   "text": "I can reroute {count} failed {itemNoun} from {from} to {to}. Approve?\n\nDry run: {count} {itemNoun} affected. Example: message {example} would go to {to} instead of {from}. I'll resend 1 copy to {to}; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.",
   "web": "I can reroute {count} failed {itemNoun} from {from} to {to}.\n\nDry run: {count} {itemNoun} affected. Example: message {example} would go to {to} instead of {from}. I'll resend 1 copy to {to}; the original stays unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  }
 },
 "incident.goodChanged": {
  "text": "{count} {itemNoun} failed since {time}. {cause}. The fix I would use would also change {noun} that went through, so I'm not proposing it. Nothing was changed.\n\nFailures:\n{groups}\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "time": "time",
   "cause": "sentence",
   "noun": "text",
   "groups": "groups"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.itemSuspended": {
  "text": "{item} in {production} is suspended: it is disabled now. To undo it while this incident is open, ask me to resume {item}. After the incident closes, enable {item} again on the production's configuration page in the Management Portal.",
  "slots": {
   "item": "text",
   "production": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, text ruled by the Contest Planner 2026-11-10 (DW-1068 re-ruling)"
 },
 "result.itemResumed": {
  "text": "{item} in {production} is enabled again.",
  "slots": {
   "item": "text",
   "production": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.itemSkipped": {
  "text": "{item} was not changed: {reason}. It needs a new approval.",
  "slots": {
   "item": "text",
   "reason": "sentence"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.itemNotChanged": {
  "text": "Nothing was changed: {reason}.",
  "slots": {
   "reason": "sentence"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.rerouted": {
  "text": "All {count} {itemNoun} were rerouted to {to} and completed there. The originals stay unchanged.",
  "slots": {
   "count": "count",
   "itemNoun": "noun",
   "to": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09",
  "one": {
   "slot": "count",
   "text": "The {itemNoun} was rerouted to {to} and completed there. The original stays unchanged."
  }
 },
 "summary.requestedSuspend": {
  "text": "{time}: OcuTalon asked for approval to suspend {item}.",
  "slots": {
   "time": "time",
   "item": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.requestedResume": {
  "text": "{time}: OcuTalon asked for approval to resume {item}.",
  "slots": {
   "time": "time",
   "item": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.requestedReroute": {
  "text": "{time}: OcuTalon asked for approval to reroute {count} {itemNoun} to {to}.",
  "slots": {
   "time": "time",
   "count": "count",
   "itemNoun": "noun",
   "to": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.itemSuspended": {
  "text": "{time}: {item} was suspended.",
  "slots": {
   "time": "time",
   "item": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.itemResumed": {
  "text": "{time}: {item} was resumed.",
  "slots": {
   "time": "time",
   "item": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.itemNotChanged": {
  "text": "{time}: {item} was not changed.",
  "slots": {
   "time": "time",
   "item": "text"
  },
  "source": "Story 23.2 Suspend, resume and reroute with a dry run, Public Text approved by the Contest Planner 2026-11-09"
 },
 "incident.partnerRequest": {
  "text": "I drafted a delay notice about this incident for {recipients}. Approve sending it?\n\nDry run: the notice below would go to the Simulated mailbox, not to a real inbox. The recipients are simulated partner contacts.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page.",
  "web": "I drafted a delay notice about this incident for {recipients}.\n\nDry run: the notice below would go to the Simulated mailbox, not to a real inbox. The recipients are simulated partner contacts.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page.",
  "slots": {
   "recipients": "text",
   "notice": "text"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.partnerSent": {
  "text": "The delay notice went to the Simulated mailbox for all {count} partner contacts. No real email was sent.",
  "slots": {
   "count": "count"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09",
  "one": {
   "slot": "count",
   "text": "The delay notice went to the Simulated mailbox for the partner contact. No real email was sent."
  }
 },
 "result.partnerSentSome": {
  "text": "The delay notice went to the Simulated mailbox for {completed} of {total} partner contacts. Not sent to the rest: {reason}. No real email was sent.",
  "slots": {
   "completed": "count",
   "total": "count",
   "reason": "sentence"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.partnerNotSent": {
  "text": "The delay notice was not sent: {reason}. It needs a new approval.",
  "slots": {
   "reason": "sentence"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.partnerKept": {
  "text": "The delay notice is approved and kept as a draft: email delivery isn't set up yet, so nothing was sent.",
  "slots": {},
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "result.partnerNotDrafted": {
  "text": "I couldn't draft the delay notice just now, so nothing was raised or sent. You can ask me again.",
  "slots": {},
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.requestedPartner": {
  "text": "{time}: OcuTalon asked for approval to send a delay notice to {count} partner contacts.",
  "slots": {
   "time": "time",
   "count": "count"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09",
  "one": {
   "slot": "count",
   "text": "{time}: OcuTalon asked for approval to send a delay notice to the partner contact."
  }
 },
 "summary.partnerSent": {
  "text": "{time}: the delay notice went to the Simulated mailbox.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.partnerKept": {
  "text": "{time}: the delay notice was approved and kept as a draft.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "summary.partnerNotSent": {
  "text": "{time}: the delay notice was not sent.",
  "slots": {
   "time": "time"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "partner.subject": {
  "text": "Simulated delay notice to {recipient}",
  "slots": {
   "recipient": "text"
  },
  "source": "Story 23.5 Draft partner delay notices that are sent only after approval, Public Text approved by the Contest Planner 2026-11-09"
 },
 "mcp.serverUnavailable": {
  "text": "I couldn't connect to the MCP server {server} at {time}, so I can't use its tools.",
  "slots": {
   "server": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / MCP servers and tools (step 4) / Server unavailable"
 },
 "mcp.toolShadowsBuiltIn": {
  "text": "The MCP server {server} offers a tool called '{tool}', which has the same name as one of my built-in tools, so I won't use it. Nothing was changed.",
  "slots": {
   "server": "text",
   "tool": "text"
  },
  "source": "EXPERIENCE Message Catalog / MCP servers and tools (step 4) / Tool shadows a built-in"
 },
 "mcp.toolChanged": {
  "text": "{tool} on {server} changed its description or inputs, so it is Unclassified again. Until an admin classifies it in Settings, it counts as risky and runs only after an approval.",
  "slots": {
   "tool": "text",
   "server": "text"
  },
  "source": "EXPERIENCE Message Catalog / MCP servers and tools (step 4) / Tool changed"
 },
 "mcp.replayToolChanged": {
  "text": "{tool} on {server} didn't run: the tool changed after this request was made, so it needs a new approval. Nothing was changed.",
  "slots": {
   "tool": "text",
   "server": "text"
  },
  "source": "EXPERIENCE Message Catalog / MCP servers and tools (step 4) / Approved call, tool changed"
 },
 "mcp.sourceStopped": {
  "text": "The source {source} stopped polling at {time}, because its tool {tool} on {server} is no longer Read-only. Your digest lists it as not checked.",
  "slots": {
   "source": "text",
   "tool": "text",
   "server": "text",
   "time": "time"
  },
  "source": "EXPERIENCE Message Catalog / MCP servers and tools (step 4) / Source stopped"
 },
 "watch.queueBacklog": {
  "text": "The {itemName} queue in the {production} production had {count} messages waiting at {time}, the oldest since {oldestAt}.\nWhy now: you asked me to watch queue backlogs.",
  "slots": {
   "itemName": "text",
   "production": "text",
   "count": "count",
   "time": "time",
   "oldestAt": "time"
  },
  "source": "Story 23.7 (Queue-backlog check); text: Contest Planner Public Text ruling, 2026-11-11",
  "one": {
   "slot": "count",
   "text": "The {itemName} queue in the {production} production had 1 message waiting at {time}, since {oldestAt}.\nWhy now: you asked me to watch queue backlogs."
  }
 },
 "files.tooLarge": {
  "text": "That file is {size}; the limit is 10 MB.",
  "slots": {
   "size": "text"
  },
  "source": "EXPERIENCE Step 6 (Send a file) and the Story 25.3 row of the same text; sent to a paired Telegram chat by Story 26.2"
 },
 "files.unreadable": {
  "text": "I couldn't read that file: {reason}.",
  "slots": {
   "reason": "text"
  },
  "source": "EXPERIENCE Step 6 (Send a file) and the Story 25.3 row of the same text; sent to a paired Telegram chat by Story 26.2"
 },
 "files.offOnDemo": {
  "text": "Sending files is off on the online demo. It works on your own install.",
  "slots": {},
  "source": "EXPERIENCE Step 6 (Send a file) and the Story 25.3 row of the same text (Core.Files TEXTOFFONDEMO); sent to a paired Telegram chat by Story 26.2"
 },
 "files.noReader": {
  "text": "I got {name}, but I can't read files yet.",
  "slots": {
   "name": "text"
  },
  "source": "Story 25.3 (Core.Files TEXTNOREADER); sent to a paired Telegram chat by Story 26.2 while no reader is on (Planner ruling H2, 2026-11-14)"
 }
}
}

}
