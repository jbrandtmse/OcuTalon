/// The REST surface of OcuTalon at /ocutalon/api (AD-13): JSON, versioned under /v1, one CSP session shared
/// with /ocutalon and the trace applications. The URL map is empty until the routes are added, so every
/// request that is signed in is answered 404 and every request without a session is answered 401.
Class OcuTalon.Web.Api Extends %CSP.REST
{

Parameter UseSession = 1;

Parameter CONTENTTYPE = "application/json";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
</Routes>
}

}
