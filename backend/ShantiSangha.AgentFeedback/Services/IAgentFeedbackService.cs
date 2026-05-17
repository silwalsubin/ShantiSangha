using ShantiSangha.AgentFeedback.Contracts;

namespace ShantiSangha.AgentFeedback.Services;

public interface IAgentFeedbackService
{
    Task<AgentFeedbackResponse> CreateAsync(
        Guid userId,
        CreateAgentFeedbackRequest request,
        Guid? triggeringMessageId,
        CancellationToken ct = default);

    Task<List<AgentFeedbackResponse>> ListAllAsync(
        string? type = null,
        string? severity = null,
        CancellationToken ct = default);
}
