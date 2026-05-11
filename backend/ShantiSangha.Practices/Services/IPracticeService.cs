using ShantiSangha.Practices.Contracts;

namespace ShantiSangha.Practices.Services;

public interface IPracticeService
{
    Task<PracticeCreatedResponse> CreateAsync(Guid userId, CreatePracticeRequest request, CancellationToken ct = default);
    Task<List<PracticeResponse>> ListAsync(Guid userId, string? date = null, CancellationToken ct = default);
    Task<List<TodayPracticeResponse>> GetTodayAsync(Guid userId, string? date = null, CancellationToken ct = default);
    Task<PracticeDetailResponse?> GetByIdAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<bool> UpdateAsync(Guid id, Guid userId, UpdatePracticeRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default);
    Task<CheckInResult?> CheckInAsync(Guid id, Guid userId, CheckInRequest request, CancellationToken ct = default);
    Task<bool> UndoCheckInAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<bool> ResetAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<List<CheckInListItem>?> GetCheckInsAsync(Guid id, Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
    Task<List<PracticeActivityResponse>?> GetHistoryAsync(Guid id, Guid userId, int page = 1, int pageSize = 50, CancellationToken ct = default);
    Task<JourneyResponse> GetJourneyAsync(Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
    Task<JourneyReflectionResponse> GetJourneyReflectionAsync(Guid userId, string? from = null, string? to = null, CancellationToken ct = default);
}
