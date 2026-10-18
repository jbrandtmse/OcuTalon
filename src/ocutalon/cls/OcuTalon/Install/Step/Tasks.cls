/// Creates the scheduled tasks that the areas declare in Tasks() (AD-23, AD-27). Tasks are seed (AD-19):
/// a task is created when no task of that name exists, and an existing task is left alone, so a schedule
/// or a property changed in the Task Manager survives every start and upgrade.
Class OcuTalon.Install.Step.Tasks Extends OcuTalon.Install.Step
{

/// Every task name starts with this.
Parameter TASKPREFIX = "OcuTalon";

ClassMethod Run() As %Status
{
	Set sc = ##class(OcuTalon.Install.Registry).Declared("Tasks", .declared)
	If $$$ISERR(sc) Quit sc
	Set n = ""
	For {
		Set n = $Order(declared(n))
		Quit:n=""
		Set sc = ..Check(declared(n), declared(n, "area"), .names)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	Set n = ""
	For {
		Set n = $Order(declared(n))
		Quit:n=""
		Set sc = ..Create(declared(n), declared(n, "area"))
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// A declaration needs a name that starts with OcuTalon and that no earlier declaration holds, and a task class.
ClassMethod Check(entry As %DynamicObject, area As %String, ByRef names) As %Status [ Private ]
{
	Set name = entry.name
	If $Extract(name, 1, $Length(..#TASKPREFIX)) '= ..#TASKPREFIX {
		Quit $SYSTEM.Status.Error(5001, area_" Tasks(): task name '"_name_"' must start with "_..#TASKPREFIX)
	}
	If $Data(names(name)) {
		Quit $SYSTEM.Status.Error(5001, area_" Tasks(): task name '"_name_"' is already declared by "_names(name))
	}
	Set names(name) = area
	If (entry.taskClass = "") || '$$$comClassDefined(entry.taskClass) || '$ClassMethod(entry.taskClass, "%Extends", "%SYS.Task.Definition") {
		Quit $SYSTEM.Status.Error(5001, area_" Tasks(): task '"_name_"' has no task class that extends %SYS.Task.Definition")
	}
	Quit $SYSTEM.Status.OK()
}

/// Creates the task unless one of that name exists. It runs as the installing user unless the declaration says
/// otherwise, in the current namespace.
ClassMethod Create(entry As %DynamicObject, area As %String) As %Status [ Private ]
{
	Set name = entry.name
	If ##class(%SYS.Task).FindId(name) '= "" Quit $SYSTEM.Status.OK()
	Try {
		Set task = ##class(%SYS.Task).%New()
		Set task.Name = name
		Set task.Description = entry.description
		Set task.TaskClass = entry.taskClass
		Set task.NameSpace = $Namespace
		Set task.RunAsUser = $Username
		Do ..Assign(task, entry.task)
		Set definition = $ClassMethod(entry.taskClass, "%New")
		Do ..Assign(definition, entry.settings)
		Set sc = task.AssignSettings(definition)
		If $$$ISOK(sc) Set sc = task.%Save()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) Quit $SYSTEM.Status.Error(5001, area_" Tasks(): task '"_name_"' could not be created: "_$Translate($SYSTEM.Status.GetErrorText(sc), $Char(13, 10), "  "))
	Quit sc
}

/// Sets each property of the declaration object on target.
ClassMethod Assign(target As %RegisteredObject, values As %DynamicObject) [ Private ]
{
	If '$IsObject(values) Quit
	Set iterator = values.%GetIterator()
	While iterator.%GetNext(.property, .value) {
		Set $Property(target, property) = value
	}
}

}
