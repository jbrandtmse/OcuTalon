/// A subclass of OcuTalon.Test.Web.ApiProbe for Test.Web.BodyLimit (Story 11.22): it appends the XData BodyBounds that a route of the product
/// appends to declare a larger body. POST /v1/messages takes 300000 bytes and POST /v1/approvals/:ref/answer takes 270000; the two entries
/// after them are malformed (a text and a bound that is not a number) and are skipped, so that POST /v1/guide/markers keeps the default
/// bound. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Web.BodyLimitProbe Extends OcuTalon.Test.Web.ApiProbe
{

XData BodyBounds [ MimeType = application/json ]
{
[
{"method": "POST", "url": "/v1/messages", "bytes": 300000},
{"method": "POST", "url": "/v1/approvals/:ref/answer", "bytes": 270000},
"not an entry",
{"method": "POST", "url": "/v1/guide/markers", "bytes": "big"}
]
}

}
