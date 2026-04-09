using Microsoft.AspNetCore.Http;
using ShantiSangha.Goals.Contracts;

namespace ShantiSangha.Goals.Services;

public interface IGoalService
{
    Task<IResult> CreateAsync(Guid userId, CreateGoalRequest request, CancellationToken ct = default);
    Task<IResult> ListAsync(Guid userId, string? date = null, CancellationToken ct = default);
    Task<IResult> GetTodayAsync(Guid userId, string? date = null, CancellationToken ct = default);
    Task<IResult> GetByIdAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<IResult> UpdateAsync(Guid id, Guid userId, UpdateGoalRequest request, CancellationToken ct = default);
    Task<IResult> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default);
    Task<IResult> CheckInAsync(Guid id, Guid userId, CheckInRequest request, CancellationToken ct = default);
    Task<IResult> UndoCheckInAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<IResult> ResetAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<IResult> GetCheckInsAsync(Guid id, Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
    Task<IResult> GetHistoryAsync(Guid id, Guid userId, int page = 1, int pageSize = 50, CancellationToken ct = default);
    Task<IResult> GetNudgeAsync(Guid id, Guid userId, CancellationToken ct = default);
    Task<IResult> GetJourneyAsync(Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
    Task<IResult> GetJourneyReflectionAsync(Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
}
