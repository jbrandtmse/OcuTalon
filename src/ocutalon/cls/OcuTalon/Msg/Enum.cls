/// The enumerations of the contracts, each a comma list; the values equal the architecture conventions. Display names live in the catalog and the web app. The bridge keeps copies in OcuTalon.Bridge.Msg.Enum (AD-2).
Class OcuTalon.Msg.Enum
{

/// Attention decision outcomes (AD-30).
Parameter OUTCOME = "ignore,digest,tellnow,act";

/// Provenance of an item: text the user wrote, or everything else (AD-14).
Parameter PROVENANCE = "user,untrusted";

/// Kinds of model request that Decide serves (AD-6).
Parameter REQUESTKIND = "decide,diagnose,turn,tool";

/// Reasons a reply is unusable, in the order Decide checks them (AD-8).
Parameter FALLBACKREASON = "no_key,daily_cap,budget,too_large,timeout,rate_limited,error,refusal,cut_off,empty,invalid,unusable";

/// Incident states (AD-15).
Parameter INCIDENTSTATE = "open,awaiting_approval,fixing,resolved,closed";

/// The open variant of an incident, stored beside its state (AD-15).
Parameter INCIDENTOPENVARIANT = "fallback,no_fix,rejected,expired";

/// Approval request states (AD-11).
Parameter APPROVALSTATE = "pending,approved,rejected,expired,cancelled,executing,done,failed";

/// Approval request kinds (AD-11).
Parameter APPROVALKIND = "fix,tool_call";

/// Notification kinds (AD-32).
Parameter NOTIFICATIONKIND = "tellnow,incident,approval,answered,result,reminder,fallback,allowance,pairing,status,digest";

/// Results of a background check (AD-18).
Parameter CHECKRESULT = "passed,failed,not_checked";

/// Channels (AD-14).
Parameter CHANNEL = "web,phone,mailbox,telegram,email,webhook,slack,system";

/// Origins of a command (AD-1).
Parameter ORIGIN = "web_user,web_admin,telegram,tool,timer,system";

}
