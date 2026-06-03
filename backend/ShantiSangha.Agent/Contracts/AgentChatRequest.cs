namespace ShantiSangha.Agent.Contracts;

/// A turn sent to the assistant. `Message` may be empty when an image is
/// attached (e.g. "here, look at this"). `ImageBase64` is the raw bytes
/// of a single photo (JPEG), base64-encoded; the assistant sees it via
/// GPT-4o vision for that turn only — we don't persist the bytes.
public record AgentChatRequest(
    string Message,
    string? ImageBase64 = null,
    string? ImageContentType = null,
    /// When set, the turn is scoped to one reminder ("Plan with assistant"):
    /// the assistant is grounded in that reminder + its notes, the exchange is
    /// ephemeral (not persisted, no global history), and it writes its plan
    /// into the reminder's notes.
    Guid? ReminderId = null);
