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
    /// speak from the person's actual chart rather than hypothesize.
    /// </summary>
    public string Type { get; set; } = ConversationType.General;

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public ICollection<Message> Messages { get; set; } = [];
}

public static class ConversationType
{
    public const string General = "general";
    public const string Chart = "chart";
}
