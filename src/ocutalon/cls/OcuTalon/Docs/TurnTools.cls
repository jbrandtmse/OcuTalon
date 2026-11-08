Include Ensemble

/// The documents tool of a turn (AD-6, AD-21, AD-31, Story 19.5; Lane A): the host's extension of OcuTalon.Bridge.Ext.TurnTools, named in the TurnToolsClass
/// setting of the Decide item. For a request of kind turn it returns the knowledge base of the turn owner's documents, and the runner's adapter composes a new
/// tool manager for that request around it (the tool "documents" then searches that owner's table only) and puts the agent's own manager back when the request
/// ends. The owner is eval for the OwnerRef eval (an evaluation run, whose documents are in OcuTalonKB.Eval and no person's turn searches), and otherwise
/// Docs.Store OwnerFor of the OwnerRef: the session itself on the online demo and instance on a local install. A request of any other kind (decide, diagnose),
/// an owner with no table (a session that has added no document, a dropped table, a reference no Session row has) and a table that cannot be built give no
/// tool and a request that runs with the agent's own tools. It never creates a table (DocumentOps does), and its Tools never returns an error over a knowledge base.
Class OcuTalon.Docs.TurnTools Extends OcuTalon.Bridge.Ext.TurnTools
{

/// The documents tool of the turn of the OwnerRef: one Docs.Store holder in tools, or none.
ClassMethod Tools(ownerRef As %String, kind As %String, Output tools As %ListOfObjects) As %Status
{
	Set tools = ##class(%ListOfObjects).%New()
	If kind '= "turn" Quit $$$OK
	Try {
		Set evalOwner = ##class(OcuTalon.Docs.Store).#EVALOWNER
		Set owner = $Select(ownerRef = evalOwner: evalOwner, 1: ##class(OcuTalon.Docs.Store).OwnerFor(ownerRef))
		Set table = ##class(OcuTalon.Docs.Store).TableFor(owner)
		If table '= "" {
			Do ##class(OcuTalon.Docs.Store).Knowledge(table, .holder)
			If $IsObject(holder) Do tools.Insert(holder)
		}
	} Catch exception {
		$$$LOGWARNING("Docs.TurnTools could not give the documents tool: " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
	Quit $$$OK
}

}
