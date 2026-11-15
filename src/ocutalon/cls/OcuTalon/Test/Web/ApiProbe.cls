/// A subclass of OcuTalon.Web.Api for the tests, which overrides its private Post so that the REST tests run on a slot with no
/// production (Story 2.4; AD-22). It has no Test methods and the product never refers to it. Post hands the input to a shadow
/// instance of Test.Core.WebChatInProbe, which records under the run number in ^OcuTalonTest("ApiProbe", "run");
/// ^OcuTalonTest("ApiProbe", "mode") is "" to let the message through and "fail" to answer an error status, as a production
/// that can't take the message does; ^OcuTalonTest("ApiProbe", "refuse") is 1 to have the allowance refuse the message with a
/// retryAt (the refused output, Story 16.9) and "busy" to have it refuse with no retryAt (an error status); when
/// ^OcuTalonTest("ApiProbe", "output") is set, Post answers that text as the service's output, as it is (QA, Story 16.9: an output that
/// is not a JSON object). Press (Story 4.3) answers instead of BreakFeedIn: it records the session of each press under
/// ^OcuTalonTest("ApiProbe", "presses", n) and answers the text in ^OcuTalonTest("ApiProbe", "press"): "fail" is an error status, any
/// other text is the service's output as it is, and an absent value is a sent press. The roles of the signed-in user (Story 33.2) are
/// the text in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which both the OcuTalon user role check and
/// the admin check of OnPreDispatch read, and the process's own $Roles otherwise. AnswerFor makes Answer, the private mapping of a save's
/// CommandResult to the HTTP answer, callable. RefusalFor does the same for AnswerResponse's not_allowed answer (Story 25.5).
Class OcuTalon.Test.Web.ApiProbe Extends OcuTalon.Web.Api
{

ClassMethod Post(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	If $Get(^OcuTalonTest("ApiProbe", "mode")) = "fail" Quit $SYSTEM.Status.Error(5001, "zz the production is not running")
	If $Data(^OcuTalonTest("ApiProbe", "output")) {
		Set output = ^OcuTalonTest("ApiProbe", "output")
		Quit $SYSTEM.Status.OK()
	}
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.WebChatInProbe", .sc)
	If '$IsObject(probe) Quit sc
	Set probe.RunNumber = $Get(^OcuTalonTest("ApiProbe", "run"))
	Set refuse = $Get(^OcuTalonTest("ApiProbe", "refuse"))
	If refuse = 1 Set probe.Refuse = 1
	If refuse = "busy" Set probe.RefuseBusy = 1
	Quit probe.OnProcessInput(input, .output)
}

/// The roles of the signed-in user: the test's, when it set them.
/// The submit of SaveChannels: an error status, as a production that does not take the command, when ^OcuTalonTest("ApiProbe", "submit") is "fail";
/// otherwise the real one.
ClassMethod SubmitChannels(command As OcuTalon.Msg.Command.SaveSettings, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("ApiProbe", "submit")) = "fail" Quit $SYSTEM.Status.Error(5001, "zz the production is not running")
	Quit ##super(command, .result)
}

/// The submit of SignInMail (Story 21.3): it records the command's Action, PageOrigin and ActingUser under ^OcuTalonTest("ApiProbe", "signin") and answers from
/// ^OcuTalonTest("ApiProbe", "signinResult"): "fail" is an error status, "none" answers no result, and otherwise a CommandResult whose Ok, Outcome and Data are the
/// pieces of the text "<ok>|<outcome>|<data>" (the default is 1|started|{"url":"https://zz.example/start"}).
ClassMethod SubmitSignIn(command As OcuTalon.Msg.Command.MailSignIn, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set result = ""
	Set ^OcuTalonTest("ApiProbe", "signin") = command.Action_"|"_command.PageOrigin_"|"_command.ActingUser_"|"_command.SessionRef
	Set answer = $Get(^OcuTalonTest("ApiProbe", "signinResult"), "1|started|{""url"":""https://zz.example/start""}")
	If answer = "fail" Quit $SYSTEM.Status.Error(5001, "zz the production is not running")
	If answer = "none" Quit $SYSTEM.Status.OK()
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = $Piece(answer, "|", 1)
	Set result.Outcome = $Piece(answer, "|", 2)
	Set result.Data = $Piece(answer, "|", 3, *)
	Quit $SYSTEM.Status.OK()
}

ClassMethod Roles() As %String [ Private ]
{
	If $Data(^OcuTalonTest("ApiProbe", "roles")) Quit ^OcuTalonTest("ApiProbe", "roles")
	Quit ##super()
}

/// 1 when the test's roles hold the OcuTalon user role or the viewer role (Shell.HasRole), else the process's own check.
ClassMethod HasUserRole() As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("ApiProbe", "roles")) Quit ##class(OcuTalon.Web.Public.Shell).HasRole(^OcuTalonTest("ApiProbe", "roles"))
	Quit ##super()
}

/// The live role set of OnPreDispatch's re-read: ^OcuTalonTest("ApiProbe", "liveRoles") when it is set, an error status when ^OcuTalonTest("ApiProbe", "liveError") is
/// set, and the test's own roles (Roles) otherwise, so that a test that sets the roles of the signed-in user holds them live too.
ClassMethod LiveRoles(Output roles As %String) As %Status [ Private ]
{
	Set roles = ""
	If $Data(^OcuTalonTest("ApiProbe", "liveError")) Quit $SYSTEM.Status.Error(5001, "zz live roles unreadable")
	Set n = $Increment(^OcuTalonTest("ApiProbe", "liveReads"))
	Set roles = $Select($Data(^OcuTalonTest("ApiProbe", "liveRoles")): ^OcuTalonTest("ApiProbe", "liveRoles"), 1: ..Roles())
	Quit $$$OK
}

/// 1 when ^OcuTalonTest("ApiProbe", "rolesReady") is 1, so that a test can see the Roles section's flag on: the install has no STEP6ROLES yet.
ClassMethod RolesInstalled() As %Boolean [ Private ]
{
	Quit ($Get(^OcuTalonTest("ApiProbe", "rolesReady")) = 1)
}

/// Answer, for the tests: the HTTP answer to a save's CommandResult.
ClassMethod AnswerFor(result As OcuTalon.Msg.CommandResult, word As %String = "") As %Status
{
	Quit ..Answer(result, word)
}

/// AnswerResponse, for the tests: the HTTP answer to a not_allowed AnswerResult whose refusal is the object (the kind that the role check named, and admin for the email rule).
ClassMethod RefusalFor(refusal As %DynamicObject) As %Status
{
	Set result = ##class(OcuTalon.Core.Msg.AnswerResult).%New()
	Set result.Result = "not_allowed"
	Quit ..AnswerResponse("", refusal, "", result)
}

/// The press that BreakFeedIn would carry out, answered from ^OcuTalonTest("ApiProbe", "press").
ClassMethod Press(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set n = $Increment(^OcuTalonTest("ApiProbe", "presses"))
	Set ^OcuTalonTest("ApiProbe", "presses", n) = input.SessionRef
	Set answer = $Get(^OcuTalonTest("ApiProbe", "press"), {"outcome": "sent", "state": "sent", "startedAt": "2030-01-01T10:00:00Z"}.%ToJSON())
	If answer = "fail" Quit $SYSTEM.Status.Error(5001, "zz BreakFeedIn is not running")
	Set output = answer
	Quit $SYSTEM.Status.OK()
}

/// The email that SimMailboxIn would record (Story 4.6): each input's session, sample and fields are recorded under
/// ^OcuTalonTest("ApiProbe", "mails", n) as "session", "sample", "sender", "subject" and "text", and the answer comes from
/// ^OcuTalonTest("ApiProbe", "mail"): "fail" is an error status, any other text is the service's output as it is, and an
/// absent value is {"ref":"zzMailRef0123456789abc"}.
ClassMethod Mail(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set n = $Increment(^OcuTalonTest("ApiProbe", "mails"))
	Set ^OcuTalonTest("ApiProbe", "mails", n, "session") = input.SessionRef
	Set ^OcuTalonTest("ApiProbe", "mails", n, "sample") = input.Sample
	Set ^OcuTalonTest("ApiProbe", "mails", n, "sender") = input.Sender
	Set ^OcuTalonTest("ApiProbe", "mails", n, "subject") = input.Subject
	Set ^OcuTalonTest("ApiProbe", "mails", n, "text") = input.Text
	Set answer = $Get(^OcuTalonTest("ApiProbe", "mail"), {"ref": "zzMailRef0123456789abc"}.%ToJSON())
	If answer = "fail" Quit $SYSTEM.Status.Error(5001, "zz SimMailboxIn is not running")
	Set output = answer
	Quit $SYSTEM.Status.OK()
}

}
