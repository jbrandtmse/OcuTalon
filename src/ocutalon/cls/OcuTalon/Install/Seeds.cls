/// The seeding helper of the installer steps (AD-19, AD-23): it writes the seed values of settings that a step declares, each only when its key
/// is absent, so that a value an admin changed is kept at every later start. It is not a step. OcuTalon.Data.Setting is named here, and nowhere in
/// a step's own class, so that a step's purge and run code stays free of settings reads (Test.Install.Retention TestNoSettingRead).
Class OcuTalon.Install.Seeds
{

/// Seeds every member of seeds, a dynamic object of {"<setting key>": "<value>"}, through OcuTalon.Data.Setting Seed. Every member is tried; the
/// result is the first error, else OK. Anything but an object is an error.
ClassMethod Defaults(seeds As %DynamicObject) As %Status
{
	If '$IsObject(seeds) || 'seeds.%IsA("%Library.DynamicObject") Quit $SYSTEM.Status.Error(5001, "Install.Seeds.Defaults needs an object of keys and values")
	Set sc = $SYSTEM.Status.OK()
	Set iterator = seeds.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set one = ##class(OcuTalon.Data.Setting).Seed(key, value)
		If $SYSTEM.Status.IsError(one) && $SYSTEM.Status.IsOK(sc) Set sc = one
	}
	Quit sc
}

}
