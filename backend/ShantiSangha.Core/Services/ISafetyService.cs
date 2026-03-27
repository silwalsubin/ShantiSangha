namespace ShantiSangha.Core.Services;

public enum SafetyCheckOutcome { Clear, Flagged, Crisis }

public record SafetyCheckResult(
    SafetyCheckOutcome Outcome,
    string? Reason = null);

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
