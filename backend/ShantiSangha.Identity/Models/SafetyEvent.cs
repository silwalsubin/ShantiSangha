namespace ShantiSangha.Identity.Models;

public enum SafetyEventType { ModerationFlagged, CrisisKeywordDetected, ResponseFlagged, ManualEscalation }

public class SafetyEvent
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public SafetyEventType EventType { get; set; }
    public string? TriggerContent { get; set; }
    public string? Details { get; set; }
    public Guid? ConversationId { get; set; }
    public DateTime CreatedAt { get; set; }
}
