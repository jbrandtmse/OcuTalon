/// The file-store call: the one way a file that a person sends gets stored, for the web chat (OcuTalon.Web.Files) and, from Story 26.2, for
/// Telegram (Lane A's TelegramIn) (AD-1, AD-4, AD-14, AD-21, AD-29; Story 25.3). Lane B.
///   - Store(sessionRef, channel, name, content, .file, .sc) makes the checks in order, size (more than FILEMAX, 10,485,760 bytes: too_large), no
///     bytes (empty) and type (wrong_type), and stores nothing when one fails. The type is read from the bytes alone: %PDF- is application/pdf,
///     FF D8 FF image/jpeg, the 8-byte PNG signature image/png, and PK 03 04 with the entry name word/document.xml in the bytes the Word (.docx)
///     type. The name (before it is cut) must carry the extension of that type (.pdf, .jpg or .jpeg, .png, .docx), else wrong_type; a declared type is never read. The
///     name is made safe by SafeName first and an empty one becomes photo.jpg, photo.png, file.pdf or file.docx. An accepted file is a
///     Data.SentFile row of the session and file is {ref, name, mediaType, size}. Store writes nothing to any log.
///   - Open(ref, sessionRef, .sc) is the bytes of the session's own file as a temporary binary stream, or "": the only reader of a row's bytes. No route
///     serves them. Describe(ref, sessionRef, .sc) is {ref, name, mediaType, size} of the session's own file, or "". Both read through
///     Ownership.SentFile, which only this class calls (AD-4).
///   - SetItem(item, file) sets the four file fields of an Msg.Item, and never the text: an Item names a file by its Ref, name, media type and size only,
///     and its provenance is untrusted (AD-14, AD-21). RefusalText(code, size) is the sentence for a refusal code.
///   - Readable() is 1 only when OcuTalon.Agent.Input says that it reads a sent file: its parameter READSFILES is exactly 1 (Story 26.2 adds it in the
///     change that makes Agent.Input read one). It is a probe of the code and no setting. Until then a file turn is answered with NoReaderText and no
///     model request is made (Core.Conversation).
Class OcuTalon.Core.Files [ DependsOn = OcuTalon.Web.Documents ]
{

/// The largest file, in bytes: Web.Documents' limit, 10 MB (FR-54).
Parameter FILEMAX = {##class(OcuTalon.Web.Documents).#FILEMAX};

/// The class that reads a sent file and the parameter in which it says so.
Parameter READERCLASS = "OcuTalon.Agent.Input";

Parameter READERPARAMETER = "READSFILES";

/// The refusal codes.
Parameter TOOLARGE = "too_large";

Parameter EMPTY = "empty";

Parameter WRONGTYPE = "wrong_type";

/// The media types.
Parameter PDF = "application/pdf";

Parameter DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

Parameter JPEG = "image/jpeg";

Parameter PNG = "image/png";

/// The entry that makes a zip a Word file.
Parameter DOCXENTRY = "word/document.xml";

/// The longest name, in characters.
Parameter NAMEMAX = 255;

/// The refusal sentences (UX-DR147): {size} is SizeText of the file's size, {reason} one of the REASON texts.
Parameter TEXTTOOLARGE = "That file is {size}; the limit is 10 MB.";

Parameter TEXTUNREADABLE = "I couldn't read that file: {reason}.";

Parameter REASONWRONGTYPE = "it isn't a PDF, Word (.docx), JPEG or PNG file";

Parameter REASONEMPTY = "the file is empty";

/// The text of the 409 not_available on the online demo, and of a drop there.
Parameter TEXTOFFONDEMO = "Sending files is off on the online demo. It works on your own install.";

/// The reply to a file turn when nothing can read the file yet; {name} is the safe name.
Parameter TEXTNOREADER = "I got {name}, but I can't read files yet.";

/// The size of the chunks the bytes are read in.
Parameter CHUNK = 32000;

/// Checks the file and stores it for the session; see the class description. Returns "" when the file is stored (file is then {ref, name, mediaType,
/// size}), or the code too_large, empty or wrong_type (file is ""). When the row could not be written the result is "", file is "" and sc is the error.
ClassMethod Store(sessionRef As %String, channel As %String, name As %String, content As %Stream.Object, Output file As %DynamicObject, Output sc As %Status) As %String
{
	Set file = ""
	Set sc = $SYSTEM.Status.OK()
	If ($Get(sessionRef) = "") || '$IsObject($Get(content)) {
		Set sc = $SYSTEM.Status.Error(5001, "A file needs a session and its bytes")
		Quit ""
	}
	If content.Size > ..#FILEMAX Quit ..#TOOLARGE
	If content.Size = 0 Quit ..#EMPTY
	Set mediaType = ..MediaTypeOf(content)
	Set clean = ..Clean($Get(name))
	If (mediaType = "") || ((clean '= "") && '..NameFits(clean, mediaType)) Quit ..#WRONGTYPE
	Set safe = $Select(clean = "": ..DefaultName(mediaType), 1: $Extract(clean, 1, ..#NAMEMAX))
	Set ref = ##class(OcuTalon.Data.SentFile).Put(sessionRef, $Get(channel), safe, mediaType, content, .sc)
	If ref = "" Quit ""
	Set file = {"ref": (ref), "name": (safe), "mediaType": (mediaType), "size": (content.Size)}
	Quit ""
}

/// The name without control characters and the bidirectional controls (U+202A to U+202E and U+2066 to U+2069), trimmed of white space and cut to
/// NAMEMAX characters.
ClassMethod SafeName(name As %String) As %String
{
	Quit $Extract(..Clean($Get(name)), 1, ..#NAMEMAX)
}

/// The name as SafeName makes it, before the cut: the extension of a long name is still checked.
ClassMethod Clean(name As %String) As %String [ Private ]
{
	Set name = $ZStrip(name, "*C")
	Set name = $Translate(name, $Char(8234, 8235, 8236, 8237, 8238, 8294, 8295, 8296, 8297))
	Quit $ZStrip(name, "<>W")
}

/// The media type of the bytes by their signature, or "" for any other bytes. Reads the stream from its start.
ClassMethod MediaTypeOf(content As %Stream.Object) As %String
{
	Do content.Rewind()
	Set head = content.Read(8)
	If $Extract(head, 1, 5) = "%PDF-" Quit ..#PDF
	If $Extract(head, 1, 3) = $Char(255, 216, 255) Quit ..#JPEG
	If head = $Char(137, 80, 78, 71, 13, 10, 26, 10) Quit ..#PNG
	If ($Extract(head, 1, 4) = $Char(80, 75, 3, 4)) && ..HasEntry(content, ..#DOCXENTRY) Quit ..#DOCX
	Quit ""
}

/// 1 when the entry name is in the bytes of the zip (the names of its entries are stored in the clear).
ClassMethod HasEntry(content As %Stream.Object, entry As %String) As %Boolean [ Private ]
{
	Set found = 0, carry = ""
	Do content.Rewind()
	While 'found && 'content.AtEnd {
		Set buffer = carry _ content.Read(..#CHUNK)
		Set found = ($Find(buffer, entry) > 0)
		Set start = $Length(buffer) - $Length(entry) + 2
		Set carry = $Extract(buffer, $Select(start < 1: 1, 1: start), *)
	}
	Do content.Rewind()
	Quit found
}

/// 1 when the name ends with an extension of the media type, in any case.
ClassMethod NameFits(name As %String, mediaType As %String) As %Boolean [ Private ]
{
	Set parts = $Length(name, ".")
	If parts < 2 Quit 0
	Set extension = $ZConvert($Piece(name, ".", parts), "L")
	If mediaType = ..#PDF Quit (extension = "pdf")
	If mediaType = ..#DOCX Quit (extension = "docx")
	If mediaType = ..#PNG Quit (extension = "png")
	If mediaType = ..#JPEG Quit ((extension = "jpg") || (extension = "jpeg"))
	Quit 0
}

/// The name of a file that came without one.
ClassMethod DefaultName(mediaType As %String) As %String [ Private ]
{
	Quit $Case(mediaType, ..#JPEG: "photo.jpg", ..#PNG: "photo.png", ..#PDF: "file.pdf", : "file.docx")
}

/// The bytes of the session's own file as a temporary binary stream at its start, or "" when the session has no such file (or the read failed; sc
/// says which). The only reader of a row's bytes.
ClassMethod Open(ref As %String, sessionRef As %String, Output sc As %Status) As %Stream.Object
{
	Set row = ##class(OcuTalon.Data.Ownership).SentFile($Get(ref), $Get(sessionRef), .sc)
	If $SYSTEM.Status.IsError(sc) || '$IsObject(row) Quit ""
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Set sc = bytes.CopyFrom(row.Content)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Do bytes.Rewind()
	Quit bytes
}

/// {ref, name, mediaType, size} of the session's own file, or "" when the session has no such file. Never the bytes.
ClassMethod Describe(ref As %String, sessionRef As %String, Output sc As %Status) As %DynamicObject
{
	Set row = ##class(OcuTalon.Data.Ownership).SentFile($Get(ref), $Get(sessionRef), .sc)
	If $SYSTEM.Status.IsError(sc) || '$IsObject(row) Quit ""
	Quit {"ref": (row.Ref), "name": (row.Name), "mediaType": (row.MediaType), "size": (row.Size)}
}

/// Deletes the session's own file; the file of another session and a missing one are left alone, as OK.
ClassMethod Discard(ref As %String, sessionRef As %String) As %Status
{
	Quit ##class(OcuTalon.Data.SentFile).Drop(ref, sessionRef)
}

/// Sets the file fields of the Item from file ({ref, name, mediaType, size}); never the text.
ClassMethod SetItem(item As OcuTalon.Msg.Item, file As %DynamicObject)
{
	Set item.FileRef = file.ref
	Set item.FileName = file.name
	Set item.FileMediaType = file.mediaType
	Set item.FileSize = file.size
}

/// The sentence for a refusal code: TEXTTOOLARGE with the size for too_large, else TEXTUNREADABLE with the reason of empty or wrong_type.
ClassMethod RefusalText(code As %String, size As %Integer = 0) As %String
{
	If code = ..#TOOLARGE Quit $Replace(..#TEXTTOOLARGE, "{size}", ..SizeText(size))
	Quit $Replace(..#TEXTUNREADABLE, "{reason}", $Case(code, ..#EMPTY: ..#REASONEMPTY, : ..#REASONWRONGTYPE))
}

/// A size as the sentence writes it, as OcuTalon.Docs.Extract.SizeText does: "14 MB", "2.1 MB", "300 KB".
ClassMethod SizeText(bytes As %Integer) As %String
{
	Quit ##class(OcuTalon.Docs.Extract).SizeText(bytes)
}

/// 1 when OcuTalon.Agent.Input reads a sent file: its parameter READSFILES is exactly 1. readerClass is the test seam; no caller in the product passes one.
/// A class that does not exist or does not define the parameter is 0.
ClassMethod Readable(readerClass As %String = {..#READERCLASS}) As %Boolean
{
	Set readable = 0
	Try {
		Set readable = ($Parameter(readerClass, ..#READERPARAMETER) _ "" = "1")
	} Catch {
		Set readable = 0
	}
	Quit readable
}

/// The reply to a file turn that nothing can read: TEXTNOREADER with the safe name.
ClassMethod NoReaderText(name As %String) As %String
{
	Quit $Replace(..#TEXTNOREADER, "{name}", ..SafeName($Get(name)))
}

}
