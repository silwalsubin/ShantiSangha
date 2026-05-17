using Microsoft.EntityFrameworkCore;
using ShantiSangha.AgentFeedback.Contracts;
using ShantiSangha.AgentFeedback.Data;
using ShantiSangha.AgentFeedback.Models;

namespace ShantiSangha.AgentFeedback.Services;

public class AgentFeedbackService(AgentFeedbackDbContext db) : IAgentFeedbackService
{
    public async Task<AgentFeedbackResponse> CreateAsync(
        Guid userId,
        CreateAgentFeedbackRequest body,
        Guid? triggeringMessageId,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(body.Title))
            throw new InvalidOperationException("Title is required.");
        if (body.Title.Length > 120)
            throw new InvalidOperationException("Title must be 120 characters or fewer.");
        if (string.IsNullOrWhiteSpace(body.Context))
            throw new InvalidOperationException("Context is required.");

        var type = ParseType(body.Type);
        var severity = ParseSeverity(body.Severity);

        var entry = new AgentFeedbackEntry
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Type = type,
            Severity = severity,
            Title = body.Title.Trim(),
            Context = body.Context.Trim(),
            Suggestion = string.IsNullOrWhiteSpace(body.Suggestion) ? null : body.Suggestion.Trim(),
            TriggeringMessageId = triggeringMessageId,
            CreatedAt = DateTime.UtcNow,
        };

        db.Entries.Add(entry);
        await db.SaveChangesAsync(ct);

        return ToResponse(entry);
    }

    public async Task<List<AgentFeedbackResponse>> ListAllAsync(
        string? type = null,
        string? severity = null,
        CancellationToken ct = default)
    {
        var query = db.Entries.AsQueryable();

        if (!string.IsNullOrWhiteSpace(type))
        {
            var parsed = ParseType(type);
            query = query.Where(e => e.Type == parsed);
        }
        if (!string.IsNullOrWhiteSpace(severity))
        {
            var parsed = ParseSeverity(severity);
            query = query.Where(e => e.Severity == parsed);
        }

        var entries = await query
            .OrderByDescending(e => e.CreatedAt)
            .ToListAsync(ct);

        return entries.Select(ToResponse).ToList();
    }

    private static AgentFeedbackType ParseType(string input) =>
        input.Trim().ToLowerInvariant() switch
        {
            "issue" => AgentFeedbackType.Issue,
            "improvement" => AgentFeedbackType.Improvement,
            "observation" => AgentFeedbackType.Observation,
            _ => throw new InvalidOperationException("Type must be 'issue', 'improvement', or 'observation'.")
        };

    private static AgentFeedbackSeverity ParseSeverity(string input) =>
        input.Trim().ToLowerInvariant() switch
        {
            "low" => AgentFeedbackSeverity.Low,
            "medium" or "med" => AgentFeedbackSeverity.Medium,
            "high" => AgentFeedbackSeverity.High,
            _ => throw new InvalidOperationException("Severity must be 'low', 'medium', or 'high'.")
        };

    private static AgentFeedbackResponse ToResponse(AgentFeedbackEntry e) => new(
        e.Id,
        e.UserId,
        e.Type.ToString().ToLowerInvariant(),
        e.Severity.ToString().ToLowerInvariant(),
        e.Title,
        e.Context,
        e.Suggestion,
        e.TriggeringMessageId,
        e.CreatedAt);
}
