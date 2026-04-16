namespace ShantiSangha.Wellness.Contracts;

public record GetUploadUrlRequest(string Extension);

public record CreateVoiceEntryRequest(string ObjectKey);

public record UploadUrlResponse(string UploadUrl, string ObjectKey);

public record VoiceEntryCreatedResponse(Guid Id, string Status, DateTime CreatedAt);

public record VoiceEntryListItem(Guid Id, string Status, DateTime CreatedAt, DateTime UpdatedAt, bool HasTranscript, string? TranscriptPreview, Guid? DraftJournalId);

public record VoiceEntryDetailResponse(Guid Id, string Status, string? Transcript, Guid? DraftJournalId, DateTime CreatedAt, DateTime UpdatedAt, string? AudioUrl);
