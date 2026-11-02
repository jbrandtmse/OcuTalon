/// A fix kind for the tests of OcuTalon.Fix.Kind (Story 7.1). It is not in Kind KINDS, so it is no registered kind: Classes and ForName do not know it, and the tests
/// use it for the base's schema check (two parameters, alpha and beta) and for the grants of a kind that declares three pairs, one of them twice.
Class OcuTalon.Test.Fix.ZzKind Extends OcuTalon.Fix.Kind
{

Parameter NAME = "zz_kind";

Parameter PARAMETERS = "alpha,beta";

Parameter RESOURCES = "ZzResource:R,ZzResource:W,ZzOther:U,ZzResource:R";

}
