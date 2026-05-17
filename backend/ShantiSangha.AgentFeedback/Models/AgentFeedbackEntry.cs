namespace ShantiSangha.AgentFeedback.Models;

public enum AgentFeedbackType { Issue, Improvement, Observation }

public enum AgentFeedbackSeverity { Low, Medium, High }

public class AgentFeedbackEntry
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public AgentFeedbackType Type { get; set; }
    public AgentFeedbackSeverity Severity { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Context { get; set; } = string.Empty;
    public string? Suggestion { get; set; }
    public Guid? TriggeringMessageId { get; set; }
    public DateTime CreatedAt { get; set; }
}
