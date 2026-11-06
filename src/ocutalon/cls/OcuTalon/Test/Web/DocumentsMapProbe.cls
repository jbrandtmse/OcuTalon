/// A dispatch class for Test.Web.DocumentsApi.TestDispatch (Story 34.2, Task 0 (a)): the same kind of Map line as Web.Api's, forwarding to
/// Test.Web.DocumentsProbe instead of Web.Documents, so that the whole chain (the map, the forwarded dispatch's role check, its own routes) can
/// run in a process that lacks the OcuTalon user role, with the roles the test sets in the probe. It has no Test methods and the product never
/// refers to it.
Class OcuTalon.Test.Web.DocumentsMapProbe Extends OcuTalon.Web.Public.ApiBase
{

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Map Prefix="/v1/documents" Forward="OcuTalon.Test.Web.DocumentsProbe"/>
</Routes>
}

}
