/// The texts of the public package against the catalog (Story 0.9, AD-3). The sign-in page and the API's signed-out answer run
/// before sign-in, so OcuTalon.Web.Public keeps its own copies of the UX texts as class parameters and may not reference the
/// catalog. The XData block Classified puts every own parameter of every class of OcuTalon.Web.Public and
/// OcuTalon.Data.Public in exactly one list:
///   - compared: a text with a catalog key, which must equal the key's web rendering (&middot; stands for U+00B7, and any
///     other &name; entity fails);
///   - notInUx: a text that the UX does not quote, so the catalog has no key for it;
///   - notText: a parameter that is not a text.
/// TestEveryParameterIsClassified reads the classes and their own parameters from the class dictionary, so a new parameter, a
/// removed one or a parameter in two lists fails, and a new text cannot skip the comparison. Test.Web.SignIn.TestTexts keeps
/// pinning the page's literals.
Class OcuTalon.Test.Web.PublicTexts Extends OcuTalon.Test.Contract
{

/// Each compared parameter equals its catalog key's web text.
Method TestCopiesEqualTheCatalog()
{
	Set count = 0
	Set iterator = ..Read("Classified").compared.%GetIterator()
	While iterator.%GetNext(.class, .parameters) {
		Set inner = parameters.%GetIterator()
		While inner.%GetNext(.name, .key) {
			Set count = count + 1
			Set copy = $Parameter(class, name)
			Set decoded = $Replace(copy, "&middot;", $Char(183))
			Do $$$AssertNotTrue($Match(decoded, "^.*&[A-Za-z0-9#]+;.*$"), class_"."_name_" holds no entity other than &middot;")
			Set text = ##class(OcuTalon.Msg.Catalog).Render(key, "", "web", .sc)
			Do $$$AssertStatusOK(sc, key_" renders")
			Do $$$AssertEquals(decoded, text, class_"."_name_" equals the catalog key "_key)
		}
	}
	Do $$$AssertEquals(count, 8, "8 parameters are compared with the catalog")
}

/// Every own parameter of every class of both public packages is in exactly one list, and no list names a parameter that the
/// class no longer has.
Method TestEveryParameterIsClassified()
{
	Kill actual, listed
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Name FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH 'OcuTalon.Web.Public.' OR Name %STARTSWITH 'OcuTalon.Data.Public.' ORDER BY Name")
	Do $$$AssertStatusOK(sc, "the public classes are listed")
	Set rows = statement.%Execute()
	Set classes = 0
	While rows.%Next() {
		Set class = rows.%GetData(1)
		Set classes = classes + 1
		Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(class)
		Set key = ""
		For {
			Set parameter = compiled.Parameters.GetNext(.key)
			Quit:key=""
			If parameter.Origin = class Set actual(class, parameter.Name) = ""
		}
	}
	Do $$$AssertTrue(classes >= 6, "both packages hold their classes: "_classes)
	Set counts("compared") = 0, counts("notInUx") = 0, counts("notText") = 0
	Set twice = ""
	Set classified = ..Read("Classified")
	For list = "compared", "notInUx", "notText" {
		Set iterator = classified.%Get(list).%GetIterator()
		While iterator.%GetNext(.class, .members) {
			If list = "compared" {
				Set inner = members.%GetIterator()
				While inner.%GetNext(.name) {
					Do ..Note(class, name, list, .listed, .counts, .twice)
				}
			} Else {
				Set inner = members.%GetIterator()
				While inner.%GetNext(, .name) {
					Do ..Note(class, name, list, .listed, .counts, .twice)
				}
			}
		}
	}
	Do $$$AssertEquals(counts("compared"), 8, "8 parameters are compared")
	Do $$$AssertEquals(counts("notInUx"), 3, "3 labels are not in the UX")
	Do $$$AssertEquals(counts("notText"), 18, "18 parameters are not texts")
	Do $$$AssertEquals(twice, "", "no parameter is in two lists")
	Set unlisted = ""
	Set stale = ""
	Set class = ""
	For {
		Set class = $Order(actual(class))
		Quit:class=""
		Set name = ""
		For {
			Set name = $Order(actual(class, name))
			Quit:name=""
			If '$Data(listed(class, name)) Set unlisted = unlisted_" "_class_"."_name
		}
	}
	Set class = ""
	For {
		Set class = $Order(listed(class))
		Quit:class=""
		Set name = ""
		For {
			Set name = $Order(listed(class, name))
			Quit:name=""
			If '$Data(actual(class, name)) Set stale = stale_" "_class_"."_name
		}
	}
	Do $$$AssertEquals($ZStrip(unlisted, "<W"), "", "every own parameter is classified")
	Do $$$AssertEquals($ZStrip(stale, "<W"), "", "no classified parameter is missing from its class")
}

/// Records one classified parameter: in listed, in the count of its list, and in twice when it was listed before.
ClassMethod Note(class As %String, name As %String, list As %String, ByRef listed, ByRef counts, ByRef twice) [ Private ]
{
	If $Data(listed(class, name)) Set twice = twice_" "_class_"."_name
	Set listed(class, name) = list
	Set counts(list) = counts(list) + 1
}

/// The classification of every own parameter of the public classes.
XData Classified [ MimeType = application/json ]
{
{
 "compared": {
  "OcuTalon.Web.Public.Login": {
   "TITLE": "signIn.title",
   "HEADING": "signIn.heading",
   "SUBMIT": "signIn.submit",
   "HELP": "signIn.help",
   "ERRORCREDENTIALS": "signIn.errorCredentials",
   "ERRORNOROLE": "signIn.errorNoRole",
   "LOGOALT": "signIn.logoAlt"
  },
  "OcuTalon.Web.Public.ApiBase": {
   "MESSAGESIGNEDOUT": "signIn.signedOut"
  }
 },
 "notInUx": {
  "OcuTalon.Web.Public.Login": ["USERLABEL", "PASSWORDLABEL", "SHOWPASSWORD"]
 },
 "notText": {
  "OcuTalon.Web.Public.ApiBase": ["CHARSET", "CONTENTTYPE"],
  "OcuTalon.Web.Public.Login": ["FAVICON", "ICONALERT", "ICONEYE", "IMAGES", "LOGODARK", "LOGOLIGHT"],
  "OcuTalon.Web.Public.Shell": ["CONTENTTYPE", "ROLE", "UseSession"],
  "OcuTalon.Web.Public.SignInAssets": ["CSS", "SCRIPT"],
  "OcuTalon.Web.Public.Status": ["CONTENTTYPE", "HandleCorsRequest", "UseSession"],
  "OcuTalon.Data.Public.Settings": ["KEYS", "READY"]
 }
}
}

}
