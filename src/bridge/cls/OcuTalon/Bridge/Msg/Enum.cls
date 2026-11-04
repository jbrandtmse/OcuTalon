/// The bridge's copy of the enumerations that its own contracts use; each equals the same-named parameter of Msg.Enum in the OcuTalon package, which a test pins (AD-2).
Class OcuTalon.Bridge.Msg.Enum
{

/// Attention decision outcomes (AD-30).
Parameter OUTCOME = "ignore,digest,tellnow,act";

/// Provenance of an item: text the user wrote, or everything else (AD-14).
Parameter PROVENANCE = "user,untrusted";

/// Kinds of model request that Decide serves (AD-6).
Parameter REQUESTKIND = "decide,diagnose,turn,tool";

/// Reasons a reply is unusable, in the order Decide checks them (AD-8).
Parameter FALLBACKREASON = "no_key,daily_cap,budget,too_large,timeout,rate_limited,error,refusal,cut_off,empty,invalid,unusable";

/// Approval request states (AD-11).
Parameter APPROVALSTATE = "pending,approved,rejected,expired,cancelled,executing,done,failed";

/// Approval request kinds (AD-11).
Parameter APPROVALKIND = "fix,tool_call";

/// Channels (AD-14).
Parameter CHANNEL = "web,phone,mailbox,telegram,email,webhook,slack,system";

}
