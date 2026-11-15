/// One memory a session saved (AD-21, AD-33): a short text the agent keeps for later turns, with its vector. Lane A. The only writer is
/// OcuTalon.Memory.Ops (Story 19.3); reads go through OcuTalon.Memory.Search and OcuTalon.Memory.List. A memory belongs to the session
/// that saved it (SessionRef) and is dropped at its online-demo sign-out (OcuTalon.Memory.DropSession). Row ids never leave the server.
/// EmbeddingIdx (an HNSW index, cosine) finds the nearest memories of an owner and TextIdx (an %iFind index, exact words) finds its keyword hits;
/// both keep all of their globals under ^OcuTalonP.MemoryI (TextIdx with IFINDSHAREDDATALOCATION INDEX, so that its word dictionary is not in ^IRIS.IF.*), so
/// every index global is in OCUTALON_PRIVATE, and deleting a row removes its entries.
/// Source, Pinned and PinnedAt are appended columns (AD-5, AD-21): a row saved before them holds them empty, which readers take as told, 0 and unpinned.
Class OcuTalon.Data.Memory Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Memory";

/// The memory's public Ref (AD-14). Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The owner of the memory: the Ref of the session that saved it, so on a local install each user's memories are that user's own (P23). Refs are case-sensitive.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// What the agent saved, at most 2,000 characters.
Property Text As %String(MAXLEN = 2000);

/// When the memory was saved, UTC to the second.
Property SavedAt As %String(MAXLEN = 20);

/// The Ref of the item (the turn) that saved the memory.
Property ItemId As %String(COLLATION = "EXACT", MAXLEN = 22);

/// What saved the memory: one of Msg.Enum ORIGIN, or photo (Core.Commands FEATUREORIGINS) for the caption of a photo.
Property Origin As %String(MAXLEN = 16);

/// The text's vector from the AllMiniLM-L6-v2 model (AD-21).
Property Embedding As %Library.Vector(DATATYPE = "DOUBLE", LEN = 384);

/// Whether the person asked for the memory: told (the person's own text in the saving turn holds a phrase of OcuTalon.Tools.MemorySource) or learned.
/// Written by OcuTalon.Memory.Ops on every new row, never from the model's arguments. Empty on a row saved before it existed, which readers take as told.
Property Source As %String(MAXLEN = 16);

/// Whether the person pinned the memory: 0 by default.
Property Pinned As %Boolean [ InitialExpression = 0 ];

/// When the memory was pinned, UTC to the second; empty while it is not pinned.
Property PinnedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefSavedAtIndex On (SessionRef, SavedAt);

/// The nearest-neighbour index of the vector (AD-21): cosine distance, the defaults of M and efConstruction.
Index EmbeddingIdx On (Embedding) As %SQL.Index.HNSW(Distance = "Cosine");

/// The exact-word keyword index of the text (AD-21), in English, case-folded, without stemming. The dictionary and the postings are kept under the index.
Index TextIdx On (Text) As %iFind.Index.Basic(IFINDSHAREDDATALOCATION = "INDEX", INDEXOPTION = 0, LANGUAGE = "en", LOWER = 1);

Storage Default
{
<Data name="MemoryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>Text</Value>
</Value>
<Value name="5">
<Value>SavedAt</Value>
</Value>
<Value name="6">
<Value>ItemId</Value>
</Value>
<Value name="7">
<Value>Origin</Value>
</Value>
<Value name="8">
<Value>Embedding</Value>
</Value>
<Value name="9">
<Value>Source</Value>
</Value>
<Value name="10">
<Value>Pinned</Value>
</Value>
<Value name="11">
<Value>PinnedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.MemoryD</DataLocation>
<DefaultData>MemoryDefaultData</DefaultData>
<IdLocation>^OcuTalonP.MemoryD</IdLocation>
<IndexLocation>^OcuTalonP.MemoryI</IndexLocation>
<StreamLocation>^OcuTalonP.MemoryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
