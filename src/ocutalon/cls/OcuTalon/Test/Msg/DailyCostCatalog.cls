/// A catalog for OcuTalon.Test.Msg.DailyCost: the renderer OcuTalon.Msg.Catalog with a CLASSES of its own, whose one Entries block holds two
/// test keys that declare a cost slot, one of the type dailyCost and one of the type cost, so that the two types can be compared. It holds no
/// product text, and the product never refers to it.
Class OcuTalon.Test.Msg.DailyCostCatalog Extends OcuTalon.Msg.Catalog
{

Parameter CLASSES = "OcuTalon.Test.Msg.DailyCostCatalog";

XData Entries [ MimeType = application/json ]
{
{
 "test.daily": {
  "text": "Cost {cost}.",
  "slots": {
   "cost": "dailyCost"
  },
  "source": "Story 33.2 test"
 },
 "test.tiered": {
  "text": "Cost {cost}.",
  "slots": {
   "cost": "cost"
  },
  "source": "Story 33.2 test"
 }
}
}

}
