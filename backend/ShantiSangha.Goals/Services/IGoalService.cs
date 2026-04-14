using ShantiSangha.Goals.Contracts;

namespace ShantiSangha.Goals.Services;

public interface IGoalService
{
    Task<GoalCreatedResponse> CreateAsync(Guid userId, CreateGoalRequest request, CancellationToken ct = default);
    Task<List<object>> ListAsync(Guid userId, string? date = null, CancellationToken ct = default);
    Task<List<TodayGoalResponse>> GetTodayAsync(Guid userId, string? date = null, CancellationToken ct = default);
    Task<object?> GetByIdAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<bool> UpdateAsync(Guid id, Guid userId, UpdateGoalRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default);
    Task<CheckInResult?> CheckInAsync(Guid id, Guid userId, CheckInRequest request, CancellationToken ct = default);
    Task<bool> UndoCheckInAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<bool> ResetAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<List<CheckInListItem>?> GetCheckInsAsync(Guid id, Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
    Task<List<GoalActivityResponse>?> GetHistoryAsync(Guid id, Guid userId, int page = 1, int pageSize = 50, CancellationToken ct = default);
    Task<NudgeResult?> GetNudgeAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<JourneyResponse> GetJourneyAsync(Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
    Task<JourneyReflectionResponse> GetJourneyReflectionAsync(Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
}
