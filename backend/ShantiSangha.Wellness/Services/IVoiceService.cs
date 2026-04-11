using ShantiSangha.Wellness.Contracts;

namespace ShantiSangha.Wellness.Services;

public interface IVoiceService
{
    Task<UploadUrlResponse?> GetUploadUrlAsync(Guid userId, GetUploadUrlRequest request, CancellationToken ct = default);
    Task<VoiceEntryCreatedResponse> CreateEntryAsync(Guid userId, CreateVoiceEntryRequest request, CancellationToken ct = default);
    Task<List<VoiceEntryListItem>> ListEntriesAsync(Guid userId, int page, int pageSize, CancellationToken ct = default);
    Task<VoiceEntryDetailResponse?> GetEntryAsync(Guid userId, Guid entryId, CancellationToken ct = default);
    Task<bool> DeleteEntryAsync(Guid userId, Guid entryId, CancellationToken ct = default);
}
