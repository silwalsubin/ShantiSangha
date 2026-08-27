namespace ShantiSangha.Agent.Contracts;

/// A turn sent to the assistant. `Message` may be empty when an image is
/// attached (e.g. "here, look at this"). `ImageBase64` is the raw bytes
/// of a single photo (JPEG), base64-encoded; the assistant sees it via
/// GPT-4o vision for that turn only — we don't persist the bytes.
public record AgentChatRequest(
    string Message,
    string? ImageBase64 = null,
    string? ImageContentType = null,
    /// The thread this turn belongs to. Null (older clients, or a first
    /// message with no thread yet) resolves to the most recent assistant
    /// thread, creating one if none exists. The resolved id is echoed back
    /// as the stream's first frame (`event: conversation`).
    Guid? ConversationId = null,
    /// When set, the turn is scoped to one reminder ("Plan with assistant"):
    /// the assistant is grounded in that reminder + its notes, the exchange is
    /// ephemeral (not persisted, no global history), and it writes its plan
    /// into the reminder's notes.
    Guid? ReminderId = null,
    /// Prior turns of THIS scoped session, oldest-first, EXCLUDING the current
    /// `Message`. Scoped chats persist nothing server-side, so the client
    /// holds the transcript and replays it here for within-session memory.
    /// Ignored outside scoped mode (the main chat replays from the DB).
    IReadOnlyList<AgentChatTurn>? History = null);

/// One prior turn in a scoped session. Role is "user" or "assistant".
public record AgentChatTurn(string Role, string Content);
