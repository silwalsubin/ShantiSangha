namespace ShantiSangha.Shared.Interfaces;

public enum SafetyCheckOutcome { Clear, Flagged, Crisis }

public record SafetyCheckResult(
    SafetyCheckOutcome Outcome,
    string? Reason = null);

/// <summary>
/// One safety spine for every AI surface. Implemented in the Chat module
/// (OpenAI moderation + crisis keyword list); consumed by both the Reflect
/// companion and the assistant orchestrator.
/// </summary>
public interface ISafetyService
{
    /// <summary>Check an inbound user message before it reaches the AI.</summary>
    Task<SafetyCheckResult> CheckInputAsync(string content, CancellationToken ct = default);

    /// <summary>Check an outbound AI response before it is delivered to the user.</summary>
    Task<SafetyCheckResult> CheckOutputAsync(string content, CancellationToken ct = default);

    /// <summary>Persist a safety event to the audit log.</summary>
    Task LogEventAsync(
        Guid userId,
        string eventType,
        string? triggerContent,
        string? details,
        Guid? conversationId,
        CancellationToken ct = default);
}
