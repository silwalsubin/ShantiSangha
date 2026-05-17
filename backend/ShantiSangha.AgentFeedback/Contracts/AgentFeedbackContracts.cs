namespace ShantiSangha.AgentFeedback.Contracts;

public record CreateAgentFeedbackRequest(
    string Type,
    string Severity,
    string Title,
    string Context,
    string? Suggestion);

public record AgentFeedbackResponse(
    Guid Id,
    Guid UserId,
    string Type,
    string Severity,
    string Title,
    string Context,
    string? Suggestion,
    Guid? TriggeringMessageId,
    DateTime CreatedAt);
