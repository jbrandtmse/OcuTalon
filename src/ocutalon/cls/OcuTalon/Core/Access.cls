/// Access, the one rule of who may chat with OcuTalon through a channel that has no web session (AD-14, AD-24; DW-1284, DW-1465, DW-1466). A message of Slack, Telegram or
/// email, a pairing, a Slack link and a mailbox save each ask it with the IRIS user of a session row and never decide for themselves:
///   - RolesMayChat(roles) is web chat's own rule on a comma list of roles: the list holds OcuTalonUser, by its whole name. A viewer without it, OcuTalonAdmin alone, %All alone and
///     no role may not chat. Web.Api OnPreDispatch is web chat's gate, and Test.Web.ViewerApi pins this method to it on ten role sets;
///   - MayChat(irisUser) is the call of every channel: the user's recursed role set read by Bridge.Approval RolesOf (the one read of another user's roles), RolesMayChat on it, and
///     then the account's state (AccountUsable). It answers 1 only when all three hold. An empty or unknown user, a role set or an account that cannot be read, and any error answer 0;
///   - AccountUsable(irisUser) is the account's state alone (Enabled, not past its ExpirationDate), for a caller that needs no chat role: the answer of an approval (DW-1482) asks it and no role.
/// It runs in the caller's job. A production job runs as _Ensemble with %All, which is what reading another user's roles and the account's state needs; no role, grant or
/// resource is added, and where the account cannot be read (a job without that privilege) it fails closed and answers 0. It names no class of the web packages: Core does not depend on them.
/// It writes nothing and never throws.
Class OcuTalon.Core.Access
{

/// The role that lets a user chat.
Parameter USERROLE = "OcuTalonUser";

/// 1 when the roles (a comma list) let a user chat, by web chat's rule: they hold OcuTalonUser by its whole name. OcuTalonViewer and OcuTalonAdmin add nothing, and a list that
/// holds %All alone does not hold the role.
ClassMethod RolesMayChat(roles As %String = "") As %Boolean
{
	Quit ((","_$Get(roles)_",") [ (","_..#USERROLE_","))
}

/// 1 when the IRIS user may chat now: their recursed role set (Bridge.Approval RolesOf) may chat (RolesMayChat) and their account is usable (Usable). Callers pass the IrisUser of
/// the session row, never the user of their own job. Anything else, and any error, is 0. Nothing is written.
ClassMethod MayChat(irisUser As %String = "") As %Boolean
{
	Set may = 0
	Try {
		If $Get(irisUser) '= "" {
			If ##class(OcuTalon.Bridge.Approval).RolesOf(irisUser, .roles) && ..RolesMayChat(roles) Set may = ..AccountUsable(irisUser)
		}
	} Catch exception {
		Set may = 0
	}
	Quit may
}

/// 1 when the IRIS account is Enabled and not past its ExpirationDate (the last day the account may be used), through Usable, the one reader. An unknown account, an empty user, an account
/// that cannot be read and any error answer 0. It never throws and writes nothing.
ClassMethod AccountUsable(irisUser As %String = "") As %Boolean
{
	Set usable = 0
	Try {
		Set usable = ..Usable($Get(irisUser))
	} Catch exception {
		Set usable = 0
	}
	Quit usable
}

/// 1 when the IRIS account is Enabled and not past its ExpirationDate (the last day the account may be used): the one method of this class that switches namespace. It reads
/// Security.Users, which only %SYS holds, for this one user, in the calling job, and it reads nothing else of the account. It answers a boolean only and writes nothing.
/// The namespace is the caller's again on every path: New $Namespace restores it when the method ends, an error included, and the Catch answers 0 for any error. An unknown
/// account, an empty user and an account that cannot be read answer 0.
ClassMethod Usable(irisUser As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set usable = 0
	Try {
		Set $Namespace = "%SYS"
		Set usable = ..Enabled($Get(irisUser))
	} Catch exception {
		Set usable = 0
	}
	Quit usable
}

/// 1 when Security.Users answers the account with Enabled 1 and an ExpirationDate that is empty or not before today. An account that never expires (AccountNeverExpires 1) has no
/// ExpirationDate, since IRIS clears it and lets the account sign in, so it is usable. Runs in %SYS, inside Usable's Try; a test subclass overrides it to raise an error inside the switch.
ClassMethod Enabled(irisUser As %String) As %Boolean [ Private ]
{
	If irisUser = "" Quit 0
	Kill properties
	Set sc = ##class(Security.Users).Get(irisUser, .properties)
	If $$$ISERR(sc) Quit 0
	If $Get(properties("Enabled")) '= 1 Quit 0
	Set expires = $Get(properties("ExpirationDate"))
	If expires = "" Quit 1
	Quit $ZDateH(expires, 3) '< +$Horolog
}

}
