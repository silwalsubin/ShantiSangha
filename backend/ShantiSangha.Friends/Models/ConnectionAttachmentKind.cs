namespace ShantiSangha.Friends.Models;

/// Bucket the iOS UI uses to surface attachments in two distinct
/// sections — a thumbnail grid for `Media` (photos + videos) and a
/// list with file icons for `File` (PDFs, docs, anything else). The
/// backend auto-classifies based on the uploaded ContentType so the
/// client doesn't have to lie about it.
public enum ConnectionAttachmentKind
{
    Media,
    File
}
