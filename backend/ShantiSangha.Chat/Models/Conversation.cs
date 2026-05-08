namespace ShantiSangha.Chat.Models;

public class Conversation
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string? Title { get; set; }

    /// <summary>
    /// Routing/grouping hint for the chat pipeline. "general" uses the default
    /// spiritual-companion prompt with broad personal context. "chart" locks
    /// the pipeline to corpus-grounded Jyotish — signature-based retrieval is
    /// mandatory, the prompt bounds the LLM to passages, and the response must
    /// speak from the person's actual chart rather than hypothesize. "pair"
    /// is the viewer's private chat about a specific subject's chart, gated by
    /// an active BirthDetailShare grant from subject to viewer; it loads both
    /// charts plus the pre-composed pair reading.
    /// </summary>
    public string Type { get; set; } = ConversationType.General;

    /// <summary>
    /// Populated only on pair conversations — the user being read. The viewer
    /// is <see cref="UserId"/>. Both must be friends with an active
    /// BirthDetailShare from subject to viewer; the controller enforces this
    /// before creating the row.
    /// </summary>
    public Guid? SubjectUserId { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public ICollection<Message> Messages { get; set; } = [];
}

public static class ConversationType
{
    public const string General = "general";
    public const string Chart = "chart";
    public const string Pair = "pair";
}
