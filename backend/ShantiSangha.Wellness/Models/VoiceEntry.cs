namespace ShantiSangha.Wellness.Models;

public enum VoiceEntryStatus { Pending, Transcribing, Completed, Failed }

public class VoiceEntry
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string StorageKey { get; set; } = string.Empty; // R2/S3 object key
    public string? Transcript { get; set; }
    public VoiceEntryStatus Status { get; set; } = VoiceEntryStatus.Pending;
    public Guid? DraftJournalId { get; set; } // journal created after transcription
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
