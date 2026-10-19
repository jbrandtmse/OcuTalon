/// The timeout API (AD-8). Epic 0 fixes the signature with a stub body; Lane A implements it in Story 1.7.
Class OcuTalon.Bridge.Timeouts
{

/// The timeouts that the bridge derives from one timer, in seconds, as an object. Not implemented yet: it answers an
/// empty object.
ClassMethod Derive(timer As %Integer) As %DynamicObject
{
	Quit {}
}

}
