/// The helpers that Test.Install.Users and Test.Install.Public share (Story 3.8): the password guard's, and the clean-up of their fixture
/// accounts and page size pins. It holds no test.
///   - State() takes the instance's PasswordValidationRoutine, whether the guard routine exists and its source; Restore(state) puts the
///     setting and the routine back as State found them.
///   - Leak(expected) is "" when State still equals the expected state, otherwise a sentence that says what differs (never a password).
///   - Source() is the guard routine's source text, and RoutineExists(name) says whether a routine of %SYS exists.
///   - Check(user, password) is the guard routine's own answer, called as the password-validation hook calls it.
///   - SignInChange(user, old, new) asks the web server of the instance for a password change through a sign-in request, signs out again,
///     and gives the HTTP status of the sign-in.
///   - PasswordOk(user, password) and TryPassword(user, password) read and write a user's password. Both run in %SYS.
///   - RemoveUser(user), RemoveUsers(prefix) and ClearPins(prefix) delete fixture users and their page size pins.
/// They change the security settings of the instance: throwaways and CI only (Rule 21).
Class OcuTalon.Test.Install.PasswordGuard
{

/// The guard's routine in %SYS, as a literal: the tests read it by its name, and %SYS holds no OcuTalon class to ask.
Parameter ROUTINE = "OcuTalonPasswordGuard";

/// The port of the web server, as the instance itself reaches it.
Parameter PORT = 52773;

/// $ListBuild(the PasswordValidationRoutine setting, 1 when the guard routine exists, the routine's source or ""). Runs in %SYS.
ClassMethod State() As %List
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set exists = ##class(%Routine).Exists(..#ROUTINE_".mac")
	Quit $ListBuild(..Setting(), exists, $Select(exists: ..Source(), 1: ""))
}

/// Puts the setting and the guard routine back as State found them: the routine is written again when it existed and is missing, then the
/// setting is set (a setting that names a missing routine would refuse every password change), and the routine is deleted when it did not
/// exist. Runs in %SYS.
ClassMethod Restore(state As %List)
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set setting = $List(state, 1)
	Set exists = $List(state, 2)
	If exists, ..Source() '= $List(state, 3) Do ..Write($List(state, 3))
	If ..Setting() '= setting Do ..SetSetting(setting)
	If 'exists, ##class(%Routine).Exists(..#ROUTINE_".mac") Do ##class(%Routine).Delete(..#ROUTINE_".mac", 0)
}

/// "" when State equals the expected state (the setting, whether the routine exists, and its source), otherwise a sentence that says what
/// differs. It names no password: the source is compared, not quoted. Runs in %SYS.
ClassMethod Leak(expected As %List) As %String
{
	Set now = ..State()
	If $List(now, 1) '= $List(expected, 1) Quit "the password-validation setting is '"_$List(now, 1)_"', not '"_$List(expected, 1)_"'"
	If $List(now, 2) '= $List(expected, 2) Quit "the guard routine "_$Select($List(now, 2): "exists", 1: "is missing")_", not as it was"
	If $List(now, 3) '= $List(expected, 3) Quit "the source of the guard routine is not as it was"
	Quit ""
}

/// The guard routine's own answer for the user and password, as IRIS calls it (1, or an error status). Runs in %SYS.
ClassMethod Check(user As %String, password As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit $$Check^OcuTalonPasswordGuard(user, password)
}

/// The source text of the guard routine, a line feed after each line, or "" when there is none. Runs in %SYS.
ClassMethod Source() As %String
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(%Routine).Exists(..#ROUTINE_".mac") Quit ""
	Set routine = ##class(%Routine).%New(..#ROUTINE_".mac")
	Set text = ""
	While 'routine.AtEnd {
		Set text = text_routine.ReadLine()_$Char(10)
	}
	Quit text
}

/// 1 when the routine of the name (without its .mac) exists in %SYS. Runs in %SYS.
ClassMethod RoutineExists(name As %String) As %Boolean
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(%Routine).Exists(name_".mac")
}

/// The PasswordValidationRoutine setting of the instance. Runs in %SYS.
ClassMethod Setting() As %String
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.System).Get(, .properties)
	Quit $Get(properties("PasswordValidationRoutine"))
}

/// Sets the PasswordValidationRoutine setting. Runs in %SYS.
ClassMethod SetSetting(value As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("PasswordValidationRoutine") = value
	Quit ##class(Security.System).Modify(, .properties)
}

/// Saves the routine from its source text (lines ending in a line feed) and compiles it. Runs in %SYS.
ClassMethod Write(source As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set routine = ##class(%Routine).%New(..#ROUTINE_".mac")
	For i = 1:1:$Length(source, $Char(10)) - 1 {
		Do routine.WriteLine($Piece(source, $Char(10), i))
	}
	Set sc = routine.Save()
	If $$$ISOK(sc) Set sc = routine.Compile("-d")
	Quit sc
}

/// Posts a sign-in to /ocutalon/ as the user with IRISOldPassword and IRISPassword, which IRIS takes as a password change, then signs
/// out with /ocutalon/?IRISLogout=end, sending the session cookie that the sign-in returned. The status is the sign-in's HTTP status, or
/// 0 when the request could not be made.
ClassMethod SignInChange(user As %String, old As %String, new As %String) As %Integer
{
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = ..#PORT
	Do request.InsertFormData("IRISUsername", user)
	Do request.InsertFormData("IRISOldPassword", old)
	Do request.InsertFormData("IRISPassword", new)
	Do request.InsertFormData("IRISLogin", "Login")
	Set sc = request.Post("/ocutalon/")
	If $$$ISERR(sc) || '$IsObject(request.HttpResponse) Quit 0
	Set status = request.HttpResponse.StatusCode
	Do request.SetParam("IRISLogout", "end")
	Do request.Get("/ocutalon/")
	Quit status
}

/// 1 when the password is the user's current one (CheckPassword compares the hash and counts no invalid login). Runs in %SYS.
ClassMethod PasswordOk(user As %String, password As %String) As %Boolean
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(user, .object) Quit 0
	Quit ''##class(Security.Users).CheckPassword(.object, password)
}

/// The status of Security.Users.Modify with the password, which calls the instance's password-validation routine. Runs in %SYS.
ClassMethod TryPassword(user As %String, password As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("Password") = password
	Quit ##class(Security.Users).Modify(user, .properties)
}

/// Deletes the user when it exists; "" is no user. Runs in %SYS.
ClassMethod RemoveUser(user As %String)
{
	If user = "" Quit
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
}

/// Deletes every user whose name starts with the prefix. Runs in %SYS.
ClassMethod RemoveUsers(prefix As %String)
{
	If prefix = "" Quit
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE Name %STARTSWITH ?", prefix)
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

/// Kills the page size settings (^EnsPortal.Settings) of every name that starts with the prefix, in OCUTALON and in OCUORDERS where it
/// exists.
ClassMethod ClearPins(prefix As %String)
{
	If prefix = "" Quit
	For namespace = "OCUTALON", "OCUORDERS" {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		Set name = prefix
		For {
			Set name = $Order(^|namespace|EnsPortal.Settings(name))
			If $Extract(name, 1, $Length(prefix)) '= prefix Quit
			Kill ^|namespace|EnsPortal.Settings(name)
		}
	}
}

}
